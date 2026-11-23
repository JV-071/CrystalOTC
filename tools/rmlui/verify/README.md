# RmlUi verification scripts

Checks of the RmlUi integration that need the real client: a window, a GPU, the Lua modules and the
game assets. The unit tests (`ctest -R Rml`) cover the renderer and the manager on their own; these
scripts cover what only shows up when everything runs together.

```
powershell -ExecutionPolicy Bypass -STA -File tools\rmlui\verify\run.ps1 -Exe .\CrystalOTC_gl_x64.exe -Tag gl
powershell -ExecutionPolicy Bypass -STA -File tools\rmlui\verify\run.ps1 -Exe .\CrystalOTC.exe -Tag angle
```

Run it from the repository root, once per executable. `-Only demo,lifetime` runs a subset. The last
lines are a table with one row per script and `failed: N`; the exit code is 1 when something failed.

## How it works

Each `.lua` file is installed as `data/crystalotcrc.lua` (the client runs that file after loading its
modules), prints `[verify] PASS ...` / `[verify] FAIL ...` lines and calls `g_app.exit()`. `run.ps1`
puts `prelude.lua` in front of it: the steps of a script run in order, each scheduled when the
previous one has run, so a slow start delays a script instead of confusing it. `shot.ps1`
starts the client, saves a capture of its window whenever the log shows `[verify] shot <name>`,
types real keys on `[verify] keys#<n> <SendKeys string>` and tells the client where the mouse is on
`[verify] mouse#<n> <x> <y>` (a window message; the real pointer does not move).

Everything is written under `build/rmlui-verify/` (git-ignored): `userdir/` (the settings folder of
the client under test, so your real settings are not touched), `shots/` and `logs/`.

| Script | What it checks |
|--------|----------------|
| `demo.lua` | the demo window opens, the backend reports itself, `print` is still the client's, OTUI text is still drawn |
| `focus.lua` | missing and malformed documents, 50 windows opened and closed, zero size and a resize on every frame, images that cannot be resolved |
| `showcase.lua` | the 9 showcase tabs, the options, outfit and minimap windows (captures of each) |
| `keys.lua` | Ctrl+Shift+U/R/O/F/M and typing "aç" with real key events |
| `lifetime.lua` | closed windows are freed, toggles in the same dispatcher cycle, the same model name in two windows, `destroy()` from inside a document event, a widget dropped during the tick, clipboard Latin-1/UTF-8, redraw rate (changing content about 60 per second, idle content 0) |
| `gc.lua` | 150 windows with a data model opened and closed while Lua allocates on every cycle: no crash, nothing left alive (the case the patch in `vcpkg-overlays/rmlui` exists for) |
| `exit-referenced.lua`, `exit-stress.lua` | the client exits with code 0 after cases that once corrupted the heap |
| `vulkan.lua` | with `renderBackend = vulkan` RmlUi stays off, says so, and no OpenGL context is created |

## Things to know before running

- The client window opens and closes about 15 times; a full run takes around five minutes.
- The checks are written for a client nobody is using: clicking or typing in its window while a
  script runs changes what the script sees.
- `keys.lua` only types when the client window really is in the foreground; otherwise the keys are
  reported as `SKIPPED` and those checks fail. Leave the machine alone during that script.
- `lifetime.lua` overwrites the clipboard for a moment. `run.ps1` puts the text back afterwards and
  skips the clipboard check when the clipboard holds something that is not text.
- `vulkan.lua` needs `config.ini` to select the Vulkan renderer; `run.ps1` writes one for the run and
  restores yours. The exit code of that run is reported as a known issue: the Vulkan renderer
  crashes on exit with or without RmlUi.
- `lifetime.lua` hides the login screen and clears the texture cache before measuring the redraw
  rate. The login screen redraws the whole UI about 60 times per second by itself, which would hide
  a document that forgets to ask for a redraw.
- `run.ps1` refuses to start when `data/crystalotcrc.lua` already exists.

## Known open item

`lifetime.lua` and `gc.lua` accept one destroyed widget object without an RmlUi context still being
referenced after the collections, and print a `[verify] NOTE` line when that happens. On a busy
machine (a build or a game running next to the client) one such object per session is sometimes
kept until the client exits: its context was released, it holds no document or GPU object, exactly
one C++ reference is left, and the destructor runs on the main thread at shutdown. Which object
holds that reference is not known; it could not be reproduced on demand. More than one object, or
any context left open, fails the check.
