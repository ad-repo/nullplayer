# Phase 2 Tasks: GStreamer Audio on Linux

Each task below is self-contained and sized to fit a restricted context window. Tasks within a PR are sequential. PRs are sequential (each builds on the prior).

Reference plan: `docs/superpowers/plans/2026-04-12-linux-audio-phase-2.md`

---

## PR 1: Package And Bootstrap Split

### Task 1.1: Add NullPlayerPlayback target to Package.swift
**Files**: `Package.swift`
**Do**:
- Add a new `.target(name: "NullPlayerPlayback", dependencies: ["NullPlayerCore"], path: "Sources/NullPlayerPlayback")`
- Add `swiftSettings: [.define("HAVE_GSTREAMER", .when(platforms: [.linux]))]` to that target
- Create `Sources/NullPlayerPlayback/` directory with a placeholder file (e.g. `Placeholder.swift` exporting nothing)
- Do NOT add CGStreamer or NullPlayerCLI yet
**Verify**: `swift build` succeeds on macOS with no behavior change

### Task 1.2: Make macOS-only dependencies conditional
**Files**: `Package.swift`
**Do**:
- Wrap `KSPlayer`, `AudioStreaming`, `CProjectM`, `CAubio` package declarations in `#if os(macOS)` or use `.when(platforms:)` conditions on the dependency references in the NullPlayer target
- Keep all four available on macOS; exclude from Linux
- `FlyingFox`, `ZIPFoundation`, `SQLite.swift` stay unconditional (Foundation-compatible)
**Verify**: `swift build` on macOS still succeeds. `swift package dump-package` shows conditional deps.

### Task 1.3: Add CGStreamer system library target
**Files**: `Package.swift`, `Sources/CGStreamer/module.modulemap`, `Sources/CGStreamer/gstreamer_link.h`
**Do**:
- Add `.systemLibrary(name: "CGStreamer", path: "Sources/CGStreamer")` to Package.swift
- Create `Sources/CGStreamer/module.modulemap` that links `gstreamer-1.0`, `gstreamer-audio-1.0`, `gstreamer-app-1.0`, `gstreamer-pbutils-1.0` via explicit linker flags (SPM systemLibrary only takes one pkgConfig)
- Include GStreamer and GLib headers via the modulemap
- Make `NullPlayerPlayback` depend on `CGStreamer` only on Linux: `.product(name: "CGStreamer", condition: .when(platforms: [.linux]))`
**Verify**: macOS build unaffected. Package resolves without errors.

### Task 1.4: Add NullPlayerCLI executable target
**Files**: `Package.swift`, `Sources/NullPlayerCLI/main.swift`
**Do**:
- Add `.executableTarget(name: "NullPlayerCLI", dependencies: ["NullPlayerCore", "NullPlayerPlayback"], path: "Sources/NullPlayerCLI")`
- Create `Sources/NullPlayerCLI/main.swift` as a minimal stub: `import Foundation; print("NullPlayerCLI stub"); RunLoop.main.run()`
- Do NOT import AppKit anywhere in NullPlayerCLI
**Verify**: `swift build --target NullPlayerCLI` succeeds. `swift build` (main NullPlayer) still works.

---

## PR 2: Minimal Shared Playback Seam

### Task 2.1: Define AudioBackendEvent and supporting types
**Files**: `Sources/NullPlayerPlayback/Audio/AudioBackendEvent.swift` (new)
**Do**:
- Create file with `AudioBackendEvent` enum, `PlaybackFailure` struct, `AnalysisFrame` struct
- Use `NullPlayerCore.Track` (qualified) in `loadFailed` case
- Use `TimeInterval` for `monotonicTime` (cross-platform)
- Import `NullPlayerCore` and `Foundation`
**Reference**: See "Backend Event Surface" in the plan for exact shapes

### Task 2.2: Define AudioBackendCapabilities
**Files**: `Sources/NullPlayerPlayback/Audio/AudioBackendCapabilities.swift` (new)
**Do**:
- Create `AudioBackendCapabilities` struct with: `supportsOutputSelection`, `supportsGaplessPlayback`, `supportsSweetFade`, `supportsEQ`, `supportsWaveformFrames`, `eqBandCount`
- All `let` properties, `Sendable`
**Reference**: See "Backend Capabilities" in the plan

