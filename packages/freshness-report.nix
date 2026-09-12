{
  pkgs,
  versions,
  curl ? pkgs.curl,
}:
pkgs.writeShellApplication {
  name = "access-freshness-report";
  runtimeInputs = [
    pkgs.coreutils
    curl
    pkgs.jq
    pkgs.gnugrep
    pkgs.gnused
  ];
  text = ''
    set -euo pipefail

    output=""
    if [ "$#" -eq 2 ] && [ "$1" = "--output" ]; then
      output="$2"
    else
      echo "usage: access-freshness-report --output <path>" >&2
      exit 2
    fi

    if [ -z "$output" ] || [ ! -d "$(dirname "$output")" ]; then
      echo "freshness output directory does not exist" >&2
      exit 2
    fi

    observed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    report="$(mktemp)"
    output_tmp="$(mktemp "$output.tmp.XXXXXX")"
    trap 'rm -f "$report" "$output_tmp"' EXIT

    jq -n --arg observedAt "$observed_at" '{observedAt: $observedAt, packages: {}}' > "$report"

    update_report() {
      local name="$1"
      local actual="$2"
      local state="$3"
      local latest="$4"
      local next
      next="$(mktemp)"
      if [ "$latest" = "__NULL__" ]; then
        jq --arg name "$name" --arg actual "$actual" --arg state "$state" \
          '.packages[$name] = {actual: $actual, latestObserved: null, state: $state}' \
          "$report" > "$next"
      else
        jq --arg name "$name" --arg actual "$actual" --arg latest "$latest" --arg state "$state" \
          '.packages[$name] = {actual: $actual, latestObserved: $latest, state: $state}' \
          "$report" > "$next"
      fi
      mv "$next" "$report"
    }

    fetch_release() {
      local name="$1"
      local url="$2"
      local -a headers=()
      if [ "$name" = tailscale ]; then
        headers=(--header 'Accept: application/vnd.github+json')
      fi
      curl --disable --fail --silent --show-error --location \
        --connect-timeout 5 --max-time 10 --retry 0 \
        "''${headers[@]}" --header 'User-Agent: clanwright-access-freshness' "$url" 2>/dev/null
    }

    parse_tailscale() {
      local response="$1"
      local tag
      local latest
      if ! printf '%s' "$response" | jq -e \
        'type == "object" and (.tag_name | type == "string") and (.draft | type == "boolean") and (.prerelease | type == "boolean")' \
        >/dev/null; then
        return 1
      fi
      if [ "$(printf '%s' "$response" | jq -r '.draft or .prerelease')" = "true" ]; then
        printf '%s' __UNKNOWN__
        return
      fi
      tag="$(printf '%s' "$response" | jq -r '.tag_name')"
      latest="''${tag#v}"
      printf '%s' "$latest" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' || return 1
      printf '%s' "$latest"
    }

    parse_stunnel() {
      printf '%s' "$1" | { grep -oE 'Version [0-9]+\.[0-9]+ released' || true; } |
        sed -E 's/^Version //; s/ released$//' | sort -Vu | tail -n 1
    }

    parse_openssh() {
      printf '%s' "$1" | { grep -oE 'openssh-[0-9]+\.[0-9]+p[0-9]+\.tar\.gz' || true; } |
        sed -E 's/^openssh-//; s/\.tar\.gz$//' | sort -Vu | tail -n 1
    }

    release_state() {
      local actual="$1"
      local latest="$2"
      local newest
      newest="$(printf '%s\n%s\n' "$actual" "$latest" | sort -V | tail -n 1)"
      if [ "$newest" = "$actual" ]; then printf '%s' current; else printf '%s' lag; fi
    }

    probe() {
      local name="$1"
      local actual="$2"
      local url="$3"
      local response
      local parser
      local latest
      local state
      if ! response="$(fetch_release "$name" "$url")"; then
        update_report "$name" "$actual" unknown __NULL__
        return
      fi
      case "$name" in
        tailscale) parser=parse_tailscale ;;
        stunnel) parser=parse_stunnel ;;
        openssh) parser=parse_openssh ;;
        *) exit 2 ;;
      esac
      if ! latest="$($parser "$response")" || [ -z "$latest" ]; then
        echo "malformed release metadata for $name" >&2
        exit 1
      fi
      if [ "$latest" = __UNKNOWN__ ]; then
        update_report "$name" "$actual" unknown __NULL__
        return
      fi
      state="$(release_state "$actual" "$latest")"
      update_report "$name" "$actual" "$state" "$latest"
    }

    probe tailscale ${versions.tailscale} https://api.github.com/repos/tailscale/tailscale/releases/latest
    probe stunnel ${versions.stunnel} https://www.stunnel.org/versions.html
    probe openssh ${versions.openssh} https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/

    if ! jq -e '
      (.observedAt | type == "string") and
      (.packages | keys == ["openssh", "stunnel", "tailscale"]) and
      ([.packages[] |
        (.actual | type == "string") and
        ((.latestObserved | type == "string") or .latestObserved == null) and
        (.state == "current" or .state == "lag" or .state == "unknown") and
        (if .state == "unknown" then .latestObserved == null else (.latestObserved | type == "string") end)
      ] | all)
    ' "$report" >/dev/null; then
      echo "malformed freshness report" >&2
      exit 1
    fi

    jq . "$report" > "$output_tmp"
    mv "$output_tmp" "$output"
    trap - EXIT
    rm -f "$report"
  '';
}
