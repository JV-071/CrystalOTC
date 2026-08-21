# Phase 2 renderer handoff

**Checkpoint:** `272f5d8` on `main` (pushed to `origin`, the fork `aacruzgon/CrystalOTC`)

**Date:** 2026-08-21

**Scope:** Phase 2 — the renderer boundary (`PoolCompiler`, `RenderFrame`, `RecordingBackend`)

## Current state

The renderer boundary exists and is exercised. A pool's published `DrawObject` list compiles
into explicit passes and packets with no graphics API involved, a frame assembles from those
programs, and a GPU-less backend serialises the result to stable text that CI diffs against a
checked-in golden.

It is **additive and switched off**. `DrawPool::setCompileFrames` defaults to false, the GL path
does not read a `PoolProgram`, and no backend consumes a `RenderFrame` yet. Phase 3 is what turns
one of these into the thing that draws.

At this checkpoint:

- `Build - macOS (Cocoa)` green — 53/53 ctest.
- `Build - Windows` green — 54/54 ctest (54 because `StringEncoding.Utf16Conversions` is
  `#ifdef WIN32`). This was the **first Windows run ever to complete** on the Phase 2 tree.
- `Renderer baseline - Linux llvmpipe` green — 53/53 ctest and all **8 gated scenes at 0
  differing pixels**.
- Both golden frames pass on **three independent toolchains** — AppleClang/libc++/arm64,
  GCC/libstdc++/x86-64, MSVC/x86-64.
- All 11 offline baseline scenes recaptured on XQuartz against pre-Phase-2 captures after every
  round of shared-code edits: ten bit-identical every time. The eleventh is `particles-blends`,
  which is bimodal on its own binary (see *Deferred follow-ups*).

## Phase 2 checklist

Against the implementation plan's Phase 2 tasks:

- [x] **API-neutral enums.** `DrawMode`, `BlendEquation`, `ShaderType` and `CompositionMode` are
      plain `uint8_t`; the GL numbering moved to `painter.cpp` and `shader.cpp`. `declarations.h`
      no longer includes `glutil.h`, which is the substance of the task — verified by
      preprocessing a TU that includes it and finding no GL symbol at all.
- [ ] **Logical handles + ResourceRegistry.** Handles exist and flow through `PoolState`; the
      **registry was deliberately not built** — see *Decisions that were not free*.
- [x] **Promote the vk side-channels.** Renamed throughout, feeder included.
- [x] **PoolCompiler + PoolProgram**, wired into `release()` in `3d7001c`. All seven surveyed
      idioms compile. **Atlas maintenance passes are not compiler work** and were re-targeted.
- [x] **FrameAssembler + RenderFrame**, including `LoadAction::Keep` and pool-hash pass skipping.
- [x] **RecordingBackend + golden frames.** 31 tests. They use hand-built scenes rather than the
      Phase 0 `scenes.json` fixtures.
- [x] **Freeze `MaterialParams`.** std140, every offset `static_assert`ed, `sizeof == 80`.

Against the exit gate — **met**, with one item parked by owner decision:

- [x] Golden-frame suite green in CI on GPU-less runners. Observed on all three, not reasoned.
- [x] Linux GL bit-identical: 8 gated scenes at 0 px with the whole boundary in the tree.
- [—] Windows GL: **no pixel gate exists and never has.** Phase 0 chose llvmpipe as the canonical
      reference precisely because no Windows machine is available, so this is structurally
      unmeasurable from this plan rather than merely unmeasured.
- [—] Windows Vulkan runtime: **deferred indefinitely by owner decision, 2026-08-21.**

## Decisions that were not free

**Handles are derived, not allocated.** `RenderHandles` mints target handles from
`(pool type, nesting depth)` and texture handles from a `Texture`'s process-wide unique id. That
is what makes compiled output byte-identical across runs, threads and platforms — the property
the golden frames rest on, and the reason the suite could be gated on three toolchains at all.
An allocating registry would have destroyed it. The texture range works because `Texture`'s
counter starts at `UINT16_MAX`, leaving everything below free; `texture.h` now names that seed so
`renderhandles.h` can `static_assert` against it rather than trusting a comment.

**`contentHash` is taken over the compiled output, not copied from `DrawHashController`.**
Identical output is a stronger justification for reusing a target than identical input, and it
stays meaningful if the compiler later changes what it emits for the same objects.

**Compilation happens inside `release()`'s lock.** The published list is exactly what the
consumer may swap away the instant the lock drops, so compiling outside it would race. The cost
is bounded and paid only when compiling is on. ~~**Phase 3 needs both paths live at once and should
move this off the lock rather than inherit it.**~~ **Moved 2026-08-21 (`360c581`):** the consumer
may only swap once the repaint flag says so, and it does not yet, so the compile window belongs to
the producer alone.

**`BlendMode` is separate from `CompositionMode`.** They are 1:1 today. Keeping them distinct lets
the producer-facing names stay stable while the renderer-facing ones describe what the GPU
actually does — `CompositionMode::ADD` is `(1-src, 1-src)`, so it is `BlendMode::AddWeird`. A
backend author who read "Add" and implemented additive blending would silently break every
particle in the game.

