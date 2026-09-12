{
  inputs,
  lib,
  pkgs,
  root,
  self,
  system,
}:
let
  consumerFor = import ./lib/consumer.nix { inherit inputs root self; };
  tailscaleInstance = {
    tailscale-admin = {
      module = {
        input = "access";
        name = "@clanwright/tailscale-admin";
      };
      roles.admin-access.machines.access-node = { };
    };
  };
  baseline = (consumerFor { instances = tailscaleInstance; }).machine;
  attemptedOverride =
    (consumerFor {
      instances = tailscaleInstance;
      machineModules = [ (import ./fixtures/package-override.nix) ];
    }).machine;
  check = import ./lib/contract.nix { inherit lib; };
  contract = check "package authority contract" {
    package-outputs =
      builtins.attrNames self.packages.${system} == [
        "freshness-report"
        "openssh"
        "stunnel"
        "tailscale"
      ];
    registered-consumer-package =
      baseline.services.tailscale.package == self.packages.${system}.tailscale;
    consumer-override-rejected =
      attemptedOverride.services.tailscale.package == self.packages.${system}.tailscale;
  };
in
assert contract;
pkgs.runCommand "access-package-authority"
  {
    verifiedEmergency = self.checks.${system}.stunnel-ssh-breakglass-contract;
  }
  ''
    test -e "$verifiedEmergency"
    touch "$out"
  ''
