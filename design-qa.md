# Login Panel Design QA

- Source visual truth: user-provided official Tibia client login screenshot.
- Implementation evidence: Metal `startup-ui` and `login-logo-parity-final` renderer captures.
- Comparison method: the official and implementation logo/card regions were normalized to the same pixel dimensions for side-by-side inspection.
- Viewport: 1020 x 644 application content at device scale 1
- Source pixels: 3024 x 1964; the 560 x 616 logo-and-card crop was normalized to 280 x 308
- Implementation pixels: 1020 x 644; the 196 x 112 logo and 280 x 180 card render natively in a 280 x 308 comparison crop
- State: source has a remembered email and checked checkbox; implementation uses clean settings. Geometry was compared after normalization, and the checked/help state was verified interactively in the application.

## Full-view comparison evidence

The official and CrystalOTC full views retain their product-specific background art. Within the requested login scope, both place the official Tibia dragon logo above a centered compact card with the same title, field order, checkbox row, recovery action, separator, and paired bottom actions.

## Focused region comparison evidence

The normalized side-by-side comparison confirms the same 196 x 112 transparent logo asset, a matching 16-unit logo-to-card gap, matching 280 x 180 card geometry, and matching internal anchors. The official client crop is on the left and the implementation crop is on the right. A separate smaller focus crop was unnecessary because the logo and every card control are legible in the normalized comparison.

## Findings

No actionable P0, P1, or P2 visual differences remain in the requested login-card scope.

- Fonts and typography: the existing CipSoft/Verdana styles, weights, sizes, title treatment, underline, and label hierarchy match the reference.
- Spacing and layout rhythm: logo size and offset, card dimensions, field spacing, checkbox position, recovery-link position, separator, and bottom action alignment match.
- Colors and visual tokens: existing popup texture, borders, greys, and white action text match the official client style.
- Image quality and asset fidelity: the exact official `client-dragon-logo-regular.png` resource is used at its native 196 x 112 size alongside the existing popup-window, checkbox, eye, and help assets.
- Copy and content: all visible official labels and actions are present with matching copy.

## Comparison history

1. Initial implementation: P1 — the extra `Remember Password` row made the card 280 x 198 instead of 280 x 180. P1 — recovery and account-creation actions were hidden when service URLs were absent.
2. Fixes: removed the password-persistence row and logic, restored the 280 x 180 default, re-anchored recovery under `Remember Email`, and kept both official actions visible with safe unconfigured-service feedback.
3. Post-fix evidence: the clean-start Metal capture loaded without UI errors; the normalized card comparison shows matching structure and rhythm. `Remember Email`, `Create New Account`, and account recovery were exercised in the running client.
4. Logo follow-up: P1 — the official standalone Tibia dragon logo was absent. The original transparent resource was extracted from the locally installed official client's `graphics_resources.rcc`, added without raster modification, and positioned 16 units above the card. The post-fix normalized comparison confirms matching size and placement.

## Interaction and runtime checks

- `Remember Email`: toggles its checked state and help indicator.
- `Create New Account`: invokes the configured flow when available; otherwise shows a safe explanatory dialog.
- `Forgot password and/or email`: opens the configured URL when available; otherwise shows a safe explanatory dialog.
- Startup capture completed successfully with no login-module parse or runtime errors.

## Follow-up polish

No scoped P3 items remain.

final result: passed
