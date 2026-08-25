# Phase 6 renderer handoff

**Checkpoint:** `994371b` on `main` — the phase's last commit, all four CI jobs green on it, on `origin`, the
fork `aacruzgon/CrystalOTC`, together with the documentation commits that follow it.

**Date:** 2026-08-21

**Scope:** Phase 6 — materials and the shader toolchain

## Current state

The Metal backend draws the client's shaders, not just its geometry. All 27 registered module
programs — 13 map shaders, 6 outfit, 1 mount, 1 item and the 6 the exaltation forge creates and
destroys mid-session — resolve to translated Metal Shading Language and render.

The number that says it: `shader-matrix`, which is sixteen module fragment programs over one
identical textured cell, went from **154,018 differing pixels (23.4%)** against OpenGL to **17 of
656,880 (0.0026%)**. It was excluded from the cross-backend gate as not comparable; it is gated at
the default tolerance now.

At this checkpoint:

- **All eleven offline scenes compare across the two backends**, where two were excluded and two
  more carried a widened tolerance. Eight match at **exactly 0 differing pixels**.
- `outfit-masks` and `temporary-framebuffers` fell from 579 and 521 px to **0**. That is the
  `Outfit - Outline` probe — the only shader in the registry declaring `useFramebuffer`, and
  therefore the only automated coverage of a shader applied at an offscreen blit — rendering on
  Metal for the first time.
- The legacy-versus-frame sweep is unmoved: ten scenes at 0 px and `graph-lines` at exactly the
  7,660 px Phase 3 recorded, so the OpenGL path is provably untouched.
- `ctest` 67/67 on both macOS configurations, up from 63.
- Metal holds **392–397 fps median** on an M3 Pro (`startup-ui` 392/396, `shader-matrix` 392/396,
  `atlas-resources` 394/397), against Phase 5's 389–404 with no module shaders compiled at all —
  and `shader-matrix` is the scene that now actually runs sixteen module fragment programs.
  Whatever the translated materials cost, this instrument cannot see it.
- The four manifest entries that said "remove this when Phase 6 lands" are gone. Three were deleted
  outright; the fourth was replaced by a differently justified one — see *Bugs found*.
- **All four CI jobs green** on `994371b` / `a2180b3`: `Tests - Lua`, `Build - macOS (Cocoa)`,
  `Build - Windows` (68/68 under MSVC — the figure the design document predicted, now observed
  rather than counted) and `Renderer baseline - Linux llvmpipe`. The macOS runner asserts
  `render path: frame (backend 'metal')` and `CPU atlases: map=8192x8192 foreground=2048x2048`,
  so Metal and the CPU atlases come up on a host with no window server.
- **Both llvmpipe gates pass.** The reference gate has `shader-matrix` at **0 px** after the
  reseed, six others at 0 and `particles-blends` at its documented 626; the legacy-versus-frame
  sweep has ten at 0 and `graph-lines` at exactly the 8,734 px Phase 3 recorded.
- The three comparable **online** scenes agree within their own noise floors, with an exactly-0 pair
  on `map-screenshot`. And `shader-matrix-map` was compared for the first time in the migration,
  which is where this phase's largest finding came from — see *Bugs found* and *Deferred follow-ups*.

## Phase 6 checklist

Against the implementation plan's Phase 6 tasks:

- [x] **Build-time toolchain** — `.frag` → glslang → SPIR-V → SPIRV-Cross → MSL, over every shipped
      fragment source, failing on anything untranslatable. Delivered differently in two respects
      that both matter; see *Decisions that were not free*.
- [x] **Inventory port** — 27 registered programs over 22 `.frag` files, validated against their GL
      rendering in the matrix scenes. Multi-texture (`u_Tex1..3`, Fog and Snow) travels in the
      packet now rather than being read off the bound program.
