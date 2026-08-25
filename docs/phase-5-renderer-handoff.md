# Phase 5 renderer handoff

**Checkpoint:** `af69cd5` on `main` — the phase's last non-documentation commit, on `origin`, the
fork `aacruzgon/CrystalOTC`, together with the documentation commits that follow it.

**Date:** 2026-08-21

**Scope:** Phase 5 — render targets and full composition on Metal

## Current state

A `RenderFrame` is now a complete description of a frame. The last thing it could not express was
CPU texture-atlas maintenance, which `TextureAtlas::flush` performed through `g_painter` inside a
raw `glDisable(GL_BLEND)` bracket — so a compiled frame was always a description with a footnote,
and the atlases had to be switched off entirely under Metal.

They are not switched off any more. The atlas is backend-neutral, its maintenance compiles to
ordinary passes, and `atlas-resources` compares Metal against OpenGL at **0 differing pixels** with
both backends reporting identical atlas state.

Most of what Phase 5 was scheduled to build had already landed in Phase 4 — retained targets,
transient targets with nesting and both flips, `Keep` loads, hash-gated pass skipping and readback
all work, because the frame model states them and the backend executes what it is given. What this
phase actually added is the part nothing described, plus the instruments to prove the rest.

At this checkpoint:

- **All four CI jobs green on `13acc96`** — `Build - macOS (Cocoa)` (run `32508823574`),
  `Build - Windows` (`32508823543`), `Renderer baseline - Linux llvmpipe` (`32508823547`),
  `Tests - Lua` (`32508823523`).
- `ctest` 63/63 on both macOS configurations and on Linux, 64/64 on Windows, up from 58/59.
- The eight reference-gated scenes pass on llvmpipe with **seven at 0 differing pixels** and
  `particles-blends` at 626 px inside its own bimodality — the proof that the atlas rework left the
  legacy path untouched, which was this phase's main risk.
- The llvmpipe legacy-versus-frame sweep passes all eleven, ten at 0 px and `graph-lines` at
  exactly the 8,734 px Phase 3 recorded.
- The legacy-versus-frame sweep is unmoved: ten offline scenes at **0 differing pixels** and
  `graph-lines` at exactly the 7,660 px Phase 3 recorded, so the OpenGL path is provably untouched.
- The Metal-versus-OpenGL offline sweep is unmoved too — six of nine comparable scenes at **0 px**,
  the two module-shader scenes still excluded until Phase 6. `atlas-resources` is the one that
  changed meaning rather than value: it stayed at 0 px but now compares atlas-backed geometry on
  **both** sides instead of atlas-backed against standalone, with both backends reporting identical
  atlas state (linear group grown to three 2048x2048 layers, 41 cached entries).
- The three comparable online scenes agree within their own noise, measured twice. Five pairs
  matched exactly, including **`map-core` at 0 differing pixels of 656,880** — the whole map scene
  agreeing across two graphics APIs, with the map now atlas-backed on both. The fourth,
  `shader-matrix-map`, is all map shaders and stays uncomparable until Phase 6; it was captured on
  both backends anyway and produced all fourteen cells without incident on each.
- Metal holds **389–404 fps median** with the atlases on, against Phase 4's recorded 320–400, so
  atlas maintenance passes cost nothing measurable.
- The eight reference-gated scenes are still green against their checked-in llvmpipe references.

## Phase 5 checklist

Against the implementation plan's Phase 5 tasks:

- [x] **Retained targets** — landed early, in Phase 4.
- [x] **Transient target pool** — landed early, in Phase 4.
- [x] **Atlas layer targets** — this phase. Maintenance passes with blend-off packets, padding
      draws and `Keep` accumulation, plus the two identity problems the plan did not know were in
      the way. See *Decisions that were not free*.
- [x] **MAP composition, light overlay, hole punch, direct passes** — all four were already
      running; this phase closed the gap between that and knowing it, with unit regressions for
      the two that are unit-testable and a repeatable online harness for the two that are not.
- [x] **Readback** — landed early, in Phase 4.
- [x] **Wire the image-comparison harness to run the matrix on macOS** — `tools/run_macos_matrix.sh`,
      plus `tools/compare_online_backends.sh` for the three comparable online scenes, which had no
      harness at all.

