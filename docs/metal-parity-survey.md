# OpenGL Renderer Parity Survey

**Status:** Code survey (pre-implementation-plan inventories)
**Date:** 2026-08-19
**Companion:** `docs/macos-rendering-architecture.md`
**Scope:** Exhaustive inventories of the OpenGL renderer behavior that "Metal with full OpenGL parity" must reproduce: composition/blend state, render targets, action lambdas, shaders, geometry, textures, coordinate conventions, and threading. ~~Every claim carries a `file:line` reference against the repository state on the survey date.~~ **Updated 2026-08-21:** every claim carries a `file:line` reference as of the date of the annotation that introduced it — unannotated claims against 2026-08-19, Phase 1/Phase 2 corrections against their own dates. The symbol name is authoritative; the line number is a hint. Refreshed against HEAD on 2026-08-21 for the citations listed below.

This document answers the three questions the architecture doc left open before an implementation plan could be drafted:

1. What is the exact blend/state table per composition mode?
2. Where, exhaustively, do framebuffers and opaque GL action lambdas enter the draw stream?
3. What does the light pass actually do?

It also settles the shader-policy question in combination with the crystalserver survey (section 5.6).

---

## 1. Frame architecture as built

### 1.1 Draw pools

Five pools, drawn every frame in enum order (`DrawPoolManager::drawLegacy`, `drawpoolmanager.cpp:250-262`, reached from `DrawPoolManager::draw` at `:230`; the compiled path orders the same five in `FrameAssembler::assemble`; enum in `declarations.h:58-65`):

| Order | Pool | Own FBO | Refresh cap | CPU atlas | Notes |
|---|---|---|---|---|---|
| 1 | `MAP` | yes | none | MAP atlas | FBO has `alphaWriting=false` and blend **disabled** during its screen blit (`drawpool.cpp:37-40`) |
| 2 | `CREATURE_INFORMATION` | no | 500 fps | FOREGROUND atlas | `m_alwaysGroupDrawings=true` — draws batched by state hash (`drawpool.cpp:48-51`) |
| 3 | `LIGHT` | no | none | — | not geometry: at most one action lambda per frame (section 3.4); the pool is skipped entirely unless `Client::canDraw(LIGHT)` (`client.cpp:137-138`) and `MapView::isDrawingLights()` (`mapview.cpp:1020`) both hold — online, lights enabled, and world-light intensity < 250 (`lightview.h:44`) |
| 4 | `FOREGROUND_MAP` | no | 500 fps | FOREGROUND atlas | grouped like CREATURE_INFORMATION |
| 5 | `FOREGROUND` | yes | 10 fps | FOREGROUND atlas | FBO sized `viewport / UI-scale` (`graphicalapplication.cpp:423`); one pre-created temp FBO with smoothing (`drawpool.cpp:44-45`) |

A pool with an FBO renders its objects into the FBO, then blits the FBO texture to the backbuffer as a quad requested in `TRIANGLE_STRIP` mode (`drawpoolmanager.cpp:560`, `framebuffer.cpp:126-134`; six-vertex triangle-list data — see the correction in section 6.2). Pools without FBOs draw objects directly to the backbuffer. A pool with an FBO whose content hash did not change skips object execution entirely and only re-blits (`drawpoolmanager.cpp:520-545`) — this caching is a core performance behavior, not an optimization detail.

### 1.2 Threading

- The **map thread** (`g_asyncDispatcher` task, `graphicalapplication.cpp:219`) builds pool object lists: FOREGROUND UI is built here too (`graphicalapplication.cpp:263-265`), and LIGHT + FOREGROUND_MAP are built in **two further parallel async tasks** while MAP builds on the map thread itself (`graphicalapplication.cpp:245-258`).
- The **main thread** executes `g_drawPool.draw()` and swaps buffers. **Updated 2026-08-20 (Phase 1):** the draw is now conditional on both platform branches. On Windows the Vulkan feeder may take the frame instead; elsewhere `g_drawPool.draw()` runs only when `g_window.hasGLContext()`, and a window without one — the Cocoa/Metal window — gets `g_drawPool.consumeAll()` instead. **Updated 2026-08-21 (Phase 4, `2bcd90a`):** that branch is gone. `g_drawPool.draw()` now runs unconditionally on the non-Windows side (`graphicalapplication.cpp:313`) and the GL-context decision moved *into* `DrawPoolManager::draw` (`drawpoolmanager.cpp:230-249`), which tries the frame path first and, on a window with no GL context, consumes the pools rather than falling back to a renderer that does not exist there. One place decides which renderer is live instead of two having to agree. `g_window.swapBuffers()` is still called every frame (`graphicalapplication.cpp:340`), but it stands down whenever a backend presents its own frames — `CocoaWindow::swapBuffers` returns immediately once `setPresentationOwned(true)` has been called (`cocoawindow.mm:573-581`).
- Handoff: each pool double-buffers its object list; `drawObjects` swaps `m_objectsDraw[0/1]` under a `SpinLock` and consumes the `m_shouldRepaint` atomic flag (`drawpoolmanager.cpp:513-519`). **Updated 2026-08-20 (Phase 1):** `drawObjects` is no longer the only consumer — `DrawPoolManager::consumeAll` (`drawpoolmanager.cpp:505-512`) performs the same swap-and-clear without drawing, for frames produced by something other than the GL path, and `VkDrawFeeder::consumeAllPools` is its Vulkan sibling. **Any** future backend that declines a frame owes this consumption. **Updated 2026-08-21 (Phase 3, `360c581`):** there is now a third consumer, `DrawPool::acquireProgram`, which performs the same swap-and-clear and additionally swaps the compiled program into a consumer-owned third slot. It is the render thread's counterpart to `release()`; a frame the compiled path declines falls back to `drawLegacy()` *without* having consumed anything, which is why completeness is peeked before any pool is acquired. The map thread blocks new map production until the flags are consumed (`canDrawMap`, `graphicalapplication.cpp:177-190`).
- Only the main thread touches GL. Pool building threads never issue GL calls — but they *do* capture GL-touching lambdas for later main-thread execution. **Added 2026-08-20 (Phase 1):** two GL entry points sit *outside* the render loop and are therefore not covered by that gate — `Painter::updateGlViewport`, reached from `setResolution`, which the constructor calls before its own `hasGLContext()` guard; and `Texture::create`, reached by font loading at module startup. Both now carry their own `hasGLContext()` early return, and `Texture::create` deliberately keeps `m_image` rather than clearing it, because those pixels are what a non-GL backend uploads later. **Completed 2026-08-21 (Phase 4, `235f919`):** the return half now exists. A backend that has taken those pixels calls `Texture::markUploaded()`, which sets a flag and releases `m_image`, and `create()` stops re-reading the file once `isUploaded()` (`texture.cpp:178-181`). Without it the garbage collector kept treating such a texture as one that had never reached the GPU — freeing the copy, which `create()` then restored from disk on every frame the texture was drawn. This was latent, not new: XQuartz's libGL returns harmlessly with no current context while Apple's OpenGL.framework segfaults, and the shipped Windows Vulkan path had been relying on the same luck. A backend that renders without a GL context inherits this obligation for any *future* out-of-loop GL entry point.

