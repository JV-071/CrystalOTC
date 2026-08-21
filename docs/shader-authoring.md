# Writing a shader for CrystalOTC

**Audience:** module authors adding or editing a `.frag` under `modules/`.
**Companion:** `docs/metal-parity-survey.md` section 5 for how the shader system is built, and
`docs/metal-implementation-plan.md` Phase 6 for why the Metal half exists.

Since Phase 6 the client has two renderers, and a shader has to work on both. This page is what
you need to know to add one without breaking the build.

## The short version

1. Put your `.frag` in `modules/game_shaders/shaders/fragment/`.
2. Register it from Lua with `g_shaders.createFragmentShader(name, path, useFramebuffer)`.
3. Add it to `tools/metal_materials.json`.
4. Run `tools/generate_metal_shaders.py --write` and commit the regenerated header.

Skip step 3 or 4 and the build fails with a message telling you which one you skipped. That is
deliberate: the alternative is a shader that renders on OpenGL and silently does nothing on macOS.

## What a fragment shader is, here

A module `.frag` is a **complete fragment shader**, not a fragment of one. It declares its own
`main()` and writes `gl_FragColor`. The client prepends a fixed *vertex* stage and nothing else —
in particular it does **not** wrap your `main()`, and it does **not** apply `u_Opacity` for you.

```glsl
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
uniform vec4 u_Color;
uniform float u_Opacity;

void main()
{
    gl_FragColor = texture2D(u_Tex0, v_TexCoord) * u_Color;
    gl_FragColor.a *= u_Opacity;   // if you want it, apply it yourself
}
```

Most shipped shaders ignore `u_Color` and `u_Opacity` entirely. That is a choice each shader makes,
not a contract — `grayscale.frag` and `hover_desaturate.frag` are the two that honour both.

## The uniforms you may declare

Declare only what you use. The names are fixed; the values come from the renderer.

| Uniform | Type | What it holds |
|---|---|---|
| `u_Tex0` | `sampler2D` | the texture being drawn |
| `u_Tex1`, `u_Tex2`, `u_Tex3` | `sampler2D` | extra textures, added with `g_shaders.addMultiTexture(name, path)` |
| `u_Color` | `vec4` | the draw's tint |
| `u_Opacity` | `float` | the draw's opacity |
| `u_Time` | `float` | seconds; **pinnable** — see below |
| `u_Resolution` | `vec2` | the size of the render target being drawn into, not the window |
| `u_WalkOffset` | `vec2` | map-shader camera offset |
| `u_MapZoom` | `float` | map-shader scale factor |
| `u_MapCenterCoord`, `u_MapGlobalCoord` | `vec2` | map-shader camera position |
| `u_ItemId`, `u_OutfitId`, `u_MountId`, `u_ShaderId` | `float` | reserved; nothing in the client binds them today |
| `u_TextOffset`, `u_TextCenter` | `vec2` | reserved, as above |
| `v_TexCoord` | `varying vec2` | texture coordinate from the fixed vertex stage |

The four map uniforms are only written while a map shader is bound at the map composition blit.
Everywhere else they hold whatever they last held, which for an offline scene is zero.

`u_Time` is derived from the wall clock and can be **pinned** with `g_shaders.setFixedTime(seconds)`.
Every renderer baseline capture pins it, because an animated shader is otherwise irreproducible and
nothing could be compared against anything. Do not build a shader that only looks right at a
particular unpinned phase.

## Things that will not survive translation to Metal

The build translates your GLSL through glslang and SPIRV-Cross. Anything SPIR-V cannot express
fails the build rather than shipping half-working, so this list is enforced rather than advisory.

- **Fixed-function state.** `gl_TexCoord`, `gl_Color`, `gl_ModelViewMatrix` and friends were removed
  from GLSL long ago. `test.frag` uses `gl_TexCoord[0]` and is excluded from translation for exactly
  this reason.
- **A uniform named after a builtin.** `uniform sampler2D texture;` collides with the `texture()`
  function in any version SPIR-V can be generated from.
- **Uniforms outside the table above.** The generated preamble declares the known set; anything else
  is an undeclared identifier.
