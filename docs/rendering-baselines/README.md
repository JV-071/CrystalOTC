# Renderer baselines

This directory defines the Phase 0 visual reference process used while the OpenGL renderer is moved behind `RenderFrame` and compared with Metal.

## Baseline policy

- The canonical reference is OpenGL rendered by Mesa llvmpipe on the pinned Linux CI image.
- XQuartz captures are the local development reference, not a cross-machine pixel oracle.
- Compare images produced by the same backend and environment. Cross-backend comparisons use the same tolerances but are diagnostic until parity is signed off.
- A channel difference of 2 and at most 0.1% differing pixels are the manifest defaults (`defaultTolerance` in [scenes.json](scenes.json)). A scene may raise its own limit with `channelTolerance`/`maxDifferentFraction` plus a `toleranceReason`; `map-core` and `shader-matrix-map` are at 0.2% because a creature on a live server cannot be perfectly frozen. Resolve the effective value with `tools/renderer_scenes.py field <id> maxDifferentFraction`. Missing passes, wrong dimensions, clipping errors, alpha errors, and coordinate shifts always fail review regardless of the aggregate percentage.
- Per-run PNGs and metadata are CI artifacts. The canonical llvmpipe reference for each gated scene is committed under `references/opengl-llvmpipe/`, together with `ENVIRONMENT.txt` for the run that produced it; the CI job compares every gated capture against its reference and fails on drift. Scenes marked `ciGate: false` are captured and archived only. See [references/opengl-llvmpipe/README.md](references/opengl-llvmpipe/README.md).

The complete coverage list lives in [scenes.json](scenes.json), and `tools/renderer_scenes.py` is the single source of truth shared by the local capture flow and the CI job: `tools/renderer_scenes.py ids --all` reports 15 scenes, `ids --offline` the 10 CI can capture, and `ids --gated` the 7 compared against a checked-in reference. Every scene has an automated `command`; Phase 0 is complete. `ciCapture: false` marks a scene CI cannot capture at all (`windowing`), and `ciGate: false` marks one captured but not compared (`outfit-masks`, `temporary-framebuffers`, `shader-matrix`), each carrying a `ciCaptureReason` or `ciGateReason`.

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

That query reports 10 scenes and includes `startup-ui`, so the loop repeats the capture shown above.

The scripted fixture is isolated from normal startup windows one frame before readback. This keeps late-opening login and game-option dialogs out of the capture without changing normal client startup behavior.

For an online capture, the server must be built from the fixture branch: `aacruzgon/crystalserver` commit `f47f6e41` on branch `local/testing`, which adds `data-global/scripts/custom/renderer_fixtures/`, a startup GlobalEvent that builds the surface and underground platforms plus a `!fixture <map|lighting>` talkaction. The driver no longer captures wherever the character happens to be: it polls the player position against the platform anchor and re-sends the talkaction until it lands, failing loudly rather than capturing the wrong place, so a plain server aborts the run. Start that server and its login database, then provide a disposable fixture account through the environment:

```sh
CRYSTALOTC_BASELINE_ACCOUNT="@fixture" \
CRYSTALOTC_BASELINE_PASSWORD="fixture-password" \
CRYSTALOTC_BASELINE_CHARACTER="Fixture Character" \
DISPLAY="$DISPLAY" build/macos-release/bin/otclient \
  --renderer-baseline=map-core \
  --renderer-baseline-output=map-core.png
```

Use the `GOD` character for `map-core`, `map-screenshot`, and `shader-matrix-map`: its group carries `hasfulllight`, which pins world light and makes those captures immune to the day/night cycle. `lighting-overlap` needs a group-1 character on the same account for the inverse reason, and stands on the underground platform; see [known-deviations.md](known-deviations.md).

Use `--renderer-baseline=map-screenshot --renderer-baseline-output=map-screenshot.png` with the same environment to capture the MAP framebuffer readback rather than the complete client window. This scene preserves and verifies the legacy asymmetric one-tile/two-tile margin crop.

The online driver defaults to `127.0.0.1:7182` and protocol 15.25. Override these with `CRYSTALOTC_BASELINE_HOST`, `CRYSTALOTC_BASELINE_PORT`, or `CRYSTALOTC_BASELINE_VERSION`. Credentials stay out of command-line arguments and capture metadata.

Before accepting the capture, record `glxinfo -B`, the git commit, viewport, backend, OS image, and whether the run used XQuartz or llvmpipe. Performance measurement is deferred to Phase 3 (item 6 in [../metal-implementation-plan.md](../metal-implementation-plan.md)): `AUTO_STAT` is compiled out of every build this repository produces and the client sleeps to cap itself at 60 FPS, so a Phase 0 frame-time figure would measure the cap rather than the renderer. Phase 0 capture review is pixel-only. Whatever is eventually measured must use a release build and at least 60 seconds of steady-state samples, and XQuartz values are only compared with other XQuartz values.

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
