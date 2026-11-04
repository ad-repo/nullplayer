# AIMP harness

The only place AIMP probe flags are documented. The harness is the test target's, as `.wmz`'s and
`.wal`'s are: `AIMPRenderDumpTests` (the probe, opt-in through `AIMP_SKIN`) and `AIMPCorpusLoadTests`
(the load gate, on by default). Trace switches the app itself reads (`AIMPSkinTrace`) exist in debug
builds only.

## Corpus

Skins are never committed. Keep them in `~/Library/Application Support/NullPlayer/AIMPSkins` or any
directory; the probe takes every `.acs5`, `.acs4`, `.acs3`, `.acs` (AIMP 2) and `.acs4proj` in it and prints the count it found.
The catalog is <https://www.aimp.ru/?do=catalog>; each skin page links a `*_full.jpg` screenshot.

## Flags

| Variable | Meaning |
|---|---|
| `AIMP_SKIN` | A skin file or a directory of them. Required. |
| `AIMP_RENDER_OUT` | Write `<out>/<skin>-<ext>.png`. Without it, census only. |
| `AIMP_RENDER_SIZE` | `WxH`. Default: the size the window opens at (`AIMPSkinRenderer.naturalSize`, or a sizable form's `initialSize`). |
| `AIMP_RENDER_ITEM` | Draw only this layout item (`AioBody` for Soot's all-in-one mode). |
| `AIMP_RENDER_PAGES` | `group=page,…`: tabbed groups on other pages (`Cassette=1`). |
| `AIMP_RENDER_COUNTERS` | `name=n,…`: skin counters at these positions (`EQ_Visible_Counter=1` opens Kenwood's EQ unit). |
| `AIMP_RENDER_TARGETS` | `1`: print every click target as `TARGET <name> <kind> x,y wxh [right=<kind>]`, topmost last; `right=` is what a right-click does. |
| `AIMP_RENDER_CLICK` | A control name: print what a click on it does: `CLICK <name> handler=<h> actions=[…]` for script handlers, `down=[…] held=[…] up=[…]` for press-and-hold handlers, and for counters the actions of the scripts that react. |
| `AIMP_RENDER_WHEEL` | `<control>:<notches>;…` (an empty control: the form's bare face): turn the wheel through a real `AIMPSkinMainView` and print `WHEEL <name> <n>: <kind> asked=[provider=value…, actions] counters=[name old->new] pages=[group->page]`. |
| `AIMP_RENDER_LIVE` | `1`: run a real main view (and the skin's other windows, wired as the window controller wires them) against a fake player that answers at once, as `AudioEngine` does: press every safe control (no menus, dialogs, search, quit), play 2 s, stop, play, next track, pause, press them all again. Prints `LIVE frames= avg= p95= max= actions= deepest= floods= [LOOP] clicked= top=[…]` (every action, by name, with its count): `deepest` is how far actions nested inside redraws, `LOOP` a runaway, `floods` frames with more than ten actions. Covers the live-only loops renders cannot show; it did not recreate the GX-77 Grey launch hang (its trigger needs launch state the probe lacks). |
| `AIMP_ACTION_TRACE` | `1`, on the running app (not the probe): log every action a skin asks of the player as `[aimp/action] <action> at <seconds> s` — the quickest way to see whether a key, timer or script reached the engine at all. |
| `AIMP_RENDER_LIBRARY` | `empty`: the companion renders get an empty music library instead of the 40-track sample. |
| `AIMP_RENDER_HIT` | `x,y;x,y…` in skin pixels: print `HIT x,y <target>` for each, through the window's own hit test. |
| `AIMP_RENDER_SCRIPTS` | `1`: run every compiled script once from a fresh state, on an engine of its own (`AIMPCorpusLoadTests.dryRun`, which the load gate counts too); print `SCRIPTS <ran> of <n>` and `SCRIPT_FAIL <name> <why>` for each that stopped, a script that did not compile as the skin loaded among them. A skin's `except` does not hide an unsupported call. |
| `AIMP_RENDER_ITEMS` | `1`: print each layout item as `ITEM <name> x,y wxh` while drawing, once per layer (parents first; a window's natural size is measured without drawing and prints nothing), and each shown control as `CONTROL <name> <class> x,y wxh <TargetPin><-<Source>.<SourcePin>[<Expression>]…`. |
| `AIMP_RENDER_STATE` | `playing`: playing, 108 s in, 30 % through, sample title, an EQ smile, a four-colour test card as cover art. Default: stopped. |
| `AIMP_RENDER_HOVER` | `x,y` in skin pixels: the pointer rests there (`OnMouseEnter`/`OnMouseMove` run, `IsActive` reads it) before drawing. Without it every `IsActive` reads on. |
| `AIMP_RENDER_VISUALIZE` | `n`: run n window frames (timers, visualization handlers over a pulsing spectrum, then the scripts that moved), a thirtieth of a second apart, before drawing; print `VISUAL frames=<animators> lamps=<faded>` and `VISUAL_FAIL <script> <why>`. |

## Run it

```bash
AIMP_SKIN=~/Library/Application\ Support/NullPlayer/AIMPSkins \
AIMP_RENDER_OUT=/tmp/aimp-render AIMP_RENDER_STATE=playing \
  swift test --filter AIMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/aimp-render.txt 2>&1
```

Confirm it took: `grep '^RENDERED' /tmp/aimp-render.txt` prints `RENDERED <n> of <m>`. Redirect, do not
pipe: a long `swift test` piped into a filter drops blocks.

## The load gate and the census

`swift test --filter AIMPCorpusLoadTests` loads every installed skin (or `AIMP_CORPUS_PATH`) against
`Tests/NullPlayerAppTests/Fixtures/AIMPSkin/corpus-baseline.tsv`, keyed by sha256: a skin recorded `ok`
that fails, or runs fewer of its scripts, fails the suite; an untyped rejection always does; a skin
absent from the baseline never does. It prints `AIMP corpus: <loaded>/<n> loaded, <r> rejected, <u>
unranked`. Re-record after improving the engine, never to turn red green:

```bash
scripts/aimp_skin_census.sh /tmp/aimp-census        # one row per skin -> census.tsv
scripts/aimp_corpus_baseline.py /tmp/aimp-census    # census.tsv -> corpus-baseline.tsv
```

Confirm it took: the census prints `census: <n> skin(s), <k> loaded`; the recorder prints `recorded <n>
skin(s), <k> ok`. `AIMP_CENSUS_OUT=<file>` is the flag the census sets on the gate.

The crawled corpus (`scripts/aimp_corpus_crawl.py`, the aimp.ru catalog) is measured the same way with
`--corpus <dir>`.

## Output grammar

```
HARNESS <count> skin(s) from <path>
SKIN <file>
  FORMAT <acs5|acs4|project> NAME <name> AUTHOR <author>
  ENTRIES <n> IMAGES <n> WITH_PIXELS <n> RESOURCES <n> LOAD_MS <ms>
  FORM items=<n> controls=<n>
  WARN [AM####] <message>
  FATAL [AM####] <message>
  DOCKED <form>                                                     (held by a dock site in the main form)
  COMPANION <form> "<title>" visible=<initial> <w>x<h>|NO_SIZE   (each also renders to <skin>-<ext>-<form>.png)
  RENDER <w>x<h> <png path> | RENDER NO_SIZE | RENDER EMPTY
RENDERED <n> of <m>
```

Without the last two flags the probe draws the default state: its sample player
(`AIMPSkinPlayerSnapshot.probe`: a sample title, volume 0.7, dark) stopped, the first tab of every
tabbed group. Either way it first runs the skin's load scripts (`AIMPSkinScript.Engine.loaded`), as the
window does when the skin is shown.
