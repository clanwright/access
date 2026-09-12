#!/usr/bin/env python3
"""Validate immutable references and required GitHub workflow policy."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from typing import Any

import yaml


COMMIT_SHA = re.compile(r"[0-9a-fA-F]{40}\Z")
IMAGE_DIGEST = re.compile(r".+@sha256:[0-9a-fA-F]{64}\Z")
PUBLISH_COMMAND = re.compile(
    r"(?:^|[;&|]\s*|\n\s*)\s*(?:(?:env|command)\s+)?(?:gh|hub)\s+release\b"
)
SECRETS_CONTEXT = re.compile(r"\$\{\{[^}]*\bsecrets\b[^}]*\}\}", re.IGNORECASE)
PUBLISH_ACTIONS = (
    "actions/create-release",
    "marvinpinto/action-automatic-releases",
    "ncipollo/release-action",
    "release-drafter/release-drafter",
    "softprops/action-gh-release",
)
GOVERNED_JOBS = {
    "ci.yml": {
        "linux": {"runs-on": "ubuntu-24.04", "timeout-minutes": "60"},
        "native-arm-darwin": {"runs-on": "macos-26", "timeout-minutes": "60"},
        "verify": {
            "needs": ["linux", "native-arm-darwin"],
            "if": "${{ always() }}",
            "runs-on": "ubuntu-24.04",
            "timeout-minutes": "5",
        },
    },
    "release-gate.yml": {
        "linux": {"runs-on": "ubuntu-24.04", "timeout-minutes": "60"},
        "native-arm-darwin": {"runs-on": "macos-26", "timeout-minutes": "60"},
        "verify": {
            "needs": ["linux", "native-arm-darwin"],
            "if": "${{ always() }}",
            "runs-on": "ubuntu-24.04",
            "timeout-minutes": "5",
        },
    },
    "freshness.yml": {
        "report": {"runs-on": "ubuntu-24.04", "timeout-minutes": "20"},
    },
}

CHECKOUT = "actions/checkout"
NIX_INSTALLER = "DeterminateSystems/nix-installer-action"
UPLOAD_ARTIFACT = "actions/upload-artifact"
AGGREGATE_COMMAND = (
    'test "${{ needs.linux.result }}" = success '
    'test "${{ needs.native-arm-darwin.result }}" = success'
)
GOVERNED_STEPS = {
    "ci.yml": {
        "linux": [
            ("uses", CHECKOUT, {"persist-credentials": "false"}),
            ("uses", NIX_INSTALLER, None),
            ("run", "bash scripts/verify.sh", None),
        ],
        "native-arm-darwin": [
            ("uses", CHECKOUT, {"persist-credentials": "false"}),
            ("uses", NIX_INSTALLER, None),
            ("run", "bash scripts/verify.sh --native-recovery", None),
        ],
        "verify": [("run", AGGREGATE_COMMAND, None)],
    },
    "release-gate.yml": {
        "linux": [
            (
                "uses",
                CHECKOUT,
                {"fetch-depth": "0", "persist-credentials": "false"},
            ),
            ("run", "git fetch --no-tags origin main:refs/remotes/origin/main", None),
            ("uses", NIX_INSTALLER, None),
            (
                "run",
                'nix develop --no-write-lock-file --command python3 scripts/verify-release.py --tag "$GITHUB_REF_NAME"',
                None,
            ),
            ("run", "bash scripts/verify.sh", None),
            (
                "run",
                "nix run --no-write-lock-file .#freshness-report -- --output access-freshness.json",
                None,
            ),
            (
                "uses",
                UPLOAD_ARTIFACT,
                {
                    "name": "access-freshness",
                    "path": "access-freshness.json",
                    "if-no-files-found": "error",
                    "retention-days": "30",
                },
            ),
        ],
        "native-arm-darwin": [
            ("uses", CHECKOUT, {"persist-credentials": "false"}),
            ("uses", NIX_INSTALLER, None),
            ("run", "bash scripts/verify.sh --native-recovery", None),
        ],
        "verify": [("run", AGGREGATE_COMMAND, None)],
    },
    "freshness.yml": {
        "report": [
            ("uses", CHECKOUT, {"persist-credentials": "false"}),
            ("uses", NIX_INSTALLER, None),
            ("run", "nix run .#freshness-report -- --output access-freshness.json", None),
            (
                "uses",
                UPLOAD_ARTIFACT,
                {
                    "name": "access-freshness",
                    "path": "access-freshness.json",
                    "if-no-files-found": "error",
                    "retention-days": "14",
                },
            ),
        ],
    },
}


def fail(path: pathlib.Path, location: str, message: str) -> None:
    raise ValueError(f"{path}:{location}: {message}")


def check_uses(path: pathlib.Path, location: str, value: object) -> None:
    if not isinstance(value, str):
        fail(path, location, "uses must be a string")
    if value.startswith("./"):
        return
    if value.startswith("docker://"):
        if not IMAGE_DIGEST.fullmatch(value.removeprefix("docker://")):
            fail(path, location, "container action must use a sha256 digest")
        return
    if "@" not in value:
        fail(path, location, "remote action must include a full commit SHA")
    action, revision = value.rsplit("@", 1)
    if not action or not COMMIT_SHA.fullmatch(revision):
        fail(path, location, "remote action must use a full 40-character commit SHA")
    if any(action.lower() == publisher for publisher in PUBLISH_ACTIONS):
        fail(path, location, "workflow must not publish a release")


def walk_uses(path: pathlib.Path, value: Any, location: str = "root") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            child_location = f"{location}.{key}"
            if key == "uses":
                check_uses(path, child_location, child)
            else:
                walk_uses(path, child, child_location)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk_uses(path, child, f"{location}[{index}]")


def reject_secrets_context(path: pathlib.Path, value: Any, location: str = "root") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            child_location = f"{location}.{key}"
            if isinstance(key, str) and (
                key == "secrets" or SECRETS_CONTEXT.search(key)
            ):
                fail(path, child_location, "secrets context is forbidden")
            reject_secrets_context(path, child, child_location)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secrets_context(path, child, f"{location}[{index}]")
    elif isinstance(value, str) and SECRETS_CONTEXT.search(value):
        fail(path, location, "secrets context is forbidden")


def reject_execution_overrides(
    path: pathlib.Path, value: Any, location: str = "root"
) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            child_location = f"{location}.{key}"
            if key in {"env", "defaults", "shell", "working-directory"}:
                fail(path, child_location, "workflow execution override is forbidden")
            reject_execution_overrides(path, child, child_location)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_execution_overrides(path, child, f"{location}[{index}]")


def container_image(path: pathlib.Path, location: str, value: object) -> None:
    image = value.get("image") if isinstance(value, dict) else value
    if not isinstance(image, str) or not IMAGE_DIGEST.fullmatch(image):
        fail(path, location, "workflow container image must use a sha256 digest")


def check_containers(path: pathlib.Path, document: object) -> None:
    if not isinstance(document, dict):
        fail(path, "root", "workflow must be a mapping")
    jobs = document.get("jobs", {})
    if not isinstance(jobs, dict):
        fail(path, "root.jobs", "jobs must be a mapping")
    for job_name, job in jobs.items():
        if not isinstance(job, dict):
            continue
        if "container" in job:
            container_image(path, f"root.jobs.{job_name}.container", job["container"])
        services = job.get("services", {})
        if isinstance(services, dict):
            for service_name, service in services.items():
                container_image(
                    path,
                    f"root.jobs.{job_name}.services.{service_name}",
                    service,
                )


def mapping(path: pathlib.Path, location: str, value: object) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(path, location, "must be a mapping")
    return value


def sequence(path: pathlib.Path, location: str, value: object) -> list[Any]:
    if not isinstance(value, list):
        fail(path, location, "must be a sequence")
    return value


def check_read_only_permissions(path: pathlib.Path, document: dict[str, Any]) -> None:
    permissions = mapping(path, "root.permissions", document.get("permissions"))
    if permissions.get("contents") != "read":
        fail(path, "root.permissions.contents", "must be read")
    for permission, access in permissions.items():
        if access == "write":
            fail(path, f"root.permissions.{permission}", "must not grant write access")

    jobs = mapping(path, "root.jobs", document.get("jobs"))
    for job_name, job_value in jobs.items():
        job = mapping(path, f"root.jobs.{job_name}", job_value)
        if "permissions" in job:
            fail(path, f"root.jobs.{job_name}.permissions", "must not override permissions")


def normalize_command(command: str) -> str:
    return " ".join(command.split())


def check_no_publication(path: pathlib.Path, document: dict[str, Any]) -> None:
    jobs = mapping(path, "root.jobs", document.get("jobs"))
    for job_name, job_value in jobs.items():
        job = mapping(path, f"root.jobs.{job_name}", job_value)
        steps = sequence(path, f"root.jobs.{job_name}.steps", job.get("steps"))
        for index, step_value in enumerate(steps):
            step = mapping(path, f"root.jobs.{job_name}.steps[{index}]", step_value)
            command = step.get("run")
            if isinstance(command, str) and PUBLISH_COMMAND.search(command):
                fail(path, f"root.jobs.{job_name}.steps[{index}].run", "workflow must not publish a release")


def check_aggregate_job(path: pathlib.Path, document: dict[str, Any]) -> None:
    jobs = mapping(path, "root.jobs", document.get("jobs"))
    aggregate = mapping(path, "root.jobs.verify", jobs.get("verify"))
    if aggregate.get("needs") != ["linux", "native-arm-darwin"]:
        fail(
            path,
            "root.jobs.verify.needs",
            "required verify must depend on Linux and native ARM Darwin",
        )
    if aggregate.get("if") != "${{ always() }}":
        fail(path, "root.jobs.verify.if", "required verify must use always()")
    if aggregate.get("runs-on") != "ubuntu-24.04":
        fail(path, "root.jobs.verify.runs-on", "required verify must use ubuntu-24.04")
    if aggregate.get("timeout-minutes") != "5":
        fail(path, "root.jobs.verify.timeout-minutes", "required verify timeout must be 5")
    if "continue-on-error" in aggregate:
        fail(path, "root.jobs.verify", "required verify must not continue on error")
    steps = sequence(path, "root.jobs.verify.steps", aggregate.get("steps"))
    if len(steps) != 1:
        fail(path, "root.jobs.verify.steps", "required verify must have one assertion step")
    step = mapping(path, "root.jobs.verify.steps[0]", steps[0])
    if any(key in step for key in ("if", "continue-on-error", "shell", "working-directory")):
        fail(path, "root.jobs.verify.steps[0]", "required verify assertion must be unconditional")
    command = step.get("run")
    expected_lines = [
        'test "${{ needs.linux.result }}" = success',
        'test "${{ needs.native-arm-darwin.result }}" = success',
    ]
    if not isinstance(command, str) or [
        line.strip() for line in command.splitlines() if line.strip()
    ] != expected_lines:
        fail(
            path,
            "root.jobs.verify.steps[0].run",
            "required verify must contain both platform result assertions",
        )


def check_step_structure(
    path: pathlib.Path,
    job_name: str,
    step_value: object,
    expected: tuple[str, str, dict[str, str] | None],
    index: int,
) -> None:
    location = f"root.jobs.{job_name}.steps[{index}]"
    step = mapping(path, location, step_value)
    kind, payload, expected_inputs = expected
    expected_keys = {"name", kind} | ({"with"} if expected_inputs is not None else set())
    if set(step) != expected_keys or not isinstance(step.get("name"), str):
        fail(path, location, "step structure does not match repository workflow policy")
    if kind == "run":
        command = step.get("run")
        if not isinstance(command, str) or normalize_command(command) != payload:
            fail(path, location, "step structure does not match repository workflow policy")
    else:
        uses = step.get("uses")
        if not isinstance(uses, str) or "@" not in uses:
            fail(path, location, "step structure does not match repository workflow policy")
        action, revision = uses.rsplit("@", 1)
        if action != payload or COMMIT_SHA.fullmatch(revision) is None:
            fail(path, location, "step structure does not match repository workflow policy")
    if expected_inputs is not None and step.get("with") != expected_inputs:
        fail(path, location, "step structure does not match repository workflow policy")


def check_governed_structure(path: pathlib.Path, document: dict[str, Any]) -> None:
    expected_jobs = GOVERNED_JOBS.get(path.name)
    expected_steps = GOVERNED_STEPS.get(path.name)
    if expected_jobs is None or expected_steps is None:
        return
    jobs = mapping(path, "root.jobs", document.get("jobs"))
    if set(jobs) != set(expected_jobs):
        fail(path, "root.jobs", "job structure does not match repository workflow policy")
    for job_name, expected_job in expected_jobs.items():
        job = mapping(path, f"root.jobs.{job_name}", jobs[job_name])
        metadata = {key: value for key, value in job.items() if key != "steps"}
        if metadata != expected_job:
            fail(
                path,
                f"root.jobs.{job_name}",
                "job structure does not match repository workflow policy",
            )
        steps = sequence(path, f"root.jobs.{job_name}.steps", job.get("steps"))
        policies = expected_steps[job_name]
        if len(steps) != len(policies):
            fail(
                path,
                f"root.jobs.{job_name}.steps",
                "step structure does not match repository workflow policy",
            )
        for index, (step, policy) in enumerate(zip(steps, policies, strict=True)):
            check_step_structure(path, job_name, step, policy, index)


def check_ci(path: pathlib.Path, document: dict[str, Any]) -> None:
    trigger = mapping(path, "root.on", document.get("on"))
    if "pull_request" not in trigger or "push" not in trigger:
        fail(path, "root.on", "CI must run for pull requests and pushes")
    check_aggregate_job(path, document)
    check_governed_structure(path, document)


def check_release_gate(path: pathlib.Path, document: dict[str, Any]) -> None:
    trigger = mapping(path, "root.on", document.get("on"))
    push = mapping(path, "root.on.push", trigger.get("push"))
    tags = sequence(path, "root.on.push.tags", push.get("tags"))
    if tags != ["v*"]:
        fail(path, "root.on.push.tags", "release gate must run only for v* tags")
    check_aggregate_job(path, document)
    check_governed_structure(path, document)


def check_freshness(path: pathlib.Path, document: dict[str, Any]) -> None:
    trigger = mapping(path, "root.on", document.get("on"))
    if "schedule" not in trigger or "workflow_dispatch" not in trigger:
        fail(path, "root.on", "freshness must support schedule and workflow_dispatch")
    check_governed_structure(path, document)


def check_required_policy(path: pathlib.Path, document: dict[str, Any]) -> None:
    reject_secrets_context(path, document)
    reject_execution_overrides(path, document)
    check_read_only_permissions(path, document)
    if path.name == "ci.yml":
        check_ci(path, document)
    elif path.name == "release-gate.yml":
        check_release_gate(path, document)
    elif path.name == "freshness.yml":
        check_freshness(path, document)
    check_no_publication(path, document)


def check(path: pathlib.Path) -> None:
    try:
        document = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
    except (OSError, yaml.YAMLError) as error:
        raise ValueError(f"{path}: invalid workflow YAML: {error}") from error
    workflow = mapping(path, "root", document)
    walk_uses(path, workflow)
    check_containers(path, workflow)
    check_required_policy(path, workflow)


def workflow_paths(paths: list[pathlib.Path]) -> list[pathlib.Path]:
    expanded: list[pathlib.Path] = []
    for path in paths:
        if path.is_dir():
            expanded.extend(sorted(path.glob("*.yml")))
            expanded.extend(sorted(path.glob("*.yaml")))
        else:
            expanded.append(path)
    return expanded


def check_inventory(directory: pathlib.Path, paths: list[pathlib.Path]) -> None:
    expected = set(GOVERNED_JOBS)
    actual = {path.name for path in paths}
    if actual != expected:
        fail(
            directory,
            "root",
            "workflow inventory must contain exactly " + ", ".join(sorted(expected)),
        )


def check_paths(paths: list[pathlib.Path]) -> None:
    for path in paths:
        if path.is_dir() and path.name == "workflows" and path.parent.name == ".github":
            check_inventory(path, workflow_paths([path]))
    for path in workflow_paths(paths):
        check(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=pathlib.Path)
    args = parser.parse_args()
    try:
        check_paths(args.paths)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
