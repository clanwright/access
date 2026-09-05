{
  machines.access-node = {
    nixpkgs.hostPlatform = "x86_64-linux";
    # Evaluation-only container; all credential references are runtime paths.
    boot.isContainer = true;
    # Replace Clan's generated empty fallback with static empty metadata so
    # evaluation can hash it without import-from-derivation. No payload exists.
    sops.defaultSopsFile = ./empty-sops.yaml;
    sops.age.keyFile = "/run/access-consumer-fixture/age-key";
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
