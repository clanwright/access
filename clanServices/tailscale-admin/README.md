# `@clanwright/tailscale-admin`

Provides a reusable `admin-access` role through the consumer-native NixOS
`services.tailscale` module. Access selects the exact Tailscale executable;
machine placement, the auth-key value, and surrounding firewall policy remain
consumer-owned.

## Settings and defaults

| Setting              | Default              | Constraint                                   |
| -------------------- | -------------------- | -------------------------------------------- |
| `authKeySecretName`  | `tailscale-auth-key` | Safe SOPS name: `[A-Za-z0-9][A-Za-z0-9._-]*` |
| `lifecycle`          | `enabled`            | `enabled` or `disabled-retained`             |
| `useRoutingFeatures` | `none`               | `none`, `client`, `server`, or `both`        |
| `openFirewall`       | `true`               | Boolean                                      |
| `acceptDns`          | `false`              | Boolean                                      |

`lifecycle = "disabled-retained"` preserves configuration and state ownership
while disabling the daemon. It never creates an ordinary `sshd` unit or adds a
startup dependency to it; Tailscale starts through its own native unit.

Both enrollment and persistent settings explicitly apply `acceptDns` (including
`true`) and `--ssh=false`. This role uses ordinary OpenSSH over Tailscale and
must not be combined with Tailscale SSH. It does not enable or configure the
consumer's ordinary sshd. Routing features require explicit opt-in; `client`
loosens reverse-path filtering, and `server` enables forwarding in NixOS.

## State and secret boundary

The service declares `/var/lib/tailscale` as Clan state. The auth key is read
only from `config.sops.secrets.<authKeySecretName>.path` with root ownership and
mode `0400`; Access never owns or receives the value.

`authKeySecretName` must start with an ASCII letter or digit and may contain
only ASCII letters, digits, `.`, `_`, and `-`. This prevents the name from
injecting a path or configuration fragment when used as a SOPS attribute.

Prefer a one-off, expiring enrollment key; its expiry does not revoke an already
enrolled node. Node-key expiry and tagged-device policy are separate consumer
decisions. Disabled-retained still declares the secret, so keep it available.

Consumers must configure least-privilege tailnet grants and host firewall rules
for SSH/admin UI ports. Tailscale's default allow-all policy is not an Access
authorization policy. `openFirewall` only opens Tailscale's UDP transport port;
it does not open SSH or an admin UI publicly. No routing, tags, exit nodes or
tailnet policy are inferred by this generic module.

Configuration baseline checked 2026-09-05 against the pinned NixOS module and
official [CLI](https://tailscale.com/docs/reference/tailscale-cli/up),
[auth-key](https://tailscale.com/docs/features/access-control/auth-keys), and
[grants](https://tailscale.com/docs/features/access-control/grants) documentation.

## Verification

Run `nix build .#checks.x86_64-linux.tailscale-admin-contract`. The check covers
the public defaults, enabled and disabled-retained behavior, runtime secret
path, state path, SSH independence, and authoritative package selection.
