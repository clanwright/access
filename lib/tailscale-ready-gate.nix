{
  pkgs,
  tailscale,
  ipv4,
  interface,
  # Private fixture seam: the public export fixes the production deadline.
  deadline ? "35s",
}:
let
  lib = pkgs.lib;
  validInput = value: builtins.isString value && value != "";
  stages = ''
    fail() {
      echo "tailscale readiness: $1 failed" >&2
      exit 1
    }
    ${tailscale}/bin/tailscale wait --timeout=30s > /dev/null 2>&1 || fail wait
    status=$(${tailscale}/bin/tailscale status --json --peers=false 2>/dev/null) || fail status
    printf '%s\n' "$status" | ${pkgs.jq}/bin/jq -e -s \
      --arg ipv4 ${lib.escapeShellArg ipv4} '
        length == 1 and (.[0] |
          .TUN == true and .BackendState == "Running" and
          ((.TailscaleIPs // []) | type == "array" and index($ipv4) != null))
      ' > /dev/null 2>&1 || fail status
    addresses=$(${pkgs.iproute2}/bin/ip -j -4 addr show dev ${lib.escapeShellArg interface} 2>/dev/null) \
      || fail address
    printf '%s\n' "$addresses" | ${pkgs.jq}/bin/jq -e -s \
      --arg ipv4 ${lib.escapeShellArg ipv4} \
      --arg interface ${lib.escapeShellArg interface} '
        length == 1 and (.[0] | type == "array" and any(.[];
          .ifname == $interface and
          (.flags | type == "array" and index("UP") != null) and
          (.addr_info | type == "array" and any(.[];
            .family == "inet" and .local == $ipv4))))
      ' > /dev/null 2>&1 || fail address
  '';
in
if !pkgs.stdenv.hostPlatform.isLinux then
  throw "tailscaleReadyGate requires Linux"
else if !validInput ipv4 then
  throw "tailscaleReadyGate requires a non-empty ipv4 string"
else if !validInput interface then
  throw "tailscaleReadyGate requires a non-empty interface string"
else
  pkgs.writeShellScript "tailscale-ready-gate" ''
    # Native timeout sends TERM to the process group; kill-after escalates only
    # while the monitored shell remains alive. The consumer's systemd unit must
    # clean up its cgroup, including any TERM-resistant descendants.
    # Its deadline diagnostic contains only the shell's Nix-store path.
    exec ${pkgs.coreutils}/bin/timeout --verbose --kill-after=2s \
      ${lib.escapeShellArg deadline} ${pkgs.runtimeShell} -euo pipefail -c ${lib.escapeShellArg stages}
  ''
