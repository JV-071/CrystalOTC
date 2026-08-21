#!/usr/bin/env bash
#
# Capture the online baseline scenes down both render backends and compare each scene against
# its OWN noise floor rather than against zero.
#
# The four online scenes are the only coverage of the MAP pool, the light overlay, the
# map-composition material and the map readback, and they are outside every automated sweep
# because they need the pinned fixture server (`crystalserver` f47f6e41). They are also where
# Phase 3's last defect and Phase 4's map-shift artefact were found, both after their handoffs
# had been drafted - which is the argument for running them at all.
#
# A live server cannot be frozen, so a cross-backend difference only means something when it is
# read against how much each backend differs from ITSELF. This captures N runs per backend per
# scene and reports both, which is the criterion Phase 3 established and Phase 4 reused.
#
# Two things this script exists to get right, both learned the hard way:
#
#  - LOGINS MUST BE SPACED. Without a gap the server still holds the previous session, the
#    `!fixture` talkaction is swallowed, and the run either never reaches the anchor or captures
#    from two tiles away - which reads as a 90%-different frame and looks like a renderer defect
#    until the shift is measured. Twelve seconds is enough.
#  - THE CHARACTER IS LOAD-BEARING, per scene. `lighting-overlap` needs a group-1 character or
#    the LIGHT pool is skipped entirely and the scene silently measures nothing.
#
# Usage:
#   tools/compare_online_backends.sh <gl-binary> <metal-binary> [runs]
#
# GL_RUN_PREFIX is prepended to the OpenGL binary only (it needs DISPLAY/XAUTHORITY).

set -uo pipefail

GL_CLIENT=${1:-}
METAL_CLIENT=${2:-}
RUNS=${3:-3}

if [[ -z "$GL_CLIENT" || -z "$METAL_CLIENT" ]]; then
    echo "usage: $0 <gl-binary> <metal-binary> [runs]" >&2
    exit 2
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT_DIR="$REPO_ROOT/artifacts/online-backends"
CAPTURE_DIR="$HOME/Library/Application Support/crystalotc-baseline/.crystalotc-baseline/render-baselines"
COMPARE="$REPO_ROOT/tools/compare_renderer_images.py"

# Twelve seconds between logins. See the header.
LOGIN_SPACING=${LOGIN_SPACING:-12}

mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/online-backends.txt"
: > "$REPORT"

ACCOUNT=${CRYSTALOTC_BASELINE_ACCOUNT:-@god}
PASSWORD=${CRYSTALOTC_BASELINE_PASSWORD:-god}

# scene:character - the character differs by scene and is not incidental.
SCENES=(
    "map-core:GOD"
    "map-screenshot:GOD"
    "lighting-overlap:Sorcerer Sample"
)

emit() { echo "$*" | tee -a "$REPORT"; }

capture() {
    local backend=$1 scene=$2 character=$3 index=$4
    local name="${backend}--${scene}-${index}"
    local log="$OUT_DIR/$name.log"
    local client=$GL_CLIENT prefix=${GL_RUN_PREFIX:-}

    if [[ "$backend" == "metal" ]]; then
        client=$METAL_CLIENT
        prefix=""
    fi

    sleep "$LOGIN_SPACING"

    env CRYSTALOTC_BASELINE_ACCOUNT="$ACCOUNT" \
        CRYSTALOTC_BASELINE_PASSWORD="$PASSWORD" \
        CRYSTALOTC_BASELINE_CHARACTER="$character" \
        ${prefix:-} "$client" \
        "--renderer-baseline=$scene" \
        "--renderer-baseline-output=$name.png" \
        --render-path=frame > "$log" 2>&1

    if [[ ! -f "$CAPTURE_DIR/$name.png" ]]; then
        emit "::error::$scene ($backend run $index): no capture produced - see $log"
        return 1
    fi

    cp "$CAPTURE_DIR/$name.png" "$OUT_DIR/$name.png"

    # A run that never reached the fixture anchor captures the login screen or the wrong tile,
    # which compares as a wildly different frame and reads as a renderer defect. The driver logs
    # arrival, so check it rather than inferring it from pixels.
    if grep -q "never reached fixture" "$log"; then
        emit "::error::$scene ($backend run $index): never reached the fixture anchor"
        return 1
    fi

    return 0
}

compare_pair() {
    local label=$1 a=$2 b=$3
    if [[ ! -f "$a" || ! -f "$b" ]]; then
        emit "  $label: MISSING"
        return
    fi
    local out
    out=$(python3 "$COMPARE" "$a" "$b" 2>&1 | tail -1)
    emit "  $label: $out"
}

status=0

for entry in "${SCENES[@]}"; do
    scene=${entry%%:*}
    character=${entry#*:}

    emit ""
    emit "=== $scene (character '$character') ==="

    for backend in gl metal; do
        for i in $(seq 1 "$RUNS"); do
            capture "$backend" "$scene" "$character" "$i" || status=1
        done
    done

    # Within-backend: the noise floor each backend has against itself.
    for backend in gl metal; do
        emit " within $backend:"
        for i in $(seq 2 "$RUNS"); do
            compare_pair "run1 vs run$i" \
                "$OUT_DIR/${backend}--${scene}-1.png" \
                "$OUT_DIR/${backend}--${scene}-$i.png"
        done
    done

    # Across backends: only meaningful read against the two floors above.
    emit " across backends:"
    for i in $(seq 1 "$RUNS"); do
        compare_pair "gl$i vs metal$i" \
            "$OUT_DIR/gl--${scene}-$i.png" \
            "$OUT_DIR/metal--${scene}-$i.png"
    done
done

emit ""
emit "report: $REPORT"
emit "Read every 'across backends' figure against that scene's 'within' figures."
emit "A cross-backend difference no larger than a backend's own variance is agreement."

exit "$status"
