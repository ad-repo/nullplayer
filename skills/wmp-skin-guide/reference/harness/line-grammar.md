# `.wmz` harness: the line grammar

Moved verbatim from `reference/harness.md` on 2026-09-25; that file is the router. Read it first.

## The line grammar

Machine-readable, one fact per line, inside a `SKIN <file.wmz>` block. `scripts/wmp_skin_census.sh`
and `scripts/wmp_render_sweep.sh` parse these; do not reword one without updating both.

```
HARNESS <n> archive(s) from <path>
SKIN <file.wmz>
SKIN <file.wmz> FAILED <error>
LOAD definition=<p> encoding=<e> entries=<n> bytes=<n> views=<n> nodes=<n> scripts=<n> resources=<n> loadms=<x>
     loadms= is in raw.txt/render.txt only: a wall clock cannot be diffed, so it is stripped from invariants.txt
FINDING [<severity>] <WMP00xx> ×<n> <message>
COMPAT unknown-tags=<n> unknown-members=<n> unknown-events=<n> resources-missing=<n> resources-unsupported=<n>
UNKNOWN tag <name> ×<n>
UNKNOWN event <name> ×<n>
UNKNOWN member <path> ×<n>
SCRIPTS programs=<n> bytes=<n> runtime=<available|unavailable (why)>
SCRIPT <path>: bytes=<n> handlers=[…]
SCRIPT inline: <event>×<n> …
SCRIPT-DIAG <view> [<code>] <message>
     every diagnostic from every transaction the view ran — onLoad, onVideoStart, the resize
     pass and each settle tick — printed once each. Until 2026-09-24 only the last transaction's
     were printed, so a WMP_RENDER_SETTLE or WMP_RENDER_SIZE run silently dropped every onLoad
     error; a SCRIPT-DIAG count taken with either flag before then is void.
RESIZE <view>: <W>x<H> -> <W>x<H>, handlers=<n>
RENDER-DUMP <view>: <W>x<H>, <n> nodes, <c> commands, <h> hits, <w> widgets, <u> unresolved
RENDER-DUMP <view> FAILED <error>
     one line per view per outcome: its stats, or FAILED when the scene never built at all.
     A refused *write* is a PNG outcome and never a second RENDER-DUMP line — see W245.
ANIMATION <view>: shortestDelay=<s> bounds=<rect>
WIDGET <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> visible=<f|none>
PROBE <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> z=<n> paint=<…> attrs=[…]
BITMAPS <view>: resolved=<n> missing=<space-separated paths>
EXPR <view>/<id>.<prop> #<order>: <source> -> <static> live=<live> deps=[…]
CALL <view> <path> <read|write|invoke> value=<v> <ok|INERT|UNRECOGNISED>
CALLS <view> <path> ×<n> <ok|INERT|UNRECOGNISED>
CLICK <view>@x,y hit=<id>#<stableID> kind=<k> action=<a> sticky=<b> handlers=<n>
CLICK <view>@x,y changed=[…] | command=<…> | unrecognised=[…] | MISS
CLICK <view>@x,y after: <n> commands, <n> widgets[<kind>×<n> …], <n> unresolved
DRAG <view>@x,y>x,y hit=<id>#<sid> kind=<k> slider=<b> direction=<d> min=<m> max=<M> border=<b> steps=<n>
DRAG <view>@x,y>x,y step=<i> at=<x>,<y> value=<v> drawn=<v> thumb=<rect>
DRAG <view>@x,y>x,y dragend handlers=<n> commands=[<action>=<value>,…]
DRAG <view>@x,y>x,y value <v> -> <v> follows-pointer=<yes|no|flat> thumb-travel=<px>
DRAG <view>@x,y>x,y MISS | not-a-slider — no value tracking to measure
HOVER <view>@x,y <onMouseOut|onMouseOver> <id>#<stableID> kind=<k> handlers=<n>
HOVER <view>@x,y <event> changed=[…] | [<code>] <message> | unrecognised=[…] | after: <…>
HOVER <view>@x,y inside=<id>#<stableID> — no edge
HOVER <view>@x,y MISS
APPKIT <view>: <W>x<H>@<n>x differing=<n>/<n> (<pct>) hosted=<n>/<n> outside=<n> (<pct>) max-delta=<n> blit=<n> (<pct>) blit-max-delta=<n> [worst=<rect>]
APPKIT <view>/<stableID> <kind> id=<id> frame=<rect> differing=<n> (<pct>)
APPKIT <view>: SKIPPED <why>
PNG <view>: <filename>
PNG <view> FAILED <error>   the write was refused; the view's own RENDER-DUMP line still stands
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

**`dispatch` prints only when the transaction actually runs.** A gated hover edge with no authored
handler returns without doing anything, and the pointer crosses a whole row of buttons on the way to
the one it wants — tracing before the gate wrote a line per crossing that said "nothing happened".
The `hover <id> -> <id>` crossing line went with it for the same reason. What this costs is the
signature that found the window-never-key defect on 2026-09-08 (*no `hover` lines at all while
`dispatch click` worked*); if that question comes back, the way to ask it is a counter or a
one-shot, not a line per pointer move.

**Three more lines were removed on 2026-09-11, and the reason is worth keeping**:
`widgets hosted=…`, `present <event> …` and `animation <view> …` were printed on every present, and
a skin repaints at its own cadence — an animated view presents 20×/s, and each present re-runs
`synchronizeWidgetViews` and the position-change transaction. Interleaved, they wrote three
identical lines forty times a second and buried every line that carried news, which is the opposite
of what a trace is for. `widgets hosted=` had earned its place once — `hosted=0` through a whole
track settled Corona's "no visualization" by saying the pane was never built — so if that question
comes up again, ask it with a line that prints when the hosted set *changes*, never one per frame.
`WIDGET` still answers the same question from the harness side.

`menu at=` prints the point a right-click landed on and every `<EFFECTS>` frame it was tested
against, which is what decides whether the visualization's own context menu opens.

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
`#-` means the live pass produced nothing for that key. A skin whose static column resolves and whose
live column is empty is not a working skin.

