#!/usr/bin/env python3
"""Compare renderer PNGs with a small per-channel tolerance.

Both images are read as RGBA. A pixel counts as different when any one of its
four channels - alpha included - drifts by more than ``--channel-tolerance``.
The run fails when the fraction of different pixels exceeds
``--max-different-fraction``.

Diff image
    ``--diff PATH`` writes a visualisation of the deltas. Without ``--diff`` no
    diff image is allocated or computed at all. The diff PNG is always fully
    opaque so that it renders identically in every viewer:

      * black          - the pixel matched exactly
      * red/green/blue - that colour channel drifted by that amount
      * neutral grey   - the alpha channel drifted by that amount

    The alpha delta is folded into all three visible channels (saturating at
    255) rather than into the diff's own alpha channel. Writing the delta into
    the alpha channel would render an alpha-only regression as an all-black or
    fully transparent image, which tells a reviewer nothing; folding it into
    the visible channels makes an alpha-only regression show up as a bright
    grey region.

Exit codes
    0  images match within tolerance
    1  too many pixels drifted beyond the per-channel tolerance
    2  usage error (bad, missing, or out-of-range command-line arguments)
    3  the two images have different dimensions
    4  an input image is missing or is not a readable image
    5  the diff image could not be written

Dependencies: the Python standard library plus Pillow. numpy is deliberately
not used - it is not available in the CI image.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError as error:  # pragma: no cover - environment problem
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from error

EXIT_MATCH = 0
EXIT_PIXEL_DRIFT = 1
EXIT_USAGE = 2
EXIT_SIZE_MISMATCH = 3
EXIT_MISSING_INPUT = 4
EXIT_DIFF_WRITE_FAILED = 5

DEFAULT_CHANNEL_TOLERANCE = 2
DEFAULT_MAX_DIFFERENT_FRACTION = 0.001


class ImageLoadError(Exception):
    """An input image is missing or cannot be decoded."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare renderer PNGs with a small per-channel tolerance.",
        epilog=(
            "exit codes: 0 match, 1 pixel drift, 2 usage error, "
            "3 size mismatch, 4 missing/unreadable input, 5 diff write failed"
        ),
    )
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--channel-tolerance", type=int, default=DEFAULT_CHANNEL_TOLERANCE)
    parser.add_argument(
        "--max-different-fraction", type=float, default=DEFAULT_MAX_DIFFERENT_FRACTION
    )
    parser.add_argument("--diff", type=Path)
    args = parser.parse_args()

    if not 0 <= args.channel_tolerance <= 255:
        parser.error("--channel-tolerance must be between 0 and 255")
    if not 0 <= args.max_different_fraction <= 1:
        parser.error("--max-different-fraction must be between 0 and 1")
    return args


def load_rgba(path: Path, role: str) -> Image.Image:
    """Load ``path`` as RGBA, reporting a one-line error instead of a traceback."""
    try:
        with Image.open(path) as image:
            return image.convert("RGBA")
    except FileNotFoundError:
        raise ImageLoadError(f"{role} image not found: {path}") from None
    except IsADirectoryError:
        raise ImageLoadError(f"{role} image is a directory: {path}") from None
    except OSError as error:
        raise ImageLoadError(f"{role} image could not be read: {path} ({error})") from None


def compare(
    reference: Image.Image,
    candidate: Image.Image,
    channel_tolerance: int,
    want_diff: bool,
) -> tuple[int, int, int, Image.Image | None]:
    """Return ``(different, maximum_delta, total_delta, diff_image)``.

    ``diff_image`` is ``None`` unless ``want_diff`` is set; nothing is
    allocated or written per pixel in that case.
    """
    width, height = reference.size
    byte_count = width * height * 4
    reference_bytes = reference.tobytes()
    candidate_bytes = candidate.tobytes()
    diff_bytes = bytearray(byte_count) if want_diff else None

    different = 0
    maximum_delta = 0
    total_delta = 0

    for index in range(0, byte_count, 4):
        delta_r = reference_bytes[index] - candidate_bytes[index]
        if delta_r < 0:
            delta_r = -delta_r
        delta_g = reference_bytes[index + 1] - candidate_bytes[index + 1]
        if delta_g < 0:
            delta_g = -delta_g
        delta_b = reference_bytes[index + 2] - candidate_bytes[index + 2]
        if delta_b < 0:
            delta_b = -delta_b
        delta_a = reference_bytes[index + 3] - candidate_bytes[index + 3]
        if delta_a < 0:
            delta_a = -delta_a

        pixel_delta = delta_r
        if delta_g > pixel_delta:
            pixel_delta = delta_g
        if delta_b > pixel_delta:
            pixel_delta = delta_b
        if delta_a > pixel_delta:
            pixel_delta = delta_a

        total_delta += delta_r + delta_g + delta_b + delta_a
        if pixel_delta > maximum_delta:
            maximum_delta = pixel_delta
        if pixel_delta > channel_tolerance:
            different += 1

        if diff_bytes is not None:
            # Fold the alpha delta into every visible channel so that an
            # alpha-only regression is not rendered as a black image.
            value = delta_r + delta_a
            diff_bytes[index] = 255 if value > 255 else value
            value = delta_g + delta_a
            diff_bytes[index + 1] = 255 if value > 255 else value
            value = delta_b + delta_a
            diff_bytes[index + 2] = 255 if value > 255 else value
            diff_bytes[index + 3] = 255

    diff_image = None
    if diff_bytes is not None:
        diff_image = Image.frombytes("RGBA", (width, height), bytes(diff_bytes))
    return different, maximum_delta, total_delta, diff_image


def main() -> int:
    args = parse_args()

    try:
        reference = load_rgba(args.reference, "reference")
        candidate = load_rgba(args.candidate, "candidate")
    except ImageLoadError as error:
        print(f"error: {error}", file=sys.stderr)
        return EXIT_MISSING_INPUT

    if reference.size != candidate.size:
        print(f"size mismatch: reference={reference.size} candidate={candidate.size}")
        return EXIT_SIZE_MISMATCH

    different, maximum_delta, total_delta, diff_image = compare(
        reference, candidate, args.channel_tolerance, args.diff is not None
    )

    width, height = reference.size
    pixel_count = width * height
    different_fraction = different / pixel_count
    mean_channel_delta = total_delta / (pixel_count * 4)

    print(
        f"pixels={pixel_count} different={different} "
        f"different_fraction={different_fraction:.6f} "
        f"max_channel_delta={maximum_delta} mean_channel_delta={mean_channel_delta:.6f}"
    )

    if diff_image is not None:
        try:
            args.diff.parent.mkdir(parents=True, exist_ok=True)
            diff_image.save(args.diff)
        except OSError as error:
            print(f"error: could not write diff image {args.diff}: {error}", file=sys.stderr)
            return EXIT_DIFF_WRITE_FAILED

    return EXIT_MATCH if different_fraction <= args.max_different_fraction else EXIT_PIXEL_DRIFT


if __name__ == "__main__":
    sys.exit(main())
