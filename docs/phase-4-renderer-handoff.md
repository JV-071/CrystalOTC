# Phase 4 renderer handoff

**Checkpoint:** `9ce989c` on `main` — the phase's last code commit; the two after it are this
documentation. Pushed to `origin`, the fork `aacruzgon/CrystalOTC`.

**Date:** 2026-08-21

**Scope:** Phase 4 — the Metal foundation

## Current state

macOS renders the client with Metal. A pool's published object list compiles to a
`PoolProgram`, five programs assemble into a `RenderFrame`, and `MetalBackend` executes it on
`MTLDevice` — in a process that creates no OpenGL context at all, from a bundle that links no X11
(asserted by CI on a runner with no XQuartz), and with no GL type below the boundary except inside
the backend that is OpenGL.

It is **selected by capability, not by preference**. A window that never created a GL context has
a Metal layer to offer and nothing else, so it resolves to the frame path and the Metal backend;
the XQuartz build resolves to OpenGL exactly as before. `--render-backend=` and
`CRYSTALOTC_RENDER_BACKEND` override, which is what lets one scene be captured down both.

At this checkpoint:

- All four CI jobs green on `3fd3b0f` — `Build - macOS (Cocoa)` (run `32494822009`),
  `Build - Windows` (`32494822190`), `Renderer baseline - Linux llvmpipe` (`32494822069`),
  `Tests - Lua` (`32494822051`).
- The macOS job now asserts which renderer came up, not only that graphics init was reached, and
  the assertion passes on a hosted runner: `[render] render path: frame (backend 'metal')` on an
  `Apple Paravirtual device`. That is worth more than it looks — the backend creates its device,
  its queue and its MSL library on virtualised hardware with no window server, and survives the
  45-second smoke launch without ever obtaining a drawable.
- `ctest` 58/58 on macOS and Linux, 59/59 on Windows, up from 57/58.
- The eight reference-gated scenes are unmoved: seven at **0 differing pixels** against their
  checked-in llvmpipe references, `particles-blends` at 626 px inside its own bimodality. The
  legacy-versus-frame sweep is unmoved too — ten scenes at 0 px, `graph-lines` at 8,734 px, the
  exact figures Phase 3 recorded. The OpenGL path is provably untouched by any of this.
- No new compiler warnings. The macOS job reports the same eleven as run `32476769555`, which
  predates this phase — identical set, identical counts — so the Metal sources, ARC and all,
  compile clean.
- The Cocoa client draws the login UI and live gameplay — map tiles, creatures, name tags, the
  minimap, the inventory and the chat panel — against the pinned fixture server.
- Nine of eleven offline baseline scenes compare against the OpenGL backend consuming the
  **same compiled frames**; six match at exactly 0 differing pixels. The two that do not compare
  are the two made of module fragment programs, which Phase 6 owns.
- Locally, the legacy-versus-frame sweep on XQuartz still reports ten scenes at 0 px and
  `graph-lines` at 7,660 — again the figures Phase 3 recorded, in the other environment.

## Phase 4 checklist

Against the implementation plan's Phase 4 tasks:

- [x] **MetalContext** — device, queue, three frames in flight with semaphore throttling,
      per-frame command buffers, drawable acquisition that survives a nil drawable, and
      completion-handler frame retirement.
- [x] **Resources** — an RGBA8 texture table, the sampler states, region updates for
      `TextureUpdate`, and staged uploads where a texture can still be in flight.
- [x] **Vertex arenas** in per-frame `MTLBuffer` rings, two non-interleaved float2 attributes
      described by an `MTLVertexDescriptor`.
- [x] **Pipeline cache** on the surveyed key; all six blend modes; `alphaWrite` as a write mask;
      blend-disabled states.
- [x] **Built-in materials** in hand-written MSL: Textured, SolidColor, ReplaceColor. No line
      pipeline, because nothing can emit a line material.
- [x] **Scissor, viewport, labels** on every buffer, encoder, texture and pipeline.
- [x] **Backbuffer-only first** — read as *offscreen* backbuffer, which turned out to be the
      better shape. See *Decisions that were not free*.
- [x] **Readback**, which the plan places in Phase 5. Brought forward because it is the
      instrument every other claim on this page is measured with.

Two further items the plan does not list, because it did not know they were needed:

