# `@clanwright/fwknop-ssh-breakglass`

Provides a reusable `breakglass` role for hidden WAN SSH access through
fwknop Single Packet Authorization. Access selects the exact fwknop executable;
the consumer supplies OpenSSH, iptables and core utility packages plus
placement, secrets, and firewall policy. The role provisions the native
OpenSSH host-key, privilege-separation user, and PAM prerequisites needed by
its standalone daemon.

## Settings and defaults

| Setting          | Default             |
| ---------------- | ------------------- |
| `sshPort`        | `47291`             |
| `spaUdpPort`     | `62201`             |
| `accessTimeout`  | `300` seconds       |
| `wanListenIPv4`  | `0.0.0.0`           |
| `keySecretName`  | `fwknop-access-key` |
| `hmacSecretName` | `fwknop-hmac-key`   |

The role creates a hardened high-port SSH daemon and fwknopd. It requires the
iptables firewall backend and rejects `networking.nftables.enable = true`.

## Secret boundary

Only SOPS secret names and runtime paths cross the interface. Both files are
root-owned with mode `0400`; rotation restarts `fwknop-ssh-breakglass.service`.
The service renders fwknop configuration at runtime and never stores key
payloads in the Nix store.

## Network boundary

By default, the break-glass SSH daemon listens on TCP `47291`, while fwknopd
receives SPA packets on UDP `62201` and opens a temporary iptables rule for at
most 300 seconds. The role does not expose an HTTP endpoint or own the consumer
firewall policy.

## Verification

Run `nix build .#checks.x86_64-linux.fwknop-ssh-breakglass-contract`. The check
covers defaults, unit ordering and hardening, generated configuration,
root-only secret metadata, the iptables assertion, and fwknop package authority
without reading a secret payload.
