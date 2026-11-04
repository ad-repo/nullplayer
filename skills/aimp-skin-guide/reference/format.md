# AIMP skin format

Reverse-engineered from Kanono (`.acs4` + `.acs4proj`), Soot and Vega MP-120 (`.acs5`), and the 16
`.acs3` decks of the corpus. The Python
reference tools are in `~/projects/aimp-skin-lab` (outside the repo); `AIMPSkinArchive`,
`AIMPSkinImage` and `AIMPNode` are the Swift readers. Every one reads bytes through `AIMPSkinBytes`
(little-endian, bounds-checked, XOR-aware), inflates through `AIMPSkinZlib`, and reads INI text
(`main.ini`, `.lng`) through `AIMPSkinINI`: sections and keys in any case (AIMP 2 writes
`[Skin_OPtions]`), file order kept, a value's leading spaces kept and its trailing ones dropped (a
`.lng` caption keeps them: `writtenLines`).

## Containers

All four carry the same metadata block after their header (AIMP 3.0's `.acs3` excepted): a `u32`
length, then that many bytes: three UTF-16LE strings (`u16` character count first: name, author,
description), a `u8` preview flag and a Windows BMP. The BMP's own file header can overstate its
size (by about a kilobyte in many `.acs3`): it ends where the block does. The body starts right
after the block.

| Format | Header | Scrambling | Body |
|---|---|---|---|
| `.acs5` | `ACS5`, `u8` 0, `u32` engine version (500), `u8`, `u8` key length (16), the key in plain text | everything after the key, the metadata length included, XORed with the key, indexed by file offset mod key length | `u32` count, then entries `{ name (u16 LE count + UTF-16LE), u8 kind, u32 size, u8 packed, packed ? (u32 packed size, 2-byte zlib header, raw DEFLATE) : bytes }` |
| `.acs4` | `ACS4`, `u8` 0, `u32` engine version (450 or 400), then the marker `3SCA` at 9 under the key | a 4-byte key, byte `i` of the file XORed with key byte `i mod 4`; the marker gives all four away. The metadata (from 17) and the zlib stream are XORed; the metadata length (at 13) and the inflated size are plain | plain `u32` inflated size, then one zlib stream: `u32` count, `{ name, u32 offset, u32 size }` × count, blob (identical files share bytes) |
| `.acs3` | `ACS3`, `u8` kind. 6: `u16` engine version (350), 2 bytes, the marker at 9; 3 and 5: the marker at 5; 1 and 2 (AIMP 3.0): the marker at 5 and no metadata | as `.acs4` | as `.acs4` without the inflated size; kinds 1 and 2 have it right after the marker, at 9 |
| `.acs4proj` | `ACSJ`, as `.acs4` with the marker in plain text | none | `u32` count, then inline entries `{ name, u32 size, bytes }` |
| `.acs` (AIMP 2) | `ACSP`, `u8` version (2 or 3), name (32 bytes) and author (35), NUL-padded, Windows-1251; `u32` entry count at `0x48` | none | no metadata block; one zlib stream from `0x4C`: entries back to back, `{ name, u32 size, bytes }`, the name 32 NUL-padded bytes (version 2) or a `u8` length and the name (version 3) |

Readers before 2026-11-02 read the strings as big-endian from one byte earlier, which matches for
Latin-1 text under 256 characters only: Cyrillic names and long descriptions broke it.

AIMP 3.0's `.acs3` (Vega AIO v1.01, kind 2, and the BMP skins of kind 1) has no metadata. Its name
and author are `main.ini`'s `[FILE]` `SkinName` and `Author`, its preview `preview.bmp`. The forms
are not SXML/BXML trees: see *AIMP 3.0 forms*.

`.acs5` entry kinds, and the extension `AIMPSkinArchive` gives them:

| Kind | What | Name |
|---|---|---|
| 1 | `ACLIMG32` image | `.img` |
| 2 | `SXML` image set (one image per DPI: 96, 120, 144, 168, 192) | `.imageset.xml` |
| 3 | `SXML` form or `Schema` | `.xml` |
| 4 | TrueType font | `.ttf` |
| 6 | language, UTF-16 INI | `.lng` |
| 7 | FastScript syntax tree (`FSXMLBIN`) | `.fsxml` |

`.acs5` images exist once per DPI: `name`, `name-120` … `name-192`. The loader decodes the 96 DPI
ones only.

## ACLIMG32 images

Entries end `.img`, or `.myimg` in some older `.acs4` skins (Sony TC-MR2); same format.

`ACLIMG32`, `u32` version, `u32` chunk count, then chunks `{ 4-char tag, u32 size, data }`:

| Chunk | Contents |
|---|---|
| `bits` | `u32` format (3), width, height, **premultiplied** BGRA, top row first |
| `bitz` | `.acs5`: the same with a `u32` packed size, then zlib |
| `layt` | `u8` orientation (1 = frames stacked), `u32` frame count, 4 × `u32` nine-slice margins (left, top, right, bottom), 4 × `u32` content margins (where a caption starts), 17 bytes unknown |
| `draw` | `u32` (1, 3, 5; unknown), `u8` how a frame fills a larger rect: 0 nine-sliced, 1 tiled (Soot's noise grain), 2 centred at its own size (glyphs on flat keys; Vega's 9-px scroll dot) |
| `fram`/`ifam`, `XDPI` | per-frame flags (unknown); design DPI (96) |

No `bits`/`bitz` chunk: a solid fill stored as a colour (not decoded yet).

## ASEIMG32 images (`.acs3`)

`.myimg` entries: `ASEIMG32`, `u32` version (1), `u32` pixel bytes, 2 bytes, `u32` frame count (at
18), 5 bytes, `u8` orientation at 27 (1 = frames stacked), 4 × `u32` nine-slice margins from 28
(order unconfirmed), 18 bytes, `u32` width and height at 62, then premultiplied BGRA from byte 70,
then a byte per frame (some skins 16 more). AIMP 3.0 calls the same layout `MySknImg`, and keeps a
0×0 one for every object, drawn or not. Its `u8` at 44 is how a picture fills (0 as is, 1
stretched, 2 tiled); with no margins and 1, the four `u32` at 45 are two columns `x, width, x,
width` that share the extra width while the rest keeps its size (Vega AIO's transport panel).

## AIMP 3.0 BMP pictures

`.acs3` kind 1 keeps its pictures as Windows bitmaps (`AddBtn.bmp`): `BITMAPINFOHEADER`, uncompressed,
mostly 32 bits with straight alpha (every alpha byte 0: opaque), else 24 bits, rarely 8 with a
palette; bottom-up. What `ASEIMG32` keeps in its header is the object's `main.ini` section:
`SkinFrames`, `SkinLayout` (1 stacked, 0 side by side), `Margins` (left, top, right, bottom),
`StretchMode` (1 stretched) and with it `TLC`/`TRC`, the two stretched columns as `left, top, right,
bottom` (`TRC=281,0,281,0`, empty, for none). `SkinHitTestMask`/`SkinHitTestMaskFrame` name a mask
frame (not read; the painter finds masks itself). One decoder (`AIMPSkinBitmap`) reads these and
AIMP 2's: magenta `FF00FF` is clear in both (`AIMP 2 (.acs)` below).

## AIMP 3.0 forms

`AIMPSkinLegacy` reads them into the later formats' tree, so the renderer takes them unchanged:
each reader (AIMP 3.0's, AIMP 2's) turns `main.ini` into typed `AIMPSkinLegacy.Object`s (a `Kind`:
text, time, status, spectrum, AIMP's own object…) and `Settings`, which one `Translator` builds the
form from.

- `MainFrame.xml` is the item tree, attribute style: `<item Class=… Name=… Align=… AlignLevel=…
  AlignMargins=…/>`. `TAIMPLayoutContainerItem` has a picture named after it,
  `TAIMPLayoutTextureItem` is a picture, `TAIMPLayoutItem` groups, `TAIMPLayoutDockSiteItem` holds
  a frame: `<Name>.xml` (`PlaylistFrame.xml`; `EqualizerFrame`'s is `EqFrame.xml`), the playlist
  tabs (`TabCtrl`) or the playlist (`Container`). No `Align` is top; lower `AlignLevel` docks first.
- `main.ini` (UTF-16) places the controls. `[Parents]` names each one's item; its own section has
  `PlaceAnchors`, `PlaceMargins` (Delphi, as `PlaceInfo`), `PlaceWidth`, `PlaceHeight`, `ZOrder`
  (back to front). Unused objects are parked left of or above their item; objects past its right
  or bottom edge show when the window grows (Vega AIO's EQ, right of its info panel).
- `[MainFrame] SizingHitTestAreaWidth` makes the window sizable from its edges (the root item's
  `SizingHitTestAreaWidth`; the window drags from its right and bottom edges, no smaller than the
  natural size, and keeps the size per skin). `AIMPEQDisplay` is the EQ curve: `EQVISE` the curve,
  `EQVISL` the preamp line.
- What a control is: `[CustomObjects]` (`ClassTextLabel` with `Template`, `Font`
  `name,BGR,height,style`, `TextAlign` 0 left, 1 right, 2 centre; `ClassNumLabel;4` time,
  `Static=1` the duration, `;5` bitrate, `;6` sample rate; `ClassStatusLabel;2` a picture per play
  state; `ClassSeekBar`, `ClassAnimator`, `ClassSpectrum` with `Peaks` bars in `Color`,
  `Orientation=1` upside down; `ClassCoverArt`), else `[Clones]` (a copy of AIMP's object), else
  AIMP's object by name: `PlayPauseBtn` (play's four frames, then pause's), `PrevBtn`, `Shuffle`
  (a switch: three frames off, three on, a mask), `VolumeBar` (`Orientation` 0 upright, 1 across,
  2 a knob through its frames), `MenuBtn`, `AddBtn` and the other popup keys.
- `[Playlist]` gives the playlist's fonts (`Nrm`, `Act`, `Sel`, `SelAct`) and colours (`BK`, `ABK`,
  `SBK`, `SABK`); `[TabCtrl]` the tabs' (`ActiveTab`).

## AIMP 2 (`.acs`)

`AIMPSkinArchive+ACSP` reads the package, `AIMPSkinBitmap` the pictures, and `AIMPSkinLegacy+AIMP2`
turns `main.ini` into the AIMP 3.0 model above, so `AIMPSkinLegacy`'s translator builds the form.
Version 3 (124 of the catalog's 166) leaves the header's name empty and credits it in `main.ini`'s
`[FILE]`; one package (version `0x20`, Dark Lagoon) is scrambled and stays `AM0011`.

- **Pictures.** Windows bitmaps: `<Object>.bmp` (version 2: `<Object>_skin.bmp`), 24-bit mostly,
  32-bit with straight alpha, a few 1-, 4-, 8- and 16-bit, some with a core header. Magenta `FF00FF`
  is the key colour (clear). They decode when drawn, as every picture does; the layout below re-cuts
  them from their headers. States
  sit side by side: `SkinFrames` of them, else as many as the object's width fits. A slider's lit
  track is `<Object>_sel`, its thumb `<Object>_thumb` (one frame). Digit strips (`time`, `BRINFO`;
  `SRINFO` borrows `BRINFO`'s) are 13 glyphs as AIMP 3's. The equalizer's bands share
  `AIMPSlider9`'s picture when they have none.
- **Panels.** An object's `[Parents]` value is its panel: `MAIN` is `MainClient` over `BottomDock`
  (two stacked states, the second docked to the playlist), `EQ` is `MainEquaFrame` (version 2:
  `Client`), `TOP`/`BTM` the playlist's `TopPanel`/`BottomPanel`, `ContainerN` a skin's own panel
  (`[CustomObjects]` `ClassContainer;PlaylistFrame` or `;MainLayoutBox`). `TCCTRL`/`TCINFO` (tray),
  `QFIClient` (quick file info) and `PlaylistFrame` (the detached playlist's title bar, over
  `PlsTopDock`) are AIMP's windows. A panel clips what lies outside it.
- **Layout.** Version 3: `MainLayout.xml` and `PlaylistLayout.xml`, sibling `<item Align Level
  Control>` elements with no root (`Control` a panel, `MainFrame`, `EqualizerFrame` or
  `PlaylistFrame`). The playlist frame is `PlsLeftBar`, `PlsRightBar` and `PlsBottomBar` round the
  playlist layout (`TabCtrl`, `TopPanel`, `BottomPanel`, `Container`). An equalizer the main layout
  leaves out (`AllInOneMode=0`) is a window right of the player (`[EquaForm]`) that `EQBtn` and the
  equalizer's `HideBtn` show and hide. Version 2 has no layout files: the player over the playlist,
  its tabs over the top panel when `[SKIN_WIDTHS]` `TabCtrlIsUp`.
- **Objects.** Version 3: a section per object, `Bounds` (left, top, right, bottom in the panel),
  `ParentBounds` (the panel as saved), `Align` (0 keeps the left edge, 1 the right, 2 both, 3 the
  proportion), `Font`, `TextAlign`, `Digits`, `Orientation` (0 upright, 1 across); empty bounds
  for unused objects. Version 2: `[SKIN_OBJS]` bounds, `[PARENTS]` (none for the equalizer's),
  `[SKIN_WIDTHS]` `<Object>_align`, `<Object>_HORIZONTAL`, `<Object>Digits` and the playlist's
  `Switch_*` colours, `[SKIN_FONTS]`, `[SKIN_TEXTALIGNS]`, `[SKIN_RECTS]` `<Panel>_TLC`/`_TRC`,
  `[SKIN_VIRTUAL_OBJS]` (clones), `[TC_PARENTS]` (tray). Object names match AIMP 3's in any case;
  AIMP 2's built-ins become AIMP 3.0's custom objects (`time`, `BRINFO`, `SRINFO`, `PlayerMode`,
  `Spectrum`, `seekbar`, `iTitle`/`iArtist`/`iAlbum`/`iGenre`; `ClassTextLabel;N` shows title,
  artist, album, year, genre for N 1–5, inferred from the labels' widths).
- **Stretching.** A panel's `TLC` and `TRC` (`x1,0,x2,0`) are the two columns that take a wider
  rect's width (`AIMPSkinImage.StretchColumns`).

## Documents

`AIMPNode.parse` takes all three encodings.

- **`SXML`** (`.acs5`): `u32` offset of the name table (from byte 12), `u32`, `u8` version, root node.
  A node is a varint name index and flags (1 attributes, 2 children, 4 text), then text (varint
  length + UTF-16LE), attributes (varint count, `{ varint name index, varint length + UTF-16LE }`),
  children. The name table is a varint count of `{ varint length + ASCII }`.
- **`BXML`** (`.acs4`): `u32` version, root node. A node is a `u16` ASCII tag and the same flags,
  then attributes (`u32` count, `{ u16 ASCII, u16 length + UTF-16LE }`), children (`u32` count),
  text (`u32` length + UTF-16LE).
- **Text XML** (`.acs4proj`, `.acs3`; AIMP 3.0's attribute-style layouts).

## Scripts

FastScript (Fast Reports' embeddable interpreter), PascalScript dialect. `.acs4` ships source
(`*.script`, UTF-16); `.acs5` ships FastScript's syntax tree in binary: `FSXMLBIN`, then nodes of
`{ u16 + UTF-16LE tag, u16 + UTF-16LE attribute text, u32 child count }`. A `var` parameter is
`varparams` then `var` inside `parameters`; an initializer is `init` holding an `expr` after a
`var`'s `type`. How they run: `layout.md` § *Scripts*.
