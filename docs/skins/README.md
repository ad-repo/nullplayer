# Skins Visualization Defaults

This document defines how visualization defaults are configured per skin and what is applied automatically for classic `.wsz` skins.

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
      "spectrumWindowFitToWidth": true
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
  }
}
```

### Supported keys

- `mainWindowMode`: `MainWindowVisMode.rawValue`
- `spectrumWindowMode`: `SpectrumQualityMode.rawValue`
- `visClassic`:
  - `mainWindowProfile`, `spectrumWindowProfile`
  - `mainWindowFitToWidth`, `spectrumWindowFitToWidth`
- `fire`:
  - `mainWindowStyle`, `mainWindowIntensity`
  - `spectrumWindowStyle`, `spectrumWindowIntensity`
- `lightning`:
  - `mainWindowStyle`, `spectrumWindowStyle`
- `matrix`:
  - `mainWindowColorScheme`, `mainWindowIntensity`
  - `spectrumWindowColorScheme`, `spectrumWindowIntensity`

## Notes

- Mode selection is not limited to `vis_classic`; any valid mode raw value is accepted.
- Only modes that have preset/profile families are represented (`visClassic`, `fire`, `lightning`, `matrix`).
- Invalid mode/preset strings are ignored safely at runtime and logged.
- If a mode requires a missing shader, the requested mode is ignored.

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
