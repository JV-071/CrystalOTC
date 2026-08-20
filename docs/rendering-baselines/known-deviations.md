# Known renderer deviations

## Windows Vulkan feeder versus OpenGL

These are current implementation gaps, not accepted Metal deviations:

- The LIGHT pool is consumed but not rendered.
- Painter/module shaders are ignored.
- Opaque OpenGL action lambdas are skipped.
- Framebuffer-derived textures without CPU pixels cannot enter the Vulkan atlas.
- Composition modes other than NORMAL and MULTIPLY fall back to NORMAL.
- Temporary framebuffers are flattened with an affine coordinate transform rather than represented as offscreen passes; clipping inside them is skipped.
- The foreground map hole is implemented by cutting previously emitted geometry, not by an alpha-zero blend-disabled draw into a retained target.

## XQuartz OpenGL versus llvmpipe OpenGL

The first local reference capture completed on 2026-08-19 with XQuartz 2.8.6 on an Apple M3 Pro. XQuartz reported OpenGL 2.1 (`2.1 Metal - 90.5`) and GLSL 1.20. The `startup-ui` scene rendered at 1020x644 with the expected login background, bitmap text, icons, translucent panels, clipping, and initial resize; no local rendering defect was observed.

The `ui-clipping-opacity` and `text-matrix` client fixtures were also captured twice on that setup. Each repeated capture was byte-equivalent at the decoded pixel level: 656,880 pixels compared, zero pixels different. Visual inspection found no clipping, alpha, alignment, TTF-stroke, or rotation defect.

The `particles-blends` fixture uses one fixed, single-burst particle for each composition mode used by live code: NORMAL, MULTIPLY, and the legacy ADD equation. Two settled captures had no pixels beyond the default per-channel tolerance; the maximum observed channel delta was 1. The ADD particle is intentionally smaller because its high-contrast center magnifies harmless one-channel raster rounding while still making the blend equation unmistakable.

The `outfit-masks` fixture freezes creature animation and captures mask recoloring, both addon layers, a mount, the creature-preview framebuffer, and the framebuffer-backed Outline shader. Outline deliberately retains its production `u_Time` brightness pulse. Two captures therefore differed in 520 pixels (0.0792%, below the 0.1% policy limit); the diff was confined to the outlined preview and is expected for this scene.

The `temporary-framebuffers` fixture covers every surveyed call site: creature preview, the nested Outline/ThingType path, item blits with both flip directions, effect and missile widgets, and spell-preview object compositing. Its animated outline probe is kept small enough for the whole-scene tolerance: the repeated XQuartz capture differed in 449 pixels (0.0684%), confined to the expected shader pulse.

The native `composition-all` fixture exercises all six painter descriptors, including the three with no production caller. Its ADD cell consistently exposes a faint image of startup UI retained in the FOREGROUND target, even though the fixture submits REPLACE clears for the target area and each destination cell. This is frozen as observed OpenGL behavior, not accepted as desirable renderer semantics. Two captures had no pixels beyond tolerance (maximum channel delta 2).

The map-screenshot offsets are intended framing, despite their unusual spelling. The MAP framebuffer is three tiles larger than the visible dimension. `MapView::calcFramebufferSource` selects the visible region after one spare tile on logical left/top, leaving two on right/bottom. For a 32 px sprite, the left-origin x offset is therefore 32; bottom-origin `glReadPixels` must skip the two logical bottom tiles, so its y offset is 64. The existing `x / 3, y / 1.5` call receives a total three-tile trim (96 px) and produces exactly those offsets. The XQuartz fixture-server capture was correctly oriented and measured 480x352, exactly the 15x11 visible tiles. Preserve the output crop while moving the arithmetic into explicit top-left readback parameters. The currently running development world has animated effects and creatures, so repeated local captures are diagnostic; a canonical comparison still requires a controlled fixture-server state.

The `graph-lines` fixture drives the real `UIGraph` action-lambda path with fixed 1 px, 3 px, and 6 px `GL_LINE_STRIP` geometry. Hover information is disabled so mouse position cannot change the result. Two XQuartz captures were pixel-identical (656,880 pixels, maximum channel delta 0).

The `atlas-resources` fixture loads sixteen unique 522x522 smooth textures, an atlas-eligible 1344x320 sheet, and an APNG frame through the production foreground atlas. Both XQuartz runs grew the linear filter group to three 2048x2048 layers. Releasing and reloading four textures left one reusable inactive size bucket while retaining 41 cached entries. Clearing the texture-manager cache also freezes the displayed APNG after its first upload. The two final captures were pixel-identical.

No XQuartz-versus-llvmpipe image has been compared yet, so no cross-environment pixel difference is accepted. Small rasterization and sampling differences may be accepted only after side-by-side evidence is attached here. XQuartz performance numbers are never compared directly with llvmpipe or native GPU numbers.

