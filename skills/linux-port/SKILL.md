---
name: linux-port
description: Linux porting workflow for NullPlayer Phase 2 (headless audio). Use when implementing or reviewing Linux playback/CLI changes, GStreamer backend behavior, output routing, or Linux-focused tests.
---

# Linux Port (Phase 2)

Use this skill for Linux port work in this repository.

## Scope

Phase 2 target is headless Linux audio:
- Linux CLI executable (`NullPlayerCLI`)
- GStreamer playback backend
- Shared playback facade/state machine
- Linux output routing + persistent IDs

Out of scope for this phase:
- AppKit/UI port
- Linux casting parity
- Linux source-browser parity for Plex/Subsonic/Jellyfin/Emby/radio queries

## Target Graph

- `NullPlayerCore`: shared models/protocols
- `NullPlayerPlayback`: cross-platform playback seam
- `NullPlayerCLI`: Linux CLI executable
- `CGStreamer`: system library bridge (Linux-only dependency for playback target)

## Key Files

### Playback seam
- `Sources/NullPlayerPlayback/Audio/AudioBackend.swift`
- `Sources/NullPlayerPlayback/Audio/AudioBackendEvent.swift`
- `Sources/NullPlayerPlayback/Audio/AudioBackendCapabilities.swift`
- `Sources/NullPlayerPlayback/Audio/AudioOutputRouting.swift`
- `Sources/NullPlayerPlayback/Audio/AudioEngineFacade.swift`
- `Sources/NullPlayerPlayback/Audio/PortableAudioAnalysis.swift`

### Linux backend
- `Sources/NullPlayerPlayback/Audio/Linux/GStreamerPipelineBuilder.swift`
- `Sources/NullPlayerPlayback/Audio/Linux/GStreamerBusBridge.swift`
- `Sources/NullPlayerPlayback/Audio/Linux/GStreamerOutputRouter.swift`
- `Sources/NullPlayerPlayback/Audio/Linux/LinuxGStreamerAudioBackend.swift`

### Linux CLI
- `Sources/NullPlayerCLI/main.swift`
- `Sources/NullPlayerCLI/LinuxCLIOptions.swift`
- `Sources/NullPlayerCLI/LinuxSourceResolver.swift`
- `Sources/NullPlayerCLI/LinuxCLIDisplay.swift`
- `Sources/NullPlayerCLI/LinuxCLIPlayer.swift`

### Tests
- `Tests/NullPlayerPlaybackTests/AudioEngineFacadeTests.swift`
- `Tests/NullPlayerPlaybackTests/PortableAudioAnalysisTests.swift`
- `Tests/NullPlayerCLITests/LinuxSmokeTests.swift`

## Architecture Rules

- `AudioEngineFacade` owns playlist state, shuffle/repeat traversal, token gating, and delegate ordering.
- Backends emit `AudioBackendEvent`; they do not directly mutate playlist state.
- Output routing always uses `AudioOutputRouting` + `AudioOutputDevice.persistentID`.
- Persisted output key is `selectedOutputDevicePersistentID`.

## Linux Backend Behavior

`LinuxGStreamerAudioBackend` capabilities:
- output selection: true
- gapless: false
- sweet fade: false
- EQ: true (10-band)
- waveform frames: false

Pipeline shape (`GStreamerPipelineBuilder`):
- `playbin3` + custom `audio-sink` bin
- `audioconvert ! audioresample ! equalizer-nbands ! tee`
- sink branch: `queue ! volume ! autoaudiosink`
- analysis branch: `queue leaky=downstream max-size-buffers=2 ! appsink`
- appsink caps: `audio/x-raw,format=F32LE,layout=interleaved,channels=2`

## Linux CLI Contract

Supported flags:
- `--cli`, `--help`, `--list-outputs`
- `--shuffle`, `--repeat-all`, `--repeat-one`
- `--volume <0-100>`
- `--eq <off|flat|10 comma-separated gains>`
- `--output <name-or-persistent-id>`
- `--no-art`
- positional local paths and `http://` / `https://` URLs

Unsupported flags must fail fast (do not silently ignore).

## Invariants To Preserve

- Bus timeout is not fatal: `gst_bus_timed_pop_filtered(...) == nil` means keep polling.
- Failed pipeline preparation must emit `.loadFailed` for the requested track/token.
- Stale token events must be dropped by facade.
- Initial load delegate order must stay `track -> time -> state`.

## Validation Checklist

```bash
swift test --filter AudioEngineFacadeTests
swift test --filter PortableAudioAnalysisTests
swift test --filter LinuxSmokeTests
```

Linux smoke tests use:
- generated WAV fixtures
- loopback HTTP server for streaming smoke
- `GST_AUDIO_SINK=fakesink`

## Practical Implementation Sequence

1. Add/adjust shared protocol or event shape in `NullPlayerPlayback`.
2. Update `AudioEngineFacade` token/state handling first.
3. Apply matching Linux backend changes.
4. Keep Linux CLI parsing strict and explicit.
5. Add or update focused playback/CLI tests.
6. Run filtered suites before broad `swift test`.

## Common Regressions

- Missing `.loadFailed` path when pipeline init fails.
- Bus processing thread exits after idle timeout.
- Output selection code still assuming Darwin numeric IDs.
- Linux CLI accidentally importing AppKit or depending on app-only managers.
