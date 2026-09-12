# Releases

Access uses SemVer and releases both bricks and all three packages atomically.
Before `v1`, a known public API break incremented the minor version. Starting
with `v1`, incompatible changes to module IDs, roles, settings, exports, or
secret interfaces require a major release and migration notes.

Branches, `main`, and raw revisions are development state. A release is an
annotated signed `vX.Y.Z` tag whose commit is reachable from protected `main`,
has passed the release gate, and has a matching stable GitHub Release.

The repository-owned [SSH allowed signers policy](../.github/release-signers)
is the release trust root. It admits the `access-release` principal only for
the `git` namespace. `scripts/verify-release.py` rejects unsigned tags and
non-SSH signatures, then asks Git to verify the SSH signature against that
exact policy with fully trusted status. It does not use an ambient
`gpg.ssh.allowedSignersFile`.

Hosted CI keeps platform evidence separate. The Linux job runs the complete
verification gate and builds the Linux package set. The native Apple Silicon
job runs on GitHub's [standard `macos-26` ARM64 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
and builds stunnel, OpenSSH, and the parsed recovery client configuration. The
required `verify` status runs after both platform jobs and fails unless each
reported `success`; its [`always()` condition](https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks#handling-skipped-but-required-checks)
prevents a failed or skipped dependency from turning the aggregate job into a
skipped successful check. The release gate repeats this structure for a stable
tag. These are build, evaluation, and parser checks; they do not establish
consumer runtime acceptance. Governed checkout steps use the triggering
repository and revision and set `persist-credentials: false`; the release job's
later main fetch is read-only against the public repository.

## Manual release procedure

1. Merge the reviewed candidate through protected `main` after CI passes.
2. Copy the matching CHANGELOG section as the proposed release body.
3. Choose the exact stable tag and verify its matching CHANGELOG heading:

   ```bash
   release_tag=vX.Y.Z
   nix develop --no-write-lock-file --command python3 scripts/verify-release.py --metadata-only --tag "$release_tag"
   ```

4. In the owner's terminal, create and push the SSH-signed tag with
   `git -c gpg.format=ssh tag -s -a "$release_tag" -m "Access $release_tag" <release-commit>`
   and `git push origin "$release_tag"`. Signing key selection and custody stay
   outside the repository.

5. Wait for the required aggregate `verify` job in `release-gate.yml` to pass.
   Its Linux dependency verifies the exact stable tag, matching CHANGELOG
   heading, annotation, trusted SSH signature, and main ancestry; reruns the
   complete gate; and produces `access-freshness.json`. Its native ARM64 Darwin
   dependency builds the published Darwin recovery dependencies and parses the
   client configuration. The aggregate fails unless both dependencies succeed.
   The workflow never publishes a release.
6. Manually create a non-draft, non-prerelease GitHub Release for the exact tag,
   paste the unchanged CHANGELOG section, and attach `access-freshness.json`.
7. Verify the tag signature, main ancestry, stable Release metadata, and
   attached artifact before any consumer update.

Publishing Access and updating a consumer are separate reviewed transactions.
Neither merge nor release authorizes deployment.
