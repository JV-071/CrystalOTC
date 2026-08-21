# macOS Rendering Investigation and Target Architecture

**Status:** Investigation and architecture proposal  
**Date:** 2026-08-19  
**Scope:** Native macOS support, Vulkan through MoltenVK, ANGLE over Metal, and a direct Metal renderer

## Purpose

This document records the investigation into bringing CrystalOTC to macOS and describes a target rendering architecture that can support OpenGL, Vulkan, and Metal without allowing one graphics API to leak through the rest of the client.

It is intended to answer four questions:

1. Why does the current macOS preset not produce a native macOS client?
2. What are the viable paths to macOS?
3. What does a fully native Metal renderer actually entail?
4. What architecture would let CrystalOTC support multiple renderers cleanly over time?

No implementation decision is made merely by this document. It is a technical reference for a future implementation plan.

## Executive summary

CrystalOTC can run natively on macOS, but adding a macOS CMake preset is not sufficient. ~~The repository currently lacks a native macOS window and input layer~~, and the Vulkan renderer is compiled only on Windows. **Corrected 2026-08-20 (Phase 1):** a native macOS window and input layer now exists (`src/framework/platform/cocoawindow.h`/`.mm`), opt-in behind `TOGGLE_COCOA_WINDOW`, default OFF. The Vulkan half is unchanged.

There are four viable paths:

| Path | Native window | GPU API ultimately used | Existing renderer reused | Principal trade-off |
|---|---:|---:|---:|---|
| XQuartz and OpenGL | No | OpenGL through X11 | Mature OpenGL path | Fastest proof, but not a native Mac application |
| Cocoa and MoltenVK | Yes | Metal through Vulkan translation | Current Vulkan path | Best route to preserve current Vulkan work |
| Cocoa and ANGLE | Yes | Metal through OpenGL ES translation | Mature OpenGL path | Strongest short-term visual compatibility |
| Cocoa and direct Metal | Yes | Metal directly | CPU-side concepts only | Cleanest Apple backend, but largest renderer project |

The recommended near-term path is a native Cocoa window with MoltenVK if preserving the current Vulkan renderer is the priority. ANGLE over Metal is a compelling alternative if complete OpenGL visual behavior is more important than keeping the custom Vulkan implementation.

A direct Metal renderer is best treated as a longer-term architecture project. The hard part is not drawing sprites with Metal. The hard part is extracting implicit OpenGL state, framebuffer operations, and shaders into explicit backend-neutral rendering commands.

## Current repository state

### macOS build scaffolding exists

`CMakePresets.json` contains `macos-release` and `macos-debug` presets. They select Ninja, a vcpkg toolchain, and release/debug settings.

This is useful scaffolding, but it does not provide a native macOS platform implementation or select a macOS-specific renderer.

### macOS currently selects the X11 platform

`PlatformWindow` selects implementations as follows:

```text
Windows                                    -> WIN32Window
Android                                    -> AndroidWindow
WebAssembly                                -> BrowserWindow
macOS with TOGGLE_COCOA_WINDOW=ON          -> CocoaWindow
Everything else, macOS included by default -> X11Window
```

The selection is in `src/framework/platform/platformwindow.cpp`. **Updated 2026-08-20 (Phase 1):** the Cocoa branch exists, but `TOGGLE_COCOA_WINDOW` defaults **OFF** (`src/CMakeLists.txt:16`), so an unmodified `macos-release` preset still builds the X11 window. XQuartz remains the Phase 0 baseline reference vehicle.

The CMake build also requests X11 for every Unix target that is not Android or WebAssembly. macOS therefore follows the historical OTClient XQuartz/GLX route rather than Cocoa/AppKit. **Updated 2026-08-20 (Phase 1):** the `find_package(X11 REQUIRED)` guard now also excludes `APPLE AND TOGGLE_COCOA_WINDOW` (`src/CMakeLists.txt:222-224`), and `X11::X11` is linked only on the non-Cocoa branch (`src/CMakeLists.txt:1006-1021`). ~~X11 is nonetheless **not fully unlinked**: the shared `${OPENGL_LIBRARIES}` link still resolves to `/opt/X11` libGL and Homebrew libX11. Cutting that is outstanding Phase 1 work.~~ **Corrected 2026-08-20 (Phase 1):** X11 is now fully unlinked. The Cocoa branch skips `find_package(OpenGL)` altogether and points `OPENGL_LIBRARIES` at Apple's OpenGL.framework (`src/CMakeLists.txt:297-316`), because the vendored `cmake/FindOpenGL.cmake` defaults `OPENGL_USE_APPLE_X11` to ON (`:54`) and folds FindX11's libraries into `OPENGL_LIBRARIES` (`:129-134`). Setting `OPENGL_USE_APPLE_X11=OFF` is **not** the fix: that branch emits `-framework AGL`, and AGL was removed from the macOS SDK. GL symbols must still resolve because the GL call sites are compiled even though nothing on this path calls GL; GLU is dropped entirely (zero `glu*` references). `otool -L` shows OpenGL.framework, AppKit, Metal and QuartzCore with no `/opt/X11` and no Homebrew paths, and `.github/workflows/build-macos.yml` now guards the regression.

Consequences of the default (XQuartz) configuration include:

- XQuartz is required to create and display the window.
- Input, clipboard, cursor, fullscreen, and window behavior are X11 behavior rather than native macOS behavior.
- Retina scaling and macOS application lifecycle integration are not handled natively.
- The output is a command-line executable, not a self-contained `.app` bundle.

**Updated 2026-08-20 (Phase 1):** all four are now conditional. With `TOGGLE_COCOA_WINDOW=ON` the window, input, clipboard, cursors, fullscreen, Retina backing scale and application lifecycle are native AppKit (`src/framework/platform/cocoawindow.mm`), and the target builds `CrystalOTC.app` (`src/CMakeLists.txt:1078`). Bundle *completeness* — real asset copies, embedded dylibs, signing — remains Phase 7; the developer build symlinks its resources (`src/CMakeLists.txt:1099`).

### Vulkan is explicitly Windows-only

The Vulkan implementation is guarded with `#ifdef WIN32` across:

- `vkloader`
- `vkcontext`
- `vkrect`
- `vkatlas`
- `vkbatch`
- `vkfeeder`
- application startup
- the main frame loop

The current loader opens `vulkan-1.dll`, surface creation uses `vkCreateWin32SurfaceKHR`, and the native window handle is an `HWND`.

The vcpkg manifest similarly limits Vulkan headers and the Vulkan Memory Allocator dependency to Windows. The allocator dependency does not currently appear to be used by the renderer.

### There is no renderer interface

The client has classes that look like an abstraction layer—`Painter`, `Texture`, `FrameBuffer`, `ShaderProgram`, and `DrawPool`—but their contracts contain OpenGL assumptions.

Examples include:

