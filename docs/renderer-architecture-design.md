# Renderer Target Architecture Design

**Status:** Design (pre-implementation)
**Date:** 2026-08-19
**Companions:** `docs/macos-rendering-architecture.md` (options and rationale), `docs/metal-parity-survey.md` (as-built inventories)
**Scope:** The concrete target architecture for a backend-neutral renderer supporting OpenGL and Metal (and later, a generalized Vulkan backend). Every structure here is derived from a surveyed behavior, not an imagined renderer; survey section references are given as `[S n.n]`.

## Design goals and non-goals

Goals, in priority order:

1. Game, UI, and module code keep the existing `g_drawPool` producer API — zero churn above the renderer boundary.
2. No GL, Vulkan, or Metal type crosses the boundary: backends consume an explicit, inspectable frame description.
3. Preserve the two behaviors that carry the client's performance: pool-level skip-if-unchanged caching `[S 1.1, S 9.8]` and state-hash draw batching `[S 6.4]`.
4. The OpenGL backend migrates onto the new boundary *first*, so the frame model is validated against the behavioral reference before Metal exists.
5. A recording/null backend makes frames testable without a GPU.

Non-goals:

- Redesigning the DrawPool producer API, the map thread protocol, or the CPU atlas packing policy.
- Supporting arbitrary runtime GLSL on Metal (`createFragmentShaderFromCode` remains GL-only until a build-time translation toolchain exists `[S 5.5-5.6]`).
- Depth/stencil, sRGB, MSAA, or compressed textures — the client uses none of them `[S 7]`; the design leaves room but specifies nothing.

## 1. Layer structure

```
Game / UI / map / particles / fonts / Lua modules
        |                            (unchanged API: g_drawPool.add*, setShaderProgram,
        v                             bindFrameBuffer, setCompositionMode, ...)
DrawPool  (per pool: MAP, CREATURE_INFORMATION, LIGHT, FOREGROUND_MAP, FOREGROUND)
        |  builds DrawObject lists on producer threads, exactly as today
        v
PoolCompiler  (runs at DrawPool::release() on the producer thread)
        |  DrawObjects + vkFbMarker boundaries + PoolState  ->  PoolProgram
        v
PoolProgram  (double-buffered per pool, swapped under the existing SpinLock)
        |  passes, draw packets, vertex data, dynamic texture updates
        v
FrameAssembler  (render thread, replaces DrawPoolManager::draw)
        |  5 PoolPrograms + composition draws + atlas maintenance -> RenderFrame
        v
RenderFrame  (transient, fully explicit, backend-neutral)
        |
   +----+----------+--------------+----------------+
   v               v              v                v
GLBackend    MetalBackend   VulkanBackend    RecordingBackend
                             (target state;   (test double:
                              see §1.1)        no GPU, see §9.1)
```

The renderer boundary is the `RenderFrame`: above it, no graphics API exists; below it, no game semantics exist.

### 1.1 Where the existing Vulkan renderer sits

The current Vulkan code is **not** a backend in the sense above. It is a parallel interception path: `VkDrawFeeder` takes over the published `DrawObject` lists directly (same swap-under-lock protocol as `DrawPoolManager::drawObjects`) and translates what it understands into `VkSpriteBatch` geometry, bypassing `Painter` entirely (`vkfeeder.h:1-24`). Its known gaps — skipped LIGHT pool, ignored painter shaders, skipped action lambdas, no FBO-derived textures — are exactly the things the `RenderFrame` makes explicit.

Two states, and the coexistence rule between them:

- **Today (unchanged during migration):** DrawPool keeps publishing `DrawObject` lists exactly as now; the PoolCompiler is *additive*, consuming the same published lists. The feeder therefore keeps working on Windows untouched while GL and Metal move to the new boundary. Nothing in this design breaks the shipped Vulkan path.
- **Target:** a `VulkanBackend` implements `IRenderBackend` and consumes `RenderFrame` like every other backend, closing the feeder's feature gaps for free (light, shaders, transient targets all arrive as ordinary passes/packets). The existing `vkcontext` (device/swapchain/frame lifecycle), `vkatlas`, and `vkbatch` are reused as that backend's internals; only the feeder's translation role disappears, replaced by the PoolCompiler. At that point `VkDrawFeeder` and the `m_vk*` side-channels on DrawPool/DrawObject retire (they were promoted into PoolCompiler input in the meantime — §10).

