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
        systems = [ "x86_64-linux" ];

        imports = [
          inputs.clan-core.flakeModules.default
          ./flake-module.nix
        ];

        perSystem =
          {
            pkgs,
            system,
            ...
          }:
          {
            packages = {
              inherit (pkgs) tailscale fail2ban fwknop;
            };
            checks = import ./checks {
              inherit
                inputs
                pkgs
                self
                system
                ;
              root = ./.;
            };
            formatter = pkgs.nixfmt;
          };
      }
    );
}
