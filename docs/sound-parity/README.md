# Official 15.32 sound inventory

For synchronized official-client capture, acoustic identification, packet/file
observation, and CrystalOTC comparison, see [the sound parity lab](lab.md).
For the current verified state, remaining experiments, repository locations,
and next-session checklist, see [the sound parity handoff](whats-next.md).

This report is generated from the active shared `/sounds/` bank. Both the current 15.25 profile and 15.30 use this bank.

- Validation: **passed**
- Bank: `sounds-ce31d979f9894dc453f296820bcfe7183b992fc08e0a8da3fb8eeb1bb0dfd654.dat`
- Audio files: 844 (220 streamed)
- Numeric effects: 592
- Location ambience templates: 91
- Item ambience templates: 9
- Music templates: 25

## Trigger coverage

| Family | In bank | Named by server | Explicitly referenced by server |
| --- | ---: | ---: | ---: |
| Numeric effects | 592 | 501 | 250 |
| Location ambience | 91 | 91 | 34 |
| Music | 25 | 25 | 21 |

Item ambience is client-driven: its item IDs, distance, count thresholds, and selected OGGs are recorded in the JSON inventory. World locations for ambience and music are server behavior and therefore appear as server references, not as soundbank metadata.

## Known mapping gaps

- Numeric effects in the bank without a crystalserver symbol: 91
- Location ambiences without a crystalserver symbol: 0
- Music templates without a crystalserver symbol: 0

The JSON inventory contains the complete ID lists and every discovered source reference. New 15.32 ambience and music IDs retain neutral server names until packet capture confirms their canonical labels; region mappings are limited to map content and asset chronology.

## Numeric effect categories

| Category | Count |
| --- | ---: |
| `ambience_stream` | 125 |
| `chat_message` | 2 |
| `creature_death` | 65 |
| `creature_noise` | 72 |
| `event` | 5 |
| `food_and_drink` | 2 |
| `item_movement` | 19 |
| `party` | 4 |
| `raid_announcement` | 1 |
| `server_message` | 1 |
| `spell_attack` | 158 |
| `spell_generic` | 1 |
| `spell_healing` | 30 |
| `spell_support` | 68 |
| `ui` | 8 |
| `vip_list` | 2 |
| `weapon_attack` | 28 |
| `whisper_without_open_chat` | 1 |

## Reproduce

Run from the CrystalOTC repository root:

```sh
python3 tools/generate_sound_inventory.py --server-root ../crystalserver
```

Use `--check` in CI or before committing to verify that the checked-in JSON and this report still match the bank and both codebases.