- [x] **Application semantics** — the map-shader composition material, per-creature/item/mount
      shaders, and the `useFramebuffer` transient route. The first was already running from Phase 4
      and had nothing to run *with*; the other two are new.
- [x] **GL side of the ABI** — `ShaderManager::ITEM_ID_UNIFORM` moved off slot 10, and `GLBackend`
      uploads the whole block rather than only its map group.
- [x] **`createFragmentShaderFromCode` policy** — registers GL-only; on Metal it resolves to no
      translated source, falls back to the default built-in and says so once.
- [~] **Diagnostics and pipeline caching** — diagnostics yes; the *on-disk* pipeline cache was not
      built, and the plan already conditioned it on "if startup cost warrants it". Nothing measured
      says it does: a material's library is compiled on first use, so a session that binds no module
      shader compiles none, and a scene that binds sixteen of them holds the same frame rate as one
      that binds none.

Against the exit gate — *"supported effects and outfits consistent across GL and Metal; toolchain
runs in CI"*:

| Scene | Metal vs OpenGL | |
|---|---:|---|
| `startup-ui` | **0 px** | |
| `ui-clipping-opacity` | **0 px** | |
| `text-matrix` | **0 px** | |
| `composition-all` | **0 px** | all six blend modes |
| `graph-lines` | **0 px** | |
| `atlas-resources` | **0 px** | |
| `outfit-masks` | **0 px** | was 579 — the Outline probe |
| `temporary-framebuffers` | **0 px** | was 521 — the same probe |
| `shader-matrix` | 17 px | was 154,018; sixteen module fragment programs |
| `particles-blends` | 28 px | its own documented bimodality |
| `shader-matrix-outfits` | 2,160 px | two ill-conditioned cells, see below |

All of 656,880 pixels, both sides forced onto `--render-path=frame` so the two consume an identical
`RenderFrame` and a difference is attributable below the renderer boundary.

**The gate is met for the offline matrix; it was qualified for map shaders at this checkpoint and is
met unqualified since 2026-08-25.** `shader-matrix-map` — the fourteen map shaders on their real
bind site, and a scene no earlier phase could compare — splits exactly in half. Eight captures sit
inside the scene's own noise floor; six differ, and all six are shaders that read `v_TexCoord` as a
*position* rather than only as a sampling coordinate. That is a
render-target orientation difference between the backends, not a translation defect. **Fixed
2026-08-25 (`0ec21a80`), after this checkpoint:** all fourteen captures now sit at or below the
scene's unshaded control frame. Measurements, the mechanism and the fix are in `known-deviations.md`,
"Map shaders on Metal: `v_TexCoord` is vertically mirrored".

The toolchain runs in CI on the Linux baseline job. That is where it belongs for two reasons that
happen to agree: `modules/**` was already a path filter there and nowhere else, and glslang plus
spirv-cross are one apt line there against a brew install on the runner whose whole purpose is the
Metal build. What it verifies is consumed only on macOS, but whether the translation still
*succeeds* is a property of the sources rather than of the consumer. The macOS job gained the two
shader directories as filters of its own, because a `.frag` change now alters what it renders.

## Decisions that were not free

**The translation is committed, not generated into the build tree.** The plan describes a CMake
step producing a `.metallib`. What shipped generates MSL *source* into a committed header, and the
build verifies rather than produces it. Three reasons, in order of weight:

- **A `.metallib` needs a Metal toolchain nobody has by default.** `xcrun metal` on this machine
  answers `cannot execute tool 'metal' due to missing Metal Toolchain`. Runtime compilation from a
  string needs only Metal.framework, which the built-in materials have used since Phase 4.
- **The repository already made this decision once, and wrote down why.**
  `data/shaders/vulkan/compile_shaders.bat` compiles the Vulkan SPIR-V manually, offline, and
  commits the result, stating that the client has no GLSL compiler in it and should not gain one.
  Making a fresh clone require glslang and SPIRV-Cross on `PATH` would contradict that for no gain.
