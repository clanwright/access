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
}