- **Three shared-code fixes** for code that asks whether something reached the GPU by reading an
  OpenGL name. See *Bugs found, and how*.
- **A cross-backend comparison harness**, `tools/compare_render_backends.sh`, without which none
  of the numbers below could be stated at all.

Against the exit gate — *"login + gameplay visually correct apart from features owned by P5/P6"*:

| Scene | Metal vs OpenGL, same compiled frame |
|---|---|
| `startup-ui` | **0 px** |
| `ui-clipping-opacity` | **0 px** |
| `text-matrix` | **0 px** |
| `composition-all` | **0 px** (all six blend modes) |
| `graph-lines` | **0 px** |
| `atlas-resources` | **0 px** |
| `particles-blends` | 22–540 px, the scene's own documented bimodality |
| `outfit-masks` | 579 px — one Outline probe, a module shader |
| `temporary-framebuffers` | 521 px — the same Outline probe |
| `shader-matrix` | not comparable: entirely module fragment programs |
| `shader-matrix-outfits` | not comparable: the six outfit programs |

All of 656,880 pixels. **Every difference in that table is a module fragment program** — except
`particles-blends`, which differs from itself by the same amount on one binary and has its own
entry in `known-deviations.md`. Module programs are the Phase 6 toolchain's deliverable, and each
difference is confined to the pixels that program would have drawn: the Outline diffs are
literally the outline and nothing else, on an otherwise black diff image.

`windowing` is outside the sweep (`ciCapture: false`) and was compared by hand. All four of its
captures match at **0 differing pixels**, including the one at 840,000 pixels rather than 656,880
and the one at HUD scale 2 — which between them are the only thing that exercises render-target
recreation and `FrameAssembler::invalidateRetainedTargets`.
**Qualified 2026-08-21 (Phase 5):** three of the four are stable and that result stands. The fourth,
`windowing-2-grown`, is **bimodal on both backends** — OpenGL differs from itself by 12,505 px on it
and Metal from itself by 157,428 px — so measuring it once per side, as this did, has a good chance
of catching both sides in the same mode and reading 0. Same-mode captures do still compare at 0 px
across the two backends, so the conclusion was right; the evidence was thinner than it looked. See
`known-deviations.md`. **Further qualified 2026-08-25:** the HUD-scale-2 capture's own pixels changed
with the Retina fix (`6b03c256`) — it is the capture that fix was measured on. Both backends take the
same shared-framework change, so the cross-backend result should hold, but it has not been
re-measured: the available OpenGL binary is too far behind to compare.

The four **online** scenes are outside it too — they need the fixture server — and they were run by
hand against the pinned `crystalserver` `f47f6e41`. They are the only coverage of the MAP pool, the
light overlay, the map-composition material and the map readback, and Phase 3's last defect was found
exactly there, after its handoff had been drafted.

A live server cannot be frozen, so each scene is compared against **its own noise floor** rather than
against zero — the criterion Phase 3 used:

| Scene | within OpenGL | within Metal | across backends |
|---|---|---|---|
| `map-core` (656,880 px) | 175 px | 190 px | 34 / 166 / 197 / 305 px |
| `map-screenshot` (168,960 px) | 0 px | 18 / 221 / 228 px | 316 / 327 px |
| `lighting-overlap` (656,880 px) | 713 px | 851 px | 60 / 198 / 773 / 911 px |

In every case the two backends differ by no more than each differs from itself, and two pairs — 34 px on
`map-core`, 60 px on `lighting-overlap` — are close to identical. `map-screenshot`'s cross-backend
difference is one creature standing a tile away plus two pixels of an animated floor sparkle: the
62-pixel animated-decoration residual Phase 0 recorded, now that the animation actually advances.

`lighting-overlap` is the most valuable of the three, because it is the only exercise the light overlay
gets and it passes through the whole of it — the CPU light bitmap arriving as a `TextureUpdate`, staged
into a buffer and blitted into a private texture inside the frame's own command buffer, then drawn as
one multiply-blended quad. Three coloured torches with overlapping gradients render correctly.

`shader-matrix-map` is the fourth, and it is **not comparable**, for the same reason its two offline
siblings are not: thirteen of its fourteen cells are map shaders and the fourteenth is an unshaded
control, and every one reports "shader unavailable in this environment" on the Metal build because
`ShaderManager` registers no GLSL without an OpenGL context. It was run anyway as a smoke test of the
map-composition route and produced all fourteen captures without incident.

