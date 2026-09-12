#!/usr/bin/env python3
"""Behavior tests for immutable and required GitHub workflow policy."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "verify_workflows", ROOT / "scripts" / "verify-workflows.py"
)
assert SPEC is not None and SPEC.loader is not None
VERIFY_WORKFLOWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFY_WORKFLOWS)


class WorkflowPolicyTests(unittest.TestCase):
    def aggregate_ci(self) -> str:
        return (ROOT / ".github/workflows/ci.yml").read_text()

    def check_temporary_workflow(self, name: str, source: str) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = pathlib.Path(temporary_directory) / name
            path.write_text(source)
            VERIFY_WORKFLOWS.check(path)

    def test_repository_workflows_satisfy_required_policy(self) -> None:
        for path in VERIFY_WORKFLOWS.workflow_paths([ROOT / ".github/workflows"]):
            VERIFY_WORKFLOWS.check(path)

    def test_repository_workflow_inventory_rejects_unknown_or_missing_files(self) -> None:
        directory = ROOT / ".github/workflows"
        current = VERIFY_WORKFLOWS.workflow_paths([directory])
        for paths in (current + [directory / "bypass.yml"], current[:-1]):
            with self.subTest(paths=[path.name for path in paths]):
                with self.assertRaisesRegex(ValueError, "workflow inventory"):
                    VERIFY_WORKFLOWS.check_inventory(directory, paths)

    def test_required_verify_aggregates_both_platform_results(self) -> None:
        self.check_temporary_workflow("ci.yml", self.aggregate_ci())

    def test_aggregate_rejects_missing_native_dependency(self) -> None:
        mutation = self.aggregate_ci().replace(
            "needs: [linux, native-arm-darwin]", "needs: [linux]"
        )
        with self.assertRaisesRegex(ValueError, "depend on Linux and native ARM Darwin"):
            self.check_temporary_workflow("ci.yml", mutation)

    def test_aggregate_rejects_missing_always_predicate(self) -> None:
        mutation = self.aggregate_ci().replace("    if: ${{ always() }}\n", "")
        with self.assertRaisesRegex(ValueError, "must use always"):
            self.check_temporary_workflow("ci.yml", mutation)

    def test_aggregate_rejects_missing_native_result_assertion(self) -> None:
        mutation = self.aggregate_ci().replace(
            '          test "${{ needs.native-arm-darwin.result }}" = success\n', ""
        )
        with self.assertRaisesRegex(ValueError, "platform result assertions"):
            self.check_temporary_workflow("ci.yml", mutation)

    def test_conditional_release_provenance_is_rejected(self) -> None:
        source = (ROOT / ".github/workflows/release-gate.yml").read_text()
        conditional = source.replace(
            "      - name: Verify release metadata and provenance\n",
            "      - name: Verify release metadata and provenance\n        if: success()\n",
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = pathlib.Path(temporary_directory) / "release-gate.yml"
            path.write_text(conditional)
            with self.assertRaisesRegex(ValueError, "step structure does not match"):
                VERIFY_WORKFLOWS.check(path)

    def test_release_publication_command_is_rejected(self) -> None:
        source = (ROOT / ".github/workflows/release-gate.yml").read_text()
        publishing = source.replace(
            "      - name: Run complete verification\n",
            "      - name: Publish release\n        run: gh release create v1.2.3\n"
            "      - name: Run complete verification\n",
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = pathlib.Path(temporary_directory) / "release-gate.yml"
            path.write_text(publishing)
            with self.assertRaisesRegex(ValueError, "step structure does not match"):
                VERIFY_WORKFLOWS.check(path)

    def test_prefixed_release_publication_commands_are_rejected(self) -> None:
        source = (ROOT / ".github/workflows/release-gate.yml").read_text()
        for command in (
            "  gh release create v1.2.3",
            "env gh release create v1.2.3",
            "command gh release create v1.2.3",
        ):
            with self.subTest(command=command):
                publishing = source.replace(
                    "      - name: Run complete verification\n",
                    f"      - name: Publish release\n        run: {command}\n"
                    "      - name: Run complete verification\n",
                )
                with tempfile.TemporaryDirectory() as temporary_directory:
                    path = pathlib.Path(temporary_directory) / "release-gate.yml"
                    path.write_text(publishing)
                    with self.assertRaisesRegex(ValueError, "step structure does not match"):
                        VERIFY_WORKFLOWS.check(path)

    def test_secrets_context_is_rejected_at_every_yaml_depth(self) -> None:
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        mutations = (
            source.replace("permissions:\n", "env:\n  TOKEN: ${{ secrets.RELEASE_TOKEN }}\n\npermissions:\n"),
            source.replace(
                "  verify:\n",
                "  verify:\n    env:\n      TOKEN: ${{ secrets.RELEASE_TOKEN }}\n",
            ),
            source.replace(
                "      - name: Run complete verification\n",
                "      - name: Run complete verification\n"
                "        env:\n          TOKEN: ${{ secrets.RELEASE_TOKEN }}\n",
            ),
            source.replace(
                "permissions:\n", "name: ${{ secrets }}\n\npermissions:\n"
            ),
            source.replace(
                "permissions:\n", "name: ${{ toJSON(secrets) }}\n\npermissions:\n"
            ),
            source.replace(
                "  linux:\n", "  linux:\n    secrets: inherit\n"
            ),
        )
        for index, mutation in enumerate(mutations):
            with self.subTest(depth=index):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    path = pathlib.Path(temporary_directory) / "ci.yml"
                    path.write_text(mutation)
                    with self.assertRaisesRegex(ValueError, "secrets context is forbidden"):
                        VERIFY_WORKFLOWS.check(path)

    def test_execution_environment_overrides_are_rejected(self) -> None:
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        mutations = (
            source.replace("permissions:\n", "env:\n  BASH_ENV: injected\n\npermissions:\n"),
            source.replace(
                "permissions:\n",
                "defaults:\n  run:\n    shell: injected {0}\n\npermissions:\n",
            ),
            source.replace(
                "      - name: Run complete verification\n",
                "      - name: Run complete verification\n        shell: injected {0}\n",
            ),
            source.replace(
                "      - name: Run complete verification\n",
                "      - name: Run complete verification\n        working-directory: elsewhere\n",
            ),
        )
        for index, mutation in enumerate(mutations):
            with self.subTest(override=index):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    path = pathlib.Path(temporary_directory) / "ci.yml"
                    path.write_text(mutation)
                    with self.assertRaisesRegex(ValueError, "execution override is forbidden"):
                        VERIFY_WORKFLOWS.check(path)

    def test_checkout_source_substitution_is_rejected(self) -> None:
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        for checkout_inputs in (
            "          persist-credentials: false\n          repository: attacker/repository\n",
            "          persist-credentials: false\n          ref: attacker-ref\n",
        ):
            with self.subTest(inputs=checkout_inputs):
                mutation = source.replace(
                    "          persist-credentials: false\n",
                    checkout_inputs,
                    1,
                )
                with self.assertRaisesRegex(ValueError, "step structure does not match"):
                    self.check_temporary_workflow("ci.yml", mutation)

    def test_release_checkout_rejects_extra_source_inputs(self) -> None:
        source = (ROOT / ".github/workflows/release-gate.yml").read_text()
        mutation = source.replace(
            "          fetch-depth: 0\n",
            "          fetch-depth: 0\n          ref: attacker-ref\n",
            1,
        )
        with self.assertRaisesRegex(ValueError, "step structure does not match"):
            self.check_temporary_workflow("release-gate.yml", mutation)

    def test_extra_local_or_pinned_action_is_rejected(self) -> None:
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        actions = (
            "./bypass",
            "actions/cache@0123456789abcdef0123456789abcdef01234567",
        )
        for action in actions:
            with self.subTest(action=action):
                mutation = source.replace(
                    "      - name: Install Nix\n",
                    f"      - name: Bypass\n        uses: {action}\n"
                    "      - name: Install Nix\n",
                    1,
                )
                with self.assertRaisesRegex(ValueError, "step structure does not match"):
                    self.check_temporary_workflow("ci.yml", mutation)

    def test_governed_job_executor_shape_is_fixed(self) -> None:
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        additions = (
            "    container: ghcr.io/example/tool@sha256:"
            + "a" * 64
            + "\n",
            "    services: {}\n",
            "    strategy:\n      fail-fast: false\n",
            "    name: Replaced status name\n",
        )
        for addition in additions:
            with self.subTest(addition=addition):
                mutation = source.replace("  linux:\n", "  linux:\n" + addition, 1)
                with self.assertRaisesRegex(ValueError, "job structure does not match"):
                    self.check_temporary_workflow("ci.yml", mutation)

    def test_echoed_linux_gate_is_rejected(self) -> None:
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        bypass = source.replace(
            "        run: bash scripts/verify.sh\n",
            "        run: echo 'bash scripts/verify.sh'\n",
            1,
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = pathlib.Path(temporary_directory) / "ci.yml"
            path.write_text(bypass)
            with self.assertRaisesRegex(ValueError, "step structure does not match"):
                VERIFY_WORKFLOWS.check(path)

    def test_metadata_only_provenance_is_rejected(self) -> None:
        source = (ROOT / ".github/workflows/release-gate.yml").read_text()
        bypass = source.replace(
            "scripts/verify-release.py --tag",
            "scripts/verify-release.py --metadata-only --tag",
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = pathlib.Path(temporary_directory) / "release-gate.yml"
            path.write_text(bypass)
            with self.assertRaisesRegex(ValueError, "step structure does not match"):
                VERIFY_WORKFLOWS.check(path)

    def test_native_mode_cannot_replace_linux_full_gate(self) -> None:
        source = (ROOT / ".github/workflows/ci.yml").read_text()
        bypass = source.replace(
            "        run: bash scripts/verify.sh\n",
            "        run: bash scripts/verify.sh --native-recovery\n",
            1,
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = pathlib.Path(temporary_directory) / "ci.yml"
            path.write_text(bypass)
            with self.assertRaisesRegex(ValueError, "step structure does not match"):
                VERIFY_WORKFLOWS.check(path)


if __name__ == "__main__":
    unittest.main()
