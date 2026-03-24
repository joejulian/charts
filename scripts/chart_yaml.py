#!/usr/bin/env python3
import argparse
import json
import re
import sys

import yaml


def load_chart(path: str | None) -> dict:
    if path:
        with open(path, encoding="utf-8") as handle:
            data = yaml.safe_load(handle) or {}
    else:
        data = yaml.safe_load(sys.stdin.read()) or {}

    deps = {}
    for dep in data.get("dependencies", []) or []:
        name = dep.get("name")
        if name:
            deps[name] = str(dep.get("version", "") or "")

    return {
        "version": str(data.get("version", "") or ""),
        "appVersion": str(data.get("appVersion", "") or ""),
        "dependencies": deps,
    }


def cmd_json(args: argparse.Namespace) -> int:
    print(json.dumps(load_chart(args.file)))
    return 0


def cmd_set_version(args: argparse.Namespace) -> int:
    with open(args.file, encoding="utf-8") as handle:
        content = handle.read()

    updated, replacements = re.subn(
        r"(?m)^version:\s*.*$",
        f'version: "{args.version}"',
        content,
        count=1,
    )
    if replacements != 1:
        raise SystemExit(f"expected exactly one top-level version field in {args.file}")

    with open(args.file, "w", encoding="utf-8") as handle:
        handle.write(updated)

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    json_parser = subparsers.add_parser("json")
    json_parser.add_argument("--file")
    json_parser.set_defaults(func=cmd_json)

    set_version_parser = subparsers.add_parser("set-version")
    set_version_parser.add_argument("--file", required=True)
    set_version_parser.add_argument("--version", required=True)
    set_version_parser.set_defaults(func=cmd_set_version)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