**Superseded 2026-08-21 (Phase 6) and again 2026-08-25:** module programs register without a GL
context and resolve on Metal, so the scene compares; and since `0ec21a80` all fourteen captures sit
at or below its unshaded control frame. The "not comparable" verdict above is Phase 4's, and true
only of Phase 4.

**One capture of four was discarded, with evidence rather than by judgement.** An early `map-screenshot`
run differed from every other by 90% of the frame at a small mean delta — alarming, and not a rendering
difference: searching over whole-tile offsets showed it is another capture shifted by exactly (+64, −64),
two tiles right and two tiles up, at which alignment 0.6% of pixels differ. The camera was two tiles off
the anchor. It came from a batch of unspaced runs whose two siblings failed to reach the fixture at all;
spacing the logins twelve seconds apart, so the server drops the previous session before the next one,
made every later run land.

## Decisions that were not free

**The backend presents, and the window stands down.** Phase 1 raised this and Phases 2 and 3 left
it open. A drawable may only be presented by the command buffer that rendered into it, and
acquiring one as late as possible is the entire reason acquisition is separate from encoding — so
the backend that acquires must present. `PlatformWindow::setPresentationOwned` is the claim, and
what remains in `CocoaWindow::swapBuffers` is the Phase 1 acquire-clear-present, which still runs
before any backend exists and whenever one declines a frame. A navy screen is a diagnosable state.

**It renders into its own offscreen backbuffer and blits that into the drawable.** The plan says
"backbuffer-only rendering first"; this is that, with one indirection that pays for itself twice.
A presented drawable can never be read, and every renderer baseline is a screenshot taken between
frames — so without the offscreen copy there is nothing for `readPixels` to read, and no way to
measure anything on this page. It also means a frame that finds no drawable loses its
presentation rather than its work. The cost is one full-screen GPU copy per frame.

**The texture matrix is derived, not resolved.** GL stores a framebuffer's texture bottom-up and
compensates when sampling it, through the `upsideDown` half of `TextureManager`'s matrix registry.
Metal has no such asymmetry: a render target's row 0 is its top row, exactly like an uploaded
image's. So the backend computes `1/w, 1/h` from the resolved texture's size and never resolves
`packet.textureMatrixId`. That is not a shortcut — resolving GL's id would apply GL's flip and
turn every sampled target upside down. **Consequence found 2026-08-21 (Phase 6) and closed
2026-08-25:** both backends fetch the correct texel, but the coordinate *value* differs —
`v_TexCoord.y` is `1 - t` on GL and `t` here — which six of the thirteen map shaders read as a
position. Absorbed in the shader translation layer (`u_Tex0FlipY`, per draw, from
`MetalResources::Resolved::isRenderTarget`) rather than by inverting this decision, which stands.
Applying the flip unconditionally takes `shader-matrix` from 17 px to 40,688, an exact mirror of the
defect, so the per-draw gate is load-bearing.

**Two pixel formats, on purpose.** Sampled textures are RGBA8, which is what `Image` already
holds, so an upload is a copy and never a swizzle. Render targets are BGRA8, matching the layer's
drawable, so one pipeline set serves every pass including the one that reaches the screen and the
present is a straight copy. The readback swaps two channels on the way out, where the GL path
flips rows instead.

**Shared storage for sampled textures, private for targets.** The build is Apple Silicon only by
Decision 5, so CPU and GPU address the same memory and an upload is a memcpy; a private copy would
buy a staging blit and nothing else. Targets are private because nothing writes them from the CPU.
A `TextureUpdate` is still staged and blitted rather than written directly, because the texture it
overwrites may be sampled by a frame that has not finished and a CPU write has nothing ordering it
against that read.

**MSL is compiled at runtime from a string.** Four functions, single-digit milliseconds at
startup. Standing up the `.frag` → glslang → SPIRV-Cross → `.metallib` build step for three
built-ins would be building the Phase 6 toolchain early instead of building the renderer.

