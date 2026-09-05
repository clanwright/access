# Access

Access is a versioned Clan service bundle for administrative connectivity and
SSH protection. It publishes two independently placeable bricks as one
atomic release:

| Clan module                          | Role           | Primary package   |
| ------------------------------------ | -------------- | ----------------- |
| `@clanwright/tailscale-admin`        | `admin-access` | Tailscale         |
| `@clanwright/stunnel-ssh-breakglass` | `breakglass`   | stunnel + OpenSSH |

The runtime flake outputs support `x86_64-linux`; formatting and verification
tooling is also available on `aarch64-darwin`. A consumer adds Access once, then
selects each module independently with `module.input = "access"`. Access owns
the exact application closures; the consumer owns machines, placement, secret
values, firewall policy, operations, and deployment.

Version `v0.2.0` introduced TLS-PSK-gated emergency SSH in place of Fail2ban and
fwknop. Version `v0.3.0` restricts the Tailscale `authKeySecretName` setting to safe identifiers; its
module IDs, roles, defaults, and package closures are unchanged from `v0.2.0`.
Use only a completed signed release, never moving `main`. Consumers updating
from `v0.2.x` should follow the [v0.3.0 migration notes](docs/migration-v0.3.0.md);
older consumers must first follow the [v0.2.0 migration notes](docs/migration-v0.2.0.md).

Daily SSH and admin UIs use Tailscale. The independent emergency service exposes
TLS 1.3, not raw SSH; it authenticates a PSK before reaching a loopback-only
OpenSSH daemon. SSH key authentication is a second gate. The recovery account
has passwordless sudo and therefore root-equivalent authority. Neither channel
can recover a failed OS, firewall blocking both paths, or lost public routing.

## Documentation

- Each module's public settings and defaults live beside its implementation in
  [`clanServices/`](clanServices/).
- [Package authority](docs/package-authority.md) explains the single nixpkgs
  context and the consumer-module boundary.
- [Verification](docs/verification.md) lists the complete local gate.
- [Releases](docs/releases.md) defines SemVer, signed tags, and manual GitHub
  Release publication.
- [v0.3.0 migration](docs/migration-v0.3.0.md) covers the Tailscale secret-name
  restriction; [v0.2.0 migration](docs/migration-v0.2.0.md) covers the earlier
  service replacement.
- [CHANGELOG](CHANGELOG.md) is the source for release notes.

The extraction starts from Clanwright source commit
`8c250131229b0476af95f5b068401e28fb0511f6`.
