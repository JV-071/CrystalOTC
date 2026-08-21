#!/usr/bin/env bash
#
# Captures every offline renderer-baseline scene twice - once with the OpenGL backend, once with
# the Metal one - and compares the two.
#
# This is the Phase 4 parity instrument, and it asks a narrower question than either of the two
# that came before it. The checked-in llvmpipe references answer "does the renderer still look
# right". compare_render_paths.sh answers "do the legacy and compiled paths draw the same thing",
# within one graphics API. This one answers "do two graphics APIs draw the same FRAME the same
# way" - and it is only meaningful because both sides consume the identical RenderFrame, which is
# why the reference side is forced onto --render-path=frame rather than left on the legacy one.
# A difference here is below the renderer boundary, in one backend, by construction.
#
# It needs two binaries, because the two backends cannot coexist in one: the Cocoa window
# deliberately creates no OpenGL context and the XQuartz window creates no Metal layer. That is
# also why this cannot be a mode of the existing per-scene loop.
#
# Usage:
#   tools/compare_render_backends.sh <gl-client> <metal-client> [scene ...]
#
# Environment:
#   CAPTURE_DIR   where the clients write captures (default: the macOS baseline write dir)
#   ARTIFACT_DIR  where diffs and logs are written (default: artifacts/render-backends)
#   GL_RUN_PREFIX wrapper for the OpenGL client, e.g. "env DISPLAY=:0 XAUTHORITY=$HOME/.Xauthority"
#
# Exit codes:
#   0  every compared scene matched within its manifest tolerance
#   1  at least one scene differed, or failed to capture
#   2  usage error

set -uo pipefail

GL_CLIENT="${1:-}"
METAL_CLIENT="${2:-}"
if [ -z "$GL_CLIENT" ] || [ ! -x "$GL_CLIENT" ] || [ -z "$METAL_CLIENT" ] || [ ! -x "$METAL_CLIENT" ]; then
    echo "usage: $0 <gl-client> <metal-client> [scene ...]" >&2
    exit 2
fi
shift 2

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCENES_TOOL="$REPO_ROOT/tools/renderer_scenes.py"
COMPARE_TOOL="$REPO_ROOT/tools/compare_renderer_images.py"

if [ "$#" -gt 0 ]; then
    scenes=("$@")
else
    scenes=()
    while IFS= read -r line; do
        [ -n "$line" ] && scenes+=("$line")
    done < <(python3 "$SCENES_TOOL" ids --offline)
fi

if [ "${#scenes[@]}" -eq 0 ]; then
    echo "::error::no scenes to compare" >&2
    exit 1
fi

default_capture_dir() {
    case "$(uname -s)" in
        Darwin) echo "$HOME/Library/Application Support/crystalotc-baseline/.crystalotc-baseline/render-baselines" ;;
        *)      echo "${XDG_DATA_HOME:-$HOME/.local/share}/crystalotc-baseline/.crystalotc-baseline/render-baselines" ;;
    esac
}

CAPTURE_DIR="${CAPTURE_DIR:-$(default_capture_dir)}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$REPO_ROOT/artifacts/render-backends}"
mkdir -p "$ARTIFACT_DIR"

report="$ARTIFACT_DIR/render-backends.txt"
: > "$report"

failed=0

skipped=0

for scene in "${scenes[@]}"; do
    # A scene the second backend cannot express yet is not a failure and must not be reported as
    # a pass either. shader-matrix is made entirely of module fragment programs, which arrive with
    # the Phase 6 toolchain; comparing it today measures the absence of a phase, and a tolerance
    # wide enough to swallow that would stop being a gate for anything else.
    if [ "$(python3 "$SCENES_TOOL" field "$scene" renderBackendComparable)" = "false" ]; then
        reason="$(python3 "$SCENES_TOOL" field "$scene" renderBackendComparableReason)"
        echo "$scene SKIPPED $reason" >> "$report"
        echo "$scene: SKIP  $reason"
        skipped=$((skipped + 1))
        continue
    fi

    read -r -a base_args <<< "$(python3 "$SCENES_TOOL" field "$scene" command)"

    captured=1
    for backend in gl metal; do
        args=()
        for arg in "${base_args[@]}"; do
            case "$arg" in
                --renderer-baseline-output=*) args+=("--renderer-baseline-output=${backend}--${scene}.png") ;;
                *) args+=("$arg") ;;
            esac
        done
        # Both sides render the same compiled frame. Without this the OpenGL side would replay
        # DrawPool objects onto Painter and the comparison would fold two differences together.
        args+=("--render-path=frame" "--render-backend=$backend")

        if [ "$backend" = "gl" ]; then
            client="$GL_CLIENT"
            prefix="${GL_RUN_PREFIX:-}"
        else
            client="$METAL_CLIENT"
            prefix=""
        fi

        log="$ARTIFACT_DIR/$backend--$scene.log"
        status=0
        # shellcheck disable=SC2086
        ${prefix} "$client" "${args[@]}" > "$log" 2>&1 || status=$?

        if [ "$status" -ne 0 ] \
           || grep -q '^ERROR: \[renderer-baseline\]' "$log" \
           || ! grep -qF '[renderer-baseline] capture complete:' "$log"; then
            echo "::error title=Render backend capture::$scene ($backend): client did not complete the capture"
            echo "$scene CAPTURE-FAILED-$backend" >> "$report"
            captured=0
            failed=1
            break
        fi

        # A run that silently used the other backend would report a pass it did not earn - the
        # same class of mistake the render-path harness had to be taught about after reporting a
        # clean sweep of legacy against legacy.
        if ! grep -qF "backend '$backend'" "$log"; then
            echo "::error title=Render backend capture::$scene ($backend): the client did not select that backend"
            echo "$scene WRONG-BACKEND-$backend" >> "$report"
            captured=0
            failed=1
            break
        fi
    done

    [ "$captured" -eq 1 ] || continue

    channel_tolerance="$(python3 "$SCENES_TOOL" field "$scene" renderBackendChannelTolerance)"
    max_fraction="$(python3 "$SCENES_TOOL" field "$scene" renderBackendMaxDifferentFraction)"

    status=0
    output="$(python3 "$COMPARE_TOOL" \
        "$CAPTURE_DIR/gl--$scene.png" \
        "$CAPTURE_DIR/metal--$scene.png" \
        --channel-tolerance "$channel_tolerance" \
        --max-different-fraction "$max_fraction" \
        --diff "$ARTIFACT_DIR/diff-$scene.png" 2>&1)" || status=$?

    if [ "$status" -eq 0 ]; then
        echo "$scene PASS $output" >> "$report"
        echo "$scene: PASS  $output"
    else
        echo "::error title=Render backend parity::$scene: $output"
        echo "$scene FAIL($status) $output" >> "$report"
        echo "$scene: FAIL  $output"
        failed=1
    fi
done

echo
if [ "$skipped" -gt 0 ]; then
    echo "$skipped scene(s) skipped: the Metal backend does not implement what they measure yet"
fi
echo "report: $report"
exit "$failed"
