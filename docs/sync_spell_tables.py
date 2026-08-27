#!/usr/bin/env python3
"""Check (and fix) modules/gamelib/spells.lua against the server and CipSoft.

Three tables in that file drift for different reasons, so each is checked
against whichever source actually owns it:

  SpellInfo             gameplay numbers — mana, level, soul, premium,
                        cooldowns, spell groups, display name.
                        Owner: crystalserver. A player's mana bar answers to
                        the server, so when the server is rebalanced this file
                        has to follow.

  SpellIconsFirstIsZero artwork. Owner: the official client. The index is a
                        slot in spell-icons-32x32.png, and CipSoft re-numbers
                        that sheet between releases.

  SpellRunesData        cooldowns for *using* a rune, which is a separate
                        cooldown from conjuring it. Owner: crystalserver's
                        data/scripts/runes.

Needs `lua` on PATH to read the current tables.

    python3 docs/sync_spell_tables.py            # report drift, change nothing
    python3 docs/sync_spell_tables.py --fix      # apply the fixes in place
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_magical_archive_spells import (  # noqa: E402
    OFFICIAL_JSON, REPO, SERVER, SPELL_GROUPS, _number, read_server_spells,
)

SPELLS_LUA = os.path.join(REPO, "modules/gamelib/spells.lua")
SERVER_RUNES = os.path.join(SERVER, "data/scripts/runes")

# Each entry: (lua field, server field). `name` is included because the rune
# conjuring spells are named after the rune they produce, and the two sides
# disagreed on 19 of them.
SPELL_FIELDS = [
    ("mana", "mana"), ("level", "level"), ("soul", "soul"),
    ("premium", "premium"), ("exhaustion", "cooldown"), ("name", "name"),
]
RUNE_FIELDS = ["id", "group", "exhaustion", "groupExhaustion", "name"]

DUMP_LUA = r"""
dofile(arg[1])
local function esc(s)
  return (s:gsub('[%c"\\]', function(c) return string.format('\\u%04x', c:byte()) end))
