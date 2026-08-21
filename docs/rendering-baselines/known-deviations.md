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

The `particles-blends` fixture uses one fixed, single-burst particle for each composition mode used by live code: NORMAL, MULTIPLY, and the legacy ADD equation. ~~Two settled captures had no pixels beyond the default per-channel tolerance; the maximum observed channel delta was 1.~~ **Re-measured 2026-08-20 (Phase 2), and the two-capture figure was misleading: the scene is bimodal.** Six consecutive captures on one binary split into two modes — within a mode 0 differing pixels (max channel delta 1-2), between modes **540 of 656,880 (0.0822%) at max channel delta 252**, confined to a 26x26 region at x 797-822 / y 311-336, the centre of the ADD (LEGACY) card. The original pair happened to land in the same mode. See *`particles-blends` is bimodally nondeterministic, and its high mode exceeds its own gate* below. The ADD particle is intentionally smaller because its high-contrast center magnifies harmless one-channel raster rounding while still making the blend equation unmistakable.

The `outfit-masks` fixture freezes creature animation and captures mask recoloring, both addon layers, a mount, the creature-preview framebuffer, and the framebuffer-backed Outline shader. Outline retains its production `u_Time` brightness pulse, which before shader time was pinned made two captures differ in 520 pixels (0.0792%, below the 0.1% policy limit), confined to the outlined preview. With `g_shaders.setFixedTime` the scene now measures 0 differing pixels; see *Capture determinism controls* below.

The `temporary-framebuffers` fixture covers every surveyed call site: creature preview, the nested Outline/ThingType path, item blits with both flip directions, effect and missile widgets, and spell-preview object compositing. Its animated outline probe made the repeated XQuartz capture differ in 449 pixels (0.0684%) before shader time was pinned, confined to the expected shader pulse; it now measures 0. See *Capture determinism controls* below.

The native `composition-all` fixture exercises all six painter descriptors, including the three with no production caller. Its ADD cell consistently exposes a faint image of startup UI retained in the FOREGROUND target, even though the fixture submits REPLACE clears for the target area and each destination cell. This is frozen as observed OpenGL behavior, not accepted as desirable renderer semantics. Two captures had no pixels beyond tolerance (maximum channel delta 2).

The map-screenshot offsets are intended framing, despite their unusual spelling. The MAP framebuffer is three tiles larger than the visible dimension. `MapView::calcFramebufferSource` selects the visible region after one spare tile on logical left/top, leaving two on right/bottom. For a 32 px sprite, the left-origin x offset is therefore 32; bottom-origin `glReadPixels` must skip the two logical bottom tiles, so its y offset is 64. The existing `x / 3, y / 1.5` call receives a total three-tile trim (96 px) and produces exactly those offsets. The XQuartz fixture-server capture was correctly oriented and measured 480x352, exactly the 15x11 visible tiles. Preserve the output crop while moving the arithmetic into explicit top-left readback parameters. Repeated captures against the live development world were diagnostic only, because its animated effects and creatures move between runs. Both map scenes were since moved onto the server-authored fixture platform; see *map-core and map-screenshot on the fixture platform* below for the resulting repeatability figures.

The `graph-lines` fixture drives the real `UIGraph` action-lambda path with fixed 1 px, 3 px, and 6 px `GL_LINE_STRIP` geometry. Hover information is disabled so mouse position cannot change the result. Two XQuartz captures were pixel-identical (656,880 pixels, maximum channel delta 0).

The `atlas-resources` fixture loads sixteen unique 522x522 smooth textures, an atlas-eligible 1344x320 sheet, and an APNG frame through the production foreground atlas. Both XQuartz runs grew the linear filter group to three 2048x2048 layers. Releasing and reloading four textures left one reusable inactive size bucket while retaining 41 cached entries. Clearing the texture-manager cache also freezes the displayed APNG after its first upload. The two final captures were pixel-identical.

The first XQuartz-versus-llvmpipe comparison was run on 2026-08-20, against the reference set
as seeded at 09:07 that morning. Five of the seven scenes gated at that date agree across the two GL
stacks; the two that do not are characterised below. XQuartz performance numbers are still
never compared directly with llvmpipe or native GPU numbers.

| Scene | Differing px | Fraction | Max channel delta | Verdict |
|---|---|---|---|---|
| `ui-clipping-opacity` | 0 | 0.0000% | 1 | agree |
| `text-matrix` | 1 | 0.0002% | 150 | agree |
| `atlas-resources` | 158 | 0.024% | 78 | agree |
| `particles-blends` | 168 | 0.026% | 52 | agree |
| `composition-all` | 490 | 0.075% | 4 | agree |
| `graph-lines` | 9,967 | **1.52%** | 235 | **differ — line smoothing** |
| `startup-ui` | 449,332 | **68.4%** | 254 | **differ — superseded, see below** |

The `startup-ui` row is no longer reproducible and should not be re-measured against the
current reference. It predates the login-background pin on both sides and was compared against
a reference that has since been dropped and reseeded (`8b0b550`, `09eb5d9`), so the background
was rolled independently on each side and its 68.4% conflates the CI asset-missing dialog with
two different backgrounds. The other six rows still stand: those reference PNGs are
byte-identical to the ones seeded in `046991f`.

