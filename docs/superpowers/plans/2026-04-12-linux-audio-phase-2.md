# Phase 2: GStreamer Audio on Linux

## Summary
- Deliver a Linux-capable playback path for `NullPlayer` by introducing a GStreamer backend behind the existing shared playback contract, while keeping the macOS backend intact.
- Treat Phase 2 as a headless-audio milestone, not a general Linux port. The target artifact is a CLI-capable Linux binary that can load, control, and observe playback without any AppKit or window code in the build.
- Preserve the existing user-facing playback behaviors where they are already meaningfully portable: local files, HTTP streams, play/pause/seek/next/previous, EQ, spectrum data, playback time/state callbacks, and track-load failures.
- Accept up front that Phase 2 requires some shared playback cleanup, but keep that cleanup narrowly scoped to Linux delivery. The goal is not to perfect the playback architecture first; the goal is to introduce the minimum shared seam needed to ship a Linux backend safely.

## Current Gaps
- `Package.swift` is still macOS-only today. The package declares `.macOS(.v14)` and pulls in AppKit-only or local-framework dependencies (`KSPlayer`, `AudioStreaming`, `CProjectM`, `CAubio`) unconditionally, so Linux cannot even reach compilation without a target/dependency split.
- The CLI path is not actually headless yet. `Sources/NullPlayer/App/main.swift`, `Sources/NullPlayer/CLI/CLIMode.swift`, `Sources/NullPlayer/CLI/CLIDisplay.swift`, and `Sources/NullPlayer/CLI/CLIArtwork.swift` all import `AppKit`, and `CLIMode` still boots through `NSApplication`.
- The current output-device model is CoreAudio-shaped. `AudioOutputDevice.id` is a `UInt32` CoreAudio device ID, while the Linux plan assumes synthetic stable identifiers. That mismatch needs an explicit data-model decision before output routing can be portable.
- `AudioEngine` cannot simply keep its exact current shared API if Linux output routing is added. CLI output selection currently bypasses the shared playback protocol and talks directly to `AudioOutputManager.shared` plus `AudioEngine.setOutputDevice(_:)`, so the Linux work needs a defined routing seam, not just a new playback backend.
- The DSP requirement is broader than "spectrum". The existing engine also owns `pcmData`, 75-bin spectrum output, 576-sample waveform frames, and normalization/BPM-related analysis hooks. A Linux backend needs those shapes preserved or explicitly downgraded.
- Gapless and sweet-fade behavior are state-machine problems, not just audio-pipeline features. Any Linux design that mentions them must also specify how generation tokens, end-of-stream ownership, and stale callback suppression carry over to GStreamer.
- The shared CLI/source-resolution path is not cross-platform today. `CLISourceResolver` reaches into `MediaLibrary`, `PlexManager`, `SubsonicManager`, `JellyfinManager`, `EmbyManager`, `RadioManager`, and `CastManager`, and several of those currently import `AppKit`. Phase 2 must either extract those services into a headless module or narrow Linux CLI input scope to direct files/URLs.
- Output-device persistence ownership is currently duplicated. `AudioEngine` reads and writes `selectedOutputDeviceUID`, `AudioOutputManager` persists `selectedAudioOutputDeviceUID`, and `AppStateManager` also stores `selectedOutputDeviceUID`. The Linux plan needs one canonical persistence key plus a migration rule.
- `AudioEngine` still owns macOS process concerns unrelated to backend choice: sleep/wake via `NSWorkspace`, missing-file alerts via `NSAlert`, and direct casting/video/radio policy. A backend split alone will not make the shared facade Linux-safe without an environment/service seam.
- The playback model is split across two `Track` types today. `AudioEngine` operates on the app-side `Track`, while delegates and core protocols expose `NullPlayerCore.Track`. A cross-platform playback target cannot be made cleanly portable until that model boundary is unified or made explicit.
- The Linux playback design must cover the system dependency and runtime details needed to make it buildable: a `systemLibrary` target, pkg-config packages, GLib/GStreamer main-loop ownership, and plugin expectations for EQ, conversion, resampling, `appsink`, and device discovery.

## Revised Scope

### In Scope For Phase 2
- Buildable Linux executable target.
- Foundation-only CLI bootstrap on Linux.
- GStreamer-backed playback for local files and HTTP audio streams.
- Linux playback input surface limited to direct filesystem paths, direct `http://` and `https://` URLs, and playlists composed from those inputs.
- Shared playback control semantics with minimal contract cleanup: play, pause, stop, seek, next, previous, shuffle, and repeat (current `repeatEnabled: Bool` semantics; repeat-one vs repeat-all distinction is a CLI-layer concern, not an engine-level contract in Phase 2).
- EQ, spectrum, time updates, and track-load failure callbacks.
- Linux waveform-frame support only if it falls out naturally from the backend/DSP seam; it is not a delivery gate for the headless Linux milestone.
- Linux audio output discovery and selection with persisted stable identifiers.
- Automated smoke coverage for Linux CLI playback.

