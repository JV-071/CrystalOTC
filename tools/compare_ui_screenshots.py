#!/usr/bin/env python3
"""Prepare and compare official-client and CrystalOTC UI screenshots.

The tool supports independent crops/scales (useful for Retina captures), masks
for dynamic map content, and writes normalized inputs, an overlay, a visible
RGBA delta, a side-by-side review image, and machine-readable metrics.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError as error:  # pragma: no cover - environment problem
    raise SystemExit("Pillow is required: python3 -m pip install Pillow") from error


def rectangle(value: str) -> tuple[int, int, int, int]:
    try:
        values = tuple(int(part) for part in value.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError("rectangle must be x,y,width,height") from None
    if len(values) != 4 or values[2] <= 0 or values[3] <= 0 or values[0] < 0 or values[1] < 0:
        raise argparse.ArgumentTypeError("rectangle must be non-negative x,y and positive width,height")
    return values


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare aligned official-client and CrystalOTC UI screenshots."
    )
    parser.add_argument("official", type=Path)
    parser.add_argument("crystal", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--official-crop", type=rectangle)
    parser.add_argument("--crystal-crop", type=rectangle)
    parser.add_argument("--official-scale", type=float, default=1.0)
    parser.add_argument("--crystal-scale", type=float, default=1.0)
    parser.add_argument(
        "--ignore-rect",
        type=rectangle,
        action="append",
        default=[],
        help="aligned x,y,width,height region excluded from metrics; repeatable",
    )
    parser.add_argument("--channel-tolerance", type=int, default=8)
    parser.add_argument("--max-different-fraction", type=float, default=1.0)
    args = parser.parse_args()
    if args.official_scale <= 0 or args.crystal_scale <= 0:
        parser.error("scales must be positive")
    if not 0 <= args.channel_tolerance <= 255:
        parser.error("--channel-tolerance must be between 0 and 255")
    if not 0 <= args.max_different_fraction <= 1:
        parser.error("--max-different-fraction must be between 0 and 1")
    return args


def load(path: Path, role: str) -> Image.Image:
    try:
        with Image.open(path) as image:
            return image.convert("RGBA")
    except (FileNotFoundError, IsADirectoryError, OSError) as error:
        raise RuntimeError(f"cannot read {role} screenshot {path}: {error}") from error


def normalize(
    image: Image.Image,
    crop: tuple[int, int, int, int] | None,
    scale: float,
) -> Image.Image:
    if crop is not None:
        x, y, width, height = crop
        if x + width > image.width or y + height > image.height:
            raise RuntimeError(
                f"crop {crop} is outside source dimensions {image.width}x{image.height}"
            )
        image = image.crop((x, y, x + width, y + height))
    if scale != 1.0:
        size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
        image = image.resize(size, Image.Resampling.LANCZOS)
    return image


def mask_for(size: tuple[int, int], ignored: list[tuple[int, int, int, int]]) -> Image.Image:
    mask = Image.new("L", size, 255)
    draw = ImageDraw.Draw(mask)
    for x, y, width, height in ignored:
        if x + width > size[0] or y + height > size[1]:
            raise RuntimeError(f"ignore rectangle {(x, y, width, height)} is outside {size}")
        draw.rectangle((x, y, x + width - 1, y + height - 1), fill=0)
    return mask


def compare(
    official: Image.Image,
    crystal: Image.Image,
    mask: Image.Image,
    tolerance: int,
) -> tuple[dict, Image.Image]:
    official_bytes = official.tobytes()
    crystal_bytes = crystal.tobytes()
    mask_bytes = mask.tobytes()
    diff_bytes = bytearray(len(official_bytes))
    compared = 0
    different = 0
    maximum_delta = 0
    total_delta = 0

    for pixel, index in enumerate(range(0, len(official_bytes), 4)):
        if mask_bytes[pixel] == 0:
            diff_bytes[index : index + 4] = b"\x30\x30\x30\xff"
            continue
        compared += 1
        deltas = [
            abs(official_bytes[index + channel] - crystal_bytes[index + channel])
            for channel in range(4)
        ]
        pixel_delta = max(deltas)
        maximum_delta = max(maximum_delta, pixel_delta)
        total_delta += sum(deltas)
        if pixel_delta > tolerance:
            different += 1
        alpha_delta = deltas[3]
        diff_bytes[index] = min(255, deltas[0] + alpha_delta)
        diff_bytes[index + 1] = min(255, deltas[1] + alpha_delta)
        diff_bytes[index + 2] = min(255, deltas[2] + alpha_delta)
        diff_bytes[index + 3] = 255

    different_fraction = different / compared if compared else 0.0
    metrics = {
        "dimensions": [official.width, official.height],
        "total_pixels": official.width * official.height,
        "compared_pixels": compared,
        "ignored_pixels": official.width * official.height - compared,
        "different_pixels": different,
        "different_fraction": different_fraction,
        "channel_tolerance": tolerance,
        "maximum_channel_delta": maximum_delta,
        "mean_channel_delta": total_delta / (compared * 4) if compared else 0.0,
    }
    return metrics, Image.frombytes("RGBA", official.size, bytes(diff_bytes))


def main() -> int:
    args = parse_args()
    try:
        official = normalize(load(args.official, "official"), args.official_crop, args.official_scale)
        crystal = normalize(load(args.crystal, "CrystalOTC"), args.crystal_crop, args.crystal_scale)
        if official.size != crystal.size:
            raise RuntimeError(
                "normalized dimensions differ: "
                f"official={official.size} CrystalOTC={crystal.size}; adjust crop/scale options"
            )
        mask = mask_for(official.size, args.ignore_rect)
        metrics, diff = compare(official, crystal, mask, args.channel_tolerance)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    args.output_dir.mkdir(parents=True, exist_ok=True)
    official.save(args.output_dir / "official-normalized.png")
    crystal.save(args.output_dir / "crystal-normalized.png")
    diff.save(args.output_dir / "diff.png")
    Image.blend(official, crystal, 0.5).save(args.output_dir / "overlay.png")

    gutter = 8
    side_by_side = Image.new(
        "RGBA", (official.width * 2 + gutter, official.height), (32, 32, 32, 255)
    )
    side_by_side.paste(official, (0, 0))
    side_by_side.paste(crystal, (official.width + gutter, 0))
    side_by_side.save(args.output_dir / "side-by-side.png")

    metrics.update(
        {
            "official_source": str(args.official),
            "crystal_source": str(args.crystal),
            "official_crop": args.official_crop,
            "crystal_crop": args.crystal_crop,
            "official_scale": args.official_scale,
            "crystal_scale": args.crystal_scale,
            "ignored_rectangles": args.ignore_rect,
            "max_different_fraction": args.max_different_fraction,
        }
    )
    (args.output_dir / "metrics.json").write_text(
        json.dumps(metrics, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"dimensions={official.width}x{official.height} "
        f"different={metrics['different_pixels']}/{metrics['compared_pixels']} "
        f"fraction={metrics['different_fraction']:.6f} "
        f"max_delta={metrics['maximum_channel_delta']} "
        f"mean_delta={metrics['mean_channel_delta']:.6f}"
    )
    print(f"artifacts: {args.output_dir}")
    return 0 if metrics["different_fraction"] <= args.max_different_fraction else 1


if __name__ == "__main__":
    sys.exit(main())
