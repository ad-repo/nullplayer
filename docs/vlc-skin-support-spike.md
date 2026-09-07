# Spike: VLC (`.vlt`) skin support

**Status:** research spike, no code written. **Date:** 2026-08-30.
**Corpus analysed:** 120 `.vlt` files from `~/Downloads/vlc-skins` — the classic VideoLAN
skins2 archive (all dated 2011, format `version="2.0"`).
**Companion document:** `docs/wmp-skin-support-spike.md`. The URL supplied with this request
(<https://sites.google.com/view/wmpgoodies/guides/making-a-skin-for-wmp>) is the *Windows Media
Player* guide and is the reference for that spike, not this one. The authoritative reference for
`.vlt` is VideoLAN's skins2 documentation and the `skin.dtd` each theme declares.

## 1. Verdict

**Yes — and this is the cheapest of the three foreign skin formats to support**, materially
cheaper than `.wal` and cheaper than `.wmz`.

The reason is one fact that holds across all 119 themes in the corpus: **skins2 has no scripting
language.** No MAKI bytecode (`.wal`), no JScript expressions (`.wmz`). Every behaviour a skin can
express is a fixed verb from a closed vocabulary written into an XML attribute:
`action="playlist.next()"`, `visible="vlc.isPlaying or vlc.isPaused"`, `value="volume"`,
`text="$T / $D"`. Layout is plain integers plus a four-value anchoring enum — no expression
evaluator anywhere.

That removes the single largest work item and the single largest schedule risk from the `.wmz`
estimate (§6 there: 2,500–4,000 LOC of JavaScriptCore hosting, rated **high** risk). What remains
is a bitmap compositor, a hit tester, a tiny expression grammar, and mode plumbing — all routine
work with a known shape in this codebase.

Rough shape: **~3,500–5,500 LOC** for a faithful engine. See §7.

## 2. What a `.vlt` actually is

Two containers, and a loader must handle both:

| Container | Count | Detected by |
|---|---|---|
| `tar` + gzip | 87 | gzip magic `1f 8b` |
| ZIP (deflate or store) | 33 | `PK\x03\x04` |

Both hold the same payload. 119 of 120 archives contain a `theme.xml`; 96 place it at the archive
root, 23 nest it one directory down (`Whiteout/Whiteout/theme.xml`), so **the loader must search
for `theme.xml` rather than assume the root**. One archive in the pack (`miniMatrix`) has a path
that exceeds the filesystem limit on extraction and carries no usable `theme.xml` — a real-world
reminder that entry-name length is an input to bound, not a given.

Assets across the whole corpus:

```
4822 png    134 ttf    12 bmp    10 otf    15 txt    1 svg    1 psd
```

**Effectively a PNG-only format.** A 400-file sample splits ~68% RGB / ~32% RGBA, so both a real
alpha channel and the legacy `alphacolor="#FF00FF"` color key are in live use — often in the same
skin. Both paths are needed; ImageIO decodes PNG natively, and the color key is a per-pixel mask
we apply at load.

`theme.xml` is **UTF-8, well-formed XML** — `xmllint --noout` passes on **119/119**. No UTF-16
transcode step (unlike `.wmz`), no bespoke tokenizer (unlike `.wal`'s Wasabi dialect). Sizes are
small: 39 to 1,126 lines, median 240.

## 3. The schema is tiny and closed

Every tag appearing anywhere in the 119 themes, with total occurrences and the number of skins
using it:

| Tag | Uses | Skins | Role |
|---|---|---|---|
| `SubBitmap` | 7,860 | 80 | sprite rect inside a sheet |
| `Bitmap` | 4,976 | 119 | image resource decl |
| `Button` | 3,355 | 119 | 3-state button |
| `Image` | 3,278 | 119 | static/clickable image |
| `Slider` | 1,674 | 117 | value control on a curve |
| `Checkbox` | 984 | 112 | 2×3-state toggle |
| `Anchor` | 709 | 69 | window magnetism point |
| `Text` | 590 | 114 | TTF text with macros |
| `SliderBackground` | 567 | 63 | slider trough |
| `Layout` | 466 | 119 | a sized view of a window |
| `Window` | 354 | 119 | top-level window |
| `Group` | 302 | 65 | positioned container |
| `Font` | 211 | 110 | TTF/OTF font decl |
| `Panel` | 204 | 31 | clipping container |
| `Video` | 160 | 98 | video output pane |
| `ThemeInfo` / `Theme` | 119 | 119 | metadata / root |
| `Playtree` | 111 | 90 | playlist tree widget |
| `Playlist` | 13 | 13 | deprecated flat playlist |
| `BitmapFont` | 6 | 5 | sprite-sheet font |
| `include` | 3 | 1 | file inclusion |

**Twenty tags.** Compare Wasabi, where `<groupdef>`/XUI lets a skin *define new component types* —
that open-endedness is why `WinampModern/` is 23,649 LOC. A closed 20-tag catalog is implementable
to completion and declarable "done".

Structure per skin is equally modest: median 3 `Window`s and 4 `Layout`s (max 5 and 25). A
`Window` holds one or more `Layout`s (alternate sizes/skins of the same window, switched by
`setLayout()`); a `Layout` holds the widget tree.

## 4. The four mechanisms to implement

### 4.1 Sprite sheets — `Bitmap` + `SubBitmap`

```xml
<Bitmap id="main" file="main.png" alphacolor="#FF00FF">
  <SubBitmap id="play_normal" x="0" y="0" width="26" height="26"/>
  ...
</Bitmap>
```

7,860 `SubBitmap`s. Skins split roughly into "one PNG per state" (Airflow: 152 `Bitmap`, 9
`SubBitmap`) and "one sheet, many rects" (default_0.8.5: 26 `Bitmap`, 122 `SubBitmap`); both
styles must work. `SubBitmap` also carries `nbframes`/`fps` for **animated bitmaps** — 9 skins,
2–23 frames. This is the same resource-cache-plus-sprite-rect model `WinampModern/` already runs.

### 4.2 Layout and resize — an anchoring enum, not expressions

Geometry is literal integers (`x`, `y`, `width`, `height`) plus two attributes that say which
window corner each edge follows when the window resizes:

```
lefttop=     leftbottom 2182 | righttop 1353 | rightbottom 819 | lefttop 609
rightbottom= rightbottom 2410 | righttop 1482 | leftbottom 1479 | lefttop 218
```

Four enum values, evaluated per resize. `Layout` carries `minwidth`/`maxwidth`/`minheight`/
`maxheight`; images carry `resize="scale" | "mosaic" | "scale2"` (tile vs stretch) and
`xkeepratio`/`ykeepratio`. **This is the whole layout engine.** It is arithmetic, and it is the
main structural difference from `.wmz`, where the equivalent required a JS host.

### 4.3 The action / condition / variable vocabulary

Three small languages, all closed:

**Actions** (`action=`, `action2=` for right-click). Non-call verbs: `move` (1,950 — drag the
window), `resizeE`/`resizeS`/`resizeSE`, `none`. Call verbs by namespace:

```
vlc.*       play pause stop quit fullscreen minimize mute onTop slower faster
            volumeUp volumeDown snapshot toggleRecord
playlist.*  next previous add del load save sort setLoop(b) setRandom(b) setRepeat(b)
            moveup movedown
playtree.*  sort del
equalizer.* enable disable
dvd.*       nextChapter previousChapter nextTitle previousTitle rootMenu
dialogs.*   prefs file fileSimple fileInfo directory disc net playlist popup
            audioPopup videoPopup miscPopup messages changeSkin streamingWizard
<window>.*  show hide maximize unmaximize setLayout(id)     ← ~360 uses, arbitrary window ids
```

The `<window>.method()` form is the only open part of the grammar, and it resolves against
window `id`s declared in the same file — a symbol-table lookup, not evaluation.

**Conditions** (`visible=`), a boolean grammar of `not` / `and` / `or` / parentheses over a fixed
predicate set:

```
vlc.isPlaying  isPaused  isStopped  isSeekable  isMute  isOnTop  hasVout  hasAudio
equalizer.isEnabled    dvd.isActive    playlist.isRepeat    <window>.isMaximized
```

Every distinct expression in the corpus is short — the most complex is
`(not vlc.isStopped) and (not dvd.isActive)`. A ~150-line recursive-descent parser covers it.

**Variables** (`value=` on sliders): `volume`, `time`, `equalizer.preamp`, `equalizer.band(0..9)`.
That is the entire list. Two-way — a slider reads and writes.

**Text macros** (`text=`), 11 codes in use across 115 skins: `$T` elapsed (254), `$N` name (196),
`$V` volume (184), `$D` duration (122), `$L` time left (46), `$B` bitrate (24), `$F` full path
(19), `$t` title (13), `$S` sample rate (12), `$d` description (9), `$H` (5). All map onto
existing `Track`/`AudioEngine` state. `Text` supports `scrolling="auto"` (marquee, 53 uses).

### 4.4 Sliders on a polyline path

```xml
<Slider id="volume" value="volume" points="(0, 20),(80, 20)" up="vol_cursor" .../>
```

`points` is a control polyline the cursor rides, with the value mapped along its arc length. The
corpus is overwhelmingly trivial: **1,675 of 1,815 are 2-point straight lines**, 106 are 1-point,
and only **34 have 3–5 points** (real curves). Implement the straight-line case first and the
polyline case behind it; almost nothing in the wild needs the general form.

### 4.5 Window magnetism — `Anchor`

709 `Anchor`s in 69 skins: a point (or line, via `points`) on a window with a `priority` and a
`range`; two windows within `range` snap together, highest priority winning. NullPlayer already
has window docking for classic; this is a per-skin declarative variant of the same idea and
should route through the existing docking machinery, not a new one.

## 5. What will not map

| Feature | Skins affected | Disposition |
|---|---|---|
| `<Video>` output pane | 98 | Render as an inert or visualiser-filled pane. NullPlayer is audio-first. |
| `dvd.*` chapter/title/menu | 47 | No-op with a diagnostic; hide via the `dvd.isActive` predicate, which is permanently false — 205 `visible="dvd.isActive"` uses then correctly resolve to hidden. |
| `dialogs.*` | 92 | Map what exists (`file`, `prefs`, `playlist`, `fileInfo`, `popup`, `changeSkin`) onto NullPlayer's own dialogs and menus; no-op the rest (`streamingWizard`, `messages`, `disc`, `net`). |
| `vlc.snapshot`, `toggleRecord` | 10 | No-op or route to the stream ripper where sensible. |
| `equalizer.band(0..9)` | 67 | 10-band — maps onto the **classic** EQ, not the 21-band modern one. Same constraint the `.wmz` spike found. |
| `<include>` | 1 | Support it (bounded, no path escape) or diagnose; one skin. |
| `<Playlist>` (deprecated) | 13 | Treat as a degenerate `<Playtree>`. |

The good news is how *little* is unmappable: `vlc.*` transport, `playlist.*`, volume, time,
seeking, EQ, and the whole text-macro set land directly on existing NullPlayer facilities.
Each unmapped item should surface as a named diagnostic in a compatibility report, mirroring
`Sources/NullPlayer/WinampModern/WinampModernCompatibilityReport.swift`, never as a load failure.

## 6. Which base to build on

Same conclusion as the `.wmz` spike, for the same reasons — **a new, independent
`Sources/NullPlayer/VLCSkin/` engine**, reusing Winamp Modern's *leaf utilities and patterns* and
Original's *hosting shell*:

- **From `WinampModern/`:**
  - `WalArchive.swift` (`Sources/NullPlayer/WinampModern/WalArchive.swift:28`) — the ZIP path
    is reusable close to verbatim; `.vlt` needs no NSIS and no LZMA, but **does** need a
    tar+gzip path added alongside (87 of 120 archives). `WalArchiveLimits` (line 4) is the
    bounding model to copy.
  - Typed `WalFailure`/`WalDiagnostic` reporting instead of traps.
  - The `NSView.draw(_:)` over `CGContext` scene-cache render shape proven in
    `Windows/WinampModern/WinampModernMainView.swift`. No Metal.
  - The ingestor protocol at `WinampModern/WinampModernSkinImporter.swift:20` — a
    `VltContainerIngestor` slots in beside `WalContainerIngestor` with no change to the
    existing ingestion path.
  - The `WinampModernHost.swift` bridge shape for the `AudioEngine` boundary.
- **From Original (`ModernSkin/`, `Windows/Modern*`):** the window/controller/provider
  conventions as the hosting shell only. As with `.wmz`, the `skin.json` *engine* is the wrong
  base — a `.vlt` is an arbitrary widget tree and translating it to `skin.json` discards the skin.
- **Do not** add skins2 nodes to `WasabiObjectGraph`. `skills/winamp-modern-skin-guide` forbids
  changes that alter Winamp Modern behaviour; reuse is by extraction, never by widening the
  Wasabi path in place.

## 7. Sketch of the work

Each phase independently demonstrable.

- **P0 — ingest.** tar.gz + ZIP, `theme.xml` search (root or one level down), XML → typed node
  tree, resource table (`Bitmap`/`SubBitmap`/`Font`). Deliverable: a tree dump for any `.vlt`.
- **P1 — static render.** PNG decode, alpha + `alphacolor` key, `SubBitmap` rects, `Group`/`Panel`
  nesting, `lefttop`/`rightbottom` anchoring, `resize` modes, first `Layout` of each `Window`.
  Deliverable: a skin rendered recognisably at its declared size, and correct on resize.
- **P2 — input and state.** Button/Checkbox 3-state hit testing, `action`/`action2` dispatch to
  `AudioEngine` and the playlist, the `visible=` condition parser, `move`/`resize*` drags.
  Deliverable: a clickable, playing skin.
- **P3 — values and text.** Sliders (straight-line first, then polyline), `value=` two-way binding
  for volume/time/EQ, `Text` with the 11 macros and `scrolling="auto"`, `Font`/`BitmapFont`.
  Deliverable: seek bar, volume, EQ, and a live title display.
- **P4 — mode plumbing.** `PlayerUIMode.vlc` and a fourth `PlayerUIControllerFamily` in
  `App/PlayerUIMode.swift` (`usesModernControllers`, `usesModernEQLayout`, `modernSkinFamily`
  each need a fourth answer); the controller factory switch near `App/WindowManager.swift:854`
  and `reloadUI(to:)`; the Skins submenu in `App/ContextMenuBuilder.swift`;
  `VltContainerIngestor`; a `VLCSkins/` support directory.
- **P5 — remaining widgets.** `Playtree`, multi-`Layout` switching via `setLayout()`,
  `Anchor` magnetism through the existing docking machinery, animated `SubBitmap`s,
  `Video` as a visualiser pane, the compatibility report.

## 8. Effort and risk

Benchmarked against the existing engines (`Skin/` = 6,934 LOC, `ModernSkin/` = 5,771,
`WinampModern/` = 23,649):

| Phase | Rough LOC | Risk |
|---|---|---|
| P0 ingest | 400–600 | low — mostly reuse, plus a tar reader |
| P1 static render | 1,000–1,500 | low, routine |
| P2 input and state | 600–900 | low |
| P3 values and text | 500–800 | low |
| P4 mode plumbing | 400–800 | **medium** — touches shared files, must be gated |
| P5 remaining widgets | 700–1,000 | medium |
| **Total** | **~3,600–5,600** | |

For comparison, the `.wmz` estimate was 7,000–11,000 with a high-risk 2,500–4,000 LOC scripting
phase. **There is no equivalent phase here.** The largest remaining risk is P4 — low-LOC but
high-care, because it edits files all modes run through, and `CLAUDE.md` binds shared-code changes
to be gated on the mode rather than argued as no-ops.

Secondary risks, all bounded:
- **Font fidelity.** 110 skins ship TTF/OTF and expect specific metrics; text will be the most
  visible source of "not quite right". `CTFontManagerRegisterGraphicsFont` on the skin's own
  bytes, never a system install.
- **Coordinate flips.** Skins2 is top-left origin, macOS bottom-left — the same trap `ui-guide`
  already documents for classic sprites.
- **Corpus rot.** These themes target VLC 0.8–1.x. Expect malformed-but-tolerated attributes
  (`rightbottom="lefttbottom"`, a typo appearing 19 times) — parse leniently, diagnose, never fail.

## 9. Security

The `.wal` sandbox rules apply verbatim and must not be weakened: no host filesystem access
outside the skin's own resource provider, every input bounded (entry count, uncompressed bytes,
compression ratio, **entry path length**, XML depth, image dimensions, frame counts), and typed
failures rather than traps.

Two notes specific to `.vlt`:
- **tar+gzip needs its own bounds.** It has no central directory, so entry count and total
  uncompressed size can only be enforced streaming. Decompression-bomb limits are mandatory.
- **`<include>` and `file=` are path inputs.** Both must resolve inside the archive root with
  `..` and absolute paths rejected — the one skin using `<include>` is not the threat model.

Unlike `.wmz`, there is **no execution ceiling to design**, because there is nothing to execute.
That is the security story in one line, and it is the strongest argument for this format.

## 10. Recommendation

**Proceed, and prefer this over `.wmz` if only one foreign format gets built.** It reaches a
higher fidelity ceiling for less work and carries no scripting-host risk, and the 120-skin corpus
in hand is a ready-made regression suite.

**P0 + P1 is the decision point**: a few days, no product-code commitment beyond a new directory,
and it answers the question that matters — whether a representative spread of these themes renders
recognisably and resizes correctly from the anchoring enum alone. Because there are no expressions
to stub, a correct P1 should look *right*, not approximate; if it does not, the gap is in the
sprite/anchor model and the estimate should be revisited before P2.

A useful cheap addition alongside P0: a `/vlt-skin-report` command mirroring the existing
`skills/wal-skin-report`, dumping tag inventory, unmapped actions, and asset stats for any `.vlt`.

## Appendix: reproducing the analysis

```bash
mkdir -p vlt/x && cd vlt
for f in ~/Downloads/vlc-skins/*.vlt; do
  b=$(basename "$f" .vlt); mkdir -p "x/$b"
  if file -b "$f" | grep -q '^Zip'; then unzip -qo "$f" -d "x/$b"; else tar xzf "$f" -C "x/$b"; fi
done

# container split: 33 zip, 87 gzip
for f in ~/Downloads/vlc-skins/*.vlt; do file -b "$f" | cut -d' ' -f1; done | sort | uniq -c

find x -iname theme.xml > list.txt          # 119
cat $(cat list.txt) > all.xml               # 31,349 lines

# every theme is well-formed UTF-8 XML: 119/119
while read f; do xmllint --noout "$f" || echo "BAD $f"; done < list.txt

grep -ohE '<[A-Za-z][A-Za-z0-9_]*' all.xml | sed 's/<//' | sort | uniq -c | sort -rn  # 20 tags
grep -ohE '[a-zA-Z_]+="' all.xml | sed 's/="//' | sort | uniq -c | sort -rn           # attributes
grep -ohE '(action|action2)="[^"]*"' all.xml | sed -E 's/^action2?="//;s/"$//' \
  | tr ';' '\n' | sed -E 's/\(.*/()/' | sort | uniq -c | sort -rn                     # verbs
grep -ohE 'visible="[^"]*"' all.xml | sort | uniq -c | sort -rn                       # conditions
grep -ohE 'value="[^"]*"' all.xml | sort | uniq -c | sort -rn                         # variables
grep -ohE 'text="[^"]*"' all.xml | grep -oE '\$[A-Za-z]' | sort | uniq -c | sort -rn  # macros
grep -ohE '(lefttop|rightbottom)="[^"]*"' all.xml | sort | uniq -c | sort -rn         # anchoring
grep -ohE 'points="[^"]*"' all.xml | awk -F'\\),\\(' '{print NF}' | sort | uniq -c    # slider curves

# PNG color type byte (offset 25): 2=rgb, 6=rgba
find x -iname '*.png' | head -400 | while read p; do
  python3 -c "import sys;print(open(sys.argv[1],'rb').read(33)[25])" "$p"; done | sort | uniq -c
```
