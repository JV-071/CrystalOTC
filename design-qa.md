# Ultia official 15.3x UI parity design QA

- Source visual truth: user-provided official Tibia login screenshot at `/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_DdYTwO/Screenshot 2026-08-24 at 11.33.54 AM.png`.
- Privacy-safe source derivative: `artifacts/ui-parity/login-final/official-full-redacted.png`.
- Rendered implementation: `artifacts/ui-parity/login-final/ultia-final.jpeg`, captured from the rebuilt native Metal `Ultia.app`.
- Source pixels: 3024 x 1964 at Retina density 2, representing a 1512 x 982 macOS screen including the menu bar.
- Implementation viewport: the same 1512-point-wide macOS display and maximized app state; Computer Use supplied a 1224 x 768 downsample of the app window for privacy-safe visual QA.
- State: offline login, official background, centered product title, top social/status bar, login form, CipSoft mark, bottom information bar, and both music toggle states.

## Full-view comparison evidence

`artifacts/ui-parity/login-final/full-side-by-side.png` places the official client on the left and Ultia on the right in one normalized comparison image. The official remembered email was redacted before comparison. The source and implementation use the same title artwork, preserve-aspect crop, dragon logo, fixed login-card geometry, CipSoft mark, top shell, and 117-pixel bottom bar.

The differing product title (`Tibia` versus the user-requested `Ultia`), live social/player counts, remembered-email state, hint copy, schedule entries, and boosted-creature content are intentional or volatile content differences rather than design drift.

## Focused comparison evidence

- `artifacts/ui-parity/login-final/login-side-by-side.png`: normalized logo and 280-pixel login-card region. Frame dimensions, input geometry, Verdana roles, button rhythm, and solid recovery-link underline match the source.
- `artifacts/ui-parity/login-final/topbar-stacked.png`: official shell above, Ultia below. Social icons, player icon, account/client buttons, music, options, and logout assets retain the official proportions and spacing.
- `artifacts/ui-parity/login-final/mute-state-comparison.png`: normal music state on the left and persistent checked/pressed state on the right after the pointer moved away. The original music setting was restored afterward.

## Findings

No actionable P0, P1, or P2 differences remain in the implemented login, character-selection, and offline-shell scope.

- Fonts and typography: the UI uses the bundled Verdana roles derived from the official QML. Labels, fields, captions, buttons, and recovery-link weight/spacing follow the source; the recovery link now uses a continuous one-pixel underline rather than a dashed bitmap-font artifact.
- Spacing and layout rhythm: the centered card/logo group, topbar insets, fixed dialog sizes, 117-pixel bottom bar, and CipSoft mark-to-bottom-bar anchor match the official layout. The product title is centered in native macOS chrome.
- Colors and visual tokens: the CAMetalLayer now declares sRGB presentation while retaining legacy raw-byte blending. The wallpaper, dragon mark, and UI textures no longer appear dull relative to the color-managed official client.
- Image quality and asset fidelity: all 1,063 extracted `graphics_resources.rcc` files are exposed at their official virtual paths and verify byte-for-byte. Twelve superseded runtime files are retained under `data/old-assets`. The title background uses the sole documented format bridge, a PNG whose decoded pixels compare to the official JPEG with ImageMagick RMSE 0.
- Copy and content: visible fixed labels and actions match the official client. `Ultia` is the requested product rename; volatile network and promotion content is intentionally not fixture-matched.

## Comparison history

1. Login and character-selection passes corrected card geometry, official title art, dragon mark, free-account details, character-table columns, quick-loot clipping, and Verdana role mapping.
2. Top-shell pass replaced approximate icon overlays with the exact official options/logout assets, made music a persistent checked toggle, removed the non-official terminal button, and corrected the recovery-link underline.
3. Color pass added the missing sRGB presentation color space to the native Metal layer, bringing wallpaper and logo luminance in line with the official Qt client.
4. Asset migration exposed all 1,063 extracted RCC resources at runtime. The initial direct `/images/title.jpg` use revealed OTClient's JPEG decode limitation and left the transient startup box over black; restoring the pixel-equivalent official PNG derivative fixed both the background and the stale `Loading game files` pixels.
5. Final side-by-side review found the missing official CipSoft mark. The exact 163 x 44 asset was added at the QML-derived anchor directly above the 117-pixel bottom bar, and the revised capture passed.

