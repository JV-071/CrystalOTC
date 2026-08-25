#!/usr/bin/env python3
"""Generate searchable UI-parity inventories from recovered official QML.

The output connects QML components to direct resource URLs, asset literals,
TibiaStyle tokens, imports, component dependencies, and layout assignments.
It is deliberately a static inventory: screenshots remain the authority for
rendered geometry and state-dependent behaviour.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
from collections import defaultdict
from pathlib import Path, PurePosixPath


DEFAULT_QML_MANIFEST = Path("data/official-client-15.3x/qml-resources-manifest.json")
DEFAULT_GRAPHICS_MANIFEST = Path(
    "data/official-client-15.3x/graphics-resources-manifest.json"
)
DEFAULT_OUTPUT_DIR = Path("docs/ui-parity")

ASSET_EXTENSIONS = "png|jpg|jpeg|webp|svg|gif|bmp|wav|ogg|fnt|json|qsb"
DIRECT_ASSET_RE = re.compile(
    rf"(?:qrc:)?(?P<path>/(?:images|animations|cursors|fonts|data|sounds|shaders)/"
    rf"[A-Za-z0-9_./@+%() -]+\.(?:{ASSET_EXTENSIONS}))",
    re.IGNORECASE,
)
STRING_ASSET_RE = re.compile(
    rf"(?P<quote>['\"])(?P<path>[^'\"\n]+\.(?:{ASSET_EXTENSIONS}))(?P=quote)",
    re.IGNORECASE,
)
STYLE_REFERENCE_RE = re.compile(r"\bTibiaStyle\.(?P<name>[A-Za-z_]\w*)")
IMPORT_RE = re.compile(r"^\s*import\s+(?P<target>[^\s;]+)", re.MULTILINE)
QML_TYPE_RE = re.compile(r"^\s*(?P<name>[A-Z][A-Za-z0-9_]*)\s*\{", re.MULTILINE)
ROOT_TYPE_RE = re.compile(r"^\s*(?P<name>[A-Za-z_][A-Za-z0-9_.]*)\s*\{")
ASSIGNMENT_RE = re.compile(
    r"^\s*(?P<name>(?:Layout\.|anchors\.)?[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?)"
    r"\s*:\s*(?P<value>.+?)\s*;?\s*(?://.*)?$"
)
STYLE_TOKEN_RE = re.compile(
    r"^\s*(?P<readonly>readonly\s+)?property\s+(?P<type>[A-Za-z_]\w*)\s+"
    r"(?P<name>[A-Za-z_]\w*)\s*:\s*(?P<value>.+?)\s*;?\s*(?://.*)?$"
)

LAYOUT_PROPERTY_NAMES = {
    "width",
    "height",
    "implicitWidth",
    "implicitHeight",
    "minimumWidth",
    "minimumHeight",
    "maximumWidth",
    "maximumHeight",
    "preferredWidth",
    "preferredHeight",
    "spacing",
    "padding",
    "leftPadding",
    "rightPadding",
    "topPadding",
    "bottomPadding",
    "horizontalSpacing",
    "verticalSpacing",
    "cellWidth",
    "cellHeight",
    "columns",
    "rows",
    "rowSpacing",
    "columnSpacing",
    "mapWindowMargin",
}


def load_json(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read {path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{path} must contain a JSON object")
    return value


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalize_resource_path(value: str) -> str:
    if value.startswith("qrc:"):
        value = value[4:]
    return "/" + value.lstrip("/")


def png_dimensions(path: Path) -> list[int] | None:
    try:
        with path.open("rb") as handle:
            header = handle.read(24)
    except OSError:
        return None
    if len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR":
        width, height = struct.unpack(">II", header[16:24])
        return [width, height]
    return None


def is_layout_property(name: str) -> bool:
    leaf = name.rsplit(".", 1)[-1]
    return (
        leaf in LAYOUT_PROPERTY_NAMES
        or leaf.endswith("Margin")
        or leaf.endswith("Margins")
    )


def find_root_type(lines: list[str]) -> str | None:
    in_block_comment = False
    for line in lines:
        stripped = line.strip()
        if in_block_comment:
            if "*/" in stripped:
                in_block_comment = False
            continue
        if stripped.startswith("/*"):
            in_block_comment = "*/" not in stripped
            continue
        if not stripped or stripped.startswith("//"):
            continue
        if stripped.startswith(("import ", "pragma ")):
            continue
        match = ROOT_TYPE_RE.match(line)
        if match:
            return match.group("name")
    return None


def component_record(
    resource: dict,
    graphics_paths: set[str],
    graphics_by_basename: dict[str, list[str]],
) -> dict:
    snapshot_path = Path(resource["snapshot_path"])
    try:
        raw = snapshot_path.read_bytes()
        text = raw.decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise RuntimeError(f"cannot read QML resource {snapshot_path}: {error}") from error
    lines = text.splitlines()

    direct_references = []
    literal_references = []
    style_references = []
    layout_assignments = []
    for line_number, line in enumerate(lines, 1):
        direct_paths_on_line = set()
        for match in DIRECT_ASSET_RE.finditer(line):
            path = normalize_resource_path(match.group("path"))
            direct_paths_on_line.add(path)
            direct_references.append(
                {
                    "path": path,
                    "line": line_number,
                    "expression": line.strip(),
                    "exists_in_graphics_rcc": path in graphics_paths,
                }
            )
        for match in STRING_ASSET_RE.finditer(line):
            literal = match.group("path")
            normalized = normalize_resource_path(literal) if literal.startswith(("/", "qrc:")) else None
            if normalized in direct_paths_on_line:
                continue
            basename = PurePosixPath(literal).name
            candidates = graphics_by_basename.get(basename, [])
            literal_references.append(
                {
                    "literal": literal,
                    "line": line_number,
                    "expression": line.strip(),
                    "exact_resource_path": (
                        normalized if normalized is not None and normalized in graphics_paths else None
                    ),
                    "basename_candidates": candidates,
                }
            )
        for match in STYLE_REFERENCE_RE.finditer(line):
            style_references.append(
                {
                    "token": match.group("name"),
                    "line": line_number,
                    "expression": line.strip(),
                }
            )
        assignment = ASSIGNMENT_RE.match(line)
        if assignment and is_layout_property(assignment.group("name")):
            value = assignment.group("value").strip()
            if len(value) <= 240:
                layout_assignments.append(
                    {
                        "property": assignment.group("name"),
                        "value": value,
                        "line": line_number,
                    }
                )

    imports = sorted(set(match.group("target") for match in IMPORT_RE.finditer(text)))
    qml_types = sorted(set(match.group("name") for match in QML_TYPE_RE.finditer(text)))
    return {
        "resource_path": resource["resource_path"],
        "snapshot_path": resource["snapshot_path"],
        "component": snapshot_path.stem,
        "root_type": find_root_type(lines),
        "bytes": len(raw),
        "lines": len(lines),
        "sha256": sha256_bytes(raw),
        "imports": imports,
        "qml_types_used": qml_types,
        "asset_references": direct_references,
        "asset_literals": literal_references,
        "style_references": style_references,
        "layout_assignments": layout_assignments,
    }


def style_tokens(component: dict) -> list[dict]:
    path = Path(component["snapshot_path"])
    text = path.read_text(encoding="utf-8")
    tokens = []
    for line_number, line in enumerate(text.splitlines(), 1):
        match = STYLE_TOKEN_RE.match(line)
        if not match:
            continue
        tokens.append(
            {
                "name": match.group("name"),
                "type": match.group("type"),
                "readonly": bool(match.group("readonly")),
                "value": match.group("value").strip(),
                "line": line_number,
            }
        )
    return tokens


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate component/asset/layout inventories from recovered official QML."
    )
    parser.add_argument("--qml-manifest", type=Path, default=DEFAULT_QML_MANIFEST)
    parser.add_argument("--graphics-manifest", type=Path, default=DEFAULT_GRAPHICS_MANIFEST)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument(
        "--active-data-root",
        type=Path,
        default=Path("data"),
        help="CrystalOTC data root used to report identical/different/missing active assets",
    )
    return parser.parse_args()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    try:
        qml_manifest = load_json(args.qml_manifest)
        graphics_manifest = load_json(args.graphics_manifest)
        graphics_resources = graphics_manifest.get("resources", [])
        graphics_by_path = {
            resource["resource_path"]: resource
            for resource in graphics_resources
            if isinstance(resource, dict) and "resource_path" in resource
        }
        graphics_by_basename: dict[str, list[str]] = defaultdict(list)
        for path in graphics_by_path:
            graphics_by_basename[PurePosixPath(path).name].append(path)
        for paths in graphics_by_basename.values():
            paths.sort()

        qml_resources = [
            resource
            for resource in qml_manifest.get("resources", [])
            if resource.get("resource_path", "").endswith(".qml")
        ]
        components = [
            component_record(resource, set(graphics_by_path), graphics_by_basename)
            for resource in qml_resources
        ]
        components.sort(key=lambda component: component["resource_path"])
    except (RuntimeError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    usage: dict[str, list[dict]] = defaultdict(list)
    unresolved_direct: dict[str, list[dict]] = defaultdict(list)
    literal_candidates: dict[str, list[dict]] = defaultdict(list)
    for component in components:
        for reference in component["asset_references"]:
            location = {
                "component": component["component"],
                "qml_path": component["resource_path"],
                "line": reference["line"],
                "expression": reference["expression"],
            }
            if reference["exists_in_graphics_rcc"]:
                usage[reference["path"]].append(location)
            else:
                unresolved_direct[reference["path"]].append(location)
        for reference in component["asset_literals"]:
            for candidate in reference["basename_candidates"]:
                literal_candidates[candidate].append(
                    {
                        "component": component["component"],
                        "qml_path": component["resource_path"],
                        "line": reference["line"],
                        "literal": reference["literal"],
                        "expression": reference["expression"],
                    }
                )

    asset_records = []
    for path, resource in sorted(graphics_by_path.items()):
        snapshot_path = Path(resource["snapshot_path"])
        active_path = args.active_data_root.joinpath(*PurePosixPath(path.lstrip("/")).parts)
        active_sha256 = None
        active_status = "missing"
        try:
            active_bytes = active_path.read_bytes()
        except (FileNotFoundError, IsADirectoryError):
            pass
        except OSError as error:
            print(f"error: cannot read active asset {active_path}: {error}", file=sys.stderr)
            return 1
        else:
            active_sha256 = sha256_bytes(active_bytes)
            active_status = (
                "identical" if active_sha256 == resource.get("sha256") else "different"
            )
        record = {
            "resource_path": path,
            "snapshot_path": resource["snapshot_path"],
            "bytes": resource.get("bytes"),
            "sha256": resource.get("sha256"),
            "dimensions": png_dimensions(snapshot_path),
            "active_path": active_path.as_posix(),
            "active_status": active_status,
            "active_sha256": active_sha256,
            "direct_references": usage.get(path, []),
            "literal_candidates": literal_candidates.get(path, []),
        }
        asset_records.append(record)

    style_component = next(
        (component for component in components if component["component"] == "TibiaStyle"),
        None,
    )
    if style_component is None:
        print("error: recovered QML does not contain TibiaStyle.qml", file=sys.stderr)
        return 1
    try:
        tokens = style_tokens(style_component)
    except OSError as error:
        print(f"error: cannot read TibiaStyle.qml: {error}", file=sys.stderr)
        return 1

    referenced_style_tokens: dict[str, set[str]] = defaultdict(set)
    for component in components:
        for reference in component["style_references"]:
            referenced_style_tokens[reference["token"]].add(component["component"])
    token_records = []
    for token in tokens:
        token_records.append(
            {
                **token,
                "referenced_by": sorted(referenced_style_tokens.get(token["name"], set())),
            }
        )

    direct_reference_count = sum(len(value) for value in usage.values())
    directly_used_records = [record for record in asset_records if record["direct_references"]]
    directly_used_active_status = {
        status: sum(record["active_status"] == status for record in directly_used_records)
        for status in ("identical", "different", "missing")
    }
    summary = {
        "qml_component_count": len(components),
        "qml_bytes": sum(component["bytes"] for component in components),
        "qml_lines": sum(component["lines"] for component in components),
        "graphics_resource_count": len(asset_records),
        "directly_referenced_graphics_count": len(usage),
        "direct_reference_occurrences": direct_reference_count,
        "unresolved_direct_path_count": len(unresolved_direct),
        "assets_with_literal_candidates": sum(
            bool(record["literal_candidates"]) for record in asset_records
        ),
        "directly_used_active_assets": directly_used_active_status,
        "style_token_count": len(token_records),
    }

    inventory = {
        "format": 1,
        "source_qml_manifest": args.qml_manifest.as_posix(),
        "summary": summary,
        "components": components,
    }
    asset_usage = {
        "format": 1,
        "source_graphics_manifest": args.graphics_manifest.as_posix(),
        "summary": summary,
        "unresolved_direct_references": dict(sorted(unresolved_direct.items())),
        "assets": asset_records,
    }
    style_inventory = {
        "format": 1,
        "source_qml_path": style_component["resource_path"],
        "summary": {
            "token_count": len(token_records),
            "referenced_token_count": sum(bool(token["referenced_by"]) for token in token_records),
        },
        "tokens": token_records,
    }

    try:
        write_json(args.output_dir / "official-qml-inventory.json", inventory)
        write_json(args.output_dir / "official-asset-usage.json", asset_usage)
        write_json(args.output_dir / "official-style-tokens.json", style_inventory)
        summary_lines = [
            "# Generated official-client UI inventory",
            "",
            "This file is generated by `tools/generate_ui_parity_inventory.py`.",
            "",
            f"- Recovered QML components: {summary['qml_component_count']:,}",
            f"- Recovered QML lines: {summary['qml_lines']:,}",
            f"- Graphics RCC resources: {summary['graphics_resource_count']:,}",
            f"- Directly referenced graphics: {summary['directly_referenced_graphics_count']:,}",
            f"- Direct resource-reference occurrences: {summary['direct_reference_occurrences']:,}",
            f"- Unresolved direct resource paths: {summary['unresolved_direct_path_count']:,}",
            "- Directly used active assets: "
            f"{directly_used_active_status['identical']:,} identical, "
            f"{directly_used_active_status['different']:,} different, "
            f"{directly_used_active_status['missing']:,} missing",
            f"- Extracted TibiaStyle tokens: {summary['style_token_count']:,}",
            "",
            "The JSON inventories retain source line numbers and expressions. Dynamic QML",
            "resource construction is recorded as basename candidates and still requires",
            "source inspection or a runtime screenshot to disambiguate.",
            "",
        ]
        (args.output_dir / "generated-summary.md").write_text(
            "\n".join(summary_lines), encoding="utf-8"
        )
    except OSError as error:
        print(f"error: cannot write inventory: {error}", file=sys.stderr)
        return 1

    print(
        f"inventoried {summary['qml_component_count']} QML components, "
        f"{summary['directly_referenced_graphics_count']} directly referenced graphics, "
        f"and {summary['style_token_count']} TibiaStyle tokens"
    )
    print(f"output: {args.output_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
