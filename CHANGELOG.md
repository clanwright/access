# Changelog

All notable changes to Access are recorded here. GitHub Release notes reproduce
the matching version section without rewriting it.

## [Unreleased]

## [0.3.2] - 2026-09-06

### Added

- Publish the pinned stock stunnel and OpenSSH packages on `aarch64-darwin` for
  installation before an incident.
- Check a secret-free strict recovery SSH client configuration with the pinned
  OpenSSH parser on both supported systems, and reject a missing stunnel PSK
  without opening a listener.

### Documentation

- Document the minimal native recovery path: an ordinary foreground stunnel
  loopback listener plus explicit `ssh -F` and `sftp -F` sessions, with the
  existing server host public key transferred over a trusted management path.
- Clarify that Access provides no custom recovery client, wrapper, profile,
  JSON export, or configuration command and that live Clanwright acceptance
  remains consumer-owned.

## [0.3.1] - 2026-09-06

### Fixed

- Make the break-glass sshd runtime directory group-readable by the configured
  recovery user while retaining the daemon's root UID, so OpenSSH can read the
  staged authorized-key file after switching accounts.

## [0.3.0] - 2026-09-05

### Breaking

- Restrict `authKeySecretName` on module `@clanwright/tailscale-admin`, role
  `admin-access`, to `[A-Za-z0-9][A-Za-z0-9._-]*`: the first character must be
  an ASCII letter or digit, and every remaining character must be an ASCII
  letter, digit, dot, underscore, or hyphen. Rename any incompatible consumer
  secret identifier before updating; see the
  [migration notes](https://github.com/clanwright/access/blob/v0.3.0/docs/migration-v0.3.0.md).

### Changed

- Separate the breakglass interface, NixOS runtime, and configuration rendering
  without changing the public module IDs or runtime defaults.
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