## Interaction and runtime checks

- The native macOS bundle builds as `build/macos-cocoa/bin/Ultia.app/Contents/MacOS/Ultia` and is running with a centered `Ultia` window title.
- A real UI click verified that the music control remains visibly checked/pressed after hover ends; a second click restored its original state.
- The corrected clean launch settles on the login screen without retaining the `Loading game files` dialog.
- Modified Lua files pass `luac -p`; Python parity tools pass `py_compile`; `git diff --check` passes.
- The migration dry run reports 1,063 identical official resources, zero missing resources, and zero differing resources.

## Follow-up polish

No scoped P3 visual item remains. Additional online, premium-account, empty-character, error, disabled, and focus variants should receive their own same-state screenshots when those states are implemented.

## Main game shell: initial geometry pass

Two new official 15.32 captures were supplied at 3024 x 1964 pixels on the
same 1512 x 982 Retina display. After removing the 21-point black system band,
the official client content is 1512 x 961 logical pixels. The empty-widget
capture establishes these rendered shell measurements:

- one right sidebar from x=1336 through x=1511: 176 logical pixels;
- top status-bar dock: 87 logical pixels;
- upper map pane: 714 logical pixels;
- split divider: 7 logical pixels;
- lower action/chat pane: 153 logical pixels;
- map content: 960 x 704 logical pixels, exactly 2x the native 480 x 352
  viewport, inside the one-pixel down-frame and four-pixel pane margin.

The first Ultia pass now uses the official 176-pixel sidebar width, 90-pixel
chat minimum, 650-pixel client minimum height, four-pixel map margin, and exact
root RCC paths for the light/dark tiled backgrounds, two-pixel frame, and
horizontal divider. The non-official horizontal miniwindow shelves remain
available but default off, and the official-compatible default now starts with
one right sidebar and no left sidebar.

Runtime QA used the local fixture server and reproduced the source shell state:
one right sidebar, no horizontal shelves, top status bar in Default style with
experience and magic level, one bottom action-bar configuration, and chat
visible. `artifacts/ui-parity/shell-initial/side-by-side.png` is the broad
review image. The Ultia half is a 1224 x 768 Computer Use normalization, so this
checkpoint is suitable for composition review but not final per-pixel metrics.

The master map/sidebar/action/chat composition is now closely aligned. This is
an in-progress checkpoint rather than acceptance: fixed sidebar components,
status-bar pixels, action bars, chat primitives, and miniwindow frames still
need component-level passes and same-state captures.

The macOS native cursor path now recognizes the official horizontal cursor
sprite sheets (for example the eight-frame 256 x 32 walk cursor), creates one
32 x 32 `NSCursor` per frame, and advances the active frame at the source
100 ms cadence. Re-selecting the same cursor while crossing map tile boundaries
preserves its phase instead of continually restarting the animation. Static
cursors and APNG cursor inputs continue through the same loader.

final result for login, character-selection, and offline-shell scope: passed
main game shell result: in progress

## Main game shell: fixed upper-right sidebar pass

- Source visual truth: the user-provided official Tibia 15.32 closed-panel
  screenshot at `/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_DskzMd/Screenshot 2026-08-24 at 3.48.07 PM.png`.
- Source derivative: `artifacts/ui-parity/sidebar-pass/official-closed-upper.png`,
  a 176 x 390 logical-pixel crop beginning at the official sidebar origin
  x=1336.
