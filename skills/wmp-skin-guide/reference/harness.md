# The `.wmz` harness — canonical probe reference

**This file is the only place a `.wmz` probe flag or corpus command is documented.** Every other
file, comment and handoff points here and never restates a command. When you add a flag, add it
here in the same change.

Everything below runs headlessly through `swift test`. Nothing here is compiled into the app.

---

## Why the harness exists

Structural and load-time cleanliness measure almost nothing. The `.wal` subsystem paid for that
first: *a vertical-flip and a wrong crop origin survived 490+ green tests because nothing ever
rendered a frame.* `.wmz` reached 6,044 lines of engine with every real-skin test `XCTSkip`ped, so
`swift test` stayed green while 4 of 14 corpus archives were being rejected outright.

So: **you cannot rank work you cannot measure**, and a probe is not trusted about an absence until
it has been shown reporting a presence.

---

## The corpus

Installed skins live outside the repo, matching the `.wal` convention:

```
~/Library/Application Support/NullPlayer/WMPSkins/
```

`WMPSkinImporter.swift` installs there. Archives are never committed; only per-skin `.md` notes are.

**Enumeration rule.** `*.[wW][mM][zZ]`, `-type f`. A bare `*.wmz` drops an upper-case spelling and a
bare `*` picks up directories. Every script **prints the count it measured and never asserts a fixed
one** — the corpus moves, and a document quoting a frozen number goes wrong in a way that looks
right. Each row carries a sha256 so byte-identical archives under two filenames are visible as
duplicates instead of counted twice.

---

## The probe flags

All of them are read by `WMPRenderDumpTests/testSweepsSkinOrCorpus`
(`Tests/NullPlayerAppTests/WMPRenderDumpTests.swift`).

| Flag | Value | What it prints |
|---|---|---|
| `WMP_SKIN` | file **or directory** | the archive(s) to measure — required |
| `WMP_RENDER_DUMP` | directory | one PNG per view; per-skin subdirectory in a sweep |
| `WMP_RENDER_PROBE` | `all` or a view id | `PROBE` — every drawn node's type, id, resolved frame, clip, z, paint and authored attributes; plus a `WIDGET` line per widget — the AppKit-hosted surfaces the scene image does **not** contain |
| `WMP_RENDER_BITMAPS` | `1` | `BITMAPS` — resolved count and every path that failed to load, with `missing=` |
| `WMP_RENDER_SCRIPTS` | `1` | `SCRIPTS`/`SCRIPT` — per program: bytes, declared handlers, and the runtime's availability |
| `WMP_RENDER_EXPR` | `1` | `EXPR` — every `JScript:` geometry expression, its source, both evaluators' values, its dependency order and deps |
| `WMP_CALL_TRACE` | `1` | `CALL`/`CALLS` — every host object-model access with receiver, member, value, and how it resolved: `ok`, `INERT` or `UNRECOGNISED` |
| `WMP_RENDER_CLICK` | `<view>@x,y[;x,y…]`, any entry may be a `>`-joined path | `CLICK` — the object hit, handler count, every attribute changed anywhere in the graph, the host command reached, and the state after. **An entry written `x,y>x,y>x,y` is a drag**: press at the first point, move through the rest, release at the last, with the pointer captured on the object the press landed on. `DRAG` reports the control's direction, range and border, the value and drawn thumb frame at every step, and then the two claims the flag exists to settle — `follows-pointer=yes\|no\|flat` and `thumb-travel=<px>`. `flat` is the one to read for: a value that never moves is trivially monotonic, and a `yes/no` answer alone would call it a pass |
| `WMP_RENDER_APPKIT` | `1` | `APPKIT` — host the scene in the **real `NSView` stack** and report what the AppKit layer adds over the artwork. `outside=` is the number that ranks: an overlay drawing inside its own widget frame is the hosting working, and one drawing anywhere else is the W43 class. `blit=`/`blit-max-delta=` is a second, separate comparison of the renderer's own image against the view's blit of it. Set `WMP_RENDER_APPKIT_DUMP=<dir>` alongside it to write both bitmaps as `<view>-scene.png` and `<view>-hosted.png` when isolating one view |
| `WMP_RENDER_SETTLE` | seconds | run the **view's own timer loop** for that long before measuring — at the period the skin asks for, honouring every `setViewTimerInterval` its handlers post back, rebuilding the scene between ticks |
| `WMP_RENDER_CLOCK` | `<s>[;<s>…]` | seconds into an animation to draw, one PNG per value (suffixed `@t<s>`; a zero clock keeps the original filename). **A render dump is a still, so this flag is the only way an animation is falsifiable** — frame zero is indistinguishable from an engine that never animates. Two pinned values, diffed, are the proof. `ANIMATION <view>: shortestDelay=… bounds=…` reports what the scene actually animates |
| `WMP_RENDER_SIZE` | `<W>x<H>` | `RESIZE` — lay the view out at its **own** size first, run `onLoad` there, then resize to this and re-drive `onResize`, which is the order a user produces. An expression-driven layout is a *different* layout, not the same one scaled. The transaction runs whether or not the view declares an `onResize`, because an expression re-reads `view.width` either way; `handlers=` is how many the changed-object set actually raised, and `handlers=0` with a skin you know authors one means nothing moved |

