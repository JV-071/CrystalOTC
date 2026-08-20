# Renderer baselines

This directory defines the Phase 0 visual reference process used while the OpenGL renderer is moved behind `RenderFrame` and compared with Metal.

## Baseline policy

- The canonical reference is OpenGL rendered by Mesa llvmpipe on the pinned Linux CI image.
- XQuartz captures are the local development reference, not a cross-machine pixel oracle.
- Compare images produced by the same backend and environment. Cross-backend comparisons use the same tolerances but are diagnostic until parity is signed off.
- A channel difference of 2 is tolerated by default. At most 0.1% of pixels may exceed that tolerance. Missing passes, wrong dimensions, clipping errors, alpha errors, and coordinate shifts always fail review regardless of the aggregate percentage.
- PNGs and metadata are CI artifacts. They are not committed until a scene is stable and its required game assets can be distributed reproducibly.

The complete required coverage and automation status live in [scenes.json](scenes.json). `startup-ui`, `ui-clipping-opacity`, `text-matrix`, `particles-blends`, `outfit-masks`, `temporary-framebuffers`, and the fixture-backed `map-core` capture are automated now. Entries marked `fixture-server`, `client-script`, `native-fixture`, or `desktop-driver` are the remaining Phase 0 fixture work, not optional coverage.

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

The client logs the real output path. By default it is under the CrystalOTC user write directory in `render-baselines/startup-ui.png`.

The deterministic offline UI fixtures use the same command shape and require no server:

```sh
for scene in ui-clipping-opacity text-matrix particles-blends outfit-masks temporary-framebuffers; do
  DISPLAY="$DISPLAY" build/macos-release/bin/otclient \
    --renderer-baseline="$scene" \
    --renderer-baseline-output="$scene.png"
done
```

The scripted fixture is isolated from normal startup windows one frame before readback. This keeps late-opening login and game-option dialogs out of the capture without changing normal client startup behavior.

For an online map capture, start the Crystal server and its login database, then provide a disposable fixture account through the environment:

```sh
CRYSTALOTC_BASELINE_ACCOUNT="@fixture" \
CRYSTALOTC_BASELINE_PASSWORD="fixture-password" \
CRYSTALOTC_BASELINE_CHARACTER="Fixture Character" \
DISPLAY="$DISPLAY" build/macos-release/bin/otclient \
  --renderer-baseline=map-core \
  --renderer-baseline-output=map-core.png
```

The online driver defaults to `127.0.0.1:7182` and protocol 15.25. Override these with `CRYSTALOTC_BASELINE_HOST`, `CRYSTALOTC_BASELINE_PORT`, or `CRYSTALOTC_BASELINE_VERSION`. Credentials stay out of command-line arguments and capture metadata.

Before accepting the capture, record `glxinfo -B`, the git commit, viewport, backend, OS image, and whether the run used XQuartz or llvmpipe. Frame-time and memory measurements must use a release build and at least 60 seconds of steady-state samples; XQuartz values are only compared with other XQuartz values.

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
