# Phase 3 renderer handoff

**Checkpoint:** `1693690` on `main` (pushed to `origin`, the fork `aacruzgon/CrystalOTC`)

**Date:** 2026-08-21

**Scope:** Phase 3 — the OpenGL renderer consumes `RenderFrame`

## Current state

The frame model is no longer a description of a renderer; it drives one. A pool's published
object list compiles to a `PoolProgram`, five programs assemble into a `RenderFrame`, and
`GLBackend` executes it — and the pixels it produces are the same pixels the legacy path
produces, measured rather than argued.

It is **opt-in and off by default**. `graphics.renderPath` is `legacy` unless a config file,
`--render-path=frame` or `CRYSTALOTC_RENDER_PATH` says otherwise. Both paths are live at once
on purpose: the comparison between them is the whole point of the phase, and it stops being
possible the moment one of them is deleted.

At this checkpoint:

- All four CI jobs green on `2768b4d` — `Build - macOS (Cocoa)`, `Build - Windows`,
  `Renderer baseline - Linux llvmpipe`, `Tests - Lua`.
- `ctest` 57/57, up from 53.
- All four online scenes agree across paths within their own noise, measured against the pinned
  fixture server `crystalserver` `f47f6e41`.
- The eight reference-gated scenes still compare at **0 differing pixels** against their
  checked-in llvmpipe references, so the legacy path is provably unchanged by any of this.
- The new legacy-versus-frame sweep passes all eleven offline scenes in **both** reference
  environments.

## Phase 3 checklist

Against the implementation plan's Phase 3 tasks:

- [x] **`GLBackend : IRenderBackend`** — with "absorb `Painter`" read narrowly, deliberately.
      See *Decisions that were not free*.
- [x] **`graphics.renderPath = legacy | frame`**, plus a command-line flag and an environment
      variable, both of which the parity harness needs.
- [x] **Readback through `ReadbackRequest`** — top-left in, top-left out, backend flips.
- [x] **Legacy-vs-frame comparison**, locally on XQuartz and in CI on llvmpipe. Delivered as a
      new driver rather than a mode of the reference gate; the shapes are not the same.
- [ ] **Delete the legacy path.** Deliberately not started — owner decision, and see below for
      why it could not have been part of this gate anyway.
- [x] **Performance envelope** — inherited from Phase 0, which deferred it here.

Against the exit gate — **met**, in both environments:

| | XQuartz (local) | llvmpipe (CI, run `32452811177`) |
|---|---|---|
| Scenes at 0 differing pixels | 10 of 11 | 10 of 11 |
| `graph-lines` | 7,660 px (1.17%), max delta 235 | 8,734 px (1.33%), max delta 168 |

Ten scenes bit-identical covers all six composition modes, every shipped fragment program, all
seven temporary-framebuffer sites including nesting and both flips, atlas growth and smooth
padding, outfit masks, text and clipping. The eleventh is the one scene designed to differ.

`windowing` is not in that sweep — it is `ciCapture: false`, because a headless runner cannot
produce it — so it was compared by hand, and it is worth doing again after any change to target
lifetime. It is the only scene that resizes the window and changes HUD scale mid-run, which is
the only thing that exercises `FrameAssembler::invalidateRetainedTargets`: a resize invalidates a
retained target's contents without changing the objects that drew into them, which is precisely
the case a content hash cannot see. All four of its captures match at **0 differing pixels**,
including the one at a different resolution entirely (840,000 px rather than 656,880), and its
recorded window state is identical.

The four **online** scenes are outside the sweep too — they need the fixture server — and they
are the only ones that exercise the MAP pool, the light overlay, the map-shader composition
material and the map readback at all. They were run by hand against `crystalserver` `f47f6e41`,
three or four captures per path, and compared against each scene's own noise floor rather than
against zero, because a live server cannot be frozen perfectly:

| Scene | within legacy | across paths |
|---|---|---|
| `map-screenshot` | 0 px | **0 px**, every pair |
| `shader-matrix-map` (14 map shaders) | worst 875 px | worst 927 px |
| `lighting-overlap` | 836 / 836 / 0 px | 340 / 668 / **0** px |
| `map-core` | 2,719 px | 2,160 px |

