# vis_classic Profile Catalog

Generated from bundled profile INI files in `Sources/NullPlayer/Resources/vis_classic/profiles/`.

- Total profiles: **32**
- Source format: `[Classic Analyzer]`, `[BarColours]`, `[PeakColours]`
- Color values in INI are R G B as drawn (the original plugin's `RGB(b, g, r)` naming is undone by its DIB byte order).

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
| BarColours | `#210955` (33, 9, 85) | `#174C66` (23, 76, 102) | `#0E8C75` (14, 140, 117) | `#09A373` (9, 163, 115) | `#04BA72` (4, 186, 114) |
| PeakColours | `#000040` (0, 0, 64) | `#40406F` (64, 64, 111) | `#80809F` (128, 128, 159) | `#C0C0CF` (192, 192, 207) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 19.6..142.1 |
| `Peak luminance range` | 4.6..255.0 |

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
| BarColours | `#5E6FB3` (94, 111, 179) | `#56A7E3` (86, 167, 227) | `#51E0D1` (81, 224, 209) | `#86CEAB` (134, 206, 171) | `#FF64A1` (255, 100, 161) |
| PeakColours | `#00576A` (0, 87, 106) | `#751087` (117, 16, 135) | `#4594DD` (69, 148, 221) | `#A9D8F9` (169, 216, 249) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 112.1..211.9 |
| `Peak luminance range` | 44.2..255.0 |

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
| BarColours | `#6A00CA` (106, 0, 202) | `#1753A4` (23, 83, 164) | `#0098BA` (0, 152, 186) | `#00CBE8` (0, 203, 232) | `#00FFC1` (0, 255, 193) |
| PeakColours | `#5E00A6` (94, 0, 166) | `#7000F5` (112, 0, 245) | `#219FFF` (33, 159, 255) | `#00ECE6` (0, 236, 230) | `#00FFC1` (0, 255, 193) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 37.1..196.3 |
| `Peak luminance range` | 32.0..196.3 |

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
| BarColours | `#3223CA` (50, 35, 202) | `#541BCF` (84, 27, 207) | `#7713D4` (119, 19, 212) | `#9A0CD9` (154, 12, 217) | `#BD05DF` (189, 5, 223) |
| PeakColours | `#BF8409` (191, 132, 9) | `#946416` (148, 100, 22) | `#694423` (105, 68, 35) | `#3E2430` (62, 36, 48) | `#14053E` (20, 5, 62) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 49.5..59.9 |
| `Peak luminance range` | 12.2..135.7 |

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
| BarColours | `#3223CA` (50, 35, 202) | `#541BCF` (84, 27, 207) | `#7713D4` (119, 19, 212) | `#9A0CD9` (154, 12, 217) | `#BD05DF` (189, 5, 223) |
| PeakColours | `#888E86` (136, 142, 134) | `#6A6B73` (106, 107, 115) | `#4D4961` (77, 73, 97) | `#30264F` (48, 38, 79) | `#14053E` (20, 5, 62) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 49.5..59.9 |
| `Peak luminance range` | 12.3..140.1 |

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
| BarColours | `#373544` (55, 53, 68) | `#4C4A5F` (76, 74, 95) | `#62607A` (98, 96, 122) | `#9795AB` (151, 149, 171) | `#FFFFFF` (255, 255, 255) |
| PeakColours | `#403D4E` (64, 61, 78) | `#6F6D7A` (111, 109, 122) | `#9F9EA6` (159, 158, 166) | `#CFCFD3` (207, 207, 211) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 54.5..255.0 |
| `Peak luminance range` | 62.9..255.0 |

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
| BarColours | `#373D45` (55, 61, 69) | `#5F636A` (95, 99, 106) | `#87898F` (135, 137, 143) | `#C3C4C7` (195, 196, 199) | `#FFFFFF` (255, 255, 255) |
| PeakColours | `#515354` (81, 83, 84) | `#797256` (121, 114, 86) | `#A19159` (161, 145, 89) | `#C9B15C` (201, 177, 92) | `#F1D05F` (241, 208, 95) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 60.3..255.0 |
| `Peak luminance range` | 82.6..206.9 |

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
| BarColours | `#00BD00` (0, 189, 0) | `#6EFD00` (110, 253, 0) | `#DEFF00` (222, 255, 0) | `#FF9600` (255, 150, 0) | `#FF0000` (255, 0, 0) |
| PeakColours | `#00BD00` (0, 189, 0) | `#6EFD00` (110, 253, 0) | `#DDFF00` (221, 255, 0) | `#FF9400` (255, 148, 0) | `#FF0000` (255, 0, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 54.2..236.6 |
| `Peak luminance range` | 54.2..236.6 |

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
| BarColours | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#FFDB00` (255, 219, 0) | `#FF0000` (255, 0, 0) |
| PeakColours | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#00FF00` (0, 255, 0) | `#FFDB00` (255, 219, 0) | `#FF0000` (255, 0, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 54.2..210.8 |
| `Peak luminance range` | 54.2..210.8 |

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
| BarColours | `#5E6FB3` (94, 111, 179) | `#56A7E3` (86, 167, 227) | `#51E0D1` (81, 224, 209) | `#86CEAB` (134, 206, 171) | `#FF64A1` (255, 100, 161) |
| PeakColours | `#00576A` (0, 87, 106) | `#751087` (117, 16, 135) | `#4594DD` (69, 148, 221) | `#A9D8F9` (169, 216, 249) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 112.1..211.9 |
| `Peak luminance range` | 44.2..255.0 |

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
| BarColours | `#CC0000` (204, 0, 0) | `#D84000` (216, 64, 0) | `#E58000` (229, 128, 0) | `#F2C000` (242, 192, 0) | `#FFFF00` (255, 255, 0) |
| PeakColours | `#5C0000` (92, 0, 0) | `#AE8080` (174, 128, 128) | `#FFFFFF` (255, 255, 255) | `#FFFFFF` (255, 255, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 43.4..236.6 |
| `Peak luminance range` | 19.6..255.0 |

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
| BarColours | `#B74400` (183, 68, 0) | `#EA7A00` (234, 122, 0) | `#FFD300` (255, 211, 0) | `#FFC900` (255, 201, 0) | `#B97900` (185, 121, 0) |
| PeakColours | `#480000` (72, 0, 0) | `#A53600` (165, 54, 0) | `#E86D00` (232, 109, 0) | `#FFC900` (255, 201, 0) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 87.5..236.6 |
| `Peak luminance range` | 15.3..255.0 |

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
| BarColours | `#D1D3D5` (209, 211, 213) | `#D1D3D5` (209, 211, 213) | `#D1D3D5` (209, 211, 213) | `#D1D3D5` (209, 211, 213) | `#D1D3D5` (209, 211, 213) |
| PeakColours | `#6A7175` (106, 113, 117) | `#6A7175` (106, 113, 117) | `#6A7175` (106, 113, 117) | `#6A7175` (106, 113, 117) | `#6A7175` (106, 113, 117) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 210.7..210.7 |
| `Peak luminance range` | 111.8..111.8 |

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
| BarColours | `#DC1BBA` (220, 27, 186) | `#A17DAF` (161, 125, 175) | `#694B79` (105, 75, 121) | `#B43C7B` (180, 60, 123) | `#67ADEB` (103, 173, 235) |
| PeakColours | `#6A2009` (106, 32, 9) | `#9B3D6D` (155, 61, 109) | `#AA6D8A` (170, 109, 138) | `#8BB350` (139, 179, 80) | `#6EF818` (110, 248, 24) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 58.9..167.9 |
| `Peak luminance range` | 46.1..202.5 |

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
| BarColours | `#373737` (55, 55, 55) | `#382F62` (56, 47, 98) | `#452E6D` (69, 46, 109) | `#F3EAFF` (243, 234, 255) | `#FFFFFF` (255, 255, 255) |
| PeakColours | `#3C3C3C` (60, 60, 60) | `#520889` (82, 8, 137) | `#A578C6` (165, 120, 198) | `#FFFFFF` (255, 255, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 52.2..255.0 |
| `Peak luminance range` | 28.8..255.0 |

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
| BarColours | `#FFFFFF` (255, 255, 255) | `#FFFFED` (255, 255, 237) | `#FFFFDC` (255, 255, 220) | `#FFFFCA` (255, 255, 202) | `#B10000` (177, 0, 0) |
| PeakColours | `#3E0000` (62, 0, 0) | `#3E0000` (62, 0, 0) | `#3E0000` (62, 0, 0) | `#3E0000` (62, 0, 0) | `#3E0000` (62, 0, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 37.4..255.0 |
| `Peak luminance range` | 13.2..13.2 |

## Metal Aluminum

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Metal Aluminum.ini`
- Description: Metal analyzer tuned to the Aluminum finish.

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
| `Message` | Metal analyzer tuned to the Aluminum finish. |

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
| BarColours | `#4D5761` (77, 87, 97) | `#757F89` (117, 127, 137) | `#9CA6B0` (156, 166, 176) | `#C4CED8` (196, 206, 216) | `#EBF5FF` (235, 245, 255) |
| PeakColours | `#EBF5FF` (235, 245, 255) | `#F0F8FF` (240, 248, 255) | `#F5FAFF` (245, 250, 255) | `#FAFDFF` (250, 253, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 85.6..243.6 |
| `Peak luminance range` | 243.6..255.0 |

## Metal Anodized Black

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Metal Anodized Black.ini`
- Description: Metal analyzer tuned to the Anodized Black finish.

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
| `Message` | Metal analyzer tuned to the Anodized Black finish. |

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
| BarColours | `#8C9199` (140, 145, 153) | `#A6ABB3` (166, 171, 179) | `#BFC4CC` (191, 196, 204) | `#D9DEE6` (217, 222, 230) | `#F2F7FF` (242, 247, 255) |
| PeakColours | `#F2F7FF` (242, 247, 255) | `#F5F9FF` (245, 249, 255) | `#F9FBFF` (249, 251, 255) | `#FCFDFF` (252, 253, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 144.5..246.5 |
| `Peak luminance range` | 246.5..255.0 |

## Metal Brass

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Metal Brass.ini`
- Description: Metal analyzer tuned to the Brass finish.

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
| `Message` | Metal analyzer tuned to the Brass finish. |

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
| BarColours | `#663D0F` (102, 61, 15) | `#8C6529` (140, 101, 41) | `#B38C42` (179, 140, 66) | `#D9B45C` (217, 180, 92) | `#FFDB75` (255, 219, 117) |
| PeakColours | `#FFDB75` (255, 219, 117) | `#FFE498` (255, 228, 152) | `#FFEDBA` (255, 237, 186) | `#FFF6DD` (255, 246, 221) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 66.4..219.3 |
| `Peak luminance range` | 219.3..255.0 |

## Metal Bronze

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Metal Bronze.ini`
- Description: Metal analyzer tuned to the Bronze finish.

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
| `Message` | Metal analyzer tuned to the Bronze finish. |

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
| BarColours | `#8C754C` (140, 117, 76) | `#A99161` (169, 145, 97) | `#C6AE75` (198, 174, 117) | `#E3CA8A` (227, 202, 138) | `#FFE69E` (255, 230, 158) |
| PeakColours | `#FFE69E` (255, 230, 158) | `#FFECB6` (255, 236, 182) | `#FFF3CF` (255, 243, 207) | `#FFF9E7` (255, 249, 231) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 118.9..230.1 |
| `Peak luminance range` | 230.1..255.0 |

## Metal Brushed Steel

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Metal Brushed Steel.ini`
- Description: Metal analyzer tuned to the Brushed Steel finish.

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
| `Message` | Metal analyzer tuned to the Brushed Steel finish. |

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
| BarColours | `#1A576B` (26, 87, 107) | `#3E7D90` (62, 125, 144) | `#61A2B5` (97, 162, 181) | `#85C8DA` (133, 200, 218) | `#A8EDFF` (168, 237, 255) |
| PeakColours | `#A8EDFF` (168, 237, 255) | `#BEF2FF` (190, 242, 255) | `#D4F6FF` (212, 246, 255) | `#EAFBFF` (234, 251, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 75.5..223.6 |
| `Peak luminance range` | 223.6..255.0 |

## Metal Copper

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Metal Copper.ini`
- Description: Metal analyzer tuned to the Copper finish.

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
| `Message` | Metal analyzer tuned to the Copper finish. |

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
| BarColours | `#B27552` (178, 117, 82) | `#C58B61` (197, 139, 97) | `#D9A171` (217, 161, 113) | `#ECB780` (236, 183, 128) | `#FFCC8F` (255, 204, 143) |
| PeakColours | `#FFCC8F` (255, 204, 143) | `#FFD9AB` (255, 217, 171) | `#FFE6C7` (255, 230, 199) | `#FFF2E3` (255, 242, 227) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 127.4..210.4 |
| `Peak luminance range` | 210.4..255.0 |

## Metal Gunmetal

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Metal Gunmetal.ini`
- Description: Metal analyzer tuned to the Gunmetal finish.

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
| `Message` | Metal analyzer tuned to the Gunmetal finish. |

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
| BarColours | `#8C99A8` (140, 153, 168) | `#A4B0BE` (164, 176, 190) | `#BCC7D4` (188, 199, 212) | `#D4DEEA` (212, 222, 234) | `#EBF5FF` (235, 245, 255) |
| PeakColours | `#EBF5FF` (235, 245, 255) | `#F0F8FF` (240, 248, 255) | `#F5FAFF` (245, 250, 255) | `#FAFDFF` (250, 253, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 151.3..243.6 |
| `Peak luminance range` | 243.6..255.0 |

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
| BarColours | `#266AE3` (38, 106, 227) | `#685DD9` (104, 93, 217) | `#8696DB` (134, 150, 219) | `#ACE8E3` (172, 232, 227) | `#DBDBFF` (219, 219, 255) |
| PeakColours | `#000091` (0, 0, 145) | `#0000FA` (0, 0, 250) | `#9A3BFF` (154, 59, 255) | `#DCBBFF` (220, 187, 255) | `#FFFFFF` (255, 255, 255) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 82.5..221.6 |
| `Peak luminance range` | 10.5..255.0 |

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
| BarColours | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) |
| PeakColours | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) | `#976822` (151, 104, 34) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 0.0..108.9 |
| `Peak luminance range` | 108.9..108.9 |

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
| BarColours | `#6148D7` (97, 72, 215) | `#4C6BD4` (76, 107, 212) | `#388ED2` (56, 142, 210) | `#24B2D0` (36, 178, 208) | `#11D5CF` (17, 213, 207) |
| PeakColours | `#26006A` (38, 0, 106) | `#8C5FFF` (140, 95, 255) | `#7291F9` (114, 145, 249) | `#59C4F3` (89, 196, 243) | `#41F6EE` (65, 246, 238) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 87.4..170.9 |
| `Peak luminance range` | 15.7..206.9 |

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
| BarColours | `#FF00FF` (255, 0, 255) | `#0041FF` (0, 65, 255) | `#00FF7D` (0, 255, 125) | `#C3FF00` (195, 255, 0) | `#FF0000` (255, 0, 0) |
| PeakColours | `#0000FF` (0, 0, 255) | `#00FFFF` (0, 255, 255) | `#00FF00` (0, 255, 0) | `#FFFF00` (255, 255, 0) | `#FF0000` (255, 0, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 18.4..236.6 |
| `Peak luminance range` | 18.4..236.6 |

## Red

- File: `Sources/NullPlayer/Resources/vis_classic/profiles/Red.ini`
- Description: The Green profile in red: a single-hue ramp for skins with a red accent.

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
| `Message` | The Green profile in red: a single-hue ramp for skins with a red accent. |

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
| BarColours | `#7D0000` (125, 0, 0) | `#9D0000` (157, 0, 0) | `#BE0000` (190, 0, 0) | `#DE0000` (222, 0, 0) | `#FF0000` (255, 0, 0) |
| PeakColours | `#4D0000` (77, 0, 0) | `#6D0000` (109, 0, 0) | `#8E0000` (142, 0, 0) | `#AF0000` (175, 0, 0) | `#D00000` (208, 0, 0) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 26.6..54.2 |
| `Peak luminance range` | 16.4..44.2 |

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
| BarColours | `#89A3A3` (137, 163, 163) | `#4AB95B` (74, 185, 91) | `#B6E279` (182, 226, 121) | `#9D4976` (157, 73, 118) | `#E200D8` (226, 0, 216) |
| PeakColours | `#174CD4` (23, 76, 212) | `#8D89D6` (141, 137, 214) | `#32689C` (50, 104, 156) | `#B0C330` (176, 195, 48) | `#194EE5` (25, 78, 229) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 63.6..224.3 |
| `Peak luminance range` | 57.9..194.5 |

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
| BarColours | `#FCFCC3` (252, 252, 195) | `#FDF3BF` (253, 243, 191) | `#DBA18E` (219, 161, 142) | `#6B3944` (107, 57, 68) | `#401A2F` (64, 26, 47) |
| PeakColours | `#401A2F` (64, 26, 47) | `#401A2F` (64, 26, 47) | `#401A2F` (64, 26, 47) | `#401A2F` (64, 26, 47) | `#401A2F` (64, 26, 47) |

| Palette Metric | Value |
|---|---|
| `BarColours entries` | 256 |
| `PeakColours entries` | 256 |
| `Bar luminance range` | 35.6..247.9 |
| `Peak luminance range` | 35.6..35.6 |
