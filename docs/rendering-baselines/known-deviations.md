# Known renderer deviations

## Windows Vulkan feeder versus OpenGL

These are current implementation gaps, not accepted Metal deviations:

- The LIGHT pool is consumed but not rendered.
- Painter/module shaders are ignored.
- Opaque OpenGL action lambdas are skipped.
- Framebuffer-derived textures without CPU pixels cannot enter the Vulkan atlas.
- Composition modes other than NORMAL and MULTIPLY fall back to NORMAL.
- Temporary framebuffers are flattened with an affine coordinate transform rather than represented as offscreen passes; clipping inside them is skipped.
- The foreground map hole is implemented by cutting previously emitted geometry, not by an alpha-zero blend-disabled draw into a retained target.

## XQuartz OpenGL versus llvmpipe OpenGL

The first local reference capture completed on 2026-08-19 with XQuartz 2.8.6 on an Apple M3 Pro. XQuartz reported OpenGL 2.1 (`2.1 Metal - 90.5`) and GLSL 1.20. The `startup-ui` scene rendered at 1020x644 with the expected login background, bitmap text, icons, translucent panels, clipping, and initial resize; no local rendering defect was observed.

The `ui-clipping-opacity` and `text-matrix` client fixtures were also captured twice on that setup. Each repeated capture was byte-equivalent at the decoded pixel level: 656,880 pixels compared, zero pixels different. Visual inspection found no clipping, alpha, alignment, TTF-stroke, or rotation defect.

The `particles-blends` fixture uses one fixed, single-burst particle for each composition mode used by live code: NORMAL, MULTIPLY, and the legacy ADD equation. Two settled captures had no pixels beyond the default per-channel tolerance; the maximum observed channel delta was 1. The ADD particle is intentionally smaller because its high-contrast center magnifies harmless one-channel raster rounding while still making the blend equation unmistakable.

The `outfit-masks` fixture freezes creature animation and captures mask recoloring, both addon layers, a mount, the creature-preview framebuffer, and the framebuffer-backed Outline shader. Outline deliberately retains its production `u_Time` brightness pulse. Two captures therefore differed in 520 pixels (0.0792%, below the 0.1% policy limit); the diff was confined to the outlined preview and is expected for this scene.

The `temporary-framebuffers` fixture covers every surveyed call site: creature preview, the nested Outline/ThingType path, item blits with both flip directions, effect and missile widgets, and spell-preview object compositing. Its animated outline probe is kept small enough for the whole-scene tolerance: the repeated XQuartz capture differed in 449 pixels (0.0684%), confined to the expected shader pulse.

The native `composition-all` fixture exercises all six painter descriptors, including the three with no production caller. Its ADD cell consistently exposes a faint image of startup UI retained in the FOREGROUND target, even though the fixture submits REPLACE clears for the target area and each destination cell. This is frozen as observed OpenGL behavior, not accepted as desirable renderer semantics. Two captures had no pixels beyond tolerance (maximum channel delta 2).

No XQuartz-versus-llvmpipe image has been compared yet, so no cross-environment pixel difference is accepted. Small rasterization and sampling differences may be accepted only after side-by-side evidence is attached here. XQuartz performance numbers are never compared directly with llvmpipe or native GPU numbers.

The client must link `libGL`, `libX11`, and `libXext` from the same XQuartz installation. Mixing XQuartz GL with Homebrew X11 links successfully but causes GLX visual selection to fail at runtime. The macOS CMake path now pins all four headers/libraries under `/opt/X11`.

The current checkout has no `config.ini` and omits the production soundbank, so the reference launch logs those two non-fatal missing-file errors. Neither affected the startup render; canonical scene metadata must retain them until deterministic fixtures provide those resources.

## Open questions

- The map screenshot currently calls `glReadPixels(x / 3, y / 1.5, ...)`. Phase 0 must capture and visually classify this as intended framing or a pre-existing bug before the backend-neutral readback request is frozen.
- XQuartz 2.8.6 requests a logout after installation so launchd can export `DISPLAY`. A same-session manual launch can still use `DISPLAY=:0`, but the documented post-logout flow remains the reproducible setup.
