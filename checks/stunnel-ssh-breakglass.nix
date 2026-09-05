{
  inputs,
  lib,
  pkgs,
  self,
  system,
}:
let
  serviceName = "stunnel-ssh-breakglass";
  sshdServiceName = "${serviceName}-sshd";
  hostKeyServiceName = "${serviceName}-hostkey";

  registeredModule =
    self.clan.modules."@clanwright/stunnel-ssh-breakglass"
      or (throw "@clanwright/stunnel-ssh-breakglass is not registered");
  evaluatedService =
    (inputs.clan-core.lib.evalService {
      modules = [ registeredModule ];
      prefix = [ ];
    }).config;

  service = import ../clanServices/stunnel-ssh-breakglass/default.nix { inherit self; };
  role = service.roles.breakglass;
  defaults = (lib.evalModules { modules = [ role.interface ]; }).config;

  secretType = lib.types.submodule (
    { ... }: {
      options = {
        path = lib.mkOption { type = lib.types.str; };
        owner = lib.mkOption { type = lib.types.str; };
        group = lib.mkOption { type = lib.types.str; };
        mode = lib.mkOption { type = lib.types.str; };
        restartUnits = lib.mkOption { type = lib.types.listOf lib.types.str; };
      };
    }
  );

  moduleFor = settings: (role.perInstance { inherit settings; }).nixosModule;
  sopsStub =
    settings:
    { lib, ... }:
    {
      options.sops.secrets = lib.mkOption {
        type = lib.types.attrsOf secretType;
        default = { };
      };

      config.sops.secrets."${settings.pskSecretName}".path = "/run/secrets/${settings.pskSecretName}";
      config.sops.secrets."${settings.authorizedKeysSecretName}".path =
        "/run/secrets/${settings.authorizedKeysSecretName}";
    };
  nixosFor =
    settings:
    lib.nixosSystem {
      inherit system;
      modules = [
        {
          system.stateVersion = "25.11";
          networking.hostName = "access-contract";
          boot.isContainer = true;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
        }
        (sopsStub settings)
        (moduleFor settings)
      ];
    };

  evaluatedNixos = nixosFor defaults;
  config = evaluatedNixos.config;
  stunnelUnit = config.systemd.services.${serviceName};
  sshdUnit = config.systemd.services.${sshdServiceName};
  hostKeyUnit = config.systemd.services.${hostKeyServiceName};
  accessStunnel = self.packages.${system}.stunnel;
  accessOpenSSH = self.packages.${system}.openssh;
  pskSecret = config.sops.secrets.${defaults.pskSecretName};
  authorizedKeysSecret = config.sops.secrets.${defaults.authorizedKeysSecretName};
  sshdConfigMatch = builtins.match ".* -f (.*)" sshdUnit.serviceConfig.ExecStart;
  sshdConfig = builtins.appendContext (builtins.head sshdConfigMatch) (
    builtins.getContext sshdUnit.serviceConfig.ExecStart
  );
  sshdConfigText = builtins.readFile sshdConfig;
  stunnelConfigRenderer = builtins.head (lib.toList stunnelUnit.serviceConfig.ExecStartPre);
  stunnelConfigRendererText = builtins.readFile stunnelConfigRenderer;
  authorizedKeysRenderer = builtins.head sshdUnit.serviceConfig.ExecStartPre;
  authorizedKeysRendererText = builtins.readFile authorizedKeysRenderer;
  hostKeyGenerator = hostKeyUnit.serviceConfig.ExecStart;
  hostKeyGeneratorText = builtins.readFile hostKeyGenerator;

  optionNames = builtins.attrNames (
    builtins.removeAttrs ((lib.evalModules { modules = [ role.interface ]; }).options) [ "_module" ]
  );
  rootOnly = secret: secret.owner == "root" && secret.group == "root" && secret.mode == "0400";
  hasRecoverySudoRule = builtins.any (
    rule:
    rule.users == [ defaults.recoveryUser ]
    && builtins.any (
      command: command.command == "ALL" && builtins.elem "NOPASSWD" command.options
    ) rule.commands
  ) config.security.sudo.extraRules;
  interfaceRejects =
    override:
    !(builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            role.interface
            { config = override; }
          ];
        }).config
        true
    )).success;
  assertionMessages = [
    "@clanwright/stunnel-ssh-breakglass requires distinct tlsPort and sshPort values."
    "@clanwright/stunnel-ssh-breakglass requires distinct PSK and authorized-key secret names."
    "@clanwright/stunnel-ssh-breakglass recoveryUser must be non-root."
  ];
  evaluatedAssertionValues =
    settings:
    builtins.tryEval (
      let
        assertions = (nixosFor settings).config.assertions;
      in
      builtins.deepSeq (map (assertion: assertion.assertion) assertions) (
        map (assertion: assertion.assertion) assertions
      )
    );
  failedAssertionMessages =
    settings:
    builtins.tryEval (
      let
        failed = builtins.filter (assertion: !assertion.assertion) (nixosFor settings).config.assertions;
      in
      builtins.deepSeq (map (assertion: assertion.message) failed) (
        map (assertion: assertion.message) failed
      )
    );
  assertionRejects =
    settings:
    let
      failed = failedAssertionMessages settings;
    in
    !failed.success || builtins.any (message: builtins.elem message assertionMessages) failed.value;
  baselineAssertions = evaluatedAssertionValues defaults;

  contract =
    builtins.deepSeq evaluatedService.result.api.schema true
    && service.manifest.name == "@clanwright/stunnel-ssh-breakglass"
    && builtins.attrNames service.roles == [ "breakglass" ]
    &&
      optionNames == [
        "authorizedKeysSecretName"
        "listenAddress"
        "pskSecretName"
        "recoveryUser"
        "sshPort"
        "tlsPort"
      ]
    && defaults.tlsPort == 47291
    && defaults.sshPort == 47292
    && defaults.listenAddress == "0.0.0.0"
    && defaults.recoveryUser == "access-recovery"
    && defaults.pskSecretName == "stunnel-ssh-psk"
    && defaults.authorizedKeysSecretName == "recovery-ssh-authorized-keys"
    && interfaceRejects { listenAddress = "0.0.0.0\nPSKsecrets = /unsafe"; }
    && interfaceRejects { recoveryUser = "access-recovery\nAllowUsers root"; }
    && interfaceRejects { pskSecretName = "psk/unsafe"; }
    && baselineAssertions.success
    && builtins.all (assertion: assertion) baselineAssertions.value
    && assertionRejects (defaults // { tlsPort = defaults.sshPort; })
    && assertionRejects (defaults // { pskSecretName = defaults.authorizedKeysSecretName; })
    && assertionRejects (defaults // { recoveryUser = "root"; })
    &&
      builtins.attrNames config.sops.secrets == [
        "recovery-ssh-authorized-keys"
        "stunnel-ssh-psk"
      ]
    && rootOnly pskSecret
    && rootOnly authorizedKeysSecret
    && pskSecret.restartUnits == [ "${serviceName}.service" ]
    && authorizedKeysSecret.restartUnits == [ "${sshdServiceName}.service" ]
    && config.users.groups ? sshd
    && config.users.groups ? access-recovery
    && config.users.users.sshd.isSystemUser
    && config.users.users.sshd.group == "sshd"
    && config.users.users.access-recovery.isNormalUser
    && config.users.users.access-recovery.createHome
    && config.users.users.access-recovery.group == "access-recovery"
    && config.users.users.access-recovery.home == "/var/lib/stunnel-ssh-breakglass-recovery"
    && hasRecoverySudoRule
    && config.security.pam.services.${sshdServiceName}.startSession
    && !config.security.pam.services.${sshdServiceName}.showMotd
    && !config.security.pam.services.${sshdServiceName}.unixAuth
    && !config.services.openssh.enable
    && !config.services.tailscale.enable
    && !(builtins.elem defaults.tlsPort config.networking.firewall.allowedTCPPorts)
    && !(builtins.elem defaults.sshPort config.networking.firewall.allowedTCPPorts)
    && stunnelUnit.wantedBy == [ "multi-user.target" ]
    &&
      stunnelUnit.after == [
        "network.target"
        "sops-install-secrets.service"
        "${sshdServiceName}.service"
      ]
    && stunnelUnit.requires == [ "${sshdServiceName}.service" ]
    && stunnelUnit.serviceConfig.Type == "simple"
    &&
      stunnelUnit.serviceConfig.ExecStart
      == "${accessStunnel}/bin/stunnel /run/${serviceName}/stunnel.conf"
    && stunnelUnit.serviceConfig.RuntimeDirectory == serviceName
    && stunnelUnit.serviceConfig.RuntimeDirectoryMode == "0700"
    && stunnelUnit.serviceConfig.DynamicUser
    &&
      stunnelUnit.serviceConfig.LoadCredential == [
        "psk:/run/secrets/${defaults.pskSecretName}"
      ]
    && stunnelUnit.serviceConfig.Restart == "on-failure"
    && stunnelUnit.serviceConfig.RestartSec == "5s"
    && stunnelUnit.serviceConfig.NoNewPrivileges
    && stunnelUnit.serviceConfig.PrivateTmp
    && stunnelUnit.serviceConfig.PrivateDevices
    && stunnelUnit.serviceConfig.ProtectSystem == "strict"
    && stunnelUnit.serviceConfig.ProtectHome
    &&
      stunnelUnit.serviceConfig.RestrictAddressFamilies == [
        "AF_INET"
        "AF_UNIX"
      ]
    && stunnelUnit.serviceConfig.MemoryDenyWriteExecute
    && stunnelUnit.serviceConfig.LockPersonality
    && stunnelUnit.serviceConfig.RestrictNamespaces
    && stunnelUnit.unitConfig.StartLimitIntervalSec == "60s"
    && stunnelUnit.unitConfig.StartLimitBurst == 5
    && sshdUnit.wantedBy == [ "multi-user.target" ]
    &&
      sshdUnit.after == [
        "network.target"
        "sops-install-secrets.service"
        "${hostKeyServiceName}.service"
      ]
    && sshdUnit.requires == [ "${hostKeyServiceName}.service" ]
    && !sshdUnit.stopIfChanged
    && sshdUnit.serviceConfig.Type == "simple"
    && sshdUnit.serviceConfig.ExecStart == "${accessOpenSSH}/bin/sshd -D -e -f ${sshdConfig}"
    && sshdUnit.serviceConfig.RuntimeDirectory == sshdServiceName
    && sshdUnit.serviceConfig.RuntimeDirectoryMode == "0750"
    &&
      sshdUnit.serviceConfig.LoadCredential == [
        "authorized-keys:/run/secrets/${defaults.authorizedKeysSecretName}"
      ]
    && sshdUnit.serviceConfig.KillMode == "process"
    && sshdUnit.serviceConfig.Restart == "on-failure"
    && sshdUnit.serviceConfig.RestartSec == "5s"
    && sshdUnit.serviceConfig.PrivateTmp
    && !(sshdUnit.serviceConfig ? ProtectSystem)
    && !(sshdUnit.serviceConfig ? NoNewPrivileges)
    && sshdUnit.unitConfig.StartLimitIntervalSec == "60s"
    && sshdUnit.unitConfig.StartLimitBurst == 5
    && hostKeyUnit.before == [ "${sshdServiceName}.service" ]
    && hostKeyUnit.serviceConfig.Type == "oneshot"
    && hostKeyUnit.serviceConfig.StateDirectory == serviceName
    && hostKeyUnit.serviceConfig.StateDirectoryMode == "0700"
    && hostKeyUnit.serviceConfig.RemainAfterExit
    && hostKeyUnit.serviceConfig.PrivateTmp
    && hostKeyUnit.serviceConfig.PrivateDevices
    && hostKeyUnit.serviceConfig.ProtectSystem == "strict"
    && hostKeyUnit.serviceConfig.ProtectHome
    && !lib.hasInfix "/run/secrets/" stunnelConfigRendererText
    && !lib.hasInfix "cert =" stunnelConfigRendererText
    && !lib.hasInfix "TLSv1.2" stunnelConfigRendererText
    && !lib.hasInfix "ciphers =" stunnelConfigRendererText
    && lib.hasInfix "[ssh]" stunnelConfigRendererText
    && lib.hasInfix "invalid stunnel PSK record" stunnelConfigRendererText
    && lib.hasInfix "[0-9a-f]{64}" stunnelConfigRendererText
    && lib.hasInfix "PSKsecrets = $CREDENTIALS_DIRECTORY/psk" stunnelConfigRendererText
    && lib.hasInfix "accept = 0.0.0.0:47291" stunnelConfigRendererText
    && lib.hasInfix "connect = 127.0.0.1:47292" stunnelConfigRendererText
    && lib.hasInfix "sslVersionMin = TLSv1.3" stunnelConfigRendererText
    && lib.hasInfix "sslVersionMax = TLSv1.3" stunnelConfigRendererText
    && lib.hasInfix "sessionResume = no" stunnelConfigRendererText
    && lib.hasInfix "sessionCacheSize = 100" stunnelConfigRendererText
    && lib.hasInfix "TIMEOUTbusy = 30" stunnelConfigRendererText
    && lib.hasInfix "TIMEOUTconnect = 10" stunnelConfigRendererText
    && lib.hasInfix "TIMEOUTidle = 900" stunnelConfigRendererText
    && lib.hasInfix "install -m 0440 -o root -g access-recovery" authorizedKeysRendererText
    && lib.hasInfix "authorized-keys" authorizedKeysRendererText
    && lib.hasInfix "invalid recovery authorized-key file" authorizedKeysRendererText
    && lib.hasInfix "ssh-keygen -lf \"$CREDENTIALS_DIRECTORY/authorized-keys\" >/dev/null 2>&1" authorizedKeysRendererText
    && lib.hasInfix "ssh-keygen -q -t ed25519" hostKeyGeneratorText;
in
if contract then
  pkgs.runCommand "stunnel-ssh-breakglass-contract" { } ''
    ${accessOpenSSH}/bin/sshd -G -T -f ${sshdConfig} > "$TMPDIR/effective-sshd-config"

    require_setting() {
      if ! grep -qxiF "$1" "$TMPDIR/effective-sshd-config"; then
        echo "missing effective sshd setting: $1" >&2
        ${pkgs.coreutils}/bin/cat "$TMPDIR/effective-sshd-config" >&2
        exit 1
      fi
    }

    require_setting 'listenaddress 127.0.0.1:47292'
    require_setting 'port 47292'
    require_setting 'passwordauthentication no'
    require_setting 'kbdinteractiveauthentication no'
    require_setting 'pubkeyauthentication yes'
    require_setting 'authenticationmethods publickey'
    require_setting 'permitrootlogin no'
    require_setting 'disableforwarding yes'
    require_setting 'allowtcpforwarding no'
    require_setting 'allowagentforwarding no'
    require_setting 'allowstreamlocalforwarding no'
    require_setting 'x11forwarding no'
    require_setting 'persourcepenalties no'
    require_setting 'permittty yes'
    require_setting 'loglevel VERBOSE'
    require_setting 'pamservicename stunnel-ssh-breakglass-sshd'
    require_setting 'authorizedkeysfile /run/stunnel-ssh-breakglass-sshd/authorized_keys'
    require_setting 'subsystem sftp ${accessOpenSSH}/libexec/sftp-server'
    touch "$out"
  ''
else
  throw "stunnel SSH break-glass contract changed"
