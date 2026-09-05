# Verification

The complete local gate is secret-free and performs no deploy, provider,
backup, restore, or consumer lockfile mutation.

```bash
bash scripts/verify.sh
```

Local verification, CI, and the release gate use this same entrypoint. It
checks formatting, static policy and secrets, evaluates all flake outputs,
executes the Linux checks, and builds the three authoritative packages.
On macOS, a configured Linux builder is required to execute the complete gate;
evaluation alone is not a passing Linux build.

The entrypoint retains per-stage logs and durations, plus a whole-run summary,
under `.work/verification/`. Set `ACCESS_VERIFY_LOG_DIR` to select an explicit
artifact directory.

The flake gate includes service API contracts, exact registry contents,
single and combined external placement, package precedence, secret metadata,
repository policy, Renovate policy, release policy, and freshness behavior.
Negative secret-interface checks pass harmless invalid fields through the
actual interfaces of both services, alongside valid controls. They verify
rejection, not the wording of the error, and contain no credential values.

Import-from-derivation is disabled in the gate: generated configuration and
script contents are inspected during check builds, never during evaluation.
This keeps evaluation independent of a developer's populated build cache.

Placement checks share a complete secret-free Clan consumer fixture. They
force the NixOS toplevel derivation and generated service units, including
assertions and per-machine setting overrides. The fixture uses Access's pinned
baseline; it does not establish compatibility with arbitrary consumer pins
or replace building the consumer's real machine closure.

Access does not use NixOS VM, QEMU, or KVM tests locally or in CI. Its accepted
verification layers are evaluation, schema and assertion checks, generated
configuration parsing, and package builds.

These checks do not exercise runtime service startup or restart transitions,
or prove a successful TLS/SSH handshake, PAM login, sudo session, client-network
reachability, or the deployed consumer's secret provisioning. Live consumer
runtime acceptance remains separate owner scope and is described in the
migration guide.

To execute only the Linux checks with a configured Linux builder:

```bash
nix build --no-link --impure --option allow-import-from-derivation false --expr \
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