That clipping, opacity, text, atlas packing, particle blending and all six composition
descriptors agree to within a handful of pixels across two independent GL implementations is
a strong result: it means those scenes are testing the client's behaviour rather than a
driver's.

**`graph-lines` — a genuine cross-stack divergence.** llvmpipe antialiases wide lines;
XQuartz rasterizes them hard-edged. Same geometry, same widths, different interpretation of
`GL_LINE_SMOOTH` and `glLineWidth`. The difference spans the whole plot area, not an edge
case. Two consequences: line rendering must be compared same-environment only, and the Metal
port's line triangulation `[S 6.3, S 9.10]` inherits a wide tolerance envelope, because the
two GL stacks already disagree with each other by 1.5% on the same source geometry. There is
no single "correct" GL line rendering to match.

**`startup-ui` — structural, not a rendering difference.** `data/things/*` is gitignored, so
the CI client has no game assets and its capture carries an asset-missing dialog in front of
the login window. Locally the assets exist and the dialog does not appear. This is expected
and is documented next to the reference images; it is not evidence about either rasterizer.
The 68.4% above is not a clean measurement of it, though, for the reason noted under the table.

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

**Pinned display density (added 2026-08-21, Phase 4).** The UI is laid out at
`m_size / m_displayDensity` while a capture is the full pixel canvas, so a window whose
density is not 1 fits half as many logical units into the same PNG. On X11 and on the
llvmpipe runner the density already is 1 and this changes nothing; on a Retina Cocoa window
it is the backing scale, and without the pin every macOS capture differed from every
reference by widget layout rather than by anything a renderer did. `windowing` still varies
it deliberately, which is what its `4-scaled` step measures.

**Suppressed text carets (added 2026-08-21, Phase 4).** The login screen's email field owns
keyboard focus and its caret blinks on a wall-clock timer. Two runs of one binary start
closely enough to usually agree, which is why this survived Phase 0 unnoticed; two different
binaries do not, and it showed up as a reliable 15-pixel column at x=456 on `startup-ui`.
The suppression runs at **scene setup**, not at the shutter, and the distinction is the whole
fix: a screenshot reads the frame that has already been drawn, so suppressing at the shutter
only takes effect from the next frame. Moving it earlier took `windowing`'s grown capture
from 12,505 differing pixels to 0.

## map-core

Five consecutive captures against the live development world measured 0, 3, 752, 749 and 0
differing pixels once the controls above were in place, down from 62%. The residual is live
world content -- a walking NPC and a timed server broadcast -- and is why the scene needs the
server-authored fixture platform rather than the live world. It was moved onto that platform
in the same phase; see *map-core and map-screenshot on the fixture platform* below.

Two contaminants were removed outright: the FPS/ping HUD, which `client_topmenu` draws
*inside* the map panel so its per-frame text lands on the MAP pool the scene exists to
exercise, and the enter-game window, which the driver hides before `loginWorld` but which
the normal startup flow re-shows because `EnterGame.show()` only guards on
`g_game.isOnline()`.

## lighting-overlap

~~Implemented and repeatable: two consecutive captures differ by **15 of 656,880 pixels
(0.0023%)**.~~

**Re-measured 2026-08-20, and the single figure was misleading.** Three consecutive captures
against the fixture server at `f47f6e41` differ pairwise by **899, 891 and 218 of 656,880
pixels** (0.137%, 0.136%, 0.033%). The first capture of a session is the outlier and later ones
converge, so a two-capture measurement lands anywhere between 0.03% and 0.14% depending on which
pair it happens to sample. Both earlier figures -- 15 px here and 161 px in the handoff -- were
real measurements of favourable pairs, not a stable property of the scene.

The variance is **not in the lights**. The differing pixels form four small clusters, all in UI
chrome: the minimap widget on the right panel and three button borders. The map viewport, the
three coloured torches and their overlap are pixel-stable. The scene therefore still
demonstrates what it was built to demonstrate, but its residual is larger than the 0.001 default
tolerance and is dominated by a widget that has nothing to do with lighting.

This is recorded rather than fixed. `lighting-overlap` is an online scene, so it is not in
`ids --gated` and has no committed reference -- nothing fails today. Anyone gating it later must
first neutralise the minimap the way `stabilizeOnlineUi` already neutralises the FPS/ping HUD,
or crop the comparison to the map viewport.

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

## map-core and map-screenshot on the fixture platform

Both scenes now capture the server-authored surface platform rather than the live world.
`map-core` measures **3 differing pixels of 656,880 (0.0005%)** between consecutive runs;
`map-screenshot` measures **62 of 168,960 (0.037%)**.

The readback residual is one animated decoration. `Thing:setAnimate(false)` freezes a sprite
at whatever phase it currently holds, which differs per run, so freezing does not by itself
make an animated item deterministic -- it only stops it advancing. Accepted, since it is well
inside policy.

