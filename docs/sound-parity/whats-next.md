# Sound parity: next-session handoff

Updated 2026-08-24 after the light-healing, horizontal great-fireball,
cardinal/diagonal geometry, distance-7, and floor/z experiments. This is the
starting document for the next sound-parity session.
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

### Cardinal and diagonal GFB geometry

The follow-up experiment measured `N3`, `S3`, and all four `(3,3)` diagonals
with stationary listeners. Two user-operated official captures supplied twelve
isolated events. Pre-effect video frames show the target outline exactly three
displayed tiles away on each intended axis.

Random file selection was controlled through the GFB files' invariant stereo
peak biases plus pitch-relative spectral matching. Three same-file official
comparisons measured diagonal-minus-cardinal deltas of `-0.80`, `-0.75`, and
`-0.95` dB, mean `-0.8333` dB. The candidate predictions are `-0.7022` dB for
Euclidean, `0` for Chebyshev, and `-1.8035` dB for Manhattan. Euclidean is the
only compatible rule, so CrystalOTC's existing `std::hypot` formula remains
unchanged.

The final synchronized Crystal run proved every boundary for six casts:

- six effect-1016 server packets at the exact target world positions;
- six matching client packets at `(0,±96)` and `(±96,±96)` pixels;
- six scheduler plays, no unexpected drops, mean delivery `7.745` ms, and mean
  packet-to-play scheduling `0.038` ms;
- six audible application-track onsets, with five complete tails and the sixth
  tail clipped only by the recording boundary.

Crystal traced cardinal gain `0.84210527` and diagonal gain `0.77670312`. After
correcting the five complete audio samples for their traced asset and pitch,
the captured diagonal-minus-cardinal delta was `-0.6917` dB, only `0.0106` dB
from the `-0.7022` dB prediction.

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

The cardinal/diagonal evidence directory is:

```text
/tmp/crystal-sound-parity-run-20260823-02
```

Its authoritative files are:

```text
official-gfb-cardinal-diagonal-user-02.mov/json
official-gfb-cardinal-diagonal-user-03.mov/json
official-gfb-cardinal-diagonal-analysis.json
server-cardinal-diagonal.jsonl
client-cardinal-diagonal.jsonl
crystal-gfb-cardinal-diagonal-user-04.mov/json
crystal-gfb-cardinal-diagonal-analysis.json
crystal-gfb-distance7-user-01.mov/json
crystal-gfb-r7-user-01.mov/json
crystal-gfb-distance7-analysis.json
```

Files containing `assistant-pilot`, `invalid-interrupted`, or `invalid-writer`
in that directory are excluded evidence. The operator performs game actions;
the recorder should start only after an explicit ready signal and an
unmistakable live cue. Let the recorder reach its configured duration because
SIGINT leaves an unindexed MOV. Long sparse Crystal captures also reproduced
intermittent AVFoundation `-11800/-16122`; use a short synchronized window.

## Completed experiment: distance geometry

The completed matrix held each listener stationary and measured:

```text
N3, S3, NE(3,3), SE(3,3), SW(3,3), NW(3,3)
```

The official same-file level result distinguishes the candidate norms, and the
Crystal application-audio result independently validates the selected mixer
gain:

| Candidate norm | Distance for (3,3) | Predicted gain |
| --- | ---: | ---: |
| **Euclidean (verified)** | 4.242641 | 0.776703 |
| Chebyshev | 3 | 0.842105 |
| Manhattan | 6 | 0.684211 |

Preserve `std::hypot`. Do not replace it with Chebyshev, Manhattan, screen-axis
weighting, or integer rounding without new official evidence.

## Completed experiment: distance 7

The distance-7 retry used short, synchronized, user-operated windows. `L7` and
`R7` each produced one effect-1016 server packet, one matching client packet,
one scheduler play, and one isolated application-audio burst:

| Cast | World target | Relative px | File | Gain | Audio delta |
| --- | --- | ---: | ---: | ---: | ---: |
| L7 | `(32301,32253,7)` | `(-224,0)` | 305 | 0.63157892 | -3.75 dB |
| R7 | `(32316,32249,7)` | `(224,0)` | 304 | 0.63157892 | -4.05 dB |

The traced gain is `1 - 7/19` on both sides. After correcting each application
sample for its traced source file and pitch, the mean measured gain delta is
`-3.90` dB versus the `-3.9914` dB prediction, an absolute error of `0.0914`
dB. Packet delivery was `6.856` ms for L7 and `11.210` ms for R7;
packet-to-play scheduling was `0.101` ms and `0.041` ms. Command-to-audible
onset was `169.571` ms and `118.203` ms respectively.

