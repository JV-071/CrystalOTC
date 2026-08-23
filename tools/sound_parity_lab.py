#!/usr/bin/env python3
"""Capture, identify, and compare official Tibia and CrystalOTC sound timelines.

The tool intentionally depends only on Python's standard library plus ffmpeg.
ffmpeg performs the spectral transform; SQLite keeps the 15.32 soundbank index
small enough to query without loading millions of fingerprints into memory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import time
from collections import Counter, defaultdict
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INVENTORY = ROOT / "docs/sound-parity/sound-inventory-15.32.json"
DEFAULT_SOUND_DIR = ROOT / "data/official-client-15.3x/sound-assets"
DEFAULT_INDEX = ROOT / "build/sound-parity/sound-fingerprints-15.32.sqlite3"
FPS = 20
BANDS = 32
HEIGHT = 32
SHINGLE_FRAMES = 6


def require_program(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"required program not found: {name}")
    return path


def spectrum_frames(path: Path) -> list[tuple[int, int]]:
    """Return volume-resistant (dominant, secondary) frequency bands at 20 Hz."""
    ffmpeg = require_program("ffmpeg")
    command = [
        ffmpeg,
        "-v", "error",
        "-i", str(path),
        "-filter_complex",
        f"showfreqs=s={BANDS}x{HEIGHT}:mode=bar:ascale=log:fscale=log:rate={FPS}",
        "-f", "rawvideo",
        "-pix_fmt", "gray",
        "-",
    ]
    result = subprocess.run(command, check=True, stdout=subprocess.PIPE)
    frame_bytes = BANDS * HEIGHT
    if len(result.stdout) % frame_bytes:
        raise RuntimeError(f"ffmpeg returned a partial spectrum frame for {path}")

    signatures: list[tuple[int, int]] = []
    for start in range(0, len(result.stdout), frame_bytes):
        frame = result.stdout[start : start + frame_bytes]
        heights = [0] * BANDS
        for band in range(BANDS):
            heights[band] = sum(frame[row * BANDS + band] > 8 for row in range(HEIGHT))
        ranked = sorted(range(BANDS), key=lambda band: (heights[band], band), reverse=True)
        if not ranked or heights[ranked[0]] == 0:
            signatures.append((255, 255))
        else:
            secondary = ranked[1] if len(ranked) > 1 and heights[ranked[1]] else ranked[0]
            signatures.append((ranked[0], secondary))
    return signatures


def audio_peak_db(path: Path) -> float:
    ffmpeg = require_program("ffmpeg")
    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-i", str(path), "-vn", "-af", "volumedetect", "-f", "null", "-"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    match = re.search(r"max_volume:\s+(-?\d+(?:\.\d+)?)\s+dB", result.stderr)
    return float(match.group(1)) if match else float("-inf")


def rms_envelope(path: Path, frame_samples: int = 480) -> list[tuple[float, float]]:
    ffmpeg = require_program("ffmpeg")
    result = subprocess.run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "info", "-i", str(path), "-vn", "-af",
            f"asetnsamples=n={frame_samples}:p=1,astats=metadata=1:reset=1,"
            "ametadata=print:key=lavfi.astats.Overall.RMS_level",
            "-f", "null", "-",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    )
    envelope: list[tuple[float, float]] = []
    timestamp: float | None = None
    for line in result.stderr.splitlines():
        time_match = re.search(r"\bpts_time:(-?\d+(?:\.\d+)?)", line)
        if time_match:
            timestamp = float(time_match.group(1))
            continue
        level_match = re.search(r"RMS_level=(-?\d+(?:\.\d+)?|-inf)", line)
        if level_match and timestamp is not None:
            value = level_match.group(1)
            envelope.append((timestamp, float(value) if value != "-inf" else float("-inf")))
            timestamp = None
    return envelope


def first_audible_frame(
    envelope: list[tuple[float, float]], start_seconds: float, end_seconds: float, threshold_db: float
) -> tuple[float, float] | None:
    return next(
        ((timestamp, level) for timestamp, level in envelope
         if start_seconds <= timestamp <= end_seconds and level >= threshold_db),
        None,
    )


def shingle_keys(frames: list[tuple[int, int]]) -> Iterable[tuple[str, bytes, int]]:
    for offset in range(0, len(frames) - SHINGLE_FRAMES + 1):
        window = frames[offset : offset + SHINGLE_FRAMES]
        if sum(primary == 255 for primary, _ in window) > 1:
            continue

        absolute = bytes(value for frame in window for value in frame)
        yield "absolute", hashlib.blake2b(absolute, digest_size=10).digest(), offset

        anchor = window[0][0]
        relative_values: list[int] = []
        for primary, secondary in window:
            if primary == 255:
                relative_values.extend((255, 255))
            else:
                relative_values.extend((primary - anchor + 64, secondary - primary + 64))
        relative = bytes(max(0, min(255, value)) for value in relative_values)
        yield "relative", hashlib.blake2b(relative, digest_size=10).digest(), offset


def has_substantial_overlap(asset_frames: int, capture_frames: int, overlap: int) -> bool:
    minimum = max(SHINGLE_FRAMES * 2, round(min(asset_frames, capture_frames) * 0.25))
    return overlap >= minimum


def sound_owners(inventory: dict[str, Any]) -> dict[int, list[dict[str, Any]]]:
    owners: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for effect in inventory["effects"]:
        for audio_id in effect["audio_file_ids"]:
            owners[audio_id].append({"kind": "effect", "id": effect["id"], "type": effect["type"]})
    for ambience in inventory["ambience_streams"]:
        owners[ambience["looping_audio_file_id"]].append({"kind": "ambience", "id": ambience["id"]})
    for item in inventory["object_streams"]:
        for threshold in item["thresholds"]:
            owners[threshold["looping_audio_file_id"]].append(
                {"kind": "item_ambience", "id": item["id"], "count": threshold["count"]}
            )
    for music in inventory["music"]:
        owners[music["audio_file_id"]].append({"kind": "music", "id": music["id"], "type": music["type"]})
    return owners


def create_index(args: argparse.Namespace) -> int:
    inventory = json.loads(args.inventory.read_text(encoding="utf-8"))
    owners = sound_owners(inventory)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        args.output.unlink()

    database = sqlite3.connect(args.output)
    database.executescript(
        """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE assets(
            audio_id INTEGER PRIMARY KEY,
            filename TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            frames INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            owners_json TEXT NOT NULL
        );
        CREATE TABLE hashes(
            kind TEXT NOT NULL,
            hash BLOB NOT NULL,
            audio_id INTEGER NOT NULL,
            frame_offset INTEGER NOT NULL
        );
        CREATE INDEX hashes_lookup ON hashes(kind, hash);
        """
    )
    metadata = {
        "schema": "crystal-sound-fingerprint-v1",
        "soundbank_sha256": inventory["soundbank_sha256"],
        "fps": str(FPS),
        "bands": str(BANDS),
        "height": str(HEIGHT),
        "shingle_frames": str(SHINGLE_FRAMES),
    }
    database.executemany("INSERT INTO metadata VALUES (?, ?)", metadata.items())

    entries = inventory["audio_files"][: args.limit or None]
    for number, entry in enumerate(entries, 1):
        path = args.sound_dir / entry["filename"]
        if not path.is_file():
            raise FileNotFoundError(path)
        frames = spectrum_frames(path)
        database.execute(
            "INSERT INTO assets VALUES (?, ?, ?, ?, ?, ?)",
            (
                entry["id"], entry["filename"], entry.get("original_filename", ""), len(frames),
                round(len(frames) * 1000 / FPS), json.dumps(owners.get(entry["id"], []), separators=(",", ":")),
            ),
        )
        database.executemany(
            "INSERT INTO hashes VALUES (?, ?, ?, ?)",
            ((kind, key, entry["id"], offset) for kind, key, offset in shingle_keys(frames)),
        )
        if number % 25 == 0 or number == len(entries):
            database.commit()
            print(f"indexed {number}/{len(entries)} audio files", file=sys.stderr)

    database.execute("ANALYZE")
    database.commit()
    database.close()
    print(args.output)
    return 0


def load_capture_epoch(metadata_path: Path | None) -> int:
    if not metadata_path:
        return 0
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    return int(metadata.get("firstSampleEpochUs") or metadata.get("startedEpochUs") or 0)


def identify(args: argparse.Namespace) -> int:
    peak_db = audio_peak_db(args.recording)
    if peak_db <= args.silence_threshold_db:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text("", encoding="utf-8")
        print(
            f"capture is silent (peak {peak_db:.1f} dB <= {args.silence_threshold_db:.1f} dB); "
            f"identified 0 occurrence(s) -> {args.output}"
        )
        return 0

    database = sqlite3.connect(args.index)
    index_metadata = dict(database.execute("SELECT key, value FROM metadata"))
    if int(index_metadata["fps"]) != FPS or int(index_metadata["shingle_frames"]) != SHINGLE_FRAMES:
        raise RuntimeError("fingerprint index parameters do not match this tool")

    capture_frames = spectrum_frames(args.recording)
    database.execute("CREATE TEMP TABLE capture_hashes(kind TEXT, hash BLOB, frame_offset INTEGER)")
    database.executemany(
        "INSERT INTO capture_hashes VALUES (?, ?, ?)",
        ((kind, key, offset) for kind, key, offset in shingle_keys(capture_frames)),
    )
    database.execute("CREATE INDEX capture_lookup ON capture_hashes(kind, hash)")

    # Hashes shared by a huge fraction of the bank are silence/noise patterns;
    # excluding them prevents a quiet capture from manufacturing matches.
    rows = database.execute(
        """
        WITH useful_hashes AS (
            SELECT kind, hash
            FROM hashes
            GROUP BY kind, hash
            HAVING COUNT(DISTINCT audio_id) <= ?
        )
        SELECT h.audio_id, h.kind, c.frame_offset - h.frame_offset AS alignment, COUNT(*) AS votes,
               a.frames, a.filename, a.original_filename, a.owners_json
        FROM capture_hashes c
        JOIN useful_hashes u ON u.kind = c.kind AND u.hash = c.hash
        JOIN hashes h ON h.kind = c.kind AND h.hash = c.hash
        JOIN assets a ON a.audio_id = h.audio_id
        GROUP BY h.audio_id, h.kind, alignment
        HAVING votes >= ?
        ORDER BY votes DESC
        """,
        (args.max_hash_assets, args.min_votes),
    ).fetchall()

    candidates: list[dict[str, Any]] = []
    for audio_id, kind, alignment, votes, asset_frames, filename, original_filename, owners_json in rows:
        asset_start = max(0, -alignment)
        capture_start = max(0, alignment)
        overlap = min(asset_frames - asset_start, len(capture_frames) - capture_start)
        # A handful of matching shingles at the very tail of a long asset can
        # otherwise score as 100% confidence because the denominator is tiny.
        # Require enough of the shorter side to be observable before treating
        # the alignment as an occurrence. This still permits sounds already in
        # progress when capture begins, including looping music and ambience.
        if not has_substantial_overlap(asset_frames, len(capture_frames), overlap):
            continue
        expected = max(1, overlap - SHINGLE_FRAMES + 1)
        confidence = min(1.0, votes / expected)
        if confidence < args.min_confidence:
            continue
        candidates.append(
            {
                "audio_file_id": audio_id,
                "fingerprint_kind": kind,
                "frame_offset": alignment,
                "offset_ms": round(alignment * 1000 / FPS),
                "votes": votes,
                "confidence": round(confidence, 4),
                "asset_frames": asset_frames,
                "filename": filename,
                "original_filename": original_filename,
                "owners": json.loads(owners_json),
            }
        )

    # Keep the strongest explanation for near-identical alignments of one file.
    selected: list[dict[str, Any]] = []
    for candidate in sorted(candidates, key=lambda item: (-item["confidence"], -item["votes"])):
        if any(
            existing["audio_file_id"] == candidate["audio_file_id"]
            and abs(existing["frame_offset"] - candidate["frame_offset"]) <= FPS // 2
            for existing in selected
        ):
            continue
        selected.append(candidate)
    selected.sort(key=lambda item: item["frame_offset"])

    first_epoch_us = load_capture_epoch(args.metadata)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as output:
        for sequence, match in enumerate(selected):
            session_us = round(match["frame_offset"] * 1_000_000 / FPS)
            event = {
                "schema": "crystal-sound-trace-v1",
                "producer": "official-client",
                "seq": sequence,
                "session_us": session_us,
                "epoch_us": first_epoch_us + session_us if first_epoch_us else 0,
                "event": "audio.match",
                "data": match,
            }
            output.write(json.dumps(event, separators=(",", ":")) + "\n")
    print(f"identified {len(selected)} occurrence(s) -> {args.output}")
    return 0


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    events = []
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            if not line.strip():
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
    return events


def event_time_us(event: dict[str, Any]) -> int:
    return int(event.get("session_us") or event.get("epoch_us") or 0)


def audio_timeline(events: list[dict[str, Any]], official: bool) -> list[dict[str, Any]]:
    accepted = {"effect.play", "ambience.play", "music.play", "item_ambience.play"}
    timeline = []
    for event in events:
        if official and event.get("event") != "audio.match":
            continue
        if not official and event.get("event") not in accepted:
            continue
        data = event.get("data", {})
        if "audio_file_id" not in data:
            continue
        timeline.append({"audio_file_id": int(data["audio_file_id"]), "time_us": event_time_us(event), "event": event})
    return sorted(timeline, key=lambda item: item["time_us"])


def packet_timeline(events: list[dict[str, Any]], server: bool) -> list[dict[str, Any]]:
    timeline = []
    for event in events:
        data = event.get("data", {})
        if server and event.get("event") == "server.send_sound_effect":
            for role in ("main", "secondary"):
                value = data.get(role)
                if value:
                    timeline.append(
                        {
                            "packet_kind": "effect",
                            "effect_id": int(value["effect_id"]),
                            "time_us": int(event.get("epoch_us", 0)),
                            "world": data.get("world"),
                            "role": role,
                        }
                    )
        elif server and event.get("event") == "server.send_anthem":
            timeline.append(
                {
                    "packet_kind": "anthem",
                    "anthem_kind": data["kind"],
                    "id": int(data["id"]),
                    "time_us": int(event.get("epoch_us", 0)),
                }
            )
        elif not server and event.get("event") == "packet.sound_effect":
            timeline.append(
                {
                    "packet_kind": "effect",
                    "effect_id": int(data["effect_id"]),
                    "time_us": int(event.get("epoch_us", 0)),
                    "world": data.get("world"),
                    "role": "secondary" if data.get("secondary") else "main",
                }
            )
        elif not server and event.get("event") == "packet.anthem":
            timeline.append(
                {
                    "packet_kind": "anthem",
                    "anthem_kind": data["kind"],
                    "id": int(data["id"]),
                    "time_us": int(event.get("epoch_us", 0)),
                }
            )
    return sorted(timeline, key=lambda item: item["time_us"])


def packet_identity(packet: dict[str, Any]) -> tuple[Any, ...]:
    if packet.get("packet_kind", "effect") == "anthem":
        return "anthem", packet.get("anthem_kind"), packet.get("id")
    world = packet.get("world") or {}
    world_key = world.get("x"), world.get("y"), world.get("z")
    return "effect", packet.get("effect_id"), packet.get("role"), world_key


def scheduler_summary(events: list[dict[str, Any]]) -> dict[str, Any]:
    families = ("effect", "ambience", "music", "item_ambience")
    result: dict[str, Any] = {
        "sound_packets_received": sum(event.get("event") == "packet.sound_effect" for event in events),
        "anthem_packets_received": sum(event.get("event") == "packet.anthem" for event in events),
        "families": {},
    }
    for family in families:
        drops = [event for event in events if event.get("event") == f"{family}.drop"]
        reasons = Counter(event.get("data", {}).get("reason", "unspecified") for event in drops)
        result["families"][family] = {
            "requests": sum(event.get("event") == f"{family}.request" for event in events),
            "plays": sum(event.get("event") == f"{family}.play" for event in events),
            "drops": len(drops),
            "drop_reasons": dict(sorted(reasons.items())),
        }
    return result


def sequence_comparison(official: list[dict[str, Any]], crystal: list[dict[str, Any]]) -> dict[str, Any]:
    matcher = SequenceMatcher(
        a=[item["audio_file_id"] for item in official],
        b=[item["audio_file_id"] for item in crystal],
        autojunk=False,
    )
    matches: list[dict[str, Any]] = []
    official_matched: set[int] = set()
    crystal_matched: set[int] = set()
    anchor_official = anchor_crystal = None
    for block in matcher.get_matching_blocks():
        for delta in range(block.size):
            oi, ci = block.a + delta, block.b + delta
            official_matched.add(oi)
            crystal_matched.add(ci)
            if anchor_official is None:
                anchor_official = official[oi]["time_us"]
                anchor_crystal = crystal[ci]["time_us"]
            timing_delta = (
                crystal[ci]["time_us"] - anchor_crystal
                - (official[oi]["time_us"] - anchor_official)
            )
            matches.append(
                {
                    "audio_file_id": official[oi]["audio_file_id"],
                    "official_index": oi,
                    "crystal_index": ci,
                    "timing_delta_ms": round(timing_delta / 1000, 3),
                }
            )
    missing = [item for index, item in enumerate(official) if index not in official_matched]
    extra = [item for index, item in enumerate(crystal) if index not in crystal_matched]
    deltas = [abs(item["timing_delta_ms"]) for item in matches]
    return {
        "official_events": len(official),
        "crystal_events": len(crystal),
        "matched": len(matches),
        "missing": [{"audio_file_id": item["audio_file_id"], "time_us": item["time_us"]} for item in missing],
        "extra": [{"audio_file_id": item["audio_file_id"], "time_us": item["time_us"]} for item in extra],
        "timing": matches,
        "mean_absolute_timing_delta_ms": round(sum(deltas) / len(deltas), 3) if deltas else None,
        "max_absolute_timing_delta_ms": round(max(deltas), 3) if deltas else None,
    }


def delivery_comparison(server: list[dict[str, Any]], client: list[dict[str, Any]], window_ms: float) -> dict[str, Any]:
    used: set[int] = set()
    matches = []
    missing = []
    window_us = int(window_ms * 1000)
    for sent in server:
        candidates = [
            (abs(received["time_us"] - sent["time_us"]), index, received)
            for index, received in enumerate(client)
            if index not in used
            and packet_identity(received) == packet_identity(sent)
        ]
        if not candidates:
            missing.append(sent)
            continue
        distance, index, received = min(candidates)
        if distance > window_us:
            missing.append(sent)
            continue
        used.add(index)
        match = {
            "packet_kind": sent.get("packet_kind", "effect"),
            "latency_ms": round((received["time_us"] - sent["time_us"]) / 1000, 3),
        }
        if match["packet_kind"] == "anthem":
            match.update({"anthem_kind": sent.get("anthem_kind"), "id": sent.get("id")})
        else:
            match.update({"effect_id": sent.get("effect_id"), "role": sent.get("role"), "world": sent.get("world")})
        matches.append(match)
    latencies = [item["latency_ms"] for item in matches]
    return {
        "server_packets": len(server),
        "client_packets": len(client),
        "matched": len(matches),
        "missing_at_client": missing,
        "extra_at_client": [item for index, item in enumerate(client) if index not in used],
        "latencies": matches,
        "mean_latency_ms": round(sum(latencies) / len(latencies), 3) if latencies else None,
        "max_latency_ms": round(max(latencies), 3) if latencies else None,
    }


def markdown_report(report: dict[str, Any]) -> str:
    playback = report["playback"]
    lines = [
        "# Sound parity comparison",
        "",
        f"- Official recognized events: {playback['official_events']}",
        f"- CrystalOTC played events: {playback['crystal_events']}",
        f"- Sequence matches: {playback['matched']}",
        f"- Missing in CrystalOTC: {len(playback['missing'])}",
        f"- Extra in CrystalOTC: {len(playback['extra'])}",
        f"- Mean absolute relative timing delta: {playback['mean_absolute_timing_delta_ms']} ms",
        f"- Maximum absolute relative timing delta: {playback['max_absolute_timing_delta_ms']} ms",
        "",
    ]
    if report.get("delivery"):
        delivery = report["delivery"]
        lines.extend(
            [
                "## Server-to-client delivery",
                "",
                f"- Server packet sounds: {delivery['server_packets']}",
                f"- Client packet sounds: {delivery['client_packets']}",
                f"- Matched: {delivery['matched']}",
                f"- Missing at client: {len(delivery['missing_at_client'])}",
                f"- Extra at client: {len(delivery['extra_at_client'])}",
                f"- Mean delivery latency: {delivery['mean_latency_ms']} ms",
                f"- Maximum delivery latency: {delivery['max_latency_ms']} ms",
                "",
            ]
        )
    scheduler = report["scheduler"]
    lines.extend(
        [
            "## CrystalOTC scheduler",
            "",
            f"- Sound packets received: {scheduler['sound_packets_received']}",
            f"- Anthem packets received: {scheduler['anthem_packets_received']}",
        ]
    )
    for family, totals in scheduler["families"].items():
        reasons = ", ".join(f"{reason}={count}" for reason, count in totals["drop_reasons"].items()) or "none"
        lines.append(
            f"- {family}: requests={totals['requests']}, plays={totals['plays']}, "
            f"drops={totals['drops']} ({reasons})"
        )
    lines.append("")
    if playback["missing"]:
        lines.extend(["## Missing audio IDs", "", ", ".join(str(item["audio_file_id"]) for item in playback["missing"]), ""])
    if playback["extra"]:
        lines.extend(["## Extra audio IDs", "", ", ".join(str(item["audio_file_id"]) for item in playback["extra"]), ""])
    return "\n".join(lines)


def compare(args: argparse.Namespace) -> int:
    official_events = read_jsonl(args.official)
    client_events = read_jsonl(args.client)
    report: dict[str, Any] = {
        "schema": "crystal-sound-comparison-v1",
        "playback": sequence_comparison(
            audio_timeline(official_events, official=True),
            audio_timeline(client_events, official=False),
        ),
        "scheduler": scheduler_summary(client_events),
    }
    if args.server:
        report["delivery"] = delivery_comparison(
            packet_timeline(read_jsonl(args.server), server=True),
            packet_timeline(client_events, server=False),
            args.delivery_window_ms,
        )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    markdown = args.output.with_suffix(".md")
    markdown.write_text(markdown_report(report), encoding="utf-8")
    print(f"{args.output}\n{markdown}")
    return 0


def timed_process(command: list[str], duration: float, output: Path, metadata: Path, kind: str) -> int:
    output.parent.mkdir(parents=True, exist_ok=True)
    metadata.parent.mkdir(parents=True, exist_ok=True)
    started = int(time.time() * 1_000_000)
    with output.open("wb") as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
        try:
            process.wait(timeout=duration)
        except subprocess.TimeoutExpired:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
    ended = int(time.time() * 1_000_000)
    metadata.write_text(
        json.dumps(
            {
                "schema": "crystal-observation-v1",
                "kind": kind,
                "started_epoch_us": started,
                "ended_epoch_us": ended,
                "command": command,
                "output": str(output),
                "exit_code": process.returncode,
            },
            indent=2,
            sort_keys=True,
        ) + "\n",
        encoding="utf-8",
    )
    return process.returncode or 0


def capture_packets(args: argparse.Namespace) -> int:
    tcpdump = require_program("tcpdump")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    metadata = args.metadata or args.output.with_suffix(".json")
    started = int(time.time() * 1_000_000)
    command = [tcpdump, "-i", args.interface, "-U", "-w", str(args.output), args.filter]
    process = subprocess.Popen(command)
    try:
        process.wait(timeout=args.duration)
    except subprocess.TimeoutExpired:
        process.send_signal(signal.SIGINT)
        process.wait(timeout=10)
    ended = int(time.time() * 1_000_000)
    metadata.write_text(
        json.dumps(
            {
                "schema": "crystal-observation-v1",
                "kind": "packet_capture",
                "started_epoch_us": started,
                "ended_epoch_us": ended,
                "interface": args.interface,
                "filter": args.filter,
                "pcap": str(args.output),
                "exit_code": process.returncode,
            },
            indent=2,
            sort_keys=True,
        ) + "\n",
        encoding="utf-8",
    )
    return process.returncode or 0


def parse_tcpdump_line(line: str) -> dict[str, Any] | None:
    match = re.match(r"^(\d+(?:\.\d+)?)\s+(.+)$", line.strip())
    if not match:
        return None
    description = match.group(2)
    length = re.search(r"\blength\s+(\d+)\s*$", description)
    return {
        "epoch_us": round(float(match.group(1)) * 1_000_000),
        "length": int(length.group(1)) if length else None,
        "description": description,
    }


def packet_capture_timeline(args: argparse.Namespace) -> int:
    tcpdump = require_program("tcpdump")
    result = subprocess.run(
        [tcpdump, "-tt", "-nn", "-r", str(args.pcap)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    packets = [packet for line in result.stdout.splitlines() if (packet := parse_tcpdump_line(line))]
    first_epoch_us = packets[0]["epoch_us"] if packets else 0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as output:
        for sequence, packet in enumerate(packets):
            epoch_us = packet.pop("epoch_us")
            event = {
                "schema": "crystal-sound-trace-v1",
                "producer": "packet-capture",
                "seq": sequence,
                "session_us": epoch_us - first_epoch_us,
                "epoch_us": epoch_us,
                "event": "network.packet",
                "data": packet,
            }
            output.write(json.dumps(event, separators=(",", ":")) + "\n")
    print(f"converted {len(packets)} packet(s) -> {args.output}")
    return 0


def media_onsets(args: argparse.Namespace) -> int:
    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    first_sample_epoch_us = int(metadata["firstSampleEpochUs"])
    duration_seconds = float(metadata["durationSeconds"])
    envelope = rms_envelope(args.recording)
    accepted = {"effect.play", "ambience.play", "music.play", "item_ambience.play"}
    measurements = []
    for event in read_jsonl(args.trace):
        if event.get("event") not in accepted:
            continue
        epoch_us = int(event.get("epoch_us", 0))
        command_seconds = (epoch_us - first_sample_epoch_us) / 1_000_000
        if command_seconds < 0 or command_seconds > duration_seconds:
            continue
        audible = first_audible_frame(
            envelope, command_seconds, command_seconds + args.search_window_ms / 1000, args.threshold_db
        )
        data = event.get("data", {})
        measurement = {
            "event": event["event"],
            "audio_file_id": data.get("audio_file_id"),
            "effect_id": data.get("effect_id"),
            "command_offset_ms": round(command_seconds * 1000, 3),
            "audible_offset_ms": round(audible[0] * 1000, 3) if audible else None,
            "audible_level_db": round(audible[1], 3) if audible else None,
            "command_to_audible_ms": round((audible[0] - command_seconds) * 1000, 3) if audible else None,
        }
        measurements.append(measurement)
    report = {
        "schema": "crystal-media-onsets-v1",
        "recording": str(args.recording),
        "trace": str(args.trace),
        "threshold_db": args.threshold_db,
        "search_window_ms": args.search_window_ms,
        "measurements": measurements,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"measured {len(measurements)} playback command(s) -> {args.output}")
    return 0


def trace_files(args: argparse.Namespace) -> int:
    fs_usage = Path("/usr/bin/fs_usage")
    if not fs_usage.is_file():
        raise RuntimeError("/usr/bin/fs_usage is unavailable")
    metadata = args.metadata or args.output.with_suffix(".json")
    command = [str(fs_usage), "-w", "-f", "filesys", "-p", str(args.pid)]
    return timed_process(command, args.duration, args.output, metadata, "filesystem_trace")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)

    index = subparsers.add_parser("index", help="build the official 15.32 acoustic fingerprint index")
    index.add_argument("--inventory", type=Path, default=DEFAULT_INVENTORY)
    index.add_argument("--sound-dir", type=Path, default=DEFAULT_SOUND_DIR)
    index.add_argument("--output", type=Path, default=DEFAULT_INDEX)
    index.add_argument("--limit", type=int, help="index only the first N files (smoke tests)")
    index.set_defaults(function=create_index)

    identify_parser = subparsers.add_parser("identify", help="recognize official soundbank files in a capture")
    identify_parser.add_argument("recording", type=Path)
    identify_parser.add_argument("--metadata", type=Path)
    identify_parser.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    identify_parser.add_argument("--output", type=Path, required=True)
    identify_parser.add_argument("--min-votes", type=int, default=3)
    identify_parser.add_argument("--min-confidence", type=float, default=0.30)
    identify_parser.add_argument("--max-hash-assets", type=int, default=20)
    identify_parser.add_argument("--silence-threshold-db", type=float, default=-80.0)
    identify_parser.set_defaults(function=identify)

    compare_parser = subparsers.add_parser("compare", help="compare recognized official audio with CrystalOTC trace")
    compare_parser.add_argument("--official", type=Path, required=True)
    compare_parser.add_argument("--client", type=Path, required=True)
    compare_parser.add_argument("--server", type=Path)
    compare_parser.add_argument("--output", type=Path, required=True)
    compare_parser.add_argument("--delivery-window-ms", type=float, default=500)
    compare_parser.set_defaults(function=compare)

    packets = subparsers.add_parser("capture-packets", help="capture encrypted packet timing with tcpdump (run as root)")
    packets.add_argument("--interface", default="pktap,all" if platform.system() == "Darwin" else "any")
    packets.add_argument("--filter", default="tcp")
    packets.add_argument("--duration", type=float, default=60)
    packets.add_argument("--output", type=Path, required=True)
    packets.add_argument("--metadata", type=Path)
    packets.set_defaults(function=capture_packets)

    packet_timestamps = subparsers.add_parser(
        "packet-timeline", help="convert pcap timestamps into the shared JSONL timeline"
    )
    packet_timestamps.add_argument("pcap", type=Path)
    packet_timestamps.add_argument("--output", type=Path, required=True)
    packet_timestamps.set_defaults(function=packet_capture_timeline)

    onsets = subparsers.add_parser(
        "media-onsets", help="measure trace playback-command to captured audible-onset latency"
    )
    onsets.add_argument("recording", type=Path)
    onsets.add_argument("--metadata", type=Path, required=True)
    onsets.add_argument("--trace", type=Path, required=True)
    onsets.add_argument("--output", type=Path, required=True)
    onsets.add_argument("--threshold-db", type=float, default=-60.0)
    onsets.add_argument("--search-window-ms", type=float, default=500.0)
    onsets.set_defaults(function=media_onsets)

    files = subparsers.add_parser("trace-files", help="record official-client filesystem activity (run as root)")
    files.add_argument("--pid", type=int, required=True)
    files.add_argument("--duration", type=float, default=60)
    files.add_argument("--output", type=Path, required=True)
    files.add_argument("--metadata", type=Path)
    files.set_defaults(function=trace_files)
    return result


def main() -> int:
    args = parser().parse_args()
    try:
        return args.function(args)
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
