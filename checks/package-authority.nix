{
  lib,
  mutation ? false,
  pkgs,
  self,
  system,
}:
let
  defaultsFor = role: (lib.evalModules { modules = [ role.interface ]; }).config;
  unwrap = value: if builtins.isAttrs value && value ? content then unwrap value.content else value;
  forcedChoice =
    definition:
    (lib.evalModules {
      modules = [
        {
          options.package = lib.mkOption { type = lib.types.package; };
          config.package = pkgs.hello;
        }
        { config.package = definition; }
      ];
    }).config.package;

  tailscaleRole =
    (import ../clanServices/tailscale-admin/default.nix { inherit self; }).roles.admin-access;
  tailscaleDefaults = defaultsFor tailscaleRole;
  tailscaleModule = (tailscaleRole.perInstance { settings = tailscaleDefaults; }).nixosModule {
    config.sops.secrets.${tailscaleDefaults.authKeySecretName}.path =
      "/run/secrets/${tailscaleDefaults.authKeySecretName}";
    inherit lib pkgs;
  };

  fail2banRole = (import ../clanServices/fail2ban-ssh/default.nix { inherit self; }).roles.ssh-guard;
  fail2banDefaults = defaultsFor fail2banRole;
  fail2banModule = (fail2banRole.perInstance { settings = fail2banDefaults; }).nixosModule {
    inherit lib pkgs;
  };

  fwknopRole =
    (import ../clanServices/fwknop-ssh-breakglass/default.nix { inherit self; }).roles.breakglass;
  fwknopDefaults = defaultsFor fwknopRole;
  fwknopModule = (fwknopRole.perInstance { settings = fwknopDefaults; }).nixosModule {
    config = {
      networking.nftables.enable = false;
      sops.secrets.${fwknopDefaults.keySecretName}.path = "/run/secrets/${fwknopDefaults.keySecretName}";
      sops.secrets.${fwknopDefaults.hmacSecretName}.path =
        "/run/secrets/${fwknopDefaults.hmacSecretName}";
    };
    inherit lib pkgs;
  };

  expectedTailscale = if mutation then pkgs.hello else self.packages.${system}.tailscale;
  fwknopUnit = fwknopModule.systemd.services.fwknop-ssh-breakglass;
  contract =
    unwrap tailscaleModule.services.tailscale.package == self.packages.${system}.tailscale
    && forcedChoice tailscaleModule.services.tailscale.package == expectedTailscale
    && unwrap fail2banModule.services.fail2ban.package == self.packages.${system}.fail2ban
    && forcedChoice fail2banModule.services.fail2ban.package == self.packages.${system}.fail2ban
    &&
      fwknopUnit.path == [
        pkgs.coreutils
        self.packages.${system}.fwknop
        pkgs.iptables
      ]
    && lib.hasPrefix "${self.packages.${system}.fwknop}/bin/fwknopd " fwknopUnit.serviceConfig.ExecStart;
in
if contract then
  pkgs.runCommand "access-package-authority" { } ''
    touch "$out"
  ''
else
  throw "Access package authority changed"
