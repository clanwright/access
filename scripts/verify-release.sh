#!/usr/bin/env bash
# Stable release metadata and repository-owned SSH trust; no network or signing.
set -euo pipefail
tag='' changelog=CHANGELOG.md main_ref=origin/main metadata_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) tag=${2:?missing tag}; shift 2 ;;
    --changelog) changelog=${2:?missing changelog}; shift 2 ;;
    --main-ref) main_ref=${2:?missing main ref}; shift 2 ;;
    --metadata-only) metadata_only=1; shift ;;
    *) echo 'usage: verify-release.sh --tag vX.Y.Z [--changelog path] [--main-ref ref] [--metadata-only]' >&2; exit 2 ;;
  esac
done
if [[ ! "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "release tag must be an exact stable vX.Y.Z tag: $tag" >&2
  exit 1
fi
version=${tag#v}
if ! grep -Eq "^## \[${version//./\\.}\]( - [0-9]{4}-[0-9]{2}-[0-9]{2})?$" "$changelog"; then
  echo "CHANGELOG has no matching [$version] heading" >&2
  exit 1
fi
[[ "$metadata_only" == 0 ]] || exit 0
root=$(git rev-parse --show-toplevel)
[[ "$(git cat-file -t "refs/tags/$tag")" == tag ]]
git -c gpg.format=ssh \
  -c "gpg.ssh.allowedSignersFile=$root/.github/release-signers" \
  -c gpg.ssh.program=ssh-keygen -c gpg.openpgp.program=false \
  -c gpg.x509.program=false -c gpg.program=false -c gpg.minTrustLevel=fully \
  verify-tag "refs/tags/$tag"
git merge-base --is-ancestor "refs/tags/$tag^{commit}" "$main_ref"
