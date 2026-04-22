# Skins Visualization Defaults

This document defines how visualization defaults are configured per skin and what is applied automatically for classic `.wsz` skins.
For modern skin portability, use `.nsz` ZIP bundles (import via **Skins > Modern > Load Skin...**).

## `skin.json` `visualization` block (modern skins)

Modern skins can define a top-level `visualization` object in `skin.json`.

```json
{
  "visualization": {
    "mainWindowMode": "vis_classic",
    "spectrumWindowMode": "vis_classic",
    "visClassic": {
      "mainWindowProfile": "Purple Neon",
      "spectrumWindowProfile": "Purple Neon",
      "mainWindowFitToWidth": true,
      "spectrumWindowFitToWidth": true,
      "mainWindowTransparentBackground": false,
      "spectrumWindowTransparentBackground": false,
      "mainWindowOpacity": 1.0,
      "spectrumWindowOpacity": 1.0
    },
    "fire": {
      "mainWindowStyle": "Inferno",
      "mainWindowIntensity": "Mellow",
      "spectrumWindowStyle": "Inferno",
      "spectrumWindowIntensity": "Mellow"
    },
    "lightning": {
      "mainWindowStyle": "Classic",
      "spectrumWindowStyle": "Classic"
    },
    "matrix": {
      "mainWindowColorScheme": "Classic",
      "mainWindowIntensity": "Subtle",
      "spectrumWindowColorScheme": "Classic",
      "spectrumWindowIntensity": "Subtle"
    }
  },
  "waveform": {
    "transparentBackgroundStyle": "glass"
  },
  "window": {
    "opacity": 0.54,
    "areaOpacity": {
      "waveformArea": {
        "background": 0.8,
        "border": 0.8,
        "content": 0.85
      }
    }
  }
}
```

### Supported keys

- `mainWindowMode`: `MainWindowVisMode.rawValue`
- `spectrumWindowMode`: `SpectrumQualityMode.rawValue`
  - Includes `Punch` (raw value: `"Punch"`) for the Metal peak-focused spectrum mode.
- `visClassic`:
  - `mainWindowProfile`, `spectrumWindowProfile`
  - `mainWindowFitToWidth`, `spectrumWindowFitToWidth`
  - `mainWindowTransparentBackground`, `spectrumWindowTransparentBackground`
  - `mainWindowOpacity`, `spectrumWindowOpacity` (`0.0`-`1.0`, only applied when transparent background is enabled)
- `fire`:
  - `mainWindowStyle`, `mainWindowIntensity`
  - `spectrumWindowStyle`, `spectrumWindowIntensity`
- `lightning`:
  - `mainWindowStyle`, `spectrumWindowStyle`
- `matrix`:
  - `mainWindowColorScheme`, `mainWindowIntensity`
  - `spectrumWindowColorScheme`, `spectrumWindowIntensity`
- `waveform`:
  - `transparentBackgroundStyle`: `"glass"` or `"clear"` for the waveform window when the shared `Transparent Background` toggle is on. Defaults to `"glass"` if omitted.
- `window.areaOpacity.waveformArea`:
  - `background`, `border`, `content`
  - Follows the same multiplier semantics as the other `areaOpacity` sections.
  - `background` controls the translucent waveform fill in `"glass"` mode.
  - `content` controls waveform lines, cue markers, playhead, and text when transparency is enabled.
  - `border` is parsed for schema consistency but is not rendered separately in v1.

## Notes

- Mode selection is not limited to `vis_classic`; any valid mode raw value is accepted.
- Only modes that have preset/profile families are represented (`visClassic`, `fire`, `lightning`, `matrix`).
- `Punch` has no extra style block in `skin.json`; configure it by setting
  `mainWindowMode` and/or `spectrumWindowMode` to `"Punch"`.
- `Punch` renders bars only (no separate peak marker line), with dominant-frequency focus
  and fast response tuned for transient-heavy material.
- Invalid mode/preset strings are ignored safely at runtime and logged.
- If a mode requires a missing shader, the requested mode is ignored.
- The waveform window has one shared `Transparent Background` toggle across classic and modern UI.
- Its default is auto-enabled only for bundled glass skins: `SmoothGlass`, `SeaGlass`, and `BloodGlass`.
- Imported/custom modern skins default this toggle off unless the user enables it.

## Classic skins (`.wsz`) behavior

When a classic skin is loaded, NullPlayer now forces these defaults:

- `mainWindowVisMode = "vis_classic"`
- `spectrumQualityMode = "vis_classic"`
- `visClassicLastProfileName.mainWindow = "Purple Neon"`
- `visClassicLastProfileName.spectrumWindow = "Purple Neon"`
- `visClassicFitToWidth.mainWindow = true`
- `visClassicFitToWidth.spectrumWindow = true`

Runtime notifications and vis_classic commands are posted so open windows update immediately.

## Bundled modern skin profile mapping (palette matched)

- `ArcticMinimal` -> `City Night`
- `BananaParty` -> `Blue Flames`
- `BloodGlass` -> `Northern Lights`
- `BubblegumRetro` -> `Northern Lights`
- `EmeraldForgePlatinum` -> `Trippy`
- `ForgedTitanium` -> `flock darkmateria`
- `HyperPopPrism` -> `Trippy`
- `IndustrialSignal` -> `Northern Lights`
- `NeonWave` -> `Lavender Pink Tips`
- `SakuraMinimal` -> `Northern Lights`
- `SeaGlass` -> `flock darkmateria`
- `Skulls` -> `BackAMP StoneAge`
- `SmoothGlass` -> `Matches`
