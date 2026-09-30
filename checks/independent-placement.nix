{
  inputs,
  lib,
  pkgs,
  root,
  self,
}:
let
  placements = [
    [ ]
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
        builtins.attrNames config.inventory.instances == lib.sort builtins.lessThan instanceNames
        && builtins.all (
          instance:
          instance.module.input == "access"
          && builtins.elem instance.module.name [
            "@clanwright/stunnel-ssh-breakglass"
            "@clanwright/tailscale-admin"
          ]
        ) (builtins.attrValues config.inventory.instances);
      consumer-settings =
        !hasTailscale || builtins.elem "--accept-dns=true" machine.services.tailscale.extraSetFlags;
      breakglass-runtime =
        !hasEmergency
        || (
          builtins.isString units.stunnel-ssh-breakglass.serviceConfig.ExecStart
          && builtins.isString units.stunnel-ssh-breakglass-sshd.serviceConfig.ExecStart
        );
      ordinary-sshd-independent = !machine.services.openssh.enable && !(units ? sshd);
      service-placement =
        machine.services.tailscale.enable == hasTailscale
        && (units ? stunnel-ssh-breakglass) == hasEmergency
        && (units ? stunnel-ssh-breakglass-sshd) == hasEmergency
        && (units ? stunnel-ssh-breakglass-hostkey) == hasEmergency
        && (units ? tailscaled) == hasTailscale;
      recovery-placement =
        (machine.users.users ? access-recovery) == hasEmergency
        && (machine.users.groups ? access-recovery) == hasEmergency
        && (machine.security.pam.services ? stunnel-ssh-breakglass-sshd) == hasEmergency
        &&
          (builtins.any (
            rule: builtins.elem "access-recovery" (rule.users or [ ])
          ) machine.security.sudo.extraRules) == hasEmergency;
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
