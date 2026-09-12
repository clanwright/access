#!/usr/bin/env python3
"""Exercise verification CLI isolation and native scope without invoking Nix."""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parent.parent


class VerificationCLI(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = pathlib.Path(self.temporary.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.logs = self.directory / "logs with spaces"
        self.logs.mkdir()
        self.env = os.environ | {
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "ACCESS_VERIFY_IN_DEV_SHELL": "1",
            "ACCESS_VERIFY_LOG_DIR": str(self.logs),
            "VERIFY_TEST_TRACE": str(self.directory / "nix-trace"),
        }
        self.command("git", "printf 'flake.nix\\0'\n")
        self.command("nixfmt", "echo intentional-formatting-failure >&2\nexit 1\n")

    def command(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(f"#!{shutil.which('bash')}\nset -eu\n" + body)
        path.chmod(0o755)

    def invoke(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(ROOT / "scripts/verify.sh"), *args],
            cwd=ROOT,
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

    def test_repeated_early_failures_keep_separate_evidence(self) -> None:
        previous = self.logs / "linux-checks.log"
        previous.write_text("previous run evidence\n")
        for _ in range(2):
            result = self.invoke()
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertIn("intentional-formatting-failure", result.stdout)
        runs = sorted(path for path in self.logs.iterdir() if path.is_dir())
        self.assertEqual(len(runs), 2)
        self.assertEqual(previous.read_text(), "previous run evidence\n")
        self.assertFalse((self.logs / "summary.log").exists())
        for run in runs:
            summary = (run / "summary.log").read_text()
            self.assertEqual(summary.count("whole-run start="), 1)
            self.assertIn("stage=formatting", summary)
            self.assertFalse((run / "linux-checks.log").exists())

    def test_native_recovery_builds_only_current_system_outputs(self) -> None:
        self.command(
            "nix",
            'printf "%s\\n" "$*" >> "$VERIFY_TEST_TRACE"\n'
            'if [[ "$1" == eval ]]; then printf "aarch64-darwin"; fi\n',
        )
        result = self.invoke("--native-recovery")
        self.assertEqual(result.returncode, 0, result.stdout)
        calls = (self.directory / "nix-trace").read_text().splitlines()
        builds = [call for call in calls if call.startswith("build ")]
        self.assertEqual(len(builds), 1, json.dumps(calls))
        self.assertIn(".#stunnel", builds[0])
        self.assertIn(".#openssh", builds[0])
        self.assertIn(".#checks.aarch64-darwin.recovery-client-config", builds[0])
        self.assertNotIn("x86_64-linux", "\n".join(calls))
        self.assertNotIn("stage=formatting", result.stdout)

    def test_unknown_mode_fails_before_any_build(self) -> None:
        self.command("nix", 'echo unexpected-call >> "$VERIFY_TEST_TRACE"\n')
        result = self.invoke("--unknown")
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertFalse((self.directory / "nix-trace").exists())


if __name__ == "__main__":
    unittest.main()
