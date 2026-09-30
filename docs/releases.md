# Releases

Access uses SemVer and releases both Clan modules and all three application
packages atomically. Future incompatible changes to module IDs, roles, settings,
exports, or secret interfaces require a major release and migration guidance.
Package and transitive closure changes are release changes even when primary
version strings stay the same.

A completed release is an annotated, SSH-signed `vX.Y.Z` tag whose commit is
reachable from protected `main`, passes the tag gate, and has a matching stable
GitHub Release. Branches and raw revisions are development state.

The repository-owned [allowed signers](../.github/release-signers) are the trust
root for the `access-release` principal in the `git` namespace.
`scripts/verify-release.sh` uses native Git signature verification with this
policy, rejects unsigned or non-SSH tags, requires fully trusted status, and
uses `git merge-base --is-ancestor` for main ancestry. Signing key selection and
custody remain outside Access.

## Manual release procedure

1. Merge the reviewed candidate through protected `main` after CI passes.
2. Choose the stable tag and validate its matching CHANGELOG heading:

   ```bash
   release_tag=vX.Y.Z
   nix develop --no-write-lock-file --command bash scripts/verify-release.sh \
     --metadata-only --tag "$release_tag"
   ```

3. Manually create and push the signed annotated tag using the existing signing
   identity:

   ```bash
   git -c gpg.format=ssh tag -s -a "$release_tag" -m "Access $release_tag" <release-commit>
   git push origin "$release_tag"
   ```

4. Wait for the required `verify` status in `release-gate.yml`. The Linux job
   verifies tag metadata, signature and main ancestry and runs the complete
   gate. The native ARM64 Darwin job builds the recovery packages and parses
   the documented client configuration. The aggregate requires both jobs to
   succeed; failed, skipped, or cancelled dependencies cannot pass it.
5. Manually create a non-draft, non-prerelease GitHub Release for the exact tag,
   using the unchanged matching CHANGELOG section as its body. This section
   describes current capabilities, contracts and their reasons; it contains no
   generated history or development chronology.
6. Verify the signature, ancestry, successful tag gate, and stable Release
   metadata before any consumer update.

Hosted workflows are read-only and secret-free. Checkout uses the triggering
repository/revision with `persist-credentials: false`; fetching public main for
ancestry is read-only. CI never merges, signs, publishes, deploys, or updates a
consumer lock. Workflow validation uses actionlint and offline zizmor; reviewers
must also check exact jobs, commands, aggregation and secret contexts.

Renovate proposes dependency updates; reviewers build and verify each candidate
before release. Publishing, consumer input migration, and deployment are
separate owner-approved transactions. Runtime trust requires
[PREDEPLOY acceptance](verification.md#predeploy-acceptance).