### Task 2.3: Define AudioOutputRouting protocol
**Files**: `Sources/NullPlayerPlayback/Audio/AudioOutputRouting.swift` (new)
**Do**:
- Create `AudioOutputRouting` protocol: `outputDevices`, `currentOutputDevice`, `refreshOutputs()`, `selectOutputDevice(persistentID:) -> Bool`
- Import `NullPlayerCore` for `AudioOutputDevice` (will be revised in PR 3, but use current type for now)
**Reference**: See "Routing Surface" in the plan

### Task 2.4: Define AudioBackend protocol
**Files**: `Sources/NullPlayerPlayback/Audio/AudioBackend.swift` (new)
**Do**:
- Create `AudioBackend` protocol conforming to `AudioOutputRouting`
- Properties: `capabilities`, `eventHandler`
- Methods: `prepare()`, `shutdown()`, `load(track:token:startPaused:)`, `play(token:)`, `pause(token:)`, `stop(token:)`, `seek(to:token:)`, `setVolume(_:token:)`, `setBalance(_:token:)`, `setEQ(enabled:preamp:bands:token:)`, `setNextTrackHint(_:token:)`
- Use `NullPlayerCore.Track` (qualified) for all track parameters
**Reference**: See "Backend Protocol" in the plan

### Task 2.5: Define PlaybackPreferencesProviding and PlaybackEnvironmentProviding
**Files**: `Sources/NullPlayerPlayback/Audio/PlaybackEnvironment.swift` (new)
**Do**:
- `PlaybackPreferencesProviding` protocol: `gaplessPlaybackEnabled`, `volumeNormalizationEnabled`, `sweetFadeEnabled`, `sweetFadeDuration`, `selectedOutputDevicePersistentID`
- `PlaybackEnvironmentProviding` protocol: `reportNonFatalPlaybackError(_:)`, `makeTemporaryPlaybackURLIfNeeded(for:)`, `beginSleepObservation(_:)`
- `PlaybackSleepEvent` enum: `.willSleep`, `.didWake`
**Reference**: See "Preferences And Environment" in the plan

### Task 2.6: Remove placeholder file from NullPlayerPlayback
**Files**: `Sources/NullPlayerPlayback/Placeholder.swift`
**Do**: Delete the placeholder from Task 1.1 now that real files exist
**Verify**: `swift build` succeeds

---

## PR 3: Portable Routing Types

### Task 3.1: Revise AudioOutputDevice to use persistentID
**Files**: `Sources/NullPlayerCore/Audio/AudioTypes.swift`
**Do**:
- Replace `id: UInt32` + `uid: String` with `persistentID: String` + `backend: String` + `backendID: String?` + `transport: AudioOutputTransport` + `isAvailable: Bool`
- Add `AudioOutputTransport` enum: `builtIn`, `usb`, `bluetooth`, `airplay`, `network`, `unknown`
- Remove `isWireless` and `isAirPlayDiscovered` (transport enum replaces them)
- Update `Equatable` to compare on `persistentID`
- Update `Hashable` to hash on `persistentID`
**Reference**: See "Revised Output Device Shape" in the plan

### Task 3.2: Update AudioOutputProviding to use persistentID
**Files**: `Sources/NullPlayerCore/Audio/AudioOutputProviding.swift`
**Do**:
- Rename `currentDeviceUID` to `currentOutputDevice: AudioOutputDevice?`
- Rename `selectDevice(uid:)` to `selectOutputDevice(persistentID:) -> Bool`
- Keep `outputDevices` and `refreshDevices()` (rename `refreshDevices` to `refreshOutputs` for consistency with `AudioOutputRouting`)
**Verify**: Will break compilation of conforming types — that's expected, fixed in Task 3.3

### Task 3.3: Update AudioOutputManager to conform to revised AudioOutputProviding
**Files**: `Sources/NullPlayer/Audio/AudioOutputManager.swift`
**Do**:
- Update `AudioOutputManager` to conform to revised protocol
- Map CoreAudio device IDs to `persistentID` (use `uid` as the `persistentID` value for Darwin)
- Set `backend: "CoreAudio"`, `transport` based on current `isWireless`/`isAirPlayDiscovered` logic
- Update `currentOutputDevice` and `selectOutputDevice(persistentID:)` signatures
**Verify**: `swift build` succeeds. macOS playback and output switching still work.

