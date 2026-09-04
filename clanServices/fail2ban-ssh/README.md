# `@clanwright/fail2ban-ssh`

Provides a reusable `ssh-guard` role through the consumer-native NixOS
`services.fail2ban` module. Access selects the exact Fail2ban executable;
machine placement and surrounding SSH and firewall policy remain
consumer-owned.

## Settings and defaults

| Setting               | Default   |
| --------------------- | --------- |
| `lifecycle`           | `enabled` |
| `maxretry`            | `5`       |
| `findtime`            | `10m`     |
| `bantime`             | `1h`      |
| `backend`             | `systemd` |
| `ignoreIPs`           | `[]`      |
| `bootstrapMarkerPath` | `null`    |

`lifecycle = "disabled-retained"` contributes no Fail2ban configuration. An
optional bootstrap marker temporarily suppresses the SSH jail and adds a
matching systemd start condition until the marker is removed.

## State, secrets, and network boundary

The role declares no SOPS secret, Clan state path, listener, or firewall
opening. It protects the existing SSH endpoint and leaves its availability
policy to the consumer.

## Verification

Run `nix build .#checks.x86_64-linux.fail2ban-ssh-contract`. The check covers
the public defaults, lifecycle behavior, ignored networks, bootstrap marker,
and authoritative package selection.
