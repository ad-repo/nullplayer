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

`SpectrumAnalyzerView` subscribes to `.audioWaveform576DataUpdated` and queues each chunk in a
`WinampModernWaveformTap` (`receive` / `samples(at:)` only; the view registers the consumer itself),
which plays them out at the audio's own rate — every surface that feeds vis_classic does the same.

**Never feed vis_classic the newest chunk.** The mixer tap delivers 4410 frames (100 ms) at 44.1 kHz —
not the 2048 it requests; `WINAMP_MODERN_VIS_GAPS=1` logs the real sizes — and `AudioEngine` posts all
7–8 chunks of a buffer at once. Keeping only the newest showed one 13 ms slice per 100 ms, so bars
spiked on whatever that slice caught and missed the beats between: "huge spikes that don't make
musical sense", in every profile. The queue's cap (`maximumQueuedChunks`) must hold one whole buffer.

When `qualityMode == .visClassicExact`, render loop behavior differs from GPU spectrum modes:
- skips generic spectrum decay/idle transform path
- uses vis_classic waveform-driven frames
- calls `renderVisClassicExact(drawable:)`

**Input gain.** `VisClassicBridge.processAndDraw` scales every surface's waveform about 128 by
`WinampModernVisSensitivity.gain(for: .visClassic)` — the calibration `WasabiVisStyle.Gain.visClassicInput`
(1.6) times the user's **Sensitivity** (key `winampModern.visSensitivity.visClassic`, one setting for
every vis_classic surface). The core maps magnitude linearly and most profiles halve it
(`FFTScale=200`), so ungained music sat near the floor: on `music`'s Hackbeat the mean bar was 24 of
255, 41 at Normal, 61 at Highest. Gain belongs on the input, never on the bar heights, which would
stretch the profile's artwork. Every vis_classic options menu offers the Sensitivity submenu
(`WinampModernVisSensitivityMenu`).

`renderVisClassicExact(drawable:)` pipeline:
1. Lazily create `VisClassicBridge` (scoped by embedded/main-window vs spectrum-window).
2. `bridge.processAndDraw(...)`: send the latest waveform, advance one frame, and CPU-render BGRA
   bytes, under one lock. A `.wal` skin with several vis boxes draws the rest with `drawAtSize`.
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

Because a user copy shadows the bundled profile of the same name, a bundled profile whose *file*
changes leaves stale copies behind. `migrateUserCopiesToRGBProfiles()` (once, flag
`visClassicProfilesRGBMigrationV1`) replaces a user copy that is exactly the channel-swapped old
version of a bundled profile — the Metal profiles when the channel order was fixed (§5.3). Anything
else in the user folder is left alone.

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

Once-per-skin auto-match keys (§7) — the `.wal` / `.wmz` archive path the scope's profile was last
matched for:
- `visClassicSkinDefaultAppliedFor.spectrumWindow`
- `visClassicSkinDefaultAppliedFor.winampModernVisBox`
- `visClassicSkinDefaultAppliedFor.wmpEffects`
- (`visClassicSkinDefaultAppliedFor.mainWindow` exists for symmetry; the main-window bridge never
  renders under `.wal` / `.wmz`, so nothing writes it)

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

All four menus build their vis_classic block with `VisClassicMenu.addItems` (`Visualization/VisClassicMenu.swift`),
each passing its own target and selectors: Profiles / Next / Previous, then Sensitivity / Fit to Width /
Transparent Background, then Import / Export INI. None offers Responsiveness or Normalization in
vis_classic mode — the core ignores both. Add a vis_classic menu item there, never in one host.

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
- `vc_process_frame_only` (advances all per-frame state), `vc_draw_at_size` (pure: draws that state
  into one box; a `.wal` skin calls it once per vis box)
- `vc_set_fixed_dt_ms` (test-only: pins the frame interval; `0` = wall clock)
- `vc_set_option`, `vc_get_option`
- `vc_load_profile_ini`, `vc_save_profile_ini`
- `vc_get_last_error`

## 5.2 Per-frame processing

