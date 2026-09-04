{
  inputs,
  lib,
  pkgs,
  self,
  system,
}:
let
  registeredModule =
    self.clan.modules."@clanwright/fwknop-ssh-breakglass"
      or (throw "@clanwright/fwknop-ssh-breakglass is not registered");
  evaluatedService =
    (inputs.clan-core.lib.evalService {
      modules = [ registeredModule ];
      prefix = [ ];
    }).config;
  service = import ../clanServices/fwknop-ssh-breakglass/default.nix { inherit self; };
  role = service.roles.breakglass;
  defaults = (lib.evalModules { modules = [ role.interface ]; }).config;
  moduleFor =
    nftables:
    (role.perInstance { settings = defaults; }).nixosModule {
      config = {
        networking.nftables.enable = nftables;
        sops.secrets.${defaults.keySecretName}.path = "/run/secrets/${defaults.keySecretName}";
        sops.secrets.${defaults.hmacSecretName}.path = "/run/secrets/${defaults.hmacSecretName}";
      };
      inherit lib pkgs;
    };
  enabled = moduleFor false;
  nftables = moduleFor true;
  fwknopUnit = enabled.systemd.services.fwknop-ssh-breakglass;
  sshdUnit = enabled.systemd.services.fwknop-ssh-breakglass-sshd;
  fwknopPackage = self.packages.${system}.fwknop;
  renderConfig = builtins.head fwknopUnit.serviceConfig.ExecStartPre;
  sshdConfigMatch = builtins.match ".* -f (.*)" sshdUnit.serviceConfig.ExecStartPre;
  sshdConfig = builtins.appendContext (builtins.head sshdConfigMatch) (
    builtins.getContext sshdUnit.serviceConfig.ExecStartPre
  );
  keySecret = enabled.sops.secrets.${defaults.keySecretName};
  hmacSecret = enabled.sops.secrets.${defaults.hmacSecretName};
  secretMetadataMatches =
    secret:
    secret == {
      owner = "root";
      group = "root";
      mode = "0400";
      restartUnits = [ "fwknop-ssh-breakglass.service" ];
    };
  contract =
    builtins.deepSeq evaluatedService.result.api.schema true
    && service.manifest.name == "@clanwright/fwknop-ssh-breakglass"
    && builtins.attrNames service.roles == [ "breakglass" ]
    && defaults.sshPort == 47291
    && defaults.spaUdpPort == 62201
    && defaults.accessTimeout == 300
    && defaults.wanListenIPv4 == "0.0.0.0"
    && defaults.keySecretName == "fwknop-access-key"
    && defaults.hmacSecretName == "fwknop-hmac-key"
    && secretMetadataMatches keySecret
    && secretMetadataMatches hmacSecret
    && builtins.length enabled.assertions == 1
    && (builtins.head enabled.assertions).assertion
    && !(builtins.head nftables.assertions).assertion
    &&
      (builtins.head nftables.assertions).message
      == "@clanwright/fwknop-ssh-breakglass requires the current iptables firewall backend; nftables is enabled."
    &&
      builtins.attrNames enabled.systemd.services == [
        "fwknop-ssh-breakglass"
        "fwknop-ssh-breakglass-sshd"
      ]
    && enabled.services.openssh.generateHostKeys
    && enabled.users.users.sshd.isSystemUser
    && enabled.users.users.sshd.group == "sshd"
    && enabled.users.groups ? sshd
    && enabled.security.pam.services.sshd.startSession
    && enabled.security.pam.services.sshd.showMotd
    && !enabled.security.pam.services.sshd.unixAuth
    && sshdUnit.wantedBy == [ "multi-user.target" ]
    &&
      sshdUnit.after == [
        "network.target"
        "sshd-keygen.service"
      ]
    && sshdUnit.wants == [ "sshd-keygen.service" ]
    && sshdUnit.serviceConfig.RuntimeDirectory == "fwknop-ssh-breakglass-sshd"
    && sshdUnit.serviceConfig.RuntimeDirectoryMode == "0700"
    && sshdUnit.serviceConfig.Restart == "on-failure"
    && sshdUnit.serviceConfig.RestartSec == "10s"
    && lib.hasPrefix "${pkgs.openssh}/bin/sshd -t -f " sshdUnit.serviceConfig.ExecStartPre
    && lib.hasPrefix "${pkgs.openssh}/bin/sshd -D -e -f " sshdUnit.serviceConfig.ExecStart
    && fwknopUnit.wantedBy == [ "multi-user.target" ]
    &&
      fwknopUnit.after == [
        "firewall.service"
        "network.target"
      ]
    && fwknopUnit.wants == [ "firewall.service" ]
    &&
      fwknopUnit.path == [
        pkgs.coreutils
        fwknopPackage
        pkgs.iptables
      ]
    &&
      builtins.elemAt fwknopUnit.serviceConfig.ExecStartPre 1
      == "${fwknopPackage}/bin/fwknopd -U -c /run/fwknop-ssh-breakglass/fwknopd.conf -a /run/fwknop-ssh-breakglass/access.conf -d /run/fwknop-ssh-breakglass/digest.cache --exit-parse-config"
    &&
      fwknopUnit.serviceConfig.ExecStart
      == "${fwknopPackage}/bin/fwknopd -f -U -c /run/fwknop-ssh-breakglass/fwknopd.conf -a /run/fwknop-ssh-breakglass/access.conf -d /run/fwknop-ssh-breakglass/digest.cache"
    && fwknopUnit.serviceConfig.ExecReload == "${pkgs.coreutils}/bin/kill -HUP $MAINPID"
    && fwknopUnit.serviceConfig.RuntimeDirectory == "fwknop-ssh-breakglass"
    && fwknopUnit.serviceConfig.RuntimeDirectoryMode == "0700"
    && fwknopUnit.serviceConfig.Restart == "on-failure"
    && fwknopUnit.serviceConfig.RestartSec == "10s"
    && fwknopUnit.serviceConfig.CapabilityBoundingSet == [ "CAP_NET_ADMIN" ]
    && fwknopUnit.serviceConfig.PrivateTmp
    && fwknopUnit.serviceConfig.ProtectHome;
in
if contract then
  pkgs.runCommand "fwknop-ssh-breakglass-contract" { } ''
    grep -qF 'ListenAddress 0.0.0.0' ${sshdConfig}
    grep -qF 'Port 47291' ${sshdConfig}
    grep -qF 'PasswordAuthentication no' ${sshdConfig}
    grep -qF 'KbdInteractiveAuthentication no' ${sshdConfig}
    grep -qF 'PermitRootLogin prohibit-password' ${sshdConfig}
    grep -qF '/run/secrets/fwknop-access-key' ${renderConfig}
    grep -qF '/run/secrets/fwknop-hmac-key' ${renderConfig}
    grep -qF 'UDPSERV_PORT 62201;' ${renderConfig}
    grep -qF 'OPEN_PORTS tcp/47291' ${renderConfig}
    grep -qF 'FW_ACCESS_TIMEOUT 300' ${renderConfig}
    grep -qF 'chmod 0600' ${renderConfig}
    touch "$out"
  ''
else
  throw "fwknop SSH break-glass contract changed"
