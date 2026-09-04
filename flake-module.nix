{
  lib,
  self,
  ...
}:
{
  clan.modules."@clanwright/tailscale-admin" =
    lib.modules.importApply ./clanServices/tailscale-admin/default.nix
      { inherit self; };
  clan.modules."@clanwright/fail2ban-ssh" =
    lib.modules.importApply ./clanServices/fail2ban-ssh/default.nix
      { inherit self; };
}
