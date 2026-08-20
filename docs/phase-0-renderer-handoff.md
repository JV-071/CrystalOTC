# Phase 0 renderer handoff

**Checkpoint:** `5e51ec3` on `main`

**Date:** 2026-08-19

**Scope:** Phase 0 — GL bring-up on macOS, baselines, and test scenes

## Current state

The OpenGL client builds and runs on Apple Silicon through XQuartz. The repository now has a deterministic capture driver, an image comparator, a documented scene manifest, and a Linux llvmpipe workflow that archives the offline reference matrix. Local captures use XQuartz for development; Linux llvmpipe remains the intended canonical renderer.

The local Crystal server at `/Users/alancruz/Github/Tibia/crystalserver` is usable for online captures. It speaks protocol 15.25 on `127.0.0.1:7182`, while its login service is on port 8080. Commit `3e7c3ad` adds a distinct 15.25 profile that reuses the checked-in 15.30 asset catalog. It does not remove 15.30 support or change the existing 15.30 packet readers.

At this checkpoint:

- `ctest --test-dir build/macos-release --output-on-failure` passes all 22 tests.
- `luac -p modules/dev_renderer_baseline/dev_renderer_baseline.lua` passes.
- The offline XQuartz fixtures listed below were captured repeatedly and visually inspected.
- `map-core` and `map-screenshot` log into the running server successfully, but the current development world is animated and is not a deterministic canonical fixture.
- No unverified lighting implementation remains in the worktree.

## Completed work

### macOS OpenGL bring-up

- Fixed macOS/XQuartz compilation, linking, and GLX context creation.
- Pinned Apple builds to XQuartz headers and `libGL`, `libX11`, and `libXext` under `/opt/X11`; mixing Homebrew X11 with XQuartz GL causes runtime visual-selection failure.
- Verified XQuartz 2.8.6 on an Apple M3 Pro: OpenGL 2.1 (`2.1 Metal - 90.5`) and GLSL 1.20.

### Capture infrastructure

- `modules/dev_renderer_baseline` drives named captures and exits automatically.
- `docs/rendering-baselines/scenes.json` is the coverage/status source of truth.
- `tools/compare_renderer_images.py` applies the documented per-channel and pixel-fraction tolerance.
- `.github/workflows/render-baseline-linux.yml` builds on Ubuntu 24.04, captures offline scenes under Xvfb/llvmpipe, records metadata, and uploads artifacts.
- Hovered normal and special tooltips are cleared immediately before full-window capture so mouse position cannot contaminate a baseline (`5e51ec3`).

### Automated offline scenes

These are included in the Linux llvmpipe workflow and have local XQuartz coverage:

- `startup-ui`
- `ui-clipping-opacity`
- `text-matrix`
- `particles-blends`
- `outfit-masks`
- `temporary-framebuffers`
- `composition-all`
- `graph-lines`
- `atlas-resources`

See `docs/rendering-baselines/known-deviations.md` for the observed OpenGL behavior and repeatability of each scene. In particular, `composition-all` freezes a surprising retained-destination artifact in the legacy ADD path; preserve it until the renderer migration makes any intentional behavior change explicit.

### Automated online diagnostics

- `map-core` captures the full client after login.
- `map-screenshot` captures the MAP framebuffer readback.
- The unusual `glReadPixels(x / 3, y / 1.5)` behavior was resolved as intentional framing. The MAP framebuffer has a three-tile margin: one logical tile on left/top and two on right/bottom. With 32 px sprites, the correct GL offsets are x=32 and y=64, producing the expected 480x352 image for a 15x11 viewport. Preserve that crop when converting readback to explicit top-left coordinates.

## Remaining Phase 0 work

Do these before declaring the Phase 0 exit gate complete:

1. Build a controlled fixture-server state for `map-core` so floors, creatures, missiles, effects, camera movement, the map FBO, and map-hole behavior are repeatable. The current live development world is diagnostic only.
2. Implement `lighting-overlap` with server-authored day/night and overlapping colored light sources. It must visibly prove the CPU light bitmap, dynamic texture upload, and MULTIPLY overlay.
3. Implement `shader-matrix`, covering all shipped map/outfit/item shaders, framebuffer-backed Outline, and Fog/Snow multi-texture bindings.
4. Add the `windowing` desktop driver for resize, display density, fullscreen, focus, and moving between displays.
5. Record at least 60 seconds of release-build frame-time and memory samples. Compare XQuartz only against XQuartz; it is not representative of native GPU performance.
6. Run and review the Linux llvmpipe workflow, retain its PNG/log/metadata artifact set, and perform the first XQuartz-versus-llvmpipe comparison. Record any evidence-backed differences in `known-deviations.md`.
7. Confirm every feature in `scenes.json` is visibly exercised, then update the manifest/README automation labels and the one-page deviations note. Phase 0 exits only when the checked-in scene list, CI-generated reference set, and deviations note are complete.

