{ self }:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/tailscale-admin";
    description = "Tailscale admin access service";
    readme = builtins.readFile ./README.md;
  };

  roles.admin-access = {
    description = "Admin access channel";
    interface =
      { lib, ... }:
      {
        options = {
          authKeySecretName = lib.mkOption {
            type = lib.types.str;
            default = "tailscale-auth-key";
          };
          lifecycle = lib.mkOption {
            type = lib.types.enum [
              "enabled"
              "disabled-retained"
            ];
            default = "enabled";
            description = "Whether Tailscale runtime and its SSH ordering edge are active.";
          };
          useRoutingFeatures = lib.mkOption {
            type = lib.types.enum [
              "none"
              "client"
              "server"
              "both"
            ];
            default = "client";
          };
          openFirewall = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          acceptDns = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether Tailscale may override the host DNS settings.";
          };
        };
      };

    perInstance =
      { settings, ... }:
      let
        enabled = (settings.lifecycle or "enabled") == "enabled";
      in
      {
        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          {
            sops.secrets."${settings.authKeySecretName}" = {
              owner = "root";
              group = "root";
              mode = "0400";
            };

            clan.core.state.tailscale.folders = [ "/var/lib/tailscale" ];

            services.tailscale = {
              inherit (settings) openFirewall useRoutingFeatures;
              enable = enabled;
              package = lib.mkForce self.packages.${pkgs.stdenv.hostPlatform.system}.tailscale;
              authKeyFile = config.sops.secrets."${settings.authKeySecretName}".path;
              extraUpFlags = if settings.acceptDns then [ ] else [ "--accept-dns=false" ];
              extraSetFlags = if settings.acceptDns then [ ] else [ "--accept-dns=false" ];
            };

            systemd.services.sshd.wants = lib.mkIf enabled [ "tailscaled.service" ];
          };
      };
  };
}
