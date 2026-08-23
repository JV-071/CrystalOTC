#!/usr/bin/env python3
"""Decode the active Tibia soundbank and correlate it with client/server triggers.

The soundbank is protobuf-encoded, but this tool deliberately uses only the
Python standard library. It decodes the small, stable schema documented in
src/protobuf/sounds.proto, validates every referenced OGG, and records explicit
CrystalOTC and crystalserver references by sound ID.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


NUMERIC_SOUND_TYPES = {
    0: "unknown",
    1: "spell_attack",
    2: "spell_healing",
    3: "spell_support",
    4: "weapon_attack",
    5: "creature_noise",
    6: "creature_death",
    7: "creature_attack",
    8: "ambience_stream",
    9: "food_and_drink",
    10: "item_movement",
    11: "event",
    12: "ui",
    13: "whisper_without_open_chat",
    14: "chat_message",
    15: "party",
    16: "vip_list",
    17: "raid_announcement",
    18: "server_message",
    19: "spell_generic",
}

MUSIC_TYPES = {
    0: "unknown",
    1: "music",
    2: "music_immediate",
    3: "music_title",
}

SOURCE_SUFFIXES = {".cpp", ".h", ".hpp", ".lua", ".xml"}
SKIP_PARTS = {".git", "build", "cmake-build-debug", "cmake-build-release"}
NON_TRIGGER_SERVER_FILES = {"src/lua/functions/core/game/lua_enums.cpp"}
TOKEN_RE = re.compile(r"\b[A-Z][A-Z0-9_]+\b")


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while True:
        if offset >= len(data):
            raise ValueError("truncated protobuf varint")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
        if shift > 63:
            raise ValueError("protobuf varint is too large")


def protobuf_fields(data: bytes) -> list[tuple[int, int, int | bytes]]:
    fields: list[tuple[int, int, int | bytes]] = []
    offset = 0
    while offset < len(data):
        key, offset = read_varint(data, offset)
        number, wire_type = key >> 3, key & 7
        if wire_type == 0:
            value, offset = read_varint(data, offset)
        elif wire_type == 1:
            value = data[offset : offset + 8]
            offset += 8
        elif wire_type == 2:
            size, offset = read_varint(data, offset)
            value = data[offset : offset + size]
            offset += size
        elif wire_type == 5:
            value = data[offset : offset + 4]
            offset += 4
        else:
            raise ValueError(f"unsupported protobuf wire type {wire_type}")
        fields.append((number, wire_type, value))
    return fields


def first(fields: list[tuple[int, int, int | bytes]], number: int, default: Any = 0) -> Any:
    return next((value for field, _, value in fields if field == number), default)


def repeated(fields: list[tuple[int, int, int | bytes]], number: int) -> list[Any]:
    return [value for field, _, value in fields if field == number]


def message(value: int | bytes) -> list[tuple[int, int, int | bytes]]:
    if not isinstance(value, bytes):
        raise ValueError("expected a length-delimited protobuf message")
    return protobuf_fields(value)


def text(value: int | bytes) -> str:
    return value.decode("utf-8") if isinstance(value, bytes) else ""


def min_max(value: int | bytes) -> dict[str, float]:
    if not value:
        return {"min": 0.0, "max": 0.0}
    fields = message(value)

    def decode_float(number: int) -> float:
        raw = first(fields, number, b"\0\0\0\0")
        return struct.unpack("<f", raw)[0] if isinstance(raw, bytes) else 0.0

    return {"min": decode_float(1), "max": decode_float(2)}


def parse_soundbank(path: Path) -> dict[str, Any]:
    top = protobuf_fields(path.read_bytes())

    audio_files = []
    for raw in repeated(top, 1):
        fields = message(raw)
        audio_files.append(
            {
                "id": first(fields, 1),
                "filename": text(first(fields, 2, b"")),
                "original_filename": text(first(fields, 3, b"")),
                "is_stream": bool(first(fields, 4)),
            }
        )

    effects = []
    for raw in repeated(top, 2):
        fields = message(raw)
        simple = first(fields, 5, b"")
        random_effect = first(fields, 6, b"")
        audio_file_ids = []
        if simple:
            audio_file_ids.append(first(message(simple), 1))
        if random_effect:
            audio_file_ids.extend(repeated(message(random_effect), 1))
        effect_type = first(fields, 2)
        effects.append(
            {
                "id": first(fields, 1),
                "type_id": effect_type,
                "type": NUMERIC_SOUND_TYPES.get(effect_type, f"unknown_{effect_type}"),
                "random_pitch": min_max(first(fields, 3, b"")),
                "random_volume": min_max(first(fields, 4, b"")),
                "audio_file_ids": audio_file_ids,
            }
        )

    ambience_streams = []
    for raw in repeated(top, 3):
        fields = message(raw)
        delayed = []
        for delayed_raw in repeated(fields, 3):
            delayed_fields = message(delayed_raw)
            delayed.append(
                {
                    "effect_id": first(delayed_fields, 1),
                    "delay_seconds": first(delayed_fields, 2),
                }
            )
        ambience_streams.append(
            {
                "id": first(fields, 1),
                "looping_audio_file_id": first(fields, 2),
                "delayed_effects": delayed,
            }
        )

    object_streams = []
    for raw in repeated(top, 4):
        fields = message(raw)
        thresholds = []
        for effect_raw in repeated(fields, 3):
            effect_fields = message(effect_raw)
            thresholds.append(
                {
                    "count": first(effect_fields, 1),
                    "looping_audio_file_id": first(effect_fields, 2),
                }
            )
        object_streams.append(
            {
                "id": first(fields, 1),
                "item_client_ids": repeated(fields, 2),
                "thresholds": thresholds,
                "max_sound_distance": first(fields, 4),
            }
        )

    music = []
    for raw in repeated(top, 5):
        fields = message(raw)
        music_type = first(fields, 3)
        music.append(
            {
                "id": first(fields, 1),
                "audio_file_id": first(fields, 2),
                "type_id": music_type,
                "type": MUSIC_TYPES.get(music_type, f"unknown_{music_type}"),
            }
        )

    return {
        "audio_files": sorted(audio_files, key=lambda entry: entry["id"]),
        "effects": sorted(effects, key=lambda entry: entry["id"]),
        "ambience_streams": sorted(ambience_streams, key=lambda entry: entry["id"]),
        "object_streams": sorted(object_streams, key=lambda entry: entry["id"]),
        "music": sorted(music, key=lambda entry: entry["id"]),
    }


def parse_cpp_enum(path: Path, enum_name: str) -> dict[int, list[str]]:
    result: dict[int, list[str]] = defaultdict(list)
    inside = False
    start = re.compile(rf"\benum\s+{re.escape(enum_name)}\b")
    entry = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*=\s*(\d+)")
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not inside:
            inside = bool(start.search(line))
            continue
        if line.lstrip().startswith("};"):
            break
        match = entry.match(line)
        if match:
            result[int(match.group(2))].append(match.group(1))
    return dict(result)


def parse_proto_enum(path: Path, enum_name: str) -> dict[int, list[str]]:
    result: dict[int, list[str]] = defaultdict(list)
    inside = False
    start = re.compile(rf"\benum\s+{re.escape(enum_name)}\b")
    entry = re.compile(r"^\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(\d+)\s*;")
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not inside:
            inside = bool(start.search(line))
            continue
        if line.lstrip().startswith("}"):
            break
        match = entry.match(line)
        if match:
            result[int(match.group(2))].append(match.group(1))
    return dict(result)


def parse_client_sound_symbols(client_root: Path) -> dict[int, list[str]]:
    path = client_root / "modules/corelib/const.lua"
    result: dict[int, list[str]] = defaultdict(list)
    current = ""
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        table = re.match(r"(UISoundEffects|ChatSoundEffects)\s*=\s*{", line)
        if table:
            current = table.group(1)
            continue
        if current and line.strip() == "}":
            current = ""
            continue
        if current:
            entry = re.match(r"\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*(\d+)", line)
            if entry:
                result[int(entry.group(2))].append(f"{current}.{entry.group(1)}")
    return dict(result)


def source_files(root: Path):
    for path in root.rglob("*"):
        if path.is_file() and path.suffix in SOURCE_SUFFIXES and not SKIP_PARTS.intersection(path.parts):
            yield path


def find_server_references(
    server_root: Path,
    enum_path: Path,
    enum_groups: dict[str, dict[int, list[str]]],
) -> dict[str, dict[int, list[dict[str, Any]]]]:
    token_map: dict[str, list[tuple[str, int, str]]] = defaultdict(list)
    for group, values in enum_groups.items():
        for sound_id, symbols in values.items():
            for symbol in symbols:
                token_map[symbol].append((group, sound_id, symbol))
                token_map[f"SOUND_EFFECT_TYPE_{symbol}"].append((group, sound_id, symbol))

    references: dict[str, dict[int, list[dict[str, Any]]]] = {
        group: defaultdict(list) for group in enum_groups
    }
    for path in source_files(server_root):
        relative = path.relative_to(server_root).as_posix()
        if relative in NON_TRIGGER_SERVER_FILES:
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            for token in set(TOKEN_RE.findall(line)):
                for group, sound_id, symbol in token_map.get(token, []):
                    if path == enum_path:
                        continue
                    references[group][sound_id].append(
                        {
                            "path": relative,
                            "line": line_number,
                            "symbol": symbol,
                            "text": line.strip()[:240],
                        }
                    )
    return {group: dict(values) for group, values in references.items()}


def add_city_music_references(server_root: Path, references: dict[int, list[dict[str, Any]]]) -> None:
    """Record the numeric music IDs used by crystalserver's city table."""
    path = server_root / "data-global/scripts/custom/city_music.lua"
    if not path.is_file():
        return
    relative = path.relative_to(server_root).as_posix()
    inside = False
    entry = re.compile(r'^\s*\["([^"]+)"\]\s*=\s*(\d+)')
    for line_number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        if not inside:
            inside = bool(re.match(r"\s*local\s+CITY_MUSIC\s*=\s*{", line))
            continue
        if line.strip() == "}":
            break
        match = entry.match(line)
        if match:
            town, music_id = match.group(1), int(match.group(2))
            references.setdefault(music_id, []).append(
                {
                    "path": relative,
                    "line": line_number,
                    "symbol": f'CITY_MUSIC["{town}"]',
                    "text": line.strip()[:240],
                }
            )


