{ self }:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/fwknop-ssh-breakglass";
    description = "Hidden WAN SSH break-glass access via fwknop SPA";
    readme = builtins.readFile ./README.md;
  };

  roles.breakglass = {
    description = "Opens a temporary high-port SSH firewall rule after valid fwknop SPA";
    interface =
      { lib, ... }:
      {
        options = {
          sshPort = lib.mkOption {
            type = lib.types.port;
            default = 47291;
            description = "Additional SSH port opened temporarily by fwknop.";
          };
          spaUdpPort = lib.mkOption {
            type = lib.types.port;
            default = 62201;
            description = "UDP port where fwknopd listens for SPA packets.";
          };
          accessTimeout = lib.mkOption {
            type = lib.types.ints.positive;
            default = 300;
            description = "Maximum SSH access window, in seconds.";
          };
          wanListenIPv4 = lib.mkOption {
            type = lib.types.str;
            default = "0.0.0.0";
            description = "IPv4 address for the break-glass SSH daemon to listen on.";
          };
          keySecretName = lib.mkOption {
            type = lib.types.str;
            default = "fwknop-access-key";
            description = "SOPS secret name containing fwknop KEY_BASE64.";
          };
          hmacSecretName = lib.mkOption {
            type = lib.types.str;
            default = "fwknop-hmac-key";
            description = "SOPS secret name containing fwknop HMAC_KEY_BASE64.";
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
            serviceName = "fwknop-ssh-breakglass";
            breakglassSshdServiceName = "${serviceName}-sshd";
            breakglassSshdRunDir = "/run/${breakglassSshdServiceName}";
            runDir = "/run/${serviceName}";
            accessFwknop = self.packages.${pkgs.stdenv.hostPlatform.system}.fwknop;
            fwknopBin = "${accessFwknop}/bin/fwknopd";
            sshdBin = "${pkgs.openssh}/bin/sshd";
            fwknopdConf = "${runDir}/fwknopd.conf";
            accessConf = "${runDir}/access.conf";
            digestCache = "${runDir}/digest.cache";
            breakglassSshdConfig = pkgs.writeText "${breakglassSshdServiceName}-config" ''
              AuthorizedKeysFile %h/.ssh/authorized_keys /etc/ssh/authorized_keys.d/%u
              AuthorizedPrincipalsFile none
              PasswordAuthentication no
              KbdInteractiveAuthentication no
              PermitRootLogin prohibit-password
              UsePAM yes
              StrictModes yes
              LogLevel VERBOSE
              PrintMotd no
              UseDNS no
              X11Forwarding no
              AddressFamily inet
              ListenAddress ${settings.wanListenIPv4}
              Port ${toString settings.sshPort}
              HostKey /etc/ssh/ssh_host_ed25519_key
              PidFile ${breakglassSshdRunDir}/sshd.pid
              KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
              Ciphers aes128-ctr,aes192-ctr,aes256-ctr
              Macs hmac-sha2-256-etm@openssh.com,hmac-sha2-512-etm@openssh.com
              Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
            '';
            renderConfig = pkgs.writeShellScript "${serviceName}-render-config" ''
                            set -euo pipefail

                            umask 077

                            key_base64="$(tr -d '\r\n' < ${
                              lib.escapeShellArg config.sops.secrets."${settings.keySecretName}".path
                            })"
                            hmac_key_base64="$(tr -d '\r\n' < ${
                              lib.escapeShellArg config.sops.secrets."${settings.hmacSecretName}".path
                            })"

                            if [ -z "$key_base64" ] || [ -z "$hmac_key_base64" ]; then
                              echo "fwknop SOPS secrets must not be empty" >&2
                              exit 1
                            fi

                            cat > ${lib.escapeShellArg fwknopdConf} <<EOF
              VERBOSE 0;
              ENABLE_UDP_SERVER Y;
              UDPSERV_PORT ${toString settings.spaUdpPort};
              ENABLE_SPA_PACKET_AGING Y;
              MAX_SPA_PACKET_AGE 120;
              ENABLE_IPT_FORWARDING N;
              ENABLE_IPT_LOCAL_NAT N;
              ENABLE_IPT_SNAT N;
              ENABLE_IPT_OUTPUT N;
              ENABLE_RULE_PREPEND Y;
              IPT_INPUT_ACCESS ACCEPT, filter, INPUT, 1, FWKNOP_INPUT, 1;
              FWKNOP_RUN_DIR ${runDir};
              FWKNOP_CONF_DIR ${runDir};
              FWKNOP_PID_FILE ${runDir}/fwknopd.pid;
              DIGEST_FILE ${digestCache};
              EOF

                            cat > ${lib.escapeShellArg accessConf} <<EOF
              SOURCE ANY
              OPEN_PORTS tcp/${toString settings.sshPort}
              KEY_BASE64 $key_base64
              HMAC_KEY_BASE64 $hmac_key_base64
              FW_ACCESS_TIMEOUT ${toString settings.accessTimeout}
              MAX_FW_TIMEOUT ${toString settings.accessTimeout}
              REQUIRE_SOURCE_ADDRESS Y
              ENABLE_CMD_EXEC N
              EOF

                            chmod 0600 ${lib.escapeShellArg fwknopdConf} ${lib.escapeShellArg accessConf}
            '';
          in
          {
            sops.secrets."${settings.keySecretName}" = {
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [ "${serviceName}.service" ];
            };

            sops.secrets."${settings.hmacSecretName}" = {
              owner = "root";
              group = "root";
              mode = "0400";
              restartUnits = [ "${serviceName}.service" ];
            };

            assertions = [
              {
                assertion = !config.networking.nftables.enable;
                message = "@clanwright/fwknop-ssh-breakglass requires the current iptables firewall backend; nftables is enabled.";
              }
            ];

            # Binding to the requested WAN address keeps the service usable during
            # bootstrap. The consumer firewall owns all reachability policy.
            systemd.services = {
              ${breakglassSshdServiceName} = {
                description = "WAN SSH daemon for fwknop break-glass access";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ];

                serviceConfig = {
                  Type = "simple";
                  ExecStartPre = "${sshdBin} -t -f ${breakglassSshdConfig}";
                  ExecStart = "${sshdBin} -D -e -f ${breakglassSshdConfig}";
                  RuntimeDirectory = breakglassSshdServiceName;
                  RuntimeDirectoryMode = "0700";
                  Restart = "on-failure";
                  RestartSec = "10s";
                };
              };

              ${serviceName} = {
                description = "fwknop SPA SSH break-glass access";
                wantedBy = [ "multi-user.target" ];
                after = [
                  "firewall.service"
                  "network.target"
                ];
                wants = [ "firewall.service" ];

                path = [
                  pkgs.coreutils
                  accessFwknop
                  pkgs.iptables
                ];

                serviceConfig = {
                  Type = "simple";
                  ExecStartPre = [
                    renderConfig
                    "${fwknopBin} -U -c ${fwknopdConf} -a ${accessConf} -d ${digestCache} --exit-parse-config"
                  ];
                  ExecStart = "${fwknopBin} -f -U -c ${fwknopdConf} -a ${accessConf} -d ${digestCache}";
                  ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
                  RuntimeDirectory = serviceName;
                  RuntimeDirectoryMode = "0700";
                  Restart = "on-failure";
                  RestartSec = "10s";
                  CapabilityBoundingSet = [
                    "CAP_NET_ADMIN"
                  ];
                  PrivateTmp = true;
                  ProtectHome = true;
                };
              };
            };
          };
      };
  };
}
