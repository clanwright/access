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
  enabled = scenario { } [ { services.tailscale.openFirewall = true; } ];
  attemptedPackageOverride = scenario { } [ (import ./fixtures/package-override.nix) ];
  closedFirewall = scenario { } [ ];
  dnsEnabled = scenario { acceptDns = true; } [ ];
  disabled = scenario { enable = false; } [ ];
  namedSecret = scenario { authKeySecretName = "custom-tailscale-key"; } [ ];
  routingClient = scenario { } [ { services.tailscale.useRoutingFeatures = "client"; } ];
  consumerUdpPort = 48555;
  withConsumerPort = scenario { } [
    { services.tailscale.openFirewall = true; }
    { networking.firewall.allowedUDPPorts = [ consumerUdpPort ]; }
  ];
  readyGate = self.lib.tailscaleReadyGate {
    inherit pkgs;
    ipv4 = "100.64.0.10";
    interface = "tailscale0";
  };
  readyGatePath = builtins.unsafeDiscardStringContext (toString readyGate);
  # Evaluation-only native composition. This does not prove Caddy's actual UID,
  # LocalAPI/socket access, sandbox, TUN, cgroup cleanup, or runtime lifetime.
  caddyModule = {
    services.caddy.enable = true;
    services.caddy.extraConfig = ":8080 { respond fixture }";
    # Consumer policy must allow Unix LocalAPI and address-query netlink reads.
    systemd.services.caddy.serviceConfig.RestrictAddressFamilies = [
      "AF_UNIX"
      "AF_INET"
      "AF_INET6"
      "AF_NETLINK"
    ];
  };
  caddyBaseline = scenario { } [ caddyModule ];
  caddyStartup = scenario { } [
    caddyModule
    { systemd.services.caddy.serviceConfig.ExecStartPre = [ readyGate ]; }
  ];
  baselineService = caddyBaseline.systemd.services.caddy;
  startupService = caddyStartup.systemd.services.caddy;
  startupUnit = caddyStartup.systemd.units."caddy.service".text;
  # NixOS settings/unit text may be a drop-in over the unchanged vendor unit.
  # This comparison preserves existing vendor capabilities; it does not prove
  # the assembled systemd unit or claim that stock Caddy has no capabilities.
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
  optionNames = builtins.attrNames (
    builtins.removeAttrs (lib.evalModules { modules = [ role.interface ]; }).options [ "_module" ]
  );
  interfaceRejects =
    candidate:
    !(builtins.tryEval (
      builtins.deepSeq
        (lib.evalModules {
          modules = [
            role.interface
            { config = candidate; }
          ];
        }).config
        true
    )).success;
  secret = enabled.sops.secrets.${defaults.authKeySecretName};
  check = import ./lib/contract.nix { inherit lib; };
  contract = check "tailscale-admin contract" {
    caddy-startup-prestart = (startupService.serviceConfig.ExecStartPre or [ ]) == [ readyGate ];
    caddy-startup-identity =
      startupService.serviceConfig.User == "caddy"
      && startupService.serviceConfig.Group == "caddy"
      && caddyStartup.services.tailscale.package == self.packages.${system}.tailscale;
    caddy-startup-evaluated-policy =
      builtins.removeAttrs startupService.serviceConfig [ "ExecStartPre" ]
      == baselineService.serviceConfig
      && startupService.serviceConfig.NoNewPrivileges
      && startupService.serviceConfig.PrivateDevices
      && startupService.serviceConfig.ProtectHome
      && builtins.elem "AF_UNIX" startupService.serviceConfig.RestrictAddressFamilies
      && builtins.elem "AF_NETLINK" startupService.serviceConfig.RestrictAddressFamilies
      && caddyStartup.systemd.packages == caddyBaseline.systemd.packages
      && caddyStartup.systemd.tmpfiles.rules == caddyBaseline.systemd.tmpfiles.rules;
    caddy-startup-evaluated-graph =
      builtins.all (name: startupService.${name} == baselineService.${name}) [
        "after"
        "before"
        "wants"
        "wantedBy"
        "requires"
        "bindsTo"
        "partOf"
        "reloadTriggers"
        "restartTriggers"
        "restartIfChanged"
        "stopIfChanged"
        "startLimitIntervalSec"
        "startLimitBurst"
      ]
      && startupService.requires == [ ]
      && startupService.bindsTo == [ ]
      && startupService.partOf == [ ];
    caddy-startup-no-privileged-prefix =
      lib.hasInfix "ExecStartPre=${readyGatePath}\n" startupUnit
      && !(lib.hasInfix "ExecStartPre=+" startupUnit)
      && !(lib.hasInfix "ExecStartPre=!" startupUnit);
    caddy-startup-no-reload-gate =
      startupService.serviceConfig.ExecReload == baselineService.serviceConfig.ExecReload
      && !(lib.hasInfix readyGatePath (lib.concatStringsSep " " startupService.serviceConfig.ExecReload));
    caddy-startup-no-tailscale-privilege-change =
      caddyStartup.services.tailscale.extraDaemonFlags == enabled.services.tailscale.extraDaemonFlags
      && caddyStartup.services.tailscale.extraSetFlags == enabled.services.tailscale.extraSetFlags
      && caddyStartup.services.tailscale.permitCertUid == enabled.services.tailscale.permitCertUid;
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
      defaults.authKeySecretName == "tailscale-auth-key" && defaults.enable && !defaults.acceptDns;
    disabled-retained =
      !disabled.services.tailscale.enable
      && !(disabled.systemd.services ? tailscaled)
      && !(builtins.elem 41641 disabled.networking.firewall.allowedUDPPorts)
      && disabled.clan.core.state.tailscale.folders == [ "/var/lib/tailscale" ]
      && disabled.sops.secrets ? tailscale-auth-key;
    enabled = enabled.services.tailscale.enable && enabled.systemd.services ? tailscaled;
    firewall =
      closedFirewall.services.tailscale.enable
      && closedFirewall.systemd.services ? tailscaled
      && enabled.services.tailscale.openFirewall
      && !closedFirewall.services.tailscale.openFirewall
      && builtins.elem 41641 enabled.networking.firewall.allowedUDPPorts
      && !(builtins.elem 41641 closedFirewall.networking.firewall.allowedUDPPorts)
      && builtins.elem consumerUdpPort withConsumerPort.networking.firewall.allowedUDPPorts
      && builtins.elem 41641 withConsumerPort.networking.firewall.allowedUDPPorts;
    interface-schema =
      builtins.deepSeq evaluatedService.result.api.schema true
      &&
        optionNames == [
          "acceptDns"
          "authKeySecretName"
          "enable"
        ];
    unknown-settings-rejected = builtins.all (name: interfaceRejects { ${name} = true; }) [
      "unknownSetting"
      "lifecycle"
      "openFirewall"
      "useRoutingFeatures"
      "authKeyValue"
      "credential"
      "hmacSecretValue"
      "keySecretValue"
      "password"
      "secretValue"
      "token"
    ];
    manifest =
      evaluatedService.manifest.name == moduleId
      && builtins.attrNames evaluatedService.roles == [ "admin-access" ];
    package-authority = enabled.services.tailscale.package == self.packages.${system}.tailscale;
    consumer-package-override-rejected =
      attemptedPackageOverride.services.tailscale.package == self.packages.${system}.tailscale;
    native-routing-policy =
      closedFirewall.services.tailscale.useRoutingFeatures == "none"
      && routingClient.services.tailscale.useRoutingFeatures == "client";
    named-secret-wiring =
      namedSecret.services.tailscale.authKeyFile == "/run/secrets/custom-tailscale-key"
      && builtins.attrNames namedSecret.sops.secrets == [ "custom-tailscale-key" ]
      && namedSecret.sops.secrets.custom-tailscale-key.owner == "root"
      && namedSecret.sops.secrets.custom-tailscale-key.group == "root"
      && namedSecret.sops.secrets.custom-tailscale-key.mode == "0400";
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
  test -x ${readyGate}
  grep -Fq ${lib.escapeShellArg "${caddyStartup.services.tailscale.package}/bin/tailscale"} ${readyGate}
  # Help parsing exercises the authoritative Linux CLI without LocalAPI calls.
  ${caddyStartup.services.tailscale.package}/bin/tailscale wait --help > wait-help 2>&1
  ${caddyStartup.services.tailscale.package}/bin/tailscale status --help > status-help 2>&1
  grep -Fq -- '--timeout' wait-help
  grep -Fq -- '--json' status-help
  grep -Fq -- '--peers' status-help
  echo 'PASS evaluated native Caddy startup composition and Access CLI/package identity'
  echo 'PASS authoritative Linux Tailscale wait/status help syntax'
  echo 'No actual UID, LocalAPI/socket, sandbox, TUN, assembled unit, cgroup or lifetime acceptance'
  mkdir -p "$out"
  cp wait-help status-help "$out/"
''
