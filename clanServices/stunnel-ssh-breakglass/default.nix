{ self }:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/stunnel-ssh-breakglass";
    description = "TLS 1.3 PSK SSH break-glass access";
    readme = builtins.readFile ./README.md;
  };

  perMachine =
    { instances, machine, ... }:
    let
      instanceNames = builtins.attrNames instances;
      selectedInstance = instances.${builtins.head instanceNames};
      settings = selectedInstance.roles.breakglass.machines.${machine.name}.settings;
    in
    {
      nixosModule = {
        imports = [ (import ./runtime.nix { inherit self settings; }) ];
        assertions = [
          {
            assertion = builtins.length instanceNames == 1;
            message = "@clanwright/stunnel-ssh-breakglass allows at most one instance on machine '${machine.name}'.";
          }
        ];
      };
    };

  roles.breakglass = {
    description = "Provides isolated TLS 1.3 PSK recovery access over SSH";
    interface = import ./interface.nix;
  };
}
