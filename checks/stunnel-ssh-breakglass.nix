{
  inputs,
  lib,
  pkgs,
  root,
  self,
  system,
}:
let
  moduleId = "@clanwright/stunnel-ssh-breakglass";
  serviceName = "stunnel-ssh-breakglass";
  sshdServiceName = "${serviceName}-sshd";
  hostKeyServiceName = "${serviceName}-hostkey";
  registeredModule = self.clan.modules.${moduleId} or (throw "${moduleId} is not registered");
  evaluatedService =
    (inputs.clan-core.lib.evalService {
      modules = [ registeredModule ];
      prefix = [ ];
    }).config;
  role = evaluatedService.roles.breakglass;
  defaults = (lib.evalModules { modules = [ role.interface ]; }).config;
  consumerFor = import ./lib/consumer.nix { inherit inputs root self; };
  instance = name: machineName: settings: {
    ${name} = {
      module = {
        input = "access";
        name = moduleId;
      };
      roles.breakglass.machines.${machineName} = { inherit settings; };
    };
  };
  scenario =
    settings:
    (consumerFor { instances = instance "stunnel-ssh-breakglass" "access-node" settings; }).machine;
  config = scenario { };
  withOrdinarySsh =
    (consumerFor {
      instances = instance "stunnel-ssh-breakglass" "access-node" { };
      machineModules = [
        {
          services.openssh = {
            enable = true;
            startWhenNeeded = false;
            ports = [ 2222 ];
            authorizedKeysFiles = [ "/etc/ssh/ordinary-authorized-keys/%u" ];
            settings.PasswordAuthentication = true;
          };
        }
      ];
    }).machine;
  ordinarySshdUnit = withOrdinarySsh.systemd.services.sshd;
  coexistingRecoveryUnit = withOrdinarySsh.systemd.services.${sshdServiceName};
  custom = scenario {
    tlsPort = 48331;
    sshPort = 48332;
    listenAddress = "192.0.2.10";
    pskSecretName = "custom-psk";
    authorizedKeysSecretName = "custom-authorized-keys";
  };
  customStunnelUnit = custom.systemd.services.${serviceName};
  customSshdUnit = custom.systemd.services.${sshdServiceName};
  stunnelUnit = config.systemd.services.${serviceName};
  sshdUnit = config.systemd.services.${sshdServiceName};
  hostKeyUnit = config.systemd.services.${hostKeyServiceName};
  accessStunnel = self.packages.${system}.stunnel;
  accessOpenSSH = self.packages.${system}.openssh;
  pskSecret = config.sops.secrets.${defaults.pskSecretName};
  authorizedKeysSecret = config.sops.secrets.${defaults.authorizedKeysSecretName};
  sshdExecStart = sshdUnit.serviceConfig.ExecStart;
  sshdConfigPrefix = "${accessOpenSSH}/bin/sshd -D -e -f ";
  sshdConfig = lib.removePrefix sshdConfigPrefix sshdExecStart;
  customSshdConfig = lib.removePrefix sshdConfigPrefix customSshdUnit.serviceConfig.ExecStart;
  nonEmptyCommands =
    value:
    map toString (
      builtins.filter (command: command != null && toString command != "") (lib.toList value)
    );
  stunnelExecStartPre = nonEmptyCommands stunnelUnit.serviceConfig.ExecStartPre;
  sshdExecStartPre = nonEmptyCommands sshdUnit.serviceConfig.ExecStartPre;
  pskValidator = builtins.head stunnelExecStartPre;
  stunnelConfig = lib.removePrefix "${accessStunnel}/bin/stunnel " stunnelUnit.serviceConfig.ExecStart;
  customStunnelConfig = lib.removePrefix "${accessStunnel}/bin/stunnel " customStunnelUnit.serviceConfig.ExecStart;
  authorizedKeysRenderer = builtins.head sshdExecStartPre;
  hostKeyGenerator = hostKeyUnit.serviceConfig.ExecStart;
  optionNames = builtins.attrNames (
    builtins.removeAttrs (lib.evalModules { modules = [ role.interface ]; }).options [ "_module" ]
  );
  rootOnly = secret: secret.owner == "root" && secret.group == "root" && secret.mode == "0400";
  hasRecoverySudoRule = builtins.any (
    rule:
    rule.users == [ "access-recovery" ]
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
  failedAssertionMessages =
    consumer:
    map (entry: entry.message) (builtins.filter (entry: !entry.assertion) consumer.machine.assertions);
  assertionRejects =
    settings: expectedMessage:
    builtins.elem expectedMessage (
      failedAssertionMessages (consumerFor {
        forceMachine = false;
        instances = instance "stunnel-ssh-breakglass" "access-node" settings;
      })
    );
  sameMachineInstances =
    (instance "breakglass-primary" "access-node" { })
    // (instance "breakglass-duplicate" "access-node" { });
  singletonMessage = "${moduleId} allows at most one instance on machine 'access-node'.";
  sameMachineConsumer = consumerFor {
    forceMachine = false;
    instances = sameMachineInstances;
  };
  collisionConsumer =
    machineModule:
    consumerFor {
      forceMachine = false;
      instances = instance "stunnel-ssh-breakglass" "access-node" { };
      machineModules = [ machineModule ];
    };
  distinctMachineInstances =
    (instance "breakglass-first" "access-node" { })
    // (instance "breakglass-second" "access-node-2" { });
  distinctFirst = consumerFor {
    instances = distinctMachineInstances;
    machineNames = [
      "access-node"
      "access-node-2"
    ];
  };
  distinctSecond = consumerFor {
    instances = distinctMachineInstances;
    machineName = "access-node-2";
    machineNames = [
      "access-node"
      "access-node-2"
    ];
  };
  check = import ./lib/contract.nix { inherit lib; };
  contract = check "stunnel SSH breakglass contract" {
    assertion-distinct-ports = assertionRejects (
      defaults // { tlsPort = defaults.sshPort; }
    ) "${moduleId} requires distinct tlsPort and sshPort values.";
    assertion-distinct-secrets = assertionRejects (
      defaults // { pskSecretName = defaults.authorizedKeysSecretName; }
    ) "${moduleId} requires distinct PSK and authorized-key secret names.";
    foreign-recovery-account-rejected =
      builtins.elem
        "${moduleId} reserves the access-recovery account; consumer user definitions must not collide."
        (
          failedAssertionMessages (collisionConsumer {
            users.users.access-recovery.description = "consumer account";
          })
        );
    foreign-recovery-account-alias-rejected =
      builtins.elem
        "${moduleId} reserves the access-recovery account and group names; consumer aliases must not collide."
        (
          failedAssertionMessages (collisionConsumer {
            users.users.z-alias = {
              isNormalUser = true;
              name = "access-recovery";
              group = "users";
            };
          })
        );
    foreign-recovery-group-alias-rejected =
      builtins.elem
        "${moduleId} reserves the access-recovery account and group names; consumer aliases must not collide."
        (
          failedAssertionMessages (collisionConsumer {
            users.groups.z-alias.name = "access-recovery";
          })
        );
    foreign-recovery-group-rejected =
      builtins.elem
        "${moduleId} reserves the access-recovery group; consumer group definitions must not collide."
        (
          failedAssertionMessages (collisionConsumer {
            users.groups.access-recovery.gid = 55555;
          })
        );
    foreign-recovery-membership-rejected =
      builtins.all
        (
          user:
          builtins.elem "${moduleId} reserves access-recovery group membership for the recovery account." (
            failedAssertionMessages (collisionConsumer {
              users.users.foreign-user = user;
            })
          )
        )
        [
          {
            isNormalUser = true;
            group = "access-recovery";
          }
          {
            isNormalUser = true;
            extraGroups = [ "access-recovery" ];
          }
        ];
    authoritative-binaries =
      stunnelUnit.serviceConfig.ExecStart == "${accessStunnel}/bin/stunnel ${stunnelConfig}"
      && lib.hasPrefix "/nix/store/" stunnelConfig
      && lib.hasPrefix "${accessOpenSSH}/bin/sshd -D -e -f /nix/store/" sshdExecStart
      && builtins.any (lib.hasPrefix "${accessOpenSSH}/bin/sshd -t -f /nix/store/") sshdExecStartPre;
    defaults =
      defaults.tlsPort == 47291
      && defaults.sshPort == 47292
      && defaults.listenAddress == "0.0.0.0"
      && defaults.pskSecretName == "stunnel-ssh-psk"
      && defaults.authorizedKeysSecretName == "recovery-ssh-authorized-keys";
    firewall-and-service-independence =
      !config.services.openssh.enable
      && !config.services.tailscale.enable
      && !(builtins.elem defaults.tlsPort config.networking.firewall.allowedTCPPorts)
      && !(builtins.elem defaults.sshPort config.networking.firewall.allowedTCPPorts);
    ordinary-ssh-coexistence =
      withOrdinarySsh.services.openssh.enable
      && !withOrdinarySsh.services.openssh.startWhenNeeded
      && withOrdinarySsh.services.openssh.ports == [ 2222 ]
      && withOrdinarySsh.services.openssh.settings.PasswordAuthentication
      && builtins.elem "/etc/ssh/ordinary-authorized-keys/%u" withOrdinarySsh.services.openssh.authorizedKeysFiles
      && !(builtins.elem "/run/stunnel-ssh-breakglass-sshd/authorized_keys" withOrdinarySsh.services.openssh.authorizedKeysFiles)
      && builtins.all (
        key: key.path != "/var/lib/stunnel-ssh-breakglass/ssh_host_ed25519_key"
      ) withOrdinarySsh.services.openssh.hostKeys
      && ordinarySshdUnit.serviceConfig.ExecStart != coexistingRecoveryUnit.serviceConfig.ExecStart
      && (ordinarySshdUnit.serviceConfig.Group or "root") != "access-recovery"
      && coexistingRecoveryUnit.serviceConfig.Group == "access-recovery"
      && coexistingRecoveryUnit.serviceConfig.ExecStart == sshdUnit.serviceConfig.ExecStart
      && coexistingRecoveryUnit.serviceConfig.LoadCredential == sshdUnit.serviceConfig.LoadCredential
      &&
        withOrdinarySsh.systemd.services.${serviceName}.serviceConfig.ExecStart
        == stunnelUnit.serviceConfig.ExecStart
      &&
        withOrdinarySsh.systemd.services.${hostKeyServiceName}.serviceConfig.ExecStart
        == hostKeyUnit.serviceConfig.ExecStart
      && !(builtins.elem "sshd.service" (coexistingRecoveryUnit.after ++ coexistingRecoveryUnit.requires))
      && !(builtins.elem "${sshdServiceName}.service" (
        ordinarySshdUnit.after ++ ordinarySshdUnit.requires
      ));
    host-key-unit =
      hostKeyUnit.before == [ "${sshdServiceName}.service" ]
      && hostKeyUnit.serviceConfig.Type == "oneshot"
      && hostKeyUnit.serviceConfig.StateDirectory == serviceName
      && hostKeyUnit.serviceConfig.StateDirectoryMode == "0700"
      && hostKeyUnit.serviceConfig.RemainAfterExit
      && hostKeyUnit.serviceConfig.PrivateTmp
      && hostKeyUnit.serviceConfig.PrivateDevices
      && hostKeyUnit.serviceConfig.ProtectSystem == "strict"
      && hostKeyUnit.serviceConfig.ProtectHome;
    interface-schema =
      builtins.deepSeq evaluatedService.result.api.schema true
      &&
        optionNames == [
          "authorizedKeysSecretName"
          "listenAddress"
          "pskSecretName"
          "sshPort"
          "tlsPort"
        ];
    interface-types =
      interfaceRejects { listenAddress = "0.0.0.0\nPSKsecrets = /unsafe"; }
      && interfaceRejects { pskSecretName = "psk/unsafe"; };
    unknown-settings-rejected = builtins.all (name: interfaceRejects { ${name} = true; }) [
      "unknownSetting"
      "recoveryUser"
      "authKeyValue"
      "credential"
      "hmacSecretValue"
      "keySecretValue"
      "password"
      "secretValue"
      "token"
    ];
    manifest =
      evaluatedService.manifest.name == moduleId
      && builtins.attrNames evaluatedService.roles == [ "breakglass" ];
    recovery-account =
      config.users.groups ? sshd
      && config.users.groups ? access-recovery
      && config.users.users.sshd.isSystemUser
      && config.users.users.sshd.group == "sshd"
      && config.users.users.access-recovery.isNormalUser
      && config.users.users.access-recovery.createHome
      && config.users.users.access-recovery.group == "access-recovery"
      && config.users.users.access-recovery.home == "/var/lib/stunnel-ssh-breakglass-recovery"
      && hasRecoverySudoRule;
    retained-host-identity-state =
      config.clan.core.state.${serviceName}.folders == [ "/var/lib/stunnel-ssh-breakglass" ];
    secret-metadata =
      builtins.attrNames config.sops.secrets == [
        "recovery-ssh-authorized-keys"
        "stunnel-ssh-psk"
      ]
      && rootOnly pskSecret
      && rootOnly authorizedKeysSecret
      && pskSecret.restartUnits == [ "${serviceName}.service" ]
      && authorizedKeysSecret.restartUnits == [ "${sshdServiceName}.service" ];
    custom-secret-wiring =
      builtins.attrNames custom.sops.secrets == [
        "custom-authorized-keys"
        "custom-psk"
      ]
      && rootOnly custom.sops.secrets.custom-psk
      && rootOnly custom.sops.secrets.custom-authorized-keys
      && custom.sops.secrets.custom-psk.restartUnits == [ "${serviceName}.service" ]
      && custom.sops.secrets.custom-authorized-keys.restartUnits == [ "${sshdServiceName}.service" ]
      && customStunnelUnit.serviceConfig.LoadCredential == [ "psk:/run/secrets/custom-psk" ]
      &&
        customSshdUnit.serviceConfig.LoadCredential == [
          "authorized-keys:/run/secrets/custom-authorized-keys"
        ];
    singleton-distinct-machines-allowed = distinctFirst.evaluated && distinctSecond.evaluated;
    singleton-same-machine-rejected = builtins.elem singletonMessage (
      failedAssertionMessages sameMachineConsumer
    );
    sshd-account-context =
      sshdUnit.serviceConfig.RuntimeDirectory == sshdServiceName
      && sshdUnit.serviceConfig.RuntimeDirectoryMode == "0750"
      && sshdUnit.serviceConfig.Group == "access-recovery"
      && !(sshdUnit.serviceConfig ? User);
    sshd-lifecycle =
      sshdUnit.wantedBy == [ "multi-user.target" ]
      &&
        sshdUnit.after == [
          "network.target"
          "sops-install-secrets.service"
          "${hostKeyServiceName}.service"
        ]
      && sshdUnit.requires == [ "${hostKeyServiceName}.service" ]
      && !sshdUnit.stopIfChanged
      && sshdUnit.serviceConfig.Type == "simple"
      && sshdUnit.serviceConfig.KillMode == "process"
      && sshdUnit.serviceConfig.Restart == "on-failure"
      && sshdUnit.serviceConfig.RestartSec == "5s"
      && sshdUnit.serviceConfig.PrivateTmp
      && !(sshdUnit.serviceConfig ? ProtectSystem)
      && !(sshdUnit.serviceConfig ? NoNewPrivileges)
      && sshdUnit.unitConfig.StartLimitIntervalSec == "60s"
      && sshdUnit.unitConfig.StartLimitBurst == 5;
    sshd-pam =
      config.security.pam.services.${sshdServiceName}.startSession
      && !config.security.pam.services.${sshdServiceName}.showMotd
      && !config.security.pam.services.${sshdServiceName}.unixAuth;
    sshd-secret-loading =
      sshdUnit.serviceConfig.LoadCredential == [
        "authorized-keys:/run/secrets/${defaults.authorizedKeysSecretName}"
      ];
    stunnel-lifecycle =
      stunnelUnit.wantedBy == [ "multi-user.target" ]
      &&
        stunnelUnit.after == [
          "network.target"
          "sops-install-secrets.service"
          "${sshdServiceName}.service"
        ]
      && stunnelUnit.requires == [ "${sshdServiceName}.service" ]
      && stunnelUnit.serviceConfig.Type == "simple"
      && !(stunnelUnit.serviceConfig ? RuntimeDirectory)
      && stunnelUnit.serviceConfig.DynamicUser
      && stunnelUnit.serviceConfig.Restart == "on-failure"
      && stunnelUnit.serviceConfig.RestartSec == "5s"
      && stunnelUnit.unitConfig.StartLimitIntervalSec == "60s"
      && stunnelUnit.unitConfig.StartLimitBurst == 5;
    stunnel-sandbox =
      stunnelUnit.serviceConfig.NoNewPrivileges
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
      && stunnelUnit.serviceConfig.RestrictSUIDSGID
      && stunnelUnit.serviceConfig.ProtectKernelTunables
      && stunnelUnit.serviceConfig.ProtectKernelModules
      && stunnelUnit.serviceConfig.ProtectControlGroups
      && stunnelUnit.serviceConfig.ProtectClock
      && stunnelUnit.serviceConfig.MemoryMax == "128M"
      && stunnelUnit.serviceConfig.TasksMax == 32
      && stunnelUnit.serviceConfig.LimitNOFILE == 1024;
    stunnel-secret-loading =
      stunnelUnit.serviceConfig.LoadCredential == [
        "psk:/run/secrets/${defaults.pskSecretName}"
      ];
  };
in
assert contract;
pkgs.runCommand "stunnel-ssh-breakglass-contract" { } ''
  psk_validator=${lib.escapeShellArg pskValidator}
  stunnel_config=${lib.escapeShellArg stunnelConfig}
  authorized_keys_renderer=${lib.escapeShellArg authorizedKeysRenderer}
  host_key_generator=${lib.escapeShellArg hostKeyGenerator}

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

  for script in "$psk_validator" "$authorized_keys_renderer" "$host_key_generator"; do
    ${pkgs.bash}/bin/bash -n "$script"
  done

  if ${pkgs.coreutils}/bin/env -u CREDENTIALS_DIRECTORY "$psk_validator" >stunnel.stdout 2>stunnel.stderr; then
    echo "stunnel validator accepted a missing credential directory" >&2
    exit 1
  fi
  require_fragment stunnel-missing-credential stunnel.stderr \
    'systemd did not provide the stunnel PSK credential'

  if ${pkgs.coreutils}/bin/env -u CREDENTIALS_DIRECTORY "$authorized_keys_renderer" >authorized.stdout 2>authorized.stderr; then
    echo "authorized-keys renderer accepted a missing credential directory" >&2
    exit 1
  fi
  require_fragment authorized-keys-missing-credential authorized.stderr \
    'systemd did not provide recovery authorized keys'

  if CREDENTIALS_DIRECTORY="$TMPDIR/missing" "$psk_validator" >stunnel-missing.stdout 2>stunnel-missing.stderr; then
    echo "stunnel validator accepted a nonexistent PSK credential" >&2
    exit 1
  fi
  require_fragment stunnel-invalid-credential stunnel-missing.stderr 'invalid stunnel PSK record'

  if CREDENTIALS_DIRECTORY="$TMPDIR/missing" "$authorized_keys_renderer" >authorized-missing.stdout 2>authorized-missing.stderr; then
    echo "authorized-keys renderer accepted a nonexistent credential" >&2
    exit 1
  fi
  require_fragment authorized-keys-invalid-credential authorized-missing.stderr \
    'invalid recovery authorized-key file'

  require_fragment stunnel-psk-validation "$psk_validator" '[A-Za-z0-9._-]+:[0-9a-f]{64}'
  reject_fragment stunnel-policy "$stunnel_config" '/run/secrets/'
  reject_fragment stunnel-policy "$stunnel_config" 'cert ='
  reject_fragment stunnel-policy "$stunnel_config" 'TLSv1.2'
  reject_fragment stunnel-policy "$stunnel_config" 'ciphers ='
  require_fragment stunnel-policy "$stunnel_config" 'PSKsecrets=/run/credentials/stunnel-ssh-breakglass.service/psk'
  require_fragment stunnel-policy "$stunnel_config" 'accept=0.0.0.0:47291'
  require_fragment stunnel-policy "$stunnel_config" 'connect=127.0.0.1:47292'
  require_fragment stunnel-policy "$stunnel_config" 'sslVersionMin=TLSv1.3'
  require_fragment stunnel-policy "$stunnel_config" 'sslVersionMax=TLSv1.3'
  require_fragment stunnel-policy "$stunnel_config" 'sessionResume=no'
  require_fragment stunnel-policy "$stunnel_config" 'sessionCacheSize=100'
  require_fragment stunnel-policy "$stunnel_config" 'TIMEOUTbusy=30'
  require_fragment stunnel-policy "$stunnel_config" 'TIMEOUTconnect=10'
  require_fragment stunnel-policy "$stunnel_config" 'TIMEOUTidle=900'
  require_fragment custom-stunnel-policy ${lib.escapeShellArg customStunnelConfig} 'accept=192.0.2.10:48331'
  require_fragment custom-stunnel-policy ${lib.escapeShellArg customStunnelConfig} 'connect=127.0.0.1:48332'
  require_fragment custom-stunnel-policy ${lib.escapeShellArg customStunnelConfig} \
    'PSKsecrets=/run/credentials/stunnel-ssh-breakglass.service/psk'
  require_fragment authorized-keys-package "$authorized_keys_renderer" \
    '${accessOpenSSH}/bin/ssh-keygen -lf "$CREDENTIALS_DIRECTORY/authorized-keys"'
  require_fragment authorized-keys-permissions "$authorized_keys_renderer" \
    'install -d -m 0750 -o root -g access-recovery /run/stunnel-ssh-breakglass-sshd'
  require_fragment authorized-keys-permissions "$authorized_keys_renderer" \
    'install -m 0440 -o root -g access-recovery "$CREDENTIALS_DIRECTORY/authorized-keys" /run/stunnel-ssh-breakglass-sshd/authorized_keys'
  require_fragment host-key-package "$host_key_generator" '${accessOpenSSH}/bin/ssh-keygen -q -t ed25519'
  require_fragment host-key-validation "$host_key_generator" '${accessOpenSSH}/bin/ssh-keygen -lf /var/lib/stunnel-ssh-breakglass/ssh_host_ed25519_key'

  ${accessOpenSSH}/bin/sshd -G -T -f ${lib.escapeShellArg sshdConfig} > effective-sshd-config
  require_setting() {
    config_file="''${2:-effective-sshd-config}"
    if ! ${pkgs.gnugrep}/bin/grep -qxiF "$1" "$config_file"; then
      echo "missing effective sshd setting: $1" >&2
      ${pkgs.coreutils}/bin/cat "$config_file" >&2
      exit 1
    fi
  }
  require_setting 'listenaddress 127.0.0.1:47292'
  require_setting 'port 47292'
  require_setting 'allowusers access-recovery'
  require_setting 'usepam yes'
  require_setting 'strictmodes yes'
  require_setting 'hostkey /var/lib/stunnel-ssh-breakglass/ssh_host_ed25519_key'
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
  ${accessOpenSSH}/bin/sshd -G -T -f ${lib.escapeShellArg customSshdConfig} > effective-custom-sshd-config
  require_setting 'listenaddress 127.0.0.1:48332' effective-custom-sshd-config
  require_setting 'port 48332' effective-custom-sshd-config
  require_setting 'allowusers access-recovery' effective-custom-sshd-config
  require_setting 'usepam yes' effective-custom-sshd-config
  require_setting 'pamservicename stunnel-ssh-breakglass-sshd' effective-custom-sshd-config
  require_setting 'strictmodes yes' effective-custom-sshd-config
  require_setting 'hostkey /var/lib/stunnel-ssh-breakglass/ssh_host_ed25519_key' effective-custom-sshd-config
  touch "$out"
''