---

## 2. Composition and blend inventory

### 2.1 The exact blend table (`painter.cpp:317-341`)

| CompositionMode | GL call | Effective formula |
|---|---|---|
| `NORMAL` | `glBlendFuncSeparate(SRC_ALPHA, ONE_MINUS_SRC_ALPHA, ONE, ONE)` | rgb: classic src-over; **alpha: additive** (dstA + srcA) |
| `MULTIPLY` | `glBlendFunc(DST_COLOR, ONE_MINUS_SRC_ALPHA)` | dst·src + dst·(1−srcA) |
| `ADD` | `glBlendFunc(ONE_MINUS_SRC_COLOR, ONE_MINUS_SRC_COLOR)` | **not classic additive**: (src+dst)·(1−src) |
| `REPLACE` | `glBlendFunc(ONE, ZERO)` | src |
| `DESTINATION_BLENDING` | `glBlendFunc(ONE_MINUS_DST_ALPHA, DST_ALPHA)` | src·(1−dstA) + dst·dstA |
| `LIGHT` | `glBlendFunc(ZERO, SRC_COLOR)` | dst·src |

All six must exist as Metal blend descriptors, but note the actual usage below when prioritizing. **Done 2026-08-21 (Phase 4, `2bcd90a`):** all six exist (`metalpipelines.mm:54-77`). One translation rule is not visible in the table above — `glBlendFunc` applies a single factor pair to all four channels, so a `*_COLOR` factor landing in an alpha slot uses that colour's alpha component and is spelled as the matching `*_ALPHA` factor on the Metal side (`metalpipelines.mm:41-52`). Arithmetically identical; the spelling is what keeps it comparable against this table and what keeps Metal's validation from rejecting a colour factor in an alpha slot.

### 2.2 Who uses which mode

| Mode | Users |
|---|---|
| `NORMAL` | default everywhere |
| `MULTIPLY` | outfit color masks (`creature.cpp:443`), paperdoll masks (`paperdoll.cpp:87`), the light-texture overlay (`lightview.cpp:126`), particles (`particletype.cpp:121`) |
| `ADD` | particles in production (`particletype.cpp:123`; the `.otps` parser accepts only normal/multiply/addition, `particletype.cpp:117-124`), plus the `composition-all` parity fixture (`uicompositionfixture.cpp:38`) |
| `REPLACE`, `DESTINATION_BLENDING`, `LIGHT` | **no *production* callers in C++, Lua bindings, or modules.** **Updated 2026-08-20:** no longer dead — the parity fixture `UICompositionFixture::drawSelf` (`uicompositionfixture.cpp:47-65`) drives all six, and the CI-gated `composition-all` baseline freezes them against a checked-in llvmpipe reference. |

### 2.3 Blend equation

`BlendEquation` supports ADD/MAX/MIN/SUBTRACT/REVERSE_SUBTRACT (`declarations.h:49-56`), but **no code path anywhere sets a non-ADD equation** — the only caller of `Painter::setBlendEquation` is pool-state execution replaying the (always-ADD) state (`drawpool.cpp:557`). **Added 2026-08-20 (Phase 2):** this enum, `DrawMode` and `ShaderType` were each defined *as* their GL constants until `fa8656d` — a fact this survey never recorded, and `ShaderType` is the one most easily missed. All three are plain `uint8_t` now and `declarations.h` includes no GL header; the GL numbering lives in `painter.cpp:36-56` (`glPrimitiveOf`, `glBlendEquationOf`) and `shader.cpp` (`glShaderStageOf`) — three cast sites, not two. See quirk 11 for the hash collision the renumbering exposed. Not exposed to Lua. Metal can support it in the pipeline key but nothing exercises it today.

### 2.4 Alpha writing and blend disable

- `glColorMask(1,1,1,alphaWriting)` (`painter.cpp:353`). Set only by `FrameBuffer::bind` from `m_useAlphaWriting` (`framebuffer.cpp:102`): true for every FBO except the MAP pool FBO (`drawpool.cpp:39`). **Added 2026-08-21 (Phase 3):** that is not the whole picture, and the rest of it matters to any explicit model. `FrameBuffer::release` does **not** restore the value, so it leaks out of nested targets and out of atlas maintenance into whatever draws next — and since atlas maintenance is per pool, the leak crosses pool boundaries. Two consequences. A pool drawing straight to the backbuffer enters with alpha writing **off**, because `drawPool` resets painter state before every target blit; and **no composition draw writes alpha at all**, for the same reason, whichever pool it belongs to. `PoolCompiler` states the value each target is entered with and deliberately does not model the leak, which a producer-thread compile of one pool could not see in any case. It is invisible today because backbuffer alpha never reaches a PNG — both screenshot paths call `Image::setOpacity(255)` (three call sites since the readback route landed: `graphicalapplication.cpp:453`, `:490`, `framebuffer.cpp:238`).
- Blend is disabled outright in three places: the MAP FBO screen blit (`m_disableBlend`, `framebuffer.cpp:127-132`), atlas layer compositing (`textureatlas.cpp` flush), and the UI map-hole punch (`uimap.cpp:86-89`, section 4).

---

## 3. Render-target inventory

Four distinct kinds of render target exist. "Framebuffer-derived textures" is not an edge case — even the GL sprite atlas is FBO-composited.

