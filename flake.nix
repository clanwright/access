{
  description = "Versioned Clan access services with authoritative application closures";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    clan-core = {
      url = "github:clan-lol/clan-core";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { self, ... }:
      {
        systems = [
          "aarch64-darwin"
          "x86_64-linux"
        ];

        flake.clan.modules = {
          "@clanwright/tailscale-admin" = import ./clanServices/tailscale-admin/default.nix {
            inherit self;
          };
          "@clanwright/stunnel-ssh-breakglass" = import ./clanServices/stunnel-ssh-breakglass/default.nix {
            inherit self;
          };
        };

        flake.lib.tailscaleReadyGate =
          {
            pkgs,
            ipv4,
            interface,
          }:
          import ./lib/tailscale-ready-gate.nix {
            inherit pkgs ipv4 interface;
            tailscale =
              self.packages.${pkgs.stdenv.hostPlatform.system}.tailscale
                or (throw "Access Tailscale readiness requires a supported Linux package output");
          };

        perSystem =
          {
            lib,
            pkgs,
            system,
            ...
          }:
          {
            formatter = pkgs.nixfmt;
            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.actionlint
                pkgs.bash
                pkgs.coreutils
                pkgs.gitleaks
                pkgs.git
                pkgs.jq
                pkgs.nixfmt
                pkgs.openssh
                pkgs.prettier
                pkgs.renovate
                pkgs.shellcheck
                pkgs.zizmor
              ];
            };
            packages = {
              inherit (pkgs) stunnel openssh;
            }
            // lib.optionalAttrs (system == "x86_64-linux") {
              inherit (pkgs) tailscale;
            };
            checks = {
              recovery-client-config = import ./checks/recovery-client-config.nix {
                inherit pkgs;
                readme = ./clanServices/stunnel-ssh-breakglass/README.md;
              };
            }
            // lib.optionalAttrs (system == "x86_64-linux") (
              import ./checks {
                inherit
                  inputs
                  pkgs
                  self
                  system
                  ;
                root = ./.;
              }
            );
          };
      }
    );
}
