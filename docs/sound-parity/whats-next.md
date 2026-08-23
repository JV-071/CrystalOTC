# Sound parity: next-session handoff

Updated 2026-08-23 after the light-healing and positioned great-fireball
experiments. This is the starting document for the next sound-parity session.
Read it before changing either repository.

## Objective and scope

The goal is observable sound parity with the official Tibia 15.3x client:

- the same event chooses the same sound template and asset family;
- the server emits the sound at the correct world position and with the correct
  source classification;
- the client applies the same randomization, attenuation, filtering, scheduling,
  overlap, and lifetime rules;
- visual-to-audio timing matches within the variation of the display and capture
  pipeline;
- ambience, item loops, music, combat, movement, floors, and burst behavior are
  eventually covered by controlled recordings rather than intuition.

This work uses the official client as a behavioral oracle. It does **not** claim
to recover CipSoft's source implementation. A change should be made only after
the relevant official behavior has been isolated and measured.

## Repository map and immutable decisions

### CrystalOTC client

- Repository: `/Users/alancruz/Github/Tibia/CrystalOTC`
- Branch at handoff: `main`
- Sound implementation baseline before this handoff document:
  `3d661c7d078954427c6780c53e1ec349ca758ae6`
- Private push remote: `origin`, currently
  `git@github.com:aacruzgon/CrystalOTC-private.git`
- Public fork remote: `fork`, currently
  `git@github.com:aacruzgon/CrystalOTC.git`
- Upstream push is deliberately disabled.
- The sound implementation stack through `3d661c7d` is 10 commits ahead of
  `origin/main`; this handoff document is an additional local commit. Do not
  assume any of them have been pushed.

### crystalserver

- Repository: `/Users/alancruz/Github/Tibia/crystalserver`
- Branch at handoff: `local/testing`
- HEAD at handoff: `9e17416ae76c9941b08be288a6cfa7802c937bb8`
- Writable fork remote: `fork`, currently
  `git@github.com:aacruzgon/crystalserver.git`
- The `origin` push URL is deliberately disabled because it is the upstream
  `zimbadev/crystalserver` repository.
- Pre-existing untracked `.claude/` and `docs/architecture/` directories belong
  to the user. They were not part of sound parity and must not be staged,
  modified, or deleted accidentally.

The server currently advertises protocol 15.25. The imported soundbank and
official archive are from the 15.3x/15.32 client. The user explicitly decided
that sound loading must **not** become version-aware yet: the current protocol
also lacks these assets, so the 15.32 bank is intentionally used to improve the
current client as well as the later 15.30 migration.

### Official asset archive

The complete imported archive is under:

```text
/Users/alancruz/Github/Tibia/CrystalOTC/data/official-client-15.3x
```

Important children include:

- `raw-archives/` — original extracted containers such as
  `graphics_resources.rcc`;
- `package-metadata/` — package JSON, asset manifest, plist, translations, and
  version metadata;
- `protocol-assets/` — appearances, sprites, minimap, satellite, and related
  protocol data;
- `sound-assets/` — archived client sound data;
- `graphics-resources/` — unpacked RCC resources;
- `store-images/`, `runtime-minimap/`, and `conflicts/`.

The directory is about 278 MB. Do not rename it and do not introduce a second
version-specific runtime loader without revisiting the decision above.

The generated sound inventory is:

```text
docs/sound-parity/sound-inventory-15.32.json
```

Its human-readable summary and regeneration command are in
`docs/sound-parity/README.md`. The inventory currently describes 844 audio
files, 592 numeric effects, 91 location ambience templates, 9 item ambience
templates, and 25 music templates.

## Relevant commits already made

### Client commits

These ten local commits form the current sound-parity stack, newest first:

```text
3d661c7d docs(sound): record positioned GFB parity
1ca18a9f fix(sound): match official positional attenuation
94d4a673 docs(sound): record healing timing parity
fda7f474 fix(sound): suppress chat alerts for spell speech
73c8cb0d feat(sound): add observable parity capture lab
529077e3 docs(sound): record regional coverage
a2131f7c fix(sound): play signature tracks as one-shots
de067a65 feat(sound): add a reproducible parity inventory
136ade94 fix(sound): preserve positioned effect playback
590a2d1b feat(sound): promote the official 15.32 soundbank
```

