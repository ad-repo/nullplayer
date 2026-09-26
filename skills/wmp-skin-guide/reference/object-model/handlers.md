# `.wmz` object model: handlers, scope and timers

Moved verbatim from `reference/object-model.md` on 2026-09-25; that file is the router. Read it first.

## An unqualified name in a handler resolves against its own element first (W216)

In WMP an event handler's unqualified names resolve against the element the handler is **on**, before
anything else. It is why one file writes `visEffects.next()` in one place and a bare `next()` in
another and expects both to work, and why `<BUTTONELEMENT onClick="player.settings.mute = down">`
reads the button it is written on.

**Closed 2026-09-22.** A markup handler is evaluated inside `with (__wmpWrap('element:<owner>'))` —
the same scope a geometry expression gets — at all four dispatch sites in `WMPScriptContext`: the
event, `value_onchange`, `<attribute>_onchange` and the completion cascade. It is **not** wrapped in
a function: a handler's `var` is the skin's global (`corona` declares `g_playlistIsVisible` in one
handler and reads it in every other), and a `with` block keeps it there. The `value` and
`<attribute>` globals the call sites bind stay, because they are bound for the element that *raised*
the event, which is not always the one the handler is written on.

**What made it safe is `WMPObjectModel.recognises`, and it was wrong at both edges.** The `with`
proxy asks it for every identifier, and it is deliberately narrower than the open property surface
the read path answers with — an element that claims every name swallows the skin's own functions.
The corpus sweep found both corrections; neither was visible from the code:

- **An authored *handler* attribute is not a name the element owns.** A `<VIEW onLoad="OnLoad();">`
  authors `onload`, so the element answered the bare `OnLoad` with the attribute's own text and
  `corona`'s entire startup died on `OnLoad is not a function`. `recognises` now declines any
  `on*`/`*_onchange` name; WMP raises those, it does not expose them as properties.
- **The computed properties `readElement` answers from the host must be claimed.** `textWidth`, the
  `<EFFECTS>` selection (`currentEffectType`, `currentPreset`, and the two titles) and the `<VIDEO>`
  flags are not authored and not standard, so a bare `textWidth` threw while `metadata.textWidth`
  beside it answered — `Asia`'s `onEndMove="scrolling = textWidth > width"`, which is how a marquee
  decides to scroll at all. `computedElementProperties` is that list and lives next to
  `readElement`; **a computed property added there and not here is readable qualified and invisible
  bare.**

**Measured 2026-09-21 over the 184-archive corpus** with
`python3 scripts/wmp_handler_scope_census.py`, which scans the decoded script text — the census
drives `onLoad` and this demand is in `onClick`, which is the W100 blind spot — and repairing the
`01 00 01 00` local headers the way `WMPArchiveHeaderRepair` does, without which
`Need_for_Speed_Underground` and `SplinterCellWMPSkin` drop out silently. The scan's encoding
breakdown, which a correct one reproduces: 158 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM.