`WMP_TEST_WMZ` and `WMP_RENDER_DUMP_DIR` are accepted aliases for `WMP_SKIN` and `WMP_RENDER_DUMP`
so the Phase 0–8 handoff docs' invocations still run. Use the names in the table.

One archive:

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/corona.wmz \
WMP_RENDER_EXPR=1 WMP_CALL_TRACE=1 WMP_RENDER_SCRIPTS=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/corona.txt 2>&1
```

**`WMP_SKIN` takes a directory and sweeps it inside one process invocation.** The `.wal` sweep does
79 archives in ~5 minutes where a shell loop over them took 25, and the test-binary startups were
nearly all of the difference. One invocation also cannot be invalidated halfway — a sweep is a
build, and an edit landing mid-loop silently wrote *empty* captures that then diffed as "everything
changed".

A skin that fails to load prints `SKIN <file> FAILED <error>` and the sweep carries on. One broken
archive must not abandon the rest.

---

## The line grammar

Machine-readable, one fact per line, inside a `SKIN <file.wmz>` block. `scripts/wmp_skin_census.sh`
and `scripts/wmp_render_sweep.sh` parse these; do not reword one without updating both.

```
HARNESS <n> archive(s) from <path>
SKIN <file.wmz>
SKIN <file.wmz> FAILED <error>
LOAD definition=<p> encoding=<e> entries=<n> bytes=<n> views=<n> nodes=<n> scripts=<n> resources=<n> loadms=<x>
FINDING [<severity>] <WMP00xx> ×<n> <message>
COMPAT unknown-tags=<n> unknown-members=<n> unknown-events=<n> resources-missing=<n> resources-unsupported=<n>
UNKNOWN tag <name> ×<n>
UNKNOWN event <name> ×<n>
UNKNOWN member <path> ×<n>
SCRIPTS programs=<n> bytes=<n> runtime=<available|unavailable (why)>
SCRIPT <path>: bytes=<n> handlers=[…]
SCRIPT inline: <event>×<n> …
SCRIPT-DIAG <view> [<code>] <message>
RESIZE <view>: <W>x<H> -> <W>x<H>, handlers=<n>
RENDER-DUMP <view>: <W>x<H>, <n> nodes, <c> commands, <h> hits, <w> widgets, <u> unresolved
RENDER-DUMP <view> FAILED <error>
ANIMATION <view>: shortestDelay=<s> bounds=<rect>
WIDGET <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> visible=<f|none>
PROBE <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> z=<n> paint=<…> attrs=[…]
BITMAPS <view>: resolved=<n> missing=<space-separated paths>
EXPR <view>/<id>.<prop> #<order>: <source> -> <static> live=<live> deps=[…]
CALL <view> <path> <read|write|invoke> value=<v> <ok|INERT|UNRECOGNISED>
CALLS <view> <path> ×<n> <ok|INERT|UNRECOGNISED>
CLICK <view>@x,y hit=<id>#<stableID> kind=<k> action=<a> sticky=<b> handlers=<n>
CLICK <view>@x,y changed=[…] | command=<…> | unrecognised=[…] | after: <…> | MISS
DRAG <view>@x,y>x,y hit=<id>#<sid> kind=<k> slider=<b> direction=<d> min=<m> max=<M> border=<b> steps=<n>
DRAG <view>@x,y>x,y step=<i> at=<x>,<y> value=<v> drawn=<v> thumb=<rect>
DRAG <view>@x,y>x,y value <v> -> <v> follows-pointer=<yes|no|flat> thumb-travel=<px>
DRAG <view>@x,y>x,y MISS | not-a-slider — no value tracking to measure
APPKIT <view>: <W>x<H>@<n>x differing=<n>/<n> (<pct>) hosted=<n>/<n> outside=<n> (<pct>) max-delta=<n> blit=<n> (<pct>) blit-max-delta=<n> [worst=<rect>]
APPKIT <view>/<stableID> <kind> id=<id> frame=<rect> differing=<n> (<pct>)
APPKIT <view>: SKIPPED <why>
PNG <view>: <filename>
```

`APPKIT` is the only line that has run an `NSView.draw`. Everything else in this file measures the
scene; this measures the window. Two things make its numbers trustworthy and both were wrong first:

* **The baseline is a second AppKit pass with the overlays hidden, not the renderer's image.**
  `cacheDisplay` composites through the display's colour space and the renderer's context does not,
  so comparing the two directly is a colour conversion as much as a measurement — it read 6.8% of
  Corona (the control skin) as differing, and 61% of a four-colour fixture, at deltas up to 64. Two
  passes through the *same* path cancel that exactly, and the corpus-wide noise floor is then **zero**,
  not "small".
* **Only a widget that actually hosts an `NSView` explains a difference.** `WMPMainView` builds
  overlays for `playlist`, `dropdownPlaylist`, `popup`, `editBox`, `listBox` and `effects` and no
  others — a slider and a text are drawn by the renderer into the image the view blits — so a
  difference inside a *slider's* frame is a defect, not hosting, and attributing it to the widget it
  happens to sit inside would file it as expected. Keep that list in step with
  `WMPMainView.synchronizeWidgetViews`.

The rep comes back at the display's backing scale, not the view's point size, and so does the image
the app presents (`WMPMainWindowController.renderBackingScale`). Indexing a 2x rep in points reads
the top-left quarter and calls it the window; presenting a 1x image into a 2x rep diffs AppKit's
upscaler against the renderer. Both were made on the way to this line and both look exactly like a
defect in the app.

`WIDGET` is the only line about the AppKit overlays — playlist, equaliser, popup, effects, video —
and they are **not in the dumped PNG at all**: the renderer draws the scene, and these are `NSView`s
hosted over it. A skin can therefore dump a perfect frame and look wrong on screen, which is exactly
what happened on 2026-09-07 (W43, W9). `visible=none` means the scene clipped the widget out; the
overlay is positioned from `frame`, so a widget with `visible=none` that still shows on screen is a
defect in the hosting, not in the scene.

`INERT` is a member that is recognised, answers, and has nothing behind it — `theme.loadString` can
only ever return the empty string, because there is no `wmploc.dll` on macOS. It gets its own word
and its own census column (`inert_calls`) because a stub that reads as working is the most expensive
bug this engine can carry; `reference/object-model.md` is the contract.

`EXPR` reports **both** evaluators: `->` is the static grammar in `WMPInitialLayoutExpression` that
the scene builder uses, and `live=` is the value the real script context produced. `live=-` with
`#-` means the live pass produced nothing for that key — usually because the topological sort failed
and no expression was evaluated at all. A skin whose static column resolves and whose live column is
empty is not a working skin.

