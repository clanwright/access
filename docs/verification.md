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
  .#packages.x86_64-linux.stunnel \
  .#packages.x86_64-linux.openssh
```

The flake gate includes isolated service behavior, exact registry contents,
single and combined external placement, package precedence, secret metadata,
repository policy, Renovate policy, release policy, and freshness schema
checks. The deliberate package-authority and plaintext-secret fixtures must
fail with their named errors; they never contain or read a credential value.

Placement checks force the real Clan-generated NixOS service configuration,
including per-machine setting overrides; they are not inventory-only checks.
The emergency contract parses sshd policy without creating keys. It does not
prove a successful TLS/SSH handshake, sudo session, client-network reachability,
or the deployed consumer's secret provisioning. Those are explicit owner
acceptance checks in the migration guide.

On macOS, distinguish evaluating Linux outputs from executing Linux checks.
With a configured Linux builder, explicitly build every Linux check:

```bash
nix build --no-link --impure --expr \
  'builtins.attrValues ((builtins.getFlake (toString ./.)).checks.x86_64-linux)'
```

Generate the non-blocking freshness artifact with:

```bash
nix run .#freshness-report -- --output access-freshness.json
```

`current`, `lag`, and `unknown` are valid explicit states. Network lookup
failure produces `unknown` and exits successfully; a successful response with
malformed metadata is blocking. The client makes one bounded unauthenticated
request to each official stable source (Tailscale GitHub Releases, stunnel's
release list, and OpenBSD's portable OpenSSH archive) and does not modify a
lockfile or repository file unless the requested output path is inside the
working tree.
