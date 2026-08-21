# Phase 1 renderer handoff

**Checkpoint:** `9396b71` on `main` (pushed to `origin`, the fork `aacruzgon/CrystalOTC`)

**Date:** 2026-08-20

**Scope:** Phase 1 — native macOS platform layer (Cocoa + `CAMetalLayer`)

## Current state

macOS has a native window. `CrystalOTC.app` opens an AppKit window, translates input,
resizes, presents a Metal frame, and launches from Finder — with no XQuartz installed and
no X11 linked. It is opt-in behind `TOGGLE_COCOA_WINDOW`, **default OFF**, because XQuartz
remains the OpenGL reference vehicle every Phase 0 baseline is captured through and the
Cocoa window deliberately provides no GL context.

At this checkpoint:

- `Build - macOS (Cocoa)` is green — run `32411659041`, 17/17 steps on `macos-15` /
  arm64 / macOS 15.7.7 / Xcode 16.4 / SDK 15.5.
- `Build - Windows` is green ~~for the full change set~~ at `7c16224` — run `32411659030`.
  **Corrected 2026-08-21:** no CI ran on the checkpoint commit `9396b71` itself; `fdfb833`
  and `9396b71` are macOS-only changes, the arm64 pin was verified locally with
  `lipo -archs`, and the Windows run at `0535c96` was cancelled. Phase 2's run
  `32440663105` at `b8458df` has since covered all of it, green, 54/54.
- `Renderer baseline - Linux llvmpipe` is green — run `32411659065`.
- `ctest` passes 22/22 on both the local XQuartz build and the macOS runner.
- Six baseline scenes recapture at 0 differing pixels after every shared-code change.

## Phase 1 checklist

Against the implementation plan's Phase 1 tasks:

- [x] **`CocoaWindow` implementing the `PlatformWindow` contract.** 1193 lines across
      `cocoawindow.h`/`.mm`. The AppKit loop is reconciled by *pumping, not running*:
      `[NSApp finishLaunching]` instead of `[NSApp run]`, and `internalPumpEvents` drains
      `nextEventMatchingMask` against `distantPast` on every `poll()`, so the client keeps
      owning its loop.
- [x] **Layer-backed view, drawable size, backing-scale changes** — with the points/pixels
      polarity *inverted* from the task wording; see "Decisions that were not free" below.
- [x] **Platform selection, and the Apple X11 dependency dropped** — fully, including the
      link, not just the gating.
- [x] **Build system**: `enable_language(OBJCXX)`, `MACOSX_BUNDLE`, `Info.plist` template,
      resources in `Contents/Resources`, and a macOS CI job.
- [x] **Clear-colour proof** via `nextDrawable` → clear pass → present.
- [x] **Draw-path tolerance for a GL-less window** — not in the original task list, and
      required before the clear-colour proof could run at all.

Against the exit gate — **met**, every criterion evidenced:

- [x] Native window opens with no `DISPLAY` and no XQuartz; window server reports a window
      titled `CrystalOTC`.
- [x] Clear colour presents: content samples `(16,26,62)` against a `(0.05,0.10,0.25)` clear.
- [x] Resize works and tracks backing scale: 510→900 points, after which the content
      measures **exactly 1800 px** = 900 × 2.
- [x] Input works — keyboard, mouse, text, scroll, modifiers, and both quit routes.
- [x] `CrystalOTC.app` launches via `open`, the way Finder does, from a neutral working
      directory.

## Decisions that were not free

**`m_size` is in backing pixels; `m_displayDensity` is the backing scale factor.** Two
independent analyses disagreed on this, so it was settled from source: `AndroidWindow`'s
`updateDisplayDensityFromSystem` sets `m_displayDensity` from the *system* screen density,
`m_size` is the raw surface size, and `Painter` feeds `getSize()` straight to `glViewport`.
`GraphicalApplication::resize` then lays the UI out at `m_size / m_displayDensity`. Getting
this backwards would have silently multiplied the HUD scale on every Retina Mac.

**A caveat the design must not inherit silently:** `g_app.setHUDScale` writes that *same*
variable, so device pixel ratio and user HUD scale are conflated framework-wide.
`m_backingScale` is mirrored separately as the drawable's true sizing source. Separating
them is a framework change, not a backend one.

**`hasGLContext()` returns false.** This reuses the escape hatch the Windows Vulkan path
established rather than special-casing macOS, which is why the whole GL stack
short-circuits with no new branching in `Graphics`, `Painter`, `Texture` or `Shader`.

**The window presents its own frames.** `swapBuffers` does acquire/clear/present and the
`CAMetalLayer` never leaves `CocoaWindowImpl`. That leaves presentation ownership genuinely
contested with `IRenderBackend::render`'s "present" clause — a Phase 4 decision, recorded in
the design document so it is not discovered late.

## Traps worth not rediscovering

Each of these cost real time and none is guessable from the code.

