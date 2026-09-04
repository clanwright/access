{ self }:
{
  _class = "clan.service";
  manifest = {
    name = "@clanwright/fail2ban-ssh";
    description = "Fail2ban SSH hardening";
    readme = builtins.readFile ./README.md;
  };

  roles.ssh-guard = {
    description = "Protects SSH with fail2ban";
    interface =
      { lib, ... }:
      {
        options = {
          lifecycle = lib.mkOption {
            type = lib.types.enum [
              "enabled"
              "disabled-retained"
            ];
            default = "enabled";
            description = "Whether this Fail2ban role contributes runtime configuration.";
          };
          maxretry = lib.mkOption {
            type = lib.types.int;
            default = 5;
          };
          findtime = lib.mkOption {
            type = lib.types.str;
            default = "10m";
          };
          bantime = lib.mkOption {
            type = lib.types.str;
            default = "1h";
          };
          backend = lib.mkOption {
            type = lib.types.str;
            default = "systemd";
          };
          ignoreIPs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "IP addresses or CIDRs excluded from the SSH jail.";
          };
          bootstrapMarkerPath = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              If set, sshd jail temporarily ignores all sources while this marker file exists.
              Used to prevent operator self-ban during bootstrap WAN SSH window.
            '';
          };
        };
      };

    perInstance =
      { settings, ... }:
      let
        ignoreIPs = settings.ignoreIPs or [ ];
        markerPath = settings.bootstrapMarkerPath or null;
      in
      {
        nixosModule =
          {
            lib,
            pkgs,
            ...
          }:
          if (settings.lifecycle or "enabled") == "enabled" then
            {
              services.fail2ban = {
                enable = true;
                package = lib.mkForce self.packages.${pkgs.stdenv.hostPlatform.system}.fail2ban;
                jails.sshd.settings = {
                  enabled = true;
                  inherit (settings)
                    backend
                    maxretry
                    findtime
                    bantime
                    ;
                }
                // (if ignoreIPs == [ ] then { } else { ignoreip = builtins.concatStringsSep " " ignoreIPs; })
                // (
                  if markerPath == null then
                    { }
                  else
                    {
                      # When bootstrap marker exists, ignorecommand exits 0 for any source
                      # and fail2ban skips banning; once marker is removed the jail returns
                      # to normal behavior without config changes.
                      ignorecommand = "/run/current-system/sw/bin/bash -lc 'test -e ${markerPath}'";
                    }
                );
              };
            }
            // (
              if markerPath == null then
                { }
              else
                {
                  systemd.services.fail2ban.unitConfig.ConditionPathExists = "!${markerPath}";
                }
            )
          else
            { };
      };
  };
}
