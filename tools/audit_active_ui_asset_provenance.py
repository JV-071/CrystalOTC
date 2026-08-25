#!/usr/bin/env python3
"""Classify statically referenced UI assets by official 15.3x provenance."""

from __future__ import annotations

import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OFFICIAL = ROOT / "data/official-client-15.3x/graphics-resources"
DATA = ROOT / "data"
OUTPUT = ROOT / "docs/ui-parity/active-ui-asset-provenance.json"
SCAN_ROOTS = (ROOT / "modules", ROOT / "mods", ROOT / "data/styles")
SCAN_SUFFIXES = {".lua", ".otui", ".otmod"}
RESOURCE_RE = re.compile(
    r"/(?P<path>(?:images|animations|cursors|fonts|tutorial|data)/"
    r"[A-Za-z0-9_./@+%() -]+?(?:\.(?:png|jpg|jpeg|gif|bmp|webp|svg|otml))?)"
    r"(?=[\s'\";,}\)]|$)",
    re.IGNORECASE,
)
EXTENSIONS = ("", ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".svg", ".otml")
DERIVED_OFFICIAL = {
    "images/title-official": "images/title.jpg",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve(resource: str) -> Path | None:
    base = DATA / resource
    for extension in EXTENSIONS:
        candidate = Path(str(base) + extension)
        if candidate.is_file():
            return candidate
    return None


def main() -> int:
    official_hashes: dict[str, list[str]] = defaultdict(list)
    for path in sorted(item for item in OFFICIAL.rglob("*") if item.is_file()):
        official_hashes[sha256(path)].append(path.relative_to(OFFICIAL).as_posix())

    occurrences: dict[str, list[dict[str, object]]] = defaultdict(list)
    for scan_root in SCAN_ROOTS:
        for source in sorted(item for item in scan_root.rglob("*") if item.suffix in SCAN_SUFFIXES):
            text = source.read_text(encoding="utf-8", errors="replace")
            for line_number, line in enumerate(text.splitlines(), 1):
                for match in RESOURCE_RE.finditer(line):
                    occurrences[match.group("path")].append(
                        {
                            "source": source.relative_to(ROOT).as_posix(),
                            "line": line_number,
                        }
                    )

    records = []
    counts: dict[str, int] = defaultdict(int)
    for resource, uses in sorted(occurrences.items()):
        active = resolve(resource)
        if active is None:
            status = "unresolved-or-dynamic"
            official_matches: list[str] = []
            active_path = None
        else:
            digest = sha256(active)
            official_matches = official_hashes.get(digest, [])
            if official_matches:
                status = "official-byte-identical"
            elif resource in DERIVED_OFFICIAL:
                status = "official-derived"
                official_matches = [DERIVED_OFFICIAL[resource]]
            else:
                status = "custom-only"
            active_path = active.relative_to(ROOT).as_posix()
        counts[status] += 1
        records.append(
            {
                "resource": "/" + resource,
                "status": status,
                "active_path": active_path,
                "official_matches": official_matches,
                "uses": uses,
            }
        )

    payload = {
        "schema": "active-ui-asset-provenance-v1",
        "official_version": "15.3x",
        "counts": dict(sorted(counts.items())),
        "resources": records,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload["counts"], indent=2))
    print(f"output: {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
