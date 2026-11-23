# RmlUi no CrystalOTC, plano 2: executor Vulkan nativo

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** RmlUi funcionando com `renderBackend = vulkan`, desenhado pelo renderer Vulkan do próprio client, com os mesmos efeitos do backend OpenGL (camadas, filtros, gradientes, sombras, máscaras) e sem criar contexto OpenGL.

**Architecture:** `RmlRenderer` já grava os comandos do RmlUi e os reproduz contra a interface `RmlBackend` (plano 1). Este plano entrega a segunda implementação, `RmlBackendVk`. A lógica do backend GL3 do RmlUi (pilha de camadas, filtros, máscara de recorte) é portada para uma classe que fala com uma interface pequena, `vkrml::Device`, e não com o Vulkan diretamente: isso permite testá-la sem GPU contra um dispositivo falso que valida as regras do Vulkan que mais dão erro (desenhar fora de passe, amostrar o anexo ativo, usar recurso destruído). A implementação real dessa interface vive no renderer Vulkan do client. Cada widget desenha numa imagem própria, fora da tela, **antes** do passe principal do quadro; o `VkDrawFeeder` reconhece essa imagem na fila do `DrawPool` e a emite como um segmento do batch de sprites com textura própria e mistura de alfa pré-multiplicado.

**Tech Stack:** C++23 (MSVC v145), Vulkan 1.1 sem extensões novas de device, GLSL 450 compilado para SPIR-V com `glslang`, RmlUi 6.3, gtest, MSBuild (`vc18/`) e CMake.

**Spec:** `docs/superpowers/specs/2026-11-16-rmlui-design.md` (seções "Executor Vulkan", "Comportamento em falhas", "Verificação"; etapas 4 e 5 da "Ordem de entrega").

**Estado de partida:** branch `claude/add-rmlui-client-bdbdf5` com o plano 1 concluído (commit `64bcf54`). OpenGL e ANGLE desenham o RmlUi com efeitos; no modo Vulkan `g_rml.isReady()` é `false`. `docs/RMLUI.md` descreve a integração e `tools/rmlui/verify/README.md` os scripts de verificação.

## Global Constraints

- Vulkan **1.1**, só com a extensão de swapchain já usada. Nenhuma extensão nova de device ou de instância.
- No modo Vulkan nenhum contexto OpenGL é criado e o driver OpenGL não é carregado por causa do RmlUi.
- Sem widget RmlUi aberto, nada do executor existe: nenhum pipeline, imagem, buffer ou shader module é criado antes do primeiro quadro de um widget RmlUi. O log `[vulkan] frame ...` e o desenho do client não mudam.
- A API Lua (`g_rml`, `UIRmlWidget`, `Rml`) e o RML/RCSS aceitos não mudam. `g_rml.getBackendName()` devolve `"Vulkan"` enquanto só a etapa 1 existir e `"Vulkan (full effects)"` com a etapa 2; `supportsAdvancedEffects()` acompanha.
- Convenções do renderer Vulkan: arquivos em `src/framework/graphics/vulkan/` dentro de `#ifdef WIN32`, ponteiros de função do Vulkan locais à classe que os usa (carregados com `vkGetDeviceProcAddr`, como `VkSpriteBatch::loadFunctions`), nenhum estado global novo além dos singletons existentes, falha de `init()` não derruba o contexto, logs com o prefixo `[vulkan]`.
- Todo código que inclui cabeçalhos do RmlUi fica atrás de `#ifdef FRAMEWORK_RMLUI`.
- Os `.spv` são versionados ao lado das fontes GLSL, em `data/shaders/vulkan/rml/`. O client não ganha compilador de shaders.
- Formatos sem sRGB (`R8G8B8A8_UNORM`), como o atlas e a swapchain atuais: a mistura acontece no mesmo espaço do OpenGL.
- Comentários e mensagens de commit em inglês, no estilo do repositório (`feat(rmlui): ...`, `fix(vulkan): ...`). Cabeçalho de licença MIT nos arquivos novos do framework.
- Commits: `git add` só dos caminhos listados na tarefa.
- Verificação em execução: sempre pelos scripts de `tools/rmlui/verify` (nunca usando a pasta de configurações real do usuário).

## Review Focus

1. **GPU sem o que o executor prefere** (sem `D24_UNORM_S8_UINT`, sem MSAA 2x): o executor escolhe a alternativa suportada ou se declara indisponível (`g_rml.isReady()` passa a `false` com uma linha `[rmlui]`); o client não cai. Teste na Tarefa 5.
2. **Recurso liberado pelo RmlUi com quadros em voo** (textura de fonte regenerada, janela fechada): a destruição só acontece depois que os dois quadros em voo terminam. Teste na Tarefa 4.
3. **Widget redimensionado a cada quadro, janela minimizada, swapchain recriada com janelas RmlUi abertas**: as camadas são recriadas no tamanho novo e nada antigo é usado depois; um quadro abandonado pelo `drawFrame` não perde comandos nem vaza callbacks. Testes nas Tarefas 2 e 6.
4. **`.spv` ausente, ou o Vulkan morre no meio da sessão**: os widgets ficam vazios, `g_rml.isReady()` é `false`, nada é chamado num device destruído. Testes nas Tarefas 4 e 6.
5. **Elementos com transformação 3D** (`rotateX`, `perspective`): no Vulkan o volume de recorte em z é `[0, 1]`, não `[-1, 1]`; sem uma projeção própria a geometria some. Teste na Tarefa 6.

## Decisões deste plano (para conferir antes da execução)

- **Compilador de shaders.** O `glslang.exe` vem do pacote oficial `glslang-main-windows-Release.zip` das releases de `KhronosGroup/glslang` (o que `compile_shaders.bat` já documenta), descompactado em `build/tools/glslang/` (ignorado pelo git). É um download de executável: a Tarefa 1 só o faz depois de você confirmar; a alternativa é você apontar a variável `GLSLANG` para um `glslang.exe` que já tenha (Vulkan SDK).
- **Queda na saída do modo Vulkan.** Hoje o client termina com `0xC0000374` em modo Vulkan mesmo sem RmlUi (destrutor estático de `VkContext` rodando depois que a janela e o device já foram embora). O spec deixa fora do escopo "completar o renderer Vulkan", mas sem uma saída limpa não há como verificar que o executor libera o que criou. A Tarefa 1 corrige só isso: `VkContext::terminate()` passa a ser chamado explicitamente no encerramento, antes de a janela ser destruída.
- **Nova entrada no `DrawPool`.** `addPrePassAction`: uma ação que o caminho OpenGL executa como qualquer outra e que o caminho Vulkan executa antes do passe principal, em vez de ignorar. É a única mudança na interface do `DrawPool`.
- **Antisserrilhado.** MSAA 2x nas camadas quando a GPU oferece para cor e stencil; senão 4x; senão 1x. É o equivalente ao `RMLUI_NUM_MSAA_SAMPLES 2` do backend GL3.
- **Memória.** Sem `vulkan-memory-allocator`: um alocador de blocos próprio para a geometria (muitos buffers pequenos) e uma alocação por imagem (dezenas, no máximo). O port `vulkan-memory-allocator` continua declarado no `vcpkg.json` e sem uso, como hoje.
- **Critério de igualdade entre os modos.** Comparação automática das capturas da janela RmlUi entre OpenGL e Vulkan: pelo menos 97% dos pixels com diferença de até 16/255 por canal. As diferenças que passarem disso são examinadas uma a uma e registradas.

## Mapa de arquivos

Novos:

