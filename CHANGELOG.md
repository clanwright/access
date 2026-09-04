# Changelog

All notable changes to Access are recorded here. GitHub Release notes reproduce
the matching version section without rewriting it.

## [Unreleased]

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
