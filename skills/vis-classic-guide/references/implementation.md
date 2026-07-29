# vis_classic Implementation Reference

## 1. Scope and Source Map

`vis_classic` in NullPlayer is an exact-style CPU analyzer core (`CVisClassicCore`) integrated into the existing Metal render loop (`SpectrumAnalyzerView`) for both:
- main-window embedded visualization
- standalone spectrum window visualization

Primary code paths:
- `Sources/CVisClassicCore/VisClassicCore.cpp`
- `Sources/CVisClassicCore/include/VisClassicCore.h`
- `Sources/CVisClassicCore/upstream/*.cpp` (Nullsoft upstream math/helpers)
- `Sources/NullPlayer/Visualization/VisClassicBridge.swift`
- `Sources/NullPlayer/Visualization/SpectrumAnalyzerView.swift`
- `Sources/NullPlayer/Audio/AudioEngine.swift`
- `Sources/NullPlayer/App/ContextMenuBuilder.swift`
- `Sources/NullPlayer/Windows/MainWindow/MainWindowView.swift`
- `Sources/NullPlayer/Windows/ModernMainWindow/ModernMainWindowView.swift`
- `Sources/NullPlayer/Windows/Spectrum/SpectrumView.swift`
- `Sources/NullPlayer/Windows/ModernSpectrum/ModernSpectrumView.swift`

Bundled profiles:
- `Sources/NullPlayer/Resources/vis_classic/profiles/*.ini`

## 2. End-to-End Data Flow

## 2.1 Audio waveform production

`AudioEngine` produces 576-sample stereo unsigned-8 waveform chunks for vis_classic:
- floating PCM ring buffers: `waveformLeftRing` / `waveformRightRing`
- chunk conversion: float `[-1, 1]` -> uint8 `[0, 255]` via `sample * 127 + 128`
- notification posted: `.audioWaveform576DataUpdated`
- userInfo payload keys: `left`, `right`, `sampleRate`

Implementation location:
- `AudioEngine.enqueueWaveformSamplesAndPost(...)`
- `AudioEngine.postAvailableWaveformChunks(...)`

## 2.2 Visual consumer and render loop

`SpectrumAnalyzerView` subscribes to `.audioWaveform576DataUpdated` and stores the latest vis_classic waveform.

When `qualityMode == .visClassicExact`, render loop behavior differs from GPU spectrum modes:
- skips generic spectrum decay/idle transform path
- uses vis_classic waveform-driven frames
- calls `renderVisClassicExact(drawable:)`

`renderVisClassicExact(drawable:)` pipeline:
1. Lazily create `VisClassicBridge` (scoped by embedded/main-window vs spectrum-window).
2. Send latest waveform to C core via `bridge.updateWaveform(...)`.
3. Ask C core to CPU-render BGRA frame bytes via `bridge.renderFrame(...)`.
4. Upload bytes to shared `MTLTexture` (`replace(region:...)`).
5. Blit texture to drawable via Metal blit encoder.

## 2.3 Main-window vs spectrum-window scope

`SpectrumAnalyzerView.visClassicPreferenceScope`:
- `.mainWindow` when `isEmbedded == true`
- `.spectrumWindow` when standalone

This scope controls independent persistence keys for:
- last profile name
- fit-to-width flag
- transparent-background flag

## 3. Profile Lifecycle and Storage

## 3.1 Bootstrapping and discovery

`VisClassicBridge.ensureProfilesBootstrapped()` copies bundled profiles into user profile directory only if user directory is empty.

Directories:
- bundled: app resources `vis_classic/profiles`
- user: `~/Library/Application Support/NullPlayer/vis_classic/profiles`

`availableProfilesCatalog()` behavior:
- load bundled `.ini`
- load user `.ini`
- merge by profile name
- user profile with same name overrides bundled entry
- sort case-insensitively

## 3.2 Persistence keys

Window-scoped keys:
- `visClassicLastProfileName.mainWindow`
- `visClassicLastProfileName.spectrumWindow`
- `visClassicFitToWidth.mainWindow`
- `visClassicFitToWidth.spectrumWindow`
- `visClassicTransparentBg.mainWindow`
- `visClassicTransparentBg.spectrumWindow`
- `visClassicOpacity.mainWindow`
- `visClassicOpacity.spectrumWindow`

