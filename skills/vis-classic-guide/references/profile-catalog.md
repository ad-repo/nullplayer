# vis_classic Profile Catalog

Generated from bundled profile INI files in `Sources/NullPlayer/Resources/vis_classic/profiles/`.

- Total profiles: **24**
- Source format: `[Classic Analyzer]`, `[BarColours]`, `[PeakColours]`
- Color values in INI are BGR; this catalog displays RGB.

## Option Legend

| Key | Meaning |
|---|---|
| `Falloff` | Per-frame bar decay amount when levels drop (higher = faster fall). |
| `PeakChange` | Peak hold timer before peak marker decays. |
| `Bar Width`, `X-Spacing`, `Y-Spacing` | Bar geometry and spacing controls. |
| `BackgroundDraw` | Background style selector (0..4). |
| `BarColourStyle` | Bar color index function selector (0..4). |
| `PeakColourStyle` | Peak color index function selector (0..2). |
| `Effect` | Effect selector; current port has explicit branch for `7` (fade shadow). |
| `Peak Effect` | Parsed/persisted compatibility field; no dedicated render branch in current port. |
| `ReverseLeft`, `ReverseRight` | Channel drawing direction flags. |
| `Mono` | `1` uses mono combined bands; `0` uses stereo split halves. |
| `Bar Level` | `0` union/max aggregation; `1` average aggregation. |
| `FFTEqualize` | Toggle FFT equalization table. |
| `FFTEnvelope` | FFT envelope power x100. |
| `FFTScale` | FFT output divisor x100 (lower = more sensitive). |
| `FitToWidth` | Whether bars are distributed across full output width. |
| `Message` | Human description embedded in profile. |

## Enum Values

- `BackgroundDraw`: `0`=Black, `1`=Flash-ish low gray, `2`=Dark solid, `3`=Dark grid, `4`=Flash grid
- `BarColourStyle`: `0`=BarColourClassic, `1`=BarColourFire, `2`=BarColourLines, `3`=BarColourWinampFire, `4`=BarColourElevator
- `PeakColourStyle`: `0`=PeakColourFade, `1`=PeakColourLevel, `2`=PeakColourLevelFade

## Profiles

## Aurora Borealis

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Aurora Borealis.ini`
- Description: From flocksoft - an aurora borealis in a dark starry sky.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 8 |
| `PeakChange` | 255 |
| `Bar Width` | 1 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 4 (Flash grid) |
| `BarColourStyle` | 2 (BarColourLines) |
| `PeakColourStyle` | 2 (PeakColourLevelFade) |
| `Effect` | 5 |
| `Peak Effect` | 4 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 180 |
| `FitToWidth` | (not set) |
| `Message` | From flocksoft - an aurora borealis in a dark starry sky. |

### Derived Behavior

- Dynamics: `Falloff=8` -> slow decay / lingering bars.
- Peak behavior: `PeakChange=255` -> long peak hold.
- Sensitivity: `FFTScale=180` -> high sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=1`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=4` (`Flash grid`), `BarColourStyle=2` (`BarColourLines`), `PeakColourStyle=2` (`PeakColourLevelFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#550921` (85, 9, 33) | `#664C17` (102, 76, 23) | `#758C0E` (117, 140, 14) | `#73A309` (115, 163, 9) | `#72BA04` (114, 186, 4) |
| PeakColours | `#400000` (64, 0, 0) | `#6F4040` (111, 64, 64) | `#9F8080` (159, 128, 128) | `#CFC0C0` (207, 192, 192) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 26.9..157.6 |
| `Peak luminance range` | 13.6..255.0 |

