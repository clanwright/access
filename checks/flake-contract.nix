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
  packageContract =
    builtins.attrNames packages == [
      "openssh"
      "stunnel"
      "tailscale"
    ];
  inputContract =
    inputs ? clan-core
    && inputs ? flake-parts
    && clanCoreNode != null
    && flakePartsNode != null
    && nixpkgsNode != null
    && lock.nodes.${clanCoreNode}.inputs.nixpkgs == [ "nixpkgs" ]
    && lock.nodes.${flakePartsNode}.inputs.nixpkgs-lib == [ "nixpkgs" ];
  registryContract =
    builtins.attrNames (self.clan.modules or { }) == [
      "@clanwright/stunnel-ssh-breakglass"
      "@clanwright/tailscale-admin"
    ];
  developmentHostContract =
    self.devShells ? aarch64-darwin
    && self.devShells.aarch64-darwin ? default
    && self.formatter ? aarch64-darwin
    &&
      builtins.attrNames (self.packages.aarch64-darwin or { }) == [
        "openssh"
        "stunnel"
      ]
    && builtins.attrNames (self.checks.aarch64-darwin or { }) == [ "recovery-client-config" ];
  closedConsumerSurface =
    builtins.attrNames (self.overlays or { }) == [ ]
    && builtins.attrNames (self.nixosModules or { }) == [ ];
  readyGate = self.lib.tailscaleReadyGate {
    inherit pkgs;
    ipv4 = "100.64.0.10";
    interface = "tailscale0";
  };
  readyGateContract =
    builtins.attrNames (self.lib or { }) == [ "tailscaleReadyGate" ]
    &&
      builtins.functionArgs self.lib.tailscaleReadyGate == {
        pkgs = false;
        ipv4 = false;
        interface = false;
      }
    && !(builtins.tryEval (
      self.lib.tailscaleReadyGate {
        pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
        ipv4 = "100.64.0.10";
        interface = "tailscale0";
      }
    )).success;
in
if
  builtins.length nixpkgsNodes == 1
  && packageContract
  && inputContract
  && registryContract
  && developmentHostContract
  && closedConsumerSurface
  && readyGateContract
then
  pkgs.runCommand "access-flake-contract" { } ''
    test -x ${readyGate}
    grep -Fq ${pkgs.lib.escapeShellArg "${packages.tailscale}/bin/tailscale"} ${readyGate}
    touch "$out"
  ''
else
  throw "Access package and registry contract is incomplete"
