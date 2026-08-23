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

The result is an observable playback specification. It does not claim to
recover CipSoft's source code; it supplies enough evidence to replace
CrystalOTC's custom policies only when a controlled official-client measurement
supports the replacement.