def find_client_references(client_root: Path, symbols: dict[int, list[str]]) -> dict[int, list[dict[str, Any]]]:
    symbol_map = {symbol: sound_id for sound_id, names in symbols.items() for symbol in names}
    references: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for path in source_files(client_root):
        relative = path.relative_to(client_root).as_posix()
        for line_number, line in enumerate(path.read_text(encoding="utf-8-sig", errors="replace").splitlines(), 1):
            for symbol, sound_id in symbol_map.items():
                if symbol in line:
                    references[sound_id].append(
                        {"path": relative, "line": line_number, "symbol": symbol, "text": line.strip()[:240]}
                    )
    return dict(references)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_and_enrich(bank: dict[str, Any], sound_dir: Path, dat_path: Path) -> list[str]:
    errors: list[str] = []
    audio_by_id = {entry["id"]: entry for entry in bank["audio_files"]}
    if len(audio_by_id) != len(bank["audio_files"]):
        errors.append("duplicate audio file IDs")

    dat_match = re.fullmatch(r"sounds-([0-9a-f]{64})\.dat", dat_path.name)
    if not dat_match or dat_match.group(1) != sha256(dat_path):
        errors.append(f"soundbank filename hash does not match {dat_path.name}")

    for entry in bank["audio_files"]:
        path = sound_dir / entry["filename"]
        entry["sha256"] = ""
        entry["bytes"] = 0
        if not path.is_file():
            errors.append(f"missing audio file {entry['filename']} (id {entry['id']})")
            continue
        entry["bytes"] = path.stat().st_size
        entry["sha256"] = sha256(path)
        filename_match = re.fullmatch(r"sound-([0-9a-f]{64})\.ogg", entry["filename"])
        if not filename_match or filename_match.group(1) != entry["sha256"]:
            errors.append(f"audio filename hash does not match {entry['filename']}")

    referenced_audio: list[tuple[str, int, int]] = []
    for effect in bank["effects"]:
        referenced_audio.extend(("effect", effect["id"], audio_id) for audio_id in effect["audio_file_ids"])
        effect["audio_files"] = [audio_by_id.get(audio_id) for audio_id in effect["audio_file_ids"]]
    for ambience in bank["ambience_streams"]:
        referenced_audio.append(("ambience", ambience["id"], ambience["looping_audio_file_id"]))
        ambience["looping_audio_file"] = audio_by_id.get(ambience["looping_audio_file_id"])
    for ambient_object in bank["object_streams"]:
        for threshold in ambient_object["thresholds"]:
            referenced_audio.append(("object ambience", ambient_object["id"], threshold["looping_audio_file_id"]))
            threshold["looping_audio_file"] = audio_by_id.get(threshold["looping_audio_file_id"])
    for music in bank["music"]:
        referenced_audio.append(("music", music["id"], music["audio_file_id"]))
        music["audio_file"] = audio_by_id.get(music["audio_file_id"])

    for kind, owner_id, audio_id in referenced_audio:
        if audio_id and audio_id not in audio_by_id:
            errors.append(f"{kind} {owner_id} references missing audio file id {audio_id}")
    return errors


