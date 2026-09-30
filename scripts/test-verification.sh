#!/usr/bin/env bash
# Check CLI boundaries and evidence isolation without building application code.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
directory=$(mktemp -d)
trap 'rm -rf "$directory"' EXIT
mkdir "$directory/bin" "$directory/logs with spaces"
export ACCESS_VERIFY_IN_DEV_SHELL=1 ACCESS_VERIFY_LOG_DIR="$directory/logs with spaces"
export VERIFY_TEST_TRACE="$directory/nix-trace"
export PATH="$directory/bin:$PATH"
cat > "$directory/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'flake.nix\0'
STUB
cat > "$directory/bin/nixfmt" <<'STUB'
#!/usr/bin/env bash
echo intentional-formatting-failure >&2
exit 1
STUB
cat > "$directory/bin/nix" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$VERIFY_TEST_TRACE"
if [[ "$1" == eval ]]; then printf aarch64-darwin; fi
STUB
for stub in "$directory/bin/"*; do
  { printf '#!%s\n' "$(command -v bash)"; tail -n +2 "$stub"; } > "$stub.tmp"
  mv "$stub.tmp" "$stub"
done
chmod +x "$directory/bin/"*
printf '%s\n' 'previous run evidence' > "$ACCESS_VERIFY_LOG_DIR/linux-checks.log"
cd "$root"
for run in 1 2; do
  if bash scripts/verify.sh > "$directory/failure-$run.log" 2>&1; then
    echo 'formatting failure unexpectedly passed' >&2
    exit 1
  fi
  grep -q intentional-formatting-failure "$directory/failure-$run.log"
done
test "$(find "$ACCESS_VERIFY_LOG_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 2
grep -qx 'previous run evidence' "$ACCESS_VERIFY_LOG_DIR/linux-checks.log"
test ! -f "$ACCESS_VERIFY_LOG_DIR/summary.log"
for run in "$ACCESS_VERIFY_LOG_DIR/"*/; do
  test "$(grep -c 'whole-run start=' "$run/summary.log")" -eq 1
  grep -q 'stage=formatting.*status=1' "$run/summary.log"
  test ! -f "$run/linux-checks.log"
done
bash scripts/verify.sh --native-recovery > "$directory/native.log" 2>&1
test "$(grep -c '^build ' "$VERIFY_TEST_TRACE")" -eq 1
grep -qF '.#stunnel .#openssh .#checks.aarch64-darwin.recovery-client-config' "$VERIFY_TEST_TRACE"
if grep -q x86_64-linux "$VERIFY_TEST_TRACE" || grep -q stage=formatting "$directory/native.log"; then
  echo 'native recovery unexpectedly ran a Linux or formatting stage' >&2
  exit 1
fi
cp "$VERIFY_TEST_TRACE" "$directory/expected-trace"
status=0
bash scripts/verify.sh --unknown > "$directory/unknown.log" 2>&1 || status=$?
test "$status" -eq 2
cmp "$VERIFY_TEST_TRACE" "$directory/expected-trace"
