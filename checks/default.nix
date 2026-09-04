{
  inputs,
  pkgs,
  root,
  self,
  system,
}:
{
  repository-policy = import ./repository-policy.nix { inherit pkgs root; };
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
      self
      system
      ;
    lib = inputs.nixpkgs.lib;
  };
  fail2ban-ssh-contract = import ./fail2ban-ssh.nix {
    inherit
      inputs
      pkgs
      self
      system
      ;
    lib = inputs.nixpkgs.lib;
  };
}
