# Phase 0 renderer handoff

**Checkpoint:** `0045e14` on `main` (pushed to `origin`, the fork `aacruzgon/CrystalOTC`)

**Date:** 2026-08-20

**Scope:** Phase 0 — GL bring-up on macOS, baselines, and test scenes

## Current state

The OpenGL client builds and runs on Apple Silicon through XQuartz. The repository has a
deterministic capture driver, an image comparator, a manifest that is now the single source
of truth for the scene list, and a Linux llvmpipe workflow with a real comparison gate.

Eleven of the fourteen declared scenes are automated. `lighting-overlap` — the scene the
previous handoff recorded as having failed twice — is implemented and repeatable, driven by
server-authored world state. `shader-matrix` and `windowing` remain unimplemented.

At this checkpoint:

- `ctest --test-dir build/macos-release --output-on-failure` passes all 22 tests.
- `luac -p` passes on `init.lua` and the capture driver.
- `python3 tools/renderer_scenes.py validate` exits 0.
- Every offline scene listed below was captured repeatedly and compared.
- The llvmpipe workflow has run on GitHub. Its first run failed; the failure and all four
  warnings were diagnosed from the logs and fixed. It has **not yet completed a green run**.

## What changed since the previous handoff

### Capture determinism

Two consecutive `map-core` captures were measured differing in **62% of their pixels**, so
no online scene could have served as a baseline. Four independent causes were found and
fixed; see `docs/rendering-baselines/known-deviations.md` for the measurements.

- Capture runs now use their own write directory, reset before any setting is read. A
  capture previously inherited *and overwrote* the developer's real client configuration.
- The window is sized before login, because `game_interface.show()` derives the map panel
  geometry from the window size at game start.
- The FPS/ping HUD (drawn inside the map panel) and the re-opening enter-game window are
  neutralised after game start.
- `g_shaders.setFixedTime` pins `u_Time`. This also removed the last drift from two existing
  scenes: `outfit-masks` and `temporary-framebuffers` went from 520 and 449 differing pixels
  to **0**.

### The lighting question, resolved

The previous handoff correctly said not to repeat the client-side approach but did not know
why it failed. The cause is now established from source:

`ProtocolGame` forces world light and every creature light to 255/215 for any player whose
group carries `hasfulllight` (groups 4, 5, 6, 7). `LightView` sets `m_isDark = intensity <
250`, so with such a character **the entire LIGHT pool is skipped**. The baseline character
`GOD` is group 6. No client-side change could ever have made lights appear for it.

The scene therefore uses a **group-1 character on the same account** and an **underground**
platform, where `MapView::updateLight` substitutes `Light{0,215}` for the server's world
light — which also removes the day/night cycle, since this build has no Lua world-light
setter and seeds `lightHour` from the wall clock.

Item light is read from `appearances.dat` by both server and client and never travels on the
wire, so placing the item server-side is sufficient. Three stock torches give pure red,
green and cyan at equal brightness.

### Server fixtures

`crystalserver` gained `data-global/scripts/custom/renderer_fixtures/` (commit `f47f6e41`,
branch `local/testing`, **not pushed**): a startup GlobalEvent that builds two platforms at
coordinates the shipped map never touches, and a `!fixture` talkaction usable by a group-1
character. No shipped file and no `.otbm` was edited; the map is never written back.

The surface platform is at z=6, not z=7, because `calcLastVisibleFloor` clamps to the sea
floor and a hole cut in a z=7 platform would expose nothing.

### Tooling and CI

- `tools/renderer_scenes.py` makes `scenes.json` the single source of truth. The scene list
  had been duplicated three times in different orders.
- The comparator's diff image dropped the alpha delta, so an alpha-only regression failed the
  gate while producing an all-black diff. Latent today (all captures are opaque) but exactly
  the regression class a Metal backend introduces. Failures now carry distinct exit codes.
