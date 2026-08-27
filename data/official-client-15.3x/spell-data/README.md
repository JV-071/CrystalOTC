# Official client spell data — 15.32.75d4a0 (macOS)

Extracted from `Tibia.app/Contents/MacOS/client` (sha256 `c0d6a4c9…`), which
carries these as Qt resources compiled into the binary rather than into
`graphics_resources.rcc`.

| File | Qt resource | Notes |
|---|---|---|
| `spells.json` | `:/spells/spells.json` | 198 spells. Authoritative for cooldowns, groups, icon indices, vocations, descriptions. |
| `spells-previews.json` | `:/spells/spells-previews.json` | Per-spell animation timelines used by `MagicalArchiveSpellPreview.qml`. |
| `ui-strings-en.json` | `client.en.qm` | The spell/action-bar subset of the 4,622 translated UI strings. |

## Extraction

Both JSON blobs sit as raw zlib streams immediately after their UTF-16BE resource
name in the binary:

```python
i = data.find("spells.json".encode("utf-16-be"))
k = data.find(b"\x78\xda", i)
blob = zlib.decompressobj().decompress(data[k:])
```

`client.en.qm` is a plain id-based Qt translation file: magic
`3cb86418caef9c95cd211cbf60a1bddd`, block tag `0x69` = messages, sub-tag `6` = the
string id, sub-tag `3` = the UTF-16BE translation.

## Icon artwork

`iconIndex` indexes the spritesheets in `../graphics-resources/images/spells/`
(201 slots each, `spell-icons-32x32.png` and `spell-icons-20x20.png`). The client
renders them through a sheet-slicing image provider registered as
`image://spell-icons-32x32/<iconIndex>` — see the `image://%1/%2` format string
and the provider-id table in the binary.
