{
  inputs,
  root,
  self,
}:
let
  fixture = import ../fixtures/consumer.nix;
in
{
  instanceNames ? builtins.attrNames fixture.inventory.instances,
}:
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
          instances = builtins.intersectAttrs (inputs.nixpkgs.lib.genAttrs instanceNames (
            _: null
          )) fixture.inventory.instances;
        };
      }
    ];
  };
  config = consumer.config;
  machine = config.nixosConfigurations.access-node.config;
  # Force every assertion, unit rendering, and the full NixOS derivation.
  # This evaluates the pinned consumer; it does not build or run the machine.
  assertionsPass = builtins.all (entry: entry.assertion) machine.assertions;
  unitTexts = builtins.mapAttrs (_: unit: unit.text) machine.systemd.units;
  evaluated = builtins.deepSeq unitTexts (
    builtins.seq machine.system.build.toplevel.drvPath assertionsPass
  );
in
assert evaluated;
{
  inherit config machine;
}
