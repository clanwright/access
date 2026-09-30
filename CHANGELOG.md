# Release notes

## [1.0.0]

Access publishes two independently placeable native Clan services and their
authoritative application packages as one release.

- `@clanwright/tailscale-admin`, role `admin-access`, configures native Tailscale
  administrative connectivity. Settings are `enable`, `authKeySecretName` and
  `acceptDns`; disabling runtime retains state and secret declarations. Ordinary
  OpenSSH, firewall/routing and tailnet authorization remain consumer policy.
- `@clanwright/stunnel-ssh-breakglass`, role `breakglass`, provides an independent
  TLS 1.3 PSK-protected channel to an isolated loopback OpenSSH daemon. A strict
  single-record PSK and SSH key are separate authentication gates. Fixed
  `access-recovery` has explicit root-equivalent sudo; retained host identity,
  separate PAM/session policy and strict client host trust keep recovery distinct
  from ordinary SSH.
- Linux `lib.tailscaleReadyGate { pkgs; ipv4; interface; }` returns a read-only,
  finite native startup command for an explicitly selected private IPv4/interface.
  It uses the Access CLI, native wait/status and kernel address inspection; no
  cached target, watcher, reload hook or transport-loss service dependency.
- `x86_64-linux` package outputs are Tailscale 1.102.4, stunnel 5.80 and OpenSSH
  10.5p1. stunnel/OpenSSH are also available on `aarch64-darwin` for native recovery
  client preparation and parser checks.

One root nixpkgs owns application closures. Native Clan registration, NixOS
consumer options and standard INI generation keep the interface small. Purposeful
glue remains only where upstream mechanisms do not express the required strict
PSK format, authorized-key staging, retained identity or exact startup predicate.
Secret interfaces contain names/runtime paths; consumers supply values and own
machines, placement and operations.

Missing selected private IP refuses the whole consuming cold start/restart.
Successful startup is a momentary observation with a bind race and no continuous
availability promise. Native service policy owns restart limits and cgroup
cleanup; timeout's kill-after escalation is conditional. Network/consumers own
explicit listeners, packet guards and atomic reload behavior.

Verification uses native source/schema/assertion checks, generated-config parsing,
package builds, actionlint/offline zizmor/native Git and redacted scans. Actual
ordinary UID/socket/netlink/sandbox/manager/cgroup/resource/journal behavior,
recovery trust/state/login and TLS/auth remain mandatory PREDEPLOY, not observed
by these gates. No runtime test runner or VM is required or supplied.

The README and adjacent service guides are the current usage/API references;
`docs/verification.md` owns the canonical PREDEPLOY boundary and `docs/releases.md`
owns protected-main, SSH-signed tag and manual publication policy.