Legacy fallback keys:
- `visClassicLastProfileName`
- `visClassicFitToWidth`

Default if fit key missing: `true`

## 3.3 Load/save/import/export

Bridge operations:
- `loadProfile(url:)` -> `vc_load_profile_ini`
- `saveCurrentProfile(to:)` -> `vc_save_profile_ini`
- `importProfile(from:)` copies `.ini` into user profile directory; auto-suffixes duplicate names (`name 2`, `name 3`, ...)
- profile cycling: `loadNextProfile()`, `loadPreviousProfile()`

## 4. Command/Control Surface

## 4.1 Notification command bus

Notification: `.visClassicProfileCommand`

Expected userInfo keys:
- `command`: `load`, `next`, `previous`, `import`, `export`, `fitToWidth`, `transparentBg`
- optional `profileName` for `load`
- optional `enabled` for explicit fit-to-width or transparent-background set
- `target`: `mainWindow` or `spectrumWindow`

`SpectrumAnalyzerView.handleVisClassicProfileCommand(_:)` applies command only if:
- current mode is `.visClassicExact`
- window is visible
- target matches view scope (`isEmbedded` vs standalone)

## 4.2 Menu integration

Global menu/context menu builder (`ContextMenuBuilder`):
- emits scoped commands for both main window and spectrum window
- profile submenu checkmarks use scoped last-profile keys
- fit checkmarks use scoped fit keys
- transparent-background checkmarks use scoped transparent keys

Local spectrum window context menus (`SpectrumView`, `ModernSpectrumView`):
- call `SpectrumAnalyzerView` vis_classic methods directly

## 4.3 Transparent-background rendering behavior

- `SpectrumAnalyzerView` applies transparent-mode state to both bridge options and layer opacity (`metalLayer.isOpaque`, `layer?.isOpaque`).
- Main-window hosts (classic and modern) redraw host chrome around the analyzer when transparent mode changes.
- Classic standalone spectrum window (`SpectrumView`) clears its analyzer content rect after drawing chrome when vis_classic transparent mode is enabled. This is required so transparent analyzer pixels do not sit on top of already-painted window content.

## 4.4 Keyboard shortcuts

Main window (`MainWindowView`, `ModernMainWindowView`):
- `,` previous vis_classic profile
- `.` next vis_classic profile

Spectrum window (`SpectrumView`, `ModernSpectrumView`):
- `[` previous vis_classic profile
- `]` next vis_classic profile
- left/right arrows also map to previous/next profile when mode is vis_classic

## 5. C Core Behavior (CVisClassicCore)

## 5.1 Public C API

From `VisClassicCore.h`:
- `vc_create`, `vc_destroy`
- `vc_set_waveform_u8`
- `vc_render_rgba`
- `vc_set_option`, `vc_get_option`
- `vc_load_profile_ini`, `vc_save_profile_ini`
- `vc_get_last_error`

## 5.2 Per-frame processing

1. Convert incoming uint8 waveform to signed float centered at 0.
2. FFT using upstream `FFT` implementation.
3. Scale FFT bins by `FFTScale` (divide; lower scale => more sensitive).
4. Build logarithmic bar-bin allocation using `LogBarValueTable`.
5. Compute bar levels per band with `Bar Level` aggregation mode.
6. Apply falloff and peak timer logic.
7. Draw bars + peaks to BGRA buffer with profile color maps and styles.

## 5.3 Analyzer options and exact meanings

All loaded from `[Classic Analyzer]` INI section:

- `Falloff` (`0..255`)
  - per-frame decay amount for dropping bars
  - higher = faster fall

- `PeakChange` (`0..255`)
  - peak hold timer length before peak drops by 1 pixel/unit per frame
  - `<= 0` disables peaks

- `Bar Width` (`1..64`)
- `X-Spacing` (`0..32`)
- `Y-Spacing` (`0..32`)
  - width/spacing parameters for non-fit geometry and visual bar segmentation

- `BackgroundDraw` (`0..4`)
  - background fill style in current port:
  - `0`: black
  - `1`: low gray (flash-ish)
  - `2`: dark solid
  - `3`: dark grid
  - `4`: flash grid

- `BarColourStyle` (`0..4`)
  - maps to upstream index selector functions:
  - `0`: `BarColourClassic`
  - `1`: `BarColourFire`
  - `2`: `BarColourLines`
  - `3`: `BarColourWinampFire`
  - `4`: `BarColourElevator`