- **A 23-shader closed set is small enough that the translation diff is worth reading.** It is
  reviewable output, not an intermediate.

Enforcement is not weakened by any of it: `check_metal_shaders` fails the build wherever both tools
are present, and the Linux job installs them and runs the same check. A `.frag` that cannot be
translated fails, anywhere. A `.frag` added without being accounted for fails, anywhere. A `.frag`
edited without regenerating fails **where the toolchain matches the one that generated the header** —
which is the developer's own machine, the one that has to regenerate it. See the trap below for why
that qualification exists and is not a hole worth closing with a version pin.

**Both stages are generated per material, not just the fragment.** SPIRV-Cross derives the
fragment's `[[stage_in]]` struct from the same varying interface it derived the vertex output from,
so a generated pair agrees by construction — where a generated fragment paired with the
hand-written built-in vertex would agree only by inspection, and only until someone changed one of
them. The generated vertex is written to match `crystalotc_vertex` exactly, including pinning
clip-space z to the near plane for Metal's `0 <= z <= w` volume.

**The GLSL fed to glslang is not the file on disk, and could not be.** The shipped sources are GLSL
1.10/1.20-era — `varying`, `texture2D`, `gl_FragColor`, loose `uniform` declarations — and SPIR-V
has neither a default uniform block nor `gl_FragColor`. Each file is wrapped in a generated
preamble declaring the frozen `MaterialParams` block, the per-draw colour/opacity block and the
samplers at **pinned** bindings, with the body's own declarations of those uniforms stripped.
`--msl-decoration-binding` then turns those binding numbers straight into MSL resource indices, so
a generated function binds exactly where the hand-written built-ins do and the backend needs no
per-material reflection.

**Registration is separated from compilation, which is what makes any of this reachable.**
`ShaderManager` used to skip registration entirely without a GL context. That silenced a wall of
failed-compile lines at startup and, as a side effect nobody wanted, left every module program
without an id — so `PoolCompiler` mapped every draw that wanted one to the default material and no
backend was ever asked for it. Registering always and compiling only where there is a context to
compile for is the whole unlock. It also closes a determinism hazard that predates this phase:
`putShader` used to run only after a successful link, so one driver rejecting one `.frag`
renumbered every shader registered after it, and two machines could disagree about which material a
handle named.

**A material resolves by `.frag` basename, not by registered name.** Party, Radial Blur, Heat and
Noise are each registered under two or three names against one file, and the file is the unit of
translation. `MaterialRegistry` publishes the mapping in a header with no graphics-API dependency,
because the Metal translation units import no OpenGL and `PainterShaderProgram`'s header pulls in
GLEW through `shaderprogram.h`.

**One `MTLLibrary` per material, compiled lazily.** Merging the generated sources would mean
renaming structs to avoid redefinition, since each declares the same blocks. Keeping them separate
also means a failure in one shader stays that shader's problem, and a session that binds none
compiles nothing.

**`GLBackend` still does not upload `time` or `resolution`.** Painter writes both on every single
draw from inside `drawArrays` — `u_Time` through `updateTime()`, which subtracts the program's own
start time and is therefore per-program, and `u_Resolution` from the painter's current resolution.
Uploading the frame-global values over the top would change what the GL path renders, which is the
one thing that backend exists not to do. The frame's copies of those two fields are for backends
with no Painter underneath them.

## Traps worth not rediscovering

**An inert shader program is not a null shader program, and the difference bites at a new place
each phase.** Phase 4 made `ShaderProgram` survive construction without a GL context. Phase 6 made
`setup*Shader` actually run on such a program, and `bindUniformLocation` reaches
`glGetUniformLocation`, whose GLEW entry point is a null pointer there. The Cocoa client segfaulted
on the first run after registration was turned on. Every GL entry point on that class needs the
`hasGLProgram()` guard, not just the ones a previous phase happened to reach.

