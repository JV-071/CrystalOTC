# `particles-blends`: the bimodal ADD card

**Status:** open, unresolved. Six candidate mechanisms eliminated, two measured facts not yet
reconciled, and a well-posed question left to answer.
**Last worked:** 2026-08-25
**Companions:** `docs/rendering-baselines/known-deviations.md` (the catalogue entry that points
here), `docs/rendering-baselines/scenes.json` (the scene's gate settings)

This document exists so the next attempt starts from the evidence rather than re-deriving it. The
defect has now defeated six plausible explanations, three of them formed and tested on 2026-08-25,
and the one lesson that generalises is at the bottom: **every inference made ahead of measurement on
this defect has been wrong.**

---

## 1. The defect

`particles-blends` is a deterministic offline fixture. It draws three cards — NORMAL, MULTIPLY and
ADD (LEGACY) — each a checkerboard panel with one fixed, single-burst particle over it, exercising
the three composition modes live code uses.

It is **bimodal on a single binary**. Six consecutive captures split into two groups:

- within a group: **0 differing pixels**
- between groups: **exactly 540 of 656,880**, max channel delta 252
- confined to `x[797..822] y[311..336]` — a 26x26 region at the centre of the ADD card

The split is not fixed; which mode a run lands in varies. A representative six-capture run:

```
mode A = {1, 4}      mode B = {2, 3, 5, 6}
```

### Why it matters

The scene is **CI-gated at the manifest defaults** — `channelTolerance` 2,
`maxDifferentFraction` 0.001 — with no per-scene override. Measured against the committed llvmpipe
reference:

| mode | vs reference | fraction | gate |
|---|---:|---:|---|
| low (4 of 6 runs) | 168 px | 0.0256% | PASS |
| high (2 of 6 runs) | 698 px | **0.1063%** | **FAIL** |

So the scene can fail CI with no change to the client. It is parked while CI is suspended (Actions
minutes exhausted), but it will start crying wolf the moment CI returns.

It is a **capture-determinism defect in a test fixture**. Nothing a user sees is wrong.

---

## 2. Reproduction

Offline; no server needed. On the XQuartz/OpenGL binary:

```sh
for i in 1 2 3 4 5 6; do
  DISPLAY=:0 XAUTHORITY=~/.Xauthority build/macos-release/bin/otclient \
    --renderer-baseline=particles-blends --renderer-baseline-output=pb$i.png
done
```

Then compare all fifteen pairs with `tools/compare_renderer_images.py`. Two captures are not enough:
a pair lands in the same mode about half the time, which is exactly how the original Phase 0
measurement missed this entirely and recorded "maximum observed channel delta 1".

---

## 3. What the difference actually is

This is the part that took longest to get right, because the totals are misleading. Sampled values
at specific points, one capture from each mode:

| point | mode A | mode B | what it is |
|---|---|---|---|
| `(770,323)` | `(7,64,147)` | `(7,64,147)` | particle body — **identical** |
| `(790,323)` | `(7,64,147)` | `(7,64,147)` | particle body — **identical** |
| `(810,323)` | `(0,0,0)` | `(100,116,139)` | the disc centre |
| `(810,330)` | `(0,0,0)` | `(248,250,252)` | the disc centre |
| `(760,300)` | `(100,116,139)` | `(100,116,139)` | outside the disc — identical |

Three facts follow, and they are arithmetic rather than inference:

**The particle body is identical in both modes.** `(7,64,147)` is what the `#facc15` tint over a
`#64748b` tile gives through the ADD blend. The particle is drawn, correctly, in both.

**Mode A's disc is an opaque white fragment.** `CompositionMode::ADD` is
`glBlendFunc(ONE_MINUS_SRC_COLOR, ONE_MINUS_SRC_COLOR)`, i.e. `out = (1 - src) * (src + dst)`.
Getting `(0,0,0)` in *every* channel requires `src = (1,1,1)`, because `dst` there is a card tile and
is not zero. The `#facc15` tint has a maximum channel of 0.98 and **cannot produce that at any
alpha**.

**Mode B's disc is no fragment at all.** `(100,116,139)` and `(248,250,252)` are exactly `#64748b`
and `#f8fafc`, the card's own checkerboard tiles (`makeParticleCard`,
`modules/dev_renderer_baseline/dev_renderer_baseline.lua`). Seeing them raw requires `src = 0`.

