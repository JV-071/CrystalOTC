# Official QML to CrystalOTC component map

This is the first implementation map. QML line-level properties and asset
references are searchable in `official-qml-inventory.json`; this document
identifies the CrystalOTC ownership boundary for the main game UI.

## Main shell

| Official source | Responsibility | CrystalOTC owner | Parity work |
| --- | --- | --- | --- |
| `clientwindow.qml` | Native client root and start-screen backdrop | `init.lua`, `modules/client_entergame/`, `modules/client_topmenu/` | Keep Crystal branding where intentional; match content geometry separately from macOS chrome. |
| `gamewindow.qml` | Master login/in-game state and dock composition | `modules/game_interface/gameinterface.otui` and `.lua` | Treat as the authoritative hierarchy for map, sidebars, bars, cooldowns, and chat. |
| `GamewindowSplitView.qml` | Upper map pane and lower chat/action pane resizing | `gameBottomPanel`, `bottomSplitter`, and splitter persistence | Match minimums, resize constraints, and persisted upper/lower heights. |
| `MapWindowPane.qml` | 15x11 map viewport, aspect ratio, scaling, light overlay | `GameMapPanel`, `UIGameMap`, and `widgets/uigamemap.lua` | Align logical viewport, four-pixel map margin, crop, and scaling modes before styling around it. |
| `HorizontalActionBarContainer.qml` | Bottom action-bar rows | `modules/game_actionbar/` bottom dock | Match 34px slots, 2px slot spacing, lock controls, row order, and hidden-row collapse. |
| `VerticalActionBarContainer.qml` | Left/right action-bar columns | `gameActionBarLeftPanel`, `gameActionBarRightPanel`, `modules/game_actionbar/` | Match dock order and interaction with status bars and sidebars. |
| `CooldownBar.qml` | 24px cooldown row | `modules/game_cooldown/` and action-bar bottom dock | Match three-pixel exterior margin and icon overlays. |
| `Chat.qml`, `ChatInput.qml`, `ChatOutput.qml` | Tabs, messages, and input | `modules/game_console/` | Match 16px tabs, 96px default tab width, padding, background, and 90px minimum content height. |

## Sidebar system

| Official source | Responsibility | CrystalOTC owner | Parity work |
| --- | --- | --- | --- |
| `sidebar.qml` | One complete sidebar and its upper/lower panes | `GameSidePanel` containers in `gameinterface.otui` | Match panel borders, internal spacing, widget drop order, and fill behavior. |
| `SidebarManager.qml` | Add/remove left/right columns | `left/rightIncreaseSidePanels`, `left/rightDecreaseSidePanels` | Use the official per-position up/down/disabled button resources and placement. |
| `TibiaSidebarPanel.qml` | Fixed upper panel frame | `gameMainRightPanel`, inventory/minimap/status modules | Match two-pixel pane border and official horizontal/vertical insets. |
| `TibiaSidebarWidget.qml` | Widget frame, 15px header, content, controls, resize handle | `UIMiniWindow`, `data/styles/30-miniwindow*.otui` | Consolidate widget styling around the official 176px width, 4px border, 12px controls, and official frame assets. |
| `inventory.qml` | Equipment, capacity/soul, panel modes | `modules/game_inventory/` | Preserve the official fixed panel composition and status modes rather than treating it as a generic miniwindow. |
| `MinimapPanel.qml` | 108x111 minimap viewport and controls | `modules/game_minimap/` | Match viewport first, then border and button placement. |
| `HitpointsManaPanel.qml` | Sidebar health/mana bars | `modules/game_interface/widgets/statsbar.lua`, inventory/status OTUI | Match official status mode and 42px right-side subpanel rules. |
| `ButtonBarPanel.qml` | Sidebar control-button grid | `mods/game_buttons/`, options/top-button modules | Map each official resource/state and match wrapping/order. |
| `container.qml`, `ContainerSlot.qml` | Container widget and 34px slots | `modules/game_containers/` and `UIItem` styles | Match four slots per row, 3px spacing, official content insets, navigation buttons, and header behavior. |
| `battlelist.qml`, `BattleListEntry.qml` | Battle widgets and rows | `modules/game_battle/` | Match primary/secondary widget state, row height, filters, marks, and header icon. |
| `vipwidget.qml` | VIP widget and rows | `modules/game_viplist/` | Match header/frame first, then status colors and row controls. |
| `skillswidget.qml` | Skills widget and grouped statistics | `modules/game_skills/` | Apply shared sidebar frame tokens before row-level parity. |

## Shared primitives

| Official source | CrystalOTC owner | Important official values |
| --- | --- | --- |
| `TibiaStyle.qml` | New shared parity token layer plus existing `data/styles/` | Verdana 11 bold default, related margin 5, unrelated 10, narrow 2, scrollbar 12. |
| `TibiaButton.qml` | `data/styles/10-buttons.otui` | Default 43x20; preserve individual up/down/disabled resources. |
| `TibiaScrollBar.qml`, `TibiaScrollBarHandle.qml` | `data/styles/10-scrollbars.otui`, `20-smallscrollbar.otui` | 12px width; minimum includes two 12px buttons and 14px handle. |
| `TibiaDialogFrameWithCaption.qml` | Window/message-box styles | 17px header line, 4px frame, 12px content-to-frame margin. |
| `TibiaFrame*.qml` | Shared frame styles | Translate each source's exact `BorderImage.border` and tile mode individually. |
| `TibiaText*.qml` | Bitmap/TTF text styles | Match font, pixel size, outline/native rendering, line height, and disabled colors. |

## Canonical shell constants

These are extracted directly from `TibiaStyle.qml` and should become shared
CrystalOTC parity tokens:

| Token | Official value |
| --- | ---: |
| Minimum client content | 1020x650 |
| Sidebar content width | 176 |
| Sidebar panel border | 2 |
| Widget header | 15 |
| Widget border | 4 |
| Widget minimized height | 19 |
| Map logical fields | 15x11 |
| Map field size | 32 |
| Map unscaled viewport | 480x352 |
| Map minimum viewport | 240x176 |
| Map surrounding margin | 4 |
| Action-bar slot | 34 |
| Action-bar slot gap | 2 |
| Cooldown bar | 24 |
| Container slot | 34 |
| Container slot gap | 3 |
| Minimap viewport | 108x111 |
| Chat tab height | 16 |
| Chat default tab width | 96 |
| Chat minimum height | 90 |

The current `GameSidePanel` is 178px wide. That may correctly represent the
official 176px sidebar plus an outer boundary, but it must be confirmed from
the first full-window screenshot rather than changed from token comparison
alone.