| Arquivo | Responsabilidade |
|---|---|
| `src/framework/graphics/vulkan/vkprepass.h` | `VkPrePassQueue`: a fila de callbacks que rodam antes do passe principal. Só cabeçalho, sem Vulkan nem RmlUi. |
| `src/framework/graphics/vulkan/vkrmldevice.h` | `vkrml::Device`: tudo o que o RmlUi precisa do Vulkan, pequeno o bastante para ter um falso. Sem `<vulkan/vulkan.h>`. |
| `src/framework/graphics/vulkan/vkrmlalloc.{h,cpp}` | `vkrml::BlockAllocator` (sub-alocação de buffers) e `vkrml::Graveyard` (destruição adiada por quadro). CPU pura. |
| `src/framework/graphics/vulkan/vkrmlrenderer.{h,cpp}` | `VkRmlRenderInterface : Rml::RenderInterface`: o port da lógica do `RenderInterface_GL3` (camadas, filtros, máscara, shaders) contra `vkrml::Device`. CPU pura. |
| `src/framework/graphics/vulkan/vkrmldevice_vk.{h,cpp}` | `VkRmlDeviceVk : vkrml::Device`: imagens, buffers, render passes, pipelines, descriptors, uploads. Único arquivo novo que chama o Vulkan. |
| `src/framework/graphics/vulkan/vkrmltargets.{h,cpp}` | `VkRmlTargets`: de `uniqueId` de textura do client para a imagem do widget. É o que o feeder consulta. |
| `src/framework/rml/rmlbackend_vk.{h,cpp}` | `RmlBackendVk : RmlBackend`: liga `RmlRenderer` a `VkRmlRenderInterface`, registra o alvo. |
| `data/shaders/vulkan/rml/*.vert`, `*.frag`, `*.spv` | 3 vértices (`main`, `passthrough`, `blur`) e 9 fragmentos (`color`, `texture`, `gradient`, `creation`, `passthrough`, `color_matrix`, `blend_mask`, `blur`, `drop_shadow`). |
| `tests/rml/vkprepass_test.cpp`, `vkrml_fake_device.h`, `vkrml_fake_device_test.cpp`, `vkrml_alloc_test.cpp`, `vkrml_renderer_test.cpp`, `vkrml_caps_test.cpp` | Dispositivo falso validador e os testes sem GPU. |
| `tools/rmlui/verify/compare.ps1` | Compara duas capturas na região da janela RmlUi, com tolerância. |
| `tools/rmlui/verify/plain.lua` | Demo e uma aba do showcase com o tema `efeitos` desligado à força, para comparar a etapa 1 com o OpenGL em condições iguais. |

Alterados: `vkcontext.{h,cpp}` (pré-passe, acesso ao device, encerramento explícito), `vkbatch.{h,cpp}` (textura por segmento, pipeline pré-multiplicado), `vkfeeder.cpp` (ações de pré-passe, alvo do RmlUi), `drawpool.{h,cpp}` e `drawpoolmanager.h` (`addPrePassAction`), `uirmlwidget.cpp`, `rmlbackend.cpp`, `rmlmanager.cpp`, `rmlrenderer.h` (id do alvo), `graphicalapplication.cpp`, `data/shaders/vulkan/compile_shaders.bat`, `src/CMakeLists.txt`, `tests/rml/CMakeLists.txt`, `vc18/otclient.vcxproj`, `tools/rmlui/verify/{run.ps1,vulkan.lua,README.md}`, `docs/RMLUI.md`, `README.md`.

## Referência e ambiente

**O que portar.** `src/framework/rml/RmlUi_Renderer_GL3.cpp` é a referência de comportamento. Os trechos que cada tarefa porta estão indicados pelo nome da função. Regra geral do port: toda inversão vertical do código GL (`VerticallyFlipped`, `height - y`, o `glBlitFramebuffer` invertido de `SaveLayerAsTexture`) **desaparece**: no Vulkan a linha 0 de uma imagem é a de cima, tanto ao desenhar quanto ao amostrar, que é a convenção que o RmlUi já usa para texturas.

**Builds.** Os mesmos do plano 1 (seção "Referência e ambiente" de `docs/superpowers/plans/2026-11-16-rmlui-opengl-angle.md`): MSBuild `Configuration=OpenGL` gera `CrystalOTC_gl_x64.exe`, `Configuration=DirectX` gera `CrystalOTC.exe`; o preset CMake `windows-release` gera `otclient.exe` e os testes. O renderer Vulkan é compilado nas duas configurações; o modo é escolhido em execução.

**Testes unitários:** `cmake --build --preset windows-release --target rml_tests` e `ctest --test-dir build/windows-release -R "Rml|VkRml"` (dentro do ambiente `vcvars64`, como no plano 1).

**Verificação em execução, modo Vulkan** (a Tarefa 1 cria o parâmetro `-Backend`):

```
powershell -ExecutionPolicy Bypass -STA -File tools\rmlui\verify\run.ps1 -Exe .\CrystalOTC_gl_x64.exe -Tag vk -Backend vulkan -Only demo,lifetime
```

O script escreve `config.ini` com `renderBackend = vulkan` durante a execução e restaura o do usuário. A máquina precisa estar livre: os scripts abrem a janela do client várias vezes e o de teclas toma o foco.

---

### Task 1: Ferramentas e saída limpa do modo Vulkan

**Files:**
- Modify: `data/shaders/vulkan/compile_shaders.bat`, `src/framework/core/graphicalapplication.cpp`, `src/framework/graphics/vulkan/vkcontext.cpp`, `tools/rmlui/verify/run.ps1`, `tools/rmlui/verify/shot.ps1`, `tools/rmlui/verify/demo.lua`, `tools/rmlui/verify/showcase.lua`, `tools/rmlui/verify/README.md`
- Create: `tools/rmlui/verify/compare.ps1`

**Interfaces:**
- Produces:
  - `run.ps1 -Backend gl|vulkan` (padrão `gl`): com `vulkan`, todo script roda com `renderBackend = vulkan`; a linha "vulkan" da tabela deixa de ser "KNOWN ISSUE".
  - Retângulo da janela junto de cada captura: um script anuncia `[verify] rect <nome da captura> <x> <y> <largura> <altura>` (coordenadas da área cliente, as de `window:getRect()`) antes do `[verify] shot <nome>`; `shot.ps1` grava `<nome>.rect` ao lado do PNG, já em pixels da captura (soma o deslocamento da área cliente dentro da janela). `demo.lua` e `showcase.lua` passam a anunciar.
  - `compare.ps1 -A <png> -B <png> [-Rect x,y,w,h] [-Tolerance 16] [-MinMatch 0.97]`: compara a região (por padrão a do `.rect` de `-A`), imprime a fração de pixels com diferença de até `Tolerance` por canal e sai com 1 abaixo de `MinMatch`.
  - `compile_shaders.bat` compila também `rml\*.vert` e `rml\*.frag` (um laço, não uma linha por arquivo). `build/tools/glslang/bin/glslang.exe` disponível.

- [ ] **Step 1: Ver a saída do modo Vulkan falhar**

Run: `powershell -ExecutionPolicy Bypass -STA -File tools\rmlui\verify\run.ps1 -Exe .\CrystalOTC_gl_x64.exe -Tag vk -Only vulkan`
Expected: linha `vulkan` com `Exit` = `-1073740940` e resultado `KNOWN ISSUE`.

- [ ] **Step 2: Achar a causa antes de mexer** (superpowers:systematic-debugging)

O que já se sabe: a pilha na detecção é `common_exit -> _execute_onexit_table -> VkContext::~VkContext -> VkContext::terminate`. Confirmar o que `terminate()` toca que já não existe nesse ponto (device, surface, janela) lendo `GraphicalApplication::terminate`, `WIN32Window::terminate` e `main.cpp`. Não seguir para o Step 3 sem a ordem real escrita no ledger.

- [ ] **Step 3: Encerrar o contexto Vulkan explicitamente**

`GraphicalApplication::terminate()` chama `VkContext::instance().terminate()` depois de `g_rml.terminate()` e de `g_drawPool.terminate()`, e antes de `g_window.terminate()`. `VkContext::terminate()` passa a ser idempotente (segunda chamada não faz nada), de modo que o destrutor estático encontre tudo já liberado.

- [ ] **Step 4: Ver a saída passar**

Trocar em `run.ps1` o rótulo de problema conhecido do passo `vulkan` por uma checagem normal de código de saída. Run: o comando do Step 1.
Expected: `vulkan` com `Exit 0`, `Pass 5`, resultado `ok`; `failed: 0`. Repetir três vezes: o encerramento não pode ser intermitente.

- [ ] **Step 5: `-Backend` no `run.ps1`**

Com `-Backend vulkan`, `run.ps1` escreve o `config.ini` uma vez (guardando o do usuário) em volta de todos os scripts, e não só do `vulkan.lua`. Run: `... -Tag vk -Backend vulkan -Only demo`
Expected: `demo` com `Exit 0`; no log, `[verify] backend=unavailable ready=false` (o executor ainda não existe) e nenhuma linha de criação de contexto OpenGL.

