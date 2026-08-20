# macOS Metal Renderer — Implementation Plan

**Status:** Implementation plan — Phase 0 complete; Phase 1 delivered 2026-08-20 (opt-in, `TOGGLE_COCOA_WINDOW` defaults OFF; native window, app bundle, no X11 link, green macOS CI), with only the architecture decision of task 4 outstanding; Phases 2–7 not started
**Date:** 2026-08-19 (last revised 2026-08-20)
**Companions:**
- `docs/macos-rendering-architecture.md` — options analysis, target-architecture rationale, full external-reference catalog
- `docs/metal-parity-survey.md` — as-built inventories; cited as `[S n.n]`
- `docs/renderer-architecture-design.md` — target structures; cited as `[D §n]`
- `docs/phase-0-renderer-handoff.md` — Phase 0 outcome, checklist against this plan, deferred follow-ups
- `docs/rendering-baselines/` — `scenes.json` (the scene manifest), the checked-in llvmpipe references, and `known-deviations.md`

**Chosen path:** Cocoa + direct Metal with **full OpenGL visual parity**, via the backend-neutral `RenderFrame` architecture `[D §1]`. MoltenVK and ANGLE are not on this path (see Decision log); the Windows Vulkan feeder path keeps working unmodified throughout `[D §1.1]`.

---

## Decision log

Resolutions of the companion doc's "Decision points to resolve before implementation":

| # | Question | Resolution |
|---|---|---|
| 1 | Visual baseline: Vulkan or full OpenGL output? | **Full OpenGL** — that is what this plan delivers |
| 2 | MoltenVK as shipped dependency? | **No** (not on this path; remains a documented fallback option) |
| 3 | ANGLE as fallback/primary? | **No** |
| 4 | Must runtime/module GLSL work on macOS? | **Repo-shipped `.frag` set: yes**, via build-time GLSL→SPIR-V→MSL. `createFragmentShaderFromCode`: GL-only, logged fallback on Metal `[S 5.5-5.6]` `[D §5.1]` |
| 5 | Apple Silicon vs Intel/universal | **Assumption: Apple Silicon first**, universal build deferred to Phase 7 evaluation — *confirm* |
| 6 | Minimum macOS version | **Assumption: macOS 14** (keeps Metal API surface modern, still covers ~3 hardware generations) — *confirm* |
| 7 | Notarized distribution in first milestone? | **No** — developer-machine builds until Phase 7 — *confirm* |
| 8 | Renderer interface also for Android/WASM? | Designed not to preclude it; desktop backends only in this plan |

Items marked *confirm* are assumptions, not blockers; they affect only deployment-target flags and Phase 7 scope.

**Correction 2026-08-20 (Phase 1):** none of 5, 6 or 7 was settled by Phase 1, and the deployment-target half of that sentence nearly became a live hazard. `CMAKE_OSX_DEPLOYMENT_TARGET` is *consumed* by `cmake/macos/Info.plist.in` for `LSMinimumSystemVersion`, but was initially set nowhere committed — so the verified `LSMinimumSystemVersion 14.0` came from a command-line `-D`, and any configure without it would have written an **empty string** into the plist: a bundle that passes `plutil -lint` while declaring no minimum OS at all. `src/CMakeLists.txt` now defaults it to 14.0 for the Cocoa build, ahead of target creation so the compile and link flags agree with the plist, and with `FORCE` because CMake pre-creates the variable as an empty cache entry on Apple and a plain cache `set` is a silent no-op there. An explicit `-D` still wins. The default is deliberately scoped to `TOGGLE_COCOA_WINDOW`: deployment target changes codegen for every target, and the XQuartz build is the vehicle the renderer baselines are captured with. Decision 6 therefore has a concrete expression in the repository but remains an assumption. `CMAKE_OSX_ARCHITECTURES` is still unset anywhere committed, so **Decision 5 resolves to whatever the build host is, by default rather than by decision** — Apple Silicon locally, and arm64 in CI because `macos-15` is arm64, so no Intel or universal build is exercised anywhere. With the macOS CI job delivered, that is now the *only* outstanding piece of Phase 1 task 4. The vcpkg version skew it interacts with is a link-warning class rather than a gap: it survives on CI too (5,124 `built for newer 'macOS' version (15.0) than being linked (14.0)` warnings in the same green run), and closes by pinning `VCPKG_OSX_DEPLOYMENT_TARGET` when someone wants a quiet log.

**Development-environment constraint:** all development happens on macOS; no Windows machine is available. Consequences threaded through the plan:

- The OpenGL behavioral reference is captured **locally via the XQuartz/GLX path** (the companion doc's path 1, promoted from "developer fallback" to required reference vehicle) and **canonically via CI software rendering** (`.github/workflows/render-baseline-linux.yml`: a digest-pinned `ubuntu:24.04` container + Xvfb + Mesa llvmpipe, no GPU). Both halves were delivered in Phase 0. The CI images are reproducible within a tolerance policy, not bit-exact: the digest freezes the base image but not the apt-installed Mesa, so `ENVIRONMENT.txt` records the exact package versions alongside it.
- Windows (GL and the Vulkan feeder) is protected by **compile gates in CI only**; runtime validation on Windows is deferred to testers/community builds. This is acceptable because the migration keeps the Windows Vulkan path additive-only by design `[D §1.1]` — its behavior is unchanged by construction, and CI catches any compile breakage from the side-channel renames. (One exception so far: the GL-less-path fixes in `67f9b38` do alter the Windows Vulkan path, by removing GL calls it was making with no current context — see Phase 1 task 6 and the risk register.)
- The llvmpipe reference gate delivered in Phase 0 is the cross-platform correctness instrument in force today (8 gated scenes, compared on every push). The RecordingBackend golden-frame suite `[D §9.1]` adds a GPU-less, image-independent instrument on top of it — platform-independent because PoolCompiler output is identical on every OS.

---

## Phase map and sequencing

```
P0 Baselines [done] ──► P2 Renderer boundary ──► P3 GL on RenderFrame ──► P4 Metal foundation ──► P5 Targets & composition ──► P6 Materials ──► P7 Hardening
                            ▲
P1 Cocoa platform [done] ───┘  (P1 ran in parallel with P2; P4 needs P1+P3 done)
```

- **P1 ∥ P2:** the Cocoa window needs no renderer work and the boundary needs no macOS.
- **P3 before P4** is the plan's central risk control: the frame model must reproduce today's GL output pixel-for-pixel *on the existing platforms* before any Metal code interprets it (companion doc, Phase 3 rationale).
- P5 and P6 have a partial overlap opportunity: built-in materials land in P4; the shader toolchain (P6) can start as soon as P2 freezes `MaterialParams`.

Scope calibration from the companion doc's table: this is the "Backend-neutral frame architecture plus OpenGL migration" (Large) plus "Direct Metal with full OpenGL visual parity" (Very large), with P1 "Medium" and P7 "Medium after rendering works". The existing Vulkan renderer (~5,800 lines) and the Win32/X11 windows (~1,100–1,300 lines each) remain the best available size anchors.

---

## Phase 0 — GL bring-up on macOS, baselines, and test scenes

**Goal:** a running OpenGL reference client on the development Mac, plus frozen "correct" references, so later work never masks renderer regressions.

Tasks:
1. ~~**XQuartz GL bring-up** (companion doc path 1, scoped "small to medium"): resolve macOS vcpkg dependencies, fix compiler/linker incompatibilities, validate GLX context creation on Apple Silicon, run the client under XQuartz.~~ **Done 2026-08-20:** the client builds and runs on Apple Silicon under XQuartz 2.8.6 (OpenGL 2.1, GLSL 1.20). The macOS CMake path pins X11/GLX to `/opt/X11` and fails the configure without it (`src/CMakeLists.txt:209-219`), because mixing XQuartz GL with Homebrew X11 links successfully but breaks GLX visual selection at runtime. This is the local day-to-day reference for every later phase.
2. ~~**CI software-GL reference**: Linux CI job with Xvfb + Mesa llvmpipe rendering the validation-matrix scenes headlessly and archiving the images.~~ **Done 2026-08-20:** `.github/workflows/render-baseline-linux.yml` captures the offline scenes and *compares* the gated ones against checked-in references (10 and 7 as delivered; 11 and 8 after the 2026-08-20 `shader-matrix` split), failing the job on regression (first green gating run `32381800862`). llvmpipe output is reproducible for a pinned container image and Mesa version — these become the canonical reference set, compared under the tolerance policy in `scenes.json`; a Mesa or container-digest bump is a deliberate reference-refresh event, not a routine update. (Windows-GL capture is replaced by this; spot-check against a community Windows screenshot when one is available.)
3. ~~Script the validation-matrix scenes (companion doc, Validation matrix): login screen, map with floors/creatures/missiles, day/night + colored overlapping lights, translucent nested-clipped UI, bitmap/TTF/outlined text, outfit masks + mounts + addons, particles, each live composition mode `[S 2.2]`, resize/fullscreen.~~ **Done 2026-08-20:** all 15 scenes in `docs/rendering-baselines/scenes.json` (16 after the later `shader-matrix` split), each with a command. Two items were delivered differently from the wording above. Day/night cannot be frozen in this build — there is no Lua world-light setter and `lightHour` is seeded from the wall clock — so `lighting-overlap` drops it and takes its ambient axis from a server-authored underground platform. And `composition-all` covers all six painter descriptors, not only the live composition modes.
4. ~~Add scenes that exercise every surveyed edge: the seven temp-FBO sites `[S 3.2]`, the map-hole punch `[S 4]`, `Outfit - Outline` (`useFramebuffer`), Fog/Snow (multi-texture), UIGraph lines `[S 6.3]`, atlas growth, map screenshot.~~ **Done 2026-08-20:** every listed edge has a scene — `temporary-framebuffers` (all seven sites incl. nesting and both flips), `map-core` (`map-hole`), `outfit-masks` (`outline-framebuffer`), `shader-matrix` (`fog-multitexture`, `snow-multitexture`), `graph-lines`, `atlas-resources` (`atlas-growth`, `smooth-padding`), `map-screenshot` (`map-readback`). Two scenes go beyond this list: `shader-matrix` covers every shipped fragment program — with `shader-matrix-outfits`, split out of it on 2026-08-20 so the fragment half could be CI-gated, carrying the six outfit cells — and `shader-matrix-map` covers the map shaders at their real MAP-blit bind site.
5. ~~Resolve open question `[D §12.4]`: inspect the `glReadPixels(x/3, y/1.5)` map-screenshot offsets.~~ **Done 2026-08-20:** intentional framing, verdict recorded in `[S 3.5]` and `[S 9.5]`; the crop is preserved deliberately.
6. ~~Record frame-time/memory baselines (existing `AUTO_STAT` counters suffice initially).~~ **Corrected 2026-08-20 — deferred to Phase 3.** `AUTO_STAT` is compiled out of every build this repository produces (`ENABLE_STATS` is defined nowhere in CMake), so those counters do not exist in a release binary. Enabling them is not a substitute either: each one allocates, builds a description string and takes a global mutex on hot paths including every Lua call and every packet, so the instrumented build does not measure the renderer. The only release-available signals are a 1 Hz integer FPS counter, `g_stats.getWidgetsInfo`, `g_atlas.getStats()` and `collectgarbage("count")`, and the client sleeps to cap itself at 60 FPS by default, so an uninstrumented figure measures the cap. A baseline with nothing to compare against is low value, so performance measurement moves to Phase 3, where legacy and RenderFrame paths can be compared in the same environment.

**Exit gate — met 2026-08-20:** the client runs on macOS via XQuartz; `docs/rendering-baselines/scenes.json` (15 scenes as delivered, 16 after the 2026-08-20 `shader-matrix` split, machine-readable, queried through `tools/renderer_scenes.py`) is the checked-in scene list and the single source of truth for coverage and tolerances; 8 llvmpipe references are **checked in** under `docs/rendering-baselines/references/opengl-llvmpipe/` and gate every push (7 at the exit gate, green run `32381800862`; the eighth, `shader-matrix`, was seeded from run `32395555810` in `f037e42` after the scene was split); `docs/rendering-baselines/known-deviations.md` records the deviations, including the XQuartz-vs-llvmpipe comparison — a multi-section note, not the one page anticipated here. Eight of the 15 scenes sit outside the CI gate: three are captured but ungated because `data/things/*` is gitignored, one needs a window manager, and four need the fixture server. (After the split: eight of 16, the ungated three now being `outfit-masks`, `temporary-framebuffers` and `shader-matrix-outfits`.) Capture determinism is held by an isolated write directory, pre-login sizing, a pinned `u_Time` and a pinned login background.

**References:** [XQuartz](https://www.xquartz.org/), [XQuartz releases](https://www.xquartz.org/releases/), CMake [`FindOpenGL`](https://cmake.org/cmake/help/latest/module/FindOpenGL.html) (moved here from the out-of-path list — the legacy GL route is now on the critical path as the reference vehicle).

---

## Phase 1 — Native macOS platform layer (parallel track)

**Goal:** a native `.app` that opens a Cocoa window, processes input, resizes, and presents a clear color through a bare `CAMetalLayer` — no renderer architecture involved.

**Delivered 2026-08-20** behind the opt-in CMake option `TOGGLE_COCOA_WINDOW` (`src/CMakeLists.txt:16`), **default OFF**: XQuartz stays the default macOS build because it is the OpenGL reference vehicle every Phase 0 baseline is captured through, and the Cocoa window deliberately provides no GL context. The two platform layers are mutually exclusive and never linked together (`src/CMakeLists.txt:198-224`, `:1006-1021`), and the Cocoa build links Apple's `OpenGL.framework` rather than XQuartz GL (`:312`).

Tasks:
1. ~~`CocoaWindow` (Objective-C++) implementing the `PlatformWindow` contract: `NSApplication`/`NSWindow`/`NSView` ownership, event translation (key/text/mouse/scroll/focus), cursor, clipboard, title, resize/maximize/fullscreen, activation/termination. Reconcile AppKit's event loop with the client's `poll()`-driven loop (companion doc's explicit warning — AppKit UI objects are main-thread-only).~~ **Done 2026-08-20:** `src/framework/platform/cocoawindow.{h,mm}`, 1173 lines. The loop reconciliation is *pump, not run*: `[NSApp finishLaunching]` instead of `[NSApp run]`, and `internalPumpEvents` drains `nextEventMatchingMask` against `distantPast` until empty on every `poll()` — the client keeps owning its loop. Main-thread-only access is handled by deferring every AppKit touch through `g_mainDispatcher`, because Lua and therefore every `g_window.*` binding runs on the map thread; `terminate()` is the sole exception, since the dispatchers are already shut down by then. Two things fell out of the port that the task did not anticipate: `NSPasteboard` is snapshotted once per `poll()` because `getClipboardText()` is called off the main thread, and `displayFatalError` is implemented as an `NSAlert` — X11Window never implemented it at all. **Input translation verified 2026-08-20** by driving real events at the running window: `A`, `Z`, numpad `5`, `Up`, `F1` and `Shift+C` each produced the correct `Fw::Key` (`KeyA`, `KeyZ`, `KeyNumpad5`, `KeyUp`, `KeyF1`, `KeyC` — Shift correctly leaving the keycode alone, since it is a separate modifier), and a `CGEvent` click produced `Fw::MouseLeftButton` press and release. Note the event source matters: System Events' accessibility `click at` never reaches the view and looks like a dead mouse path — a real `CGEvent` is required to test this.
2. ~~Layer-backed view exposing `CAMetalLayer`; implement `drawableSize()` (pixels) vs logical size (points); react to backing-scale changes and display moves.~~ **Done 2026-08-20, with the points/pixels polarity inverted from the wording above.** `m_size` is in **backing pixels** and `m_displayDensity` is the backing scale factor; the framework has no separate logical-size channel — `GraphicalApplication::resize` feeds `m_size` straight to `g_graphics` (and thence `glViewport`/`Painter::setResolution`) while laying the UI out at `m_size / m_displayDensity`, the same convention `AndroidWindow` uses with the system screen density. `getDrawableSize()` exists and is kept distinct because the two diverge for one frame across a backing-scale change and Phase 4's `MetalContext` must size from it. Backing-scale changes arrive through `windowDidChangeBackingProperties:`; a display move is covered only insofar as it changes the backing scale — there is no `windowDidChangeScreen:` handler. One consequence to carry into Phase 4: this codebase does not separate device pixel ratio from user HUD scale (`g_app.setHUDScale` writes the same variable), so `m_backingScale` is mirrored separately as the drawable's true sizing source.
3. ~~Platform selection: route macOS to `CocoaWindow` in `src/framework/platform/platformwindow.cpp`; drop the Apple X11 requirement in CMake — both the generic `find_package(X11 REQUIRED)` for Unix and the Phase 0 XQuartz block, which hard-fails the configure without `/opt/X11` and force-pins four `X11_*` cache variables. Keep both reachable while XQuartz remains the GL reference vehicle: gate them on the selected platform layer rather than deleting them.~~ ~~**Done 2026-08-20, gating exactly as prescribed — but the X11 *link* is only partly dropped.**~~ **Done 2026-08-20; the X11 link was severed the same day.** Routing: `platformwindow.cpp` selects `CocoaWindow` under `CRYSTALOTC_COCOA_WINDOW`, and `x11window.cpp`'s top-level guard excludes itself from that build. Gating: the generic `find_package(X11 REQUIRED)` is now conditioned on `NOT (APPLE AND TOGGLE_COCOA_WINDOW)` (`src/CMakeLists.txt:222-224`), the XQuartz `/opt/X11` block moved into the `else()` arm (`src/CMakeLists.txt:209-219`), and `X11::X11` is linked only there — both paths stay reachable, neither was deleted. ~~**Still open:** the Cocoa binary continues to link `/opt/X11` `libGL`/`libGLU` and Homebrew `libX11` … severing it belongs with Phase 4.~~ **Corrected 2026-08-20 (`9fcf605`): severed in Phase 1, not deferred to Phase 4.** The Cocoa build bypasses `find_package(OpenGL)` entirely and points `OPENGL_LIBRARIES` at Apple's `OpenGL.framework` (`src/CMakeLists.txt:306-316`, substitution at `:312`; the unconditional link site is `:974`). The bypass, not a flag, is the fix: the vendored `cmake/FindOpenGL.cmake` defaults `OPENGL_USE_APPLE_X11` to `ON` (line 54) and folds `FindX11` into `OPENGL_LIBRARIES` (lines 129-134), but setting it `OFF` links `-framework AGL`, and AGL was removed from the macOS SDK years ago. Core GL symbols must still resolve because the GL call sites are compiled even though nothing on this path calls them; GLU is dropped outright — the client references zero `glu*` symbols. Guarded permanently by the CI step "Assert the Cocoa build links no X11" (`otool -L`, run `32411659041`) on a runner with no XQuartz installed. Removing XQuartz as a build requirement is what makes a hosted macOS runner possible at all (task 4).
4. ~~Build system: `enable_language(OBJC OBJCXX)`, `MACOSX_BUNDLE` target, `Info.plist` template, resources under `Contents/Resources` via `MACOSX_PACKAGE_LOCATION`; fix macOS vcpkg dependency resolution; CI macOS build job (compile + launch smoke test).~~ **Partly done 2026-08-20.** *Done:* `enable_language(OBJCXX)` — `OBJC` proved unnecessary, nothing compiles as plain Objective-C; `MACOSX_BUNDLE` plus `cmake/macos/Info.plist.in`, producing `${CMAKE_BINARY_DIR}/bin/CrystalOTC.app`, with bundles always output to the build directory regardless of `TOGGLE_BIN_FOLDER` so the XQuartz build stays where the baseline tooling expects it. `ResourceManager::discoverWorkDir` gained bundle candidates so the `.app` boots from a neutral working directory — note the candidate is `getBaseDir() + "Contents/Resources/"`, not `../Resources/`, because PhysicsFS reports the `.app` directory itself as the base dir for a bundled executable rather than `Contents/MacOS` where the binary actually lives. `NSHighResolutionCapable` is load-bearing rather than cosmetic: without it the window server hands back a 1x backing store, `backingScaleFactor` reads 1.0 on a Retina display, and the whole pixels-vs-points contract of task 2 would rest on a lie. *Done differently:* resources are **symlinked** into `Contents/Resources` by a `POST_BUILD` step, **not** staged via `MACOSX_PACKAGE_LOCATION`, which is used nowhere in the repository — `data/` alone is ~776 MB and a per-build copy would dominate the edit/run loop. This is a bundle that runs, not a bundle that ships; real staging is Phase 7 task 1. *Qualified, not blocking:* macOS vcpkg **resolution** works; what remains is a link-warning class. vcpkg builds its ports against the host SDK while the bundle links at the 14.0 deployment target, so every link emits `ld: warning: object file … was built for newer 'macOS' version (X) than being linked (14.0)`. The `26.0` originally recorded here was **this developer machine's SDK, not a property of the build** — on the `macos-15` runner (SDK 15.5) the identical configuration emits 5,124 such warnings, all `(15.0)` vs `(14.0)`, and still links, tests 22/22 and runs (run `32411659041`). Silencing them means pinning `VCPKG_OSX_DEPLOYMENT_TARGET` to match `CMAKE_OSX_DEPLOYMENT_TARGET`; that is cleanliness work, not a Phase 1 gap. *Done since:* the macOS CI job — `.github/workflows/build-macos.yml`, job `cocoa-release` on `macos-15` (`7c16224`). It builds the **Cocoa** configuration rather than the default XQuartz one, which only became possible once task 3 severed the X11 link: XQuartz is a `.dmg` install a hosted runner cannot reasonably provide. First green run `32411659041` — 17/17 steps on macOS 15.7.7 / arm64 / Xcode 16.4 / SDK 15.5: configure, build, 22/22 CTest, bundle checks (`plutil -lint` plus non-empty `CFBundleIdentifier`, `CFBundleExecutable`, `NSHighResolutionCapable=true`, `LSMinimumSystemVersion=14.0` — asserted, not assumed, because an unset deployment target silently produced an empty string), the `otool -L` X11 assertion, and a 45-second smoke launch that reaches `OpenGL initialization skipped` and is still alive when killed. It triggers on push to `main` and on PRs, path-filtered; it is **not yet a required check**. Phase 7 task 6 retains only that promotion plus the golden-frame and image-matrix extension.
5. ~~Minimal proof: clear-color frame via `nextDrawable` → clear pass → present (this code seeds Phase 4's `MetalContext`).~~ **Done 2026-08-20:** `CocoaWindow::swapBuffers` acquires, clears and presents, and already skips the frame on a nil drawable — the window-server starvation case Phase 4 task 1 has to handle properly. Measured: content samples uniformly at (16,26,62) against the (0.05,0.10,0.25) clear colour. Phase 4 replaces the clear with the encoded `RenderFrame`; the acquisition and submission shape is what it keeps.
6. **Draw-path tolerance for a GL-less window** — not anticipated by this plan, and required before task 5 could run at all. The non-Windows branch of the render loop called `g_drawPool.draw()` unconditionally, so a window reporting `hasGLContext() == false` segfaulted on a null GLEW pointer inside `FrameBuffer::bind()` — the one GL entry point that did not already check. `GraphicalApplication` now guards that branch and calls the new `DrawPoolManager::consumeAll()` when the draw is skipped. Consuming is not optional: the map thread blocks in `canDrawMap` until `shouldRepaint` is consumed, so a frame that skips `draw()` must still consume it or map production stops permanently. This mirrors `VkDrawFeeder::consumeAllPools` without the Vulkan dependency, and is where Phase 4's Metal backend hooks in. ~~Every platform that ships today reports `hasGLContext() == true`, so the new branch is unreachable for them.~~ **Corrected 2026-08-20: that reasoning was wrong.** The shipped Windows Vulkan path also reports `hasGLContext() == false` — `WIN32Window::hasGLContext()` returns `m_wglContext != nullptr` and `internalCreateWindow` skips GL-context creation outright when `renderBackend == "vulkan"`. Windows is unaffected only because the guard added here sits in the non-Windows `#else` arm, not because its GL context exists. The conclusion held; the justification did not.

   **Two GL-less-path bugs found and fixed 2026-08-20 (`67f9b38`), neither anticipated by this plan.** Both were invisible for the same reason: XQuartz's `libGL` returns harmlessly when called with no current context, so the strays went unnoticed while XQuartz was the only macOS GL provider; Apple's `OpenGL.framework` segfaults instead, and linking it (task 3) turned both into crashes. (1) `Painter::Painter` calls `setResolution` *before* its own `hasGLContext()` guard, and `setResolution` ends in `updateGlViewport` → `glViewport` — the comment claiming the painter makes no GL call sat three lines below one. The call has to stay (the painter is deliberately kept alive as a carrier of resolution and matrices), so the guard moved into `updateGlViewport`. (2) `Texture::create` reached `glGenTextures` unguarded, although the `Texture` constructor a hundred lines above already returned early for exactly this case; fonts load through it during module startup, long before anything draws. Both were found by backtrace, not inspection. **This matters beyond macOS:** `Graphics::init` takes its no-GL branch and builds the `Painter` there, and a GL context is created on Windows only if Vulkan init fails — so the shipped Windows Vulkan path ran the same two functions with no current context and was relying on the same luck.

**Exit gate — met 2026-08-20:** the native window opens with no `DISPLAY` and no XQuartz running (the window server reports a window titled "CrystalOTC"); the clear colour presents (content samples (16,26,62) against a (0.05,0.10,0.25) clear); resize works and tracks backing scale (510→900 points, after which the content measures exactly 1800 px = 900 × 2); and `CrystalOTC.app` launches via `open`, the way Finder does, booting from a neutral working directory, with `Info.plist` passing `plutil -lint`. The XQuartz path is unaffected: 22/22 CTest and five baseline scenes recaptured at 0 differing pixels. **"Input works" was closed the same day** rather than left to Phase 4: keyboard translation was verified against the `Fw::Key` table for letters, numpad, arrows, function keys and a shifted key, a real `CGEvent` click produced `Fw::MouseLeftButton`, and both quit routes — a click on the close button and `Cmd+Q` — travel `windowShouldClose:`/`applicationShouldTerminate:` → `m_onClose` → the cross-thread dispatch → `Application::exit()`, ending in a graceful "Exiting application.." and exit code 0 rather than a kill. Still unexercised: text input (`NSTextInputClient`), scroll wheel, and the modifier synthesis in `flagsChanged:`. Since 2026-08-20 the build-and-boot half of this gate is reproved automatically: run `32411659041` builds the Cocoa configuration on a clean `macos-15` runner **with no XQuartz present**, runs 22/22 CTest, asserts the `Info.plist` keys are non-empty, asserts via `otool -L` that nothing X11 is linked, and smoke-launches the `.app` for 45 seconds. What CI cannot cover is exactly the residual: with no window server it never presents a frame or delivers an event, so input, resize and the clear-colour proof remain local-only evidence.

**References (read in this order — companion doc "Suggested reading order" items 1–4):**
- [NSApplication](https://developer.apple.com/documentation/appkit/nsapplication) — event loop and lifecycle
- [NSWindow](https://developer.apple.com/documentation/appkit/nswindow), [NSView](https://developer.apple.com/documentation/appkit/nsview) — window/content-view ownership
- [Managing your game window for Metal in macOS](https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos) — the AppKit↔Metal boundary, point-to-pixel conversion, resize
- [CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer), [`drawableSize`](https://developer.apple.com/documentation/quartzcore/cametallayer/drawablesize), [`nextDrawable()`](https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable()), [CAMetalDrawable](https://developer.apple.com/documentation/quartzcore/cametaldrawable), [CALayer](https://developer.apple.com/documentation/quartzcore/calayer)
- [NSResponder](https://developer.apple.com/documentation/appkit/nsresponder), [NSEvent](https://developer.apple.com/documentation/appkit/nsevent), [NSWindowDelegate](https://developer.apple.com/documentation/appkit/nswindowdelegate), [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard), [NSCursor](https://developer.apple.com/documentation/appkit/nscursor)
- [High Resolution Guidelines for OS X](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Introduction/Introduction.html) — points/pixels/backing-scale model
- CMake: [`MACOSX_BUNDLE`](https://cmake.org/cmake/help/latest/prop_tgt/MACOSX_BUNDLE.html), [`MACOSX_BUNDLE_INFO_PLIST`](https://cmake.org/cmake/help/latest/prop_tgt/MACOSX_BUNDLE_INFO_PLIST.html), [`MACOSX_PACKAGE_LOCATION`](https://cmake.org/cmake/help/latest/prop_sf/MACOSX_PACKAGE_LOCATION.html), [`enable_language`](https://cmake.org/cmake/help/latest/command/enable_language.html)

---

## Phase 2 — Renderer boundary: PoolCompiler, RenderFrame, RecordingBackend

**Goal:** a representative frame can be compiled and inspected with zero GL calls (companion doc Phase 2 criterion), on all existing platforms.

Tasks:
1. **API-neutral enums.** Replace GL-valued enums in `declarations.h` (`DrawMode::TRIANGLES = GL_TRIANGLES`, `BlendEquation::ADD = GL_FUNC_ADD` `[S 2.3]`) with plain enums; introduce `BlendMode` per `[D §4]` (six modes, `AddWeird` included).
2. **Logical handles + ResourceRegistry** `[D §2.1]`: `Texture`/`FrameBuffer`/`PainterShaderProgram` gain handles; native-object ownership stays where it is for now (GL still direct) — the registry is introduced as pass-through.
3. **Rename/promote the vk side-channels**: `vkFbMarker/vkFbSize/vkFbDest/vkFbFlip/vkFbOpacity`, `m_vkPendingFb*`, `m_vkMapHole` become the compiler's declared inputs (`fbMarker`, `mapHole`, …). The Vulkan feeder keeps reading them — rename only, no behavior change `[D §1.1]`.
4. **PoolCompiler + PoolProgram** `[D §1, §3]`: compile published `DrawObject` lists into passes/packets/vertex arenas at `release()` time, additive alongside the existing path. Implement all seven idiom compilations `[D §6]`: FBO-marker pass splitting (with nesting), pool-FBO prepare metadata, map-shader material hook, hole-punch packet, UIGraph line triangulation, LightView `TextureUpdate`, atlas maintenance passes.
5. **FrameAssembler + RenderFrame** `[D §3, §8]` including `LoadAction::Keep` and pool-hash pass skipping.
6. **RecordingBackend** `[D §9.1]` + golden-frame tests: fixture scenes from Phase 0 compiled headlessly in CI; assertions on pass splitting, `onlyOnce` scoping `[S 9.9]`, scissor clamping, packet state.
7. Freeze `MaterialParams` `[D §5.2]` (unblocks Phase 6 toolchain work).

**Touch list:** `src/framework/graphics/declarations.h`, `drawpool.*`, `drawpoolmanager.*`, new `src/framework/graphics/render/` (compiler, frame, handles, recording backend), `texture.h`, `framebuffer.h`, `paintershaderprogram.h`.

**Exit gate:** golden-frame suite green in CI on a GPU-less runner; Windows/Linux GL and Windows Vulkan behavior bit-identical to before (they still run the old path).

*No new external references — this phase is entirely internal. Keep `[S]`/`[D]` at hand.*

---

## Phase 3 — GL backend consumes RenderFrame

**Goal:** the OpenGL renderer becomes `GLBackend : IRenderBackend`, executing `RenderFrame` — proving the model describes real behavior before Metal exists.

Tasks:
1. Implement `GLBackend` `[D §9]`: absorb `Painter`'s projection matrices (backbuffer-flipping vs FBO variants `[D §7]`), scissor y-flip, blend table `[S 2.1]`, alpha-write mask, program binding for built-ins, texture/target tables.
2. Runtime flag `graphics.renderPath = legacy | frame` (config already carries `graphics.renderBackend` `[S drawpoolmanager.cpp:58]`); ship both paths during stabilization.
3. Screenshot/readback through `ReadbackRequest` (top-left origin at the boundary; flip inside the backend `[D §7]`).
4. Wire the existing Phase 0 comparison harness (`tools/compare_renderer_images.py`, driven per scene from the `scenes.json` tolerances by `.github/workflows/render-baseline-linux.yml`) to the legacy-vs-new comparison. Two comparisons, both same-environment so no cross-platform noise pollutes the gate: locally, legacy-path vs new-path on XQuartz; in CI, legacy-path vs new-path on llvmpipe (small tolerance; hard-fail on missing passes/clip/coordinate errors, per the companion doc's validation-matrix note).
5. After parity: delete `Painter`, `FrameBuffer` (shim first), `DrawPool::addAction(std::function)`; legacy path removed `[D §10]`.

**Exit gate:** legacy and new GL paths pixel-match on both reference environments; Windows and Linux CI builds compile green (Windows runtime behavior is unchanged by construction — the Vulkan feeder still consumes the same published `DrawObject` lists `[D §1.1]`).

*References: none external; this is a refactor against `[S]` ground truth.*

---

## Phase 4 — Metal foundation

**Goal:** login UI and normal gameplay render on macOS with correct sprites, text, clipping, opacity, and the three live blend modes — before advanced passes.

Tasks:
1. **MetalContext** `[D §9]`: `MTLDevice`, `MTLCommandQueue`, 2–3 frames in flight with semaphore throttling, per-frame command buffers, drawable acquisition (handle nil drawables/zero-size), completion-handler frame retirement driving the deferred-destruction queue `[D §2.1]`.
2. **Resources:** RGBA8 texture table (`MTLTexture`), the four sampler states `[S 7]`, `glTexSubImage2D`-equivalent region updates (LightView streams every frame `[S 3.4]`), private-storage + staged upload where profitable.
3. **Vertex arenas** in per-frame `MTLBuffer` rings `[D §2.3]`; two non-interleaved float2 attributes matching the fixed vertex stage `[S 5.1]`, described via `MTLVertexDescriptor`.
4. **Pipeline cache** on `PipelineKey` `[D §4]`; the full six-mode blend table as `MTLRenderPipelineColorAttachmentDescriptor` states; `alphaWrite` via `writeMask`; `blendEnabled=false` states.
5. **Built-in materials** in hand-written MSL: Textured, SolidColor, ReplaceColor (`[S 5.1]` — four tiny functions; Line is compiled away in P2).
6. Scissor (`setScissorRect`, pre-clamped packets), viewport, labels on every buffer/encoder/texture/pipeline (companion doc debugging note).
7. Backbuffer-only rendering first: pool passes targeting retained textures can initially render direct-to-drawable for bring-up, but P5's target machinery should follow immediately.

**Exit gate:** companion doc Phase 4B criterion, upgraded to our baseline: login + gameplay visually correct apart from features owned by P5/P6 (light overlay, map shaders, temp-FBO widgets may be stubbed to direct draws behind a flag).

**References (companion doc reading-order items 5–7 plus resources):**
- [Metal framework index](https://developer.apple.com/documentation/metal)
- [MTLDevice](https://developer.apple.com/documentation/metal/mtldevice), [Setting up a command structure](https://developer.apple.com/documentation/metal/setting-up-a-command-structure), [MTLCommandQueue](https://developer.apple.com/documentation/metal/mtlcommandqueue), [MTLCommandBuffer](https://developer.apple.com/documentation/metal/mtlcommandbuffer), [MTLCommandEncoder](https://developer.apple.com/documentation/metal/mtlcommandencoder)
- [MTLRenderCommandEncoder](https://developer.apple.com/documentation/metal/mtlrendercommandencoder), [MTLRenderPassDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpassdescriptor), [MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor), [MTLRenderPipelineState](https://developer.apple.com/documentation/metal/mtlrenderpipelinestate)
- [MTLSamplerDescriptor](https://developer.apple.com/documentation/metal/mtlsamplerdescriptor), [MTLVertexDescriptor](https://developer.apple.com/documentation/metal/mtlvertexdescriptor)
- [Synchronizing CPU and GPU work](https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work) — the in-flight-frames pattern
- [Resource fundamentals](https://developer.apple.com/documentation/metal/resource-fundamentals), [Buffers](https://developer.apple.com/documentation/metal/buffers), [Textures](https://developer.apple.com/documentation/metal/textures)
- [Copying data to a private resource](https://developer.apple.com/documentation/metal/copying-data-to-a-private-resource)
- [Synchronizing a managed resource in macOS](https://developer.apple.com/documentation/metal/synchronizing-a-managed-resource-in-macos) — only if Intel/universal is confirmed (Decision 5)
- [Metal feature set tables](https://developer.apple.com/metal/capabilities/) — capability/limit checks (texture size vs atlas layer size)

---

## Phase 5 — Render targets and full composition on Metal

**Goal:** the complete frame pass graph `[S 10]` runs on Metal; output matches the *local XQuartz* OpenGL reference captured on the same Mac, within tolerances. The checked-in llvmpipe references are same-environment CI references, not a cross-stack oracle for Metal (`docs/rendering-baselines/README.md`), so a macOS reference set has to be captured and frozen before this gate can run.

Tasks:
1. **Retained targets** (MAP, FOREGROUND) with `Keep` load, hash-gated pass skipping `[D §8]`, resize/scale recreation (`viewport/scale` FOREGROUND sizing `[S 9.7]`).
2. **Transient target pool** keyed by size, per-frame recycling `[D §2.2]`; the seven temp-FBO sites incl. nesting and h/v flips `[S 3.2]`; resolve open question `[D §12.2]` (smooth transient descriptor bit).
3. **Atlas layer targets**: maintenance passes with blend-off packets, padding draws, `Keep` accumulation `[S 3.3]`; verify the outside-bounds padding sample against Metal clamp behavior `[S 9.6]`.
4. **MAP composition** with blend disabled + no alpha write `[S 2.4, S 9.3]`; **light overlay** (`TextureUpdate` + Multiply packet); **hole punch** packet; CREATURE_INFORMATION/FOREGROUND_MAP direct passes.
5. **Readback**: blit-encoder copy to shared buffer → `ReadbackResult` (map screenshot, full-screen screenshot, `extractTexture` equivalent `[S 3.5]`).
6. Wire the image-comparison harness (P3.4) to run the matrix on macOS.

**Exit gate:** companion doc Phase 5 criterion — Metal matches the OpenGL reference scenes apart from documented tolerances; performance within the envelope established in Phase 3 (there is no Phase 0 performance baseline — see Phase 0 task 6).

**References:**
- [MTLBlitCommandEncoder](https://developer.apple.com/documentation/metal/mtlblitcommandencoder) — readback copies, atlas-growth layer copies
- [Resource synchronization](https://developer.apple.com/documentation/metal/resource-synchronization) — render-to-texture then sample hazards (untracked heaps only; default tracking covers the simple case)
- Re-consult [MTLRenderPassDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpassdescriptor) load/store actions

---

## Phase 6 — Materials and the shader toolchain

**Goal:** every supported effect renders consistently on GL and Metal; the shader set is closed and build-verified.

Tasks:
1. **Build-time toolchain** `[D §5.1]`: `.frag` (+ fixed vertex scaffold + `MaterialParams` UBO header) → **glslang** → SPIR-V → **SPIRV-Cross** → MSL → `metal`/`metallib` compile, as a CMake step over `modules/game_shaders/shaders/**` and any C++-registered fragments. Build fails on untranslatable GLSL — that is the "closed set" enforcement.
2. **Inventory port**: the 27 registered module programs over 22 `.frag` files `[S 5.3, S 5.6]` — validate each against its GL rendering in the matrix scenes; multi-texture binding (`u_Tex1..3` → texture slots) for Fog/Snow.
3. **Application semantics**: map-shader-as-composition-material with fade `[D §5.3]`; per-creature/item shaders; the `useFramebuffer` transient route (Outline).
4. **GL side of the ABI**: map `MaterialParams` fields onto the legacy uniform locations so existing `.frag` sources compile unchanged; retire the index-10 collision `[S 9.4]`. It is latent, not live — `u_ItemId` is never bound in shipped code — so there is no prior visual behavior to preserve; the requirement is only that the Metal ABI must not inherit the shared index space.
5. `createFragmentShaderFromCode`: GL-only registration; Metal logs once and falls back to Textured `[D §5.1]`; document in module-author docs.
6. Shader/pipeline compilation diagnostics + on-disk pipeline cache if startup cost warrants it.

**Exit gate:** companion doc Phase 6 criterion — supported effects and outfits consistent across GL and Metal; toolchain runs in CI.

**References:**
- [Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) — the authority when SPIRV-Cross output needs hand-adjustment
- [Libraries and functions](https://developer.apple.com/documentation/metal/libraries-and-functions), [Pipeline state creation](https://developer.apple.com/documentation/metal/pipeline-state-creation)
- [MTLFunctionConstantValues](https://developer.apple.com/documentation/metal/mtlfunctionconstantvalues) — optional variant reduction
- Toolchain (new references, not in the companion doc): [glslang](https://github.com/KhronosGroup/glslang) — GLSL→SPIR-V; [SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross) — SPIR-V→MSL, including its MSL-specific resource-binding options

---

## Phase 7 — Hardening and distribution

**Goal:** a distributable, debuggable `CrystalOTC.app`.

Tasks:
1. Bundle completeness: assets in `Contents/Resources`, any dylibs in `Contents/Frameworks`, correct rpaths (companion doc bundle-layout note).
2. Deployment target + architectures per Decisions 5/6; universal build if confirmed.
3. Signing, hardened runtime, notarization (`notarytool`), Gatekeeper verification.
4. Reliability matrix: sleep/wake, display hot-plug/switch, fullscreen transitions, window-server drawable starvation, prolonged play (atlas growth `[S 3.3]`, memory), allocation-failure paths (structured init errors per companion doc).
5. GPU diagnostics in release: capture scopes, labels, `MTLCommandBuffer` error logging; crash reporting.
6. CI: the macOS build + smoke job already exists from Phase 1 (`.github/workflows/build-macos.yml`, job `cocoa-release` on `macos-15`, green since run `32411659041` — build, 22/22 CTest, bundle-key assertions, an `otool -L` no-X11 assertion and a 45-second smoke launch). What remains here is to promote it to a **required** check, widen its path filter if the matrix needs it, and extend it with the golden-frame suite and the CI-capturable image matrix (11 scenes, 8 of them gated) once Metal can draw them.

**References:**
- [Metal debugger](https://developer.apple.com/documentation/xcode/metal-debugger), [Capturing a Metal workload in Xcode](https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode), [Metal debugging types](https://developer.apple.com/documentation/metal/metal-debugging-types)
- [Improving your game's graphics performance and settings](https://developer.apple.com/documentation/metal/improving-your-game-s-graphics-performance-and-settings), [Reducing the memory footprint of Metal apps](https://developer.apple.com/documentation/metal/reducing-the-memory-footprint-of-metal-apps)
- [Apple distribution overview](https://developer.apple.com/documentation/technologyoverviews/distribution), [Code signing](https://developer.apple.com/documentation/security/code-signing-services), [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [Hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime)

---

## Out-of-path references (kept for completeness)

Retained from the companion doc in case the fallback strategy changes; **not needed on this plan's path**:

- MoltenVK: [repository](https://github.com/KhronosGroup/MoltenVK), [runtime user guide](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md), [configuration parameters](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Configuration_Parameters.md), [`VK_EXT_metal_surface`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_metal_surface.html), [`VK_KHR_portability_enumeration`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_portability_enumeration.html), [`VK_KHR_portability_subset`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_portability_subset.html), [Loader driver interface on macOS](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderDriverInterface.md), [validation layers](https://github.com/KhronosGroup/Vulkan-ValidationLayers)
- ANGLE: [repository](https://chromium.googlesource.com/angle/angle), [DevSetup](https://github.com/google/angle/blob/main/doc/DevSetup.md), [`EGL_ANGLE_platform_angle`](https://chromium.googlesource.com/angle/angle/+/main/extensions/EGL_ANGLE_platform_angle.txt), [`EGL_ANGLE_platform_angle_metal`](https://chromium.googlesource.com/angle/angle/+/main/extensions/EGL_ANGLE_platform_angle_metal.txt), [extension support](https://github.com/google/angle/blob/main/doc/ExtensionSupport.md), [debugging tips](https://github.com/google/angle/blob/main/doc/DebuggingTips.md)
- [NSOpenGLContext](https://developer.apple.com/documentation/appkit/nsopenglcontext) (deprecated native GL — not used; the GL reference runs through XQuartz/GLX per Phase 0); CMake [`FindVulkan`](https://cmake.org/cmake/help/latest/module/FindVulkan.html) (relevant again when the VulkanBackend of `[D §1.1]` is scheduled)

---

## Risk register

| Risk | Phase | Mitigation |
|---|---|---|
| Frame model fails to describe some GL behavior discovered late | P2/P3 | P3-before-P4 ordering; golden frames; the survey's exhaustive lambda list `[S 4]` bounds the unknowns |
| Pixel-parity gate too strict for legitimate GL/Metal sampling differences | P3/P5 | **Mitigation delivered in P0:** tolerance policy in `scenes.json` (`defaultTolerance` plus per-scene overrides with recorded reasons); structural differences still hard-fail. Already realised for line rendering — two GL stacks disagree by 1.52% on `graph-lines` — so line geometry needs a wide envelope from the start |
| SPIRV-Cross output diverges from GL semantics for some `.frag` | P6 | per-shader matrix scenes; MSL spec as arbiter; hand-patch individual shaders (closed set makes this tractable) |
| ~~AppKit loop vs `poll()` loop integration~~ | P1 | **Retired 2026-08-20** — the mitigation worked as written. Solved by pumping, not running: `[NSApp finishLaunching]` instead of `[NSApp run]`, with `internalPumpEvents` draining `nextEventMatchingMask` against `distantPast` on every `poll()`, so the client keeps owning its loop. Main-thread-only access is funnelled through `g_mainDispatcher` as X11Window and WIN32Window already do; window-state callbacks only latch inside AppKit handlers and fire at the tail of `poll()`, coalescing a live resize drag into one `m_onResize` per frame. Residual: text input, scroll and modifier synthesis remain unexercised, though keyboard, mouse-button and both quit routes were verified 2026-08-20 |
| ~~Cocoa binary still links XQuartz `libGL`/`libGLU`/`libX11`~~ | P1 | **Retired 2026-08-20 (`9fcf605`)** — severed in P1, not deferred to P4. The Cocoa build skips `find_package(OpenGL)` and sets `OPENGL_LIBRARIES` to Apple's `OpenGL.framework` (`src/CMakeLists.txt:312`); flipping `OPENGL_USE_APPLE_X11=OFF` would not have worked, since that branch links `-framework AGL`, removed from the SDK years ago. Now guarded permanently by the CI step "Assert the Cocoa build links no X11" (`otool -L`, run `32411659041`), which also fails if `AppKit`/`Metal`/`QuartzCore` go missing |
| Performance regression from explicit passes (encoder churn) | P4/P5 | packet batching preserved `[S 6.4]`; pass merging where load/store allows (companion doc: passes stay logically explicit, physically mergeable) |
| Breaking the shipped Windows Vulkan path | P1/P2/P3 | additive compiler; side-channel renames only; Windows CI compile gate; no local runtime validation possible — behavior preserved by construction, tester validation before releases. **First exception recorded 2026-08-20:** `67f9b38` changed two functions the Windows Vulkan path actually executes (`Painter::updateGlViewport`, `Texture::create`), removing GL calls it was issuing with no current context. Strictly a removal of illegal calls, and the Windows compile gate is green (run `32411659030`), but it is the first Windows-affecting *behaviour* change in this migration and is unvalidated at runtime — carry it into the next tester validation |
| Atlas padding trick behaves differently on Metal clamp | P5 | dedicated scene **exists and is gated** (`atlas-resources`, feature `smooth-padding`, reference checked in); fall back to CPU-padded upload if sampling differs `[S 9.6]` |
| ~~XQuartz/GLX bring-up on Apple Silicon stalls (P0.1)~~ | P0 | **Retired 2026-08-20** — the client builds and runs under XQuartz 2.8.6 on Apple Silicon; GL/Xlib pinned to `/opt/X11` (`src/CMakeLists.txt:209-219`) |
| XQuartz or llvmpipe GL output deviates from real Windows GL | P0/P3 | **Measured in P0:** five of the seven gated scenes agree across the two GL stacks to within a few hundred pixels, but `GL_LINE_SMOOTH`/`glLineWidth` rasterization does not (1.52% on `graph-lines`), so line geometry is compared same-environment only and carries a wide envelope. Divergence is bounded, not absent. "Known deviations" note delivered; spot-check against community Windows screenshots still open |

## Definition of done

The macOS milestone is complete when: the `.app` runs the full 16-scene validation matrix locally, with Metal output matching the same-environment macOS references within the tolerance policy; the CI-capturable subset (11 scenes, 8 of them gated) and the golden-frame suite are required CI — the rest of the matrix cannot be required, because three scenes need `data/things/*`, one needs a window manager and four need the fixture server; the llvmpipe CI job, green since 2026-08-20, continues to prove GL-on-`RenderFrame` parity (standing in for Windows/Linux runtime validation); Windows, Linux and macOS CI are green — Windows and Linux compile-gated with the Vulkan feeder behaviour-unchanged by construction, macOS building, unit-testing, bundle-checking and smoke-launching the Cocoa `.app` as a required job; and the shader toolchain rejects untranslatable GLSL at build time.
