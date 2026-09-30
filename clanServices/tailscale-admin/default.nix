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
            type = lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9._-]*";
            default = "tailscale-auth-key";
            description = "Safe SOPS secret name containing the Tailscale authentication key.";
          };
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether the Tailscale runtime is active; retained state is never deleted.";
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
      {
        nixosModule =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            extraFlags = [
              "--accept-dns=${lib.boolToString settings.acceptDns}"
              "--ssh=false"
            ];
          in
          {
            sops.secrets."${settings.authKeySecretName}" = {
              owner = "root";
              group = "root";
              mode = "0400";
            };

            clan.core.state.tailscale.folders = [ "/var/lib/tailscale" ];

            services.tailscale = {
              inherit (settings) enable;
              package = lib.mkForce self.packages.${pkgs.stdenv.hostPlatform.system}.tailscale;
              authKeyFile = config.sops.secrets."${settings.authKeySecretName}".path;
              extraUpFlags = extraFlags;
              extraSetFlags = extraFlags;
            };
          };
      };
  };
}