**`OPENGL_USE_APPLE_X11=OFF` is not the way to unlink X11.** It looks like the fix; it sets
`-framework AGL`, and AGL was removed from the macOS SDK years ago. The working approach is
to bypass `find_package(OpenGL)` for the Cocoa build entirely and point `OPENGL_LIBRARIES`
at Apple's `OpenGL.framework`.

**PhysicsFS reports the `.app` directory as the base dir**, not `Contents/MacOS` where the
binary actually lives. So the bundle resource candidate is
`getBaseDir() + "Contents/Resources/"`, not `../Resources/`. The obvious guess resolves to
`bin/Resources/` and the bundle silently cannot find its data.

**`MacTypes.h` defines `Size`, `Point` and `Rect` at global scope** and so does the
framework. No include order resolves it and the SDK has no opt-out, so Apple's spellings are
renamed for the duration of the Apple includes. AppKit's umbrella also drags in `NSOpenGL.h`,
whose `GLhandleARB` disagrees with glew's — suppressed through Apple's own `__gl_h_` guards,
since this translation unit wants no OpenGL.

**Correction 2026-08-21 (Phase 2, `c8050f5`):** those guards are *not* sufficient on their
own. `OpenGL.h`, `CGLDevice.h` and `CGLIOSurface.h` are not covered by
`__gl_h_`/`__gltypes_h_` and they use `GLint`/`GLenum`/`GLsizei`/`GLuint`; glew was
supplying those types for free through `platformwindow.h` → `declarations.h`. When
`fa8656d` dropped `glutil.h` from `declarations.h`, the Cocoa build stopped compiling with
15 `unknown type name 'GLint'`/`'GLenum'` errors from inside Apple's own headers (run
`32432243243`). `cocoawindow.mm` now includes `framework/graphics/glutil.h` explicitly and
first (`cocoawindow.mm:48`).

**`PlatformWindow` declares no destructor**, so `~CocoaWindow()` cannot be an `override`.

**System Events' accessibility `click at` never reaches a custom `NSView`.** The mouse path
looks dead until a real `CGEvent` is posted. The first click test produced no output for
exactly this reason.

**An unset `CMAKE_OSX_DEPLOYMENT_TARGET` interpolates to an empty string** in the plist —
a bundle that passes `plutil -lint` while declaring no minimum OS. And a plain cache `set`
does not fix it: CMake pre-creates the variable as an empty cache entry on Apple, so `FORCE`
is required. Both defaults now live ahead of target creation, or the flags and the plist
would disagree.

## Bugs found, and how

Three defects surfaced, none by reading the code.

**Two latent GL calls on the "no GL context" path** (`67f9b38`), found by backtrace after
linking Apple's `OpenGL.framework` turned them from silent into fatal. `Painter::Painter`
calls `setResolution` — which ends in `glViewport` — *before* its own `hasGLContext()`
guard, with a comment claiming it makes no GL call sitting three lines below one.
`Texture::create` reached `glGenTextures` unguarded although the constructor a hundred lines
above already returned early for the same case. XQuartz's libGL tolerates calls with no
current context; Apple's segfaults.

**These matter beyond macOS.** The shipped Windows Vulkan path also reports
`hasGLContext() == false` and runs the same two functions, so it had been relying on the
same luck. This is the migration's first Windows-affecting *behaviour* change, and it is
**unvalidated at runtime** — the Windows compile gate is green, but no local or CI check on
this plan can reach it. ~~Carry it into the next tester validation.~~ **Superseded
2026-08-21 (owner decision):** Windows Vulkan runtime validation is deferred
**indefinitely**, until a Windows machine is available. The change stays unvalidated at
runtime by choice — it is parked, not outstanding, and must not be listed as pending or as
gating anything.

**Modifier keys latched on permanently** (`fdfb833`), found by driving real `CGEvent`s at
one of the three input paths the exit gate had recorded as implemented but unexercised.
`handleFlagsChanged` compared against `isKeyPressed()`, which reads false for modifier keys
forever because `processKeyDown`/`processKeyUp` return early before touching `m_keyInfo`.
Every release looked like "no change", so after one press each of Shift, Control and Command
the client believed all three were held for the rest of the session — and text input stayed
suppressed, since it declines to emit while Ctrl or Alt is set. Fixed by tracking the
previous mask.

The fix also confirmed both halves of the `__APPLE__` mapping empirically: Command is what
sets `KeyboardAltModifier` (`0x100008` → `2`), and Option deliberately sets nothing
(`0x80020` → `0`).

## Owner decisions recorded 2026-08-20

- **Decision 5 resolved: Apple Silicon only, no universal binary.** Pinned as
  `CMAKE_OSX_ARCHITECTURES=arm64` for the Cocoa build and verified with `lipo -archs`.
  Previously unset, so it resolved to the build host by accident.
- **Branch protection deliberately absent** while the repository has a single contributor.
  No CI job is a *required* check and none can be until protection is enabled; every job
  gates by failing loudly rather than by blocking a merge. The macOS job is the one to
  promote first.