**`glUniform*` with location -1 is a specified no-op, and that is load-bearing here.**
`m_uniformLocations` is filled with -1 at construction, which is why `GLBackend` can now upload the
whole parameter block including fields no shipped shader binds. Had it been zero-filled, a stray
upload would have written the *first active uniform* of whatever program was bound.

**A capture that "matches" can be measuring the wrong thing.** `outfit-masks` carried a 0.002
cross-backend tolerance for one Outline probe. It now measures 0 px — but that is not the tolerance
having been generous, it is the shader having been absent before and present now. When a tolerance
disappears, check whether the thing it covered started working or stopped being drawn.

**`gl_FragCoord` is bottom-left in GL and top-left in Metal, and only one shader in the tree cares.**
`rain.frag` is it. The generated source declares `origin_upper_left` so SPIRV-Cross emits a direct
`[[position]]`, and a helper converts back to what the shipped GLSL expects. Getting this wrong is
invisible in fifteen of sixteen `shader-matrix` cells.

**A byte-exact check of generated output silently pins the tool versions.** The first CI run said
the committed header was stale when nothing was wrong with it: Ubuntu's glslang is not Homebrew's,
SPIRV-Cross names its temporaries after SPIR-V ids that glslang assigns, and the two therefore
produce byte-different equivalent MSL. The header records the toolchain that made it and `--check`
compares byte-for-byte only when the local tools match; otherwise it verifies that everything still
translates and that the material table is unchanged. Worth knowing before writing any other
generated-and-verified artifact: "regenerate and diff" is only a valid check when the generator is
pinned, and neither apt nor Homebrew pins one.

**Two shader compilers will never agree on an ill-conditioned shader, and no translator can make
them.** See *Bugs found* for `heat.frag` and `noise.frag`. The useful lesson is the diagnostic
order: dump the packet state first and confirm the *inputs* are identical before spending any time
on the translation. They were, which turned a suspected translation defect into a documented
property of the source in one step.

**The Windows job cancels itself, and this is the third phase to record it.** Batch the commits and
push once.

## Bugs found, and how

**`rain.frag` read an uninitialised variable, and had since it was written.** It declares
`vec2 s = floor(uv), f = fract(uv), p;` and then reads `p` in the very expression that first
assigns it. The shader's output was undefined by construction and every compiler was free to
produce a different rain pattern — which is exactly what happened: 1,184 differing pixels on
`shader-matrix`, confined entirely to the Rain cell.

Found by attributing the diff per grid cell rather than reading the total, then by an experiment
that ruled out the obvious fix: zero-filling `p` on the Metal side *alone* made it worse (2,049 px),
which is what established that OpenGL was not zero-filling either. Initialising `p` in the source
also restores what the expression evidently meant — `s + p + scale` becomes `s + scale`, the
canonical form of this shadertoy-derived hash. With it defined, the two backends agree at 17 px.

It changes what the shader draws on **every** backend — 2,032 px on XQuartz locally, 1,461 px on
llvmpipe in CI, the two GL stacks rasterising rain differently — so the checked-in llvmpipe
reference for `shader-matrix` was reseeded as a deliberate refresh, and verified to differ from its
predecessor only inside the Rain cell.

**`heat.frag` and `noise.frag` are ill-conditioned by construction, and that is not a defect to
fix.** They are the two cells of `shader-matrix-outfits` that still differ, at 2,160 px combined.
Both accumulate five cosine terms scaled by 30 into a value reaching about **125 radians**, take
`cos()` of *that*, subtract two such results, and use the difference as a **texture-coordinate
offset of roughly 1.6e-3** — which on a sprite sheet is more than one texel. A few ULP in the
accumulation therefore decides which texel is sampled, so a minority of pixels land on a different
sprite pixel entirely while the rest agree exactly.