The `DrawObject` publish mechanism can only be removed after **both** the GL/Metal backends and the Vulkan path have moved off it; until then it is the compatibility keel of the migration.

Two-stage compilation (PoolCompiler on producer threads, FrameAssembler on the render thread) mirrors today's split exactly: object lists are built on the map thread and executed on the main thread `[S 1.2]`. Compiling at `release()` time keeps the render thread's per-frame work at "assemble and encode," and the PoolProgram double-buffer replaces the current `m_objectsDraw[0/1]` swap one-for-one — same lock, same `shouldRepaint` protocol, no new synchronization. **Added 2026-08-20 (Phase 1):** the FrameAssembler inherits one further obligation — a frame it declines to render must still swap and clear the pool flags, or the map thread blocks permanently in `canDrawMap` (`graphicalapplication.cpp:177-190`). `DrawPoolManager::consumeAll` (`drawpoolmanager.cpp:235-248`) is that operation in backend-neutral form; `VkDrawFeeder::consumeAllPools` is its Vulkan predecessor.

## 2. Resource model

### 2.1 Logical handles

```cpp
struct TextureHandle      { uint32_t id; };   // 0 = invalid/white
struct RenderTargetHandle { uint32_t id; };   // 0 = backbuffer
struct MaterialHandle     { uint16_t id; };   // 0 = Textured (default)
```

Handles are allocated by a render-thread `ResourceRegistry` and mapped to native objects inside each backend (GL texture id, `id<MTLTexture>`, …). Shared classes change as follows:

| Class | Today | Target |
|---|---|---|
| `Texture` | owns GL texture id, uploads via `glTexImage2D` `[S 7]` | owns a `TextureHandle` + CPU-side descriptor (size, smooth, repeat, mipmaps, upside-down); uploads become `TextureUpdate` commands queued to the registry |
| `FrameBuffer` | owns GL FBO + texture `[S 3]` | replaced by `RenderTargetHandle` + retained `TextureHandle`; the class survives only as a thin shim during migration |
| `PainterShaderProgram` | compiles GLSL, uploads uniforms, and owns a process-wide `u_Time` override (`setFixedTime`/`clearFixedTime`, `paintershaderprogram.h:73-75`) that every renderer baseline depends on | becomes a `MaterialHandle` + parameter block description (section 5); GLSL compilation moves into GLBackend, and the time override becomes a FrameAssembler-supplied frame-global (§5.2) |
| `CoordsBuffer` | client-side float arrays `[S 6.1]` | unchanged as producer scratch; PoolCompiler copies into the PoolProgram's vertex arena |

Destruction is deferred: the registry retires a handle only after every in-flight frame referencing it completes (GL: frame fence; Metal: command-buffer completion handler). This replaces today's `g_mainDispatcher.addEvent([id]{ glDeleteFramebuffers... })` pattern with one uniform mechanism.

### 2.2 Render targets

Three lifetime classes, matching the survey's inventory `[S 3]`:

- **Retained targets** — the MAP and FOREGROUND pool targets. Persist across frames; their texture is sampled by a later composition draw *and may be reused without re-rendering* when the pool hash is unchanged. Resized on viewport/scale change (FOREGROUND at `viewport/scale` `[S 9.7]`).
- **Transient targets** — the temp-FBO idiom (7 sites `[S 3.2]`). Requested by size, served from a per-frame pool keyed on dimensions, recycled every frame. Never survive a frame.
- **Atlas layer targets** — retained, written by atlas-maintenance passes, sampled by ordinary draws `[S 3.3]`.

```cpp
struct RenderTargetDesc {
    Size size;                 // pixels
    bool retained;             // false => transient pool
    bool alphaWriting = true;  // MAP target: false  [S 2.4]
    Color clearColor = Color::alpha;
};
```

All targets are RGBA8. All logical coordinates are **top-left origin** (section 7).

### 2.3 Transient geometry

