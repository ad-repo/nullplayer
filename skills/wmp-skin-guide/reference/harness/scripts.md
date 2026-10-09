# `.wmz` harness: the committed scripts

Moved verbatim from `reference/harness.md` on 2026-09-25; that file is the router. Read it first.

## The committed scripts

### `scripts/wmp_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--parse-only]`

*What is the state of the corpus?* One TSV row per archive: sha256, whether it loaded, the codes it
was rejected for, encoding, view/node/script counts, findings by code, per-view node/command/hit
counts, resolved and missing artwork, the unimplemented tags and host members it demands, and the
git rev it was measured at. This is the only honest source for the reach numbers in `WMP_TASKS.md`
**for anything a view reaches on load**.

**It drives `onLoad` and nothing else, and that bounds every demand number it produces.** A member
called from an `onClick` is invisible here, so a row ranked on this alone is ranked on the subset
of the corpus that runs before the user touches anything: `view.returnToMediaCenter` counted **7**
and is authored by **162 of 180 archives** (W100), and W136's click-handler methods (`copy`,
`deleteSelected`) were ranked on the same blind spot. When a row is about a *control*, the census gives you a floor and `harness/live-loop.md` § *Auditing one authored
control across the whole corpus* gives you the number.

`--parse-only` re-derives the TSV from a previous run's logs without paying the sweep again — it is
how a parsing change is checked against a capture that is already known-good.

**Check `render.txt` is non-empty before believing a single number out of a capture.** The script
exits **0** on a run that was killed part-way through its own `swift test`, leaving an output
directory that looks exactly like a successful one — `corpus/`, `render.txt`, `render.stderr.txt`
— with `render.txt` at zero lines and no `census.tsv`. Reproduced twice on 2026-09-11 by starting
it detached (`nohup … &`): `render.stderr.txt` ends mid-build (`[1/6] Write swift-version…`), not
after it. The script's header already warns that *a binary that will not compile* writes an empty
capture that diffs as "everything changed"; **a killed run is the same failure with a clean exit
status**, which is worse, because nothing anywhere says so. **Both corpus scripts now write
`<outdir>/INCOMPLETE` when they start and remove it only on reaching `done`** (2026-09-24);
`--parse-only` and `wmp_render_sweep.sh compare` refuse a directory that still carries it, so a
killed run is a refused capture rather than a plausible one. Anything else that reads a capture
should check for the file too. Still run it in the foreground: the marker catches a killed run, it
does not prevent one. A capture from before 2026-09-24 has no marker either way — for one of those,
`wc -l <outdir>/render.txt` and the presence of `census.tsv` are still the check.

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

### `scripts/wms_grep.py [-i] [-l | -c] [--ext wms,js] [--corpus <dir>] <regex>`

*Which archives' markup or script says this?* A regex over every `.wms`/`.js` entry, decoded the way
`WMPTextDecoder` reads it, with the header repair `zipfile` needs for the two `01 00 01 00`
archives and the exclusions applied. Default output is `archive/entry:line: text`; `-l` lists
archives, `-c` counts per archive. It **always** ends with a stderr line giving matches, entries,
archives matched *of archives scanned*, the encoding breakdown, and anything unreadable — a count
without its denominator is what it exists to replace. Checked 2026-09-24 against W266's scan
(`event.keycode =` → the same 3 archives, and it also read the two `.wms` that scan could not) and
against `wmp_markup_census.sh` (`<EQUALIZERSETTINGS` → 163 of 179 against 161 of 177, the difference
being exactly the two archives `unzip` cannot open). Use `wmp_markup_census.sh` for a tag or
attribute tally; use this for everything else — a member name, a handler body, a literal.

The decoding, header repair and exclusion reading live in `scripts/wmp_corpus.py`, and
`wmp_handler_scope_census.py` imports them from there; a new Python corpus scan should too.

### `scripts/wmp_control_audit.py [--render <render.txt>] [--sample N] [--skin <archive>] [-v] <member>`

*Which authored controls reach this member, and where is each one clicked?* `harness/live-loop.md` § *Auditing one authored
control across the whole corpus* as one command (W267). Steps 1–2 need nothing but the corpus and
take ~2 s: every handler attribute resolved through the skin's functions to three levels, with the
counts by tag, handler, tooltip and "in the first `<VIEW>`", and the encoding breakdown as
calibration. Steps 3–5 need a probe capture, which **the census does not contain** — it never sets
`WMP_RENDER_PROBE` — so without `--render` the script prints the sweep that makes one (~35 s for the
corpus once the tests are built; a directory handed to `WMP_SKIN` must hold copies — the sweep
skips symlinks and reports "No .wmz archives"). `-v` prints one row per control with its point and where the point
came from; `--sample N` prints the `WMP_RENDER_CLICK` + `WMP_CALL_TRACE=1` runs.