- Rendered implementation: `artifacts/ui-parity/sidebar-pass/ultia-final.jpeg`,
  captured from the rebuilt native Metal client in the same closed-lower-panel
  state.
- Normalized implementation crop:
  `artifacts/ui-parity/sidebar-pass/ultia-final-upper.png`, normalized from the
  1224 x 768 Computer Use capture to the source crop's 176 x 390 dimensions.
- State: online local fixture character; sidebar hitpoints/mana row hidden;
  inventory expanded; Store normal and unhighlighted; control row expanded;
  only Skills, Battle List, and Spell List displayed; Helper Stats and all
  lower miniwindows closed.

### Comparison evidence

`artifacts/ui-parity/sidebar-pass/final-upper-side-by-side.png` places the
official fixed sidebar block on the left and the normalized Ultia block on the
right. The 108 x 111 minimap viewport, rose/layer controls, 142-pixel equipment
grid, status strip, Stop button, Store row, 6-logical-pixel Store-to-shortcut gap,
three-button shortcut row, and Options/Logout column align by row and column.

The map pixels, equipment objects, soul/capacity values, player-condition
icons, clock position, and minimap rose lighting are live data and intentionally
differ between the official account and the local fixture character. The
Computer Use implementation capture is downsampled, so it is suitable for
component geometry and composition QA rather than source-resolution color
error metrics.

`artifacts/ui-parity/sidebar-pass/helper-stats-available.jpeg` records the
Shortcuts manager after the custom Helper Stats control was removed from the
fixed special column and from the displayed defaults. Helper Stats remains in
Available Shortcuts and can be added or removed by the user like every other
managed shortcut.

### Findings and changes

No actionable P0, P1, or P2 differences remain in the fixed upper-right
sidebar scope.

- The redundant compact hitpoints/mana sidebar panel now defaults off when the
  official top status dock is active; the option remains available.
- The equipment grid now follows the recovered `inventory.qml` rhythm: three
  34-pixel columns separated by three pixels, two-pixel vertical slot spacing,
  and the official soul/capacity row alignment.
- The normal Store state no longer renders unwired highlight, animation, New,
  or Sale overlays. Its control row begins at the official vertical offset and
  the expanded button uses the matching down-arrow state.
- The official-compatible shortcut default is Skills, Battle List, and Spell
  List. Helper Stats is a managed optional shortcut rather than permanent
  special-column chrome; Options and Logout remain fixed on the right.
- The user confirmed that the separately corrected official walk cursor strip
  now animates smoothly.

### Runtime checks

- The rebuilt client completed a clean logout/restart and returned online to
  the local Crystal fixture server.
- Helper Stats was visibly moved between Displayed Shortcuts and Available
  Shortcuts, then left available with the three official default shortcuts
  displayed.
- All 67 CTest cases pass. Modified Lua files pass `luac -p`, `git diff
  --check` passes, and the official asset migration remains 1,063 identical,
  zero missing, zero replaced.

final result for fixed upper-right sidebar scope: passed
main game shell result: in progress

## Main game shell: full-screen sidebar correction and splitter feedback

The fixed-sidebar measurements were repeated from the two complete 3024 x
1964 Retina captures, rather than from close-ups with unrelated crop origins:

- official source: `/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_Dmw6vd/Screenshot 2026-08-24 at 4.56.55 PM.png`;
- pre-correction Ultia source: `/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_2PIdb8/Screenshot 2026-08-24 at 4.57.06 PM.png`.

The shared minimap-frame corner establishes an 8-backing-pixel, or
4-logical-pixel, vertical offset in Ultia. The minimize and blessing buttons
already had the same 115-logical-pixel position relative to their respective
minimap frames, so their internal inventory geometry was restored to the
official 161-pixel total and the complete fixed/lower right-sidebar stack was
moved upward by four logical pixels. The blessing button's OTUI left margin is
three because the engine's right-anchor resolution renders the official
two-pixel inter-button gap from that value. The green full-blessing state is
fed by the protocol's icon color, with a blessing-status fallback for servers
that do not provide the color.

