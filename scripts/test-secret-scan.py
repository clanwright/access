#!/usr/bin/env python3
"""Keep the public SSH fingerprint exception limited to verification output."""

from __future__ import annotations

import base64
import hashlib
import json
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parent.parent


class SecretScanPolicy(unittest.TestCase):
    def scan(self, line: str) -> tuple[int, list[dict]]:
        with tempfile.TemporaryDirectory() as temporary:
            directory = pathlib.Path(temporary)
            source = directory / "source"
            source.mkdir()
            (source / "verification.log").write_text(line + "\n")
            report = directory / "report.json"
            command = [
                "gitleaks", "dir", str(source), "--no-banner", "--redact",
                "--report-format", "json", "--report-path", str(report),
            ]
            policy = ROOT / ".gitleaks.toml"
            if policy.exists():
                command.extend(["--config", str(policy)])
            result = subprocess.run(command, text=True, capture_output=True)
            self.assertIn(result.returncode, [0, 1], result.stderr)
            return result.returncode, json.loads(report.read_text())

    def test_only_complete_public_signature_output_is_exempt(self) -> None:
        # Derive a public fingerprint from the existing release trust policy.
        # No credential, signing key, or access artifact is generated.
        record = next(
            line for line in (ROOT / ".github/release-signers").read_text().splitlines()
            if line and not line.startswith("#")
        )
        public_key = base64.b64decode(record.split()[-1], validate=True)
        fingerprint = base64.b64encode(hashlib.sha256(public_key).digest()).decode().rstrip("=")
        line = f'Good "git" signature for access-release with ED25519 key SHA256:{fingerprint}'

        status, findings = self.scan(line)
        self.assertEqual(status, 0, "public Git signature output must not be reported as a credential")
        self.assertEqual(findings, [])
        for changed in ["unexpected: " + line, line + " unexpected"]:
            with self.subTest(context=changed.split(" SHA256:")[0]):
                status, findings = self.scan(changed)
                self.assertEqual(status, 1, "the exception must match the entire verification line")
                self.assertIn("generic-api-key", [finding["RuleID"] for finding in findings])


if __name__ == "__main__":
    unittest.main()