Established rather than assumed, in two steps. A dump of every module packet is byte-identical
across the two backends apart from the texture's unique id — same texcoords, same viewport, same
texture-matrix id — so the inputs are not in question. And forcing safe fp math on the Metal side
changes the figure by exactly nothing, so it is not FMA contraction either. The same two programs on
an image widget in `shader-matrix` differ by only 1 and 15 pixels, because there the offset stays
inside one texel.

**The map composition packet carried no multi-textures.** `PoolCompiler` fills `DrawPacket::extraTex`
from the bound program, which covers every packet it builds — but the composition packet is the
frame assembler's, built from the pool's declared material, and the compiler never sees it. So Fog
and Snow, the only two shaders that use `u_Tex1` and both of them map shaders, sampled an unbound
texture argument at the one site they are actually used. Found by capturing `shader-matrix-map`;
fixed in `b951233` by carrying the handles with the material from `MapView`, the only place holding
both. Fog went from 273,805 differing pixels at mean channel delta 17.8 to 195,742 at 3.95 — the
clouds appear.

**And behind it, the finding this phase could not fix — closed 2026-08-25.** The residual on those
six map shaders is that GL stores a render target bottom-up and samples it through an `upsideDown`
texture matrix, while Metal stores targets top-down and samples through a plain one. Both fetch the
correct texel;
`v_TexCoord.y` runs the opposite way. A shader that only samples cannot tell — which is why
`shader-matrix` compares at 17 px on the same programs — and a full-screen post-effect that uses the
coordinate as a position sees a mirrored field. No change to the geometry or the matrix fixes it,
because the two backends need different texcoords to reach the same pixel; only unifying the storage
convention does, and that is a phase of work either way. **Corrected 2026-08-25 (`0ec21a80`): that
last clause was wrong.** The two backends do need different texcoords, but the difference does not
have to be absorbed in the storage convention — the shader translation layer takes it, exactly as it
already takes `gl_FragCoord`'s origin for `rain.frag`. The shader's arithmetic runs in GL coordinate
space via `crystalotc_texCoordGL()` and converts once at the `u_Tex0` fetch via
`crystalotc_sampleTex0()`, both gated per draw on `u_Tex0FlipY`. Metal keeps its top-down targets
and the Phase 4 decision stands.

**Four deferred lambdas captured a pointer into a string that had already been popped.**
`ShaderManager`'s `create*` and `setup*` entry points captured `name.data()` — a raw `const char*`
into a Lua-owned string that `polymorphicPop` releases immediately — and the `setup*` ones captured
`&`, binding locals by reference into a lambda that outlives the call. The map key, and therefore
which id a shader got, depended on that memory surviving until the main thread ran the event. They
take `std::string` now. Not observed failing; found while making registration deterministic, which
is the same property it threatened.

## Owner decisions recorded 2026-08-21

_None this phase._

## Deferred follow-ups

**The `shader-matrix` llvmpipe reference was reseeded, and that closes the one piece of Phase 6 that
could not be finished from a developer machine.** The `rain.frag` fix moved OpenGL output on that
scene, so the existing reference failed the gate — at 1,461 px in CI, where the same fix measured
2,032 px locally on XQuartz. Refreshed from run `32525617431` via the documented
`workflow_dispatch` + `refresh_references: true` route.

It was verified rather than trusted, which is what separates a reseed from hiding a failure: the new
reference differs from its predecessor by 1,461 px **confined entirely to the Rain cell**, 0 px in
each of the other sixteen cells and 0 px outside the grid; the seven other gated references from the
same run are byte-identical to the committed ones apart from `particles-blends` at its documented
626 px, so nothing in the container or Mesa drifted underneath the refresh; and
`forge_result_silhouette`'s image area is still pixel-identical to the `no shader` control.

**An on-disk pipeline cache is still unbuilt, and nothing measured yet justifies one.** The frame
rate is identical with sixteen module materials live and with none, so if it is ever built the case
should come from a startup-time measurement rather than from this one.

