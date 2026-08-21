#!/usr/bin/env bash
#
# Captures every offline renderer-baseline scene twice - once on the legacy render path, once
# on the compiled frame path - and compares the two.
#
# This is the Phase 3 parity instrument. The checked-in llvmpipe references answer "does the
# renderer still look right"; this answers the different and more precise question "do the two
# paths draw the same thing", in one environment, from one binary, with no cross-stack noise.
# A difference here is a difference in the frame model, not in a GL driver.
#
# Usage:
#   tools/compare_render_paths.sh <client-binary> [scene ...]
#
# Environment:
#   CAPTURE_DIR   where the client writes captures (default: the macOS baseline write dir)
#   ARTIFACT_DIR  where diffs and logs are written (default: artifacts/render-paths)
#   RUN_PREFIX    wrapper for the client, e.g. "xvfb-run -a -s '-screen 0 1020x644x24'"
#
# Exit codes:
#   0  every compared scene matched within its manifest tolerance
#   1  at least one scene differed, or failed to capture
#   2  usage error

set -uo pipefail

CLIENT="${1:-}"
if [ -z "$CLIENT" ] || [ ! -x "$CLIENT" ]; then
    echo "usage: $0 <client-binary> [scene ...]" >&2
    exit 2
fi
shift

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
ARTIFACT_DIR="${ARTIFACT_DIR:-$REPO_ROOT/artifacts/render-paths}"
mkdir -p "$ARTIFACT_DIR"

report="$ARTIFACT_DIR/render-paths.txt"
: > "$report"

failed=0

for scene in "${scenes[@]}"; do
    # The manifest owns the argv; only the output filename is rewritten, so that the two runs
    # of one scene cannot overwrite each other.
    read -r -a base_args <<< "$(python3 "$SCENES_TOOL" field "$scene" command)"

    captured=1
    for path in legacy frame; do
        args=()
        for arg in "${base_args[@]}"; do
            case "$arg" in
                --renderer-baseline-output=*) args+=("--renderer-baseline-output=${path}--${scene}.png") ;;
                *) args+=("$arg") ;;
            esac
        done
        args+=("--render-path=$path")

        log="$ARTIFACT_DIR/$path--$scene.log"
        status=0
        # shellcheck disable=SC2086
        ${RUN_PREFIX:-} "$CLIENT" "${args[@]}" > "$log" 2>&1 || status=$?

        if [ "$status" -ne 0 ] \
           || grep -q '^ERROR: \[renderer-baseline\]' "$log" \
           || ! grep -qF '[renderer-baseline] capture complete:' "$log"; then
            echo "::error title=Render path capture::$scene ($path): client did not complete the capture"
            echo "$scene CAPTURE-FAILED-$path" >> "$report"
            captured=0
            failed=1
            break
        fi
    done

    [ "$captured" -eq 1 ] || continue

    # A scene that falls back to the legacy path renders identically for a trivial reason, which
    # would make this gate report a pass it did not earn.
    if grep -q 'fall back to the legacy path' "$ARTIFACT_DIR/frame--$scene.log"; then
        echo "::error title=Render path capture::$scene: the frame path declined and fell back"
        echo "$scene FRAME-DECLINED" >> "$report"
        failed=1
        continue
    fi

    # The render-path tolerance, which is the scene's normal tolerance unless the manifest says
    # otherwise. Exactly one scene says otherwise, and it says why.
    channel_tolerance="$(python3 "$SCENES_TOOL" field "$scene" renderPathChannelTolerance)"
    max_fraction="$(python3 "$SCENES_TOOL" field "$scene" renderPathMaxDifferentFraction)"

    status=0
    output="$(python3 "$COMPARE_TOOL" \
        "$CAPTURE_DIR/legacy--$scene.png" \
        "$CAPTURE_DIR/frame--$scene.png" \
        --channel-tolerance "$channel_tolerance" \
        --max-different-fraction "$max_fraction" \
        --diff "$ARTIFACT_DIR/diff-$scene.png" 2>&1)" || status=$?

    if [ "$status" -eq 0 ]; then
        echo "$scene PASS $output" >> "$report"
        echo "$scene: PASS  $output"
    else
        echo "::error title=Render path parity::$scene: $output"
        echo "$scene FAIL($status) $output" >> "$report"
        echo "$scene: FAIL  $output"
        failed=1
    fi
done

echo
echo "report: $report"
exit "$failed"
