{
  inputs,
  pkgs,
  root,
  self,
}:
let
  fixture = import ./fixtures/consumer.nix;
  moduleIds = [
    "@clanwright/stunnel-ssh-breakglass"
    "@clanwright/tailscale-admin"
  ];
  consumer = inputs.clan-core.lib.clan {
    self.inputs = {
      access = self;
      self.clan = consumer.config;
    };
    specialArgs.clan-core = inputs.clan-core;
    directory = root;
    imports = [ fixture ];
  };
  inventory = consumer.config.inventory;
  machine = consumer.config.nixosConfigurations.access-node.config;
  contract =
    machine.services.tailscale.enable
    && machine.users.users ? fixture-recovery
    && builtins.elem "--accept-dns=true" machine.services.tailscale.extraSetFlags
    && !machine.services.openssh.enable
    && builtins.isString machine.systemd.services.stunnel-ssh-breakglass.serviceConfig.ExecStart
    && builtins.isString machine.systemd.services.stunnel-ssh-breakglass-sshd.serviceConfig.ExecStart
    && builtins.attrNames self.clan.modules == moduleIds
    &&
      builtins.attrNames inventory.instances == [
        "stunnel-ssh-breakglass"
        "tailscale-admin"
      ]
    && builtins.all (
      instance: instance.module.input == "access" && builtins.elem instance.module.name moduleIds
    ) (builtins.attrValues inventory.instances);
in
if contract then
  pkgs.runCommand "access-external-consumer" { } ''
    touch "$out"
  ''
else
  throw "Access external consumer contract changed"