They are signed commits. Before pushing, inspect the private remote and the
entire ahead range; do not push to `upstream`.

### Server commits

Relevant server commits, newest first:

```text
9e17416a fix(sound): emit rune audio at its target
33cec81c fix(spells): send incantations with spell speech mode
e82f848c feat(sound): trace serialized sound events
a162d6b0 feat(sound): wire regional soundscapes
```

Before pushing the server, use the `fork` remote and inspect the branch because
`local/testing` does not report an upstream tracking branch at this handoff.

## What has been verified

### Trace and capture boundaries

The tooling observes four distinct boundaries:

1. crystalserver serializes a sound packet for a player;
2. CrystalOTC decodes the packet and records the world/relative position;
3. the scheduler resolves, accepts, or rejects the requested asset;
4. ScreenCaptureKit records audible application audio and video on one clock.

The server trace is enabled with `CRYSTALSERVER_SOUND_TRACE`; implementation is
in:

```text
/Users/alancruz/Github/Tibia/crystalserver/src/game/sound_trace.cpp
/Users/alancruz/Github/Tibia/crystalserver/src/game/sound_trace.hpp
```

The authoritative packet serialization is in
`src/server/network/protocol/protocolgame.cpp`, especially
`ProtocolGame::sendDoubleSoundEffect`. Server dispatch and source ownership are
in `src/game/game.cpp`, especially `Game::sendDoubleSoundEffect`.

The client trace is enabled with `CRYSTALOTC_SOUND_TRACE`. Its packet parsing is
in `src/client/protocolgameparse.cpp`; effect scheduling and tracing are in
`src/framework/sound/soundmanager.cpp`.

Every JSONL event uses schema `crystal-sound-trace-v1` and carries monotonic and
Unix-epoch microsecond clocks. The recorder's adjacent JSON records the epoch of
its first media sample, allowing native events to be aligned with audio/video.

### Light healing (`exura`)

The official bank maps light healing to effect 1001, audio file 323, gain 0.5,
and uniform pitch randomization from 0.9 through 1.1.

The first Crystal recording also played effect 2782/audio file 684, a generic
console notification. The server had serialized successful spell incantations
as ordinary `TALKTYPE_SAY`. Commit `33cec81c` now sends
`TALKTYPE_SPELL_USE`, and commit `fda7f474` renders spell speech without the
chat-notification sound. The world effect remains the sole owner of spell
audio.

Measured results:

- official pitch estimates over ten casts: 0.9178-1.0818, mean 1.0035,
  sample standard deviation 0.0614;
- Crystal trace pitches over ten casts: 0.9147-1.0973, mean 1.0155,
  sample standard deviation 0.0616;
- official audio followed the first visible healing frame by 35.3 ms on
  average, range 19.7-46.8 ms;
- Crystal's nine unambiguous samples averaged 34.7 ms, range 27.1-42.1 ms;
- server-to-client delivery averaged 8.72 ms;
- playback scheduling followed packet receipt by 0.074 ms on average;
- no cast was dropped or throttled.

Conclusion: do not add a speculative client scheduling delay. The roughly
106-ms command-to-captured-audio interval is media/display pipeline latency;
the within-recording audio-to-visual relationship already matches.

### Positioned great fireball rune (GFB)

The clean official horizontal sequence was intended as:

```text
L1, R1, L3, R3, L5, R5, L7, R7
```

Official mean channel peaks at distances 1, 3, 5, and 7 were:

| Distance | Mean peak dBFS | Relative to distance 1 |
| ---: | ---: | ---: |
| 1 | -8.905 | 0.000 dB |
| 3 | -9.965 | -1.060 dB |
| 5 | -11.050 | -2.145 dB |
| 7 | -12.465 | -3.560 dB |

The observations fit a linear **amplitude** fade, not a linear-dB fade:

```text
positionGain = clamp(1 - distanceTiles / 19, 0, 1)
```

Relative predictions at distances 1, 3, 5, and 7 are 0, -1.023, -2.184,
and -3.522 dB. A free linear amplitude fit crosses zero at 18.964 tiles.

The official client did not pan left/right. Its channel bias did not reverse
when the source moved across the listener. It preserves the stereo image in the
OGG and applies only gain.

This matters because OpenAL ignores `AL_POSITION` for stereo buffers. Converting
to mono or using OpenAL positioning would introduce panning not seen in the
official recording. Commit `1ca18a9f` therefore:

- computes gain from the relative pixel offset and sprite size;
- applies the measured 19-tile linear fade directly;
- does not call `SoundSource::setPosition` for these effects;
- records `position_gain` in `effect.resolve` and `effect.play` traces.

The implementation is currently in the anonymous namespace at the top of
`src/framework/sound/soundmanager.cpp` and in
`SoundManager::playSoundEffectInternal`.

### Rune target-position server bug

Before `9e17416a`, GFB packets always placed the sound at the caster even though
the visual target was elsewhere. Temporary probes proved the target was intact
at every earlier boundary:

```text
client cursor tile:       32299,32262,7
client player tile:       32302,32262,7
server playerUseItemEx:   to=32299,32262,7
RuneSpell LuaVariant:     32299,32262,7
luaCombatExecute variant: 32299,32262,7
```

The loss happened in generic `Spell::postCastSpell`, which sent every rune
sound at `player->getPosition()`. The fix adds an explicit sound-position
overload. `RuneSpell::executeUse` now snapshots:

- `var.pos` for position-targeted runes;
- the target creature position for creature-targeted runes;
- the caster position only as a fallback.

Instant spells continue using the original caster-centered overload. The
relevant server files are:

```text
/Users/alancruz/Github/Tibia/crystalserver/src/creatures/combat/spells.cpp
/Users/alancruz/Github/Tibia/crystalserver/src/creatures/combat/spells.hpp
```

GFB itself is declared in:

```text
/Users/alancruz/Github/Tibia/crystalserver/data/scripts/runes/great_fireball.lua
```

It assigns generic cast sound 10 and impact sound 1016. Effect 10 is not an
audible catalog entry in this client and is expected to trace as
`unknown_effect`; effect 1016 is the audible GFB template and randomly selects
audio files 303, 304, or 305 with pitch 0.9-1.1. Do not treat effect 10's drop
as the original positioning bug.

The final three-tile-left verification proved all layers:

```text
server world position: 32299,32262,7
listener position:     32302,32262,7
client relative_px:    -96,0
position_gain:         0.84210527 = 1 - 3/19
```

### Post-fix Crystal application-audio validation

The final Crystal recording successfully captured L1, R1, L3, R3, L5, and R5.
The intended distance-7 casts did not reach the server and therefore provide no
audio evidence. Do not label them client audio drops.

Because GFB randomizes both asset and pitch, comparing arbitrary raw peaks is
misleading. Comparing the same chosen audio file gave:

| Audio file | Comparison | Measured delta | Predicted delta |
| ---: | --- | ---: | ---: |
| 304 | distance 1 to 3 | -1.107 dB | -1.023 dB |
| 304 | distance 1 to 5 | -2.168 dB | -2.184 dB |
| 303 | distance 3 to 5 | -1.137 dB | -1.160 dB |

The trace resolved the six GFB events as follows:

| Cast | Offset px | File | Gain | Pitch |
| --- | ---: | ---: | ---: | ---: |
| L1 | -32 | 304 | 0.94736844 | 0.954542 |
| R1 | 32 | 305 | 0.94736844 | 0.995546 |
| L3 | -96 | 304 | 0.84210527 | 0.971853 |
| R3 | 96 | 303 | 0.84210527 | 1.079531 |
| L5 | -160 | 304 | 0.73684210 | 1.080931 |
| R5 | 160 | 303 | 0.73684210 | 0.918147 |

This independently verifies the application mixer for the measured horizontal
cases.

## Evidence files from the 2026-08-23 session

The working evidence directory is:

```text
/tmp/crystal-sound-parity-run-20260823-01
```

It is about 517 MB and is **ephemeral**. `/tmp` may be cleared by reboot or OS
maintenance. MOV files should not be committed to Git. Copy the directory to a
durable local archive if the raw evidence must survive.

Most important files:

```text
official-exura-isolated-01.mov/json/jsonl
official-exura-randomization-10b.mov/json
crystal-exura-spell-mode-fix-01.mov/json
crystal-exura-randomization-10.mov/json
official-gfb-horizontal-02.mov/json
crystal-gfb-horizontal-post-fix.mov/json
client-positional-falloff.jsonl
server-rune-position-fix.jsonl
```