The GL path draws from client memory with no buffer objects `[S 6.1]`. The target model makes that explicit: each PoolProgram owns a growable CPU **vertex arena** (positions + texcoords, still non-interleaved to match the fixed shader ABI); draw packets reference `(offset, count)` slices. Backends upload arenas into per-frame ring buffers (Metal: `MTLBuffer` per in-flight frame; GL: client arrays or a streamed VBO — behavior-identical either way).

## 3. The RenderFrame

```cpp
struct RenderFrame {
    Size drawableSize;
    std::vector<RenderPass> passes;      // in execution order
    std::vector<TextureUpdate> uploads;  // dynamic texture data (light bitmap, streams)
    std::vector<ReadbackRequest> readbacks;
};

struct RenderPass {
    RenderTargetHandle target;           // 0 = backbuffer
    LoadAction load;                     // Clear | Keep
    Color clearColor;
    Rect viewport;                       // defines the projection (top-left pixel space)
    const VertexArena* arena;            // geometry source for this pass's packets
    std::vector<DrawPacket> packets;
};
```

`LoadAction::Keep` is required, not optional: retained pool targets are re-blitted without re-rendering when unchanged `[S 1.1]`, and the atlas layers accumulate across frames with `autoClear=false` `[S 3.3]`. On Metal this is `MTLLoadActionLoad`; on GL it is simply "don't clear".

### 3.1 DrawPacket

One packet = one batched draw. Fields are exactly the surveyed `PoolState` `[drawpool.h:151-167]` minus GL types, plus the geometry slice:

```cpp
struct DrawPacket {
    uint32_t vertexOffset, vertexCount;  // into the pass's arena; triangles
    TextureHandle texture;               // 0 = untextured (solid color)
    TextureHandle extraTex[3];           // multi-texture shaders (Fog, Snow) [S 5.3]
    MaterialHandle material;             // 0 = Textured / Solid (auto by texture)
    const MaterialParams* params;        // null for built-ins; see section 5
    Matrix3 transform;                   // model transform (pool transform stack)
    Matrix3 textureMatrix;               // per-texture pixel->uv [S 7]
    Rect scissor;                        // empty = disabled; top-left origin, pre-clamped
    Color color;
    float opacity;
    BlendMode blend;                     // section 4
    bool blendEnabled = true;            // hole punch, MAP blit, atlas writes [S 2.4]
};
```

Deliberately absent: `BlendEquation` (no live caller; ADD is hardcoded until a user appears `[S 2.3]`), `DrawMode` (everything is triangles after compilation; strips and lines are compiled away — sections 3.2, 6), and `std::function` anything.

### 3.2 Command vocabulary is packets only

The architecture doc suggested `SetViewport / SetMaterial / Blit / ...` state commands. This design rejects mutable command streams in favor of **immutable packets carrying full state**, because the survey shows state combinations are tiny (~25-30 live pipeline states `[S 10]`) and the existing batcher already coalesces identical-state runs `[S 6.4]`. Backends diff consecutive packets to skip redundant binds; correctness never depends on ordering-sensitive state commands. "Blit" is not a command: an FBO blit today is literally a textured strip draw `[framebuffer.cpp:125-133]`, so it compiles to an ordinary packet sampling the target's texture.

## 4. Blend and pipeline state

`BlendMode` reproduces the surveyed table `[S 2.1]` exactly, as data:

```cpp
enum class BlendMode : uint8_t {
    Normal,        // rgb: srcA, 1-srcA | a: 1, 1        (alpha accumulates!)
    Multiply,      // dstColor, 1-srcA
    AddWeird,      // 1-srcColor, 1-srcColor              (particles depend on this)
    Replace,       // 1, 0
    DestBlend,     // 1-dstA, dstA
    LightModulate, // 0, srcColor
};
```

The name `AddWeird` is intentional documentation `[S 9.1]`. All six ship in every backend (each is one descriptor `[S 9.11]`).

The Metal pipeline cache key, sized by the survey:

```cpp
struct PipelineKey {           // ~25-30 live combinations [S 10]
    MaterialHandle material;   // fixed vertex stage throughout [S 5.1]
    BlendMode blend;
    bool blendEnabled;
    bool alphaWrite;
    bool textured;             // selects Textured vs SolidColor built-in when material==0
};
```

GL implements the same key as cached program+state tuples; the abstraction costs GL nothing.

## 5. Material system

