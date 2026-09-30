# Verification

The complete secret-free local gate performs no deployment, provider, backup,
restore, or consumer lock mutation:

```bash
bash scripts/verify.sh
```

Local verification, CI, and release gates use this entrypoint. It checks
formatting, static tooling and a redacted full-tree secret scan, evaluates flake
outputs, executes Linux checks, and builds the three authoritative Linux
packages. On macOS, executing Linux builds requires a configured Linux builder;
evaluation alone is not build evidence.

Native recovery verification runs on the invoking host with its pinned stunnel
and OpenSSH packages:

```bash
bash scripts/verify.sh --native-recovery
```

This mode builds the recovery packages and parses the documented client
configuration; it does not replace the complete Linux gate. CI also runs a
native `aarch64-darwin` recovery job. The stable aggregate `verify` status
requires both platform jobs to succeed.

Each invocation retains stage logs, durations, and a whole-run summary in a
unique directory under `.work/verification/`, including failed runs. Set
`ACCESS_VERIFY_LOG_DIR` to choose an artifact root. Prior logs are never reused
as current evidence.

## Source, build and parser evidence

Import-from-derivation is disabled. Generated configurations and scripts are
inspected during builds, never by reading derivation outputs during evaluation.
Secret-free Clan fixtures exercise the public modules, placement, assertions,
rendered units, and NixOS toplevel derivations. They use Access's pinned baseline;
consumers must build their real configurations with their native NixOS modules.

| Owning check                      | Evidence                                                                                                                                                                                                  |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `flake-contract`                  | Exact two-module registry, public exports and startup-gate arguments, supported application outputs, package authority.                                                                                   |
| `independent-placement`           | Each service alone and combined, recovery placement limit and absence when omitted.                                                                                                                       |
| `tailscale-admin-contract`        | Boolean enable/retention, safe secret names, rejected removed settings, enrollment/persistent flags, native firewall/routing policy, package precedence, Caddy startup composition.                       |
| `stunnel-ssh-breakglass-contract` | Fixed reserved account/group, ports and secret interfaces, secret metadata/restarts, retained state, dependencies and hardening, sudo/PAM policy, generated SSH parsing and missing-credential rejection. |
| `recovery-client-config`          | Actual `ssh -G -F` parsing on each native platform; actual stunnel parsing ending at an absent PSK before listener startup.                                                                               |
| `tailscale-ready-gate`            | Isolated fake CLI/ip process fixtures for refusal, stage ordering, deadlines, cancellation and withheld status/address output.                                                                            |
| `release-contract`                | Stable-tag/changelog glue and refusal of lightweight or unsigned annotated tags through native Git, without a signing credential fixture.                                                                 |

The `repository-policy`, `verification-contract`, `secret-scan-contract` and
`renovate-contract` checks cover repository boundaries, gate CLI and evidence
isolation, redaction/scan exceptions and native Renovate validation.

Negative interface cases use harmless invalid fields and positive controls.
Trusted signed-tag admission and ancestry refusal are checked separately on
existing repository tags with the actual release verifier. The hermetic check
does not create signing keys or claim to exercise that signed path.
Checks use no secret values, generated access artifacts, credential fixtures,
remote connections, or project-managed VMs. Runtime limitations and required
observations are collected in PREDEPLOY acceptance below.

Static tooling uses actionlint, explicit offline zizmor, shellcheck and the
native Renovate validator. These validate syntax and recognized policies;
reviewers must also inspect exact workflow jobs, commands, aggregation and
secret contexts. Renovate proposes dependency updates, so reviewed builds of
those candidates establish the tested closure.

The gate and release scripts are purposeful local glue: the gate retains stage
logs and timings across native tools, while release verification ties native
Git trust and ancestry to the stable tag and matching CHANGELOG section.
Neither takes over hosted publication or consumer operations.

