#!/usr/bin/env bash
set -euo pipefail

if [[ "${ACCESS_VERIFY_IN_DEV_SHELL:-}" != 1 ]]; then
  exec nix develop --no-write-lock-file --command \
    env ACCESS_VERIFY_IN_DEV_SHELL=1 bash scripts/verify.sh
fi

verify_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
verify_started_seconds=$SECONDS
if [[ -n "${ACCESS_VERIFY_LOG_DIR:-}" ]]; then
  verify_log_dir=$ACCESS_VERIFY_LOG_DIR
  mkdir -p "$verify_log_dir"
else
  mkdir -p .work/verification
  verify_log_dir="$(mktemp -d ".work/verification/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
fi
summary="$verify_log_dir/summary.log"

finish() {
  status=$?
  trap - EXIT
  duration=$((SECONDS - verify_started_seconds))
  printf 'whole-run start=%s duration_seconds=%s status=%s\n' \
    "$verify_started_at" "$duration" "$status" | tee -a "$summary"
  printf 'verification artifacts: %s\n' "$verify_log_dir"
  exit "$status"
}
trap finish EXIT

run_stage() {
  name=$1
  shift
  stage_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stage_started_seconds=$SECONDS
  set +e
  (set -e; "$@") 2>&1 | tee "$verify_log_dir/$name.log"
  status=${PIPESTATUS[0]}
  set -e
  duration=$((SECONDS - stage_started_seconds))
  printf 'stage=%s start=%s duration_seconds=%s status=%s\n' \
    "$name" "$stage_started_at" "$duration" "$status" | tee -a "$summary"
  return "$status"
}

formatting() {
  git ls-files -z '*.nix' | xargs -0 nixfmt --check
  prettier --check "**/*.{md,json,json5,yml,yaml}"
}

static_checks() {
  python3 scripts/verify-workflows.py .github/workflows
  git diff --check
  actionlint
  renovate-config-validator renovate.json5
}

secret_scan() {
  gitleaks dir . --no-banner --redact
}

flake_checks() {
  # Materialize derivation metadata before flake check's read-only --no-build
  # evaluation. This builds no outputs and needs no cross-platform builder.
  nix eval --json --no-write-lock-file \
    --option allow-import-from-derivation false .#checks \
    --apply 'builtins.mapAttrs (_: checks: builtins.mapAttrs (_: check: check.drvPath) checks)' \
    > "$verify_log_dir/check-derivations.json"
  nix flake check --all-systems --no-build --no-write-lock-file \
    --option allow-import-from-derivation false
}

packages() {
  nix build --no-write-lock-file --no-link \
    --option allow-import-from-derivation false \
    .#packages.x86_64-linux.tailscale \
    .#packages.x86_64-linux.stunnel \
    .#packages.x86_64-linux.openssh
}

linux_checks() {
  check_names="$(
    nix eval --json --no-write-lock-file --option allow-import-from-derivation false \
      .#checks.x86_64-linux --apply builtins.attrNames \
      | python3 -c 'import json, sys; print(" ".join(json.load(sys.stdin)))'
  )"
  check_refs=()
  for check_name in $check_names; do
    check_refs+=(".#checks.x86_64-linux.$check_name")
  done
  if [[ "${#check_refs[@]}" -eq 0 ]]; then
    echo "no x86_64-linux checks found" >&2
    return 1
  fi
  nix build --no-write-lock-file --no-link \
    --option allow-import-from-derivation false "${check_refs[@]}"
}

run_stage formatting formatting
run_stage static static_checks
run_stage secret-scan secret_scan
run_stage flake-check flake_checks
run_stage native-recovery nix build --no-write-lock-file --no-link \
  --option allow-import-from-derivation false \
  .#stunnel .#openssh \
  .#checks."$(nix eval --impure --raw --expr builtins.currentSystem)".recovery-client-config
run_stage packages packages
run_stage linux-checks linux_checks