Use `official-gfb-horizontal-02`, not `official-gfb-horizontal-01`, as the clean
official horizontal sample. The first experiment had contamination and/or
setup errors.

The post-fix capture's first media-sample epoch is `1787517745392725` us. Its
six successful GFB packet offsets are approximately 31.317, 35.975, 40.484,
44.359, 50.098, and 58.992 seconds. A sound 2674 event near 54.551 seconds was
not GFB and was excluded. The two intended distance-7 actions produced no GFB
server packet.

Always make new trace and capture names. Reusing one path can truncate evidence
when a traced process restarts.

## Highest-priority next experiment: distance geometry

Horizontal falloff does not prove how two-dimensional tile offsets are reduced
to a scalar distance. The current client uses Euclidean distance through
`std::hypot`. That is still an assumption.

### Step 1: cardinal-axis symmetry

Measure north and south at three tiles while holding the listener stationary:

```text
N3, S3
```

Compare them with the verified L3/R3 result. This checks whether vertical screen
offsets use the same scale as horizontal offsets before diagonals are analyzed.

### Step 2: diagonal norm

Measure at least:

```text
NE(3,3), SE(3,3), SW(3,3), NW(3,3)
```

The candidate gain values are far enough apart to distinguish:

| Candidate norm | Distance for (3,3) | Predicted gain |
| --- | ---: | ---: |
| Euclidean | 4.242641 | 0.776703 |
| Chebyshev | 3 | 0.842105 |
| Manhattan | 6 | 0.684211 |

Do not compare one arbitrary GFB peak with another. Repeat each location enough
times to identify or match the selected file, or compare only samples resolved
to the same official asset by the fingerprint tooling. Random pitch also changes
duration and peak structure. Relative measurements within one client are more
useful than absolute official-versus-Crystal dBFS because the clients may have
different master/channel slider values.

If the official result is not Euclidean, update the client formula only after
the official measurement is clear, rebuild, rerun the same matrix, and record
the conclusion in `lab.md`.

### Step 3: retry distance 7 correctly

The prior Crystal L7/R7 actions never reached the server. Before spending more
runes:

1. confirm there are enough GFB charges;
2. use an open map viewport where both target tiles are inside the actual map
   widget, not a sidebar or panel;
3. move the cursor first, then press the configured actionbar key (F5 in the
   previous session) without clicking;
4. wait at least three seconds between casts for the two-second rune cooldown;
5. watch the **server trace** for effect 1016 at the intended world position;
6. classify a missing server event as targeting/input failure, not audio failure.

The previous run also emitted effect 2674 during one unsuccessful attempt. Do
not fold such feedback sounds into the GFB peak window.

## Second priority: floors and z behavior

The sound packet contains `x`, `y`, and `z`, but the current Crystal parser
calculates `relative_px` from only x/y:

```cpp
Point((pos.x - center.x) * spriteSize,
      (pos.y - center.y) * spriteSize)
```

Consequently, a received sound directly above or below the listener currently
gets gain 1.0 regardless of floor. This has not been compared with the official
client.

Test these separately:

1. same x/y/z;
2. same x/y, one visible floor above;
3. same x/y, one visible floor below;
4. one floor above with a horizontal offset;
5. one floor below with a horizontal offset;
6. a floor not rendered/visible to the listener;
7. listener changes floor while a long sound is already playing.

For every silence, first establish whether the server sent a packet to the
listener. `Game::sendDoubleSoundEffect` finds spectators around the source, so
server visibility/spectator rules can suppress delivery before the client has a
chance to apply floor attenuation. Compare server trace, client packet trace,
and audio in that order.

Targeted runes may not be able to address an invisible floor. A controlled
server-side diagnostic action may be needed to emit one known sound at an exact
position. Keep such a fixture narrowly scoped and do not commit it as gameplay
behavior until the official result requires a production change.

## Third priority: burst scheduling and overlap

Crystal still contains two custom policies with no completed official parity
measurement:

1. at most four effect requests per 100-ms poll window;
2. drop the same resolved filename if it played less than 150 ms ago.

They are in `SoundManager::playSoundEffectInternal`.

Important gotchas in the current implementation:

- the four-per-window counter increments **before** catalog lookup, filtering,
  and asset resolution;
- an unknown effect such as GFB's generic main effect 10 therefore consumes one
  of the four slots even though it is inaudible;
