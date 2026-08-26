#!/usr/bin/env python3
"""Recover the official server's world light from official-client screenshots.

The world light arrives over an encrypted protocol inside an anti-cheat-protected
client, so its values are not readable off the wire. They do not need to be. The
client applies the ambient light as a *multiply* over the finished frame, so two
screenshots of the same scene differ by exactly the light and nothing else::

    frame_t / frame_reference  =  palette_rgb(colour) x (level / 255)

Shoot one reference frame at midday, when the light pass is idle and the frame is
the unlit scene, and every other frame divides down to the ambient light alone.

Recovering the pair from that ratio is exact rather than approximate, because the
palette is a 6x6x6 cube: every channel of ``palette_rgb`` is one of
``{0, 51, 102, 153, 204, 255}``. Only 216 colours are possible, so this scores all
of them - for each candidate the best-fit level is a one-line least squares, and
the candidate with the smallest residual is the answer.

Capture protocol - the method is only as good as this:

* Stand outdoors, above ground, somewhere with **no torches, braziers or other
  light sources** in view, and no creatures wandering through.
* Do not move the camera between shots. Do not move at all.
* In Options > Effects set **Ambient Light to 0%** (it is a floor and would clamp
  the night end) and **Clouds & Indoor Effect to 0%**.
* One screenshot per real minute for one real hour. A Tibian day is one real
  hour, so that is the full cycle at one frame per 24 Tibian minutes.
* Pick the midday frame as ``--reference``: real minute :30 is Tibian 12:00.

Usage::

    tools/recover_official_ambient_light.py shots/*.png --reference shots/1130.png
    tools/recover_official_ambient_light.py shots/ --reference shots/1130.png --json out.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("error: needs numpy and pillow - pip install numpy pillow")


PALETTE_STEPS = (0, 51, 102, 153, 204, 255)

# Ratios below this are dominated by quantisation; above it by clipping. Pixels
# outside the band in the reference frame carry no usable signal either way.
MIN_REFERENCE_VALUE = 40
MAX_REFERENCE_VALUE = 250


def palette_rgb(index: int) -> tuple[int, int, int]:
    """The 6x6x6 cube entry: index = r*36 + g*6 + b, each channel n*51."""
    return (
        PALETTE_STEPS[index // 36 % 6],
        PALETTE_STEPS[index // 6 % 6],
        PALETTE_STEPS[index % 6],
    )


def detect_viewport(frame: np.ndarray, reference: np.ndarray) -> tuple[int, int, int, int]:
    """Find the game viewport as (x, y, w, h) by what the light actually touches.

    Only the map is drawn under the light overlay, so on a dark frame every map
    pixel divides down well below its reference value while the surrounding UI
    divides to exactly 1. The bounding box of the pixels that moved is the
    viewport - which means a whole-window or whole-screen capture needs no
    coordinates from the user. On a capture that is already viewport-only, this
    finds the whole frame and costs nothing.
    """
    usable = np.all(reference >= MIN_REFERENCE_VALUE, axis=-1)
    ratio = np.ones(reference.shape[:2], dtype=np.float64)
    lum_frame = frame.astype(np.float64).mean(axis=-1)
    lum_reference = reference.astype(np.float64).mean(axis=-1)
    np.divide(lum_frame, lum_reference, out=ratio, where=usable & (lum_reference > 0))

    moved = usable & (np.abs(ratio - 1.0) > 0.06)
    rows = np.flatnonzero(moved.any(axis=1))
    cols = np.flatnonzero(moved.any(axis=0))
    if rows.size == 0 or cols.size == 0:
        return 0, 0, reference.shape[1], reference.shape[0]
    return int(cols[0]), int(rows[0]), int(cols[-1] - cols[0] + 1), int(rows[-1] - rows[0] + 1)


def measure_ratio(frame: np.ndarray, reference: np.ndarray) -> tuple[np.ndarray, int]:
    """Per-channel median of frame/reference over pixels that carry signal."""
    usable = np.all(
        (reference >= MIN_REFERENCE_VALUE) & (reference <= MAX_REFERENCE_VALUE), axis=-1
    )
    count = int(usable.sum())
    if count < 500:
        raise ValueError(f"only {count} usable pixels - is the reference frame the right scene?")

    num = frame[usable].astype(np.float64)
    den = reference[usable].astype(np.float64)

    # Median, not mean: a creature walking through or a swaying animation shifts a
    # minority of pixels a long way, and the median simply ignores them.
    return np.median(num / den, axis=0), count


def solve(ratio: np.ndarray) -> tuple[int, float, float]:
    """Best (palette index, level, residual) for a measured ratio vector."""
    best = (None, 0.0, float("inf"))
    for index in range(216):
        p = np.array(palette_rgb(index), dtype=np.float64)
        denom = float(p @ p)
        if denom == 0.0:
            continue
        # ratio ~= p/255 * level/255, so level = 255^2 * <ratio,p> / <p,p>
        level = 255.0 * 255.0 * float(ratio @ p) / denom
        if not 0.0 <= level <= 255.0:
            continue
        residual = float(np.linalg.norm(ratio - p * level / (255.0 * 255.0)))
        if residual < best[2]:
            best = (index, level, residual)
    return best


def load(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.uint8)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("frames", type=Path, nargs="+",
                        help="screenshots to analyse (files, or a directory of .png)")
    parser.add_argument("--reference", type=Path, required=True,
                        help="the midday frame, shot with the light pass idle")
    parser.add_argument("--json", type=Path, default=None,
                        help="also write the results to this file as JSON")
    parser.add_argument("--crop", default=None, metavar="X,Y,W,H",
                        help="crop every frame to this region before measuring; "
                             "omit to detect the game viewport automatically")
    args = parser.parse_args()

    paths: list[Path] = []
    for entry in args.frames:
        paths.extend(sorted(entry.glob("*.png")) if entry.is_dir() else [entry])
    paths = [p for p in paths if p.resolve() != args.reference.resolve()]
    if not paths:
        return _fail("no frames to analyse")

    try:
        reference = load(args.reference)
    except OSError as exc:
        return _fail(str(exc))

    if args.crop:
        try:
            cx, cy, cw, ch = (int(v) for v in args.crop.split(","))
        except ValueError:
            return _fail("--crop wants four integers: X,Y,W,H")
    else:
        # Detect from the darkest frame, where the light has moved the map furthest
        # from the reference and the UI around it has not moved at all.
        darkest = min(paths, key=lambda p: float(load(p).mean()) if p.exists() else 1e9)
        cx, cy, cw, ch = detect_viewport(load(darkest), reference)
        whole = (cx, cy, cw, ch) == (0, 0, reference.shape[1], reference.shape[0])
        print(f"viewport: {cw}x{ch} at ({cx},{cy})"
              f"{' - whole frame, already cropped' if whole else f', detected from {darkest.name}'}")

    reference = reference[cy:cy + ch, cx:cx + cw]
    print(f"reference: {args.reference.name}  {reference.shape[1]}x{reference.shape[0]}\n")
    print(f"{'frame':<34} {'level':>6} {'colour':>7} {'palette rgb':>15} {'fit':>7}")
    print("-" * 74)

    results = []
    for path in paths:
        try:
            frame = load(path)
        except OSError as exc:
            print(f"{path.name:<34} skipped: {exc}")
            continue
        frame = frame[cy:cy + ch, cx:cx + cw]
        if frame.shape != reference.shape:
            print(f"{path.name:<34} skipped: size differs from the reference")
            continue

        try:
            ratio, count = measure_ratio(frame, reference)
        except ValueError as exc:
            print(f"{path.name:<34} skipped: {exc}")
            continue

        index, level, residual = solve(ratio)
        if index is None:
            print(f"{path.name:<34} no palette entry fits - check the capture conditions")
            continue

        rgb = palette_rgb(index)
        # A good fit sits well under 0.02. Higher means the scene moved, a light
        # source was in view, or the reference frame was not actually unlit.
        flag = "" if residual < 0.02 else "  <-- poor fit, check this frame"
        print(f"{path.name:<34} {level:6.1f} {index:>7} {str(rgb):>15} {residual:7.4f}{flag}")

        results.append({
            "frame": path.name,
            "level": round(level, 1),
            "colour": index,
            "palette_rgb": list(rgb),
            "residual": round(residual, 5),
            "pixels": count,
        })

    if args.json and results:
        args.json.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
        print(f"\nwrote {len(results)} results to {args.json}")
    return 0


def _fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
