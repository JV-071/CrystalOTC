# Sound parity lab

This lab measures the official client's observable sound behaviour and compares
it with CrystalOTC. It records four separate boundaries rather than treating a
speaker recording as proof of why a sound did or did not happen:

1. crystalserver serializes a sound packet for one player;
2. CrystalOTC decodes that packet;
3. CrystalOTC's scheduler accepts, resolves, or rejects the request;
4. audio becomes audible in the official or Crystal client.

All machine-readable timelines use JSON Lines with schema
`crystal-sound-trace-v1`. Every native trace event carries both a monotonic
session clock and a Unix-epoch clock in microseconds.

## Build the recorder

The native macOS recorder uses ScreenCaptureKit, so the official client's video
and application audio share one media clock:

```sh
swift build -c release --package-path tools/sound-parity-capture
```

The first run may trigger macOS's Screen Recording permission prompt. Grant the
terminal or Codex host permission, then restart that process before recording.

## Build the 15.32 fingerprint index

The index is generated from the archived official soundbank, not from renamed
or hand-labelled samples. `ffmpeg` calculates the spectra and the standard
library's SQLite module stores absolute and pitch-relative fingerprints.

```sh
python3 tools/sound_parity_lab.py index
```

The generated database is placed under `build/sound-parity/` and is not a
source artifact. Rebuild it whenever the archived soundbank changes.

## Record the official client

Start Tibia first. The installed client identifies itself as
`com.tibia.client`; selecting by PID is also supported.

```sh
mkdir -p /tmp/crystal-sound-official
tools/sound-parity-capture/.build/release/sound-parity-capture \
  --bundle-id com.tibia.client \
  --duration 60 \
  --output /tmp/crystal-sound-official/official.mov
```

The adjacent JSON file records the process and the wall-clock time of the first
captured sample. The MOV includes the app's screen and audio, which makes
visual-to-audio onset measurable without synchronizing two recording devices.

Network capture adds arrival timing but not decrypted sound IDs:

```sh
sudo python3 tools/sound_parity_lab.py capture-packets \
  --interface pktap,all \
  --filter 'tcp' \
  --duration 60 \
  --output /tmp/crystal-sound-official/official.pcap
```

Convert the PCAP's packet arrival times into the same epoch-based JSONL format
used by the audio and native traces. The encrypted packets cannot reveal sound
IDs, but their bursts can be aligned with the recorded screen and sound onset:

```sh
python3 tools/sound_parity_lab.py packet-timeline \
  /tmp/crystal-sound-official/official.pcap \
  --output /tmp/crystal-sound-official/network.jsonl
```

Filesystem observation can confirm whether the client reads an OGG during the
scenario. A preload or memory-mapped soundbank may legitimately produce no read
at playback time.

```sh
sudo python3 tools/sound_parity_lab.py trace-files \
  --pid "$(pgrep -f '/Tibia.app/Contents/MacOS/client$')" \
  --duration 60 \
  --output /tmp/crystal-sound-official/filesystem.txt
```

## Recognize the official timeline

```sh
python3 tools/sound_parity_lab.py identify \
  /tmp/crystal-sound-official/official.mov \
  --metadata /tmp/crystal-sound-official/official.json \
  --output /tmp/crystal-sound-official/official-sounds.jsonl
```

Each `audio.match` event names the soundbank audio-file ID, filename, owning
numeric effects/ambiences/music templates, capture offset, vote count, and
confidence. The default confidence threshold is intentionally conservative;
lower it only while reviewing the corresponding audio/video manually.

## Record CrystalOTC and crystalserver

Tracing is opt-in and uses a bounded asynchronous writer. Normal runs do not
open a trace file or pay for JSON serialization.

Start the server with:

```sh
CRYSTALSERVER_SOUND_TRACE=/tmp/crystal-sound-run/server.jsonl \
  ../crystalserver/build/macos-release/bin/crystalserver
```

Start the native client executable directly so the environment reaches it:

```sh
CRYSTALOTC_SOUND_TRACE=/tmp/crystal-sound-run/client.jsonl \
  build/macos-cocoa/bin/CrystalOTC.app/Contents/MacOS/CrystalOTC
```

The client trace includes:

- packet sound ID, source, world position, and screen-relative position;
- resolved OGG, channel, randomized gain, and pitch;
- source start and audible end;
- every rejection reason, including filters and source refusal;
- the current custom four-effects-per-100-ms limit;
- the current custom identical-file 150-ms throttle;
- location ambience loops and delayed-effect deadlines;
- item-ambience selection, hold, swap, fade, resume, and stop transitions;
- music selection, one-shot playback, and fade behaviour.

The server trace records the exact main/secondary IDs, sources, world position,
recipient, ambience, and music packet serialized for each player.

## Compare runs