def attach_references(
    bank: dict[str, Any],
    schema_symbols: dict[int, list[str]],
    server_enums: dict[str, dict[int, list[str]]],
    server_references: dict[str, dict[int, list[dict[str, Any]]]],
    client_symbols: dict[int, list[str]],
    client_references: dict[int, list[dict[str, Any]]],
) -> None:
    for effect in bank["effects"]:
        sound_id = effect["id"]
        effect["schema_symbols"] = schema_symbols.get(sound_id, [])
        effect["server_symbols"] = server_enums["effects"].get(sound_id, [])
        effect["server_references"] = server_references["effects"].get(sound_id, [])
        effect["client_symbols"] = client_symbols.get(sound_id, [])
        effect["client_references"] = client_references.get(sound_id, [])
    for ambience in bank["ambience_streams"]:
        sound_id = ambience["id"]
        ambience["server_symbols"] = server_enums["ambience"].get(sound_id, [])
        ambience["server_references"] = server_references["ambience"].get(sound_id, [])
    for music in bank["music"]:
        sound_id = music["id"]
        music["server_symbols"] = server_enums["music"].get(sound_id, [])
        music["server_references"] = server_references["music"].get(sound_id, [])


def build_summary(bank: dict[str, Any], errors: list[str], catalog_file: str) -> dict[str, Any]:
    effect_types = Counter(entry["type"] for entry in bank["effects"])
    return {
        "valid": not errors,
        "validation_errors": errors,
        "catalog_file": catalog_file,
        "audio_files": len(bank["audio_files"]),
        "streaming_audio_files": sum(entry["is_stream"] for entry in bank["audio_files"]),
        "numeric_effects": len(bank["effects"]),
        "effect_type_counts": dict(sorted(effect_types.items())),
        "ambience_streams": len(bank["ambience_streams"]),
        "object_ambience_streams": len(bank["object_streams"]),
        "music_templates": len(bank["music"]),
        "server_defined_effects": sum(bool(entry["server_symbols"]) for entry in bank["effects"]),
        "server_referenced_effects": sum(bool(entry["server_references"]) for entry in bank["effects"]),
        "server_defined_ambience_streams": sum(bool(entry["server_symbols"]) for entry in bank["ambience_streams"]),
        "server_referenced_ambience_streams": sum(bool(entry["server_references"]) for entry in bank["ambience_streams"]),
        "server_defined_music_templates": sum(bool(entry["server_symbols"]) for entry in bank["music"]),
        "server_referenced_music_templates": sum(bool(entry["server_references"]) for entry in bank["music"]),
        "client_local_effects": sum(bool(entry["client_references"]) for entry in bank["effects"]),
    }