Two contaminants were removed. The hovered-tile **crosshair** is drawn into the MAP pool
wherever the pointer sits, so it reached the framebuffer readback as well as the window
capture; `suppressCaptureTooltip` does not reach it because it is a map texture, not a
widget. It alone accounted for a full 32x32 tile of drift. Separately, running the interface
isolation immediately before `doMapScreenshot` relayouts the widget tree and intermittently
left the client with no map widget to read back from, so the capture silently timed out; the
readback path now gets only the animation freeze, which is all that applies to it.

## shader-matrix

Every shipped fragment program over one identical textured cell, plus a no-shader control:
sixteen fragment cells and one control. **0 differing pixels** between consecutive runs -- only
possible because `u_Time` is now pinnable; nine of the shaders animate and, before the split,
thirteen animated cells could never have fit the 656-pixel budget.

**Updated 2026-08-20 (`cb6fe6a`):** ~~a row applying the six outfit shaders through their real
creature route~~ moved out to `shader-matrix-outfits`, so the fragment half no longer depends on
gitignored `data/things/*` and could be CI-gated -- it now has a checked-in reference. Both
halves share one grid (`SHADER_GRID`) and the fragment cells kept their exact coordinates, so
the split is verifiable against the pre-split captures; it measures 0 differing pixels in the
`y < 482` band against three of them. `shader-matrix-outfits` also measures **0 differing
pixels** over 656,880 across consecutive runs, and carries the only automated coverage of a
`useFramebuffer` shader (Outline) applied at an offscreen blit.

Two constraints shaped it. The cells must be **textured**: `Painter::drawCoords` binds the
extra multi-texture units only inside its textured branch and otherwise leaves the texcoord
attribute disabled, so solid-colour cells would not exercise Fog or Snow at all. The cell
image is large and fully opaque, which also keeps it out of atlas packing -- the
offset-sampling shaders (bloom, radial blur, zomg, pulse, heat, noise) would otherwise sample
whatever happened to be packed beside it, coupling the result to packing order.

Map shaders appear here as fragment programs only. Their real bind site is the MAP framebuffer
to screen blit, and `Client::canDraw(MAP)` is literally `g_game.isOnline()`, so a UIMap with no
connection produces no MAP-pool content. `shader-matrix-map` is the online scene that carries
that coverage; it is declared in the manifest and described below.

## Three determinism traps worth knowing before adding a scene

Each of these produced a large, confusing pixel difference and each has the same shape: a
capture that trusted a delay instead of verifying a state.

**A randomized login background.** `client_background` picks one of six backgrounds at random
on every startup, seeded from the wall clock. Any scene showing the login screen was therefore
one-in-six likely to match its own previous capture. `startup-ui` had never been compared
against a second local run -- only inspected -- so this went unnoticed until `windowing`'s
first frame differed by 68% for no reason its driver could explain. The background is now
pinned for capture runs; `startup-ui` measures 0 differing pixels.

**A teleport that does not always land.** Online scenes fired the `!fixture` talkaction at
game start and captured after a fixed delay. `Game::playerSaySpell` returns early while the
player is walk-exhausted, and the player may not be fully placed when the first one goes out,
so a swallowed talkaction produced a capture from wherever the character happened to be --
two consecutive `map-core` runs differing across 38% of the frame purely because the camera
was elsewhere. The driver now polls the player position against the fixture anchor and
re-sends periodically, failing loudly rather than capturing the wrong place.

**Settings that need a frame.** `setMinimumAmbientLight`, `setAnimate` and the console
splitter all take effect on the *following* frame. Applying any of them in the same tick as
the screenshot records the pre-change state: it left the light ambient grey in one run out of
two, left creatures on whatever animation phase they already held, and gave the first frame of
a multi-capture scene a map panel 153 px shorter than the thirteen after it. All three are now
applied ahead of the shutter, not inside it.

## windowing

Four captures plus a state file. The resize round-trip is exact -- grown to 1200x700 and
restored, the frame is byte-identical to the initial capture -- and the HUD-scale step differs
from the initial frame across 86% of the image, which is the measurement behind the quirk 7
correction below.

Two constraints are structural. The window can only be tested by **growing** it, because
`modules/startup/startup.lua` sets a desktop minimum size of exactly the capture size, so any
smaller request is clamped and never lands. And the fullscreen probe must run **last and take
no image**: toggling fullscreen recreates the window, and a framebuffer read back immediately
afterwards came out entirely black.

`focus` is a pure state bit with no consumers anywhere in the tree, and a headless runner has
no window manager, so `setFullscreen` is silently dropped there while the client still flips
its own state bit. Both are recorded in `windowing-state.txt` rather than asserted as pixels,
and the scene is marked `ciCapture: false` because CI can provide neither a window manager nor
a display larger than the capture size.

## shader-matrix-map

Fourteen captures: one per map shader plus a `Default` frame to diff against. A map shader
applies to the whole composed map, so only one can be shown per frame.

This is the only coverage of the route map shaders actually take -- bound at the MAP
framebuffer to screen blit through the pool's `onBeforeDraw` hook, which is also where the
four map uniforms are written. `shader-matrix` covers the same fragment programs but on image
widgets, which never reaches that bind site.