The official splitter-feedback source is the 3024 x 1964 capture at
`/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_YN8Yyg/Screenshot 2026-08-24 at 5.15.36 PM.png`.
Recovered `GamewindowSplitView.qml` specifies a 60 x 22 percentage frame,
seven-pixel splitter spacer, and 31 x 31 resize-mode wrapper centered on the
pointer. Ultia now reproduces that structure with the exact official
background, frame, divider, and three resize-mode icons. The value is computed
from the fitted visible-world-map width divided by the native 480-pixel map
width, matching the official QML formula. The first implementation sampled the
internal render rectangle, which remained at 480 pixels while Retina output was
scaled and therefore left the label stuck at 100%; the user-provided full-screen
capture exposed that P1 mismatch. Runtime diagnosis then found the nested label,
button, and icon had been queried with a direct-child lookup from the root, so
the missing label reference made every update return early. The lookups are now
recursive and the percentage source uses the fitted visible width.

The user clarified that 200% is the official gameplay maximum. Ultia therefore
caps both the splitter's real map rectangle and its pixel-exact stops at the
960 x 704 logical viewport represented by 200%; the label clamp is only a
defensive final guard. The overlay remains visible while the splitter or its
mode button is active and uses the official 500 ms departure delay.

`artifacts/ui-parity/splitter-feedback/source-implementation-comparison.png`
places the official 200% source state beside the pre-fix Ultia 100% runtime
state at the same logical component scale. The post-fix comparison at
`artifacts/ui-parity/splitter-feedback/source-implementation-postfix.png`
places the official component beside Ultia dynamically reporting 97%. This
proves the update path, frame, typography, spacing, and icon composition. The
later full-resolution 200% user capture closes the exact maximum-state check.

### Runtime checks

- The rebuilt online client centered the feedback on the pointer, retained
  splitter input through the phantom label area, and exposed the official
  resize-map icon.
- After correcting the nested-widget lookup, the same rebuilt online client
  dynamically displayed `97%` at a smaller non-native map size instead of the
  static OTUI default. The evidence is
  `artifacts/ui-parity/splitter-feedback/ultia-dynamic-97-postfix.png`.
- The next full-screen user capture reached the maximum splitter position but
  reported `199%`. This was not caused by the 90-pixel chat minimum: the cap
  calculation omitted UIMap's one-pixel inset on the top and bottom, leaving
  the fitted map one step short. The cap now includes that two-pixel inset so
  the maximum map rectangle is exactly 960 x 704. Pre-fix evidence is
  `artifacts/ui-parity/splitter-feedback/ultia-max-199-prefinal.png`.
- The full-resolution post-fix capture supplied at 18:35 shows the overlay at
  exactly `200%` with the map at its maximum and the chat at its minimum. This
  closes the two-pixel inset blocker and confirms that the 200% limit is real,
  not merely a clamped label. Durable evidence is
  `artifacts/ui-parity/splitter-feedback/ultia-max-200-final.png`.
- The chat output now uses the existing `Verdana Bold-11px` raster instead of
  the lighter 13-pixel `-new` variant. A normalized full-resolution crop beside
  the official source at
  `artifacts/ui-parity/splitter-feedback/chat-font-200-comparison.png` shows
  matching glyph height and line cadence; future chat work should preserve the
  official saturated per-message colors.
- All 67 CTest cases pass. Modified Lua files pass `luac -p`; `git diff
  --check` passes.

final result for full-screen sidebar source measurement and splitter feedback:
passed

## Sidebar miniwindow free-space curtain

The former implementation appended a variable-height `sidebarFreeSpace`
widget after the sidebar miniwindows. Resizing Backpack therefore moved that
widget's top edge and made the grey area look as though it was being pushed up
or down. The official behavior keeps the side-panel texture fixed and reveals
or covers it behind the resized miniwindow.

