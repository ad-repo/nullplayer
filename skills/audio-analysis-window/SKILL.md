---
name: audio-analysis-window
description: The classic and modern Audio Analysis windows — a Friture-style multi-pane analyzer (Scope, Levels, Spectrogram), the stereo PCM path that feeds them, per-pane consumer gating, and the shared AudioAnalysisDSP module. Use when modifying either analysis window, its panes, the spectrogram shader, or the stereo/DSP plumbing.
---

# Audio Analysis Window

A classic and modern UI window offering a Friture-style (https://friture.org) real-time view of the
playing audio. Exactly one pane is visible at a time; the pane is selected via the window's
**right-click context menu** (no in-window controls — matches the Spectrum window). Modeled on the
Spectrum windows in each UI mode.

## Accessing

- Window menu / main window right-click context menu → **Audio Analysis**
- Available in classic and modern UI modes.

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
- **Chrome rendering — modern.** `ModernAudioAnalysisView` draws the modern skin title bar + close
  button (`spectrum_` prefix) and insets the SwiftUI hosting view into the content area via
  `contentAreaRect()` / `layoutHostingView()`. Its hosting view uses an aqua/darkAqua appearance
  selected from the modern skin brightness.
- **Chrome rendering — classic.** `AudioAnalysisView` uses `SkinRenderer`'s playlist/spectrum-style
  chrome with the `AUDIO ANALYSIS` bitmap title and no shade button. It hosts the same SwiftUI pane
  content inside the classic side and bottom borders. Neither mode may cover its chrome with the
  pane's opaque black background.

## Panes

| Pane | Source notification | Consumer(s) it registers | Render |
|------|--------------------|----------------------|--------|
| **Scope** (oscilloscope) | `.audioPCMDataUpdated` (`userInfo["pcm"]` 512 mono) | spectrum | CoreGraphics (`NSView`) |
| **Levels** (peak/RMS) | `.audioStereoPCMDataUpdated` (`left`/`right` 512) | stereo | SwiftUI bars |
| **Spectrogram** (waterfall) | `.audioSpectrumDataUpdated` (`spectrum` 75 bands) | spectrum | Metal (`MTKView`) |
| **Octave** (1/3-octave spectrum) | `.audioFFTMagnitudesUpdated` (`magnitudes` raw linear, `sampleRate`, `fftSize`) | spectrum + magnitudes | CoreGraphics (`NSView`) bars + peak-hold |
| **Pitch** (fundamental frequency) | `.audioPCMDataUpdated` (512 mono) | spectrum | SwiftUI (Hz, note name, cents deviation) |
| **Delay** (L/R phase delay) | `.audioStereoPCMDataUpdated` (`left`/`right` 512) | stereo | SwiftUI (ms, samples, direction) |

`.audioPCMDataUpdated` is posted *inside* the spectrum block, so the Scope and Pitch panes register a
**spectrum** consumer (not a dedicated PCM one) to make mono PCM flow.

**Octave requires dual consumers:** it registers both **spectrum** (to trigger the FFT) and
**magnitudes** (to receive raw linear magnitudes). This is the only pane that gates the magnitudes
path; all others share existing notification/consumer infrastructure.

## Architecture

- **Windows**: `Windows/ModernAudioAnalysis/ModernAudioAnalysisWindowController.swift` and
  `Windows/AudioAnalysis/AudioAnalysisWindowController.swift` conform to
  `App/AudioAnalysisWindowProviding.swift`. Their skin-specific NSViews host the shared pane content.
- **Shared UI and gating**: `Windows/AudioAnalysis/AudioAnalysisContentView.swift` and
  `AudioAnalysisConsumerCoordinator.swift`.
- **Pane selection state**: `AudioAnalysisModel: ObservableObject` (`@Published var selectedPane`),
  owned by the NSView and observed by `AudioAnalysisContentView`. The right-click `menu(for:)` mutates
  it (radio items + Close); the shared content view's `.onChange` persists it (UserDefaults) and
  invokes its `onPaneChange` callback, which each window's NSView routes to
  `controller.setVisiblePane(_:)` → `AudioAnalysisConsumerCoordinator`.
- **Panes**: shared files under `Windows/AudioAnalysis/`: `ScopePaneView.swift`,
  `LevelsPaneView.swift` (vertical full-height peak/RMS meters, no title text),
  `SpectrogramPaneView.swift`, `OctavePaneView.swift` (1/3-octave bands CoreGraphics with peak-hold),
  `PitchPaneView.swift` (Hz + note + cents SwiftUI), and `DelayPaneView.swift` (stereo delay
  cross-correlation SwiftUI).
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

- **Magnitudes path** (new): `Audio/AudioEngine.swift` and `Audio/StreamingAudioPlayer.swift` publish
  `.audioFFTMagnitudesUpdated` (userInfo: `"magnitudes"` raw linear half-spectrum, `"sampleRate"`,
  `"fftSize"`) gated by `addMagnitudesConsumer`/`removeMagnitudesConsumer`/`magnitudesNeeded`.
  Posted inside the spectrum FFT block, *after* magnitudes are computed but *before* dB conversion.
  Octave pane is the sole consumer; the gating cost is zero when no Octave pane is visible.

## Consumer gating (CPU)

`AudioAnalysisConsumerCoordinator` owns the gating (shared by both windows): `setVisiblePane(_:)`
maps each pane to its consumer(s):
- Scope (pane 0) → spectrum
- Levels (pane 1) → stereo
- Spectrogram (pane 2) → spectrum
- Octave (pane 3) → spectrum + magnitudes (dual consumers)
- Pitch (pane 4) → spectrum
- Delay (pane 5) → stereo

Only the visible pane's consumer(s) are registered; others are removed. `deregisterAll()` removes
everything via a `consumerRemovers` map that tracks which remove function to call per consumer ID.
The controller registers the initial pane in `showWindow(_:)`; the shared content view re-invokes
it on `.onChange(of: model.selectedPane)`. Both `stopRenderingForHide()` and `windowWillClose` call
`consumerCoordinator.deregisterAll()` so a hidden/closed window leaves the FFT, stereo, and
magnitudes paths idle. The spectrogram also pauses its `MTKView` (`isPaused`) while hidden or
miniaturized.

## Persistence

Window frame saved in `AppStateManager` session state (`audioAnalysisWindowFrame`). On restore it's
gated by a UI-mode match (`modeMatches`), so a frame saved in classic only restores in classic and
vice-versa. The selected pane persists via `UserDefaults`
(`AudioAnalysisModel.selectedPaneDefaultsKey`). Docks/snaps with Main/EQ/Playlist/Spectrum via
`WindowManager`.

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
- **Modern independence / shared layer**: files under `Windows/ModernAudioAnalysis/` must not import
  from `Skin/` or `Windows/MainWindow/`. The shared files in `Windows/AudioAnalysis/` (content view,
  model, coordinator, panes) must stay **mode-neutral** — no modern- or classic-skin-specific imports;
  only the classic shell (`AudioAnalysisView` / `AudioAnalysisWindowController`) may use `Skin/`.
- **Two playback paths**: any new tap data must be emitted by both `AudioEngine` and the
  `StreamingAudioPlayer` delegate route, or streaming silently misses it.

See [visualizations](../visualizations/SKILL.md) for the visualization index and
[spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md) for the related spectrum window.
