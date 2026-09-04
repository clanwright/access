# `@clanwright/tailscale-admin`

Provides a reusable `admin-access` role through the consumer-native NixOS
`services.tailscale` module. Access selects the exact Tailscale executable;
machine placement, the auth-key value, and surrounding firewall policy remain
consumer-owned.

## Settings and defaults

| Setting              | Default              |
| -------------------- | -------------------- |
| `authKeySecretName`  | `tailscale-auth-key` |
| `lifecycle`          | `enabled`            |
| `useRoutingFeatures` | `client`             |
| `openFirewall`       | `true`               |
| `acceptDns`          | `false`              |

`lifecycle = "disabled-retained"` preserves configuration and state ownership
while disabling the daemon and its SSH ordering edge.

## State and secret boundary

The service declares `/var/lib/tailscale` as Clan state. The auth key is read
only from `config.sops.secrets.<authKeySecretName>.path` with root ownership and
mode `0400`; Access never owns or receives the value.

## Verification

Run `nix build .#checks.x86_64-linux.tailscale-admin-contract`. The check covers
the public defaults, enabled and disabled-retained behavior, runtime secret
path, state path, SSH ordering, and authoritative package selection.