### 5.1 The fixed contract

The survey's decisive finding: every shader in the client — built-in or module — shares one vertex stage (`projection × transform × pos`, optional `textureMatrix × uv`) and one fragment ABI (`calculatePixel()`, then `alpha *= opacity`) `[S 5.1-5.2]`. Materials are therefore **fragment variants against a single vertex function**, not arbitrary pipelines.

```cpp
enum class BuiltinMaterial : uint16_t {
    Textured = 0, SolidColor, ReplaceColor, Line /* compiled away, see §6 */,
    FirstModule = 16,   // registry-assigned: Fog, Rain, Outline, ...
};
```

Module shaders register through the existing `ShaderManager` names; registration returns a `MaterialHandle`. Each backend resolves a handle to its native form:

- **GLBackend:** compiles the shipped GLSL exactly as today (`shadersources.h` scaffold + module `.frag`).
- **MetalBackend:** looks up the MSL function produced by the **build-time toolchain**: `module .frag` → glslang → SPIR-V → SPIRV-Cross → MSL, emitted into a compiled `.metallib` at build time. New `.frag` files get translated by the build; no runtime translator ships `[S 5.6]`. A handle with no MSL entry logs once and falls back to `Textured` (never crashes a frame).
- `createFragmentShaderFromCode` registers GL-only materials; on Metal the fallback applies. This is the documented policy from the survey discussion.

### 5.2 Parameter blocks

The uniform ABI becomes one typed struct, replacing per-location uploads:

```cpp
struct MaterialParams {                  // std140-compatible layout
    float time;                          // TIME_UNIFORM: frame-global, pinnable (see below)
    Size  resolution;                    // RESOLUTION_UNIFORM
    // client extension [S 5.2]:
    float itemId, outfitId, mountId, shaderId;
    Point walkOffset;  float mapZoom;
    PointF mapCenterCoord, mapGlobalCoord;
    PointF textOffset, textCenter;
};
```

Projection/transform/textureMatrix/color/opacity stay in the packet (they vary per draw); `MaterialParams` varies per material per frame. The index-10 collision (`ITEM_ID` vs `TRANSFORM_MATRIX` `[S 5.2, S 9.4]`) dies here by construction — the new ABI has no shared index space. The GL backend maps struct fields to the legacy uniform locations so existing `.frag` sources compile unmodified.

**One field is not per-material.** `time` is a frame-global input the FrameAssembler supplies to every material at once, and it must keep the process-wide override `PainterShaderProgram` gained on 2026-08-20 (`setFixedTime`/`clearFixedTime`, `paintershaderprogram.h:73-75`, Lua-exposed as `g_shaders.setFixedTime`, `luafunctions.cpp:518-523`). Pinning it is the only reason an animated shader frame is reproducible at all — nine of the shipped programs animate, and the renderer baselines pin the phase to 2.0 s — so the override has to survive the migration into every backend, not just GL (§9.1).

### 5.3 Map shaders and `useFramebuffer`

- **Map shaders** are the material on the MAP composition packet (Pass C in the frame graph `[S 10]`), with `MaterialParams` filled by MapView — replacing the `onBeforeDraw` lambda `[S 4]`. Shader-fade becomes packet opacity.
- **`useFramebuffer` shaders** (only Outline `[S 5.3]`) keep their surveyed shape: PoolCompiler emits a transient-target pass for the wrapped draws, then a packet sampling it with the shader material — identical to the temp-FBO compilation below.

## 6. Compiling the seven lambda idioms

The complete `addAction` surface `[S 4]` maps as:

| Idiom | Compiled form |
|---|---|
| `bindFrameBuffer`/`releaseFrameBuffer` (7 sites) | PoolCompiler splits the object stream at the existing `vkFbMarker` boundaries `[S 3.2]` into: transient-target pass (packets with pool-local coords) + one packet in the outer pass sampling the transient texture with `vkFbDest`/`vkFbFlip`/`vkFbOpacity`. Nesting recurses. |
| pool-FBO `prepare` | pass metadata on the retained target's composition packet (dest/src already mirrored in `m_vkPendingFbDest/Src`) |
| map-shader `onBeforeDraw` | material + params on the MAP composition packet (§5.3) |
| UI map-hole punch | packet: untextured rect, `Color::alpha`, `blendEnabled=false` — semantics preserved, GL toggling gone; `m_vkMapHole` rect retires |
| `UIGraph` lines | PoolCompiler triangulates: each segment becomes a screen-space quad of `width` px (2 triangles), `SolidColor` material. Replaces `GL_LINE_STRIP`+`glLineWidth`+`GL_LINE_SMOOTH`, which Metal lacks `[S 6.3, S 9.10]`. Anti-aliasing tolerance accepted (analytics graphs). |
| LightView | `TextureUpdate` (the CPU light bitmap `[S 3.4]`) + one `Multiply` quad packet. No pass, no FBO. |

