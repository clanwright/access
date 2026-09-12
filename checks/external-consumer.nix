{
  inputs,
  pkgs,
  root,
  self,
}:
let
  moduleIds = [
    "@clanwright/stunnel-ssh-breakglass"
    "@clanwright/tailscale-admin"
  ];
  consumer = (import ./lib/consumer.nix { inherit inputs root self; }) { };
  inventory = consumer.config.inventory;
  machine = consumer.machine;
  check = import ./lib/contract.nix { lib = inputs.nixpkgs.lib; };
  contract = check "external consumer contract" {
    breakglass-runtime =
      machine.users.users ? fixture-recovery
      && builtins.isString machine.systemd.services.stunnel-ssh-breakglass.serviceConfig.ExecStart
      && builtins.isString machine.systemd.services.stunnel-ssh-breakglass-sshd.serviceConfig.ExecStart;
    inventory =
      builtins.attrNames inventory.instances == [
        "stunnel-ssh-breakglass"
        "tailscale-admin"
      ]
      && builtins.all (
        instance: instance.module.input == "access" && builtins.elem instance.module.name moduleIds
      ) (builtins.attrValues inventory.instances);
    registered-modules = builtins.attrNames self.clan.modules == moduleIds;
    service-independence = !machine.services.openssh.enable;
    tailscale-settings =
      machine.services.tailscale.enable
      && builtins.elem "--accept-dns=true" machine.services.tailscale.extraSetFlags;
  };
in
assert contract;
pkgs.runCommand "access-external-consumer" { } ''
  touch "$out"
''