- `PeakColourStyle` (`0..2`)
  - `0`: `PeakColourFade`
  - `1`: `PeakColourLevel`
  - `2`: `PeakColourLevelFade`

- `Effect` (`0..7`)
  - currently implemented effect behavior in this port:
  - `7` adds a one-pixel dark shadow at right edge of each bar
  - other values are parsed/persisted but not currently rendered as distinct effects

- `Peak Effect` (`0..5`)
  - parsed and persisted for profile compatibility
  - currently no distinct rendering branch in this port

- `ReverseLeft` / `ReverseRight` (`0|1`)
  - channel draw direction flags

- `Mono` (`0|1`)
  - `1`: mono analyzer across full width using both channels
  - `0`: stereo split (left half + right half)

- `Bar Level` (`0|1`)
  - `0`: union (max) level calculation
  - `1`: average level calculation

- `FFTEqualize` (`0|1`)
  - toggles FFT equalization table

- `FFTEnvelope` (`1..1000` stored as integer percentage)
  - applied as envelope power (`value / 100`)
  - controls FFT smoothing/peak sharpness

- `FFTScale` (`1..2000` stored as integer percentage)
  - applied as divisor (`value / 100`)
  - lower value increases bar amplitude (more sensitive)

- `FitToWidth` (`0|1`)
  - when enabled, bars are mapped across full drawable width
  - when disabled, bars use fixed `Bar Width` + `X-Spacing` stepping

- `Message`
  - free-form profile description string

Color sections:
- `[BarColours]` indices `0..255` with `B G R` values
- `[PeakColours]` indices `0..255` with `B G R` values

## 5.4 Known compatibility notes in this port

- `Effect` and `Peak Effect` are not fully feature-complete vs historical plugin behavior; only `Effect == 7` has a dedicated render branch.
- `volumeFunc_` table is initialized with a log curve (`LogBase10Table`) for upstream parity but is not directly used in the current draw path.
- Profile parsing is tolerant: unknown keys are ignored, out-of-range values are clamped.

## 6. Why Profiles Produce Different "Response Curves"

Profiles can differ substantially in dynamics because they change analyzer math, not only colors.

Most influential knobs:
- `FFTScale`: input gain/sensitivity into 0-255 bars
- `Bar Level`: peak/union vs averaged-bin aggregation
- `Falloff`: decay slope
- `PeakChange`: peak hold/release timing
- `Mono`: one unified band set vs split stereo bars
- bar geometry (`Bar Width`, `X-Spacing`, `FitToWidth`) changes perceived responsiveness and density

This is why two profiles can feel like different analyzers even with similar palettes.

## 7. Assigning Profiles to Skins (Future Default vis_classic)

If making `vis_classic` the default and assigning skin-specific profiles:

1. Keep existing window-scoped vis_classic preference model.
2. Add a skin-identity -> profile-name mapping layer above current profile restore.
3. Resolve skin identity deterministically:
   - bundled skin name, or
   - absolute loaded skin path hash for external skins
4. Apply mapping on skin change and at startup before first vis_classic frame render.
5. Fall back in this order:
   - mapped profile if present
   - scoped last-profile key
   - first available profile

Avoid collapsing scope into one global profile key; main and spectrum windows intentionally persist independently.

## 8. Shared Keys Across UIs — Family Switch and Reset Semantics

The window-scoped keys (`visClassicLastProfileName.mainWindow` / `.spectrumWindow`, fit,
transparent, opacity) are scoped by **window**, not by UI family. The classic, modern, and
metal UIs all read and write the **same** keys. This is intentional (§3.2, §7.1) — but it
means the *profile is shared state*, and the correct default depends on which UI is active:

- Classic UI: default analyzer profile is `WindowManager.classicVisClassicProfileName`
  (`"Purple Neon"`), written by `WindowManager.writeClassicVisualizationDefaultKeys(for:)`.
  Classic skins do **not** go through `ModernSkinEngine`.
- Modern/metal UI: default comes from `ModernSkinEngine.currentSkin.config.visualization`
  (a metal finish resolves to its per-finish `"Metal <finish>"` profile).

Two rules follow, and both had leak bugs before 0.29.2:

### 8.1 A UI-family switch is a skin change → apply the incoming skin's defaults