### Task 3.4: Migrate output device persistence to canonical key
**Files**: `Sources/NullPlayer/Audio/AudioOutputManager.swift`, `Sources/NullPlayer/Audio/AudioEngine.swift`, `Sources/NullPlayer/App/AppStateManager.swift`
**Do**:
- Canonical key: `selectedOutputDevicePersistentID`
- On first read, check old keys in order: `selectedOutputDeviceUID`, `selectedAudioOutputDeviceUID`
- Write only `selectedOutputDevicePersistentID` going forward
- Remove duplicate writes from AudioEngine (lines ~4815-4819) and AppStateManager
- Single owner for persistence: AudioOutputManager
**Verify**: Fresh launch migrates old key. Output selection persists across restarts.

---

## PR 4: Darwin Facade Extraction

### Task 4.1: Create AudioEngineFacade with playlist state
**Files**: `Sources/NullPlayerPlayback/Audio/AudioEngineFacade.swift` (new)
**Do**:
- Create `AudioEngineFacade` class that owns: playlist array, currentIndex, shuffleEnabled, repeatEnabled, loadToken (UInt64), seekToken
- Implement next/previous/advance logic (extract from AudioEngine.swift)
- Implement token validation: `isCurrentToken(_:) -> Bool`
- Implement backend event handler that validates tokens before forwarding to delegate
- Hold a reference to `any AudioBackend`
- Conform to enough of `AudioPlaybackProviding` for transport controls and playlist management
**Important**: This is the largest task in the PR. Focus on playlist state and token validation first, then transport forwarding.

### Task 4.2: Extract delegate ordering into facade
**Files**: `Sources/NullPlayerPlayback/Audio/AudioEngineFacade.swift`
**Do**:
- Implement the canonical delegate delivery sequences from the plan:
  - Load: `audioEngineDidChangeTrack` -> `audioEngineDidUpdateTime` -> `audioEngineDidChangeState`
  - Seek: one immediate time update, then resume cadence
  - EOS: advance or stop, with token validation
  - Load failure: `audioEngineDidFailToLoadTrack`, then advance or stop
  - Load interrupted by load: stop(old token), load(new token), drop stale events
- Rate-limit time updates to a stable UI cadence
- Only the facade delivers delegate callbacks — backends must not call delegates directly

### Task 4.3: Wire AudioEngine as DarwinAudioBackend
**Files**: `Sources/NullPlayer/Audio/AudioEngine.swift`, `Sources/NullPlayer/Audio/DarwinAudioBackend.swift` (new, optional — or keep in AudioEngine)
**Do**:
- Make AudioEngine conform to `AudioBackend` protocol
- Map existing methods to protocol: `load`, `play`, `pause`, `stop`, `seek`, `setVolume`, `setBalance`, `setEQ`, `setNextTrackHint`, `prepare`, `shutdown`
- Emit `AudioBackendEvent` via `eventHandler` instead of calling delegates directly where feasible
- This can be incremental — start with transport controls, then EOS/error events
**Important**: Do NOT break existing macOS behavior. The facade and direct AudioEngine usage should coexist during migration.

---

## PR 5: Darwin Output Router + Environment

### Task 5.1: Isolate AudioOutputManager behind AudioOutputRouting
**Files**: `Sources/NullPlayer/Audio/AudioOutputManager.swift`
**Do**:
- Make AudioOutputManager conform to `AudioOutputRouting` (from NullPlayerPlayback)
- Ensure CLI and engine code access output routing only through the protocol, not `AudioOutputManager.shared` directly
- Audit `CLIPlayer.swift` and `CLIQueryHandler.swift` for direct `AudioOutputManager` references and route through the abstraction

### Task 5.2: Implement DarwinPlaybackPreferences
**Files**: `Sources/NullPlayer/Audio/DarwinPlaybackPreferences.swift` (new)
**Do**:
- Conform to `PlaybackPreferencesProviding`
- Back each property with `UserDefaults` reads/writes
- Use canonical `selectedOutputDevicePersistentID` key from Task 3.4
- Wire into AudioEngineFacade

