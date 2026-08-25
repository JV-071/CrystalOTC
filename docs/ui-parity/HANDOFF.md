# Ultia UI parity handoff

Last updated: 2026-08-24
Repository: `/Users/alancruz/Github/Tibia/CrystalOTC`
Branch / starting commit: `main` / `5ec024ef`
Current product name: **Ultia**
Official reference: Tibia macOS client `15.32.bf29ac`

This document is the durable context for continuing the official-client UI
parity project in a fresh Codex session. Read this file before changing or
cleaning the worktree.

## Fresh-session quick start

1. Read this file, `docs/ui-parity/README.md`, `docs/ui-parity/component-map.md`,
   and `design-qa.md`.
2. Run `git status --short`. The worktree is deliberately dirty and contains
   the current parity implementation and the newly exposed official resource
   tree. Do **not** reset, checkout, delete, or overwrite these changes.
3. Verify asset integrity with `python3 tools/migrate_official_ui_assets.py`.
   The expected dry-run result is 1,063 identical, 0 missing, 0 replaced.
4. Build with `cmake --build build/macos-cocoa --parallel` and launch with
   `open -n build/macos-cocoa/bin/Ultia.app` when runtime verification is
   needed.
5. Continue with the main in-game shell. Login, character selection, and the
   offline start shell have already passed their scoped visual QA.

A useful first prompt for the next session is:

> Read `docs/ui-parity/HANDOFF.md`, `docs/ui-parity/README.md`, and
> `design-qa.md`. Preserve the dirty worktree. Verify the official-asset dry
> run, then continue official Tibia 15.32 UI parity with the main game shell,
> starting from the supplied/captured `shell-default` state.

## Goal and working method

The user's goal is for CrystalOTC, now branded **Ultia**, to reproduce the
official Tibia 15.3x client UI: layout, fonts, sizing, colors, assets, control
states, and state-dependent behavior. The official client is the visual and
behavioral reference; custom Ultia functionality may remain where there is no
official equivalent.

Use all three forms of evidence together:

- recovered official QML for hierarchy, anchors, dimensions, tokens, and
  resource-state assignments;
- decoded `graphics_resources.rcc` files for exact pixels and paths;
- same-state screenshots for rendered geometry, Retina/font behavior, dynamic
  content, and final acceptance.

QML is reference evidence, not runtime code. Ultia is OTUI/Lua/C++ and does not
load the extracted QML. Translate official constraints and states into the
existing architecture instead of copying a second UI runtime into the client.

## Authoritative official inputs

The installed official client is expected at:

```text
~/Library/Application Support/CipSoft GmbH/Tibia/packages/Tibia.app
```

Its persisted layout and general settings are at:

```text
~/Library/Application Support/CipSoft GmbH/Tibia/packages/Tibia.app/Contents/Resources/clientoptions.json
```

Do not share or commit `clientoptions.json`; it can contain device and account
state. Read only the settings needed to understand layout behavior.

The repository snapshot is:

```text
data/official-client-15.3x/
```

Important recovered material:

- QML: `data/official-client-15.3x/qml-resources/qt/qml/qmlcomponents/`
- decoded graphics: `data/official-client-15.3x/graphics-resources/`
- snapshot metadata: `data/official-client-15.3x/snapshot-manifest.json`
- QML resource metadata:
  `data/official-client-15.3x/qml-resources-manifest.json`

The recovered snapshot contains 396 QML files, 91,661 QML lines, 344
`TibiaStyle` tokens, 1,063 decoded graphics resources, and 681 direct graphics
references. `gamewindow.qml` is the main shell reference. Use the generated
inventories in `docs/ui-parity/` to find exact consumers and source line
numbers instead of manually browsing the whole tree.

The snapshot is about 282 MB. It is intentionally retained as reference data.

## Screenshot references already supplied

The display used for the official captures is a 1512-point-wide Retina macOS
display. The login source capture is 3024 x 1964 pixels at 2x and represents a
1512 x 982 logical screen including the menu bar. Preserve logical pixels when
translating geometry; Retina backing pixels are not new UI dimensions.

Official login source:

```text
/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_DdYTwO/Screenshot 2026-08-24 at 11.33.54 AM.png
```

Earlier character-selection/reference captures were supplied around 11:34 and
11:35 under the same temporary directory. The four useful in-game shell
captures are:

```text
/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_pWqnBr/Screenshot 2026-08-24 at 11.41.35 AM.png
/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_3VkOX4/Screenshot 2026-08-24 at 11.42.38 AM.png
/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_oE6v6s/Screenshot 2026-08-24 at 11.43.14 AM.png
/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_Dn1vs2/Screenshot 2026-08-24 at 11.43.23 AM.png
```

Those temporary paths are not durable and may disappear after logout or
reboot. If they no longer exist, ask the user to reattach fresh originals. The
durable, privacy-safe login comparison derivatives are under:

```text
artifacts/ui-parity/login-final/
```

That directory is ignored by Git. It contains full, login-card, topbar, and
music-toggle comparisons. The official email was redacted; do not recover,
repeat, or expose it.

For future captures follow `docs/ui-parity/screenshot-capture.md`. Use
unmodified PNGs, record logical size/backing scale, keep state consistent, and
avoid private messages or account data.

## Asset migration and provenance

The decoded official graphics tree is authoritative for shared Tibia UI.
`tools/migrate_official_ui_assets.py --apply` was run and exposed all 1,063
official resources below `data/` at their original virtual paths.

Migration behavior:

- byte-identical runtime files are left untouched;
- missing official files are installed;
- conflicting legacy files are copied to the same relative path under
  `data/old-assets/` before replacement;
- `docs/ui-parity/official-runtime-asset-migration.json` records hashes and
  provenance.

The migration's current dry-run invariant is:

```json
{
  "mode": "dry-run",
  "identical": 1063,
  "missing": 0,
  "replaced": 0
}
```

Twelve superseded files are retained under `data/old-assets/`: eleven cursors
and the former custom `images/title.jpg`. Do not delete that archive.

Custom-only files still exist for OTClient/Ultia features with no official
15.3x equivalent. This is intentional. Do not blindly move every file not
present in the official RCC; doing so will break custom modules. The rule is:
an official virtual path must use the official file, while a feature without
an official equivalent may keep its custom resource.

`tools/audit_active_ui_asset_provenance.py` statically classifies active UI
references. Its latest counts are:

| Classification | Count |
| --- | ---: |
| official-byte-identical | 320 |
| official-derived | 1 |
| custom-only | 659 |
| unresolved-or-dynamic | 439 |

Dynamic/unresolved entries require runtime or source inspection; they are not
automatically defects.

### Deliberate title-image exception

The original official `/images/title.jpg` is installed and hash-verified, but
OTClient's native startup image path did not decode/render it. Referencing it
directly produced a black background and left stale `Loading game files`
dialog pixels even though loading had completed.

Runtime therefore uses `data/images/title-official.png`, a lossless decoded
PNG conversion of the official JPEG. ImageMagick reports RMSE `0` between the
decoded images. This is the sole known `official-derived` resource and is not
old Crystal artwork.

Do not change these references back to `/images/title` unless the JPEG loader
is fixed and verified on the native startup path:

- `modules/client_background/background.otui`
- `modules/client_background/background.lua`
- `modules/dev_renderer_baseline/dev_renderer_baseline.lua`

## Completed implementation

### Branding and native macOS window

- Renamed the product to `Ultia` in `init.lua` and `src/CMakeLists.txt`.
- Bundle output is `build/macos-cocoa/bin/Ultia.app` with executable `Ultia`,
  bundle identifier `com.ultia.client`, and display/name values `Ultia`.
- `src/framework/platform/cocoawindow.mm` now draws a centered native titlebar
  label while retaining the native title for window management/accessibility.
- The Metal layer declares the sRGB presentation color space while retaining
  `MTLPixelFormatBGRA8Unorm`. This corrected the dull wallpaper/logo seen
  against the official Qt client. Rosetta was not the cause; it translates
  instructions rather than intentionally changing UI colors.
- Normal startup no longer always enables module live reload. Pass
  `--live-reload` explicitly for development; otherwise the title no longer
  contains `(LIVE RELOAD ENABLED)`.

### Login, character selection, and offline shell

- `modules/client_background/background.otui` and `.lua` implement the
  official title crop, login shell, bottom bar, and exact 163 x 44 CipSoft mark
  anchored immediately above the 117-pixel bottom bar.
- `modules/client_entergame/entergame.otui` implements the official fixed login
  geometry and Verdana roles.
- The recovery link uses a real one-pixel child line for a continuous solid
  underline. The previous bitmap-font underline appeared dashed.
- `modules/client_entergame/characterlist.otui` and `.lua` implement the
  character-selection geometry, table columns, free-account section, and
  related states.
