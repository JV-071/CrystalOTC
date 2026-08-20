#!/usr/bin/env python3
"""Query and validate docs/rendering-baselines/scenes.json.

This is the single source of truth shared by the local capture workflow and by
the renderer-baseline CI job, so that neither hard-codes a scene list.

Subcommands
    ids --offline       scene ids CI can capture without a game server
                        (excludes scenes marked "ciCapture": false):
                        the scene has a non-empty "command" and
                        "requiresOnlineGame" is not true. One id per line.
    ids --gated         scene ids CI must COMPARE against a committed
                        reference: offline and "ciGate" is not false.
                        One id per line.
    ids --all           every scene id, one per line.
    field ID KEY        print one resolved field for scene ID:
                          captureSize           per-scene override, else the
                                                manifest-level captureSize;
                                                printed as "WIDTH HEIGHT"
                                                (space separated, e.g.
                                                "480 352")
                          channelTolerance      per-scene override, else
                                                defaultTolerance, else 2
                          maxDifferentFraction  per-scene override, else
                                                defaultTolerance, else 0.001
                          command               the capture command line, or
                                                an empty line when the scene
                                                has no automated command
    validate            validate the manifest. Prints nothing on success;
                        prints one message per problem on stderr otherwise.

Exit codes
    0  success / manifest is valid
    1  validation failure, or the manifest is missing or unreadable
    2  usage error (unknown subcommand, scene id, or field)

Reference images for gated scenes live at
docs/rendering-baselines/references/<canonicalBackend>/<scene-id>.png.

Standard library only - no third-party imports.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPOSITORY_ROOT / "docs" / "rendering-baselines" / "scenes.json"
REFERENCE_ROOT = REPOSITORY_ROOT / "docs" / "rendering-baselines" / "references"

EXIT_SUCCESS = 0
EXIT_INVALID = 1
EXIT_USAGE = 2

DEFAULT_CHANNEL_TOLERANCE = 2
DEFAULT_MAX_DIFFERENT_FRACTION = 0.001

REQUIRED_MANIFEST_KEYS = ("schemaVersion", "canonicalBackend", "captureSize", "scenes")
REQUIRED_SCENE_KEYS = ("id", "automation", "requiresOnlineGame", "features")
SUPPORTED_FIELDS = ("captureSize", "channelTolerance", "maxDifferentFraction", "command")

BASELINE_FLAG = "--renderer-baseline="


class ManifestError(Exception):
    """The manifest is missing, unreadable, or not valid JSON."""


def load_manifest(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as handle:
            manifest = json.load(handle)
    except FileNotFoundError:
        raise ManifestError(f"manifest not found: {path}") from None
    except OSError as error:
        raise ManifestError(f"manifest could not be read: {path} ({error})") from None
    except json.JSONDecodeError as error:
        raise ManifestError(f"manifest is not valid JSON: {path} ({error})") from None
    if not isinstance(manifest, dict):
        raise ManifestError(f"manifest must be a JSON object: {path}")
    return manifest


def scenes_of(manifest: dict) -> list[dict]:
    scenes = manifest.get("scenes")
    if not isinstance(scenes, list):
        return []
    return [scene for scene in scenes if isinstance(scene, dict)]


def is_offline(scene: dict) -> bool:
    """Capturable by CI without a game server.

    Requires a command, no game server, and no explicit ``ciCapture: false``. The
    last case exists for scenes that need something a headless runner cannot give
    them at all -- a window manager, or a display larger than the capture size --
    as opposed to merely rendering differently there.
    """
    command = scene.get("command")
    if not isinstance(command, str) or not command.strip():
        return False
    if scene.get("requiresOnlineGame") is True:
        return False
    return scene.get("ciCapture") is not False


def is_gated(scene: dict) -> bool:
    """Offline and not explicitly excluded from the CI comparison gate."""
    return is_offline(scene) and scene.get("ciGate") is not False


def find_scene(manifest: dict, scene_id: str) -> dict | None:
    for scene in scenes_of(manifest):
        if scene.get("id") == scene_id:
            return scene
    return None


def format_number(value: object) -> str:
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return f"{value:.10g}"
    return str(value)


def resolve_field(manifest: dict, scene: dict, key: str) -> str:
    if key == "captureSize":
        size = scene.get("captureSize")
        if size is None:
            size = manifest.get("captureSize")
        if not isinstance(size, list) or len(size) != 2:
            raise ManifestError(
                f"captureSize for scene '{scene.get('id')}' is not a 2-element array"
            )
        return f"{size[0]} {size[1]}"

    if key in ("channelTolerance", "maxDifferentFraction"):
        fallback = (
            DEFAULT_CHANNEL_TOLERANCE
            if key == "channelTolerance"
            else DEFAULT_MAX_DIFFERENT_FRACTION
        )
        defaults = manifest.get("defaultTolerance")
        if isinstance(defaults, dict) and key in defaults:
            fallback = defaults[key]
        return format_number(scene.get(key, fallback))

    if key == "command":
        command = scene.get("command")
        return command if isinstance(command, str) else ""

    raise KeyError(key)


def baseline_ids_in(command: str) -> list[str]:
    """Scene ids named by ``--renderer-baseline=`` tokens in ``command``.

    ``--renderer-baseline-output=`` is deliberately not matched: it carries a
    file name, not a scene id.
    """
    return [
        token[len(BASELINE_FLAG) :]
        for token in command.split()
        if token.startswith(BASELINE_FLAG)
    ]


def is_size_pair(value: object) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and all(isinstance(item, int) and not isinstance(item, bool) and item > 0 for item in value)
    )


def is_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def validate_tolerances(container: object, where: str, errors: list[str]) -> None:
    if not isinstance(container, dict):
        return
    if "channelTolerance" in container:
        value = container["channelTolerance"]
        if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 255:
            errors.append(f"{where}: channelTolerance must be an integer between 0 and 255")
    if "maxDifferentFraction" in container:
        value = container["maxDifferentFraction"]
        if not is_number(value) or not 0 <= value <= 1:
            errors.append(f"{where}: maxDifferentFraction must be a number between 0 and 1")


def validate(manifest: dict) -> list[str]:
    errors: list[str] = []

    for key in REQUIRED_MANIFEST_KEYS:
        if key not in manifest:
            errors.append(f"manifest: missing required key '{key}'")

    if not is_size_pair(manifest.get("captureSize")):
        errors.append("manifest: captureSize must be an array of two positive integers")

    if "defaultTolerance" in manifest:
        defaults = manifest["defaultTolerance"]
        if not isinstance(defaults, dict):
            errors.append("manifest: defaultTolerance must be an object")
        else:
            validate_tolerances(defaults, "manifest.defaultTolerance", errors)

    raw_scenes = manifest.get("scenes")
    if not isinstance(raw_scenes, list) or not raw_scenes:
        errors.append("manifest: scenes must be a non-empty array")
        return errors

    seen: set[str] = set()
    for position, scene in enumerate(raw_scenes):
        if not isinstance(scene, dict):
            errors.append(f"scenes[{position}]: must be an object")
            continue

        scene_id = scene.get("id")
        where = f"scene '{scene_id}'" if isinstance(scene_id, str) else f"scenes[{position}]"

        if not isinstance(scene_id, str) or not scene_id.strip():
            errors.append(f"scenes[{position}]: id must be a non-empty string")
        elif scene_id in seen:
            errors.append(f"{where}: duplicate scene id")
        else:
            seen.add(scene_id)

        for key in REQUIRED_SCENE_KEYS:
            if key not in scene:
                errors.append(f"{where}: missing required key '{key}'")

        if "automation" in scene and (
            not isinstance(scene["automation"], str) or not scene["automation"].strip()
        ):
            errors.append(f"{where}: automation must be a non-empty string")

        if "requiresOnlineGame" in scene and not isinstance(scene["requiresOnlineGame"], bool):
            errors.append(f"{where}: requiresOnlineGame must be a boolean")

        features = scene.get("features")
        if "features" in scene and (
            not isinstance(features, list)
            or not features
            or not all(isinstance(item, str) and item.strip() for item in features)
        ):
            errors.append(f"{where}: features must be a non-empty array of strings")

        if "command" in scene:
            command = scene["command"]
            if not isinstance(command, str) or not command.strip():
                errors.append(f"{where}: command must be a non-empty string")
            else:
                named = baseline_ids_in(command)
                if len(named) != 1:
                    errors.append(
                        f"{where}: command must contain exactly one "
                        f"'{BASELINE_FLAG}<id>' token, found {len(named)}"
                    )
                elif named[0] != scene_id:
                    errors.append(
                        f"{where}: command captures '{named[0]}' but the scene id is "
                        f"'{scene_id}'"
                    )

        if "captureSize" in scene and not is_size_pair(scene["captureSize"]):
            errors.append(f"{where}: captureSize must be an array of two positive integers")

        validate_tolerances(scene, where, errors)

        if "ciGate" in scene:
            if not isinstance(scene["ciGate"], bool):
                errors.append(f"{where}: ciGate must be a boolean")
            elif scene["ciGate"] is False:
                reason = scene.get("ciGateReason")
                if not isinstance(reason, str) or not reason.strip():
                    errors.append(
                        f"{where}: ciGate false requires a non-empty ciGateReason explaining "
                        "why the scene is captured but not compared"
                    )

        if "ciCapture" in scene:
            if not isinstance(scene["ciCapture"], bool):
                errors.append(f"{where}: ciCapture must be a boolean")
            elif scene["ciCapture"] is False:
                reason = scene.get("ciCaptureReason")
                if not isinstance(reason, str) or not reason.strip():
                    errors.append(
                        f"{where}: ciCapture false requires a non-empty ciCaptureReason "
                        "explaining why CI cannot capture the scene at all"
                    )

    return errors


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Query and validate the renderer baseline scene manifest.",
        epilog="exit codes: 0 success, 1 validation failure, 2 usage error",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=MANIFEST_PATH,
        help="path to scenes.json (default: %(default)s)",
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    ids_parser = subparsers.add_parser("ids", help="print scene ids, one per line")
    selection = ids_parser.add_mutually_exclusive_group(required=True)
    selection.add_argument(
        "--offline", action="store_true", help="scenes capturable without a game server"
    )
    selection.add_argument(
        "--gated", action="store_true", help="offline scenes compared against a reference"
    )
    selection.add_argument("--all", action="store_true", help="every scene id")

    field_parser = subparsers.add_parser("field", help="print one resolved scene field")
    field_parser.add_argument("id")
    field_parser.add_argument("key", help=f"one of: {', '.join(SUPPORTED_FIELDS)}")

    subparsers.add_parser("validate", help="validate the manifest")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        manifest = load_manifest(args.manifest)
    except ManifestError as error:
        print(f"error: {error}", file=sys.stderr)
        return EXIT_INVALID

    if args.subcommand == "validate":
        errors = validate(manifest)
        for message in errors:
            print(f"{args.manifest}: {message}", file=sys.stderr)
        return EXIT_INVALID if errors else EXIT_SUCCESS

    if args.subcommand == "ids":
        if args.all:
            selected = [scene.get("id") for scene in scenes_of(manifest)]
        elif args.gated:
            selected = [scene.get("id") for scene in scenes_of(manifest) if is_gated(scene)]
        else:
            selected = [scene.get("id") for scene in scenes_of(manifest) if is_offline(scene)]
        for scene_id in selected:
            print(scene_id)
        return EXIT_SUCCESS

    if args.subcommand == "field":
        scene = find_scene(manifest, args.id)
        if scene is None:
            print(f"error: unknown scene id: {args.id}", file=sys.stderr)
            return EXIT_USAGE
        try:
            print(resolve_field(manifest, scene, args.key))
        except KeyError:
            print(
                f"error: unsupported field '{args.key}' "
                f"(supported: {', '.join(SUPPORTED_FIELDS)})",
                file=sys.stderr,
            )
            return EXIT_USAGE
        except ManifestError as error:
            print(f"error: {error}", file=sys.stderr)
            return EXIT_INVALID
        return EXIT_SUCCESS

    parser.error(f"unknown subcommand: {args.subcommand}")
    return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main())