The earlier attempted distance-7 casts in the horizontal run remain correctly
classified as input/targeting failures because no effect-1016 packet reached
the server. The successful retry supersedes only the missing measurement, not
that boundary diagnosis.

## Completed diagnostic: floors and z behavior

The sound packet contains `x`, `y`, and `z`, but the current Crystal parser
calculates `relative_px` from only x/y:

```cpp
Point((pos.x - center.x) * spriteSize,
      (pos.y - center.y) * spriteSize)
```

Consequently, a received sound directly above or below the listener gets gain
1.0 regardless of floor. The 2026-08-24 experiment separated normal server
delivery from forced packet delivery and confirmed that behavior.

Normal `Position::sendSingleSoundEffect` actions at the listener's x/y and z-1
or z+1 were accepted by the talk action, but neither produced a
`server.send_sound_effect` event, client packet, scheduler event, or audible
sample. Both application AAC tracks are silent for their complete eight-second
windows. This is server suppression, not an audio failure:
`Game::sendSingleSoundEffect` uses `Spectators().find<Player>(pos)` and the
spectator query defaults to `multifloor=false`, filtering recipients whose z
differs from the source before serialization.

A temporary, name-restricted diagnostic binding then bypassed only spectator
selection and serialized effect 1016 directly to the test player with an exact
world position. It was removed after the experiment and is not gameplay
behavior. Every accepted direct action reached all three observable Crystal
boundaries:

| Case | Server world relation | Client relative px | Scheduled gain | Captured audio |
| --- | --- | ---: | ---: | --- |
| same x/y/z control | `(0,0,0)` | `(0,0)` | 1.00000000 | isolated burst, `2.952-5.522` s |
| same x/y, one above | `(0,0,-1)` | `(0,0)` | 1.00000000 | isolated burst, `1.691-4.319` s |
| same x/y, one below | `(0,0,+1)` | `(0,0)` | 1.00000000 | isolated burst, `1.716-4.419` s |
| real tile three west, one above | `(-3,0,-1)` | `(-96,0)` | 0.84210527 | isolated burst, `2.849-5.325` s |
| real tile three west, one below | `(-3,0,+1)` | `(-96,0)` | 0.84210527 | isolated burst, `1.709-4.466` s |
| real tile four floors above | `(0,0,-4)` | `(0,0)` | 1.00000000 | isolated burst, `1.987-4.832` s |
| real tile four floors below | `(0,0,+4)` | `(0,0)` | 1.00000000 | isolated burst, `2.110-4.897` s |

The different peak levels in those recordings are not z attenuation: GFB
randomly selected files 303-305 and pitches within the catalog range. The
client trace is decisive: z never changed `relative_px` or `position_gain`.
Horizontal distance three used `1 - 3/19` above and below, while same-x/y used
gain 1.0 even at four floors' separation.

The listener-movement case has a usable official comparison. In CrystalOTC,
effect 1016 was scheduled once at gain 1.0; video shows the player descend one
floor roughly half a second after playback began, and the AAC burst remains
continuous from `1.313-4.022` seconds with no detected interruption longer than
40 ms. In the official client, video likewise shows one GFB followed by a
one-floor descent during playback, and its application-audio burst remains
continuous from `2.042-4.429` seconds. Official server serialization and
internal scheduling are unobservable and must not be inferred.

The official targeted-rune cross-floor attempt displayed `Destination is out
of range` and was rejected before a valid audio action. It is excluded rather
than counted as silence. Therefore the official client's attenuation or
suppression rule for a newly received cross-floor positioned sound remains
unresolved. Do not change CrystalOTC's z formula or enable multifloor server
spectators without a real official cross-floor source, such as a controlled
second actor or environmental source.

Authoritative evidence is under
`/tmp/crystal-sound-parity-run-20260824-01`. Official filenames start with
`official-`; Crystal filenames start with `crystal-`. The failed
`official-gfb-floor-same-xyz-user-01.invalid-writer.mov`, the contaminated
official retry, and all previously marked `assistant-pilot`,
`invalid-interrupted`, or `invalid-writer` files are excluded evidence.

## Next behavioral priority: burst scheduling and overlap

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

1. a real official cross-floor source obtained without targeted-rune range
   rejection, with server delivery kept separate from client attenuation;
2. no temporary diagnostic logging left in either repository;
3. the recorder's short synchronized workflow preserved until the long sparse
   AVFoundation failure is independently understood;
4. builds/tests run and logical commits prepared.

Distance geometry through seven horizontal tiles is settled. The floor
diagnostic is complete, but the official new-sound cross-floor rule still needs
an oracle action. In parallel, the burst-policy matrix is the next high-risk
custom behavior; keep its deterministic server fixture separate from
positional experiments.
