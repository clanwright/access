{ self, settings }:
{
  config,
  lib,
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
  inherit (rendered.names) hostKey service sshd;
  inherit (rendered.packages) openssh stunnel;
  inherit (rendered) paths;
  pskSecretPath = config.sops.secrets.${settings.pskSecretName}.path;
  authorizedKeysSecretPath = config.sops.secrets.${settings.authorizedKeysSecretName}.path;
in
{
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
      assertion = settings.recoveryUser != "root";
      message = "@clanwright/stunnel-ssh-breakglass recoveryUser must be non-root.";
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
  users.groups.${settings.recoveryUser} = { };
  users.users.sshd = {
    isSystemUser = true;
    group = "sshd";
    description = "OpenSSH privilege-separation user";
  };
  users.users.${settings.recoveryUser} = {
    isNormalUser = true;
    createHome = true;
    home = paths.recoveryHome;
    group = settings.recoveryUser;
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
      users = [ settings.recoveryUser ];
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
        ExecStart = rendered.generateHostKey;
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
          rendered.renderAuthorizedKeys
          "${openssh}/bin/sshd -t -f ${rendered.sshdConfig}"
        ];
        ExecStart = "${openssh}/bin/sshd -D -e -f ${rendered.sshdConfig}";
        RuntimeDirectory = sshd;
        RuntimeDirectoryMode = "0750";
        Group = settings.recoveryUser;
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
        ExecStartPre = rendered.renderStunnelConfig;
        ExecStart = "${stunnel}/bin/stunnel ${paths.stunnelConfig}";
        RuntimeDirectory = service;
        RuntimeDirectoryMode = "0700";
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
