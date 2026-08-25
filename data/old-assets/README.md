# Superseded official-path assets

This directory preserves runtime files that were replaced by byte-exact
resources extracted from the official Tibia 15.3x client's
`graphics_resources.rcc`. It is an archive, not a runtime resource namespace.
Paths below this directory mirror the former paths below `data` so every
replacement remains traceable.

Run `python3 tools/migrate_official_ui_assets.py` for a dry-run audit or add
`--apply` to install missing official files and archive conflicts.
