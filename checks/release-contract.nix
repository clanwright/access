{ pkgs, root }:
let
  requiredPaths = [
    "CHANGELOG.md"
    "docs/package-authority.md"
    "docs/releases.md"
    "docs/verification.md"
    ".github/workflows/ci.yml"
    ".github/workflows/freshness.yml"
    ".github/workflows/release-gate.yml"
  ];
  missingPaths = builtins.filter (path: !(builtins.pathExists (root + "/${path}"))) requiredPaths;
in
if missingPaths != [ ] then
  throw "release contract incomplete"
else
  pkgs.runCommand "access-release-contract"
    {
      src = root;
      nativeBuildInputs = [ pkgs.gnugrep ];
    }
    ''
      set -eu

      grep -qF 'tags: ["v*"]' "$src/.github/workflows/release-gate.yml"
      grep -qF 'fetch-depth: 0' "$src/.github/workflows/release-gate.yml"
      grep -qF 'git merge-base --is-ancestor' "$src/.github/workflows/release-gate.yml"
      grep -qF 'nix flake check --all-systems --no-write-lock-file' "$src/.github/workflows/ci.yml"
      grep -qF 'nix flake check --all-systems --no-write-lock-file' "$src/.github/workflows/release-gate.yml"
      grep -qF 'workflow_dispatch:' "$src/.github/workflows/freshness.yml"
      grep -qF 'access-freshness.json' "$src/.github/workflows/freshness.yml"
      grep -qF 'access-freshness.json' "$src/.github/workflows/release-gate.yml"
      grep -qF 'git tag -s -a v0.2.0' "$src/docs/releases.md"
      grep -qF '## [0.1.0]' "$src/CHANGELOG.md"

      if grep -RE 'uses: [^ ]+@(v[0-9]+|main|master)([[:space:]]|$)' "$src/.github/workflows"; then
        echo "release contract incomplete: action is not commit-pinned" >&2
        exit 1
      fi

      if grep -RE 'gh release|create-release|action-gh-release|releases:[[:space:]]*write' "$src/.github/workflows"; then
        echo "release contract incomplete: workflow may publish a release" >&2
        exit 1
      fi

      touch "$out"
    ''
