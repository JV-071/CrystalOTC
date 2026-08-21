#!/usr/bin/env bash
#
# The macOS render matrix, as one command.
#
# Three sweeps have to agree before a macOS release, and until now they were three ad-hoc
# invocations with different argument shapes, two binaries, and one of them (the online scenes)
# with no script at all. This is the entry point the plan's Phase 5 task 6 asks for.
#
# It CANNOT run in CI and that is not a temporary limitation: it needs an XQuartz binary and a
# Cocoa binary at once, plus a window server for the first and the pinned fixture server for the
# third. No hosted runner provides any of those. The Definition of Done says so explicitly - the
# OpenGL-versus-Metal sweep runs locally before a macOS release rather than in CI - so what CI
# gates is the Linux llvmpipe reference set and the legacy-versus-frame sweep, and this covers
# the rest.
#
# Usage:
#   tools/run_macos_matrix.sh [--skip-online]
#
# Expects both configurations already built:
#   cmake --build build/macos-release --parallel 8   # XQuartz, the OpenGL reference vehicle
#   cmake --build build/macos-cocoa   --parallel 8   # Cocoa/Metal
#
# The online sweep additionally needs the pinned fixture server running:
#   cd ../crystalserver && ./build/macos-release/bin/crystalserver
# Its pin is machine-checked - `python3 tools/renderer_scenes.py fixture` prints the commit the
# scenes were authored against.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT" || exit 2

GL_CLIENT="build/macos-release/bin/otclient"
METAL_CLIENT="build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC"

SKIP_ONLINE=0
[[ "${1:-}" == "--skip-online" ]] && SKIP_ONLINE=1

# The two offline sweeps spell this differently and both spellings are load-bearing:
# compare_render_backends.sh wraps only the OpenGL client (GL_RUN_PREFIX), because the Metal one
# must NOT get a DISPLAY; compare_render_paths.sh drives a single client and wraps all of it
# (RUN_PREFIX). Setting only one of them is not a quiet degradation - the XQuartz client aborts
# with "Unable to open X11 display" on every capture, and eleven identical capture failures read
# as a renderer defect rather than as a missing environment variable.
DISPLAY=${DISPLAY:-:0}
XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
export DISPLAY XAUTHORITY
export GL_RUN_PREFIX="env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY"
export RUN_PREFIX="$GL_RUN_PREFIX"

# Fail on the setup problem, once, instead of on its eleven downstream symptoms. XQuartz does not
# put its tools on PATH by default, so look there too - and if the probe itself is unavailable,
# skip the check rather than refuse to run, since a missing xdpyinfo says nothing about DISPLAY.
XDPYINFO=$(command -v xdpyinfo || true)
[[ -z "$XDPYINFO" && -x /opt/X11/bin/xdpyinfo ]] && XDPYINFO=/opt/X11/bin/xdpyinfo

if [[ -n "$XDPYINFO" ]] && ! "$XDPYINFO" -display "$DISPLAY" > /dev/null 2>&1; then
    echo "::error::cannot open X11 display '$DISPLAY' - the OpenGL reference vehicle is XQuartz," >&2
    echo "so both offline sweeps need it running. Start XQuartz, or set DISPLAY/XAUTHORITY." >&2
    exit 2
fi

fail=0
declare -a SUMMARY=()

require() {
    if [[ ! -x "$1" ]]; then
        echo "::error::missing $2 binary at $1 - build it first (see the header)" >&2
        exit 2
    fi
}

require "$GL_CLIENT" "XQuartz/OpenGL"
require "$METAL_CLIENT" "Cocoa/Metal"

run_sweep() {
    local label=$1; shift
    echo
    echo "############################################################"
    echo "# $label"
    echo "############################################################"
    if "$@"; then
        SUMMARY+=("PASS  $label")
    else
        SUMMARY+=("FAIL  $label")
        fail=1
    fi
}

# 1. Legacy versus frame, on OpenGL. Proves the frame model still describes the renderer it was
#    validated against - and it is the only one of the three that also runs in CI, on llvmpipe,
#    so a disagreement between here and there is an environment difference rather than a defect.
run_sweep "legacy vs frame (OpenGL/XQuartz)" \
    bash tools/compare_render_paths.sh "$GL_CLIENT"

# 2. Metal versus OpenGL, both forced onto the frame path so the two consume an identical
#    RenderFrame and any difference is attributable BELOW the renderer boundary.
run_sweep "Metal vs OpenGL (offline scenes)" \
    bash tools/compare_render_backends.sh "$GL_CLIENT" "$METAL_CLIENT"

# 3. The online scenes - the only coverage of the MAP pool, the light overlay, the
#    map-composition material and the map readback. Compared against each scene's own noise
#    floor, because a live server cannot be frozen.
if [[ "$SKIP_ONLINE" -eq 1 ]]; then
    SUMMARY+=("SKIP  online scenes (--skip-online)")
elif ! pgrep -f crystalserver > /dev/null 2>&1; then
    SUMMARY+=("SKIP  online scenes (fixture server not running)")
    echo
    echo "::warning::the fixture server is not running, so the MAP pool, the light overlay and"
    echo "the map readback were not exercised at all. Start it and re-run, or pass --skip-online"
    echo "to say the omission is deliberate."
else
    run_sweep "Metal vs OpenGL (online scenes)" \
        bash tools/compare_online_backends.sh "$GL_CLIENT" "$METAL_CLIENT" 3
fi

echo
echo "############################################################"
echo "# macOS matrix summary"
echo "############################################################"
printf '%s\n' "${SUMMARY[@]}"

if [[ "$fail" -ne 0 ]]; then
    echo
    echo "::error::the macOS matrix did not pass"
    exit 1
fi

echo
echo "The online sweep reports figures rather than a verdict on purpose: read each"
echo "'across backends' number against that scene's own 'within' numbers."
exit 0
