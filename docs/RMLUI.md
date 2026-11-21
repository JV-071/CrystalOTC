# RmlUi in CrystalOTC (HTML/CSS inside OTUI)

CrystalOTC embeds [RmlUi](https://github.com/mikke89/RmlUi) 6.3. A document (`.rml` + `.rcss`, RmlUi's
HTML and CSS) is drawn inside an OTUI widget and lives with the rest of the interface: draw order,
clipping, focus, keyboard and mouse.

The integration is a port of [otclient-rmlui](https://github.com/fellipealbuquerque/otclient-rmlui) and
keeps its Lua API (`g_rml`, `UIRmlWidget`, `RmlWidget`, `RmlWindow`, the global `Rml`) and its RML/RCSS
extensions (`data-drag`, the `item/` / `effect/` / `outfit/` images, the `efeitos` theme). A module
written for that fork runs here unchanged.

## Render backends

| How the client draws | Selected by | RmlUi executor | `g_rml.getBackendName()` |
|---|---|---|---|
| Desktop OpenGL | `OpenGL\|x64` configuration, CMake build | RmlUi's GL3 backend, GLSL 330 | `OpenGL 3.3 (full effects)` |
| ANGLE (Direct3D 11) | `DirectX\|x64` configuration, the shipped `CrystalOTC.exe` | the same backend, OpenGL ES 3 branch | `OpenGL ES 3 (full effects)` |
| Vulkan | `renderBackend = vulkan` in `config.ini` | none yet | `unavailable` |

With the Vulkan renderer RmlUi stays off: `g_rml.isReady()` is `false`, `loadDocument` returns `false`
and the example modules refuse to open. No OpenGL context is ever created for RmlUi's sake.

RmlUi costs nothing until it is used. Nothing is initialised, and no GPU memory is allocated, before
the first RmlUi widget asks for a context (`g_rml.isReady()` is what starts it).

## Examples

| Module | Open with | Shows |
|---|---|---|
| `client_rmlshowcase` | the debug icon in the top bar or **Ctrl+Shift+U** | a tabbed window: data binding, forms, game sprites, native OTUI widgets inside RML (minimap, item, creature), images (img, decorator, nine-patch, carousel), CSS effects, OTUI to RmlUi comparison, Lua and DOM |
| `client_rmloptions` | **Ctrl+Shift+O** or from the showcase | client options in RmlUi, using the same keys as `client_options` |
| `game_rmloutfit` | **Ctrl+Shift+F** or from the showcase | outfit window: rotating preview, colours per part, addons, looktypes; in game it sends `changeOutfit` |
| `game_rmlminimap` | **Ctrl+Shift+M** or from the showcase | RML controls around the native `UIMinimap`; out of game it loads the bundled `data/minimap.otmm` |
| `client_rmldemo` | **Ctrl+Shift+R** | the smallest example |

The Lua helpers live in `modules/corelib/rml.lua` (global `Rml`). The file is written as documentation:
an OTUI vs RmlUi table, data models, text, images, DOM, `Rml.host` and `Rml.watch`. The examples use
nothing else. Their interface text is in Portuguese, as in the fork.

## Build

RmlUi comes from a vcpkg overlay port, `vcpkg-overlays/rmlui`: version 6.3 with FreeType, the debugger
plugin and the Lua plugin built against the client's LuaJIT. It is listed in `vcpkg.json`, so both builds
pick it up without extra steps.

- **MSBuild** (`vc18/otclient.vcxproj`): `FRAMEWORK_RMLUI` and `RMLUI_STATIC_LIB` are defined in
  `vc18/settings.props`. `tools/rmlui/verify-port.ps1` checks that the port is installed and that its
  Lua plugin links against the Lua 5.1 API.
- **CMake**: `TOGGLE_RMLUI` (default `ON`) adds the sources and `find_package(RmlUi)`. With
  `-DTOGGLE_RMLUI=OFF` nothing of RmlUi is compiled or linked. Android and WebAssembly never get it.

`vcpkg-overlays/vcpkg-get-python-packages` is unrelated to RmlUi itself: it lets the pinned ANGLE port
build with the Python 3.15 that current vcpkg checkouts download.

Fonts are loaded from `data/fonts/rml/*.ttf` (Barlow and Share Tech Mono, OFL).

## Quick use

```lua
local window = g_ui.createWidget('RmlWindow', rootWidget)
window:setSize({ width = 560, height = 360 })
window.onEscape = function() window:destroy() end

-- the model has to exist before the document that uses it (data-model="demo")
local model
model = Rml.openModel(window, 'demo', {
  count = 0,
  Add = function(event, delta) model.count = model.count + delta end,
})
window:loadDocument('/modules/my_module/window.rml')
```

`Rml.createWindow{ document = ..., model = 'demo', data = {...} }` does the same in one call. The
helpers live in `modules/corelib/rml.lua`, which is also the reference for them.

```html
<rml>
<head><link type="text/rcss" href="window.rcss"/></head>
<body>
  <div data-model="demo">
    <header data-drag="window">Title <button data-drag="none" data-event-click="Close()">×</button></header>
    <p>Clicks: {{count}}</p>
    <button data-event-click="Add(1)">+1</button>
    <img src="item/3031.png"/>   <!-- a game sprite -->
  </div>
</body>
</rml>
```

A document can also be declared in OTUI:

```otui
RmlWidget
  id: panel
  size: 300 200
  rml-source: /modules/my_module/panel.rml
  rml-debugger: false
```

## API

### `g_rml`

| Function | Description |
|---|---|
| `isReady()` | starts RmlUi on the first call; `false` when there is no executor for the active renderer |
| `supportsAdvancedEffects()` | `true` when filters, shadows, gradients and masks are available |
| `getBackendName()` | name of the executor (see the table above) |
| `setReportEnabled(bool)` / `isReportEnabled()` | a flag kept for API compatibility; no report is written |
| `loadFontFace(path)` | loads an extra TTF/OTF font |
| `utf8(text)` / `latin1(text)` | Latin-1 (server, OTUI) to and from UTF-8 (RmlUi) |
| `getWidgetCount()` / `getWidgets()` | the RmlUi widgets that exist |
| `getContextCount()` | how many of them hold an RmlUi context (a document and its GPU objects) |
| `getReplayedFrameCount()` | RmlUi frames drawn on the GPU since the client started (diagnostics) |

`utf8` and `latin1` follow the client's usual policy (`stdext`): characters that Latin-1 cannot express
are dropped, and malformed UTF-8 yields an empty string.

### `UIRmlWidget` (base of `RmlWidget` and `RmlWindow`)

| Method | Description |
|---|---|
| `loadDocument(path)` → bool | loads and shows the document, then calls `onRmlDocumentLoaded(path)` |
| `unloadDocument()` / `reloadDocument()` | unloads / reloads, clearing the style cache |
| `hasDocument()` / `getDocumentPath()` | |
| `setDebuggerVisible(bool)` / `isDebuggerVisible()` | RmlUi's visual debugger inside the widget |
| `setExtraStyleSheet(rcss)` | extra RCSS applied over the document (themes); `''` removes it |
| `getDocument()` | the `Document` of RmlUi's Lua plugin (`GetElementById`, `QuerySelector`, ...) |
| `getContext()` | the `Context` of RmlUi's Lua plugin (`OpenDataModel`, `ProcessMouseMove`, ...) |

Lua events called on the widget: `onRmlDocumentLoaded(path)`, `onRmlUpdate()` (before
`Context:Update()`) and `onRmlLayout()` (after layout, to measure `offset_*` / `scroll_*`). `RmlWindow`
calls `self.onEscape` on Esc.

The DOM API is the one of [RmlUi's Lua plugin](https://mikke89.github.io/RmlUiDoc/pages/lua_manual.html).
The plugin replaces the global `print`; the client restores its own, so `print` behaves the same whether
or not RmlUi was started.

### Lifetime, data models and text

- **`destroy()` ends the RmlUi side too.** One dispatcher cycle after a widget is destroyed its
  context, document and GPU objects are released; it is safe to call `destroy()` from an event of the
  document itself. Do not keep the context, the document, elements or the model of a destroyed
  window: the first three are gone, and a closed model (or a nested table of it) raises
  `DataModel closed`.
- **Open data models with `Rml.openModel(window, name, data)`** (or `Rml.createWindow` /
  `Rml.createPanel`), not with `getContext():OpenDataModel`. RmlUi's Lua plugin keeps every value of
  an open model alive, functions and what they capture included, until `Context:CloseDataModel(name)`
  is called; the helpers do that when the window goes away. A model opened directly has to be closed
  by the module, outside of any event of that document.
- **The same model name can be open in several windows**; each window has its own model. This and
  the safe closing of models rely on `vcpkg-overlays/rmlui/lua-datamodel-lifetime.patch`: stock
  RmlUi 6.3 indexes open models by name only and crashes some time after a model with nested
  tables is closed (see the port file for the details).
- **Text from the server goes through `Rml.text()` or `Rml.escape()`.** RmlUi works in UTF-8, the
  protocol and OTUI in Latin-1 (`Rml.fromRml()` for the way back). `inner_rml` parses its value as
  RML, so anything a player can type (names, chat) must be passed through `Rml.escape()` before it
  is written there; values bound with `{{field}}` need no escaping.
- **The clipboard is converted**: copying from a document gives the client Latin-1 text, pasting
  into one gives it UTF-8.

### In RML and RCSS

- `data-drag="window"` turns an element into a handle that moves the OTUI widget; `data-drag="none"`
  opts a descendant out (buttons inside a title bar).
- Game sprites as images, once the assets are loaded: `item/<id>.png`, `effect/<id>.png` and
  `outfit/<looktype>-<head>-<body>-<legs>-<feet>-<addons>-<direction>.png` (direction 0 = N, 1 = E,
  2 = S, 3 = W; addons add 1 and 2). Protobuf and classic `.dat/.spr` assets both work. An id that does
  not exist gives a transparent image. An image asked for before the assets are loaded is transparent
  too and reloads by itself. Give the `<img>` a `width`/`height` in RCSS. The suffix `@2x`..`@8x`
  enlarges without blurring: `item/3043@3x.png`.
- An image **file** that cannot be loaded is drawn as a white box, RmlUi's look for a broken image.
- Native OTUI widgets inside a document: reserve the space with an element and call
  `Rml.host(window, 'elementId', g_ui.createWidget('Minimap'))`.
- The `efeitos` theme is active when the executor has the full feature set:
  `@media (theme: efeitos) { .x { box-shadow: ...; decorator: linear-gradient(...); filter: blur(2dp); } }`.
- Text fields (`<input type="text">`, `<textarea>`) keep the keyboard: typing does not trigger game
  shortcuts.

## How it works

```
UI / Lua thread (poll)              UI draw thread                    graphics thread (main)
--------------------------          --------------------------        ----------------------
tick every 16 ms: onRmlUpdate       UIRmlWidget::drawSelf             DrawPool::draw
  Context::SetDimensions              Context::Render() again           action: RmlRenderer::replay()
  Context::Update                       (dropped when unchanged)           RmlBackend runs the commands
  Context::Render()                   g_drawPool.addAction(replay)         and composites into the
    -> RmlRenderer records the        g_drawPool.addTexturedRect(...)      widget's texture
       calls with proxy handles                                         textured rect (premultiplied
    -> changed? repaint()                                               alpha) where the widget is
  onRmlLayout
mouse / keyboard events ->
  Context::Process*
```

RmlUi has no "needs redraw" signal, so the document is rendered into the recorder on every tick and
`RmlRenderer::endFrame()` tells whether the result differs from the last frame it queued. An
identical frame is dropped; a different one is queued and the widget asks the UI for a redraw. A
document that does not change therefore costs no GPU work, and one that changes (animation, hover,
data binding) is redrawn once per tick instead of at the 10 redraws per second the UI falls back to
when nothing asks for more.

- `src/framework/rml/rmlmanager.*`: `g_rml`, the system and file interfaces (files are read through
  `g_resources`), fonts, virtual images, the tick.
- `src/framework/rml/uirmlwidget.*`: the widget: one `Rml::Context` per widget, input, dragging, the
  extra style sheet, the debugger.
- `src/framework/rml/rmlrenderer.*`: the `Rml::RenderInterface` given to RmlUi. It records every call
  and replays it on the graphics thread, mapping proxy handles to real ones.
- `src/framework/rml/rmlbackend.h`: `RmlBackend`, the executor interface the replay runs against, and
  `createRmlBackend()`, which picks the executor for the active renderer.
- `src/framework/rml/rmlbackend_gl.*`: the OpenGL executor. It composites each frame into the widget's
  texture through a framebuffer object.
- `src/framework/rml/RmlUi_Renderer_GL3.*`: RmlUi 6.3's own GL3 backend as vendored by the fork
  (composite into a target framebuffer, shader programs shared between instances, state cleanup), plus
  an OpenGL ES 3 branch for the ANGLE builds.
- `src/client/rmlimages.*`: builds the `item/`, `effect/` and `outfit/` images from the sprites.
- `CompositionMode::PREMULTIPLIED` in the painter: RmlUi 6 works with premultiplied alpha.

### Rules the code relies on

RmlUi is not thread safe: every call from C++ goes through `g_rml.mutex()`.

- **Commands are queued complete.** `RmlRenderer` builds each command locally and only then puts it in
  the queue shared with the graphics thread. Nothing is written to a command after it is queued.
- **The executor leaves the client's GPU state as it found it**, in every entry point: when it is
  created (RmlUi's backend compiles its shaders and leaves no program bound), around each replay, and
  when it is destroyed. The painter caches the bound program and texture; a mismatch makes later draws
  fail silently, including the copy of fonts into the texture atlas.
- **Widgets give up their context before RmlUi shuts down.** `RmlManager::terminate()` releases the
  context of every widget and frees every executor before `Rml::Shutdown()`. Lua collects the remaining
  widgets later, in `lua_close()`, and their destructors must find nothing left to release.
- **A destroyed widget gives up its context on the next dispatcher cycle**, not inside `destroy()`
  (which may be running in an event of that context) and not when Lua collects the widget (a
  document's callbacks usually capture the window, so that would be never).
- **Only frames without lasting effects are dropped.** A frame that creates or releases geometry,
  textures, filters or shaders always reaches the executor, whatever it draws; RmlUi keeps those
  handles. Layer and mask-image handles are compared by order of creation, because they get new
  values on every frame.
- **A handle the executor refused never reaches it again.** RmlUi only holds proxies, so it keeps
  drawing with a shader or filter whose name the executor did not know; those commands are skipped.
- **The tick holds strong references** to the widgets it visits: a Lua callback can drop the last
  reference to another widget in the middle of the loop.

## Tests

`tests/rml` (gtest, CMake build only) covers what needs no GPU: the recording and handle mapping of
`RmlRenderer` against a fake executor (including a concurrent record/replay test, refused handles
and which frames may be dropped), the executor factory without an OpenGL context, the text
conversion, and how `RmlManager::loadImage` resolves the virtual sprite images.

```
cmake --build --preset windows-release --target rml_tests
ctest --test-dir build/windows-release -R Rml
```

What needs the real client (a window, a GPU, the Lua modules, the assets) is checked by the scripts
in `tools/rmlui/verify`: one command per executable, described in the README there.

```
powershell -ExecutionPolicy Bypass -STA -File tools\rmlui\verify\run.ps1 -Exe .\CrystalOTC_gl_x64.exe -Tag gl
```

## Differences from otclient-rmlui

- RmlUi comes from a vcpkg overlay port instead of CMake `FetchContent`, so the MSBuild project can use it.
  The port carries one patch to RmlUi's Lua plugin (data model lifetime).
- The replay runs against `RmlBackend` instead of calling the OpenGL backend directly.
- The OpenGL backend also runs on OpenGL ES 3 (ANGLE).
- The rules above fix defects found while porting: commands queued complete, GPU state around
  creation and destruction, contexts released before shutdown and when a widget is destroyed, refused
  handles, the tick's references, the clipboard encoding.
- A document is redrawn when it changes and only then, instead of on every UI pass.
- Data models are opened through `Rml.openModel` so that they are closed with their window.
- The client's `print` is preserved, and thing ids from documents are range-checked.
- The examples are adapted to this client: top-bar button, the options that exist here, the bundled minimap.

## Not covered yet

- **Vulkan**: no executor. It is the next step of this work.
- **Linux and macOS**: the CMake wiring is in place but was never built or run.
- **In game**: `changeOutfit` from `game_rmloutfit` and the hosted minimap with the live map were not
  exercised against a server.
- The same items the fork leaves out: an OpenGL 2 fallback and the client's bitmap `.otfont` fonts
  inside RmlUi (TTF/OTF only).
- **One open item**: on a busy machine a single destroyed widget object per session is sometimes kept
  referenced until the client exits. Its RmlUi context is gone (no document, no GPU object); what
  holds the last reference is not known. `tools/rmlui/verify/README.md` has the details.

## Licences

RmlUi is MIT licensed (`src/framework/rml/RMLUI_LICENSE.txt`). Barlow and Share Tech Mono are under the
SIL Open Font License (`data/fonts/rml/OFL.txt`, `data/fonts/rml/ShareTechMono-OFL.txt`).