1. Convert incoming uint8 waveform to signed float centered at 0.
2. FFT using upstream `FFT` implementation. Its size is the plugin's `CalculateFFTVariables`: 512
   bins, doubled until `FFT >= 2 * bars per channel` (576 mono bars → 2048). A fixed 512 starved the
   last bars of a wide analyzer and made the mapping linear (#682).
3. Scale FFT bins by `FFTScale` (divide; lower scale => more sensitive).
4. Build logarithmic bar-bin allocation using `LogBarValueTable`: one table in mono; in stereo one
   per channel, each covering the whole spectrum. The last bar takes everything above 16 kHz, and
   the lowest bars one bin each.
5. Compute bar levels per band with `Bar Level` aggregation mode, and the frame's volume
   (`VolumeFunction` averaged over the bars).
6. Apply falloff (scaled by elapsed time), then the plugin-frame steps — peaks (§5.3 `Peak Effect`)
   and the Effect's ghosts — once per elapsed 33 ms tick.
7. `vc_draw_at_size`: background, then the Effect's bars and ghosts, then peaks, into a BGRA buffer.

## 5.3 Analyzer options and exact meanings

All loaded from `[Classic Analyzer]` INI section:

- `Falloff` (`0..75`, the plugin's range)
  - per-frame decay amount for dropping bars
  - higher = faster fall

- `PeakChange` (`0..255`)
  - how many frames a peak holds before its Peak Effect moves it
  - `0` disables peaks

- `Bar Width` (`1..64`)
- `X-Spacing` (`0..32`)
- `Y-Spacing` (`1..7`, the plugin's range; a stored `0` loads as `1`)
  - `Bar Width` / `X-Spacing`: width/spacing parameters for non-fit geometry
  - `Y-Spacing`: only every Nth row is drawn, counted from the bottom (`1` = no gaps); peaks snap
    down to that grid

- `BackgroundDraw` (`0..4`), ported from the plugin (`VisClassicEffects.cpp`); none is drawn when
  the transparent background is on (§4.3)
  - `0`: black
  - `1`: Flash — the whole box in `VolumeColours[volume]`, `volume` being the frame's average of
    `VolumeFunction[level]` over the bars
  - `2`: Solid — `VolumeColours[0]`
  - `3`: Grid — each Y-spaced row, in the bar columns only, in `BarColours[row height] / 3`
  - `4`: Flash Grid — the same grid in `VolumeColours[row height]` (static, not volume-driven)

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

- `Effect` (`0..7`), ported from the plugin's `Render*Bars*` (`VisClassicEffects.cpp`). Ghost
  colours blend the bar colour with the background colour `VolumeColours[0]`:
  - `0` None
  - `1` Mirror: bars grow up and down from the middle
  - `2` Reflection: bars stand on a line one third up; a half-height copy at /1.75 brightness hangs below
  - `3` Shadow: a ghost of the bar's high-water mark, dropping 1 level a frame, in (bar + bg) / 2
  - `4` Double Shadow: two ghosts, dropping 2 and 1 levels a frame
  - `5` Smoke: a ghost per column (`Bar Width` columns per bar, as equal slices of the drawn bar so
    every box size matches) drifting right one column a frame, decaying by a random 0–3
  - `6` Reflection Waves: Reflection whose reflected rows wobble sideways; louder music, bigger waves
  - `7` Fade Shadow: the ghost holds 24 frames, fading toward the background every 4, then re-takes the bar
  - Grid and Flash Grid follow the Mirror and Reflection layouts (Reflection Waves draws them only
    with `X-Spacing=0`, as the plugin does)
  - ghosts advance in `vc_process_frame_only`, one step per 33 ms tick, and reset whenever the
    geometry or the Effect changes; drawing only reads them, so several boxes share one core

- `Peak Effect` (`0..5`), ported from the plugin (`VisClassicPeaks.cpp`). A peak's whole life is a
  table built from the effect and `PeakChange`: set at a bar's level, it counts down through
  `level[ref][t]`, drawn in `PeakColours[colour[ref][t]]` so its colour fades over its life. It
  restarts from the bar when its life ends or the bar reaches it. Moving peaks travel 5 levels a frame.
  - `0` Normal: hold, then snap back to the bar
  - `1` Fall: hold, then fall (`PeakFallOffMode=1`: slow then fast, log-shaped)
  - `2` Rise: hold, then rise to the top
  - `3` FallAndRise: odd levels fall, even levels rise
  - `4` RiseFall: drift up ~25 levels while holding, then fall
  - `5` Sparks: hold a random time, then shoot up at a random speed (seeded generator)
  - peak steps, like every plugin-frame step, run in whole 33 ms ticks of elapsed time

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
- `[BarColours]` indices `0..255` with `R G B` values
- `[PeakColours]` indices `0..255` with `R G B` values
- `[VolumeColours]` indices `0..255` with `R G B` values (backgrounds `1`, `2`, `4`)
- `[VolumeFunction]` indices `0..255`, integers; default `256 - 256 / (i + 1)` (the plugin's 1/x)

**Channel order is `R G B` as drawn.** The original plugin (`WACUP/vis_classic`, `File.cpp`) reads the
three numbers into variables named `r g b` and stores `RGB(b, g, r)` into a COLORREF — but that
COLORREF goes straight into a 32-bit DIB, whose byte order undoes the swap; its built-in default,
`bmpRGB(204 + i/5, i, 0)`, is the red→yellow of "Default Red & Yellow". The port first took the
variable names at face value (`parseBGR`) and drew every bundled profile with red and blue exchanged
("Flames" blue); `parseRGB` and the saver now use `R G B`. The seven `Metal *` profiles had been
authored by eye against the swap and were rewritten so they still draw as authored.

## 5.4 Known compatibility notes in this port

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

## 7. Default Profile per Skin Family

| Family | Default profile | Where |
|---|---|---|
| Classic | always `"Purple Neon"` | `WindowManager.classicVisClassicProfileName` / `writeClassicVisualizationDefaultKeys` |
| Original (modern / metal) | per skin, hand-picked | `skin.json` → `visualization.visClassic.mainWindowProfile` / `spectrumWindowProfile` |
| Winamp Modern (`.wal`) | the bundled profile nearest the skin's colours | `VisClassicProfileMatcher` |
| WMP (`.wmz`) | the bundled profile nearest the skin's colours | `VisClassicProfileMatcher` |

### 7.1 The matcher

`Visualization/VisClassicProfileMatcher.swift`, pure and tested (`HostedVisSkinColorsTests`):
- **Candidates**: bundled profiles only (never the user folder), minus `Current Settings` and any
  profile whose bars are near-black (LCD draws only peaks). Parsed once per session.
- **Summary**: `low` = mean of `[BarColours]` 32–127, `high` = mean of 128–255, in Lab.
- **Score**: `ΔE(low) + 2·ΔE(high)`, ΔE with lightness at half weight (`kL = 2`); ties by name. At full
  lightness weight a mid-brown profile beat every red and pink one. A bundled `Red` profile (Green's
  ramp in red) exists because nothing else was red.
- **Targets**: the Spectrum window and `<EFFECTS>` use the hosted surface style (`visualizationLow` /
  `visualizationHigh` = dim text → current text). The `.wal` `<vis>` box uses its own `colorband`
  first → last, and falls back to the surface style when those are shading, not bar colour
  (`isDegenerateTarget`: both near-black, like Rika's `colorallbands="0,0,0"`, or both near-white,
  the undeclared default).

### 7.2 Once per skin

`applySkinDefault(for:skinIdentity:…)` writes the match to `scope.lastProfileNameKey` only when the
skin identity (the archive path, `WindowManager.hostedSkinIdentity`) differs from
`scope.skinDefaultAppliedForKey`, so a user's pick survives a same-skin relaunch and a new skin
re-picks — Original's `ModernSkinLoadReason.keepsSavedProfiles`, keyed on identity. A `.wal` colour-theme switch
keeps the identity and does not re-pick. Hooks, and how each reaches a live bridge:
- `.spectrumWindow`: `WindowManager.applyHostedVisClassicSkinDefault` on
  `.hostedSurfaceStyleDidChange`; reloads `sharedVisClassicBridge` and posts
  `.visClassicProfileCommand` `load` / `spectrumWindow` for a visible window.
- `.wmpEffects`: `SkinEffectsSurfaceView` before its bridge is built and on the style notification;
  loads its own bridge directly (nothing listens to the notification for this target).
- `.winampModernVisBox`: `VisClassicVisRenderer.draw`, gated on a per-renderer last-seen identity;
  loads its own bridge when the stored name differs (several boxes, one scope).
- `.mainWindow`: not hooked — no embedded analyzer exists under `.wal` / `.wmz`.

**Instrument**: a DEBUG build logs every match —
`VisClassicProfileMatcher: <lastProfileNameKey> -> "<name>" (score <n>) for <archive path>` — in the
app log (`/tmp/np.log` under `launch.sh`). No log line on a relaunch is the once-per-skin rule
working, not a missing hook.

Avoid collapsing scope into one global profile key; main and spectrum windows intentionally persist independently.

## 8. Shared Keys Across UIs — Family Switch and Reset Semantics

The window-scoped keys (`visClassicLastProfileName.mainWindow` / `.spectrumWindow`, fit,
transparent, opacity) are scoped by **window**, not by UI family. The classic, modern, and
metal UIs all read and write the **same** keys. This is intentional (§3.2, §7.1) — but it
means the *profile is shared state*, and the correct default depends on which UI is active:

- Classic UI: default analyzer profile is `WindowManager.classicVisClassicProfileName`
  (`"Purple Neon"`), written by `WindowManager.writeClassicVisualizationDefaultKeys(for:)`.
  Classic skins do **not** go through `ModernSkinEngine`.
- Modern/metal UI: the embedded main-window visualizer defaults to Cava through
  `ModernSkinEngine.currentSkin.config.visualization.mainWindowMode`. The dedicated Spectrum
  window remains `vis_classic`; its default profile comes from the active skin (a metal finish
  resolves to its per-finish `"Metal <finish>"` profile). Modern/metal skins also retain their
  main-window vis_classic profile mapping for users who select that mode manually.

Three rules follow, and all had leak bugs before 0.29.2:

### 8.1 A UI-family switch is a skin change → apply the incoming skin's defaults

`WindowManager.prepareUIRuntime(for:)` runs on every live UI switch. It must **not** preserve
the outgoing family's shared profile keys:

- Entering modern/metal: `ModernSkinEngine.loadPreferredSkin(for:, reason: .familyEntry)`.
  (Launch / session-restore keeps the default `.launch` so a user's last-session choices survive;
  a *live* family switch replaces the profile keys but keeps Original's own main-window mode,
  and a skin pick or reset, `.skinChange`, replaces both.)
- Entering classic: `writeClassicVisualizationDefaultKeys(for: .all)`.
- Entering `.wal` / `.wmz`: `VisClassicProfileMatcher.forgetAppliedSkin(for: [.spectrumWindow])`, so
  the shared Spectrum key (still holding Classic's or Original's profile) is re-matched once the
  skin's style resolves.

`seedClassicVisualizationDefaults` runs at every launch in every mode, because the classic skin is
loaded regardless, and is gated by `appliesClassicVisualizationDefaults(family:)`, true for `.classic`
only. It used to admit `.wal` (which answers false to `isRunningModernUI` and `isRunningWMPUI` alike),
so every `.wal` launch reset the Spectrum window to vis_classic / "Purple Neon". It writes only keys
never saved before (`onlyIfUnset: true`) — a fresh install's fallbacks are Classic mode and the first
profile alphabetically — and a Classic skin pick writes nothing: Classic skins carry no visualization
settings, so rewriting them on a load only discarded the user's choice.

Preserving instead (the old `loadPreferredSkin(for:)` default of `true`) carried classic's
`vis_classic` mode and `"Purple Neon"` profile into a modern skin instead of applying Cava and
the incoming skin's retained vis_classic profile defaults.

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
(`reason` `.familyEntry` or `.skinChange`), omitted vis_classic appearance fields resolve to
canonical opaque defaults (`transparentBackground = false`, `opacity = 1.0`) so a
glass/metal skin cannot leak transparency into an opaque skin such as NeonWave. On launch
(`.launch`), omitted fields remain untouched so the user's saved
choices survive.

### 8.3 Reset must resolve defaults from the active UI

`VisualizationPreferences.applyCurrentSkinDefaults` switches on
`WindowManager.shared.runningControllerFamily`. Classic calls `writeClassicVisualizationDefaultKeys`;
reading `ModernSkinEngine.currentSkin` there applies the wrong (modern default skin's) profile.
`.wal` / `.wmz` write the same mode and fit keys, then forget the Spectrum scope's skin identity and
re-run the matcher, so a reset returns the skin's match rather than "Purple Neon". `.mainWindow` / `.spectrumWindow` / `.all` scopes
are all honored.