---

## The two committed scripts

### `scripts/wmp_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--parse-only]`

*What is the state of the corpus?* One TSV row per archive: sha256, whether it loaded, the codes it
was rejected for, encoding, view/node/script counts, findings by code, per-view node/command/hit
counts, resolved and missing artwork, the unimplemented tags and host members it demands, and the
git rev it was measured at. This is the only honest source for the reach numbers in `WMP_TASKS.md`.

`--parse-only` re-derives the TSV from a previous run's logs without paying the sweep again — it is
how a parsing change is checked against a capture that is already known-good.

It also writes two **ranked promotion files**, every run, and names the worst rows on stdout where
the person who ran it is already looking. Both exist because a number the instrument already
measured and nobody ranked is worse than one it cannot see:

* `starved.tsv` — every view by `unresolved / (nodes + unresolved)`, plus `hits == 0` and
  `commands == 0`. **The rule has to be a ratio, not a count** (W70): `unresolved > 0` is true of
  most views in the corpus, so a raw count ranks nothing. Corona — the skin the reporter called
  working — carries 8 unresolved against 66 nodes on `vPlayer`; ALXMorph carries 15 against 15 and
  draws a shell nothing reacts to. A promoted view is one worth dumping and looking at, never a
  defect on its own: `hits == 0` is correct for a view that is pure artwork.