### Explicitly Out Of Scope For Phase 2
- Linux windowing or any AppKit replacement UI.
- Video playback on Linux.
- Casting parity on Linux.
- Linux parity for existing source-browser query features backed by `MediaLibrary`, Plex, Subsonic, Jellyfin, Emby, or radio managers. Those stay macOS-only until the service layer is extracted from AppKit-heavy targets.
- Album-art rendering in the Linux CLI if it requires AppKit image types. Linux may fall back to text-only now-playing output.
- Exact byte-for-byte parity with AVAudioEngine internals where backend mechanics differ, as long as public state transitions and delegate behavior remain consistent.

## Minimum Required Cleanup

### Required For Linux Delivery
- Package and target split so Linux can compile without AppKit or macOS-only frameworks.
- A small playback backend seam so the Linux binary can use GStreamer without forking all playlist/control logic.
- A portable output-routing seam so Linux CLI output selection does not depend on `AudioOutputManager`.
- A Linux-safe CLI bootstrap and source resolver limited to direct file paths and raw HTTP/HTTPS URLs.
- A narrow track-adaptation boundary so `NullPlayerPlayback` does not depend on app-only `Sources/NullPlayer/Data/Models/Track.swift`.

### Explicitly Deferred Cleanup
- Full unification of the two `Track` models into one canonical type.
- Replacing `repeatEnabled` with a shared `RepeatMode` enum across the whole app.
- Full delegate/event normalization beyond what Linux MVP actually needs.
- Full Darwin backend cleanup before Linux work starts.
- Linux support for every current macOS waveform/UI-facing notification shape.

## Concrete Architecture Decisions

### Canonical Playback Track
- Recommendation for Phase 2: do not force full `Track` unification.
- Introduce one narrow adapter boundary owned by the shared playback layer:
  - Linux-facing playback code may traffic in `NullPlayerCore.Track`
  - Darwin/app code may continue using the app-local `Track` temporarily
  - conversion between them should happen in one place rather than throughout the engine
- Constraint: `NullPlayerPlayback` must not import or depend on `Sources/NullPlayer/Data/Models/Track.swift`.
- Follow-up cleanup can decide later whether `NullPlayerCore.Track` should become the only real playback model.

### Repeat Semantics
- Recommendation for Phase 2: keep the existing repeat shape unless it directly blocks Linux backend work.
- Near-term behavior:
  - preserve current engine semantics
  - allow the Linux CLI adapter to implement repeat-all the same way the current macOS CLI does if needed
  - defer `RepeatMode` redesign to later playback cleanup work that is explicitly out of scope for this document
- Reasoning: repeat redesign is a broader product and persistence migration, not a prerequisite for first Linux delivery.

### Output Routing Ownership
- Recommendation: make routing a sibling shared protocol consumed by the facade and CLI, not a Darwin-only manager with optional shared wrappers.
- Canonical ownership:
  - preferences persistence owned by `PlaybackPreferencesProviding`
  - live device discovery owned by the backend-specific router
  - selection requests flow through the facade/routing seam, never directly from CLI to `AudioOutputManager`

### Linux Capability Defaults
- Recommendation for the first Linux cut:

```swift
AudioBackendCapabilities(
    supportsOutputSelection: true,
    supportsGaplessPlayback: false,
    supportsSweetFade: false,
    supportsEQ: true,
    supportsWaveformFrames: false,
    eqBandCount: 10
)
```

- Gapless and sweet-fade should ship disabled on Linux until correctness is proven with tokenized EOS handling and race coverage.
- Waveform-frame parity should also be treated as optional for the Linux MVP unless a real Linux consumer appears.

## Workstreams