- one double GFB packet currently consumes two request slots: effect 10 and
  effect 1016;
- the duplicate throttle operates on the resolved filename, not the numeric
  effect ID;
- random templates can evade the duplicate throttle by choosing different
  files;
- dropped events are visible as `cycle_limit` or `duplicate_throttle` in the
  client JSONL trace.

This could be a significant divergence during real combat. Measure the official
client before removing or changing either policy.

Recommended matrix:

| Variable | Cases |
| --- | --- |
| simultaneous distinct effects | 1 through 8 in one server dispatch |
| simultaneous identical template | 1 through 8 |
| identical spacing | 25, 50, 75, 100, 125, 150, 175, 200, 250 ms |
| randomized template | same effect repeatedly, record chosen assets |
| double packets | main+secondary combinations, including unknown main |
| channel/source | OWN, OTHERS, CREATURES, GLOBAL |

Generate deterministic server packets rather than relying on combat timing.
Capture the official application audio, and use the Crystal server/client traces
to explain every accepted or dropped event. If the official client layers more
than Crystal, change the policy and add a regression test around the measured
boundary.

## Remaining experiment matrix after bursts

### Ownership and source classification

`Game::sendDoubleSoundEffect` currently assigns:

- `OWN` when the actor is the receiving player;
- `OTHERS` when another player is the actor;
- `CREATURES` for non-player creatures;
- `GLOBAL` for no actor or an NPC.

Source affects filter categories and possibly channel gain. Test the same asset
under each source. The user has only one official Tibia account, so a controlled
two-official-player test is not presently available. Use a monster/NPC for the
available distinctions, or coordinate with a consenting second player; never
pretend a one-account experiment proved `OTHERS` parity.

### Moving source and moving listener

Test:

- stationary source and listener;
- source moves immediately after a one-shot packet;
- listener moves immediately after a one-shot packet;
- listener teleports;
- either side changes floor;
- a long/looping sound continues during movement.

Crystal currently applies gain once when playback starts; it does not attach a
one-shot source to a moving creature. Confirm whether the official client also
uses packet-time position or continuously updates gain.

### Ambience and item loops

Exercise enter, remain, cross boundary, leave, and rapid re-entry. For item
ambience, test counts immediately below/at/above every bank threshold and the
configured radius. The client trace already records item-ambience selection,
hold, swap, fade, resume, and stop events.

Do not conflate server-selected location ambience/music with client-selected
item ambience. Location and music mappings live in server behavior; item IDs,
count thresholds, radius, and OGG choices come from the soundbank.

### Music and anthem behavior

Test town entry, combat transition, repeated anthem packets, mute/unmute, track
completion, logout, and login-screen transition. Signature tracks were changed
to one-shots in `a2131f7c`; verify each template rather than assuming all music
shares one looping rule.

### Load and stalls

Test normal delivery, injected packet delay, a burst after a client stall, audio
device changes, and source exhaustion. Separate network arrival, scheduler
decision, and audible onset. The client follows the OS default audio device when
the required OpenAL Soft extensions are available; device reopen behavior is a
separate risk from effect scheduling.

## Reproduction workflow

### 1. Start from clean worktrees

From the client:

```sh
cd /Users/alancruz/Github/Tibia/CrystalOTC
git status --short
git log --oneline -12
```

From the server:

```sh
cd /Users/alancruz/Github/Tibia/crystalserver
git status --short
git log --oneline -8
```

Preserve the server's untracked `.claude/` and `docs/architecture/` directories.
Do not reset, clean, or stage broad globs.

### 2. Build recorder, client, and server

```sh
cd /Users/alancruz/Github/Tibia/CrystalOTC
swift build -c release --package-path tools/sound-parity-capture
cmake --build build/macos-cocoa --target otclient -j 8

cd /Users/alancruz/Github/Tibia/crystalserver
cmake --build build/macos-release --target crystalserver -j 8
```

The client window saying `LIVE RELOAD ENABLED` does not reload native C++.
Restart the process after changing `soundmanager.cpp` or protocol parsing.
Likewise, rebuild and restart crystalserver after changing its C++.

### 3. Create a unique run directory

```sh
mkdir -p /tmp/crystal-sound-parity-YYYYMMDD-NN
```

Use unique trace filenames for every restart.

### 4. Start traced server