end
local function enc(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" or t == "number" then return tostring(v) end
  if t == "string" then return '"' .. esc(v) .. '"' end
  if t == "table" then
    local out = {}
    for k, x in pairs(v) do out[#out + 1] = '"' .. esc(tostring(k)) .. '":' .. enc(x) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end
io.write(enc({ SpellInfo = SpellInfo,
               SpellIconsFirstIsZero = SpellIconsFirstIsZero,
               SpellRunesData = SpellRunesData }))
"""


def read_lua_tables(path=SPELLS_LUA):
    """Run the file through `lua` and bring its three tables back as JSON."""
    if not shutil.which("lua"):
        sys.exit("need `lua` on PATH to read spells.lua")
    with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as handle:
        handle.write(DUMP_LUA)
        dumper = handle.name
    try:
        done = subprocess.run(["lua", dumper, path], capture_output=True, text=True)
        if done.returncode:
            sys.exit(f"lua failed reading {path}:\n{done.stderr}")
        return json.loads(done.stdout)
    finally:
        os.unlink(dumper)


def read_server_runes(root=SERVER_RUNES):
    """Parse the rune *usage* scripts, which are separate from the conjurings."""
    runes = {}
    if not os.path.isdir(root):
        return runes
    for path in glob.glob(os.path.join(root, "**", "*.lua"), recursive=True):
        src = open(path, encoding="utf-8", errors="replace").read()
        rune_item = re.search(r"rune:runeId\(\s*(\d+)", src)
        if not rune_item:
            continue
        group = re.search(r'rune:group\(\s*"([^"]*)"', src)

        def one(pattern, cast=int, default=None):
            hit = re.search(pattern, src)
            return cast(hit.group(1)) if hit else default

        runes[int(rune_item.group(1))] = {
            "id": one(r"rune:id\(\s*(\d+)"),
            "name": one(r'rune:name\(\s*"([^"]*)"', str),
            "group": SPELL_GROUPS.get(group.group(1).lower().replace(" ", "")) if group else None,
            "exhaustion": one(r"rune:cooldown\(\s*([\d. *]+?)\s*\)", _number),
            "groupExhaustion": one(r"rune:groupCooldown\(\s*([\d. *]+?)\s*\)", _number),
        }
    return runes


def normalize_group(value):
    """Lua renders {[1]=x} as a JSON array and {[2]=x} as an object."""
    if value is None:
        return {}
    if isinstance(value, list):
        return {i + 1: v for i, v in enumerate(value) if v is not None}
    return {int(k): v for k, v in value.items()}


def find_drift(tables, server, runes, official):
    spell_info = tables["SpellInfo"]["Default"]
    by_id = {entry["id"]: (key, entry) for key, entry in spell_info.items()}
    icons = {int(k): v for k, v in (tables.get("SpellIconsFirstIsZero") or {}).items()}
    rune_data = {int(k): v for k, v in (tables.get("SpellRunesData") or {}).items()}

    drift = []

    for spellid, remote in sorted(server.items()):
        if spellid not in by_id:
            drift.append(("SpellInfo", spellid, None, "missing", None,
                          f"server defines {remote['name']!r}"))
            continue
        key, entry = by_id[spellid]
        for lua_field, server_field in SPELL_FIELDS:
            want = remote.get(server_field)
            if want is None:
                continue  # server is silent; its own default already applies
            have = entry.get(lua_field)
            if lua_field == "premium":
                have = bool(have)
            if have != want:
                drift.append(("SpellInfo", spellid, key, lua_field, have, want))
        want_group = {}
        if remote["group"] and remote["groupCooldown"] is not None:
            want_group[remote["group"]] = remote["groupCooldown"]
        if remote["group2"] and remote["groupCooldown2"] is not None:
            want_group[remote["group2"]] = remote["groupCooldown2"]
        if want_group and normalize_group(entry.get("group")) != want_group:
            drift.append(("SpellInfo", spellid, key, "group",
                          normalize_group(entry.get("group")), want_group))

    for spell in official:
        spellid, want = spell["spellid"], spell["iconIndex"]
        have = icons.get(spellid)
        if have != want:
            drift.append(("SpellIcons", spellid, spell["name"], "iconIndex", have, want))
    for spellid in sorted(set(icons) - {s["spellid"] for s in official}):
        drift.append(("SpellIcons", spellid, None, "iconIndex", icons[spellid], None))

    for item_id, remote in sorted(runes.items()):
        have = rune_data.get(item_id)
        if have is None:
            drift.append(("SpellRunes", item_id, remote["name"], "missing", None, remote))
            continue
        for field in RUNE_FIELDS:
            if remote.get(field) is not None and have.get(field) != remote[field]:
                drift.append(("SpellRunes", item_id, remote["name"], field,
                              have.get(field), remote[field]))
    return drift


def lua_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return f'"{value}"'
    if value is None:
        return "nil"
    return str(value)


def apply(drift, path=SPELLS_LUA):
    """Rewrite only the specific field lines that drifted."""
    lines = open(path, encoding="utf-8").read().split("\n")

    def block_index(header_prefix, entry_pattern, depth_indent):
        start = next(i for i, l in enumerate(lines) if l.startswith(header_prefix))
        found, i = {}, start + 1
        while i < len(lines):
            hit = entry_pattern.match(lines[i])
            if hit:
                key = hit.group("q") or hit.group("b")
                j, depth = i + 1, 1
                while j < len(lines):
                    depth += lines[j].count("{") - lines[j].count("}")
                    if depth == 0:
                        break
                    j += 1
                found[key] = (i, j)
                i = j + 1
                continue
            if lines[i].startswith("}") and i > start:
                break
            i += 1
        return found

    spell_blocks = block_index(
        "SpellInfo = {",
        re.compile(r'^\t\t(?:\["(?P<q>.+)"\]|(?P<b>[A-Za-z_][A-Za-z0-9_]*)) = \{$'), 3)
    rune_blocks = block_index(
        "SpellRunesData = {",
        re.compile(r'^\t(?:\[(?P<q>\d+)\]|(?P<b>[A-Za-z_][A-Za-z0-9_]*)) = \{$'), 2)

    icon_start = next(i for i, l in enumerate(lines)
                      if l.startswith("SpellIconsFirstIsZero = {"))

    applied, skipped = 0, []
    for table, ident, key, field, _old, new in drift:
        if table == "SpellIcons":
            row = icon_start + ident
            if row >= len(lines):
                skipped.append((table, ident, field, "out of range"))
                continue
            indent = lines[row][:len(lines[row]) - len(lines[row].lstrip())]
            comma = "," if lines[row].rstrip().endswith(",") else ""
            lines[row] = f"{indent}{lua_value(new)}{comma}"
            applied += 1
            continue

        if field == "missing":
            skipped.append((table, ident, field, "needs a new entry — add by hand"))
            continue

        blocks = spell_blocks if table == "SpellInfo" else rune_blocks
        lookup = key if table == "SpellInfo" else str(ident)
        if lookup not in blocks:
            skipped.append((table, ident, field, "block not found"))
            continue
        a, b = blocks[lookup]
        indent = "\t\t\t" if table == "SpellInfo" else "\t\t"

        if field == "group":
            head = next((k for k in range(a, b + 1)
                         if re.match(rf"^{indent}group = \{{$", lines[k])), None)
            if head is None:
                skipped.append((table, ident, field, "group table not found"))
                continue
            depth, end = 1, head + 1
            while end <= b:
                depth += lines[end].count("{") - lines[end].count("}")
                if depth == 0:
                    break
                end += 1
            items = sorted(new.items())
            block = [f"{indent}group = {{"]
            for n, (gid, value) in enumerate(items):
                block.append(f"{indent}\t[{gid}] = {value}" + ("," if n < len(items) - 1 else ""))
            block.append(f"{indent}}}" + ("," if lines[end].rstrip().endswith(",") else ""))
            delta = len(block) - (end - head + 1)
            lines[head:end + 1] = block
            for other, (x, y) in list(blocks.items()):
                blocks[other] = (x + delta if x > head else x, y + delta if y > head else y)
            if icon_start > head:
                icon_start += delta
            applied += 1
            continue

        pattern = re.compile(rf"^({indent}{field} = )(.+?)(,?)$")
        for k in range(a, b + 1):
            hit = pattern.match(lines[k])
            if hit:
                lines[k] = hit.group(1) + lua_value(new) + hit.group(3)
                applied += 1
                break
        else:
            skipped.append((table, ident, field, "field not present"))

    open(path, "w", encoding="utf-8").write("\n".join(lines))
    return applied, skipped


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fix", action="store_true", help="apply the fixes in place")
    args = parser.parse_args()

    tables = read_lua_tables()
    server = read_server_spells()
    runes = read_server_runes()
    official = json.load(open(OFFICIAL_JSON, encoding="utf-8"))
    if not server:
        sys.exit(f"no server spell scripts under {SERVER} — set CRYSTALSERVER")

    drift = find_drift(tables, server, runes, official)
    if not drift:
        print("spells.lua is in sync with crystalserver and the official client")
        return

    by_table = {}
    for entry in drift:
        by_table.setdefault(entry[0], []).append(entry)
    for table, entries in by_table.items():
        print(f"\n{table}: {len(entries)} drifted")
        for _, ident, key, field, old, new in entries[:40]:
            label = key if key is not None else ""
            print(f"  #{ident:<6} {str(label)[:30]:<30} {field:<16} {old!r} -> {new!r}")
        if len(entries) > 40:
            print(f"  ... +{len(entries) - 40} more")

    if not args.fix:
        print(f"\n{len(drift)} drifted values. Re-run with --fix to apply.")
        return

    applied, skipped = apply(drift)
    print(f"\napplied {applied} of {len(drift)}")
    for entry in skipped:
        print(f"  skipped: {entry}")


if __name__ == "__main__":
    main()