## Decisions that were not free

**The obstacle was identity, not passes.** The plan describes task 3 as emitting maintenance
passes, and that part is nearly mechanical. Two things had to change first, and neither is about
passes:

- **A region was keyed on its occupant's OpenGL name.** A backend that creates no GL textures
  reports name 0 for every texture in the client, so the whole atlas would have collided on one
  key. Regions are keyed on `Texture::getUniqueId()` now — the identity the renderer boundary
  already speaks, and one that exists whether or not anything has reached a GPU.
- **A layer was sampled through its framebuffer texture's unique id.** That works on OpenGL only
  because an FBO's colour attachment *is* an ordinary GL texture. An atlas layer is a render
  target, and its pixels live wherever the active backend keeps target contents — so it is named
  by a target handle, in a third `RenderHandles` range `static_assert`ed clear of the pool and
  transient ranges below it and of the `Texture` unique-id space above it.

**Compiling maintenance is deliberately non-destructive.** `compileMaintenance` describes the work
and leaves the pending list, the disabled regions and the un-bumped layer revisions exactly as they
were; `commitMaintenance` retires them, and only once the backend has accepted the frame. The
alternative loses sprites silently: a backend may decline a frame, the fallback is the legacy path,
and the legacy path would find a drained atlas whose regions are marked composited and whose
pixels were never written.

**The clear-rect is a quad, not a clear.** `Painter::clearRect` is a scissored `glClear`, which no
packet can express. An unblended transparent quad over the same integer-aligned rect writes the
same zeros to the same pixels, and it is a thing a frame can describe. It is also redundant in
every case reachable today — with blending off, the draws that follow replace the same region —
but it is reproduced anyway, because the legacy path still issues it and the whole point of the
phase is that the two paths agree.

**The atlas layer stack is bounded, and running out is a supported outcome.** One layer is one
handle, so the handle range fixes a maximum per (atlas, filter group). An atlas that cannot grow
leaves the texture unpacked, which draws standalone — exactly what already happens to a texture too
large to pack. The alternative, minting a handle past the end of the group, would silently
composite into the next group's layer.

**`DrawPoolManager` holds the atlases without owning them.** The pools own them and the pools are
never deleted, so an atlas outlives static destruction. Holding a `shared_ptr` instead made
`g_drawPool`'s own teardown destroy them — see *Bugs found*.

## Traps worth not rediscovering

**A `TextureAtlas` cannot be constructed in a unit test.** It creates layer framebuffers, which
reach `glGenFramebuffers`, and in a test process `X11Window` inherits
`PlatformWindow::hasGLContext() == true` while every GLEW pointer is null. Phase 4 recorded this
for `ShaderProgram`; it applies to anything that touches a framebuffer. The atlas tests hand-build
an `AtlasProgram` instead, and the MAP composition packet's `alphaWrite` is untestable for the
same reason — it needs a pool that owns a framebuffer.

**`RUN_PREFIX` and `GL_RUN_PREFIX` are not the same variable and not interchangeable.** The
backend sweep wraps only the OpenGL client, because giving the Metal one a `DISPLAY` is wrong; the
path sweep drives a single client and wraps all of it. Setting only one produced eleven identical
capture failures reading `Unable to open X11 display`, which is indistinguishable at a glance from
a renderer defect — and it happened *after* an unrelated shutdown crash had already been fixed in
the same file, so the same symptom had two different causes an hour apart. The matrix script now
sets both and preflights the display once.

**A fourth way into the `gh run list` trap: labelling the output instead of filtering it.** Phases
2, 3 and 4 each recorded a different one — needing the full SHA, passing an eight-character prefix,
writing a full-length SHA from memory. This one is `gh run list --commit <sha> --limit 1` piped
through a `jq` filter that prints a hardcoded job name. `--limit 1` returns the most *recent* run,
not the one you meant, so the label is a claim the command never checked. It reported "Windows:
completed success" for a run that was the macOS job, while the Windows job had in fact been
**cancelled** — and a monitor that did filter by name caught the contradiction. Filter on
`.name`, or ask for all runs and read them.

