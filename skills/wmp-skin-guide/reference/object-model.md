# The `.wmz` script runtime and host object model

**This file is the canonical reference for what skin JScript can reach.** `WMPObjectModel.swift` is
the executable source of truth; this explains the shape, the rules, and how to add a member without
making the demand tally lie. The probe flags that measure it are in `reference/harness.md`.

---

## The shape

One persistent `JSContext` per **skin session**, on one WMP-owned serial queue
(`WMPScriptContext`). Inside it:

- the skin's own `.js` programs, evaluated **once** at session start, in declaration order;
- every element id of the current view as a global, backed by live element state;
- `player`, `player.controls`, `player.settings`, `player.currentMedia`, `player.currentPlaylist`,
  `player.network`, `eq`, `theme`, `view`, `mediacenter`;
- WMP's own enumeration constants (`osMediaOpen`, `psPlaying`, …) as globals;
- `setTimeout` / `setInterval` / `clearTimeout` / `clearInterval`, host-executed and bounded;
- nothing else. `ActiveXObject`, `WScript`, `Enumerator`, `VBArray` and `GetObject` are explicitly
  undefined, and a bare JavaScriptCore global has no `fetch`, `require`, `XMLHttpRequest` or file
  API of its own.

`WMPScriptRuntime` is the actor around it: one transaction at a time, expressions then handlers,
returning a `WMPScriptOutput` of scene overrides, host commands, timer requests, diagnostics and the
call trace. Reads answer off an immutable `WMPHostSnapshot`; writes become typed host commands the
main actor applies. Nothing in the model touches `AudioEngine`, AppKit or the file system.

**Why it is in-process at all** — and what that costs — is Amendment 2 in
`docs/wmp-skin/phase-0-decision-record.md`. Read it before changing the boundary.

---

## The three resolutions

Every member access is recorded as one of these, and `WMP_CALL_TRACE` prints them as `ok`, `INERT`
and `UNRECOGNISED`:

| Resolution | Meaning | What happens |
|---|---|---|
| `live` | a real host value or a real effect | answers, or posts a command |
| `inert` | recognised, answered, nothing behind it | answers a documented default; **counted separately** |
| `unrecognised` | not implemented | throws, aborting *that handler only*, and is tallied as demand |

`inert` exists because of the most expensive class of phantom bug this subsystem can carry: a member
that is recognised and returns something plausible disappears from the demand tally and reads, from
every instrument, exactly like a working one. Some members cannot be anything else — `theme.loadString`
names a string inside `wmploc.dll`, which does not exist on macOS — so they answer and say so.

**The rules that follow from that:**

1. **Do not add a member you cannot implement.** If it has no host behind it, mark it `inert()`.
2. **Unimplemented is a queue, not a set.** Each member added lets the scripts run further and
   surfaces the next one. Re-measure with `WMP_CALL_TRACE=1` after every change; never work down a
   static list.
3. **Fail closed per handler, never per session.** There is no `scriptsDisabled`. A skin puts its
   whole startup in one handler, so one missing member already costs many unrelated features; a
   session-wide kill switch made that invisible instead of visible.
4. **Member lookup is case-insensitive.** WMP's objects are IDispatch and the corpus spells the same
   member both ways in one file (`player.currentMedia.getItemInfo` and
   `player.currentmedia.getiteminfo`). A case-sensitive bridge answers `undefined` for a call that
   works in WMP.

---

## What a property read answers, and who wins

Three rules, each of which was a live defect first:

1. **An element answers the geometry it is *drawn* at.** Every transaction is handed
   `WMPScene.scriptGeometry` — the local frame of every node the last scene resolved — and element
   state is synced from it before anything runs. WMP's `element.height` includes a height that came
   from background artwork or an alignment stretch, and a script tests exactly that: Corona's
   `ResizeY` animates `svVideo` to 0 and **gives up on the first tick if it reads 0 to begin with**,
   which is what an authored-attributes-only model reports for an element sized by its bitmap.
2. **A script value outranks the markup.** `visible` is resolved from the override before the
   authored attribute — Corona's `SetPane` switches its video and visualization panes purely by
   writing `vid.visible` / `vis.visible`, and a builder reading only markup draws whichever the
   author left on.
3. **A script value outranks the artwork's natural size.** The intrinsic size of a background bitmap
   fills in an *unstated* dimension; it never overwrites one the skin computed. It did, and every
   rebuild stamped 241 px back over the height the script had just set.
