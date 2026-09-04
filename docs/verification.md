# Verification

The complete local gate is secret-free and performs no deploy, provider,
backup, restore, or consumer lockfile mutation.

```bash
git ls-files -z '*.nix' | xargs -0 nix develop --command nixfmt --check
nix develop --command prettier --check "**/*.{md,json,json5,yml,yaml}"
nix develop --command actionlint
nix develop --command renovate-config-validator renovate.json5
nix develop --command gitleaks dir . --no-banner --redact
nix flake check --all-systems --no-write-lock-file
nix build --no-write-lock-file \
  .#packages.x86_64-linux.tailscale \
  .#packages.x86_64-linux.fail2ban \
  .#packages.x86_64-linux.fwknop
```

The flake gate includes isolated service behavior, exact registry contents,
single and combined external placement, package precedence, secret metadata,
repository policy, Renovate policy, release policy, and freshness schema
checks. The deliberate package-authority and plaintext-secret fixtures must
fail with their named errors; they never contain or read a credential value.

Generate the non-blocking freshness artifact with:

```bash
nix run .#freshness-report -- --output access-freshness.json
```

`current`, `lag`, and `unknown` are valid explicit states. Network lookup
failure produces `unknown` and exits successfully; a successful response with
malformed metadata is blocking. The client makes one bounded unauthenticated
request to each official stable GitHub Release endpoint and does not modify a
lockfile or repository file unless the requested output path is inside the
working tree.
