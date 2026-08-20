# Canonical llvmpipe references

Seeded from a green run of `Renderer baseline - Linux llvmpipe`
(run `32378720716`, commit `4976522`). `ENVIRONMENT.txt` is that run's
fingerprint; check it first when a comparison fails unexpectedly.

`startup-ui` was reseeded from that run. Its first reference came from an earlier
run and could never match again: the login background is chosen at random from
six images on every startup, and pinning it changed what the scene renders.

Only the scenes `tools/renderer_scenes.py ids --gated` reports are stored here.
`outfit-masks` and `temporary-framebuffers` are captured by CI but deliberately
not gated, so they have no reference; see their `ciGateReason` in `scenes.json`.

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