* `appkit.tsv` — every hosted view by how much of the window an AppKit overlay painted **outside**
  any widget frame (W71), with the magnitude of the worst pixel and the separate blit comparison.
  This is the class that produced W43-W46, and it was invisible to every other instrument here.

### `scripts/wmp_markup_census.sh <outdir> [--corpus <dir>] [name ...]`

*How many skins would this element or attribute reach?* One row per name: uses, skins, and the
denominator it measured. It reads the `.wms` files straight out of the archives rather than through
the engine, so it measures **authored demand** and nothing about the result.

It exists because nothing else can see the Class A case that matters most here: **an attribute the
graph parses and the engine then ignores.** That is not an unknown tag, not an unknown member and
not a diagnostic — it is markup that loads cleanly, reports clean, and changes nothing on screen.
Ranking Phase 5's drawing work needed exactly this number, and `fontFace` is the example that pays
for the script: 109 skins author it, 21 author `fontType`, and the builder read only `fontType`.

Two traps it enforces, both of which produced a confident wrong answer first:

- **`grep` goes silent on these files.** A `.wms` is usually UTF-16 and carries bytes `grep` calls
  binary, and a binary file matched with `-o` prints **nothing at all**. The first run of this census
  returned a full table of zeros that read exactly like "the corpus never uses this". Every file is
  stripped to ASCII before it is counted, and `-a` is passed anyway. This generalizes: any ad-hoc
  scan of `.wms` text needs both.
- **A tag spans many lines.** Corpus markup routinely opens `<SLIDER` and closes `>` six lines
  later, so a per-line scan finds neither the attributes nor the tag. Newlines fold to spaces first.

Its denominator is smaller than the sweep's: `unzip` cannot open the two archives whose local header
signature is overwritten (`WMPArchiveHeaderRepair` handles those and `unzip` does not), so a count
here is short by at most two skins and never long. It prints which ones it dropped.

### `scripts/wmp_corpus_exclusions.txt`

The blacklist both scripts read before anything measures. Each script links the in-scope archives
into `<outdir>/corpus` (a hard link, because the harness enumerates with `isRegularFile` and a
symlink is not one) and sweeps *that*, so an excluded skin cannot reach a log, a PNG, or a column —
filtering afterwards would still let its diagnostics rank work. Both print what they dropped and the
count they actually measured; the corpus denominator in `WMP_TASKS.md` is that number, not the
directory listing.

A skin belongs here when no work in this engine changes its outcome — not when it is merely broken.
The standing entry is `Darkling.wmz`, authored against WMP's Party Mode host (`PartyMode.*`), which
this player has no equivalent of; its own `OnLoad` catches the missing host and draws a "designed for
Party Mode" panel, exactly as real WMP does outside Party Mode. Record the reason in the file next to
the entry, and treat removing a line as a decision.

### `scripts/wmp_render_sweep.sh capture|compare`

*Did my change move anything?* `capture` writes the invariant lines **and** every PNG; `compare`
diffs both. Every engine-wide change from Phase 2 onward passes through this.

```bash
git worktree add ../nullplayer-base HEAD
(cd ../nullplayer-base && scripts/wmp_render_sweep.sh capture /tmp/wmp-sweep/base)
# …make the change…
scripts/wmp_render_sweep.sh capture  /tmp/wmp-sweep/curr
scripts/wmp_render_sweep.sh compare  /tmp/wmp-sweep/base /tmp/wmp-sweep/curr
```