```sh
cd /Users/alancruz/Github/Tibia/crystalserver
CRYSTALSERVER_SOUND_TRACE=/tmp/crystal-sound-parity-YYYYMMDD-NN/server.jsonl \
  ./build/macos-release/bin/crystalserver
```

The server needs its local MySQL service on `127.0.0.1` and may need sandbox
approval to connect. Wait for the world-online log before reconnecting the
client.

### 5. Start traced CrystalOTC

```sh
cd /Users/alancruz/Github/Tibia/CrystalOTC
CRYSTALOTC_SOUND_TRACE=/tmp/crystal-sound-parity-YYYYMMDD-NN/client.jsonl \
  build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC
```

The previous test character was `Druid Sample`, normally at Thais temple around
`32302,32262,7`. Verify its actual position from the new trace; do not hard-code
old coordinates into production behavior.

### 6. Record one application at a time

Official client bundle ID:

```text
com.tibia.client
```

Crystal bundle ID:

```text
com.crystalotc.client
```

Example official capture:

```sh
tools/sound-parity-capture/.build/release/sound-parity-capture \
  --bundle-id com.tibia.client \
  --duration 90 \
  --output /tmp/crystal-sound-parity-YYYYMMDD-NN/official-test.mov
```

Example Crystal capture by PID:

```sh
tools/sound-parity-capture/.build/release/sound-parity-capture \
  --pid PID \
  --duration 90 \
  --output /tmp/crystal-sound-parity-YYYYMMDD-NN/crystal-test.mov
```

ScreenCaptureKit needs macOS Screen Recording permission. A 90-second 1280x720
capture was roughly 63 MB. Record only the intended application so system audio
and the other client do not contaminate the file.

Mute music and ambience in both clients for isolated effects. Start with an
idle recording to establish the noise floor. Keep both characters at the same
map position and use the same action sequence. Wait long enough for cooldown and
sound tails.

### 7. Identify and compare

Build the fingerprint index if needed:

```sh
cd /Users/alancruz/Github/Tibia/CrystalOTC
python3 tools/sound_parity_lab.py index
```

Identify an official capture:

```sh
python3 tools/sound_parity_lab.py identify \
  /tmp/crystal-sound-parity-YYYYMMDD-NN/official-test.mov \
  --metadata /tmp/crystal-sound-parity-YYYYMMDD-NN/official-test.json \
  --output /tmp/crystal-sound-parity-YYYYMMDD-NN/official-test-sounds.jsonl
```

Compare official recognition, client trace, and server trace:

```sh
python3 tools/sound_parity_lab.py compare \
  --official /tmp/crystal-sound-parity-YYYYMMDD-NN/official-test-sounds.jsonl \
  --client /tmp/crystal-sound-parity-YYYYMMDD-NN/client.jsonl \
  --server /tmp/crystal-sound-parity-YYYYMMDD-NN/server.jsonl \
  --output /tmp/crystal-sound-parity-YYYYMMDD-NN/comparison.json
```

The full command reference and packet/file observation options are in
`docs/sound-parity/lab.md`.

## Capture discipline and known hazards

- Other players can contaminate the official recording. A previous GFB test had
  to be restarted after another player attacked the test character. Use an
  isolated area when possible and discard contaminated runs.
- The official account may need to buy or replenish rune charges. Confirm
  supplies before starting a timed capture.
- Move the cursor to the target tile **before** pressing the actionbar hotkey.
  Do not click the world after positioning; a click can move, attack, or change
  the target.
- Record exact intended order and wait intervals in commentary or a sidecar
  note. Do not infer them later solely from the waveform.
- If a cast is missing, inspect server trace first, then client packet trace,
  then scheduler trace. Silence alone cannot identify the failing layer.
- Official network packets are encrypted. A PCAP can establish arrival timing
  but cannot reveal sound IDs.
- Filesystem tracing may show no playback-time read because the official client
  can preload or memory-map its bank.
- Application-audio onset includes encoder/capture latency. Prefer relative
  timing within the same MOV and visual-to-audio offsets.
- Random asset selection and pitch must be controlled before comparing peaks or
  durations.
- Left/right source position did not pan the official GFB samples. A fixed
  channel imbalance from the source file is not evidence of panning.
