#!/usr/bin/env python3
"""Install the extracted official 15.3x UI resources into the runtime tree.

Existing byte-identical files are left untouched. A conflicting runtime file is
first moved to data/old-assets at the same relative path, then replaced
with the official file. The command is a dry run unless --apply is supplied.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "data/official-client-15.3x/graphics-resources"
DEFAULT_TARGET = ROOT / "data"
DEFAULT_ARCHIVE = DEFAULT_TARGET / "old-assets"
DEFAULT_MANIFEST = ROOT / "docs/ui-parity/official-runtime-asset-migration.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def relative_display(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--archive", type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--apply", action="store_true", help="perform the migration")
    args = parser.parse_args()

    source = args.source.resolve()
    target = args.target.resolve()
    archive = args.archive.resolve()
    manifest = args.manifest.resolve()
    if not source.is_dir():
        parser.error(f"official image directory does not exist: {source}")
    if source == target or source == archive or target == archive:
        parser.error("source, target, and archive must be distinct")
    if archive.parent != target:
        parser.error("archive must be a direct child of the runtime data directory")

    records: list[dict[str, str]] = []
    counts = {"identical": 0, "missing": 0, "replaced": 0}
    for official in sorted(path for path in source.rglob("*") if path.is_file()):
        relative = official.relative_to(source)
        runtime = target / relative
        archived = archive / relative
        official_hash = sha256(official)

        if not runtime.exists():
            action = "missing"
        elif sha256(runtime) == official_hash:
            action = "identical"
        else:
            action = "replaced"
            if archived.exists() and sha256(archived) != sha256(runtime):
                raise RuntimeError(
                    f"refusing to overwrite a different archived asset: {archived}"
                )

        counts[action] += 1
        records.append(
            {
                "path": relative.as_posix(),
                "action": action,
                "official_sha256": official_hash,
            }
        )

        if not args.apply or action == "identical":
            continue
        runtime.parent.mkdir(parents=True, exist_ok=True)
        if action == "replaced":
            archived.parent.mkdir(parents=True, exist_ok=True)
            if not archived.exists():
                runtime.replace(archived)
        shutil.copy2(official, runtime)

    payload = {
        "schema": "official-ui-runtime-assets-v1",
        "official_version": "15.3x",
        "mode": "applied" if args.apply else "dry-run",
        "source": relative_display(source),
        "target": relative_display(target),
        "archive": relative_display(archive),
        "counts": counts,
        "assets": records,
    }
    if args.apply:
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({"mode": payload["mode"], **counts}, indent=2))
    if args.apply:
        print(f"manifest: {relative_display(manifest)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
