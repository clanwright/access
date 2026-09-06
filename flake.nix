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

        imports = [
          inputs.clan-core.flakeModules.default
          ./flake-module.nix
        ];

        perSystem =
          {
            lib,
            pkgs,
            system,
            ...
          }:
          let
            freshnessReport = import ./packages/freshness-report.nix {
              inherit pkgs;
              versions = {
                tailscale = pkgs.tailscale.version;
                stunnel = pkgs.stunnel.version;
                openssh = pkgs.openssh.version;
              };
            };
          in
          {
            formatter = pkgs.nixfmt;
            devShells.default = pkgs.mkShell {
              packages = [
                pkgs.actionlint
                pkgs.gitleaks
                pkgs.nixfmt
                pkgs.prettier
                (pkgs.python3.withPackages (packages: [ packages.pyyaml ]))
                pkgs.renovate
              ];
            };
            packages = {
              inherit (pkgs) stunnel openssh;
            }
            // lib.optionalAttrs (system == "x86_64-linux") {
              inherit (pkgs) tailscale;
              freshness-report = freshnessReport;
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