Every shader measurably changes the map, from 1,768 changed pixels for Snow, a sparse overlay,
to 68,505 for Fog, Bloom and Party. Fade is set to 0/0 so the switch is immediate, and
`drawViewportEdge` is applied alongside each shader as `game_shaders` does, because it changes
which tiles the map view renders.

## Corrections applied to the planning documents

Two documented assumptions were checked against the source, did not hold, and have since been
corrected in place (commit `a35ca65`). Recorded here with the evidence.

**`AUTO_STAT` is compiled out of every build this repository produces.** `ENABLE_STATS` is
defined nowhere in CMake and the release binary contains none of the stat description
literals. The implementation plan's Phase 0 item "existing `AUTO_STAT` counters suffice
initially" was therefore wrong for a release build and has been struck (item 6 of
`docs/metal-implementation-plan.md`). Enabling them is not a valid substitute either: each
`AUTO_STAT` allocates, builds a description string and takes a global mutex on hot paths
including every Lua call and every packet, so the instrumented build does not measure the
renderer either. The only release-available accessors are a **1 Hz integer** FPS counter,
`g_stats.getWidgetsInfo`, `g_atlas.getStats()` and `collectgarbage("count")`. The client
also sleeps to cap itself at 60 FPS by default, so an uninstrumented FPS figure measures the
cap rather than the renderer. A frame-time baseline needed a decision before it could be
built, and that decision has since been taken: performance measurement is deferred to Phase
3, where the legacy and RenderFrame paths can be compared in the same environment. **Measured
there 2026-08-21**, and the deferral's premise held - the figure that carried information was
whole-process CPU at a display-locked frame rate, not a frame-time average. Numbers in
`docs/metal-implementation-plan.md`, Phase 5's exit gate.

~~**Survey quirk 7 was inaccurate as written and has been corrected** in
`docs/metal-parity-survey.md`. The FOREGROUND framebuffer does not stretch.
`GraphicalApplication::resize` sizes the UI and that framebuffer at `viewport/scale`, but the
framebuffer is blitted 1:1 into a destination rect equal to its own size, inside a painter
whose resolution is the full physical viewport. A scale change is therefore capturable as a
genuine image difference rather than a rescale, which is what the `display-density` feature
should freeze.~~

**That correction was itself wrong, and is re-corrected 2026-08-21 (Phase 5).** It read
`FrameBuffer::prepare`, whose *default* dest is `Rect(0, 0, getSize())` and is genuinely 1:1,
and did not read the caller. `UIManager::render` passes an explicit dest of
`{0, 0, g_graphics.getViewportSize()}` - the full **physical** viewport - through the
`preDraw(type, f, dest, src, colorClear)` overload, so the whole framebuffer texture is mapped
onto the whole viewport and scaled by `m_displayDensity`, with `LINEAR` filtering. **It
stretches.** A scale change is therefore *both* things: fewer logical units fit, and what does
fit is resampled - so `display-density` freezes a combination rather than a pure layout
difference, which does not change what the scene is worth but does change what it means.

The consequence is larger than the quirk. On a window with a backing scale of 2 the client
composites its entire UI at 1x into a half-size target and bilinearly upscales it. Measured
against a density-1 capture of the same scene: high-frequency detail falls to roughly a third,
and an even/odd column asymmetry appears from nothing (0.95 to 0.73), which is the fingerprint
of a 2x upscale. It is shared framework code, not a backend behaviour, and the pinned density
recorded above is why no automated scene can see it. Written up as a follow-up in
`docs/phase-5-renderer-handoff.md`.

Also relevant to the `windowing` scene, and the reason it is marked `ciCapture: false`:
`focus` is **not observable in any captured image** -- `hasFocus()` has zero consumers
anywhere in the tree, so it is a pure state bit. And under the CI Xvfb there is no window
manager, so `setFullscreen`/`maximize` are silently dropped while the client still flips its
own state bits, making `isFullscreen()` a false-positive assertion headlessly. The Xvfb
screen is also exactly the capture size, so any windowing step that grows the window past
1020x644 would exceed the root window there.

## atlas-resources has a small bounded variance in CI

The scene loads an APNG frame, and which frame is displayed depends on timing. Consecutive CI
runs compared it at 0 and then at 158 differing pixels, confined to a 23x12 region -- the APNG
sprite itself. It sits well inside the 0.1% default tolerance and needs no per-scene override,
but a future failure there should be checked against this region before being treated as a
rendering regression.

**It shows up in the render-path comparison too, 2026-08-21.** The legacy-versus-frame sweep
measured this scene at 0 differing pixels in CI on run `32452811177` and at 158 on run
`32476769563`, which is the same APNG-frame timing, not a difference between the paths - locally
on XQuartz it is 0 on both. Worth stating because 158 appearing in a *path* comparison invites
exactly the wrong conclusion: the two captures are one binary in one run, so a real path
difference there would be deterministic, and this one is not.