**The Windows job cancels itself, and Phase 2 said so.** `build-windows.yml` sets
`cancel-in-progress: true` on a job that takes about an hour, so pushing again while it runs kills
it. Phase 2 recorded that Windows was cancelled on four consecutive commits before one completed;
this phase repeated it, cancelling a run at roughly the 55-minute mark by pushing the
documentation. When a phase's evidence depends on a green Windows build, batch the commits and push
once.

**The atlas being on is invisible in a capture.** An atlas-backed draw and a standalone one produce
the same picture; that is the point. So a regression that quietly switched the atlases off again
would look exactly like nothing happening, and every cross-backend measurement would silently stop
meaning what it says. `DrawPoolManager::init` logs the configuration and the macOS CI job asserts
it — which needs no window server, so it is gateable where a capture is not.

**`windowing-2-grown` is bimodal, and a single run per side hides it.** Phase 4 recorded all four
`windowing` captures matching across backends at 0 px. Three of the four really are stable; the
grown one differs from itself by 12,505 px on OpenGL and by 157,428 px on Metal, and matches at 0 px
across backends only when both happen to land in the same mode. Measuring it once per side has a
good chance of doing exactly that. It is the one shutter that fires immediately after a resize, so
it is the one that can still read a frame from before the new size settled - and 12,505 is the same
number Phase 4 recorded as the pre-fix symptom of that, which moving capture suppression into scene
setup reduced without eliminating. Nothing about it is specific to Metal, to the atlas or to the
render path.

**Read online-scene differences by location, not by total.** `lighting-overlap` reported
cross-backend figures modestly *above* both within-backend floors, which looks like a real
difference. Every one of those pixels is in `x[850..1005]` — the live battle-list and minimap
panel — and zero are inside the map panel, which is what the scene exists to measure. Each backend
differs from itself in the same band by a comparable amount. The totals were misleading and the
bounding box settled it in one look.

## Bugs found, and how

**A shutdown abort on every capture**, found the first time the parity sweep ran after the atlas
change — every scene reported "client did not complete the capture" while its log ended in
`capture complete`. `DrawPoolManager` had gained a `shared_ptr` array of the atlases, so
`g_drawPool`'s static destruction now destroyed them, which reached `~Texture` through the layer
framebuffers at `__cxa_finalize` time and locked a mutex that had already been destroyed. The
atlases had previously survived to process exit because only the never-deleted pools held them.
Found by backtrace, not by reading.

**A recycled atlas region could show the wrong sprite.** This is the Phase 3 animated-texture
defect reached by another route, and it predates this phase on the GL frame path. A destroyed
sprite's shelf space is handed to a new sprite of identical size; the packet that draws it is
byte-identical to the one that drew its predecessor, so the pool's content hash matches and a
retained target is re-composited rather than re-rendered. Neither existing hash term can see it —
an atlas-backed state carries no `TexturePtr`, and its `textureId` is the layer's, which does not
change when the layer's contents do. A layer notes that its pixels changed and `PoolState` carries
the revision.

**`removeTexture` left a pending composite behind.** It would have painted the departing texture
into shelf space just handed back for reuse, and set `enabled` back to true on a region the same
call had retired. Harmless while a composite ran the instant it was queued; not harmless once one
is described in one place and executed later in another.

**A texture that never reached a GPU had no way out of the atlas.** `~Texture` queued its atlas
release only when it had an OpenGL name to delete. On a backend where that name is always zero,
that is every texture in the client — so turning the atlases on under Metal without this would have
leaked every region. The queue entry now carries the unique id and the GL deletion is the optional
half.

## Owner decisions recorded 2026-08-21

_None this phase._

## Deferred follow-ups

**`Painter` still cannot die, but for a shorter list of reasons.** `TextureAtlas::flush` is no
longer the blocker in principle — `compileMaintenance` is its described form and the frame path
runs that — but `flush()` itself survives because the legacy path still calls it. That dependency
now expires with the legacy path rather than ahead of it.

**A hosted macOS runner CAN capture Metal frames, and they match the existing references.** The
probe was added as an open question and answered on its first run (`13acc96`, run `32508823574`):
**11 of 11** offline scenes captured, in about 73 seconds total, on a runner with no window server.
The offscreen-backbuffer design is what makes it work — the backend needs a drawable only to
*present*, and a capture reads the offscreen target instead.