Run the same controlled scenario in both clients, starting each recording just
before the first deliberate action. The comparator aligns audio-ID sequences,
so the sessions do not need identical wall-clock start times. Relative timing
is measured from the first aligned sound.

```sh
python3 tools/sound_parity_lab.py compare \
  --official /tmp/crystal-sound-official/official-sounds.jsonl \
  --client /tmp/crystal-sound-run/client.jsonl \
  --server /tmp/crystal-sound-run/server.jsonl \
  --output /tmp/crystal-sound-run/comparison.json
```

This writes JSON for automated analysis and Markdown for review. The report
separates:

- missing and extra audible files;
- per-match relative timing error;
- server-to-client packet delivery latency;
- packets emitted by the server but absent at the client;
- ambience and music anthem delivery as well as positioned sound effects;
- packets received by the client and every scheduler rejection reason.

## Controlled scenario matrix

Change one variable at a time and repeat each case enough times to reveal
random choices:

| Family | Cases |
| --- | --- |
| Distance | source at 0 through 9 tiles in each cardinal direction |
| Floors | same tile, one floor above, one floor below, visible adjacent floor |
| Bursts | 1 through 8 simultaneous effects and identical effects at 25-250 ms spacing |
| Ownership | own attack, another player, creature, boss, global/NPC |
| Movement | stationary, walking source, walking listener, teleport, floor change |
| Ambience | enter, remain, cross boundary, leave, rapidly re-enter |
| Item loops | counts immediately below/at/above every threshold and radius |
| Music | town entry, combat, repeated anthem, mute/unmute, track completion |
| Load | normal latency, injected delay, packet burst after a stall |

## Verified baseline: light healing

The first isolated official/Crystal comparison uses `exura` at the same Thais
temple tile with music and ambience muted. The archived official catalog maps
light healing to effect `1001`, audio file `323`, gain `0.5`, and randomized
pitch `0.9` through `1.1`. The isolated official recording has the same
time-frequency structure as that asset.

The initial Crystal run also played effect `2782` (audio file `684`), the
generic console-message notification, immediately beside effect `1001`. The
cause was crystalserver serializing successful spell incantations as ordinary
`TALKTYPE_SAY`. The parity path is:

1. crystalserver sends the incantation as `TALKTYPE_SPELL_USE`;
2. the console renders `MessageModes.Spell` without a chat notification;
3. the world sound packet remains the sole owner of spell audio.

The corrected isolated run emitted and played one effect `1001` and no effect
`2782`. Its recorded spectrum begins directly with the healing asset instead
of the former 75-ms notification beep. In that run, server-to-client delivery
was 11.1 ms, scheduling followed 0.07 ms after packet receipt, and captured
audible onset followed the playback command by 104 ms. Treat the last value as
an end-to-end media-stack measurement for that run, not as a hard-coded client
delay.

A repeated isolated sample confirmed both pitch and relative playback timing.
For ten official casts, pitch estimated from normalized inverse audible duration
ranged from `0.9178` to `1.0818` (mean `1.0035`, sample standard deviation
`0.0614`). The matching ten Crystal trace values ranged from `0.9147` to
`1.0973` (mean `1.0155`, sample standard deviation `0.0616`). Both distributions
are consistent with the catalog's uniform `0.9` through `1.1` range.

More importantly, the official recording's audio followed the first visible
healing-effect frame by 35.3 ms on average (19.7-46.8 ms). Crystal's nine
unambiguous video samples averaged 34.7 ms (27.1-42.1 ms); one frame sequence
was excluded because an overlapping animation made its visual onset ambiguous.
Across all eleven traced Crystal casts in that capture, server-to-client
delivery averaged 8.72 ms and playback scheduling followed packet receipt by
0.074 ms on average. No cast was dropped or throttled. This supports preserving
the current immediate scheduling path: the roughly 106-ms trace-command to
captured-audio interval includes the display/capture pipeline, while the
within-recording audio-to-visual relationship matches the official client.

The result is an observable playback specification. It does not claim to
recover CipSoft's source code; it supplies enough evidence to replace
CrystalOTC's custom policies only when a controlled official-client measurement
supports the replacement.

## Verified baseline: positioned great fireball rune

The horizontal GFB experiment held the listener still and cast at equal left
and right offsets of 1, 3, 5, and 7 tiles. The official recording showed no
directional panning: changing the sign of the horizontal offset did not swap or
materially alter the two channels. It preserved the stereo image already in the
asset and changed only its gain.

The mean official channel peaks were `-8.905`, `-9.965`, `-11.050`, and
`-12.465` dBFS at distances 1, 3, 5, and 7. Relative to the one-tile sample,
those are `0`, `-1.060`, `-2.145`, and `-3.560` dB. They fit a linear amplitude
fade to silence at 19 tiles:

```text
positionGain = clamp(1 - distanceTiles / 19, 0, 1)
```

The predicted relative levels are `0`, `-1.023`, `-2.184`, and `-3.522` dB.
A free linear fit to the four measured amplitudes crosses zero at 18.964 tiles.
OpenAL source positioning is not equivalent: it ignores position for stereo
buffers and, for mono buffers, introduces panning that the official recording
does not exhibit. CrystalOTC therefore applies the measured gain directly and
leaves the stereo source unpositioned.

The server also has to preserve the selected rune tile. Before correction, the
client sent the target at three tiles left and the Lua combat variant retained
that position, but generic rune post-cast handling serialized both sound IDs at
the caster. Rune post-cast sounds now use the position variant or targeted
creature position; instant spells keep their caster-centered behaviour. A
post-fix trace confirmed server world position `(32299, 32262, 7)`, client
offset `(-96, 0)` pixels, and gain `0.84210527` for a listener at
`(32302, 32262, 7)`.

The post-fix application-audio capture independently validates the mixer. For
audio file 304, its mean stereo peak changed by `-1.107` dB from distance 1 to
3 and by `-2.168` dB from distance 1 to 5, against predictions of `-1.023` and
`-2.184` dB. For audio file 303, the measured distance-3 to distance-5 change
was `-1.137` dB against a predicted `-1.160` dB. Comparing like files controls
for GFB's randomized asset and pitch selection.

## Verified distance geometry: cardinals and diagonals

The follow-up experiment held both listeners stationary and targeted three
tiles north, three tiles south, and all four `(3,3)` diagonals. Two clean
official recordings supplied twelve isolated GFB events in total. Video frames
immediately before each cast show the target outline exactly three displayed
tiles away on each intended axis; this rules out cursor placement as an
explanation for the measured level difference.

The official GFB files retain distinct stereo peak biases even though source
position does not pan them. File 303 is about 1 dB left-heavy, file 304 is
balanced, and file 305 is about 0.2 dB right-heavy. Using that invariant plus
the pitch-relative spectral match allowed the randomized file and pitch to be
controlled before comparing levels. Three same-file comparisons measured the
diagonal below the cardinal by `-0.80`, `-0.75`, and `-0.95` dB, mean
`-0.8333` dB.

For a cardinal distance of 3 and a diagonal offset of `(3,3)`, the candidate
diagonal-minus-cardinal predictions are:

| Norm | Predicted delta | Error from same-file official mean |
| --- | ---: | ---: |
| Euclidean | -0.7022 dB | 0.1311 dB |
| Chebyshev | 0.0000 dB | 0.8333 dB |
| Manhattan | -1.8035 dB | 0.9702 dB |

Euclidean is the only compatible rule. CrystalOTC already uses `std::hypot`,
so no positional formula change was required. Its traced gains were
`0.84210527` for `(0,±3)` and `0.77670312` for every `(±3,±3)` diagonal.

The final synchronized Crystal capture verified all four boundaries for six
casts:

- six server packets carried the exact six target world positions;
- all six arrived at the client with `(0,±96)` or `(±96,±96)` relative pixels;
- all six resolved and played, with mean packet delivery of `7.745` ms and mean
  packet-to-play scheduling of `0.038` ms;
- the only drops were the six expected generic effect-10 `unknown_effect`
  results, with no unexpected scheduler drops;
- all six audible onsets are present in the application AAC track; five tails
  are complete and the last onset is present but its tail reaches the recording
  boundary.

After correcting the five complete Crystal samples for their traced source file
and pitch, the mean diagonal-minus-cardinal level was `-0.6917` dB. The traced
Euclidean gains predict `-0.7022` dB, an absolute error of `0.0106` dB.

The evidence is under
`/tmp/crystal-sound-parity-run-20260823-02`. The authoritative files are
`official-gfb-cardinal-diagonal-user-02.mov`,
`official-gfb-cardinal-diagonal-user-03.mov`,
`official-gfb-cardinal-diagonal-analysis.json`,
`server-cardinal-diagonal.jsonl`, `client-cardinal-diagonal.jsonl`,
`crystal-gfb-cardinal-diagonal-user-04.mov`, and
`crystal-gfb-cardinal-diagonal-analysis.json`.

## Verified distance 7

The user-operated retry captured one isolated GFB at seven tiles left and one
at seven tiles right. Each action was verified independently at all three
boundaries:

| Cast | Server target | Client relative px | File / pitch | Traced gain | Corrected audio delta |
| --- | --- | ---: | --- | ---: | ---: |
| L7 | `(32301,32253,7)` | `(-224,0)` | 305 / 1.010917 | 0.63157892 | -3.75 dB |
| R7 | `(32316,32249,7)` | `(224,0)` | 304 / 0.930067 | 0.63157892 | -4.05 dB |