- ~~General enums are assigned OpenGL constants such as `GL_TRIANGLES` and `GL_FUNC_ADD`.~~ **Corrected 2026-08-20 (Phase 2, `fa8656d`):** they no longer are. `CompositionMode`, `DrawMode`, `BlendEquation` and `ShaderType` are plain `uint8_t` enums and `declarations.h` no longer includes `glutil.h`, so a translation unit that wants a graphics forward declaration no longer gets GLEW with it. The GL numbering moved into `glPrimitiveOf`/`glBlendEquationOf` (`painter.cpp`) and `glShaderStageOf` (`shader.cpp`). The leak narrowed rather than closed: the ten files that include `shaderprogram.h` still pull GL in, because that class calls `glUniform*` from inline methods.
- `Painter` stores an OpenGL texture ID and contains `updateGl*` methods.
- `Painter::drawCoords` ends in `glDrawArrays`.
- `Texture` owns and uploads OpenGL texture objects.
- `FrameBuffer` owns OpenGL framebuffer objects.
- `Shader` and `ShaderProgram` compile GLSL and upload OpenGL uniforms.
- Some `DrawPool` actions are lambdas that directly bind or prepare OpenGL framebuffers.

The current effective design is therefore:

```text
Game and UI
    |
    v
DrawPool containing geometry and OpenGL-derived state/actions
    |
    v
OpenGL Painter
    |
    v
OpenGL textures, shader programs, FBOs, and glDrawArrays
```

### Vulkan works as a parallel translation path

The Vulkan backend does not implement the `Painter` contract. Instead, `VkDrawFeeder` intercepts published `DrawPool` objects and translates the portions it understands into Vulkan vertices and batches.

This has allowed Vulkan to be introduced without rewriting the established OpenGL path. It also explains the current limitations documented by `vkfeeder.h`:

- the `LIGHT` pool is skipped;
- painter shader programs are ignored;
- OpenGL action lambdas are skipped;
- textures produced only by an OpenGL framebuffer cannot enter the Vulkan atlas;
- some composition modes are drawn as normal blending.

MoltenVK would preserve these behaviors. It makes the existing Vulkan commands run over Metal, but does not add missing rendering features by itself.

## macOS implementation alternatives

## 1. XQuartz and OpenGL

This retains `X11Window` and the existing OpenGL renderer.

### Required work

**Status 2026-08-20:** ~~all but the macOS build job are complete~~ **updated 2026-08-20 (Phase 1):** every item is complete except a build job for *this* configuration — `.github/workflows/build-macos.yml` covers macOS in CI but builds the Cocoa configuration on purpose, since XQuartz is a `.dmg` install a hosted runner cannot provide, so the XQuartz path remains a local-only build — see `docs/metal-implementation-plan.md` Phase 0 and `docs/rendering-baselines/known-deviations.md`.

- Install and document XQuartz.
- Resolve the existing macOS/vcpkg dependencies.
- Validate GLX context creation on Apple Silicon.
- Correct any compiler or linker incompatibilities.
- Add a basic macOS build job.

### Advantages

- Lowest renderer implementation cost.
- Exercises the mature OpenGL path.
- Useful as an early build-system and game-logic smoke test.

### Disadvantages

- Not a native macOS experience.
- Requires the user to install and run XQuartz.
- Does not use the custom Vulkan renderer.
- Poor foundation for distribution, Retina behavior, and macOS integration.

This path is appropriate only as a proof-of-life or developer fallback.

## 2. Cocoa and MoltenVK

MoltenVK implements Vulkan over Metal. The existing SPIR-V shaders are translated to Metal Shading Language by MoltenVK at runtime.

### Required work

- Implement a Cocoa `PlatformWindow`.
- Back its `NSView` with a `CAMetalLayer`.
- Generalize the Vulkan code from `WIN32` to a renderer capability such as `CRYSTALOTC_HAS_VULKAN`.
- Define `VK_USE_PLATFORM_METAL_EXT` on macOS.
- Enable `VK_EXT_metal_surface` and create a `VkMetalSurfaceEXT` from the `CAMetalLayer`.
- Enable portability enumeration when using the Vulkan loader.
- Enable `VK_KHR_portability_subset` when the selected device advertises it.
- Link or bundle MoltenVK and the required Apple frameworks.
- Extend Vulkan device and extension diagnostics.
- Build a macOS `.app` and copy its runtime resources.

### Advantages

- Reuses the existing Vulkan atlas, batching, synchronization, and SPIR-V shaders.
- Preserves the current Windows Vulkan rendering model.
- Uses Metal on the actual hardware without maintaining a second native pipeline immediately.
- Smaller renderer change than direct Metal.

### Disadvantages

- Keeps the current Vulkan feature gaps.
- Adds MoltenVK as a runtime dependency.
- Requires Vulkan portability-specific instance and device handling.
- Debugging crosses the CrystalOTC, Vulkan, MoltenVK, and Metal layers.

This is the recommended route when the existing Vulkan renderer is the desired behavioral baseline.

## 3. Cocoa and ANGLE over Metal

ANGLE exposes OpenGL ES while translating commands to Metal. The pinned vcpkg ANGLE port supports macOS and includes a `metal` feature, although CrystalOTC currently enables ANGLE only on Windows.

### Required work

- Implement the same Cocoa window and input layer.
- Build ANGLE with its Metal backend.
- Create an EGL display, surface, and OpenGL ES context for the native view.
- Compile the client in its OpenGL ES configuration.
- Validate all framebuffer, shader, blending, texture, and extension behavior.
- Bundle the ANGLE libraries in the application.

### Advantages

- Reuses the mature OpenGL renderer rather than the incomplete Vulkan feeder.
- Likely offers better immediate lighting, framebuffer, and shader compatibility.
- Runs on Metal without using Apple's deprecated native OpenGL stack.
- Can serve as a robust fallback if MoltenVK initialization fails.

### Disadvantages

- Does not use the custom Vulkan backend.
- Requires careful EGL and native-view integration.
- Runtime shader compatibility must be tested against OpenGL ES rather than desktop OpenGL.
- Adds ANGLE as a substantial build and runtime dependency.

This may be the best first production renderer if visual correctness is more important than maintaining Vulkan identity.

## 4. Cocoa and direct Metal

This backend calls Metal directly, with no Vulkan or OpenGL translation layer.

It provides maximum control over Apple GPU behavior, but it requires a native implementation of rendering resources, frame scheduling, render passes, pipelines, synchronization, texture uploads, and shaders.

There are two materially different versions of this project:

1. **Metal with current Vulkan parity:** an atlas-batched sprite renderer with the same current omissions as `VkDrawFeeder`.
2. **Metal with full OpenGL parity:** map render targets, lighting, all composition modes, framebuffer-derived textures, and the supported painter shader system.

The first is a contained but substantial backend. The second requires the architectural extraction described below.

## What a direct Metal renderer entails

### Native application and window lifecycle

A `CocoaWindow`, implemented in Objective-C++, must provide the existing `PlatformWindow` contract using AppKit:

- create and own `NSApplication`, `NSWindow`, and `NSView`;
- create or expose a `CAMetalLayer`;
- convert view size in points to drawable size in pixels;
- react to Retina backing-scale changes and movement between displays;
- translate key, text, mouse, scroll, focus, and window events;
- implement cursor loading, clipboard access, title changes, resize, maximize, and fullscreen;
- coordinate application activation and termination.

This work is common to MoltenVK, ANGLE, and direct Metal.

**Delivered 2026-08-20 (Phase 1), with two contract details this list did not state.** Every bullet above is satisfied by `src/framework/platform/cocoawindow.mm`. But: (a) `m_size` is in **backing pixels** and `m_displayDensity` is the **backing scale factor**, not points and a separate scale — forced by `GraphicalApplication::resize`, which feeds `m_size` to `g_graphics` while laying the UI out at `m_size / m_displayDensity`; `AndroidWindow` already used this convention. Note `g_app.setHUDScale` writes that same variable, so device pixel ratio and user HUD scale are conflated framework-wide. (b) The window **presents its own frames**: `CocoaWindow::swapBuffers` performs acquire/clear/present and the window reports `hasGLContext() == false`, so no `CAMetalLayer` is exposed outside `cocoawindow.mm`.

