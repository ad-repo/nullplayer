# Phase 3: UI on Linux

## Status
- Initial high-level plan.
- This document is intentionally architecture-first. Detailed PR/task slicing should be a later revision after the UI stack decision is made.

## Summary
- Deliver the first real Linux desktop UI for `NullPlayer` on top of the Phase 2 playback/runtime work.
- Treat the UI stack choice as the first Phase 3 milestone, not as an implementation detail to defer until after coding starts.
- Phase 3 should account for the full seven-window Linux UI set:
  - main player
  - playlist
  - equalizer
  - library browser
  - spectrum
  - waveform
  - projectM
- Sequence the phase so the library browser and main player land first as the initial Linux UI surfaces, then bring in the playlist as the rest of the core usability milestone, then bring over the remaining four windows.
- Keep the Linux UI goal narrow: a usable desktop app for playback and local-library browsing, not macOS UI parity.

## Starting Point
- Phase 2 established the Linux-capable playback seam (`NullPlayerPlayback`), Linux CLI target (`NullPlayerCLI`), and GStreamer backend.
  - `NullPlayerPlayback` already compiles cross-platform: it contains `AudioBackend` protocol (`prepare()`, `shutdown()`, `load(track:token:startPaused:)`, `play(token:)`, `pause(token:)`, `stop(token:)`, `seek(to:token:)`), `LinuxGStreamerAudioBackend` (the GStreamer implementation), and `AudioEngineFacade` (the coordination layer). Linux-specific code is gated with `#if os(Linux)`.
- The existing macOS UI architecture is still AppKit-native and window-manager-centric. `MainWindowProviding`, `PlaylistWindowProviding`, `LibraryBrowserWindowProviding`, `EQWindowProviding`, `SpectrumWindowProviding`, `WaveformWindowProviding`, `ProjectMWindowProviding`, and `WindowManager` all assume `NSWindow`/AppKit ownership.
- Several current window implementations also pull on AppKit-only or macOS-heavy services beyond raw rendering: file panels, alerts, SwiftUI/AppKit hosting, AVFoundation image loading, projectM/OpenGL, spectrum/Metal rendering, and the current library/service browser stack.
- Conclusion: Phase 3 is not a compile-time port of AppKit windows. It is a Linux UI shell built on shared playback/core surfaces plus selectively extracted data, visualization, and window-management services.

## Guiding Decisions
- Do not attempt classic-skin or modern-skin parity in the first Linux UI.
- Do not block Phase 3 on perfect one-to-one `WindowManager` parity before any Linux GUI ships.
- Preserve the product shape of seven distinct windows, but sequence delivery.
- Keep presentation state and view models UI-toolkit-neutral so the Linux UI choice does not leak into playback, library, or business logic.
- Keep Linux source scope deliberately smaller than macOS at first: local playback and local library first; remote-source parity is follow-up work.

## Primary Decision Gate: GTK 4 Swift Bindings Or Pivot

### Goal
- Choose a Linux UI approach that is viable for real application work, not just a demo window.

### Candidate Direction
- Start by evaluating GTK 4 from Swift.
- Keep the door open to pivot quickly if direct GTK 4 bindings are too costly or brittle for `NullPlayer`'s actual needs.
- The first pivot target should still be GTK-backed if possible, using a higher-level Swift abstraction rather than raw bindings.
- The decision is about the whole developer experience: build reliability, widget coverage, list performance, async state updates, packaging, and maintainability.

### Known GTK4 Swift Options (candidates for evaluation, not confirmed choices)
- **`swift-gtk4`** (raw bindings): direct Swift wrappers over GTK4 C API; closest to the metal, most control, but highest boilerplate and maintenance burden.
- **`Adwaita`** (higher-level): built on top of `gtk4-swift`; provides widget abstractions that more closely resemble declarative UI; reduces boilerplate for common patterns.
- **Custom C interop wrapper** (CGStreamer pattern): add a GTK4 system library target to `Package.swift` (same pattern as `CGStreamer`) and write raw C interop in Swift. Viable if existing bindings lack coverage or are too unstable. No external SwiftPM dependencies required.

### What The Evaluation Must Prove
- A Linux app target can build and launch reliably through SwiftPM without contaminating shared playback targets.
- The toolkit can support a responsive player shell plus production-grade list views for playlist and library data.
- Background playback and library updates can drive UI refreshes safely on the toolkit's main thread model.
- Multiple top-level windows, keyboard shortcuts, menus, drag-and-drop, and window lifecycle events are practical.
- The dependency story is acceptable for contributor setup and future CI.

