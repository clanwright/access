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

The entrypoint retains per-stage logs and durations, plus a whole-run summary,
under `.work/verification/`. Set `ACCESS_VERIFY_LOG_DIR` to select an explicit
artifact directory.

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

Placement checks share a complete secret-free Clan consumer fixture. They
force the NixOS toplevel derivation and generated service units, including
assertions and per-machine setting overrides. The fixture uses Access's pinned
baseline; it does not establish compatibility with arbitrary consumer pins
or replace building the consumer's real machine closure.

Access does not use NixOS VM, QEMU, or KVM tests locally or in CI. Its accepted
verification layers are evaluation, schema and assertion checks, generated
configuration parsing, and package builds.

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
release list, and OpenBSD's portable OpenSSH archive) and does not modify a
lockfile or repository file unless the requested output path is inside the
working tree.