After migration, `DrawPool::addAction(std::function...)` is deleted; attempts to register raw actions become compile errors, which is the enforcement mechanism for "no GL above the boundary."

Atlas maintenance `[S 3.3]` compiles to explicit passes too: per dirty layer, one `Keep`-loaded pass on the layer target with `blendEnabled=false` packets (clear-rect packet, padding draw, main draw). The FrameAssembler interleaves them before the pool passes that sample the layer, making today's implicit flush-ordering an explicit dependency.

## 7. Coordinate and orientation convention

Single rule: **every logical surface is top-left origin, y-down, in pixels.** Consequences, resolving the survey's orientation inventory `[S 8]`:

- The projection matrix (`painter.cpp:249-267`) moves into the backends. GL keeps the y-flipping matrix for the backbuffer and uses a *non-flipping* variant for FBO passes, absorbing today's `upsideDown` texture-matrix mechanism; Metal uses one convention everywhere.
- `Texture::setUpsideDown` and flipped-blit quads (`addHorizontally/VerticallyFlippedQuad`) leave shared code; the compiler emits pre-flipped UVs where `vkFbFlip` demands it, and only the GL backend knows render-target textures are stored bottom-up.
- Scissor rects arrive in packets top-left and **pre-clamped to the target** (Metal validates; GL forgave `[S 8]`). The GL backend applies its own y-flip formula internally.
- Readback results are delivered top-left-origin; the backend flips, not the caller. The `x/3, y/1.5` screenshot offsets `[S 9.5]` are **intentional framing, not an oddity** (resolved 2026-08-20): they select the visible region inside the MAP FBO's three-tile margin, yielding x=32 and y=64 at 32 px sprites. The boundary reproduces that crop, expressed as explicit top-left readback parameters rather than as divisors in `client.cpp`.

## 8. Caching and the frame graph

Pool-level skip-if-unchanged survives structurally: `PoolProgram` carries the pool's content hash; when unchanged, the FrameAssembler emits **no rendering passes** for that pool — only the composition packet sampling the retained target `[S 1.1, S 9.8]`. FOREGROUND's 10 fps refresh gate and shader-refresh clocks stay in DrawPool, untouched.

The assembled superset frame is the survey's pass graph `[S 10]` verbatim: transient passes → MAP target pass → MAP composition (map-shader material, blend off, no alpha write) → CREATURE_INFORMATION → light upload + multiply packet → FOREGROUND_MAP → transient passes → FOREGROUND target pass (hole punch inside) → FOREGROUND composition → readbacks → present.

## 9. Backend interface

```cpp
class IRenderBackend {
public:
    virtual ~IRenderBackend() = default;
    virtual bool initialize(const NativeSurface&, const RenderBackendConfig&) = 0;
    virtual void shutdown() = 0;
    virtual void resize(Size drawableSize) = 0;

    // resource plane (render thread only; called by ResourceRegistry)
    virtual void createTexture(TextureHandle, const TextureDesc&, const ImageView*) = 0;
    virtual void updateTexture(TextureHandle, const TextureUpdate&) = 0;
    virtual void destroyTexture(TextureHandle) = 0;      // deferred internally
    virtual void createRenderTarget(RenderTargetHandle, const RenderTargetDesc&) = 0;
    virtual void destroyRenderTarget(RenderTargetHandle) = 0;
    virtual bool createMaterial(MaterialHandle, const MaterialDesc&) = 0;  // false => fallback

    // frame plane
    virtual bool render(const RenderFrame&) = 0;         // encode, submit, present
    virtual void readPixels(const ReadbackRequest&, ReadbackResult&) = 0;

    virtual RendererCaps caps() const = 0;
};
```

