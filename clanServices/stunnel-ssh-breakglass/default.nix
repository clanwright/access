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
    interface = import ./interface.nix;

    perInstance =
      { settings, ... }:
      {
        nixosModule = import ./runtime.nix { inherit self settings; };
      };
  };
}