In every case the paths differ by no more than the legacy path differs from itself, and two
pairs match exactly. Doing this found the animated-texture defect below, which no static scene
could have caught — worth repeating whenever target-reuse logic changes.

**Why task 5 is not part of this gate.** The gate is *"legacy and new GL paths pixel-match"*.
That requires both paths to exist; task 5 removes one. It is the step after the phase closes,
not a prerequisite for closing it.

## Decisions that were not free

**`GLBackend` draws through `Painter` rather than replacing it.** Painter owns the blend table,
the scissor y-flip, the colour mask, the projection and the uniform upload sequence — which are
exactly the things that have to stay identical. Reimplementing them alongside the original would
have created a second version of the thing under test, and any difference between the two would
have been indistinguishable from a defect in the frame model. So the split is: the backend owns
everything the frame model *added* — passes, targets, load actions, materials, handle
resolution, geometry slices — and `drawCoords` was refactored onto a raw-array primitive so both
paths reach one draw call. Absorbing the rest is what task 5 is for, when there is no longer a
legacy path to differ from.

**`ResourceRegistry` resolves and does not allocate.** Phase 2 re-decided this and the decision
held on contact. Handles are derived, not issued, and that is what makes compiled output
byte-identical across runs and platforms; an allocating registry would destroy the property the
golden frames rest on. It also owns nothing, because `Texture` and `FrameBuffer` still own their
GL objects — there is nothing yet for a backend to own.

**`IRenderBackend` has no resource plane.** The design sketched six more virtuals. Their only
implementation would forward to objects the backend does not own, which is an interface
specified against an imagined renderer — the exact failure Phase 2 refused. They arrive with
Metal, which will actually own something.

**Atlas maintenance is hoisted in front of the frame, not interleaved per pool.** GL creates a
texture and offers it to the atlas as each object draws, then flushes after each pool. Doing all
of it before any pass is equivalent, and the reason is worth keeping: a region created during
frame N is not consulted until the *producer* runs for frame N+1, because it is `DrawPool::add`
that translates a source rect into atlas coordinates. Nothing this frame draws can see a region
this frame created. `atlas-resources` matching at 0 px is the evidence.

**Alpha-writing leakage is not modelled, and could not be.** `FrameBuffer::release` never
restores `glColorMask`, so the value leaks out of nested targets and out of atlas maintenance
into whatever draws next — across pool boundaries. A pool is compiled alone, on a producer
thread, before the frame is ordered, so that leak is not visible to the compiler even in
principle. What is well defined is the value each target is *entered* with, and that is what a
packet states. Harmless today because backbuffer alpha never reaches a PNG: both screenshot
paths call `Image::setOpacity(255)`.

**Compilation moved off the pool lock.** Phase 2 held the lock while compiling because the
published list is what a consumer may swap away — but that is only true once the repaint flag
says so, and it does not yet. The compile window is exclusively the producer's. The consumer
gained a third program slot mirroring the object list's build/publish/draw rotation, so a second
publish cannot overwrite what the consumer is reading.

## Traps worth not rediscovering

**A transient target handle names a slot, not a buffer.** `transientTarget(pool, depth)` is the
same handle for every bind at that depth, and several widgets bind depth 0 in one frame at
different sizes. Sizing them all up front collapses them onto whichever pass came last; the
earlier blits then sample a texture smaller than their source rect, clamp, and render as the
sprite's last row smeared across the whole quad. GL never noticed because its bind callback
resizes immediately before it binds — so the backend must too, at pass execution time.

**A parity harness that does not pass its own flag reports a clean sweep it did not earn.** The
first full run compared legacy against legacy and returned eleven passes. Nothing in the output
distinguished that from a real result. The script now fails a scene whose frame run *fell back*
to the legacy path, for the same class of reason.

**`macOS ships bash 3.2`,** so no `mapfile`. A `while IFS= read -r` loop works in both.

**`gh run list --commit` needs the full SHA** — recorded by Phase 2, and rediscovered anyway
within the hour by passing an eight-character prefix to a monitor, which then reported every job
complete with an empty conclusion.

