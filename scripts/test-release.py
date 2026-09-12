#!/usr/bin/env python3
"""Behavior tests for release metadata and provenance verification."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "verify_release", ROOT / "scripts" / "verify-release.py"
)
assert SPEC is not None and SPEC.loader is not None
VERIFY_RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY_RELEASE)


class ReleaseProvenanceTests(unittest.TestCase):
    def test_signed_tag_uses_only_repository_ssh_signer_policy(self) -> None:
        completed = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        with (
            mock.patch.object(VERIFY_RELEASE, "repository_root", return_value=ROOT),
            mock.patch.object(
                VERIFY_RELEASE,
                "git",
                side_effect=[
                    "tag",
                    "object 0123456789abcdef\n\nAccess v1.2.3\n"
                    "-----BEGIN SSH SIGNATURE-----\nfixture\n"
                    "-----END SSH SIGNATURE-----",
                    "0123456789abcdef0123456789abcdef01234567",
                ],
            ),
            mock.patch.object(VERIFY_RELEASE.subprocess, "run", return_value=completed) as run,
        ):
            VERIFY_RELEASE.verify_provenance("v1.2.3", "origin/main")

        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(
            [
                "git",
                "-c",
                "gpg.format=ssh",
                "-c",
                f"gpg.ssh.allowedSignersFile={ROOT / '.github/release-signers'}",
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
                "v1.2.3",
            ],
            commands,
        )

    def test_unsigned_annotated_tag_is_rejected_without_creating_a_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            repository = pathlib.Path(temporary_directory)
            isolated_environment = {
                **os.environ,
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_CONFIG_NOSYSTEM": "1",
            }
            git = ["git", "-c", "commit.gpgSign=false", "-c", "tag.gpgSign=false"]
            subprocess.run(
                [*git, "init", "-q", "-b", "main"],
                cwd=repository,
                check=True,
                env=isolated_environment,
            )
            subprocess.run(
                [*git, "config", "user.name", "Release contract test"],
                cwd=repository,
                check=True,
                env=isolated_environment,
            )
            subprocess.run(
                [*git, "config", "user.email", "release-contract@example.invalid"],
                cwd=repository,
                check=True,
                env=isolated_environment,
            )
            (repository / "tracked").write_text("fixture\n")
            subprocess.run(
                [*git, "add", "tracked"],
                cwd=repository,
                check=True,
                env=isolated_environment,
            )
            subprocess.run(
                [*git, "commit", "-q", "-m", "fixture"],
                cwd=repository,
                check=True,
                env=isolated_environment,
            )
            subprocess.run(
                [*git, "tag", "-a", "v1.2.3", "-m", "unsigned fixture"],
                cwd=repository,
                check=True,
                env=isolated_environment,
            )
            policy_directory = repository / ".github"
            policy_directory.mkdir()
            (policy_directory / "release-signers").write_text(
                (ROOT / ".github/release-signers").read_text()
            )

            with mock.patch.object(VERIFY_RELEASE, "repository_root", return_value=repository):
                with self.assertRaisesRegex(ValueError, "does not contain an SSH signature"):
                    VERIFY_RELEASE.verify_provenance("v1.2.3", "main")

    def test_invalid_signer_policy_is_rejected_before_git_verification(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            policy = pathlib.Path(temporary_directory) / "release-signers"
            policy.write_text("someone ssh-ed25519 invalid\n")
            with self.assertRaisesRegex(ValueError, "restricted"):
                VERIFY_RELEASE.validate_signer_policy(policy)

    def test_missing_signer_policy_is_rejected_before_git_verification(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            policy = pathlib.Path(temporary_directory) / "release-signers"
            with self.assertRaisesRegex(ValueError, "policy is missing"):
                VERIFY_RELEASE.validate_signer_policy(policy)

    def test_openpgp_signature_format_is_rejected_without_creating_a_key(self) -> None:
        tag_object = (
            "object 0123456789abcdef\n\nAccess v1.2.3\n"
            "-----BEGIN SSH SIGNATURE-----\ntext in message\n"
            "-----BEGIN PGP SIGNATURE-----\nfixture\n"
            "-----END PGP SIGNATURE-----"
        )
        with self.assertRaisesRegex(ValueError, "does not contain an SSH signature"):
            VERIFY_RELEASE.validate_ssh_tag_signature("v1.2.3", tag_object)


if __name__ == "__main__":
    unittest.main()
