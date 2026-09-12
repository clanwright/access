{
  instances ? null,
  machineNames ? [ "access-node" ],
  machineModules ? [ ],
}:
let
  machines = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = {
        imports = if builtins.isAttrs machineModules then machineModules.${name} or [ ] else machineModules;
        nixpkgs.hostPlatform = "x86_64-linux";
        # Evaluation-only container; all credential references are runtime paths.
        boot.isContainer = true;
        # Static empty SOPS metadata exercises the real sops-nix module without
        # containing a decrypted payload or generated credential.
        sops.defaultSopsFile = ./empty-sops.yaml;
        sops.age.keyFile = "/run/access-consumer-fixture/${name}-age-key";
        system.stateVersion = "26.11";
      };
    }) machineNames
  );
  defaultInstances = {
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
in
{
  inherit machines;
  inventory = {
    meta.name = "access-consumer-fixture";
    machines = builtins.listToAttrs (
      map (name: {
        inherit name;
        value = { };
      }) machineNames
    );
    instances = if instances == null then defaultInstances else instances;
  };
}
