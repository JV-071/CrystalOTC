#!/usr/bin/env python3
"""Decode an official Tibia session dump into readable server messages.

The official client records and replays game sessions as ``.dmp`` files, and it
ships one: the Dawnport tutorial, embedded in ``graphics_resources.rcc`` as
``tutorial/tutorial-sessiondump.dmp``. It is the only capture of genuine
official-server traffic that comes with the client, which makes it the one place
on disk where questions like "what world light does CipSoft actually send?" have
an answer that is read rather than guessed.

Format, recovered by inspection:

* A ``dmpd`` header, then a run of frames.
* Each frame is a ``0x6D`` magic byte, a little-endian ``uint16`` length, and
  that many bytes of a serialised ``tibia.protobuf.protocol.GameserverMessage``.
* That wrapper carries the protocol opcode in field 1, and the message body in
  the field whose *number equals that opcode* - so field 130 holds the body of a
  ``GameServerAmbient``. Opcode names come from ``src/client/protocolcodes.h``.

The protobuf schema itself is not in the binary: the protocol messages are built
with protobuf's lite runtime, which keeps type names but drops field names and
descriptors. So bodies are printed structurally, by field number and wire type,
with bytes shown as text when they decode as such.

Usage::

    tools/decode_official_sessiondump.py path/to/tutorial-sessiondump.dmp
    tools/decode_official_sessiondump.py dump.dmp --opcode 130
    tools/decode_official_sessiondump.py dump.dmp --histogram

It only reads; it never writes to the official application bundle.
"""

from __future__ import annotations

import argparse
import collections
import re
import sys
from pathlib import Path


FRAME_MAGIC = 0x6D
MAX_FRAME_LEN = 8192

REPO_ROOT = Path(__file__).resolve().parents[1]
PROTOCOL_CODES = REPO_ROOT / "src/client/protocolcodes.h"

# Opcodes worth calling out when they appear, because they are the ones this tool
# exists to read. Everything else is named from protocolcodes.h.
NOTABLE = {
    130: "world light: field 1 is the level 0..255, field 2 the palette index 0..215",
    239: "world time: field 1 is the Tibia hour, field 2 the minute",
}


def load_opcode_names() -> dict[int, str]:
    """Map opcode -> GameServer* name by reading the client's own enum."""
    try:
        text = PROTOCOL_CODES.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {}

    names: dict[int, str] = {}
    in_server_enum = False
    for line in text.splitlines():
        if "GameServer" in line and "enum" in line:
            in_server_enum = True
        match = re.match(r"\s*(GameServer\w+)\s*=\s*(\d+)\s*,", line)
        if match:
            in_server_enum = True
            names[int(match.group(2))] = match.group(1)
        elif in_server_enum and line.strip().startswith("Client"):
            break
    return names


def read_varint(buf: bytes, pos: int) -> tuple[int, int]:
    result = 0
    shift = 0
    while pos < len(buf):
        byte = buf[pos]
        result |= (byte & 0x7F) << shift
        pos += 1
        shift += 7
        if not byte & 0x80:
            return result, pos
        if shift > 70:
            break
    raise ValueError("truncated varint")


def parse_fields(buf: bytes) -> list[tuple[int, int, object]]:
    """Parse a protobuf message into (field number, wire type, value) triples."""
    fields: list[tuple[int, int, object]] = []
    pos = 0
    while pos < len(buf):
        tag, pos = read_varint(buf, pos)
        number, wire = tag >> 3, tag & 7
        if number == 0:
            raise ValueError("field number 0")
        if wire == 0:
            value, pos = read_varint(buf, pos)
            fields.append((number, wire, value))
        elif wire == 2:
            length, pos = read_varint(buf, pos)
            if length < 0 or pos + length > len(buf):
                raise ValueError("length-delimited field overruns the message")
            fields.append((number, wire, buf[pos:pos + length]))
            pos += length
        elif wire == 5:
            fields.append((number, wire, buf[pos:pos + 4]))
            pos += 4
        elif wire == 1:
            fields.append((number, wire, buf[pos:pos + 8]))
            pos += 8
        else:
            raise ValueError(f"unsupported wire type {wire}")
    return fields


