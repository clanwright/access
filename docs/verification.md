# Verification

The complete local gate is secret-free and performs no deploy, provider,
backup, restore, or consumer lockfile mutation.

```bash
bash scripts/verify.sh
```

Local verification, CI, and the release gate use this same entrypoint. It
checks formatting, static policy and secrets, evaluates all flake outputs,
executes the Linux checks, and builds the three authoritative Linux packages.
The secret-free native recovery SSH parser check is exposed on both
`x86_64-linux` and `aarch64-darwin` and runs on the invoking host with that
system's pinned OpenSSH package; one host does not execute the other system's
check.
On macOS, a configured Linux builder is required to execute the complete gate;
evaluation alone is not a passing Linux build.

CI and the release gate also run a separate native `aarch64-darwin` job for
both recovery packages and their parser check. Linux and Darwin jobs run in
parallel; the stable `verify` status waits for both and succeeds only when both
jobs succeed. A failed, skipped, or cancelled platform job cannot produce a
successful aggregate gate. This preserves the existing required status check.
The same focused entrypoint
can be invoked locally without a Linux builder:

```bash
bash scripts/verify.sh --native-recovery
```

This focused mode does not replace the complete Linux gate.

The entrypoint retains per-stage logs and durations, plus a whole-run summary,
under `.work/verification/`. Set `ACCESS_VERIFY_LOG_DIR` to select an explicit
artifact root. Every invocation creates a unique timestamped child directory,
including failed runs, so an earlier stage log cannot be mistaken for current
evidence. The CLI contract checks this isolation and the native-only scope.

The full-tree secret scan explicitly loads `.gitleaks.toml` and retains the
default detection rules. Its only exception is the complete successful Git SSH
signature message containing a public Ed25519 fingerprint, which the generic
API-key rule otherwise mistakes for a credential. It excludes no directories.
The scanner contract uses the existing public release key to check this exception
and verifies that adding unrelated text before or after the message is still
reported. It creates no credential fixtures.

The flake gate includes service API contracts, exact registry contents,
single and combined external placement, package precedence, secret metadata,
repository policy, Renovate policy, release policy, and freshness behavior.
It also checks that native `stunnel` and `openssh` outputs exist on both
supported systems and that the strict recovery client SSH template is accepted
by `ssh -G -F` without contacting a server.
The check also passes the documented client directives to stunnel, ending with
an intentionally absent PSK file. It requires a missing-PSK failure before
listener startup, without creating any credential. This covers directive
parsing and rejection of a missing credential, not successful TLS initialization
or an authenticated connection.
Negative secret-interface checks pass harmless invalid fields through the
actual interfaces of both services, alongside valid controls. They verify
rejection, not the wording of the error, and contain no credential values.

Import-from-derivation is disabled in the gate: generated configuration and
script contents are inspected during check builds, never during evaluation.
This keeps evaluation independent of a developer's populated build cache.

Service scenarios share a complete secret-free Clan consumer fixture and use
the registered module interface, including settings and placement overrides.
Positive scenarios force the NixOS toplevel derivation, assertions, and generated
service units. Negative scenarios check invalid settings and conflicting
placement, with positive controls to distinguish rejection from a broken
fixture. Contract failures identify the violated invariant. The fixture uses Access's pinned
baseline; it does not establish compatibility with arbitrary consumer pins
or replace building the consumer's real machine closure.

Access does not provision or run project-managed VMs for development, builds,
or tests, locally or in CI, including NixOS VM, QEMU, or KVM tests. External
Linux builders and hosted CI infrastructure remain outside Access machine
ownership. Its accepted verification layers are evaluation, schema and
assertion checks, generated-configuration parsing, and package builds.

Materialize check derivation metadata first, then run the native check with
remote builders disabled and evaluate every system without building it. The
metadata step builds no outputs; it prevents lazy source paths from being
missing during the read-only `--no-build` evaluation:

```bash
nix eval --json --no-write-lock-file --builders '' \
  --option allow-import-from-derivation false .#checks \
  --apply 'builtins.mapAttrs (_: checks: builtins.mapAttrs (_: check: check.drvPath) checks)' \
  > /dev/null
nix flake check --no-write-lock-file --builders '' \
  --option allow-import-from-derivation false
nix flake check --no-write-lock-file --all-systems --no-build --builders '' \
  --option allow-import-from-derivation false
```

These checks do not exercise runtime service startup or restart transitions,
or prove a successful TLS/SSH handshake, PAM login, sudo session, client-network
reachability, or the deployed consumer's secret provisioning. Live consumer
runtime acceptance remains separate owner scope. It must cover positive
terminal login, sudo, and SFTP plus rejection of a wrong SSH key, wrong or
missing PSK, and missing or changed pinned host key in Clanwright.

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
release list, and OpenBSD's portable OpenSSH archive), ignores user curl
configuration, and does not modify a
lockfile or repository file unless the requested output path is inside the
working tree.
