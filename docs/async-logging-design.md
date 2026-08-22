# Asynchronous Logging: Design Notes and Evidence Plan

**Status:** Investigation (pre-implementation)
**Date:** 2026-08-22
**Scope:** `src/framework/core/logger.{h,cpp}` — why `g_logger` is currently unsafe to call from the frame path, what an asynchronous logger would look like, and what has to be measured before one is built.
**Origin:** `70714b6` (`perf(sound): comment out the tracing that stalls the map thread`), which disabled the item-ambient tracing added in `a29c291` after it was observed costing roughly 8x frame rate.

## 0. What is established, and what is only reasoning

This section exists because the rest of the document is easy to mistake for a finding. Most of it is not.

**Established by observation:**

- On the `macos-cocoa` build (arm64, Release + LTO, `vsync: false`, window maximized), the client ran **below 100 fps** with `CRYSTALOTC_SOUND_DEBUG=1` armed and **~800 fps** with the trace calls commented out. Same machine, same scene, same build otherwise.
- The traced session wrote 3104 `[snd]` lines to `crystalotc.log`.
- Tracing was armed by an environment variable exported in an interactive shell, not by a default. `m_soundDebug` defaults to false.
- Two hypotheses were **falsified** before this one: shrinking the game window and lowering the antialiasing mode (which together move the map framebuffer between 1x and 4x its linear resolution) changed the frame rate not at all. The map fill rate introduced in `da96cd8` is not the regression.

**Not established — reasoning only:**

- *Which* term inside `Logger::log` dominates. The ranking in §3 is suspicion, not measurement.
- The actual line rate per second during play. 3104 lines over a session says nothing about the peak.
- Whether stdout being attached to a terminal is the dominant term. This is the current best guess and it is untested.

The conclusion "the tracing was expensive" is solid. The explanation "because of X" is not. Everything below §3 is written to be checked, not believed.

## 1. What `Logger::log` does today

Every call, in order (`src/framework/core/logger.cpp:44-99`):

| Step | Line | Work |
|---|---|---|
| Thread guard | `:57-62` | If not on the event thread, repost onto `g_dispatcher` and return |
| Prefix + copy | `:68-69` | Build `outmsg` from the level prefix and the message |
| stdout | `:71` | `std::cout << outmsg << std::endl` — **writes and flushes** |
| File | `:74-75` | `m_outFile << outmsg << std::endl` (writes and flushes) then `m_outFile.flush()` again |
| History | `:79-81` | Copy the string into `m_logMessages`, a deque capped at `MAX_LOG_HISTORY` = 1000 (`logger.h:42`) |
| Lua callback | `:83-89` | `g_dispatcher.addEvent` with `outmsg` **captured by value** — another copy — later invoking `m_onLog` |
| Fatal | `:91-98` | `displayFatalError`, then `exit(-1)` |

Two things to notice.

`std::endl` is not a newline. It is a newline *plus a flush*. An `ofstream` normally batches into an internal buffer and issues one `write()` syscall per few kilobytes; `std::endl` forces one syscall per line. The explicit `m_outFile.flush()` on `:75` then flushes a buffer that is already empty — harmless, but it shows the intent was "get this to disk now", which is what defeats the buffering.

There is **no mutex anywhere in `Logger`**. Today that is safe only because of the thread guard on `:57` — every log body is funnelled onto one thread. Any redesign has to preserve that property for `m_logMessages` and `m_onLog` explicitly rather than by accident.

## 2. Why this lands on the frame path

The guard on `:57` reposts calls made from a non-event thread, so logging is normally *already* off the hot path.

But `src/framework/core/graphicalapplication.cpp:223` sets `g_eventThreadId` **to the map thread itself**:

```cpp
const auto& mapThread = g_asyncDispatcher.submit_task([this] {
    g_luaThreadId = g_eventThreadId = stdext::getThreadId();
```

The map thread is the thread that runs `preLoad()` (`:244`) and builds the MAP draw pool (`:257`) — it feeds draw work to the renderer. When `MapView::updateItemAmbientSounds` logged from inside `preLoad`, the guard saw "already on the event thread", skipped the hop, and ran the whole body — syscalls included — inline on the thread the frame rate depends on.

So the defect is not that the logger is slow in the abstract. It is that **the one mechanism protecting hot threads from it does not fire for the hottest thread in the client.**

## 3. Cost candidates, ranked by suspicion — all unverified