- The workflow had never executed. Four blockers would have hard-failed its first run, and a
  fifth (alsa's autotools requirement) was only visible once it did run.
- `outfit-masks` and `temporary-framebuffers` are captured but **not gated**: `data/things/*`
  is gitignored, so a CI runner renders them empty and gating would freeze a blank reference.

## Automated scenes

Offline, gated in CI: `startup-ui`, `ui-clipping-opacity`, `text-matrix`, `particles-blends`,
`composition-all`, `graph-lines`, `atlas-resources`.

Offline, captured but not gated: `outfit-masks`, `temporary-framebuffers`.

Online, require the fixture server: `map-core`, `map-screenshot`, `lighting-overlap`.

## Remaining Phase 0 work

1. **Add the `windowing` driver.** It is the last offline scene with no command. Note that
   `focus` is not observable in any captured image (`hasFocus()` has zero consumers), and CI's
   Xvfb has no window manager, so `setFullscreen`/`maximize` are silently dropped while the
   client still flips its state bits — those are logged-state assertions, not image ones.
2. **Implement `shader-matrix-map`.** `shader-matrix` now covers every shipped fragment
   program offline, but not the map-*composition* route: map shaders bind at the MAP
   framebuffer to screen blit and `canDraw(MAP)` is literally `g_game.isOnline()`, so that
   bind site, its four map uniforms and the shader fade still need a live map.
3. **Support multi-capture in the driver.** `captureScene` is hard-wired to one screenshot
   followed by exit, which `windowing` needs factored apart.
4. ~~Record 60 seconds of release-build frame-time and memory.~~ **Deferred to Phase 3.**
   `AUTO_STAT` is compiled out of every build this repository produces, and the client caps
   itself at 60 FPS by default, so a Phase 0 figure would measure the cap rather than the
   renderer — and there is nothing to compare it against until a second path exists.
5. **Get the llvmpipe workflow green**, then seed references with
   `workflow_dispatch(refresh_references=true)` and commit them. Until references exist every
   gated scene logs `UNGATED-pending-reference` and the gate is a no-op.
6. **First XQuartz-versus-llvmpipe comparison**, recorded with evidence.
7. **Push the crystalserver fixture commit** once the client side is confirmed.

## Reproduction commands

```sh
cmake --preset macos-release -DTOGGLE_BIN_FOLDER=ON
cmake --build --preset macos-release --parallel 8
ctest --test-dir build/macos-release --output-on-failure
```

Offline scene:

```sh
DISPLAY=:0 build/macos-release/bin/otclient \
  --renderer-baseline=graph-lines --renderer-baseline-output=graph-lines.png
```

Online scenes. Note the character differs by scene — this is load-bearing, not incidental:

```sh
# map-core / map-screenshot: GOD (group 6). Its hasfulllight flag pins world light to 255,
# which disables the LIGHT pool and makes the surface immune to the day/night cycle.
DISPLAY=:0 CRYSTALOTC_BASELINE_ACCOUNT=@god CRYSTALOTC_BASELINE_PASSWORD=god \
CRYSTALOTC_BASELINE_CHARACTER=GOD \
build/macos-release/bin/otclient --renderer-baseline=map-core --renderer-baseline-output=map-core.png

# lighting-overlap: a group-1 character, or the LIGHT pool is skipped entirely.
DISPLAY=:0 CRYSTALOTC_BASELINE_ACCOUNT=@god CRYSTALOTC_BASELINE_PASSWORD=god \
CRYSTALOTC_BASELINE_CHARACTER="Sorcerer Sample" \
build/macos-release/bin/otclient --renderer-baseline=lighting-overlap --renderer-baseline-output=lighting-overlap.png
```

Captures land in the isolated baseline write directory, not the normal client one:
`~/Library/Application Support/crystalotc-baseline/.crystalotc-baseline/render-baselines/`.

Scene list and comparison:

```sh
python3 tools/renderer_scenes.py ids --offline
python3 tools/renderer_scenes.py ids --gated
python3 tools/compare_renderer_images.py reference.png candidate.png --diff diff.png
```

The server must be running for online scenes:

```sh
cd /Users/alancruz/Github/Tibia/crystalserver && ./build/macos-release/bin/crystalserver
```

Expected non-fatal local logs: missing `config.ini`, missing production soundbank, and
duplicate-library linker warnings.

## Commit ledger

Oldest first. Note that the sixteen previously subject-only messages were rewritten with
full bodies; every hash below is therefore new since the previous handoff.

```text
8194e58 fix(macos): bring up the XQuartz OpenGL client
1993a61 test(renderer): add deterministic baseline capture
bab2daf ci(renderer): archive llvmpipe startup baselines
47ad6ee fix(login): support the local 15.25 crystal server
af37763 test(renderer): capture the live map fixture
01e295e test(renderer): add deterministic UI fixtures
51cbff4 ci(renderer): capture deterministic UI matrix
bd66a9b test(renderer): add particle blend fixture
700a0f9 ci(renderer): capture particle blend baseline
bb8e117 test(renderer): add deterministic outfit fixture
f394a10 ci(renderer): capture outfit mask baseline
a60fd9b test(renderer): cover temporary framebuffer paths
c31e77f ci(renderer): capture temporary framebuffer baseline
c837b5a test(renderer): cover all composition modes
2381dbc ci(renderer): capture composition baseline
f99e738 test(renderer): automate map readback baseline
b751b93 test(renderer): add deterministic graph fixture
e759e87 ci(renderer): capture graph baseline
eb66c2b test(renderer): cover atlas resource lifecycle
c5b510b ci(renderer): capture atlas baseline
5f9ad3e test(renderer): suppress capture tooltips
bf9c28d docs(renderer): hand off phase zero progress
32cde60 refactor(login): collapse the duplicated devserver branch
d8f3f7a fix(renderer): make online baseline captures reproducible
d0cebb6 feat(graphics): allow pinning shader time for reproducible captures
497dc70 fix(renderer): make the baseline comparator and manifest gate-ready
942fe68 ci(renderer): make the llvmpipe baseline job runnable and gated
3b49ea5 test(renderer): implement the lighting-overlap scene
0045e14 ci(renderer): fix the first llvmpipe run's failures and warnings
```

## Repository hygiene at handoff

These design documents remain untracked and were deliberately neither edited nor staged:

- `docs/macos-rendering-architecture.md`
- `docs/metal-implementation-plan.md`
- `docs/metal-parity-survey.md`
- `docs/renderer-architecture-design.md`

Their commit disposition is still an open decision. Note that
`docs/renderer-architecture-design.md` §7 and §12.4 should be amended: the
`glReadPixels(x/3, y/1.5)` offsets are confirmed **intentional framing**, not a bug, so the
crop is preserved deliberately rather than "not reproduced at the boundary".

The `crystalserver` fixture commit `f47f6e41` is unpushed on branch `local/testing`.