## `particles-blends` is bimodally nondeterministic, and its high mode exceeds its own gate

The scene is not merely noisy, it is **bimodal on the same binary**. Six consecutive XQuartz
captures at `021112b` fell into two clusters: within a cluster **0 differing pixels** (max
channel delta 1-2), between clusters **540 of 656,880 (0.0822%) at max channel delta 252**. The
differing pixels are one 26x26 region at x 797-822 / y 311-336 — the centre of the ADD (LEGACY)
card, i.e. the `renderer-baseline-add-weird` emitter, not raster noise spread over the frame.

This matters because the scene is **gated**. It takes the manifest defaults with no override
(`channelTolerance` 2, `maxDifferentFraction` 0.001), and the committed llvmpipe reference was
seeded from whichever mode that run happened to produce. Compared against that reference with the
exact gate parameters, the six runs above split:

| Mode | vs committed reference | Fraction | Max channel delta | Gate |
|---|---|---|---|---|
| low (4 of 6 runs) | 168 px | 0.0256% | 50-52 | PASS |
| high (2 of 6 runs) | 698 px | **0.1063%** | 252 | **FAIL** |

`render-baseline-linux.yml` fails the job on a nonzero comparator exit, so **this scene can fail
CI spuriously with no change to the client**. An independent four-run measurement taken the same
day put the cross-mode difference at 946 px (0.1440%), so the size of the excursion varies between
sessions as well; both measurements land above the 0.001 limit against the reference.

What it is NOT, established 2026-08-20 so the next attempt does not start here:

- **Not a duplicated burst.** `ParticleEmitter::update` computes
  `nextBurst = floor((elapsed - delay) * burstRate) + 1` and emits only bursts in
  `[m_currentBurst, nextBurst)`. With `burst-rate: 1` that stays at 1 until a full second has
  passed, and the emitter's `duration: 0.02` finishes it long before - so exactly one particle
  is emitted, at any frame rate. A doubled particle was the attractive theory, because a second
  identical opaque particle is invisible under NORMAL and MULTIPLY but glaring under
  `(1-src, 1-src)`, which matches the symptom exactly. It is not what happens.
- **Not a random size.** `ParticleEmitter::update` scales each particle by
  `random_range(pRandomSizeMultiplier.x, pRandomSizeMultiplier.y)`, and `random_range` swaps its
  arguments when min > max - so a default of `(1, 0)` would have produced a uniformly random
  multiplier in [0,1]. The default is `PointF pRandomSizeMultiplier{ 1 }`, and `TPoint`'s
  single-argument constructor sets both components, giving `(1, 1)`. The draw is deterministic
  in size.
- The particle definitions are otherwise fixed in position, velocity, duration and colour
  (`renderer-baseline-particles.otps`), so the remaining candidates are in how the frame is
  composed or when the shutter falls, not in what the emitter produces.

Recorded rather than fixed, because the fix is a choice, not a correction. Three options, in
preference order: find and remove the source of the bimodality in the emitter (it is a
single-burst emitter, so a genuinely fixed frame should be reachable); or give the scene a
`maxDifferentFraction`/`toleranceReason` override wide enough for the high mode, the way `map-core`
carries one for its creature; or ungate it. Do not simply reseed the reference — that picks a mode
at random and leaves the other one failing.

The `particles-blends` row in the XQuartz-versus-llvmpipe table above (168 px, 0.026%, max delta 52)
was measured in the low mode, and is reproducible only in the low mode.

## `graph-lines` differs between the two render paths, by design

Added 2026-08-21 (Phase 3). This is a deviation between the **legacy and compiled render paths**,
which is a different axis from every other section here - same machine, same binary, same GL
driver, same frame.

`UIGraph` draws its series with `GL_LINE_STRIP`, `glLineWidth` and `GL_LINE_SMOOTH`. Metal has
neither wide nor smoothed lines, so `DrawPool::addLineStrip` triangulates the strip into quads at
record time and a compiled frame draws those instead. The two are meant to differ, and only at the
edges: same vertices, same widths, same colours.

Measured in both reference environments, one binary each, both paths:

```
XQuartz    graph-lines  different=7660 of 656880 (1.17%)  max_channel_delta=235
llvmpipe   graph-lines  different=8734 of 656880 (1.33%)  max_channel_delta=168   run 32452811177
```

Every other offline scene matches at **exactly 0 differing pixels**, so this is the sole exception
rather than the largest of several. `scenes.json` gives the scene a `renderPathTolerance` of 0.03,
separate from its reference tolerance, with the measurement and the reasoning recorded there.

The limit is well above 1.17% on purpose. This same scene already disagrees by 1.52% *between GL
stacks* (see the XQuartz-versus-llvmpipe section above) because llvmpipe antialiases wide lines
where XQuartz rasterises them hard - so the CI figure for the path comparison was expected to be
larger than the local one, and is: 1.33% against 1.17%. Both sit at well under half the limit. A
structural regression, such as a series not being drawn at all, moves the number well past 3%.

Run it with `tools/compare_render_paths.sh <client-binary>`.

## Metal versus OpenGL