### Metal device and frame lifecycle

A `MetalRenderBackend` or `MetalContext` would own:

- `id<MTLDevice>`;
- `id<MTLCommandQueue>`;
- the `CAMetalLayer`;
- a bounded number of in-flight frames;
- per-frame command buffers and transient allocations;
- drawable acquisition and presentation;
- render-pass descriptors;
- resize and zero-sized-window behavior;
- GPU completion handlers and deferred resource retirement.

A normal frame would be:

```text
CAMetalLayer.nextDrawable
    |
    v
MTLCommandQueue.commandBuffer
    |
    v
Create MTLRenderPassDescriptor
    |
    v
Create one or more MTLRenderCommandEncoder instances
    |
    v
Bind pipelines, buffers, textures, samplers, and scissors
    |
    v
Encode draws
    |
    v
Present drawable and commit command buffer
```

### Textures and atlas

The CPU-side atlas algorithms can be shared with Vulkan:

- shelf packing;
- content-hash deduplication;
- chunking oversized images;
- stable atlas-slot coordinates;
- occupancy accounting.

The GPU side must be implemented with Metal:

- `MTLTextureType2DArray` for atlas layers;
- `MTLSamplerState` for sampling behavior;
- shared upload buffers or direct replacement regions;
- private GPU storage where beneficial;
- atlas growth and copying old layers into a larger texture;
- safe descriptor/resource replacement while frames are in flight.

### Sprite batching

The Vulkan batch maps naturally to Metal:

| Vulkan concept | Metal equivalent |
|---|---|
| `VkBuffer` | `MTLBuffer` |
| graphics pipeline | `MTLRenderPipelineState` |
| descriptor set | explicit texture, sampler, and buffer bindings |
| push constants | `setVertexBytes` or a small constant buffer |
| dynamic scissor | `setScissorRect` |
| `vkCmdDraw` | `drawPrimitives` |
| `vkCmdDrawIndexed` | `drawIndexedPrimitives` |

The current sprite vertex format and most geometry-generation logic can become shared code. Vulkan-specific handles and structures must not remain in that shared layer.

### Render targets and passes

Full parity requires explicit Metal render targets for operations that OpenGL currently performs through FBOs.

Examples include:

- rendering the map to an off-screen texture;
- scaling or cropping the map texture into its destination rectangle;
- applying the lighting pass;
- composing foreground-map and foreground UI;
- producing textures that are later sampled by another draw;
- cached or intermediate UI rendering;
- screenshots and pixel readback.

Metal requires these relationships to be explicit. Each pass needs:

- color attachment textures;
- load and store actions;
- clear values;
- pixel format compatibility;
- a defined order relative to passes that sample its result;
- recreation when the target size changes.

### Pipeline and state translation

OpenGL permits mutable global state. Metal expresses more state through immutable pipeline objects.

The backend must translate:

- normal, multiply, add, replace, destination, and light composition;
- blend equations;
- alpha-write behavior;
- scissor rectangles;
- opacity and color tint;
- projection, transform, and texture matrices;
- textured versus solid geometry;
- render-target pixel formats;
- material and shader selection.

A pipeline cache would use a key similar to:

```cpp
struct PipelineKey {
    MaterialId material;
    BlendMode blendMode;
    PixelFormat colorFormat;
    bool alphaWrite;
    bool textured;
};
```

The cache would compile or retrieve the corresponding `MTLRenderPipelineState`.

### Shader strategy

The first native Metal shaders are simple:

- textured rectangle vertex and fragment functions;
- sprite-array vertex and fragment functions;
- solid-color geometry;
- multiply-blend variant where the blend state can express it.

Full parity is harder because the established client accepts painter shader concepts built around GLSL.

Affected features include:

- outfit recoloring;
- replacement-color shaders;
- map effects;
- animated shader effects;
- module-defined painter shaders;
- lighting and special composition;
- arbitrary runtime GLSL sources, if those must remain supported.

A direct Metal backend must choose one of these policies:

1. Manually maintain MSL equivalents for every supported built-in shader.
2. Define a backend-neutral material/effect vocabulary and implement it per backend.
3. Compile GLSL to SPIR-V and translate SPIR-V to MSL during the build.
4. Treat arbitrary runtime GLSL as unsupported on Metal.

The preferred long-term direction is a backend-neutral material/effect vocabulary. Runtime user-supplied GLSL should be considered a separate compatibility feature rather than the core renderer contract.

### Resource ownership

Shared client objects should not expose an API-specific object such as a GL texture ID, `VkImage`, or `MTLTexture`.

Instead, shared code should use typed logical handles:

```cpp
struct TextureHandle { uint32_t value; };
struct RenderTargetHandle { uint32_t value; };
struct BufferHandle { uint32_t value; };
struct MaterialHandle { uint32_t value; };
```

The active backend owns the mapping from these handles to native resources. This has several benefits:

- backend headers do not leak into game/UI code;
- resources can be recreated after device or surface loss;
- destruction can be deferred until the GPU finishes using a resource;
- diagnostic labels and resource accounting become centralized;
- tests can use a recording or null backend.

## Target architecture

## Architectural goals

The target renderer should:

- keep platform-window concerns separate from GPU rendering;
- prevent OpenGL, Vulkan, and Metal types from appearing in shared drawing code;
- convert state changes and framebuffer actions into explicit commands;
- support several render passes per frame;
- retain atlas batching and multithreaded map production;
- make resource lifetime and synchronization explicit;
- allow OpenGL to remain functional while a new backend is developed;
- make rendering output testable without a real GPU where possible.

## High-level structure

```text
Game, UI, map, particles, fonts
                |
                v
        Backend-neutral DrawPool
                |
                v
        RenderFrame compiler
        - resolves painter state
        - resolves render targets
        - batches compatible draws
        - creates explicit passes
                |
                v
     Backend-neutral RenderFrame
     - passes
     - commands
     - resource handles
     - material parameters
                |
        +-------+-------+
        |       |       |
        v       v       v
     OpenGL   Vulkan   Metal
     backend  backend  backend
```

The renderer boundary should occur after the client has decided **what** to draw but before API-specific code decides **how** to encode it.

## Platform layer

`PlatformWindow` should remain responsible for operating-system behavior, but expose rendering surfaces through a platform-neutral contract.

One possible interface is:

```cpp
enum class NativeSurfaceType {
    Win32,
    X11,
    Android,
    WebCanvas,
    CocoaMetalLayer,
};

struct NativeSurface {
    NativeSurfaceType type;
    void* display;
    void* window;
    void* layer;
};

class PlatformWindow {
public:
    virtual NativeSurface nativeSurface() const = 0;
    virtual Size drawableSize() const = 0;
    virtual float displayScale() const = 0;
};
```

The renderer should consume `drawableSize()`, not assume that logical window points equal physical pixels.

The exact interface may instead use platform-specific providers or compile-time types. The important requirement is that the generic window interface no longer claims one `void*` means an `HWND` on every platform.

## Renderer interface

A minimal backend interface could be:

