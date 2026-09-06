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
  customRecoveryUser = "custom-recovery";
  customRecoveryNixos = nixosFor (defaults // { recoveryUser = customRecoveryUser; });
  config = evaluatedNixos.config;
  stunnelUnit = config.systemd.services.${serviceName};
  sshdUnit = config.systemd.services.${sshdServiceName};
  customRecoverySshdUnit = customRecoveryNixos.config.systemd.services.${sshdServiceName};
  hostKeyUnit = config.systemd.services.${hostKeyServiceName};
  accessStunnel = self.packages.${system}.stunnel;
  accessOpenSSH = self.packages.${system}.openssh;
  pskSecret = config.sops.secrets.${defaults.pskSecretName};
  authorizedKeysSecret = config.sops.secrets.${defaults.authorizedKeysSecretName};
  sshdExecStart = sshdUnit.serviceConfig.ExecStart;
  stunnelConfigRenderer = builtins.head (lib.toList stunnelUnit.serviceConfig.ExecStartPre);
  authorizedKeysRenderer = builtins.head sshdUnit.serviceConfig.ExecStartPre;
  hostKeyGenerator = hostKeyUnit.serviceConfig.ExecStart;

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
    && lib.hasPrefix "${accessOpenSSH}/bin/sshd -D -e -f /nix/store/" sshdExecStart
    && lib.hasPrefix "${accessOpenSSH}/bin/sshd -t -f /nix/store/" (
      builtins.elemAt sshdUnit.serviceConfig.ExecStartPre 1
    )
    && sshdUnit.serviceConfig.RuntimeDirectory == sshdServiceName
    && sshdUnit.serviceConfig.RuntimeDirectoryMode == "0750"
    && sshdUnit.serviceConfig.Group == defaults.recoveryUser
    && !(sshdUnit.serviceConfig ? User)
    && customRecoverySshdUnit.serviceConfig.RuntimeDirectory == sshdServiceName
    && customRecoverySshdUnit.serviceConfig.RuntimeDirectoryMode == "0750"
    && customRecoverySshdUnit.serviceConfig.Group == customRecoveryUser
    && !(customRecoverySshdUnit.serviceConfig ? User)
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
    && builtins.length (lib.toList stunnelUnit.serviceConfig.ExecStartPre) == 1;
in
if contract then
  pkgs.runCommand "stunnel-ssh-breakglass-contract" { } ''
    require_fragment() {
      label="$1"
      path="$2"
      fragment="$3"

      if ! ${pkgs.gnugrep}/bin/grep -qF -- "$fragment" "$path"; then
        echo "missing $label fragment: $fragment" >&2
        ${pkgs.coreutils}/bin/cat "$path" >&2
        exit 1
      fi
    }

    reject_fragment() {
      label="$1"
      path="$2"
      fragment="$3"

      if ${pkgs.gnugrep}/bin/grep -qF -- "$fragment" "$path"; then
        echo "unexpected $label fragment: $fragment" >&2
        ${pkgs.coreutils}/bin/cat "$path" >&2
        exit 1
      fi
    }

    stunnel_renderer=${lib.escapeShellArg stunnelConfigRenderer}
    authorized_keys_renderer=${lib.escapeShellArg authorizedKeysRenderer}
    host_key_generator=${lib.escapeShellArg hostKeyGenerator}
    sshd_start=${lib.escapeShellArg sshdExecStart}
    sshd_config="''${sshd_start#* -f }"

    if [ "$sshd_config" = "$sshd_start" ] || [ ! -r "$sshd_config" ]; then
      echo "could not derive readable sshd config from generated ExecStart" >&2
      echo "$sshd_start" >&2
      exit 1
    fi

    reject_fragment stunnel-renderer "$stunnel_renderer" '/run/secrets/'
    reject_fragment stunnel-renderer "$stunnel_renderer" 'cert ='
    reject_fragment stunnel-renderer "$stunnel_renderer" 'TLSv1.2'
    reject_fragment stunnel-renderer "$stunnel_renderer" 'ciphers ='
    require_fragment stunnel-renderer "$stunnel_renderer" '[ssh]'
    require_fragment stunnel-renderer "$stunnel_renderer" 'invalid stunnel PSK record'
    require_fragment stunnel-renderer "$stunnel_renderer" '[0-9a-f]{64}'
    require_fragment stunnel-renderer "$stunnel_renderer" 'PSKsecrets = $CREDENTIALS_DIRECTORY/psk'
    require_fragment stunnel-renderer "$stunnel_renderer" 'accept = 0.0.0.0:47291'
    require_fragment stunnel-renderer "$stunnel_renderer" 'connect = 127.0.0.1:47292'
    require_fragment stunnel-renderer "$stunnel_renderer" 'sslVersionMin = TLSv1.3'
    require_fragment stunnel-renderer "$stunnel_renderer" 'sslVersionMax = TLSv1.3'
    require_fragment stunnel-renderer "$stunnel_renderer" 'sessionResume = no'
    require_fragment stunnel-renderer "$stunnel_renderer" 'sessionCacheSize = 100'
    require_fragment stunnel-renderer "$stunnel_renderer" 'TIMEOUTbusy = 30'
    require_fragment stunnel-renderer "$stunnel_renderer" 'TIMEOUTconnect = 10'
    require_fragment stunnel-renderer "$stunnel_renderer" 'TIMEOUTidle = 900'
    require_fragment authorized-keys-renderer "$authorized_keys_renderer" 'install -m 0440 -o root -g access-recovery'
    require_fragment authorized-keys-renderer "$authorized_keys_renderer" 'authorized-keys'
    require_fragment authorized-keys-renderer "$authorized_keys_renderer" 'invalid recovery authorized-key file'
    require_fragment authorized-keys-renderer "$authorized_keys_renderer" 'ssh-keygen -lf "$CREDENTIALS_DIRECTORY/authorized-keys" >/dev/null 2>&1'
    require_fragment host-key-generator "$host_key_generator" 'ssh-keygen -q -t ed25519'

    ${accessOpenSSH}/bin/sshd -G -T -f "$sshd_config" > "$TMPDIR/effective-sshd-config"

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