- **The Windows Vulkan behaviour change is acknowledged and accepted**, ~~to be exercised at
  the next tester validation~~. **Superseded 2026-08-21:** the owner deferred Windows Vulkan
  runtime validation indefinitely, until a Windows machine is available. Accepted and
  unvalidated; nothing is owed.

Decisions 6 (macOS 14 minimum) and 7 (no notarization in the first milestone) remain
assumptions, though 6 now has a concrete expression as the committed deployment-target
default.

## Deferred follow-ups

None block Phase 2, which needs no macOS at all.

**vcpkg deployment-target skew.** vcpkg builds its ports against the host SDK while the
bundle links at 14.0, so every link emits `ld: warning: object file … was built for newer
'macOS' version (X) than being linked (14.0)` — 5,124 of them on the runner. It is a warning
class, not a gap: the same configuration links, tests 22/22 and runs. Closed by pinning
`VCPKG_OSX_DEPLOYMENT_TARGET` to match, when someone wants a quiet log.

**Resources are symlinked, not staged.** `data/` alone is ~776 MB and a per-build copy would
dominate the edit/run loop, so this is a bundle that runs rather than one that ships. Real
staged copies, embedded dylibs, rpaths, signing and notarization are Phase 7.

**The macOS CI job cannot exercise input or presentation.** A hosted runner has no window
server, so it never delivers an event or presents a frame. Keyboard, mouse, text, scroll,
modifiers, resize and the clear-colour proof are all local-only evidence.

**Documentation citation drift.** The documents carry 147 line-anchored citations, 17 of
them into `src/CMakeLists.txt`, which six commits touched in a single day. Two audits were
needed in one day and several corrections from the first were falsified within hours. A
range check does not catch it — a citation can stay in range while pointing at unrelated
code. Citing actively-edited files by symbol rather than line is the standing suggestion.

## Reproduction commands

Default (XQuartz) build — unchanged, still the baseline reference vehicle:

```sh
cmake --preset macos-release -DTOGGLE_BIN_FOLDER=ON
cmake --build --preset macos-release --parallel 8
ctest --test-dir build/macos-release --output-on-failure
```

Cocoa build and bundle:

```sh
cmake --preset macos-release -DTOGGLE_COCOA_WINDOW=ON
cmake --build --preset macos-release --parallel 8
open build/macos-release/bin/CrystalOTC.app
```

The bundle also runs directly, and does so from any working directory:

```sh
build/macos-release/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC
```

Assert the X11 unlink locally, the same way CI does:

```sh
otool -L build/macos-release/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC \
  | grep -iE "/opt/X11|libX11|libXext|libGLU" && echo "REGRESSED" || echo "clean"
```

Driving synthetic input requires real `CGEvent`s — System Events' accessibility clicks do
not reach the view. `python3` with `Quartz` (pyobjc) is sufficient; see `fdfb833` for the
measurements taken that way.

## Commit ledger

Oldest first, regenerated from `git log --format='%h %s' --reverse d7e9057..HEAD` at
`9396b71`. `d7e9057` is the Phase 0 audit checkpoint this phase started from.

```text
6c928f6 feat(graphics): let the draw path tolerate a window with no GL context
0082719 feat(macos): add the native Cocoa/Metal platform window
797a852 feat(macos): build CrystalOTC.app and let it find its resources
e34e2aa fix(macos): give the app bundle a real minimum system version
8f999ed docs(renderer): correct the Phase 1 claims the implementation falsified
8b3af3c docs(renderer): record that Phase 1 input is verified, not assumed
67f9b38 fix(graphics): stop the GL-less path from calling into GL
9fcf605 feat(macos): stop the Cocoa build from linking X11
7c16224 ci(macos): add a macOS build, test and smoke-launch job
cd617a7 docs(renderer): correct the Phase 1 claims that shipped after the last audit
fdfb833 fix(macos): stop Cocoa modifier keys from latching on
0535c96 docs(renderer): record that the last three input paths were exercised
9396b71 feat(macos): pin the Cocoa build to Apple Silicon
```

## What Phase 2 inherits

Phase 2 (the renderer boundary: `PoolCompiler`, `RenderFrame`, `RecordingBackend`) needs no
macOS and can start immediately. Three things from this phase bear on it:

- `DrawPoolManager::consumeAll` exists and is the backend-neutral form of the obligation a
  frame-producing backend owes the map thread. The `FrameAssembler` inherits it: a frame it
  declines to render must still swap and clear the pool flags, or the map thread blocks
  permanently in `canDrawMap`.
- `RenderFrame::drawableSize` and `IRenderBackend::resize` are already in the right unit,
  because the platform layer reports backing pixels.
- ~~Presentation ownership is unresolved between the window and `IRenderBackend::render`.
  Phase 4 must choose; Phase 2 should not assume either.~~ **Chosen 2026-08-21 (Phase 4):**
  the backend presents. A drawable may only be presented by the command buffer that rendered
  into it, so a backend that acquires one has to; `PlatformWindow::setPresentationOwned` is how
  it says so, and `CocoaWindow::swapBuffers` stands down while the claim holds.