`WindowManager.prepareUIRuntime(for:)` runs on every live UI switch. It must **not** preserve
the outgoing family's shared profile keys:

- Entering modern/metal: `ModernSkinEngine.loadPreferredSkin(for:, preservePersistedProfiles: false)`.
  (Launch / session-restore keeps the default `true` so a user's last-session choices survive;
  a *live* family switch passes `false`.)
- Entering classic: `writeClassicVisualizationDefaultKeys(for: .all)`.

Preserving instead (the old `loadPreferredSkin(for:)` default of `true`) carried classic's
`"Purple Neon"` into a modern skin and vice-versa.

### 8.2 The `VisClassicBridge`s are cached — re-sync them explicitly

`WindowManager` caches `mainWindowVisClassicBridge` and `sharedVisClassicBridge`; they
survive UI switches and load a profile from `UserDefaults` **only at creation**. After a
switch, the one-shot `.visClassicProfileCommand` reload is **dropped** by
`SpectrumAnalyzerView.handleVisClassicProfileCommand` when the target window isn't visible
(guard: `qualityMode == .visClassicExact && window?.isVisible == true`) — which is exactly
the case mid-rebuild. The modern **main** window self-resyncs
(`ModernMainWindowView` reloads `lastProfileName(.mainWindow)` on setup), but the dedicated
**Spectrum** window does not. So `prepareUIRuntime` calls
`resyncCachedVisClassicBridgesToScopedSettings()` to call
`VisClassicBridge.reloadPersistedSettings()` on **both** cached bridges
(visibility-independent). The bridge method rehydrates profile, fit-to-width, and the C++
transparent-background option; loading a profile alone is insufficient because
`transparentbg` is independent core state. When adding any new vis_classic surface, either
give it a self-resync on show, or rely on this central resync — never assume the reload
notification was delivered.

Skin configs are intentionally sparse. On a live skin/UI-family change
(`preservePersistedProfiles: false`), omitted vis_classic appearance fields resolve to
canonical opaque defaults (`transparentBackground = false`, `opacity = 1.0`) so a
glass/metal skin cannot leak transparency into an opaque skin such as NeonWave. On launch
(`preservePersistedProfiles: true`), omitted fields remain untouched so the user's saved
choices survive.

### 8.3 Reset must resolve defaults from the active UI

`VisualizationPreferences.applyCurrentSkinDefaults` branches on
`WindowManager.shared.isRunningModernUI`. In classic UI it must call
`writeClassicVisualizationDefaultKeys`; reading `ModernSkinEngine.currentSkin` there applies
the wrong (modern default skin's) profile. `.mainWindow` / `.spectrumWindow` / `.all` scopes
are all honored.

### 8.4 Standalone Cava window and the `.all` reset

Cava colors fall back to the active skin's gradient (pushed per-UI by `ModernCavaView` /
`CavaView`, so they are inherently UI-mode-correct). The **embedded** main-window Cava keys
(`.mainWindow`) live in `mainWindowKeys`; the **standalone** Cava window keys
(`CavaSettings.preferenceKeys(for: .cavaWindow)`) live in `cavaWindowKeys`, which is included
**only** in `.all`. "Reset All Visualization Preferences" (`reset(.all)`) therefore resets
both, and `postResetNotifications(.all)` calls
`WindowManager.refreshCavaWindowAfterReset()` → the open Cava window's
`refreshAfterReset()` (re-reads tuning via `presenter.settingsDidChange()` and re-derives
skin colors via `skinDidChange()`). A per-window Cava reset is *not* wired into
`.mainWindow` / `.spectrumWindow` — the standalone window is `.all`-only by design.

### 8.5 Cava "custom colors" flag is shared across UIs

`CavaSettings.hasCustomColors(.cavaWindow)` (and `.mainWindow`) is a single shared flag; when
set, `effectiveLowColor/HighColor` ignore the skin default. Entering modern/metal clears it
via `ModernSkinEngine.configureSkinDependencies` (on `!preservePersistedProfiles`), but the
classic branch of `prepareUIRuntime` does **not** reload a skin, so it must call
`CavaSettings.resetCustomColorsForSkinChange()` explicitly — otherwise a modern-picked Cava
gradient survives into classic instead of reverting to the classic default (Winamp green).
Any new UI-family-entry path must clear this flag the same way.
