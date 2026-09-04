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
    [ "fail2ban-ssh" ]
    [ "fwknop-ssh-breakglass" ]
    [
      "tailscale-admin"
      "fail2ban-ssh"
      "fwknop-ssh-breakglass"
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
    in
    builtins.deepSeq config._services.allServices true
    && builtins.attrNames config.inventory.instances == lib.sort builtins.lessThan instanceNames
    &&
      builtins.length (builtins.attrNames config._services.allServices) == builtins.length instanceNames;
in
if builtins.all placementMatches placements then
  pkgs.runCommand "access-independent-placement" { } ''
    touch "$out"
  ''
else
  throw "Access independent placement contract changed"