### Task 5.3: Implement DarwinPlaybackEnvironment
**Files**: `Sources/NullPlayer/Audio/DarwinPlaybackEnvironment.swift` (new)
**Do**:
- Conform to `PlaybackEnvironmentProviding`
- `reportNonFatalPlaybackError`: show `NSAlert` on main thread
- `makeTemporaryPlaybackURLIfNeeded`: extract existing NAS temp-copy logic from AudioEngine
- `beginSleepObservation`: wrap `NSWorkspace.shared.notificationCenter` sleep/wake observers (currently in AudioEngine lines 558-581)
- Remove direct NSWorkspace/NSAlert usage from AudioEngine once wired through environment

---

## PR 6: Linux CLI MVP

### Task 6.1: Linux CLI entry point
**Files**: `Sources/NullPlayerCLI/main.swift`
**Do**:
- Replace stub with real Foundation-only entry point
- Parse CLI arguments (reuse `CLIOptions` parsing logic, extract if needed)
- Reject unsupported Linux flags early with a clear help message (see plan for full flag list)
- Set up signal handlers (SIGINT, SIGTERM)
- Bootstrap a Foundation RunLoop (no NSApplication)
**Constraint**: No AppKit imports anywhere in NullPlayerCLI compile path

### Task 6.2: Linux source resolver
**Files**: `Sources/NullPlayerCLI/LinuxSourceResolver.swift` (new)
**Do**:
- Accept direct file paths (resolve to file:// URLs)
- Accept direct http:// and https:// URLs
- Reject anything else with clear error messages
- No MediaLibrary, Plex, Subsonic, Jellyfin, Emby, Radio, or Cast references

### Task 6.3: Linux CLI display
**Files**: `Sources/NullPlayerCLI/LinuxCLIDisplay.swift` (new)
**Do**:
- Text-only now-playing display (no artwork, no NSImage)
- Show: track title/filename, playback state, time position/duration, volume, EQ status
- Keyboard input handling for play/pause, next/previous, seek, volume, quit
- Terminal raw mode setup for keypress detection

### Task 6.4: Linux CLI player adapter
**Files**: `Sources/NullPlayerCLI/LinuxCLIPlayer.swift` (new)
**Do**:
- Consume only `AudioEngineFacade` and `AudioOutputRouting`
- Wire CLI display to facade delegate callbacks
- Wire keyboard input to facade transport controls
- No cast/radio/library-manager references
- No AppKit imports

---

## PR 7: Linux GStreamer Backend MVP

### Task 7.1: GStreamer pipeline builder
**Files**: `Sources/NullPlayerPlayback/Audio/Linux/GStreamerPipelineBuilder.swift` (new, `#if os(Linux)`)
**Do**:
- Build `playbin3` pipeline with custom audio-sink bin
- Audio-sink shape: `audioconvert ! audioresample ! equalizer-nbands ! tee`
- Sink branch: `queue ! volume ! <output sink>`
- Analysis branch: `queue leaky=downstream max-size-buffers=2 ! appsink`
- appsink caps: `audio/x-raw,format=F32LE,layout=interleaved` (stereo)
- Set `emit-signals=false` on appsink

### Task 7.2: GStreamer bus bridge
**Files**: `Sources/NullPlayerPlayback/Audio/Linux/GStreamerBusBridge.swift` (new, `#if os(Linux)`)
**Do**:
- Run GLib main loop on a dedicated thread
- Watch GStreamer bus for: EOS, ERROR, STATE_CHANGED, STREAM_START, DURATION_CHANGED
- Marshal bus events into `AudioBackendEvent` values
- Deliver events onto a serial backend queue, then to `eventHandler`

### Task 7.3: LinuxGStreamerAudioBackend
**Files**: `Sources/NullPlayerPlayback/Audio/Linux/LinuxGStreamerAudioBackend.swift` (new, `#if os(Linux)`)
**Do**:
- Conform to `AudioBackend` (and `AudioOutputRouting` via inheritance)
- Own one `playbin3` instance
- Implement: `prepare`, `shutdown`, `load`, `play`, `pause`, `stop`, `seek`
- Implement: `setVolume`, `setBalance`, `setEQ`
- Emit `AudioBackendEvent` for state changes, time updates, EOS, load failures
- All state mutations on a single serial queue
- Set capabilities: `supportsOutputSelection: true, supportsGaplessPlayback: false, supportsSweetFade: false, supportsEQ: true, supportsWaveformFrames: false, eqBandCount: 10`

### Task 7.4: PCM analysis frame delivery
**Files**: `Sources/NullPlayerPlayback/Audio/Linux/LinuxGStreamerAudioBackend.swift`
**Do**:
- Pull samples from appsink on the backend queue (not callback threads)
- Keep only most recent few buffers (discard old to avoid latency)
- Package as `AnalysisFrame`: interleaved stereo float32, sampleRate, monotonicTime
- Emit via `AudioBackendEvent.analysisFrame`

---

## PR 8: Shared DSP And Routing Wiring

### Task 8.1: Portable audio analysis helper
**Files**: `Sources/NullPlayerPlayback/Audio/PortableAudioAnalysis.swift` (new)
**Do**:
- Accept `AnalysisFrame` input from either backend
- Produce 75-bin `spectrumData` (FFT + binning to match current macOS shape)
- Produce 512-sample `pcmData` snapshot
- Implement silence-decay behavior (current macOS: 0.85 decay factor, zero below 0.01)
- Expose via properties that the facade can read and forward to consumers

### Task 8.2: GStreamer output router
**Files**: `Sources/NullPlayerPlayback/Audio/Linux/GStreamerOutputRouter.swift` (new, `#if os(Linux)`)
**Do**:
- Conform to `AudioOutputRouting`
- Use GStreamer device monitor to enumerate audio sinks
- Generate stable `persistentID` per plan precedence: hardware serial > device path + backend > unique name > hashed display name
- Implement `selectOutputDevice` by rebuilding the sink element in the pipeline
- Emit `AudioBackendEvent.outputsChanged` when device list changes

### Task 8.3: Wire DSP and routing into LinuxGStreamerAudioBackend
**Files**: `Sources/NullPlayerPlayback/Audio/Linux/LinuxGStreamerAudioBackend.swift`
**Do**:
- Feed `AnalysisFrame` from appsink into `PortableAudioAnalysis`
- Expose `spectrumData` and `pcmData` from the analysis helper through the facade
- Wire `GStreamerOutputRouter` as the backend's `AudioOutputRouting` implementation

---

## PR 9: Smoke Tests And Capability Gating

### Task 9.1: Facade unit tests
**Files**: `Tests/NullPlayerTests/AudioEngineFacadeTests.swift` (new)
**Do**:
- Test shuffle/repeat traversal
- Test stale generation-token invalidation (old token events dropped)
- Test delegate event ordering: load, seek, EOS, load failure, load-interrupted-by-load
- Use a mock `AudioBackend` that emits scripted events

### Task 9.2: Portable DSP tests
**Files**: `Tests/NullPlayerTests/PortableAudioAnalysisTests.swift` (new)
**Do**:
- Test 75-bin spectrum output shape from known input
- Test 512-sample pcmData shape
- Test silence decay behavior (verify decay factor and zero threshold)
- Test empty/nil input handling

### Task 9.3: Routing persistence tests
**Files**: `Tests/NullPlayerTests/AudioOutputRoutingTests.swift` (new)
**Do**:
- Test stable-ID persistence (write + read back)
- Test legacy key migration: `selectedOutputDeviceUID` -> `selectedOutputDevicePersistentID`
- Test legacy key migration: `selectedAudioOutputDeviceUID` -> `selectedOutputDevicePersistentID`
- Test missing-device fallback (persisted device no longer available)

### Task 9.4: Linux CLI smoke tests
**Files**: `Tests/NullPlayerCLITests/LinuxSmokeTests.swift` (new)
**Do**:
- Test: start playback for a local audio fixture
- Test: pause/resume
- Test: seek
- Test: next/previous
- Test: apply EQ
- Test: enumerate outputs
- Test: select output (when >1 sink present)
- Test: HTTP stream URL playback
- Use `appsink`/`fakesink` so CI validates without real speakers
**CI**: Requires `libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`, `gstreamer1.0-plugins-base`, `gstreamer1.0-plugins-good`

### Task 9.5: Verify macOS regression-free
**Files**: (no new files)
**Do**:
- Run existing `swift test` on macOS
- Manual QA: local file playback, streaming, output switching, EQ
- Verify no behavior change from the facade extraction