### 3.1 Pool FBOs (2)

MAP and FOREGROUND, described in section 1.1. Sizing: MAP FBO tracks the map view; FOREGROUND FBO is `viewport / scale` and re-created on resize/scale change (`graphicalapplication.cpp:423`). `FrameBuffer::bind` clears to transparent (or draws a clear-color quad when the clear color is non-alpha) unless `autoClear` is off (`framebuffer.cpp:104-112`).

### 3.2 Temporary (nested) FBOs — all 7 call sites

`DrawPool::bindFrameBuffer/releaseFrameBuffer` (`drawpool.cpp:682-765`) push bind/release **action lambdas** into the object stream; between them, object coordinates are local to the temp FBO. Bind pushes a fresh default painter state; release re-applies the outer state and blits with `FrameBuffer::draw(dest, flipDirection)`. Temp FBOs are pooled per drawpool and nestable (`m_bindedFramebuffers` counter). The ~~`vkFbMarker/vkFbSize/vkFbDest/vkFbFlip/vkFbOpacity`~~ **`fbMarker/fbSize/fbDest/fbFlip/fbOpacity`** fields on `DrawObject` (`drawpool.h:223-227`) already encode these boundaries declaratively — the frame compiler should promote exactly this data to the primary representation. **Updated 2026-08-20 (Phase 2):** the `vk` prefixes were dropped (`700b41b`) — they were never Vulkan-specific. The promotion happened: `PoolCompiler` (`src/framework/graphics/render/poolcompiler.cpp:255-330`) splits the object stream at these markers into a transient-target pass plus one packet in the outer pass sampling it, and handles them *before* the `ActionIdiom` switch because the shipped Vulkan feeder still consumes raw 1/2. The class is named `PoolCompiler` (plus `FrameAssembler`), not `RenderFrameCompiler`, ~~and it has no production caller yet.~~ **Updated 2026-08-21:** it has one — `DrawPool::release()` calls `compilePublishedObjects()` (`drawpool.cpp:384`), which runs `PoolCompiler::compile` (`drawpool.cpp:460`) **outside** `release()`'s lock, between its two lock scopes: no consumer may touch the published list until the repaint flag is set, so that window belongs to the producer alone (`drawpool.cpp:377-389`). It is behind the static `DrawPool::setCompileFrames` switch (`drawpool.h:140-141`), default **off** (`drawpool.cpp:31`). ~~Nothing in the shipping frame path reads the resulting `PoolProgram`.~~ **Corrected 2026-08-21:** the shipping frame path reads it through `DrawPool::acquireProgram()` (`drawpool.cpp:401`) and `hasUsableProgram()` (`:420`), both called by `DrawPoolManager::drawFrame` (`drawpoolmanager.cpp:296-321`) — as sections 1.2 and 10 of this document already say. `getCompiledProgram()` (`drawpool.h:145`) remains the test-only peek, consumed by `tests/render/render_boundary_test.cpp`.

| Site | Purpose | Flip |
|---|---|---|
| `creature.cpp:155-167` | UI creature preview (battle list, outfit window): compose outfit+masks at native size, blit into widget rect | none |
| `creature.cpp:460-462` | outfit shader with `useFramebuffer` (Outline): render creature into FBO, blit through shader | none |
| `thingtype.cpp:775-780` (`drawWithFrameBuffer`) | thing rendered via FBO when `g_drawPool.shaderNeedFramebuffer()` (`thingtype.cpp:829`) | none |
| `uiitem.cpp:53-68` | item widget: draw item at native size, blit centered 1:1 or shrink-to-fit | **h/v flip** via `m_flipDirection` |
| `uieffect.cpp:49-51` | effect widget, same pattern | none |
| `uimissile.cpp:50-52` | missile widget, same pattern | none |
| `uispellpreview.cpp:136-138` | spell preview widget | none |

All seven are the same idiom: *render small scene at native resolution, blit scaled/flipped into a destination rect*. In the explicit frame model each becomes a short offscreen pass plus one textured draw sampling it.

### 3.3 Texture-atlas layer FBOs

The GL CPU-side atlas (`textureatlas.cpp`) allocates one FBO per 1–N atlas layers per filter group (nearest/linear). **Note added 2026-08-21 (Phase 4):** this whole section is GL-only in practice — the CPU atlases are switched off under the Metal backend, for the reasons recorded at the end of section 10. New textures are composited into a layer by *GPU draw* during `flush()` on the main thread: bind layer FBO, `glDisable(GL_BLEND)`, `clearRect`, draw the source texture as a strip — with an oversized padding draw first for linear-filtered entries (`SMOOTH_PADDING`, src rect extends beyond the texture: `{-pad,-pad,w+2p,h+2p}`, relying on clamp/repeat sampling). Draws then sample the layer FBO's texture with translated src rects (`drawpool.cpp:67-76`). Atlas flush runs after each pool's objects (`drawpoolmanager.cpp:352-353`, `:544-545`).

### 3.4 The light pass — CPU pixels, not GPU geometry

**The architecture doc overstates this pass.** `LightView` (`lightview.cpp`) does not draw light geometry into a LightMap FBO. It:

1. accumulates light sources per frame on the map thread (`addLightSource`, dedup by position/color hash);
2. computes the light bitmap **on the CPU** (`updatePixels`) into a pixel buffer of one RGBA texel per visible tile (double-buffered, swapped under the pool spinlock);
3. enqueues one action lambda (`lightview.cpp:105-119`) that uploads the pixels (`Texture::updatePixels` → `glTexSubImage2D`) and draws a single textured quad over the map destination with `CompositionMode::MULTIPLY`, linear filtering providing the smoothing (`m_texture->setSmooth(true)`, texture sized `mapSize` in tiles, drawn stretched with fractional src coords).

Metal parity for lighting is therefore: **at most one dynamic RGBA8 texture upload plus one multiply-blended quad, in the frames where the LIGHT pool runs at all.** **Corrected 2026-08-20** (established while implementing the `lighting-overlap` baseline): both halves are conditional. The pool never runs unless world-light intensity < 250 (`client.cpp:137-138`, `mapview.cpp:1020`, `lightview.h:44`) — a `hasfulllight` character disables lighting client-side outright, and underground `MapView::updateLight` substitutes `Light{0,215}` for the server's world light (`mapview.cpp:606-612`). Even when it does run, the texture upload is guarded by the light hash controller (`lightview.cpp:94-110`); only the multiply quad is unconditional inside the lambda (`lightview.cpp:126`). The LIGHT pool's other machinery (hash controller with `agroup`, scale factor) feeds the CPU computation, not the GPU.