def coverage_gaps(bank: dict[str, Any], server_enums: dict[str, dict[int, list[str]]]) -> dict[str, Any]:
    groups = {
        "effects": {entry["id"] for entry in bank["effects"]},
        "ambience": {entry["id"] for entry in bank["ambience_streams"]},
        "music": {entry["id"] for entry in bank["music"]},
    }
    result = {}
    for group, bank_ids in groups.items():
        server_ids = set(server_enums[group])
        result[group] = {
            "bank_ids_without_server_symbol": sorted(bank_ids - server_ids),
            "server_ids_absent_from_bank": sorted(server_ids - bank_ids),
        }
    return result


def markdown_report(inventory: dict[str, Any]) -> str:
    summary = inventory["summary"]
    gaps = inventory["coverage_gaps"]

    def gap_ids(values: list[int]) -> str:
        return f" (`{', '.join(map(str, values))}`)" if 0 < len(values) <= 20 else ""

    lines = [
        "# Official 15.32 sound inventory",
        "",
        "This report is generated from the active shared `/sounds/` bank. Both the current 15.25 profile and 15.30 use this bank.",
        "",
        f"- Validation: **{'passed' if summary['valid'] else 'failed'}**",
        f"- Bank: `{summary['catalog_file']}`",
        f"- Audio files: {summary['audio_files']} ({summary['streaming_audio_files']} streamed)",
        f"- Numeric effects: {summary['numeric_effects']}",
        f"- Location ambience templates: {summary['ambience_streams']}",
        f"- Item ambience templates: {summary['object_ambience_streams']}",
        f"- Music templates: {summary['music_templates']}",
        "",
        "## Trigger coverage",
        "",
        "| Family | In bank | Named by server | Explicitly referenced by server |",
        "| --- | ---: | ---: | ---: |",
        f"| Numeric effects | {summary['numeric_effects']} | {summary['server_defined_effects']} | {summary['server_referenced_effects']} |",
        f"| Location ambience | {summary['ambience_streams']} | {summary['server_defined_ambience_streams']} | {summary['server_referenced_ambience_streams']} |",
        f"| Music | {summary['music_templates']} | {summary['server_defined_music_templates']} | {summary['server_referenced_music_templates']} |",
        "",
        "Item ambience is client-driven: its item IDs, distance, count thresholds, and selected OGGs are recorded in the JSON inventory. World locations for ambience and music are server behavior and therefore appear as server references, not as soundbank metadata.",
        "",
        "## Known mapping gaps",
        "",
        f"- Numeric effects in the bank without a crystalserver symbol: {len(gaps['effects']['bank_ids_without_server_symbol'])}{gap_ids(gaps['effects']['bank_ids_without_server_symbol'])}",
        f"- Location ambiences without a crystalserver symbol: {len(gaps['ambience']['bank_ids_without_server_symbol'])}{gap_ids(gaps['ambience']['bank_ids_without_server_symbol'])}",
        f"- Music templates without a crystalserver symbol: {len(gaps['music']['bank_ids_without_server_symbol'])}{gap_ids(gaps['music']['bank_ids_without_server_symbol'])}",
        "",
        "The JSON inventory contains the complete ID lists and every discovered source reference. New 15.32 ambience and music IDs retain neutral server names until packet capture confirms their canonical labels; region mappings are limited to map content and asset chronology.",
        "",
        "## Numeric effect categories",
        "",
        "| Category | Count |",
        "| --- | ---: |",
    ]
    lines.extend(f"| `{name}` | {count} |" for name, count in summary["effect_type_counts"].items())
    lines.extend(
        [
            "",
            "## Reproduce",
            "",
            "Run from the CrystalOTC repository root:",
            "",
            "```sh",
            "python3 tools/generate_sound_inventory.py --server-root ../crystalserver",
            "```",
            "",
            "Use `--check` in CI or before committing to verify that the checked-in JSON and this report still match the bank and both codebases.",
            "",
        ]
    )
    if summary["validation_errors"]:
        lines.extend(["## Validation errors", ""])
        lines.extend(f"- {error}" for error in summary["validation_errors"])
        lines.append("")
    return "\n".join(lines)


