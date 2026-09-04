{
  lib,
  pkgs,
  root,
  self,
  system,
}:
let
  reportSource = root + "/packages/freshness-report.nix";
  fixtureDirectory = root + "/checks/fixtures/freshness";
  packageNames = [
    "fail2ban"
    "fwknop"
    "tailscale"
  ];
  versions = {
    tailscale = self.packages.${system}.tailscale.version;
    fail2ban = self.packages.${system}.fail2ban.version;
    fwknop = self.packages.${system}.fwknop.version;
  };
  fixture = name: builtins.fromJSON (builtins.readFile (fixtureDirectory + "/${name}.json"));
  fixtures = {
    current = fixture "current";
    lag = fixture "lag";
    unknown = fixture "unknown";
  };
  validEntry =
    name: entry:
    builtins.attrNames entry == [
      "actual"
      "latestObserved"
      "state"
    ]
    && entry.actual == versions.${name}
    && builtins.elem entry.state [
      "current"
      "lag"
      "unknown"
    ]
    && (
      if entry.state == "unknown" then
        entry.latestObserved == null
      else
        builtins.isString entry.latestObserved
    );
  validReport =
    report:
    builtins.attrNames report == [
      "observedAt"
      "packages"
    ]
    && builtins.match "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z" report.observedAt != null
    && builtins.attrNames report.packages == packageNames
    && builtins.all (name: validEntry name report.packages.${name}) packageNames;
  currentContract = builtins.all (
    entry: entry.state == "current" && entry.actual == entry.latestObserved
  ) (builtins.attrValues fixtures.current.packages);
  lagContract = builtins.any (entry: entry.state == "lag" && entry.actual != entry.latestObserved) (
    builtins.attrValues fixtures.lag.packages
  );
  unknownContract = builtins.any (entry: entry.state == "unknown" && entry.latestObserved == null) (
    builtins.attrValues fixtures.unknown.packages
  );
  source = builtins.readFile reportSource;
  clientContract = builtins.all (needle: lib.hasInfix needle source) [
    "tailscale/tailscale/releases/latest"
    "fail2ban/fail2ban/releases/latest"
    "mrash/fwknop/releases/latest"
    "--connect-timeout 5"
    "--max-time 10"
    "--retry 0"
  ];
in
if !(builtins.pathExists reportSource) || !(builtins.pathExists fixtureDirectory) then
  throw "freshness metadata missing"
else if
  !(builtins.all validReport (builtins.attrValues fixtures))
  || !currentContract
  || !lagContract
  || !unknownContract
  || !clientContract
then
  throw "freshness metadata changed"
else
  pkgs.runCommand "access-freshness-contract"
    {
      nativeBuildInputs = [ pkgs.jq ];
    }
    ''
      test -x ${self.packages.${system}.freshness-report}/bin/access-freshness-report
      if printf '%s\n' '{"packages":}' | jq -e . >/dev/null 2>&1; then
        echo "malformed freshness metadata was accepted" >&2
        exit 1
      fi
      touch "$out"
    ''