`data/particles/particle2.png` is 32x32, white throughout, with a radial alpha ramp — 255 at the
centre, 124 a quarter of the way out, 6 at the edge. So `src = (1,1,1)` and `src = 0` are precisely
its **centre texel and its edge texel**.

> **The two modes sample different texels of the same texture.** They are not the same texel with a
> rounding difference, which is what every earlier reading assumed.

---

## 4. What it is NOT

Each of these was expected to work. Recording why, so nobody re-treads them.

### 4.1 A duplicated burst — eliminated 2026-08-20

`ParticleEmitter::update` computes `nextBurst = floor((elapsed - delay) * burstRate) + 1` and emits
only bursts in `[m_currentBurst, nextBurst)`. With `burst-rate: 1` that stays at 1 until a full
second has passed, and the emitter's `duration: 0.02` finishes it long before. Exactly one particle
is emitted at any frame rate.

Attractive because a second identical opaque particle is invisible under NORMAL and MULTIPLY and
glaring under `(1-src, 1-src)` — which matches the symptom exactly. It is not what happens.

### 4.2 A random size multiplier — eliminated 2026-08-20

`random_range` swaps its arguments when min > max, so a default of `(1, 0)` would have produced a
uniformly random multiplier in `[0,1]`. The default is `PointF pRandomSizeMultiplier{ 1 }`, and
`TPoint`'s single-argument constructor sets both components, giving `(1, 1)`.

Also, `size: 96 96` sets **both** `pStartSize` and `pFinalSize`
(`particletype.cpp`), so `m_size = m_startSize + (m_finalSize - m_startSize) / m_duration *
m_elapsedTime` is exactly constant. The particle does not change size with age.

### 4.3 Colour-interpolation rounding — eliminated 2026-08-25

`Particle::updateColor` runs `m_color = m_colors[0] * (1 - factor) + m_colors[1] * factor` every
frame even when both stops carry the identical colour, which every card here does. Both `operator*`
and `operator+` construct a new `Color`, so that expression rounds three times and its result
depends on `factor` — that is, on the particle's age at the instant the frame is drawn.

This looked like an exact fit: age-dependent, sub-LSB, and only amplified where a blend saturates.

**Test:** assign `m_colors[0]` directly when the two endpoints are equal. The branch is reachable —
`colors: #facc15ff #facc15ff` parses to two identical `Color`s and `operator==` compares hashes.
**Result:** six fresh captures still split into two modes at exactly 540 px. Reverted.

Corollary: the particle's colour is now *proven* constant across runs.

### 4.4 A sub-texel sampling offset — eliminated 2026-08-25

Hypothesis: an atlas region's coordinates are normalised against a 2048x2048 layer rather than a
32x32 texture, so magnified sampling lands fractionally differently.

**Test:** a uniform sub-texel shift would move every high-gradient pixel in the quad, especially at
the edges. **Result:** across the particle's 95x95 quad, **8,081 of 9,025 pixels are bit-identical**
between modes, and image-wide only **four** differing pixels lie outside the ADD card — two in each
of the NORMAL and MULTIPLY cards. The difference is sparse and localised, not a shift.

### 4.5 The 1:1 composite blit's filtering — eliminated 2026-08-25

`TextureAtlas::flush` copies a texture into its layer with `dest {x, y, w, h}` against
`src {0, 0, w, h}` — one to one, blending disabled — but samples it through the source's own LINEAR
filter, where no interpolation is needed and float error at texel centres could plausibly cost a
least-significant bit.

