# Phase 0 renderer handoff

**Checkpoint:** `d56850a` on `main` (pushed to `origin`, the fork `aacruzgon/CrystalOTC`)

**Date:** 2026-08-20

**Scope:** Phase 0 — GL bring-up on macOS, baselines, and test scenes

## Current state

The OpenGL client builds and runs on Apple Silicon through XQuartz. The repository has a
deterministic capture driver, an image comparator, a manifest that is now the single source
of truth for the scene list, and a Linux llvmpipe workflow with a real comparison gate.

All fifteen declared scenes are automated. (**Updated 2026-08-20, post-handoff:** sixteen, after `shader-matrix` was split into a gated fragment half and an ungated `shader-matrix-outfits`; see *Post-handoff cleanup* below.) `lighting-overlap` — the scene the previous
handoff recorded as having failed twice — is implemented and repeatable, driven by
server-authored world state. `shader-matrix`, `shader-matrix-map` and `windowing` were added
after the previous handoff; `windowing` is the only scene a headless runner cannot capture.

At this checkpoint:

- `ctest --test-dir build/macos-release --output-on-failure` passes all 22 tests.
- `luac -p` passes on `init.lua` and the capture driver.
- `python3 tools/renderer_scenes.py validate` exits 0.
- Every offline scene listed below was captured repeatedly and compared.
- The llvmpipe workflow runs green on GitHub. Its first run failed; the failure and all four
  warnings were diagnosed from the logs and fixed. Run `32381800862` compared six gated scenes
  at 0 differing pixels and `atlas-resources` at 158, inside tolerance.

## Phase 0 checklist

Against the implementation plan's Phase 0 tasks:

- [x] **XQuartz GL bring-up.** Client builds and runs on Apple Silicon; XQuartz 2.8.6, OpenGL 2.1, GLSL 1.20.
- [x] **CI software-GL reference.** Ubuntu container + Xvfb + Mesa llvmpipe, digest-pinned, green.
- [x] **Script the validation-matrix scenes.** All 15 scenes in `scenes.json` have a command. (16 after the post-handoff split.)
- [x] **Cover every surveyed edge.** Seven temp-FBO sites, map hole, `useFramebuffer` Outline, Fog/Snow multi-texture, UIGraph lines, atlas growth, map readback.
- [x] **Resolve `[D §12.4]`** — the `x/3, y/1.5` offsets are intentional framing; verdict recorded in the survey.
- [x] ~~Frame-time and memory baselines~~ — **deferred to Phase 3** (`AUTO_STAT` is compiled out; the client caps at 60 FPS, so a Phase 0 figure measures the cap and has nothing to compare against).

Against the exit gate:

