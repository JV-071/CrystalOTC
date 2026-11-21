# RmlUi no CrystalOTC: design

Data: 2026-11-16. Estado: aguardando aprovação.

## Intenção

Trazer para o CrystalOTC o RmlUi (documentos `.rml` + `.rcss`, HTML/CSS) hospedado dentro de
widgets OTUI, a partir do fork de referência
[`fellipealbuquerque/otclient-rmlui`](https://github.com/fellipealbuquerque/otclient-rmlui)
(commits `abd46bd`, `fea555e`, `25310ef`, `bf3785d`, `5011102`, `fa41ffc`, `82c2e17`), que parte da
mesma base (OTClient Redemption).

O fork só roda em OpenGL 3.3 de desktop e é compilado por CMake. O CrystalOTC é distribuído pelo
MSBuild (`vc18/otclient.vcxproj`), o executável padrão (`DirectX|x64`) desenha por ANGLE
(OpenGL ES 3 sobre Direct3D 11) e existe um renderer Vulkan próprio. O RmlUi precisa funcionar
nos três.

## Objetivos

1. Os 7 commits do fork, inteiros: `g_rml`, `UIRmlWidget` / `RmlWidget` / `RmlWindow`, imagens
   virtuais de sprites (`item/`, `effect/`, `outfit/`), `data-drag`, tema `efeitos`, o helper Lua
   `Rml` e os cinco módulos de exemplo.
2. A mesma API Lua e o mesmo RML/RCSS do fork, sem mudanças: um módulo escrito para o fork roda
   aqui.
3. Funcionar nos três modos de desenho do client, com os efeitos de CSS que dependem de camadas
   (sombras, filtros, gradientes, máscaras) em todos:

   | Modo | Como se chega nele | Executor do RmlUi |
   |---|---|---|
   | OpenGL de desktop | configuração `OpenGL\|x64`, build CMake | backend GL3 do RmlUi, `#version 330` |
   | ANGLE | configuração `DirectX\|x64` (o `CrystalOTC.exe` distribuído) | o mesmo backend, caminho GLES3 |
   | Vulkan | `renderBackend = vulkan` no `config.ini` | executor Vulkan novo, escrito aqui |

4. Custo zero para quem não usa: nada do RmlUi é inicializado (nem memória de GPU alocada) até o
   primeiro widget RmlUi ser criado.

## Fora do escopo

- Reescrever qualquer interface existente do jogo em RmlUi. Só entram os exemplos do fork.
- O que o próprio fork declara não portado do NWO: fallback OpenGL 2, fontes bitmap `.otfont`
  dentro do RmlUi, relatório `rmluireport.log`.
- Android e WebAssembly: ficam sem RmlUi, como no fork.
- Completar o renderer Vulkan do client naquilo que ele já não faz hoje (iluminação, shader
  programs do painter). Widgets OTUI nativos hospedados num documento (`Rml.host`) continuam
  sendo desenhados pelo feeder Vulkan atual, com as limitações que ele já tem.

## O que faria isto falhar mesmo "funcionando"

- No modo Vulkan, carregar o driver OpenGL ou criar um contexto GL por causa do RmlUi. O modo
  Vulkan puro existe para evitar isso.
- Qualquer regressão de desenho ou de memória no client quando nenhum widget RmlUi existe.
- Uma API Lua diferente da do fork.

## Restrições encontradas no código

- **Build.** `vc18/otclient.vcxproj` usa vcpkg em modo manifesto com o triplet
  `x64-windows-static` e `VcpkgAutoLink`. Não roda CMake, então o `FetchContent` do fork não se
  aplica. O repositório já tem `vcpkg-overlays/` (usado para o `openal-soft`). A baseline do
  vcpkg fixada em `vcpkg.json` traz o port `rmlui` na versão 6.2, com a feature `lua` presa ao
  Lua oficial, não ao LuaJIT.
- **PCH.** `vc18/settings.props` força `framework\pch.h` em todo arquivo. O backend GL3 é código
  de terceiros e precisa ficar fora do PCH e do unity build.
- **ANGLE.** `glutil.h` inclui `<GLES3/gl3.h>` quando `OPENGL_ES` está definido, e
  `win32window.cpp` cria um contexto ES 3. O backend GL3 do RmlUi já tem um caminho GLES3
  (usado para Emscripten): `#version 300 es`, `GL_CLAMP_TO_EDGE` no lugar de
  `GL_CLAMP_TO_BORDER`, sem `GL_FRAMEBUFFER_SRGB`. O fork nunca o exercitou.
- **Vulkan.** O renderer declara Vulkan 1.1, só com a extensão de swapchain. Tem um único
  render pass com um anexo de cor (sem stencil, sem MSAA), um pipeline de sprites mais a
  variante MULTIPLY, e todas as texturas num atlas 2D-array. `VkDrawFeeder` traduz a fila do
  `DrawPool` em triângulos e ignora ações (lambdas GL). `VkContext::drawFrame` grava um único
  command buffer por quadro, com dois quadros em voo.
- **Backend Vulkan oficial do RmlUi 6.3.** Só implementa a interface básica (sem `PushLayer`,
  `CompileFilter`, `CompileShader`) e cria o próprio instance, device e swapchain. Não serve
  como base.
- **Compilador de shaders.** Os `.spv` do renderer Vulkan são versionados e gerados por
  `data/shaders/vulkan/compile_shaders.bat` com `glslang.exe`, que não está instalado nesta
  máquina. `build_pak.py` já empacota os `.spv` e exclui as fontes GLSL sob
  `data/shaders/vulkan/`.
- **Encaixe do fork.** Os pontos do engine que o fork altera existem aqui sem divergência
  relevante: `DrawPool::addAction`, os virtuais de `UIWidget`, `Texture`, `luafunctions.cpp`,
  `painter.cpp`, `graphicalapplication.cpp`, e as APIs de sprites que `rmlimages.cpp` usa.

## Abordagens consideradas para o Vulkan

- **A. Executor Vulkan nativo e completo (escolhida).** Cada widget RmlUi é desenhado numa
  imagem própria, fora da tela, com stencil e com os shaders do backend GL3 portados para
  SPIR-V. O resultado entra no batch como um segmento com textura própria, na ordem correta em
  relação ao OTUI. É a única opção que entrega efeitos no Vulkan puro. É também a mais cara:
  estimativa de 3 a 4 mil linhas de Vulkan e cerca de dez shaders.
- **B. Básico pelo batch existente.** A geometria do RmlUi vira triângulos do batch e as
  texturas vão para o atlas. Pequeno, mas sem sombras, filtros, gradientes e máscaras, e com
  recorte pior em cantos arredondados (não há stencil). Não atende ao objetivo 3.
- **C. Contexto OpenGL escondido só para o RmlUi.** Efeitos completos com pouco código novo, mas
  carrega o driver GL no modo Vulkan e copia pixels entre APIs a cada quadro. Contraria o motivo
  de existir do modo Vulkan.

Escolha do usuário: **A**.

## Arquitetura

O fork já separa "o que o RmlUi pediu" de "quem desenha": `RmlRenderer` implementa
`Rml::RenderInterface` gravando comandos com handles substitutos na thread de UI e os reproduz
depois na thread gráfica. O design mantém essa costura e troca só o destino da reprodução.

```
thread de UI / Lua                      thread principal (gráfica)
------------------                      --------------------------
RmlManager tick: Context::Update        OpenGL / ANGLE:
UIRmlWidget::drawSelf                     DrawPool::draw -> ação replay()
  Context::Render()                         -> executor GL3 -> textura do widget
    -> RmlRenderer grava comandos         retângulo texturizado (alfa pré-multiplicado)
  DrawPool: ação replay + retângulo
            texturizado do alvo         Vulkan:
                                          VkDrawFeeder vê o alvo RmlUi na fila
                                            -> agenda o renderer para este quadro
                                            -> emite um segmento com a textura do alvo
                                          VkContext::drawFrame, antes do passe principal
                                            -> executor Vulkan reproduz os comandos
                                               na imagem do widget
```

### Camada independente de backend (port direto do fork)

- `src/framework/rml/rmlmanager.*`: `g_rml`, interfaces de sistema e de arquivo (via
  `g_resources`), fontes, imagens virtuais, tick.
- `src/framework/rml/uirmlwidget.*`: o widget, um `Rml::Context` por widget, entrada, arrasto.
- `src/framework/rml/rmlrenderer.*`: gravação e reprodução. Passa a reproduzir contra uma
  interface de executor em vez de chamar `RenderInterface_GL3` diretamente.
- `src/client/rmlimages.*`: imagens `item/`, `effect/`, `outfit/` montadas na CPU.
- Bindings em `luafunctions.cpp`, `CompositionMode::PREMULTIPLIED` em `declarations.h` e
  `painter.cpp`, `LuaInterface::getLuaState`, registro em `client.cpp`, término em
  `graphicalapplication.cpp`.

### Interface de executor

Um tipo com as operações que `RmlRenderer::execute` despacha hoje (geometria, texturas,
scissor, máscara de recorte, transformação, camadas, filtros, shaders, início e fim de quadro
com o alvo). Duas implementações: OpenGL e Vulkan. A escolha é feita uma vez por renderer,
conforme o backend ativo do client.

Por passar por essa interface, a gravação e o mapeamento de handles ficam testáveis sem GPU,
com um executor falso.

### Executor OpenGL (desktop e ANGLE)

O `RmlUi_Renderer_GL3.*` do fork (backend oficial do RmlUi 6.3 com as três mudanças do fork:
composição num framebuffer alvo, shaders compartilhados entre instâncias, limpeza de estado),
mais um ramo para `OPENGL_ES` equivalente ao de Emscripten. Um único arquivo atende aos dois
modos. A restauração de estado GL em `replay()` é mantida e revisada para ES 3.

### Executor Vulkan

Código novo, dentro do renderer Vulkan do client e seguindo as convenções dele (ponteiros de
função locais via `vkloader`, sem estado global, `#ifdef WIN32`, falha de `init()` não derruba
o contexto).

- **Paridade com o backend GL3.** Mesmas operações, mesmos nove programas de shader (cor,
  textura, gradiente, criação, passthrough, matriz de cor, máscara de mistura, blur, drop
  shadow), mesma pilha de camadas e mesmos alvos de pós-processamento, mesmos filtros.
- **Alvo por widget.** Uma imagem de cor por widget, criada como 2D-array de uma camada para
  poder ser amostrada pelo shader de sprites existente. Recorte por stencil. Antisserrilhado
  equivalente ao do backend GL3.
- **Onde executa.** `VkContext::drawFrame` ganha um ponto de extensão entre o início do
  command buffer e o início do passe principal. O feeder registra ali os renderers que têm
  comandos pendentes no quadro.
- **Composição.** `VkSpriteBatch` ganha, por segmento, a textura a ligar e um terceiro pipeline
  com mistura de alfa pré-multiplicado. O feeder reconhece a textura alvo do RmlUi na fila do
  `DrawPool` e emite o retângulo como vértices normais do batch, de modo que scissor, recorte
  de buraco do mapa e a transformação retroativa de framebuffers temporários continuem valendo.
- **Vida dos recursos.** Com dois quadros em voo, imagens, buffers e descriptors liberados pelo
  RmlUi são destruídos só depois que os quadros que os usam terminam.
- **Requisitos.** Continua em Vulkan 1.1 sem extensões novas de device.
- **Shaders.** Fontes GLSL em `data/shaders/vulkan/rml/`, `.spv` versionados ao lado,
  `compile_shaders.bat` estendido.

### Build

- `vcpkg-overlays/rmlui/`: port do RmlUi 6.3 (o mesmo do fork), com a feature Lua construída
  sobre o `luajit` do vcpkg, FreeType e o plugin de debugger. Entra em `vcpkg.json` para
  Windows, Linux e macOS.
- `vc18/`: os novos fontes no `.vcxproj`, `FRAMEWORK_RMLUI` nas definições, backend GL3 fora do
  PCH e do unity build.
- `src/CMakeLists.txt`: opção `TOGGLE_RMLUI` (como no fork), `find_package(RmlUi)` no lugar do
  `FetchContent`, desligada à força em Android e WASM.

### Lua, dados e exemplos

- `modules/corelib/rml.lua` (global `Rml`) e a entrada em `corelib.otmod`.
- Módulos: `client_rmldemo` (Ctrl+Shift+R), `client_rmlshowcase` (botão "RmlUi" no menu
  superior, Ctrl+Shift+U), `client_rmloptions` (Ctrl+Shift+O), `game_rmloutfit` (Ctrl+Shift+F),
  `game_rmlminimap` (Ctrl+Shift+M). Nenhum desses atalhos está em uso no client hoje.
- `data/styles/10-rmlwidget.otui`, `data/styles/rml/otc.rcss`, `data/fonts/rml/` (Barlow e
  Share Tech Mono, licença OFL), `src/framework/rml/RMLUI_LICENSE.txt`.
- Onde um exemplo depende de algo que difere no CrystalOTC (opções do `client_options`,
  protocolo 15.30, assets protobuf), o exemplo é adaptado ao client; a API do RmlUi não muda.
- `docs/RMLUI.md`: a documentação do fork, atualizada para este client (build por MSBuild, os
  três modos, o executor Vulkan).

## Comportamento em falhas

- Executor indisponível (sem OpenGL 3.3 ou ES 3; no Vulkan, `.spv` ausente ou formato de stencil
  não suportado): os widgets ficam vazios, `g_rml.isReady()` passa a `false` depois do primeiro
  quadro e sai uma linha `[rmlui]` no log. É o comportamento do fork.
- O backend do client é decidido uma vez, na inicialização (`main.cpp`: se `VkContext::init`
  falhar, cria-se o contexto GL antes do primeiro quadro). Como os executores do RmlUi são
  preguiçosos, nenhum existe nesse momento, e o RmlUi simplesmente usa o backend que ficou
  ativo. Não há troca de executor no meio da sessão e nenhum código de transição.
- Se o Vulkan morrer no meio da sessão, o client hoje congela a imagem (não existe volta para
  OpenGL em modo Vulkan puro). O RmlUi não muda isso: o executor Vulkan para de desenhar junto
  com o resto.
- `g_rml.getBackendName()` informa o executor ativo. `g_rml.supportsAdvancedEffects()` é `true`
  nos três modos quando o executor inicializa por completo, o que liga o tema `efeitos`.

## Verificação

- Compilar `OpenGL|x64` e `DirectX|x64` pelo MSBuild e o preset `windows-release` do CMake.
- Teste unitário (em `tests/`, gtest) da gravação e do mapeamento de handles do `RmlRenderer`
  com um executor falso.
- Assets: `data/things` é ignorado pelo git e está vazio nesta worktree. A verificação usa os
  assets 15.30 do checkout principal (`data/things/1530`), ligados à worktree sem copiar nem
  versionar.
- Visual, por capturas de tela, em cada um dos três modos e **fora do jogo**: `client_rmldemo`,
  todas as abas do `client_rmlshowcase`, `client_rmloptions`, e o modo sem login de
  `game_rmloutfit` (preview) e `game_rmlminimap` (minimapa carregado de `.otmm`). Critério: o
  mesmo resultado nos três modos, com as diferenças registradas. É isto que fecha cada etapa.
- Dentro do jogo (`changeOutfit` no protocolo 15.30, `UIMinimap` hospedado com o mapa real):
  verificado só se houver um servidor local e uma conta de teste fornecidos pelo usuário. Sem
  isso, fica declarado como não verificado e entregue como lista de conferência.
- Sem widget RmlUi aberto: o log `[mem]` e o desenho do client não mudam em relação a antes.
- Linux e macOS: a fiação de CMake é feita, mas não há como verificar aqui. Fica declarado
  como não verificado.

## Ordem de entrega

1. Port do vcpkg e client linkando com o RmlUi nas duas configurações do MSBuild e no CMake.
2. OpenGL de desktop: camada independente, executor GL, `client_rmldemo`. Depois o restante dos
   exemplos e o helper `Rml`.
3. ANGLE: o mesmo conjunto rodando na configuração `DirectX|x64`.
4. Vulkan, etapa 1: alvo por widget, geometria, texturas, scissor, transformações, máscara de
   recorte e composição no batch.
5. Vulkan, etapa 2: camadas, filtros, gradientes, sombras e máscaras; tema `efeitos` ligado.
6. Documentação.

Cada etapa termina com o client compilando e algo visível para conferir.

## Decisões

Do usuário:

- RmlUi completo, com os 7 commits.
- O Vulkan faz parte do escopo.
- Abordagem A para o Vulkan.

Minhas, para você conferir:

- RmlUi vem de um port em `vcpkg-overlays/`, na versão 6.3, em vez de `FetchContent` ou de
  código do RmlUi copiado para dentro do repositório.
- ANGLE usa o caminho GLES3 do mesmo backend GL3, sem um backend separado.
- Os módulos de exemplo carregam sozinhos, como no fork, o que inclui o botão "RmlUi" no menu
  superior e os cinco atalhos. Isso aparece para os jogadores no client distribuído.
- O patch do `Tibia.otfi` (commit `bf3785d`) é portado, porque o `game_things/things.lua` daqui
  ainda tem o caminho `.dat/.spr`. A correção de `g_settings.setNumber` em `client_options`
  (commit `fa41ffc`) não se aplica: o código corrigido não existe aqui.
- `docs/RMLUI.md` em inglês, seguindo o README e os comentários do repositório.
- Inicialização preguiçosa do RmlUi e dos executores.
- Sem troca de executor no meio da sessão: o backend é o que a inicialização do client decidiu.
- A verificação que fecha cada etapa é a de fora do jogo. A de dentro do jogo depende de você
  ter um servidor local e uma conta de teste.

Deixado para quem implementar:

- Como o port resolve o LuaJIT dentro do CMake do RmlUi e quais patches do port oficial
  precisam ser refeitos para a 6.3.
- A forma da interface de executor e a organização dos arquivos do executor Vulkan.
- Estrutura de render passes, cache de pipelines, alocação de memória (o `vcpkg.json` já traz
  `vulkan-memory-allocator`, hoje sem uso) e a forma de passar uniformes aos shaders.
- Como o feeder identifica a textura alvo do RmlUi.
- De onde vem o `glslang.exe` para compilar os shaders.

## Riscos

- **Executor Vulkan.** É a maior parte do trabalho e a de maior incerteza. A etapa 1 existe
  para ter resultado visível antes dos efeitos.
- **ANGLE.** Caminho do backend nunca exercitado pelo fork. Pode exigir ajustes de formato e de
  MSAA específicos de ES 3.
- **Port do vcpkg.** RmlUi 6.3 estático com `/MT`, plugin Lua contra o `lua51.lib` do LuaJIT.
- **Memória de GPU.** Cada widget RmlUi aberto mantém sua pilha de camadas. É o mesmo custo do
  fork em OpenGL, mas pesa mais num modo Vulkan pensado para economizar memória.
- **Verificação no jogo.** A parte de `game_rmloutfit` e `game_rmlminimap` que depende de login
  pode ficar sem verificação se não houver servidor e conta de teste.