`NativeSurface` follows the companion doc's platform contract (`CocoaMetalLayer` case for macOS).

**Status 2026-08-20 (Phase 1): not implemented as specified.** `CocoaWindow` keeps its `CAMetalLayer` private inside an opaque `CocoaWindowImpl` and adds only `getDrawableSize()`; it does not override `PlatformWindow::getNativeWindowHandle()`, which still defaults to `nullptr`. There is currently no route by which any backend could obtain the layer. Phase 4 must either add the `NativeSurface` accessor this section assumes, or adopt the alternative in the next note.

**Open as of 2026-08-20 (Phase 1): presentation ownership.** Phase 1 put acquire/clear/present inside the *window* — `CocoaWindow::swapBuffers` (driven by the unconditional `g_window.swapBuffers()` at `graphicalapplication.cpp:342`) — so `render()`'s "present" clause and `swapBuffers()` now overlap. Phase 4 has to pick one: the backend takes the drawable from the window, which needs the accessor above, or the window keeps presenting and `render()` ends at "encode, submit". This is a decision to make deliberately, not a defect — recorded so Phase 4 does not discover it late.

Implementations, in migration order:

- **GLBackend** — the migration target for the existing painter; must be pixel-identical to today's output (Phase 3 gate in the companion doc).
- **MetalBackend** — per the companion doc's device/frame lifecycle section; pipeline cache keyed by §4; 2-3 frames in flight; vertex arenas in per-frame ring buffers; labels on everything.
- **RecordingBackend** — the test double (§9.1).
- **VulkanBackend** — later, per §1.1: rebuilds the Windows Vulkan path on this interface, reusing `vkcontext`/`vkatlas`/`vkbatch` and retiring `VkDrawFeeder`. Not required for the macOS milestone; listed so the interface is designed with it in mind (the feeder's atlas/batch model already maps cleanly, per the companion doc's Vulkan→Metal concept table).

### 9.1 RecordingBackend

A backend with no GPU behind it. `initialize` needs no surface, `render()` serializes the received `RenderFrame` — every pass, packet, blend mode, scissor, resource handle, and a content hash of each vertex-arena slice — to a stable JSON/binary form, and resource calls record descriptors. It exists for three jobs:

1. **CI without hardware:** validate PoolCompiler output (pass splitting at FBO markers, hole-punch packets, line triangulation, `onlyOnce` scoping) on headless runners.
2. **Golden-frame regression tests:** compile a fixed scene, diff the recording against a checked-in baseline; refactors that reorder passes, drop state, or change geometry fail a test instead of shipping a rendering bug.
3. **Cross-backend triage:** when GL and Metal disagree visually, record the identical frame both consumed — if the recordings match, the bug is below the boundary in one backend; if not, it is in the compiler. This turns "pixels differ" into a bisectable question. It only works while the `u_Time` pin (§5.2) survives the migration into *every* backend: unpinned, the two frames are captured at different animation phases and there is nothing to compare.

Backend selection is explicit config (`graphics.renderBackend`), which already exists for Vulkan (`drawpoolmanager.cpp:58`); fallback policy per the companion doc's error-handling section.

## 10. What stays, what changes, what dies

| Component | Fate |
|---|---|
| `g_drawPool` producer API, pool structure, thread protocol, hashing/batching | **stays** |
| CPU atlas packing, region translation in `DrawPool::add` | **stays** (flush becomes explicit passes) |
| LightView CPU computation | **stays** (output becomes TextureUpdate + packet) |
| `vkFbMarker`/`m_vkPendingFb*`/`m_vkMapHole` side-channels | **promoted** into PoolCompiler input, then renamed (no longer vk-specific) |
| `Painter` | **dies**; its projection/state logic moves into GLBackend, its matrix helpers into the compiler |
| `FrameBuffer` | **dies** after migration (shim during) |
| GL enums in `declarations.h` (`GL_TRIANGLES`, `GL_FUNC_ADD`) | **replaced** by API-neutral enums (companion doc Phase 2) |
| `DrawPool::addAction(std::function)` | **deleted** after the seven idioms compile (§6) |
| `VkDrawFeeder` | **retired** once the Vulkan backend consumes RenderFrame (out of scope here; the PoolCompiler is its designed successor) |
| `PainterShaderProgram` GLSL compilation | **moves** into GLBackend; class becomes material registration |

