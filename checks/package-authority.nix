{
  lib,
  mutation ? false,
  pkgs,
  self,
  system,
}:
let
  role = (import ../clanServices/tailscale-admin/default.nix { inherit self; }).roles.admin-access;
  defaults = (lib.evalModules { modules = [ role.interface ]; }).config;
  module = (role.perInstance { settings = defaults; }).nixosModule {
    config.sops.secrets.${defaults.authKeySecretName}.path =
      "/run/secrets/${defaults.authKeySecretName}";
    inherit lib pkgs;
  };
  forcedChoice =
    (lib.evalModules {
      modules = [
        {
          options.package = lib.mkOption { type = lib.types.package; };
          config.package = pkgs.hello;
        }
        { config.package = module.services.tailscale.package; }
      ];
    }).config.package;
  expected = if mutation then pkgs.hello else self.packages.${system}.tailscale;
  rejectedMutation =
    !(builtins.tryEval (
      import ./fixtures/package-override.nix {
        inherit
          lib
          pkgs
          self
          system
          ;
      }
    )).success;
  contract =
    forcedChoice == expected
    && (mutation || rejectedMutation)
    &&
      builtins.attrNames self.packages.${system} == [
        "freshness-report"
        "openssh"
        "stunnel"
        "tailscale"
      ];
in
if contract then
  pkgs.runCommand "access-package-authority"
    {
      # The emergency check verifies actual unit/config binary paths, including keygen.
      verifiedEmergency = self.checks.${system}.stunnel-ssh-breakglass-contract;
    }
    ''
      test -e "$verifiedEmergency"
      touch "$out"
    ''
else
  throw "Access package authority changed"