def write_or_check(path: Path, content: str, check: bool) -> bool:
    if check:
        return path.is_file() and path.read_text(encoding="utf-8") == content
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--server-root", type=Path, default=Path("../crystalserver"))
    parser.add_argument("--sound-dir", type=Path)
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    parser.add_argument("--check", action="store_true", help="fail if checked-in output differs")
    args = parser.parse_args()

    client_root = args.client_root.resolve()
    server_root = args.server_root.resolve()
    sound_dir = (args.sound_dir or client_root / "data/sounds").resolve()
    json_output = args.json_output or client_root / "docs/sound-parity/sound-inventory-15.32.json"
    markdown_output = args.markdown_output or client_root / "docs/sound-parity/README.md"

    catalog_path = sound_dir / "catalog-sound.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    sound_entries = [entry for entry in catalog if entry.get("type") == "sounds"]
    if len(sound_entries) != 1:
        raise ValueError(f"expected exactly one sounds entry in {catalog_path}")
    dat_path = sound_dir / sound_entries[0]["file"]

    bank = parse_soundbank(dat_path)
    errors = validate_and_enrich(bank, sound_dir, dat_path)

    enum_path = server_root / "src/creatures/creatures_definitions.hpp"
    if not enum_path.is_file():
        raise FileNotFoundError(f"crystalserver enum file not found: {enum_path}")
    server_enums = {
        "effects": parse_cpp_enum(enum_path, "SoundEffect_t"),
        "ambience": parse_cpp_enum(enum_path, "SoundAmbientEffect_t"),
        "music": parse_cpp_enum(enum_path, "SoundMusicEffect_t"),
    }
    server_references = find_server_references(server_root, enum_path, server_enums)
    add_city_music_references(server_root, server_references["music"])
    schema_symbols = parse_proto_enum(client_root / "src/protobuf/sounds.proto", "ESoundEffectType")
    client_symbols = parse_client_sound_symbols(client_root)
    client_references = find_client_references(client_root, client_symbols)
    attach_references(bank, schema_symbols, server_enums, server_references, client_symbols, client_references)

    inventory = {
        "format_version": 1,
        "generated_by": "tools/generate_sound_inventory.py",
        "soundbank_sha256": sha256(dat_path),
        "summary": build_summary(bank, errors, dat_path.name),
        "coverage_gaps": coverage_gaps(bank, server_enums),
        **bank,
    }
    json_content = json.dumps(inventory, indent=2, sort_keys=True) + "\n"
    markdown_content = markdown_report(inventory)

    json_ok = write_or_check(json_output, json_content, args.check)
    markdown_ok = write_or_check(markdown_output, markdown_content, args.check)
    if args.check and not (json_ok and markdown_ok):
        if not json_ok:
            print(f"out of date: {json_output}", file=sys.stderr)
        if not markdown_ok:
            print(f"out of date: {markdown_output}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(
        f"sound inventory: {len(bank['audio_files'])} files, {len(bank['effects'])} effects, "
        f"{len(bank['ambience_streams'])} ambiences, {len(bank['object_streams'])} object ambiences, "
        f"{len(bank['music'])} music templates"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
