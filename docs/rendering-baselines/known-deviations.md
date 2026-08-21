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

**Survey quirk 7 was inaccurate as written and has been corrected** in
`docs/metal-parity-survey.md`. The FOREGROUND framebuffer does not stretch.
`GraphicalApplication::resize` sizes the UI and that framebuffer at `viewport/scale`, but the
framebuffer is blitted 1:1 into a destination rect equal to its own size, inside a painter
whose resolution is the full physical viewport. A scale change is therefore capturable as a
genuine image difference rather than a rescale, which is what the `display-density` feature
should freeze.

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