## Lighting investigation: do not repeat this approach

A client-only `lighting-overlap` prototype was tested and then removed because it did not exercise the renderer as claimed:

- An initial approach attached client-created light effects to map positions/tiles.
- A second approach added client-created `Creature` instances and exposed `Map::setLight` plus `Creature::setLight` to Lua.
- The probe creatures were visible, `UIMap::isDrawingLights()` was true, minimum ambient light was zero, and a red-only intensity-15 diagnostic was used.
- The resulting screenshot showed no colored illumination. Earlier effect-probe and no-probe captures were also visually identical in the map lighting.

The likely issue is that mutating client-created things this way does not feed the same cached/protocol-driven light state used by the production map draw. Do not restore the removed Lua bindings merely to make the script run. Prefer deterministic server-spawned items/effects/creatures with known light attributes, then verify the RGB overlap in the captured pixels before marking the scene automated.

The last red-only diagnostic image was written outside the repository at:

`~/Library/Application Support/crystalotc/.crystalotc/render-baselines/lighting-overlap-xquartz.png`

It is diagnostic evidence only and must not be accepted as a baseline.

## Reproduction commands

Configure, build, and test:

```sh
cmake --preset macos-release -DTOGGLE_BIN_FOLDER=ON
cmake --build --preset macos-release --parallel 2
ctest --test-dir build/macos-release --output-on-failure
```

The existing local build used a vcpkg checkout pinned to `vcpkg.json`; if needed, set `VCPKG_ROOT` and `VCPKG_DEFAULT_BINARY_CACHE` before configuring.

Capture an offline scene through XQuartz:

```sh
DISPLAY=:0 build/macos-release/bin/otclient \
  --renderer-baseline=graph-lines \
  --renderer-baseline-output=graph-lines-xquartz.png
```

Capture the live server map with the existing disposable development account:

```sh
DISPLAY=:0 \
CRYSTALOTC_BASELINE_ACCOUNT=@god \
CRYSTALOTC_BASELINE_PASSWORD=god \
CRYSTALOTC_BASELINE_CHARACTER=GOD \
build/macos-release/bin/otclient \
  --renderer-baseline=map-core \
  --renderer-baseline-output=map-core-xquartz.png
```

Use `map-screenshot` in place of `map-core` for MAP readback. The online driver defaults to host `127.0.0.1`, game port 7182, and protocol 15.25; environment overrides are documented in `docs/rendering-baselines/README.md`.

Compare two same-environment captures:

```sh
python3 tools/compare_renderer_images.py reference.png candidate.png \
  --diff artifacts/render-baselines/diff.png
```

Expected non-fatal local logs include missing `config.ini`, a missing production soundbank, and duplicate-library linker warnings.

## Commit ledger

The Phase 0 work is split into reviewable commits, oldest first:

```text
074ef5a fix(macos): bring up the XQuartz OpenGL client
ada8bc0 test(renderer): add deterministic baseline capture
55355fc ci(renderer): archive llvmpipe startup baselines
3e7c3ad fix(login): support the local 15.25 crystal server
d8fe826 test(renderer): capture the live map fixture
0df4c94 test(renderer): add deterministic UI fixtures
24e6cf7 ci(renderer): capture deterministic UI matrix
a3c34e4 test(renderer): add particle blend fixture
257687c ci(renderer): capture particle blend baseline
6c97e6e test(renderer): add deterministic outfit fixture
fa495d7 ci(renderer): capture outfit mask baseline
00bf705 test(renderer): cover temporary framebuffer paths
c81de3e ci(renderer): capture temporary framebuffer baseline
f94e028 test(renderer): cover all composition modes
601d005 ci(renderer): capture composition baseline
3971be8 test(renderer): automate map readback baseline
3522528 test(renderer): add deterministic graph fixture
8982eb2 ci(renderer): capture graph baseline
6aa461e test(renderer): cover atlas resource lifecycle
1a15470 ci(renderer): capture atlas baseline
5e51ec3 test(renderer): suppress capture tooltips
```

## Repository hygiene at handoff

The following design documents were already untracked during this work and were intentionally neither edited nor staged by the implementation commits:

- `docs/macos-rendering-architecture.md`
- `docs/metal-implementation-plan.md`
- `docs/metal-parity-survey.md`
- `docs/renderer-architecture-design.md`

They are essential context for the next agent, but their ownership/commit disposition should be decided separately.
