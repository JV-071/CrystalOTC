#!/usr/bin/env python3
"""Translate the client's module fragment shaders into Metal Shading Language.

Every painter shader in this client - built-in or module - is a fragment variant against one
fixed vertex stage, so a material is a pair of MSL functions rather than an arbitrary pipeline.
This script is the closed-set enforcement the migration plan calls for: it drives each shipped
`.frag` through glslang into SPIR-V and SPIRV-Cross into MSL, and fails loudly on anything it
cannot translate.

The GLSL it feeds glslang is NOT the file on disk. The shipped sources are GLSL 1.10/1.20-era
(`varying`, `texture2D`, `gl_FragColor`, loose `uniform` declarations), which SPIR-V does not
accept: SPIR-V has no default uniform block and no `gl_FragColor`. So each file is wrapped in a
generated preamble that declares the frozen `MaterialParams` block, the per-draw colour/opacity
block and the samplers at PINNED bindings, and the body's own declarations of those uniforms are
stripped. `--msl-decoration-binding` then makes SPIRV-Cross use those binding numbers directly as
MSL resource indices, so the generated functions bind exactly where the hand-written built-ins do
and the backend needs no per-material reflection.

Output is a single generated C++ header holding one MSL source string per translated file. It is
committed to the repository and re-verified by the build, rather than generated into the build
tree only: the tools are a developer/CI dependency, not a dependency of compiling the client, and
a 22-shader closed set is small enough that reviewing the translation diff is a feature.

Usage:
    tools/generate_metal_shaders.py --check          # verify the committed header is current
    tools/generate_metal_shaders.py --write          # regenerate it
    tools/generate_metal_shaders.py --list           # print the translated material keys
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "tools" / "metal_materials.json"
GENERATED_HEADER = (
    REPO_ROOT / "src" / "framework" / "graphics" / "render" / "metal" / "metalmodulematerials.h"
)

# Pinned resource bindings. These are the contract between this generator and
# `MetalABI` in src/framework/graphics/render/metal/metalinternal.h; the numbers below must
# match the *_BUFFER / *_SLOT constants there, because --msl-decoration-binding turns each one
# straight into an MSL [[buffer(n)]] / [[texture(n)]] index.
#
# Buffers and textures live in different MSL index spaces but share GLSL's binding space inside
# one descriptor set, so the samplers sit in set 1 to keep glslang from rejecting the overlap.
BINDING_DRAW_PARAMS = 0      # vec4 u_Color, float u_Opacity      -> [[buffer(0)]]
BINDING_MATERIAL_PARAMS = 1  # the frozen MaterialParams block    -> [[buffer(1)]]
BINDING_VERTEX_PARAMS = 2    # the three 3x3 matrices             -> [[buffer(2)]]
TEXTURE_SET = 1              # u_Tex0..3 -> [[texture(0..3)]] / [[sampler(0..3)]]

MAX_TEXTURE_UNITS = 4

# The frozen MaterialParams block, spelled as the GLSL a naturally written std140 block would
# use. Offsets are static_asserted on the C++ side (render/materialparams.h); this declaration
# has to agree with them field for field, in order.
MATERIAL_PARAMS_GLSL = """\
layout(std140, set = 0, binding = {binding}) uniform CrystalOTCMaterialParams {{
    float u_Time;
    float u_MapZoom;
    float u_ItemId;
    float u_OutfitId;
    float u_MountId;
    float u_ShaderId;
    vec2 u_Resolution;
    vec2 u_WalkOffset;
    vec2 u_MapCenterCoord;
    vec2 u_MapGlobalCoord;
    vec2 u_TextOffset;
    vec2 u_TextCenter;
}};
"""

DRAW_PARAMS_GLSL = """\
layout(std140, set = 0, binding = {binding}) uniform CrystalOTCDrawParams {{
    vec4 u_Color;
    float u_Opacity;
}};
"""

# The fixed vertex stage, written to match `crystalotc_vertex` in metalshaders.h exactly rather
# than to match the GLSL scaffold. The one deliberate difference from the GLSL is the z
# component: GLSL writes the matrix product's third row, which is 1.0 for every 2D affine
# transform this client builds and therefore sits on GL's far plane, while Metal's clip volume is
# 0 <= z <= w. Pinning z to the near plane is inside the volume whatever a transform does, and it
# keeps a module pipeline's vertex stage identical to a built-in one's.
VERTEX_GLSL = """\
layout(location = 0) in vec2 a_Vertex;
layout(location = 1) in vec2 a_TexCoord;
layout(location = 0) out vec2 v_TexCoord;

