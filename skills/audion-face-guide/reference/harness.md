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
| `FACE <name> FAILED [AUD####] <message>` | a fatal finding; the block ends |
| `LOAD size=WxH mask=WxH\|none inactiveMask=WxH\|none findings=<n>` | the loaded face |
| `FINDING [AUD####] <message>` | each warning, in the loader's stable order |
| `ELEMENTS buttons=… indicators=… digits=… animations=… text=…` | the roles that survived loading, `-` for none |
| `RENDER-DUMP <label>: WxH ops=<n> [hovered=<role>] [pressed=<role>]` | one per rendered state and tick |
| `PROBE <label> <element> x,y WxH [offset=<px> text=WxH]` | one per draw op, face pixels, top-left; labels add the marquee offset and text image size |
| `PNG <label>: <face>/<file>` or `PNG <label> FAILED <why>` | the dump written, or why not |

## Scripts

All refuse a dirty tree without `--allow-dirty` (a sweep is a build), redirect `swift test` to files
with stderr apart, and leave an `INCOMPLETE` marker that only a finished run removes. Shared helpers
are in `scripts/lib/audion_corpus.sh`. Never capture a baseline with `git stash`; use
`scripts/baseline_worktree.sh`.

| Command | Does |
|---|---|
| `scripts/audion_face_census.sh <out> [--corpus <dir>]` | `census.tsv`: one row per face — sha256, load and fatal code, size, masks, warnings by code, surviving elements, what the six files FaceKit ignores hold, the limits' inputs, and the rev. Prints the tallies and the headroom maxima. |
| `scripts/audion_corpus_baseline.py <census-out>` | Re-records `Tests/NullPlayerAppTests/Fixtures/AudionFace/corpus-baseline.tsv`, the ratchet `AudionFaceCorpusLoadTests` enforces on every `swift test`. Only after improving the loader. |
| `scripts/audion_render_sweep.sh capture <out>` | Renders every face `stopped` and `playing` into `<out>/png`, keeps `invariants.txt`, and fails a capture reporting fewer faces than it was given. |
| `scripts/audion_render_sweep.sh compare <a> <b>` | Diffs two captures' invariant lines, then their images through `scripts/png_diff.py --summary`. |
| `scripts/audion_facekit_reference.sh <out>` | The oracle: FaceKit's own rendering of every face (below). |
| `scripts/audion_oracle_compare.py <oracle-out> <sweep-out>` | Classifies each face against the oracle; writes `<sweep-out>/oracle-compare.tsv`. |

The census digest is SHA-256 over every file in the face, in UTF-8 byte order of its relative path:
the path, a NUL, the contents. `AudionFaceCorpusLoadTests.sha256(of:)` computes the same one.

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
| `text-only` | every pixel past rounding is inside the artist or album box: glyph rasterization |
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
