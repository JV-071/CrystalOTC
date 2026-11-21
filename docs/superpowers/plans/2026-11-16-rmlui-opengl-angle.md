# RmlUi no CrystalOTC, plano 1: OpenGL e ANGLE

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** RmlUi 6.3 (documentos `.rml`/`.rcss` dentro de widgets OTUI) rodando no CrystalOTC nas configurações `OpenGL|x64` e `DirectX|x64` (ANGLE), com a API Lua, o helper `Rml` e os cinco módulos de exemplo do fork de referência.

**Architecture:** O RmlUi entra por um port em `vcpkg-overlays/`. O código do fork é portado no estado do commit `82c2e17`, com uma mudança estrutural: `RmlRenderer` deixa de chamar o backend OpenGL diretamente e passa a reproduzir os comandos gravados contra uma interface de executor (`RmlBackend`). Este plano entrega o executor OpenGL (desktop e ES 3). O executor Vulkan é o plano 2, escrito depois deste, sobre a mesma interface.

**Tech Stack:** C++23 (MSVC v145), RmlUi 6.3, LuaJIT, FreeType, OpenGL 3.3 / OpenGL ES 3 (ANGLE), vcpkg (manifesto + overlay), MSBuild (`vc18/`), CMake + gtest (`tests/`).

**Spec:** `docs/superpowers/specs/2026-11-16-rmlui-design.md`

**Escopo em relação ao spec:** este plano cobre as etapas 1, 2, 3 e 6 da "Ordem de entrega" do spec. As etapas 4 e 5 (executor Vulkan) são o plano 2, `docs/superpowers/plans/<data>-rmlui-vulkan.md`, escrito logo depois que este for implementado, porque seus detalhes dependem da interface `RmlBackend` e do backend GL3 já estarem na árvore. O projeto só está concluído com os dois planos.

## Global Constraints

- RmlUi na versão **6.3**, com FreeType, plugin de debugger e plugin Lua construído sobre o **LuaJIT** do vcpkg.
- A API Lua (`g_rml`, `UIRmlWidget`, `RmlWidget`, `RmlWindow`, global `Rml`) e o RML/RCSS aceitos são os do fork no commit `82c2e17`, sem mudanças.
- Todo C++ novo fica atrás de `#ifdef FRAMEWORK_RMLUI`. Android e WASM ficam sem RmlUi.
- Nada do RmlUi é inicializado antes do primeiro widget RmlUi existir (`g_rml.isReady()` é quem inicializa).
- No modo Vulkan (`renderBackend = vulkan`) nenhum contexto OpenGL é criado por causa do RmlUi. Neste plano, o RmlUi fica desligado nesse modo.
- Sem widget RmlUi aberto, o desenho e a memória do client não mudam.
- Comentários e mensagens de commit em inglês, no estilo do repositório (`feat(rmlui): ...`). Cabeçalho de licença MIT dos arquivos do framework nos arquivos novos.
- Commits: `git add` só dos caminhos listados na tarefa. Nunca `git add -A` (há arquivos de verificação não versionados na árvore).

## Review Focus

1. **Documento inexistente ou RML malformado**: `loadDocument` devolve `false`, registra uma linha `[rmlui]` e o widget fica vazio, sem exceção. Teste na Tarefa 4.
2. **Widget destruído com quadro ainda na fila** (fechar a janela, recarregar o módulo): as liberações rodam na thread gráfica e nada é usado depois de liberado. Testes nas Tarefas 2 e 4.
3. **Texto Latin-1 vindo do servidor ou do OTUI** (acentos) e UTF-8 inválido: conversão correta, sem travar o RmlUi. Teste na Tarefa 4.
4. **Imagem de sprite pedida antes de os assets carregarem, ou com id inválido**: fica transparente, sem exceção, e recarrega quando os assets ficam prontos. Teste na Tarefa 4.
5. **Client em modo Vulkan**: `g_rml.isReady()` é `false`, os módulos de exemplo não quebram e nenhuma fila cresce sem limite. Teste na Tarefa 4.

## Referência e ambiente

**Fork de referência (`REF`).** Clone esparso do fork no commit `82c2e17`. Se a pasta não existir, crie:

```bash
export MSYS_NO_PATHCONV=1
REF="$TEMP/otclient-rmlui-ref" && mkdir -p "$REF" && cd "$REF" \
 && git clone --quiet --filter=blob:none --no-checkout --depth 12 --branch rmlui https://github.com/fellipealbuquerque/otclient-rmlui.git . \
 && git sparse-checkout set --no-cone 'src/framework/rml/' 'src/client/rmlimages.*' 'modules/client_rml*/' 'modules/game_rml*/' 'modules/corelib/rml.lua' 'data/styles/rml/' 'data/styles/10-rmlwidget.otui' 'data/fonts/rml/' 'docs/RMLUI.md' 'src/framework/luafunctions.cpp' 'modules/game_things/things.lua' \
 && git checkout --quiet 82c2e17fd6ac202c119eda519ccb10e5db3a82d1
```

Os diffs do fork em arquivos do engine estão nos commits `abd46bd` e `bf3785d`: `gh api repos/fellipealbuquerque/otclient-rmlui/commits/<sha> --jq '.files[] | select(.filename=="<caminho>") | .patch'`.

**Build MSBuild** (a partir da raiz da worktree; a primeira execução restaura as dependências do vcpkg e pode levar dezenas de minutos, rode em segundo plano):

