{
  inputs,
  lib,
  pkgs,
  root,
  self,
}:
let
  registeredRole =
    moduleId: roleName:
    let
      evaluated =
        (inputs.clan-core.lib.evalService {
          modules = [ self.clan.modules.${moduleId} ];
          prefix = [ ];
        }).config;
    in
    evaluated.roles.${roleName};
  tailscaleRole = registeredRole "@clanwright/tailscale-admin" "admin-access";
  emergencyRole = registeredRole "@clanwright/stunnel-ssh-breakglass" "breakglass";
  optionNames =
    role:
    builtins.attrNames (
      builtins.removeAttrs (lib.evalModules { modules = [ role.interface ]; }).options [ "_module" ]
    );
  evaluateSettings =
    role: candidate:
    builtins.tryEval (
      import ./fixtures/plaintext-secret.nix {
        inherit lib candidate;
        inherit (role) interface;
      }
    );
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
  instances = {
    tailscale-admin = {
      module = {
        input = "access";
        name = "@clanwright/tailscale-admin";
      };
      roles.admin-access.machines.access-node = { };
    };
    stunnel-ssh-breakglass = {
      module = {
        input = "access";
        name = "@clanwright/stunnel-ssh-breakglass";
      };
      roles.breakglass.machines.access-node = { };
    };
  };
  machine =
    ((import ./lib/consumer.nix { inherit inputs root self; }) { inherit instances; }).machine;
  tailscaleSecret = machine.sops.secrets.tailscale-auth-key;
  pskSecret = machine.sops.secrets.stunnel-ssh-psk;
  authorizedKeysSecret = machine.sops.secrets.recovery-ssh-authorized-keys;
  rootOnly = secret: secret.owner == "root" && secret.group == "root" && secret.mode == "0400";
  check = import ./lib/contract.nix { inherit lib; };
  contract = check "secret boundary contract" {
    emergency-option-schema =
      optionNames emergencyRole == [
        "authorizedKeysSecretName"
        "listenAddress"
        "pskSecretName"
        "recoveryUser"
        "sshPort"
        "tlsPort"
      ];
    no-secret-directories = builtins.all (name: !(builtins.pathExists (root + "/${name}"))) [
      "sops"
      "vars"
      "secrets"
    ];
    plaintext-settings-rejected =
      roleRejectsPlaintext tailscaleRole && roleRejectsPlaintext emergencyRole;
    registered-secret-metadata =
      rootOnly tailscaleSecret
      && rootOnly pskSecret
      && rootOnly authorizedKeysSecret
      && pskSecret.restartUnits == [ "stunnel-ssh-breakglass.service" ]
      && authorizedKeysSecret.restartUnits == [ "stunnel-ssh-breakglass-sshd.service" ];
    tailscale-option-schema =
      optionNames tailscaleRole == [
        "acceptDns"
        "authKeySecretName"
        "lifecycle"
        "openFirewall"
        "useRoutingFeatures"
      ];
  };
in
assert contract;
pkgs.runCommand "access-secret-contract" { } ''
  touch "$out"
''
