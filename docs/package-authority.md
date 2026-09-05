# Package authority

Access has one root `nixpkgs` input. `clan-core` and flake-parts follow that
pin, so each Access release identifies one tested package and library closure.
The public application outputs are `tailscale`, `stunnel`, and `openssh` for
`x86_64-linux`.

Tailscale uses the NixOS module supplied by the consumer's nixpkgs, with its
`package` option forced to the matching Access output. The emergency service
uses owned units: stunnel, sshd and host-key generation use Access packages.
Coreutils, shell, PAM, sudo and systemd remain in the consumer context. The
consumer's ordinary OpenSSH service is not enabled or repackaged by Access. Access
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
