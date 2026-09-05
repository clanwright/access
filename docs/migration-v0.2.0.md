# Migrating from v0.1.x

This is a breaking, general-purpose Access release. Consumer adaptation and
deployment are separate changes, not performed by Access.

## Removed surfaces

Remove `@clanwright/fail2ban-ssh` and `@clanwright/fwknop-ssh-breakglass`
instances. Their roles, settings and the `fail2ban`/`fwknop` package exports
are removed, without compatibility aliases. No SPA, temporary firewall grants
or iptables backend requirement remains. Historical secret values and deployed
state are not deleted by this repository.

## New emergency channel

Place `@clanwright/stunnel-ssh-breakglass`, role `breakglass`, independently of
Tailscale. Follow its [service API](../clanServices/stunnel-ssh-breakglass/README.md).
Provide per-server PSK and authorized-key runtime secrets, choose a free public
TCP port, and allow that TLS port in the consumer/provider firewall. Do not
expose the loopback backend SSH port. No DNS, certificates, ACME, management
server or custom VPN is required. This is an authenticated visible TLS listener,
not a hidden port and not a guarantee against network filtering or DoS.

The recovery account has full passwordless sudo. Retain the independently
verified SSH host fingerprint and a client configuration with strict host-key
checking. Two shared credentials on the same Mac are layered authentication,
not independent MFA. Never reuse them across servers.

## Daily access

`useRoutingFeatures` now defaults to `none`, not `client`; explicitly opt in if
the consumer needs subnet/exit routing. Both DNS values are now actively applied.
Tailscale SSH is explicitly disabled; ordinary OpenSSH remains consumer-owned.
Review tailnet grants and host-interface firewall rules for all admin ports.

## Owner acceptance after the release

Build the actual consumer closure before deployment. On the owner's selected
server, verify TLS + SSH success, sudo and SFTP, rejected invalid credentials,
no raw public SSH backend, and disabled forwarding. Verify recovery with
Tailscale and ordinary sshd stopped, then repair/restart Tailscale. Confirm
successful-login journal events reach the consumer's notification destination
without making login depend on it. Repeat after changes and approximately
monthly. Keep a working session during the initial transition; removing the
old channel before verifying the new one risks lockout without provider console.

## Recovery material

Access owns no backup or secret storage. A consumer may keep an age-passphrase-
encrypted recovery kit in a separate private GitHub repository plus a local Mac
copy. The owner chooses and enters the passphrase locally: never in Nix, command
arguments, logs, CI or this repository. Private GitHub visibility is not
encryption. Retain independent GitHub/2FA recovery access so losing the Mac does
not create a circular dependency. This release creates neither that repository
nor credentials, and does not perform backup/restore operations.