The client must link `libGL`, `libX11`, and `libXext` from the same XQuartz installation. Mixing XQuartz GL with Homebrew X11 links successfully but causes GLX visual selection to fail at runtime. The macOS CMake path now pins all four headers/libraries under `/opt/X11`.

The current checkout has no `config.ini` and omits the production soundbank, so the reference launch logs those two non-fatal missing-file errors. Neither affected the startup render; canonical scene metadata must retain them until deterministic fixtures provide those resources.

## Capture determinism controls

Baseline runs are no longer ordinary client runs. Three controls were added after
consecutive `map-core` captures were measured differing in 62% of their pixels.

**Isolated write directory.** A run with `--renderer-baseline=` appends `-baseline` to the
application's compact name and resets that directory before any setting is read. Previously
a capture both inherited and overwrote the developer's real client state: `game_interface`
persists the console splitter position and restores it at the next login, and the minimap
cache and per-character UI state accumulate. A CI runner starts with none of it, so a local
capture and a CI capture could never have agreed.

**Window sized before login.** `game_interface.show()` derives the map panel geometry from
the window size at the instant the game starts. Online scenes previously resized only after
that had happened, so the panel came out a different size from run to run. Offline scenes
never had the problem because `beginClientScene()` resizes during `onRun`. Every capture now
logs the map panel rect it was taken at.

**Pinned shader time.** `u_Time` is wall-clock derived. Nine of the twenty-one shipped
shaders animate, and `g_shaders.setFixedTime` now pins the phase to 2.0 s for captures.
This is measurable: `outfit-masks` and `temporary-framebuffers` previously drifted by 520
and 449 pixels per run against a 656-pixel budget, purely from the Outline pulse. Both are
now **0 differing pixels**.

## map-core

Five consecutive captures against the live development world measured 0, 3, 752, 749 and 0
differing pixels once the controls above were in place, down from 62%. The residual is live
world content -- a walking NPC and a timed server broadcast -- and is why the scene needs the
server-authored fixture platform rather than the live world. It is not yet pointed at that
platform, so it is still diagnostic, not canonical.

Two contaminants were removed outright: the FPS/ping HUD, which `client_topmenu` draws
*inside* the map panel so its per-frame text lands on the MAP pool the scene exists to
exercise, and the enter-game window, which the driver hides before `loginWorld` but which
the normal startup flow re-shows because `EnterGame.show()` only guards on
`g_game.isOnline()`.

## lighting-overlap

Implemented and repeatable: two consecutive captures differ by **15 of 656,880 pixels
(0.0023%)**.

The two earlier attempts recorded in the handoff failed for a reason no client-side change
could have fixed. The baseline character `GOD` belongs to a group carrying `hasfulllight`,
so the server reports world light 255/215, and `LightView` sets `m_isDark = intensity < 250`
-- the entire LIGHT pool is skipped. The scene therefore logs in as a **group-1 character on
the same account** and stands on the server-authored **underground** platform, where
`MapView::updateLight` substitutes `Light{0,215}` for the server's world light. That also
removes the day/night cycle, which cannot be frozen at all: this build has no Lua world-light
setter and seeds `lightHour` from the wall clock.

Three stock torches supply pure red (colour 180), green (67) and cyan (35) light at equal
brightness, overlapping pairwise and at the centre, so the per-channel `max()` in the light
bitmap is directly visible.

Two deviations are frozen as observed:

- **Ambient is the client default, not zero.** The driver requests a zero ambient floor, but
  `client_options` applies its own 25% default during game start and wins, so unlit ground
  settles at a mid grey rather than black. It is stable, so it is accepted; do not read the
  unlit tiles as a zero-ambient reference.
- **`day-night` is not exercised** and has been removed from the scene's declared features.
  The ambient axis here comes from the client, not from a server-driven world light.

The console splitter had to be pinned explicitly. Across consecutive runs of this scene the
map panel settled at three different heights (308, 370 and 461 px) and waiting longer did not
converge. Separately, the outfit-customisation window the server pushes at login not only
covered the map but had already altered the layout by the time it was hidden, so the game
interface is isolated early and repeatedly rather than only at the shutter.

## CI gating

Two scenes are captured and archived but deliberately **not** gated against a reference:
`outfit-masks` and `temporary-framebuffers`. `data/things/*` is gitignored, so a CI runner
has no game assets and both render empty previews there; gating them would freeze a blank
image as the accepted reference. The manifest records this in `ciGate`/`ciGateReason`.

Reference images are compared against a **digest-pinned** `ubuntu:24.04` container. llvmpipe
rasterization is the reference implementation for every checked-in PNG and the hosted runner
image is rebuilt roughly weekly, so bumping that digest must be treated as a deliberate
reference-refresh event, not a routine dependency update.

## Open questions

- XQuartz 2.8.6 requests a logout after installation so launchd can export `DISPLAY`. A same-session manual launch can still use `DISPLAY=:0`, but the documented post-logout flow remains the reproducible setup.