| half of the class | measured |
|---|---|
| unqualified **call** — the recorded row | **31 uses / 20 archives**: `previous()` 10, `next()` 8, `alphaBlendTo` 4, `nextEffect` 1. Resolving a handler through the call graph (handler → the skin's own function, three levels) adds **nothing**: the idiom is written in the attribute itself. |
| unqualified **property**, net of the `value` and `<attr>_onchange` globals already bound | **255 unresolved reads + 249 silent writes / 100 archives**: `down` 196/89, `toolTip=` 114/40, `left`/`top` 108/9, `width` 34/25, `scrolling` 20/17 |

**The call half is the row and is not what carries it.** `player.settings.mute = down` on a sticky
mute button is 89 archives on its own; before this a read threw
`ReferenceError: Can't find variable: down` — so the button latched and the player never muted —
while a write silently made a global and never reached the element, which is `toolTip='Seek'` and
`scrolling=false` reporting success and changing nothing.

Reproduce either half with `WMP_RENDER_CLICK`: `circle` at `vMain@69,68` (the visualizer fringe)
posts `command=stepEffect value=-1`, and `9SeriesDefault` at `vPlayer@394,309` — the mute button's
mapping colour, found the way harness/live-loop.md § *Auditing one authored control* prescribes, **median
pixel, never the first** — posts `command=setMute value=1`. Both printed the `ReferenceError` on the
`CLICK` line before. The corpus sweep across the change is **551 of 553 images identical and every
structural invariant byte-identical**; the two that moved are `Revert (1)`, whose authored idle fade
now runs, and `Scooby-Doo_2`, which differs run to run on its own `Math.random()`. Corpus
handler-errors went 69 → 68 — three gone, two new on `Asia`'s own double-escaped `textWidth&gt;width`
that only became reachable once the statement before it ran.
`Tests/NullPlayerAppTests/WMPHandlerElementScopeTests.swift` holds both halves and both guards.

### The element has to have an address, and the authored `id` is not one (W256)

**Both the `with` scope above and the bound `value` global were keyed on `event.targetID`, which is
the skin's own `id` attribute — and the corpus leaves it off wherever it has no script that needs to
name the element.** `anemone`'s ten equaliser bands are
`<SLIDER value_onchange="eq.gainLevel1=value;">` with no `id` at all, so the handler ran with no
scope and no `value`: `eq.gainLevel1 = value` wrote **null** on every move of the drag, the band
never changed, and the thumb settled straight back onto the host's unchanged gain. Reported live as
"an equaliser slider cannot be dragged".

`WMPJScriptEvent` now carries `targetStableID` beside `targetID`, and `WMPScriptContext.perform`
resolves the raising element by stable id where the markup named none. **The dispatch sites already
knew it** — `WMPMainWindowController.handlers(in:event:targetStableID:)` selects the handlers by
stable id, because an element's identifier is not unique across views (W89) — so this is telling the
runtime what the caller had in hand, not a new lookup.

Measured 2026-09-22 over the 184-archive corpus with
`python3 scripts/wmp_slider_drag_census.py` (populations A and A'), which reads each `.wms` out of
its archive — never `grep`, see harness/corpus.md § *A corpus number taken with `grep` is not a corpus
number*:

| class | measured |
|---|---|
| `value_onchange` with no `id` — the reported case | **70 nodes / 35 of 184 archives** |
| any handler with no `id` — the scope half | **1,667 nodes / 101 archives** |

**A handler with no address is invisible to every other instrument**: it dispatches, it runs, it
throws nothing, and `SCRIPT-DIAG` stays silent — the only signature is the *argument* the host
command carries. `Tests/NullPlayerAppTests/WMPEqualizerSliderDragTests.swift` asserts the argument
and keeps the control that shows the null.

## A view runs the functions its own `scriptFile` names (W204/W257)

**One `JSContext` serves the whole skin, so two views that each declare their own `.js` and define
the same top-level name collide: the program evaluated last wins every call, in every view.** WMP
gives each view the scope its own `scriptFile` list builds. `Plus! SlimLine` is the case that
reported it — `perfect.js` on `perfectSkin`, `perfectV.js` on `perfectVSkin`, 17 names in common —
and the horizontal view therefore ran the vertical view's `Init()`, whose `EndVideo()` calls
`switchSkin('perfectVSkin')` and put the skin straight back where it had come from.

`WMPScriptContext` records the top-level functions each program defines as it evaluates them, marks
the names **two or more** programs define, and rebinds only those to the installed view's own
programs whenever a view is installed, restored, or run as a windowless dispatcher
(`applyFunctionScope`). Within one view's own list the later program still wins, which is
evaluation order and unchanged.

**The three things it leaves alone are the contract, not omissions:**

- a name exactly **one** program defines stays shared and reaches every view — a skin whose views
  deliberately share a helper is relying on that;
- a view that declares no `scriptFile` of its own keeps the skin's last-loaded binding;
- **non-function globals are one variable in one scope**, here as in the markup. `perfect.js`'s
  `var currView = "perfectSkin"` and `perfectV.js`'s `"perfectVSkin"` are still the same variable.
  No corpus skin has been shown to need otherwise, and two views' `Init`s writing one flag is also
  how these skins share state. **Measured 2026-09-24 and none needs otherwise (W204)**: `SlimLine`
  re-reads each shared value from a preference in `Init`, `pharaoh`'s `vidIsRunning` is derived
  from the same player state in both views, and the one `holiday_skin` value that crosses views
  (`playlistIsVisible`) is read in `Globe` only by an `onEndMove` nothing there fires.

A case-folded alias from the section below follows the function it aliases when a view rebinds it.

**It reaches 6 of 184 archives** — `Plus! SlimLine` (17 contested names), `holiday_skin` (22),
`pharaoh` (2), `portals` (2), `corona` and `9SeriesDefault` (1), and only four of those change
behaviour: `corona`'s two `OpenMedia`s are byte-identical. The census first said 7, counting
`Sports`, whose archive carries two `.wms` files; the loader takes `ExtremeSports.wms` (WMP0022)
and `saltmine.js` never evaluates. **Count only the programs the loaded definition names.** The
census is also worth re-reading before trusting a re-run: the first pass tried UTF-16 before UTF-8
and accepted any decode with no NUL bytes, so two plain CP1252 `.js` files came back as mojibake
with zero functions in them and the answer was 3 archives instead of 7. Sniff the BOM; a decoder that cannot fail is
the same trap as a `grep` that prints nothing (W256).

`WMP_VIEW_SCRIPT_SCOPE=0` restores the pre-W257 last-program-wins binding — the A/B, in one binary.


## A skin's own function, called in the wrong case (W42)

**JavaScriptCore resolves a global by exact spelling, so a skin that misspells the case of its own
function throws `ReferenceError` and loses every statement after it in that handler.** `elvis.js`'s
`Init()` calls `UpdateMetaData()` against `function UpdateMetadata` on line 17: what went with it
was the rest of `Init` — the two `setColumnResizeMode` calls, the volume slider's position, the
video/visualization pane and `OnPlayStateChange()`. `TDK.wms` binds `onLoad="onLoadVideo();"`
against `function OnLoadVideo`, and six archives bind `onClose="onCloseVideo();"` against
`function OnCloseVideo`.

`WMPScriptContext.aliasCaseFoldedGlobals` installs an alias, and it is **last resort, never a
fold**: only for a spelling that resolves to nothing at all, only when exactly one global
case-folds to it, and only when that global is a function. Element ids cannot be aliased into —
they are objects — and a member call (`player.controls.Play()`) belongs to rule 4's
case-insensitive lookup rather than here.

It runs in two places because the corpus writes the call site in two places. A markup handler is
scanned in `evaluate` before it runs; a **program** is scanned only after the whole set has
evaluated, because the declaration a call needs is usually further down the same file — scanning
`elvis.js` before it ran would have found nothing.

**Three archives declare two top-level names that differ only in case, and they are the reason the
alias is last resort rather than a fold.** `Kids` has both `StartVideo` and `startVideo` with
different bodies, `Cablemusic` has `startProgram`/`StartProgram`, `HOB` has `eqIsOpen`/`EQIsOpen`.
Every one of their call sites resolves exactly, so none of them reaches this path at all, and an
ambiguous fold is declined even if one did.

Measured 2026-09-22 over 184 archives: **16 hold a call site that resolves only case-folded** —
`elvis`, `Plus! HueShifter`, `TDK`, `portals`, `deepbluesomething`, `Secura`, `activate`, `anemone`,
`modernblue`, `holiday_skin`, `Stars and Stripes` and the five-skin US military family. The corpus
sweep across the change is **550 of 553 images identical**, the two that moved being `elvis` and
`Plus! HueShifter` drawing the metadata their handlers now reach, and the third `Scooby-Doo_2`,
which differs run to run on its own `Math.random()` and was cleared with a same-mode control.

**What this does not do is empty the class, and that is the expected shape** (rule 2: unimplemented
is a queue). Each of the four skins that advanced now stops at its *next* genuine gap: `elvis`
`elvis.js:17` → `:21` on `volume_slider`, `Plus! HueShifter` `:15` → `:19`, `TDK` line 2 → 188 on
`g_fUserHasSized`. Those names exist nowhere in their archives in any spelling, so they still throw,
and so does `Plus! Plasma Ball`'s `UpdateMetaData` — **a name no spelling reaches is not this
defect, and inventing a no-op for it is the `inert()` phantom this file exists to prevent.**
`Tests/NullPlayerAppTests/WMPScriptRuntimeTests.swift` holds both call-site halves and all three
guards.


## Ambient `<attribute>_onchange` handlers

**The SDK defines an `_onchange` handler for every attribute of most elements, not a list of five**
(*Ambient Event Handlers*: "when a skin attribute changes value, an event occurs… the name of the
event handler is the name of the attribute followed by `_onchange`"). It is **three** pieces, and
each one is a separate place a name can go missing:

1. **Classification** — `WMPAttributeParser.parse` makes any `*_onchange` attribute a `.handler`.
   A name missing here is not a handler that fails; it is markup classified as a literal, invisible
   to the dispatcher *and* to the `UNKNOWN event` tally. That is the state 387 handlers across 104
   of the 177 measured archives sat in until W129.
2. **Collection** — `WMPScriptViewPlan.attributeChangeHandlers`, keyed by folded attribute, holding
   the **authored** spelling beside the source because the handler reads the attribute by name.
   `value` is deliberately absent: it has its own map and its own two directions (W51/W52), and
   collecting it twice raises it twice in one transaction. The general rule is matched *after* the
   `value_onchange`/`onChange` case for exactly that reason.
3. **Dispatch**, of which there are two, and a name needs the right one:
   * *Element side* — `WMPScriptContext.raiseAttributeChangeHandlers`, in the same transaction as
     the write, bounded the way W87's cascade is: only what the markup declared, each
     `(element, attribute)` at most once, never a re-resolve of the expression set.
   * *Host side* — `WMPMainWindowController.refreshHostState`, off the snapshot diff, for the four
     attributes of the *player* that no script writes and that move underneath the skin:
     `currentPosition` (105 uses / 81 skins), `currentEffectType` (77 / 65), `currentPlaylist`
     (65 / 48), `currentPreset` (40 / 30), `currentMedia` (12 / 9).

**A host attribute needs something to call `refreshHostState` before any of this fires.** Every
other path into it is a track, a 10 Hz clock tick, a transport action or a file open, and the
effect selection is none of them: choosing a visualization from NullPlayer's own menu goes through
`WMPEffectSelection`, so the controller observes `WMPEffectSelection.didChange` explicitly. With a
track playing the position tick hides the gap — the event lands inside 100 ms and looks immediate —
and with the player stopped nothing would have been raised at all. **Check what refreshes the
snapshot before adding a host-side `_onchange`**; a diff nothing runs is a dispatch site that is not
one.

**The failure mode of all three is silence.** Nothing throws, so no diagnostic appears anywhere: the
readout simply keeps the value it loaded with. A headless capture cannot see it either — no
attribute changes in a still — so this class is verified through the live loop, `reference/harness/live-loop.md`
§ *Driving the app*.

**An attribute with no dispatch site stays off `WMPCorpusReportHarness.supportedEvents`**, whatever
its reach — listing one would drop it out of the tally while it still does nothing, which is where
`onResize` sat for three phases. `textWidth_onchange` (21 skins) is the current example: this engine
never moves the attribute. `selectedItem_onchange` (12) is **half** dispatched since W136 — a user's
click on a `<LISTBOX>` row writes `selectedItem` and raises it (`WMPMainWindowController.enqueueListEvent`),
a `<POPUP>` choice still does not — so it stays off the list too.

**A write-back is safe when the host setter is idempotent, and that is a thing to check rather than
assume.** All 40 `currentPreset_onchange` uses are `mediacenter.effectPreset=currentPreset` — the
handler handing the host back the number it was just given — which settles only because
`WMPEffectSelection.setPreset` early-returns on an unchanged value. A setter that re-applied would
have restarted the visualizer on every preset change instead. Same argument as W51's write-backs,
made at the host rather than at the registry.

**Reading a handler's reach is not reading its result, and W129 is the case that proves it.** Of the
four host attributes, only `currentEffectType_onchange` moves a pixel today: `setVisEffectsText()`
paints `visEffectName.value = currentEffectTitle + " - " + currentPresetTitle`, both of which W101
implemented. The other three were talked about as visible and are not — 96 of the 105
`currentPosition_onchange` uses are `seek.value = player.controls.currentPosition`, a number **W120
already supplies** from the declared range, and all 9 `currentMedia_onchange` uses are
`updateAlbumArt()`, whose body is `backgroundImage = "WMPImage_AlbumArtLarge"`, a WMP built-in
pseudo-resource this engine does not resolve. **Read the handler's body before naming a skin to look
at**; the census says a skin asks, never that anything answers.

---

## Geometry expressions

A `JScript:` geometry attribute is evaluated in the real context, so `view.width - svMain.left`
works because `view` and `svMain` are the same live objects the handlers see, and
`Half(view.width)` works because the skin's own `.js` declared `Half`.

Two rules that are not obvious and are both paid for:

- **The owning element is in scope.** Corona's `width="JScript:svBottomLeft.width-left;"` means
  *this* element's `left`. The expression is evaluated inside `with (thisElement)`, and the proxy's
  `has` trap answers **only** for properties the element genuinely owns — not the open surface —
  because an element that claims every identifier swallows the skin's own functions. That exact
  mistake made `GetEqSliderLeft(1)` resolve to an empty string and cost all ten equaliser sliders
  their geometry.
- **A trailing semicolon is authored.** The corpus writes `JScript:view.width-svMain.left;`, which
  is a syntax error inside a `return (…)`.

Expressions resolve in dependency order, measured by running them once and recording what each one
read. A failing expression costs **itself and nothing else**, and a cycle costs only the keys inside
it. The model this replaced emptied the whole ordered list on any single failure (W21).

---

## Timers

There are **two** kinds and a skin uses both.

`setTimeout`/`setInterval` record a bounded request and keep the **function**, not its text: the
request's `source` is `__wmpTimer:<token>` and firing it invokes the stored closure. Re-evaluating a
function's text — all a stateless runtime could do — loses every variable it captured, which is most
of what a skin's timers are for. Count and minimum period stay inside `WMPPhase0Limits`.

**`view.timerInterval` is the other one, and it is how a `.wmz` animates.** It is a host timer, not a
scene property: a write posts `setViewTimerInterval` and the controller runs a repeating task that
dispatches the view's authored `onTimer` handlers at that period, with zero stopping it. The view's
markup `timerInterval` starts it before any script runs. Corona's compact view collapses its video
panel entirely through this — `RegisterTimerEvent` then `view.timerInterval = leastInterval` — and its
player view declares `timerInterval="4000"` to drive its transport readouts. Wiring `setTimeout` and
not this left both views frozen in their authored state with no diagnostic anywhere to say why.

**An `onTimer` with no `timerInterval` beside it ticks at WMP's default second, not never (W260).**
The SDK's default for the attribute is 1000 ms, and a view that asks for the event and leaves the
period unstated is asking for that — which is exactly the period a clock wants.
`authoredTimerInterval` answered `0` for an absent attribute and **every caller reads `0` as "this
view has no timer"**, so the handler was registered and never once raised. `Stealth` writes its
elapsed readout from `OnTimerTick()` and nothing else, so it sat at the authored `00:00` through a
whole track while the visualizer ran beside it — reported as the skin not playing at all, which is
the shape of this class: *nothing on screen says the timer is the thing that is missing.*
**7 views in 7 archives** author it (`Stealth`, `digitaldj`, `Revert`, `Revert (1)`, `Grinch`,
`Erektorset`, `Josie_and_the_Pussycats`), against 199 views / 90 archives that state a period;
measured 2026-09-22 over 184.

**An authored `0` still means off**, and must stay off — that is WMP's meaning for it and the corpus
writes it deliberately (`corona`'s `viewTiny` opens stopped and starts its own clock from a script).
Only an *absent* attribute takes the default, and only where the view authors the handler, so a view
with no `onTimer` keeps costing nothing.

---

## `sourceURL` is spelled the way WMP spells it (W41)

**Every corpus consumer of `player.currentMedia.sourceURL` classifies the string rather than opening
it, and every classifier is written against Windows syntax** — `cd:` for a disc, a backslash for a
file, anything else for the network. A macOS `file:///Users/…` matches none of them, so the member
resolved, the handler ran to the end, and **nine archives lit their *network* lamp for every local
track**, two of them with a buffering readout behind it. The member has answered since W115; the
value was the whole of what was left under the row.

So the conversion lives at the host boundary — `WMPAudioEngineHost.sourceURLSpelling`, the same seam
that states `crossFadeWindow` in milliseconds because WMP does. A file URL is stated as the
drive-rooted path a Windows player would state; **nothing else is touched**, because an `http://`,
`mms://` or server URL is already the string WMP would report. Nothing in this engine reads the value
back — it is a readout, never a route to the file.

Re-measured 2026-09-22 over 184 archives with the `WMPTextDecoder` decode: **19 uses / 14 archives**,
against the "4 skins" the row carried. The split is what makes the spelling decidable rather than a
matter of taste:

| Idiom | Archives | Needs |
|---|---:|---|
| `search(/cd:/i)` then `search(/\\/i)` — the CD/local/network lamp | 8 | a backslash |
| the same, but `search(/:\\/i)` (`Kids`) | 1 | the drive colon too |
| `indexOf('http')` (`Cablemusic`) | 1 | either spelling works |
| `search('://')` to drop URLs from a query (`digitaldj`) | 1 | **not** `file://` |
| `item(0).sourceURL.indexOf('wmpdvd:')` (`Compact`) | 1 | a playlist item's real URL |
| displayed, as the last-resort middle line (`Revert`) | 2 | a path a person can read |

**A playlist item's `sourceURL` answered the item's *title*** until the same change —
`WMPPlaylistItemSnapshot` carried no URL at all — which is what `Compact` and `digitaldj` were
testing. `name` is the title; `sourceURL` is the URL, spelled as above.

**The two host paths that rebuild `metadata` must carry it.** A local film rebuilt the struct with a
title only and dropped the source with it, so every classifier read a film as a stream; the cast path
has no URL to state and honestly states none.

---