- [ ] **Step 6: `compare.ps1`**

Gerar as capturas com retângulo: `... -Exe .\CrystalOTC_gl_x64.exe -Tag gl -Only demo` e `... -Exe .\CrystalOTC.exe -Tag angle -Only demo`. Teste do próprio script: uma captura com ela mesma (fração 1.0, saída 0); `demo-gl.png` com `demo-angle.png` (saída 0: OpenGL e ANGLE já são iguais); `demo-gl.png` com `-Rect` apontando para um canto do fundo de `demo-angle.png` deslocado (saída 1).

- [ ] **Step 7: `glslang`**

Depois da confirmação do usuário (ver "Decisões deste plano"): baixar o zip oficial para `build/tools/`, descompactar em `build/tools/glslang/`, e rodar `data\shaders\vulkan\compile_shaders.bat` com `GLSLANG` apontando para ele.
Expected: `SPIR-V gotowe.` e `git status` sem mudanças em `data/shaders/vulkan/*.spv` (os quatro `.spv` existentes são regenerados byte a byte; se mudarem, registrar a versão do glslang no ledger e manter os antigos).

- [ ] **Step 8: Commit**

```bash
git add data/shaders/vulkan/compile_shaders.bat src/framework/core/graphicalapplication.cpp src/framework/graphics/vulkan/vkcontext.cpp tools/rmlui/verify/run.ps1 tools/rmlui/verify/compare.ps1 tools/rmlui/verify/README.md
git commit -m "fix(vulkan): terminate the context explicitly at shutdown; verification in Vulkan mode"
```

---

### Task 2: Pré-passe: do `DrawPool` até o command buffer do quadro

**Files:**
- Create: `src/framework/graphics/vulkan/vkprepass.h`
- Modify: `src/framework/graphics/drawpool.h`, `drawpool.cpp`, `drawpoolmanager.h`, `src/framework/graphics/vulkan/vkcontext.h`, `vkcontext.cpp`, `vkfeeder.cpp`, `src/framework/rml/uirmlwidget.cpp`
- Test: `tests/rml/vkprepass_test.cpp` (novo), `tests/rml/CMakeLists.txt`

**Interfaces:**
- Produces:

```cpp
// drawpool.h - DrawObject
bool vkPrePass{ false };   // the action must run before the main pass on the Vulkan path

// drawpool.h / drawpoolmanager.h
// An action for work that renders into a texture drawn later in this same pool (RmlUi).
// OpenGL: executed in order, exactly like addAction. Vulkan: handed to VkContext and executed
// before the main render pass of the frame, with its command buffer open.
void addPrePassAction(const std::function<void()>& action);

// vkcontext.h
static constexpr uint32_t kFramesInFlight = 2;          // was the private MAX_FRAMES_IN_FLIGHT
struct PrePass { VkCommandBuffer cmd; uint32_t frameIndex; uint64_t frameNumber; };
void addPrePass(std::function<void()> callback);         // main thread, before drawFrame
const PrePass* currentPrePass() const;                   // non-null only while the callbacks run
VkDevice device() const; VkPhysicalDevice physicalDevice() const;
VkQueue graphicsQueue() const; VkCommandPool commandPool() const;

// vkprepass.h - the queue itself, header only, testable without a device
class VkPrePassQueue {
public:
    void add(std::function<void()> callback);
    void run();     // executes in registration order, then clears; a callback may add another
    void drop();    // frame abandoned: clears without executing
    size_t size() const;
};
```

- Consumes: `UIRmlWidget::drawSelf` (plano 1) chama hoje `g_drawPool.addAction([renderer] { renderer->replay(); })`.

- [ ] **Step 1: Testes da fila (falhando)**

`tests/rml/vkprepass_test.cpp`, suíte `VkPrePass`:
- `RunsInRegistrationOrderAndClears`: três callbacks anotam 1, 2, 3; depois de `run()` a ordem é `{1,2,3}` e `size() == 0`.
- `ACallbackAddedWhileRunningAlsoRuns`: o primeiro callback registra um segundo; ambos executam no mesmo `run()`.
- `DropDiscardsWithoutRunning`: depois de `drop()` nada executou e `size() == 0`.
- `RunWithNothingRegisteredDoesNothing`.

Run: `ctest --test-dir build/windows-release -R VkPrePass` — Expected: não compila (`VkPrePassQueue` não existe).

- [ ] **Step 2: Implementar `VkPrePassQueue`** e ver os quatro testes passarem.

- [ ] **Step 3: `DrawPool::addPrePassAction`**

Cria o `DrawObject` como `addAction` faz e marca `vkPrePass = true`. `UIRmlWidget::drawSelf` passa a usá-lo. No caminho OpenGL nada muda.
Run (regressão OpenGL): `... run.ps1 -Exe .\CrystalOTC_gl_x64.exe -Tag gl -Only demo,lifetime` — Expected: `failed: 0`.

- [ ] **Step 4: `VkContext` executa o pré-passe**

`drawFrame`: depois de `vkBeginCommandBuffer` e antes de `vkCmdBeginRenderPass`, preenche `PrePass`, executa a fila e zera `currentPrePass()`. Em todo retorno antecipado (contexto não pronto, `OUT_OF_DATE`, falha) a fila é descartada com `drop()`. `VkDrawFeeder::feedPool`: um objeto com `vkPrePass` vai para `VkContext::addPrePass` em vez de ser ignorado; os demais objetos com `action` continuam ignorados.

- [ ] **Step 5: Evidência em execução**

Temporário, removido antes do commit: uma linha `[vulkan] pre-pass: N callbacks` no primeiro quadro em que N > 0. Run: `... -Tag vk -Backend vulkan -Only demo`.
Expected: o log **não** tem a linha (o RmlUi ainda se recusa a iniciar no modo Vulkan, então nenhum widget grava nada). É a confirmação de que o caminho novo fica inerte até a Tarefa 6.

- [ ] **Step 6: Commit**

```bash
git add src/framework/graphics/drawpool.h src/framework/graphics/drawpool.cpp src/framework/graphics/drawpoolmanager.h src/framework/graphics/vulkan/vkprepass.h src/framework/graphics/vulkan/vkcontext.h src/framework/graphics/vulkan/vkcontext.cpp src/framework/graphics/vulkan/vkfeeder.cpp src/framework/rml/uirmlwidget.cpp tests/rml/vkprepass_test.cpp tests/rml/CMakeLists.txt vc18/otclient.vcxproj
git commit -m "feat(vulkan): pre-pass actions from the draw pool to the frame's command buffer"
```

---

### Task 3: Batch de sprites com textura por segmento e alfa pré-multiplicado

**Files:**
- Modify: `src/framework/graphics/vulkan/vkbatch.h`, `vkbatch.cpp`, `vkfeeder.cpp`
- Create: `src/framework/graphics/vulkan/vkrmltargets.h`, `vkrmltargets.cpp`
- Modify: `src/framework/rml/rmlrenderer.h` (`RmlTargetTexture::uniqueId()`), `src/CMakeLists.txt`, `vc18/otclient.vcxproj`

**Interfaces:**
- Produces:

```cpp
// vkbatch.h
// Texture for SUBSEQUENT vertices: VK_NULL_HANDLE = the atlas. Closes the current segment, like
// setScissor. The binding must sample a 2D-array view (the sprite shader reads layer 0).
void setTexture(VkDescriptorSet binding);
// setPipeline: 0 = alpha, 1 = MULTIPLY, 2 = premultiplied alpha (ONE, ONE_MINUS_SRC_ALPHA)
VkDescriptorSet createTextureBinding(VkImageView arrayView, VkSampler sampler);   // VK_NULL_HANDLE on failure
void destroyTextureBinding(VkDescriptorSet binding);                               // caller defers it past the frames in flight

// vkrmltargets.h - no RmlUi and no OpenGL headers
struct VkRmlTarget { VkDescriptorSet binding{ VK_NULL_HANDLE }; uint32_t width{ 0 }; uint32_t height{ 0 }; };
class VkRmlTargets {
public:
    static VkRmlTargets& instance();
    void set(uint32_t textureUniqueId, const VkRmlTarget& target);
    void erase(uint32_t textureUniqueId);
    const VkRmlTarget* find(uint32_t textureUniqueId) const;   // nullptr = not an RmlUi target (or not rendered yet)
};
```

