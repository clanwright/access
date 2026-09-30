#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
verify="$root/scripts/verify-release.sh"
fixture="$root/checks/fixtures/release/changelog.md"
bash "$verify" --metadata-only --tag v1.2.3 --changelog "$fixture"
for tag in v1 v1.2 v1.2.3-rc1 v01.2.3 v1.02.3 v1.2.03 main latest v1.2.4; do
  if bash "$verify" --metadata-only --tag "$tag" --changelog "$fixture"; then
    echo "invalid or undocumented tag accepted: $tag" >&2
    exit 1
  fi
done
# Exercise actual Git rejection without creating a signing credential.
repository=$(mktemp -d)
trap 'rm -rf "$repository"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='Release contract test' GIT_COMMITTER_NAME='Release contract test'
export GIT_AUTHOR_EMAIL='release-contract@example.invalid' GIT_COMMITTER_EMAIL='release-contract@example.invalid'
cd "$repository"
git init -q -b main
git -c commit.gpgSign=false commit --allow-empty -qm fixture
mkdir .github
cp "$root/.github/release-signers" .github/release-signers
for kind in lightweight annotated; do
  if [[ "$kind" == lightweight ]]; then
    git -c tag.gpgSign=false tag v1.2.3
  else
    git -c tag.gpgSign=false tag -a v1.2.3 -m unsigned
  fi
  if bash "$verify" --tag v1.2.3 --main-ref main --changelog "$fixture"; then
    echo "unsigned $kind tag accepted" >&2
    exit 1
  fi
  git tag -d v1.2.3
done
