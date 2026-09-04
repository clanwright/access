# Package authority

Access has one root `nixpkgs` input. `clan-core` and flake-parts follow that
pin, so each Access release identifies one tested package and library closure.
The public application outputs are `tailscale`, `fail2ban`, and `fwknop` for
`x86_64-linux`.

Tailscale and Fail2ban use the NixOS modules supplied by the consumer's
nixpkgs. Their `package` options are forced to the matching Access outputs.
fwknop is a custom unit: only its daemon path comes from Access, while OpenSSH,
iptables, coreutils, shell, and systemd remain in the consumer context. Access
does not export an overlay, NixOS module stack, package selector, or package
override option.

This creates an intentional compatibility boundary: a consumer-native NixOS
module may be older or newer than the Access package. Access verifies its own
current baseline and an external Clan fixture; each consumer must additionally
build its real machine closures before deployment. A compatibility failure is
fixed by a new Access release or a reviewed consumer update, never by silently
selecting a consumer package.

Package and transitive closure changes are released atomically even when the
three primary version strings do not change.
