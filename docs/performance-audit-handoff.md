# Performance audit handoff

**Checkpoint:** `27bee8d0` on `main` (local; not yet pushed to the fork `aacruzgon/CrystalOTC`)

**Date:** 2026-08-27

**Scope:** Client-wide CPU performance — draw-list production, frame compilation, UI traversal,
Lua bridge, Metal encoding — plus the profiling harness the work should have started with.

## Current state

Six optimisations landed, one was built and removed as provably useless, and a frame profiler
now exists so the next question does not cost a rebuild.

The single most important result is the **last** one measured, and it invalidates most of the
prioritisation that preceded it: on an Apple-silicon machine, in-game, the client spends
**94% of each frame blocked waiting for a drawable**, not computing. All CPU work in the frame
totals roughly 0.6 ms against a 3.76 ms present wait. Read the *What the numbers actually say*
section before planning any further CPU work.

## What landed

Seven commits, oldest first. `perf(...)` commits are mine; note the tree also carries a parallel
agent's `fix(...)`/`feat(...)` work interleaved between `e76b505d` and `27bee8d0`.

```text
039e499e perf(renderer): mix the vertex content hash eight bytes at a time
1b5d155d perf(graphics): append vertices through a claim pointer, not vector::insert
799238db perf(map): stop copying every visible tile into the walking-run buffer
c4f9a814 perf(lua): drop the per-access string build and refcount in __index
4aae9cd7 perf(metal): skip encoder state that is already bound
e76b505d perf(ui): stop the atlas-region check forcing a full UI repaint
27bee8d0 feat(profiler): add a frame profiler that can be left switched on
```

| Commit | Evidence |
| --- | --- |
| `039e499e` content hash | **Measured.** Producer frame 0.1213 → 0.0859 ms (−29%); compile step 0.0612 → 0.0263 ms (−59%). |
| `1b5d155d` claim pointer | **Measured.** Draw-list build 0.0596 → 0.0448 ms (−25%); producer frame 0.0859 → 0.0700 ms (−19%). Combined with the above, −42%. |
| `799238db` map tiles | **Unmeasured.** No harness reaches tile iteration; no test coverage for `drawFloor`. |
| `c4f9a814` Lua `__index` | **Unmeasured.** No C++ Lua benchmark exists. |
| `4aae9cd7` Metal encoder | **Unmeasured.** Nothing drives a live encoder in the suite. |
| `e76b505d` atlas repaint | **Partially measured.** Removes ~75 forced pool republishes/second. Did *not* achieve its goal — see *The UI dead end*. |
| `27bee8d0` profiler | Verified against the live client; its output matches an independent `sample(1)` run of the same scene. |

Benchmark method for the two measured rows: a harness linking the real `libotclient_core.a`
and driving the shipping producer API through the `DrawPoolTestAccess` seam — 2,600 textured
quads from 64 textures, geometry jittered per frame so the hash controller sees a changed scene,
warm-up frames discarded, 5 warmed runs. Each row moved only its own target and left the other
alone, which is what attributes the saving to the change rather than to drift.

Three tests were added (102 total, all passing):

- `ContentHashSeesGeometryPacketMetadataCannotDistinguish` — two draws with byte-identical packet
  metadata differing only in vertex values must hash differently. Verified as a real guard by
  disabling the term and confirming only this test fails.
- `VertexPrimitivesEmitTheirDeclaredLayout` — pins all nine `VertexArray` primitives as exact
  float sequences. Only two of the nine were reachable from the suite before; both flipped quads,
  both upside-down variants and the float-precision triangle had **no** coverage, so a transposed
  pair would have shipped a mirrored sprite with every test green. Expected values transcribed
  from the previous implementations and cross-checked by running the test against them.
- `CoordsBufferAppendConcatenates` — the batching path.

## What the numbers actually say

Live profiler output, in-game, idle, Apple silicon, Metal backend:

