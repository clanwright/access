{
  lib,
  self,
  ...
}:
{
  clan.modules."@clanwright/tailscale-admin" =
    lib.modules.importApply ./clanServices/tailscale-admin/default.nix
      { inherit self; };
}
