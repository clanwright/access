{ pkgs, root }:
let
  config = builtins.fromJSON (builtins.readFile (root + "/renovate.json"));
  group = builtins.head config.packageRules;
  check = import ./lib/contract.nix { lib = pkgs.lib; };
in
assert check "Access Renovate policy" {
  nixOnly = config.enabledManagers == [ "nix" ];
  ignoredFlakeParts = config.ignoreDeps == [ "flake-parts" ];
  weekly = config.schedule == [ "before 6am on monday" ] && config.timezone == "Europe/Moscow";
  oneClosureGroup =
    builtins.length config.packageRules == 1
    && group.groupName == "access-closure"
    && group.matchManagers == [ "nix" ]
    &&
      group.matchDepNames == [
        "nixpkgs"
        "clan-core"
      ]
    && group.schedule == config.schedule;
  manualReview = config.automerge == false && group.automerge == false;
};
pkgs.runCommand "access-renovate-contract" { } ''touch "$out"''