**The CPU atlases are off under Metal**, joining the rule Vulkan already follows and for a harder
reason: `TextureAtlas` keys its regions on a texture's OpenGL name, which is zero for every
texture here, so the whole client would collide on key 0. `TextureAtlas::flush` is also unguarded
OpenGL from top to bottom. Modelling atlas layers as passes is Phase 5; until then the compiler
already emits standalone textures when no atlas claims one.
**Reversed 2026-08-21 (Phase 5, `83e81ac`), which is what this decision expected:** both reasons
were removable rather than permanent. Regions are keyed on the unique id and maintenance compiles
to passes, so the atlases run under Metal and `atlas-resources` compares across the backends at 0
differing pixels with atlas-backed geometry on both sides. Vulkan keeps the exclusion, for its own
unrelated reason.

## Traps worth not rediscovering

**`PlatformWindow::hasGLContext()` defaults to `true`.** Only `WIN32Window` and `CocoaWindow`
override it; `X11Window` inherits the default. So in a unit-test process built for XQuartz the
answer is yes, there is a GL context, while GLEW's function pointers are all null. A test that
constructed a `ShaderProgram` to check the no-GL path segfaulted on a jump to address 0 for
exactly this reason, and had to be removed rather than fixed.

**A screenshot reads the frame that has already been drawn.** Anything suppressed immediately
before the shutter — a blinking caret, a tooltip — only takes effect from the *next* frame. This
is invisible within one binary, where two runs are closely enough timed to agree, and reliable
across two, where they are not: it was 15 pixels on `startup-ui` and 12,505 on `windowing`'s grown
capture until the suppression moved to scene setup.

**The UI is laid out at `m_size / m_displayDensity`, and the capture is the full pixel canvas.** A
Retina Cocoa window therefore fits half as many logical units into the same PNG as an X11 one, and
every macOS capture differs from every reference by widget layout rather than by anything a
renderer did. Pinning the density to 1 for captures is a no-op everywhere it already is 1.
**Updated 2026-08-25 (`07b9597d`):** device pixel ratio and HUD scale are separate inputs now and `getDisplayDensity()`
returns their product, so pinning the density means calling **both** `g_app.setDevicePixelRatio(1)`
and `g_app.setHUDScale(1)`. `setHUDScale(1)` alone leaves a scaled window at its backing ratio and
silently unpins every macOS capture.

**ARC and non-ARC cannot share a translation unit,** which a unity build will happily try to
arrange. The Metal sources are compiled with `-fobjc-arc` and `cocoawindow.mm` is not, so they are
excluded from unity inclusion and from the precompiled header — a PCH whose ARC state differs from
the TU using it is a hard error, not a warning.

**Metal validates a scissor rect; GL forgave one.** The compiler already clamps to the pass
viewport, but an *enabled empty* scissor — the compiler's way of saying "this clip rect misses its
target, so draw nothing" — is a zero-sized rect Metal rejects outright. It has no pixels either
way, so the draw is dropped before it is encoded.

**`gh run list --commit` fails silently, and there is more than one way in.** Phase 2 recorded it
as "needs the full SHA" and Phase 3 rediscovered it within the hour by passing an eight-character
prefix. Phase 4 found a third route: writing out a full-length SHA from memory rather than
resolving it. `git rev-parse` costs nothing and is the only thing that makes the argument true.

What makes this worth a third entry is the failure mode rather than the cause. The command returns
an empty list for a commit that does not exist, which is indistinguishable from a commit whose jobs
have not started — so a monitor built on it polls forever, emits nothing, and its silence reads
exactly like "still running". Two such monitors ran here against invented SHAs and would have been
reported as green-by-timeout if nobody had asked what they were watching. Any watch on this command
should resolve the SHA first and treat "no runs at all" as a state to report, not to wait through.

**Frame rate carries information on this vehicle, and did not on the last one.** XQuartz
advertises no swap-control extension, so Phase 3 measured both paths at an identical display-locked
~121 fps. `CAMetalLayer.displaySyncEnabled` genuinely comes off: the same scene measures 320–400
fps median on Metal. The two figures are not comparable to each other and never will be — one is a
ceiling — but the Metal one is a cost.

## Bugs found, and how

Four defects, three of them pre-existing and latent for as long as the code has existed. None was
found by reading it; each surfaced the moment something other than OpenGL tried to draw.

**Every animation froze on frame 0.** `AnimatedTexture::update` gates the frame advance on
`isEmpty()`, which asks whether the OpenGL name is zero. The gate exists so an animation does not
run ahead of a texture nothing can draw; on a backend that creates no OpenGL textures the answer
is "not yet" forever.