- Consumes: `Segment` e `recordExternal` de `VkSpriteBatch`; `VkDrawFeeder::feedPool` (ramo `useTexcoords`).

- [ ] **Step 1: Alvo de teste visível** (o "teste que falha" desta tarefa é visual)

Temporário, atrás de `#if 0`/`#if 1` local e removido no Step 5: no primeiro quadro, o feeder cria uma imagem 2D-array 64x64 de uma camada preenchida com magenta **pré-multiplicado** a 50% (`128, 0, 128, 128`), registra-a em `VkRmlTargets` com o id `0xFFFFFFFF` e emite um quadrado de 200x200 px em (40, 40) com esse id, entre o pool do mapa e o da interface.
Run: `... -Tag vk -Backend vulkan -Only demo` e abrir `build\rmlui-verify\shots\demo-vk.png`.
Expected antes da implementação: nada desenhado em (40,40) (o feeder não conhece o id).

- [ ] **Step 2: Segmento com textura e terceiro pipeline**

`Segment` ganha `VkDescriptorSet texture`; `recordExternal` liga o descriptor do segmento (o do atlas quando nulo) só quando ele muda. `createPipeline` cria o terceiro pipeline, igual ao primeiro exceto pela mistura. Os bindings externos saem de um descriptor pool próprio (64 conjuntos, `FREE_DESCRIPTOR_SET`), com o mesmo layout do pipeline de sprites.

- [ ] **Step 3: O feeder reconhece o alvo**

No ramo com textura de `feedPool`: antes de `resolveSlot`, `VkRmlTargets::instance().find(texture->m_uniqueId)`. Se achar: `batch.setTexture(target->binding)`, `batch.setPipeline(2)`, coordenadas de textura = pixels da origem divididos pelo tamanho do alvo (sem inversão), camada 0; os vértices passam pelo mesmo mapeamento de framebuffer temporário, scissor e recorte do mapa dos demais. Depois do objeto, `setTexture(VK_NULL_HANDLE)` e o pipeline anterior.

- [ ] **Step 4: Ver o quadrado**

Run: o comando do Step 1.
Expected: um quadrado magenta translúcido em (40,40)-(240,240), por cima do fundo e por baixo da interface (o texto do menu superior passa por cima dele), com a cor do fundo visível através dele em 50%. Registrar a captura no ledger.

- [ ] **Step 5: Remover o alvo de teste, verificar regressão e commit**

Run: `... -Tag vk -Backend vulkan -Only demo` (sem quadrado) e `... -Tag gl -Only demo` — Expected: `failed: 0` nos dois.

```bash
git add src/framework/graphics/vulkan/vkbatch.h src/framework/graphics/vulkan/vkbatch.cpp src/framework/graphics/vulkan/vkfeeder.cpp src/framework/graphics/vulkan/vkrmltargets.h src/framework/graphics/vulkan/vkrmltargets.cpp src/framework/rml/rmlrenderer.h src/CMakeLists.txt vc18/otclient.vcxproj
git commit -m "feat(vulkan): per-segment texture and premultiplied blending in the sprite batch"
```

---

### Task 4: `vkrml::Device`, o dispositivo falso, o alocador e a destruição adiada

**Files:**
- Create: `src/framework/graphics/vulkan/vkrmldevice.h`, `vkrmlalloc.h`, `vkrmlalloc.cpp`
- Modify: `src/CMakeLists.txt`, `vc18/otclient.vcxproj`
- Test: `tests/rml/vkrml_fake_device.h`, `tests/rml/vkrml_alloc_test.cpp`, `tests/rml/vkrml_fake_device_test.cpp`

**Interfaces:**
- Produces:

```cpp
// vkrmldevice.h
namespace vkrml {
using Image = uint32_t;      // 0 = none
using Geometry = uint32_t;   // 0 = none

enum class ImageKind : uint8_t {
    Texture,       // sampled only, uploaded once (fonts, images, saved layers)
    Target,        // the widget's image: color attachment, sampled by the sprite batch
    LayerColor,    // multisampled color attachment of a layer
    LayerStencil,  // multisampled stencil shared by the layers of one renderer
    Postprocess,   // single-sample color attachment, sampled, blit source and destination
};
enum class Program : uint8_t { Color, Texture, Gradient, Creation, Passthrough, ColorMatrix, BlendMask, Blur, DropShadow };
enum class Blend : uint8_t { Premultiplied, Replace, ColorWriteOff };
enum class Stencil : uint8_t { Off, TestEqual, Replace, Increment };   // Replace / Increment always pass and write

struct Rect { int x{ 0 }, y{ 0 }, width{ 0 }, height{ 0 }; };          // pixels, origin at the top-left

struct Draw {
    Program program{ Program::Color };
    Blend blend{ Blend::Premultiplied };
    Stencil stencil{ Stencil::Off };
    uint8_t stencilReference{ 0 };       // TestEqual: compared; Replace: written
    Geometry geometry{ 0 };              // 0 = full-target triangle
    Image texture{ 0 };                  // 0 = none
    Image mask{ 0 };                     // BlendMask only
    Rml::Matrix4f transform;             // projection * element transform (identity for full-target draws)
    Rml::Vector2f translation;
    Rml::Vector2f uvOffset, uvScale{ 1.f, 1.f };   // full-target draws
    const void* uniforms{ nullptr };     // the program's fragment parameter block
    uint32_t uniformSize{ 0 };
    const Rect* scissor{ nullptr };      // nullptr = none
};

class Device {
public:
    virtual ~Device() = default;
    virtual bool alive() const = 0;                 // false once the Vulkan context is gone: every call below is a no-op
    virtual bool canRecord() const = 0;             // true only while a pre-pass is open: creating and drawing need it
    virtual bool supportsEffects() const = 0;
    virtual Image createImage(ImageKind kind, int width, int height) = 0;
    virtual void uploadImage(Image image, Rml::Span<const Rml::byte> rgba) = 0;   // outside a pass
    virtual void destroyImage(Image image) = 0;                                    // deferred past the frames in flight
    virtual Geometry createGeometry(Rml::Span<const Rml::Vertex> vertices, Rml::Span<const int> indices) = 0;
    virtual void destroyGeometry(Geometry geometry) = 0;
    virtual void beginPass(Image color, Image stencil) = 0;    // keeps what the images hold; stencil 0 = none
    virtual void endPass() = 0;
    virtual void clear(bool color, bool stencil, uint8_t stencilValue) = 0;        // inside a pass
    virtual void draw(const Draw& draw) = 0;                                       // inside a pass
    virtual void resolve(Image multisampled, Image destination) = 0;               // outside a pass
    virtual void blit(Image source, const Rect& from, Image destination, const Rect& to, bool linear) = 0;   // outside a pass
    virtual void publishTarget(Image target, uint32_t textureUniqueId) = 0;        // makes it findable by the feeder
    virtual void unpublishTarget(uint32_t textureUniqueId) = 0;
};

// vkrmlalloc.h
// First-fit allocator over fixed-size blocks; free neighbours are merged. Offsets are aligned.
class BlockAllocator {
public:
    struct Allocation { uint32_t block{ UINT32_MAX }; uint32_t offset{ 0 }; uint32_t size{ 0 }; bool valid() const; };
    explicit BlockAllocator(uint32_t blockSize, uint32_t alignment);
    Allocation allocate(uint32_t size);      // a request larger than a block gets a block of its own
    void free(const Allocation& allocation);
    uint32_t blockCount() const;
    uint32_t blockSize(uint32_t block) const;
    bool blockIsEmpty(uint32_t block) const;
};

// What is released while frames are in flight is destroyed `delay` frames later.
template<typename T>
class Graveyard {
public:
    explicit Graveyard(uint32_t delay);
    void bury(uint64_t frameNumber, T item);
    template<typename F> void collect(uint64_t frameNumber, F&& destroy);   // destroys what was buried at or before frameNumber - delay
    template<typename F> void flush(F&& destroy);                           // shutdown: everything, now
    size_t size() const;
};
}
```

