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
    fixture             print the fixture-server pin as key=value lines.
    fixture KEY         print one pin field: repository, branch, commit,
                        scriptPath, or vendoredCopy.
    validate            validate the manifest. Prints nothing on success;
                        prints one message per problem on stderr otherwise.
                        Beyond manifest shape this also enforces the
                        fixture-server pin: the vendored fixture scripts must
                        match their recorded sha256 digests, the anchors must
                        agree with FIXTURE_ANCHORS in the capture driver, and
                        every online scene must name an anchor that exists.

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
import hashlib
import json
import re
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
SUPPORTED_FIELDS = (
    "captureSize",
    "channelTolerance",
    "maxDifferentFraction",
    "command",
    "renderPathChannelTolerance",
    "renderPathMaxDifferentFraction",
    "renderBackendChannelTolerance",
    "renderBackendMaxDifferentFraction",
    "renderBackendComparable",
    "renderBackendComparableReason",
)

BASELINE_FLAG = "--renderer-baseline="

CAPTURE_DRIVER_PATH = (
    REPOSITORY_ROOT / "modules" / "dev_renderer_baseline" / "dev_renderer_baseline.lua"
)

REQUIRED_FIXTURE_KEYS = (
    "repository",
    "branch",
    "commit",
    "scriptPath",
    "vendoredCopy",
    "files",
    "anchors",
)
FIXTURE_PIN_FIELDS = ("repository", "branch", "commit", "scriptPath", "vendoredCopy")

# ``local FIXTURE_ANCHORS = { ... }`` in the capture driver, and one ``key = {x=,y=,z=}``
# entry inside it. The manifest is the declared contract; this is the second copy that
# has to agree with it.
DRIVER_ANCHOR_TABLE_RE = re.compile(r"^local FIXTURE_ANCHORS\s*=\s*\{(.*?)^\}", re.S | re.M)
DRIVER_ANCHOR_ENTRY_RE = re.compile(
    r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*"
    r"x\s*=\s*(-?\d+)\s*,\s*y\s*=\s*(-?\d+)\s*,\s*z\s*=\s*(-?\d+)\s*\}"
)


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

    # The legacy-vs-frame comparison is a different question from the reference gate, and one
    # scene answers it differently: UIGraph's lines are GL_LINE_STRIP with GL_LINE_SMOOTH on the
    # legacy path and triangulated quads on the compiled one, because Metal has neither wide nor
    # smoothed lines. The two are MEANT to differ there. A scene with no override answers both
    # questions with the same numbers.
    # And the cross-BACKEND comparison is a third question: one frame description, two graphics
    # APIs. It defaults to the same numbers again, because a backend that draws the same frame
    # differently is a defect rather than a tolerance - the exceptions have to earn their entry
    # with a measurement and a reason, exactly as the render-path one did.
    for prefix, override_key in (("renderPath", "renderPathTolerance"),
                                 ("renderBackend", "renderBackendTolerance")):
        if not key.startswith(prefix):
            continue

        base = key[len(prefix)].lower() + key[len(prefix) + 1 :]
        if base not in ("channelTolerance", "maxDifferentFraction"):
            continue

        override = scene.get(override_key)
        if isinstance(override, dict) and base in override:
            return format_number(override[base])
        return resolve_field(manifest, scene, base)

    # Whether the two graphics backends can be compared on this scene AT ALL yet. A scene made
    # entirely of module fragment programs measures nothing on a backend that has none, so
    # comparing it would report a failure whose cause is a phase that has not run rather than a
    # defect. Absent means comparable, which is the answer for every scene that does not say
    # otherwise.
    if key == "renderBackendComparable":
        return "false" if scene.get("renderBackendComparable") is False else "true"

    if key == "renderBackendComparableReason":
        reason = scene.get("renderBackendComparableReason")
        return reason if isinstance(reason, str) else ""

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


def driver_anchors(path: Path) -> dict[str, dict[str, int]] | None:
    """``FIXTURE_ANCHORS`` as declared by the capture driver, or None if unreadable."""
    try:
        source = path.read_text(encoding="utf-8")
    except OSError:
        return None
    table = DRIVER_ANCHOR_TABLE_RE.search(source)
    if table is None:
        return None
    return {
        name: {"x": int(x), "y": int(y), "z": int(z)}
        for name, x, y, z in DRIVER_ANCHOR_ENTRY_RE.findall(table.group(1))
    }


