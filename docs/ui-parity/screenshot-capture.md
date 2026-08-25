# Official-client screenshot capture

The recovered QML now provides layout rules, constants, asset paths, and
control states. Screenshots are needed now to establish rendered geometry,
Retina/font behavior, and the exact state of dynamic docks.

## Capture requirements

- Use official client `15.32.bf29ac`, matching the extracted snapshot.
- Capture PNG without resizing, recompression, annotation, or manual cropping.
- Keep the full client content visible. Window chrome may remain; it can be
  removed deterministically later.
- Record both the PNG pixel dimensions and the client window's logical size.
- Record the macOS display scale (1x or 2x). A 1512x921-point Retina window may
  produce a 3024x1842-pixel capture.
- Keep the same character, location, chat messages, equipment, open container,
  and action assignments across the pack where possible.
- Stand still on a visually quiet tile and avoid active effects, animated
  overlays, menus, tooltips, notifications, and private messages.
- Use a disposable/test character or obscure private names before sharing.
- Do not include `clientoptions.json`; it contains device/account state.

Put files under `docs/ui-parity/captures/official/` using the scenario IDs
below, or attach the original PNGs in the conversation with those IDs.

## Initial capture pack

Use a 1512x921 logical-point client window for all six images if possible. If
the official client is currently borderless/maximized at that size, keep that
state rather than introducing window-frame differences.

1. `shell-default.png`

   Full in-game client. One right sidebar; fixed minimap/inventory/status/button
   panels visible; one open container and VIP or battle widget; chat visible;
   one bottom action bar visible; left/right action bars hidden.

2. `shell-empty-widgets.png`

   Same state, but close lower sidebar widgets while keeping the fixed upper
   sidebar panel. This isolates map, sidebar, chat, and outer-frame geometry.

3. `shell-multi-sidebar.png`

   Open one left sidebar and two right sidebars. Put at least one widget in each
   column. Keep the bottom pane and action-bar configuration unchanged.

4. `actionbars-all.png`

   Show all three bottom, all three left, and all three right action bars, plus
   the cooldown bar. Populate enough slots to expose item, spell, text, empty,
   cooldown, and disabled/unusable visual states.

5. `widget-states.png`

   In one or more sidebars show an expanded container, expanded battle/VIP
   widget, and a minimized widget simultaneously. Include a widget scrollbar
   and resize handle if available.

6. `chat-focused.png`

   Keep the full client visible. Focus the chat input, open at least three tabs,
   select the middle tab, and include enough lines to show the chat scrollbar.
   Do not expose private conversation content.

After the shell converges, capture options/dialog/component states only for the
next feature being implemented. There is no need to produce every official
dialog up front.

## Metadata template

Create a small `capture-metadata.json` beside the images:

```json
{
  "official_client_version": "15.32.bf29ac",
  "window_logical_points": [1512, 921],
  "capture_pixels": [3024, 1842],
  "display_scale": 2,
  "borderless": true,
  "maximized": true,
  "macos_display_mode": "Built-in Retina Display",
  "notes": "Same character/location and UI state across capture pack"
}
```

If `capture_pixels` is 1512x921, use `display_scale: 1`. Do not upscale it.
