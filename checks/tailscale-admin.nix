{
  inputs,
  lib,
  pkgs,
  self,
  system,
}:
let
  registeredModule =
    self.clan.modules."@clanwright/tailscale-admin"
      or (throw "@clanwright/tailscale-admin is not registered");
  evaluatedService =
    (inputs.clan-core.lib.evalService {
      modules = [ registeredModule ];
      prefix = [ ];
    }).config;
  service = import ../clanServices/tailscale-admin/default.nix { inherit self; };
  role = service.roles.admin-access;
  defaults = (lib.evalModules { modules = [ role.interface ]; }).config;
  moduleFor =
    settings:
    (role.perInstance { inherit settings; }).nixosModule {
      config.sops.secrets.${settings.authKeySecretName}.path =
        "/run/secrets/${settings.authKeySecretName}";
      inherit lib pkgs;
    };
  enabled = moduleFor defaults;
  disabled = moduleFor (defaults // { lifecycle = "disabled-retained"; });
  unwrap = value: if builtins.isAttrs value && value ? content then unwrap value.content else value;
  consumerPackageChoice =
    (lib.evalModules {
      modules = [
        {
          options.package = lib.mkOption { type = lib.types.package; };
          config.package = pkgs.hello;
        }
        { config.package = enabled.services.tailscale.package; }
      ];
    }).config.package;
  contract =
    builtins.deepSeq evaluatedService.result.api.schema true
    && service.manifest.name == "@clanwright/tailscale-admin"
    && builtins.attrNames service.roles == [ "admin-access" ]
    && defaults.authKeySecretName == "tailscale-auth-key"
    && defaults.lifecycle == "enabled"
    && defaults.useRoutingFeatures == "client"
    && defaults.openFirewall
    && !defaults.acceptDns
    && enabled.services.tailscale.enable
    && !(disabled.services.tailscale.enable)
    && enabled.services.tailscale.authKeyFile == "/run/secrets/tailscale-auth-key"
    && enabled.services.tailscale.extraUpFlags == [ "--accept-dns=false" ]
    && enabled.services.tailscale.extraSetFlags == [ "--accept-dns=false" ]
    && unwrap enabled.services.tailscale.package == self.packages.${system}.tailscale
    && consumerPackageChoice == self.packages.${system}.tailscale
    && enabled.clan.core.state.tailscale.folders == [ "/var/lib/tailscale" ]
    && enabled.systemd.services.sshd.wants.condition
    && !(disabled.systemd.services.sshd.wants.condition)
    && enabled.sops.secrets.tailscale-auth-key.owner == "root"
    && enabled.sops.secrets.tailscale-auth-key.group == "root"
    && enabled.sops.secrets.tailscale-auth-key.mode == "0400";
in
if contract then
  pkgs.runCommand "tailscale-admin-contract" { } ''
    touch "$out"
  ''
else
  throw "Tailscale admin contract changed"
