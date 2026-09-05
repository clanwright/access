{ self }:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/stunnel-ssh-breakglass";
    description = "TLS 1.3 PSK SSH break-glass access";
    readme = builtins.readFile ./README.md;
  };

  roles.breakglass = {
    description = "Provides isolated TLS 1.3 PSK recovery access over SSH";
    interface =
      { lib, ... }:
      let
        ipv4Octet = "(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])";
        ipv4Address = lib.types.strMatching "${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}\\.${ipv4Octet}";
        recoveryUserName = lib.types.strMatching "[a-z_][a-z0-9_-]*";
        secretName = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
        unprivilegedPort = lib.types.ints.between 1024 65535;
      in
      {
        options = {
          tlsPort = lib.mkOption {
            type = unprivilegedPort;
            default = 47291;
            description = "Public unprivileged TCP port where stunnel accepts TLS 1.3 PSK clients.";
          };
          sshPort = lib.mkOption {
            type = unprivilegedPort;
            default = 47292;
            description = "Unprivileged TCP port for the loopback-only recovery sshd backend.";
          };
          listenAddress = lib.mkOption {
            type = ipv4Address;
            default = "0.0.0.0";
            description = "IPv4 address where the public stunnel listener binds.";
          };
          recoveryUser = lib.mkOption {
            type = recoveryUserName;
            default = "access-recovery";
            description = "Dedicated non-root recovery account name.";
          };
          pskSecretName = lib.mkOption {
            type = secretName;
            default = "stunnel-ssh-psk";
            description = "SOPS secret name containing the stunnel TLS PSK record.";
          };
          authorizedKeysSecretName = lib.mkOption {
            type = secretName;
            default = "recovery-ssh-authorized-keys";
            description = "SOPS secret name containing authorized public SSH keys for the recovery user.";
          };
        };
      };

    perInstance =
      { settings, ... }:
      {
        nixosModule =
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

            sshdConfig = pkgs.writeText "${sshdServiceName}-config" ''
              AddressFamily inet
              ListenAddress 127.0.0.1
              Port ${toString settings.sshPort}
              HostKey ${hostKeyPath}
              PidFile ${sshdRunDir}/sshd.pid
              AuthorizedKeysFile ${authorizedKeysPath}
              AuthorizedKeysCommand none
              AuthorizedPrincipalsFile none
              AllowUsers ${settings.recoveryUser}
              AuthenticationMethods publickey
              PubkeyAuthentication yes
              PasswordAuthentication no
              KbdInteractiveAuthentication no
              HostbasedAuthentication no
              GSSAPIAuthentication no
              PermitEmptyPasswords no
              PermitRootLogin no
              UsePAM yes
              PAMServiceName ${sshdServiceName}
              StrictModes yes
              PermitUserEnvironment no
              PermitUserRC no
              PermitTTY yes
              DisableForwarding yes
              AllowAgentForwarding no
              AllowTcpForwarding no
              AllowStreamLocalForwarding no
              GatewayPorts no
              PermitTunnel no
              PermitOpen none
              PermitListen none
              X11Forwarding no
              MaxAuthTries 3
              MaxSessions 1
              MaxStartups 10:30:60
              PerSourcePenalties no
              LoginGraceTime 30
              LogLevel VERBOSE
              SyslogFacility AUTHPRIV
              PrintMotd no
              UseDNS no
              Subsystem sftp ${accessOpenSSH}/libexec/sftp-server
            '';

            renderStunnelConfig = pkgs.writeShellScript "${serviceName}-render-config" ''
              set -euo pipefail
              : "''${CREDENTIALS_DIRECTORY:?systemd did not provide the stunnel PSK credential}"

              if ! ${pkgs.gawk}/bin/awk '
                BEGIN { records = 0; valid = 1 }
                /^[A-Za-z0-9._-]+:[0-9a-f]{64}$/ { records += 1; next }
                { valid = 0 }
                END { exit !(valid && records == 1) }
              ' "$CREDENTIALS_DIRECTORY/psk"; then
                echo "invalid stunnel PSK record" >&2
                exit 1
              fi

              umask 077
              ${pkgs.coreutils}/bin/cat > ${lib.escapeShellArg stunnelConfig} <<EOF
              foreground = yes
              debug = notice
              [ssh]
              client = no
              accept = ${settings.listenAddress}:${toString settings.tlsPort}
              connect = 127.0.0.1:${toString settings.sshPort}
              PSKsecrets = $CREDENTIALS_DIRECTORY/psk
              sslVersionMin = TLSv1.3
              sslVersionMax = TLSv1.3
              renegotiation = no
              sessionResume = no
              sessionCacheSize = 100
              TIMEOUTbusy = 30
              TIMEOUTconnect = 10
              TIMEOUTidle = 900
              EOF
              ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg stunnelConfig}
            '';

            renderAuthorizedKeys = pkgs.writeShellScript "${sshdServiceName}-render-authorized-keys" ''
              set -euo pipefail
              : "''${CREDENTIALS_DIRECTORY:?systemd did not provide recovery authorized keys}"

              if ! ${accessOpenSSH}/bin/ssh-keygen -lf "$CREDENTIALS_DIRECTORY/authorized-keys" >/dev/null 2>&1; then
                echo "invalid recovery authorized-key file" >&2
                exit 1
              fi

              ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g ${lib.escapeShellArg settings.recoveryUser} ${lib.escapeShellArg sshdRunDir}
              ${pkgs.coreutils}/bin/install -m 0440 -o root -g ${lib.escapeShellArg settings.recoveryUser} "$CREDENTIALS_DIRECTORY/authorized-keys" ${lib.escapeShellArg authorizedKeysPath}
            '';

            generateHostKey = pkgs.writeShellScript "${hostKeyServiceName}-generate" ''
              set -euo pipefail
              umask 077

              if [ ! -s ${lib.escapeShellArg hostKeyPath} ]; then
                ${accessOpenSSH}/bin/ssh-keygen -q -t ed25519 -N "" -f ${lib.escapeShellArg hostKeyPath}
              fi
              ${accessOpenSSH}/bin/ssh-keygen -lf ${lib.escapeShellArg hostKeyPath} >/dev/null
            '';
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
                  ExecStart = generateHostKey;
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
                    renderAuthorizedKeys
                    "${accessOpenSSH}/bin/sshd -t -f ${sshdConfig}"
                  ];
                  ExecStart = "${accessOpenSSH}/bin/sshd -D -e -f ${sshdConfig}";
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
                  ExecStartPre = renderStunnelConfig;
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
          };
      };
  };
}
