{ self, settings }:
{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  rendered = import ./rendering.nix {
    inherit
      lib
      pkgs
      self
      settings
      ;
  };
  inherit (rendered.names)
    hostKey
    recoveryUser
    service
    sshd
    ;
  inherit (rendered.packages) openssh stunnel;
  inherit (rendered) paths;
  pskSecretPath = config.sops.secrets.${settings.pskSecretName}.path;
  authorizedKeysSecretPath = config.sops.secrets.${settings.authorizedKeysSecretName}.path;
  moduleFile = toString ./runtime.nix;
in
{
  _file = moduleFile;
  assertions = [
    {
      assertion = settings.tlsPort != settings.sshPort;
      message = "@clanwright/stunnel-ssh-breakglass requires distinct tlsPort and sshPort values.";
    }
    {
      assertion = settings.pskSecretName != settings.authorizedKeysSecretName;
      message = "@clanwright/stunnel-ssh-breakglass requires distinct PSK and authorized-key secret names.";
    }
    {
      assertion = builtins.all (
        definition: definition.file == moduleFile || !(builtins.hasAttr recoveryUser definition.value)
      ) options.users.users.definitionsWithLocations;
      message = "@clanwright/stunnel-ssh-breakglass reserves the access-recovery account; consumer user definitions must not collide.";
    }
    {
      assertion = builtins.all (
        definition: definition.file == moduleFile || !(builtins.hasAttr recoveryUser definition.value)
      ) options.users.groups.definitionsWithLocations;
      message = "@clanwright/stunnel-ssh-breakglass reserves the access-recovery group; consumer group definitions must not collide.";
    }
    {
      assertion =
        lib.all (user: user.name != recoveryUser) (
          builtins.attrValues (builtins.removeAttrs config.users.users [ recoveryUser ])
        )
        && lib.all (group: group.name != recoveryUser) (
          builtins.attrValues (builtins.removeAttrs config.users.groups [ recoveryUser ])
        );
      message = "@clanwright/stunnel-ssh-breakglass reserves the access-recovery account and group names; consumer aliases must not collide.";
    }
    {
      assertion =
        config.users.groups.${recoveryUser}.members == [ ]
        && lib.all lib.id (
          lib.mapAttrsToList (
            name: user:
            name == recoveryUser
            || (user.group != recoveryUser && !(builtins.elem recoveryUser user.extraGroups))
          ) config.users.users
        );
      message = "@clanwright/stunnel-ssh-breakglass reserves access-recovery group membership for the recovery account.";
    }
  ];

  sops.secrets = lib.mkMerge [
    {
      ${settings.pskSecretName} = {
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "${service}.service" ];
      };
    }
    {
      ${settings.authorizedKeysSecretName} = {
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "${sshd}.service" ];
      };
    }
  ];

  clan.core.state.${service}.folders = [ paths.state ];

  users.groups.sshd = { };
  users.groups.${recoveryUser} = { };
  users.users.sshd = {
    isSystemUser = true;
    group = "sshd";
  };
  users.users.${recoveryUser} = {
    isNormalUser = true;
    createHome = true;
    home = paths.recoveryHome;
    group = recoveryUser;
    shell = pkgs.bashInteractive;
    description = "Emergency recovery account managed by @clanwright/stunnel-ssh-breakglass";
  };

  security.pam.services.${sshd} = {
    startSession = true;
    showMotd = false;
    unixAuth = false;
  };
  security.sudo.extraRules = [
    {
      users = [ recoveryUser ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  systemd.services = {
    ${hostKey} = {
      description = "Generate an isolated host key for TLS SSH break-glass access";
      before = [ "${sshd}.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = rendered.ensureHostKey;
        RemainAfterExit = true;
        StateDirectory = service;
        StateDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    ${sshd} = {
      description = "Loopback SSH daemon for TLS break-glass access";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "sops-install-secrets.service"
        "${hostKey}.service"
      ];
      requires = [ "${hostKey}.service" ];
      stopIfChanged = false;

      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          rendered.stageAuthorizedKeys
          "${openssh}/bin/sshd -t -f ${rendered.sshdConfig}"
        ];
        ExecStart = "${openssh}/bin/sshd -D -e -f ${rendered.sshdConfig}";
        RuntimeDirectory = sshd;
        RuntimeDirectoryMode = "0750";
        Group = recoveryUser;
        LoadCredential = [ "authorized-keys:${authorizedKeysSecretPath}" ];
        UMask = "0077";
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = "5s";
        PrivateTmp = true;
      };

      unitConfig = {
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
      };
    };

    ${service} = {
      description = "TLS 1.3 PSK SSH break-glass listener";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "sops-install-secrets.service"
        "${sshd}.service"
      ];
      requires = [ "${sshd}.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = rendered.validatePsk;
        ExecStart = "${stunnel}/bin/stunnel ${rendered.stunnelConfig}";
        DynamicUser = true;
        LoadCredential = [ "psk:${pskSecretPath}" ];
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        MemoryMax = "128M";
        TasksMax = 32;
        LimitNOFILE = 1024;
      };

      unitConfig = {
        StartLimitIntervalSec = "60s";
        StartLimitBurst = 5;
      };
    };
  };
}