- **Reading a variable before it is assigned.** This is undefined behaviour in GLSL, and two
  compilers will disagree about it. `rain.frag` did this for years — it read `p` inside the
  expression that first assigned it — and the two backends produced visibly different rain until it
  was fixed. The build cannot catch this; the cross-backend comparison can, and did.

## Things that translate but will not compare

Some shaders are legitimate and still cannot be pixel-identical on two GPUs. If yours is one, say so
in `docs/rendering-baselines/scenes.json` rather than widening a gate quietly.

The pattern to recognise: **taking a trigonometric function of a large argument, then using small
differences of the result.** `heat.frag` and `noise.frag` accumulate cosine terms into roughly 125
radians, take `cos()` of that, subtract two such results, and use the difference as a
texture-coordinate offset of about a texel and a half. A few units in the last place decide which
texel gets sampled. Nothing is wrong with either shader; they simply have no compiler-independent
answer, and they carry a measured `renderBackendTolerance` because of it.

## Registering it

From your module's Lua, at load time:

```lua
g_shaders.createFragmentShader("Map - Fog", "/game_shaders/shaders/fragment/fog", false)
g_shaders.addMultiTexture("Map - Fog", "/game_shaders/images/clouds")   -- fills u_Tex1
g_shaders.setupMapShader("Map - Fog")                                   -- map shaders only
```

The third argument is `useFramebuffer`. With it true, whatever the shader is applied to is first
rendered into an offscreen target and the shader runs at the blit, on the composited result rather
than on each draw. `Outfit - Outline` is the only shipped shader that uses it — an outline needs to
see the finished sprite, not one layer of it.

Several registered names may share one `.frag`; Party, Radial Blur, Heat and Noise each do. The
Metal side keys on the **file**, not the name, so sharing costs nothing.

`g_shaders.createFragmentShaderFromCode` exists and is **OpenGL-only by policy**. There is no file
to translate, so on Metal such a shader falls back to drawing the geometry unshaded and logs that it
did, once. If you need your effect on macOS, ship a `.frag`.

## Regenerating the Metal translation

```sh
tools/generate_metal_shaders.py --write     # regenerate after any .frag change
tools/generate_metal_shaders.py --check     # what the build and CI run
tools/generate_metal_shaders.py --list      # the translated material keys
```

You need `glslang` and `spirv-cross`:

```sh
brew install glslang spirv-cross            # macOS
apt-get install glslang-tools spirv-cross   # Debian/Ubuntu
```

The generated header, `src/framework/graphics/render/metal/metalmodulematerials.h`, is **committed**.
The client has no GLSL compiler built into it and is not getting one, so the translation happens on
your machine or in CI, never at the user's runtime. Building the client itself needs neither tool —
when they are absent the build says so and skips the check.

Commit the regenerated header with your shader. Reviewing the MSL diff is worth the minute it takes;
it is the only place you will see what your shader actually became.

**Your glslang does not have to match anyone else's.** SPIRV-Cross names its temporaries after
SPIR-V ids that glslang assigns, so two glslang versions translate the same shader into
byte-different but equivalent MSL. The header records the toolchain that produced it, and `--check`
compares byte-for-byte only when the local tools match that line. When they do not — which is the
normal case in CI, where the distribution's glslang is not the one you have — it still translates
every shader, so an untranslatable one still fails, and it still compares the material table, so an
added or removed shader still fails. What it cannot see in that case is an edit to an existing
`.frag` that was not regenerated. Regenerate anyway; your own build will catch you.

## Checking your work

A shader is not done when it renders. Add it to a matrix scene and compare the two backends:

```sh
GL_RUN_PREFIX="env DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority" \
bash tools/compare_render_backends.sh \
  build/macos-release/bin/otclient \
  build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC shader-matrix
```

If it differs, attribute the difference **per grid cell** before drawing any conclusion. The scene
lays cells out from `SHADER_GRID` in `modules/dev_renderer_baseline/dev_renderer_baseline.lua` —
`x = 48 + column * 156`, `y = 104 + row * 126`, cells 148x118, six columns — and a total tells you
nothing about which shader is responsible. Both shader defects found in Phase 6 were located this
way in a single step.