**And would have frozen again one level up.** Phase 3 stopped a compiled frame re-compositing a
retained target while the animation behind it advanced, by folding the native texture id into the
pool's content hash. That signal is the same OpenGL name — constant here — so the defect returns by
a different route. It also never covered `Texture::updatePixels` overwriting pixels in place, which
Phase 3 recorded as a follow-up waiting for a streaming texture to reach a retained target.
`Texture::getContentRevision` is the form of the question that has an answer on both paths.

**No shader could be set at all.** `Painter` skipped building its four built-in programs without a
GL context, so `getReplaceColorShader()` was null — and `DrawPool::setShaderProgram` guards on "is
the current state's shader already the replace-colour one", against a state whose shader is null by
default. Null compared equal to null, so the guard answered yes to every question and refused every
shader. Painter now builds the programs unconditionally and lets them be inert: a draw records the
material it wanted by naming the program it bound, and the replace-colour program is what every
marked creature and highlighted item binds.

**A texture uploaded by a non-GL backend was reloaded from disk on every frame it was drawn.**
`Texture::create` keeps its CPU pixels when there is no GL context, deliberately, so a backend has
something to upload — but nothing could then say it had. With `m_id` stuck at zero the garbage
collector kept treating the texture as one that had never reached the GPU, freed the copy, and
`create()` restored it from disk the next time it was drawn. Every frame.

## Owner decisions recorded 2026-08-21

- **Presentation belongs to the backend.** Recorded here as settled rather than as an option, and
  the design document's open note is closed against it.

## Deferred follow-ups

None block Phase 5.

**Online captures need spacing between logins.** Twelve seconds is enough. Without it the server still
holds the previous session, the `!fixture` talkaction is swallowed, and the run either fails to reach the
anchor at all or captures from two tiles away — which reads as a 90%-different frame and looks like a
renderer defect until the shift is measured. Worth folding into the capture driver rather than the shell
loop, if the online scenes are ever automated.

**Module materials draw as plain geometry.** All 27 registered module programs, and therefore
`shader-matrix`, `shader-matrix-outfits`, and the single Outline probe in two further scenes. This
is the Phase 6 boundary and it is stated in the manifest rather than tolerated: two scenes carry
`renderBackendComparable: false` with a reason, and two carry a measured
`renderBackendTolerance`. All four entries name Phase 6 and say to remove them when it lands. **Removed 2026-08-21 (Phase 6):** three are deleted outright — `outfit-masks` and `temporary-framebuffers` now compare at 0 px and `shader-matrix` at 17 — and the fourth survives only on `shader-matrix-outfits`, re-justified for shader ill-conditioning rather than for absent materials.

~~**`ShaderManager` registers nothing without a GL context**, so a module program never reaches
`PoolCompiler::materialOf` on this backend and the material-handle-to-MSL mapping is entirely
unexercised. Phase 6 will be new territory rather than a filled-in table.~~ **Closed 2026-08-21
(Phase 6):** registration and compilation were separated, so a module program is registered without a
GL context and only its GLSL is skipped. That is what gives it a material identity on this backend,
and it turned out to be the unlock the whole phase rested on.

**`IRenderBackend` still has no resource plane.** The Metal backend owns native objects now, which
is the condition Phase 3 said the six virtuals were waiting for — but they would still only be
called by the backend itself, since `Texture` and `FrameBuffer` continue to own the GL ones.
Revisit when the legacy path goes, not before.

**Deferred destruction is Metal's own.** A command buffer retains every resource it references
until it completes, so a texture destroyed mid-flight is safe without a retirement queue. What the
backend does own is eviction: cache entries whose client object has been destroyed are swept every
600 frames, because handles are never reused and a dead entry is inert rather than dangerous.

**The offscreen backbuffer costs one full-screen copy per frame.** It could be skipped in frames
where no readback is pending, at the cost of the uniform treatment that makes `readPixels` work at
all. Worth measuring before worth doing.

## Reproduction commands

Both configurations, which are different compile surfaces:

```sh
cmake --build build/macos-release --parallel 8   # XQuartz, the OpenGL reference vehicle
cmake --build build/macos-cocoa   --parallel 8   # Cocoa/Metal, what CI gates
ctest --test-dir build/macos-cocoa --output-on-failure
```

One scene, on Metal:

```sh
build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC \
  --renderer-baseline=startup-ui --renderer-baseline-output=metal-startup-ui.png
```