### 3.5 Readback sites (3)

| Site | Reads | Notes |
|---|---|---|
| `FrameBuffer::extractTexture` (`framebuffer.cpp:198-211`) | any FBO → `glReadPixels` → new `Texture` with `upsideDown` flag | this is the "texture with no source pixels" case the Vk feeder cannot handle |
| `FrameBuffer::doScreenshot` (`framebuffer.cpp:213-245`) | map FBO region → PNG, `image.flipVertically()` | called from `client.cpp:167` with a 3-sprite margin. **Resolved 2026-08-20:** the `glReadPixels(x/3, y/1.5, ...)` offsets are *intentional framing*, not an oddity. The MAP FBO carries a three-tile margin — one logical tile left/top, two right/bottom — so at 32 px sprites the correct offsets are x=32 and y=64, and the `/3` and `/1.5` divisors produce exactly those. Verified: the capture measures 480x352 for a 15x11 viewport. Preserve the crop. |
| `GraphicalApplication::doScreenshot` (`graphicalapplication.cpp:448-459`) | default framebuffer → PNG | Lua-exposed (`g_app.doScreenshot`) |

**Updated 2026-08-21 (Phase 3, `360c581`):** two of the three now have a second route. When the frame path is active, `GraphicalApplication::doScreenshot` and `Client::doMapScreenshot` go through `IRenderBackend::readPixels`, which takes a **top-left** region and returns top-left pixels — so the caller no longer flips, and the map crop is expressed as a one-tile inset instead of `x / 3, y / 1.5`. Identical GL calls underneath; what changed is where the coordinate convention lives. `FrameBuffer::extractTexture` is untouched and still the case a Vulkan-style backend cannot serve.

---

## 4. Action-lambda inventory (complete)

Every site outside the drawpool internals that pushes a GL callback into the object stream, i.e. every lambda the explicit frame model must replace. **Updated 2026-08-20 (Phase 2):** `addAction` is no longer the way to enumerate them — `UIGraph` and `LightView` now record through `addLineStrip`/`addLightOverlay`, which wrap `addDeclaredAction`. Five of the seven carry an `ActionIdiom` tag (`renderdeclarations.h:179-188`); the framebuffer bind/release pair deliberately keeps `Opaque` and is recognised by its `fbMarker` instead, because the shipped Vulkan feeder consumes those as raw 1/2. Two of the seven — the line strips and the light overlay — additionally carry the geometry and state the callback would have produced, so the GL path still runs the lambda while a compiler reads the declared version.

| Site | What the lambda does | Explicit-model replacement |
|---|---|---|
| `drawpool.cpp:703` (bindFrameBuffer) | resize+bind temp FBO, reset painter state | begin-offscreen-pass |
| `drawpool.cpp:740` (releaseFrameBuffer) | release FBO, re-apply outer state, blit with flip | end-pass + textured draw |
| `drawpoolmanager.cpp:496` (preDraw) | `m_framebuffer->prepare(dest, src, colorClear)` — set pool FBO blit quad and clear color; tagged `ActionIdiom::PoolTargetPrepare` since Phase 2 (`drawpoolmanager.cpp:497`) | pass metadata (already mirrored in `m_pendingFbDest/Src`, `drawpool.h:481-482`) |
| `mapview.cpp:106` (registerEvents) | installs `m_pool->onBeforeDraw` (`mapview.cpp:110`): bind the active **map shader** and set its uniforms (center/global coord, zoom, walk offset, fade opacity) right before the MAP FBO→screen blit; and `m_pool->onAfterDraw` (`mapview.cpp:146`), which does `resetShaderProgram()` + `resetOpacity()` after it | material + parameter block on the map-composition draw; the teardown is implicit once every packet carries its own state |
| `uimap.cpp:86-89` (drawSelf) | `glDisable(GL_BLEND)`, draw `Color::alpha` filled rect over the game-view rect (punches a transparent hole through the FOREGROUND FBO so the map shows through), `glEnable(GL_BLEND)`; since Phase 2 the two toggles are tagged `ActionIdiom::BlendOff`/`BlendOn` (`uimap.cpp:87`, `:90`); rect also registered via `setMapHole` | REPLACE-style draw with blend off; the explicit rect already exists (`m_mapHole`, `drawpool.h:499`). `PoolCompiler` reproduces the bracket from the two tags, not from the rect — the rect stays for the Vulkan feeder, which infers the hole by matching it. |
| `uigraph.cpp:55`, `:76` | `g_painter->drawLine(...)` with width + color for skill graphs | since Phase 2 recorded via `addLineStrip` (`drawpool.cpp:593-607`), tagged `ActionIdiom::LineStrip`, carrying screen-space quads from `RenderLines::triangulateStrip` (section 6.3) |
| `lightview.cpp:117` | upload light pixels, draw multiply quad (section 3.4) | since Phase 2 recorded via `addLightOverlay` (`drawpool.cpp:621-640`), tagged `ActionIdiom::LightOverlay`, carrying the declared multiply quad; the upload is declared separately by `addTextureUpload` *inside* the hash-gated branch (`lightview.cpp:105-109`), so a compiled frame uploads in exactly the frames the GL path uploads in |

That is the entire list. The "GL lambdas" problem is seven idioms, not an unbounded surface.

`onBeforeDraw`/`onAfterDraw` hooks exist on every pool (`drawpool.h:117-118`), but — **corrected 2026-08-20** — only the MAP pool ever registers them, both inside `MapView::registerEvents`: the map-shader bind (`mapview.cpp:110`) and its teardown (`mapview.cpp:146`). There is no foreground counterpart; `uimap.cpp:75` is a `g_drawPool.preDraw` callback for the FOREGROUND_MAP pool, a different mechanism.

---

## 5. Shader inventory

### 5.1 Built-in programs (4)

Created in `Painter::Painter` (`painter.cpp:84-91`) from `shader/shadersources.h`:

| Program | Vertex | Fragment | Metal analog |
|---|---|---|---|
| textured | pos+texcoord, `u_TextureMatrix` | `tex(Tex0) * u_Color`, `alpha *= u_Opacity` | core sprite pipeline |
| solid color | pos only | `u_Color` | untextured pipeline |
| replace color | pos+texcoord | `a > 0.01 ? u_Color : 0` | mask/tint pipeline (marked/highlighted creatures) |
| line | pos only | `u_Color` | graph lines |

The vertex stage is **always** `projection × transform × (x, y, 1)`; the fragment contract is **always** `calculatePixel()` with alpha multiplied by `u_Opacity` afterward (`shadersources.h:50-57`). Custom painter shaders replace only `calculatePixel` — they are fragment-only against a fixed vertex stage and fixed uniform ABI.

### 5.2 The uniform ABI

Framework indices (`paintershaderprogram.h:30-45`): projection=0, textureMatrix=1, color=2, opacity=3, time=4, tex0–3=5–8, resolution=9, transform=10.
Client extension (`framework/graphics/shadermanager.h:31-43`): itemId=10, outfitId=11, mountId=12, shaderId=13, mapZoom=14, walkOffset=15, mapCenterCoord=16, mapGlobalCoord=17, textOffset=18, textCenter=19.

**Hazard (latent — see below):** `ITEM_ID_UNIFORM = 10` collides with `TRANSFORM_MATRIX_UNIFORM = 10`. `Painter::drawCoords` writes the transform matrix through index 10 on every draw, so an item shader binding `u_ItemId` at slot 10 would have its uniform location aliased. **Investigated 2026-08-20:** the collision is currently *unreachable*. `registerItemShaders()` only calls `createFragmentShader`, and neither `setupItemShader` nor `setupTextShader` has a caller anywhere in `modules/` or `mods/`, so `u_ItemId` is never bound in shipped code and there is no current visual outcome to preserve. ~~The Metal ABI must still not inherit the shared index space.~~ **Closed 2026-08-20 (Phase 2):** `MaterialParams` (`src/framework/graphics/render/materialparams.h`) is the frozen replacement ABI and has no shared index space at all — named fields at fixed std140 offsets, every offset `static_assert`ed. The collision cannot be inherited by construction. Two further confirmations recorded while freezing it: every C++ bind site for `u_ItemId`/`u_OutfitId`/`u_MountId` sits inside a commented-out example block (`item.cpp:71-75`, `creature.cpp:379-385`, `:416-419`), and no shipped `.frag` references any of them. `mapZoom`, `mapCenterCoord` and `mapGlobalCoord` are the opposite case — written by `MapView` every frame a map shader is bound, read by no shipped shader.

### 5.3 Module shader inventory (`modules/game_shaders/shaders.lua`)

All registered from `.frag` files via `createFragmentShader`; none use `createFragmentShaderFromCode`.

- **Map (13):** Fog (+`tex1` clouds), Rain, Snow (+`tex1` snow), Gray Scale, Bloom, Sepia, Pulse, Old Tv, Party, Radial Blur, Zomg, Heat, Noise
- **Outfit (6):** Rainbow, Ghost, Jelly, Fragmented, cyclopedia-black, **Outline (`useFramebuffer = true` — the only one)**
- **Item (1):** Hover - Desaturate
- **Mount (1):** Rainbow

**Corrected 2026-08-20:** no C++ code registers a shader anywhere. The only other registration site is Lua — `game_exaltationforge` creates six further programs out of `modules/game_exaltationforge/menu/shaders/*.frag` (`game_exaltationforge.lua:247`, `:573`, and the `recreateForgeResultShader` helper at `:545-546`, driven from `:1043`, `:1072` and `playResultFade` at `:1090`, `:1094`), removing and re-creating them mid-session (`g_shaders.removeShader`, `game_exaltationforge.lua:545`, `:1102-1106`). Attached effects only *reference* registry names (`AttachedEffect::setShader` → `g_shaders.getShader`, `attachedeffect.cpp:228`). Multi-texture (`addMultiTexture` → `u_Tex1..3`) is used by exactly two shaders (Fog, Snow).

### 5.4 Where painter shaders apply

- **Map shaders:** bound at MAP-FBO→screen blit time via `onBeforeDraw` (`mapview.cpp:110-144`), with map-specific uniforms and shader-fade (opacity ramp on switch). They are full-screen post-effects over the composed map texture.
- **Outfit/creature shaders:** per-draw pool state (`setShaderProgram(..., onlyOnce=true)`, `creature.cpp:436-437`); if the shader declares `useFramebuffer`, the creature is first rendered into a temp FBO and the shader applies at the blit (`creature.cpp:454-465`).
- **Item/thing shaders:** same two-route pattern via `shaderNeedFramebuffer()` (`thingtype.cpp:829`, `drawpoolmanager.cpp:228`).
- Shader presence keys the pool refresh clock (`m_shaderRefreshDelay`) and the state hash (`drawpool.cpp:135-136`).

### 5.5 Runtime-code path

`createFragmentShaderFromCode` is Lua-exposed (`luafunctions.cpp:507`) but unused by shipped modules. The crystalserver protocol (15.25) carries shader **names/ids only** (`attachedeffects.xml`; `protocolgame.cpp` sends `shader->name`) — no GLSL crosses the wire.

### 5.6 Consequence for the Metal shader policy

The full supported set is: 4 built-ins + 27 registered module programs compiled from 22 `.frag` files + the fixed vertex stage. All against one fixed ABI. (**Corrected 2026-08-20:** the 21 `game_shaders` programs are backed by only 16 unique files — `party.frag`, `radialblur.frag`, `heat.frag` and `noise.frag` are each registered under two or three names — and the exaltation forge adds 6 files and 6 programs; `forge.frag` and `test.frag` ship with no registration site. Registration is also runtime and repeatable — `removeShader` + `createFragmentShader` — so the material registry must support mid-session create/destroy.) This is compatible with either hand-written MSL or a build-time GLSL→SPIR-V→MSL step; a runtime translator is only needed if `createFragmentShaderFromCode` must keep working for out-of-repo Lua.

---

## 6. Geometry and draw modes