## 11. Design decisions and their grounds

1. **Packets over state-command streams** — live state space is ~25-30 pipelines `[S 10]`; immutability buys testability and reordering safety at negligible cost.
2. **Two-stage compilation on existing threads** — preserves the surveyed producer/consumer split and its lock protocol `[S 1.2]` rather than inventing a render-graph scheduler.
3. **`Keep` load action as a first-class citizen** — pool caching and atlas accumulation are load-bearing `[S 9.8, S 3.3]`; a clear-every-pass model would silently destroy the client's performance profile.
4. **Blend table copied by formula, not by name** — `AddWeird` and additive-alpha `Normal` are behavioral contracts `[S 9.1-9.2]`.
5. **Build-time GLSL→MSL, closed shader set** — grounded in the crystalserver finding that shaders are name-referenced, never wire-delivered `[S 5.5]`; runtime translation deferred until a real need exists.
6. **Top-left-everywhere orientation with backend-internal flips** — eliminates the `upsideDown`/flip-quad/scissor-formula triad `[S 8]` as shared-code concerns.
7. **BlendEquation dropped from the packet** — zero live callers `[S 2.3]`; re-adding a field later is cheap, carrying dead state through every backend is not.
8. **Uniform ABI as a struct** — retires the index-10 collision `[S 9.4]` structurally instead of by convention.

## 12. Open questions for the implementation plan

1. Should the GLBackend adopt streamed VBOs when consuming vertex arenas, or keep client arrays for bit-exact Phase 3 comparison first? (Recommendation: client arrays first, VBOs as a follow-up flag.)
2. ~~Does the FOREGROUND pool's pre-created smoothed temp FBO (`drawpool.cpp:40`) need `smooth` as a transient-target descriptor bit, or can transient targets always be non-smooth except that one site?~~ **Answered from source 2026-08-20:** the question's premise was wrong — no single call site consumes it. Temp targets are pooled by *nesting depth*, not by site or size: `bindFrameBuffer` and `releaseFrameBuffer` key on `frameIndex = m_bindedFramebuffers` (`drawpool.cpp:483`, `:508`) and `getTemporaryFrameBuffer(index)` indexes a per-pool vector (`drawpool.cpp:526-534`), with the counter starting at -1 (`drawpool.h:326`). The pre-created buffer is therefore depth 0 for *whichever* FOREGROUND site issues the outermost bind (uiitem, uieffect, uimissile, uispellpreview, creature preview), and it is LINEAR only because `FrameBuffer::m_smooth` defaults to true (`framebuffer.h:86`, applied on resize at `framebuffer.cpp:67`) while every lazily created buffer is explicitly `setSmooth(false)` (`drawpool.cpp:532`). So `smooth` must be a per-target descriptor bit — it cannot be inferred from the site. The same default also makes both retained pool targets LINEAR (`setFramebuffer`, `drawpool.cpp:447-451`).
3. Golden-frame format for the RecordingBackend: full packet dump vs. hash-tree? (Affects CI diff ergonomics only.)
4. ~~Whether the `x/3, y/1.5` screenshot offsets are a bug to fix or behavior to keep.~~ **Resolved 2026-08-20:** intentional framing (`[S 3.5]`). The crop is preserved deliberately; the readback API expresses it as explicit top-left parameters.
5. **Settled from source 2026-08-20 (Phase 1), recorded here because §3 and §9 depend on it:** the platform layer reports `m_size` in **backing pixels** and `m_displayDensity` as the **backing scale factor**, following the `AndroidWindow` precedent. This is forced by `GraphicalApplication::resize`, which feeds `m_size` to `g_graphics` (and thence `glViewport`/`Painter::setResolution`) while laying the UI out at `m_size / m_displayDensity`. `RenderFrame::drawableSize` and `IRenderBackend::resize` are therefore already in the right unit. **Caveat the design must not inherit silently:** `g_app.setHUDScale` writes the *same* variable, so device pixel ratio and user HUD scale are conflated; separating them is a framework change, not a backend one.
