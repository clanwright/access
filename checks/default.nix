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
}
