{
  lib,
  self,
  ...
}:
{
  clan.modules."@clanwright/tailscale-admin" =
    lib.modules.importApply ./clanServices/tailscale-admin/default.nix
      { inherit self; };
  clan.modules."@clanwright/stunnel-ssh-breakglass" =
    lib.modules.importApply ./clanServices/stunnel-ssh-breakglass/default.nix
      { inherit self; };
}
