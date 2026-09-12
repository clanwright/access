{
  inputs,
  lib,
  pkgs,
  root,
  self,
}:
let
  placements = [
    [ "tailscale-admin" ]
    [ "stunnel-ssh-breakglass" ]
    [
      "tailscale-admin"
      "stunnel-ssh-breakglass"
    ]
  ];
  consumerFor = import ./lib/consumer.nix { inherit inputs root self; };
  placementChecks =
    instanceNames:
    let
      consumer = consumerFor { inherit instanceNames; };
      inherit (consumer) config machine;
      hasTailscale = builtins.elem "tailscale-admin" instanceNames;
      hasEmergency = builtins.elem "stunnel-ssh-breakglass" instanceNames;
      units = machine.systemd.services;
    in
    {
      inventory =
        builtins.attrNames config.inventory.instances == lib.sort builtins.lessThan instanceNames;
      ordinary-sshd-independent = !machine.services.openssh.enable && !(units ? sshd);
      service-placement =
        machine.services.tailscale.enable == hasTailscale
        && (units ? stunnel-ssh-breakglass) == hasEmergency
        && (units ? stunnel-ssh-breakglass-sshd) == hasEmergency
        && (units ? stunnel-ssh-breakglass-hostkey) == hasEmergency
        && (units ? tailscaled) == hasTailscale;
      transport-independence =
        if hasEmergency then
          lib.hasPrefix "${self.packages.x86_64-linux.openssh}/bin/sshd " units.stunnel-ssh-breakglass-sshd.serviceConfig.ExecStart
          && !(builtins.elem "tailscaled.service" (
            units.stunnel-ssh-breakglass.after ++ units.stunnel-ssh-breakglass.requires
          ))
        else
          true;
    };
  check = import ./lib/contract.nix { inherit lib; };
  contract = builtins.all (
    instanceNames:
    check "independent placement (${lib.concatStringsSep "+" instanceNames})" (
      placementChecks instanceNames
    )
  ) placements;
in
assert contract;
pkgs.runCommand "access-independent-placement" { } ''
  touch "$out"
''
