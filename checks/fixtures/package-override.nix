{ pkgs, ... }:
{
  services.tailscale.package = pkgs.hello;
}
