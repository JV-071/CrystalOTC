# Official Tibia client 15.3x asset snapshot

This is a self-contained asset reference extracted from the locally installed
official Tibia client version `15.32.bf29ac`. It is intentionally versioned as
`15.3x` so later protocol upgrades can be compared without replacing this set.

## Contents

- `graphics-resources/` contains all 1,063 resources decoded from the official
  `graphics_resources.rcc` archive with their original virtual paths.
- `protocol-assets/` contains the 6,248 canonical game assets listed by the
  official asset manifest: appearances, sprite sheets, static data, maps,
  satellite layers, minimap layers, proficiencies, and catalogs.
- `sound-assets/` contains all 846 canonical sound catalog/data/audio files.
- `runtime-minimap/` contains the official client's installed runtime minimap
  cache.
- `store-images/` contains the installed store-image cache.
- `package-metadata/` contains the official asset/package manifests, version
  marker, application metadata, icon, translation catalog, and Qt path config.
- `raw-archives/` retains the original `graphics_resources.rcc` archive.
- `conflicts/` retains the official title and cursor variants that would
  overwrite active CrystalOTC custom resources.

## Manifests

- `graphics-resources-manifest.json` maps every decoded RCC resource to its
  snapshot path and SHA-256 digest.
- `active-import-manifest.json` records which previously missing UI resources
  were copied into CrystalOTC's active `data/` tree.
- `snapshot-manifest.json` inventories every versioned snapshot file and records
  its size and SHA-256 digest.

The snapshot is addressable under `/official-client-15.3x/`, but current modules
do not load it. Assets should be copied or mapped deliberately when implementing
protocol 15.30+ features. CrystalOTC's active custom title image and cursors
therefore remain unchanged.

Generic Qt frameworks, Qt Quick/QML runtime files, executables, BattlEye files,
and user state (`screenshots`, `characterdata`, `conf`, `cache`, and logs) are not
part of this asset snapshot.