### 1. Build And Target Split
- Split the current `NullPlayer` executable target into platform-appropriate layers instead of trying to conditionalize the entire app in place.
- Recommended target graph:
  - `NullPlayerCore`: existing pure models and notifications
  - `NullPlayerPlayback`: new cross-platform playback/state-machine/DSP/routing target
  - `NullPlayer`: macOS executable with AppKit/UI and Darwin backend wiring
  - `NullPlayerCLI`: headless executable target for Linux, and optionally macOS CLI builds later
  - `CGStreamer`: new system-library target wrapping GStreamer via a hand-written `module.modulemap` that links `gstreamer-1.0`, `gstreamer-audio-1.0`, `gstreamer-app-1.0`, and `gstreamer-pbutils-1.0` (SPM's `.systemLibrary` accepts only one `pkgConfig` string, so a single pkgConfig entry cannot cover all four; use a custom modulemap with explicit linker flags or a `pkg-config --libs` wrapper script instead)
- Keep macOS-only code in macOS-scoped files or targets: App delegate/bootstrap, windowing, video, ProjectM, CoreAudio output management, AVAudioEngine playback, AppKit artwork/display helpers.
- Add a Linux CLI entry target or Linux-only bootstrap path that depends only on Foundation-compatible code plus the new GStreamer backend.
- Make package dependencies conditional by platform so Linux does not attempt to resolve or link macOS-only frameworks.
- Resolve the duplicate track-model problem only enough to keep `NullPlayerPlayback` free of app-only types.
- Prefer an adapter boundary over a full model migration in Phase 2.
- Do not leave `NullPlayerPlayback` depending on app-only `Sources/NullPlayer/Data/Models/Track.swift`; that would defeat the point of the split.

### 2. Service And Environment Boundary
- Introduce a small shared environment seam instead of letting the playback facade reach directly into `UserDefaults`, `NSAlert`, `NSWorkspace`, `WindowManager`, or casting/radio singletons.
- Recommended shared services:
  - `PlaybackPreferencesProviding` for persisted playback settings and selected output ID
  - `PlaybackEnvironmentProviding` for temp-file policy, sleep/wake hooks, and user-visible error reporting
  - `PlaybackSourceResolving` for the Linux Phase 2 direct-file/direct-URL input surface
- Narrow Linux Phase 2 deliberately: do not pull `MediaLibrary`, Plex, Subsonic, Jellyfin, Emby, radio, or casting managers into the Linux compile path.
- Keep macOS-only source resolution and rich library queries in the existing app target until a later phase extracts those services cleanly.

### 3. Audio Backend Boundary
- Split `AudioEngine` into:
  - a platform-neutral facade that owns playlist state, repeat/shuffle rules, generation tokens, delegate delivery, and backend selection
  - a `DarwinAudioBackend` that wraps the current AVAudioEngine/AudioStreaming behavior
  - a `LinuxGStreamerAudioBackend` that owns the GStreamer pipeline and bus handling
- Keep `AudioEngineDelegate` semantics stable where possible, and make only the smallest `AudioPlaybackProviding` revisions needed for Linux routing/backend insertion.
- Move backend-private concepts out of the facade: AVAudioEngine graph nodes, CoreAudio output switching, GStreamer element construction, and streaming-library-specific callbacks.
- Keep backend-independent logic in the facade: playlist mutation, current index, auto-advance decisions, repeat/shuffle traversal, stale-load invalidation, and delegate notification ordering.
- Recommended Linux graph:
  - use `playbin3` for URI handling
  - provide a custom `audio-sink` bin shaped as `audioconvert ! audioresample ! equalizer-nbands ! tee`
  - sink branch: `queue ! volume ! <selected output sink>`
  - analysis branch: `queue leaky=downstream max-size-buffers=2 ! appsink`
  - keep the analysis branch post-EQ but pre-volume so Linux visualizations reflect heard EQ changes without becoming user-volume-dependent
- Recommended `appsink` caps and behavior:
  - caps: `audio/x-raw,format=F32LE,layout=interleaved`
  - request stereo where possible and downmix in the pipeline instead of in Swift
  - set `emit-signals=false` and pull samples from the backend queue, not arbitrary callback threads
  - keep only the most recent few buffers to avoid growing latency when analysis consumers fall behind
- Run all backend state mutations on a single serial queue.
- Run GStreamer bus watches and device-monitor callbacks on one dedicated GLib main-loop thread, then marshal typed backend events back onto the serial queue and finally onto `MainActor` for delegates.

### 4. Portable DSP Surface
- Extract the analysis pipeline into a backend-agnostic helper that consumes PCM frames from either backend and produces the shapes the rest of the app already expects.
- Preserve these output contracts unless explicitly revised:
  - `spectrumData` remains 75 bins
  - `pcmData` remains the lightweight waveform-facing PCM snapshot
- Treat EQ and spectrum/waveform analysis as separate responsibilities:
  - EQ belongs in the playback backend graph
  - analysis belongs in the shared portable DSP layer
- Make BPM/normalization support a deliberate decision:
  - if Phase 2 keeps them, define how Linux obtains analysis frames
  - if Phase 2 defers them, the plan must state the exact fallback behavior and what values/events remain available
- Recommended parity target:
  - preserve BPM detection if `CAubio` is made available on Linux
  - preserve current behavior that normalization only applies to local-file playback; do not promise streaming normalization in Phase 2 because the current Darwin path does not provide it either
  - emit silence-decay and reset behavior from the shared DSP helper instead of re-implementing visual decay separately per backend
  - standardize one analysis-frame format before it enters shared DSP:
    - interleaved stereo float32
    - sample rate attached to every frame
    - monotonically increasing frame timestamp (`monotonicTime: TimeInterval?`) if the backend can provide it
- Defer Linux-specific 576-sample waveform notification parity unless a concrete Linux consumer requires it.

### 5. Output Routing Abstraction
- Replace the CoreAudio-specific routing assumption with a portable device model.
- Update `AudioOutputDevice` so the stable persisted identifier is backend-neutral. The portable key should be string-based and survive reboots/device reordering; backend-native numeric IDs can remain optional implementation detail.
- Introduce a shared routing surface used by both CLI and engine code:
  - enumerate outputs
  - resolve current output
  - select output by stable identifier
  - notify when the device list changes
- Keep the existing macOS `AudioOutputManager` behavior behind that shared surface.
- Add a Linux routing implementation backed by GStreamer device monitoring and sink reconfiguration.
- Canonicalize persistence to one key, recommended: `selectedOutputDevicePersistentID`.
- On migration, read old keys in this order:
  - `selectedOutputDeviceUID`
  - `selectedAudioOutputDeviceUID`
  - then write only `selectedOutputDevicePersistentID`
- Recommended Linux persistent-ID precedence from GStreamer device properties:
  - hardware serial or stable node ID if exposed
  - device path plus backend name
  - backend-reported unique name
  - hashed display name only as last resort

### 6. Linux CLI Bootstrap
- Replace the `NSApplication`-driven CLI startup on Linux with a Foundation-only entry path.
- Keep the current CLI behavior where it is portable:
  - argument parsing
  - keyboard controls
  - signal handling
  - progress/status output
- Split CLI helpers into portable versus macOS-only pieces:
  - portable: `CLIOptions`, terminal display, direct file/URL resolution, keyboard input, and a new headless playback adapter built only on shared playback/routing seams
  - macOS-only: the current `CLIMode` bootstrap, `NSImage` artwork loading/rendering, cast/radio glue, and any CLI affordance that still depends on AppKit-heavy managers
- Treat the current `CLIPlayer` as a macOS-oriented implementation to be replaced or heavily reduced, not as code that is already safe to move wholesale into the Linux compile path.
- The Linux CLI should not import `AppKit` anywhere in its compile path.
- The Linux playback adapter and `CLIQueryHandler` should speak only to the shared output-routing abstraction, not `AudioOutputManager`.
- Linux CLI contract for Phase 2:
  - supported:
    - `--cli`
    - direct positional file paths
    - direct `http://` and `https://` URLs
    - `--shuffle`, `--repeat-all`, `--repeat-one`, `--volume`, `--eq`, `--output`, `--list-outputs`, `--no-art`
  - not supported on Linux in Phase 2:
    - `--source`
    - `--artist`, `--album`, `--track`, `--genre`, `--playlist`, `--search`
    - `--station`, `--radio`, `--folder`, `--channel`, `--region`
    - `--cast`, `--cast-type`, `--sonos-rooms`, `--list-devices`, `--list-sources`, `--list-libraries`, `--list-artists`, `--list-albums`, `--list-tracks`, `--list-genres`, `--list-playlists`, `--list-stations`
  - unsupported flags should fail fast with a Linux-specific help message rather than silently ignoring behavior

### 7. State Machine Preservation
- Preserve the current user-visible playback semantics around stale work cancellation and advancement decisions, but do not turn Phase 2 into a full event-system cleanup project.
- Keep explicit generation tokens for:
  - track load invalidation
  - deferred/gapless preparation
  - asynchronous analysis work
- Define ownership of end-of-stream events so the backend cannot double-advance when a seek, stop, or replacement load races with EOS.
- Introduce a backend-to-facade event surface rather than letting backends call arbitrary engine internals. Recommended events:
  - `stateChanged`
  - `timeUpdated`
  - `endOfStream`
  - `loadFailed`
  - `formatChanged`
  - `analysisFrame`
  - `outputsChanged`
- Define the Linux equivalents for:
  - paused vs stopped transitions
  - failed load transitions
  - seek completion and time update resumption
  - gapless pre-roll / sweet-fade overlap windows
- If gapless or sweet-fade semantics cannot be made correct in the first Linux cut, gate them behind a backend capability flag and keep the public API stable while degrading behavior predictably.
- Treat facade ownership as authoritative:
  - the facade advances playlist state
  - the backend reports raw EOS and error events tagged with the current load token
  - stale EOS/error events are ignored before they can mutate playlist state
- Time-update policy:
  - backend emits coarse playback position samples
  - facade rate-limits delegate delivery to a stable UI cadence
  - seek should produce one immediate delegate time update for the new position before normal cadence resumes
- Limit Phase 2 normalization work to the callbacks Linux actually relies on: track, state, time, and load failure. Playlist/spectrum/waveform callback cleanup can remain follow-up work unless it blocks the seam.

## Implementation Blueprint

### Shared Surface Revisions
- `Sources/NullPlayerCore/Audio/AudioPlaybackProviding.swift`
  - add only the backend/routing surface that Linux actually needs
  - preserve `repeatEnabled` in Phase 2 unless its shape directly blocks the new seam
  - keep playlist mutation, EQ, and transport controls here
- `Sources/NullPlayerCore/Audio/AudioOutputProviding.swift`
  - either replace with `AudioOutputRouting` or evolve it in place to use `persistentID`
  - stop exposing `currentDeviceUID`
- `Sources/NullPlayerCore/Audio/AudioTypes.swift`
  - migrate `AudioOutputDevice` from `id/uid` to `persistentID/backend/backendID/...`
  - keep a temporary Darwin-only adapter if existing UI code still needs the old CoreAudio ID during migration
- `Sources/NullPlayerCore/Models/Track.swift`
  - use as the Linux/shared playback-facing track shape where convenient
  - do not require whole-app track unification in Phase 2

### Facade/Internal Split
- New facade-owned responsibilities:
  - active playlist and current index
  - `shuffleEnabled` + existing repeat semantics
  - load token / seek token / analysis token
  - Linux-required delegate ordering for track/state/time/load-failure paths
  - next/previous/advance decisions
  - capability gating for gapless/sweet-fade/output selection
- Backend-owned responsibilities:
  - decode/play/pause/stop/seek
  - EQ node or pipeline wiring
  - raw output enumeration and selection
  - raw PCM analysis frame delivery
  - backend-native EOS and error events
- Explicit non-goal:
  - backends must not mutate playlist state, call delegates directly, or persist output IDs themselves

### Darwin Migration Shape
- Split the current `AudioEngine.swift` only as far as needed to create a usable shared seam:
  - `AudioEngineFacade`:
    - playlist state
    - repeat/shuffle traversal
    - token validation
    - Linux-required delegate delivery
  - `DarwinAudioBackend`:
    - AVAudioEngine graph
    - AudioStreaming integration
    - local/streaming load paths
    - seek/play/pause/stop implementation
  - `DarwinAudioOutputRouter`:
    - current `AudioOutputManager` logic
    - migration from legacy UID keys
  - `PlaybackEnvironment`:
    - `UserDefaults`
    - temp playback URL policy
    - `NSWorkspace` sleep/wake hooks
    - user-visible nonfatal error reporting
- Keep macOS behavior unchanged as much as possible, but do not require a full Darwin cleanup before Linux work can start. Once the seam is sufficient for one Linux backend path, Linux implementation can proceed in parallel.

### Linux MVP Shape
- `Sources/NullPlayerCLI/main.swift`
  - parse args
  - reject unsupported Linux-only flags early
  - bootstrap a Foundation-only run loop and signal handlers
- `Sources/NullPlayerPlayback/Audio/LinuxGStreamerAudioBackend.swift`
  - own one `playbin3` instance per active player
  - deliver typed events back onto the facade queue
- `Sources/NullPlayerPlayback/Audio/GStreamerOutputRouter.swift`
  - enumerate sinks/devices
  - choose current device
  - rebuild sink chain on output change
- `Sources/NullPlayerPlayback/CLI/LinuxCLIPlayer.swift` or equivalent
  - consume only shared playback and routing surfaces
  - no cast/radio/library-manager references

### Deferred Until After Linux MVP
- Full `Track` model unification
- Repeat API redesign (`RepeatMode`)
- Full playlist/spectrum/waveform callback normalization
- Gapless local-file handoff on Linux
- Sweet-fade crossfade overlap on Linux
- Service-backed source resolution
- Artwork rendering beyond text-only CLI output
- Streaming placeholder replacement for remote library services

## Proposed Shared Interfaces

### Revised Output Device Shape

```swift
public struct AudioOutputDevice: Equatable, Hashable, Sendable {
    public let persistentID: String
    public let name: String
    public let backend: String
    public let backendID: String?
    public let transport: AudioOutputTransport
    public let isAvailable: Bool
}

public enum AudioOutputTransport: String, Sendable {
    case builtIn
    case usb
    case bluetooth
    case airplay
    case network
    case unknown
}
```

### Routing Surface

```swift
public protocol AudioOutputRouting: AnyObject {
    var outputDevices: [AudioOutputDevice] { get }
    var currentOutputDevice: AudioOutputDevice? { get }
    func refreshOutputs()
    func selectOutputDevice(persistentID: String?) -> Bool
}
```

### Backend Capabilities

```swift
public struct AudioBackendCapabilities: Sendable {
    public let supportsOutputSelection: Bool
    public let supportsGaplessPlayback: Bool
    public let supportsSweetFade: Bool
    public let supportsEQ: Bool
    public let supportsWaveformFrames: Bool
    public let eqBandCount: Int  // e.g. 10 for macOS AVAudioUnitEQ, configurable for GStreamer equalizer-nbands
}
```

### Backend Event Surface

```swift
// All Track references below are NullPlayerCore.Track, not the app-local Track.
enum AudioBackendEvent: Sendable {
    case stateChanged(PlaybackState, token: UInt64)
    case timeUpdated(current: TimeInterval, duration: TimeInterval, token: UInt64)
    case endOfStream(token: UInt64)
    case loadFailed(track: NullPlayerCore.Track, failure: PlaybackFailure, token: UInt64)
    case formatChanged(sampleRate: Double, channels: Int, token: UInt64)
    case analysisFrame(AnalysisFrame, token: UInt64)
    case outputsChanged([AudioOutputDevice], current: AudioOutputDevice?)
}

struct PlaybackFailure: Sendable {
    let code: String
    let message: String
}

struct AnalysisFrame: Sendable {
    let samples: [Float]
    let channels: Int
    let sampleRate: Double
    /// Monotonic elapsed time since process start (seconds), for frame ordering.
    /// Cross-platform: backed by mach_absolute_time on Darwin, CLOCK_MONOTONIC on Linux.
    let monotonicTime: TimeInterval?
}
```

### Backend Protocol

```swift
/// Backends also conform to AudioOutputRouting (defined above) for device
/// enumeration and selection. The facade holds the backend as both
/// AudioBackend and AudioOutputRouting; output reads go through the
/// routing surface, not duplicated here.
protocol AudioBackend: AudioOutputRouting {
    var capabilities: AudioBackendCapabilities { get }
    var eventHandler: (@Sendable (AudioBackendEvent) -> Void)? { get set }

    func prepare()
    func shutdown()
    func load(track: NullPlayerCore.Track, token: UInt64, startPaused: Bool)
    func play(token: UInt64)
    func pause(token: UInt64)
    func stop(token: UInt64)
    func seek(to time: TimeInterval, token: UInt64)

    func setVolume(_ value: Float, token: UInt64)
    func setBalance(_ value: Float, token: UInt64)
    /// Band count must match capabilities.eqBandCount.
    func setEQ(enabled: Bool, preamp: Float, bands: [Float], token: UInt64)

    func setNextTrackHint(_ track: NullPlayerCore.Track?, token: UInt64)
}
```

### Preferences And Environment

```swift
protocol PlaybackPreferencesProviding: AnyObject {
    var gaplessPlaybackEnabled: Bool { get set }
    var volumeNormalizationEnabled: Bool { get set }
    var sweetFadeEnabled: Bool { get set }
    var sweetFadeDuration: TimeInterval { get set }
    var selectedOutputDevicePersistentID: String? { get set }
}

protocol PlaybackEnvironmentProviding: AnyObject {
    func reportNonFatalPlaybackError(_ message: String)
    /// Copy a remote/NAS file to a local temp path for reliable AVAudioFile/GStreamer access.
    /// Returns the original URL unchanged if no copy is needed (e.g. already local).
    func makeTemporaryPlaybackURLIfNeeded(for originalURL: URL) throws -> URL
    func beginSleepObservation(_ handler: @escaping @Sendable (PlaybackSleepEvent) -> Void)
}

enum PlaybackSleepEvent: Sendable {
    case willSleep
    case didWake
}
```

## Concrete Event Ordering

### Load And Start
1. Facade increments `loadToken`.
2. Facade updates playlist/current index immediately.
3. Facade tells backend `load(track:token:startPaused:)`.
4. Backend emits `formatChanged` if known.
5. Backend emits `stateChanged(.playing|.paused, token:)`.
6. Facade validates token, updates local state, and emits one canonical delegate sequence in this order:
   - `audioEngineDidChangeTrack`
   - `audioEngineDidUpdateTime(current:duration:)`
   - `audioEngineDidChangeState`
7. The facade must be the only layer that delivers those delegate callbacks; backend adapters and property observers should not emit duplicate track/state notifications out-of-band.

### Seek
1. Facade records `pendingSeekToken`.
2. Facade calls backend `seek(to:token:)`.
3. First backend `timeUpdated` for that token becomes authoritative.
4. Facade emits one immediate delegate time update for the seek target and resumes normal time cadence.
5. Any earlier `timeUpdated` or `endOfStream` carrying an older token is dropped.

### End Of Stream
1. Backend emits `endOfStream(token:)`.
2. Facade ignores it unless `token == activeLoadToken`.
3. Facade decides repeat/shuffle/stop outcome.
4. If advancing, facade increments token before asking the backend to load the next track.
5. Delegate sees either:
   - next-track callbacks for advance, or
   - `.stopped` after the final time update for terminal stop

### Load Failure
1. Backend emits `loadFailed(track:failure:token:)`.
2. Facade validates token.
3. Facade notifies:
   - `audioEngineDidFailToLoadTrack`
   - then either loads the next eligible track or enters `.stopped`

### Load Interrupted By Load
1. Facade receives a new load request while a prior load (token N) is still in progress.
2. Facade increments token to N+1 immediately and updates playlist/current index.
3. Facade calls `backend.stop(token: N)` followed by `backend.load(track:token:startPaused:)` with token N+1.
4. Any pending backend events carrying token N (stateChanged, timeUpdated, formatChanged, endOfStream, loadFailed) are silently dropped by the facade's token check — they never reach delegates.
5. The backend is not required to cancel in-flight work synchronously; it must only guarantee that events carry the token they were issued with. The facade is the sole authority on which token is current.
6. Delegates see only the N+1 load sequence (track change, time update, state change) — no partial or interleaved callbacks from the abandoned load.

## Package Sketch

```swift
.executableTarget(
    name: "NullPlayerCLI",
    dependencies: [
        "NullPlayerCore",
        "NullPlayerPlayback",
    ],
    path: "Sources/NullPlayerCLI"
),
.target(
    name: "NullPlayerPlayback",
    dependencies: [
        "NullPlayerCore",
    ],
    path: "Sources/NullPlayerPlayback",
    swiftSettings: [
        .define("HAVE_GSTREAMER", .when(platforms: [.linux])),
    ]
),
.systemLibrary(
    name: "CGStreamer",
    path: "Sources/CGStreamer"
    // Uses a hand-written module.modulemap instead of pkgConfig,
    // because SPM systemLibrary only accepts one pkgConfig string
    // but GStreamer requires linking gstreamer-1.0, gstreamer-audio-1.0,
    // gstreamer-app-1.0, and gstreamer-pbutils-1.0.
    // The modulemap and a link-flags header handle all four.
)
```

Linux backend target options:
- simplest: keep Linux-only files inside `NullPlayerPlayback` under `#if os(Linux)`
- cleaner if the file count grows: split them into `NullPlayerPlaybackLinux` and make `NullPlayerPlayback` depend on it only on Linux

Important dependency constraint:
- if backend or facade protocols traffic in playback-track values, those values must come from `NullPlayerCore.Track`, not the existing app-local `Sources/NullPlayer/Data/Models/Track.swift`

## Concrete File-Level Plan

### Package / Bootstrap
- `Package.swift`
  - introduce `NullPlayerPlayback`, `NullPlayerCLI`, and `CGStreamer` targets
  - make `KSPlayer`, `AudioStreaming`, `CProjectM`, and Darwin-only audio glue conditional on macOS
  - remove the assumption that the entire package is `.macOS(.v14)` only
- `Sources/NullPlayer/App/main.swift`
  - macOS-only bootstrap
  - delegate CLI startup to a non-AppKit path outside the AppKit compile path
- `Sources/NullPlayerCLI/main.swift`
  - Foundation-only entry point
  - own signal handling and event loop bootstrap without `NSApplication`
- `Sources/NullPlayer/CLI/CLIMode.swift`
  - shrink to macOS-only bootstrap glue if still needed, or delete once `NullPlayerCLI` owns headless startup
- `Sources/CGStreamer/`
  - add module map and thin headers for GStreamer and GLib imports

### Audio
- `Sources/NullPlayer/Audio/AudioEngine.swift`
  - split into smaller shared files under the new cross-platform target
  - keep only facade/state-machine responsibilities in the shared layer
- `Sources/NullPlayerCore/Models/Track.swift` and/or `Sources/NullPlayerPlayback/Models/`
  - establish one playback-track model used by backends, facade, CLI, and delegate translation
  - remove the current ambiguity between core `Track` and app-local `Track` before the backend split goes too far
- `Sources/NullPlayerPlayback/Audio/`
  - add `AudioBackend.swift`
  - add `AudioEngineFacade.swift`
  - add `PortableAudioAnalysis.swift`
  - add `AudioOutputRouting.swift`
  - add `PlaybackPreferences.swift`
- `Sources/NullPlayer/Audio/`
  - isolate current AVFoundation/CoreAudio implementation into Darwin-specific backend files
  - move `AudioOutputManager` behind the shared routing abstraction
  - move sleep/wake and alert policy out of shared playback code
- `Sources/NullPlayerPlaybackLinux/Audio/` or Linux-scoped files under `Sources/NullPlayerPlayback/Audio/`
  - add `LinuxGStreamerAudioBackend.swift`
  - add `GStreamerPipelineBuilder.swift`
  - add `GStreamerOutputRouter.swift`
  - add `GStreamerBusBridge.swift`
- `Sources/NullPlayerCore/Audio/AudioTypes.swift`
  - revise `AudioOutputDevice` to stop assuming CoreAudio-only identifiers
  - add a canonical `persistentID`
- `Sources/NullPlayerCore/Audio/AudioPlaybackProviding.swift`
  - revise intentionally for portable output routing and explicit repeat semantics if needed
  - stop assuming the Linux backend can fit behind today's exact protocol unchanged

### CLI
- `Sources/NullPlayer/CLI/CLIPlayer.swift`
  - either replace with a new portable headless player or shrink to a macOS-only wrapper around shared CLI/playback components
  - do not carry current cast/radio/output-manager coupling into the Linux target
- `Sources/NullPlayer/CLI/CLIQueryHandler.swift`
  - keep only portable output queries in the Linux build
  - keep service-backed query modes macOS-only for Phase 2
- `Sources/NullPlayer/CLI/CLIDisplay.swift`
  - split terminal-only display from AppKit artwork functionality
- `Sources/NullPlayer/CLI/CLIArtwork.swift`
  - keep macOS-only, or replace with a cross-platform image loader in a later phase

## Capability Decisions Needed Up Front
- Output-device persistence key:
  - recommended: `AudioOutputDevice.persistentID: String`
  - optional backend fields: `backendID`, `uid`, transport flags
- Backend capability flags:
  - `supportsOutputSelection`
  - `supportsGaplessPlayback`
  - `supportsSweetFade`
  - `supportsEQ`
  - `supportsWaveformFrames`
- Linux CLI artwork:
  - recommended for Phase 2: disable artwork on Linux and keep text-only output
- Streaming implementation:
  - recommended: one GStreamer path for both local and HTTP playback rather than preserving a separate Linux streaming subsystem
- Linux source resolution:
  - recommended for Phase 2: support direct file paths and raw HTTP/HTTPS URLs only
- GStreamer runtime model:
  - recommended: dedicated GLib main-loop thread plus one serial backend queue

## Suggested Landing Order
1. Restructure `Package.swift` so a Linux target can compile a no-op headless binary without importing AppKit.
2. Extract portable CLI code and narrow Linux source resolution to direct file/URL playback.
3. Introduce the smallest shared playback/backend seam needed to host both Darwin and Linux backends.
4. Add portable output routing and persistent-ID migration.
5. Add the Linux GStreamer backend with `appsink`-driven analysis, but start with one output sink and capability-gated gapless/sweet-fade behavior.
6. Normalize only the delegate paths Linux depends on: track, time, state, and load failure.
7. Turn on Linux smoke tests for local files, HTTP streams, seek, EQ, and output enumeration.

## PR-Sized Rollout

### PR 1: Package And Bootstrap Split
- add `NullPlayerCLI` and `NullPlayerPlayback` targets
- make macOS-only dependencies conditional
- keep Linux build at a stub/no-op state, but compiling

### PR 2: Minimal Shared Playback Seam
- introduce a narrow backend protocol
- add the smallest track-adaptation boundary needed to keep app-only `Track` out of `NullPlayerPlayback`
- avoid broad `Track` and repeat migrations

### PR 3: Portable Routing Types
- migrate `AudioOutputDevice` to `persistentID`
- add routing protocol
- implement legacy UID migration in one place

### PR 4: Darwin Facade Extraction
- introduce `AudioEngineFacade`
- move Linux-required delegate ordering and token validation into the facade
- keep the current Darwin playback path behind the new seam

### PR 5: Darwin Output Router + Environment
- isolate `AudioOutputManager`
- add `PlaybackPreferencesProviding` and `PlaybackEnvironmentProviding`
- remove direct `UserDefaults`/`NSWorkspace`/`NSAlert` reads from shared playback code

### PR 6: Linux CLI MVP
- add Foundation-only Linux `main`
- add direct file/URL source parsing
- add unsupported-flag rejection and text-only display path

### PR 7: Linux GStreamer Backend MVP
- local file and HTTP playback
- time/state/error callbacks
- PCM analysis frames for shared DSP

### PR 8: Shared DSP And Routing Wiring
- connect 75-bin spectrum and `pcmData` to Linux
- add Linux output enumeration and selection

### PR 9: Smoke Tests And Capability Gating
- Linux smoke coverage
- explicit Linux capability flags
- verify gapless/sweet-fade stay disabled but API-stable
- leave waveform-frame parity as optional follow-up work

## Test Plan
- Add unit tests for the shared playback facade:
  - shuffle/repeat traversal
  - stale generation-token invalidation
  - delegate event ordering on load failure, stop, seek, and EOS
- Add unit tests for portable DSP helpers:
  - 75-bin spectrum shape
  - empty-input / silence decay behavior
- Add waveform frame chunking tests only if Linux waveform-frame delivery is kept in scope.
- Add routing tests for stable-ID persistence and missing-device fallback behavior.
- Add Linux CLI smoke coverage that:
  - starts playback for a local fixture
  - pauses/resumes
  - seeks
  - advances next/previous
  - applies EQ
  - enumerates outputs
  - selects an output when more than one sink is present
- Add HTTP stream smoke coverage so Linux is not validated only against local files.
- Add Linux backend tests that run against `appsink` and `fakesink` so CI can validate playback state and analysis without requiring real speakers.
- Add one Linux integration job with explicit packages installed:
  - `libgstreamer1.0-dev`
  - `libgstreamer-plugins-base1.0-dev`
  - `gstreamer1.0-plugins-base`
  - `gstreamer1.0-plugins-good`
- Run the existing `swift test` suite on macOS after the split to catch regressions in the Darwin backend.

## Exit Criteria
- Linux build succeeds without compiling AppKit/UI code.
- Linux CLI can play a local file path and an HTTP stream URL end-to-end.
- Delegate callbacks for state, time, track, and load failures still fire in the expected order for Linux playback paths.
- Output enumeration and selection work through the shared routing surface, with persisted stable IDs.
- macOS builds still use the existing playback path with no user-visible regression in current features.

## Assumptions
- GStreamer 1.x and the required base/good audio plugins are available on the Linux target.
- Phase 2 is allowed to reshape internals aggressively as long as the shared playback contract and macOS behavior remain intact.
- Linux can persist backend-neutral output IDs even when the underlying sink implementation exposes unstable runtime handles.
- The first Linux cut may intentionally degrade unsupported features behind capability checks instead of shipping incorrect behavior.
