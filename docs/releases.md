# Releases

Access uses SemVer and releases both bricks and all three packages atomically. During `0.x`, a
known public API break increments the minor version; patches are intended to be
compatible. Every break names the affected module IDs, roles, settings,
exports, or secret interfaces and includes migration notes. After `v1`, those
surfaces require a major release. The owner will declare `v1` only after all
planned domains have been extracted and exercised.

Branches, `main`, and raw revisions are development state. A release is an
annotated signed `vX.Y.Z` tag whose commit is reachable from protected `main`,
has passed the release gate, and has a matching stable GitHub Release.

## Manual release procedure

1. Merge the reviewed candidate through protected `main` after CI passes.
2. Copy the matching CHANGELOG section as the proposed release body.
3. Choose the exact stable tag and verify its matching CHANGELOG heading:

   ```bash
   release_tag=vX.Y.Z
   nix develop --no-write-lock-file --command python3 scripts/verify-release.py --metadata-only --tag "$release_tag"
   ```

4. In the owner's terminal, create and push the signed tag with
   `git tag -s -a "$release_tag" -m "Access $release_tag" <release-commit>` and
   `git push origin "$release_tag"`.

5. Wait for `release-gate.yml` to pass. It verifies the exact stable tag,
   matching CHANGELOG heading, annotation, and main ancestry; reruns the
   complete gate, and produces `access-freshness.json`; it never publishes a
   release.
6. Manually create a non-draft, non-prerelease GitHub Release for the exact tag,
   paste the unchanged CHANGELOG section, and attach `access-freshness.json`.
7. Verify the tag signature, main ancestry, stable Release metadata, and
   attached artifact before any consumer update.

Publishing Access and updating a consumer are separate reviewed transactions.
Neither merge nor release authorizes deployment.
