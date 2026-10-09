# Audion face harness

Read `../SKILL.md` first; its isolation rule binds every section here.

**This is the only file that documents an `AUDION_*` flag, a corpus command, or a measured
number.** A flag or script is added here in the same change that adds it. Every number sits next to
the command that produced it.

## The corpus

- Installed faces: `~/Library/Application Support/NullPlayer/AudionFaces/<face>/`;
  `AUDION_CORPUS_PATH` overrides it for every script and for `AudionFaceCorpusLoadTests`. Faces are
  never committed. Seed it by copying Panic's 2021 distribution there (856 face folders).
- A face is any folder containing `index.json`. Folder names carry leading and trailing spaces and
  characters like `™` and `∆`, so quote every path.
- `scripts/audion_corpus_exclusions.txt` lists faces kept out of the measured corpus (empty). Faces
  are folders and cannot be hard-linked into a farm the way `.wmz` archives are, so the scripts write
  the in-scope folders to `<out>/faces.txt` and hand the harness that list.

## The harness

`Tests/NullPlayerAppTests/AudionFaceRenderDumpTests.swift`, `testSweepsFaceOrCorpus`. It skips unless
`AUDION_FACE` is set, draws through `AudionFaceScene` and `AudionFaceRenderer` — the path the face
window uses — and writes every line through `HarnessOutput.emit` (`Tests/NullPlayerAppTests/HarnessOutput.swift`,
shared with `.wmz`), never `print`. Nothing it runs reads `UserDefaults`, so it uses no suite.

```bash
AUDION_FACE="$HOME/Library/Application Support/NullPlayer/AudionFaces/Beam" \
AUDION_RENDER_DUMP=/tmp/audion AUDION_RENDER_STATE=playing \
  swift test --build-system native --filter AudionFaceRenderDumpTests/testSweepsFaceOrCorpus
```

### Probe flags

| Flag | Value | Effect |
|---|---|---|
| `AUDION_FACE` | a face folder, a corpus root, or a list file | Which faces to measure. A root is walked for every folder holding `index.json`; a list file names one face folder per line. |
| `AUDION_RENDER_DUMP` | output directory | Writes `<dir>/<face>/<label>.png`. |
| `AUDION_RENDER_STATE` | comma list of `stopped`, `playing`, `paused`, `connecting`, `streaming`, `lag` | The host states to render (default `stopped`). Every non-stopped state is the oracle's playing state — 1:23 into 3:33, fixed title/artist/album/format, no track index — with the stream phase named. |
| `AUDION_RENDER_CLOCK` | comma list of 60 Hz ticks | One image per tick: the animation frame and the album marquee. **Setting it turns Reduce Motion off**, since a clock run asks for motion; without it every state pins Reduce Motion on, as the oracle does. |
| `AUDION_RENDER_HOVER` | `x,y` in face pixels, top-left | Hovers the topmost visible button under the point. |
| `AUDION_RENDER_CLICK` | `x,y` | Presses it. |
| `AUDION_RENDER_SCALE` | 1–4 | Integer scale; text re-rasterized at that size. |
| `AUDION_RENDER_PROBE` | any | One `PROBE` line per draw op. |

The image label is `<state>[-f<tick>][-hover][-click][@<n>x]`; the canonical sweep's are `stopped`
and `playing`.

### Line grammar

One fact per line, inside a `FACE` block.