| # | Term | Line | Why suspected | Falsified by |
|---|---|---|---|---|
| 1 | `std::cout` flush to a **tty** | `:71` | The client was launched from a shell (that is how the env var got set), so stdout was a terminal. A terminal must lay out and render every line; writing hundreds of lines/sec to a visible one throttles the writer hard, and the stall lands on the map thread. Logging to a file is far cheaper than logging to a tty. | E2 |
| 2 | Per-line file flush | `:74-75` | One `write()` syscall per line instead of per ~4KB. Real, but a non-fsync flush is ~1-3µs; the arithmetic does not obviously reach 8x on its own. | E3 |
| 3 | `g_dispatcher.addEvent` per line | `:85` | A string copy, a `std::function` allocation, and a dispatcher-queue push per line — then the event runs and crosses into Lua. | E4 |
| 4 | History deque | `:79-81` | A second string copy plus a `pop_front` once past 1000 entries. Cheapest of the four. | E4 |

**Explicitly ruled out:** the Lua terminal handler. `modules/client_terminal/terminal.lua:262` (`addLine`) only does a `gsub` and a `table.insert`, and schedules real widget work *solely when the terminal window is visible* (`:270`). With the terminal closed — the normal case — the Lua side is cheap. This was checked, not assumed.

## 4. Evidence plan

Ordered cheapest-first. E1 alone may settle it.

**Prerequisite for every experiment below.** The tracing that produces the load was
commented out in `70714b6`, and the `CRYSTALOTC_SOUND_DEBUG` arm along with it, so none
of this reproduces on a stock checkout. Restore it first:

```bash
grep -rn "\[snd-trace\] disabled" src modules   # the five restore points
# uncomment them, then: cmake --build build/macos-cocoa -j8
```

Any experiment that needs the load must state whether it ran against a restored build or
a synthetic one (E5), because a stock build produces zero `[snd]` lines and will look
perfectly healthy.

### E1 — Sampling profiler (no code change, no perturbation)

`sample` and `xctrace` are both present on this machine.

```bash
# Reproduce with tracing armed, then while it is running:
sample $(pgrep -f CrystalOTC.app) 10 -f /tmp/traced.sample
# Look for the map thread's stack: how much of its time sits under
# Logger::log, and under which callee - write(), the dispatcher, or Lua.
```

Take one sample with tracing armed and one without, on the same scene, and diff the map thread's self-time distribution. This is the single highest-value experiment: it answers §3 directly instead of ranking guesses.

**Trap to avoid:** do *not* reach for the built-in `AUTO_STAT` instrumentation for this. `ENABLE_STATS` is never defined anywhere in the build, so every `AUTO_STAT` compiles to `((void)0)` today — and `src/framework/util/stats.h:158-163` documents *why* it was disabled: the stats system contends on a single mutex thousands of times a second between the main thread and the map thread. Turning it on to measure a map-thread stall would perturb the exact thing being measured.

### E2 — Is it the terminal? (isolates candidate 1)

Same build, tracing armed, same scene, three launches:

```bash
# a) stdout to a visible terminal
CRYSTALOTC_SOUND_DEBUG=1 build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC
# b) stdout discarded
CRYSTALOTC_SOUND_DEBUG=1 build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC > /dev/null
# c) no tty at all
open build/macos-cocoa/bin/CrystalOTC.app   # then arm with Ctrl+Shift+S (restored build only)
```

If (b) and (c) recover most of the frame rate and (a) does not, candidate 1 is the answer and the fix is mostly about stdout, not the file.

### E3 — Is it the disk flush? (isolates candidate 2)

Patch `:74-75` to `m_outFile << outmsg << '\n';` with no flush, rebuild, rerun (a) from E2. Any recovery is attributable to the file flush specifically.

### E4 — What is the actual line rate?

Add a counter incremented in `Logger::log` and dumped once a second, or post-process a timestamped run. Needed to turn any per-line microbenchmark into a per-frame cost. Without this number, every estimate in §3 is unanchored — this is the single most useful missing datum after E1.

### E5 — Synthetic bound

A standalone harness that calls the current `Logger::log` N times against (i) a tty, (ii) `/dev/null`, (iii) a file, and reports ns/line. Gives a clean per-line cost to multiply by E4's rate, and a baseline to prove any redesign actually helped.

**Definition of done for the investigation:** E1 + E4 produce a sentence of the form "at N lines/sec, `Logger::log` consumed X ms/sec of map-thread time, of which Y% was <term>." Until that sentence can be written with real numbers, §3 stays a ranking of guesses.

