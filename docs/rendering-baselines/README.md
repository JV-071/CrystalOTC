# Renderer baselines

This directory defines the Phase 0 visual reference process used while the OpenGL renderer is moved behind `RenderFrame` and compared with Metal.

## Baseline policy

- The canonical reference is OpenGL rendered by Mesa llvmpipe on the pinned Linux CI image.
- XQuartz captures are the local development reference, not a cross-machine pixel oracle.
- Compare images produced by the same backend and environment. Cross-backend comparisons use the same tolerances but are diagnostic until parity is signed off. Since Phase 4 there are structured exceptions: `tools/compare_render_backends.sh` compares OpenGL against Metal *on the same compiled frame*, which is a narrower and answerable question, and since Phase 5 `tools/compare_online_backends.sh` asks it of the online scenes against each scene's own noise floor - see below.
- A channel difference of 2 and at most 0.1% differing pixels are the manifest defaults (`defaultTolerance` in [scenes.json](scenes.json)). A scene may raise its own limit with `channelTolerance`/`maxDifferentFraction` plus a `toleranceReason`; `map-core` and `shader-matrix-map` are at 0.2% because a creature on a live server cannot be perfectly frozen. Resolve the effective value with `tools/renderer_scenes.py field <id> maxDifferentFraction`. Missing passes, wrong dimensions, clipping errors, alpha errors, and coordinate shifts always fail review regardless of the aggregate percentage.
- Per-run PNGs and metadata are CI artifacts. The canonical llvmpipe reference for each gated scene is committed under `references/opengl-llvmpipe/`, together with `ENVIRONMENT.txt` for the run that produced it; the CI job compares every gated capture against its reference and fails on drift. Scenes marked `ciGate: false` are captured and archived only. See [references/opengl-llvmpipe/README.md](references/opengl-llvmpipe/README.md).

`tools/compare_render_paths.sh <client-binary>` (added 2026-08-21, Phase 3) answers a different question from everything else here: it captures each offline scene twice from one binary, once per render path, and compares the two. The reference gate asks whether the renderer still looks right; this asks whether the legacy and compiled paths draw the same thing, with no cross-stack difference mixed in. Tolerances come from the manifest, and one scene - `graph-lines` - carries its own `renderPathTolerance` because the two paths are meant to differ there.

`tools/compare_render_backends.sh <gl-client> <metal-client>` (added 2026-08-21, Phase 4) asks the next question in that series: whether two graphics APIs draw the same **frame** the same way. It forces the OpenGL side onto `--render-path=frame` so that both sides consume an identical `RenderFrame`, which is what makes a difference attributable below the renderer boundary rather than anywhere above it. It takes two binaries because the two backends cannot coexist in one - the Cocoa window creates no OpenGL context and the XQuartz window creates no Metal layer - and it refuses a run that silently used the wrong one. Tolerances come from `renderBackendTolerance`, and a scene the second backend cannot express at all carries `renderBackendComparable: false` with a reason naming the phase that owns it, which the harness reports as a skip rather than as a pass or a failure. The mechanism remains supported, but **as of Phase 6 no scene uses it**: all eleven offline scenes compare, and the only surviving `renderBackendTolerance` is `shader-matrix-outfits`'. Results in [known-deviations.md](known-deviations.md), section "Metal versus OpenGL".

`tools/compare_online_backends.sh <gl-client> <metal-client> [runs]` (added 2026-08-21, Phase 5) is the same question again for the **online** scenes, which no other harness touches. It covers three of the four - `map-core`, `map-screenshot` and `lighting-overlap`. The fourth, `shader-matrix-map`, was deliberately outside it: all fourteen of its cells are map shaders and no module program resolved on Metal until Phase 6, so there was nothing yet to compare. **The reason for that exclusion expired with Phase 6** — module materials resolve on Metal now — and the first cross-backend measurement of it, together with the orientation finding it produced, is in `docs/phase-6-renderer-handoff.md` and in [known-deviations.md](known-deviations.md). It is still captured by hand rather than by this harness. They are the only coverage of the MAP pool, the light overlay, the map-composition material and the map readback, and until now they were run by hand - which is how Phase 3 and Phase 4 each found a defect only after drafting their handoff. A live server cannot be frozen, so this one reports figures rather than a verdict: N runs per backend per scene, the within-backend spread printed beside the cross-backend one, on the rule that a cross-backend difference no larger than a backend's own variance is agreement. It spaces logins by twelve seconds, because without a gap the server still holds the previous session and the run either misses the fixture anchor or captures from two tiles away - which reads as a 90%-different frame and looks like a renderer defect until the shift is measured.