The server-to-client delivery latencies were `6.856` ms and `11.210` ms, and
the client packet-to-play latencies were `0.101` ms and `0.041` ms. The two
isolated AAC bursts began `169.571` ms and `118.203` ms after their respective
server commands. Both gains exactly match `1 - 7/19` to float precision.

After correcting the captured peaks for the selected source file and traced
pitch, the two audio deltas average `-3.90` dB. The expected delta for
`0.6315789474` gain is `-3.9914` dB, leaving `0.0914` dB absolute error.

The authoritative files are `crystal-gfb-distance7-user-01.mov/json`,
`crystal-gfb-r7-user-01.mov/json`, and
`crystal-gfb-distance7-analysis.json` in the same run-02 evidence directory.
The first file contains the complete L7 event; its later R7 action occurred
after that recorder window ended and therefore is trace-only in that window.
The dedicated R7 file supplies the matching audio evidence.

Two capture hazards were isolated during the run. Interrupting the recorder
before its fixed duration prevents AVAssetWriter from finalizing the MOV, so a
user saying “done” is not a reason to send SIGINT. Long captures started before
the operator was ready also produced sparse Crystal streams and intermittent
AVFoundation `-11800/-16122` failures. Wait for an explicit ready signal, send
an unmistakable live cue, keep the capture narrowly timed, and let it finish
normally. The recorder now stops accepting late queued samples before marking
its inputs finished and reports whether a future writer failure occurred while
starting, appending video, appending audio, or finishing.

## Floor/z diagnostic result

The 2026-08-24 run kept three different boundaries separate: normal server
spectator delivery, forced client packet/scheduler handling, and captured
application audio. Evidence is under
`/tmp/crystal-sound-parity-run-20260824-01`.

Two normal server actions requested effect 1016 at the listener's x/y on the
adjacent floor above and below. The action confirmation is visible in each
capture, but the server trace has no corresponding `server.send_sound_effect`,
the client has no packet or scheduler event, and the complete AAC tracks are
silent. `Game::sendSingleSoundEffect` selects spectators with the default
same-floor query, so these are delivery suppressions rather than audio
failures.

A temporary diagnostic binding bypassed only spectator selection and directly
serialized a positioned sound packet to the test player. It was name-restricted
and removed after recording. The following real-tile cases all produced one
server event, one matching client packet, one scheduler play, and one isolated
application-audio burst:

| Offset from listener | Client relative px | Position gain | Evidence stem |
| --- | ---: | ---: | --- |
| `(0,0,0)` | `(0,0)` | 1.00000000 | `crystal-gfb-floor-direct-same-xyz-user-01` |
| `(0,0,-1)` | `(0,0)` | 1.00000000 | `crystal-gfb-floor-direct-above-same-xy-user-01` |
| `(0,0,+1)` | `(0,0)` | 1.00000000 | `crystal-gfb-floor-direct-below-same-xy-user-01` |
| `(-3,0,-1)` | `(-96,0)` | 0.84210527 | `crystal-gfb-floor-direct-above-west3-real-user-01` |
| `(-3,0,+1)` | `(-96,0)` | 0.84210527 | `crystal-gfb-floor-direct-below-west3-real-user-01` |
| `(0,0,-4)` | `(0,0)` | 1.00000000 | `crystal-gfb-floor-direct-above4-same-xy-real-user-01` |
| `(0,0,+4)` | `(0,0)` | 1.00000000 | `crystal-gfb-floor-direct-below4-same-xy-real-user-01` |

This confirms that CrystalOTC currently calculates positioned gain from x/y
only. It does not establish official parity for a newly received cross-floor
sound. The official client's targeted GFB attempt at an upper-floor tile was
rejected with `Destination is out of range`, so no server event should be
expected and no audio conclusion may be drawn from that attempt.

The already-playing listener-movement case is observable in both clients. The
Crystal recording `crystal-gfb-listener-move-down-during-playback-user-01`
shows the player descend during one scheduled effect-1016 source; its audio is
continuous from `1.313-4.022` seconds. The official recording
`official-gfb-listener-move-down-during-playback-user-01` shows one GFB and the
same one-floor descent during playback; its application audio is continuous
from `2.042-4.429` seconds. This supports retaining one-shot playback across a
listener floor change. Official server delivery and internal scheduler state
remain unobservable.

The clean official same-floor control is
`official-gfb-floor-same-xyz-user-03`. The first attempted control is renamed
`official-gfb-floor-same-xyz-user-01.invalid-writer.mov` after AVFoundation
failed to finalize it, and the second retry contains unrelated nearby sounds.
Neither is authoritative. Continue excluding every file marked
`assistant-pilot`, `invalid-interrupted`, or `invalid-writer`.