## 5. Design sketch — asynchronous logger

Only worth building if §4 shows the cost is in the I/O rather than somewhere unexpected. Recorded now so the reasoning is not lost.

### Goals

1. A `g_logger` call from any thread costs a format, a move, and an enqueue — no syscall, no Lua, no unbounded work.
2. Delete the special case: the thread guard on `:57` becomes unnecessary, because no thread is privileged any more.
3. Crash safety is not reduced. A log whose last lines are missing after a crash is worse than a slow log.
4. Line ordering is preserved globally, not per-thread.

### Non-goals

- Changing the `g_logger.info(...)`/`fmt` call sites or the Lua binding surface.
- Structured logging, levels-per-sink, log rotation.
- Making `Logger` allocation-free. A per-line string allocation is fine; a syscall is not.

### Structure

```
any thread                       writer thread (new, single)
  g_logger.info(...)
    format -> std::string
    enqueue {level, msg, when}  ->  [bounded queue]  ->  pop
                                                          std::cout << msg << '\n'
                                                          m_outFile  << msg << '\n'
                                                          flush if level >= LogWarning
                                                          (periodic flush otherwise)
```

### Constraints that fall out of the current code

- **The Lua callback cannot move to the writer thread.** `m_onLog` runs Lua (`terminal.lua:20`), which must run on the Lua thread. It has to keep going through `g_dispatcher.addEvent` exactly as it does on `:85` — which is already called from arbitrary threads on `:58`, so the dispatcher is safe for this. The enqueue and the dispatch are two separate fan-outs from the producer.
- **`m_logMessages` needs an owner.** Today it is single-threaded by accident (`:79`). Either move it behind the writer thread, or guard it. `fireOldMessages()` (`:126-133`) reads it from the event thread at module init, so a plain "writer thread owns it" answer needs a way to serve that read.
- **The fatal path must stay synchronous.** `:91-98` calls `exit(-1)`. It has to drain the queue and flush both sinks *before* exiting, or the fatal error is the one line guaranteed to be lost.
- **Shutdown must drain.** `g_eventThreadId` is reset at `graphicalapplication.cpp:356`; the writer thread needs a matching join with a drain, or the tail of every session disappears.

### Backpressure policy

A bounded queue with **drop-oldest and a counter**, never block the producer. When lines are dropped, emit one `... N lines dropped ...` marker so the gap is visible rather than silent. Blocking a producer reintroduces exactly the stall this design exists to remove; an unbounded queue turns a log storm into a memory leak.

### Interim alternative, if async is too much

Roughly five lines, and it keeps the crash-safety property where it matters:

```cpp
std::cout << outmsg << '\n';

if (m_outFile.good()) {
    m_outFile << outmsg << '\n';

    // Anything signalling trouble hits the disk now, because the next thing
    // that happens may be the crash. Routine lines ride the stream's buffer.
    if (level >= Fw::LogWarning) {
        std::cout.flush();
        m_outFile.flush();
    }
}
```

Plus an explicit flush on shutdown. The tradeoff accepted: a hard crash loses the last few buffered `info` lines. Note this does **nothing** for candidates 1, 3 or 4 — if E1/E2 point at the tty or the dispatcher, this change will not move the number.

## 6. Open questions

1. Does the Windows/Vulkan path or the Android `__android_log_print` on `:68` have its own constraints on where the write happens?
2. Is anything relying on log lines being on disk *synchronously* — a crash reporter, a test harness reading `crystalotc.log`, the `render-baselines` tooling?
3. `logFunc` (`:101-124`) builds a Lua traceback before logging. It has the same thread guard and the same exposure; does it need the same treatment, or is it rare enough to leave?
4. Should `std::cout` remain a sink at all in a release build, given a tty is the suspected dominant cost?

## 7. References

- `src/framework/core/logger.cpp`, `src/framework/core/logger.h`
- `src/framework/core/graphicalapplication.cpp:223` (event thread == map thread), `:244` (`preLoad`)
- `src/framework/util/stats.h:158-163` (why `AUTO_STAT` is disabled)
- `modules/client_terminal/terminal.lua:20` (`onLog`), `:262` (`addLine`)
- `70714b6` — disabled the sound tracing; `grep -rn "\[snd-trace\] disabled" src modules` restores it
- `a29c291` — added the tracing being discussed