Added 2026-08-21 (Phase 4). This is a different comparison from every other one on this page:
both sides consume the **same compiled `RenderFrame`**, so a difference is below the renderer
boundary in one backend rather than anywhere above it. `tools/compare_render_backends.sh` runs
it, and it forces the OpenGL side onto `--render-path=frame` for exactly that reason - left on
the legacy path it would fold two differences together.

It needs two binaries. The Cocoa window deliberately creates no OpenGL context and the XQuartz
window creates no Metal layer, so the two backends cannot coexist in one process.

Measured on an Apple M3 Pro, XQuartz 2.8.6 against Metal, out of 656,880 pixels:

| Scene | Differing pixels | Cause |
|---|---:|---|
| `startup-ui` | 0 | - |
| `ui-clipping-opacity` | 0 | - |
| `text-matrix` | 0 | - |
| `composition-all` | 0 | all six blend modes agree exactly |
| `graph-lines` | 0 | both backends draw the same triangulated quads |
| `atlas-resources` | 0 | - |
| `particles-blends` | 22-540 | the scene's own bimodality, documented above |
| `outfit-masks` | 579 | one Outline probe |
| `temporary-framebuffers` | 521 | the same Outline probe |
| `shader-matrix` | not compared | every cell is a module fragment program |
| `shader-matrix-outfits` | not compared | all six cells are outfit programs |

**Every difference in that table is a module fragment program**, with the single exception of
`particles-blends`, which differs from itself on one binary by the same amount and for the reason
recorded above. `ShaderManager` does not create GLSL programs without an OpenGL context, so none
of the 27 registered module programs is available on the Metal backend and the geometry draws
unshaded. The `.frag` to SPIR-V to MSL
toolchain is Phase 6; the manifest records the two uncomparable scenes as
`renderBackendComparable: false` and the two Outline probes as a measured
`renderBackendTolerance`, and all four entries say to remove them when Phase 6 lands.

The Outline diffs are worth looking at rather than reading: each is literally the outline of one
creature and nothing else, on an otherwise black diff image.

`windowing` is outside the sweep (`ciCapture: false`) and was compared by hand: all four captures
match at 0 differing pixels, including the 840,000-pixel grown one and the one at HUD scale 2.

### The online scenes

Outside the sweep (they need the fixture server) and compared by hand against `crystalserver`
`f47f6e41`, three or four captures per backend. A live server cannot be frozen, so each scene is
measured against **its own noise floor** rather than against zero:

| Scene | within OpenGL | within Metal | across backends |
|---|---|---|---|
| `map-core` (656,880 px) | 175 px | 190 px | 34 / 166 / 197 / 305 px |
| `map-screenshot` (168,960 px) | 0 px | 18 / 221 / 228 px | 316 / 327 px |
| `lighting-overlap` (656,880 px) | 713 px | 851 px | 60 / 198 / 773 / 911 px |
| `shader-matrix-map` | - | - | not comparable: all fourteen cells are map shaders |

The two backends differ by no more than each differs from itself. `map-screenshot`'s residual is one
creature a tile away plus two pixels of an animated floor sparkle - the 62-pixel animated-decoration
residual Phase 0 recorded, now that the animation advances on both paths.

**Online captures need spacing between logins.** Twelve seconds is enough for the server to drop the
previous session. Without it the `!fixture` talkaction is swallowed and the run either never reaches the
anchor or captures from two tiles away. One capture in this set did the latter and differed from its
siblings across 90% of the frame - which looks like a renderer defect and is not: searching over
whole-tile offsets showed it to be another capture shifted by exactly (+64, -64), at which alignment
0.6% of pixels differ. Measure the shift before believing the percentage.

Two things this comparison is **not**. It is not a reference gate - the checked-in llvmpipe PNGs
are same-environment CI references, not a cross-stack oracle for Metal, and a macOS reference set
still has to be captured and frozen. And it is not a performance comparison: XQuartz advertises no
swap-control extension and is display-locked at ~121 fps, while `CAMetalLayer.displaySyncEnabled`
genuinely comes off and the same scene measures 320-400 fps median on Metal. One of those numbers
is a ceiling and the other is a cost.

## The CPU atlas under Metal, and the smooth-padding clamp

Added 2026-08-21 (Phase 5). Phase 4 switched the CPU texture atlases **off** under Metal for two
reasons, and recorded that `atlas-resources` matching cross-backend at 0 px therefore said nothing
about Metal's clamp behaviour, because it was comparing atlas-backed geometry on the OpenGL side
against standalone textures on the Metal side. Both reasons are gone:

- A region was keyed on its occupant's **OpenGL name**, which is zero for every texture a non-GL
  backend creates, so the whole client would have collided on one key. Regions are keyed on
  `Texture::getUniqueId()` now.
- `TextureAtlas::flush` was unguarded OpenGL from top to bottom. `compileMaintenance` is the
  described form of the same work and the frame path runs that; `flush()` survives for the legacy
  path only.

