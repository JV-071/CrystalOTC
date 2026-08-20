#!/usr/bin/env python3
"""Compare renderer PNGs with a small per-channel tolerance."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError as error:
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from error


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--channel-tolerance", type=int, default=2)
    parser.add_argument("--max-different-fraction", type=float, default=0.001)
    parser.add_argument("--diff", type=Path)
    args = parser.parse_args()

    if not 0 <= args.channel_tolerance <= 255:
        parser.error("--channel-tolerance must be between 0 and 255")
    if not 0 <= args.max_different_fraction <= 1:
        parser.error("--max-different-fraction must be between 0 and 1")
    return args


def main() -> int:
    args = parse_args()
    with Image.open(args.reference) as image:
        reference = image.convert("RGBA")
    with Image.open(args.candidate) as image:
        candidate = image.convert("RGBA")

    if reference.size != candidate.size:
        print(f"size mismatch: reference={reference.size} candidate={candidate.size}")
        return 1

    reference_pixels = reference.load()
    candidate_pixels = candidate.load()
    diff_image = Image.new("RGBA", reference.size, (0, 0, 0, 255))
    diff_pixels = diff_image.load()

    different = 0
    maximum_delta = 0
    total_delta = 0
    width, height = reference.size
    for y in range(height):
        for x in range(width):
            deltas = tuple(abs(a - b) for a, b in zip(reference_pixels[x, y], candidate_pixels[x, y]))
            pixel_delta = max(deltas)
            maximum_delta = max(maximum_delta, pixel_delta)
            total_delta += sum(deltas)
            if pixel_delta > args.channel_tolerance:
                different += 1
            diff_pixels[x, y] = (deltas[0], deltas[1], deltas[2], 255)

    pixel_count = width * height
    different_fraction = different / pixel_count
    mean_channel_delta = total_delta / (pixel_count * 4)

    print(
        f"pixels={pixel_count} different={different} "
        f"different_fraction={different_fraction:.6f} "
        f"max_channel_delta={maximum_delta} mean_channel_delta={mean_channel_delta:.6f}"
    )

    if args.diff:
        args.diff.parent.mkdir(parents=True, exist_ok=True)
        diff_image.save(args.diff)

    return 0 if different_fraction <= args.max_different_fraction else 1


if __name__ == "__main__":
    sys.exit(main())