**Never capture the baseline with `git stash`** — it relinks `.build` under the user's running app.

---

## Traps the scripts enforce, inherited rather than re-earned

- **A sweep is a build — freeze the tree.** `capture` and the census refuse a dirty tree without
  `--allow-dirty`. A binary that will not compile writes an *empty* capture that diffs as
  "everything changed". Never run either while the user may be building: SwiftPM lock contention
  stalls both.
- **Redirect to a file and grep the file.** Piping a long `swift test` into a filter drops lines
  silently. stderr gets its own file.
- **Every harness line is one `write(2)`, never `print`.** `WMPHarnessOutput.emit` takes a lock,
  flushes stdio so XCTest's own lines stay ordered against ours, and writes the line and its
  terminator in a single unbuffered call. It exists because `print` did not: in the 180-archive
  sweep at rev `171cf89a` a `CALL` line and the `SKIN` line opening the next archive landed inside
  one another (`CALL vSKIN Windows_XP_Media_Center_Edition.wmz`) and the **5,087 bytes** that should
  have followed — the rest of that skin's trace, two `PNG` lines and a `RENDER-DUMP` — never reached
  the file. It was byte-identical across two full sweeps and did not reproduce on a two-archive
  corpus, so it was the buffered stream, not the content: what is lost is whatever `stdout` was
  holding. Removing the buffer removes the loss. Do not reintroduce `print` here.
- **The damage detectors stay, and one of them is arithmetic.** A splice is only the *visible* half
  of a lost write, and the invisible half is the common one: that same run lost three blocks and the
  prefix scan saw **one**, because the splice consumes the record prefix that would have betrayed
  it. So both scripts also check each loaded block's `RENDER-DUMP` count against the `views=` its own
  `LOAD` line declares (a view that fails still emits `RENDER-DUMP <view> FAILED`), and flag a
  second `LOAD` inside one block. **Count distinct view ids, not lines.** A view that lays out and
  then fails to rasterize emits *both* — the stats dump and the `FAILED` one — so when W32 admitted
  `Nautical` (one view, laid out, then `WMP0015` on `vol_slider.bmp`) the arithmetic read 2 against
  `views=1` and called the block damaged when nothing had been lost. Reading a live defect as a lost
  log block is this check's own failure mode, pointed the wrong way, and it survived a solo re-run —
  which is what distinguishes it from a real splice. Damaged skins are listed in `damaged.txt`, get a row carrying
  identity and nothing else, and are left out of the diff. Re-run one alone with
  `--corpus <a directory holding just that archive>`. Their PNGs are unaffected and still compare.
- **Compare pixels, not alpha.** Pillow 9.5 made `getbbox()` on an RGBA image consider the alpha
  channel alone, and every dump carries alpha, so a change that moved a visible control but left
  alpha untouched came back "identical" across 590 `.wal` images. `alpha_only=False` in
  `wmp_render_sweep.sh` is load-bearing, not tidiness.
- **A `maxdelta` of 1** is an LSB rounding difference, not a regression. The script reports the
  number; a human reads it.
- **The alpha trap has a second door: `ImageChops.difference` on RGBA.** `wmp_render_sweep.sh`
  passes `alpha_only=False` and is safe, but an ad-hoc Pillow comparison written beside it is not:
  `getbbox()` on the *difference image* looks at alpha alone for the same reason, so a colour-only
  change reports "identical". During the Phase 5 sweep that scan found 3 changed images where the
  script found 198. Split the bands: `any(band.getbbox() for band in diff.split())`.
- **`SCRIPT inline:` is emitted in dictionary order and is not stable between runs** — the same
  archive reports the same handler tally in a different order each time. It inflates the invariants
  diff with churn that is not a change; open as W64. Until it is fixed, read a large invariants diff
  by what the `RENDER-DUMP`, `BITMAPS` and `LOAD` lines say, not by the line count.
- **A large image diff is read by looking, and by which way it went.** 198 of 545 changed in the
  Phase 5 sweep. Counting the *drawn* (alpha > 8) pixels in each pair and sorting sorts the whole
  set into "changed colour within the same silhouette" and "lost or gained content", and the second
  list was one skin long — which is the list worth opening.

