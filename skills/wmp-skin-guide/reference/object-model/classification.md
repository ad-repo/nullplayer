# `.wmz` object model: recognised, dispatched, and verified not gaps

Moved verbatim from `reference/object-model.md` on 2026-09-25; that file is the router. Read it first.

## Recognising an event is not dispatching it

**`WMPAttributeValue.handlerNames` decides what becomes a `.handler` at all, and
`WMPCorpusReportHarness.supportedEvents` decides what counts as implemented.** An event needs a name
in the first **and a dispatch site** to be either. Neither list was ever printed by the harness, so
the whole class of "events the markup declares and nothing ever raises" was invisible:
`WMPCompatibilityReport` collected the counts and compared them, and `compatibilityLines` emitted
only tags and members. That is how `onResize` sat unrecognised through three phases. It is now
`UNKNOWN event <name> ×<n>`.

**Do not add a name to `handlerNames` or `supportedEvents` without its dispatch site.** A recognised
event nothing raises drops out of the tally while still doing nothing — exactly the state `onResize`
was in. Classification is one line; the dispatch site is the real cost, and it is different per
event.

Measured 2026-09-08 over the 179 archives: **4,114 uses**, down from 6,823 (see `harness.md` for
what W51/W52 drained, and for why the distinct-*name* count is not the figure to quote). `onresize`
is absent from that list because it closed in the same change that added the instrument;
`value_onchange`, `openstate_onchange` and `playstate_onchange` are absent because they are now
accepted spellings of events this engine does dispatch. Reproduce with
`scripts/wmp_render_sweep.sh capture <dir> --allow-dirty` and tally `UNKNOWN event` in
`<dir>/raw.txt` by name and by containing `SKIN` block.

---

## A dispatch site with no classification is as silent as the inverse (W56)

**The rule above has a second direction, and it cost this engine 151 handlers.**
`handlers(in:event:)` has accepted `positionchange` wherever it raises `change` since W119 — a
comment there explains the alias and names the corpus — but **`onpositionchange` was never in
`handlerNames`**, so no attribute ever became a `.handler` under that name and the alias could
never match. The site was live, reachable and correct; nothing could arrive at it. In the running
app the symptom is a dispatch line that looks like a working one:

```
[wmp/dispatch] change targetID=volume stable=20 view=TubeFrameView handlers=0
```

`handlers=0` beside a `targetID` whose markup plainly authors a handler is this class, and it reads
identically to a control whose skin authored nothing. **Read a `handlers=0` against the node's own
attributes**, the same check `WMP_RENDER_CLICK`'s `handlers=0` already needs.

**Re-measured 2026-09-22 over the 182 readable archives: 151 uses across 42 archives**, every one
on a `SLIDER` (91) or a `CUSTOMSLIDER` (60) — `wmp_markup_census.sh <outdir> onpositionchange`, then
split by element with a decoder rather than `grep`.

**It is a user gesture, not the clock, and that is W119 staying shut.** `change` is raised only from
`WMPMainView.performSlider` and the popup/listbox selects; the position tick raises `hostsettle` and
`currentposition_onchange`, neither of which is in the alias set. The tick was spelled
`positionchange` once, and classifying this name is precisely the change that would have made that
spelling live again — `testAClockTickDoesNotRaiseASlidersPositionChange` is the guard.

**A correction the fix forced, and it is the more useful half.** The W119 comment in
`refreshHostState` states that a clock tick "was raising all of them ten times a second". It never
could have: the attribute was not a handler, so the tick reached nothing. The rename to `hostsettle`
was right for other reasons and is what makes this fix safe, but **the stated cause was never
verified** — a claim about a handler that was never classified is a claim about markup nothing ran.

### What a binding was already carrying, and what it was not

**Do not read "the event never ran" as "the control did nothing".** `WMPTransportAction.boundAction(for:)`
maps a slider's `value="wmpprop:…"` straight to the host, so for most of these the host effect was
already happening by another route and only the rest of the handler was lost. Split over the 151:

| | uses | what was lost |
|---|---:|---|
| slider **has** a `wmpprop:` value binding | **124** | the rest of the handler — almost always a tooltip the skin writes (`updateSeekToolTip()`, `tooltip = 'Volume = ' + …`) |
| slider has **no** binding | **27** | the handler was the only route: 25 `seek` sliders' tooltips, and `tubeframe`'s `TruBass`/`SrsWow`, the only two where the **host effect itself** never happened |

This is why a live A/B on a volume or balance slider proves nothing — it moves either way. The
signature that separates them is the tooltip: 25 archives author `toolTip="Seek"` and rewrite it to
`MM:SS / total` from this handler, so a seek bar whose tooltip is still the word is the before-state.

**The 124 now write the host twice per drag step**, once through the binding and once through the
script. Every corpus case writes the same property with the same value, so it is idempotent — but a
slider that fights the pointer is what a counter-example to that would look like.

---

## Verified **not** gaps — check this before opening a row

These were `tasks/WMP_TASKS.md` § *2c-note* until 2026-09-19; they rank nothing and cannot be taken, so
they live here with the rest of the documented refusals.