`tools/run_macos_matrix.sh [--skip-online]` (added 2026-08-21, Phase 5) runs all three sweeps and prints one summary. It is the pre-release check for macOS and it cannot run in CI - it needs an XQuartz binary and a Cocoa binary at once, a window server for the first and the pinned fixture server for the third. It sets both `RUN_PREFIX` and `GL_RUN_PREFIX`, which are not interchangeable: the backend sweep must wrap only the OpenGL client, since giving the Metal one a `DISPLAY` is wrong, while the path sweep drives a single client and wraps all of it.

The complete coverage list lives in [scenes.json](scenes.json), and `tools/renderer_scenes.py` is the single source of truth shared by the local capture flow and the CI job: `tools/renderer_scenes.py ids --all` reports 16 scenes, `ids --offline` the 11 CI can capture, and `ids --gated` the 8 compared against a checked-in reference. Every scene has an automated `command`; Phase 0 is complete. `ciCapture: false` marks a scene CI cannot capture at all (`windowing`), and `ciGate: false` marks those captured but not compared (`outfit-masks`, `temporary-framebuffers`, `shader-matrix-outfits`), each carrying a `ciCaptureReason` or `ciGateReason`.

`shader-matrix` was split on 2026-08-20 so that its sixteen fragment cells could be gated: every fragment cell draws a tracked image from `data/images`, so it renders identically with or without game assets, while the six outfit cells depend on gitignored `data/things/*` and moved to `shader-matrix-outfits`. The fragment cells kept their exact coordinates through the split.

## macOS XQuartz bring-up

Prerequisites:

1. Install XQuartz 2.8.6 or newer, then log out and back in when its installer requests it.
2. Clone vcpkg and check out the full `builtin-baseline` SHA from `vcpkg.json`.
3. Set `VCPKG_ROOT` to that checkout.

Configure and build:

```sh
cmake --preset macos-release -DTOGGLE_BIN_FOLDER=ON
cmake --build --preset macos-release --parallel 2
```

Start XQuartz, obtain the `DISPLAY` value from an XQuartz terminal, and launch the automated startup capture from the repository root:

```sh
DISPLAY="$DISPLAY" build/macos-release/bin/otclient \
  --renderer-baseline=startup-ui \
  --renderer-baseline-output=startup-ui.png
```

The client logs the real output path. A `--renderer-baseline=` run gets its own isolated write directory: init.lua appends `-baseline` to the compact name and resets that directory before any setting is read, so captures land in `<userdir>/crystalotc-baseline/.crystalotc-baseline/render-baselines/startup-ui.png` rather than in the normal client directory. There is no organization-name component in that path.

The deterministic offline UI fixtures use the same command shape and require no server. Drive the loop from the manifest rather than a hardcoded list, so a scene added later is picked up without editing this file:

```sh
for scene in $(python3 tools/renderer_scenes.py ids --offline); do
  DISPLAY="$DISPLAY" build/macos-release/bin/otclient \
    --renderer-baseline="$scene" \
    --renderer-baseline-output="$scene.png"
done
```

That query reports 11 scenes and includes `startup-ui`, so the loop repeats the capture shown above.

The scripted fixture is isolated from normal startup windows one frame before readback. This keeps late-opening login and game-option dialogs out of the capture without changing normal client startup behavior.

