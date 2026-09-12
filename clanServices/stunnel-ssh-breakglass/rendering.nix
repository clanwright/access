{
  lib,
  pkgs,
  self,
  settings,
}:
let
  names = rec {
    service = "stunnel-ssh-breakglass";
    sshd = "${service}-sshd";
    hostKey = "${service}-hostkey";
  };
  paths = rec {
    stunnelRun = "/run/${names.service}";
    sshdRun = "/run/${names.sshd}";
    stunnelConfig = "${stunnelRun}/stunnel.conf";
    authorizedKeys = "${sshdRun}/authorized_keys";
    state = "/var/lib/${names.service}";
    hostKey = "${state}/ssh_host_ed25519_key";
    recoveryHome = "/var/lib/${names.service}-recovery";
  };
  packages = {
    stunnel = self.packages.${pkgs.stdenv.hostPlatform.system}.stunnel;
    openssh = self.packages.${pkgs.stdenv.hostPlatform.system}.openssh;
  };
in
rec {
  inherit names packages paths;

  sshdConfig = pkgs.writeText "${names.sshd}-config" ''
    AddressFamily inet
    ListenAddress 127.0.0.1
    Port ${toString settings.sshPort}
    HostKey ${paths.hostKey}
    PidFile ${paths.sshdRun}/sshd.pid
    AuthorizedKeysFile ${paths.authorizedKeys}
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
    PAMServiceName ${names.sshd}
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
    Subsystem sftp ${packages.openssh}/libexec/sftp-server
  '';

  renderStunnelConfig = pkgs.writeShellScript "${names.service}-render-config" ''
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
    ${pkgs.coreutils}/bin/cat > ${lib.escapeShellArg paths.stunnelConfig} <<EOF
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
    ${pkgs.coreutils}/bin/chmod 0600 ${lib.escapeShellArg paths.stunnelConfig}
  '';

  renderAuthorizedKeys = pkgs.writeShellScript "${names.sshd}-render-authorized-keys" ''
    set -euo pipefail
    : "''${CREDENTIALS_DIRECTORY:?systemd did not provide recovery authorized keys}"

    if ! ${packages.openssh}/bin/ssh-keygen -lf "$CREDENTIALS_DIRECTORY/authorized-keys" >/dev/null 2>&1; then
      echo "invalid recovery authorized-key file" >&2
      exit 1
    fi

    ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g ${lib.escapeShellArg settings.recoveryUser} ${lib.escapeShellArg paths.sshdRun}
    ${pkgs.coreutils}/bin/install -m 0440 -o root -g ${lib.escapeShellArg settings.recoveryUser} "$CREDENTIALS_DIRECTORY/authorized-keys" ${lib.escapeShellArg paths.authorizedKeys}
  '';

  generateHostKey = pkgs.writeShellScript "${names.hostKey}-generate" ''
    set -euo pipefail
    umask 077

    if [ ! -s ${lib.escapeShellArg paths.hostKey} ]; then
      ${packages.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f ${lib.escapeShellArg paths.hostKey}
    fi
    ${packages.openssh}/bin/ssh-keygen -lf ${lib.escapeShellArg paths.hostKey} >/dev/null
  '';
}