def is_anchor(value: object) -> bool:
    return (
        isinstance(value, dict)
        and set(value) == {"x", "y", "z"}
        and all(isinstance(value[axis], int) and not isinstance(value[axis], bool) for axis in "xyz")
    )


def validate_fixture_server(manifest: dict, errors: list[str]) -> None:
    """Enforce the fixture-server pin.

    The four online scenes are uncapturable without server-side fixtures that live in a
    different repository, on a personal fork. Prose cannot keep that honest, so the pin is
    checked three ways: the vendored scripts against their digests, the anchors against the
    capture driver's own copy, and each online scene's anchor key against the anchor table.
    """
    fixture = manifest.get("fixtureServer")
    if fixture is None:
        if any(scene.get("requiresOnlineGame") is True for scene in scenes_of(manifest)):
            errors.append(
                "manifest: scenes require an online game but there is no 'fixtureServer' pin "
                "recording which server commit provides the fixtures"
            )
        return

    if not isinstance(fixture, dict):
        errors.append("manifest.fixtureServer: must be an object")
        return

    for key in REQUIRED_FIXTURE_KEYS:
        if key not in fixture:
            errors.append(f"manifest.fixtureServer: missing required key '{key}'")

    for key in FIXTURE_PIN_FIELDS:
        value = fixture.get(key)
        if key in fixture and (not isinstance(value, str) or not value.strip()):
            errors.append(f"manifest.fixtureServer: {key} must be a non-empty string")

    commit = fixture.get("commit")
    if isinstance(commit, str) and not re.fullmatch(r"[0-9a-f]{40}", commit):
        errors.append(
            "manifest.fixtureServer: commit must be a full 40-character lowercase sha1, so the "
            "pin cannot drift with an abbreviation collision"
        )

    # The vendored copy is what a reader actually has in hand; verify it is the pinned code.
    files = fixture.get("files")
    vendored = fixture.get("vendoredCopy")
    if "files" in fixture and not isinstance(files, dict):
        errors.append("manifest.fixtureServer: files must be an object of name -> sha256")
    elif isinstance(files, dict) and isinstance(vendored, str):
        directory = REPOSITORY_ROOT / vendored
        if not directory.is_dir():
            errors.append(f"manifest.fixtureServer: vendoredCopy directory not found: {vendored}")
        else:
            for name, digest in sorted(files.items()):
                if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                    errors.append(
                        f"manifest.fixtureServer.files['{name}']: must be a sha256 hex digest"
                    )
                    continue
                target = directory / name
                if not target.is_file():
                    errors.append(f"manifest.fixtureServer: vendored file missing: {vendored}/{name}")
                    continue
                actual = hashlib.sha256(target.read_bytes()).hexdigest()
                if actual != digest:
                    errors.append(
                        f"manifest.fixtureServer: {vendored}/{name} does not match the pinned "
                        f"digest (recorded {digest[:12]}..., found {actual[:12]}...). Either the "
                        "vendored copy drifted from the server or the pin was not updated with it"
                    )
            present = {item.name for item in directory.glob("*.lua")}
            for extra in sorted(present - set(files)):
                errors.append(
                    f"manifest.fixtureServer: {vendored}/{extra} is not recorded in files, so its "
                    "contents are unpinned"
                )

    anchors = fixture.get("anchors")
    if "anchors" in fixture and (not isinstance(anchors, dict) or not anchors):
        errors.append("manifest.fixtureServer: anchors must be a non-empty object")
        return
    if not isinstance(anchors, dict):
        return

    for name, anchor in sorted(anchors.items()):
        if not is_anchor(anchor):
            errors.append(
                f"manifest.fixtureServer.anchors['{name}']: must be an object with integer "
                "x, y and z"
            )

    # Second copy: the driver compares the player position against its own table.
    declared = driver_anchors(CAPTURE_DRIVER_PATH)
    if declared is None:
        errors.append(
            "manifest.fixtureServer: could not read FIXTURE_ANCHORS from "
            f"{CAPTURE_DRIVER_PATH.relative_to(REPOSITORY_ROOT)}, so the anchors cannot be "
            "cross-checked against the capture driver"
        )
        return

    for name, anchor in sorted(anchors.items()):
        if not is_anchor(anchor):
            continue
        if name not in declared:
            errors.append(
                f"manifest.fixtureServer.anchors['{name}']: the capture driver's FIXTURE_ANCHORS "
                "has no such key"
            )
        elif declared[name] != anchor:
            errors.append(
                f"manifest.fixtureServer.anchors['{name}']: manifest says "
                f"{anchor['x']},{anchor['y']},{anchor['z']} but the capture driver says "
                f"{declared[name]['x']},{declared[name]['y']},{declared[name]['z']}"
            )
    for name in sorted(set(declared) - set(anchors)):
        errors.append(
            f"manifest.fixtureServer.anchors: the capture driver declares anchor '{name}' that "
            "the manifest does not pin"
        )


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

    fixture = manifest.get("fixtureServer")
    anchor_keys: set[str] = set()
    if isinstance(fixture, dict) and isinstance(fixture.get("anchors"), dict):
        anchor_keys = set(fixture["anchors"])

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

        if "renderBackendComparable" in scene:
            if not isinstance(scene["renderBackendComparable"], bool):
                errors.append(f"{where}: renderBackendComparable must be a boolean")
            elif scene["renderBackendComparable"] is False:
                reason = scene.get("renderBackendComparableReason")
                if not isinstance(reason, str) or not reason.strip():
                    errors.append(
                        f"{where}: renderBackendComparable false requires a non-empty "
                        "renderBackendComparableReason explaining what the second backend does "
                        "not implement yet, and which phase owns it"
                    )

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

        # An online scene is uncapturable without the fixture server, and which character
        # captures it is load-bearing rather than incidental: a hasfulllight group pins world
        # light to 255 and disables the LIGHT pool entirely. Both must be declared.
        if scene.get("requiresOnlineGame") is True:
            anchor_key = scene.get("fixtureAnchor")
            if not isinstance(anchor_key, str) or not anchor_key.strip():
                errors.append(
                    f"{where}: an online scene must name the fixture platform it captures via "
                    "'fixtureAnchor'"
                )
            elif anchor_keys and anchor_key not in anchor_keys:
                errors.append(
                    f"{where}: fixtureAnchor '{anchor_key}' is not one of "
                    f"fixtureServer.anchors ({', '.join(sorted(anchor_keys))})"
                )

            group = scene.get("requiresCharacterGroup")
            if not isinstance(group, str) or not group.strip():
                errors.append(
                    f"{where}: an online scene must declare 'requiresCharacterGroup' - whether "
                    "the capture character carries hasfulllight decides whether the LIGHT pool "
                    "runs at all"
                )

        elif "fixtureAnchor" in scene:
            errors.append(f"{where}: fixtureAnchor is only meaningful for an online scene")

    validate_fixture_server(manifest, errors)

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

    fixture_parser = subparsers.add_parser(
        "fixture", help="print the fixture-server pin"
    )
    fixture_parser.add_argument(
        "key",
        nargs="?",
        help=f"one of: {', '.join(FIXTURE_PIN_FIELDS)} (omit to print every field)",
    )

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

    if args.subcommand == "fixture":
        fixture = manifest.get("fixtureServer")
        if not isinstance(fixture, dict):
            print("error: manifest has no 'fixtureServer' pin", file=sys.stderr)
            return EXIT_INVALID
        if args.key is None:
            for key in FIXTURE_PIN_FIELDS:
                print(f"{key}={fixture.get(key, '')}")
            anchors = fixture.get("anchors")
            if isinstance(anchors, dict):
                for name, anchor in sorted(anchors.items()):
                    if is_anchor(anchor):
                        print(f"anchor.{name}={anchor['x']},{anchor['y']},{anchor['z']}")
            return EXIT_SUCCESS
        if args.key not in FIXTURE_PIN_FIELDS:
            print(
                f"error: unsupported pin field '{args.key}' "
                f"(supported: {', '.join(FIXTURE_PIN_FIELDS)})",
                file=sys.stderr,
            )
            return EXIT_USAGE
        print(fixture.get(args.key, ""))
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