| Line | Meaning |
|---|---|
| `HARNESS <n> face(s) from <path>` | the run |
| `FACE <name>` | opens a face's block; every face prints exactly one |
| `DIGEST <sha256>` or `DIGEST FAILED <why>` | the census digest (below), before the face loads |
| `FACE <name> FAILED [AUD####] <message>` | a fatal finding; the block ends |
| `LOAD size=WxH mask=WxH\|none inactiveMask=WxH\|none findings=<n>` | the loaded face |
| `FINDING [AUD####] <message>` | each warning, in the loader's stable order |
| `ELEMENTS buttons=… indicators=… digits=… animations=… text=…` | the roles that survived loading, `-` for none |
| `PALETTE authored=<album>/<artist> ground=… text=… current=… selection=… selected=… text/ground=… current/ground=… selected/selection=… selection/ground=… overruled=…` | `AudionFacePalette.surfaceStyle(for:)` as hex roles (`authored` is `AudionFacePalette.roles(for:)`'s text and current text — the face's own colours, or the neutral ones with no display), the four contrasts NullPlayer's windows depend on, and which of those roles the style's `legible` replaced (`text`, `current`, or `-`) |
| `RENDER-DUMP <label>: WxH ops=<n> [hovered=<role>] [pressed=<role>]` | one per rendered state and tick |
| `PROBE <label> <element> x,y WxH [offset=<px> text=WxH]` | one per draw op (`AudionFaceDrawOp.Element`'s description), face pixels, top-left; labels add the marquee offset and text image size |
| `PNG <label>: <face>/<file>` or `PNG <label> FAILED <why>` | the dump written, or why not |

## The live app

Launch the debug build on an installed face with app-control's one command; it kills any running
NullPlayer, so say so first. `-audionFacePath <folder>` is what it passes: an installed face is
selected in place, anything else is installed first.

```bash
skills/app-control/scripts/launch.sh "audion:Black Bar"   # LAUNCH PASS: audion skin 'Black Bar' …
```

| Env var (DEBUG and release) | Effect |
|---|---|
| `AUDION_PLACE_TRACE=1` | Logs `[place/tile] hosted <frame>` each time the shared tiler places one of NullPlayer's windows beside a face (`WindowManager.positionSubWindow`). |

`skills/app-control/scripts/skin-mode-switch-test.sh` runs `.wmz → Audion → Audion' → Classic`
at the end of its chain; `skin-pick-matrix.py` picks AppleClassic and Agitator; `window-census.sh`
takes `audion`. Long face lists are A–Z submenus, which `menu.applescript`'s `skin` and `current`
verbs reach into.

## Scripts

All refuse a dirty tree without `--allow-dirty` (a sweep is a build), redirect `swift test` to files
with stderr apart, and leave an `INCOMPLETE` marker that only a finished run removes. Shared helpers
are in `scripts/lib/audion_corpus.sh`. Never capture a baseline with `git stash`; use
`scripts/baseline_worktree.sh`.

| Command | Does |
|---|---|
| `scripts/audion_face_census.sh <out> [--corpus <dir>]` | `census.tsv`: one row per face — the harness's `DIGEST`, load and fatal code, size, masks, warnings by code, surviving elements, what the six files FaceKit ignores hold, the limits' inputs, and the rev. Prints the tallies and the headroom maxima. |
| `scripts/audion_corpus_baseline.py <census-out>` | Re-records `Tests/NullPlayerAppTests/Fixtures/AudionFace/corpus-baseline.tsv`, the ratchet `AudionFaceCorpusLoadTests` enforces on every `swift test`. Only after improving the loader. |
| `scripts/audion_render_sweep.sh capture <out>` | Renders every face `stopped` and `playing` into `<out>/png` with `AUDION_RENDER_PROBE` on, keeps `invariants.txt` (`PALETTE` lines included, so a palette change diffs) (`PROBE` and `DIGEST` lines stay in `raw.txt` only), and fails a capture reporting fewer faces than it was given. |
| `scripts/audion_render_sweep.sh compare <a> <b>` | Diffs two captures' invariant lines, then their images through `scripts/png_diff.py --summary`. |
| `scripts/audion_facekit_reference.sh <out> [--corpus <dir>]` | The oracle: FaceKit's own rendering of every face in the sweep's face list, exclusions applied (below). |
| `scripts/audion_oracle_compare.py <oracle-out> <sweep-out>` | Classifies each face against the oracle, taking the text boxes from the sweep's `PROBE … label:` lines (so the loader is the only reader of `index.json`; a capture without them is refused); writes `<sweep-out>/oracle-compare.tsv`. |

The census digest is SHA-256 over every regular file in the face, in UTF-8 byte order of its
relative path: the path, a NUL, the contents. `AudionFaceHarness.digest(of:)` is its one definition:
the harness prints it and `AudionFaceCorpusLoadTests` keys the ratchet with it.

## The oracle

`scripts/audion_facekit_reference.sh` clones FaceKit at the pinned `5b7c847` into
`$AUDION_FACEKIT_CACHE` (default `~/Library/Caches/NullPlayer/facekit`), compiles
`AudionFace.swift`, `AudionFaceView.swift` and `AudionSliderWindow.swift` **unmodified** beside a
headless `main.swift` the script writes, and runs one process per face (FaceKit traps on some hostile
input; a trap costs that face, not the run). It renders the canonical states: stopped (FaceKit's
`stop()`), and playing at 1:23 of 3:33 with the harness's fixed text, `enableAllButtons` and every
`supports…` true, and Reduce Motion pinned on by swizzling `NSWorkspace`. Output is never committed.

Three Core Animation facts the host works around, each found by an oracle that disagreed with
itself — **re-check them before trusting a change to the host**:

1. **FaceKit's backing layer never displays headless.** Its base and animation are drawn by its own
   `draw(_:in:)` for `self.layer`, which only a window server calls. The host calls that method and
   puts the result in a sublayer beneath all others, where the backing layer's contents sit;
   `cacheDisplay(in:to:)` and assigning the backing layer's `contents` both drew no base at all.
2. **`render(in:)` applies `mask` now**, though its documentation says it does not. Applying
   FaceKit's mask again by hand squared it (alpha 226 → 200, 226²/255) on every semi-transparent edge.
3. **`render(in:)` composites siblings in array order and ignores `zPosition`**, which the screen
   honours. FaceKit relies on it: digits and indicators (its `sublayer`, zPosition 2) draw over the
   buttons (1) though the buttons are added after; labels are 10. The host sorts the siblings by
   zPosition before rendering. 88 of the 856 faces have a button rect overlapping a digit or
   indicator rect, so the order is visible there.

### What the comparison means

`audion_oracle_compare.py` compares premultiplied pixels. Per face, the worst state's verdict:

| Verdict | Meaning |
|---|---|
| `identical` | every byte equal |
| `rounding` | no premultiplied channel off by more than 1 — compositing arithmetic: Core Animation composites FaceKit's layers in 16-bit backing stores, the renderer in 8 bits. Compared un-premultiplied, a 1-level step at alpha 8 reads as 32 levels, which is why the metric is premultiplied |
| `text-only` | every pixel past rounding is inside a label box the sweep drew: glyph rasterization |
| `geometry` | a pixel past rounding outside the text boxes — a defect, or a listed departure |
| `missing` | one side has no image |

The comparison renders with no track index, at 1×, so the track-digit and mask-scaling departures
(decision record § *Deliberate departures from FaceKit*) never enter it.

## Measured

At the commit that closed A3 (2026-10-08), over the 856 faces of Panic's 2021 distribution:

| Command | Result |
|---|---|
| `scripts/audion_face_census.sh` | 856 faces, 856 load, 0 fatal. Warnings: `AUD0008` 13, `AUD0009` 1,080, `AUD0013` 1,515. 20–27 s. |
| `scripts/audion_render_sweep.sh capture` ×2, then `compare` | 856 faces, 8,601 invariant lines, 1,712 images per capture; the two captures **identical** (lines and images). ~29 s each. |
| `scripts/audion_facekit_reference.sh` | 856 rendered, 0 refused, 0 died; 19 s on all cores. |
| `scripts/audion_oracle_compare.py` | **856/856 geometry-identical**: identical 484, rounding 371, text-only 1 (`subzero`, playing: its album and artist boxes overlap by a row, and only its glyphs differ), geometry 0. |
| `swift test --build-system native` | 3,007 tests, 19 skipped, 0 failures; `AudionFaceCorpusLoadTests` 856/856, 0 unranked, ~5.5 s. |
| Phase 6 re-check (A8) | Census identical in tallies and headroom; the sweep identical to `93ff3dd4` (9,457 lines, 1,712 images, every `PROBE` line); oracle 856/856 geometry-identical (484 / 371 / 1 / 0); `swift test` 3,034, 19 skipped, 0 failures. |

Limit headroom, from the census (`headroom` lines; images over every PNG, not only decoded ones):

| Limit | Bound | Corpus maximum | Face |
|---|---:|---:|---|
| `AUD0003` `index.json` | 256 KiB | 4,561 B | Audion XP 1 |
| `AUD0004` side | 4,096 px | 1,600 px | Black Bar |
| `AUD0004` image on disk | 8 MiB | 613,876 B | Jack&Sally |
| `AUD0005` entries | 2,000 | 257 | Puffhookah v.1.0 |
| `AUD0005` bytes | 64 MiB | 4,094,887 B | Matrix |
| `AUD0011` pixels | 64 Mpx | 5,368,982 | Escher∆ |

Median face: 355,603 px. What the census found in the files FaceKit ignores is
`format.md` § *Files FaceKit ignores*; the counts behind it are the census's `window_vs_mask_iou`,
`drag_in_window`, `inactive_vs_base`, `active_alpha`, `about` and `icon` tallies.

### Redraw cost (A8, 2026-10-09)

Per tick with the album marquee scrolling, debug build, from a throwaway test timing 120 ticks of
`AudionFaceCanvas.draw` (before: a full `AudionFaceRenderer.render`). Scale is device pixels per face
pixel, so 6 is UI Size 300% on a retina display.

| Face (base) | Scale 2 | Scale 4 | Scale 6 |
|---|---:|---:|---:|
| Izam (288×185, the median) | 1.17 → 0.09 ms | 3.80 → 0.15 | 8.47 → 0.25 |
| DeepBlue (487×275, p90) | 2.64 → 0.10 | 9.63 → 0.21 | 21.33 → 0.38 |
| Been Hexxed? (800×600, the largest) | 8.01 → 0.38 | 32.09 → 1.38 | 72.03 → 3.06 |

Live, debug build, playing, `top -pid` over 5 s: Been Hexxed? 15% at 100%, 30% at 200%, 50% at
300%; AppleClassic ~11% at 100%, ~17% at 300%. Before the view drew through `draw(_:)`, Been
Hexxed? ran 28 / 68 / 95%: `sample` put 1,953 of 2,557 main-thread samples in Core Animation copying
and colour-converting the whole new `layer.contents` image every tick. What remains at 300% is
CoreGraphics compositing the album box (760×37 face pixels, 1 Mpx at scale 6). Nothing past these
algorithmic fixes was optimized. Release builds show faces since A9, but no release profile has been
taken: release has no auto-play hook and `menu.applescript` cannot set UI Size, so it needs the user
to play a track at 300%. Take one before optimizing further.

### Palette legibility (A7, 2026-10-09)

From the sweep's `PALETTE` lines over all 856 faces (a throwaway tally over `invariants.txt`):

| Contrast | Minimum | Median | Guarded by |
|---|---:|---:|---|
| text / ground | 3.00 | 8.98 | `legible`, 3.0 |
| current text / ground | 3.04 | 9.06 | `legible`, 3.0 |
| selected text / selection | 3.01 | 6.27 | `legible`, 3.0 |
| selection / ground | 1.31 | 2.41 | the palette's `legible(threshold: 1.3)` |

`overruled` (the guarded style against `roles(for:)`): of the 764 faces with a real display, none
476, both 143, current only 16, text only 5 — the faces' own low-contrast pairs (Cracked's pale
yellow and green on white), not sampling errors. The 92 without one wear the neutral roles, which a
light ground overrules (both 35, text only 5). 27 selections fall back to black or white. Before the
A7 fixes, 89 faces had a selection under 1.3 against the ground (down to 1.00) and 85 sampled a 1×1
placeholder display's corner pixel.

The line is deterministic: `dominantColor` breaks a bucket tie by key. Before the A7 review it broke
ties in `Dictionary` order, seeded per process, so a tied face (Contragravity, gayheart, Time) got a
different palette from one run — or launch — to the next. Two captures of one tree must give
identical `PALETTE` lines; a difference is a defect.

`Tests/NullPlayerAppTests/Goldens/AudionFace/palettes.tsv` pins the line for six faces
(`AudionFacePhase5Tests.testPaletteGoldens`, skipped without the corpus); re-record with
`AUDION_PALETTE_GOLDEN_UPDATE=1` and read the diff.

## What the sweep raises

- **A diff between two captures is unclassified.** Run the oracle comparison on the new capture
  before calling it a regression or a fix; a `geometry` verdict is a defect unless it is a listed
  departure, and each one gets an `A###` row or a dossier in `skins/`.
- **A sweep proves the canonical states only.** Hover, press, the marquee, an animation and scale
  need the probe flags; a byte-identical sweep across a change to any of them is unmeasured.

## Debugging a live defect

The process is `skills/live-ui-testing`. The engine-specific half is `../SKILL.md` § *Debugging a
live defect*: oracle first, then the renderer's image against a capture of the window, using the
flags above to reproduce the state.