The SDK conformance audit (2026-09-11) disproved nine candidate gaps, and **that is the more valuable
half of it**: each is a plausible-looking gap that would otherwise cost a session to chase. Check
this list before opening a row that came from reading the SDK against a corpus scan.

* **`onresize` is dispatched.** `WMPMainWindowController.swift:1162` builds the event as `"resize"`;
  handler names are stored with the `on` prefix stripped, so grepping the sources for `onresize`
  finds only the census table. 47 uses / 19 skins already work. It is raised on a user drag, at
  open when the view opens at a size it was not authored at (W211), and **when a transaction
  presents a canvas different from the one on screen** — a skin resizing its own view (W274).
  WMP runs `onResize` whoever changed the size, and a handler that reads a stretched pane in the
  transaction that grew the window reads the old layout: `NVIDIA`'s `plModeToggle()` sized its
  chooser off `plListBoxSub.height` at −95 and the list was never hosted, and `onPlayerResize()` is
  the skin's own correction. The raise is keyed on the canvas, not on `viewSize`, because the view
  timer cancels the click's task mid-build (W197) and the transaction that finally presents the
  new size is the timer's.
* **`nineGridMargins`, `resizeImages`, `elementType`, `bottom`, `right`, `accDescription`** — ambient
  attributes with **zero corpus uses**. Absent from the engine and correctly so.
* **`moveSizeTo` and `slideTo`** — ambient methods, **zero calls** corpus-wide. (`resizeTo` is also
  zero and is implemented anyway.) All three are in the vocabulary after W128, which costs nothing:
  the vocabulary is the SDK's list, not a demand tally.
* **`<COLUMN>`, `<ITEM>`, `<SETTINGS>`** — SDK elements with zero corpus uses.
* **`eq.reset()` / `eq.nextPreset()` / `eq.previousPreset()`** — 104 / 91 / 87 skins, and all three
  are implemented (`WMPObjectModel.swift:811-817`). A naive receiver-filtered scan reports them as
  missing; they are not.
* **`scrollingAmmount` / `scrolingDelay` (25 skins, 54 uses), `horizontalAlignemnt` (3), `donwImage`,
  `tootip`, `hegiht`, `visilble`** — **author typos**, copy-pasted across the Plus! family. WMP
  ignores an unknown attribute too, so matching them would be *less* faithful, not more. This is the
  largest single false lead in the whole scan.
* **`transparencyColor="white"` / `clippingColor="white"` (10 / 7 skins)** — feared to be losing the
  declared key to the implicit magenta default. Traced: `colors(_:names:)`
  (`WMPSceneBuilder.swift:820`) delegates to the name-aware `color(_:names:)`, so `declared` is
  non-empty and `implicitColorKey` stays nil (`WMPSceneBuilder.swift:761`). Correct today.
* **`mediacenter.effectType` read as a property (376 uses / 192 files / 130 archives)** — checked while landing W128
  because `effectType` is an SDK `EFFECTS` *method* and the vocabulary gates reads. Every use is on
  the `mediacenter` host receiver, answered by `readMediaCenter` before the element path. Not a gap
  and not a regression risk.
* **`metadata.*`, `vis.*`, `ipl.*`, `ddpl.*` are element ids, not host objects (W315).** WMP has no
  global by those names and `bindHostGlobals` binds none of them, so a skin's `<TEXT id="metadata">`
  (108 archives) is what its script reaches. `WMPCorpusReportHarness.supports(memberPath:in:)`
  classifies such a path against the element table when the skin authors that id; `eq` is bound as
  a global and is never taken over. What stays unknown under those heads is either real element
  demand (`hoverFontStyle`, `vis.nextEffect`…) or an **author leftover**: `Grinch`, `Primitive`,
  `Israeli`, `Heart_Butterfly` and `Asia MP11` call a template `UpdateMetadata()` with no `metadata`
  element, which throws in WMP too — nothing to implement.
* **`<CONTROLS>` (77 skins), `<VIDEOSETTINGS>` (84), `windowed` (114), `allowAll`,
  `dropDownVisible` (114)** — real gaps, but already tracked as W103 and the documented
  refusals in this file (`<CONTROLS>`/`<VIDEOSETTINGS>` were W111, moved to
  `tasks/LOW_QUALITY_TASKS.md` 2026-09-19 — they cost no pixels and no longer rank anything). Not
  re-opened.

---

## Recognised, answered, and nothing behind them (`INERT`)

This was `tasks/WMP_TASKS.md` § *2b* until 2026-09-19. It ranks nothing: it is the tier you do not take
runtime work from.

These do **not** stop a handler; they are the ranked list of "properties skins set that nothing
renders", which is Phase 5 rendering work rather than runtime work. Top by skins:
`playlist1.itemPlayingColor` / `.itemPlayingBackgroundColor` / `.disabledItemColor` (15 each),
`timeN.upToolTip` (10 each), the `playlist1.itemSelected*` family (9 each). Full column:
`inert_calls` in `census.tsv`. `vidback.alphaBlendTo` (14) was the second row here and is gone:
W38 made it live, and `setColumnWidth` joined this tier in its place — recognised so it stops
aborting its handler, counted `inert()` because nothing draws playlist columns.

---