4. **Artwork is a scripted property like any other, and the view root is not an exception.**
   `WMPSceneBuilder.resolveResource` used to read the authored attribute alone, so images were the
   single property class the override path skipped while geometry, colours, slider metrics and text
   all went through it (W75). `Alienware Invader` hides its whole player behind a 568-frame intro
   whose every tick is `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"`, and its `mainView`
   drew **nothing at all** until the override was consulted. Three rules the fix is made of, and each
   is a way of getting it wrong:
   - The override carries an **authored path string**, so it resolves through
     `archive.resolve(_:relativeTo:)` under the same provider rules as markup. It is not a file path
     and it is not trusted.
   - A path the skin does not contain **warns (`WMP0023`) and leaves the authored artwork in place**.
     A mistyped frame name must never blank a node that has something to draw.
   - `""` is an **authored absence**, not a missing file: it clears that name the way an absent
     attribute does, which is how every store-thumbnail `previewView` drops its splash bitmap
     alongside the zero-size collapse. `view.backgroundImage` is on the `view` compatibility list for
     that reason — the view root resolves it like any other node, so the tally must not call it
     unknown.

   The image store keys its cache on the canonical resource path, so a scripted swap is a different
   key and a different decode; the scene owns no image state of its own.

## Elements

Every element id is a global, and a write to one of its properties mutates the retained graph and
marks it dirty. Element state lives for the whole session: that is the difference between a click
that toggles a pane and a click that does nothing.

The **property** surface is open — a WMP element carries far more properties than this engine draws,
and refusing `hoverFontStyle` on a `TEXT` would abort the handler that sets it, which in Corona is
the whole of `InitControls`. An unauthored, undrawn property is stored and answers `inert`, so the
census can rank "properties skins set that nothing renders" instead of losing them.

The **method** surface is closed. `WMPObjectModel.elementMethodVocabulary` lists the names WMP
defines as element methods; one of those that this engine does not implement stays `unrecognised`
rather than falling into the open property surface. Without that, `svPlaylist.moveTo(…)` reads as an
empty string, dies with a bare `TypeError`, and never appears in the tally that ranks the work.

Implemented today: `moveTo`, `resizeTo`, `alphaBlendTo` (endpoint applied immediately — the tween is
*not* drawn yet, and its `onEndMove`/`onEndAlphaBlend` completion is W55),
`appendItem`/`removeAllItems`/`getItem` on `POPUP`, `setColumnResizeMode` and `setColumnWidth` on the
playlist kinds including the unmodelled `ITEMSPLAYLIST`, and `close`/`minimize` on the view.

`WMPObjectModel.implementedElementMethods` is the flat set of those names, and
`WMPJScriptCompatibility.members["element"]` is derived from it rather than restating it. That
matters as much as the implementation: the corpus census classifies a member against that table, so
one the runtime answers and the table does not know is measured as demand for something that already
works. `moveTo` and `resizeTo` were counted that way from Phase 3 until W38 closed, which is part of
why `alphaBlendTo` read as the largest row on the backlog.

`alphaBlendTo(target, ms)` writes `alphaBlend`, which is the same property the scene builder inherits
down a subtree, so a faded-in container brings its children back with it. Two details are
load-bearing:

* `alphaBlend` is in `standardElementProperties` — a write commits as a mutation even on an element
  whose markup never authored it — but deliberately **not** in `standardNumericProperties`, because
  an unset numeric property answers 0 and an unset `alphaBlend` is 255. `readElement` holds that
  default. A skin stepping its own alpha (`x.alphaBlendTo(x.alphaBlend - 64, 200)`) would otherwise
  start from invisible and never come back.
* The endpoint is clamped to 0-255. The builder normalises by dividing by 255, so an unclamped
  endpoint would multiply a subtree's inherited alpha past opaque.

`textWidth` is **measured**, not stored. It is the one element property whose answer this engine has
to compute, because 92 of the 180 archives use it to decide whether to marquee —
`metadata.scrolling = (metadata.textWidth > metadata.width)` is the idiom, and `WoW` runs it on every
metadata change. Falling into the open property surface answered the unset-numeric `0`, so every one
of those skins concluded its text fits and the marquee could never start. It measures the element's
*live* `value` in its live `fontFace`/`fontSize`/`fontStyle` through `WMPTextMetrics`, which is the
same code the renderer lays the line out with — the comparison has to be against what is drawn, and
a second measurement path would drift from it. `scrolling`, `scrollingDelay` and `scrollingAmount`
are in `standardElementProperties`/`standardNumericProperties` for the reason `alphaBlend` is:
`WoW`'s markup authors the two numbers and never `scrolling`, so a write to it would otherwise be
stored inert and never reach the scene.

`setColumnWidth` is recognised so it stops aborting the handler that calls it, and counted
**`inert()`**: nothing draws playlist columns. `setColumnResizeMode` predates the `inert` convention
and is still counted live; that is a known inconsistency, not a statement that a resize mode does
anything.

## `theme.openView`

WMP opens the named view as an **additional** window and `theme.closeView` closes it; that is what
separates it from `theme.currentViewID`, which *replaces* the presented view. This app has one WMP
window, so `openView` posts its own `openView` host command and `WMPMainWindowController` presents
the view, pushing the view it covered onto `openedViewStack` (capped, cleared when the skin is torn
down). `closeView` pops that stack and switches back; only with an empty stack does it still order
the window out, which is what it always did.

It is **live**, not `inert()`: a view is presented as a result, and the skin's own close button
returns from it. What is lost is the extra window — an auxiliary panel covers the player instead of
sitting beside it. That reduction is the whole of the deviation and is written here because nothing
in the call trace can show it.