O **dispositivo falso** (`tests/rml/vkrml_fake_device.h`, classe `vkrml::FakeDevice`) registra cada chamada num `std::vector<std::string>` e **falha o teste** (`ADD_FAILURE`) quando: `draw`/`clear` fora de um passe; `beginPass` com outro aberto; `resolve`/`blit`/`uploadImage`/`destroyImage` dentro de um passe; imagem ou geometria inexistente ou já destruída; o tipo da imagem não serve para o uso (anexo de cor = `Target`/`LayerColor`/`Postprocess`, stencil = `LayerStencil`, amostrada = `Texture`/`Postprocess`, origem de `resolve` = `LayerColor`); a textura ou a máscara de um `draw` é o anexo de cor do passe aberto; `Stencil` diferente de `Off` num passe sem stencil. Também falha quando algo além de `destroyImage`, `destroyGeometry` e `unpublishTarget` é chamado com `recordFlag == false`. Tem `aliveFlag`, `recordFlag` e `effectsFlag` públicos.

- [ ] **Step 1: Testes do alocador e do cemitério (falhando)**

`vkrml_alloc_test.cpp`:
- `VkRmlBlockAllocator.AllocationsDoNotOverlapAndRespectAlignment` (bloco 1024, alinhamento 16, tamanhos 10, 100, 33).
- `...FreedSpaceIsReused` e `...NeighbouringFreeRangesAreMerged` (liberar dois vizinhos e alocar a soma no mesmo bloco).
- `...AFullBlockOpensAnother` e `...ARequestLargerThanABlockGetsItsOwn`.
- `...ABlockWithEverythingFreedIsEmpty`.
- `VkRmlGraveyard.NothingIsDestroyedBeforeTheDelayHasPassed`: enterrado no quadro 10 com atraso 2: `collect(10)` e `collect(11)` não destroem, `collect(12)` destrói (Review Focus 2).
- `...FlushDestroysEverything`, `...CollectKeepsTheOrderOfBurial`.

- [ ] **Step 2: Testes do próprio falso (falhando)**

`vkrml_fake_device_test.cpp`: cada regra acima tem um teste que comete a infração dentro de `EXPECT_NONFATAL_FAILURE` (um validador que não acusa nada não protege ninguém), mais `ACorrectSequenceIsAccepted`.

- [ ] **Step 3: Implementar** `BlockAllocator`, `Graveyard`, `FakeDevice`. Run: `ctest --test-dir build/windows-release -R "VkRml"` — Expected: todos passam.

- [ ] **Step 4: Commit**

```bash
git add src/framework/graphics/vulkan/vkrmldevice.h src/framework/graphics/vulkan/vkrmlalloc.h src/framework/graphics/vulkan/vkrmlalloc.cpp tests/rml/vkrml_fake_device.h tests/rml/vkrml_alloc_test.cpp tests/rml/vkrml_fake_device_test.cpp tests/rml/CMakeLists.txt src/CMakeLists.txt vc18/otclient.vcxproj
git commit -m "feat(rmlui): device seam, validating fake, block allocator and deferred destruction for the Vulkan executor"
```

---

### Task 5: `VkRmlDeviceVk`, shaders e escolha de formatos

**Files:**
- Create: `src/framework/graphics/vulkan/vkrmldevice_vk.h`, `vkrmldevice_vk.cpp`, `data/shaders/vulkan/rml/*` (12 fontes + 12 `.spv`)
- Modify: `src/framework/graphics/vulkan/vkcontext.h`, `vkcontext.cpp`, `src/CMakeLists.txt`, `vc18/otclient.vcxproj`
- Test: `tests/rml/vkrml_caps_test.cpp`

**Interfaces:**
- Consumes: `vkrml::Device`, `BlockAllocator`, `Graveyard` (Tarefa 4); `VkContext::currentPrePass()`, `device()`, `kFramesInFlight` (Tarefa 2); `VkSpriteBatch::createTextureBinding` e `VkRmlTargets` (Tarefa 3).
- Produces:

```cpp
// vkrmldevice_vk.h
namespace vkrml {
// What the GPU offers, reduced to what the choice depends on (filled from vkGetPhysicalDevice*Properties).
struct Caps {
    bool d24s8{ false }, d32s8{ false }, s8{ false };    // usable as depth-stencil attachment
    uint32_t colorSamples{ 1 }, stencilSamples{ 1 };     // bit masks of VkSampleCountFlags
    uint32_t maxImageDimension{ 0 };
};
enum class StencilFormat : uint8_t { None, D24S8, D32S8, S8 };
struct Choice { StencilFormat stencil{ StencilFormat::None }; uint32_t samples{ 1 }; bool usable{ false }; };
Choice choose(const Caps& caps);   // usable == false: no stencil format at all
}

class VkRmlDeviceVk final : public vkrml::Device { public: bool init(); void shutdown(); /* + Device */ };

// vkcontext.h
// The RmlUi device of this context, created on first use. nullptr when it cannot be created
// (missing .spv, no stencil format); the reason is logged once.
vkrml::Device* rmlDevice();
```

Decisões de implementação fixadas aqui:
- **Recursos compartilhados** (shader modules, render passes, pipelines, samplers, o pixel branco) pertencem ao `VkRmlDeviceVk`, um por contexto, criado no primeiro uso e destruído em `VkContext::terminate()` antes do device. Os pipelines são criados sob demanda e guardados por chave `(Program, Blend, Stencil, tipo de passe)`.
- **Passes**: três tipos de render pass, todos com `loadOp = LOAD` e sem transição de layout (layout inicial = final): camada (cor MSAA + stencil), pós-processo (cor, 1 amostra) e alvo (cor, 1 amostra). As transições são barreiras explícitas feitas pelo device, que guarda o layout atual de cada imagem; `clear` usa `vkCmdClearAttachments`.
- **Parâmetros dos shaders**: matriz e translação por push constants do estágio de vértice (72 bytes); os parâmetros de fragmento num bloco uniforme dinâmico, copiado para uma arena por quadro em voo (reiniciada quando o quadro volta). Conjunto 0 = bloco, conjunto 1 = textura, conjunto 2 = máscara; onde não há textura liga-se o pixel branco.
- **Vértices**: `Rml::Vertex` vai para o buffer como está (posição `R32G32_SFLOAT` em 0, cor `R8G8B8A8_UNORM` em 8, coordenada de textura `R32G32_SFLOAT` em 12); índices de 32 bits. Geometria em blocos de 1 MiB `HOST_VISIBLE` mapeados permanentemente, sub-alocados pelo `BlockAllocator`.
- **Texturas do RmlUi**: `R8G8B8A8_UNORM`, filtro linear, `CLAMP_TO_EDGE`; upload por buffer de staging gravado no command buffer do pré-passe.
- **Alvo do widget**: imagem 2D de uma camada com duas views (2D para o framebuffer, 2D-array para o batch de sprites), amostrada com filtro `NEAREST`; `publishTarget` cria o binding com `VkSpriteBatch::createTextureBinding` e registra em `VkRmlTargets`.
- **Sem pré-passe aberto** (`currentPrePass() == nullptr`): `canRecord()` é `false`; `createImage`, `createGeometry`, `beginPass`, `draw`, `uploadImage`, `resolve` e `blit` registram um erro uma vez e não fazem nada. As destruições valem sempre.
- **Destruição adiada**: `destroyImage` e `destroyGeometry` enterram o recurso num `Graveyard` com atraso `VkContext::kFramesInFlight`; a coleta roda no início de cada pré-passe e `shutdown()` destrói tudo.

- [ ] **Step 1: Testes da escolha de formatos (falhando)** — Review Focus 1

`vkrml_caps_test.cpp`, suíte `VkRmlCaps`:
- `PrefersD24S8AndTwoSamples`: tudo disponível → `D24S8`, 2 amostras, `usable`.
- `FallsBackToD32S8ThenS8`.
- `WithoutAnyStencilFormatItIsNotUsable`.
- `UsesFourSamplesWhenTwoAreMissing`: máscaras de amostras `1|4` → 4.
- `UsesOneSampleWhenColorAndStencilShareNoMultisampleCount`: cor `1|2`, stencil `1|4` → 1.

- [ ] **Step 2: Implementar `vkrml::choose`** e ver passar.

- [ ] **Step 3: Shaders**

