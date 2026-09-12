{
  inputs,
  lib,
  pkgs,
  root,
  self,
  system,
}:
let
  moduleId = "@clanwright/tailscale-admin";
  registeredModule = self.clan.modules.${moduleId} or (throw "${moduleId} is not registered");
  evaluatedService =
    (inputs.clan-core.lib.evalService {
      modules = [ registeredModule ];
      prefix = [ ];
    }).config;
  role = evaluatedService.roles.admin-access;
  defaults = (lib.evalModules { modules = [ role.interface ]; }).config;
  consumerFor = import ./lib/consumer.nix { inherit inputs root self; };
  instance = name: settings: {
    ${name} = {
      module = {
        input = "access";
        name = moduleId;
      };
      roles.admin-access.machines.access-node = { inherit settings; };
    };
  };
  scenario =
    settings: machineModules:
    (consumerFor {
      instances = instance "tailscale-admin" settings;
      inherit machineModules;
    }).machine;
  enabled = scenario { } [ ];
  dnsEnabled = scenario { acceptDns = true; } [ ];
  disabled = scenario { lifecycle = "disabled-retained"; } [ ];
  interfaceAccepts =
    authKeySecretName:
    (builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            role.interface
            { config = { inherit authKeySecretName; }; }
          ];
        }).config.authKeySecretName
        true
    )).success;
  secret = enabled.sops.secrets.${defaults.authKeySecretName};
  check = import ./lib/contract.nix { inherit lib; };
  contract = check "tailscale-admin contract" {
    accept-dns-customization =
      dnsEnabled.services.tailscale.extraUpFlags == [
        "--accept-dns=true"
        "--ssh=false"
      ]
      &&
        dnsEnabled.services.tailscale.extraSetFlags == [
          "--accept-dns=true"
          "--ssh=false"
        ];
    default-flags =
      enabled.services.tailscale.extraUpFlags == [
        "--accept-dns=false"
        "--ssh=false"
      ]
      &&
        enabled.services.tailscale.extraSetFlags == [
          "--accept-dns=false"
          "--ssh=false"
        ];
    default-settings =
      defaults.authKeySecretName == "tailscale-auth-key"
      && defaults.lifecycle == "enabled"
      && defaults.useRoutingFeatures == "none"
      && defaults.openFirewall
      && !defaults.acceptDns;
    disabled-retained =
      !disabled.services.tailscale.enable
      && disabled.clan.core.state.tailscale.folders == [ "/var/lib/tailscale" ]
      && disabled.sops.secrets ? tailscale-auth-key;
    enabled = enabled.services.tailscale.enable;
    interface-schema = builtins.deepSeq evaluatedService.result.api.schema true;
    manifest =
      evaluatedService.manifest.name == moduleId
      && builtins.attrNames evaluatedService.roles == [ "admin-access" ];
    package-authority = enabled.services.tailscale.package == self.packages.${system}.tailscale;
    secret-metadata =
      enabled.services.tailscale.authKeyFile == "/run/secrets/tailscale-auth-key"
      && secret.owner == "root"
      && secret.group == "root"
      && secret.mode == "0400";
    secret-name-type =
      interfaceAccepts "tailscale_auth.key-1"
      && !(interfaceAccepts "tailscale/auth-key")
      && !(interfaceAccepts ".tailscale-auth-key")
      && !(interfaceAccepts "tailscale-auth-key\nunsafe");
    ssh-independence = !enabled.services.openssh.enable && !(enabled.systemd.services ? sshd);
  };
in
assert contract;
pkgs.runCommand "tailscale-admin-contract" { } ''
  touch "$out"
''
