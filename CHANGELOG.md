# Changelog

All notable changes to Access are recorded here. GitHub Release notes reproduce
the matching version section without rewriting it.

## [Unreleased]

### Changed

- Separate the breakglass interface, NixOS runtime, and configuration rendering
  without changing the public module IDs or runtime defaults.
- Restrict Tailscale `authKeySecretName` to safe identifiers containing letters,
  digits, dots, underscores, and hyphens, starting with a letter or digit.
  Existing names containing whitespace or shell metacharacters must be renamed.
- Share the complete local, CI, and release verification entrypoint.

### Verification fixes

- Decouple freshness behavior fixtures from pinned application versions.
- Exercise invalid secret settings through the actual service interfaces and
  force complete consumer assertions and generated systemd units.
- Validate immutable GitHub Action references and stable release tags against
  the matching changelog section, without fixing tests to an example release.

## [0.2.0] - 2026-09-05

### Breaking

- Replace `@clanwright/fail2ban-ssh` and `@clanwright/fwknop-ssh-breakglass`
  with `@clanwright/stunnel-ssh-breakglass`, role `breakglass`: TLS 1.3 PSK
  protects a separate loopback-only, public-key-authenticated OpenSSH daemon.
- Remove `fail2ban` and `fwknop` package exports; publish authoritative `stunnel`
  and `openssh` closures alongside `tailscale`.
- Default Tailscale routing features to `none` and explicitly disable Tailscale
  SSH in favor of consumer-owned ordinary OpenSSH.

### Security and fixes

- Isolate emergency host keys, authorized keys, account and service lifecycle
  from ordinary sshd and Tailscale. Recovery has explicit root-equivalent sudo;
  password/root login and SSH forwarding are disabled.
- Apply both true and false DNS preferences to existing Tailscale state.
- Stop creating a dependency-only ordinary sshd unit from the Tailscale role.
- Update service/package/secret contracts and freshness sources for the new stack.

See [migration notes](docs/migration-v0.2.0.md). This release does not deploy,
rotate secrets, create a recovery repository, or update consumer locks.

## [0.1.0] - 2026-09-04

### Added

- `@clanwright/tailscale-admin`, with independently configurable placement,
  retained state ownership, disabled-retained lifecycle, and an
  Access-authoritative Tailscale closure.
- `@clanwright/fail2ban-ssh`, with SSH jail defaults, ignored-network and
  bootstrap-marker controls, and an Access-authoritative Fail2ban closure.
- `@clanwright/fwknop-ssh-breakglass`, with hardened high-port SSH, SPA runtime
  configuration, iptables enforcement, root-only runtime secret paths, and an
  Access-authoritative fwknop closure.
- External-consumer, independent-placement, package-authority, secret-boundary,
  freshness, release, and repository policy checks.
- Weekly non-automerge dependency grouping, machine-readable freshness
  metadata, secret-free CI, and a non-publishing release gate.