## BackAMP StoneAge

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/BackAMP StoneAge.ini`
- Description: Colours inspired by the classic BackAMP StoneAge skin by Fli7e. If only the skin was revised, that'd be so cool! It's still one of my favourite skins... when I first saw it I thought it'd be cool to have a spectrum analyzer that matched the colours, then this plug-in happened.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 14 |
| `PeakChange` | 87 |
| `Bar Width` | 1 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 4 (Flash grid) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 2 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | Colours inspired by the classic BackAMP StoneAge skin by Fli7e. If only the skin was revised, that'd be so cool! It's still one of my favourite skins... when I first saw it I thought it'd be cool to have a spectrum analyzer that matched the colours, then this plug-in happened. |

### Derived Behavior

- Dynamics: `Falloff=14` -> fast decay / snappier drop.
- Peak behavior: `PeakChange=87` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=1`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=4` (`Flash grid`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#B36F5E` (179, 111, 94) | `#E3A756` (227, 167, 86) | `#D1E051` (209, 224, 81) | `#ABCE86` (171, 206, 134) | `#A164FF` (161, 100, 255) |
| PeakColours | `#6A5700` (106, 87, 0) | `#871075` (135, 16, 117) | `#DD9445` (221, 148, 69) | `#F9D8A9` (249, 216, 169) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 124.2..225.5 |
| `Peak luminance range` | 46.5..255.0 |

