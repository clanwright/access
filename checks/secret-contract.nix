{
  lib,
  pkgs,
  root,
  self,
}:
let
  defaultsFor = role: (lib.evalModules { modules = [ role.interface ]; }).config;

  tailscaleRole =
    (import ../clanServices/tailscale-admin/default.nix { inherit self; }).roles.admin-access;
  tailscaleDefaults = defaultsFor tailscaleRole;
  tailscaleModule = (tailscaleRole.perInstance { settings = tailscaleDefaults; }).nixosModule {
    config.sops.secrets.${tailscaleDefaults.authKeySecretName}.path =
      "/run/secrets/${tailscaleDefaults.authKeySecretName}";
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

  optionNames =
    role:
    builtins.attrNames (
      builtins.removeAttrs ((lib.evalModules { modules = [ role.interface ]; }).options) [ "_module" ]
    );
  tailscaleOptions = optionNames tailscaleRole;
  fwknopOptions = optionNames fwknopRole;
  plaintextRejected = !(builtins.tryEval (import ./fixtures/plaintext-secret.nix { })).success;
  rootOnly = secret: secret.owner == "root" && secret.group == "root" && secret.mode == "0400";
  contract =
    tailscaleOptions == [
      "acceptDns"
      "authKeySecretName"
      "lifecycle"
      "openFirewall"
      "useRoutingFeatures"
    ]
    &&
      fwknopOptions == [
        "accessTimeout"
        "hmacSecretName"
        "keySecretName"
        "spaUdpPort"
        "sshPort"
        "wanListenIPv4"
      ]
    && tailscaleModule.services.tailscale.authKeyFile == "/run/secrets/tailscale-auth-key"
    && builtins.attrNames tailscaleModule.sops.secrets == [ "tailscale-auth-key" ]
    && rootOnly tailscaleModule.sops.secrets.tailscale-auth-key
    &&
      builtins.attrNames fwknopModule.sops.secrets == [
        "fwknop-access-key"
        "fwknop-hmac-key"
      ]
    && builtins.all (
      secret: rootOnly secret && secret.restartUnits == [ "fwknop-ssh-breakglass.service" ]
    ) (builtins.attrValues fwknopModule.sops.secrets)
    && plaintextRejected
    && !(builtins.pathExists (root + "/sops"))
    && !(builtins.pathExists (root + "/vars"))
    && !(builtins.pathExists (root + "/secrets"));
in
if contract then
  pkgs.runCommand "access-secret-contract" { } ''
    touch "$out"
  ''
else
  throw "Access secret boundary changed"
