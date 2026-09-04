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
  fwknop-ssh-breakglass-contract = import ./fwknop-ssh-breakglass.nix {
    inherit
      inputs
      pkgs
      self
      system
      ;
    lib = inputs.nixpkgs.lib;
  };
  external-consumer = import ./external-consumer.nix {
    inherit
      inputs
      pkgs
      root
      self
      ;
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
  service-contracts = import ./service-contracts.nix {
    inherit pkgs self system;
  };
  package-authority = import ./package-authority.nix {
    inherit pkgs self system;
    lib = inputs.nixpkgs.lib;
  };
  secret-contract = import ./secret-contract.nix {
    inherit pkgs root self;
    lib = inputs.nixpkgs.lib;
  };
}