layout(std140, set = 0, binding = {binding}) uniform CrystalOTCVertexParams {{
    mat3 u_ProjectionMatrix;
    mat3 u_TransformMatrix;
    mat3 u_TextureMatrix;
}};

void main()
{{
    gl_Position = vec4((u_ProjectionMatrix * u_TransformMatrix * vec3(a_Vertex, 1.0)).xy, 0.0, 1.0);
    v_TexCoord = (u_TextureMatrix * vec3(a_TexCoord, 1.0)).xy;
}}
"""

# `gl_FragCoord` is bottom-left origin in GL and top-left in Metal. Declaring origin_upper_left
# gives SPIRV-Cross a direct [[position]] to emit, and this helper converts back to what the
# shipped GLSL expects, so a shader reading fragment coordinates lands on the same pixels under
# both backends. Only rain.frag uses it.
FRAG_COORD_HELPER = """\
layout(origin_upper_left) in vec4 gl_FragCoord;

vec4 crystalotc_fragCoord()
{
    return vec4(gl_FragCoord.x, u_Resolution.y - gl_FragCoord.y, gl_FragCoord.z, gl_FragCoord.w);
}
"""

# Lines the wrapper supplies itself. A shipped `.frag` declaring any of these would otherwise
# redeclare a block member or an interface variable.
STRIP_LINE = re.compile(
    r"^\s*(uniform\s+(float|vec2|vec3|vec4|mat2|mat3|mat4|int|bool|sampler2D)\s+\w+\s*;"
    r"|varying\s+(highp\s+|mediump\s+|lowp\s+)?\w+\s+\w+\s*;)\s*(//.*)?$"
)


def _fail(message: str) -> "NoReturn":  # type: ignore[valid-type]
    print(f"generate_metal_shaders: {message}", file=sys.stderr)
    raise SystemExit(1)


# The directories the client registers shaders from. Every `.frag` under them has to be
# accounted for - translated or explicitly excluded with a reason - so that adding one and
# forgetting it is a failure rather than a shader that silently renders unshaded on Metal.
SHADER_DIRS = (
    "modules/game_shaders/shaders/fragment",
    "modules/game_exaltationforge/menu/shaders",
)


def load_manifest() -> dict:
    with MANIFEST.open(encoding="utf-8") as handle:
        return json.load(handle)


def check_coverage(manifest: dict) -> None:
    """Fail if a shipped .frag is neither translated nor deliberately excluded."""
    covered = {m["source"] for m in manifest["materials"]}
    excluded = {e["source"] for e in manifest.get("excluded", [])}

    for entry in manifest.get("excluded", []):
        if not entry.get("reason", "").strip():
            _fail(f"excluded shader '{entry['source']}' carries no reason")

    on_disk = set()
    for directory in SHADER_DIRS:
        root = REPO_ROOT / directory
        if not root.is_dir():
            _fail(f"shader directory is missing: {directory}")
        for path in sorted(root.glob("*.frag")):
            on_disk.add(str(path.relative_to(REPO_ROOT)))

    if missing := sorted(on_disk - covered - excluded):
        _fail(
            "these fragment shaders are neither translated nor excluded:\n  "
            + "\n  ".join(missing)
            + "\nAdd them to tools/metal_materials.json, or exclude them with a reason."
        )

    if stale := sorted((covered | excluded) - on_disk):
        _fail("the manifest names fragment shaders that no longer exist:\n  " + "\n  ".join(stale))

    if overlap := sorted(covered & excluded):
        _fail("these shaders are both translated and excluded:\n  " + "\n  ".join(overlap))

    keys = [m["key"] for m in manifest["materials"]]
    if len(keys) != len(set(keys)):
        _fail("two materials share a key; a key must be unique because it names the MSL functions")


def strip_declarations(body: str) -> str:
    """Drop the loose uniform/varying declarations the generated preamble replaces."""
    kept = []
    for line in body.splitlines():
        if STRIP_LINE.match(line):
            kept.append("")  # keep the line count so #line-free diagnostics still line up
            continue
        kept.append(line)
    return "\n".join(kept)


def build_fragment_glsl(body: str) -> str:
    stripped = strip_declarations(body)

    # Legacy spellings that SPIR-V has no equivalent for. `texture2D` is a plain rename and is
    # done with a macro; the `gl_`-prefixed names cannot be, because GLSL reserves that prefix
    # for macro names, so they are substituted textually.
    stripped = re.sub(r"\bgl_FragColor\b", "crystalotc_FragColor", stripped)
    uses_frag_coord = re.search(r"\bgl_FragCoord\b", stripped) is not None
    stripped = re.sub(r"\bgl_FragCoord\b", "crystalotc_fragCoord()", stripped)

    used_textures = [
        unit for unit in range(MAX_TEXTURE_UNITS) if re.search(rf"\bu_Tex{unit}\b", stripped)
    ]

    parts = ["#version 450 core", "", "#define texture2D texture", ""]
    parts.append(MATERIAL_PARAMS_GLSL.format(binding=BINDING_MATERIAL_PARAMS))
    parts.append(DRAW_PARAMS_GLSL.format(binding=BINDING_DRAW_PARAMS))
    for unit in used_textures:
        parts.append(
            f"layout(set = {TEXTURE_SET}, binding = {unit}) uniform sampler2D u_Tex{unit};"
        )
    parts.append("")
    parts.append("layout(location = 0) in vec2 v_TexCoord;")
    parts.append("layout(location = 0) out vec4 crystalotc_FragColor;")
    parts.append("")
    if uses_frag_coord:
        parts.append(FRAG_COORD_HELPER)
    parts.append(stripped)
    return "\n".join(parts) + "\n"


def build_vertex_glsl() -> str:
    return "#version 450 core\n\n" + VERTEX_GLSL.format(binding=BINDING_VERTEX_PARAMS)


def run(cmd: list[str], *, what: str) -> None:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stdout + result.stderr).strip()
        _fail(f"{what} failed:\n{detail}")


def translate(source: str, stage: str, entry_name: str, workdir: Path, glslang: str,
              spirv_cross: str) -> str:
    """GLSL -> SPIR-V -> MSL for one stage, returned with its entry point renamed."""
    suffix = ".vert" if stage == "vert" else ".frag"
    glsl_path = workdir / f"{entry_name}{suffix}"
    spv_path = workdir / f"{entry_name}.spv"
    glsl_path.write_text(source, encoding="utf-8")

    run(
        [glslang, "-V", "--target-env", "vulkan1.0", "-S", stage,
         "-o", str(spv_path), str(glsl_path)],
        what=f"glslang ({entry_name}, {stage})",
    )

    result = subprocess.run(
        [spirv_cross, "--msl", "--msl-version", "20300", "--msl-decoration-binding",
         "--stage", stage, "--entry", "main", str(spv_path)],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        detail = (result.stdout + result.stderr).strip()
        _fail(f"spirv-cross ({entry_name}, {stage}) failed:\n{detail}")

    # SPIRV-Cross names the MSL entry point and its interface structs after the SPIR-V entry
    # point, which is always `main`, so the two stages of one material would collide on both.
    # A Metal library may not hold two functions of the same name whatever their stage.
    msl = re.sub(r"\bmain0_(in|out)\b", rf"{entry_name}_\1", result.stdout)
    msl = re.sub(r"\bmain0\b", entry_name, msl)
    return msl


def strip_msl_preamble(msl: str) -> str:
    """Drop the boilerplate the material's own preamble already supplies."""
    lines = []
    for line in msl.splitlines():
        stripped = line.strip()
        if stripped.startswith("#include <metal_stdlib>"):
            continue
        if stripped.startswith("#include <simd/simd.h>"):
            continue
        if stripped == "using namespace metal;":
            continue
        lines.append(line)
    return "\n".join(lines).strip("\n")


