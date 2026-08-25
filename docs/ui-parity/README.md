# Official-client UI parity

This directory is the implementation reference for matching the official Tibia
15.3x client UI in Ultia. It combines losslessly recovered QML, the
decoded `graphics_resources.rcc`, static component/asset inventories, persisted
official layout state, and controlled screenshots.

Screenshots are the rendered acceptance reference. The recovered QML explains
why the pixels are where they are and which official resource produces them.

For the complete session state, completed implementation, validation commands,
known exceptions, and next-session checklist, read [HANDOFF.md](HANDOFF.md).

## Recovered reference

The official macOS executable contains standard Qt resource tables. The local
extractor reconstructs the table containing the application module and its
companion `qmldir` metadata. The current snapshot contains:

- 396 complete QML source files;
- 91,661 lines of QML;
- 344 `TibiaStyle` tokens;
- 1,063 decoded graphics RCC resources;
- 681 graphics resources referenced directly by QML;
- source line numbers and expressions for every detected resource reference;
- dimensions for every PNG in the graphics archive.

The extracted QML lives under
`data/official-client-15.3x/qml-resources/qt/qml/qmlcomponents/`. It is a
reference snapshot; Ultia does not load QML at runtime.

## Reproduce the reference

From the repository root, with the official client installed in its standard
macOS location:

```sh
python3 tools/extract_official_qml.py
python3 tools/generate_ui_parity_inventory.py
python3 tools/generate_official_snapshot_manifest.py
python3 tools/audit_active_ui_asset_provenance.py
```

Inspect all resource tables without writing files:

```sh
python3 tools/extract_official_qml.py --list-trees
```

The generated artifacts are:

- `official-qml-inventory.json`: components, imports, QML types, asset
  expressions, style references, and layout assignments;
- `official-asset-usage.json`: reverse asset-to-component usage, PNG sizes,
  unresolved references, and active CrystalOTC asset status;
- `official-style-tokens.json`: values and consumers of `TibiaStyle` tokens;
- `active-ui-asset-provenance.json`: every statically referenced runtime UI
  resource classified as official-byte-identical, official-derived,
  custom-only, or dynamic;
- `generated-summary.md`: small regeneration summary.

## Translation rules

QML is evidence, not code to paste into OTUI. Apply these translations:

- `anchors` and `Layout.*` become OTUI anchors, box layouts, and explicit
  minimum/maximum constraints.
- `BorderImage.border` values become OTUI `image-border`/side-specific border
  values. Preserve the official source image without atlas resampling.
- `BorderImage.Repeat` becomes the corresponding repeated/tiled OTUI image
  behavior.
- `implicitWidth`/`implicitHeight` become content-derived size rules; do not
  freeze them unless the official QML uses a fixed value.
- `TibiaStyle` values are shared design tokens. Define a single CrystalOTC
  equivalent rather than scattering copied numbers through modules.
- QML states and loaders become Lua-driven OTUI state changes. State screenshots
  must validate up, down, disabled, focused, minimized, and expanded variants.
- Preserve logical pixel dimensions. Retina screenshot pixels are normalized
  during comparison and are not new UI dimensions.

## Asset policy

The extracted official RCC tree is the authoritative source for shared UI.
`tools/migrate_official_ui_assets.py --apply` exposes all 1,063 official
resources below `data` at their original virtual paths. Existing
byte-identical files remain untouched; conflicting legacy files are preserved
at the same relative path below `data/old-assets` before replacement.
The generated `official-runtime-asset-migration.json` records every file and
its SHA-256 provenance.

Custom-only resources remain available for Ultia features that have no official
15.3x equivalent. They must not replace an official resource at an official
path. New parity work should reference the original official path and validate
the asset's QML border, tile, and state usage before adding OTUI styling.

One runtime format bridge is deliberate: `/images/title-official.png` is a
lossless PNG conversion of the extracted official `/images/title.jpg`. The
original JPEG remains installed and hash-verified, but OTClient's current image
loader does not decode that JPEG on the native startup path. The PNG preserves
the official decoded pixels (ImageMagick comparison RMSE `0`) and prevents the
login background from falling back to black.

## Implementation order

1. Shared tokens and primitives: fonts, margins, buttons, frames, scrollbars.
2. Main shell: game map, split panes, sidebars, status/action-bar docks, chat.
3. Sidebar panel stack: minimap, inventory/status, HP/mana, control buttons.
4. Sidebar widgets: container, battle, VIP, skills, trackers, analysers.
5. Dialog frame and common form controls.
6. Feature dialogs one at a time.

See [component-map.md](component-map.md) for the source mapping and
[screenshot-capture.md](screenshot-capture.md) for the first capture pack.

## Screenshot comparison

Once two corresponding screenshots exist, normalize and compare them with:

```sh
python3 tools/compare_ui_screenshots.py \
  docs/ui-parity/captures/official/shell-default.png \
  docs/ui-parity/captures/crystal/shell-default.png \
  --output-dir artifacts/ui-parity/shell-default \
  --ignore-rect 350,80,480,352
```

Use independent `--official-crop`, `--crystal-crop`, `--official-scale`, and
`--crystal-scale` options when the captures include window chrome or different
Retina backing scales. The output contains normalized inputs, an overlay, a
visible delta, side-by-side review, and JSON metrics.