**Frame rate is the wrong axis for measuring this on XQuartz.** There are two ceilings: the
client sleeps to hold 60 FPS, and the driver holds the swap to the display refresh. XQuartz
advertises neither `GLX_MESA_swap_control` nor `GLX_SGI_swap_control`, so the second one does
not come off, and both paths report an identical ~120 on a 120 Hz panel however much they cost.

## Bugs found, and how

Five defects, all in code that had passed review, none found by reading it. Every one was
invisible until something *executed* the frame description rather than merely producing it —
which is the argument for ordering Phase 3 before Phase 4, made concrete.

**Built-in shader programs compiled to garbage materials.** `PainterShaderProgram::m_id` was
uninitialised for the four programs `Painter` builds itself, because they never go through
`ShaderManager::putShader`. `PoolCompiler::materialOf` mapped them through the module range, so
the handle differed per run. Not theoretical: the replace-colour program reaches pool state from
`creature.cpp` and `item.cpp` — every marked creature and every highlighted item.

**The framebuffer-release packet lost its material.** It carried only `fbOpacity`. GL applies the
whole *outer* state before `FrameBuffer::draw`, which is precisely how a `useFramebuffer` shader
comes to apply at the blit rather than to each wrapped draw — so dropping it silently un-shaded
every Outline outfit.

**Alpha writing was hardcoded true**, and the MAP target's **clear colour was assumed
transparent** when `UIMap` passes `Color::black`. The clear colour travelled only inside the
`prepare` callback, so a consumer that runs no callbacks could not learn it; it is declared now.

**A compiled frame froze animated textures** — the fifth, found only once the online scenes ran.
An `AnimatedTexture` is one Texture whose GL name is re-aimed at the current frame on every tick,
while the logical handle a packet carries is deliberately stable, so a pool that published because
an animation advanced compiled to a byte-identical program. The content hash matched and the
retained target was re-composited rather than re-rendered. The *drawing* was never wrong; only the
caching was, which is exactly why eleven static scenes all passed. `map-screenshot` gave it away:
24 differing pixels, identical across repeated runs of each path and different between them, which
enlarged are a blue floor sparkle at two phases. Fixed by folding the native texture id into the
hash — the thing that does change when an animation advances — as hash input only.

## Owner decisions recorded 2026-08-21

- **Stop at the exit gate.** Task 5 — deleting `Painter`, `FrameBuffer`, `addAction` and the
  four callback-carrying entry points — is deferred rather than attempted. Two reasons beyond
  scope: it removes the instrument the exit gate is measured with, and it changes shipped
  behaviour, since with no legacy path `graph-lines` renders hard-edged and its checked-in
  reference would have to be reseeded as a deliberate refresh event.

## Deferred follow-ups

None block Phase 4.

**`Painter` cannot die until atlas maintenance is modelled as passes.** `TextureAtlas::flush`
drives the atlas through `g_painter` — `clearRect`, `setTexture`, `drawCoords`. That modelling is
Phase 5 work in the design (`[D §6]`), so task 5 has a dependency the plan places outside Phase
3. Worth knowing before anyone schedules the deletion as a self-contained refactor.

**Presentation ownership is still unresolved** between `CocoaWindow::swapBuffers` and
`IRenderBackend::render`. Phase 1 raised it, Phase 2 did not settle it, and Phase 3 did not need
to: on GL the window still presents, and `render()` ends at "encode, submit". Phase 4 must choose.

**A dead texture is skipped rather than drawn stale.** The legacy path binds a GL id whose
`Texture` has been destroyed but whose id has not yet been released by the batched deleter; the
frame path resolves the handle to nothing and skips the packet. Arguably an improvement, but it
is a behaviour difference, and it is the one place the two paths can legitimately disagree
without a scene noticing.

**The performance envelope is coarse.** Whole-process CPU over 20-second windows, n of 2 or 3,
at a display-locked frame rate. Nothing below roughly 15% is resolvable. It is an envelope for
Phase 5's gate to sit inside, not a benchmark, and a Metal figure will not be comparable to it at
all because it will not be measured through XQuartz.