def generate(manifest: dict, glslang: str, spirv_cross: str) -> str:
    entries = []
    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        for material in manifest["materials"]:
            key = material["key"]
            source_path = REPO_ROOT / material["source"]
            if not source_path.is_file():
                _fail(f"material '{key}' names a missing source file: {material['source']}")

            body = source_path.read_text(encoding="utf-8")
            fragment = translate(
                build_fragment_glsl(body), "frag", f"crystalotc_frag_{key}",
                workdir, glslang, spirv_cross,
            )
            vertex = translate(
                build_vertex_glsl(), "vert", f"crystalotc_vert_{key}",
                workdir, glslang, spirv_cross,
            )
            source = "\n\n".join([
                "#include <metal_stdlib>",
                "using namespace metal;",
                strip_msl_preamble(vertex),
                strip_msl_preamble(fragment),
            ])
            entries.append((key, material["source"], source))

    return render_header(entries)


def render_header(entries: list[tuple[str, str, str]]) -> str:
    out: list[str] = []
    out.append("""\
/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

// GENERATED FILE - DO NOT EDIT.
//
// Produced by tools/generate_metal_shaders.py from the .frag sources named below, through
// glslang and SPIRV-Cross. Regenerate with `tools/generate_metal_shaders.py --write`; the
// build re-runs the translation and fails if this file is stale, so editing it by hand only
// delays the contradiction.

#pragma once

#include <array>
#include <string_view>

// One MTLLibrary per material, compiled on first use rather than all at startup. Each carries
// both stages: SPIRV-Cross derives the fragment's [[stage_in]] struct from the same varying
// interface it derived the vertex's output from, so a generated pair agrees by construction
// where a generated fragment paired with the hand-written built-in vertex would only agree by
// inspection. A session that binds no module shader compiles none of them.
struct MetalModuleMaterial
{
    std::string_view key;           // the .frag basename, which is what a material resolves to
    std::string_view vertexEntry;
    std::string_view fragmentEntry;
    std::string_view source;
};
""")

    for key, source, msl in entries:
        out.append("// ---------------------------------------------------------------------------")
        out.append(f"// {source}")
        out.append("// ---------------------------------------------------------------------------")
        out.append(f'inline constexpr std::string_view METAL_MODULE_MSL_{key.upper()} = R"MSL(')
        out.append(msl)
        out.append(')MSL";')
        out.append("")

    out.append("inline constexpr std::array METAL_MODULE_MATERIALS = std::to_array<MetalModuleMaterial>({")
    for key, _source, _msl in entries:
        out.append(
            f'    {{ "{key}", "crystalotc_vert_{key}", "crystalotc_frag_{key}", '
            f"METAL_MODULE_MSL_{key.upper()} }},"
        )
    out.append("});")
    out.append("")
    return "\n".join(out)