**`PainterShaderProgram` still compiles GLSL, and the design says it should not.** The fate table
has it becoming material registration with compilation moving into `GLBackend`. It has not, and it
cannot until the legacy path goes — the same dependency `Painter` and `FrameBuffer` have. Phase 6
narrowed it rather than closing it: the class now carries a source key and a material identity
alongside the GLSL.

~~**Map shaders are not consistent across the backends, and that is this phase's one unmet claim.**~~
**Closed 2026-08-25.** Absorbed in the shader translation layer rather than by unifying the storage
convention — the shader's arithmetic runs in GL coordinate space and converts once at the `u_Tex0`
fetch, gated per draw on whether that texture resolved to a render target. All fourteen
`shader-matrix-map` captures now sit at or below the scene's unshaded control frame (Fog 197,123 ->
111; Pulse 267,328 -> 899), the offline `shader-matrix` holds at exactly 17 px, and the offline
cross-backend sweep is unchanged at its documented values. No OpenGL or shared framework file was
touched. Mechanism, measurements and the reason the per-draw gate cannot be a compile-time constant
are in `known-deviations.md`. The paragraph below is the original statement of the problem:

**Map shaders were not consistent across the backends, and that was this phase's one unmet claim.**
Six of the thirteen — Fog, Snow, Old Tv, Pulse, Heat and Noise — differ substantially at the map
composition site because `v_TexCoord` is vertically mirrored between GL and Metal targets. The
mechanism is fully characterised and the two possible fixes are costed in `known-deviations.md`;
neither is small, and both change a decision the rest of the migration rests on. This is the top
item to schedule, and it should be scheduled as work rather than carried as a tolerance: a mirrored
coordinate field is a visible difference in a shipped effect, not sampling noise.

**The three comparable online scenes were re-measured and agree.** `map-core`, `map-screenshot` and
`lighting-overlap`, three runs per backend, every cross-backend figure at or below that scene's own
noise floor and an exactly-0 pair on `map-screenshot`. Worth repeating after anything that changes
what the MAP pool draws, which is what made this run worth doing.

**`createFragmentShaderFromCode` is a documented gap rather than a supported feature on Metal.** It
registers GL-only and falls back to the default built-in with a one-time log. No shipped module
uses it. Module-author documentation landed later in the same phase: `docs/shader-authoring.md`.

**`test.frag` and `forge.frag` still ship with no registration site.** `test.frag` is excluded from
translation with its reason recorded — it is pre-1.20 fixed-function source that no SPIR-V version
accepts. `forge.frag` translates fine and is translated, but nothing can select it either.

## Reproduction commands

Regenerate the Metal translation after changing any `.frag`:

```sh
tools/generate_metal_shaders.py --write     # regenerate the committed header
tools/generate_metal_shaders.py --check     # what CI and the build run
tools/generate_metal_shaders.py --list      # the translated material keys
```

It needs `glslang` and `spirv-cross` on `PATH` (`brew install glslang spirv-cross`, or
`apt-get install glslang-tools spirv-cross`). The build runs `--check` automatically whenever both
are found, and skips it with a status message when they are not.

Both configurations, which are different compile surfaces:

```sh
cmake --build build/macos-release --parallel 8   # XQuartz, the OpenGL reference vehicle
cmake --build build/macos-cocoa   --parallel 8   # Cocoa/Metal, what CI gates
ctest --test-dir build/macos-release --output-on-failure
ctest --test-dir build/macos-cocoa   --output-on-failure
```

The cross-backend sweep, which is what the exit gate is measured with:

```sh
GL_RUN_PREFIX="env DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority" \
bash tools/compare_render_backends.sh \
  build/macos-release/bin/otclient \
  build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC
```

Attributing a difference to a shader rather than to a scene — the step that turned this phase's two
findings from suspicions into measurements — means comparing per grid cell. `SHADER_GRID` in
`modules/dev_renderer_baseline/dev_renderer_baseline.lua` gives the layout:
`x = 48 + column * 156`, `y = 104 + row * 126`, cells 148x118, six columns.