```text
1194 frames over 5004 ms (238.6 fps)
zone                         ms/frame  calls/frame   total ms
frame: draw                    3.9967          1.0     4772.1
frame: backend render          3.9848          1.0     4757.9
frame:   gpu present/wait      3.7620          1.0     4491.8
main: poll                     0.1950          1.0      232.8
map: drawFloor                 0.1519          0.5      181.4
frame:   encode                0.1495          1.0      178.5
map: drawLights                0.1264          0.5      150.9
ui:  traversal                 0.0842          0.1      100.6
pool: release                  0.0359          2.2       42.9
pool: compile                  0.0305          1.9       36.4
frame: assemble                0.0065          1.0        7.7
map: preLoad                   0.0045          0.5        5.3
map: drawCreatureInfo          0.0038          0.5        4.6
map: updateVisibleTiles        0.0012          0.0        1.4
frame: swapBuffers             0.0003          1.0        0.3
```

Three things to take from this:

1. **The frame is a wait, not a computation.** 3.76 of 4.00 ms sits in `nextDrawable`. Removing
   CPU work cannot show up in frame time until that changes.
2. **`calls/frame` matters as much as the timing.** The UI traverses ~0.1 times per rendered
   frame and the map draws ~0.5 times. Totals alone hide that completely, and reading a total
   without it is what produced the wrong ranking earlier.
3. **The producer is cheap now.** Release + compile together are ~0.066 ms/frame. The two
   measured optimisations did their job; there is little left there to win.

**Caveat that limits all of the above:** this is one scene — one character, standing still, one
machine, one backend. A crowded hunt has not been captured. That is the next measurement, and
it may well reorder this again.

## Claims this work falsified

Recorded because each cost real time and would otherwise be re-derived.

- **`-O1` is not the problem.** `CMakePresets.json` pins `-O1 -DNDEBUG` for the macOS presets and
  has since the initial commit. A full `-O3` control build (clean, and the binary is 220 KB
  *smaller*) measured inside the noise on the producer path: 0.0609 vs 0.0617 ms to build the
  list, 0.1230 vs 0.1235 including compile, across three alternating runs. The path is bound by
  `memmove` calls and a dependent hash chain; there is nothing for `-O3` to win. The same harness
  detected the content-hash change immediately, so it is not blind. Raising it to `-O2` is free
  but should not be expected to move the frame.
- **The synthetic benchmark over-weighted the compiler.** It drove a 2,600-quad map pool and no
  UI, so the compile step looked like ~50% of producer time. Against the live client it is 2.4%
  of CPU work and under 1% of the frame.
- **A `sample(1)` reading is not a frame budget.** It said UI traversal was 54% of CPU work. True,
  and misleading — the pie it was 54% of is ~0.6 ms out of a 4 ms frame.

## The UI dead end

An eighth change — a UI traversal throttle, `graphics.uiTraversalInterval` — was built, measured
to do **nothing**, and removed. Do not rebuild it without first fixing what is below.

Instrumented in the running client it skipped **0%** of traversals: `dirty=95 timer=0 skipped=0`,
in every steady-state window. The config really was live, verified by setting
`renderBackend = opengl` (which a Cocoa build cannot provide) and watching it log the rejection.

It never fires because something marks the tree dirty every tick. Counting `UIWidget::repaint()`
callers by `std::source_location` found, in **steady state** (not the startup burst, which is
~50× larger and misled an earlier reading of this same data):

| Source | Calls / 5 s |
| --- | --- |
| the atlas-region hack in `drawText` (`uiwidgettext.cpp:320` then, `:339` now) | ~370 |
| `uitextedit.cpp:690` — end of `UITextEdit`'s update | ~95 |
| `uiwidget.cpp:1940` — `onGeometryChange` | ~12 |
| `uiwidget.cpp:1924` — `applyStyle` | ~5 |

`e76b505d` fixed the top one. `Texture::getAtlasRegion()` is derived from whichever pool is
currently selected and returns null when the region is disabled — neither observable by the
per-widget `m_atlasRegion` cache — so it flips for a handful of widgets every frame, and each
flip called `updateText()`, which ends in `repaint()`. Splitting `rebuildTextLayout()` out
removes the repaint while keeping the (genuinely necessary) coordinate rebuild.

**It did not unblock the throttle.** `uitextedit.cpp:690` runs at almost exactly the traversal
rate and keeps the tree just as dirty; behind that there is another. This is not a bug list to
work through — `setRect` and `updateState` both guard correctly and the changes that fire are
real. The UI's model is "any touch repaints everything", and several subsystems touch widgets
every frame legitimately.