```powershell
$env:VCPKG_ROOT = 'C:\vcpkg'
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' vc18\otclient.vcxproj /m /p:Configuration=OpenGL /p:Platform=x64 /v:minimal
```

`Configuration=OpenGL` gera `CrystalOTC_gl_x64.exe` na raiz; `Configuration=DirectX` gera `CrystalOTC.exe` (ANGLE).

**Build CMake e testes:**

```powershell
$env:VCPKG_ROOT = 'C:\vcpkg'
cmake --preset windows-release -DOPTIONS_ENABLE_SCCACHE=OFF
cmake --build --preset windows-release --target <alvo>
ctest --test-dir build\windows-release -R <regex> --output-on-failure
```

**Verificação visual.** Usada pelas tarefas 4, 5 e 6.

1. Uma vez: ligar os assets do checkout principal (os dois caminhos são ignorados pelo git):
   ```powershell
   cmd /c mklink /J data\things\1530 <checkout principal>\data\things\1530
   cmd /c mklink /J data\things\1530_mapview <checkout principal>\data\things\1530_mapview
   ```
2. Escrever o roteiro da tarefa em `data/crystalotcrc.lua` (o `init.lua` executa `/crystalotcrc.lua` depois de carregar os módulos). O arquivo **não é versionado**: apague-o antes de cada commit.
3. Rodar o executável da raiz da worktree e esperar ele sair sozinho (o roteiro termina com `g_app.exit()`).
4. Ler o PNG gerado por `g_app.doScreenshot('<nome>.png')` com a ferramenta Read. Ele é gravado no diretório de escrita do client (`g_resources.getWriteDir()`, nesta máquina `%APPDATA%\Crystal\crystalotc\`; confirme na primeira execução).
5. Conferir `crystalotc.log` na raiz: linha `[rmlui] ready`, nenhuma linha `ERROR` nova.

Esqueleto de roteiro:

```lua
local function at(ms, fn) scheduleEvent(fn, ms) end
at(1500, function() modules.client_rmldemo.toggle() end)
at(3500, function() g_app.doScreenshot('rml-demo.png') end)
at(5000, function() g_app.exit() end)
```

---

### Task 1: Port `rmlui` 6.3 com LuaJIT em `vcpkg-overlays/`

**Files:**
- Create: `vcpkg-overlays/rmlui/vcpkg.json`, `vcpkg-overlays/rmlui/portfile.cmake`, `vcpkg-overlays/rmlui/usage`, `tools/rmlui/verify-port.ps1`
- Modify: `vcpkg.json`

**Interfaces:**
- Produces: headers `<RmlUi/Core.h>`, `<RmlUi/Debugger.h>`, `<RmlUi/Lua.h>`; bibliotecas estáticas `rmlui.lib`, `rmlui_debugger.lib`, `rmlui_lua.lib`; pacote CMake `RmlUi` com o alvo `RmlUi::RmlUi`. Em link estático o consumidor precisa da definição `RMLUI_STATIC_LIB` (o alvo CMake já a propaga; o MSBuild a define na Tarefa 3).

- [ ] **Step 1: Escrever o teste (script de verificação do port)**

Salve como `tools/rmlui/verify-port.ps1` (fora da pasta do port, para não entrar no hash de ABI dele):

```powershell
$root = "vc18\vcpkg_installed\x64-windows-static"
$must = "lib\rmlui.lib","lib\rmlui_lua.lib","lib\rmlui_debugger.lib",
        "include\RmlUi\Core.h","include\RmlUi\Lua.h","include\RmlUi\Debugger.h",
        "share\rmlui\RmlUiConfig.cmake"
$missing = $must | Where-Object { -not (Test-Path (Join-Path $root $_)) }
if ($missing) { throw "missing: $($missing -join ', ')" }
$dumpbin = (Get-ChildItem 'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe' | Select-Object -Last 1).FullName
$syms = & $dumpbin /symbols "$root\lib\rmlui_lua.lib"
if (-not ($syms | Select-String 'lua_objlen')) { throw "rmlui_lua.lib was not built against the Lua 5.1 API (LuaJIT)" }
if ($syms | Select-String 'lua_rawlen') { throw "rmlui_lua.lib references the Lua 5.2+ API" }
"rmlui port OK"
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `powershell -File tools\rmlui\verify-port.ps1`
Expected: FAIL com `missing: lib\rmlui.lib, ...`

- [ ] **Step 3: Escrever o port**

`vcpkg-overlays/rmlui/vcpkg.json`:

```json
{
  "name": "rmlui",
  "version": "6.3",
  "description": "RmlUi 6.3 with FreeType, the debugger plugin and Lua bindings built against LuaJIT (CrystalOTC overlay).",
  "homepage": "https://github.com/mikke89/RmlUi",
  "license": "MIT",
  "dependencies": [
    { "name": "freetype", "default-features": false },
    "luajit",
    { "name": "vcpkg-cmake", "host": true },
    { "name": "vcpkg-cmake-config", "host": true }
  ]
}
```

`vcpkg-overlays/rmlui/portfile.cmake`:

```cmake
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO mikke89/RmlUi
    REF 6.3
    SHA512 0
    HEAD_REF master
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DRMLUI_FONT_ENGINE=freetype
        -DRMLUI_LUA_BINDINGS=ON
        -DRMLUI_LUA_BINDINGS_LIBRARY=luajit
        -DRMLUI_SAMPLES=OFF
        -DBUILD_TESTING=OFF
        -DRMLUI_COMPILER_OPTIONS=OFF
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/RmlUi)
vcpkg_copy_pdbs()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

configure_file("${CMAKE_CURRENT_LIST_DIR}/usage" "${CURRENT_PACKAGES_DIR}/share/${PORT}/usage" COPYONLY)
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt" "${SOURCE_PATH}/Source/Debugger/LICENSE.txt")
```

`usage`: as duas linhas `find_package(RmlUi CONFIG REQUIRED)` / `target_link_libraries(main PRIVATE RmlUi::RmlUi)`.

Em `vcpkg.json` (raiz), acrescente à lista `dependencies`: `{ "name": "rmlui", "platform": "!android & !wasm32" }`.

Diferenças deliberadas em relação ao port oficial (versão 6.2 na baseline): sem a feature `lua` presa ao Lua oficial, sem os patches `add-itlib-and-robin-hood` e `skip-custom-find-modules` (o RmlUi usa os contêineres embutidos e instala o próprio `FindLuaJIT.cmake`), sem a edição dos `Header.h`.

- [ ] **Step 3b: Fixar o SHA512 e instalar**

Run: `& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' vc18\otclient.vcxproj /t:VcpkgInstallManifestDependencies /p:Configuration=OpenGL /p:Platform=x64 /v:minimal` (com `VCPKG_ROOT` definido).
A primeira execução falha informando `Actual hash`: copie esse valor para `SHA512` e rode de novo. Se a configuração do RmlUi não achar o LuaJIT, passe `-DLUAJIT_INCLUDE_DIR=${CURRENT_INSTALLED_DIR}/include/luajit` em `OPTIONS` e `-DLUAJIT_LIBRARY=` em `OPTIONS_RELEASE` / `OPTIONS_DEBUG` apontando para `lib/lua51.lib` e `debug/lib/lua51.lib`.

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `powershell -File tools\rmlui\verify-port.ps1`
Expected: `rmlui port OK`

- [ ] **Step 5: Commit**

```bash
git add vcpkg-overlays/rmlui tools/rmlui/verify-port.ps1 vcpkg.json
git commit -m "build(vcpkg): add rmlui 6.3 overlay port with LuaJIT bindings"
```

---

### Task 2: Interface de executor, `RmlRenderer` e testes sem GPU

**Files:**
- Create: `src/framework/rml/rmlbackend.h`, `src/framework/rml/rmlrenderer.h`, `src/framework/rml/rmlrenderer.cpp`, `tests/rml/CMakeLists.txt`, `tests/rml/rmlrenderer_test.cpp`
- Modify: `src/CMakeLists.txt`, `tests/CMakeLists.txt`

**Interfaces:**
- Consumes: pacote `RmlUi` da Tarefa 1.
- Produces:

```cpp
// rmlbackend.h
class RmlTargetTexture;
using RmlTargetTexturePtr = std::shared_ptr<RmlTargetTexture>;

// Executes RmlUi's render calls with real GPU handles. Graphics thread only.
class RmlBackend
{
public:
    virtual ~RmlBackend() = default;
    virtual std::string name() const = 0;                 // "OpenGL 3.3", "OpenGL ES 3"
    virtual bool supportsAdvancedEffects() const = 0;
    virtual Rml::RenderInterface& renderInterface() = 0;
    virtual void beginReplay() = 0;                       // save client GPU state
    virtual void endReplay() = 0;                         // restore it
    virtual void beginFrame(const RmlTargetTexturePtr& target) = 0;
    virtual void endFrame() = 0;
};
using RmlBackendPtr = std::unique_ptr<RmlBackend>;

// rmlrenderer.h
struct RmlRendererHooks
{
    std::function<RmlBackendPtr()> createBackend;                    // graphics thread, first replay
    std::function<ImagePtr(const std::string& source)> loadImage;    // UI thread
    std::function<void(const RmlBackend* backend)> onBackendResult;  // nullptr = no executor
};

class RmlTargetTexture final : public Texture { public: explicit RmlTargetTexture(const Size&); void realize(); };

class RmlRenderer final : public Rml::RenderInterface
{
public:
    explicit RmlRenderer(RmlRendererHooks hooks);
    void beginFrame(const RmlTargetTexturePtr& target);   // UI thread
    void endFrame();
    void retire();
    void replay();                                        // graphics thread
    void releaseBackend();                                // graphics thread, after retire()
    bool backendFailed() const;
    bool hasAdvancedEffects() const;
    // + every Rml::RenderInterface override of the fork's RmlRenderer
};
using RmlRendererPtr = std::shared_ptr<RmlRenderer>;
```

- [ ] **Step 1: Fiação do CMake**

Em `src/CMakeLists.txt`: depois do bloco `OPENGL_ES` (linha 93), a opção e a definição, como no fork:

```cmake
option(TOGGLE_RMLUI "Enable RmlUi (UIRmlWidget, g_rml)" ON)
if (TOGGLE_RMLUI AND TOGGLE_FRAMEWORK_GRAPHICS AND NOT ANDROID AND NOT WASM)
  set(OTCLIENT_RMLUI ON)
  set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DFRAMEWORK_RMLUI)
else()
  set(OTCLIENT_RMLUI OFF)
endif()
```

Depois de `find_package(LuaJIT REQUIRED)` (linha 271, fora do bloco Android/WASM): se `OTCLIENT_RMLUI`, criar o alvo importado `LuaJIT::LuaJIT` a partir de `LUAJIT_LIBRARY` / `LUAJIT_INCLUDE_DIR` quando ele não existir, `find_package(RmlUi CONFIG REQUIRED)` e `log_option_enabled("RMLUI")`. Antes de `add_library(otclient_core ...)`: acrescentar `framework/rml/rmlrenderer.cpp` a `SOURCE_FILES` sob `if(OTCLIENT_RMLUI)`. Depois dele: `target_link_libraries(otclient_core PUBLIC RmlUi::RmlUi)` sob a mesma condição.

Em `tests/CMakeLists.txt`: `if(TOGGLE_RMLUI AND TOGGLE_FRAMEWORK_GRAPHICS AND NOT WASM) add_subdirectory(rml) endif()`.

`tests/rml/CMakeLists.txt`:

```cmake
find_package(RmlUi CONFIG REQUIRED)
otclient_add_gtest(rml_tests
    rmlrenderer_test.cpp
)
target_compile_definitions(rml_tests PRIVATE FRAMEWORK_RMLUI)
target_link_libraries(rml_tests PRIVATE RmlUi::RmlUi)
```

- [ ] **Step 2: Escrever os testes que falham**

`tests/rml/rmlrenderer_test.cpp`. Um `FakeBackend` que implementa `RmlBackend` e `Rml::RenderInterface`: devolve handles reais crescentes a partir de 1000, registra cada chamada num `std::vector<std::string>` (`"CompileGeometry"`, `"RenderGeometry:1000:0"` com geometria e textura reais, `"beginFrame"`, ...) e guarda os bytes do último `GenerateTexture`. Um helper `makeRenderer(fake, &results)` monta os hooks. Casos:

```cpp
TEST(RmlRenderer, ReplayWithoutCommandsCreatesNoBackend)        // createBackend never called
TEST(RmlRenderer, ProxyHandlesMapToBackendHandles)              // RenderGeometry reaches the fake with 1000, not the proxy
TEST(RmlRenderer, ReleaseErasesMapping)                         // after ReleaseGeometry, a later RenderGeometry(proxy) is not forwarded
TEST(RmlRenderer, ResourcesCreatedOutsideFrameRunBeforeTheFrame) // GenerateTexture outside begin/end precedes "beginFrame" in the log
TEST(RmlRenderer, LayerHandlesExpireAtEndOfFrame)               // CompositeLayers in frame 2 with a frame-1 layer gets 0
TEST(RmlRenderer, BackendCreationFailureIsReportedOnce)         // factory returns nullptr: onBackendResult(nullptr) once, backendFailed(), later replays do nothing and keep no queue
TEST(RmlRenderer, RetireStopsRecordingButKeepsReleases)         // after retire(): RenderGeometry dropped, ReleaseTexture still replayed by releaseBackend()
TEST(RmlRenderer, ReleaseBackendDestroysBackendAfterPendingReleases) // fake destructor runs after the queued releases
TEST(RmlRenderer, LoadTexturePremultipliesAlpha)                // loadImage -> 1x1 RGBA {200,100,50,128} becomes {100,50,25,128}; null image returns handle 0
TEST(RmlRenderer, EachFrameReachesItsTarget)                    // two frames, two targets: fake.beginFrame receives each one in order
TEST(RmlRenderer, ReplayIsBracketedByBeginEndReplay)            // "beginReplay" first, "endReplay" last, only when there are commands
```

- [ ] **Step 3: Rodar e ver falhar**

Run: `cmake --preset windows-release -DOPTIONS_ENABLE_SCCACHE=OFF` e `cmake --build --preset windows-release --target rml_tests`
Expected: falha de compilação, `rmlrenderer.h` não existe.

- [ ] **Step 4: Implementar**

`rmlbackend.h` conforme o bloco Interfaces. `rmlrenderer.h/.cpp`: copie de `REF/src/framework/rml/` e altere:

- remova `RenderInterface_GL3`, `m_fbo`, `m_attachedTarget`, `m_glFailed` e todo `gl*`; o renderer guarda `RmlBackendPtr m_backend`, `bool m_backendFailed` e os hooks;
- `replay()`: cria o backend na primeira vez que há comandos; chama `beginReplay()`, executa, chama `endReplay()`;
- `execute()`: `Op::BeginFrame` chama `m_backend->beginFrame(cmd.target)`, `Op::EndFrame` chama `m_backend->endFrame()` e expira as camadas; os demais comandos vão para `m_backend->renderInterface()`;
- `LoadTexture` usa `m_hooks.loadImage`;
- `releaseGl()` vira `releaseBackend()`;
- `RmlTargetTexture` fica como no fork (`realize()` só será chamado pelo executor OpenGL). Os testes rodam sem contexto GL: o construtor não pode fazer nenhuma chamada GL nem depender de `g_graphics` estar inicializado.

- [ ] **Step 5: Rodar os testes e ver passar**

Run: `cmake --build --preset windows-release --target rml_tests` e `ctest --test-dir build\windows-release -R RmlRenderer --output-on-failure`
Expected: 11 testes, todos PASS.

- [ ] **Step 6: Commit**

```bash
git add src/framework/rml/rmlbackend.h src/framework/rml/rmlrenderer.h src/framework/rml/rmlrenderer.cpp src/CMakeLists.txt tests/CMakeLists.txt tests/rml
git commit -m "feat(rmlui): record RmlUi render calls and replay them through a backend interface"
```

---

### Task 3: Executor OpenGL (desktop e ES 3) e fiação do MSBuild

**Files:**
- Create: `src/framework/rml/RmlUi_Renderer_GL3.h`, `src/framework/rml/RmlUi_Renderer_GL3.cpp`, `src/framework/rml/RMLUI_LICENSE.txt`, `src/framework/rml/rmlbackend_gl.h`, `src/framework/rml/rmlbackend_gl.cpp`, `src/framework/rml/rmlbackend.cpp`
- Modify: `src/framework/graphics/declarations.h:28-36`, `src/framework/graphics/painter.cpp:287`, `src/CMakeLists.txt`, `vc18/otclient.vcxproj`, `vc18/settings.props`

**Interfaces:**
- Consumes: `RmlBackend`, `RmlTargetTexture` (Tarefa 2).
- Produces:

```cpp
// rmlbackend.h (additions)
RmlBackendPtr createRmlBackend();          // nullptr + one "[rmlui]" log line when no executor fits
std::string rmlExpectedBackendName();      // "OpenGL 3.3" | "OpenGL ES 3" | "none" (no GL context)

// declarations.h
enum class CompositionMode { ..., LIGHT, PREMULTIPLIED };  // glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)
```

- [ ] **Step 1: Trazer o backend GL3 e adicionar o ramo ES 3**

Copie `RmlUi_Renderer_GL3.h`, `RmlUi_Renderer_GL3.cpp` e `RMLUI_LICENSE.txt` de `REF/src/framework/rml/`. No `.cpp`, introduza no topo uma macro única:

```cpp
#if defined(RMLUI_PLATFORM_EMSCRIPTEN) || defined(__ANDROID__) || defined(OPENGL_ES)
    #define RMLUI_GL3_ES 1
#endif
```

e troque por `RMLUI_GL3_ES` as cinco guardas `RMLUI_PLATFORM_EMSCRIPTEN` / `__ANDROID__` que escolhem comportamento de ES (modo de wrap `GL_CLAMP_TO_EDGE`, ausência de `GL_TEXTURE_BORDER_COLOR`, ausência de `GL_FRAMEBUFFER_SRGB`, mensagem de `Initialize`, `Shutdown`). No bloco de seleção do cabeçalho de shader, acrescente um ramo para `OPENGL_ES` antes do ramo `RMLUI_GL3_CUSTOM_LOADER`: `#version 300 es\nprecision highp float;\n` e `#include <framework/graphics/glutil.h>`.

- [ ] **Step 2: `RmlBackendGL` e a fábrica**

`rmlbackend_gl.h/.cpp`: `class RmlBackendGL final : public RmlBackend` com `static RmlBackendPtr create()` (devolve `nullptr` se o `RenderInterface_GL3` não for válido). O corpo vem do que a Tarefa 2 removeu do `rmlrenderer.cpp` do fork: salvar e restaurar o estado GL em `beginReplay`/`endReplay`, o FBO ligado à textura alvo e a limpeza em `beginFrame` (chamando `target->realize()`), `EndFrame` do GL3 em `endFrame`, e o destrutor apagando o FBO só se `g_graphics.ok()`. `name()` devolve `"OpenGL ES 3"` com `OPENGL_ES` e `"OpenGL 3.3"` sem. `supportsAdvancedEffects()` devolve `true`.

`rmlbackend.cpp`: `createRmlBackend()` devolve `RmlBackendGL::create()` quando `g_window.hasGLContext()`; caso contrário registra `[rmlui] no executor for the active render backend` e devolve `nullptr`. `rmlExpectedBackendName()` segue a mesma decisão.

- [ ] **Step 3: Modo de composição**

`declarations.h`: acrescente `PREMULTIPLIED` depois de `LIGHT`. `painter.cpp`, em `updateGlCompositionMode`: o `case` correspondente com `glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`.

- [ ] **Step 4: Fiação dos dois builds**

`src/CMakeLists.txt`: some os três `.cpp` novos ao bloco `if(OTCLIENT_RMLUI)` de fontes e marque `RmlUi_Renderer_GL3.cpp` com `SKIP_PRECOMPILE_HEADERS ON` e `SKIP_UNITY_BUILD_INCLUSION ON`.

`vc18/settings.props`: acrescente `FRAMEWORK_RMLUI;` e `RMLUI_STATIC_LIB;` a `PREPROCESSOR_DEFS`.

`vc18/otclient.vcxproj`: `ClCompile` para `rmlrenderer.cpp`, `rmlbackend.cpp`, `rmlbackend_gl.cpp` e:

```xml
<ClCompile Include="..\src\framework\rml\RmlUi_Renderer_GL3.cpp">
  <IncludeInUnityFile>false</IncludeInUnityFile>
  <PrecompiledHeader>NotUsing</PrecompiledHeader>
  <ForcedIncludeFiles></ForcedIncludeFiles>
</ClCompile>
```

e `ClInclude` para os quatro headers.

- [ ] **Step 5: Compilar as duas configurações**

Run: o comando MSBuild com `Configuration=OpenGL` e depois com `Configuration=DirectX`.
Expected: as duas terminam com `0 Error(s)` e geram `CrystalOTC_gl_x64.exe` e `CrystalOTC.exe`.

- [ ] **Step 6: Conferir que nada mudou sem RmlUi em uso**

Run: `.\CrystalOTC_gl_x64.exe` com um roteiro que só tira `baseline.png` aos 3 s e sai.
Expected: tela de login normal; `crystalotc.log` sem nenhuma linha `[rmlui]`.

- [ ] **Step 7: Commit**

```bash
git add src/framework/rml src/framework/graphics/declarations.h src/framework/graphics/painter.cpp src/CMakeLists.txt vc18/otclient.vcxproj vc18/settings.props
git commit -m "feat(rmlui): add the OpenGL 3.3 / ES 3 backend and premultiplied blending"
```

---

### Task 4: `g_rml`, `UIRmlWidget`, imagens de sprites e o demo

**Files:**
- Create: `src/framework/rml/rmlmanager.h`, `src/framework/rml/rmlmanager.cpp`, `src/framework/rml/uirmlwidget.h`, `src/framework/rml/uirmlwidget.cpp`, `src/client/rmlimages.h`, `src/client/rmlimages.cpp`, `data/styles/10-rmlwidget.otui`, `data/fonts/rml/` (Barlow-Regular/Medium/Bold, BarlowCondensed-Bold, `OFL.txt`), `modules/client_rmldemo/` (4 arquivos), `tests/rml/rmlmanager_text_test.cpp`
- Modify: `src/framework/luafunctions.cpp:46,991`, `src/framework/luaengine/luainterface.h`, `src/framework/core/graphicalapplication.cpp:119-120`, `src/client/client.cpp:59`, `src/CMakeLists.txt`, `vc18/otclient.vcxproj`, `tests/rml/CMakeLists.txt`

**Interfaces:**
- Consumes: `RmlRenderer`, `RmlRendererHooks`, `createRmlBackend()`, `rmlExpectedBackendName()`, `CompositionMode::PREMULTIPLIED`.
- Produces: tudo o que o `rmlmanager.h` e o `uirmlwidget.h` do fork declaram, mais:

```cpp
RmlRendererPtr RmlManager::createRenderer();             // builds the hooks around g_rml
void RmlManager::onBackendResult(const RmlBackend* b);   // replaces onBackendResult(bool)
lua_State* LuaInterface::getLuaState() const;
void registerRmlImageProvider();                         // rmlimages.h
```

Lua: singleton `g_rml` (`isReady`, `supportsAdvancedEffects`, `getBackendName`, `setReportEnabled`, `isReportEnabled`, `loadFontFace`, `utf8`, `latin1`, `getWidgetCount`, `getWidgets`) e classe `UIRmlWidget` (`create`, `loadDocument`, `unloadDocument`, `reloadDocument`, `hasDocument`, `getDocumentPath`, `setDebuggerVisible`, `isDebuggerVisible`, `setExtraStyleSheet`, `getDocument`, `getContext`).

- [ ] **Step 1: Teste unitário de texto (falha)**

`tests/rml/rmlmanager_text_test.cpp`, somado a `rml_tests`:

```cpp
TEST(RmlText, Latin1ToUtf8)        { EXPECT_EQ(RmlManager::utf8("a\xE7\xE3o"), "a\xC3\xA7\xC3\xA3o"); }
TEST(RmlText, Utf8ToLatin1)        { EXPECT_EQ(RmlManager::latin1("a\xC3\xA7\xC3\xA3o"), "a\xE7\xE3o"); }
TEST(RmlText, AsciiIsUntouched)    { EXPECT_EQ(RmlManager::utf8("abc"), "abc"); EXPECT_EQ(RmlManager::latin1("abc"), "abc"); }
TEST(RmlText, TruncatedUtf8DoesNotThrow)   { EXPECT_NO_THROW(RmlManager::latin1("ab\xC3")); }
TEST(RmlText, OutsideLatin1IsReplacedByOneChar) { EXPECT_EQ(RmlManager::latin1("\xE2\x82\xAC").size(), 1u); }
```

Run: `cmake --build --preset windows-release --target rml_tests` → falha de compilação (`rmlmanager.h` não existe).

- [ ] **Step 2: Portar o gerenciador, o widget e as imagens**

Copie de `REF` os seis arquivos C++, o `.otui`, as fontes Barlow e `modules/client_rmldemo/`. Mudanças em relação ao fork:

- `rmlmanager.cpp`: `init()` devolve `false` e registra `[rmlui] disabled: no executor for the active render backend` (uma vez) quando `!g_window.hasGLContext()`; `createRenderer()` monta os hooks (`createRmlBackend`, `loadImage`, `onBackendResult`); `onBackendResult(nullptr)` marca falha, e com backend guarda `name()` e `supportsAdvancedEffects()`; `getBackendName()` usa esse nome (antes do primeiro quadro, `rmlExpectedBackendName()`), mantendo o sufixo ` (full effects)` do fork; `retireRenderer` agenda `renderer->releaseBackend()`.
- `uirmlwidget.cpp`: o renderer vem de `g_rml.createRenderer()`. O restante fica igual.
- `rmlimages.cpp`: sem mudanças previstas; ajuste só o que não compilar contra as APIs de sprites daqui.

Engine: aplique os trechos do commit `abd46bd` do fork em `luafunctions.cpp` (includes e bloco de bindings depois de `UIQrCode::setCodeBorder`), `luainterface.h` (`getLuaState`), `graphicalapplication.cpp` (`g_rml.terminate()` depois de `g_ui.terminate()`) e `client.cpp` (`registerRmlImageProvider()` depois de `g_things.init()`).

Builds: some `rmlmanager.cpp`, `uirmlwidget.cpp` e `client/rmlimages.cpp` ao CMake e ao `.vcxproj` (com os headers).

- [ ] **Step 3: Testes unitários passam**

Run: `ctest --test-dir build\windows-release -R "RmlText|RmlRenderer" --output-on-failure`
Expected: 16 testes, todos PASS.

- [ ] **Step 4: Demo visível em OpenGL**

Compile `Configuration=OpenGL`. Roteiro: abrir o demo aos 1,5 s, `doScreenshot('rml-demo-gl.png')` aos 3,5 s, sair aos 5 s.
Expected: no PNG, a janela do demo sobre a tela de login com título, texto em Barlow e botões; o log tem `[rmlui] ready - RmlUi 6.3 (backend OpenGL 3.3 (full effects))`.

- [ ] **Step 5: Casos do Review Focus**

Um roteiro por caso, cada um terminando em `g_app.exit()`; o processo deve sair com código 0 e o log não pode ter `ERROR` nem exceção Lua:

```lua
-- 1. documento inexistente e RML malformado (escreva /bad.rml no write dir com "<rml><body><div></body>")
local w = g_ui.createWidget('RmlWindow', rootWidget); w:setSize({ width = 300, height = 200 })
assert(w:loadDocument('/modules/nao_existe/x.rml') == false)
assert(w:hasDocument() == false)

-- 2. abrir e fechar 50 vezes, um ciclo a cada 100 ms
--    ao final: assert(g_rml.getWidgetCount() == 0)

-- 3. tamanho zero e redimensionamento a cada quadro
--    w:setSize({ width = 0, height = 0 }); depois 60 quadros alternando 300x200 e 301x201

-- 4. <img src="item/99999999.png"/> e <img src="outfit/abc.png"/> num documento: sem exceção
```

Caso 5 (modo Vulkan): crie `config.ini` na raiz com `[graphics]` / `renderBackend = vulkan`, rode o roteiro do Step 4 sem a captura, e apague o `config.ini` em seguida.
Expected: o log tem `[rmlui] disabled: no executor for the active render backend` uma única vez e nenhuma linha `wglCreateContext`; o processo sai com código 0.

- [ ] **Step 6: Commit**

```bash
git add src/framework/rml src/client/rmlimages.h src/client/rmlimages.cpp src/framework/luafunctions.cpp src/framework/luaengine/luainterface.h src/framework/core/graphicalapplication.cpp src/client/client.cpp src/CMakeLists.txt vc18/otclient.vcxproj data/styles/10-rmlwidget.otui data/fonts/rml modules/client_rmldemo tests/rml
git commit -m "feat(rmlui): add g_rml, UIRmlWidget, game sprite images and the demo module"
```

---

### Task 5: Helper `Rml` e os quatro módulos de exemplo restantes

**Files:**
- Create: `modules/corelib/rml.lua`, `data/styles/rml/otc.rcss`, `data/fonts/rml/ShareTechMono-Regular.ttf`, `data/fonts/rml/ShareTechMono-OFL.txt`, `modules/client_rmlshowcase/`, `modules/client_rmloptions/`, `modules/game_rmloutfit/`, `modules/game_rmlminimap/` (4 arquivos cada)
- Modify: `modules/corelib/corelib.otmod`, `modules/game_things/things.lua`, `modules/client_rmldemo/rmldemo.lua`

**Interfaces:**
- Consumes: `g_rml`, `UIRmlWidget` (Tarefa 4); `modules.client_topmenu.addLeftButton(id, description, icon, callback, front)`.
- Produces: global Lua `Rml`; `modules.client_rmlshowcase.toggle()`, `modules.client_rmloptions.toggle()`, `modules.game_rmloutfit.toggle()`, `modules.game_rmlminimap.toggle()`.

- [ ] **Step 1: Trazer os arquivos**

Copie de `REF`. Em `corelib.otmod`, acrescente `dofile 'rml'` logo depois de `dofile 'objectpool'`. Atualize `rmldemo.lua` para a versão final do fork (ela passa a usar `Rml`).

- [ ] **Step 2: Adaptar ao CrystalOTC**

- `client_rmloptions`: cada opção exibida precisa existir em `modules/client_options` daqui (mesma chave em `g_settings`). Remova as linhas cujas chaves não existem; não acrescente opções novas.
- `client_rmldemo` e `client_rmlshowcase`: onde o fork escolhe versão de cliente e ids por formato de asset para carregar sprites fora do jogo, use o protocolo **1530** (assets protobuf em `data/things/1530`).
- `game_rmlminimap`: o `.otmm` de fora do jogo vem de `data/things/1530/`.
- `things.lua`: aplique o trecho do commit `bf3785d` do fork (opções do `Tibia.otfi`) no caminho `.dat/.spr` daqui (`tryLoadDatWithFallbacks` e `g_sprites.loadSpr`), sem tocar no caminho protobuf.

- [ ] **Step 3: Verificação visual em OpenGL**

Um roteiro que abre o showcase, percorre as abas uma a uma (pelo data model do módulo) capturando `rml-showcase-<aba>-gl.png`, depois abre opções, outfit e minimapa capturando `rml-options-gl.png`, `rml-outfit-gl.png`, `rml-minimap-gl.png`.
Expected, conferido em cada PNG: abas Início, Data binding, Formulários, Sprites (com itens e outfit desenhados depois de carregar os assets), OTUI no RML (widget de item e de criatura dentro do documento), Imagens (carrossel), Efeitos (sombras, gradiente e blur visíveis), OTUI para RmlUi; janela de opções com os valores atuais; preview de outfit; minimapa com os controles. O botão "RmlUi" aparece no menu superior. Log sem `ERROR`.

- [ ] **Step 4: Custo zero sem uso**

Rode o client com um roteiro que só espera 3 s e sai, sem abrir nenhuma janela RmlUi.
Expected: `crystalotc.log` não tem `[rmlui] ready`. Carregar os módulos de exemplo não pode inicializar o RmlUi; se algum chamar `g_rml.isReady()` no `init()`, mova a chamada para o `toggle()`.

- [ ] **Step 5: Atalhos e teclado**

Pelo roteiro Lua: chamar `toggle()` de cada módulo duas vezes (abre e fecha) e, no showcase, focar um `<input type="text">` com `Element:Focus()`, enviar `aç` em UTF-8 por `window:getContext():ProcessTextInput(...)` e conferir pelo data model que o valor recebido é `aç`.

Pelo teclado real (cobre o caminho OTUI para RmlUi): com o client aberto, envie as teclas por PowerShell (`(New-Object -ComObject WScript.Shell).AppActivate('CrystalOTC')` seguido de `[System.Windows.Forms.SendKeys]::SendWait('^+u')`), capture a tela, depois clique no campo de texto da aba Formulários, envie `aç` e capture de novo. Repita para `^+r`, `^+o`, `^+f`, `^+m`.
Expected: cada atalho abre a janela correspondente; o campo mostra `aç`; nenhum atalho do jogo dispara enquanto o campo está em foco.

- [ ] **Step 6: Commit**

```bash
git add modules/corelib/rml.lua modules/corelib/corelib.otmod data/styles/rml data/fonts/rml modules/client_rmlshowcase modules/client_rmloptions modules/game_rmloutfit modules/game_rmlminimap modules/client_rmldemo modules/game_things/things.lua
git commit -m "feat(rmlui): add the Rml Lua helpers and the showcase, options, outfit and minimap examples"
```

---

### Task 6: ANGLE (`DirectX|x64`)

**Files:**
- Modify: `src/framework/rml/RmlUi_Renderer_GL3.cpp`, `src/framework/rml/rmlbackend_gl.cpp` (só o que a verificação exigir)

**Interfaces:**
- Consumes: tudo das Tarefas 3 a 5.
- Produces: nenhuma interface nova.

- [ ] **Step 1: Rodar a verificação das Tarefas 4 e 5 no executável ANGLE**

Compile `Configuration=DirectX` e repita, com `CrystalOTC.exe`, os roteiros do Step 4 e 5 da Tarefa 4 e do Step 3 da Tarefa 5, com sufixo `-angle` nos PNGs.
Expected inicial: registre o que falhar (shader que não compila, framebuffer incompleto, tela vazia). O log deve dizer `backend OpenGL ES 3`.

- [ ] **Step 2: Corrigir o que for específico de ES 3**

Corrija dentro do ramo `RMLUI_GL3_ES` ou em `RmlBackendGL`, sem alterar o caminho de desktop. Cada correção leva um comentário de uma linha dizendo qual limite de ES 3 ela contorna.

- [ ] **Step 3: Comparar com OpenGL**

Leia lado a lado cada par `-gl.png` / `-angle.png`.
Expected: mesmo conteúdo, mesmas posições, efeitos presentes nos dois (sombra, gradiente, blur, máscara). `g_rml.supportsAdvancedEffects()` é `true` nos dois. Diferenças de antisserrilhado de um pixel são aceitas e anotadas.

- [ ] **Step 4: Regressão em OpenGL**

Recompile `Configuration=OpenGL` e repita o Step 4 da Tarefa 4.
Expected: igual ao PNG anterior.

- [ ] **Step 5: Commit**

```bash
git add src/framework/rml
git commit -m "fix(rmlui): make the GL backend work on OpenGL ES 3 through ANGLE"
```

Se nenhuma correção foi necessária, não há commit: registre isso no relatório da tarefa.

---

### Task 7: Build CMake completo e documentação

**Files:**
- Create: `docs/RMLUI.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: tudo.
- Produces: nenhuma.

- [ ] **Step 1: Build CMake do client e de todos os testes**

Run: `cmake --build --preset windows-release` e `ctest --test-dir build\windows-release --output-on-failure`
Expected: build sem erros; todos os testes PASS (os 16 de `rml_tests` e os que já existiam).

- [ ] **Step 2: Build sem RmlUi**

Run: `cmake --preset windows-release -DOPTIONS_ENABLE_SCCACHE=OFF -DTOGGLE_RMLUI=OFF` e `cmake --build --preset windows-release`
Expected: compila; nenhum símbolo `Rml` no executável. Reconfigure com `-DTOGGLE_RMLUI=ON` ao final.

- [ ] **Step 3: Documentação**

`docs/RMLUI.md`, em inglês, a partir de `REF/docs/RMLUI.md`: mesma estrutura (exemplos, uso rápido, API de `g_rml` e `UIRmlWidget`, recursos no RML/RCSS, como funciona). Troque a seção de build pelo MSBuild e pelo port em `vcpkg-overlays/rmlui`; na seção "como funciona", descreva `RmlBackend` e os executores; declare que o modo Vulkan ainda não tem executor (plano 2) e que Linux e macOS não foram verificados. Em `README.md`, uma linha na lista de recursos apontando para `docs/RMLUI.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/RMLUI.md README.md
git commit -m "docs(rmlui): document the RmlUi integration"
```

- [ ] **Step 5: Verificação dentro do jogo**

Se o usuário tiver fornecido um servidor local e uma conta de teste: entrar no jogo nas duas configurações e conferir `game_rmloutfit` (trocar cores, addons e looktype e confirmar que o personagem muda, ou seja, que `changeOutfit` funciona no protocolo 15.30) e `game_rmlminimap` (o `UIMinimap` hospedado mostra o mapa real, zoom e troca de andar funcionam).
Sem servidor: não rode nada. Entregue esses itens no relatório final como lista de conferência, marcados como não verificados.