The cross-backend sweep, which needs both binaries because the two backends cannot coexist in one:

```sh
GL_RUN_PREFIX="env DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority" \
bash tools/compare_render_backends.sh \
  build/macos-release/bin/otclient \
  build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC
```

Performance, where the frame rate now means something:

```sh
build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC \
  --renderer-baseline=startup-ui --renderer-baseline-output=bench.png --renderer-benchmark=20
```

## Commit ledger

_Regenerated from `git log --format='%h %s' --reverse 6076b37..aec105b` rather than appended to by
hand. `6076b37` is the Phase 3 audit checkpoint this phase started from. The range ends at a named
commit rather than at HEAD, because any later documentation commit - including the one that records
this range - would otherwise leave the list permanently one entry short of itself._

```text
719d962 feat(macos): give the platform layer a typed presentation surface
235f919 fix(graphics): let a texture say its pixels changed under a stable handle
49aec81 fix(graphics): keep built-in shader identities without an OpenGL context
2bcd90a feat(renderer): draw the client with Metal
ec188da test(renderer): measure the Metal and OpenGL backends against each other
9ce989c fix(renderer): clear a Metal target nobody has written yet
3fd3b0f docs(renderer): correct what Phase 4 falsified across the migration set
6dacace docs(renderer): record the online-scene evidence for the Metal backend
a59d285 docs(renderer): close the Phase 4 audit's remaining loose ends
aec105b docs(renderer): record the CI evidence for Phase 4
```

Note the shape: three of the six code commits are fixes to shared code that had nothing to do with
Metal, and every one of them was a place where the client asked whether something had reached the
GPU by reading an OpenGL name. That is the phase's real finding.

## What Phase 5 inherits

Phase 5 is render targets and full composition on Metal — which, on inspection, is largely already
running: retained targets, transient targets with nesting and both flips, `Keep` loads, hash-gated
pass skipping and readback all work, because the frame model states them and the backend executes
what it is given. What Phase 5 actually owes:

- ~~**Atlas layer targets.** The one part of the frame the compiler does not describe, and the reason
  the CPU atlases are switched off here. It is also what unblocks deleting `Painter`, which
  `TextureAtlas::flush` still drives.~~ **Delivered 2026-08-21 (Phase 5, `83e81ac`).** A frame is a
  complete description now: `TextureAtlas::compileMaintenance` emits the layer passes and
  `FrameAssembler` orders them ahead of every pool. `flush()` survives only because the legacy path
  calls it, so the `Painter` dependency expires with that path rather than before it.
- ~~**A macOS reference set.** The checked-in llvmpipe references are same-environment CI references,
  not a cross-stack oracle for Metal. A macOS baseline has to be captured and frozen before any
  gate can compare against it rather than against the OpenGL backend on another machine.~~
  **Contradicted by this same phase, corrected 2026-08-21 (Phase 5 audit).** The first sentence stands;
  the conclusion does not, and the plan already said so — `tools/compare_render_backends.sh`, which Phase 4
  itself added, runs the gate against the *live* OpenGL backend with both sides forced onto
  `--render-path=frame`, so the two consume an identical `RenderFrame` and no frozen reference is needed.
  None exists and none is owed.
- **The map-composition material**, which is the one part of the online coverage Phase 4 could not
  measure: all fourteen `shader-matrix-map` cells are map shaders, and no module program resolves on
  Metal until Phase 6. The route itself works — the scene captures — but nothing shaded comes out of it.
  **Measured 2026-08-21 (Phase 6):** shaded output comes out of it now, and comparing it for the first
  time found that `v_TexCoord` is vertically mirrored between the backends at that site. See
  `docs/phase-6-renderer-handoff.md` and `known-deviations.md`. **Fixed 2026-08-25 (`0ec21a80`):**
  absorbed in the shader translation layer, not by changing the storage convention — see the
  texture-matrix decision above. All fourteen `shader-matrix-map` captures now sit at or below the
  scene's unshaded control frame (Fog 197,123 → 111, Pulse 267,328 → 899, control 2,083); offline
  `shader-matrix` holds at exactly 17 px. Measured locally; CI is suspended.
- **The performance envelope, on a vehicle that can measure one.** Phase 3's figures are XQuartz
  CPU time at a locked frame rate and are not comparable. Metal's are.
