# Access

Access is a versioned Clan service bundle for administrative connectivity and
SSH protection. It publishes three independently placeable bricks as one
atomic release:

| Clan module                         | Role           | Primary package |
| ----------------------------------- | -------------- | --------------- |
| `@clanwright/tailscale-admin`       | `admin-access` | Tailscale       |
| `@clanwright/fail2ban-ssh`          | `ssh-guard`    | Fail2ban        |
| `@clanwright/fwknop-ssh-breakglass` | `breakglass`   | fwknop          |

The flake supports `x86_64-linux`. A consumer adds Access once, then selects
each module independently with `module.input = "access"`. Access owns the exact
application closures; the consumer owns machines, placement, secret values,
firewall policy, operations, and deployment.

The first planned release is `v0.1.0`. Until it is published, this repository
is development state and must not be used as a moving deployment input.

## Documentation

- Each module's public settings and defaults live beside its implementation in
  [`clanServices/`](clanServices/).
- [Package authority](docs/package-authority.md) explains the single nixpkgs
  context and the consumer-module boundary.
- [Verification](docs/verification.md) lists the complete local gate.
- [Releases](docs/releases.md) defines SemVer, signed tags, and manual GitHub
  Release publication.
- [CHANGELOG](CHANGELOG.md) is the source for release notes.

The extraction starts from Clanwright source commit
`8c250131229b0476af95f5b068401e28fb0511f6`.