---

## Proving the instrument

*When a probe reports nothing, check the probe can see the thing at all.* Three `.wal` harness blind
spots each made a real defect look absent. Four checks run on every plain `swift test`
(`WMPRenderDumpTests`) and are the reason the corresponding sweep columns can be believed:

| Test | Proves |
|---|---|
| `testRenderBitmapsProbeReportsAMissingAsset` | `BITMAPS` names a deliberately renamed asset — the Class C detector actually notices an absence |
| `testRenderProbeReportsResolvedFramesForEveryDrawnNode` | `PROBE` reports the frame a node was *drawn at*, not the one it was authored with |
| `testExpressionProbeReportsSourceAndResolvedValue` | `EXPR` reports both the source text and the value it resolved to |
| `testUprightCropColorKeyNestedClipZOrderAndBackingScale` | the renderer's own pixels, at 1× and 2× — the check that nothing else in this table substitutes for |
| `testEmitsEveryLineWholeUnderConcurrentWriters` | eight concurrent writers and 9 KB lines all arrive whole and exactly once — the emitter cannot splice or drop a measurement |
| `testAppKitProbeSeesAnOverlayAndReportsNothingWithoutOne` | `APPKIT` in both directions: a scene with nothing hosted over it diffs to **exactly zero**, and a scene carrying a `PLAYLIST` diffs inside that widget's frame and nowhere else. Without the first half, "no defect" and "blind instrument" print the same line |

`compare` was checked the same way on 2026-09-07: a one-pixel **colour-only** change (alpha
untouched) to one dumped PNG and a one-character change to one invariant line, each reported.

**Measuring a transparency key: read the keys out of the markup.** The class W8 counted is scored by
scanning every dumped PNG for *opaque* pixels holding a key colour and reporting any view over 5% of
its area — a census column cannot see it, because a view that draws its key is structurally perfect.
The trap is assuming which colour that is. A magenta-only scan gave 23 views across 21 skins; adding
`#FF0000` gave 37 across 34, with 11 views pure red and no magenta at all. Neither is the rule.
**Score against the set of colours each skin's own `.wms` declares** — `clippingColor` and
`transparencyColor`, both of which a single node commonly carries with *different* values — and
never against a hard-coded palette. Closing W8 under that rule leaves **28 views across 26 skins at
or above 5%**, and every one of them is now a different defect (see W48): artwork whose flat colour
is keyed nowhere in the markup, or a `BUTTONGROUP` blitting its whole sheet.

**Proving `WMP_RENDER_CLOCK` itself.** It was checked the way the table above demands, before any
claim was made from it: `Xbox Live Skin` (whose `intro_anim.gif` is 145 frames) dumped at 0, 1.5 and
3 seconds gives three different images — 4,475 pixels change between the first two and 3,917 between
the second two — and the logo visibly moves. A flag that reported the same PNG three times would
have looked exactly like a working one on the `ANIMATION` line alone.

**Proving the drag probe.** Same rule, and its negative answers are reachable: a drag along Corona's
horizontal volume slider (`vPlayer@415,318>430,318>450,318>475,318`) gives `value 0 -> 100
follows-pointer=yes thumb-travel=48`, and its vertical `eq1` (`286,250>286,230>286,200`) gives
`-14 -> 14 follows-pointer=yes thumb-travel=34` — both axes, value and drawn thumb tracking
together. A drag that never leaves its start point reports `follows-pointer=flat thumb-travel=0`,
and one that starts on a button reports `not-a-slider`, so a mis-aimed probe reads as mis-aimed
rather than as a passing slider. The handler lookup goes through
`WMPMainWindowController.handlers(in:event:…)` — **the app's own matcher, never a second one**: 175
of 179 archives author `value_onchange` rather than `onChange`, and a private lookup here would
report every one of those sliders as having no handler.

**Three things a clean sweep does not prove.** It measures the default state and nothing else — not a
tab, a setting, a drag, a hover, or anything driven by live playback. A structural probe is not a
picture: a node existing says nothing about where it is drawn. And **a correct dumped frame is not a
correct window**: the AppKit overlays, the window's shape and its shadow, and every repaint decision
live outside the renderer. On 2026-09-07 the headless `vPlayer` and `viewTiny` frames were correct in
every state tested while the live app showed a dark box the size of the window, drawers that were
never erased, and a black panel during playback. Only the reporter driving the app found any of them.

