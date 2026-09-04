{ pkgs, root }:
let
  requiredPaths = [
    "AGENTS.md"
    "LICENSE"
    "README.md"
    ".github/CODEOWNERS"
    ".github/PULL_REQUEST_TEMPLATE.md"
  ];
  missingPaths = builtins.filter (path: !(builtins.pathExists (root + "/${path}"))) requiredPaths;
in
if missingPaths != [ ] then
  throw "Access repository contract is incomplete: missing ${builtins.concatStringsSep ", " missingPaths}"
else
  pkgs.runCommand "access-repository-policy"
    {
      src = root;
      nativeBuildInputs = [ pkgs.findutils ];
    }
    ''
      set -eu

      for forbidden in sops vars secrets deploy provider backups restore; do
        if [ -e "$src/$forbidden" ]; then
          echo "Forbidden Access ownership surface: $forbidden" >&2
          exit 1
        fi
      done

      if find "$src" -type f \( \
        -name '.env' -o \
        -name '.env.*' -o \
        -name '*.key' -o \
        -name '*.pem' -o \
        -name '*.p12' \
      \) -print -quit | grep . >/dev/null; then
        echo "Credential-shaped file found in Access source" >&2
        exit 1
      fi

      touch "$out"
    ''
