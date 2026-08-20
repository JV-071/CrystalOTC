# Renderer fixture server scripts

A **vendored, read-only copy** of the server-side scripts the four online renderer-baseline
scenes depend on. The live source is the `crystalserver` repository; this copy exists so the
client repository can state exactly what those scenes require, and so the requirement survives
the fork going away.

Do not edit these files here. Change them in `crystalserver`, then re-vendor (see *Updating the
pin* below) — `tools/renderer_scenes.py validate` fails if this copy drifts from the recorded
digests.

## Provenance

The pin lives in [`../scenes.json`](../scenes.json) under `fixtureServer`; print it with:

```sh
python3 tools/renderer_scenes.py fixture
```

| Field | Value |
|---|---|
| Repository | `https://github.com/aacruzgon/crystalserver` |
| Branch | `local/testing` |
| Commit | `f47f6e41504f126218fc2d649c5a0c088c3375a0` |
| Path in that repo | `data-global/scripts/custom/renderer_fixtures` |

The commit is **only** on that personal fork. An upstream `crystalserver` clone has never had
it, so "the server is running" is not the same as "the fixtures are installed".

## What the scripts do

| File | Role |
|---|---|
| `renderer_fixtures_lib.lua` | The `RendererFixtures` table: coordinates, item ids, tile/creature builders, and the `DESTINATIONS` alias map |
| `renderer_fixtures_startup.lua` | `GlobalEvent("RendererBaselineFixtures")` — builds both platforms `onStartup` |
| `renderer_fixtures_talkaction.lua` | `TalkAction("!fixture")` — teleports the caller to a platform |

They build two platforms at coordinates the shipped map never touches, create their contents
with `setLoadedFromMap(true)` so map-clean and decay cannot remove them, and freeze their
creatures with `setMoveLocked`/`setDirectionLocked`. **No shipped file and no `.otbm` is
edited, and the map is never written back.**

| Platform | Anchor | Used by |
|---|---|---|
| Surface, `z = 6` | `34400, 34100, 6` | `map-core`, `map-screenshot`, `shader-matrix-map` |
| Underground, `z = 8` | `34500, 34201, 8` | `lighting-overlap` |

The surface platform is at `z = 6` rather than `z = 7` because `calcLastVisibleFloor` clamps to
the sea floor, so a hole cut in a `z = 7` platform would expose nothing.

## Installing

1. Check out the pinned commit in a `crystalserver` clone and build it.
2. Confirm `data-global/scripts/custom/renderer_fixtures/` is present.
3. **Restart the server.** The platform builder is a `GlobalEvent` `onStartup`, which fires only
   on the `GAME_STATE_INIT` transition — dropping the scripts into a running server does
   nothing. This is the single most common way the online scenes fail.
4. A healthy boot logs one line beginning `[renderer-fixtures]`, reporting the tile and creature
   counts for both platforms.

## The capture character matters

Which character captures a scene is load-bearing, not incidental. `ProtocolGame` forces world
light and every creature light to 255/215 for any player whose group carries `hasfulllight`
(groups 4–7), and `LightView` sets `m_isDark = intensity < 250` — so for such a character the
entire LIGHT pool is skipped.

| Scene | Character group | Why |
|---|---|---|
| `map-core`, `map-screenshot`, `shader-matrix-map` | `hasfulllight` (e.g. `GOD`, group 6) | Pins world light to 255, making the surface immune to the wall-clock day/night cycle this build cannot freeze from Lua |
| `lighting-overlap` | group 1 (normal) | The inverse: a `hasfulllight` character renders no lights at all |

`!fixture` is registered for group 1 and up, so both cases can teleport themselves. Each scene
declares its requirement as `requiresCharacterGroup` in the manifest.

## Updating the pin

Re-vendoring is three steps plus a validate:

```sh
# 1. copy the scripts out of the server checkout
cp /path/to/crystalserver/data-global/scripts/custom/renderer_fixtures/*.lua \
   docs/rendering-baselines/fixture-server/

# 2. record the new digests
shasum -a 256 docs/rendering-baselines/fixture-server/*.lua

# 3. update commit/branch and the "files" digests in docs/rendering-baselines/scenes.json,
#    and the anchors if any coordinate moved

python3 tools/renderer_scenes.py validate
```

`validate` enforces four things, so a half-finished update fails rather than rotting:

- every vendored `.lua` matches its recorded sha256, and none is unrecorded;
- `commit` is a full 40-character sha1;
- the manifest anchors agree with `FIXTURE_ANCHORS` in
  `modules/dev_renderer_baseline/dev_renderer_baseline.lua`;
- every `requiresOnlineGame` scene names an anchor that exists, and declares its character
  group.

If a coordinate changes, the client's `FIXTURE_ANCHORS` table must change with it — the capture
driver polls the player position against that table and aborts rather than capturing the wrong
place.