`WMP_RENDER_APPKIT` (W71) closes the *overlay* part of that third gap and none of the rest. Window
shape and shadow live in the window server and stay a short, genuinely manual list; so do hover, a
tab, a setting and live playback.

---

## What the harness measured on 2026-09-07 (14-skin corpus, rev `055063ed`)

Recorded here because it **contradicts the recovery plan's inherited hand measurement**, which came
from the branch's own phase handoff docs. Those docs are unverified narrative — phase 7 asserts a
release capability gate that its own `AppCapabilities.swift` does not implement — so check every
number from them against the code before relying on it. This is census output.

| Claim in the plan | Census |
|---|---|
| 4 of 14 archives load | **10 of 14 load** |
| 7 of 10 rejections are `WMP0025` (text encoding) | **0 encoding rejections.** The decoder already resolves the corpus: utf16LE ×11, windows1252 ×2 |
| 3 of 10 rejections are `WMP0027` (duplicate attribute) | **all 4 rejections are `WMP0027`** — Alpine7618_v09, anemone, Official_Xbox_XP, The Unit, exactly the four skins measured as carrying duplicate attributes |

So the whole of the Tier-1 loading blocker was the lenient-XML-parser work (`W2`), and the decoder
work (`W1`) was not ranked ahead of it. Two further clusters the census surfaced, which the plan had
folded into later phases:

- **`WMP0032`, 7 views across 5 skins** — "View requires positive literal width and height for
  static layout". A view whose size is computed in script renders nothing at all, which is why
  `claw.wmz` and `iconic.wmz` load cleanly and produce **zero** layouts.
- **`WMP0024`, 2 views** — an *empty* resource attribute rejected as "absolute, drive-qualified, or
  invalid", killing the whole view.

Every count above carries the corpus it was measured against. Do not rewrite an old numerator
against a new denominator.

## After Phase 2 (14-skin corpus, rev `733d3631`)

`load ok=14`. The four `WMP0027` rejections are gone; see `reference/loading.md` for what replaced
the parser and what it now tolerates. Re-measured against the **new 14-archive denominator**, so
these are not comparable line-for-line with the numbers above:

| | rev `055063ed` (10 loading) | rev `733d3631` (14 loading) |
|---|---|---|
| archives loaded | 10 | **14** |
| rejections | 4 × `WMP0027` | **0** |
| `WMP0032` blacked-out views | 7 across 5 skins | 9 across 6 skins |
| `WMP0024` killed views | 2 | 3 |
| `WMP0034` duplicate attributes | — (the code did not exist) | 19 across 4 skins |
| render dumps | 18 PNGs | 25 PNGs |

**What the sweep proved about collateral damage.** All 18 pre-existing PNGs are byte-identical. The
only invariant lines that moved are diagnostic *locations*, and they moved because the new parser
points at a tag's opening `<` where libxml2 reported the position the tag ended at — verified by hand
against `corona.wms`, where `svTop` opens on line 42 and its closing `>` is on line 46. Nothing else
in any block changed: no counts, no node ids, no bitmap resolution, no layout shapes.

**Two Class B defects became visible only because the skins now load** — a probe cannot see a defect
in a skin it rejects, and neither can you:

- `Alpine7618_v09/view-2@1x.png` renders its art in the lower ~150 px of a 517×412 view and flat
  `#FF00FF` everywhere else: the transparency key is not applied to the uncovered background (`W8`).
- `Official_Xbox_XP/mainBox@1x.png` has `WMPWidgetViews`' opaque black `VIDEO` placeholder painted
  over the skin's own artwork (`W9`).

Both were found by *looking at the PNGs*. The census reports both skins as clean loads with resolved
bitmaps, which is exactly the blind spot the harness notes warn about: a structural probe says a node
exists, never that it is drawn right.

## After Phase 3 (180-archive corpus, rev `c8a843e4`)