### Exit Rule
- If the GTK 4 binding spike cannot quickly demonstrate a working app shell, a scalable playlist view, and a usable library list/tree surface, pivot immediately rather than forcing the entire phase through the wrong abstraction.

## Recommended Milestone Shape
- First milestone: a Linux desktop app with the library browser and main player implemented first, followed by the playlist:
  - library browser
  - main player
  - playlist
- Second milestone: bring over the remaining four windows:
  - equalizer
  - spectrum
  - waveform
  - projectM
- Preserve the current product shape of separate windows, but do not block early progress on perfect parity for every window-management detail.

## Target Structure

The Linux UI executable requires a new SwiftPM target alongside the existing macOS and CLI targets:

- `NullPlayer` — macOS executable (`Sources/NullPlayer/`, macOS-only)
- `NullPlayerCLI` — cross-platform CLI executable (`Sources/NullPlayerCLI/`)
- `NullPlayerLinuxUI` — new Linux desktop executable (`Sources/NullPlayerLinuxUI/`), depending on `NullPlayerPlayback` and `NullPlayerCore`

`NullPlayerLinuxUI` must not import AppKit. All shared logic it needs must already live in `NullPlayerPlayback` or `NullPlayerCore` (or be moved there as a prerequisite).

Moving `MediaLibraryStore`, `LocalFileDiscovery`, `AudioFileValidator`, `ModernBrowserSource`, `ModernBrowseMode`, `ModernBrowserSortOption`, and supporting model types (`AlbumSummary`, `LocalVideo`, `LocalEpisode`, `FileScanSignature`) from `NullPlayer` to `NullPlayerCore` is a prerequisite for `NullPlayerLinuxUI` to use them. Moving `MediaLibraryStore` also requires `SQLite.swift` to become a `NullPlayerCore` dependency.

## Scope

### In Scope For Phase 3
- Linux desktop executable target and app lifecycle.
- UI framework evaluation and decision.
- Linux UI shell wired to `NullPlayerPlayback` and the existing playback facade.
- All seven Linux UI windows, delivered in phases rather than all at once.
- Library browser and main player first, then playlist, as the first usability milestone.
- Equalizer, spectrum, waveform, and projectM as the second milestone.
- Extraction of any required library/query/presentation/visualization seams needed to make the above Linux-safe.
- Basic Linux UI state persistence where required for usability.

### Explicitly Out Of Scope For The First Cut
- Classic skin rendering on Linux.
- Modern skin rendering parity on Linux.
- Exact `WindowManager` parity: docking, snapping, shade mode, hide-title-bars mode, and full multi-window choreography on day one.
- Full Plex/Subsonic/Jellyfin/Emby/radio browser parity.
- Linux-specific desktop integrations beyond what is required to launch and use the app.

## Workstreams

### 1. UI Stack Decision
- Build a short, bounded spike around GTK 4 from Swift.
- Require the spike to cover the real app shape, not just controls in isolation:
  - app window
  - transport controls
  - playlist list view
  - library list/tree/search view
  - additional top-level windows
- Produce one explicit go/no-go decision with rationale.
- If the result is "no-go," pivot immediately to the next-best Linux UI approach instead of layering more experiments on top.

### 2. Linux App Shell
- Add a Linux desktop app target that sits beside the existing macOS app and Linux CLI targets.
- Define a Linux entry point, main-thread model, app lifecycle, and top-level window structure.
- Keep the Linux shell separate from AppKit-era window orchestration.

### 3. Cross-Platform Presentation And Window Layer
- Extract toolkit-neutral presentation models for all seven windows.
- Extract or replace AppKit-specific provider protocols and window-management assumptions where Linux needs different concrete types.
  - The seven provider protocols — `MainWindowProviding`, `PlaylistWindowProviding`, `LibraryBrowserWindowProviding`, `EQWindowProviding`, `SpectrumWindowProviding`, `WaveformWindowProviding`, `ProjectMWindowProviding` — are currently defined in `Sources/NullPlayer/App/` (macOS-only target). All use `NSWindow` for the `window` property.
  - Extraction work must either: (a) move these protocols to `NullPlayerCore` with an opaque or erased platform window type, or (b) define parallel Linux-safe protocol definitions in a new shared module (e.g., `NullPlayerLinuxUI`). Either way, the `NSWindow` reference must be replaced or conditionally compiled out before Linux controllers can conform.
