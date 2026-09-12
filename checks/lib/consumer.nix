{
  inputs,
  root,
  self,
}:
{
  forceMachine ? true,
  instanceNames ? null,
  instances ? null,
  machineName ? "access-node",
  machineNames ? [ "access-node" ],
  machineModules ? [ ],
}:
let
  baseFixture = import ../fixtures/consumer.nix { };
  requestedInstances =
    if instances != null then
      instances
    else if instanceNames != null then
      builtins.intersectAttrs (inputs.nixpkgs.lib.genAttrs instanceNames (
        _: null
      )) baseFixture.inventory.instances
    else
      baseFixture.inventory.instances;
  fixture = import ../fixtures/consumer.nix {
    instances = requestedInstances;
    inherit machineNames machineModules;
  };
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
        inherit (fixture) inventory;
      }
    ];
  };
  config = consumer.config;
  machine = config.nixosConfigurations.${machineName}.config;
  # Force every assertion, unit rendering, and the full NixOS derivation.
  # This evaluates the pinned consumer; it does not build or run the machine.
  assertionsPass = builtins.all (entry: entry.assertion) machine.assertions;
  unitTexts = builtins.mapAttrs (_: unit: unit.text) machine.systemd.units;
  evaluated = builtins.deepSeq unitTexts (
    builtins.seq machine.system.build.toplevel.drvPath assertionsPass
  );
in
assert !forceMachine || evaluated;
{
  inherit
    config
    evaluated
    machine
    ;
}
