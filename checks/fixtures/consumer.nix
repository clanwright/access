{
  inventory = {
    meta.name = "access-consumer-fixture";
    machines.access-node = { };
    instances = {
      tailscale-admin = {
        module = {
          input = "access";
          name = "@clanwright/tailscale-admin";
        };
        roles.admin-access.machines.access-node.settings = { };
      };
      fail2ban-ssh = {
        module = {
          input = "access";
          name = "@clanwright/fail2ban-ssh";
        };
        roles.ssh-guard.machines.access-node.settings = { };
      };
      fwknop-ssh-breakglass = {
        module = {
          input = "access";
          name = "@clanwright/fwknop-ssh-breakglass";
        };
        roles.breakglass.machines.access-node.settings = { };
      };
    };
  };
}