Portar para GLSL 450 os 12 shaders de `RmlUi_Renderer_GL3.cpp` (linhas 66 a 302), com `layout(location)`, `layout(push_constant)`, `layout(set, binding)` e sem as inversões verticais. O bloco do gradiente guarda as posições das paradas em `vec4[4]` (16 floats) para caber em 352 bytes. Estender `compile_shaders.bat` não é necessário (o laço da Tarefa 1 já cobre `rml\`).
Run: `data\shaders\vulkan\compile_shaders.bat` — Expected: `SPIR-V gotowe.` e 12 `.spv` novos. `build_pak.py` já leva `data/shaders/vulkan/**/*.spv` e deixa as fontes de fora (o filtro é por prefixo de caminho); conferir listando o que ele incluiria de `data/shaders/vulkan/rml`.

- [ ] **Step 4: `VkRmlDeviceVk`**

Implementar a interface inteira. Estruturas C++ espelho dos blocos uniformes ficam em `vkrmldevice_vk.cpp` com `static_assert` de tamanho.

- [ ] **Step 5: Teste de fumaça com a GPU**

Temporário, removido no Step 6: no primeiro quadro, um pré-passe cria um `Target` 200x200, abre um passe nele, limpa com cor, desenha um triângulo com o programa `Color` e um quadrado com `Texture` (uma textura 2x2 de quatro cores enviada por `uploadImage`), fecha e publica com o id `0xFFFFFFFE`; o feeder emite o quadrado em (40,40) como na Tarefa 3.
Run: `... -Tag vk -Backend vulkan -Only demo`.
Expected: na captura, o triângulo e as quatro cores (linear entre elas) em (40,40); nenhum `[vulkan]` de erro no log; `Exit 0` (tudo destruído no encerramento).

- [ ] **Step 6: Remover o teste de fumaça, regressão e commit**

Run: `ctest -R "Rml|VkRml"`, `... -Tag vk -Backend vulkan -Only demo`, `... -Tag gl -Only demo` — Expected: tudo verde.

```bash
git add src/framework/graphics/vulkan/vkrmldevice_vk.h src/framework/graphics/vulkan/vkrmldevice_vk.cpp src/framework/graphics/vulkan/vkcontext.h src/framework/graphics/vulkan/vkcontext.cpp data/shaders/vulkan/rml tests/rml/vkrml_caps_test.cpp tests/rml/CMakeLists.txt src/CMakeLists.txt vc18/otclient.vcxproj
git commit -m "feat(vulkan): device for the RmlUi executor and its SPIR-V shaders"
```

---

### Task 6: Etapa 1: geometria, texturas, scissor, transformação e máscara de recorte

**Files:**
- Create: `src/framework/graphics/vulkan/vkrmlrenderer.h`, `vkrmlrenderer.cpp`, `src/framework/rml/rmlbackend_vk.h`, `rmlbackend_vk.cpp`
- Create: `tools/rmlui/verify/plain.lua`
- Modify: `src/framework/rml/rmlbackend.cpp`, `rmlmanager.cpp`, `tools/rmlui/verify/vulkan.lua`, `tools/rmlui/verify/exit-stress.lua`, `tools/rmlui/verify/run.ps1`, `src/CMakeLists.txt`, `vc18/otclient.vcxproj`
- Test: `tests/rml/vkrml_renderer_test.cpp`

**Interfaces:**
- Consumes: `vkrml::Device` e `FakeDevice` (Tarefa 4), `VkContext::rmlDevice()` (Tarefa 5), `RmlBackend` (plano 1).
- Produces:

```cpp
// vkrmlrenderer.h
class VkRmlRenderInterface final : public Rml::RenderInterface {
public:
    explicit VkRmlRenderInterface(vkrml::Device& device);
    ~VkRmlRenderInterface() override;                 // destroys every image and geometry it still owns

    // One frame of one widget. target is a vkrml::ImageKind::Target of the given size.
    void beginFrame(vkrml::Image target, int width, int height);
    void endFrame();
    bool supportsEffects() const;                      // false until Task 8

    static Rml::Matrix4f projection(int width, int height);   // pixels, y down, z in [0, 1] (Vulkan clip space)
    // + every Rml::RenderInterface method
};

// rmlbackend_vk.h
class RmlBackendVk final : public RmlBackend {
public:
    static RmlBackendPtr create();    // nullptr when VkContext has no usable RmlUi device
    // name(): "Vulkan"
};

// rmlbackend.cpp
// createRmlBackend(): Vulkan executor when the client is drawing with Vulkan, OpenGL executor when
// it has a GL context, nullptr otherwise. rmlExpectedBackendName() follows the same order.
```

`RmlManager::init()` deixa de recusar por falta de contexto OpenGL: recusa quando `rmlExpectedBackendName()` devolve `"none"`.

Comportamento da etapa 1 (o que os testes fixam):
- `beginFrame`: cria na primeira vez (e recria quando o tamanho muda) a camada 0 (`LayerColor` + `LayerStencil`) e um `Postprocess`; abre o passe na camada 0 e limpa cor e stencil. O passe aberto é rastreado: qualquer operação "fora de passe" o fecha antes, e o próximo desenho o reabre na camada do topo.
- `RenderGeometry`: programa `Texture` quando há textura, `Color` quando não; `Stencil::TestEqual` com a referência atual quando a máscara de recorte está ligada, `Off` quando não; scissor em pixels do alvo, sem inversão.
- `RenderToClipMask`: `Set` limpa o stencil para 0 e desenha com `Replace` referência 1 (referência de teste 1); `SetInverse` limpa para 1 e desenha com `Replace` referência 0 (teste 1); `Intersect` desenha com `Increment` e a referência de teste sobe 1. Sempre `Blend::ColorWriteOff`.
- `endFrame`: fecha o passe, `resolve` da camada 0 para o `Postprocess`, abre o passe no alvo, limpa a cor, desenha o `Postprocess` com `Passthrough` e `Blend::Premultiplied` e fecha. Quem publica o alvo é o `RmlBackendVk` (ele conhece o `uniqueId` da textura do client).
- Sem pré-passe (`device.canRecord() == false`; acontece quando o backend é liberado com comandos ainda na fila): um quadro inteiro é ignorado em silêncio e nada é criado (`GenerateTexture` e `CompileGeometry` devolvem 0); as liberações valem.
- Camadas, filtros e shaders ainda não existem: `PushLayer` devolve a camada do topo, `CompositeLayers`/`PopLayer` não fazem nada, `CompileFilter`, `CompileShader`, `SaveLayerAsTexture` e `SaveLayerAsMaskImage` devolvem 0.
- `device.alive() == false`: nenhuma chamada chega ao device; os identificadores guardados são esquecidos sem `destroy*`.

- [ ] **Step 1: Testes da etapa 1 (falhando)**

`vkrml_renderer_test.cpp`, suíte `VkRmlRenderer`, todos contra `FakeDevice` (que já acusa qualquer sequência inválida):
- `AnEmptyFrameClearsTheLayerAndCompositesIntoTheTarget`: a sequência exata de `beginFrame` + `endFrame`.
- `GeometryWithoutTextureUsesTheColorProgram` / `GeometryWithTextureUsesTheTextureProgram`.
- `TheTranslationAndTransformReachTheDraw`: `SetTransform(m)` → `draw.transform == projection(w,h) * m`; `SetTransform(nullptr)` → só a projeção.
- `TheScissorIsPassedInTargetPixels`: região (10,20)-(110,70) → `Rect{10,20,100,50}`; desligado → `scissor == nullptr`.
- `ClipMaskSetWritesOneAndTestsForOne`, `ClipMaskSetInverseClearsToOneAndWritesZero`, `ClipMaskIntersectIncrementsTheReference`, `WithTheClipMaskDisabledNothingIsTested`.
- `LayersAreReusedByTheNextFrame`: dois quadros do mesmo tamanho → nenhuma `createImage` no segundo.
- `AResizeRecreatesTheLayersAndDestroysTheOldOnes` (Review Focus 3): quadro 64x48 e depois 128x96 → as imagens antigas são destruídas, nenhuma é usada depois.
- `ReleasedTexturesAndGeometryAreDestroyed`.
- `ADeadDeviceIsNeverCalled` (Review Focus 4): `aliveFlag = false` → um quadro inteiro e o destrutor não registram nenhuma chamada.
- `OutsideAPrePassOnlyDestructionsTakeEffect`: com `recordFlag = false`, um quadro com geometria e textura não gera nenhuma chamada; `ReleaseGeometry`/`ReleaseTexture` de recursos criados antes geram os `destroy*`.
- `LayerCallsAreHarmlessBeforeTheEffectsExist`: `PushLayer`, um desenho, `CompositeLayers`, `PopLayer` → o desenho vai para a camada 0 e o quadro termina normalmente; `CompileFilter("blur")` e `CompileShader("linear-gradient")` devolvem 0.
- `VkRmlProjection.KeepsRotatedGeometryInsideTheClipVolume` (Review Focus 5): para pontos com z entre -1000 e 1000, `projection(800, 600)` dá `0 <= z/w <= 1`; o canto (0,0) vai para (-1,-1) e (800,600) para (1,1).

Run: `ctest --test-dir build/windows-release -R VkRmlRenderer` — Expected: não compila (`VkRmlRenderInterface` não existe).

- [ ] **Step 2: Implementar `VkRmlRenderInterface` (etapa 1)** e ver a suíte passar. Referência: `BeginFrame`, `EndFrame`, `CompileGeometry`, `RenderGeometry`, `SetScissor`, `EnableClipMask`, `RenderToClipMask`, `GenerateTexture`, `SetTransform` do backend GL3.

- [ ] **Step 3: `RmlBackendVk`, a fábrica e o `RmlManager`**

`RmlBackendVk::beginFrame(target)`: cria na primeira vez (e recria quando `target` muda) a imagem `Target` do tamanho de `target` e chama `VkRmlRenderInterface::beginFrame`. `RmlBackendVk::endFrame()`: `VkRmlRenderInterface::endFrame()` e depois `device.publishTarget(imagem, target->uniqueId())`. O destrutor remove a publicação e destrói a imagem. `tests/rml/rmlbackend_test.cpp` continua valendo (sem contexto nenhum não há executor).

- [ ] **Step 4: `vulkan.lua` passa a esperar o RmlUi ligado**

As cinco checagens viram: `g_rml.isReady()` é `true`; `getBackendName()` é `"Vulkan"`; `supportsAdvancedEffects()` é `false`; `loadDocument` do demo devolve `true`; depois de fechar a janela, `g_rml.getContextCount() == 0`. A contagem de linhas de contexto OpenGL continua tendo de ser 0.

- [ ] **Step 5: Verificação em execução**

Run: `... -Exe .\CrystalOTC_gl_x64.exe -Tag vk -Backend vulkan -Only vulkan,demo,focus,lifetime,gc,exit`
Expected: `failed: 0`. `demo-vk.png` mostra a janela do demo com texto, botões e sprites de itens; sem gradientes e sombras (tema `efeitos` desligado). `lifetime`: cerca de 62 quadros por segundo com conteúdo mudando, 0 parado.

Comparação em condições iguais: no OpenGL o tema `efeitos` está ligado, então as capturas normais diferem de propósito nesta etapa. `plain.lua` abre o demo e a aba "Formulários" do showcase, chama `window:getContext():ActivateTheme('efeitos', false)` em cada janela e captura `plain-demo-<tag>` e `plain-forms-<tag>` (anunciando o retângulo); `run.ps1` ganha o passo `plain`.
Run: `... -Tag gl -Only plain`, `... -Tag vk -Backend vulkan -Only plain`, e `compare.ps1 -A build\rmlui-verify\shots\plain-demo-gl.png -B build\rmlui-verify\shots\plain-demo-vk.png` (idem para `plain-forms`).
Expected: fração >= 0.97 nas duas. Diferenças acima disso: olhar a imagem, corrigir ou registrar no ledger o que difere e por quê.

- [ ] **Step 5b: Janela do client redimensionada com RmlUi aberto** (Review Focus 3)

`exit-stress.lua` ganha o modo `window`: com a janela do demo aberta, `g_window.resize` alterna dez vezes entre dois tamanhos, depois volta ao original e sai; `run.ps1` roda esse modo três vezes no passo `exit`.
Run: `... -Tag vk -Backend vulkan -Only exit` — Expected: todos com `Exit 0`. Run: `... -Tag gl -Only exit` — Expected: idem (regressão).

- [ ] **Step 6: `.spv` ausente** (Review Focus 4)

Renomear `data/shaders/vulkan/rml/color.frag.spv`, rodar `... -Tag vk-nospv -Backend vulkan -Only demo`, restaurar o arquivo.
Expected: `Exit 0`; no log uma linha `[vulkan]` dizendo qual shader faltou e `[verify] backend=unavailable ready=false`; a janela do demo não abre e nada mais muda.

- [ ] **Step 7: Commit**

```bash
git add src/framework/graphics/vulkan/vkrmlrenderer.h src/framework/graphics/vulkan/vkrmlrenderer.cpp src/framework/rml/rmlbackend_vk.h src/framework/rml/rmlbackend_vk.cpp src/framework/rml/rmlbackend.cpp src/framework/rml/rmlmanager.cpp tests/rml/vkrml_renderer_test.cpp tests/rml/CMakeLists.txt tools/rmlui/verify/vulkan.lua tools/rmlui/verify/plain.lua tools/rmlui/verify/exit-stress.lua tools/rmlui/verify/run.ps1 src/CMakeLists.txt vc18/otclient.vcxproj
git commit -m "feat(rmlui): Vulkan executor, stage 1 (geometry, textures, scissor, transforms, clip mask)"
```

---

### Task 7: Etapa 2a: camadas, opacidade, textura de camada e máscara de imagem

**Files:**
- Modify: `src/framework/graphics/vulkan/vkrmlrenderer.h`, `vkrmlrenderer.cpp`
- Test: `tests/rml/vkrml_renderer_test.cpp`

**Interfaces:**
- Consumes: `VkRmlRenderInterface` da Tarefa 6.
- Produces: `PushLayer`, `PopLayer`, `CompositeLayers`, `SaveLayerAsTexture`, `SaveLayerAsMaskImage`, e os filtros `opacity` (programa `Passthrough` com cor) e máscara (`BlendMask`). Referência: `PushLayer`, `CompositeLayers`, `PopLayer`, `SaveLayerAsTexture`, `SaveLayerAsMaskImage`, `BlitLayerToPostprocessPrimary`, `RenderLayerStack` e os casos `Passthrough` e `MaskImage` de `RenderFilters` no backend GL3. Os buffers de pós-processo (primário, secundário, terciário, máscara) são criados sob demanda, como em `EnsureFramebufferPostprocess`.

- [ ] **Step 1: Testes (falhando)**

- `PushLayerDrawsIntoANewClearedLayer`: depois de `PushLayer`, o desenho seguinte está num passe cuja cor é uma `LayerColor` diferente da camada 0, limpa; o stencil é o mesmo da camada 0.
- `PopLayerReturnsToTheParentLayer`.
- `CompositeLayersResolvesTheSourceAndDrawsItIntoTheDestination`: `resolve(source → postprocess)`, depois um desenho `Passthrough` na camada de destino com a textura = esse pós-processo.
- `BlendModeReplaceDisablesBlending`: `Blend::Replace` nesse desenho.
- `LayersBeyondTheFirstAreReusedAcrossFrames`.
- `OpacityFilterDrawsWithTheOpacityAsColor`: `CompileFilter("opacity", {value: 0.5})` → um desenho `Passthrough` entre dois pós-processos com o bloco uniforme `(0.5, 0.5, 0.5, 0.5)`.
- `SaveLayerAsTextureCopiesTheScissorRegionIntoANewTexture`: scissor (10,20,100,50) → uma `Texture` 100x50 criada e um `blit` da região (10,20,100,50) para (0,0,100,50), sem inversão; o identificador devolvido serve como textura num desenho posterior.
- `SaveLayerAsMaskImageFeedsTheBlendMaskProgram`: o filtro devolvido, usado em `CompositeLayers`, gera um desenho `BlendMask` com `mask` = o pós-processo de máscara.
- `ReleaseFilterOfAMaskImageDoesNotDestroyTheSharedMaskBuffer`.
- Atualizar `LayerCallsAreHarmlessBeforeTheEffectsExist` da Tarefa 6: deixa de existir (as chamadas agora têm efeito).

- [ ] **Step 2: Implementar** e ver a suíte inteira passar.

- [ ] **Step 3: Verificação em execução**

`supportsEffects()` continua `false` (o tema `efeitos` ainda não liga), mas `opacity`, `border-radius` com recorte e `mask-image` fora do tema já usam camadas.
Run: `... -Tag vk -Backend vulkan -Only demo,showcase,lifetime,gc,exit` — Expected: `failed: 0`. Comparar a aba "Imagens" do showcase (usa opacidade na transição) entre `gl` e `vk`: fração >= 0.97.

- [ ] **Step 4: Commit**

```bash
git add src/framework/graphics/vulkan/vkrmlrenderer.h src/framework/graphics/vulkan/vkrmlrenderer.cpp tests/rml/vkrml_renderer_test.cpp
git commit -m "feat(rmlui): Vulkan executor, layers, opacity, saved layers and mask images"
```

---

### Task 8: Etapa 2b: gradientes, matriz de cor, desfoque e sombra; tema `efeitos` ligado

**Files:**
- Modify: `src/framework/graphics/vulkan/vkrmlrenderer.h`, `vkrmlrenderer.cpp`, `src/framework/rml/rmlbackend_vk.cpp`, `tools/rmlui/verify/vulkan.lua`
- Test: `tests/rml/vkrml_renderer_test.cpp`

**Interfaces:**
- Produces: `CompileShader`/`RenderShader`/`ReleaseShader` (gradientes linear, radial e cônico, com repetição; `shader` "creation"), `CompileFilter` para `blur`, `drop-shadow`, `brightness`, `contrast`, `invert`, `grayscale`, `sepia`, `hue-rotate`, `saturate`; `supportsEffects()` devolve `device.supportsEffects()`; `RmlBackendVk::name()` continua `"Vulkan"` e `supportsAdvancedEffects()` passa a `true`. Referência: `CompileFilter`, `RenderFilters`, `RenderBlur`, `SigmaToParameters`, `SetBlurWeights`, `SetTexCoordLimits`, `CompileShader`, `RenderShader` do backend GL3.

```cpp
// vkrmlrenderer.h - pure functions, tested on their own
namespace vkrml {
void sigmaToParameters(float desiredSigma, int& passLevel, float& sigma);      // as in the GL3 backend
std::array<float, 4> blurWeights(float sigma);                                   // normalised: w0 + 2*(w1+w2+w3) == 1
}
```

- [ ] **Step 1: Testes (falhando)**

- `VkRmlBlur.SigmaToParametersMatchesTheReference`: para sigma 0.5, 2, 6, 20, 100 os pares `(passLevel, sigma)` iguais aos da função do backend GL3 (valores copiados para o teste rodando a função original uma vez).
- `VkRmlBlur.WeightsAreNormalised`.
- `LinearGradientFillsTheUniformBlock`: `CompileShader("linear-gradient", {...})` com duas paradas → `RenderShader` gera um desenho `Gradient` cujo bloco tem a função, `p`, `v`, o número de paradas e as cores **pré-multiplicadas**.
- `RepeatingGradientsUseTheRepeatingFunction`, `RadialAndConicGradientsAreSupported`, `MoreThanSixteenStopsAreTruncated`.
- `AnUnknownShaderOrFilterIsRefused`: devolve 0 e nada chega ao device.
- `ColorMatrixFiltersCarryTheirMatrix`: `grayscale(1)` → desenho `ColorMatrix` com a matriz de tons de cinza; `brightness(2)` → diagonal 2.
- `BlurRunsItsPassesBetweenPostprocessBuffers`: sigma 4 → os `blit` de redução (lineares), dois desenhos `Blur` (horizontal e vertical) com os pesos e o deslocamento de texel certos, e o `blit` de volta; a entrada e a saída são o pós-processo primário.
- `DropShadowDrawsTheShadowThenTheOriginalOnTop`.
- `FiltersRunInTheOrderTheyWereGiven`.

- [ ] **Step 2: Implementar** e ver a suíte inteira passar.

- [ ] **Step 3: Ligar o tema**

`vulkan.lua`: `getBackendName()` passa a `"Vulkan (full effects)"` e `supportsAdvancedEffects()` a `true`.

- [ ] **Step 4: Verificação em execução, as nove abas**

Run: `... -Exe .\CrystalOTC_gl_x64.exe -Tag vk -Backend vulkan` (tudo, com a máquina livre: inclui o script de teclas).
Expected: `failed: 0`.

Run: `compare.ps1` para as nove capturas `showcase-N-*`, `options`, `outfit` e `minimap` entre `gl` e `vk`, na região da janela.
Expected: fração >= 0.97 em todas. A aba "Efeitos" é a que mais importa: gradientes, `box-shadow`, `blur`, `drop-shadow`, `grayscale`, transformações e brilho do texto presentes e no mesmo lugar. Cada diferença acima da tolerância: olhar a imagem, achar a causa, corrigir ou registrar no ledger com a justificativa.

- [ ] **Step 5: Commit**

```bash
git add src/framework/graphics/vulkan/vkrmlrenderer.h src/framework/graphics/vulkan/vkrmlrenderer.cpp src/framework/rml/rmlbackend_vk.cpp tests/rml/vkrml_renderer_test.cpp tools/rmlui/verify/vulkan.lua
git commit -m "feat(rmlui): Vulkan executor, gradients and filters; full effects on Vulkan"
```

---

### Task 9: Paridade nos três modos, memória e documentação

**Files:**
- Modify: `docs/RMLUI.md`, `README.md`, `tools/rmlui/verify/README.md`, `modules/corelib/rml.lua` (só o comentário sobre o backend), `docs/superpowers/specs/2026-11-16-rmlui-design.md` (estado)

- [ ] **Step 1: Os três modos, do zero**

Recompilar `OpenGL|x64` e `DirectX|x64`. Run, com a máquina livre:
`... -Exe .\CrystalOTC_gl_x64.exe -Tag gl`, `... -Exe .\CrystalOTC.exe -Tag angle`, `... -Exe .\CrystalOTC.exe -Tag vk -Backend vulkan`.
Expected: `failed: 0` nos três. `compare.ps1` entre `gl` e `vk` e entre `angle` e `vk` para todas as capturas de janela: >= 0.97.

- [ ] **Step 2: Custo zero sem RmlUi**

Run: um script que só espera 5 s e sai, em modo Vulkan, com `memoryLog` ligado.
Expected: a linha `[vulkan] frame 1 (game queue)` com os mesmos números de antes deste plano (vértices, segmentos, camadas do atlas) e nenhuma linha `[vulkan] rmlui`; nenhum `.spv` de `rml/` lido (uma linha de log temporária em `loadShader` confirma e é removida).

- [ ] **Step 3: Memória com janelas abertas e fechadas**

O `VkRmlDeviceVk` registra, com `memoryLog` ligado, uma linha `[vulkan] rmlui: images N (X MB), geometry blocks M, pipelines P` quando esses números mudam de patamar. Run: `lifetime` e `gc` em modo Vulkan.
Expected: depois de todas as janelas fechadas e de dois quadros, imagens = 0 e blocos de geometria vazios liberados; pipelines permanecem (são compartilhados). Registrar os valores de pico no ledger.

- [ ] **Step 4: Documentação**

`docs/RMLUI.md`: a tabela de backends ganha a linha do Vulkan; "How it works" ganha o caminho Vulkan (pré-passe, alvo por widget, segmento do batch); "Rules the code relies on" ganha: o executor só grava dentro do pré-passe, destruição adiada por dois quadros, nenhuma inversão vertical; "Not covered yet" perde o Vulkan. `README.md`: a linha do RmlUi passa a citar os três modos. `tools/rmlui/verify/README.md`: o parâmetro `-Backend` e o `compare.ps1`.

- [ ] **Step 5: Commit**

```bash
git add docs/RMLUI.md README.md tools/rmlui/verify/README.md modules/corelib/rml.lua docs/superpowers/specs/2026-11-16-rmlui-design.md
git commit -m "docs(rmlui): the Vulkan executor"
```

## O que fica fora deste plano

- Iluminação, shader programs do painter e o resto do que o renderer Vulkan do client ainda não faz (spec, "Fora do escopo"). Widgets OTUI hospedados num documento (`Rml.host`) continuam sendo desenhados pelo feeder, com as limitações atuais.
- Linux e macOS: o renderer Vulkan é só Windows.
- Verificação dentro do jogo: continua dependendo de um servidor e de uma conta de teste.
- A pendência aberta do plano 1 (um objeto de widget sem contexto que às vezes fica referenciado até o client fechar, em máquina carregada).
