#!/usr/bin/env python3
"""Reject mutable GitHub Actions and container references in workflow YAML."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from typing import Any

import yaml


COMMIT_SHA = re.compile(r"[0-9a-fA-F]{40}\Z")
IMAGE_DIGEST = re.compile(r".+@sha256:[0-9a-fA-F]{64}\Z")


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


def check(path: pathlib.Path) -> None:
    try:
        document = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
    except (OSError, yaml.YAMLError) as error:
        raise ValueError(f"{path}: invalid workflow YAML: {error}") from error
    walk_uses(path, document)
    check_containers(path, document)


def workflow_paths(paths: list[pathlib.Path]) -> list[pathlib.Path]:
    expanded: list[pathlib.Path] = []
    for path in paths:
        if path.is_dir():
            expanded.extend(sorted(path.glob("*.yml")))
            expanded.extend(sorted(path.glob("*.yaml")))
        else:
            expanded.append(path)
    return expanded


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=pathlib.Path)
    args = parser.parse_args()
    try:
        for path in workflow_paths(args.paths):
            check(path)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