The result is better than "it captures". Those captures compare against the **checked-in llvmpipe
OpenGL references** — the canonical set, produced by the *legacy* GL path on a completely different
stack — as follows:

| Scene | CI Metal vs llvmpipe reference | |
|---|---:|---|
| `startup-ui` | **0 px** | |
| `ui-clipping-opacity` | **0 px** | |
| `composition-all` | **0 px** | all six blend modes |
| `atlas-resources` | **0 px** | atlas growth and smooth padding |
| `text-matrix` | 1 px | |
| `graph-lines` | 8,734 px | the documented line-triangulation difference — and *exactly* llvmpipe's own frame-versus-legacy figure |
| `particles-blends` | 698 px | inside its documented bimodality |
| `shader-matrix` | 154,018 px (23.4%) | module fragment programs; this is the number Phase 6 removes |

Five of eight at effectively zero, and all three that differ are already-documented cases rather
than new ones. `graph-lines` landing on llvmpipe's exact frame-versus-legacy figure is the strongest
parity evidence in the project so far: it means the compiled frame path produces bit-identical
output on llvmpipe-GL, XQuartz-GL and macOS-Metal alike.

**What this retires:** the assumption, made in Phase 4 and repeated in Phase 5's own follow-up list,
that gating macOS would need a frozen macOS reference set. It does not. The existing reference set
already serves Metal. That in turn is what would let macOS UI work be gated on macOS rather than
against a GL binary on another machine.

**Determinism, measured 2026-08-21 by re-running the same job and diffing the two artifact sets**
(run `32508823574`, attempts 1 and 2, on different hosted runners). It needed no commit, and it was
worth doing rather than assuming:

- **Nine of eleven scenes are byte-identical across two runners** — 0 differing pixels at max
  channel delta 0, including `startup-ui`, `text-matrix`, `graph-lines`, `atlas-resources`,
  `shader-matrix` and both ungated outfit scenes. Those are gateable.
- **`composition-all` sits exactly on the tolerance boundary.** The two runs differ by 0 pixels but
  at max channel delta **2**, which is the comparator's threshold. That sub-threshold jitter is
  enough to read 0 px against the reference on one run and 15 px on the other. Stable against
  *itself*, marginal against a third image — which is the shape that produces a gate failing every
  few weeks for no reason.
- **`particles-blends` is genuinely unstable**, 102 px in `x[800..819] y[314..333]` — inside the
  26x26 ADD-card region at `x 797-822 / y 311-336` that `known-deviations.md` already documents.
  Same defect, same place, milder amplitude here (max channel delta 20) than the 540-946 px at 252
  recorded on the OpenGL side. Not a Metal problem, and already the scene that fails its own
  existing gate.

So a macOS Metal gate is viable **now** for nine scenes, and the two exclusions are the two scenes
already known to be flaky before Metal existed. That is a better position than this section
originally guessed at, and it is only visible because the probe was run twice — a single
observation would have gated `composition-all` at a threshold it crosses at random.

**The atlas layer count is capped at 32 per (atlas, filter group).** Ample — the largest observed
usage is three — but it is a cap where there was none, and hitting it degrades to unpacked textures
rather than failing loudly. Widening it is one constant and a `static_assert`.

~~**The whole UI renders at half resolution on a Retina Mac, and this is unowned rather than
deferred.**~~ **Fixed 2026-08-25.** Part 2 of the three-part plan below landed first and was the fix
(`b58e805d`, `6b03c256`); part 1 followed the same day (`07b9597d`) and is also done, though it
turned out not to be a prerequisite. Part 3 is unchanged advice. Measured locally; CI is suspended.
`FrameBuffer` gained a content scale and `RenderPass` a `projectionExtent`, so a target can be
addressed in one coordinate space and rasterised in a denser one; the FOREGROUND target is now sized
in device pixels while the UI keeps laying out in logical units, and the composition blit is 1:1.
Measured on `windowing`'s
HUD-scale-2 capture: mean absolute horizontal gradient 3.702 -> 5.193 at a best alignment of (0,0),
so the image is the same image, sharper. Density 1 is unchanged - both sweeps at every documented
value. The original write-up follows, because its diagnosis is what the fix was built from.