- The Linux UI should bind to presentation state, not directly to macOS window controllers or AppKit views.
- This is the main insulation layer that keeps a future toolkit pivot survivable.

### 4. Library And Visualization Service Extraction
- Extract the minimum local-library query and scan surfaces needed for a Linux browser.
  - `MediaLibraryStore` (with methods including `artistNames(limit:offset:sort:)`, `albumSummaries(limit:offset:sort:)`, `albumsForArtist(_:)`, `tracksForAlbum(_:)`, `searchTracks(query:limit:offset:)`, `artistLetterOffsets(sort:)`, `albumLetterOffsets(sort:)`, `updateTrackRating(trackId:rating:)`, and related) is currently in `NullPlayer` (macOS-only). Must move to `NullPlayerCore`.
  - `LocalFileDiscovery` (with `discoverMediaStreaming(from:recursiveDirectories:includeVideo:includeLegacyWMA:audioBatchSize:onAudioBatch:)`, `isSupportedAudioFile(_:includeLegacyWMA:)`, `isSupportedVideoFile(_:)`, `hasSupportedDropContent(_:includeVideo:includePlaylists:)`) is also in `NullPlayer` (macOS-only). Must move to `NullPlayerCore`.
  - `ModernBrowserSource` and `ModernBrowseMode` enums are currently in `Sources/NullPlayer/Windows/ModernLibraryBrowser/` (macOS-only). Must move to `NullPlayerCore` before Linux can use them.
- Extract visualization/runtime seams needed by spectrum, waveform, and projectM windows.
- Keep the first browser provider narrow and portable.
- Do not make initial Linux delivery depend on full remote-source browser portability.

### 5. Core Three Windows
- Deliver the library browser and main player first, then the playlist.
- The library browser is a first implementation target because Linux library support is needed to drive playback, queueing, and broader UI/audio validation.
- The main player is also a first implementation target because it is the primary playback/transport state surface for validating what the browser launches.
- The point of the first milestone is a usable Linux music player driven through real library flows, not full parity chrome.

### 6. Remaining Four Windows
- Port the equalizer, spectrum, waveform, and projectM windows after the core three are functional.
- Treat these as real Phase 3 scope, not as out-of-band stretch goals.
- Capability-gate features when Linux dependencies are not yet ready, but keep the product shape explicit.

### 7. Validation And Packaging Baseline
- Add automated coverage where it is realistic at this phase:
  - build coverage for the Linux app target
  - presenter/view-model tests
  - targeted integration smoke tests around playback-driven UI state
- Define the minimum developer setup and runtime dependency story for a GTK-based Linux build.
- Packaging beyond a developer-runnable app can wait, but the setup story must be explicit and repeatable.

## Sequencing
1. Decide the Linux UI stack.
2. Stand up the Linux desktop app shell.
3. Extract presentation and service seams required by the shell.
4. Ship the library browser and main player first.
5. Add the playlist.
6. Add the equalizer, spectrum, waveform, and projectM windows.
7. Tighten validation and contributor setup.

## Exit Criteria
- A Linux desktop build launches a real GUI app.
- The GUI can control playback end-to-end through the shared playback facade.
- The Linux port has an explicit implementation path for all seven windows, with the first three delivered before the remaining four.
- The Linux UI target builds without importing AppKit in its compile path.
- The chosen UI stack is explicit and justified; the project is not left in a half-committed toolkit experiment.

## Risks And Watchpoints
- The biggest technical risk is choosing the wrong UI abstraction and discovering too late that list-heavy music-player workflows are awkward or fragile.
- Reusing the current AppKit window/provider model too literally would create high-cost coupling and slow the Linux effort.
- The library browser is not just a view problem; it depends on extracting Linux-safe data/query services from the current app target.
- Spectrum, waveform, and projectM are not just windows; they also depend on graphics/runtime capability decisions on Linux.
- If Phase 3 silently expands toward full macOS parity for skins, remote sources, or every window-management detail, it will become too large to land.

## Recommended Non-Goals For This Phase
- Do not try to make Linux look like Winamp first.
- Do not make perfect multi-window parity a gate for shipping the first Linux GUI milestone.
- Do not block the first browser on remote service support.
- Do not let visualization or secondary-window work get onto the critical path before the core three windows are usable.