### 6.1 Vertex data

`CoordsBuffer` holds **two separate client-side float2 arrays** (positions, texcoords) — no interleaving, no VBOs anywhere in the GL path; `glDrawArrays` sources CPU memory each draw (`painter.cpp:118-170`, `glDrawArrays` at `:166`; `coordsbuffer.h`). The Metal backend therefore owes a per-frame transient vertex allocator; there is no existing buffer-object lifetime to mirror.

### 6.2 Draw methods

`RECT` (2 triangles), `TRIANGLE`, `REPEATED_RECT` (tiling), `BOUNDING_RECT` (frame outline as thin rects), `UPSIDEDOWN_RECT` (declared; **no callers found** — likely vestigial). Pool draws execute as `DrawMode::TRIANGLES` (`drawpoolmanager.cpp:389`); FBO blits and atlas composits **request** `TRIANGLE_STRIP`. **Corrected 2026-08-20 (Phase 2) — this was never accurate:** the "strip" is not a 4-vertex quad and never was. `CoordsBuffer::addQuad` and `addRect` emit **identical six-vertex triangle-list data** (`vertexarray.h:61-79` and `:101-119`), so drawing them as a strip yields the same two real triangles plus two degenerate ones. Blits (`framebuffer.cpp:174-196`, `:126-134`) and atlas composits (`textureatlas.cpp:181-189`) therefore compile to triangles **pixel-identically**, not merely equivalently — no strip support is owed by any backend.

### 6.3 Lines

`Painter::drawLine` (`painter.cpp:172-190`): `GL_LINE_STRIP` with `glLineWidth(width)` and `GL_LINE_SMOOTH`. Used only by `UIGraph` (`uigraph.cpp:65,83`). Metal has no wide or smooth lines — the port must triangulate (screen-space quad strip per segment). Visual tolerance here can be generous; it is analytics graphs, not game art — and **measurably has to be**: XQuartz and llvmpipe already disagree by 1.52% of the frame on identical `graph-lines` geometry (quirk 10; `docs/rendering-baselines/known-deviations.md`).

### 6.4 Batching

Consecutive objects with identical state hashes merge coord buffers (`drawpool.cpp:87-99`); grouped pools coalesce by state hash across the whole list. The state hash covers blend/composition/opacity/clip/shader/transform/color/texture (`drawpool.cpp:119-146`). This CPU-side batching is backend-neutral and should survive unchanged.

---

## 7. Texture inventory

- **Format:** everything is RGBA8/`GL_UNSIGNED_BYTE` (`texture.cpp:398-420`); 1/3/4-channel images normalize on upload. No sRGB formats, no compressed textures, no depth/stencil anywhere.
- **Updates:** `glTexSubImage2D` after first allocation (`texture.cpp:201-220`) — LightView re-uploads through this path only when its light hash changed (`lightview.cpp:94-110`), and not at all in frames where the LIGHT pool is skipped (section 3.4); the satellite map and animated textures also stream.
- **Sampling:** smooth ⇒ LINEAR (+`LINEAR_MIPMAP_LINEAR` with mips), else NEAREST (+`NEAREST_MIPMAP_NEAREST`); wrap is REPEAT or CLAMP_TO_EDGE per-texture (`texture.cpp:344-363`). Four sampler states cover the whole client.
- **Per-texture matrix:** textures own a transform-matrix id in a global registry (`g_textures.getMatrixById`, `painter.cpp:273`), consumed by the GL path only — a packet carries the same `textureMatrixId` on every backend and the Metal one ignores it, per the upside-down bullet below mapping pixel src coords to normalized coords — this is the `u_TextureMatrix` the fixed vertex stage consumes.
- **Upside-down flag:** FBO-backed textures set `setUpsideDown(true)` (`framebuffer.cpp:69`, `framebuffer.cpp:208`), which flips the texture matrix. This is the central GL-vs-render-target orientation mechanism ~~the Metal backend must map onto its own texture-origin convention~~. **Resolved 2026-08-21 (Phase 4, `2bcd90a`):** the Metal backend maps it onto nothing, because it never resolves a matrix id at all. Metal render targets store row 0 at the top, exactly like an uploaded image, so the backend derives `1/w, 1/h` from the resolved texture's size (`metalbackend.mm:55-65`). That is not a shortcut: resolving GL's id there would apply GL's flip and invert every sampled target. The flag stays a GL-only concept.

---

## 8. Coordinate conventions

- **Projection:** top-left-origin pixel space → GL NDC via the documented matrix (`painter.cpp:297-316`): `[2/w, 0, 0; 0, -2/h, 0; -1, 1, 1]`.
- **Scissor:** GL scissor is bottom-left origin; the flip is `glScissor(left, resH - bottom - 1, w, h)` (`painter.cpp:345`). Metal's `setScissorRect` is top-left origin — the flip **disappears** rather than needing translation, and must be clamped to the render-target bounds (Metal validates; GL forgave).
- **FBO blits:** may be horizontally/vertically flipped via explicit flipped quads (`framebuffer.cpp:183-188`), used by `uiitem.cpp:68` (`m_flipDirection`).
- **Screenshots:** CPU `flipVertically()` after readback (`framebuffer.cpp:237`).
- Proposal for the explicit frame model: define all logical render targets as top-left origin; resolve every flip in the frame compiler; forbid orientation knowledge in shaders.

---

## 9. Quirks and hazards to preserve or resolve deliberately