- The clean launch now settles on the login screen without retaining the
  `Loading game files` box.

### Top shell and controls

- `data/styles/20-topmenu.otui` contains official options/logout button styles
  and pressed offsets.
- `modules/client_topmenu/topmenu.lua` adds official icon-button constructors.
- `modules/client_options/options.lua` and
  `modules/game_interface/gameinterface.lua` use the exact official
  options/logout up/down resources.
- `modules/client_terminal/terminal.lua` hides the non-official topbar terminal
  button. The Ctrl+T shortcut remains available.
- `modules/client_options/data_options.lua` synchronizes the music control's
  checked state with the audio setting before changing official mute icons.
  A real click verified that the pressed state remains after the pointer leaves;
  a second click restored the original setting.

### Fonts

The implemented login/shell scope uses the bundled Verdana roles derived from
official QML, including the appropriate bold 11-pixel default role. Continue
mapping font family, weight, pixel size, line height, native/bitmap rendering,
and disabled color per QML component; do not assume one global font role fits
every widget.

## Important changed files

The core tracked implementation changes are:

```text
init.lua
src/CMakeLists.txt
src/framework/platform/cocoawindow.mm
data/styles/20-topmenu.otui
modules/client_background/background.lua
modules/client_background/background.otui
modules/client_entergame/entergame.otui
modules/client_entergame/characterlist.lua
modules/client_entergame/characterlist.otui
modules/client_options/data_options.lua
modules/client_options/options.lua
modules/client_terminal/terminal.lua
modules/client_topmenu/topmenu.lua
modules/game_interface/gameinterface.lua
modules/dev_renderer_baseline/dev_renderer_baseline.lua
design-qa.md
```

The eleven tracked cursor files and `data/images/title.jpg` are also modified
because they were replaced with their official byte-identical versions. Many
official resources under `data/images/` are newly untracked because the
repository did not previously expose the complete RCC tree.

New parity tooling and documentation includes:

```text
tools/extract_official_qml.py
tools/generate_ui_parity_inventory.py
tools/generate_official_snapshot_manifest.py
tools/migrate_official_ui_assets.py
tools/audit_active_ui_asset_provenance.py
tools/compare_ui_screenshots.py
docs/ui-parity/
data/old-assets/
```

At handoff time Git reports 30 tracked files changed and 585 untracked entries;
the tracked diff is approximately 2,471 insertions and 118 deletions. No commit
was created. Treat the whole worktree as user-owned and preserve unrelated or
pre-existing changes.

## Build, launch, and validation

Build the native macOS bundle:

```sh
cmake --build build/macos-cocoa --parallel
```

Known non-fatal build noise: several dependencies were built for macOS 26
while the app target is macOS 14. These currently appear as linker warnings,
not build failures.

Launch a fresh instance:

```sh
open -n build/macos-cocoa/bin/Ultia.app
```

Launch with development reload only when intentionally wanted:

```sh
open -n build/macos-cocoa/bin/Ultia.app --args --live-reload
```

The compact application name changed to `ultia`, so its persisted preference
directory is distinct from the old CrystalOTC one. The window was maximized and
closed cleanly during QA so the new size was persisted, but a new machine or
clean preference directory may need the window maximized again before capture.

Run the proportionate static checks after changes:

```sh
python3 tools/migrate_official_ui_assets.py
python3 tools/generate_ui_parity_inventory.py
python3 tools/audit_active_ui_asset_provenance.py
python3 -m py_compile \
  tools/migrate_official_ui_assets.py \
  tools/audit_active_ui_asset_provenance.py \
  tools/generate_ui_parity_inventory.py
luac -p \
  init.lua \
  modules/client_background/background.lua \
  modules/client_entergame/characterlist.lua \
  modules/client_options/data_options.lua \
  modules/client_options/options.lua \
  modules/client_terminal/terminal.lua \
  modules/client_topmenu/topmenu.lua \
  modules/dev_renderer_baseline/dev_renderer_baseline.lua \
  modules/game_interface/gameinterface.lua
git diff --check
```

Verify bundle identity if native build files change:

```sh
plutil -p build/macos-cocoa/bin/Ultia.app/Contents/Info.plist
```

Expected identity fields are `Ultia`, `Ultia`, `com.ultia.client`, and `Ultia`
for display name, executable, identifier, and bundle name respectively.

## QA status and evidence

`design-qa.md` is the authoritative review log. Its final result for login,
character selection, and offline-shell scope is **passed**, with no actionable
P0/P1/P2 difference and no scoped P3 item remaining.

