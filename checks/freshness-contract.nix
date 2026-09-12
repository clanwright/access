{
  lib,
  pkgs,
  root,
  self,
  system,
}:
let
  productionVersions = {
    tailscale = self.packages.${system}.tailscale.version;
    openssh = self.packages.${system}.openssh.version;
    stunnel = self.packages.${system}.stunnel.version;
  };
  testVersions = {
    tailscale = "1.2.3";
    openssh = "9.8p1";
    stunnel = "5.70";
  };
  mockCurl = pkgs.writeShellScriptBin "curl" ''
    set -eu

    if [ "''${1:-}" != --disable ]; then
      echo "curl configuration must be disabled by the first argument" >&2
      exit 65
    fi
    shift

    url=""
    fail=0
    silent=0
    show_error=0
    location=0
    connect_timeout=""
    max_time=""
    retry=""
    user_agent=0
    github_accept=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --fail) fail=$((fail + 1)); shift ;;
        --silent) silent=$((silent + 1)); shift ;;
        --show-error) show_error=$((show_error + 1)); shift ;;
        --location) location=$((location + 1)); shift ;;
        --connect-timeout) connect_timeout="''${2:?}"; shift 2 ;;
        --max-time) max_time="''${2:?}"; shift 2 ;;
        --retry) retry="''${2:?}"; shift 2 ;;
        --header)
          case "''${2:?}" in
            'User-Agent: clanwright-access-freshness') user_agent=$((user_agent + 1)) ;;
            'Accept: application/vnd.github+json') github_accept=$((github_accept + 1)) ;;
            Authorization:*|Proxy-Authorization:*)
              echo "authenticated freshness request" >&2
              exit 65 ;;
            *)
              echo "unexpected freshness header: $2" >&2
              exit 65 ;;
          esac
          shift 2 ;;
        --user|--netrc|--netrc-file|--oauth2-bearer|--cookie|--cookie-jar|--data|--request)
          echo "authenticated or non-GET freshness request: $1" >&2
          exit 65 ;;
        https://*)
          if [ -n "$url" ]; then
            echo "multiple freshness endpoints in one request" >&2
            exit 65
          fi
          url="$1"
          shift ;;
        *)
          echo "unexpected curl argument: $1" >&2
          exit 65 ;;
      esac
    done

    if [ "$fail" -ne 1 ] || [ "$silent" -ne 1 ] || [ "$show_error" -ne 1 ] \
      || [ "$location" -ne 1 ] || [ "$connect_timeout" != 5 ] \
      || [ "$max_time" != 10 ] || [ "$retry" != 0 ] || [ "$user_agent" -ne 1 ]; then
      echo "freshness request is not bounded as required" >&2
      exit 65
    fi
    case "$url" in
      https://api.github.com/repos/tailscale/tailscale/releases/latest)
        test "$github_accept" -eq 1 ;;
      https://www.stunnel.org/versions.html|https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        test "$github_accept" -eq 0 ;;
      *)
        echo "unexpected freshness endpoint: $url" >&2
        exit 64 ;;
    esac
    if [ -n "''${FRESHNESS_CURL_LOG:-}" ]; then
      printf '%s\n' "$url" >> "$FRESHNESS_CURL_LOG"
    fi

    case "''${FRESHNESS_FIXTURE:?missing freshness fixture}:$url" in
      current:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v${testVersions.tailscale}","draft":false,"prerelease":false}' ;;
      current:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version 5.9 released' 'Version ${testVersions.stunnel} released' 'Version 99.99 available' ;;
      current:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'openssh-9.7p1.tar.gz' 'openssh-${testVersions.openssh}.tar.gz' ;;
      lag:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v1.2.4","draft":false,"prerelease":false}' ;;
      lag:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version 5.9 released' 'Version 5.70 released' 'Version 5.71 released' 'Version 99.99 available' ;;
      lag:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'openssh-9.7p1.tar.gz' 'openssh-9.8p1.tar.gz' 'openssh-9.9p1.tar.gz' ;;
      ahead:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v1.2.2","draft":false,"prerelease":false}' ;;
      ahead:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version 5.69 released' ;;
      ahead:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'openssh-9.7p1.tar.gz' ;;
      prerelease:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v1.2.4","draft":false,"prerelease":true}' ;;
      prerelease:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version ${testVersions.stunnel} released' ;;
      prerelease:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'openssh-${testVersions.openssh}.tar.gz' ;;
      unknown:*) exit 22 ;;
      malformed-json:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":' ;;
      malformed-stunnel:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v${testVersions.tailscale}","draft":false,"prerelease":false}' ;;
      malformed-stunnel:https://www.stunnel.org/versions.html)
        printf '%s\n' 'no release version here' ;;
      malformed-openssh:https://api.github.com/repos/tailscale/tailscale/releases/latest)
        printf '%s' '{"tag_name":"v${testVersions.tailscale}","draft":false,"prerelease":false}' ;;
      malformed-openssh:https://www.stunnel.org/versions.html)
        printf '%s\n' 'Version ${testVersions.stunnel} released' ;;
      malformed-openssh:https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/)
        printf '%s\n' 'not an OpenSSH portable archive' ;;
      *)
        echo "unexpected freshness endpoint: $url" >&2
        exit 64 ;;
    esac
  '';
  reportUnderTest = import ../packages/freshness-report.nix {
    inherit pkgs;
    curl = mockCurl;
    versions = testVersions;
  };