**Trust the point by its source column.** Checked 2026-09-25 by clicking every located W100 control
(`returnToMediaCenter`, 199 controls in 165 of 179 archives — the raw `wms_grep.py` count, exactly):

| source | hit the control |
|---|---|
| `probe` — a drawn node's frame centre | 55 of 55 |
| `mapping` — a drawn group's bitmap, median pixel of the colour | 74 of 76 |
| `authored`, `authored-mapping` — the authored `left`/`top` chain | **26 of 65** |
| `none (<why>)` — colour absent from the bitmap, or the bitmap absent from the archive | 3, all real skin defects |

The authored fallback is what step 4 prescribes and it is right less than half the time: it cannot
see alignment, script moves, hidden groups or views the sweep never dumps. The script prints it
flagged unverified and never samples it. The two `mapping` misses are `digitaldj` (its script
disables the transport until the splash is dismissed) and `Plus!_The_Bionic_Dot`, whose
`main_blue_set_map.png` holds `#0066FF` where the click lands and whose group still reports
`unmapped-pixel` — unexplained as of this writing. **W100's own 162/180 is not reproducible**: five
archives joined the corpus after it closed (`Ovoid` and `Raptor` author the button) and `Darkling`
(one control) is now excluded.

### `scripts/png_diff.py <a> <b>` / `<base-dir> <curr-dir> [--summary] [--top N]`

*Which way did this image change?* Per differing pair: `lsb` (maxdelta ≤ 1), `recolour` (alpha band
identical — same silhouette), `moved` (same drawn-pixel count, alpha changed), `gained`/`lost`
(drawn pixels, alpha > 8, went up or down), `size`. It compares every band separately, so neither
Pillow alpha trap below applies. Tree mode prints the same totals as `compare`; `--summary` adds
per-skin counts and lists only `lost`, `gained` and `size`. `wmp_render_sweep.sh compare --summary`
calls it. Exits 1 when anything differs.

### `scripts/baseline_worktree.sh [<dir>] [<rev>]`

The baseline for any before/after pair — see `harness/sweep-limits.md` § *A baseline worktree needs the vendored frameworks
linked in*.

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

### `python3 scripts/wmp_slider_drag_census.py [--corpus <dir>]`

The three W256 populations in one pass, over the installed corpus minus the exclusions:

- **A** — elements authoring a handler and **no `id`** (1,667 nodes / 101 archives), and the
  `value_onchange` subset (70 / 35). These are the handlers that used to run with no bound `value`
  and no element scope; the defect has no signature but the *argument* a host command carries.
- **B** — sliders painting a **thumb and no track** (448 / 41), whose hit region used to be the
  knob. `<CUSTOMSLIDER>` is excluded: its `positionImage` is the authority on its region (W150).
- **C** — archives whose `<EQUALIZERSETTINGS>` is named something other than `eq` (7).

It reads each `.wms` out of its archive rather than grepping it, which is the whole reason it is
committed — see `harness/corpus.md` § *A corpus number taken with `grep` is not a corpus number*. Re-run it before
quoting any of the four numbers.

### `python3 scripts/wmp_implicit_key.py [--corpus <dir>] [--color RRGGBB] [--tsv <file>] [--alpha only|none|any]`

*How much artwork relies on WMP's implicit transparency colour?* Counts drawn sprites that hold
opaque `#FF00FF` pixels and hang off a node declaring neither `transparencyColor` nor
`clippingColor` — the W78 class, and the measurement that had to exist before anything defaulted a
key engine-wide. It reads `.wms` and artwork straight out of the archives, so it measures authored
demand, never a render result.

Measured 2026-09-08 over the 179-archive corpus: **603 node/attribute references across 80 skins and
499 distinct sprites**, of 22,649 drawn artwork references of which 8,833 declare a key themselves.
`--tsv` writes every row, sorted by how many key pixels the sprite holds, which is the order to open
them in. What it does *not* count is a mapping/clipping/position image — read for its colours, never
blitted, and an implicit key there would delete a mapping colour from its own map.

**`--alpha only|none|any` splits the class by whether the sprite authored an alpha channel, and that
split is W78a.** W78 shipped keying only `none` (527 refs / 66 skins / 437 sprites), on the reasoning
that a sprite carrying alpha has already said what is see-through. `--alpha only` measures what that
left behind — **76 references across 21 skins and 62 sprites** — and the falsifying check is not the
count but the pairing: **11 of those nodes hold two states of the same button, one exported without
an alpha channel and one with, with identical magenta counts** (`Half-Life_2`
`m_pause_no.png`/`m_pause_hov.gif`, both 1,394). Under the veto the normal state keyed and the hover
state did not, so the button turned magenta under the pointer. The engine now keys `any`, which is
this script's default so that what it counts is what the engine does. A `key_pixels` count is of
**opaque** key pixels: a partially transparent one is composited paint, and the corpus holds none.

