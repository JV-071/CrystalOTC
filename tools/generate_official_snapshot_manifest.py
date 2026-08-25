#!/usr/bin/env python3
"""Regenerate the complete official-client snapshot manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import defaultdict
from pathlib import Path


DEFAULT_ROOT = Path("data/official-client-15.3x")
DEFAULT_MANIFEST_NAME = "snapshot-manifest.json"
DEFAULT_EXCLUSIONS = [
    "generic Qt frameworks and Qt Quick runtime modules",
    "client executable and BattlEye",
    "screenshots",
    "characterdata",
    "conf",
    "cache",
    "logs",
    "crash dumps",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Hash and inventory every file in the official-client snapshot."
    )
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--manifest-name", default=DEFAULT_MANIFEST_NAME)
    parser.add_argument("--official-client-version")
    parser.add_argument("--protocol-asset-family")
    return parser.parse_args()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    args = parse_args()
    manifest_path = args.root / args.manifest_name
    previous = {}
    if manifest_path.is_file():
        try:
            previous = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"error: cannot read existing manifest {manifest_path}: {error}", file=sys.stderr)
            return 1

    version = args.official_client_version or previous.get("official_client_version")
    family = args.protocol_asset_family or previous.get("protocol_asset_family")
    if not version or not family:
        print(
            "error: official version and protocol family must be provided on the first run",
            file=sys.stderr,
        )
        return 1

    files = []
    categories: dict[str, dict[str, int]] = defaultdict(lambda: {"files": 0, "bytes": 0})
    try:
        paths = sorted(
            path
            for path in args.root.rglob("*")
            if path.is_file() and path != manifest_path
        )
        for path in paths:
            relative = path.relative_to(args.root).as_posix()
            size = path.stat().st_size
            category = relative.split("/", 1)[0]
            categories[category]["files"] += 1
            categories[category]["bytes"] += size
            files.append({"path": relative, "bytes": size, "sha256": sha256_file(path)})
    except OSError as error:
        print(f"error: cannot inventory snapshot: {error}", file=sys.stderr)
        return 1

    manifest = {
        "official_client_version": version,
        "protocol_asset_family": family,
        "snapshot_file_count": len(files),
        "snapshot_bytes": sum(item["bytes"] for item in files),
        "categories": dict(sorted(categories.items())),
        "excluded_as_non_asset_runtime_or_user_state": previous.get(
            "excluded_as_non_asset_runtime_or_user_state", DEFAULT_EXCLUSIONS
        ),
        "files": files,
    }
    # The older wording excluded QML as a whole. The application QML is now a
    # deliberate snapshot category; only the generic Qt runtime remains out.
    manifest["excluded_as_non_asset_runtime_or_user_state"] = [
        "generic Qt frameworks and Qt Quick runtime modules"
        if value == "generic Qt frameworks and Qt Quick/QML runtime"
        else value
        for value in manifest["excluded_as_non_asset_runtime_or_user_state"]
    ]
    try:
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    except OSError as error:
        print(f"error: cannot write {manifest_path}: {error}", file=sys.stderr)
        return 1

    print(
        f"inventoried {manifest['snapshot_file_count']} files "
        f"({manifest['snapshot_bytes']} bytes) in {manifest_path}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