`UIMiniWindowContainer` now bottom-aligns the existing parent frame texture and
removes the redundant filler child. Window sizing, ordering, clipping, drop
targets, and overflow fitting remain owned by the existing sidebar container;
only the free-space paint layer changed. The user verified the Backpack resize
interaction and confirmed that the curtain behavior now matches the source.

All 67 CTest cases pass. The modified Lua files pass `luac -p`, and `git diff
--check` passes.

## Right-rail origin and inventory-content alignment

The final alignment pass used the complete 3024 x 1964 Retina captures, with
the focused crops serving only as semantic references:

- official source: `/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_Egy99W/Screenshot 2026-08-24 at 7.03.13 PM.png`;
- pre-correction Ultia source: `/var/folders/h0/b63p3q_54c56l3yqml5pxddm0000gn/T/TemporaryItems/NSIRD_screencaptureui_EG7lAU/Screenshot 2026-08-24 at 7.03.18 PM.png`;
- normalized comparison: `artifacts/ui-parity/inventory-spacing/fullscreen-1903-comparison-before.png`.

Direct matching against the native two-times-scaled UI resources placed the
official minimize button at backing-pixel row 304 and Ultia's at row 296. The
entire right rail therefore started eight Retina pixels, or four logical
pixels, too high. `gameRightTopPanel` now owns that four-pixel top margin so
the minimap, its surrounding controls, and every panel anchored below it move
as one rail.

The same measurement placed the official Store Inbox button at row 304 and
Ultia's at row 288. Once the shared rail correction accounted for eight of
those backing pixels, the equipment roots and Store Inbox button still needed
four logical pixels of internal movement. The amulet and helmet roots now
carry that offset; all dependent equipment rows, Soul/Capacity panels, and the
Store Inbox button follow automatically. The minimize and blessing buttons
were deliberately left unchanged inside the inventory panel.

The user verified the restarted client and confirmed the corrected result.
All 67 CTest cases pass and `git diff --check` passes.

final result: passed

## Cyclopedia map mode, Navigation panel, and sidebar upper-pane frame

The official-client extraction was used as the implementation source rather
than inferring this state from the screenshots alone. In
`CyclopediaMapDialog.qml`, Surface View selects the Satellite renderer while
Map View selects the palette minimap renderer. The red street-outline view in
the earlier Ultia capture was therefore a valid official mode, but it was the
wrong default for the source state. Ultia now opens the textured Surface View
by default, migrates the previous default once, and continues to persist an
explicit user selection of Map View.

The same official QML defines the expanded Navigation panel as Current area
headline/help, current area name, day/night rose, map-layer selector, and zoom
controls. Ultia now restores that structure and resolves the displayed area
from the local player's map position. The Cyclopedia rose consumes the same
live world-time state as the rose above inventory, both when the dialog opens
and on every subsequent world-time update.

Visual evidence:

- official reference: `artifacts/ui-parity/cyclopedia-map/official.png`;
- pre-fix Ultia palette-map state:
  `artifacts/ui-parity/cyclopedia-map/ultia-before.png`;
- post-fix textured Surface View and complete Navigation panel:
  `artifacts/ui-parity/cyclopedia-map/ultia-surface-navigation-after.png`.

The official `sidebar.qml` encloses the entire upper pane in one
`TibiaFrame2PixelUpFilled`; inventory is a child of that framed pane rather
than owning a separate bottom border asset. A trial reduction of Ultia's
three-pixel upper-pane frame allowance removed the bottom edge, so that change
was reverted. The current restarted build again shows the enclosing frame in
`artifacts/ui-parity/inventory-collapse/ultia-after-restored.jpeg`. No
replacement inventory-border bitmap is required.

The modified Lua files pass `luac -p`, all 67 CTest cases pass, and `git diff
--check` passes.

final result: passed