The script runtime became one persistent `JSContext` per skin session. Loading did not change and
was not expected to; what changed is what runs after it. The census's default pass now drives each
view's own `onLoad`, the way the app does — a harness that skipped it was measuring a skin nobody
sees.

| | rev `ada068ff` | rev `c8a843e4` |
|---|---|---|
| archives loaded | 171 of 180 | 171 of 180 |
| views laid out | 482 | 482 |
| paint commands | 9,120 | **9,186** |
| widgets | 1,396 | **1,436** |
| unresolved nodes | 2,393 | **2,352** |
| `expression-error` corpus-wide | every expression in most skins | **1**, plus 8 `invalid-geometry` |
| distinct `UNRECOGNISED` members | (not comparable — measured statically) | **6** |

`compare`: **442 images identical, 40 differing, none lost, none new.** Every difference is script
state now being applied, and they were looked at rather than counted: `Plus! Aquarium/view-2` went
from a **blank page** to the whole skin; `WoW/videoView` gained the logo its `onLoad` sets;
`Grinch/view-2` and `Plus! SlimLine/perfectVSkin` *lost* pixels because their scripts hide a video
pane and a stray close box when nothing is playing, which is what WMP does.

The remaining 228 handler errors are ranked in `WMP_TASKS.md`, and 102 of them are one missing host
object (`mediacenter`).

---

## After Phase 6 (179-archive corpus, rev `824261d4` + the Phase 6 change)

Phase 6 is where the corpus tooling stops being a description of the corpus and starts ranking work
by itself. Three instruments and one capability landed; every number below is
`scripts/wmp_skin_census.sh /tmp/wmp/census`, measured 2026-09-08 over 179 archives and **607 views**.

**What the instruments found on their first run.**

* **Starvation (W70).** 41 views across 36 skins resolve less than half the nodes they declare;
  79 views across 49 skins have no hit target at all; 65 across 37 draw no command. The worst are
  not the ones anybody had named: `Disney_Mix_Central/mainView` resolves **2 of 25**,
  `Batman Begins/mainView` 2 of 21, `Alienware Invader/mainView` 2 of 20, and
  `Cablemusic/mainview` 35 of 98. ALXMorph — the skin live QA reported as dead — sits at exactly
  0.50 and is one of the *milder* cases. The ranking is in `starved.tsv` every run.
* **AppKit hosting (W71).** 545 of the 607 views were hosted through the real `NSView` stack and
  diffed. **Exactly two paint outside any widget frame** — `Revert.wmz` and `Revert (1).wmz`, both
  releases of the same skin, `vwPL`, 4,000 px at delta 196, in a 250x4 band at `3,256` where the
  playlist overlay's frame (`3,14 250x257`) runs past the 260-tall view's own bottom edge. That is
  the entire W43 class in the corpus's default state, and it is one defect in one skin. The
  reporter's "tons of issues" are therefore, on this evidence, mostly *scene*-side (the starvation
  class above) or driven by something a default-state sweep still cannot reach.
* **Drag (W72).** Every slider in the corpus is now drivable headlessly. See *Proving the drag
  probe* above for the two worked axes.

**What one capability change drained.** `value_onchange`, `OpenState_onchange` and
`PlayState_onchange` are WMP's other spelling for three events the engine already dispatches, and
the corpus writes them by an order of magnitude more than the spellings that worked: 175 of 179
archives, 144 and 139, against 11 and 7. Accepting both spellings in the one matcher every dispatch
site already goes through took measured event demand from **6,823 uses to 4,114** — 2,709 uses, 40%
of everything the corpus asks for in this class, in one change with no new dispatch site. It also
removed a phantom `UNKNOWN member player.settings.volume = value;updatevoltooltip()`, which was a
handler body being read as a member path.

`scripts/wmp_render_sweep.sh compare` across the change: **545 images identical, 0 differing, 0 lost,
0 new**, and 2,070 green tests. The distinct-event vocabulary reads 140 → 142 rather than 140 → 137;
36 blocks were damaged in both captures (W35), so the edges of that vocabulary move between runs and
the *uses* figure is the one to quote.

**What Phase 6 did not touch.** Everything the ranked lists now point at. Draining A/C/D
automatically was the job; the lists are the output, not the fixes.