- [x] The client runs on macOS via XQuartz.
- [x] A checked-in scene list (`scenes.json`, machine-readable, single source of truth).
- [x] A CI-generated reference-image set — all 7 seeded and gating green (run `32381800862`). (**Updated 2026-08-20:** 8 gated post-handoff, and all 8 have a committed reference — `shader-matrix`'s was seeded from run `32395555810` in `f037e42`.)
- [x] A known-deviations note, including the XQuartz-versus-llvmpipe comparison with evidence.

### Scenes

Repeatability is two or more consecutive captures compared with
`tools/compare_renderer_images.py`, out of 656,880 pixels unless noted.

| Scene | Impl | Where | CI | Repeatability |
|---|---|---|---|---|
| `startup-ui` | [x] | offline | gated | 0 px |
| `ui-clipping-opacity` | [x] | offline | gated | 0 px |
| `text-matrix` | [x] | offline | gated | 0 px |
| `particles-blends` | [x] | offline | gated | within tolerance, max delta 1 at this checkpoint; **re-measured 2026-08-20 as bimodal — 0 px within a mode, 540 px (max delta 252) between modes, and the high mode fails its own CI gate** — see known-deviations |
| `composition-all` | [x] | offline | gated | 0 px |
| `graph-lines` | [x] | offline | gated | 0 px |
| `atlas-resources` | [x] | offline | gated | 0 px |
| `outfit-masks` | [x] | offline | captured only | 0 px (was 520 before pinned `u_Time`) |
| `temporary-framebuffers` | [x] | offline | captured only | 0 px (was 449 before pinned `u_Time`) |
| `shader-matrix` | [x] | offline | gated (post-handoff) | 0 px |
| `shader-matrix-outfits` | [x] | offline | captured only (post-handoff) | 0 px |
| `windowing` | [x] | offline | not capturable | 0 px |
| `lighting-overlap` | [x] | online | — | 161 px (0.024%) at this checkpoint; **re-measured 2026-08-20 at 899/891/218 px pairwise** — see known-deviations |
| `map-screenshot` | [x] | online | — | 62 px of 168,960 (0.037%) |
| `map-core` | [x] | online | — | 16–765 px, tolerance 0.002 |
| `shader-matrix-map` | [x] | online | — | 778 px, tolerance 0.002 |

`captured only` means CI captures and archives the scene but does not compare it, because
`data/things/*` is gitignored so a runner renders creature and item previews empty. `not
capturable` means a headless runner cannot produce the scene at all. Both carry a reason in
the manifest.

### Supporting work

- [x] Comparator made gate-ready: alpha delta visible in diffs, distinct exit codes, no diff allocation when unused.
- [x] `tools/renderer_scenes.py` — manifest is the single source of truth; the scene list had been duplicated three times.
- [x] llvmpipe workflow fixed and green: four build blockers, autotools for `alsa`, a real comparison gate, concurrency, caches, environment fingerprint.
- [x] Server fixtures committed and pushed to `aacruzgon/crystalserver` (`f47f6e41`, branch `local/testing`).
- [x] Capture determinism: isolated write directory, pre-login window sizing, pinned `u_Time`, pinned login background, verified fixture arrival, crosshair suppression.
- [x] Design documents tracked and four contradicted claims corrected.
- [x] Windows release job gated off forks; the Windows build itself is the compile gate and passes.

## What changed since the previous handoff

### Capture determinism

Two consecutive `map-core` captures were measured differing in **62% of their pixels**, so
no online scene could have served as a baseline. Four independent causes were found and
fixed; see `docs/rendering-baselines/known-deviations.md` for the measurements.

- Capture runs now use their own write directory, reset before any setting is read. A
  capture previously inherited *and overwrote* the developer's real client configuration.
- The window is sized before login, because `game_interface.show()` derives the map panel
  geometry from the window size at game start.
- The FPS/ping HUD (drawn inside the map panel) and the re-opening enter-game window are
  neutralised after game start.
- `g_shaders.setFixedTime` pins `u_Time`. This also removed the last drift from two existing
  scenes: `outfit-masks` and `temporary-framebuffers` went from 520 and 449 differing pixels
  to **0**.

### The lighting question, resolved

The previous handoff correctly said not to repeat the client-side approach but did not know
why it failed. The cause is now established from source:

`ProtocolGame` forces world light and every creature light to 255/215 for any player whose
group carries `hasfulllight` (groups 4, 5, 6, 7). `LightView` sets `m_isDark = intensity <
250`, so with such a character **the entire LIGHT pool is skipped**. The baseline character
`GOD` is group 6. No client-side change could ever have made lights appear for it.

The scene therefore uses a **group-1 character on the same account** and an **underground**
platform, where `MapView::updateLight` substitutes `Light{0,215}` for the server's world
light — which also removes the day/night cycle, since this build has no Lua world-light
setter and seeds `lightHour` from the wall clock.

Item light is read from `appearances.dat` by both server and client and never travels on the
wire, so placing the item server-side is sufficient. Three stock torches give pure red,
green and cyan at equal brightness.

### Server fixtures

`crystalserver` gained `data-global/scripts/custom/renderer_fixtures/` (commit `f47f6e41`,
branch `local/testing`, pushed to `aacruzgon/crystalserver`): a startup GlobalEvent that
builds two platforms at coordinates the shipped map never touches, and a `!fixture`
talkaction usable by a group-1 character. No shipped file and no `.otbm` was edited; the map
is never written back.

The surface platform is at z=6, not z=7, because `calcLastVisibleFloor` clamps to the sea
floor and a hole cut in a z=7 platform would expose nothing.

### Tooling and CI

- `tools/renderer_scenes.py` makes `scenes.json` the single source of truth. The scene list
  had been duplicated three times in different orders.
- The comparator's diff image dropped the alpha delta, so an alpha-only regression failed the
  gate while producing an all-black diff. Latent today (all captures are opaque) but exactly
  the regression class a Metal backend introduces. Failures now carry distinct exit codes.
- The workflow had never executed. Four blockers would have hard-failed its first run, and a
  fifth (alsa's autotools requirement) was only visible once it did run.
- `outfit-masks`, `temporary-framebuffers` and - post-handoff - `shader-matrix-outfits` are
  captured but **not gated**: `data/things/*`
  is gitignored, so a CI runner renders them empty and gating would freeze a blank reference.

## Automated scenes

Offline, gated in CI: `startup-ui`, `ui-clipping-opacity`, `text-matrix`, `particles-blends`,
`composition-all`, `graph-lines`, `atlas-resources`, and — post-handoff — `shader-matrix`.

Offline, captured but not gated: `outfit-masks`, `temporary-framebuffers`, `shader-matrix-outfits`.

Offline, not capturable in CI: `windowing` — a desktop driver, not a headless capture.

Online, require the fixture server: `map-core`, `map-screenshot`, `lighting-overlap`,
`shader-matrix-map`.

## Remaining Phase 0 work

None. Every scene in `scenes.json` has a command, all seven gated scenes had a reference at this checkpoint (eight are gated post-handoff, and all eight now have one - `shader-matrix`'s was seeded from run `32395555810` in `f037e42`), and
the workflow gates them green: run `32381800862` compared six at exactly 0 differing pixels
and `atlas-resources` at 158, inside its tolerance.

The exit gate is met. What follows is deferred work that does not block it.

## Deferred follow-ups

Real issues found during Phase 0 that were deliberately not fixed in the phase itself. None
block the exit gate. Three were resolved in the post-handoff cleanup below and are struck
through; four remain deferred.

**Node 20 deprecation in `build-windows.yml`.** Its actions (`checkout`, `cache`,
`upload-artifact`, `download-artifact`) target the deprecated Node 20 runtime. GitHub
currently force-runs them on Node 24 with a warning, so it is cosmetic until it is not. The
bump was prepared and then deliberately reverted: it includes `actions/cache`, and changing
that ~~risks invalidating the warm vcpkg cache on a build whose median is around 60 minutes.
It deserves its own commit and a cold build to verify, not a ride-along on an unrelated
fix.~~ **Corrected 2026-08-21 (Phase 2, `11de064`):** there was no warm vcpkg cache to lose.
`lukka/run-vcpkg` set `VCPKG_BINARY_SOURCES=clear;x-gha,readwrite` and vcpkg has removed the
`x-gha` backend — `warning: The 'x-gha' binary caching backend has been removed` appears
verbatim in run `32440663105` — so nothing was cached and every run rebuilt every port
(~52 min of a 63-min job). `11de064` replaced the cached paths
(`vcpkg/installed`+`buildtrees` → `.cache/vcpkg`+`vcpkg/downloads`) and pointed both
variables at the workspace, as `build-macos.yml` and `render-baseline-linux.yml` already
did. The Node 20 bump is still deferred — it deserves its own commit — but not for the
cache reason.

The renderer-baseline workflow is already off Node 20~~, where there was no cache to lose~~. **Corrected 2026-08-21:** that contrast no longer holds in either direction — it is
on `actions/checkout@v5`, `actions/cache@v6` and `actions/upload-artifact@v7`, and it does
cache, through the same file-based `VCPKG_BINARY_SOURCES`/`VCPKG_DEFAULT_BINARY_CACHE` pair
that `11de064` gave the Windows job.

~~**`tests-lua.yml` tests nothing.**~~ **Resolved 2026-08-20 (post-handoff).** It now
syntax-checks every tracked `.lua` file with LuaJIT - the parser the client actually embeds -
and fails the job if the sweep ever checks zero files. `actions/checkout` is pinned by SHA.
Fixing it surfaced three genuine invalid escape sequences in
`tools/lua-binding-generator/generate_lua_bindings.lua` (`\*` and `\%`, neither a Lua escape),
which had made that file unloadable; they are fixed.

~~**`actions/labeler@main` is unpinned.**~~ **Resolved 2026-08-20 (post-handoff).** Pinned to
`v7.0.0` by SHA, and `.github/labeler.yml` migrated from the v4 schema to the v5-and-later
`changed-files`/`any-glob-to-any-file` form. The action had reached v7 while the config stayed
v4, so this was already broken rather than merely at risk.

**The container digest does not freeze Mesa.** The baseline job pins `ubuntu:24.04` by digest,
which freezes the base image, but Mesa is installed by `apt` at job time from the Ubuntu
archive, so a point release can shift llvmpipe rasterization without the digest moving. The
exact package versions are recorded in the reference set's `ENVIRONMENT.txt` so a drift is
diagnosable in one look. Fully pinning apt versions would break the job whenever Ubuntu
rotates a superseded version out of the archive.

**`XZ_SANDBOX` unused-variable warning** is emitted by the `liblzma` port at the pinned vcpkg
baseline, not by this repository. Silencing it means patching a port or moving the baseline.

~~**`shader-matrix` cannot be CI-gated as one scene.**~~ **Resolved 2026-08-20
(post-handoff).** The outfit row is now `shader-matrix-outfits` and `shader-matrix` is gated.
The fragment cells kept their exact coordinates through the split, verified against three
pre-split captures at 0 differing pixels in the `y < 482` band. The reasoning still applies to
`outfit-masks` and `temporary-framebuffers`, which remain gated off - splitting those would
mean removing their creature previews, which is the coverage, not an incidental cell.

**`map-screenshot` carries a 62-pixel residual** from one animated decoration.
`Thing:setAnimate(false)` stops a sprite advancing but leaves it on whatever phase it already
held, and that phase differs per run. Freezing at a *known* phase would need a binding that
does not exist.

## Post-handoff cleanup (2026-08-20)

Work done after checkpoint `d56850a`, before Phase 1 started. Three of the deferred follow-ups
above, plus the fixture-server pin, which was never on that list; the rest stay deferred with
their reasoning unchanged.

**`shader-matrix` split, and the fragment half gated.** The scene's six outfit cells moved to a
new `shader-matrix-outfits`; the sixteen fragment cells plus one unshaded control cell stayed
in `shader-matrix`, which is now CI-gated. Every fragment cell draws
`data/images/background_crystal1`, which is tracked, so the scene renders identically with or
without game assets. Both halves share one grid (`SHADER_GRID` in the capture driver) and the
fragment cells kept their exact coordinates: the `y < 482` band of a post-split capture is
**0 differing pixels** against three separate pre-split captures. Both scenes measure 0 px
across consecutive runs.

~~Its reference is not seeded yet. A gated scene with no reference is a GitHub *notice*, not a
failure, so the workflow stays green and reports `UNGATED-pending-reference` until the PNG from
the next green run is committed under `references/opengl-llvmpipe/`.~~ **Seeded 2026-08-20
(`f037e42`)** from run `32395555810`, the first run after the split: it compared the other seven
gated scenes at PASS - six at 0 differing pixels, `atlas-resources` at its documented 158 - and
reported this one as `UNGATED-pending-reference`, exactly as designed. All eight gated scenes now
have a committed reference, and `ENVIRONMENT.txt` fingerprints that run.

**The fixture-server dependency is pinned and machine-checked.** The four online scenes were
uncapturable without `crystalserver` scripts that exist only on a personal fork, and nothing in
this repository recorded that beyond prose. Now:

- `scenes.json` carries a `fixtureServer` block - repository, branch, full commit sha, script
  path, and the platform anchors - readable with `tools/renderer_scenes.py fixture`.
- The three fixture scripts are vendored byte-identically under
  `docs/rendering-baselines/fixture-server/`, with a README covering installation, the
  restart requirement and the per-scene character-group rule.
- `renderer_scenes.py validate` now fails if the vendored copy drifts from its recorded sha256
  digests, if a vendored `.lua` is unrecorded, if the manifest anchors disagree with
  `FIXTURE_ANCHORS` in the capture driver, or if an online scene does not name an existing
  anchor and declare its `requiresCharacterGroup`. All five failure modes were tested.
- The driver's timeout message used to say only `never reached fixture 'map' at ...`, which is
  identical across four genuinely different causes. It now names all four, leading with the
  likeliest: the server was not restarted after the scripts were installed.

**`tests-lua.yml` is a real gate.** It syntax-checks every tracked `.lua` file with LuaJIT -
the parser the client embeds, rather than PUC `lua5.1` - and fails if the sweep ever checks
zero files, which is the exact way it was previously vacuous. Writing it surfaced three
invalid escape sequences (`\*` and `\%`, neither a Lua escape) in
`tools/lua-binding-generator/generate_lua_bindings.lua` that had made that file unloadable;
they are fixed, and the sweep is clean.

**`actions/labeler` pinned and its config migrated.** Pinned to `v7.0.0` by SHA. The config was
still v4 schema against a `@main` reference that had reached v7, so it was already broken, not
merely at risk; it now uses the v5-and-later `changed-files`/`any-glob-to-any-file` form with
explicit `permissions`.

Deliberately still deferred: the Node 20 bump in `build-windows.yml` (~~it drags
`actions/cache` and needs a cold ~60-minute build to verify~~ — **corrected 2026-08-21:**
that reason is void, see the follow-up above; `11de064` has already rewritten the job's cache
paths, and the bump is deferred only because it deserves its own commit), Mesa version
pinning, the `XZ_SANDBOX` port warning, and `map-screenshot`'s 62-pixel
animated-decoration residual.

## Reproduction commands

```sh
cmake --preset macos-release -DTOGGLE_BIN_FOLDER=ON
cmake --build --preset macos-release --parallel 8
ctest --test-dir build/macos-release --output-on-failure
```

Offline scene:

```sh
DISPLAY=:0 build/macos-release/bin/otclient \
  --renderer-baseline=graph-lines --renderer-baseline-output=graph-lines.png
```

Online scenes. Note the character differs by scene — this is load-bearing, not incidental:

```sh
# map-core / map-screenshot: GOD (group 6). Its hasfulllight flag pins world light to 255,
# which disables the LIGHT pool and makes the surface immune to the day/night cycle.
DISPLAY=:0 CRYSTALOTC_BASELINE_ACCOUNT=@god CRYSTALOTC_BASELINE_PASSWORD=god \
CRYSTALOTC_BASELINE_CHARACTER=GOD \
build/macos-release/bin/otclient --renderer-baseline=map-core --renderer-baseline-output=map-core.png

# lighting-overlap: a group-1 character, or the LIGHT pool is skipped entirely.
DISPLAY=:0 CRYSTALOTC_BASELINE_ACCOUNT=@god CRYSTALOTC_BASELINE_PASSWORD=god \
CRYSTALOTC_BASELINE_CHARACTER="Sorcerer Sample" \
build/macos-release/bin/otclient --renderer-baseline=lighting-overlap --renderer-baseline-output=lighting-overlap.png
```

Captures land in the isolated baseline write directory, not the normal client one:
`~/Library/Application Support/crystalotc-baseline/.crystalotc-baseline/render-baselines/`.

Scene list and comparison:

```sh
python3 tools/renderer_scenes.py ids --offline
python3 tools/renderer_scenes.py ids --gated
python3 tools/compare_renderer_images.py reference.png candidate.png --diff diff.png
```

The server must be running for online scenes:

```sh
cd /Users/alancruz/Github/Tibia/crystalserver && ./build/macos-release/bin/crystalserver
```

Expected non-fatal local logs: missing `config.ini`, missing production soundbank, and
duplicate-library linker warnings.

## Commit ledger

Oldest first, regenerated from `git log --format='%h %s' --reverse 8194e58~1..HEAD` at
`f037e42` rather than appended to by hand. Everything after `d56850a` is post-handoff work:
the documentation-correction pass, the audit skill, and the cleanup batch. Note that the
sixteen originally subject-only messages were rewritten with full bodies, so every hash
below is new since the previous handoff.

```text
8194e58 fix(macos): bring up the XQuartz OpenGL client
1993a61 test(renderer): add deterministic baseline capture
bab2daf ci(renderer): archive llvmpipe startup baselines
47ad6ee fix(login): support the local 15.25 crystal server
af37763 test(renderer): capture the live map fixture
01e295e test(renderer): add deterministic UI fixtures
51cbff4 ci(renderer): capture deterministic UI matrix
bd66a9b test(renderer): add particle blend fixture
700a0f9 ci(renderer): capture particle blend baseline
bb8e117 test(renderer): add deterministic outfit fixture
f394a10 ci(renderer): capture outfit mask baseline
a60fd9b test(renderer): cover temporary framebuffer paths
c31e77f ci(renderer): capture temporary framebuffer baseline
c837b5a test(renderer): cover all composition modes
2381dbc ci(renderer): capture composition baseline
f99e738 test(renderer): automate map readback baseline
b751b93 test(renderer): add deterministic graph fixture
e759e87 ci(renderer): capture graph baseline
eb66c2b test(renderer): cover atlas resource lifecycle
c5b510b ci(renderer): capture atlas baseline
5f9ad3e test(renderer): suppress capture tooltips
bf9c28d docs(renderer): hand off phase zero progress
32cde60 refactor(login): collapse the duplicated devserver branch
d8f3f7a fix(renderer): make online baseline captures reproducible
d0cebb6 feat(graphics): allow pinning shader time for reproducible captures
497dc70 fix(renderer): make the baseline comparator and manifest gate-ready
942fe68 ci(renderer): make the llvmpipe baseline job runnable and gated
3b49ea5 test(renderer): implement the lighting-overlap scene
0045e14 ci(renderer): fix the first llvmpipe run's failures and warnings
09e9d2f docs(renderer): record phase zero determinism findings
42e5a5e test(renderer): capture the map scenes on the fixture platform
38200aa test(renderer): add the shader matrix scene
98a7f75 docs(renderer): correct two planning assumptions and record new scenes
f58286e docs(renderer): track the renderer design documents as authored
a35ca65 docs(renderer): correct four claims contradicted by the source
046991f ci(renderer): seed the canonical llvmpipe reference set
343e2a5 docs(renderer): record the first XQuartz versus llvmpipe comparison
16fc2c3 test(renderer): add the windowing multi-capture driver
8b0b550 fix(renderer): pin the randomized login background
261fefe test(renderer): add the map-composition shader scene
ba2383b fix(renderer): verify fixture arrival instead of assuming it
262a72a docs(renderer): record the windowing and map-shader scenes
65060b0 ci(windows): do not publish releases from a fork
6843c99 docs(renderer): record deferred follow-ups and restate what is left
4ba926a fix(renderer): do not report a missing shader as a capture failure
aa58b68 docs(renderer): add a Phase 0 completion checklist
87f0c32 docs(renderer): mark the server fixture commit as pushed
4976522 ci(renderer): correct the derived capture directory
09eb5d9 ci(renderer): reseed the startup-ui reference
d56850a docs(renderer): close out Phase 0
05d645f docs(renderer): correct stale claims left by Phase 0
ebf63c6 docs(skills): add a phase documentation audit skill
c71eda4 fix(tools): correct three invalid escape sequences in the binding generator
70b25a5 ci(lua): syntax-check every tracked Lua file with LuaJIT
c9bcd99 ci(labeler): pin actions/labeler and migrate the config to the v5 schema
cb6fe6a test(renderer): split the outfit cells out of the shader matrix
b621ef5 test(renderer): pin the fixture-server dependency and check it
4ed061f docs(renderer): record the post-handoff cleanup batch
f037e42 ci(renderer): seed the shader-matrix llvmpipe reference
```

## Repository hygiene at handoff

The working tree is clean and `main` is pushed to `origin`, the fork `aacruzgon/CrystalOTC`.

The four renderer design documents are tracked as of `f58286e`:

- `docs/macos-rendering-architecture.md`
- `docs/metal-implementation-plan.md`
- `docs/metal-parity-survey.md`
- `docs/renderer-architecture-design.md`

The four claims of theirs that the source contradicted were corrected in `a35ca65`. Among
them, `docs/renderer-architecture-design.md` §7 and §12.4 now record the
`glReadPixels(x/3, y/1.5)` offsets as **intentional framing**, not a bug, so the crop is
preserved deliberately rather than "not reproduced at the boundary".

Deliberately not in this repository:

- **The server fixtures.** They live in `crystalserver`, commit `f47f6e41` on branch
  `local/testing`, pushed to `aacruzgon/crystalserver`. No online scene runs without it.
  **Post-handoff:** the pin now lives in `scenes.json` under `fixtureServer` and the scripts
  are vendored read-only under `docs/rendering-baselines/fixture-server/`, enforced by
  `renderer_scenes.py validate`. The running server still has to come from that commit.
- **Sprite and appearance data.** `data/things/*` is gitignored, which is why `outfit-masks`,
  `temporary-framebuffers` and `shader-matrix-outfits` are captured but never gated
  (`shader-matrix` itself became gateable post-handoff by splitting the outfit cells out).
- **References for the ungated scenes.** Only the gated PNGs are checked in - seven at this
  checkpoint, eight since `f037e42` seeded `shader-matrix` - under
  `docs/rendering-baselines/references/opengl-llvmpipe/`, next to the `ENVIRONMENT.txt`
  fingerprint of the run that produced them.
