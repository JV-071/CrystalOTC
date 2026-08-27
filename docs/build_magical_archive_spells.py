#!/usr/bin/env python3
"""Rebuild the Magical Archive spell table.

The Magical Archive renders three sources of truth that do not agree, so this
script merges them explicitly instead of letting one overwrite the others:

  official  data/official-client-15.3x/spell-data/spells.json
            CipSoft's own table, extracted from the installed client. Owns
            identity, artwork and lore: icon indices, descriptions, scaling,
            base power, spell groups, vocations, rune parameters.

  server    crystalserver data/scripts/spells/**.lua
            What a player on THIS server actually experiences. Owns the
            numbers a player can feel: mana, level, soul, premium, cooldowns.
            The server is rebalanced independently of CipSoft, so it wins.

  repo      modules/game_cyclopedia/tab/magicalArchives/spells.json
            The file being rebuilt. Owns the preview-rendering fields, which
            have been hand-corrected locally and are richer than CipSoft's
            (whose `missile` value for Lightning is literally a leaked C++
            fragment). Those corrections are preserved.

Run from the repo root:

    python3 docs/build_magical_archive_spells.py            # rebuild
    python3 docs/build_magical_archive_spells.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.environ.get("CRYSTALSERVER", os.path.join(os.path.dirname(REPO), "crystalserver"))

OFFICIAL_JSON = os.path.join(REPO, "data/official-client-15.3x/spell-data/spells.json")
OFFICIAL_PREVIEWS = os.path.join(REPO, "data/official-client-15.3x/spell-data/spells-previews.json")
ARCHIVE_JSON = os.path.join(REPO, "modules/game_cyclopedia/tab/magicalArchives/spells.json")
ARCHIVE_PREVIEWS = os.path.join(REPO, "modules/game_cyclopedia/tab/magicalArchives/spells-preview.json")
SERVER_SPELLS = os.path.join(SERVER, "data/scripts/spells")

# Fields CipSoft owns. Copied from the official table verbatim.
OFFICIAL_FIELDS = [
    "spellid", "name", "formulaWithoutParams", "parameterHints",
    "spellGroupPrimary", "spellGroupSecondary", "iconIndex",
    "isRune", "isRuneCreatable", "onlyPromoted", "autoUnlock",
    "crossHairTarget", "aggressive", "allowedVocations",
    "description", "source", "scaling", "mean", "runeParams",
]

# Fields the server owns. A player's mana bar answers to the server, not CipSoft.
SERVER_FIELDS = {
    "castCostMana": "mana",
    "minimumCasterLevel": "level",
    "castCostSoulPoints": "soul",
    "premium": "premium",
    "cooldownSelf": "cooldown",
    "cooldownPrimaryGroup": "groupCooldown",
    "cooldownSecondaryGroup": "groupCooldown2",
}

# Fields that drive the local preview engine. Keep hand-tuned values.
PREVIEW_FIELDS = ["effect", "missile", "radius", "aimattarget", "damagetype", "range"]

SPELL_GROUPS = {
    "attack": 1, "healing": 2, "support": 3, "special": 4, "crippling": 6,
    "focus": 7, "ultimatestrikes": 8, "greatbeams": 9, "burstsofnature": 10,
    "stance": 11,
}


def _number(expr):
    """Evaluate the `2 * 1000` form the server scripts use for durations."""
    expr = expr.strip()
    product = re.fullmatch(r"([\d.]+)\s*\*\s*([\d.]+)", expr)
    if product:
        return int(float(product.group(1)) * float(product.group(2)))
    return int(float(expr)) if re.fullmatch(r"[\d.]+", expr) else None


def read_server_spells(root=SERVER_SPELLS):
    """Parse the server's player-spell scripts into {spellid: fields}.

    Monster spells and the example stub carry no player-facing id, so they are
    skipped. Absent calls fall back to the server's own defaults (level 0,
    soul 0, premium false) rather than being left unknown.
    """
    spells = {}
    if not os.path.isdir(root):
        return spells
    for path in glob.glob(os.path.join(root, "**", "*.lua"), recursive=True):
        if "/monster/" in path or os.path.basename(path).startswith("#"):
            continue
        src = open(path, encoding="utf-8", errors="replace").read()
        found_id = re.search(r"spell:id\(\s*(\d+)", src)
        if not found_id:
            continue

        def one(pattern, cast=int, default=None):
            hit = re.search(pattern, src)
            return cast(hit.group(1)) if hit else default

        groups = re.search(r'spell:group\(\s*"([^"]*)"\s*(?:,\s*"([^"]*)"\s*)?\)', src)
        cooldowns = re.search(r"spell:groupCooldown\(\s*([\d. *]+?)\s*(?:,\s*([\d. *]+?)\s*)?\)", src)
        spells[int(found_id.group(1))] = {
            "file": os.path.relpath(path, SERVER),
            "name": one(r'spell:name\(\s*"([^"]*)"', str),
            "words": one(r'spell:words\(\s*"([^"]*)"', str),
            "mana": one(r"spell:mana\(\s*(\d+)\s*\)"),
            "level": one(r"spell:level\(\s*(\d+)\s*\)", default=0),
            "soul": one(r"spell:soul\(\s*(\d+)\s*\)", default=0),
            "premium": one(r"spell:isPremium\(\s*(true|false)\s*\)", lambda v: v == "true", False),
            "cooldown": one(r"spell:cooldown\(\s*([\d. *]+?)\s*\)", _number),
            "group": SPELL_GROUPS.get(groups.group(1).lower().replace(" ", "")) if groups else None,
            "group2": SPELL_GROUPS.get(groups.group(2).lower().replace(" ", "")) if groups and groups.group(2) else None,
            "groupCooldown": _number(cooldowns.group(1)) if cooldowns else None,
            "groupCooldown2": _number(cooldowns.group(2)) if cooldowns and cooldowns.group(2) else None,
        }
    return spells


def milliseconds_to_seconds(value):
    """The client table stores seconds; the server scripts store milliseconds."""
    if value is None:
        return None
    return value / 1000 if value % 1000 else value // 1000


def merge(official, server, existing):
    """Produce the merged table plus a per-spell record of what changed."""
    by_official = {s["spellid"]: s for s in official}
    by_existing = {s["spellid"]: s for s in existing}

    # A spell belongs in the archive if CipSoft still ships it, or this server
    # still casts it. Anything else is content that no longer exists anywhere.
    keep = set(by_official) | (set(server) & set(by_existing))
    dropped = sorted(set(by_existing) - keep)
    added = sorted(keep - set(by_existing))

    merged, changes = [], []
    for spellid in sorted(keep):
        base = by_official.get(spellid)
        prior = by_existing.get(spellid, {})
        entry = {}

        if base:
            for field in OFFICIAL_FIELDS:
                if field in base:
                    entry[field] = base[field]
        else:
            # Server-only spell CipSoft has dropped: keep whatever we had.
            entry.update({k: v for k, v in prior.items() if k not in SERVER_FIELDS})
            entry["spellid"] = spellid

        for field, server_key in SERVER_FIELDS.items():
            value = server.get(spellid, {}).get(server_key)
            if server_key in ("cooldown", "groupCooldown", "groupCooldown2"):
                value = milliseconds_to_seconds(value)
            if value is None:
                # Server is silent: keep CipSoft's number, else what we had.
                value = (base or {}).get(field, prior.get(field))
            if value is not None:
                entry[field] = value

        for field in PREVIEW_FIELDS:
            if prior.get(field) is not None:
                entry[field] = prior[field]
            elif base and base.get(field) is not None:
                entry[field] = base[field]

        if prior:
            for field in sorted(set(entry) | set(prior)):
                if entry.get(field) != prior.get(field):
                    changes.append((spellid, entry.get("name"), field,
                                    prior.get(field), entry.get(field)))
        merged.append(entry)

    return merged, changes, added, dropped


def sync_previews(spellids, existing, official):
    """Give every spell a preview, without disturbing the hand-tuned ones.

    The local previews are a superset of CipSoft's — they carry `creature` and
    `transform` actions, grid bounds and map-effect patterns that the official
    file has no concept of. So an existing entry is never overwritten; only
    genuinely missing spells are seeded from the official timeline, and entries
    for spells that no longer exist are removed.
    """
    merged = dict(existing)
    seeded, removed = [], []

    for spellid in sorted(spellids):
        key = str(spellid)
        if key in merged:
            continue
        source = official.get(key)
        if source:
            merged[key] = source
            seeded.append((spellid, source.get("name")))

    for key in sorted(merged, key=int):
        if int(key) not in spellids:
            removed.append((int(key), merged[key].get("name")))
            del merged[key]

    return merged, seeded, removed


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true",
                        help="report what would change without writing")
    args = parser.parse_args()

    if not os.path.exists(OFFICIAL_JSON):
        sys.exit(f"missing official table: {OFFICIAL_JSON}")

    official = json.load(open(OFFICIAL_JSON, encoding="utf-8"))
    existing = json.load(open(ARCHIVE_JSON, encoding="utf-8"))
    server = read_server_spells()
    if not server:
        print(f"warning: no server scripts at {SERVER_SPELLS} — "
              f"keeping existing gameplay numbers", file=sys.stderr)

    merged, changes, added, dropped = merge(official, server, existing)

    print(f"official {len(official)}  server {len(server)}  "
          f"existing {len(existing)}  ->  merged {len(merged)}")
    if added:
        names = {s["spellid"]: s["name"] for s in merged}
        print(f"\nadded ({len(added)}):")
        for spellid in added:
            print(f"  #{spellid} {names.get(spellid)}")
    if dropped:
        names = {s["spellid"]: s.get("name") for s in existing}
        print(f"\ndropped ({len(dropped)}) — gone from both CipSoft and the server:")
        for spellid in dropped:
            print(f"  #{spellid} {names.get(spellid)}")

    by_field = {}
    for _, _, field, _, _ in changes:
        by_field[field] = by_field.get(field, 0) + 1
    if by_field:
        print(f"\nfield updates ({len(changes)}):")
        for field, count in sorted(by_field.items(), key=lambda kv: -kv[1]):
            print(f"  {field}: {count}")

    previews, seeded, removed_previews = sync_previews(
        {s["spellid"] for s in merged},
        json.load(open(ARCHIVE_PREVIEWS, encoding="utf-8")),
        json.load(open(OFFICIAL_PREVIEWS, encoding="utf-8")),
    )
    if seeded:
        print(f"\npreviews seeded from the official timeline ({len(seeded)}):")
        for spellid, name in seeded:
            print(f"  #{spellid} {name}")
    if removed_previews:
        print(f"\npreviews removed ({len(removed_previews)}):")
        for spellid, name in removed_previews:
            print(f"  #{spellid} {name}")

    if args.dry_run:
        print("\ndry run — nothing written")
        return

    with open(ARCHIVE_JSON, "w", encoding="utf-8") as handle:
        json.dump(merged, handle, indent=4, ensure_ascii=False)
        handle.write("\n")
    with open(ARCHIVE_PREVIEWS, "w", encoding="utf-8") as handle:
        json.dump(previews, handle, indent=4, ensure_ascii=False)
        handle.write("\n")
    print(f"\nwrote {ARCHIVE_JSON}")
    print(f"wrote {ARCHIVE_PREVIEWS}")


if __name__ == "__main__":
    main()
