{ pkgs, root }:
{
  repository-policy = import ./repository-policy.nix { inherit pkgs root; };
}