**A texture whose pixels change in place is still invisible to the content hash.** The
animated-texture fix folds the native texture *id* in, which catches an animation advancing
because the id changes with it. It does not catch `Texture::updatePixels` overwriting an
already-resolved texture whose id stays the same. Nothing reaches it today — the only in-place
updater is `LightView`, and the LIGHT pool has no retained target to reuse — but a future
streaming texture drawn into the MAP or FOREGROUND target would, and would need a content
revision on `Texture` rather than an id.

**One map-core run died with SIGSEGV in `ProtocolGame::parseMessage`.** Network thread, no
renderer frame in the stack, on the legacy path where the compiler does not run. It did not
reproduce in four further attempts. Recorded rather than chased: it is a pre-existing flake in
the online fixture path and Phase 3 is not the change that would explain it. Worth knowing if
someone else meets it while running these scenes.

**`RenderFrame::readbacks` is still produced by nobody.** `ReadbackRequest` is the parameter type
of `readPixels`, not a queue the frame carries. Fine as it is; worth not mistaking for an
oversight.

## Reproduction commands

Both paths, one binary, one scene:

```sh
DISPLAY=:0 XAUTHORITY=~/.Xauthority build/macos-release/bin/otclient \
  --renderer-baseline=startup-ui --renderer-baseline-output=startup-ui.png \
  --render-path=frame
```

The whole parity sweep, which is what CI runs:

```sh
DISPLAY=:0 XAUTHORITY=~/.Xauthority bash tools/compare_render_paths.sh \
  build/macos-release/bin/otclient
```

Performance, on any scene the capture driver builds:

```sh
/usr/bin/time -p build/macos-release/bin/otclient \
  --renderer-baseline=shader-matrix --renderer-baseline-output=bench.png \
  --renderer-benchmark=20 --render-path=frame
```

Both macOS configurations still build, and they are different compile surfaces:

```sh
cmake --build build/macos-release --parallel 8   # XQuartz, the reference vehicle
cmake --build build/macos-cocoa   --parallel 8   # Cocoa, what CI gates
ctest --test-dir build/macos-release --output-on-failure
```

## Commit ledger

Oldest first, regenerated from `git log --format='%h %s' --reverse afd88b5..1693690` rather than
appended to by hand. `afd88b5` is the Phase 2 handoff this phase started from. 40 files,
+2048/−111. Documentation-audit commits made after this checkpoint are not listed, following the
same convention Phase 2's ledger used.

```text
360c581 feat(renderer): run the OpenGL renderer on a compiled RenderFrame
1902851 test(renderer): gate the legacy and compiled render paths against each other
2768b4d docs(renderer): correct what Phase 3's first half falsified
8199692 test(renderer): measure the two render paths against each other
48ccd40 docs(renderer): record the performance envelope Phase 0 deferred here
c6c0acf docs(renderer): hand off Phase 3
1693690 docs(renderer): record the one parity check the sweep cannot make
```

## What Phase 4 inherits

Phase 4 is the Metal foundation: `MetalContext`, resources, vertex arenas, the pipeline cache,
built-in MSL materials. Five things from this phase bear on it.

- **`IRenderBackend` is the seam, and it is deliberately thin.** Adding the resource plane is
  Phase 4's job, and it will be the first backend with something to own — so it is also where
  `ResourceRegistry` grows deferred destruction.
- **`GLBackend` is the worked example**, and it is short. Every decision it makes about a packet
  is a decision Metal has to make too, in the same order.
- **`RecordingBackend` becomes useful for the first time.** When Metal and GL disagree visually,
  record the frame both consumed: matching recordings put the bug below the boundary, differing
  ones put it in the compiler. Phase 3 never needed it, because there was only one backend.
- **The `u_Time` pin has to survive.** `PainterShaderProgram::currentTime()` is what the frame
  assembler asks; an unpinned Metal frame and an unpinned GL frame are captured at different
  animation phases and have nothing to compare.
- **Do not create a line pipeline.** Nothing can emit a line material, `BuiltinMaterial` reserves
  no slot for one, and `graph-lines` already demonstrates what the triangulated geometry looks
  like against GL's — 1.2% to 1.3% of the frame, edges only.
