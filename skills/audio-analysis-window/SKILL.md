---
name: audio-analysis-window
description: The modern-UI Audio Analysis window — a Friture-style multi-pane analyzer (Scope, Levels, Spectrogram), the stereo PCM path that feeds it, per-pane consumer gating, and the shared AudioAnalysisDSP module. Use when modifying the analysis window, its panes, the spectrogram shader, or the stereo/DSP plumbing.
---

# Audio Analysis Window

A modern-UI-only window offering a Friture-style (https://friture.org) real-time view of the
playing audio. Exactly one pane is visible at a time; the pane is selected via the window's
**right-click context menu** (no in-window controls — matches the Spectrum window). Modeled on the
`ModernSpectrum` window pattern and has **zero** dependencies on the classic skin system.

## Accessing

- Window menu / main window right-click context menu → **Audio Analysis** (guarded by
  `isRunningModernUI`)
- Available in **modern UI mode only**.

## Window chrome & sizing

- **Center-stack window.** Registered as `CenterStackWindowKind.audioAnalysis` in `WindowManager`.
  It opens at the **same width as the main window**, docks/snaps flush in the vertical stack and is
  vertically stretchable like spectrum/playlist windows. `showAudioAnalysis` applies
  `applyCenterStackSizingConstraints` / `applyDefaultCenterStackFrameForCurrentHT` /
  `normalizedCenterStackRestoredFrame` exactly like `showSpectrum`. The controller's default size is
  `ModernSkinElements.spectrumWindowSize`.
- **Double Size (Large UI).** `WindowManager.applyDoubleSize()` has an explicit audio-analysis block
  (after the waveform block) that rescales the frame by `classicScaleMultiplier`. Without it the
  window is the one stack window that doesn't follow Large UI when toggled.
- **Hide Title Bars.** Included in `effectiveHideTitleBars(for:)` (sub-window list), so it auto-hides
  when docked and follows the global HT toggle. The view reads `effectiveHideTitleBars` for its
  title-bar height, drawing, and hit-testing.
- **Chrome rendering.** `ModernAudioAnalysisView` draws the skin title bar + close button (`spectrum_`
  prefix) and insets the SwiftUI hosting view into the content area (inside `borderWidth`, below
  `titleBarHeight`) via `contentAreaRect()` / `layoutHostingView()`. The hosting view's `appearance`
  is set from skin brightness (aqua/darkAqua) and the content gets `skinTextColor` — do **not** cover
  the chrome with an opaque background.

## Panes (MVP)

| Pane | Source notification | Consumer it registers | Render |
|------|--------------------|----------------------|--------|
| **Scope** (oscilloscope) | `.audioPCMDataUpdated` (`userInfo["pcm"]` 512 mono) | spectrum | CoreGraphics (`NSView`) |
| **Levels** (peak/RMS) | `.audioStereoPCMDataUpdated` (`left`/`right` 512) | stereo | SwiftUI bars |
| **Spectrogram** (waterfall) | `.audioSpectrumDataUpdated` (`spectrum` 75 bands) | spectrum | Metal (`MTKView`) |

`.audioPCMDataUpdated` is posted *inside* the spectrum block, so the Scope pane registers a
**spectrum** consumer (not a dedicated PCM one) to make mono PCM flow.

Deferred (DSP exists, panes not built): Octave spectrum, Pitch tracker, Delay estimator.

## Architecture

- **Window**: `Windows/ModernAudioAnalysis/ModernAudioAnalysisWindowController.swift` (conforms to
  `App/AudioAnalysisWindowProviding.swift`) + `ModernAudioAnalysisView.swift` (SwiftUI host + the
  `menu(for:)` context menu for pane selection + Close).
- **Pane selection state**: `AudioAnalysisModel: ObservableObject` (`@Published var selectedPane`),
  owned by the NSView and observed by `AudioAnalysisContentView`. The right-click `menu(for:)` mutates
  it (radio items + Close); the content view's `.onChange` persists it and calls
  `controller.setVisiblePane(_:)`.
- **Panes**: `ScopePaneView.swift`, `LevelsPaneView.swift` (vertical full-height peak/RMS meters,
  no title text), `SpectrogramPaneView.swift`.
- **Shader**: `Visualization/SpectrogramShaders.metal` — fullscreen quad generated from
  `[[vertex_id]]` (no vertex buffer), samples an `r32Float` history texture, Viridis colormap LUT.
  Low frequencies at the bottom (texCoord.y = 0). **Loaded via `BundleHelper.url(...)` +
  `device.makeLibrary(source:)`** — `makeDefaultLibrary()` returns nil in SPM executables (same
  pattern as `SpectrumAnalyzerView`). The `.metal` file is a `.copy` resource in `Package.swift`.
- **DSP**: `Sources/NullPlayerCore/Audio/AudioAnalysisDSP.swift` — pure-Swift, unit-tested
  (`Tests/NullPlayerCoreTests/AudioAnalysisDSPTests.swift`): `peakDBFS`, `rmsDBFS`, `octaveBands`,
  `estimatePitchHz` (autocorrelation), `estimateDelaySamples` (L/R cross-correlation).
- **Stereo path**: `Audio/AudioEngine.swift` and `Audio/StreamingAudioPlayer.swift` publish
  `.audioStereoPCMDataUpdated` (downsampled L/R) gated by `addStereoConsumer`/`removeStereoConsumer`/
  `stereoNeeded`, mirroring the spectrum/waveform consumer pattern. Wired in **both** the local
  engine and the streaming delegate (`streamingPlayerDidUpdateStereoPCM(left:right:sampleRate:)`).

## Consumer gating (CPU)

The controller registers the initial pane in `showWindow(_:)`; `AudioAnalysisContentView` updates it
on `.onChange(of: model.selectedPane)`. The controller registers exactly the visible pane's consumer,
and both `stopRenderingForHide()` and `windowWillClose` call `deregisterAllConsumers()`. A
hidden/closed window must leave the FFT and stereo path idle. The spectrogram also pauses its
`MTKView` (`isPaused`) while hidden or miniaturized.

## Persistence

Window frame saved in `AppStateManager` session state (`audioAnalysisWindowFrame`, gated by
`savedInModernMode`); the selected pane persists via `UserDefaults`. Docks/snaps with
Main/EQ/Playlist/Spectrum via `WindowManager`.

## Gotchas

- **Notifications post from the audio thread.** Observers must marshal to main: AppKit observers
  use `addObserver(forName:object:queue:.main)`; the SwiftUI Levels pane uses
  `.publisher(for:).receive(on: DispatchQueue.main)`. Mutating SwiftUI `@State` off-main is a bug.
- **Spectrogram bands are already 0–1.** `.audioSpectrumDataUpdated`'s `"spectrum"` is **75 bands
  normalized 0–1** (see `AudioEngine` doc comment), NOT dBFS. Feed them straight to the colormap.
  Treating them as dBFS (e.g. `(v + 80) / 80`) pushes every band to ≈1.0 → the whole window floods
  yellow.
- **Shader load (SPM)**: load the `.metal` source via `BundleHelper.url(...)` and compile with
  `device.makeLibrary(source:)`. `device.makeDefaultLibrary()` returns nil in SPM executables →
  "Failed to load shader library" and a blank pane.
- **Metal**: guard `pipelineState` and `historyTexture` **before** creating the command encoder
  (see [metal-gotchas](../metal-gotchas/SKILL.md)); watch the render-to-texture y-flip. The
  spectrogram uses paced `MTKView` drawing (`preferredFramesPerSecond`), not a manual timer loop.
- **Modern independence**: files under `Windows/ModernAudioAnalysis/` must not import from `Skin/`
  or `Windows/MainWindow/`.
- **Two playback paths**: any new tap data must be emitted by both `AudioEngine` and the
  `StreamingAudioPlayer` delegate route, or streaming silently misses it.

See [visualizations](../visualizations/SKILL.md) for the visualization index and
[spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md) for the related spectrum window.
