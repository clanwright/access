{ pkgs, root }:
let
  configPath = root + "/renovate.json5";
in
if !(builtins.pathExists configPath) then
  throw "Access inputs are not one weekly group"
else
  pkgs.runCommand "access-renovate-contract"
    {
      src = root;
      nativeBuildInputs = [
        pkgs.gnugrep
        pkgs.renovate
      ];
    }
    ''
      set -eu

      fail() {
        echo "Access inputs are not one weekly group" >&2
        exit 1
      }

      renovate-config-validator "$src/renovate.json5" || fail
      grep -qF 'enabledManagers: ["nix"]' "$src/renovate.json5" || fail
      grep -qF 'ignoreDeps: ["flake-parts"]' "$src/renovate.json5" || fail
      grep -qF 'schedule: ["before 6am on monday"]' "$src/renovate.json5" || fail
      grep -qF 'matchDepNames: ["nixpkgs", "clan-core"]' "$src/renovate.json5" || fail
      grep -qF 'groupName: "access-closure"' "$src/renovate.json5" || fail
      test "$(grep -c 'groupName:' "$src/renovate.json5")" -eq 1 || fail
      test "$(grep -c 'automerge: false' "$src/renovate.json5")" -eq 2 || fail

      touch "$out"
    ''