`WoW/mainView`, the residual's headline at 3.5%, was the same thing seen through a `CUSTOMSLIDER`:
`volume_1.png` is a 31-frame filmstrip against an 86x84 `volume_map.png`, and every frame carries the
same flat magenta wedge beside a genuinely antialiased knob. The crop was already correct; only the
wedge was paint that should not have been.

**After the veto came off, the corpus residual is 878 opaque magenta pixels across 2 of 545 views,
and neither is an implicit-key case.** `portals/mode1` (829 px, 0.38%) is a `BUTTONGROUP` declaring
`transparencyColor="#000000"` whose sheet's magenta filler is blitted whole instead of drawn through
its mapping — that is W48(a). `Plus! Pulsar/mainView` (49 px, 0.04%) is a `<button
id="shutterButton">` declaring `transparencyColor="#ffffff"`, so the implicit key correctly stands
aside and real WMP draws the same corner.

**One corpus view is nondeterministic and a PNG-diff sweep will flag it forever.**
`Scooby-Doo_2/infoView` picks its character at random in `scooby.js`: three runs of one binary give
two hashes. Do not read it as collateral from a change.

The companion number, from the markup census's own attribute counts: **4,979 of the 6,076
`transparencyColor` declarations in the corpus (82%, 142 skins) are `#ff00ff`.** That is why the
default is that colour and not another.

### `python3 scripts/wmp_handler_scope_census.py [json-out]`

**What a handler names without qualifying it**, over the installed corpus: every unqualified *call*
of an element-method name — resolved through the skin's own functions to three levels — and every
unqualified *property* reference that names an attribute the handler's own element authored, split
into reads and writes. It is the instrument W216 was measured with (31 calls / 20 archives; 255
reads + 249 writes / 100 archives, 2026-09-21).

**The census cannot answer this and neither can a sweep**: `wmp_skin_census.sh` drives `onLoad`,
this demand is in `onClick`, and that is the blind spot `harness/live-loop.md` § *Auditing one authored control across the
whole corpus* exists for. So it reads the decoded script text directly, the way `WMPTextDecoder`
does, and **repairs the `01 00 01 00` local file headers the way `WMPArchiveHeaderRepair` does** —
without that, `Need_for_Speed_Underground` and `SplinterCellWMPSkin` are dropped on a `BadZipFile`
and a scan that does not print what it skipped reads as a clean corpus. It prints the **encoding
breakdown as calibration**: a correct run over 184 archives reproduces 158 UTF-16-BOM / 146 cp1252 /
89 UTF-8 / 9 UTF-8-BOM, and a run that does not has decoded something differently from the engine.

**It nets out what the engine already binds** — `value`, and the changing attribute inside an
`<attribute>_onchange` — so the count is the residue a handler cannot reach, not the population of
bare names. Extending it to another class of name means changing `VOCAB` or `is_handler`, both at
the top of the file.

### `scripts/wmp_render_sweep.sh capture|compare`

*Did my change move anything?* `capture` writes the invariant lines **and** every PNG; `compare`
diffs both. Every engine-wide change from Phase 2 onward passes through this. Each changed invariant
line is prefixed with the `[skin]` it belongs to, and the `DIFFER` line names the changed skins —
a `RENDER-DUMP` line carries only a view id. `compare --summary` replaces the per-image list with
`png_diff.py`'s classes.

```bash
scripts/baseline_worktree.sh ../nullplayer-base HEAD
(cd ../nullplayer-base && scripts/wmp_render_sweep.sh capture /tmp/wmp-sweep/base)   # + --allow-dirty if the script says so
# …make the change…
scripts/wmp_render_sweep.sh capture  /tmp/wmp-sweep/curr
scripts/wmp_render_sweep.sh compare  /tmp/wmp-sweep/base /tmp/wmp-sweep/curr
```

**Never capture the baseline with `git stash`** — it relinks `.build` under the user's running app.

**A before/after `wmp_skin_census.sh` pair *is* a render sweep — do not run both.** The census
writes every PNG to `<outdir>/png/<skin>/` with every probe on, so comparing the two `png/` trees by
`sha256` answers the same question `compare` answers, off captures you already paid for. W128 needed
the `UNRECOGNISED` tally *and* proof that nothing moved; one census pair gave both, and a second pair
of sweeps would have been ~10 minutes of rebuild for a duplicate answer. Use `wmp_render_sweep.sh`
when the pixels are the whole question; use the census when you also need the counts.

