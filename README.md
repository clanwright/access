# Access

Access is a versioned Clan service bundle for administrative connectivity and
SSH protection. It publishes two independently placeable bricks as one
atomic release:

| Clan module                          | Role           | Primary package   |
| ------------------------------------ | -------------- | ----------------- |
| `@clanwright/tailscale-admin`        | `admin-access` | Tailscale         |
| `@clanwright/stunnel-ssh-breakglass` | `breakglass`   | stunnel + OpenSSH |

The authoritative `tailscale`, `stunnel`, and `openssh` package outputs support
`x86_64-linux`. The `stunnel` and `openssh` outputs are also available on
`aarch64-darwin` for a stock-binary recovery client; formatting and verification
tooling supports both systems. A consumer adds Access once, then selects each
module independently with `module.input = "access"`. Access owns the exact
application closures; the consumer owns machines, placement, secret values,
firewall policy, operations, and deployment.

The public `clan.modules` registry contains exactly these two modules, without
aliases. `lib.tailscaleReadyGate` supplies an optional Linux startup predicate
for consumer services binding an explicitly selected private IPv4. Use a
completed [signed release](docs/releases.md) for consumer updates; moving
`main` is development state.

Daily SSH and admin UIs use Tailscale. The independent emergency service exposes
TLS 1.3, not raw SSH; it authenticates a PSK before reaching a loopback-only
OpenSSH daemon. SSH key authentication is a second gate. The recovery account
has passwordless sudo and therefore root-equivalent authority. Neither channel
can recover a failed OS, firewall blocking both paths, or lost public routing.

## Documentation

- Each module's public settings and defaults live beside its implementation in
  [`clanServices/`](clanServices/).
- The [Tailscale guide](clanServices/tailscale-admin/README.md#private-binding-startup-gate)
  documents the optional finite startup gate for an explicitly selected private
  IPv4 and interface.
- The [break-glass module guide](clanServices/stunnel-ssh-breakglass/README.md)
  includes the minimal native macOS recovery preparation and incident runbook.
- [Package authority](docs/package-authority.md) explains the single nixpkgs
  context and the consumer-module boundary.
- [Verification](docs/verification.md) owns the local gate and the separate
  [PREDEPLOY acceptance](docs/verification.md#predeploy-acceptance) boundary.
- [Releases](docs/releases.md) defines SemVer, signed tags, and manual GitHub
  Release publication.
- [Release notes](CHANGELOG.md) describe the current baseline's capabilities,
  contracts and reasons.
- Agent workflows: [issue tracker](docs/agents/issue-tracker.md),
  [triage labels](docs/agents/triage-labels.md), and
  [domain docs](docs/agents/domain.md).
