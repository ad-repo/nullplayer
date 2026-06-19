---
name: audio-analysis-window
description: The modern-UI Audio Analysis window — a Friture-style multi-pane analyzer (Scope, Levels, Spectrogram), the stereo PCM path that feeds it, per-pane consumer gating, and the shared AudioAnalysisDSP module. Use when modifying the analysis window, its panes, the spectrogram shader, or the stereo/DSP plumbing.
---

# Audio Analysis Window

A modern-UI-only window offering a Friture-style (https://friture.org) real-time view of the
playing audio. A SwiftUI segmented picker switches between panes; exactly one pane is visible at
a time. Modeled on the `ModernSpectrum` window pattern and has **zero** dependencies on the
classic skin system.

## Accessing

- Window menu / right-click main window → **Audio Analysis** (guarded by `isModernUIEnabled`)
- Available in **modern UI mode only**.

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
  `App/AudioAnalysisWindowProviding.swift`) + `ModernAudioAnalysisView.swift` (SwiftUI host + picker).
- **Panes**: `ScopePaneView.swift`, `LevelsPaneView.swift`, `SpectrogramPaneView.swift`.
- **Shader**: `Visualization/SpectrogramShaders.metal` — fullscreen quad generated from
  `[[vertex_id]]` (no vertex buffer), samples an `r32Float` history texture, Viridis colormap LUT.
  Low frequencies at the bottom (texCoord.y = 0).
- **DSP**: `Sources/NullPlayerCore/Audio/AudioAnalysisDSP.swift` — pure-Swift, unit-tested
  (`Tests/NullPlayerCoreTests/AudioAnalysisDSPTests.swift`): `peakDBFS`, `rmsDBFS`, `octaveBands`,
  `estimatePitchHz` (autocorrelation), `estimateDelaySamples` (L/R cross-correlation).
- **Stereo path**: `Audio/AudioEngine.swift` and `Audio/StreamingAudioPlayer.swift` publish
  `.audioStereoPCMDataUpdated` (downsampled L/R) gated by `addStereoConsumer`/`removeStereoConsumer`/
  `stereoNeeded`, mirroring the spectrum/waveform consumer pattern. Wired in **both** the local
  engine and the streaming delegate (`streamingPlayerDidUpdateStereoPCM(left:right:sampleRate:)`).

## Consumer gating (CPU)

`ModernAudioAnalysisView` calls `controller.setVisiblePane(_:)` on `.onAppear` and
`.onChange(of:selectedPane)`; the controller registers exactly the visible pane's consumer and
`windowWillClose` calls `deregisterAllConsumers()`. A hidden/closed window must leave the FFT and
stereo path idle. The spectrogram also pauses its `MTKView` (`isPaused`) on window miniaturize and
when removed from its window.

## Persistence

Window frame saved in `AppStateManager` session state (`audioAnalysisWindowFrame`, gated by
`savedInModernMode`); the selected pane persists via `UserDefaults`. Docks/snaps with
Main/EQ/Playlist/Spectrum via `WindowManager`.

## Gotchas

- **Notifications post from the audio thread.** Observers must marshal to main: AppKit observers
  use `addObserver(forName:object:queue:.main)`; the SwiftUI Levels pane uses
  `.publisher(for:).receive(on: DispatchQueue.main)`. Mutating SwiftUI `@State` off-main is a bug.
- **Metal**: guard `pipelineState` and `historyTexture` **before** creating the command encoder
  (see [metal-gotchas](../metal-gotchas/SKILL.md)); watch the render-to-texture y-flip. The
  spectrogram uses paced `MTKView` drawing (`preferredFramesPerSecond`), not a manual timer loop.
- **Modern independence**: files under `Windows/ModernAudioAnalysis/` must not import from `Skin/`
  or `Windows/MainWindow/`.
- **Two playback paths**: any new tap data must be emitted by both `AudioEngine` and the
  `StreamingAudioPlayer` delegate route, or streaming silently misses it.

See [visualizations](../visualizations/SKILL.md) for the visualization index and
[spectrum-analyzer-window](../spectrum-analyzer-window/SKILL.md) for the related spectrum window.