A layer also had to stop being sampled through its framebuffer texture's unique id. That works on
OpenGL only because an FBO's colour attachment *is* an ordinary GL texture; a layer is a render
target, and it is named by a target handle now.

**The comparison is therefore meaningful for the first time, and it passes.** `atlas-resources`
exercises atlas growth and `SMOOTH_PADDING` through the production foreground atlas. Both backends
report identical atlas state - `fg=size=2048x2048 cached=41`, nearest group one layer, **linear
group grown to three layers**, one inactive size bucket after the release-and-reload - and the
captures compare at **0 differing pixels** (max channel delta 1, inside the comparator's tolerance
of 2), repeatably across the two sweeps that measured it.

Read that against *`atlas-resources` has a small bounded variance in CI* above: this scene is known
to vary by up to 158 px from APNG-frame timing in the llvmpipe job. The cross-backend figure here
is not immune to that by construction - it is 0 because both captures landed on the same frame -
so a future non-zero should be checked against that region before being read as a clamp difference.

The padding draw deliberately samples outside the source texture, with a source rect of
`{-pad, -pad, w+2p, h+2p}`, and relies on clamp-to-edge to smear the border outwards. It survives
the translation because `GL_CLAMP_TO_EDGE` and `MTLSamplerAddressModeClampToEdge` are each the
**non-repeat default** on their backend, and the sampler follows the source texture's own
`hasRepeat()` on both. A texture with repeat set would wrap on both backends alike, so that is not
a Metal-specific hazard either. The risk register's fallback - upload CPU-padded textures instead -
is not needed.

One thing this does **not** cover: the `MTLTextureType2DArray` sprite array the architecture note
sketches for Metal. That is a different structure, it remains unbuilt, and nothing needs it.

## Online scenes, Metal versus OpenGL

Added 2026-08-21 (Phase 5), driven by `tools/compare_online_backends.sh`. The four online scenes
are the only coverage of the MAP pool, the light overlay, the map-composition material and the map
readback, and they were run by hand in Phases 3 and 4 - which is how both phases found a defect
after their handoff had been drafted. Three of them have a harness now: `map-core`,
`map-screenshot` and `lighting-overlap`. The fourth, `shader-matrix-map`, stays outside it because
it is not comparable at all until Phase 6 - every one of its fourteen cells is a map shader - so it
is captured by hand as a smoke test of the route rather than compared.

A live server cannot be frozen, so each scene is compared against **its own noise floor** rather
than against zero: three runs per backend, the within-backend spread reported beside the
cross-backend one. A cross-backend difference no larger than a backend's own variance is agreement.

What made this run worth doing at all is that turning the atlases on changed how the **map** is
drawn under Metal - map sprites are atlas-backed there now, where before they were standalone -
and no offline scene exercises the MAP pool.

Measured against `crystalserver` `f47f6e41`, on an Apple M3 Pro. Two independent sweeps, three
runs per backend per scene, kept separately rather than averaged - the spread *between* the sweeps
is itself the most honest statement of how noisy a live server is:

| Scene | sweep | within OpenGL | within Metal | across backends |
|---|---|---:|---:|---|
| `map-core` (656,880 px) | 1 | 0 / 1,936 px | 78 / 157 px | 63 / 172 / 1,920 px |
| | 2 | 2,651 px | 4 / 23 px | **0** / 713 / 2,649 px |
| `map-screenshot` (168,960 px) | 1 | 0 px | 24 px | 0 / 24 / 24 px |
| | 2 | 0 / 24 px | 24 px | **0** / **0** / 24 px |
| `lighting-overlap` (656,880 px) | 1 | 145 / 337 px | 13 / 191 px | 393 / 403 / 547 px |
| | 2 | 138 / 153 px | **0** / **0** px | 182 / 44 / 29 px |

Every cross-backend figure sits at or below the larger of the two floors for that scene, and five
pairs matched exactly - including `map-core` at **0 differing pixels of 656,880** in sweep 2, which
is the whole map scene agreeing across two graphics APIs. Note also that Metal was perfectly stable
across all three `lighting-overlap` runs in sweep 2 while OpenGL was not; neither backend is
consistently the quieter one.

But the totals are the less informative half, because **where** the pixels are settles it:

- On `lighting-overlap`, the settled runs differ only in `x[850..1005]` - the right-hand UI panel,
  which is live battle-list and minimap content. **Zero pixels inside the map panel** (`x[177..843]`),
  and each backend differs from *itself* in the same band by a comparable amount (206 px within
  OpenGL, 192 px within Metal, over `x[876..1005]`). The light overlay and the map agree exactly.
- On `map-core`, `GL3 vs Metal3` likewise has **zero** differing pixels inside the map panel. The 19
  map-panel pixels in the run-2 pair appear identically in Metal's own run2-vs-run3 comparison, so
  they are Metal's frame-to-frame variance rather than a systematic difference.

That residual Metal-side variance is the animated floor decoration Phase 0 first recorded as a
"62-pixel animated-decoration residual". `Thing:setAnimate(false)` stops a sprite advancing but
leaves it on whatever phase it already held. Under OpenGL two runs happen to land on the same
phase; under Metal they do not, because Phase 4 had to fix `AnimatedTexture::update` gating its
frame advance on the OpenGL name. Same root cause as the 24-pixel `map-screenshot` residual.