**Test:** force `GL_TEXTURE_MIN/MAG_FILTER` to `GL_NEAREST` around both composite draws.
**Result:** no change; six captures still split at exactly 540 px. Reverted.

### 4.6 The particle texture's atlas residency — eliminated 2026-08-25

Hypothesis: `DrawPool::add` translates a source rect into atlas coordinates only once a region
exists, so a texture is standalone for its first frames and atlas-backed afterwards. Whether the
shutter catches it before or after would give exactly two modes.

**Test:** keep `/particles/particle2` out of the atlas entirely (skip `allowAtlasCache()` for it)
while leaving the atlas fully on for everything else — so frame timing and pool hashing are
unchanged and only this texture's residency is fixed. The exclusion was **verified by log**
(`[probe] kept OUT of atlas: /particles/particle2`).
**Result:** still bimodal, at exactly 540 px. Reverted.

---

## 5. The two facts that do not reconcile

Both are measured, repeatedly, and they are the crux:

1. **Disabling the FOREGROUND atlas entirely makes the scene fully deterministic.** Setting
   `foregroundAtlasSize = -1` — the switch Vulkan already uses — gives six captures with **all
   fifteen pairs at 0 differing pixels**.
2. **Keeping the particle texture out of that atlas does not** (4.6 above). Same 540 px.

If the atlas mattered *through this texture's sampling*, (2) would have fixed it. If it did not
matter at all, (1) would not have. So the atlas is implicated through something other than the
particle texture's own residency — most likely frame timing or pool content hashing, since atlas
maintenance work varies frame to frame and the FOREGROUND pool is hash-gated with a 10 fps refresh
cap.

A note on (1): turning the atlas off also removes its maintenance work from the frame, so it is
**not** a clean isolation of sampling. It changes timing too. That is why it cannot by itself
establish a mechanism, only that the atlas is involved.

---

## 6. Next steps

In order. Do not skip to the fix.

1. **Instrument the draw, do not reason about it.** Log, for the ADD card's draw: the source rect,
   the resolved texture id, the transform-matrix id, and whether the handle resolved to an atlas
   region or a standalone texture. Capture several runs, and diff the log between a mode-A run and a
   mode-B run. This answers "which texels, and why" directly.
2. **Establish what the ~17px disc is.** It is much smaller than the 96x96 particle, and section 3
   shows it behaves as the texture's centre texel in one mode and its edge texel in the other. Is it
   the particle's own centre, or a separate draw on top of it? The instrumentation in step 1 should
   settle this; if it does not, count the draws submitted for that card.
3. **Reconcile section 5.** Once step 1 says what differs, check it against both facts. Any proposed
   mechanism must explain why excluding the texture from the atlas changes nothing while disabling
   the atlas fixes it.
4. **Only then choose a fix.** The options below are unchanged, but three of them are guesses until
   the above is done.

### Fix options, once the mechanism is known

- **Fix the determinism at its source.** Preferred: the scene keeps its default tolerance and the
  gate keeps meaning something.
- **Give the scene a `maxDifferentFraction` / `toleranceReason` override** wide enough for the high
  mode, the way `map-core` carries one for its creature.
- **Ungate it** (`ciGate: false`), with the reason recorded in the manifest.
- **Do not reseed the reference.** It picks a mode at random and leaves the other failing. This is
  the one option that is actively wrong, and it is the tempting one because it makes CI green.

---

## 7. The lesson worth carrying

Three of the six eliminations above were hypotheses formed on 2026-08-25 and killed the same day,
each of which looked like an exact fit for the evidence before it was tested. The pattern that
finally produced progress was not a better theory — it was **cropping the two captures and looking
at them**, which immediately showed a black disc against a white one and made every prior "tiny
difference amplified by ADD" reading untenable.

So: measure first, and prefer a measurement that can *falsify* the current story over one that can
only confirm it. On this defect specifically, an inference made ahead of measurement has been wrong
six times out of six.