```cpp
class IRenderBackend {
public:
    virtual ~IRenderBackend() = default;

    virtual bool initialize(const NativeSurface& surface,
                            const RenderBackendConfig& config) = 0;
    virtual void shutdown() = 0;
    virtual void resize(Size drawableSize) = 0;

    virtual TextureHandle createTexture(const TextureDesc&, const ImageView&) = 0;
    virtual void updateTexture(TextureHandle, const TextureUpdate&) = 0;
    virtual void destroyTexture(TextureHandle) = 0;

    virtual RenderTargetHandle createRenderTarget(const RenderTargetDesc&) = 0;
    virtual void destroyRenderTarget(RenderTargetHandle) = 0;

    virtual MaterialHandle createMaterial(const MaterialDesc&) = 0;
    virtual void destroyMaterial(MaterialHandle) = 0;

    virtual bool render(const RenderFrame& frame) = 0;
    virtual ReadbackResult readPixels(const ReadbackRequest&) = 0;
};
```

The interface should describe capabilities rather than imitate Vulkan or Metal. It should remain small and should not expose low-level command-buffer primitives to ordinary UI or game code.

## Explicit frame representation

The `RenderFrame` should contain a sequence of explicit passes:

```cpp
struct RenderFrame {
    Size drawableSize;
    std::vector<RenderPass> passes;
};

struct RenderPass {
    RenderTargetHandle target;
    LoadAction loadAction;
    Color clearColor;
    std::vector<RenderCommand> commands;
};
```

Representative commands include:

```text
SetViewport
SetScissor
SetMaterial
SetBlendMode
SetTransform
BindTexture
DrawTriangles
DrawIndexedTriangles
Blit
Resolve
```

An even better representation may combine state and geometry into immutable draw packets:

```cpp
struct DrawPacket {
    GeometrySlice geometry;
    TextureHandle texture;
    MaterialHandle material;
    Matrix3 transform;
    Rect scissor;
    Color color;
    float opacity;
    BlendMode blendMode;
};
```

Immutable packets avoid depending on a mutable global-state machine and are easier to sort, batch, record, validate, and test.

## Frame compilation

Existing `DrawPool` objects can remain the production format initially. A new `RenderFrameCompiler` should consume them and produce explicit render passes and packets.

Responsibilities include:

- resolving `onlyOnce` painter-state overrides;
- applying transform, projection, and texture matrices;
- replacing framebuffer bind/release lambdas with explicit pass boundaries;
- converting map-local geometry into screen or render-target coordinates;
- resolving clipping and map-hole behavior;
- assigning materials and blend modes;
- grouping compatible packets into batches;
- declaring dependencies between render targets and later sampling passes.

This compiler is the natural successor to `VkDrawFeeder`. Its output should be usable by every backend.

## Suggested frame passes

A complete frame will likely resemble:

```text
1. Map pass
   Draw terrain, items, creatures, effects, and map overlays into MapColor.

2. Light pass
   Draw light sources into LightMap.

3. Map composition pass
   Combine MapColor and LightMap into the map destination.

4. Creature information / foreground-map pass
   Draw names, health bars, static text, and map-relative foreground elements.

5. Foreground UI pass
   Draw windows, panels, text, icons, particles, and cursor-facing UI.

6. Presentation pass
   Composite or copy the final color to the swapchain/CAMetalLayer drawable.
```

Some of these can be merged when a backend and feature configuration permit it. They should remain logically explicit even if optimized into fewer physical passes.

## Backend responsibilities

Each backend should own:

- native device/context creation;
- swapchain or drawable management;
- native texture, buffer, sampler, shader, and pipeline objects;
- command encoding;
- render-target allocation;
- synchronization and in-flight lifetime;
- pipeline caching;
- GPU diagnostics and labels;
- capability reporting;
- readback and screenshots;
- device/surface loss handling where applicable.

Each backend should not own:

- UI hierarchy;
- game object traversal;
- map drawing rules;
- atlas packing policy, if the policy is shared;
- semantic composition decisions;
- OpenGL-derived lambdas or state IDs.

## Material system

Materials should identify a semantic effect instead of a source-language shader object.

Example built-in materials:

```text
SolidColor
Textured
TexturedReplaceColor
OutfitMask
LightMultiply
MapEffect
Particle
```

Each backend maps a material to its native shader and pipeline implementation:

```text
Material::OutfitMask
    OpenGL -> GLSL program
    Vulkan -> SPIR-V modules and Vulkan pipeline
    Metal  -> MSL functions and Metal pipeline state
```

Material parameters should be described by typed structures or a stable parameter block, not by raw OpenGL uniform locations.

## Texture strategy

The existing Vulkan array atlas is useful but should not become the only texture representation. The target architecture should support:

- ordinary standalone textures;
- atlas-backed immutable sprite regions;
- dynamic render-target textures;
- streaming or animated textures;
- texture arrays where supported;
- CPU-backed images that can be restored after GPU resource loss.

The resource manager can decide whether an image is stored standalone or in an atlas. A draw packet should refer to a logical texture view/region without knowing how the backend stores it.

## Threading and synchronization

The current map thread publishes draw data that the main/render thread consumes. That ownership boundary should remain explicit.

Recommended rules:

- game and map threads never call graphics APIs;
- published draw data is immutable for the rest of the frame;
- only the render thread creates command encoders and submits GPU work;
- resource uploads enter a render-thread upload queue;
- resource deletion is deferred until all frames that reference it have completed;
- per-frame transient vertex/constant storage uses a ring or frame-indexed allocator;
- no backend should require a global `deviceWaitIdle` during normal gameplay.

Metal completion handlers, Vulkan fences, and OpenGL synchronization can implement the same logical frame-retirement mechanism behind the backend interface.

## Error handling and fallback

Backend selection should be explicit and capability-driven:

```text
Requested backend: metal
    -> initialize direct Metal
    -> if unavailable and fallback permitted: initialize ANGLE/OpenGL
    -> otherwise report a clear fatal error
```

On macOS, MoltenVK and direct Metal both ultimately require Metal-capable hardware. A fallback policy should not silently initialize an incomplete renderer after resources have been destructively migrated.

The renderer should expose structured initialization errors such as:

- missing runtime library;
- unsupported device capability;
- surface creation failure;
- shader/pipeline compilation failure;
- incompatible pixel format;
- resource allocation failure.

## Migration plan

## Phase 0: Establish rendering baselines

- ~~Capture representative Windows OpenGL and Vulkan screenshots.~~ **Superseded 2026-08-20:** no Windows machine is available and the visual baseline was resolved as full OpenGL, so the canonical reference is Mesa llvmpipe in CI, with XQuartz as the local reference — see `docs/metal-implementation-plan.md` Phase 0 and `docs/rendering-baselines/`.
- ~~Record known Vulkan deviations.~~ **Done 2026-08-20:** `docs/rendering-baselines/known-deviations.md`, section "Windows Vulkan feeder versus OpenGL".
- ~~Create scenes covering map, lighting, outfits, particles, text, clipping, opacity, all blend modes, and resize/fullscreen behavior.~~ **Done 2026-08-20:** 15 scenes in `docs/rendering-baselines/scenes.json` (16 after `shader-matrix` was later split so its fragment half could be CI-gated), covering all six painter descriptors rather than only the live composition modes. Two qualifications: fullscreen and focus are recorded as state rather than pixels, because toggling fullscreen recreates the window and `hasFocus()` has no consumers; and day/night proved unfreezable in this build, so it was dropped from the lighting scene.
- ~~Establish memory and frame-time baselines.~~ **Deferred to Phase 3 (2026-08-20):** `AUTO_STAT` is compiled out of every build this repository produces (`ENABLE_STATS` is defined in no CMake file), and enabling it instruments hot paths rather than the renderer. Measurement moves to where the legacy and RenderFrame paths can be compared in one environment.