**Run 1 of each scene is an outlier and should be read as one.** It carries the largest spread in
both `map-core` (1,936 px within OpenGL) and `lighting-overlap`, because the world state has not
settled - creatures are still moving into position. The figures above keep it rather than dropping
it, since a floor computed only from settled runs would understate the noise.

## `windowing`'s grown capture is bimodal, on both backends

Added 2026-08-21 (Phase 5). Phase 4 recorded all four `windowing` captures matching OpenGL against
Metal at 0 differing pixels, including the grown one at 840,000 pixels. That measurement was taken
once and it got lucky.

Re-measured across two runs per backend:

| Comparison | Differing pixels | Fraction |
|---|---:|---:|
| `windowing-1-initial`, `-3-restored`, `-4-scaled` — within OpenGL, and across backends | 0 | 0% |
| `windowing-2-grown` — OpenGL run A vs run B | 12,505 | 1.49% |
| `windowing-2-grown` — Metal run A vs run B | 157,428 | 18.7% |
| `windowing-2-grown` — OpenGL vs Metal, same mode | **0** | 0% |
| `windowing-2-grown` — OpenGL vs Metal, different modes | 12,505 / 166,582 | 1.5% / 19.8% |

So the grown capture is **bimodal on both backends**, and when the two land in the same mode they
agree exactly. It is a scene-determinism problem, not a renderer difference: nothing about it is
specific to Metal, to the atlas, or to the render path.

The 12,505 figure is not new either - it is the number Phase 4 recorded as the symptom of "a
screenshot reads the frame that has already been drawn", which moving the capture suppression into
scene setup was supposed to fix. It reduced how often this fires without eliminating it. The grown
capture is the one shutter that fires immediately after a resize, so it is the one that can still
read a frame from before the new size settled.

**Do not compare `windowing-2-grown` across a single run per side.** Capture it at least twice per
backend and compare same-mode figures, exactly as `particles-blends` requires. The other three
captures are stable and remain the real evidence that render-target recreation and
`FrameAssembler::invalidateRetainedTargets` work - `-4-scaled` at HUD scale 2 and `-2-grown` at a
different resolution entirely are the only things in the whole suite that exercise them.

## `composition-all` sits on the tolerance boundary

Added 2026-08-21 (Phase 5), found by capturing the same scene on two different hosted macOS
runners and diffing.

The two captures differ by **0 pixels** — but at a maximum channel delta of **2**, which is exactly
`defaultTolerance.channelTolerance`. That is not a comfortable pass; it is a tie. Sub-threshold
jitter of that size is enough to change the verdict against a *third* image: the same scene compared
to its checked-in llvmpipe reference reads **0 px** from one run and **15 px** from the other.

This matters for anyone about to gate the scene somewhere new. It is stable against itself and
marginal against a reference, which is the exact shape that yields a gate failing every few weeks
with no cause anyone can find. The existing llvmpipe gate has not tripped on it because both sides
of that comparison are produced in the same environment, and the earlier note above already records
"maximum channel delta 2" between two XQuartz captures — the same tie, seen once and read as a pass.

Either widen this scene's `channelTolerance` to 4 with a recorded reason, or accept that its verdict
carries roughly a 15-pixel margin of noise and set `maxDifferentFraction` accordingly. Do not gate it
at the default and assume the 0 px is a property of the scene.

## CI gating

Three scenes are captured and archived but deliberately **not** gated against a reference:
`outfit-masks`, `temporary-framebuffers` and `shader-matrix-outfits`. `data/things/*` is
gitignored, so a CI runner has no game assets and their creature, item and outfit previews
render empty there; gating them would freeze a blank image as the accepted reference. The
manifest records this in `ciGate`/`ciGateReason`, and `tools/renderer_scenes.py ids --gated`
is the authoritative list.

**Updated 2026-08-20:** `shader-matrix` used to be the fourth. It was the near miss - sixteen
fragment cells that would gate cleanly and one outfit row that would not - so the outfit row
was split out into `shader-matrix-outfits` and the fragment half is now gated. One cell of it,
`forge_result_silhouette`, still renders differently by environment: `game_exaltationforge`
registers that shader in its `onLoad`, which does not run without game assets, so with assets
the cell draws a black silhouette and without them it draws the image unshaded. Both are
deterministic, so the gate holds against the llvmpipe reference - but a local XQuartz capture
of this scene will always differ from that reference in that one cell.

Reference images are compared against a **digest-pinned** `ubuntu:24.04` container. llvmpipe
rasterization is the reference implementation for every checked-in PNG and the hosted runner
image is rebuilt roughly weekly, so bumping that digest must be treated as a deliberate
reference-refresh event, not a routine dependency update.

## Open questions

- XQuartz 2.8.6 requests a logout after installation so launchd can export `DISPLAY`. A same-session manual launch can still use `DISPLAY=:0`, but the documented post-logout flow remains the reproducible setup.
