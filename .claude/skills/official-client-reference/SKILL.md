---
name: official-client-reference
description: "Consult the installed official Tibia client for ground truth before implementing or fixing client behaviour. Use when working on options, UI logic, rendering, light effects, defaults, sliders, protocol handling or any parity question where 'what does the real client do' decides the answer - including reading its options JSON, its symbols, its embedded QML, and disassembling when nothing cheaper answers it."
when_to_use: "Trigger for: what does the official client do, match the real client, client parity, option default, slider range, is this backwards, UI logic fix, rendering/light behaviour, before changing an option's semantics, decompile the client, look inside the client binary."
---

# Official Client Reference

Before changing how CrystalOTC behaves - an option's meaning, a default, a
slider's direction, a rendering rule - look at the official client first. It is
the specification, and most questions are answered by a file you can read in
seconds.

## Why this ordering matters

The Clouds & Indoor Effect fix got its direction backwards **twice** from
reasoning about screenshots: once from a slider mapping copied off a neighbouring
option, once from over-reading a pair of night screenshots. Both times a single
string in the official client settled it immediately - the option is named
`lightAttenuationCloudsIndoor`, and *attenuation* means reduction, which fixes the
direction with no inference at all.

**Naming and defaults beat visual inference.** Screenshots are for calibrating
*how much*, never for deciding *which way*.

## Two installs, and they are complementary

| | macOS install | Windows dump |
|---|---|---|
| Path | `~/Library/Application Support/CipSoft GmbH/Tibia/packages/Tibia.app` | `/Users/alancruz/Github/Tibia/gameclient-15.25.3a4a52` |
| Version | 15.32 (`package.json.version`) | 15.25 |
| Binary | `Contents/MacOS/client` - Mach-O x86_64, 48 MB | `bin/client.exe` - PE32+ x86-64 |
| C++ symbols | **Yes** - ~6280 `tibia::` names | No, fully stripped |
| Game QML | **Yes, as plain source** (82 docs) | **Yes, as plain source** (77 docs) |
| Saved options | `Contents/Resources/conf/clientoptions.json` | `conf/clientoptions.json` |
| Factory defaults | `Contents/MacOS/graphics_resources.rcc` | `bin/graphics_resources.rcc` |

Prefer the **macOS** install: it is newer and it is what the user actually runs.
It carries readable QML too, so the Windows dump is only needed when you want to
confirm a finding against 15.25 - mind the version skew when you do.

**Trap:** `/Applications/Tibia.app/Contents/MacOS/Tibia` is only the ~3 MB
**launcher**. The real client is the 48 MB binary under `packages/`.

## Escalation ladder

Work down this list. Stop as soon as the question is answered.

### 1. Option names and values

Options live under an `options` object. Walk it and match on the leaf key - a
substring search over the serialised blob drowns in false positives ("light"
matches `gameWindowShowLootHighlighting`).

```bash
python3 -c "
import json, sys
def walk(o, path=''):
    if isinstance(o, dict):
        for k, v in o.items():
            yield from walk(v, f'{path}.{k}' if path else k)
    else:
        yield path, o
d = json.load(open(sys.argv[1]))
for p, v in walk(d):
    if 'light' in p.split('.')[-1].lower():
        print(f'{p} = {v!r}')
" ~/Library/Application\ Support/CipSoft\ GmbH/Tibia/packages/Tibia.app/Contents/Resources/conf/clientoptions.json
```

**`clientoptions.json` is the user's saved state, not the shipped default.** The
factory defaults are embedded in `graphics_resources.rcc` (a lower
`clientOptionsVersion`). Check the `.rcc` copy before claiming a default:

```bash
strings -a .../graphics_resources.rcc | grep -A12 '"clientOptionsVersion"'
```

**Reading convention:** sliders shown as 0-100% are stored as 0..1 floats, so
`0.75` is 75% and `0` means the option is off. This was originally confirmed
against `lightAmbientLevel: 0.25` ↔ "Ambient Light: 25%" and
`lightLevelSeparatorLevel: 0.8` ↔ "Level Separator: 80%" - do not expect those
two numbers to still be there. This file is live user state and both have since
changed (currently `0` and `1`). The convention holds; the sample values do not.

**Read the name as evidence.** `lightAttenuationCloudsIndoor` says the value
*attenuates* light - a reduction, not a substitution, not a brightness. Names in
this file are consistently literal.

### 2. macOS symbols - the class map

Locals are stripped (`nm -a | awk '$2=="t"'` is empty), but **globals are not**:
3,522 `T` symbols carry addresses, 3,021 of them `tibia::`, and
`dyld_info -exports` reaches 6,280. So you get both a class map *and* somewhere
to pivot from. RTTI and exported names tell you what the subsystem is made of;
the addresses let you disassemble it.