Two things it is deliberately **not**:

- **Not an alias for `setCurrentView`.** The two mean different things to the host, and collapsing
  them in the object model would erase the distinction before the controller could act on it — the
  return path is the part that depends on knowing a view was *opened* rather than switched to.
- **Not extended to `theme.openViewRelative`.** That variant places the opened window at an offset
  from the current one (`theme.openViewRelative('vwEQ', 0, 130)`), which is meaningless with one
  window; aliasing it here would present the view, silently drop the offset, and vanish from the
  demand tally. It stays unimplemented and is tracked as W50.

Initial load treats `openView` and `setCurrentView` identically in one place only: the windowless-view
redirect. A view that never becomes a window can honour neither as a window operation, and both are
a request for which view to show next.

## `mediacenter`

WMP's Media Center host object: the video surface, the visualization ("effects") selection, and the
shell's own localised strings. It was the largest single thing stopping a handler in this corpus —
**159 `ReferenceError: Can't find variable: mediacenter` across 110 of the 179 measured archives**,
each one killing an `OnLoad` on whichever line first touched it (W37).

**Every member of it is `inert()`, and that is the finding rather than a shortcut.** There is no
video surface to zoom (`imageSourceWidth`/`Height` already answer 0 for the same reason), the
engine draws exactly one effect with no type and no presets (`WMPEffectsSurfaceView`), and there is
no high-contrast mode. Nothing here has a host behind it to be live about.

What it is **not** is a stub that answers a constant. Skins round-trip these — `Plus! Professional`
writes `mediacenter.effectPreset = visEffects.currentPreset` in one view and reads it back into a
control in another — so a write stores **session state** and the next read answers it, exactly as
`player.settings.autoStart` does. A constant would break the read-back while looking identical from
every instrument.

The corpus asks for exactly these nine names and **never uses `mediacenter` as a bare identifier**,
so the table below is the whole object. A tenth name stays `unrecognised` and ranks itself.

| Member | Default | Why that default |
|---|---|---|
| `videoZoom` | `100` | WMP's own 100%. Nothing is scaled; the number is what a skin's zoom readout prints |
| `videoStretchToFit` | `false` | nothing is fitted to anything |
| `videoShrinkToFit` | `false` | as above. Corpus use is write-only |
| `effectType` | `""` | one effect, and it has no type |
| `effectPreset` | `0` | one effect, and it has no presets |
| `showTitles` | `false` | no titles are drawn over a video that does not exist |
| `showEffects` | `true` | the effects surface *is* always drawn, so `myeffect.visible = mediacenter.showEffects` is right |
| `contrastMode` | `""` | no high-contrast mode. The corpus tests it `== "BW"` / `== "WB"` and falls through to its normal path |
| `getNamedString(name)` | `""` | the same `wmploc.dll` string table `theme.loadString` names, reached by a second route (`BuyMusicButton`, `BuyMusicURL`, `PLCID` — the WMP store's own resources) |

`contrastMode` is the host's accessibility setting and is **read-only in WMP too**, so a write to it
stays `unrecognised` rather than being quietly accepted.

Two things this deliberately does not do:

- **It does not answer the paren form.** Nine skins author
  `currentEffectType="jscript:mediacenter.effectType();"` on a `<WMPEFFECTS>`, which WMP accepts
  because IDispatch allows a property get with parentheses and JavaScriptCore does not. The
  expression fails, costs itself alone, and is tallied as an `expression-error` — visible, on an
  attribute this engine's one effects surface does not read anyway.
- **It is not a route to the visualization subsystem.** `effectType`/`effectPreset` naming a real
  NullPlayer visualization would be a capability, not a member: it needs a `<WMPEFFECTS>` that can
  host one and a host snapshot field to answer from. Neither exists, and inventing a mapping here
  would make the demand disappear while nothing changed on screen.

---

## `theme.openDialog`

`FILE_OPEN` posts an `openFileDialog` host command and answers the empty string, counted **inert**.
WMP hands the chosen path back to the script synchronously; an `NSOpenPanel` is main-actor work that
the script queue must never block on (`DispatchQueue.main.sync` is banned in this subsystem), so the
host opens the picker and plays the result while the skin's own `player.URL = newFile` line does
nothing. It is not cosmetic: **WMP mode has no other route to a track**, because the auxiliary
NullPlayer windows stay hidden until they have WMP-owned chrome, and before this the only way to
start playback was to leave WMP mode and come back.

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

---

## Adding a member

1. Measure first: `WMP_CALL_TRACE=1` over the corpus, and take the top `UNRECOGNISED` row.
2. Implement it in `WMPObjectModel` — `live` if there is a host behind it, `inert()` if there is
   not, and leave it out entirely if neither is honest.
3. Add it to `WMPJScriptCompatibility.members` in the same change; that table is what the census's
   static `UNKNOWN member` tally is measured against.
4. Re-measure. The next member is now visible; the list you started from is already stale.