1. **`ADD` composition is not additive** — `(1−src, 1−src)` weights. Particles depend on it. Copy the formula, not the name.
2. **`NORMAL` accumulates alpha additively** (`ONE, ONE` alpha factors) — matters inside FBOs later sampled with their alpha.
3. **MAP FBO blits with blend disabled and writes no alpha** — map pixels replace, never blend, at composition.
4. Uniform index 10 collision (section 5.2) — **latent, not live:** `setupItemShader` and `setupTextShader` have no callers in `modules/` or `mods/`, so `u_ItemId` is never bound and the collision is currently unreachable. ~~Still must not be inherited by the Metal ABI.~~ **Closed 2026-08-20 (Phase 2):** `MaterialParams` retires it structurally — no shared index space, offsets `static_assert`ed. See section 5.2. **Live again as a constraint on the GL side, 2026-08-21 (Phase 3):** `GLBackend` has to upload the frozen block onto the *legacy* slots, where the collision still exists, so it uploads only the map group (14-17) and deliberately not `itemId`. Writing a float to slot 10 would corrupt `u_TransformMatrix` on every later draw. The structural fix holds; what it does not do is make the old index space safe to write through.
5. ~~`glReadPixels(x/3, y/1.5)` looks like a bug.~~ **Resolved 2026-08-20:** intentional framing, see section 3.5. Preserve the crop.
6. Atlas smooth-padding draw samples outside the source texture bounds, relying on clamp behavior (section 3.3).
7. ~~FOREGROUND FBO renders at `viewport/scale` and stretches.~~ **Corrected 2026-08-20:** it does not stretch. `GraphicalApplication::resize` sizes the UI and the FOREGROUND FBO at `viewport/scale`, but the FBO is blitted 1:1 into a destination rect equal to its own size, inside a painter whose resolution is the full physical viewport. A UI-scale change is therefore a genuine image difference, not a rescale — which is what a `display-density` baseline should freeze.
8. Pool FBO skip-if-unchanged (hash) is load-bearing for performance; ~~the explicit model needs an equivalent "reuse last target contents" pass mode.~~ **Done 2026-08-21 (Phase 2):** the equivalent is in the tree. `PoolProgram::contentHash` (`poolprogram.h:52-60`) hashes the **compiled output** — every packet's state plus its arena geometry — deliberately rather than copying the producer's `DrawHashController` state. **Qualified 2026-08-21 (Phase 3, `ca825ac`): one term in that hash is not compiled output, and has to not be.** An `AnimatedTexture` is one Texture whose GL name is re-aimed at the current frame on every tick, while the logical handle a packet carries stays deliberately stable — so an animation advancing produced a byte-identical program, the hash matched, the retained target was reused, and the animation stopped on screen. The native texture id is folded in as well, as hash input only. **Extended 2026-08-21 (Phase 4, `235f919`): the id alone is not enough.** A backend that creates no GL textures leaves every native id at zero, so that term is constant under it and the animation freezes again from the other side — and the id never covered `Texture::updatePixels` overwriting pixels under a stable handle on any backend. `Texture::getContentRevision()`, an atomic bumped by `updateImage`, `updatePixels` and `AnimatedTexture::update`, is the backend-independent form of the same question, and both terms are folded (`poolcompiler.cpp:188-194`): the id because it is free and already resolved, the revision because it is the one that is always true. The same phase also had to stop `AnimatedTexture::update` gating its frame advance on `isEmpty()` — the GL name again — which had held every animation on frame 0 under such a backend. Purity lost, correctness gained: identical output is a stronger justification for reuse than identical input, but only while the output really does describe everything that will be sampled. `FrameAssembler` keeps `m_targetContent`/`m_targetValid` per pool (`frameassembler.h:66-71`): a pool whose `contentHash` matches its retained target contributes **no** passes and is only re-composited (`frameassembler.cpp:104-119`), mirroring `drawObjects`' early return. Pools that draw straight to the backbuffer are never skipped. Targets invalidated without their objects changing — resize, scale change, device loss — are dropped via `FrameAssembler::invalidateRetainedTargets()` (`frameassembler.cpp:56-60`).
9. `onlyOnce` state overrides restore the *previous* state, not defaults (`DrawPool::resetOnlyOnceParameters`, defined inline at `drawpool.h:353-375`; the setters that record the previous value start at `drawpool.cpp:200`) — compiler must replicate exact scoping.
10. ~~Line rendering needs triangulation on Metal (section 6.3).~~ **Done 2026-08-20 (Phase 2):** the triangulation is in the tree and backend-neutral — `RenderLines::triangulateStrip`, recorded by `DrawPool::addLineStrip`, covered by `tests/render/render_boundary_test.cpp`. What remains is the tolerance, not the geometry. **Quantified 2026-08-20:** XQuartz and llvmpipe already differ by 9,967 px — 1.52% of the frame, max channel delta 235 — on identical `graph-lines` geometry, because llvmpipe antialiases wide lines and XQuartz rasterizes them hard-edged. There is therefore no single correct GL line rendering for a triangulated Metal path to match: line scenes may only be compared same-environment, and the triangulated path inherits that tolerance envelope (`docs/rendering-baselines/known-deviations.md`). **Updated 2026-08-20 (Phase 2):** the triangulation now exists in shared code — `RenderLines::triangulateStrip` (`src/framework/graphics/render/linetriangulation.h:43-77`), one quad per segment, zero-length segments skipped. `UIGraph` records it at `addLineStrip` time alongside the still-live `GL_LINE_STRIP` callback (`drawpool.cpp:593-607`), so a compiled frame has the geometry without any backend re-deriving it, and the renderer vocabulary reserves no line material at all (`renderdeclarations.h:153-155`). **Measured against the legacy path 2026-08-21 (Phase 3):** with `GLBackend` executing the triangulated geometry, `graph-lines` differs from the legacy `GL_LINE_STRIP` render by **7,660 px of 656,880 (1.17%), max channel delta 235**, on XQuartz, same binary, same environment. Same vertices, same widths, same colours — only edge pixels, since `GL_LINE_SMOOTH` antialiases and quads do not. On llvmpipe in CI the same comparison measures **8,734 px (1.33%), max channel delta 168** (run `32452811177`) — larger, as predicted, because llvmpipe antialiases wide lines where XQuartz rasterises them hard. This is the **only** scene of eleven that does not match at 0 px in either environment, and it is the only one designed not to. `scenes.json` gives it a `renderPathTolerance` separate from its reference tolerance, so accommodating a deliberate divergence does not weaken a gate that has nothing to do with it.
11. `REPLACE`, `DESTINATION_BLENDING`, `LIGHT` composition modes and non-ADD blend equations are currently dead code — decide whether parity includes them (recommendation: implement the table entries anyway; they are one blend descriptor each). **Updated 2026-08-20 — half settled, half still open.** The three composition modes are no longer dead and the decision is closed: the CI-gated `composition-all` baseline (`uicompositionfixture.cpp`) exercises all six against a checked-in llvmpipe reference, so parity *does* include them and a backend missing a descriptor fails an existing gate. Non-ADD blend equations are still genuinely dead — the only caller of `Painter::setBlendEquation` (`painter.cpp:240`) is the pool-state replay at `drawpool.cpp:493`, and `DrawPool::setBlendEquation` (`drawpool.cpp:226`) / `DrawPoolManager::setBlendEquation` (`drawpoolmanager.h:75`) have no callers in `src/`, `modules/` or `mods/`, nor any Lua binding — so that half remains a decision, recommendation unchanged. **Composition half delivered 2026-08-21 (Phase 4):** the Metal backend implements all six descriptors (`metalpipelines.mm:54-77`), so parity includes them on both backends. The blend-equation half is unchanged and Metal states it in code — the pipeline hardcodes ADD (`metalpipelines.mm:202`) — so reintroducing a non-ADD equation is now a change to two backends rather than one. **Added 2026-08-20 (Phase 2):** dead, but no longer inert. Once the enums stopped carrying GL constants (`fa8656d`), `BlendEquation::MAX` and `CompositionMode::MULTIPLY` both hashed as `1`, and since `PoolState` equality *is* hash equality two states differing only in those fields would have batched together and rendered with the wrong one. The blend-equation term is now tagged into a separate range (`drawpool.cpp:132-140`). Anything that reintroduces raw enumerator values into that hash reopens this.

