# `@clanwright/tailscale-admin`

Provides a reusable `admin-access` role through the consumer-native NixOS
`services.tailscale` module. Access selects the exact Tailscale executable;
machine placement, the auth-key value, and surrounding firewall policy remain
consumer-owned.

## Settings and defaults

| Setting             | Default              | Constraint                                   |
| ------------------- | -------------------- | -------------------------------------------- |
| `authKeySecretName` | `tailscale-auth-key` | Safe SOPS name: `[A-Za-z0-9][A-Za-z0-9._-]*` |
| `enable`            | `true`               | Boolean                                      |
| `acceptDns`         | `false`              | Boolean                                      |

The boolean `enable` maps directly to the native daemon switch rather than
introducing a separate lifecycle vocabulary. `enable = false` retains state
and secret declarations. The role never creates an ordinary `sshd` unit or adds a
startup dependency to it; Tailscale starts through its own native unit.

Both enrollment and persistent settings explicitly apply `acceptDns` (including
`true`) and `--ssh=false`. This role uses ordinary OpenSSH over Tailscale and
must not be combined with Tailscale SSH. It does not enable or configure the
consumer's ordinary sshd.

Firewall and routing policy use the consumer's native
`services.tailscale.openFirewall` and `services.tailscale.useRoutingFeatures`
options. Keeping these choices on the native module avoids a second policy API.
Choose both explicitly when adopting Access and preserve the consumer's intended
transport behavior; this role supplies no firewall or routing defaults.

## State and secret boundary

The service declares `/var/lib/tailscale` as Clan state. The auth key is read
only from `config.sops.secrets.<authKeySecretName>.path` with root ownership and
mode `0400`; Access never owns or receives the value.

`authKeySecretName` must start with an ASCII letter or digit and may contain
only ASCII letters, digits, `.`, `_`, and `-`. This prevents the name from
injecting a path or configuration fragment when used as a SOPS attribute.

Prefer a one-off, expiring enrollment key; its expiry does not revoke an already
enrolled node. Node-key expiry and tagged-device policy are separate consumer
decisions. `enable = false` still declares the secret, so keep it available.

Consumers must configure least-privilege tailnet grants and host firewall rules
for SSH/admin UI ports. Tailscale's default allow-all policy is not an Access
authorization policy. Native `services.tailscale.openFirewall` only opens
the UDP transport port; it does not open SSH or an admin UI publicly. No routing, tags, exit nodes or
tailnet policy are inferred by this generic module.

## Verification

Run `nix build .#checks.x86_64-linux.tailscale-admin-contract`. The check covers
the public defaults, both `enable` values, native consumer policy, runtime secret
path, state path, SSH independence, and authoritative package selection.

## Private-binding startup gate

The optional Linux helper `access.lib.tailscaleReadyGate { pkgs; ipv4; interface; }`
returns an executable Nix store path. Use it in the binding service's native
`ExecStartPre`, with the canonical IPv4 used by its listener and the effective
`services.tailscale.interfaceName`. For example, inside a consumer NixOS module:

```nix
{ config, inputs, pkgs, ... }:
let
  privateIpv4 = "100.64.0.10"; # Synthetic example; use the listener's actual address.
  ready = inputs.access.lib.tailscaleReadyGate {
    inherit pkgs;
    ipv4 = privateIpv4;
    interface = config.services.tailscale.interfaceName;
  };
in
{
  systemd.services.caddy.serviceConfig.ExecStartPre = [ ready ];
}
```

This helper uses Access's authoritative Tailscale package and consumer-native
jq, iproute2, coreutils and shell. The effective daemon must use the same Access
package. The helper does not configure the listener, firewall, daemon or service
dependencies, and supplies no enrollment key or privilege grant.

Each invocation performs native `tailscale wait --timeout=30s`, then verifies
one status snapshot for `Running`, kernel TUN mode and membership of the selected
node IPv4. Native `ip -j -4 address show dev` verifies that the exact interface is
`UP` and owns that IPv4. All stages share a native `timeout --kill-after=2s 35s`
bound, including the status and kernel queries. An unavailable or mismatched
state fails nonzero. Status/address JSON is not printed. There is no cache,
watcher, retry loop or fallback.

Native timeout signals the command's process group. Its kill-after escalation
is conditional: if the monitored shell exits first, a descendant ignoring TERM
can outlive the invocation. The 35-second deadline bounds the command, not
arbitrary leftover work, systemd queueing or the complete service start. Use
native systemd cgroup cleanup and retain the consuming unit's restart/start-limit
policy; do not substitute shell supervision. A failed `ExecStartPre` can trigger
native retry even when `RestartPreventExitStatus=1` suppresses a main-process
exit 1.

Generic native wait can finish on a different node IP. If the selected IP is
still absent, the exact postcheck refuses admission immediately; it does not
wait again. Success is a momentary startup observation: it does not eliminate
the race before the application binds or guarantee continued address presence.

Run under the service's existing UID and sandbox, without a `+` execution
prefix. For stock Caddy this is `User=caddy`, `Group=caddy`. The gate needs
`AF_UNIX` for LocalAPI and `AF_NETLINK` for same-namespace kernel address reads;
include both in a consumer family allowlist. The helper adds no capability or
sandbox relaxation. Consider the native vendor unit and NixOS drop-in together.

Pinned Tailscale grants Linux Unix-socket clients read access; write/operator
authorization is separate. The packaged daemon uses
`/run/tailscale/tailscaled.sock`, a `0755` runtime directory and a `0666` socket.
`wait` and `status` use read-only LocalAPI endpoints; kernel inspection uses
same-namespace netlink GET/dump. These source contracts require no root,
operator enrollment, sudo or access to the root-only state directory. See the
upstream [LocalAPI permissions](https://github.com/tailscale/tailscale/blob/v1.102.4/ipn/ipnserver/server.go#L314-L332)
and [packaged unit](https://github.com/tailscale/tailscale/blob/v1.102.4/cmd/tailscaled/tailscaled.service#L8-L15).

The helper uses the stock Linux CLI socket default. Ordinary NixOS aliases
`/var/run` to `/run`, reaching the packaged daemon socket. A consumer overriding
the daemon socket, filesystem/socket namespace or that alias falls outside
this default composition. The helper adds no socket-selection API or fallback.

Missing selected private IP blocks the whole consuming cold start/restart.
Access adds no `ExecReload` hook or transport-loss `BindsTo`, `Requires` or
`PartOf` coupling to a shared public/private service. The binding owner controls
its listener, packet policy and native reload. Independent public cold start
or updates during private-IP loss, automatic return and continuous private
socket closure are outside this startup-only contract.

`tailscale-ready-gate` checks the generated command with isolated fake CLI
processes for negative state, deadline and cancellation behavior.
`flake-contract` checks the public arguments, platform and authoritative CLI.
`tailscale-admin-contract` composes stock Caddy with the helper to check package
equality, ordinary UID, native sandbox/lifecycle preservation and consumer
Unix/netlink family declarations. The complete source-versus-runtime boundary
and required consumer observations live in
[Verification](../../docs/verification.md#predeploy-acceptance).