Making the traversal skippable therefore needs an **invalidation refactor**, not a fix:
per-widget dirty regions, or a `repaint()` that marks only its own subtree instead of forcing the
whole pool. Given the frame budget above, that work is currently **not** justified — it targets
0.084 ms/frame.

## Running a profiling session

No rebuild required. Either put this in `config.ini`:

```ini
[debug]
profile = 1
profileIntervalMs = 5000
```

or toggle it live from the console, which is better for a hunt because the capture can start once
the action does:

```lua
g_profiler.setEnabled(true)    -- clears counters, starts a fresh capture
g_profiler.report()            -- print now, keep capturing
g_profiler.setEnabled(false)   -- print a final report and stop
```

Reports go to the client log every interval and each window stands alone (counters reset after
every report), so a capture never blends two scenes.

Design note, in case extending it: the zone set is **closed** and indexed by enum rather than
hashed by name. That is what buys an accumulator that is a plain array slot in thread-local
storage — no allocation, no lock, no string work on the sampled path — which is what makes it
safe to leave on for a whole session. The `Stats`/`AUTO_STAT` system next door takes arbitrary
string descriptions, heap-allocates a `Stat` per call and takes a process-wide mutex; that is
why it ships compiled out, and why it was not reused here. Adding a zone means adding an
enumerator *and* a name — a `static_assert` enforces the pair.

## Measurement pitfalls hit during this work

All three produced wrong numbers that were reported before being caught. Worth reading before
trusting any capture.

- **Window occlusion.** macOS stops delivering drawables to a background `CAMetalLayer`, so an
  occluded client stops rendering entirely and drops to ~4% CPU. An A/B comparison taken this way
  compares two idle processes. Keep the client window visible, and check `frame: gpu present/wait`
  is non-trivial before believing a capture.
- **Startup versus steady state.** The first few windows after launch are module loading and UI
  construction, and can be ~50× the steady-state rate. Always read the later windows.
- **`sed -i.bak` preserves the original mtime.** Restoring a file from the `.bak` leaves it older
  than the object built from it, so ninja skips the rebuild and the binary silently keeps the old
  code while the source looks correct. `touch` after any such restore.

## Open questions

- **Why 240 fps, and which counter caps it?** In `AdaptativeFrameCounter::update()` the expression
  `m_targetFps == 0 ? m_maxFps : clamp(m_targetFps, 1, max(m_maxFps, m_targetFps))` collapses to
  just `m_targetFps` whenever it is non-zero, because the upper bound is always at least that —
  so `setMaxFps(0)` ("No Frame Rate Limit") cannot lift the cap while `m_targetFps` is non-zero,
  and it defaults to `60u`. The literal `240` at `graphicalapplication.cpp:168` and `:222` is set
  on `m_mapProcessFrameCounter`, the **producer**, not the render loop — so confirm which counter
  is actually capping before changing a constant. *(Owner: user, in progress. A parallel agent is
  editing the same two files for FPS reporting accuracy.)*
- **A crowded hunt capture.** Everything above is one idle scene. The ranking may invert under
  load; `calls/frame` will show whether the producer keeps up.
- **Is the present wait vsync or GPU saturation?** 3.76 ms/frame ≈ 266 Hz. If the client is
  spinning uncapped against the display rather than pacing, that is where battery and thermals go
  — and it is a policy question, not an optimisation.
- **Low-end hardware is entirely unprofiled.** It may not even be CPU-bound. Do not plan work for
  it from this document's numbers.

## Things checked and cleared

Recorded so they are not re-audited.

- `AUTO_STAT` is compiled out by default; the macro does not evaluate its arguments.
- The map thread is throttled twice over — `canDrawMap` blocks until the renderer consumes, and
  the frame counter sleeps to a 2× ceiling.
- Garbage collection is incremental (500 thing types per 2 s sweep).
- The Metal buffer ring is properly triple-buffered with a semaphore and doubling growth.
- `stdext::map`/`set` are `phmap` flat hash tables, not `std::unordered_map`.
- `setRect` and `updateState` both return early when nothing changed.
