{
  description = "Versioned Clan access services with authoritative application closures";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      checks.${system}.repository-policy = import ./checks/repository-policy.nix {
        inherit pkgs;
        root = ./.;
      };
      formatter.${system} = pkgs.nixfmt;
    };
}
