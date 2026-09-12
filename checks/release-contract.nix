{ pkgs, root }:
let
  python = pkgs.python3.withPackages (packages: [ packages.pyyaml ]);
  requiredPaths = [
    "CHANGELOG.md"
    "docs/package-authority.md"
    "docs/releases.md"
    "docs/verification.md"
    "scripts/verify.sh"
    "scripts/verify-release.py"
    "scripts/verify-workflows.py"
    "scripts/test-release.py"
    "scripts/test-workflows.py"
    "checks/fixtures/release/pinned.yml"
    "checks/fixtures/release/tag.yml"
    "checks/fixtures/release/major-tag.yml"
    "checks/fixtures/release/main.yml"
    "checks/fixtures/release/latest.yml"
    "checks/fixtures/release/branch.yml"
    "checks/fixtures/release/latest-container.yml"
    "checks/fixtures/release/changelog.md"
    ".github/workflows/ci.yml"
    ".github/workflows/freshness.yml"
    ".github/workflows/release-gate.yml"
    ".github/release-signers"
  ];
  missingPaths = builtins.filter (path: !(builtins.pathExists (root + "/${path}"))) requiredPaths;
in
if missingPaths != [ ] then
  throw "release contract incomplete"
else
  pkgs.runCommand "access-release-contract"
    {
      src = root;
      nativeBuildInputs = [
        pkgs.git
        python
      ];
    }
    ''
      set -eu

      fail() {
        echo "release contract incomplete: $1" >&2
        exit 1
      }

      ${python}/bin/python "$src/scripts/verify-workflows.py" \
        "$src/checks/fixtures/release/pinned.yml"

      for fixture in major-tag tag main latest branch latest-container; do
        if ${python}/bin/python "$src/scripts/verify-workflows.py" \
          "$src/checks/fixtures/release/$fixture.yml"; then
          fail "mutable $fixture fixture was accepted"
        fi
      done

      ${python}/bin/python "$src/scripts/verify-workflows.py" "$src/.github/workflows"

      ${python}/bin/python "$src/scripts/test-workflows.py"

      ${python}/bin/python "$src/scripts/test-release.py"

      ${python}/bin/python "$src/scripts/verify-release.py" \
        --metadata-only \
        --tag v1.2.3 \
        --changelog "$src/checks/fixtures/release/changelog.md"

      for tag in v1 v1.2 v1.2.3-rc1 v01.2.3 v1.02.3 v1.2.03 main latest; do
        if ${python}/bin/python "$src/scripts/verify-release.py" \
          --metadata-only \
          --tag "$tag" \
          --changelog "$src/checks/fixtures/release/changelog.md"; then
          fail "unstable tag $tag was accepted"
        fi
      done

      if ${python}/bin/python "$src/scripts/verify-release.py" \
        --metadata-only \
        --tag v1.2.4 \
        --changelog "$src/checks/fixtures/release/changelog.md"; then
        fail "tag without a matching CHANGELOG heading was accepted"
      fi

      touch "$out"
    ''