- Do not restore OpenAL `setPosition` for stereo effects without new evidence.
- The 19-tile zero is a strong extrapolated fit. Normal server spectator and
  client viewport ranges may make direct gameplay measurements at 18/19 tiles
  impossible. If testing the boundary, distinguish formula validation from an
  observable official-client experiment.

## Diagnostic escalation if cursor targeting fails again

The temporary probes used in the previous session were removed before commit.
If an action again fails to reach the intended tile, add narrowly scoped logs in
this order:

1. client `modules/game_actionbar/game_actionbar.lua`, function
   `actionBarUseItemAtCursor`, logging mouse tile, picked target, and player
   position;
2. server `src/game/game.cpp`, `Game::playerUseItemEx`, logging `fromPos` and
   `toPos` for rune item 3191;
3. server `src/creatures/combat/spells.cpp`, `RuneSpell::executeUse`, logging the
   constructed `LuaVariant`;
4. server `src/lua/functions/creatures/combat/combat_functions.cpp`,
   `luaCombatExecute`, logging the received position variant;
5. only then inspect `Combat::doCombat`, `Combat::CombatFunc`, and final sound
   dispatch.

Remove all diagnostic logs before committing. The previous investigation proved
these layers correct and found the actual sound-position loss in post-cast
handling, so do not re-litigate them unless a new trace contradicts that result.

Also note that `Combat::combatTileEffects` and `Combat::postCombatEffects` can
emit sounds when sound parameters are attached to a `Combat`. GFB attaches its
sounds to the `RuneSpell`, not its `Combat`, so its current pair comes from rune
post-cast handling. A future script that configures both layers could duplicate
audio; inspect both ownership paths when investigating duplicates.

## Validation and commit checklist

Client validation:

```sh
cd /Users/alancruz/Github/Tibia/CrystalOTC
cmake --build build/macos-cocoa --target otclient -j 8
python3 -m unittest tests.tools.test_sound_parity_lab
ctest --test-dir build/macos-cocoa --output-on-failure
git diff --check
```

At this handoff the client build passed, the Python lab tests passed 8/8, and
CTest passed 67/67.

Server validation:

```sh
cd /Users/alancruz/Github/Tibia/crystalserver
cmake --build build/macos-release --target crystalserver -j 8
cmake --build build/macos-tests --target crystalserver_ut -j 8
build/macos-tests/tests/unit/crystalserver_ut
git diff --check
```

`ctest --test-dir build/macos-release` currently reports that no tests are
registered. Run the unit executable directly. At this handoff all reported
server suites except one pre-existing security test passed. The failing test is
`RSA::start logs error for missing .pem file`: it expects one logger entry but
observes two and exits 255. The sound changes compiled and ran successfully;
do not hide this known failure, and do not claim a fully green server suite.

Before each commit:

- inspect `git status --short` and `git diff --cached`;
- stage explicit files only;
- preserve unrelated user work;
- use signed, logical commits matching recent Conventional Commit style;
- do not push unless the user requests it and the destination remote has been
  verified.

## Suggested definition of done for the next session

The next session should ideally finish with:

1. a clean official N3/S3 and four-diagonal GFB capture;
2. enough repeated samples or fingerprints to control random asset/pitch choice;
3. a documented decision among Euclidean, Chebyshev, Manhattan, or another
   measured distance rule;
4. a matching Crystal capture after any required implementation change;
5. the distance-7 Crystal samples retried with server packet confirmation;
6. no temporary diagnostic logging left in either repository;
7. updated `lab.md`, builds/tests run, and logical commits prepared.

If time remains, begin the floor matrix. Do not jump to burst-policy changes
until distance geometry is settled, because positional and scheduling variables
are much easier to reason about independently.

## Ready-to-paste next-session instruction

```text
Continue the official Tibia versus CrystalOTC sound-parity work. First read
/Users/alancruz/Github/Tibia/CrystalOTC/docs/sound-parity/whats-next.md and
/Users/alancruz/Github/Tibia/CrystalOTC/docs/sound-parity/lab.md completely.
The client repo is /Users/alancruz/Github/Tibia/CrystalOTC and the server repo is
/Users/alancruz/Github/Tibia/crystalserver. Preserve unrelated work in both.
Start with the documented cardinal/diagonal GFB experiment, verify every action
at the server/client/audio boundaries, and update the handoff evidence as you go.
Do not make sound loading version-aware; the imported official 15.32 bank is
intentionally used by the current client too.
```
