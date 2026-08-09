# CrystalOTC

A game client for the CrystalOTC server (protocol 15.30), built on the
[OTClient - Redemption](https://github.com/mehah/otclient) engine with a set of
in-house extensions:

- **Custom Vulkan renderer** - atlas-batched sprite pipeline: one 2D-array atlas,
  content-hash deduplication, chunked storage for oversized textures, and a
  MAILBOX-first presentation mode (uncapped FPS without tearing). The client can
  start in pure-Vulkan mode without ever creating an OpenGL context.
- **Memory-optimized asset lifecycle** - lazy module UI construction, batched GL
  texture deletion, pixel-copy garbage collection with disk reload on first draw,
  heap trimming after the appearances parse, and live memory diagnostics
  (`[mem]` / `[boot]` / `[gc]` log lines).
- **Protocol 15.30 support** with protobuf appearances and per-version asset
  directories (`data/things/1530/`).

## Building (Windows)

Requirements: Visual Studio 2022 (v143 toolset), [vcpkg](https://github.com/microsoft/vcpkg)
with `VCPKG_ROOT` set. Dependencies are restored automatically from `vcpkg.json`.

```
msbuild vc18\otclient.vcxproj /p:Configuration=DirectX /p:Platform=x64
```

The executable is produced as `CrystalOTC.exe` in the repository root.
Select the renderer with `renderBackend = vulkan` or `gl` in `config.ini`
(also available in-game under Options -> Graphics).

## Building (Linux / Docker / Android)

The upstream CMake build is preserved - see `CMakeLists.txt`, `Dockerfile`
and the scripts in the repository root. The Vulkan renderer is currently
Windows-only; other platforms use the OpenGL path.

## Credits and license

CrystalOTC is a derivative of [OTClient - Redemption](https://github.com/mehah/otclient)
by mehah and contributors, which itself descends from
[OTClient](https://github.com/edubart/otclient) by edubart and contributors.

Licensed under the MIT License - see [LICENSE](LICENSE).