**Packets carry complete state; there is no command stream.** The surveyed live pipeline-state
space is ~25-30 combinations, so immutability is affordable and buys sortability, recordability
and testability without correctness depending on the order state commands arrived in.

**`MaterialParams` is floats, not `Size`/`Point`/`PointF`.** The design sketched those types;
they are integer types here and cannot sit in a std140 float block. The offsets are the ones a
naturally written GLSL block produces, so the Phase 6 toolchain need not emit a padding member.

## Traps worth not rediscovering

Each of these cost real time and none is guessable from the code.

**`#define private public` cannot link on MSVC.** The suite first reached `DrawPool`'s producer
API that way, copying `tests/map/map_spectators_test.cpp`. It is undefined behaviour that
Itanium-ABI toolchains tolerate because access specifiers are not part of their mangling. MSVC
encodes them, so the test emitted calls to `public:`-mangled symbols the library defined as
`private:` — 11 unresolved externals, after a one-hour build. Note the existing map test links
today only because its accesses resolve to inline members and data; the trick breaks the moment
a test calls an out-of-line private function. Use the `friend struct DrawPoolTestAccess` seam.

**`cocoawindow.mm` depends on glew for GL *types*, not for GL.** It suppresses Apple's `gl.h` and
`gltypes.h` via `__gl_h_`/`__gltypes_h_`, but those guards do **not** cover `OpenGL.h`,
`CGLDevice.h` or `CGLIOSurface.h`, which use `GLint`/`GLenum`/`GLsizei`/`GLuint`. glew supplied
them for free through `declarations.h`. Removing that include broke the Cocoa build with 15
errors from inside Apple's own headers. The file now includes `glutil.h` explicitly and first.
The file's comment had stated the dependency exactly — and a documentation audit classified that
same comment as a stale nit hours before it broke.

**`Matrix3 x{ DEFAULT_MATRIX3 }` does not copy.** Brace syntax selects the
initializer-list-of-floats constructor. `PoolState` spells it `= DEFAULT_MATRIX3` for this reason.

**The XQuartz and Cocoa builds are different compile surfaces.** `cocoawindow.mm` is not in the
XQuartz build at all. Verifying only `macos-release` misses an entire translation unit; build
both.

**`gh run list --commit` needs the full SHA.** A short SHA silently matches nothing, so a monitor
filtered that way waits forever and its silence looks like "still running".

**The Windows job cancels itself.** `build-windows.yml` has a job-level `concurrency` group with
`cancel-in-progress: true`, and the job takes ~60 minutes. A burst of pushes touching `src/**`
means it never completes. Windows was cancelled on four consecutive Phase 2 commits before one
finally ran.

## Bugs found, and how

Four defects, three of them pre-existing. None was found by reading the code.

**An out-of-bounds read in `DrawPool`'s state stack** (`bf4458b`), found by a Linux **segfault**
in a test that passes on macOS. `m_lastStateIndex` is unsigned, so `releaseFrameBuffer` with no
matching bind wrapped it and the next `getCurrentState()` read outside the fixed ten-element
array. macOS had tolerated it silently for as long as the code existed. `nextStateAndReset()` had
the mirror-image bug past depth 9. Both ends are now guarded, and a refused bind refuses its
matching release too — guarding only the bind would have replaced one corruption with another.

**Two latent GL-type problems in the Cocoa include contract** (`c8050f5`), found by the first CI
run to touch the tree, on a configuration that had never been built locally.

**A link-level portability defect in the test seam** (`b8458df`), found by MSVC — see the traps.

All three were in code that had already passed review, and none was reachable by the macOS-only
checking this repository had before Phase 2 added `ctest` to Windows and Linux.

## Owner decisions recorded 2026-08-21

- **Windows Vulkan runtime validation is deferred indefinitely.** No Windows machine exists and
  none is expected soon. Nothing Vulkan-related is to be scheduled, blocked on, or counted as
  outstanding until the owner states that testing hardware is available. Two behaviour changes
  are queued behind it — `67f9b38` (Phase 1) and Phase 2's side-channel rename — both
  compile-verified under MSVC and both preserved by construction. **The queue is parked, not
  owed; it must not hold a gate open.**

## Deferred follow-ups

None block Phase 3.

**`ResourceRegistry` — re-decided, not skipped. Built 2026-08-21 (`360c581`), resolution only.** Its two jobs separated under what Phase 2
actually built. Allocation is obsolete (see the determinism decision above). Resolution and
deferred destruction need a backend that owns native objects, and none exists: `RecordingBackend`
only prints handles and the GL path never sees one. A table with no consumer would be untested
code specified against an imagined renderer. Schedule it with Phase 3's `GLBackend`.