For an online capture, the server must be built from the fixture branch. That dependency is pinned in `scenes.json` under `fixtureServer` — print it with `python3 tools/renderer_scenes.py fixture` — and the scripts themselves are vendored for reference under [fixture-server/](fixture-server/), which documents installation, the restart requirement, and the per-scene character-group rule. In short: `aacruzgon/crystalserver` commit `f47f6e41` on branch `local/testing`, which adds `data-global/scripts/custom/renderer_fixtures/`, a startup GlobalEvent that builds the surface and underground platforms plus a `!fixture <map|lighting>` talkaction. The GlobalEvent fires only on the `GAME_STATE_INIT` transition, so a server that was already running when the scripts were installed will not have the platforms. The driver no longer captures wherever the character happens to be: it polls the player position against the platform anchor and re-sends the talkaction until it lands, failing loudly rather than capturing the wrong place, so a plain server aborts the run. Start that server and its login database, then provide a disposable fixture account through the environment:

```sh
CRYSTALOTC_BASELINE_ACCOUNT="@fixture" \
CRYSTALOTC_BASELINE_PASSWORD="fixture-password" \
CRYSTALOTC_BASELINE_CHARACTER="Fixture Character" \
DISPLAY="$DISPLAY" build/macos-release/bin/otclient \
  --renderer-baseline=map-core \
  --renderer-baseline-output=map-core.png
```

Use the `GOD` character for `map-core`, `map-screenshot`, and `shader-matrix-map`: its group carries `hasfulllight`, which pins world light and makes those captures immune to the day/night cycle. `lighting-overlap` needs a group-1 character on the same account for the inverse reason, and stands on the underground platform; see [known-deviations.md](known-deviations.md). Each online scene declares this as `requiresCharacterGroup` in the manifest, and `renderer_scenes.py validate` requires it to be present.

Use `--renderer-baseline=map-screenshot --renderer-baseline-output=map-screenshot.png` with the same environment to capture the MAP framebuffer readback rather than the complete client window. This scene preserves and verifies the legacy asymmetric one-tile/two-tile margin crop.

The online driver defaults to `127.0.0.1:7182` and protocol 15.25. Override these with `CRYSTALOTC_BASELINE_HOST`, `CRYSTALOTC_BASELINE_PORT`, or `CRYSTALOTC_BASELINE_VERSION`. Credentials stay out of command-line arguments and capture metadata.

Before accepting the capture, record `glxinfo -B`, the git commit, viewport, backend, OS image, and whether the run used XQuartz or llvmpipe. Performance measurement is deferred to Phase 3 (item 6 in [../metal-implementation-plan.md](../metal-implementation-plan.md)): `AUTO_STAT` is compiled out of every build this repository produces and the client sleeps to cap itself at 60 FPS, so a Phase 0 frame-time figure would measure the cap rather than the renderer. Phase 0 capture review is pixel-only. ~~Whatever is eventually measured must use a release build and at least 60 seconds of steady-state samples, and XQuartz values are only compared with other XQuartz values.~~ **Measured 2026-08-21 (Phase 3), and differently:** `--renderer-benchmark=<seconds>` (added 2026-08-21, Phase 3) reuses any scene the capture driver already builds. It removes the client's own 60 FPS sleep **and** asks for vsync off - two ceilings, and only the first comes off here, because XQuartz advertises neither `GLX_MESA_swap_control` nor `GLX_SGI_swap_control`. With the rate display-locked, frame rate carries no information and CPU time does: both paths render the same number of frames, so whole-process CPU over a fixed window compares per-frame cost directly. The same-environment rule survives unchanged; the 60-second one did not, because the useful figure turned out to be CPU over a 20-second window rather than a frame-rate average. Numbers are in `../metal-implementation-plan.md`, Phase 5's exit gate.

## Image comparison

Install Pillow, then compare two same-environment captures:

```sh
python3 tools/compare_renderer_images.py reference.png candidate.png \
  --diff artifacts/render-baselines/diff.png
```

The command exits nonzero when dimensions differ or more than the allowed fraction of pixels exceeds the per-channel tolerance.

## Capture review checklist

- Confirm the scenario ID and every feature listed for it in `scenes.json` are visible.
- Inspect the generated diff, not only the aggregate result.
- Treat coherent shifted edges, missing regions, and alpha halos as structural failures.
- Store the client log and GL renderer metadata beside every PNG artifact.
- Record accepted platform-specific differences in [known-deviations.md](known-deviations.md).
