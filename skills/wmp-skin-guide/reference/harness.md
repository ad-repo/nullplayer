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
| `WMP_RENDER_PROBE` | `all` or a view id | `PROBE` — every drawn node's type, id, resolved frame, clip, z, paint and authored attributes |
| `WMP_RENDER_BITMAPS` | `1` | `BITMAPS` — resolved count and every path that failed to load, with `missing=` |
| `WMP_RENDER_SCRIPTS` | `1` | `SCRIPTS`/`SCRIPT` — per program: bytes, declared handlers, and the runtime's availability |
| `WMP_RENDER_EXPR` | `1` | `EXPR` — every `JScript:` geometry expression, its source, both evaluators' values, its dependency order and deps |
| `WMP_CALL_TRACE` | `1` | `CALL`/`CALLS` — every host object-model access with receiver, member, value, and whether the member was recognised |
| `WMP_RENDER_CLICK` | `<view>@x,y[;x,y…]` | `CLICK` — the object hit, handler count, every attribute changed anywhere in the graph, the host command reached, and the state after |
| `WMP_RENDER_SETTLE` | seconds | pump the run loop, then drive the skin's `onTimer` handlers, before measuring |
| `WMP_RENDER_SIZE` | `<W>x<H>` | build at that size and re-drive `onResize` — an expression-driven layout is a *different* layout, not the same one scaled |

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
COMPAT unknown-tags=<n> unknown-members=<n> resources-missing=<n> resources-unsupported=<n>
UNKNOWN tag <name> ×<n>
UNKNOWN member <path> ×<n>
SCRIPTS programs=<n> bytes=<n> runtime=<available|unavailable (why)>
SCRIPT <path>: bytes=<n> handlers=[…]
SCRIPT inline: <event>×<n> …
SCRIPT-DIAG <view> [<code>] <message>
RENDER-DUMP <view>: <W>x<H>, <n> nodes, <c> commands, <h> hits, <w> widgets, <u> unresolved
RENDER-DUMP <view> FAILED <error>
PROBE <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> z=<n> paint=<…> attrs=[…]
BITMAPS <view>: resolved=<n> missing=<space-separated paths>
EXPR <view>/<id>.<prop> #<order>: <source> -> <static> live=<live> deps=[…]
CALL <view> <path> <read|write> value=<v> <ok|UNRECOGNISED>
CALLS <view> <path> ×<n> <ok|UNRECOGNISED>
CLICK <view>@x,y hit=<id>#<stableID> kind=<k> action=<a> sticky=<b> handlers=<n>
CLICK <view>@x,y changed=[…] | command=<…> | unrecognised=[…] | after: <…> | MISS
PNG <view>: <filename>
```

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
- **Interleaved writes eat blocks of the log at random.** Two writers land inside one another and
  the lines they collide with are lost outright, not mangled — which reads exactly like a skin that
  stopped drawing and is not one. Both scripts detect it, list the skins in `damaged.txt`, give them
  a row carrying identity and nothing else, and leave them out of the diff. Re-run a damaged skin
  alone with `--corpus <a directory holding just that archive>`. Their PNGs are unaffected and are
  still compared.
- **Compare pixels, not alpha.** Pillow 9.5 made `getbbox()` on an RGBA image consider the alpha
  channel alone, and every dump carries alpha, so a change that moved a visible control but left
  alpha untouched came back "identical" across 590 `.wal` images. `alpha_only=False` in
  `wmp_render_sweep.sh` is load-bearing, not tidiness.
- **A `maxdelta` of 1** is an LSB rounding difference, not a regression. The script reports the
  number; a human reads it.

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

`compare` was checked the same way on 2026-09-07: a one-pixel **colour-only** change (alpha
untouched) to one dumped PNG and a one-character change to one invariant line, each reported.

**Two things a clean sweep does not prove.** It measures the default state and nothing else — not a
tab, a setting, a drag, a hover, a timer, or anything time-driven. And a structural probe is not a
picture: a node existing says nothing about where it is drawn. Only a rendered frame, or the user
driving the real app, says that.

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

So the whole of the Tier-1 loading blocker is the lenient-XML-parser work (`W2`), and the decoder
work (`W1`) is no longer ranked ahead of it. Two further clusters the census surfaced, which the
plan had folded into later phases:

- **`WMP0032`, 7 views across 5 skins** — "View requires positive literal width and height for
  static layout". A view whose size is computed in script renders nothing at all, which is why
  `claw.wmz` and `iconic.wmz` load cleanly and produce **zero** layouts.
- **`WMP0024`, 2 views** — an *empty* resource attribute rejected as "absolute, drive-qualified, or
  invalid", killing the whole view.

Every count above carries the corpus it was measured against. Do not rewrite an old numerator
against a new denominator.
