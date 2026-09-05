#!/usr/bin/env python3
"""Validate stable release metadata and, by default, local Git provenance."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


STABLE_TAG = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], check=True, text=True, stdout=subprocess.PIPE
    ).stdout.strip()


def verify_metadata(tag: str, changelog: pathlib.Path) -> None:
    match = STABLE_TAG.fullmatch(tag)
    if match is None:
        raise ValueError(f"release tag must be an exact stable vX.Y.Z tag: {tag}")
    version = tag.removeprefix("v")
    heading = re.compile(rf"^## \[{re.escape(version)}\](?: - [0-9]{{4}}-[0-9]{{2}}-[0-9]{{2}})?$", re.MULTILINE)
    if heading.search(changelog.read_text()) is None:
        raise ValueError(f"CHANGELOG.md has no matching [{version}] heading")


def verify_provenance(tag: str, main_ref: str) -> None:
    if git("cat-file", "-t", tag) != "tag":
        raise ValueError(f"release ref is not an annotated tag: {tag}")
    release_commit = git("rev-list", "-n", "1", tag)
    subprocess.run(
        ["git", "merge-base", "--is-ancestor", release_commit, main_ref], check=True
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
