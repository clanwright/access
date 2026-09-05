{ self, settings }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  serviceName = "stunnel-ssh-breakglass";
  sshdServiceName = "${serviceName}-sshd";
  hostKeyServiceName = "${serviceName}-hostkey";
  stunnelRunDir = "/run/${serviceName}";
  sshdRunDir = "/run/${sshdServiceName}";
  stunnelConfig = "${stunnelRunDir}/stunnel.conf";
  authorizedKeysPath = "${sshdRunDir}/authorized_keys";
  stateDir = "/var/lib/${serviceName}";
  hostKeyPath = "${stateDir}/ssh_host_ed25519_key";
  recoveryHome = "/var/lib/${serviceName}-recovery";
  accessStunnel = self.packages.${pkgs.stdenv.hostPlatform.system}.stunnel;
  accessOpenSSH = self.packages.${pkgs.stdenv.hostPlatform.system}.openssh;
  pskSecretPath = config.sops.secrets.${settings.pskSecretName}.path;
  authorizedKeysSecretPath = config.sops.secrets.${settings.authorizedKeysSecretName}.path;
  rendered = import ./rendering.nix {
    inherit
      accessOpenSSH
      authorizedKeysPath
      hostKeyPath
      hostKeyServiceName
      lib
      pkgs
      serviceName
      settings
      sshdRunDir
      sshdServiceName
      stunnelConfig
      ;
  };
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

  sops.secrets.${settings.pskSecretName} = {
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "${serviceName}.service" ];
  };
  sops.secrets.${settings.authorizedKeysSecretName} = {
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "${sshdServiceName}.service" ];
  };

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
    home = recoveryHome;
    group = settings.recoveryUser;
    shell = pkgs.bashInteractive;
    description = "Emergency recovery account managed by @clanwright/stunnel-ssh-breakglass";
  };

  security.pam.services.${sshdServiceName} = {
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
    ${hostKeyServiceName} = {
      description = "Generate an isolated host key for TLS SSH break-glass access";
      before = [ "${sshdServiceName}.service" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = rendered.generateHostKey;
        RemainAfterExit = true;
        StateDirectory = serviceName;
        StateDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };

    ${sshdServiceName} = {
      description = "Loopback SSH daemon for TLS break-glass access";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "sops-install-secrets.service"
        "${hostKeyServiceName}.service"
      ];
      requires = [ "${hostKeyServiceName}.service" ];
      stopIfChanged = false;

      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          rendered.renderAuthorizedKeys
          "${accessOpenSSH}/bin/sshd -t -f ${rendered.sshdConfig}"
        ];
        ExecStart = "${accessOpenSSH}/bin/sshd -D -e -f ${rendered.sshdConfig}";
        RuntimeDirectory = sshdServiceName;
        RuntimeDirectoryMode = "0750";
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

    ${serviceName} = {
      description = "TLS 1.3 PSK SSH break-glass listener";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "sops-install-secrets.service"
        "${sshdServiceName}.service"
      ];
      requires = [ "${sshdServiceName}.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = rendered.renderStunnelConfig;
        ExecStart = "${accessStunnel}/bin/stunnel ${stunnelConfig}";
        RuntimeDirectory = serviceName;
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