This prevents platform-port work from masking pre-existing renderer differences.

## Phase 1: Native macOS platform layer

- ~~Add `CocoaWindow` in Objective-C++.~~ **Done 2026-08-20:** `src/framework/platform/cocoawindow.{h,mm}`.
- ~~Create a native `.app` target.~~ **Done 2026-08-20:** `CrystalOTC.app` (`src/CMakeLists.txt:1078`), with resources symlinked rather than staged — a bundle that runs, not one that ships.
- ~~Implement input, clipboard, cursors, Retina scaling, resize, fullscreen, focus, and lifecycle behavior.~~ **Done 2026-08-20**, though input is written rather than verified — see the success criterion below.
- ~~Expose a `CAMetalLayer` and drawable size.~~ **Done differently 2026-08-20:** drawable size is exposed (`CocoaWindow::getDrawableSize`), but the layer is **not** — it stays private inside `CocoaWindowImpl`, because the window presents its own frames. Phase 4 has to decide whether the backend takes the drawable from the window or the window keeps presenting.
- ~~Remove the unconditional macOS dependency on X11.~~ **Done 2026-08-20:** platform selection and `find_package(X11)` exclude the Cocoa build (`src/CMakeLists.txt:222-224`), `X11::X11` is linked only on the non-Cocoa branch (`src/CMakeLists.txt:1006-1021`), and the Cocoa branch no longer pulls X11 in through `${OPENGL_LIBRARIES}`: it bypasses `find_package(OpenGL)` and links Apple's OpenGL.framework (`src/CMakeLists.txt:297-316`). `otool -L` shows no `/opt/X11` and no Homebrew paths; CI asserts it. The default (non-Cocoa) macOS build still links XQuartz by design.

Success criterion: a native macOS window can open, process input, resize, and present a clear color.

**Status 2026-08-20: met.** The window opens, resizes (tracking backing scale) and presents a clear colour; `CrystalOTC.app` launches from Finder; and input was verified by driving real events at the running window — keyboard translation against the `Fw::Key` table, a `CGEvent` click producing `Fw::MouseLeftButton`, and both quit routes reaching the client for a graceful shutdown. ~~Text input, scroll and modifier synthesis remain unexercised.~~ **Exercised 2026-08-20 (`fdfb833`):** text input and scroll were correct; modifier synthesis was latching modifiers on permanently and is fixed. ~~and there is still no macOS CI job to exercise any of it automatically.~~ **Corrected 2026-08-20 (Phase 1):** a macOS CI job now exists — `.github/workflows/build-macos.yml`, run `32411659041` on `macos-15`, 17/17 steps green. It builds the Cocoa configuration, runs `ctest`, lints the bundle `Info.plist` (including `NSHighResolutionCapable`, load-bearing for the pixels-vs-points contract), asserts the binary links no X11, and smoke-launches the client until it logs `OpenGL initialization skipped`. It cannot exercise input: a hosted runner has no window server, so keyboard, mouse, text input and scroll remain hand-verified only.

## Phase 2: Stabilize the renderer boundary

- ~~Introduce API-neutral enums for primitive topology, blend modes, shader/material types, and pixel formats.~~ **Done 2026-08-20 (Phase 2), except pixel formats:** `DrawMode`, `BlendEquation`, `ShaderType` and `CompositionMode` are plain `uint8_t` enums in `declarations.h`, and `BlendMode`, `LoadAction`, `BuiltinMaterial` and `ActionIdiom` were added in `src/framework/graphics/render/renderdeclarations.h`. There is **no** pixel-format enum anywhere in `src/framework/graphics/`; texture formats are still chosen inside the GL path.
- ~~Stop defining shared enums with `GL_*` values.~~ **Done 2026-08-20 (Phase 2, `fa8656d`):** no enumerator carries a GL token and `declarations.h` includes no graphics-API header. The numbering moved to `glPrimitiveOf`/`glBlendEquationOf` in `painter.cpp` and `glShaderStageOf` in `shader.cpp`. `ShaderType` turned out to be a *third* GL-valued enum, which the parity survey does not list beside `DrawMode` and `BlendEquation`.
- ~~Introduce logical resource handles.~~ **Done at the boundary only, 2026-08-20 (Phase 2, `71bb824`):** `TextureHandle`, `RenderTargetHandle` and `MaterialHandle` live in `renderdeclarations.h` and are minted deterministically by `renderhandles.h`; `DrawPool::PoolState` carries a `textureHandle` beside its native `textureId`. The shared classes were **not** converted: there is no `ResourceRegistry` in `src/`, and `Texture`, `FrameBuffer` and `PainterShaderProgram` gained no handle members and still own their GL objects directly. `[D §2.1]`'s pass-through registry remains Phase 3 work.
- ~~Convert framebuffer action lambdas into explicit operations.~~ **Declared, not converted, 2026-08-20 (Phase 2, `700b41b`):** each action is now tagged with an `ActionIdiom` and, where it carries geometry, records declared state and coords, so the compiler can express all seven surveyed idioms without executing the callback — an untagged action poisons the program rather than being silently dropped. The `std::function` lambdas themselves remain and the GL path still runs them; `DrawPool::addAction(std::function)` is still present and called from `mapview.cpp`, `uimap.cpp`, `drawpool.cpp` and `drawpoolmanager.cpp`.
- ~~Add a `RenderFrameCompiler` alongside the existing path.~~ **Built, but not yet alongside anything, 2026-08-20 (Phase 2, `797bd79`/`6509905`):** it shipped as `PoolCompiler` plus `FrameAssembler` under `src/framework/graphics/render/`. It has **no production caller** — it is not wired into `DrawPool::release()`, `DrawPool` holds no `PoolProgram`, and the only non-test reference is `PoolCompiler::materialOf` from `mapview.cpp`. Running it beside the GL path, and comparing the two, is Phase 3.
- ~~Implement a recording/null backend for tests.~~ **Done 2026-08-20 (Phase 2, `021112b`):** `RecordingBackend` serialises a `RenderFrame` to stable, human-readable text at fixed float precision. `tests/render/render_boundary_test.cpp` adds 22 cases, taking `ctest` from 22 to 44.

Success criterion: a representative frame can be compiled and inspected without calling OpenGL.

**Status 2026-08-20: met, with one qualification about where it is enforced.** `RenderGoldenFrame.RepresentativeFrameMatchesTheBaseline` compiles a representative pool — direct draws, a composition-mode bracket, a nested transient target with a flip, a map-hole punch and a live scissor — into three passes and six packets, and diffs the recording against a checked-in golden on a runner with no GPU. The qualification: `ctest` runs in exactly one workflow, `.github/workflows/build-macos.yml`. `build-windows.yml` and `render-baseline-linux.yml` compile the new suite but never execute it, so the golden frame is gated on macOS alone.

## Phase 3: Preserve the OpenGL backend

- Make the current OpenGL renderer consume the new frame representation.
- Keep Windows/Linux behavior stable.
- Compare output and performance against Phase 0.

