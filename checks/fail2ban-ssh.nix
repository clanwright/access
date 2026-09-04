{
  inputs,
  lib,
  pkgs,
  self,
  system,
}:
let
  registeredModule =
    self.clan.modules."@clanwright/fail2ban-ssh"
      or (throw "@clanwright/fail2ban-ssh is not registered");
  evaluatedService =
    (inputs.clan-core.lib.evalService {
      modules = [ registeredModule ];
      prefix = [ ];
    }).config;
  service = import ../clanServices/fail2ban-ssh/default.nix { inherit self; };
  role = service.roles.ssh-guard;
  defaults = (lib.evalModules { modules = [ role.interface ]; }).config;
  moduleFor = settings: (role.perInstance { inherit settings; }).nixosModule { inherit lib pkgs; };
  enabled = moduleFor defaults;
  disabled = moduleFor (defaults // { lifecycle = "disabled-retained"; });
  ignoredNetworks = moduleFor (
    defaults
    // {
      ignoreIPs = [
        "100.64.0.0/10"
        "10.0.0.0/8"
      ];
    }
  );
  markerPath = "/run/access bootstrap's";
  marker = moduleFor (defaults // { bootstrapMarkerPath = markerPath; });
  unwrap = value: if builtins.isAttrs value && value ? content then unwrap value.content else value;
  consumerPackageChoice =
    (lib.evalModules {
      modules = [
        {
          options.package = lib.mkOption { type = lib.types.package; };
          config.package = pkgs.hello;
        }
        { config.package = enabled.services.fail2ban.package; }
      ];
    }).config.package;
  jail = enabled.services.fail2ban.jails.sshd.settings;
  contract =
    builtins.deepSeq evaluatedService.result.api.schema true
    && service.manifest.name == "@clanwright/fail2ban-ssh"
    && builtins.attrNames service.roles == [ "ssh-guard" ]
    && defaults.lifecycle == "enabled"
    && defaults.maxretry == 5
    && defaults.findtime == "10m"
    && defaults.bantime == "1h"
    && defaults.backend == "systemd"
    && defaults.ignoreIPs == [ ]
    && defaults.bootstrapMarkerPath == null
    && enabled.services.fail2ban.enable
    && jail.enabled
    && jail.maxretry == 5
    && jail.findtime == "10m"
    && jail.bantime == "1h"
    && jail.backend == "systemd"
    && !(jail ? ignoreip)
    && disabled == { }
    && ignoredNetworks.services.fail2ban.jails.sshd.settings.ignoreip == "100.64.0.0/10 10.0.0.0/8"
    &&
      marker.services.fail2ban.jails.sshd.settings.ignorecommand
      == "${lib.getExe pkgs.bash} -c ${lib.escapeShellArg ''test -e "$1"''} -- ${lib.escapeShellArg markerPath}"
    && !(marker ? systemd)
    && unwrap enabled.services.fail2ban.package == self.packages.${system}.fail2ban
    && consumerPackageChoice == self.packages.${system}.fail2ban
    && !(enabled ? sops)
    && !(enabled ? clan)
    && !(enabled ? networking);
in
if contract then
  pkgs.runCommand "fail2ban-ssh-contract" { } ''
    touch "$out"
  ''
else
  throw "Fail2ban SSH contract changed"