**A fresh worktree cannot build as-is** — `Frameworks/` is only partly in git — which is what
`scripts/baseline_worktree.sh` exists for; `harness/sweep-limits.md` § *A baseline worktree needs the vendored frameworks
linked in* has the traps. The script ends on `git status -- Sources Tests scripts` being clean, the
check that the baseline really is the rev asked for. The manual version of it was confirmed working
2026-09-11 for W128's before/after census — the W76 note in the archive records a pixel comparison
that could not run for exactly this reason.

---

## Traps the scripts enforce, inherited rather than re-earned

- **A sweep is a build — freeze the tree.** `capture` and the census refuse a dirty tree without
  `--allow-dirty`. A binary that will not compile writes an *empty* capture that diffs as
  "everything changed". Never run either while the user may be building: SwiftPM lock contention
  stalls both.
- **Redirect to a file and grep the file.** Piping a long `swift test` into a filter drops lines
  silently. stderr gets its own file.
- **Every harness line is one `write(2)`, never `print`.** `HarnessOutput.emit`
  (`Tests/NullPlayerAppTests/HarnessOutput.swift`, shared with the Audion face harness) takes a lock,
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
  it. So both scripts also check each loaded block's view count against the `views=` its own
  `LOAD` line declares (a view that fails to *build* still emits `RENDER-DUMP <view> FAILED`), and
  flag a second `LOAD` inside one block. **Count distinct view ids, not lines.** A view that lays
  out and then fails downstream can emit *two* lines about itself — so when W32 admitted `Nautical`
  (one view, laid out, then `WMP0015` on `vol_slider.bmp`) the arithmetic read 2 against `views=1`
  and called the block damaged when nothing had been lost. Reading a live defect as a lost log block
  is this check's own failure mode, pointed the wrong way, and it survived a solo re-run — which is
  what distinguishes it from a real splice. **The census was fixed at W32 and the sweep was not,
  which cost a quarter of the corpus for a month**: the sweep still counted lines, and a refused PNG
  write printed a second `RENDER-DUMP … FAILED`, so **48 of 184 archives** were flagged until W245
  closed both halves on 2026-09-20 — a refused write is now a `PNG <view> FAILED` line, and the
  sweep counts ids. `WMPDumpLineAccountingTests` pins the emitter, the id counting and the
  short-block case, running the script's own `PYDAMAGED` block rather than a copy of it. Damaged skins are listed in `damaged.txt`, get a row carrying
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
  script found 198. Split the bands: `any(band.getbbox() for band in diff.split())` — or use
  `scripts/png_diff.py`, which does, rather than writing the comparison again.
- **`SCRIPT inline:` used to be emitted in dictionary order and was not stable between runs** — the
  same archive reported the same handler tally in a different order each time (~19 lines per
  capture), inflating the invariants diff with churn that was not a change (W64). **Fixed:**
  `WMPRenderDumpTests.tally` sorts by count and breaks ties on the name, because Swift randomizes
  hash order per process. If reordered tallies ever reappear in a `compare`, that tie-break has
  regressed — read the diff by what the `RENDER-DUMP`, `BITMAPS` and `LOAD` lines say meanwhile.
- **A detector's own false positives cost more than the thing it detects.** The `views=` arithmetic
  silently dropped **48 of 184 archives** from every invariants comparison for a month (W245), and
  the damage it was reporting was not real. Two tells were on the page the whole time and are worth
  reusing on any run-to-run check: **an identical "damaged" set across two runs** is arithmetic, not
  interleaving, because interleaving is not deterministic; and **an exact match between a flagged
  count and an explained one** — 76 flagged lines against 76 known-refused `WMP0035` writes — names
  the cause outright. **Re-measured after the fix, over three consecutive 184-archive captures: 0
  damaged, byte-identical invariants each time, and the prefix-scan arm fired on nothing.** So the
  interleaving these checks were written for is *unfired here*, not disproven — the 180-archive run
  that lost three blocks predates this tree and the buffered `print` that caused it is gone. Both
  arms stay: a hand-deleted `RENDER-DUMP` line is still caught, which is the test that keeps them
  honest.
- **A large image diff is read by looking, and by which way it went.** 198 of 545 changed in the
  Phase 5 sweep. Counting the *drawn* (alpha > 8) pixels in each pair and sorting sorts the whole
  set into "changed colour within the same silhouette" and "lost or gained content", and the second
  list was one skin long — which is the list worth opening. **`compare --summary` does this sort**
  (via `scripts/png_diff.py`): a class per image and only the lost, gained and resized ones listed.

---