```bash
C=~/Library/Application\ Support/CipSoft\ GmbH/Tibia/packages/Tibia.app/Contents/MacOS/client
nm "$C" | c++filt | grep -iE "light|render" | sed 's/^[0-9a-f]* //' | sort -u
nm "$C" | c++filt | grep -oE "tibia::[A-Za-z_:]+" | sort -u   # full class map
```

That is how `tibia::qmlcomponents::TLightmapPaintedItem` and
`tibia::worldmap::TAmbientLightStorage` were found.

Qt registers classes into QML under short names; the moc string table holds them
next to the C++ name. Dumping the NUL-separated strings around a class name gives
its QML element name and its property list:

```python
data = open(client_path,'rb').read()
i = data.find(b'TLightmapPaintedItem')
print(data[i-200:i+2000].split(b'\x00'))
```

`TLightmapPaintedItem` registers as QML element **`LightMap`**.

### 3. Readable QML and settings-key neighbours

**Both** binaries embed whole QML documents as plain ASCII - imports, ids,
property and signal declarations, handler bodies, the lot - alongside settings
keys in registration order. Grep for a distinctive binding and read outwards:

```bash
strings -a "$C" | grep -n 'socketComponent.socket.gemImageSource'
# then sed -n 'N-15,N+10p' around the hit for the whole component
```

Do not be misled by the thousands of `QmlCacheGeneratedCode` /
`_qt_qml_qmlcomponents_qml_*_qml` RTTI symbols: those are the AOT cache and they
sit *next to* the retained source, not instead of it. Seeing them is not
evidence the source is gone - search for the document body before concluding
anything is compiled away.

The example below uses the Windows dump because that is where the attenuation
keys were first found, but the same greps work on the macOS binary.

```bash
cd /Users/alancruz/Github/Tibia/gameclient-15.25.3a4a52/bin
strings -a client.exe | grep -inE "attenuat|indoor|cloud"   # find it
strings -a client.exe | sed -n '318240,318340p'             # read its neighbours
```

Neighbouring strings are informative: that is how the one UI key
`lightAttenuationCloudsIndoor` was found to back **two** stored keys,
`lightAttenuationClouds` and `lightAttenuationIndoor`.

### 4. Resource bundles

Qt `.rcc`, zlib-compressed entries. Brute-force decompression works:

```python
import zlib
data = open('graphics_resources.rcc','rb').read()
for i in range(len(data)-2):
    if data[i] == 0x78 and data[i+1] in (0x01,0x5e,0x9c,0xda):
        try: out = zlib.decompressobj().decompress(data[i:i+400000])
        except Exception: continue
        if len(out) > 200: ...  # collect
```

Contents are JSON, QML and images. **No shaders in readable form** on either
platform, and no HLSL/GLSL text in either binary despite the shipped shader
compilers. Do not go looking for the rendering maths here.

### 5. Disassembly - last resort

No Ghidra, radare2 or rizin on this machine. Build a venv:

```bash
python3 -m venv $SP/venv && $SP/venv/bin/pip install -q capstone pefile numpy
```

The method is the same on both platforms: find a string's virtual address, scan
the text section for RIP-relative references to it, disassemble around the hits.

**Mach-O** - map sections from `otool -l` (`sectname`/`segname`/`addr`/`size`/
`offset`), then:

```python
data = open(client_path,'rb').read()
i = data.find(b'lightAttenuationIndoor\x00')
T = next(a + (i-o) for (seg,sect),(a,s,o) in secs.items() if o <= i < o+s)  # vmaddr

ta, tsz, toff = secs[('__TEXT','__text')]
b = np.frombuffer(data[toff:toff+tsz], dtype=np.uint8).astype(np.int64)
n = len(b)
d32 = b[0:n-3] | (b[1:n-2] << 8) | (b[2:n-1] << 16) | (b[3:n] << 24)
d32 = np.where(d32 >= 2**31, d32 - 2**32, d32)
hits = np.nonzero(d32 == (T - (ta + np.arange(n-3) + 4)))[0]
```

Annotate `lea reg, [rip+disp]` operands by resolving the target back to a C
string - that turns a wall of stack shuffling into readable key names.

**PE** - same idea, with `pefile` for the section table:

```python
import pefile, numpy as np
from capstone import *
pe = pefile.PE('client.exe', fast_load=True)
base = pe.OPTIONAL_HEADER.ImageBase
data = open('client.exe','rb').read()
secs = [(s.Name.decode().rstrip('\x00'), s.PointerToRawData, s.SizeOfRawData,
         base + s.VirtualAddress) for s in pe.sections]

def va2off(va):
    for n, f, sz, v in secs:
        if v <= va < v + sz: return f + (va - v)

off = data.find(b'lightAttenuationIndoor\x00')
T = next(v + (off - f) for n, f, sz, v in secs if f <= off < f + sz)

n_, f_, sz_, tva = next(x for x in secs if x[0] == '.text')
b = np.frombuffer(data[f_:f_+sz_], dtype=np.uint8).astype(np.int64)
n = len(b)
d32 = b[0:n-3] | (b[1:n-2] << 8) | (b[2:n-1] << 16) | (b[3:n] << 24)
d32 = np.where(d32 >= 2**31, d32 - 2**32, d32)
hits = np.nonzero(d32 == (T - (tva + np.arange(n-3) + 4)))[0]   # disp32 field offsets

md = Cs(CS_ARCH_X86, CS_MODE_64)
start = tva + int(hits[0]) - 0x60
o = va2off(start)
for a, sz, m, op in md.disasm_lite(data[o:o+0x140], start):
    print(f"0x{a:x}  {m:8} {op}")
```

## What this can and cannot tell you

**Reachable:** option names, defaults, value ranges, which stored keys a control
writes, settings migration logic, class names, QML element names, the QML UI
(both binaries), protocol message handler names, and - via the export trie plus
`LC_FUNCTION_STARTS` - named function addresses to disassemble.

**Harder, but not a dead end:** the renderer's actual arithmetic. An earlier pass
concluded this was unreachable; that conclusion was wrong and rested on the
"no function addresses" error corrected above. The obstacles below are real, but
they are reasons to enter through the symbol table rather than through string
xrefs - not reasons to stop. See the export-trie route at the end of this file.

- Each `lightAttenuation*` key has exactly **one** xref, and it is the settings
  *migration* table (`0x100a42328`-`0x100a423f9`), which builds (dest, source)
  pairs and hands both to one generic function. Confirms the structure - two
  stored keys fed from one UI key, nothing scaled in between - but the runtime
  read happens through a struct member with no string involved, so string xrefs
  cannot reach the consumer.
- `TLightmapPaintedItem` and `TAmbientLightStorage` export no vtable of their
  own - only Qt's `QQmlElement<...>` wrapper typeinfo - so there is no virtual
  table to walk into `paint()`.

Reaching a lightmap constant from here means a real Ghidra session, not a few
greps.

**So: pin numeric magnitudes empirically.** When naming gives you the *shape* but
not the *scale*, set the official client and CrystalOTC to the same option value
at the same spot and time of day, and tune the one constant until they match.
Minutes, versus hours of reverse engineering for the same number.

## Traps

- **A reference screenshot may not be the official server.** Screenshots from the
  official client connected to a third-party server (e.g. "Nova Sage") show *that
  server's* choices for anything server-sent - world light level and colour
  especially. They do not isolate official behaviour. State which server a
  comparison came from before concluding anything from it.
- **The client decides nothing the server sends.** World light level and colour
  arrive over the protocol (`parseWorldLight`), so no amount of digging in the
  install reveals what CipSoft's servers send. Compare against upstream canary's
  source for that - it is on disk, and it is a fact rather than a recollection.
- **Mind the version skew.** The two installs are different client versions.
  Confirm a finding on the macOS build before relying on it, or check it holds in
  both - the attenuation keys did.
- **Say which rung a claim came from.** "The binary names it attenuation" and
  "I recall real Tibia does X" are not the same strength of evidence, and the
  second one has been wrong here before.

## Related

- `crystalserver-ops` - restarting/rebuilding the server after a protocol or
  light change.

## Getting to function addresses on macOS

The string-xref route above stalls because the runtime read happens through a
struct member. Enter through the symbol table instead:

```bash
C=~/Library/Application\ Support/CipSoft\ GmbH/Tibia/packages/Tibia.app/Contents/MacOS/client
nm "$C" | awk '$2=="T"' | c++filt | grep -i lightmap      # addressed globals
dyld_info -exports "$C" | grep -i lightmap                 # wider still
otool -l "$C" | grep -A3 LC_FUNCTION_STARTS                # exact boundaries
```

`__TEXT` is contiguous, so `off = va - 0x1000090a0 + 37024` maps a VM address to
a file offset (re-derive both constants from `otool -l` per build). capstone in a
venv finishes the job.

For a class with no exported symbol at all, find its Itanium typeinfo-name string
in `__TEXT,__const`, search `__DATA_CONST` for a qword pointing at it (that is
`typeinfo+8`), then search for the typeinfo address itself - each hit is
`vtable+8`. Walking the vtable hands you every virtual method.

**Still prefer the cheap rungs first.** Naming and defaults settle most parity
questions in seconds, and empirical calibration is still the fastest way to pin a
single magnitude. This route is for when the question genuinely is "what is the
formula".