---

## 10. What the pipeline-state space actually is

Observed live combinations, for the Metal pipeline cache key:

- Fragment function: textured | solid | replace-color | ~~line~~ | one of 27 registered module programs over 22 `.frag` files (fixed vertex stage throughout). **Updated 2026-08-20 (Phase 2):** GL's fourth built-in, the line program, is deliberately **not** a material — `BuiltinMaterial` reserves no slot for it (`renderdeclarations.h:147-157`) because `UIGraph`'s lines are triangulated into ordinary solid-colour geometry at record time (section 6.3). A Metal pipeline cache keyed off this list must not create a line pipeline; nothing can emit one.
- Blend: all six — NORMAL | MULTIPLY | ADD in production, plus REPLACE | DESTINATION_BLENDING | LIGHT under the CI-gated `composition-all` baseline (updated 2026-08-20)
- Alpha write: on | off (off only for MAP FBO passes)
- Color format: single RGBA8/BGRA8 everywhere
- Blend disabled: MAP blit, atlas compositing, hole punch

That is on the order of **25–30 live pipeline states** — comfortably enumerable, no runtime pipeline explosion.

Frame pass graph as built (superset frame):

```
[map thread] build MAP | LIGHT ∥ FOREGROUND_MAP ∥ FOREGROUND-UI object lists
[main thread]
  Pass A*: temp-FBO passes nested in MAP objects (creature previews, shader-FBO things)
  Pass B : MAP objects -> MAP FBO                     (skipped if hash unchanged)
  Pass C : MAP FBO -> backbuffer  [map shader, blend off, no alpha write]
  Pass D : CREATURE_INFORMATION -> backbuffer
  Pass E : light texture upload + multiply quad -> backbuffer
  Pass F : FOREGROUND_MAP -> backbuffer
  Pass A*: temp-FBO passes nested in FOREGROUND objects (item/effect/missile widgets)
  Pass G : FOREGROUND -> FOREGROUND FBO               (10 fps + hash gated; hole punched with blend off)
  Pass H : FOREGROUND FBO -> backbuffer
  (atlas-layer compositing passes interleave after each pool's objects)
  present
```

Every pass boundary above is already explicit in code (pool structure, ~~`vkFbMarker`s~~ **`fbMarker`s**, `prepare` rects) except the atlas flush, which is self-contained. This is the pass list the frame compiler must emit. **Updated 2026-08-20 (Phase 2):** the emitters exist — `PoolCompiler::compile` produces one pool's passes (including the nested transient ones) and `FrameAssembler::assemble` (~~`frameassembler.cpp:64-122`~~ **`frameassembler.cpp:71-151`**) orders the per-pool programs in enum order and interleaves the composition draws. ~~Neither has a production caller yet, and the atlas-flush passes are still not modelled: nothing in `src/framework/graphics/render/` references `TextureAtlas`.~~ **Updated 2026-08-21:** `PoolCompiler::compile` now has a production caller — `DrawPool::release()` → `compilePublishedObjects()` (`drawpool.cpp:374`, `:394`), behind `setCompileFrames`, default off; ~~`FrameAssembler::assemble` still has none outside `tests/render/render_boundary_test.cpp`.~~ **Updated 2026-08-21 (Phase 3, `360c581`): it has one — `DrawPoolManager::drawFrame`, which acquires each pool's program, assembles them and hands the frame to `GLBackend`.** The atlas-flush passes are still not modelled *as passes*, but the work is no longer merely declared: `DrawPoolManager::prepareResources` performs it, for every pool, before any pass runs. The compiler still sets `PoolProgram::requiresAtlasMaintenance` from the pool's atlas, and `PoolProgram::residency` now carries the textures whose GPU residency the render thread must establish — the ones `PoolState::execute` would have created and offered to the atlas. Hoisting all of it in front of the frame rather than interleaving it per pool is equivalent, and the reason is worth stating: a region created during frame N is not consulted until the **producer** runs for frame N+1, because it is `DrawPool::add` that translates a source rect into atlas coordinates. Measured rather than argued — `atlas-resources`, which exercises atlas growth and smooth padding, matches the legacy path at 0 differing pixels. **Qualified 2026-08-21 (Phase 4, `2bcd90a`): under Metal the question does not arise, because there is no CPU atlas.** `DrawPoolManager::init` sets both atlas sizes to -1 when the selected backend is Metal (`drawpoolmanager.cpp:169-181`), for a harder reason than the Vulkan one it joins: `TextureAtlas` keys its regions on a texture's **OpenGL name**, which is zero for every texture a non-GL backend creates, so the whole client would collide on one key — and `TextureAtlas::flush` is unguarded OpenGL throughout. Metal therefore draws from standalone textures, which is already what the compiler emits when no atlas claims one, and `atlas-resources` matching cross-backend at 0 px compares atlas-backed geometry against standalone textures rather than saying anything about Metal's clamp behaviour. Modelling atlas layers as explicit passes stays Phase 5.
