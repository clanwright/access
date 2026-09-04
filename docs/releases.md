# Releases

Access uses SemVer and releases all three bricks atomically. During `0.x`, a
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
3. In the owner's terminal, create and push the signed tag:

   ```bash
   git tag -s -a v0.1.0 -m "Access v0.1.0" <release-commit>
   git push origin v0.1.0
   ```

4. Wait for `release-gate.yml` to pass. It verifies main ancestry, reruns the
   complete gate, and produces `access-freshness.json`; it never publishes a
   release.
5. Manually create a non-draft, non-prerelease GitHub Release for the exact tag,
   paste the unchanged CHANGELOG section, and attach `access-freshness.json`.
6. Verify the tag signature, main ancestry, stable Release metadata, and
   attached artifact before any consumer update.

Publishing Access and updating a consumer are separate reviewed transactions.
Neither merge nor release authorizes deployment.