def as_text(raw: bytes) -> str | None:
    """Return raw as a string if it plausibly is one, else None."""
    if len(raw) < 2:
        return None
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if all(32 <= ord(ch) < 127 or ch in "\n\t" for ch in text):
        return text
    return None


def render(buf: bytes, indent: int = 1, max_depth: int = 6) -> str:
    try:
        fields = parse_fields(buf)
    except ValueError:
        return f"{'  ' * indent}<{len(buf)} bytes> {buf[:48].hex()}"

    lines = []
    pad = "  " * indent
    for number, wire, value in fields:
        if wire == 0:
            lines.append(f"{pad}f{number} = {value}")
        elif wire == 2:
            text = as_text(value)
            if text is not None:
                lines.append(f'{pad}f{number} = "{text}"')
            elif value and indent < max_depth:
                nested = render(value, indent + 1, max_depth)
                lines.append(f"{pad}f{number} = {{\n{nested}\n{pad}}}")
            else:
                lines.append(f"{pad}f{number} = {value.hex()}")
        else:
            lines.append(f"{pad}f{number} = {value.hex()}")
    return "\n".join(lines)


def iter_frames(data: bytes):
    """Yield (offset, opcode, body bytes) for every frame that parses."""
    pos = 0
    while pos < len(data) - 3:
        if data[pos] != FRAME_MAGIC:
            pos += 1
            continue
        length = data[pos + 1] | (data[pos + 2] << 8)
        if not 0 < length <= MAX_FRAME_LEN or pos + 3 + length > len(data):
            pos += 1
            continue
        payload = data[pos + 3:pos + 3 + length]
        try:
            fields = parse_fields(payload)
        except ValueError:
            pos += 1
            continue
        # Field 1 is the opcode, and a well-formed frame repeats it as the body's
        # field number. Requiring both is what keeps this resynchronising cleanly
        # instead of locking onto a 0x6D that happened to sit inside a payload.
        if not fields or fields[0][0] != 1 or fields[0][1] != 0:
            pos += 1
            continue
        opcode = fields[0][2]
        body = next((v for n, w, v in fields if n == opcode and w == 2), None)
        yield pos, opcode, body
        pos += 3 + length


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dump", type=Path, help="path to a .dmp session dump")
    parser.add_argument("--opcode", type=int, action="append", default=None,
                        help="only show frames with this opcode (repeatable)")
    parser.add_argument("--histogram", action="store_true",
                        help="summarise opcode counts instead of printing frames")
    parser.add_argument("--max-depth", type=int, default=6,
                        help="how deep to descend into nested messages (default 6)")
    args = parser.parse_args()

    try:
        data = args.dump.read_bytes()
    except OSError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if not data.startswith(b"dmpd"):
        print("warning: no 'dmpd' header - continuing, but this may not be a session dump",
              file=sys.stderr)

    names = load_opcode_names()
    frames = list(iter_frames(data))
    if not frames:
        print("error: no frames decoded; the dump format may have changed", file=sys.stderr)
        return 1

    if args.histogram:
        counts = collections.Counter(opcode for _, opcode, _ in frames)
        print(f"{len(frames)} frames, {len(counts)} distinct opcodes\n")
        print(f"{'opcode':>6}  {'count':>5}  name")
        for opcode, count in sorted(counts.items()):
            print(f"{opcode:>6}  {count:>5}  {names.get(opcode, '?')}")
        return 0

    wanted = set(args.opcode) if args.opcode else None
    shown = 0
    for offset, opcode, body in frames:
        if wanted is not None and opcode not in wanted:
            continue
        shown += 1
        name = names.get(opcode, "?")
        print(f"@0x{offset:06x}  opcode {opcode}  {name}")
        if opcode in NOTABLE:
            print(f"            note: {NOTABLE[opcode]}")
        if body:
            print(render(body, 3, args.max_depth))
        print()

    if wanted is not None and shown == 0:
        print(f"no frames matched opcode(s) {sorted(wanted)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
