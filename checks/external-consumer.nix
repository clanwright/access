{
  inputs,
  pkgs,
  root,
  self,
}:
let
  fixture = import ./fixtures/consumer.nix;
  moduleIds = [
    "@clanwright/fail2ban-ssh"
    "@clanwright/fwknop-ssh-breakglass"
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
  contract =
    builtins.deepSeq consumer.config._services.allServices true
    && builtins.attrNames self.clan.modules == moduleIds
    &&
      builtins.attrNames inventory.instances == [
        "fail2ban-ssh"
        "fwknop-ssh-breakglass"
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