def resolve_tool(explicit: str | None, candidates: list[str], what: str) -> str:
    if explicit:
        if not shutil.which(explicit) and not Path(explicit).is_file():
            _fail(f"{what} not found at '{explicit}'")
        return explicit
    for candidate in candidates:
        found = shutil.which(candidate)
        if found:
            return found
    _fail(
        f"{what} not found on PATH (tried: {', '.join(candidates)}). "
        "Install glslang and spirv-cross, or pass --glslang/--spirv-cross."
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="regenerate the committed header")
    mode.add_argument("--check", action="store_true", help="fail if the committed header is stale")
    mode.add_argument("--list", action="store_true", help="print the translated material keys")
    parser.add_argument("--glslang", help="path to glslang or glslangValidator")
    parser.add_argument("--spirv-cross", dest="spirv_cross", help="path to spirv-cross")
    parser.add_argument("--output", type=Path, help="write somewhere other than the committed path")
    args = parser.parse_args()

    manifest = load_manifest()
    check_coverage(manifest)

    if args.list:
        for material in manifest["materials"]:
            print(f"{material['key']}\t{material['source']}")
        return 0

    glslang = resolve_tool(args.glslang, ["glslang", "glslangValidator"], "glslang")
    spirv_cross = resolve_tool(args.spirv_cross, ["spirv-cross"], "spirv-cross")

    generated = generate(manifest, glslang, spirv_cross)
    target = args.output or GENERATED_HEADER

    if args.write:
        target.write_text(generated, encoding="utf-8")
        print(f"wrote {target.relative_to(REPO_ROOT) if target.is_relative_to(REPO_ROOT) else target}"
              f" ({len(manifest['materials'])} materials)")
        return 0

    if not target.is_file():
        _fail(f"{target} does not exist; run --write")
    current = target.read_text(encoding="utf-8")
    if current != generated:
        _fail(
            f"{target.relative_to(REPO_ROOT)} is stale. "
            "Re-run tools/generate_metal_shaders.py --write and commit the result."
        )
    print(f"{target.relative_to(REPO_ROOT)} is up to date ({len(manifest['materials'])} materials)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
