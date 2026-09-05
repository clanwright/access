{
  inputs,
  lib,
  pkgs,
  root,
  self,
}:
let
  fixture = import ./fixtures/consumer.nix;
  placements = [
    [ "tailscale-admin" ]
    [ "stunnel-ssh-breakglass" ]
    [
      "tailscale-admin"
      "stunnel-ssh-breakglass"
    ]
  ];
  consumerFor =
    instanceNames:
    let
      consumer = inputs.clan-core.lib.clan {
        self.inputs = {
          access = self;
          self.clan = consumer.config;
        };
        specialArgs.clan-core = inputs.clan-core;
        directory = root;
        imports = [
          {
            inherit (fixture) machines;
            inventory = fixture.inventory // {
              instances = builtins.intersectAttrs (lib.genAttrs instanceNames (
                _: null
              )) fixture.inventory.instances;
            };
          }
        ];
      };
    in
    consumer.config;
  placementMatches =
    instanceNames:
    let
      config = consumerFor instanceNames;
      machine = config.nixosConfigurations.access-node.config;
      hasTailscale = builtins.elem "tailscale-admin" instanceNames;
      hasEmergency = builtins.elem "stunnel-ssh-breakglass" instanceNames;
      units = machine.systemd.services;
    in
    builtins.attrNames config.inventory.instances == lib.sort builtins.lessThan instanceNames
    &&
      builtins.length (builtins.attrNames config._services.allServices) == builtins.length instanceNames
    && machine.services.tailscale.enable == hasTailscale
    && !machine.services.openssh.enable
    && !(units ? sshd)
    && (units ? stunnel-ssh-breakglass) == hasEmergency
    && (units ? stunnel-ssh-breakglass-sshd) == hasEmergency
    && (units ? stunnel-ssh-breakglass-hostkey) == hasEmergency
    && (units ? tailscaled) == hasTailscale
    && (
      if hasEmergency then
        lib.hasPrefix "${self.packages.x86_64-linux.openssh}/bin/sshd " units.stunnel-ssh-breakglass-sshd.serviceConfig.ExecStart
        && !(builtins.elem "tailscaled.service" (
          units.stunnel-ssh-breakglass.after ++ units.stunnel-ssh-breakglass.requires
        ))
      else
        true
    );
in
if builtins.all placementMatches placements then
  pkgs.runCommand "access-independent-placement" { } ''
    touch "$out"
  ''
else
  throw "Access independent placement contract changed"