**The whole UI rendered at half resolution on a Retina Mac, and this was unowned rather than
deferred.** Found while answering a question about `@2x` assets, not by any gate.

*As of 2026-08-21, before the fix:*

`GraphicalApplication::resize` lays the UI out at `m_size / m_displayDensity` **and** sizes the
FOREGROUND target at `m_size / m_displayDensity`; `UIManager::render` then blits that target into
`{0, 0, g_graphics.getViewportSize()}` — the full physical viewport — through a `FrameBuffer` whose
`m_smooth` defaults to true. On a window reporting a backing scale of 2, that composites the entire
UI at 1x into a half-size intermediate target and bilinearly stretches it to 2x. Measured against a
density-1 capture: high-frequency detail falls to about a third, and an even/odd column asymmetry
appears from nothing (0.95 → 0.73), which is the fingerprint of a 2x upscale. Survey quirk 7 said
the opposite until this phase re-corrected it.

**Nothing about this is Metal.** It is shared framework code and `GLBackend` would do the same on
the same window. It has been latent since Phase 1 for two compounding reasons: XQuartz reports
density 1, so the OpenGL reference vehicle never sees it; and every baseline capture pins the
density to 1 (`g_app.setDevicePixelRatio(1)` and `g_app.setHUDScale(1)` in the capture driver — a
single `setHUDScale(1)` before the 2026-08-25 split) so that macOS captures stay comparable with
llvmpipe references. That pin is correct and should stay — but its side effect is that **the
one configuration real users get is the one nothing measures.**

Higher-resolution art does **not** fix this and would make it slightly worse: a 2x asset is sampled
down to its logical size in the intermediate target and then upscaled again, so two resamples
instead of one, for double the texture memory. The bottleneck is the target, not the source.

Three separable parts, in order:

1. ~~Split device pixel ratio from user HUD scale. They are one variable today — `g_app.setHUDScale`
   writes exactly what `getDisplayDensity` reads — which is what makes the layout and the target
   size move together.~~ **Done 2026-08-25**, though it turned out not to be a prerequisite for
   part 2, which landed first. `PlatformWindow` holds both inputs and caches their product;
   `getDisplayDensity()` keeps its name and returns that product, so no consumer changed. Worth
   doing on its own merits rather than for the Retina fix: the conflation meant that on a
   ratio-2 display, HUD scale 1 laid the interface out at device resolution and HUD scale 2 was a
   silent no-op, while a display change discarded the user's choice entirely.
2. ~~Keep laying out in logical units, but size the FOREGROUND target in **physical** pixels and draw
   into it with a scaled projection, so widgets rasterize at native resolution and the composition
   blit becomes 1:1.~~ **Done 2026-08-25 (`b58e805d`, `6b03c256`) — this was the fix.** `FrameBuffer`
   gained a content scale and `RenderPass` a `projectionExtent`; both backends split the device
   viewport from the projection extent, and the composition blit is 1:1.
3. Only then evaluate higher-resolution art — and keep game sprites `NEAREST`-filtered at integer
   scale regardless, since 32x32 pixel art is meant to look crisp and blocky rather than resampled.

**On the status (superseded 2026-08-25 — it was done outside the plan, and still owned by no
phase):** this is recorded three times — the Phase 1 handoff, design open question 5, and the plan's
Phase 1 task 2 — always as "a framework change, not a backend one", and once as "carry into
Phase 4". Phase 4 honoured it as a constraint (mirroring `m_backingScale` separately) rather
than as work. So it was classified out of scope and never scheduled, which reads like a deferral
while assigning nothing to anyone. It belongs to no phase in this plan; Phase 6 is the shader
toolchain and Phase 7's reliability matrix does not list it. Recorded here so it stops being an
orphan, not because Phase 5 owns it.

**`extractTexture` remains the one readback no non-GL backend can serve.** Unchanged since the
survey first recorded it.

**An atlas layer costs a full-size texture, and Metal pays for it later than OpenGL does.** The MAP
atlas defaults to 8192x8192, which is 256 MB of BGRA8 per layer. OpenGL allocates the first one at
atlas construction, because `createNewLayer` resizes the layer framebuffer immediately; Metal
allocates only when a pass first names the layer, which is when something is actually composited
into it. So this is not a regression - Metal is strictly lazier - but it is worth knowing before
anyone raises `ATLAS_LAYERS_PER_GROUP` or the default atlas size, and `MetalResources` never evicts
a target once created.