in
pkgs.runCommand "access-freshness-contract"
  {
    nativeBuildInputs = [
      pkgs.jq
      reportUnderTest
    ];
  }
  ''
    production_report=${self.packages.${system}.freshness-report}/bin/access-freshness-report
    test -x "$production_report"
    grep -qF 'probe tailscale ${productionVersions.tailscale} https://api.github.com/repos/tailscale/tailscale/releases/latest' "$production_report"
    grep -qF 'probe stunnel ${productionVersions.stunnel} https://www.stunnel.org/versions.html' "$production_report"
    grep -qF 'probe openssh ${productionVersions.openssh} https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/' "$production_report"
    run_report() {
      fixture="$1"
      result="$TMPDIR/$fixture/report.json"
      mkdir -p "$(dirname "$result")"
      FRESHNESS_FIXTURE="$fixture" FRESHNESS_CURL_LOG="$TMPDIR/$fixture/curl.log" \
        ${reportUnderTest}/bin/access-freshness-report --output "$result"
      assert_all_endpoints "$TMPDIR/$fixture/curl.log"
      assert_report_contract "$result"
    }

    assert_all_endpoints() {
      log="$1"
      test "$(wc -l < "$log")" -eq 3
      grep -qxF 'https://api.github.com/repos/tailscale/tailscale/releases/latest' "$log"
      grep -qxF 'https://www.stunnel.org/versions.html' "$log"
      grep -qxF 'https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/' "$log"
    }

    assert_report_contract() {
      report="$1"
      jq -e \
        --arg tailscale '${testVersions.tailscale}' \
        --arg stunnel '${testVersions.stunnel}' \
        --arg openssh '${testVersions.openssh}' '
          (keys == ["observedAt", "packages"])
          and (.observedAt | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
          and (.packages | keys == ["openssh", "stunnel", "tailscale"])
          and (.packages.tailscale.actual == $tailscale)
          and (.packages.stunnel.actual == $stunnel)
          and (.packages.openssh.actual == $openssh)
          and ([.packages[] |
            (keys == ["actual", "latestObserved", "state"])
            and (.actual | type == "string")
            and (.state == "current" or .state == "lag" or .state == "unknown")
            and (if .state == "unknown"
                 then .latestObserved == null
                 else (.latestObserved | type == "string")
                 end)
          ] | all)
        ' "$report" >/dev/null
    }

    run_report current
    jq -e \
      --arg tailscale '${testVersions.tailscale}' \
      --arg stunnel '${testVersions.stunnel}' \
      --arg openssh '${testVersions.openssh}' '
        .packages == {
          tailscale: {actual: $tailscale, latestObserved: $tailscale, state: "current"},
          stunnel: {actual: $stunnel, latestObserved: $stunnel, state: "current"},
          openssh: {actual: $openssh, latestObserved: $openssh, state: "current"}
        }
      ' "$TMPDIR/current/report.json" >/dev/null

    run_report lag
    jq -e '
      .packages.tailscale == {actual: "${testVersions.tailscale}", latestObserved: "1.2.4", state: "lag"}
      and .packages.stunnel == {actual: "${testVersions.stunnel}", latestObserved: "5.71", state: "lag"}
      and .packages.openssh == {actual: "${testVersions.openssh}", latestObserved: "9.9p1", state: "lag"}
    ' "$TMPDIR/lag/report.json" >/dev/null

    run_report unknown
    jq -e '[.packages[] | .state == "unknown" and .latestObserved == null] | all' \
      "$TMPDIR/unknown/report.json" >/dev/null

    run_report ahead
    jq -e '[.packages[] | .state == "current" and (.latestObserved != .actual)] | all' \
      "$TMPDIR/ahead/report.json" >/dev/null

    run_report prerelease
    jq -e '
      .packages.tailscale == {actual: "${testVersions.tailscale}", latestObserved: null, state: "unknown"}
      and .packages.stunnel.state == "current"
      and .packages.openssh.state == "current"
    ' "$TMPDIR/prerelease/report.json" >/dev/null

    for fixture in malformed-json malformed-stunnel malformed-openssh; do
      result="$TMPDIR/$fixture/report.json"
      mkdir -p "$(dirname "$result")"
      printf '%s\n' preserved-output > "$result"
      set +e
      FRESHNESS_FIXTURE="$fixture" FRESHNESS_CURL_LOG="$TMPDIR/$fixture/curl.log" \
        ${reportUnderTest}/bin/access-freshness-report --output "$result" \
        2>"$TMPDIR/$fixture/stderr.log"
      status="$?"
      set -e
      test "$status" -eq 1
      grep -qF 'malformed release metadata' "$TMPDIR/$fixture/stderr.log"
      grep -qxF preserved-output "$result"
    done

    test "$(wc -l < "$TMPDIR/malformed-json/curl.log")" -eq 1
    test "$(wc -l < "$TMPDIR/malformed-stunnel/curl.log")" -eq 2
    test "$(wc -l < "$TMPDIR/malformed-openssh/curl.log")" -eq 3

    touch "$out"
  ''