## Blue Flames

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Blue Flames.ini`
- Description: What if there was a brilliant blue fire and it moved to music?  Maybe it would look something like this.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 60 |
| `Bar Width` | 2 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 0 (Black) |
| `BarColourStyle` | 4 (BarColourElevator) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | What if there was a brilliant blue fire and it moved to music?  Maybe it would look something like this. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=60` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=2`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=0` (`Black`), `BarColourStyle=4` (`BarColourElevator`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#CA006A` (202, 0, 106) | `#A45317` (164, 83, 23) | `#BA9800` (186, 152, 0) | `#E8CB00` (232, 203, 0) | `#C1FF00` (193, 255, 0) |
| PeakColours | `#A6005E` (166, 0, 94) | `#F50070` (245, 0, 112) | `#FF9F21` (255, 159, 33) | `#E6EC00` (230, 236, 0) | `#C1FF00` (193, 255, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 50.6..223.4 |
| `Peak luminance range` | 42.1..223.4 |

## Blue on Dark-Orange

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Blue on Dark-Orange.ini`
- Description: Blue on dark orange?  These colours are horrible.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 2 (Dark solid) |
| `BarColourStyle` | 0 (BarColourClassic) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | Blue on dark orange?  These colours are horrible. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=2` (`Dark solid`), `BarColourStyle=0` (`BarColourClassic`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#CA2332` (202, 35, 50) | `#CF1B54` (207, 27, 84) | `#D41377` (212, 19, 119) | `#D90C9A` (217, 12, 154) | `#DF05BD` (223, 5, 189) |
| PeakColours | `#0984BF` (9, 132, 191) | `#166494` (22, 100, 148) | `#234469` (35, 68, 105) | `#30243E` (48, 36, 62) | `#3E0514` (62, 5, 20) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 64.1..71.6 |
| `Peak luminance range` | 18.0..110.1 |

## Blue on Grey

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Blue on Grey.ini`
- Description: Blue and grey, what did you expect?  Not at all exciting, move along.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 2 (Dark solid) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | Blue and grey, what did you expect?  Not at all exciting, move along. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=2` (`Dark solid`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#CA2332` (202, 35, 50) | `#CF1B54` (207, 27, 84) | `#D41377` (212, 19, 119) | `#D90C9A` (217, 12, 154) | `#DF05BD` (223, 5, 189) |
| PeakColours | `#868E88` (134, 142, 136) | `#736B6A` (115, 107, 106) | `#61494D` (97, 73, 77) | `#4F2630` (79, 38, 48) | `#3E0514` (62, 5, 20) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 64.1..71.6 |
| `Peak luminance range` | 18.2..139.9 |

## ChaNinja

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/ChaNinja.ini`
- Description: Default colour scheme in ChaNinja Style RC5 Windows theme.  If only the rest of Winamp could match this Windows theme... Winamp and Windows themed in harmony.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 2 |
| `BackgroundDraw` | 0 (Black) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 1 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 180 |
| `FitToWidth` | (not set) |
| `Message` | Default colour scheme in ChaNinja Style RC5 Windows theme.  If only the rest of Winamp could match this Windows theme... Winamp and Windows themed in harmony. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=180` -> high sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=2`.
- Style maps: `BackgroundDraw=0` (`Black`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#443537` (68, 53, 55) | `#5F4A4C` (95, 74, 76) | `#7A6062` (122, 96, 98) | `#AB9597` (171, 149, 151) | `#FFFFFF` (255, 255, 255) |
| PeakColours | `#4E3D40` (78, 61, 64) | `#7A6D6F` (122, 109, 111) | `#A69E9F` (166, 158, 159) | `#D3CFCF` (211, 207, 207) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 56.3..255.0 |
| `Peak luminance range` | 64.8..255.0 |

## City Night

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/City Night.ini`
- Description: My favourite Winamp Modern colour theme (and it works with Bento City Night 2 too).

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 2 |
| `BackgroundDraw` | 4 (Flash grid) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 1 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 180 |
| `FitToWidth` | (not set) |
| `Message` | My favourite Winamp Modern colour theme (and it works with Bento City Night 2 too). |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=180` -> high sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=2`.
- Style maps: `BackgroundDraw=4` (`Flash grid`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#453D37` (69, 61, 55) | `#6A635F` (106, 99, 95) | `#8F8987` (143, 137, 135) | `#C7C4C3` (199, 196, 195) | `#FFFFFF` (255, 255, 255) |
| PeakColours | `#545351` (84, 83, 81) | `#567279` (86, 114, 121) | `#5991A1` (89, 145, 161) | `#5CB1C9` (92, 177, 201) | `#5FD0F1` (95, 208, 241) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 62.3..255.0 |
| `Peak luminance range` | 83.1..186.4 |

## Classic

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Classic.ini`
- Description: A spectrum using the classic green, amber, and red colours blended and made to look like wide LEDs.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 2 |
| `BackgroundDraw` | 3 (Dark grid) |
| `BarColourStyle` | 0 (BarColourClassic) |
| `PeakColourStyle` | 1 (PeakColourLevel) |
| `Effect` | 0 |
| `Peak Effect` | 1 |
| `ReverseLeft` | 0 (Off) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | A spectrum using the classic green, amber, and red colours blended and made to look like wide LEDs. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=2`.
- Style maps: `BackgroundDraw=3` (`Dark grid`), `BarColourStyle=0` (`BarColourClassic`), `PeakColourStyle=1` (`PeakColourLevel`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#00BD00` (0, 189, 0) | `#00FD6E` (0, 253, 110) | `#00FFDE` (0, 255, 222) | `#0096FF` (0, 150, 255) | `#0000FF` (0, 0, 255) |
| PeakColours | `#00BD00` (0, 189, 0) | `#00FD6E` (0, 253, 110) | `#00FFDD` (0, 255, 221) | `#0094FF` (0, 148, 255) | `#0000FF` (0, 0, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 18.4..200.8 |
| `Peak luminance range` | 18.4..200.8 |

## Classic LED

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Classic LED.ini`
- Description: A spectrum made from tiny green, amber, and red LEDs (well ok, pixels, but just pretend they're LEDs).

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 100 |
| `Bar Width` | 1 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 2 |
| `BackgroundDraw` | 4 (Flash grid) |
| `BarColourStyle` | 0 (BarColourClassic) |
| `PeakColourStyle` | 1 (PeakColourLevel) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 0 (Off) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 220 |
| `FitToWidth` | (not set) |
| `Message` | A spectrum made from tiny green, amber, and red LEDs (well ok, pixels, but just pretend they're LEDs). |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=100` -> long peak hold.
- Sensitivity: `FFTScale=220` -> lower sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=1`, `X-Spacing=1`, `Y-Spacing=2`.
- Style maps: `BackgroundDraw=4` (`Flash grid`), `BarColourStyle=0` (`BarColourClassic`), `PeakColourStyle=1` (`PeakColourLevel`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#00DBFF` (0, 219, 255) | `#0000FF` (0, 0, 255) |
| PeakColours | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#00DBFF` (0, 219, 255) | `#0000FF` (0, 0, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 18.4..182.4 |
| `Peak luminance range` | 18.4..182.4 |

## Current Settings

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Current Settings.ini`
- Description: No Message field in this profile.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 14 |
| `PeakChange` | 87 |
| `Bar Width` | 1 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 4 (Flash grid) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 2 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | (not set) |

### Derived Behavior

- Dynamics: `Falloff=14` -> fast decay / snappier drop.
- Peak behavior: `PeakChange=87` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=1`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=4` (`Flash grid`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#B36F5E` (179, 111, 94) | `#E3A756` (227, 167, 86) | `#D1E051` (209, 224, 81) | `#ABCE86` (171, 206, 134) | `#A164FF` (161, 100, 255) |
| PeakColours | `#6A5700` (106, 87, 0) | `#871075` (135, 16, 117) | `#DD9445` (221, 148, 69) | `#F9D8A9` (249, 216, 169) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 124.2..225.5 |
| `Peak luminance range` | 46.5..255.0 |

## Default Red & Yellow

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Default Red & Yellow.ini`
- Description: A nice red and yellow blend with the fade shadow effect.  Default? well yeah, way back when I made the plug-in, if there was no profiles saved then you'd get this profile.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 2 |
| `BackgroundDraw` | 0 (Black) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 7 |
| `Peak Effect` | 1 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | A nice red and yellow blend with the fade shadow effect.  Default? well yeah, way back when I made the plug-in, if there was no profiles saved then you'd get this profile. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=2`.
- Style maps: `BackgroundDraw=0` (`Black`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#0000CC` (0, 0, 204) | `#0040D8` (0, 64, 216) | `#0080E5` (0, 128, 229) | `#00C0F2` (0, 192, 242) | `#00FFFF` (0, 255, 255) |
| PeakColours | `#00005C` (0, 0, 92) | `#8080AE` (128, 128, 174) | `#FFFFFF` (255, 255, 255) | `#FFFFFF` (255, 255, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 14.7..200.8 |
| `Peak luminance range` | 6.6..255.0 |

## Flames

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Flames.ini`
- Description: Flames with the peaks shooting up like sparks.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 14 |
| `PeakChange` | 60 |
| `Bar Width` | 2 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 0 (Black) |
| `BarColourStyle` | 3 (BarColourWinampFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 5 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 180 |
| `FitToWidth` | (not set) |
| `Message` | Flames with the peaks shooting up like sparks. |

### Derived Behavior

- Dynamics: `Falloff=14` -> fast decay / snappier drop.
- Peak behavior: `PeakChange=60` -> medium peak hold.
- Sensitivity: `FFTScale=180` -> high sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=2`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=0` (`Black`), `BarColourStyle=3` (`BarColourWinampFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#0044B7` (0, 68, 183) | `#007AEA` (0, 122, 234) | `#00D3FF` (0, 211, 255) | `#00C9FF` (0, 201, 255) | `#0079B9` (0, 121, 185) |
| PeakColours | `#000048` (0, 0, 72) | `#0036A5` (0, 54, 165) | `#006DE8` (0, 109, 232) | `#00C9FF` (0, 201, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 61.8..200.8 |
| `Peak luminance range` | 5.2..255.0 |

## flock darkmateria

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/flock darkmateria.ini`
- Description: By flocksoft - a preset to match the style of the darkmateria skin.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 2 (Dark solid) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 1 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 0 (Union/Max) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 180 |
| `FitToWidth` | (not set) |
| `Message` | By flocksoft - a preset to match the style of the darkmateria skin. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=180` -> high sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Union/max bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=2` (`Dark solid`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#D5D3D1` (213, 211, 209) | `#D5D3D1` (213, 211, 209) | `#D5D3D1` (213, 211, 209) | `#D5D3D1` (213, 211, 209) | `#D5D3D1` (213, 211, 209) |
| PeakColours | `#75716A` (117, 113, 106) | `#75716A` (117, 113, 106) | `#75716A` (117, 113, 106) | `#75716A` (117, 113, 106) | `#75716A` (117, 113, 106) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 211.3..211.3 |
| `Peak luminance range` | 113.3..113.3 |

## Green

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Green.ini`
- Description: If you have one of those old green monitors then you're not missing much when using this profile.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 2 |
| `BackgroundDraw` | 3 (Dark grid) |
| `BarColourStyle` | 0 (BarColourClassic) |
| `PeakColourStyle` | 2 (PeakColourLevelFade) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | If you have one of those old green monitors then you're not missing much when using this profile. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=2`.
- Style maps: `BackgroundDraw=3` (`Dark grid`), `BarColourStyle=0` (`BarColourClassic`), `PeakColourStyle=2` (`PeakColourLevelFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#007D00` (0, 125, 0) | `#009D00` (0, 157, 0) | `#00BE00` (0, 190, 0) | `#00DE00` (0, 222, 0) | `#00FF00` (0, 255, 0) |
| PeakColours | `#004D00` (0, 77, 0) | `#006D00` (0, 109, 0) | `#008E00` (0, 142, 0) | `#00AF00` (0, 175, 0) | `#00D000` (0, 208, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 89.4..182.4 |
| `Peak luminance range` | 55.1..148.8 |

## Lavender Pink Tips

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Lavender Pink Tips.ini`
- Description: Somehow the name of this seems wrong, it looks more like pink with lavender tips, but anyway, interesting colours from "random"

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 2 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 0 (Black) |
| `BarColourStyle` | 3 (BarColourWinampFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | Somehow the name of this seems wrong, it looks more like pink with lavender tips, but anyway, interesting colours from "random" |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=2`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=0` (`Black`), `BarColourStyle=3` (`BarColourWinampFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#BA1BDC` (186, 27, 220) | `#AF7DA1` (175, 125, 161) | `#794B69` (121, 75, 105) | `#7B3CB4` (123, 60, 180) | `#EBAD67` (235, 173, 103) |
| PeakColours | `#09206A` (9, 32, 106) | `#6D3D9B` (109, 61, 155) | `#8A6DAA` (138, 109, 170) | `#50B38B` (80, 179, 139) | `#18F86E` (24, 248, 110) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 39.1..181.1 |
| `Peak luminance range` | 32.5..190.4 |

## LCD

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/LCD.ini`
- Description: A typical LCD display.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 2 (Dark solid) |
| `BarColourStyle` | 0 (BarColourClassic) |
| `PeakColourStyle` | 1 (PeakColourLevel) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | A typical LCD display. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=2` (`Dark solid`), `BarColourStyle=0` (`BarColourClassic`), `PeakColourStyle=1` (`PeakColourLevel`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) |
| PeakColours | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) | `#000000` (0, 0, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 0.0..0.0 |
| `Peak luminance range` | 0.0..0.0 |

## Lightning

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Lightning.ini`
- Description: Inspired by a storm with lightning, deep purple and flashes of bright white.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 14 |
| `PeakChange` | 42 |
| `Bar Width` | 1 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 1 (Flash-ish low gray) |
| `BarColourStyle` | 2 (BarColourLines) |
| `PeakColourStyle` | 1 (PeakColourLevel) |
| `Effect` | 7 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 250 |
| `FitToWidth` | (not set) |
| `Message` | Inspired by a storm with lightning, deep purple and flashes of bright white. |

### Derived Behavior

- Dynamics: `Falloff=14` -> fast decay / snappier drop.
- Peak behavior: `PeakChange=42` -> short peak hold.
- Sensitivity: `FFTScale=250` -> lower sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=1`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=1` (`Flash-ish low gray`), `BarColourStyle=2` (`BarColourLines`), `PeakColourStyle=1` (`PeakColourLevel`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#373737` (55, 55, 55) | `#622F38` (98, 47, 56) | `#6D2E45` (109, 46, 69) | `#FFEAF3` (255, 234, 243) | `#FFFFFF` (255, 255, 255) |
| PeakColours | `#3C3C3C` (60, 60, 60) | `#890852` (137, 8, 82) | `#C678A5` (198, 120, 165) | `#FFFFFF` (255, 255, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 54.3..255.0 |
| `Peak luminance range` | 37.6..255.0 |

## Matches

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Matches.ini`
- Description: By flocksoft - some stylish matches (PS: this profile is optimized to the minimal height of visualization window).

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 4 |
| `PeakChange` | 112 |
| `Bar Width` | 5 |
| `X-Spacing` | 3 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 2 (Dark solid) |
| `BarColourStyle` | 3 (BarColourWinampFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 0 (Union/Max) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 180 |
| `FitToWidth` | (not set) |
| `Message` | By flocksoft - some stylish matches (PS: this profile is optimized to the minimal height of visualization window). |

### Derived Behavior

- Dynamics: `Falloff=4` -> slow decay / lingering bars.
- Peak behavior: `PeakChange=112` -> long peak hold.
- Sensitivity: `FFTScale=180` -> high sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Union/max bins`.
- Geometry: `Bar Width=5`, `X-Spacing=3`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=2` (`Dark solid`), `BarColourStyle=3` (`BarColourWinampFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#FFFFFF` (255, 255, 255) | `#EDFFFF` (237, 255, 255) | `#DCFFFF` (220, 255, 255) | `#CAFFFF` (202, 255, 255) | `#0000B1` (0, 0, 177) |
| PeakColours | `#00003E` (0, 0, 62) | `#00003E` (0, 0, 62) | `#00003E` (0, 0, 62) | `#00003E` (0, 0, 62) | `#00003E` (0, 0, 62) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 12.7..255.0 |
| `Peak luminance range` | 4.5..4.5 |

## Northern Lights

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Northern Lights.ini`
- Description: I was playing around with shades of blue and purple and ended up with this... "northern lights" came to mind.  Yeah, not at all like typical northern lights... fine, go load Aurora Borealis then.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 15 |
| `PeakChange` | 50 |
| `Bar Width` | 1 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 0 (Black) |
| `BarColourStyle` | 2 (BarColourLines) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 190 |
| `FitToWidth` | (not set) |
| `Message` | I was playing around with shades of blue and purple and ended up with this... "northern lights" came to mind.  Yeah, not at all like typical northern lights... fine, go load Aurora Borealis then. |

### Derived Behavior

- Dynamics: `Falloff=15` -> fast decay / snappier drop.
- Peak behavior: `PeakChange=50` -> short peak hold.
- Sensitivity: `FFTScale=190` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=1`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=0` (`Black`), `BarColourStyle=2` (`BarColourLines`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#E36A26` (227, 106, 38) | `#D95D68` (217, 93, 104) | `#DB9686` (219, 150, 134) | `#E3E8AC` (227, 232, 172) | `#FFDBDB` (255, 219, 219) |
| PeakColours | `#910000` (145, 0, 0) | `#FA0000` (250, 0, 0) | `#FF3B9A` (255, 59, 154) | `#FFBBDC` (255, 187, 220) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 103.0..227.1 |
| `Peak luminance range` | 30.8..255.0 |

## poo

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/poo.ini`
- Description: Poo

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 2 (Dark solid) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 0 |
| `Peak Effect` | 3 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | Poo |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=2` (`Dark solid`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) |
| PeakColours | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) | `#226897` (34, 104, 151) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 0.0..92.5 |
| `Peak luminance range` | 92.5..92.5 |

## Purple Neon

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Purple Neon.ini`
- Description: Soothing purple and blue that looks like it is glowing, you know, like a neon sign.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 13 |
| `PeakChange` | 87 |
| `Bar Width` | 2 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 3 (Dark grid) |
| `BarColourStyle` | 4 (BarColourElevator) |
| `PeakColourStyle` | 2 (PeakColourLevelFade) |
| `Effect` | 5 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | Soothing purple and blue that looks like it is glowing, you know, like a neon sign. |

### Derived Behavior

- Dynamics: `Falloff=13` -> fast decay / snappier drop.
- Peak behavior: `PeakChange=87` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=2`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=3` (`Dark grid`), `BarColourStyle=4` (`BarColourElevator`), `PeakColourStyle=2` (`PeakColourLevelFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#D74861` (215, 72, 97) | `#D46B4C` (212, 107, 76) | `#D28E38` (210, 142, 56) | `#D0B224` (208, 178, 36) | `#CFD511` (207, 213, 17) |
| PeakColours | `#6A0026` (106, 0, 38) | `#FF5F8C` (255, 95, 140) | `#F99172` (249, 145, 114) | `#F3C459` (243, 196, 89) | `#EEF641` (238, 246, 65) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 103.9..197.6 |
| `Peak luminance range` | 25.3..231.2 |

## Rainbow

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Rainbow.ini`
- Description: Perhaps you like all the colours in a rainbow.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 80 |
| `Bar Width` | 3 |
| `X-Spacing` | 1 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 0 (Black) |
| `BarColourStyle` | 0 (BarColourClassic) |
| `PeakColourStyle` | 1 (PeakColourLevel) |
| `Effect` | 0 |
| `Peak Effect` | 0 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 1 (On) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | Perhaps you like all the colours in a rainbow. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=80` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Mono combined channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=3`, `X-Spacing=1`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=0` (`Black`), `BarColourStyle=0` (`BarColourClassic`), `PeakColourStyle=1` (`PeakColourLevel`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#FF00FF` (255, 0, 255) | `#FF4100` (255, 65, 0) | `#7DFF00` (125, 255, 0) | `#00FFC3` (0, 255, 195) | `#0000FF` (0, 0, 255) |
| PeakColours | `#FF0000` (255, 0, 0) | `#FFFF00` (255, 255, 0) | `#00FF00` (0, 255, 0) | `#00FFFF` (0, 255, 255) | `#0000FF` (0, 0, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 18.4..236.6 |
| `Peak luminance range` | 18.4..236.6 |

## Trippy

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Trippy.ini`
- Description: I hit random for the colours and this is what happened.  It's like watching The Electric Company on acid.

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 12 |
| `PeakChange` | 50 |
| `Bar Width` | 1 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 4 (Flash grid) |
| `BarColourStyle` | 4 (BarColourElevator) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 1 |
| `Peak Effect` | 1 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 170 |
| `FitToWidth` | (not set) |
| `Message` | I hit random for the colours and this is what happened.  It's like watching The Electric Company on acid. |

### Derived Behavior

- Dynamics: `Falloff=12` -> moderate decay.
- Peak behavior: `PeakChange=50` -> short peak hold.
- Sensitivity: `FFTScale=170` -> high sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=1`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=4` (`Flash grid`), `BarColourStyle=4` (`BarColourElevator`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#A3A389` (163, 163, 137) | `#5BB94A` (91, 185, 74) | `#79E2B6` (121, 226, 182) | `#76499D` (118, 73, 157) | `#D800E2` (216, 0, 226) |
| PeakColours | `#D44C17` (212, 76, 23) | `#D6898D` (214, 137, 141) | `#9C6832` (156, 104, 50) | `#30C3B0` (48, 195, 176) | `#E54E19` (229, 78, 25) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 62.2..205.6 |
| `Peak luminance range` | 64.9..210.4 |

## Twilight

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Twilight.ini`
- Description: From Leandro Ariza - inspired on a scenario of The Legend of Zelda: Twilight Princess, "The Twilight Realm".

### Technical Settings

| Key | Value |
|---|---|
| `Falloff` | 10 |
| `PeakChange` | 60 |
| `Bar Width` | 2 |
| `X-Spacing` | 0 |
| `Y-Spacing` | 1 |
| `BackgroundDraw` | 4 (Flash grid) |
| `BarColourStyle` | 1 (BarColourFire) |
| `PeakColourStyle` | 0 (PeakColourFade) |
| `Effect` | 1 |
| `Peak Effect` | 5 |
| `ReverseLeft` | 1 (On) |
| `ReverseRight` | 0 (Off) |
| `Mono` | 0 (Off) |
| `Bar Level` | 1 (Average) |
| `FFTEqualize` | 1 (On) |
| `FFTEnvelope` | 20 |
| `FFTScale` | 200 |
| `FitToWidth` | (not set) |
| `Message` | From Leandro Ariza - inspired on a scenario of The Legend of Zelda: Twilight Princess, "The Twilight Realm". |

### Derived Behavior

- Dynamics: `Falloff=10` -> moderate decay.
- Peak behavior: `PeakChange=60` -> medium peak hold.
- Sensitivity: `FFTScale=200` -> balanced sensitivity (lower values are more reactive).
- Channel layout: `Stereo split channels`; level aggregation uses `Average bins`.
- Geometry: `Bar Width=2`, `X-Spacing=0`, `Y-Spacing=1`.
- Style maps: `BackgroundDraw=4` (`Flash grid`), `BarColourStyle=1` (`BarColourFire`), `PeakColourStyle=0` (`PeakColourFade`).

### Palette Snapshot

| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |
|---|---|---|---|---|---|
| BarColours | `#C3FCFC` (195, 252, 252) | `#BFF3FD` (191, 243, 253) | `#8EA1DB` (142, 161, 219) | `#44396B` (68, 57, 107) | `#2F1A40` (47, 26, 64) |
| PeakColours | `#2F1A40` (47, 26, 64) | `#2F1A40` (47, 26, 64) | `#2F1A40` (47, 26, 64) | `#2F1A40` (47, 26, 64) | `#2F1A40` (47, 26, 64) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 33.2..239.9 |
| `Peak luminance range` | 33.2..33.2 |
