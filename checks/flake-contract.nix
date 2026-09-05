{
  inputs,
  pkgs,
  root,
  self,
  system,
}:
let
  lock = builtins.fromJSON (builtins.readFile (root + "/flake.lock"));
  nixpkgsNodes = builtins.filter (
    name:
    let
      original = lock.nodes.${name}.original or { };
    in
    (original.owner or null) == "NixOS" && (original.repo or null) == "nixpkgs"
  ) (builtins.attrNames lock.nodes);
  rootInputs = lock.nodes.root.inputs;
  clanCoreNode = rootInputs.clan-core or null;
  flakePartsNode = rootInputs.flake-parts or null;
  nixpkgsNode = rootInputs.nixpkgs or null;
  packages = self.packages.${system} or { };
  packageContract = builtins.all (name: builtins.hasAttr name packages) [
    "tailscale"
    "stunnel"
    "openssh"
  ];
  inputContract =
    inputs ? clan-core
    && inputs ? flake-parts
    && clanCoreNode != null
    && flakePartsNode != null
    && nixpkgsNode != null
    && lock.nodes.${clanCoreNode}.inputs.nixpkgs == [ "nixpkgs" ]
    && lock.nodes.${flakePartsNode}.inputs.nixpkgs-lib == [ "nixpkgs" ];
  registryContract = self ? clan && self.clan ? modules;
  developmentHostContract =
    self.devShells ? aarch64-darwin
    && self.devShells.aarch64-darwin ? default
    && self.formatter ? aarch64-darwin
    && builtins.attrNames (self.packages.aarch64-darwin or { }) == [ ]
    && builtins.attrNames (self.checks.aarch64-darwin or { }) == [ ];
  closedConsumerSurface =
    builtins.attrNames (self.overlays or { }) == [ ]
    && builtins.attrNames (self.nixosModules or { }) == [ ];
in
if
  builtins.length nixpkgsNodes == 1
  && packageContract
  && inputContract
  && registryContract
  && developmentHostContract
  && closedConsumerSurface
then
  pkgs.runCommand "access-flake-contract" { } ''
    touch "$out"
  ''
else
  throw "Access package and registry contract is incomplete"
