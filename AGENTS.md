# Project Context

Access is a public, versioned Clan flake for administrative access and SSH
protection. It owns the Tailscale, Fail2ban, and fwknop application closures and
the reusable Clan service recipes that configure them.

## Authority

1. Runtime code and evaluated configuration outrank prose.
2. `README.md` is the documentation index; adjacent service READMEs own service
   API and implementation details.
3. Access owns no machine placement, secret value, provider operation, backup,
   restore, or deployment procedure.
4. Secret interfaces contain names and runtime paths only. Never add, decrypt,
   print, or fixture a credential or generated access artifact.
5. One root nixpkgs pin owns all three application closures. Consumers receive
   no package override or nixpkgs-follow interface.

## Workflow

- Implement behavior test-first and keep each brick independently evaluable.
- Use native Clan `clan.modules` exports and consumer-native NixOS modules.
- Run focused checks after every change and `nix flake check
--no-write-lock-file` before review.
- Run a redacted full-tree secret scan before every commit.
- Hosted workflows are secret-free and may test or report freshness only. They
  never merge, release, deploy, or modify a consumer lock.
- Releases require a protected-main commit, a manually signed tag, a green tag
  gate, and a separately manual GitHub Release.

## Closed boundaries

Do not create or mutate GitHub resources, publish a release, deploy a machine,
or perform provider, secret, backup, restore, or prune operations without an
explicit owner approval in the current turn.
