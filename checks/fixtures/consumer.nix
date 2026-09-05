{
  machines.access-node = {
    nixpkgs.hostPlatform = "x86_64-linux";
    system.stateVersion = "26.11";
  };
  inventory = {
    meta.name = "access-consumer-fixture";
    machines.access-node = { };
    instances = {
      tailscale-admin = {
        module = {
          input = "access";
          name = "@clanwright/tailscale-admin";
        };
        roles.admin-access.machines.access-node.settings.acceptDns = true;
      };
      stunnel-ssh-breakglass = {
        module = {
          input = "access";
          name = "@clanwright/stunnel-ssh-breakglass";
        };
        roles.breakglass.machines.access-node.settings = {
          tlsPort = 48111;
          sshPort = 48112;
          recoveryUser = "fixture-recovery";
        };
      };
    };
  };
}