## Reproduction commands

Both configurations, which are different compile surfaces:

```sh
cmake --build build/macos-release --parallel 8   # XQuartz, the OpenGL reference vehicle
cmake --build build/macos-cocoa   --parallel 8   # Cocoa/Metal, what CI gates
ctest --test-dir build/macos-release --output-on-failure
ctest --test-dir build/macos-cocoa   --output-on-failure
```

The whole macOS matrix, which is the pre-release check:

```sh
# Needs XQuartz running, and the pinned fixture server for the online third.
cd ../crystalserver && ./build/macos-release/bin/crystalserver &
bash tools/run_macos_matrix.sh
```

Just the online scenes, with their own noise floors:

```sh
GL_RUN_PREFIX="env DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority" \
bash tools/compare_online_backends.sh \
  build/macos-release/bin/otclient \
  build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC 3
```

Confirm the atlas is actually live under a backend, which no capture can show:

```sh
build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC \
  --renderer-baseline=startup-ui --renderer-baseline-output=probe.png 2>&1 \
  | grep "CPU atlases"
```

## Commit ledger

_Regenerated from `git log --format='%h %s' --reverse 17cf76d..af69cd5` rather than appended to
by hand. `17cf76d` is the Phase 4 audit checkpoint this phase started from. The range ends at a
named commit rather than at HEAD, because the documentation commits after it - including the one
that records this range - would otherwise leave the list permanently one entry short of itself.
17 files, +1172/-77 across `src/`, `tests/`, `tools/` and `.github/`._

```text
83e81ac feat(renderer): model atlas maintenance as explicit render passes
6e49deb docs(renderer): correct what the atlas passes falsified
f34c1f2 feat(renderer): state the atlas configuration and assert it in CI
25ec4da test(renderer): cover the light overlay and the map-hole punch
af69cd5 test(renderer): measure the online scenes across both backends
```

Note the shape, which is the opposite of Phases 3 and 4: all the *behaviour* is in the first
commit. Of the two that touch `src/`, the second adds a single log line, and everything else is
instrumentation - the tests, the harnesses and the CI assertions that make the first commit's
claims checkable by someone who was not there. That is what a phase looks like when most of its
scheduled work has already landed early and what remains is proving it.

## What Phase 6 inherits

Phase 6 is the materials toolchain: `.frag` → glslang → SPIR-V → SPIRV-Cross → MSL, the 27
registered module programs, and the GL side of the `MaterialParams` ABI.

- **Two scenes are excluded from the cross-backend gate and two more carry a widened tolerance**,
  all four naming Phase 6 and saying to restore the defaults when it lands. Those four entries are
  the phase's acceptance test: it is done when they can be removed. **Done 2026-08-21 (Phase 6):**
  three were removed and the fourth re-justified, so the acceptance test was met as posed.
- ~~**`ShaderManager` registers nothing without a GL context**, so a module program has never reached
  `PoolCompiler::materialOf` on the Metal backend. The material-handle-to-MSL mapping is entirely
  unexercised rather than partly built.~~ **Closed 2026-08-21 (Phase 6):** registration was separated
  from compilation, which is what gave a module program a material identity there at all.
- **The map-composition route works but nothing shaded comes out of it.** `shader-matrix-map`
  captures all fourteen cells without incident and every one of them is a map shader, so the route
  is proven and its payload is not. **Payload delivered and measured 2026-08-21 (Phase 6)** — and it
  is where that phase's largest finding came from: comparing the scene for the first time showed
  `v_TexCoord` running the opposite way on a render target between the two backends, which six of
  the thirteen map shaders can see. **Closed 2026-08-25 (`0ec21a80`):** absorbed in the shader
  translation layer; all fourteen `shader-matrix-map` captures now sit at or below the scene's
  unshaded control frame.
- **The frame is now a complete description**, which changes what a Phase 6 failure means: if a
  module material renders differently on the two backends, the recorded frames will be identical
  and the difference is in the translation. That is the triage `RecordingBackend` was built for and
  has not yet been needed for.
