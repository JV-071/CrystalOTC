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

Every scene in `scenes.json` now has a command; none are unimplemented. One item is left, and
it is blocked rather than pending:

1. **Reseed the `startup-ui` reference.** It is the only gated scene without a reference. The
   original was captured before the login background was pinned, so it could never match
   again and was deliberately removed; `startup-ui` logs `UNGATED-pending-reference` until it
   is replaced. A reference must come from llvmpipe, so only a green run of the workflow can
   produce one: take `startup-ui.png` from that run's artifact and commit it to
   `docs/rendering-baselines/references/opengl-llvmpipe/`.

2. **Push the crystalserver fixture commit** (`f47f6e41` on branch `local/testing`) once the
   client side is considered settled. Note that repository's remotes are named the opposite
   way round from this one: `origin` is upstream (`zimbadev/crystalserver`) and the fork is
   `fork` (`aacruzgon/crystalserver`). Pushing to `origin` there has been disabled locally to
   prevent the mistake.

## Deferred follow-ups

Real issues found during Phase 0 that are deliberately not being fixed here. None block the
exit gate.

**Node 20 deprecation in `build-windows.yml`.** Its actions (`checkout`, `cache`,
`upload-artifact`, `download-artifact`) target the deprecated Node 20 runtime. GitHub
currently force-runs them on Node 24 with a warning, so it is cosmetic until it is not. The
bump was prepared and then deliberately reverted: it includes `actions/cache`, and changing
that risks invalidating the warm vcpkg cache on a build whose median is around 60 minutes.
It deserves its own commit and a cold build to verify, not a ride-along on an unrelated fix.
The renderer-baseline workflow is already off Node 20, where there was no cache to lose.

**`tests-lua.yml` tests nothing.** It installs LuaJIT, checks out the code, and ends. It runs
on every push and pull request with no path filter and always reports green, so it reads as a
passing check while asserting nothing. It also uses `actions/checkout@main`, an unpinned
floating ref.

**`actions/labeler@main` is unpinned** in `pr-labeler.yml`, and `.github/labeler.yml` still
uses v4 syntax, so a labeler major release can break it with no change in this repository.

**The container digest does not freeze Mesa.** The baseline job pins `ubuntu:24.04` by digest,
which freezes the base image, but Mesa is installed by `apt` at job time from the Ubuntu
archive, so a point release can shift llvmpipe rasterization without the digest moving. The
exact package versions are recorded in the reference set's `ENVIRONMENT.txt` so a drift is
diagnosable in one look. Fully pinning apt versions would break the job whenever Ubuntu
rotates a superseded version out of the archive.

**`XZ_SANDBOX` unused-variable warning** is emitted by the `liblzma` port at the pinned vcpkg
baseline, not by this repository. Silencing it means patching a port or moving the baseline.

**`shader-matrix` cannot be CI-gated as one scene.** Its sixteen fragment cells would gate
cleanly, but its six outfit cells render creature previews from `data/things/*`, which is
gitignored, so a CI runner draws them empty. Splitting the outfit row into its own scene would
let the fragment half be gated. The same reasoning applies to `outfit-masks` and
`temporary-framebuffers`, which are gated off for exactly this reason.

**`map-screenshot` carries a 62-pixel residual** from one animated decoration.
`Thing:setAnimate(false)` stops a sprite advancing but leaves it on whatever phase it already
held, and that phase differs per run. Freezing at a *known* phase would need a binding that
does not exist.

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