Doing this before full Metal ensures the new abstraction describes real existing behavior instead of an imagined renderer.

## Phase 4A: MoltenVK production path

This phase can occur earlier if rapid macOS Vulkan enablement is preferred.

- Generalize the Vulkan implementation to Windows and macOS.
- Add Metal-surface and portability-extension handling.
- Bundle MoltenVK.
- Validate SPIR-V shaders and swapchain behavior on Apple Silicon.
- Add macOS Vulkan CI and smoke tests.

Success criterion: the current Vulkan renderer runs in a native macOS window with output matching Windows Vulkan.

## Phase 4B: Direct Metal foundation

- Implement `MetalRenderBackend` device and frame lifecycle.
- Add Metal resource tables and deferred destruction.
- Implement solid-color and textured pipelines.
- Implement standalone textures and the sprite array atlas.
- Implement scissor, transforms, opacity, and normal/multiply blending.

Success criterion: login UI and normal gameplay render with parity to the current Vulkan path.

## Phase 5: Render targets and full composition

- Implement map and intermediate render targets.
- Implement map scaling/cropping and framebuffer-derived textures.
- Implement the light pass.
- Complete composition and blend modes.
- Implement screenshots/readback.

Success criterion: Metal output matches the established OpenGL reference scenes apart from documented tolerances.

## Phase 6: Shader and material migration

- Inventory every built-in and module-created shader.
- Define the supported semantic material set.
- Add MSL implementations.
- Decide the policy for arbitrary runtime GLSL.
- Add shader/pipeline compilation diagnostics and caching.

Success criterion: supported effects and outfits behave consistently across OpenGL, Vulkan, and Metal.

## Phase 7: Distribution and hardening

- Bundle dependencies and assets in `CrystalOTC.app`.
- Set deployment targets and supported architectures.
- Add Apple Silicon and, if required, Intel/universal builds.
- Add signing, hardened runtime, and notarization.
- Add macOS crash reporting and GPU diagnostics.
- Exercise sleep/wake, display switching, fullscreen, hot-plugging, and prolonged play.

## Validation matrix

Each backend should be checked against the same functional matrix:

| Area | Representative validation |
|---|---|
| Startup | Login background, fonts, icons, initial resize |
| Map | Floors, tiles, creatures, missiles, effects, camera movement |
| Lighting | Day/night, colored lights, overlapping light sources |
| UI | Opaque and translucent windows, nested clipping, scroll areas |
| Text | Bitmap fonts, TTF fonts, outlined text, alignment |
| Outfits | Mask colors, mounts, addons, animation |
| Composition | Normal, multiply, add, replace, destination, light |
| Shaders | Every built-in material/effect and supported module shader |
| Resources | Atlas growth, large textures, animated textures, GC/reload |
| Windowing | Resize, Retina scale, fullscreen, focus, multiple displays |
| Reliability | Device allocation failure, missing shader, surface recreation |
| Performance | Frame time, draw calls, upload volume, CPU/GPU memory |

Image-based comparison should allow small color and sampling tolerances but must identify missing passes, incorrect alpha, clipping errors, and coordinate differences.

## Scope assessment

The following labels are relative rather than calendar commitments:

| Deliverable | Scope |
|---|---:|
| Current client compiling through XQuartz | Small to medium |
| Native Cocoa window and clear Metal surface | Medium |
| Current Vulkan renderer running through MoltenVK | Medium to large |
| ANGLE/OpenGL ES running over Metal | Medium to large |
| Direct Metal with current Vulkan feature parity | Large |
| Backend-neutral frame architecture plus OpenGL migration | Large |
| Direct Metal with full OpenGL visual parity | Very large |
| Production `.app`, CI, signing, notarization, and hardening | Medium after rendering works |

The existing Vulkan implementation contains roughly 5,800 lines across its context, atlas, batching, feeder, and test-rectangle components. The Win32 and X11 window implementations are each roughly 1,100–1,300 lines. These figures do not predict the exact Metal implementation size, but they show why the work is more than adding a compile flag.

## Decision points to resolve before implementation

1. Is the required macOS visual baseline the current Vulkan output or full OpenGL output?
2. Is MoltenVK acceptable as a shipped dependency?
3. Is ANGLE acceptable as a fallback or primary first renderer?
4. Must runtime/module-supplied GLSL work on macOS?
5. Is Apple Silicon sufficient initially, or is Intel/universal support required?
6. What is the minimum supported macOS version?
7. Must the client be notarized and distributable outside developer machines in the first milestone?
8. Should the long-term renderer interface also accommodate Android and WebAssembly, or only desktop backends initially?

## Recommended direction

The most pragmatic sequence is:

1. Build the native Cocoa window and application bundle foundation.
2. Use MoltenVK to get the current Vulkan renderer running on macOS.
3. In parallel with renderer feature work, extract `VkDrawFeeder` concepts into an API-neutral `RenderFrameCompiler`.
4. Make OpenGL consume the explicit frame model so that it remains the complete behavioral reference.
5. Implement direct Metal behind the same model only if its control, performance, maintenance, or dependency advantages justify the additional backend.

This sequence produces a usable macOS client earlier without abandoning the cleaner target architecture.

If full visual parity is mandatory in the first macOS release, substitute ANGLE over Metal for step 2, then continue the same renderer-boundary extraction.

## Relevant repository files

- `CMakePresets.json`
- `vcpkg.json`
- `src/CMakeLists.txt`
- `src/main.cpp`
- `src/framework/core/graphicalapplication.cpp`
- `src/framework/platform/platformwindow.h`
- `src/framework/platform/platformwindow.cpp`
- `src/framework/platform/win32window.*`
- `src/framework/platform/x11window.*`
- `src/framework/platform/cocoawindow.*`
- `src/framework/core/resourcemanager.cpp`
- `cmake/macos/Info.plist.in`
- `.github/workflows/build-macos.yml`
- `cmake/FindOpenGL.cmake`
- `src/framework/graphics/declarations.h`
- `src/framework/graphics/painter.*`
- `src/framework/graphics/texture.*`
- `src/framework/graphics/framebuffer.*`
- `src/framework/graphics/shader*`
- `src/framework/graphics/drawpool.*`
- `src/framework/graphics/render/*`
- `tests/render/render_boundary_test.cpp`
- `src/framework/graphics/vulkan/*`
- `data/shaders/vulkan/*`

## External implementation references

The references below are grouped by implementation concern. Prefer these primary vendor sources over tutorials when making platform, API-lifetime, synchronization, or distribution decisions.

### Suggested reading order

Before implementing the first native macOS window and Metal frame, read these in order:

1. [NSApplication](https://developer.apple.com/documentation/appkit/nsapplication) for the application event loop and lifecycle.
2. [NSWindow](https://developer.apple.com/documentation/appkit/nswindow) and [NSView](https://developer.apple.com/documentation/appkit/nsview) for native window and content-view ownership.
3. [Managing your game window for Metal in macOS](https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos) for the AppKit-to-Metal boundary, including point-to-pixel conversion and resize handling.
4. [CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer) and [`drawableSize`](https://developer.apple.com/documentation/quartzcore/cametallayer/drawablesize) for drawable presentation and Retina pixel sizing.
5. [MTLDevice](https://developer.apple.com/documentation/metal/mtldevice) and [setting up a command structure](https://developer.apple.com/documentation/metal/setting-up-a-command-structure) for the core Metal object model.
6. [MTLRenderCommandEncoder](https://developer.apple.com/documentation/metal/mtlrendercommandencoder) and [MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor) for render-pass and pipeline encoding.
7. [Synchronizing CPU and GPU work](https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work) and [resource synchronization](https://developer.apple.com/documentation/metal/resource-synchronization) before designing per-frame buffers and resource retirement.
8. The [MoltenVK runtime user guide](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md) if implementing the Vulkan-on-Metal path.

### Cocoa and AppKit

- [AppKit framework](https://developer.apple.com/documentation/appkit) — entry point for native macOS application, window, view, event, text-input, cursor, clipboard, and display APIs.
- [NSApplication](https://developer.apple.com/documentation/appkit/nsapplication) — owns the macOS event loop, distributes events, and reports application activation and termination.
- [NSWindow](https://developer.apple.com/documentation/appkit/nswindow) — native window behavior, content-view ownership, focus, resizing, minimizing, and fullscreen integration.
- [NSView](https://developer.apple.com/documentation/appkit/nsview) — content view, coordinate conversion, responder-chain participation, and layer backing.
- [NSResponder](https://developer.apple.com/documentation/appkit/nsresponder) — responder-chain contract used by views and windows for keyboard and other events.
- [NSEvent](https://developer.apple.com/documentation/appkit/nsevent) — keyboard, mouse, modifier, scroll, gesture, and event-monitoring data.
- [NSWindowDelegate](https://developer.apple.com/documentation/appkit/nswindowdelegate) — resize, focus, fullscreen, display-change, and close callbacks required by `CocoaWindow`.
- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard) — native clipboard integration.
- [NSCursor](https://developer.apple.com/documentation/appkit/nscursor) — system and custom cursor integration.
- [NSOpenGLContext](https://developer.apple.com/documentation/appkit/nsopenglcontext) — relevant only if a deprecated native OpenGL fallback is deliberately retained; it is not needed for MoltenVK or direct Metal.

AppKit objects that affect the interface should be created and operated from the main thread. The future platform implementation must reconcile AppKit's application loop with CrystalOTC's existing `poll()`-driven loop rather than treating `NSWindow` like a passive Win32 or X11 handle.

### Core Animation and the Metal presentation surface

- [Managing your game window for Metal in macOS](https://developer.apple.com/documentation/metal/managing-your-game-window-for-metal-in-macos) — Apple's focused guide to hosting a `CAMetalLayer` in an AppKit view and keeping drawable dimensions synchronized with a resizable, Retina-aware window.
- [High Resolution Guidelines for OS X](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Introduction/Introduction.html) — background on macOS logical points, backing pixels, scale factors, coordinate conversion, and high-resolution assets. The guide is archived, but the coordinate model remains relevant.
- [CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer) — Core Animation layer whose drawables provide the presentation textures for Metal.
- [`CAMetalLayer.drawableSize`](https://developer.apple.com/documentation/quartzcore/cametallayer/drawablesize) — drawable size in pixels; by default it follows layer bounds multiplied by `contentsScale`.
- [`CAMetalLayer.nextDrawable()`](https://developer.apple.com/documentation/quartzcore/cametallayer/nextdrawable()) — obtains the next presentable drawable and may block or return no drawable under some conditions.
- [CAMetalDrawable](https://developer.apple.com/documentation/quartzcore/cametaldrawable) — presentable texture and presentation-timing interface.
- [CALayer](https://developer.apple.com/documentation/quartzcore/calayer) — backing-scale, bounds, lifecycle, and display integration underlying `CAMetalLayer`.

The client must distinguish logical window size in AppKit points from drawable size in physical pixels. Render-target and swapchain sizing should use `drawableSize`; UI layout should continue using the logical coordinate system expected by the client.

### Metal API foundations

- [Metal framework](https://developer.apple.com/documentation/metal) — central API index for devices, command submission, resources, shaders, pipelines, render passes, synchronization, and debugging.
- [MTLDevice](https://developer.apple.com/documentation/metal/mtldevice) — creates queues, buffers, textures, samplers, libraries, and pipeline states for one GPU.
- [MTLCommandQueue](https://developer.apple.com/documentation/metal/mtlcommandqueue) — ordered source of command buffers submitted to the GPU.
- [MTLCommandBuffer](https://developer.apple.com/documentation/metal/mtlcommandbuffer) — groups encoded GPU work, completion handlers, presentation, and submission.
- [MTLCommandEncoder](https://developer.apple.com/documentation/metal/mtlcommandencoder) — common encoder lifecycle; encoders are lightweight and recreated as command buffers are assembled.
- [MTLRenderCommandEncoder](https://developer.apple.com/documentation/metal/mtlrendercommandencoder) — binds graphics state and encodes draws for one render pass.
- [MTLBlitCommandEncoder](https://developer.apple.com/documentation/metal/mtlblitcommandencoder) — texture/buffer copies, fills, mip generation, and explicit resource synchronization operations.
- [MTLRenderPassDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpassdescriptor) — describes color/depth/stencil attachments and their load/store actions.
- [MTLRenderPipelineDescriptor](https://developer.apple.com/documentation/metal/mtlrenderpipelinedescriptor) — describes shaders, vertex layout, formats, multisampling, and blend state used to create a reusable pipeline state.
- [MTLRenderPipelineState](https://developer.apple.com/documentation/metal/mtlrenderpipelinestate) — compiled immutable graphics pipeline used for rendering.
- [MTLSamplerDescriptor](https://developer.apple.com/documentation/metal/mtlsamplerdescriptor) — filtering, addressing, LOD, and comparison behavior for sampled textures.
- [Metal feature set tables](https://developer.apple.com/metal/capabilities/) — authoritative capability and limit matrix across Apple and Mac GPU families.

The initial backend should use the established Metal command queue/buffer/encoder APIs unless the minimum deployment target and project goals explicitly justify adopting Metal 4-only interfaces.

### Metal resources and synchronization

- [Resource fundamentals](https://developer.apple.com/documentation/metal/resource-fundamentals) — common buffer/texture ownership, storage modes, hazard tracking, heaps, and residency topics.
- [Buffers](https://developer.apple.com/documentation/metal/buffers) — creation and use of untyped GPU/CPU data buffers.
- [Textures](https://developer.apple.com/documentation/metal/textures) — texture descriptors, usage flags, views, formats, and data access.
- [Synchronizing CPU and GPU work](https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work) — multiple in-flight resource instances and semaphore-based frame throttling to avoid CPU/GPU stalls.
- [Resource synchronization](https://developer.apple.com/documentation/metal/resource-synchronization) — access hazards, barriers, fences, events, and synchronization scope.
- [Synchronizing a managed resource in macOS](https://developer.apple.com/documentation/metal/synchronizing-a-managed-resource-in-macos) — important if Intel or discrete-GPU Macs are supported; Apple-family GPUs generally use shared memory differently.
- [Copying data to a private resource](https://developer.apple.com/documentation/metal/copying-data-to-a-private-resource) — staging uploads from CPU-visible memory to GPU-private buffers or textures.

These references should guide the frame-indexed upload allocator and deferred-destruction queue. Resource lifetime must extend until every submitted command buffer that references the resource has completed.

### Metal shaders and pipeline development

- [Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf) — authoritative MSL syntax, address spaces, resource bindings, attributes, and shader-stage behavior.
- [Libraries and functions](https://developer.apple.com/documentation/metal/libraries-and-functions) — compiling, loading, specializing, and retrieving Metal shader functions.
- [Pipeline state creation](https://developer.apple.com/documentation/metal/pipeline-state-creation) — creating and reusing render and compute pipeline state objects.
- [MTLVertexDescriptor](https://developer.apple.com/documentation/metal/mtlvertexdescriptor) — maps the shared sprite/geometry vertex layout to Metal shader inputs.
- [MTLFunctionConstantValues](https://developer.apple.com/documentation/metal/mtlfunctionconstantvalues) — optional shader specialization mechanism for reducing shader duplication.

The semantic material system proposed by this document should map each material to a known MSL vertex/fragment pair and pipeline key. Raw GLSL uniform locations or shader IDs should not cross the backend boundary.

### Metal debugging and performance tools

- [Metal debugger](https://developer.apple.com/documentation/xcode/metal-debugger) — GPU traces, pass/resource inspection, shader debugging, counters, and performance analysis.
- [Capturing a Metal workload in Xcode](https://developer.apple.com/documentation/xcode/capturing-a-metal-workload-in-xcode) — Xcode scheme and frame-capture workflow.
- [Metal debugging types](https://developer.apple.com/documentation/metal/metal-debugging-types) — programmatic capture scopes, shader logs, and GPU diagnostics.
- [Improving your game's graphics performance and settings](https://developer.apple.com/documentation/metal/improving-your-game-s-graphics-performance-and-settings) — device-aware settings and performance workflow.
- [Reducing the memory footprint of Metal apps](https://developer.apple.com/documentation/metal/reducing-the-memory-footprint-of-metal-apps) — resource-allocation and memory-pressure guidance.

The backend should assign labels to command buffers, encoders, textures, buffers, heaps, and pipeline objects so Xcode captures remain understandable.

### MoltenVK and Vulkan portability

- [MoltenVK repository and overview](https://github.com/KhronosGroup/MoltenVK) — implementation status, platform support, build entry points, and release artifacts.
- [MoltenVK runtime user guide](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Runtime_UserGuide.md) — linking/embedding options, required Apple frameworks, Metal-surface creation, loader behavior, and runtime configuration.
- [MoltenVK configuration parameters](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/MoltenVK_Configuration_Parameters.md) — runtime behavior, advertised extensions, queue behavior, performance, and diagnostic configuration.
- [`VK_EXT_metal_surface`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_metal_surface.html) — creates a Vulkan presentation surface from a `CAMetalLayer`.
- [`VK_KHR_portability_enumeration`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_portability_enumeration.html) — opts into enumeration of portability devices such as MoltenVK.
- [`VK_KHR_portability_subset`](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_portability_subset.html) — device extension that reports differences from fully conformant native Vulkan and must be enabled when advertised.
- [Vulkan Loader driver interface on macOS](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderDriverInterface.md) — loader discovery rules for bundled and system Vulkan drivers on macOS.
- [Vulkan validation layers](https://github.com/KhronosGroup/Vulkan-ValidationLayers) — development-time Vulkan correctness diagnostics.

The implementation must choose deliberately between linking MoltenVK directly and using the Vulkan loader with a bundled driver manifest. Mixing a bundled MoltenVK driver with an unintended system installation can create duplicate-driver discovery problems.

### ANGLE over Metal

- [ANGLE repository and platform support](https://chromium.googlesource.com/angle/angle) — official support matrix; the Metal backend supports OpenGL ES 2.0 and 3.0 on macOS.
- [ANGLE development setup and application integration](https://github.com/google/angle/blob/main/doc/DevSetup.md) — building ANGLE, linking EGL/GLES, selecting a backing renderer through `EGL_ANGLE_platform_angle`, and using the shader translator.
- [`EGL_ANGLE_platform_angle`](https://chromium.googlesource.com/angle/angle/+/main/extensions/EGL_ANGLE_platform_angle.txt) — base extension for selecting an ANGLE backend when creating an EGL display.
- [`EGL_ANGLE_platform_angle_metal`](https://chromium.googlesource.com/angle/angle/+/main/extensions/EGL_ANGLE_platform_angle_metal.txt) — Metal-specific ANGLE platform selection.
- [ANGLE extension support](https://github.com/google/angle/blob/main/doc/ExtensionSupport.md) — feature/extension compatibility reference.
- [ANGLE debugging tips](https://github.com/google/angle/blob/main/doc/DebuggingTips.md) — diagnostics and explicitly selecting the Metal renderer on macOS.

CrystalOTC must validate its actual OpenGL ES calls and GLSL ES shaders against the chosen ANGLE build rather than assuming desktop OpenGL/GLEW behavior transfers unchanged.

### CMake and application-bundle integration

- [CMake `FindVulkan`](https://cmake.org/cmake/help/latest/module/FindVulkan.html) — provides `Vulkan::Headers`, `Vulkan::Vulkan`, shader tools, and the optional `Vulkan::MoltenVK` imported target.
- [CMake `MACOSX_BUNDLE`](https://cmake.org/cmake/help/latest/prop_tgt/MACOSX_BUNDLE.html) — builds an executable target as a macOS application bundle.
- [CMake `MACOSX_BUNDLE_INFO_PLIST`](https://cmake.org/cmake/help/latest/prop_tgt/MACOSX_BUNDLE_INFO_PLIST.html) — supplies a custom `Info.plist` template for the bundle.
- [CMake `MACOSX_PACKAGE_LOCATION`](https://cmake.org/cmake/help/latest/prop_sf/MACOSX_PACKAGE_LOCATION.html) — places assets, frameworks, and other files inside the bundle structure.
- [CMake `enable_language`](https://cmake.org/cmake/help/latest/command/enable_language.html) — enables Objective-C and Objective-C++ (`OBJC`, `OBJCXX`) for Cocoa/Metal source files.
- [CMake `FindOpenGL`](https://cmake.org/cmake/help/latest/module/FindOpenGL.html) — the XQuartz/GLX OpenGL route is the local reference vehicle for the Metal port, so this is on the critical path rather than out of it (see `docs/metal-implementation-plan.md` Phase 0).

The target bundle should place game resources under `Contents/Resources`, executables under `Contents/MacOS`, and embedded dynamic frameworks/libraries under `Contents/Frameworks`, with runpaths appropriate to that layout.

### Signing, hardened runtime, and distribution

- [Apple distribution overview](https://developer.apple.com/documentation/technologyoverviews/distribution) — App Store and direct-distribution entry points.
- [Code signing](https://developer.apple.com/documentation/security/code-signing-services) — signing concepts and verification APIs.
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — Developer ID, hardened runtime, secure timestamps, notary submission, and Gatekeeper expectations.
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — `notarytool`, automation, log retrieval, and ticket stapling.
- [Hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime) — runtime protections and entitlements relevant to a directly distributed app.

All embedded libraries, including MoltenVK or ANGLE, must be placed at stable bundle-relative paths and included correctly in the final code-signing operation.

### Legacy X11 fallback

- [XQuartz](https://www.xquartz.org/) — maintained X11 server for macOS and the dependency required by the existing `X11Window` route.
- [XQuartz releases](https://www.xquartz.org/releases/) — current installers and supported system information.

XQuartz is not the target native macOS architecture, but it is no longer optional: it is the required local OpenGL reference vehicle for the Metal migration, and a hard requirement of the default macOS CMake path (`src/CMakeLists.txt:209-219`).