The full-tree secret scan explicitly loads `.gitleaks.toml`, retains default
rules, redacts results, and excludes no directories. Its narrow exception is
the complete successful Git SSH-signature message containing a public Ed25519
fingerprint. The scanner contract verifies that unrelated surrounding text is
still reported using the existing public release key, without credential
fixtures. Run this scan before every commit.

## PREDEPLOY acceptance

Actual runtime evidence remains required under separately authorized consumer
scope and is not observed by these checks. Missing evidence is neither PASS nor
a local source-refactoring blocker. Access adds no privileged runner, test host,
credential fixture or isolation workaround. Access never provisions or runs
project-managed NixOS VM, QEMU, or KVM workflows; external Linux builders and
hosted CI remain outside its machine ownership.

| Deferred case                     | Required observation                                                                                                                                                                                                                                                                                                                                        | Owner                                              |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| Startup admission                 | Exact Access CLI/daemon under the assembled Caddy vendor unit/drop-in, effective ordinary UID, environment, namespace and sandbox can read the default LocalAPI socket and inspect the selected `UP` interface/IPv4. Wrong state/address/interface and denied socket/netlink access prevent main. Record only exit/layer/timing, never status/address JSON. | Access and consuming unit owner.                   |
| Native manager                    | Every start/restart runs a fresh pre-start gate; failure prevents main. Preserve retry/start-limit policy. Timeout and stop prevent later stages/main and clean the effective cgroup, including TERM-resistant descendants.                                                                                                                                 | Access and consuming unit owner.                   |
| Listener, reload, lifetime        | Exact listener and packet policy, public routes/TLS retained after failed reload, explicit reload after address return, and the limits of momentary startup admission. No watcher or automatic-return guarantee.                                                                                                                                            | Network with Apps/VPN consumers.                   |
| Administrative and recovery trust | Enrollment/state retention, explicit native firewall/routing policy, credential staging, stable host-key creation/reuse, ordinary/recovery SSH isolation, terminal login, PAM/sudo/SFTP; wrong SSH key, missing/wrong PSK, missing/changed pinned host key, direct public SSH and forwarding all refuse.                                                    | Access with consumer and Lifecycle handoff owners. |
| Resource limits and journals      | Confirm effective configured unit limits, including recovery `MemoryMax`, `TasksMax` and `LimitNOFILE`, and native cgroup accounting/cleanup. Observe useful gate/recovery diagnostics during success, refusal, timeout and authentication failures without credentials or raw Tailscale status/address JSON in journal/stdout/stderr.                      | Access and consuming unit owner.                   |

stunnel's absent-PSK parser result proves directive parsing and missing-credential
rejection, not a successful TLS connection. Recovery script inspection does not
prove credential staging or persistent host-key creation/reuse. Evaluated Caddy
composition does not prove vendor-unit/drop-in assembly or effective socket and
netlink permissions. TERM-responsive process fixtures do not prove resistant-child
cleanup: native timeout escalation depends on its monitored process remaining
alive. Success of the startup predicate is momentary, with a race before bind
and no guarantee of continued address presence.

Reuse shared evidence when it proves the same property. An ordinary Nix build
does not run a system manager or prove deployed actor permissions, TUN state,
network reachability, or live trust. Deferral neither closes live issues nor
authorizes transport/credential operations, release, consumer input migration,
or deployment. Source defects still require correction now.

For evaluation without building other systems, materialize check derivation
metadata first; this builds no outputs and avoids missing lazy source paths:

```bash
nix eval --json --no-write-lock-file \
  --option allow-import-from-derivation false .#checks \
  --apply 'builtins.mapAttrs (_: checks: builtins.mapAttrs (_: check: check.drvPath) checks)' \
  > /dev/null
nix flake check --no-write-lock-file --all-systems --no-build \
  --option allow-import-from-derivation false
```

For Linux checks with a configured builder:

```bash
nix build --no-link --impure --option allow-import-from-derivation false --expr \
  'builtins.attrValues ((builtins.getFlake (toString ./.)).checks.x86_64-linux)'
```