Useful evidence under `artifacts/ui-parity/login-final/`:

- `full-side-by-side.png`: full official source and Ultia implementation;
- `login-side-by-side.png`: focused logo/card comparison;
- `topbar-stacked.png`: official and Ultia top shells;
- `mute-state-comparison.png`: normal and persistent checked state;
- `official-full-redacted.png`: privacy-safe official source;
- `ultia-final.jpeg`: final native Metal implementation capture.

Intentional differences in those captures are the requested product name
(`Tibia` versus `Ultia`), live network counters, remembered-email state, hint
copy, promotion/event/boosted data, and other volatile content. They are not
layout defects.

## Current main-shell status: geometry, cursor, and fixed sidebar

The master shell geometry pass and fixed upper-right sidebar pass are complete
within their stated scopes. The final correction was derived from the complete
3024 x 1964 screenshots: the shared right-rail origin is four logical pixels
lower, aligning the minimap and every panel below it with the official shell.
Inside the official 161-pixel inventory panel, the equipment roots and Store
Inbox button are another four logical pixels lower while the minimize/blessing
pair remains fixed and keeps the official two-pixel gap. Durable comparison
evidence is under `artifacts/ui-parity/shell-initial/`,
`artifacts/ui-parity/sidebar-pass/`, and
`artifacts/ui-parity/inventory-spacing/`; the detailed backing-pixel
measurements and normalization notes are in `design-qa.md`.

The official-compatible online default now has one 176-pixel right sidebar,
no left or horizontal custom shelves, no duplicate compact hitpoints/mana row,
the recovered minimap/equipment/control geometry, and one three-button managed
shortcut row. The custom Helper Stats control is no longer permanent chrome;
it remains selectable under Available Shortcuts. Store highlight/New/Sale
overlays default off until backed by real controller state.

The macOS native cursor loader also splits the official horizontal cursor
strips into square frames and advances them at 100 ms without restarting the
animation when the semantic cursor is selected again. The user confirmed the
walk cursor animates smoothly.

The map/chat splitter now has the official pointer-centered resize feedback
from `GamewindowSplitView.qml`: a 60 x 22 percentage header, seven-pixel
splitter interval, 31 x 31 mode-button wrapper, and official map/chat/both
icons. The displayed percentage comes from the real `UIMap` rectangle width
over the native 480-pixel viewport. The first version incorrectly sampled the
fixed internal Retina render texture and stayed at 100%; the corrected version
uses the fitted visible-world-map width. The other root cause was a direct-child
lookup for the nested label/button/icon; all three now use recursive lookup.
Post-fix runtime evidence shows the label dynamically reporting 97%. Per the
user's clarification, gameplay is hard-capped at 200% (960 x 704) and
pixel-exact stops do not exceed it. A subsequent 199% maximum capture exposed a
missing two-pixel UIMap inset in the cap geometry; this is now included so the
maximum rendered map, not merely the outer widget, reaches 960 x 704. Evidence
is under `artifacts/ui-parity/splitter-feedback/`. Computer Use verified the
component chrome, and the user's next full-resolution capture showed the
maximum overlay at exactly 200%, closing the splitter-feedback blocker.

Chat output now uses the existing `Verdana Bold-11px` raster rather than the
lighter `Verdana Bold-11px-new` variant. The full-resolution comparison shows
the official client is using 11-pixel bold Verdana; do not increase the point
size when refining its remaining color/raster differences.

Sidebar free space now behaves like the official fixed curtain. The previous
`sidebarFreeSpace` child was resized below Backpack and visibly pushed its grey
frame edge. `UIMiniWindowContainer` now paints the same frame once on the fixed,
bottom-aligned parent and lets miniwindows reveal or cover it through normal
clipping. The user verified the corrected Backpack resize interaction.

The user also verified the final right-rail/inventory pass: the minimap and its
surrounding rail are at the official top offset, the equipment and Store Inbox
button sit lower with the source spacing, and the minimize/blessing buttons
remain in place.

The Cyclopedia map pass is also implemented from the extracted official QML.
The earlier red-outline map was the official Map View renderer, not a missing
or substituted asset; the source screenshot uses Surface View. Ultia now uses
textured Surface View as the migrated default while retaining the user's
explicit view choice. The expanded Navigation panel includes Current area,
the area name, rose, layer selector, and zoom controls at the official vertical
cadence. The Cyclopedia rose and the main minimap rose now share the same live
world-time update path.