**Atlas maintenance passes — re-targeted, not skipped.** They cannot be compiler work: the
atlas's pending-texture list is filled by `PoolState::execute` on the **render** thread while the
frame is drawn, and the program is compiled on a producer thread before that happens.
`PoolProgram::requiresAtlasMaintenance` states the omission so a compiled frame is never mistaken
for complete. The work belongs to the frame assembler.

**`particles-blends` can fail its own CI gate.** It is bimodal on one binary: within a mode 0
differing pixels, between modes ~540-946 px at max channel delta 252, confined to the ADD card.
The high mode exceeds its own `maxDifferentFraction` of 0.001. Two attractive theories were
eliminated and recorded in `known-deviations.md` — it is **not** a duplicated burst and **not** a
random size multiplier. The root cause is unknown. Do not reseed the reference; that picks a mode
at random and leaves the other failing.

**The Windows vcpkg cache fix is unconfirmed.** `11de064` gave the job a working binary cache —
`run-vcpkg` had been setting `VCPKG_BINARY_SOURCES` to the removed `x-gha` backend, so nothing
was cached and 52 of the job's 63 minutes went on rebuilding every port. The first run after the
fix still pays full price because the cache starts empty; the payoff shows on the second.

**Golden tests do not consume `scenes.json`.** They use hand-built scenes. Wiring them to the
Phase 0 fixture manifest remains open.

## Reproduction commands

Both macOS configurations — the XQuartz one is the baseline reference vehicle, the Cocoa one is a
separate compile surface and is what CI gates:

```sh
cmake --preset macos-release -DTOGGLE_BIN_FOLDER=ON
cmake --build --preset macos-release --parallel 8
ctest --test-dir build/macos-release --output-on-failure

cmake -S . -B build/macos-cocoa -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DBUILD_STATIC_LIBRARY=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_FLAGS_RELEASE="-O1 -DNDEBUG" -DTOGGLE_COCOA_WINDOW=ON
cmake --build build/macos-cocoa --parallel 8
```

Run the compiler against real frames by flipping `DrawPool::s_compileFrames` to `true`, then
capturing the offline scenes; an incomplete program logs once per pool.

Baseline capture needs XQuartz with `DISPLAY=:0 XAUTHORITY=~/.Xauthority` — note the auth file is
`~/.Xauthority`, not the `~/.serverauth.*` the process list advertises.

## Commit ledger

Oldest first, regenerated from `git log --format='%h %s' --reverse 030adbd..HEAD`. `030adbd` is
the Phase 1 handoff this phase started from.

```text
fa8656d refactor(graphics): stop the shared enums carrying OpenGL values
71bb824 feat(renderer): add the backend-neutral boundary vocabulary
700b41b feat(renderer): let draw pools declare what their GL callbacks do
797bd79 feat(renderer): compile pool programs into an explicit render frame
6509905 feat(renderer): declare the map shader, graph lines and light overlay
021112b test(renderer): cover the renderer boundary with a golden frame
1e552cd docs(renderer): correct the Phase 2 claims the implementation falsified
ab2e0da docs(renderer): record that particles-blends can fail its own CI gate
2784e73 ci(renderer): run the unit tests on Windows and Linux too
0f07f44 feat(renderer): re-composite an unchanged pool instead of redrawing it
3d7001c feat(renderer): compile the published object list from release()
637ded7 feat(renderer): declare atlas maintenance as an omission with a known owner
77c3d86 docs(renderer): record what the remaining Phase 2 items turned into
c8050f5 fix(macos): give the Cocoa window its own glutil.h include
bf4458b fix(graphics): stop an unbalanced framebuffer release corrupting memory
fe2c004 docs(renderer): record what the particles-blends flake is not
b8458df fix(renderer): reach DrawPool's producer API without redefining `private`
11de064 ci(windows): give the job a vcpkg binary cache that actually works
a1ac1c8 docs(renderer): record the Phase 2 exit gate against observed CI
272f5d8 docs(renderer): resolve the contradictions the first correction pass left
```

## What Phase 3 inherits

Phase 3 makes the OpenGL renderer consume `RenderFrame`. Five things from this phase bear on it:

- **The compiler has a caller but no consumer.** `release()` compiles when switched on; nothing
  reads the result. Phase 3's first job is `graphics.renderPath = legacy | frame` and a
  `GLBackend` that executes a frame. **Discharged 2026-08-21 (`360c581`).**
- **Move compilation off the pool lock.** Phase 2 compiles inside it deliberately; running both
  paths live makes that the wrong trade. **Discharged 2026-08-21 (`360c581`).**
- **Presentation ownership is still unresolved** between `CocoaWindow::swapBuffers` and
  `IRenderBackend::render`. Phase 1 raised it; Phase 2 did not settle it.
- **The `u_Time` pin must survive into every backend.** Without it a GL-versus-Metal comparison
  captures two different animation phases and has nothing to compare.
- **`RecordingBackend` is the triage instrument.** When two backends disagree visually, record the
  frame both consumed: matching recordings put the bug below the boundary, differing ones put it
  in the compiler. **Still true, and not yet needed:** Phase 3's four defects were all found by
  comparing captured pixels between the paths, and three of the four were in the compiler.
