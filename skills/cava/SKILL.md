# Cava Spectrum Analyzer

Cava is a responsive, bar-based audio spectrum analyzer window built on a clean-room Swift reimplementation of the cava algorithm (https://github.com/karlstav/cava, MIT-licensed).

## Accessing Cava

Open **Windows > Cava** in the menu bar or right-click any main window to toggle the standalone
Cava window. Cava is also available inside the 76×16 main-window visualization area via
**Visuals > Main Window > Mode > Cava**.

## What It Shows

Cava renders real-time audio spectrum as vertical bars:
- **Mono mode:** Single row of bars growing up from the bottom edge, reflecting the two channels combined (see the mono magnitude-averaging note under Gotchas)
- **Stereo mode:** Mirrored layout — left channel grows upward (top half), right channel grows downward (bottom half)

Each bar's color is interpolated between a **low color** (short/quiet bars) and a **high color** (tall/loud bars) — i.e. by bar *height / intensity*, NOT by frequency. Many named presets are available (see Right-Click Menu), including metallic gradients. Bar heights respond in real time to audio content; decay and smoothing are built into the DSP.

## Audio Path

Cava consumes the full-stereo audio tap from `AudioEngine`. The tap is emitted by **both** playback paths:
- Local file playback via `AVAudioEngine`
- Streaming audio via `AudioStreaming` library

The tap fires at the source rate (typically 44.1/48 kHz), producing 2048 samples per notification. The local `AVAudioEngine` path posts from its audio callback; the streaming path coalesces onto the main queue before `AudioEngine` forwards the notification. `CavaRenderModel` observes with `queue: nil`, marshals buffer ownership to the main thread, and schedules all `CavaCore` access on its serial processing queue.

## DSP (CavaCore Algorithm)

CavaCore implements the cava spectrum analyzer in pure Swift using Accelerate vDSP. Pipeline per
channel, in order:

1. **Dual FFT:** Parallel bass (4096-point DFT) and treble (2048-point DFT, used above 4 kHz). Each real input chunk receives a matching-length Hann window before any zero-padding; the normal 2048-sample tap is therefore Hann-windowed at 2048 samples before entering the 4096-point bass DFT.
2. **Contiguous log bands, energy ÷ bin-count exponent:** Each bar maps to a **non-overlapping** log-spaced frequency band `[edge(n), edge(n+1))` (50 Hz–10 kHz); its value is the summed magnitude divided by `binCount^bandExponent`. Plain `sum` over-weights high bars (treble bands span far more FFT bins than bass bands) and suppresses bass; `mean` does the opposite. Exponent `bandExponent` (default **0.3**) is the tilt knob: `sum` (÷N^0) = brightest, `mean` (÷N^1) = bassiest, and √N (÷N^0.5) is the neutral midpoint. The 0.3 default keeps bass strong while letting mid/high frequencies read clearly.
3. **Monstercat neighbor smoothing:** Spatial blur across adjacent bars (stateless).
4. **Integral/exponential smoothing:** Per-bar temporal EMA, `alpha = 1 - noiseReduction` (app default 0.65). Higher noiseReduction = smoother but less dynamic.
5. **Autosens (before gravity):** A persistent gain (`sens`) scales the magnitudes. See the autosens gotcha for the fast-attack/slow-release + deadband + low-start design.
6. **Clamp to [0,1], then gravity/falloff:** Instant rise, gravity fall. Clamping BEFORE gravity keeps `peakValues` in the normalized domain (a pre-convergence spike can't poison it). See the gravity gotcha for the `>=` requirement.

Output: Per-channel bar arrays in 0…1 range. The order matters: **autosens must run before gravity**, and gravity operates in the normalized domain, or bars never decay to zero on silence.

## Rendering

`CavaDrawing` (CoreGraphics, mode-neutral) renders gradient bars:
- Interpolates each bar's color between the low- and high-**intensity** colors by bar height (not by frequency)
- Draws solid rectangles per bar with subtle borders for definition
- Handles both mono (single row) and stereo (mirrored L/R) layouts

`CavaRenderModel` drives a **60 Hz scheduler** on the main thread while confining all DSP to one serial worker queue:
- The audio tap (~21 Hz) *stashes* the latest L/R buffer. On the next tick the worker calls `CavaCore.analyze(_:)` (the FFTs) **once per new buffer**, then `CavaCore.render()` (monstercat/smoothing/autosens/gravity) on render ticks so decay/smoothing advance at the display rate. Only the finished bar arrays return to the main thread. `execute(_:)` (= `analyze` + `render`) is kept for tests/one-shot callers.
- At most one worker operation is outstanding. Incoming audio is coalesced to the newest buffer while it is busy, preventing a queue backlog during other expensive UI operations.
- Normal playback reads settings on new-audio ticks rather than 60×/sec. Explicit menu/double-click changes call `settingsDidChange()` so mode and tuning also update immediately while paused or stopped.
- **Pause-freeze:** if no new audio arrives for >~6 ticks (~100 ms), the timer stops re-running the stale buffer and holds the last frame. Re-running a static buffer indefinitely would let autosens hunt and the display throb; freezing keeps a paused Cava perfectly still.
- Idle-skip: a per-frame signature detects settled bars and skips the redraw (not the DSP), so a static display costs no repaint.
- Calls `onNeedsDisplay` (the views invalidate their content/animation rect) only when bars change.

Both classic and modern views call `CavaDrawing.draw()` with current bar data, low/high colors, and mode.
The embedded main-window instance uses its own `CavaPresenter(scope: .mainWindow)`, always renders
mono, and has a scope-distinct audio consumer and processing queue so it can run independently beside
the standalone window.

## Window Layout

- **Both modes:** Single-height center-stack window (like Flow / NetworkMonitor / Spectrum)
- **Classic:** `SkinRenderer` draws border-only chrome (title "CAVA" + close button)
- **Modern:** `ModernSkinRenderer` chrome with `spectrum_*` style elements (title bar + close button)
- **Whole-face drag:** Click title bar or content area to drag; **double-click anywhere toggles Mono ⇄ Stereo**; close button in top-right
- **Hide Title Bars (modern):** Modern center-stack subwindows hide their titlebar whenever docked; the global Hide Title Bars setting also hides it while detached. The close button is then unreachable, but the content remains draggable. Classic Cava always keeps its classic chrome.
- **Docking:** Participates in center-stack docking (snaps below main/other windows)

## Right-Click Menu

- **Mono** / **Stereo:** Toggle between single-row and mirrored layouts (double-click the window does the same)
- **Color:** Submenu with **Match Skin** at the top, then named gradient presets (each with a low→high swatch and a checkmark on the active one). Presets include standard combos (Blue → Magenta, Fire, Ice, Vaporwave, Aurora, Ocean, Neon, …) and a metallic set (Gold, Silver, Copper, Bronze, Gunmetal). Selecting a preset sets `lowGradientColor`/`highGradientColor`, sets `hasCustomColors = true`, and persists. **Match Skin** clears `hasCustomColors` so the gradient follows the active skin again (see below).
- **Transparent Background** (modern only): Off by default — Cava is opaque. Toggling it on drops the window background to the skin's `window.opacity` (the metal/translucent look). Not shown in classic (classic Cava is always opaque black).
- **Bars:** Bar-count presets (16 / 24 / 32 / 48 / 64).
- **Smoothing:** Temporal smoothing / latency (`noiseReduction`): Snappy (0.50) · Balanced (0.65, default) · Smooth (0.80) · Very Smooth (0.90). Lower = more real-time but livelier; higher = smoother but laggier.
- **Bass:** Bass↔treble tilt (`bandExponent`): Less (0.15) · Balanced (0.30, default) · More (0.50) · Max (0.70).
- **Reset to Defaults:** Restores Bars / Smoothing / Bass to factory defaults (`CavaSettings.resetTuning()`); leaves mode, colors, and transparency untouched.
- **Close:** Hide the window

The menu is built and handled by `CavaPresenter` itself (an `NSObject` with `@objc` actions targeting `self`); the view only supplies the `onNeedsDisplay` / `onNeedsFullDisplay` / `onClose` closures. Changing Bars / Smoothing / Bass updates `CavaSettings`; `CavaRenderModel.settingsDidChange()` applies the change immediately and rebuilds `CavaCore` when bar count, sample rate, `noiseReduction`, or `bassTilt` differs.

## Persistence (AppStateManager)

- **Window visibility/frame:** Visibility is restored in either UI mode. The exact saved frame is restored only when the saved and running UI modes match; otherwise Cava opens at the target mode's default stack position.
- **Durable preferences:** `CavaSettings` (UserDefaults) — mode selection, bar count, gradient colors — persist independently of Remember State
- **Restoration:** On launch, if Cava was visible, `showCava(at:)` repositions it at the saved frame (or default stack position if no frame saved)

## Settings (CavaSettings)

Durable UserDefaults-backed preferences:

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `cavaMode` | Int (enum) | 1 (stereo) | 0=mono, 1=stereo |
| `cavaBarCount` | Int | 32 | 1–128; clamped on set |
| `cavaLowGradientColor` | NSColor (archived) | Bright blue (0, 0.3, 1) | Low-intensity (short-bar) color; used only when `cavaColorsCustomized` |
| `cavaHighGradientColor` | NSColor (archived) | Magenta (1, 0, 1) | High-intensity (tall-bar) color; used only when `cavaColorsCustomized` |
| `cavaColorsCustomized` | Bool | false | If false, colors follow the skin (Match Skin) |
| `cavaTransparentBackground` | Bool | false | Modern-only translucent background |
| `cavaNoiseReduction` | Double | 0.65 | Smoothing / latency (0…0.95) |
| `cavaBassTilt` | Double | 0.30 | Bass↔treble tilt (`bandExponent`, 0…1) |

Access via `CavaSettings.mode`, `CavaSettings.barCount`, etc. Menu and double-click changes take effect immediately; settings that alter DSP construction recreate CavaCore through `settingsDidChange()`.

`CavaSettings.Scope` separates `.cavaWindow` from `.mainWindow`. The legacy static properties above
remain wrappers for `.cavaWindow` and continue using the existing keys. Scope-aware accessors use
`cava.mainWindow.*` keys for the embedded analyzer. Main-window tuning and color choices are reset
with the centralized Main Window visualization reset and never modify the standalone window.

## Key Files

| File | Role |
|------|------|
| `Cava/CavaSettings.swift` | UserDefaults-backed preferences (mode, bar count, colors) |
| `Cava/CavaRenderModel.swift` | Observes audio tap, feeds CavaCore, 60 Hz timer, idle skip |
| `Cava/CavaDrawing.swift` | CoreGraphics bar renderer (mode-neutral) |
| `Cava/CavaPresenter.swift` | Shared runtime, menu builder, display notifications |
| `App/CavaWindowProviding.swift` | Protocol for classic/modern implementations |
| `Windows/Cava/CavaWindowController.swift` | Classic window controller (NSWindowController) |
| `Windows/Cava/CavaView.swift` | Classic view (NSView, draws + handles drag/clicks) |
| `Windows/ModernCava/ModernCavaWindowController.swift` | Modern window controller |
| `Windows/ModernCava/ModernCavaView.swift` | Modern view (NSView, modern skin renderer, corner radius) |
| `App/WindowManager.swift` | Integration: `showCava()`, `toggleCava()`, `cavaWindowFrame`, center-stack logic |
| `App/ContextMenuBuilder.swift` | Menu item: "Cava" in Windows menu + `toggleCava()` action |
| `Windows/MainWindow/MainWindowView.swift` | Classic inline Cava rendering + lifecycle |
| `Windows/ModernMainWindow/ModernMainWindowView.swift` | Modern inline Cava rendering + lifecycle |
| `App/AppStateManager.swift` | State capture/restore: `isCavaVisible`, `cavaWindowFrame` |
| `NullPlayerCore/Audio/CavaCore.swift` | DSP engine (pure Swift vDSP FFT + smoothing) |

## Gotchas

### Mode Independence (Hard Rule)
Files in `Cava/` must NOT import `Skin/` or `ModernSkin/`. Files in `Windows/ModernCava/` must NOT import `Skin/` or `Windows/MainWindow/`. Coupling only via:
- `WindowManager` (via provider protocol)
- `AudioEngine` (shared service, no UI dependency)
- `CavaSettings` (UserDefaults enum)
- Shared models (NSColor, NSRect, etc.)

### Audio Tap Availability
Both playback paths (local + streaming) emit the stereo tap:
- Local: `AVAudioEngine` PCM tap installed at engine setup
- Streaming: `AudioStreaming` library's real-time PCM tap (different implementation, same notification)

**Critical:** If only one playback path is in use, Cava will update while that path plays. The tap is idled when Cava is hidden (no consumer registered).
The standalone and embedded render models use different consumer IDs, so opening or hiding either
one cannot unregister the other's tap demand.

### Notification Threading
`Notification.Name.audioStereoPCMFullDataUpdated` arrives from different queues: local playback posts from the audio callback, while streaming playback forwards it on the main queue after coalescing. `CavaRenderModel` observes with `queue: nil` and explicitly marshals buffer assignment to main via `DispatchQueue.main.async`. The timer then coalesces the newest buffer onto the serial Cava processing queue; only completed bar arrays and display invalidation return to main. Never touch UI or run FFT work directly from the observer block.

### Gravity must rise/hold on `>=`, not `>` (the big jitter bug)
`applyGravityAndFalloff` had `if bars[i] > peakValues[ch][i]` (strict). At steady state `bars[i] == peakValues`, so it fell through to the decay branch, subtracted the `falloff` (0.05), then snapped back up the next frame — a self-sustaining **period-2 flicker of amplitude 0.05 on every bar, even on a perfectly constant signal**. Barely visible on tall bars, a violent ±60% strobe on short bars ("short bars jitter intensely"). Fix: rise/hold on `>=`, and clamp the gravity fall so it never undershoots the current value (`max(bars[i], peak - falloff)`). Constant-input test coverage must remain steady.

### Autosens is a persistent gain: low start, fast attack, slow release, deadband
`sens` is a single persistent gain (not a per-frame AGC), applied to magnitudes *before* gravity. Design, learned the hard way:
- **Start LOW (`1e-6`) and grow into the signal** during `sensInit` (×1.2/frame until first overshoot). Starting at 1.0 was far too high for summed-energy magnitudes, so every bar clipped at full scale for ~5 s at launch while the gain ground down. Starting low means bars *ramp up* from small instead of pinning.
- **Hold gain on digital silence.** Initial grow-in and later recovery are gated on a non-silent raw magnitude. Growing `sens` during leading silence can hit its cap before the first audible sample and pin the display for tens of seconds.
- **Gentle attack (×0.98) on overshoot**, NOT an aggressive proportional attack — a hard attack ducks the whole spectrum on every transient (reads as pumping/jitter). A single bar briefly touching the ceiling is normal.
- **Deadband:** only *recover* (×1.001) when the peak is well below the ceiling (< 0.85); hold the gain steady in `[0.85, 1.0]`. Otherwise the gain hunts up-into-clip and back — a global throb, very visible when paused.
- Do NOT re-introduce a per-frame "divide by the running peak" AGC: it re-inflates a decaying tail so bars never fall to zero on silence.

### Mono averages magnitude spectra, not the time-domain signals
Mono is NOT `(L+R)*0.5` in the time domain — summing stereo material comb-filters it (phase differences create moving spectral notches = jitter that only appears in mono). Instead `CavaRenderModel` always runs `CavaCore` with `channels: 2` and, for mono display, **averages the two channels' output bar arrays**. Channel count therefore never changes on a mode switch; bar count, sample rate, smoothing, and bass tilt can rebuild the core.

### Bar energy = band sum ÷ bin-count exponent — this sets the bass/treble tilt
Bars sum magnitudes over contiguous non-overlapping log bands, then divide by `binCount^bandExponent` (default 0.3). This normalization IS the frequency-balance knob, because high-frequency bands span many more FFT bins than bass bands:
- `max` over overlapping ±10% ranges (original) → bass dominant, treble dead.
- plain `sum` → treble dominant, **bass suppressed too much**.
- `sum ÷ N` (mean) → bass-heavy again.
- `sum ÷ N^0.5` (√N) → neutral midpoint.
- `sum ÷ N^0.3` (`CavaCore.bandExponent`, current) → strong bass but mid/high still read clearly.
Tune the single `bandExponent` constant (0=sum … 1=mean) if the tilt needs adjusting; don't reach for a separate EQ table first.

### Verifying DSP changes without the app
If the full XCTest bundle cannot launch because of its dynamic-framework rpaths/codesigning, test `CavaCore` with a standalone `swiftc` harness linked against the built objects:
`swiftc -O harness.swift -I .build/arm64-apple-macosx/debug/Modules .build/arm64-apple-macosx/debug/NullPlayerCore.build/*.o -framework Accelerate -o harness`. Important coverage includes **identical-input steadiness** (constant in → constant out), frequency localization, stereo panning, autosens bounds, silence decay, leading-silence gain stability, launch ramp, and paused-buffer stability.

### Keep all DSP off the main thread and coalesce work
The 60 Hz `Timer` is only a scheduler. Both `CavaCore.analyze` and `CavaCore.render` run on `com.nullplayer.cava.processing`, and the core is confined to that serial queue. This matters especially in debug builds, where the dual FFTs are much slower and can compound unrelated main-thread work such as library expansion into visible stalls. Keep FFT analysis at the audio-buffer cadence (~21 Hz), permit at most one processing operation at a time, and coalesce incoming audio to the newest buffer while busy. Only immutable bar-array results should cross back to main for display.

### Idle Skip + Timer
The 60 Hz timer redraws only if the ordered bar signature changed. Closing, ordering out, miniaturizing, or fully occluding the window stops the render model and unregisters its full-stereo consumer; showing/deminiaturizing it starts them again. A visible settled display keeps the timer but skips redundant repaints.

### Do NOT inherit the spectrum window's transparency
`ModernCavaView` draws its background via `renderer.drawWindowBackground(..., backgroundOpacity:)`. Passing `renderer.skin.spectrumWindowBackgroundOpacity` (= the skin's `window.opacity`) made Cava translucent on metal/modern skins that set a low window opacity — not wanted by default. Use `effectiveBackgroundOpacity` (1.0 unless `CavaSettings.transparentBackground` is on). Also fill the content background in `drawCavaContent` when opaque, because the timer fast-path (animation-rect-only redraw) skips `drawWindowBackground` and would otherwise leave the content transparent between frames. `transparentBackground` is a durable `CavaSettings`/UserDefaults pref, default false, modern-only.

### Colors follow the skin until the user overrides
Cava's *default* gradient tracks the active skin; a user pick (via the Color menu) overrides it until they choose **Match Skin**:
- `CavaSettings.hasCustomColors` (UserDefaults) gates this. `effectiveLowColor`/`effectiveHighColor` return the user's stored colors when true, otherwise the in-memory skin default.
- The skin default is pushed by the **skin-aware views** (they can import `Skin/`/`ModernSkin/`; `CavaSettings` can't), in `commonInit` and `skinDidChange`:
  - **Classic** (`CavaView`): the "Winamp Green" preset — green, like the classic Winamp spectrum.
  - **Modern** (`ModernCavaView`): `skin.config.palette.resolvedPrimary()` → `resolvedAccent()`, so it matches each modern skin's palette automatically.
- `setSkinDefaultColors(low:high:)` is the plain-NSColor bridge that keeps `CavaSettings` free of skin imports. The default is in-memory (recomputed each session), not persisted — only the user override and the `hasCustomColors` flag persist.

### Color Persistence
`CavaSettings` archives/unarchives NSColor via `NSKeyedArchiver` (legacy Cocoa binary format). This works but is brittle; avoid changing color archiving logic. If colors fail to load, defaults kick in silently.

### Window Sizing
- Classic: Uses `SkinElements.SpectrumWindow.windowSize` / `minSize` (shared with Spectrum Analyzer)
- Modern: Uses `ModernSkinElements.spectrumWindowSize` / `spectrumMinSize`

Cava is single-height (multiplier = 1.0 in `centerStackHeightMultiplier`), same as Flow and Spectrum (single-bar window).

### Corner Radius (Modern)
Modern Cava view reads corner radius from the current skin config and applies via `layer.cornerRadius`. If skin changes, the radius updates. Sharp corners are computed per adjacent docked edge.

### Encoding/Decoding in AppStateManager
`WindowState` uses `CodingKeys` to map property names to string keys. `isCavaVisible` and `cavaWindowFrame` must appear in the enum and all decode/encode branches, or state save/restore fails silently.

## Comparison Table: Cava vs. Other Spectrum Windows

| Aspect | Cava | Spectrum Analyzer | Audio Analysis | Flow |
|--------|------|-------------------|-----------------|------|
| **Input** | Full-rate stereo PCM | Shared spectrum + waveform notifications | Stereo PCM + FFT magnitudes/spectrum | Network throughput |
| **Output** | Bars (16–64 menu presets) | Spectrum/ambient visualization modes | Scope/Levels/Spectrogram/Octave/Pitch/Delay | Upload/Download |
| **Rendering** | CoreGraphics bars | Metal GPU spectrum | Metal GPU multi-pane | CoreGraphics bars |
| **DSP** | cava vDSP FFT+smooth | vis_classic FFT | friture-style analysis | Network syscalls |
| **CPU** | Low (idle skip) | Medium (Metal overhead) | High (3 panes) | Negligible |
| **Customization** | Mode (mono/stereo), bar count, colors | vis_classic profiles | Pane visibility | Interface selection |

## When to Use Cava

- **Want bar-based spectrum?** Cava (responsive, low CPU)
- **Want waveform/frequency detail?** Spectrum Analyzer
- **Want multi-pane analysis (scope+levels+spec)?** Audio Analysis Window
- **Want network throughput?** Flow
