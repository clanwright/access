{
  lib,
  pkgs,
  root,
  self,
}:
let
  optionNames =
    role:
    builtins.attrNames (
      builtins.removeAttrs (lib.evalModules { modules = [ role.interface ]; }).options [ "_module" ]
    );
  tailscaleRole =
    (import ../clanServices/tailscale-admin/default.nix { inherit self; }).roles.admin-access;
  emergencyRole =
    (import ../clanServices/stunnel-ssh-breakglass/default.nix { inherit self; }).roles.breakglass;
  evaluateSettings =
    role: candidate:
    builtins.tryEval (
      import ./fixtures/plaintext-secret.nix {
        inherit lib candidate;
        inherit (role) interface;
      }
    );
  # Positive controls distinguish a working evaluator from universal failure.
  roleRejectsPlaintext =
    role:
    (evaluateSettings role { }).success
    && builtins.all (name: !(evaluateSettings role { ${name} = true; }).success) [
      "authKeyValue"
      "credential"
      "hmacSecretValue"
      "keySecretValue"
      "password"
      "secretValue"
      "token"
    ];
  defaults = (lib.evalModules { modules = [ tailscaleRole.interface ]; }).config;
  tailscale = (tailscaleRole.perInstance { settings = defaults; }).nixosModule {
    config.sops.secrets.${defaults.authKeySecretName}.path =
      "/run/secrets/${defaults.authKeySecretName}";
    inherit lib pkgs;
  };
  secret = tailscale.sops.secrets.${defaults.authKeySecretName};
  contract =
    optionNames tailscaleRole == [
      "acceptDns"
      "authKeySecretName"
      "lifecycle"
      "openFirewall"
      "useRoutingFeatures"
    ]
    &&
      optionNames emergencyRole == [
        "authorizedKeysSecretName"
        "listenAddress"
        "pskSecretName"
        "recoveryUser"
        "sshPort"
        "tlsPort"
      ]
    && secret.owner == "root"
    && secret.group == "root"
    && secret.mode == "0400"
    && roleRejectsPlaintext tailscaleRole
    && roleRejectsPlaintext emergencyRole
    && builtins.all (name: !(builtins.pathExists (root + "/${name}"))) [
      "sops"
      "vars"
      "secrets"
    ];
in
if contract then
  pkgs.runCommand "access-secret-contract" { } ''touch "$out"''
else
  throw "Access secret boundary changed"
