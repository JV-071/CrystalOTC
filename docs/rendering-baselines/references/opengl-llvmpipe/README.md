# Canonical llvmpipe references

Seeded from three green runs of `Renderer baseline - Linux llvmpipe`. Six of the
references come from run `32369322871` (commit `0045e145`) and have not been
touched since: `atlas-resources`, `composition-all`, `graph-lines`,
`particles-blends`, `text-matrix` and `ui-clipping-opacity`.

`startup-ui` came later, from run `32378720716` (commit `4976522`). Its first
reference, seeded from the same earlier run as the other six, could never match
again: the login background is chosen at random from six images on every
startup, and pinning it changed what the scene renders.

`ENVIRONMENT.txt` is the newest contributing run's fingerprint (`32395555810`,
commit `4ed061ff`); check it first when a comparison fails unexpectedly. It
describes every set here: all three runs used the same container digest and the
same Mesa packages, and each later run compared the earlier references at 0
differing pixels - except `atlas-resources`, which sits at its documented 158.

Only the scenes `tools/renderer_scenes.py ids --gated` reports are stored here.
`outfit-masks`, `temporary-framebuffers` and `shader-matrix-outfits` are captured
by CI but deliberately not gated, so they have no reference; see their
`ciGateReason` in `scenes.json`.

`shader-matrix` became gated on 2026-08-20, when its six outfit cells were split
out into `shader-matrix-outfits` so the sixteen fragment cells no longer depended
on gitignored `data/things/*`. Its reference comes from run `32395555810`
(commit `4ed061ff`), the first run after the split, which compared the other
seven at PASS and reported this one as `UNGATED-pending-reference`.

**Reseeded 2026-08-21** from run `32525617431` (commit `a2180b31`), a deliberate
refresh dispatched with `refresh_references: true`.

The cause was `19e29e3`, which fixed `rain.frag`: it read an uninitialised `vec2 p`
inside the expression that first assigns it, so its output was undefined by
construction and every compiler was free to draw different rain. Defining it
changes what the shader draws on **every** backend.

The refresh was verified to be exactly that change and nothing else, which is what
makes it a legitimate reseed rather than a way of making a failure go away:

- Against the previous reference, the new one differs by **1,461 px, all of them
  inside the Rain cell**, and by 0 px in every one of the other sixteen cells and
  outside the grid entirely. (Locally on XQuartz the same fix measured 2,032 px -
  the two GL stacks rasterise the rain differently, as this scene's other
  cross-stack caveats would predict.)
- The other seven gated references produced by the same run are byte-identical to
  the committed ones, except `particles-blends` at its documented 626 px. So the
  container and Mesa did not drift underneath the refresh.

`forge_result_silhouette` was re-verified against this new reference, as the note
below requires: its **image area** is still pixel-identical to the neighbouring
`no shader` control (0 differing pixels over the 136x92 image rect). Compare image
areas rather than whole cells - the cells carry different text labels, which
differ by construction and account for ~800 px on their own.

One cell in `shader-matrix`, `forge_result_silhouette`, renders **unshaded** in CI: the shader
is registered by `game_exaltationforge`, and that module fails to load without
game assets, so the client logs `shader unavailable in this environment` and the
cell draws the plain image. Verified against this reference: that cell is
pixel-identical to the neighbouring `no shader` control. It is deterministic and
gates fine, but it means the shader itself is only exercised locally, and a local
XQuartz capture of this scene will always differ from this reference in that one
cell - locally the shader draws a black silhouette.

## These are CI references, not universal ones

Compare same-environment only. A local XQuartz capture will not match these and
is not expected to. Two differences are structural, not defects:

- **`data/things/*` is gitignored**, so the CI client has no game assets. The
  `startup-ui` reference therefore contains an "Unable to load ... Tibia.dat /
  Tibia.spr" dialog in front of the login window. It is stable and still
  exercises fonts, translucent panels and clipping, but it is an artifact of the
  environment. Adding assets to CI would legitimately invalidate this reference.
- Mesa's llvmpipe is the reference rasterizer, and its output is what these PNGs
  freeze.

## The container digest does not fully freeze Mesa

The job pins `ubuntu:24.04` by digest, which freezes the *base image*. Mesa is
installed with `apt-get` at job time from the Ubuntu archive, so a Mesa point
release can still change llvmpipe rasterization without the digest moving. That
is why `ENVIRONMENT.txt` records the exact package versions
(`libgl1-mesa-dri`, `libglew-dev`, ...) alongside the digest.

Pinning the apt versions too would freeze it completely, at the cost of breaking
the job whenever Ubuntu rotates a superseded version out of the archive. The
current trade is: do not pin, but record enough to diagnose a drift in one look.

## Refreshing

Run the workflow with `workflow_dispatch` and `refresh_references: true`, which
skips the comparison, then copy the captures out of the run artifact and commit
them with the reason in the message. Treat a container digest bump or a Mesa
version change as a deliberate refresh event, never as a routine update.