Do not remove `MAIN_RIGHT_PANEL_EXTRA_HEIGHT = 3` from
`modules/game_mainpanel/mainpanel.lua`. The extracted `sidebar.qml` confirms
that one `TibiaFrame2PixelUpFilled` encloses the complete upper pane. A trial
without this allowance made the bottom frame disappear; it was reverted and
the restarted client again shows the correct enclosing edge. This is geometry,
not a missing inventory-specific border asset.

Cyclopedia evidence is under `artifacts/ui-parity/cyclopedia-map/`; the
restored collapsed-inventory frame is under
`artifacts/ui-parity/inventory-collapse/`. Detailed provenance and the
official QML mapping are recorded in `design-qa.md`.

All 67 tests pass, the asset dry-run remains 1,063 identical / 0 missing / 0
replaced, and `git diff --check` passes. CrystalServer was running during the
last online QA session; resolve its current process state afresh in a future
session.

## Next implementation phase: remaining main game shell

Continue in the order documented by `component-map.md`:

1. top status-bar pixels and dynamic labels;
2. bottom/left/right action bars and cooldown row;
3. chat tabs/output/input and the remaining resize-mode layout-policy behavior;
4. reusable sidebar miniwindow frames, then container, battle, VIP, skills,
   trackers, and analysers.

Canonical starting constants are already summarized in `component-map.md`,
including 176-pixel sidebar content width, 15 x 11 logical map fields at 32
pixels, 480 x 352 unscaled viewport, 34-pixel action/container slots, 12-pixel
scrollbars, 16-pixel chat tabs, and 90-pixel minimum chat height. Validate
composed geometry from screenshots before changing the existing 178-pixel
`GameSidePanel`; that value may include the official 176-pixel content plus an
outer boundary.

Before implementing a component:

1. locate its official QML and exact resource paths using the generated JSON;
2. inspect all relevant up/down/disabled/focused/minimized/expanded states;
3. map the rules into the current OTUI/Lua owner listed in
   `component-map.md`;
4. use the official resource at its original runtime path;
5. relaunch for Lua/OTUI changes unless explicitly using `--live-reload`;
6. capture the same viewport and state in both clients;
7. combine source and implementation into one comparison image and record the
   result in `design-qa.md`.

## Screenshots to request next

The existing four in-game screenshots are enough to begin broad shell
measurement if their temporary files still exist. For reliable state-by-state
development, ask the user for fresh original PNGs when beginning the main
shell, preferably at the same 1512-point logical window size and 2x Retina
scale:

- default game shell with one right sidebar and chat/action bar visible;
- shell with lower sidebar widgets closed, isolating map/dock geometry;
- left Battle List open;
- right Analytics Selector open and an analyser expanded;
- minimap/equipment/status/control-button area;
- expanded container plus minimized/expanded Battle or VIP widgets;
- populated hotbar, cooldown, chat tabs, scrollbar, and focused input;
- focused close-ups for hover, pressed, checked, disabled, minimized, expanded,
  and scrollbar states as each component is implemented.

Use the scenario names and metadata template in
`docs/ui-parity/screenshot-capture.md`. Do not request every dialog in advance;
capture only the next feature and its meaningful states.

## Known pitfalls

- Do not equate Retina screenshot pixels with logical UI dimensions.
- Do not attribute color differences to Rosetta without evidence; the observed
  issue was presentation color-space configuration.
- Do not use visual approximations when an exact official up/down/disabled
  resource exists.
- Do not implement a toggle by swapping only its icon; keep the widget's
  checked/on state synchronized so pressed styling persists after hover.
- Do not use bitmap-glyph underline decoration for the recovery link; it caused
  the dashed appearance.
- Do not restore the topbar terminal icon; it is intentionally hidden for
  official parity while its keyboard shortcut remains.
- Do not use the official JPEG directly until native JPEG rendering is fixed;
  preserve the documented pixel-equivalent PNG bridge.
- Do not delete custom-only assets merely because the official RCC lacks them.
- Do not clean the untracked resource tree or `data/old-assets`.
- Temporary screenshot paths may vanish. Ask the user to reattach originals
  rather than substituting resized screenshots.

## Definition of done for each next component

A component is complete when its layout derives from official QML/tokens, its
official assets and all meaningful control states are wired correctly, its
fonts and logical-pixel sizing match, interaction behavior is verified, a
same-state screenshot comparison has no unexplained actionable difference, and
the relevant build/static checks pass without introducing unrelated changes.
