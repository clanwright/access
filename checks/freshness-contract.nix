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
    "openssh"
    "stunnel"
    "tailscale"
  ];
  versions = {
    tailscale = self.packages.${system}.tailscale.version;
    openssh = self.packages.${system}.openssh.version;
    stunnel = self.packages.${system}.stunnel.version;
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
    "stunnel.org/versions.html"
    "cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/"
    "--connect-timeout 5"
    "--max-time 10"
    "--retry 0"
  ];
  mockCurl = pkgs.writeShellScriptBin "curl" ''
    set -eu

    url="''${!#}"
    if [ -n "''${FRESHNESS_CURL_LOG:-}" ]; then
      printf '%s\n' "$url" >> "$FRESHNESS_CURL_LOG"
    fi

    case "''${FRESHNESS_FIXTURE:?missing freshness fixture}:$url" in
      current:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v${versions.tailscale}","draft":false,"prerelease":false}' ;;
      current:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version 5.9 released' 'Version ${versions.stunnel} released' 'Version 99.99 available' ;;
      current:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'openssh-10.4p1.tar.gz' 'openssh-${versions.openssh}.tar.gz' ;;
      lag:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v1.104.0","draft":false,"prerelease":false}' ;;
      lag:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version 5.9 released' 'Version 5.80 released' 'Version 5.81 released' 'Version 99.99 available' ;;
      lag:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'openssh-10.4p1.tar.gz' 'openssh-10.5p1.tar.gz' 'openssh-10.6p1.tar.gz' ;;
      unknown:*) exit 22 ;;
      malformed-json:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":' ;;
      malformed-stunnel:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v${versions.tailscale}","draft":false,"prerelease":false}' ;;
      malformed-stunnel:https://www.stunnel.org/versions.html)
        printf '%s\n' 'no release version here' ;;
      malformed-openssh:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v${versions.tailscale}","draft":false,"prerelease":false}' ;;
      malformed-openssh:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version ${versions.stunnel} released' ;;
      malformed-openssh:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'not an OpenSSH portable archive' ;;
      *)
        echo "unexpected freshness endpoint: $url" >&2
        exit 64 ;;
    esac
  '';
  reportUnderTest = import reportSource {
    pkgs = pkgs // {
      curl = mockCurl;
    };
    inherit versions;
  };
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
      nativeBuildInputs = [
        pkgs.jq
        reportUnderTest
      ];
    }
    ''
      test -x ${self.packages.${system}.freshness-report}/bin/access-freshness-report
      if printf '%s\n' '{"packages":}' | jq -e . >/dev/null 2>&1; then
        echo "malformed freshness metadata was accepted" >&2
        exit 1
      fi

      run_report() {
        fixture="$1"
        result="$TMPDIR/$fixture/report.json"
        mkdir -p "$(dirname "$result")"
        FRESHNESS_FIXTURE="$fixture" FRESHNESS_CURL_LOG="$TMPDIR/$fixture/curl.log" \
          ${reportUnderTest}/bin/access-freshness-report --output "$result"
      }

      assert_all_endpoints() {
        log="$1"
        test "$(wc -l < "$log")" -eq 3
        grep -qxF 'https://api.github.com/repos/tailscale/tailscale/releases/latest' "$log"
        grep -qxF 'https://www.stunnel.org/versions.html' "$log"
        grep -qxF 'https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/' "$log"
      }

      run_report current
      assert_all_endpoints "$TMPDIR/current/curl.log"
      jq -e \
        --arg tailscale '${versions.tailscale}' \
        --arg stunnel '${versions.stunnel}' \
        --arg openssh '${versions.openssh}' '
          .packages == {
            tailscale: {actual: $tailscale, latestObserved: $tailscale, state: "current"},
            stunnel: {actual: $stunnel, latestObserved: $stunnel, state: "current"},
            openssh: {actual: $openssh, latestObserved: $openssh, state: "current"}
          }
        ' "$TMPDIR/current/report.json" >/dev/null

      run_report lag
      assert_all_endpoints "$TMPDIR/lag/curl.log"
      jq -e '
        .packages.tailscale == {actual: "${versions.tailscale}", latestObserved: "1.104.0", state: "lag"}
        and .packages.stunnel == {actual: "${versions.stunnel}", latestObserved: "5.81", state: "lag"}
        and .packages.openssh == {actual: "${versions.openssh}", latestObserved: "10.6p1", state: "lag"}
      ' "$TMPDIR/lag/report.json" >/dev/null

      run_report unknown
      assert_all_endpoints "$TMPDIR/unknown/curl.log"
      jq -e '[.packages[] | .state == "unknown" and .latestObserved == null] | all' \
        "$TMPDIR/unknown/report.json" >/dev/null

      for fixture in malformed-json malformed-stunnel malformed-openssh; do
        result="$TMPDIR/$fixture/report.json"
        mkdir -p "$(dirname "$result")"
        if FRESHNESS_FIXTURE="$fixture" FRESHNESS_CURL_LOG="$TMPDIR/$fixture/curl.log" \
          ${reportUnderTest}/bin/access-freshness-report --output "$result"; then
          echo "malformed $fixture upstream response was accepted" >&2
          exit 1
        fi
        test ! -e "$result"
      done
      touch "$out"
    ''