## Commit ledger

_Regenerated from `git log --format='%h %s' --reverse 45801df..994371b` rather than appended to by
hand. `45801df` is the Phase 5 audit checkpoint this phase started from. The range runs to the last
commit of the phase rather than stopping short of the documentation, because this phase's
documentation was not a tail: the handoff was written mid-phase, and running the online scenes
afterwards found a defect. 40 files changed, 4266 insertions(+), 197 deletions(-)._

```text
19e29e3 fix(shaders): give rain.frag's noise hash a defined input
ec953ac feat(renderer): translate the module fragment shaders to Metal Shading Language
33961ca feat(renderer): give a module shader a material identity without an OpenGL context
ef9de16 feat(renderer): draw the module materials on Metal
c09ff96 test(renderer): cover the module material boundary and restore the gate defaults
b62f747 docs(renderer): hand off Phase 6
b951233 fix(renderer): give the map composition packet its multi-textures
d462ae3 docs(shaders): document the fragment ABI for module authors
c2a4dc6 chore(renderer): make the shader generator executable
ab9fbe3 docs(renderer): correct what Phase 6 falsified across the migration set
72397b4 docs(renderer): record the online-scene evidence and the divergence it exposed
a2180b3 fix(renderer): stop the shader check failing on a different glslang
994371b ci(renderer): reseed the shader-matrix llvmpipe reference after the rain fix
```

Note the shape, and that it is the opposite of Phase 5's: the phase's first commit is a one-word fix
to a shader nobody had looked at in years, and it is load-bearing for the exit gate; the last is a
fix found by running an online scene that no phase before this one could even compare. Neither could
have come from the translation toolchain - both shaders translate cleanly - and both came from
running the two backends against each other and attributing the difference per cell.

## What Phase 7 inherits

Phase 7 is hardening and distribution: bundle completeness, signing and notarization, the
reliability matrix, GPU diagnostics, and promoting the macOS job to a required check.

- **The cross-backend gate is now unconditional**, and that is the thing to protect. Eleven scenes,
  no exclusions, eight at 0 px. Any future scene that cannot be compared needs a stated reason in
  the manifest, which `renderer_scenes.py validate` already enforces.
- **The macOS image matrix is ready to be gated and is not gated.** Phase 5 established that a
  hosted runner captures all eleven offline scenes with no window server, and that nine of them are
  byte-identical across two runners. What blocked gating was `shader-matrix` differing by 23.4% from
  the llvmpipe reference; that number is now the 0.31% the `rain.frag` reseed removes. After the
  reseed, gating the macOS captures against the checked-in llvmpipe references is a step Phase 7 can
  take rather than a question it has to answer — with `composition-all` and `particles-blends`
  excluded for the reasons `known-deviations.md` already records.
- **A shader is now a build-time dependency of the Metal binary.** `modules/game_shaders/**` is in
  the macOS job's path filter for that reason. Anyone adding a `.frag` has to regenerate; the build
  and the Linux job both say so, loudly.
- **The reliability matrix should include a shader that fails to compile.** Every path is written -
  a missing MSL entry, a library that fails to build, an entry point that is absent - and none has
  ever been exercised, because all 23 materials translate and compile.
- ~~**The map-shader orientation divergence is the one thing this phase leaves visibly wrong**~~
  **Closed 2026-08-25 (`0ec21a80`), after this handoff was written.** Absorbed in the shader
  translation layer rather than by unifying the storage convention; no OpenGL or shared framework
  file was touched, so no checked-in reference moved. Phase 7 inherits nothing here. What it does
  inherit is the check recorded as owed in `known-deviations.md`: `map-core` and `lighting-overlap`
  could not be compared across backends that session, because the available OpenGL binary predates
  roughly thirty commits of UI work and the two disagree on window height (1020x650 against
  1020x644).