**`EXPR` is scoped to the dumped view, and reading it any other way is how this line lied.** WMP ids
belong to a `VIEW` and so do both evaluators — `WMPScriptViewPlan` collects the view's own subtree,
and `WMPInitialLayoutResolver` refuses a reference that leaves the view it was built for. The probe
used to walk `graph.allNodes`, so every *other* view's expressions were printed under this view's
name, asked of an evaluator that by construction cannot answer them, once per view in the skin.
Corpus-wide that manufactured **34,300 rows** reading `#-` / `live=-` against 7,700 real ones — 82%,
read for a day as an engine defect starving half the corpus — and the same collision by *name* also
credited a sibling's order number to 131 rows that were not evaluated at all, so it lied in both
directions. See `harness-history.md` § *After the cascade* for what the corrected sweep says, and
`testExpressionProbeReportsOnlyTheDumpedViewsOwnExpressions` for the check that holds it.

---

## Input and tooltips the markup authors

Two counts the census does not produce, both measured 2026-09-08, both with a command next to them.

**Nodes that author input on a kind the builder does not treat as a control** — `537` across `143`
of the 179 archives, which is what `WMPSceneBuilder.authorsInputHandler` exists for: `326` `<TEXT>`
across 69 skins, `90` `<EFFECTS>` across 81, `21` `<VIDEO>` across 21, then `stopbutton`,
`progressbar`, `prevbutton`, `playbutton` and `nextbutton` at 12-13 each — transport spellings this
engine still parses as *unknown* kinds, so they are hit targets now and carry no transport action.
`Sports` is the reason it was written: ten `<TEXT>` playlist rows whose `onmouseover` could never
fire because nothing registered them as targets.

```bash
python3 scripts/wmp_input_kinds.py
```

**Tooltips.** Measured with the markup census (re-measured 2026-09-25 over 179 after W268):

```bash
scripts/wmp_markup_census.sh /tmp/wmp/markup toolTip upToolTip downToolTip
```

| Attribute | Uses | Skins |
|---|---|---|
| `upToolTip` | 4,717 | 177 of 179 |
| `toolTip` | 3,746 | 175 of 179 |
| `downToolTip` | 528 | 104 of 179 |

None of them reached the screen before 2026-09-08: only widgets answered `stringForToolTip`, and a
skin's controls are `<BUTTON>`s. The tip is resolved per drawn state in `WMPSceneBuilder.toolTip` —
`downToolTip` while the control is down, `upToolTip` otherwise, plain `toolTip` behind both — and
read through the scene overrides, so a script assignment (`alx_dl.wms` writes `toolTip='Volume'`
from its slider's `onMouseUp`) wins over the authored attribute.
