---
name: visualization-cast
description: Casting the Visualizations window's picture and the app's own audio live to a Chromecast (HLS) or a DLNA TV (endless MPEG-TS) — the GL readback seam, the H.264/AAC encoder and MPEG-TS muxer, the process tap that mutes the Mac, the live playlist a Chromecast plays steadily, quality limits, the dark-window note, and the live test script. Use when changing any of it or debugging a vis cast that buffers, crackles, or will not start.
---

# Visualization Cast

Right-click the Visualizations window (Classic `ProjectMView` or Original `ModernProjectMView`) →
**Cast Visualization ▸** a Chromecast or a TV, with **Resolution ▸** 720p / 1080p (default) / 4K and
**Frame Rate ▸** 30 / 60. Whatever engine and preset the window runs goes to the TV live, with the
music; the Mac's speakers go quiet and the window turns black under a note. macOS 14.2+ (the process
tap); earlier, the item is disabled with a tooltip. `.wal` and `.wmz` hosts do not offer it
(`VisualizationContextMenu.Options.showsCast`).

## Files

| File | Owns |
|---|---|
| `Casting/VisualizationCast.swift` | The session: start/stop order, the wait for segments, the LOAD, end observers, `serving` (the one handoff the HTTP routes and `CastManager` read) |
| `Casting/VisualizationCast+HTTP.swift` | The answers for `/viscast/*`, and the one HEAD rule |
| `Casting/VisualizationCastQuality.swift` | The settings: sizes, bitrates, the 4K rule, persistence |
| `Casting/VisualizationCastEncoder.swift` | The tick-driven H.264 + AAC encoder; segments, the playlist, the live body |
| `Casting/MPEGTSMuxer.swift` | Annex B, PAT/PMT, PES, PCR, ADTS — the transport stream both receivers read |
| `Casting/ProcessAudioTap.swift` | Core Audio process tap on NullPlayer's own output, `.mutedWhenTapped`; `AudioTapRing`, the IO thread's handoff to the encoder |
| `CAudioTapRing/` (C target) | The lock-free single-producer ring under `AudioTapRing` (C11 atomics: Swift's `Atomic` needs macOS 15) |
| `Visualization/VisualizationGLView+Cast.swift` | The GL seam (surface pin, readback, black window), the note overlay, the **Cast Visualization ▸** submenu and its actions |

The rest of the app sees one seam each: `CastManager.activeSession` is nil while
`VisualizationCast.ownsCastManagers` (`serving` is set: from just before the LOAD; so the normal cast menu and its observers stay blind to it), a
normal cast first stops a vis cast (`_castCore`), `CastMetadata.isLive` / `loadMedia(isLive:)` send
`streamType: LIVE` and the DLNA live `protocolInfo`, and `LocalMediaServer` routes `GET`/`HEAD
/viscast/*` to `VisualizationCast.httpResponse`.

## Pipeline

1. **Picture.** While `castEncoder` is set, `applyCastSurfaceSize` pins the GL surface's backing to
   the cast size (`kCGLCPSurfaceBackingSize`), every engine draws its normal frame at that size into
   framebuffer 0, and `readBackForCast` reads it into a pooled `CVPixelBuffer` (flipped with vImage)
   at most once per cast frame. An offscreen FBO cannot do this: projectM 4.1 only composites into
   FBO 0 (`projectm_opengl_render_frame_fbo` is 4.2). The back buffer is then cleared, so the window
   shows black under the note. `stopRendering` is refused while casting, so a hidden window keeps
   feeding the TV.
2. **Sound.** `ProcessAudioTap` taps the app's own mixed output (so the volume slider still applies)
   and mutes it on the Mac. Creating the tap blocks ~5 s while macOS shows the *System Audio
   Recording* prompt, so it is built off the main thread. A denied permission is not detectable: the
   cast goes out silent.
3. **Encoder.** A wall-clock tick at the frame rate takes the newest frame (or repeats the last) and
   exactly one tick of audio from `AudioTapRing` (silence-padded when short, the newest 200 ms kept), so the
   stream never stalls and picture and sound share one timeline. H.264 High, real time, no
   reordering, a keyframe every second (each starts a segment), BT.709-tagged; AAC-LC 48 kHz 192 kbps.
4. **Transport.** Chromecast: `live.m3u8` + `seg-N.ts` (1 s segments). DLNA: `live.ts`, one endless
   body fed per segment (`liveBody`, buffering the newest 4).

## Measured behaviour (each is load-bearing)

- **The playlist is an EVENT playlist starting 6 s back.** A Chromecast (Ultra, 2026-11-07) starts a
  sliding live playlist at its newest segment whatever `EXT-X-START` says, then flaps
  BUFFERING/PLAYING — freezing and jumping back to the edge — for 15 s to 1:45. With
  `#EXT-X-PLAYLIST-TYPE:EVENT` it honours `EXT-X-START:TIME-OFFSET=-6.0` and plays after one
  buffering, ~5 s (3 of 3 runs at 1080p60, 2 of 2 at 30). So the playlist lists every segment from
  sequence 0 (~90 KB of text an hour) while only the newest 8 segments' bytes are kept; the session
  waits for 6 segments before the LOAD. Tried and not it: LOAD `currentTime` (a re-cast then sat in
  BUFFERING), `hlsSegmentFormat`, 2 s keyframes, ffmpeg's own TS packaging.
- **`TARGETDURATION` is the longest segment rounded up, plus one;** rounded down, a Chromecast stalled
  every few seconds.
- **Bitrates: 720p 6, 1080p 12, 4K 25 Mbps, the same at 60 fps,** with `DataRateLimits` at 1.25×.
  8 Mbps at 1080p left saturated colours blocky (H.264 keeps chroma at quarter resolution); the
  average-bitrate setting alone ran 18 Mbps against an 8 target; Goom at 1080p60 held 16–20 Mbps
  against an 18 target and a Chromecast buffered for 1:45.
- **4K casts at 30 fps only** (`VisualizationCastQuality.frameRateAllowed`; 60 fps is greyed out). A
  Samsung QN90B played 4K60 H.264 with crackling sound and 4K30 cleanly; a Chromecast Ultra rejects
  4K H.264 (LOAD_FAILED) and the session shows *The TV rejected the stream — try a lower resolution.*
- **The PCR runs level with the PTS** (ffmpeg's `-muxdelay 0`). The 0.7 s lead it had was not shown to
  matter on its own; it is what the measured configuration uses.
- **Every `HEAD /viscast/*` answers with an empty chunked body and `Connection: close`.** FlyingFox sends
  `Content-Length: 0` for an empty `Data` body, and the Samsung (which HEADs before every GET) took
  that as an empty stream and errored. The live `contentFeatures` are
  `DLNA.ORG_PN=MPEG_TS_HD_NA_ISO;DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=0170…` (no seeking), sent
  only when the client asks, like `/media/` (`sonos-casting` § *DLNA feature headers*).
- **The tap's ring is lock-free.** A try-lock on the IO thread (drop the buffer when the encoder
  holds it) still lost 1–2 IO buffers in some casts, each a ~10 ms hole, even with the reader's hold
  cut to two memcpys. The C ring never blocks either side; the log's `tap frames dropped` line at
  each stop should read 0 (only a reader stalled for 400 ms fills it).
- **Teardown runs off the main thread** (`VisualizationCast.tearDown`): the encoder's `stop` waits out
  a tick in flight and the tap's Core Audio teardown blocks. `stop` marks the encoder stopped under
  its lock first, so a render thread still holding it gets no pool buffer from the invalidated session.
- **Never finish a live stream under the encoder's lock:** `finish()` runs its termination handler,
  which takes the same lock. Switching quality on a DLNA cast deadlocked the app that way.
- **Changing resolution or frame rate is stop-then-start** (`qualityDidChange`); the TV reconnects.
- **The window is dark, the right-click menu is not.** `CastOverlayLabel` passes clicks through, so
  engines, presets and the cast submenu work over it; it names the device and the live
  engine — preset, and says the TV's picture and sound run behind, so changes can take 15–30 seconds to show there.

## Testing

`Tests/NullPlayerAppTests/VisualizationCastTests.swift` (no devices): whole 188-byte packets, the
PSI CRCs, continuity counters, PCR level with the PTS, adaptation-field stuffing, the ADTS header,
the audio ring, the EVENT playlist from a running encoder, and the 4K rule.

`skills/cast-testing/scripts/viscast-test.sh [--chromecast <name>] [--dlna <name>] [--skin <skin>]`
re-checks everything above on the LAN's TVs: Chromecast settles (PLAYING within 15 s, no BUFFERING
after), the playlist shape, the stream (size, rate, BT.709, codecs, continuous timestamps, PCR level,
no silent gaps), the dark still window, an engine switch mid-cast filling the frame, a 60 fps restart
without a hang, Stop restoring the window, the DLNA HEAD/GET and headers, and 4K at 30 only. It
relaunches the debug build and puts your cast settings back. Run it on a Classic skin and on an
Original one: the two Visualizations windows are separate hosts.

## Debugging a live defect

Read `skills/live-ui-testing/SKILL.md` first; `app-control` has the launching and driving. What is
specific here:

- **Measure the stream, not the TV.** `curl -s -m 10 http://127.0.0.1:8765/viscast/live.ts -o x.ts`
  takes a copy of what the TVs get (any cast; `live.m3u8` while a Chromecast is the target), then
  `ffprobe` / `ffmpeg` it. A Chromecast's own view is the log's `MEDIA_STATUS` lines: media time and
  state. Media time frozen through a BUFFERING spell and jumping on PLAYING is the live-edge flap.
- **One run is not a result.** The Chromecast's settle time varied 7–50 s between identical runs
  before the EVENT playlist; compare three runs per variant (the test script's `settled`).
- **The receiver is a black box; A/B against ffmpeg.** Piping each segment through `ffmpeg -c copy
  -copyts -f mpegts` before serving it tells a packaging defect from a playlist or timing one.
- **A TV-only symptom needs the user's eyes or ears** (the 4K60 crackle never showed in the
  stream); say so and change one variable for them to judge.
