{
  inputs,
  pkgs,
  root,
  self,
  system,
}:
{
  repository-policy = import ./repository-policy.nix { inherit pkgs root; };
  verification-contract = import ./verification-contract.nix { inherit pkgs root; };
  secret-scan-contract = import ./secret-scan.nix { inherit pkgs root; };
  flake-contract = import ./flake-contract.nix {
    inherit
      inputs
      pkgs
      root
      self
      system
      ;
  };
  tailscale-admin-contract = import ./tailscale-admin.nix {
    inherit
      inputs
      pkgs
      root
      self
      system
      ;
    lib = inputs.nixpkgs.lib;
  };
  tailscale-ready-gate = import ./tailscale-ready-gate.nix { inherit pkgs; };
  stunnel-ssh-breakglass-contract = import ./stunnel-ssh-breakglass.nix {
    inherit
      inputs
      pkgs
      root
      self
      system
      ;
    lib = inputs.nixpkgs.lib;
  };
  independent-placement = import ./independent-placement.nix {
    inherit
      inputs
      pkgs
      root
      self
      ;
    lib = inputs.nixpkgs.lib;
  };
  renovate-contract = import ./renovate-contract.nix {
    inherit pkgs root;
  };
  release-contract = import ./release-contract.nix {
    inherit pkgs root;
  };
}
