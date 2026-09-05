# Migrating from v0.2.x to v0.3.0

This release tightens one consumer-facing setting. Consumer adaptation and
deployment remain separate changes owned by the consumer.

## Breaking setting

Module `@clanwright/tailscale-admin`, role `admin-access`, now requires
`authKeySecretName` to match `[A-Za-z0-9][A-Za-z0-9._-]*`. The first character
must be an ASCII letter or digit. Each remaining character must be an ASCII
letter, digit, dot, underscore, or hyphen. Empty names, names beginning with
`.`, `_`, or `-`, and names containing slashes, whitespace, or other characters
are rejected during evaluation. The default `tailscale-auth-key` remains valid.

Before updating:

1. Inspect only the configured secret identifier names in the consumer's
   Tailscale service instances and secret-provisioning metadata. Do not read or
   decrypt secret values for this migration.
2. For each incompatible name, choose a unique valid identifier and update both
   `authKeySecretName` and the matching consumer-owned provisioning metadata in
   the same reviewed change. Check for collisions explicitly: mechanically
   changing `a/b` to `a-b`, for example, can collide with an existing `a-b`.
3. After the signed `v0.3.0` release is available, pin that exact release and
   build the actual consumer configurations before any deployment.

Access does not rename provisioning records or rotate credentials
automatically. This migration changes identifier compatibility only; any
credential lifecycle decision remains with the consumer.

The public module IDs, roles, setting defaults, and the root-pinned `tailscale`,
`stunnel`, and `openssh` package closures are unchanged from `v0.2.0`.
Consumers on `v0.1.x` must complete the [v0.2.0 migration](migration-v0.2.0.md)
before applying these notes.
