#!/usr/bin/env python3
"""Validate stable release metadata and, by default, local Git provenance."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


STABLE_TAG = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
SSH_SIGNATURE_MARKER = "-----BEGIN SSH SIGNATURE-----"
SSH_SIGNATURE_END = "-----END SSH SIGNATURE-----"
NON_SSH_SIGNATURE_MARKERS = (
    "-----BEGIN PGP SIGNATURE-----",
    "-----BEGIN SIGNED MESSAGE-----",
)
SIGNER_POLICY_LINE = re.compile(
    r'access-release namespaces="git" '
    r'(?:ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(?:256|384|521)) '
    r"[A-Za-z0-9+/]+={0,3}\Z"
)


def git(*args: str, cwd: pathlib.Path | None = None) -> str:
    return subprocess.run(
        ["git", *args], check=True, cwd=cwd, text=True, stdout=subprocess.PIPE
    ).stdout.strip()


def repository_root() -> pathlib.Path:
    return pathlib.Path(git("rev-parse", "--show-toplevel"))


def validate_signer_policy(path: pathlib.Path) -> None:
    try:
        lines = [
            line.strip()
            for line in path.read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
    except OSError as error:
        raise ValueError(f"release signer policy is missing: {path}") from error
    if not lines or any(SIGNER_POLICY_LINE.fullmatch(line) is None for line in lines):
        raise ValueError(
            "release signer policy must contain only access-release SSH keys "
            'restricted to namespaces="git"'
        )


def validate_ssh_tag_signature(tag: str, tag_object: str) -> None:
    if (
        tag_object.count(SSH_SIGNATURE_MARKER) != 1
        or not tag_object.endswith(SSH_SIGNATURE_END)
        or any(marker in tag_object for marker in NON_SSH_SIGNATURE_MARKERS)
    ):
        raise ValueError(f"release tag does not contain an SSH signature: {tag}")


def verify_metadata(tag: str, changelog: pathlib.Path) -> None:
    match = STABLE_TAG.fullmatch(tag)
    if match is None:
        raise ValueError(f"release tag must be an exact stable vX.Y.Z tag: {tag}")
    version = tag.removeprefix("v")
    heading = re.compile(rf"^## \[{re.escape(version)}\](?: - [0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})?$", re.MULTILINE)
    if heading.search(changelog.read_text()) is None:
        raise ValueError(f"CHANGELOG.md has no matching [{version}] heading")


def verify_provenance(tag: str, main_ref: str) -> None:
    root = repository_root()
    allowed_signers = root / ".github" / "release-signers"
    validate_signer_policy(allowed_signers)
    if git("cat-file", "-t", tag, cwd=root) != "tag":
        raise ValueError(f"release ref is not an annotated tag: {tag}")
    tag_object = git("cat-file", "tag", tag, cwd=root)
    validate_ssh_tag_signature(tag, tag_object)
    subprocess.run(
        [
            "git",
            "-c",
            "gpg.format=ssh",
            "-c",
            f"gpg.ssh.allowedSignersFile={allowed_signers}",
            "-c",
            "gpg.ssh.program=ssh-keygen",
            "-c",
            "gpg.openpgp.program=false",
            "-c",
            "gpg.x509.program=false",
            "-c",
            "gpg.program=false",
            "-c",
            "gpg.minTrustLevel=fully",
            "verify-tag",
            tag,
        ],
        check=True,
        cwd=root,
    )
    release_commit = git("rev-list", "-n", "1", tag, cwd=root)
    subprocess.run(
        ["git", "merge-base", "--is-ancestor", release_commit, main_ref],
        check=True,
        cwd=root,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--changelog", type=pathlib.Path, default=pathlib.Path("CHANGELOG.md"))
    parser.add_argument("--main-ref", default="origin/main")
    parser.add_argument("--metadata-only", action="store_true")
    args = parser.parse_args()
    try:
        verify_metadata(args.tag, args.changelog)
        if not args.metadata_only:
            verify_provenance(args.tag, args.main_ref)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
