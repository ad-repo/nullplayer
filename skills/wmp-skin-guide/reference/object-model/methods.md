# `.wmz` object model: methods

Moved verbatim from `reference/object-model.md` on 2026-09-25; that file is the router. Read it first.

## Methods

The **method** surface is closed. `WMPObjectModel.elementMethodVocabulary` lists the names WMP
defines as element methods; one of those that this engine does not implement stays `unrecognised`
rather than falling into the open property surface. Without that, `svPlaylist.moveTo(…)` reads as an
empty string, dies with a bare `TypeError`, and never appears in the tally that ranks the work.

**The vocabulary is the SDK's element-method list, not a list of names the corpus has been seen to
call (W128).** It is transcribed from the Skin Programming Reference:
[`ambient-attributes`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/ambient-attributes),
[`view-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/view-element),
[`playlist-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/playlist-element),
[`listbox-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/listbox-element),
[`popup-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/popup-element),
[`editbox-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/editbox-element),
[`effects-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/effects-element),
[`buttongroup-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/buttongroup-element).
`VIDEO`, `BUTTON`, `TEXT` and `SUBVIEW` define no methods of their own. Start the next audit from
those pages rather than from a corpus scan — a scan can only find what some skin already calls.

**The rule the audit established: a method outside the vocabulary is invisible to the tally, not
merely unimplemented.** It reaches the open property surface instead, answers `""`, and the call
dies as a bare `TypeError` — the same abort at the same statement, but classified as an *inert
property* rather than as unrecognised method demand, so it ranks in Tier 2b ("recognised, answered,
nothing behind it") when it belongs in Tier 2a. `view.returnToMediaCenter` is the evidence: it had
to be found by a live reporter (W100) because `WMP_CALL_TRACE` could not see it, and
`WMP_CALL_TRACE` is what every row in `WMP_TASKS.md` is ranked from.

Two consequences bind any change to this set:

* **Widening it implements nothing.** `elementMethod(_:_:)` stays the kind-aware authority on what
  actually runs, and `implementedElementMethods` on what the census counts as answered.
  `WMPJScriptCompatibility.members["element"]` is derived from the latter, not from the vocabulary —
  which is why `setFocus` is in the vocabulary and correctly absent from the compatibility table.
* **A name is only ever added, never removed.** The vocabulary gates *reads* as well as calls:
  `readElement` consults it only after `element.properties`, `element.authored` and
  `standardElementProperties`, so an authored or already-written name still answers, but an
  **unauthored bare property read** of a vocabulary name aborts its handler. Before adding a name,
  grep the extracted corpus scripts for `\.<name>\s*[^(]` and confirm the hits are calls or host
  receivers. W128 found exactly one read class — `mediacenter.effectType`, 376 uses across 130
  archives — and it is a host receiver answered by `readMediaCenter` before the element path, so it
  was safe. **Decode the corpus the way `WMPTextDecoder` does when you run that grep**: the first
  W128 scan read every file as UTF-8 and silently skipped the 153 of 392 that are UTF-16, reporting
  141. See `harness/corpus.md` § *Counting a tag across the corpus*. Dropping a
  name can only turn a currently-tallied call back into a silent empty string.

Implemented today: `moveTo`, `resizeTo`, `alphaBlendTo` (**animated over the duration they name
wherever a frame clock is driving them, and applied instantly everywhere else — see *Tweens* below**),
`appendItem`/`removeAllItems`/`getItem` on `POPUP`, `setColumnResizeMode` and `setColumnWidth` on the
playlist kinds — `ITEMSPLAYLIST` among them, and it is a modelled `.playlist` kind since W97 —
`next`/`previous`/`nextPreset` on `EFFECTS`, and `close`/`minimize`/`size` on the view.

**`view.size(corner)` is the resize grip, and on a `.wmz` window it is the only resize there is**
(W193). 235 calls in 88 of the 185 installed archives, authored as
`onMouseDown="view.size('bottomright')"` on a small corner button: `bottomright` in 86 archives,
`topright` in 4, `right` in 3, and `bottom`/`bottomleft`/`left`/`topleft` in 2 each — `Revert` is
the only skin that authors all seven. The window is borderless and has no OS frame, so while this
was inert the user reached for the macOS window edge instead, which skips whatever the skin wraps
around its own resize: `Compact`'s `DoSize()` pins both drawers to their edges for the duration and
unpins them after, and a window widened any other way leaves the drawer behind.

It posts `sizeWindow` with the corner as its value, and `WMPMainView.beginScriptResize(corner:)`
arms the **same** edge drag the window's own resize band runs — one clamp against the view's
`minWidth`/`maxWidth`, one anchored edge, one relayout. Two gates are all it adds: `scene.isResizable`
(the permission the band already asks for — all 88 archives author `resizAble="true"`, so it costs
the corpus nothing), and the left button must still be down, because the call arrives from an
asynchronous script transaction and a quick click's command can land after the release, where arming
a drag would resize the window on whatever the user pressed next. `WMPMainView.mouseUp` no longer
returns early while a target is captured: the grip is a real element, so it has an `onMouseUp` and
an `onClick` to raise and a pressed state to drop.

**What this cannot reproduce is WMP's blocking call.** In WMP `view.size` returns when the drag
ends, so `DoSize()`'s unpin runs afterwards; here a transaction completes before its commands are
applied, so both brackets have already landed when the drag starts. The drag is right, the
bracketing is early, and no arrangement of this pipeline changes that.

### Tweens (W194)

**A duration animates only where something is drawing frames, and the decision is made per
transaction.** `WMPScriptRuntime.transact(animatesTweens:)` is the caller promising a clock. Only a
window has one: `WMPMainWindowController` passes it on the **click and view-timer paths**, and
nothing else does — not a render dump, not the corpus census, not the windowless dispatcher (W89),
and not the load, resize or close paths, where an `onLoad` sequence chained through `onEndMove` has
to have finished before the first present. Without a clock the call behaves exactly as it did before
this row, so **the settled state is identical either way** and no headless measurement on this
subsystem moved. The corollary is that no probe here can see the row at all; it is drivable only in
the running app.

With a clock, `WMPObjectModel.tweenGroup` emits a `WMPScriptTween` — the channels it is moving with
their `from` and `to`, the duration, and the completion event — and writes nothing. The runtime holds
the live set per view scope; `WMPMainWindowController.startTweenLoop` drives
`WMPScriptRuntime.tweenFrame` at 30 fps until the output stops reporting `hasActiveTweens`. **A frame
is a real transaction**: the interpolated value goes through the object model, becomes a mutation and
therefore a scene override, and the element reads where it *is* mid-slide, which is what W112 is
about. Motion is linear — WMP's own easing is undocumented and the corpus slides drawers over two to
four hundred milliseconds. The last frame writes the endpoint itself rather than an interpolation
near it, so a drawer rests on the pixel the skin named.

Three things still arrive instantly under a clock, each because a frame would be a guess:

* **A duration of zero**, which is never a tween and must be readable by the rest of the handler.
* **A channel already at its destination.** Its completion is raised at once, or a sequence chained
  off a no-op move would stall waiting for a frame with nothing to draw.
* **A channel whose current value the model does not hold.** `left`/`top`/`width`/`height` are
  synced from the scene each transaction so they are always there; `alphaBlend` is absent unless
  authored or previously written, and an absent one *inherits* (`WMPSceneBuilder.inheritedAlpha`),
  so the only number a fade could start from is the opaque default. `alphaBlendTo` on an unauthored
  `alphaBlend` therefore arrives rather than fading — which is what the Alienware/ALX family's
  `m_anim_*` subtrees depend on.

A later call on the same element and property **replaces** the one running, so a drawer re-toggled
mid-slide reverses from wherever it currently is. `WMPScriptRuntime.cancelTweens(for:)` and
`discardView` drop a view's motion outright: a view that stops existing has no motion to finish.

**The callback is the load-bearing half of this row, not the tween.** Moving `onEndMove` from
end-of-handler to end-of-tween changes when 36 views chain their next step, and `Compact` shrinks its
own window inside `Playlist_OnEndMove` — so the window now shrinks a beat after the drawer starts
closing, which is what WMP does. `Tests/NullPlayerAppTests/WMPTweenTests.swift` pins both halves,
starting with the no-clock invariant.

**A call that lands its endpoint completes in the same transaction (W55).** *Under a frame clock the
completion is raised at the end of the tween instead; everything here describes the mechanism both
paths share and the timing of the headless one.* `WMPObjectModel` records
`(stableID, event)` on every `moveTo` and `alphaBlendTo`; `WMPScriptContext.raiseCompletionHandlers`
turns each into the `onEndMove`/`onEndAlphaBlend` the markup authored, before the geometry cascade so
a chained step's writes still propagate, bounded by `WMPPhase0Limits.expressionPasses` and once per
`(element, event)` so a handler that moves something again cannot spin. WMP tweens over the call's
third argument and completes when the tween ends; this engine arrives instantly, so the honest
completion is now. **`onEndResize` is deliberately absent: zero archives author one**, so it would be
a dispatch site with nothing to prove it. Measured over 179 archives: `onEndMove` 247 uses / 113
skins, `onEndAlphaBlend` 50 / 21.

Without this a skin's sequence stopped after step one, and the drawer template Microsoft shipped is
built out of it: `toggleVidDrawer()` slides the drawer and `onEndMove="checkVidDrawer()"` is the only
thing that shows or hides its contents. 36 corpus views were drawing a drawer's controls stranded
outside a drawer that had already slid shut.

**An event handler reads its target's `value` as a bare name.** WMP evaluates a handler against the
element that raised it. `WMPScriptContext` binds that one identifier for the duration of the event
and clears it after, rather than scoping the whole element: 111 of the 141 `onDragEnd` sources are
`player.controls.currentPosition = value`, and a bare *assignment* like `toolTip='Seek'` (6 uses)
creates a global and costs nothing either way — so only reads were ever blocked, and `with(element)`
would change name resolution for every handler in the corpus to buy those six. `onDragEnd` itself is
raised by `WMPMainView.mouseUp` for a captured slider; it is authored only on `SLIDER` (125) and
`CUSTOMSLIDER` (16). **A seek commits on release and nowhere else (W156)**, and the release is where
the engine decides whether the skin committed it: a transaction that posts `seekSeconds` owns the
seek, and one that does not hands it back to `WMPMainWindowController`, which commits the value the
pointer left. See `SKILL.md`.

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

`scrollingDelay` remains the skin's authored value in the object model, but the renderer follows
WMP's timing contract: a value below the 30 ms minimum falls back to the 85 ms default. It must not
be clamped to 30 ms or rendered at the invalid value. Plus! Professional authors `10`; treating it
literally scrolls at 200 px/s instead of WMP's roughly 24 px/s at its authored two-pixel step
(W126).

`setColumnWidth` is recognised so it stops aborting the handler that calls it, and counted
**`inert()`**: nothing draws playlist columns. `setColumnResizeMode` predates the `inert` convention
and is still counted live; that is a known inconsistency, not a statement that a resize mode does
anything.

## `theme.openView`, `theme.openViewRelative` and `theme.closeView`

WMP opens the named view as an **additional** window beside the opener and leaves the opener alone;
only `theme.currentViewID` *replaces* a view. That is what this engine now does.
`WMPViewWindowMaterializer` builds one borderless `NSWindow` per open view, all rendering and taking
input against **one shared script runtime**; the first view presented binds the app's own window and
is the player. `openView` posts its own `openView` host command and the controller materializes a
window for it; the calling window's scene is untouched, so — unlike `setCurrentView` — the command
does **not** report "switched view" and the transaction that posted it still draws.

Measured over the 180 installed archives: `openView` 579 uses across **90** skins, `view.close()`
424 across 170, `theme.closeView(name)` 183 across **84**, `theme.currentViewID` 196 across 68,
`theme.openViewRelative` 8 across 2 (`Revert`).

- **`theme.closeView(name)` closes the window showing that view**, and is a silent no-op when it is
  not open. It used to be unrecognised, which aborted the handler on that statement: `Halo 2`'s
  `checkRemoteViewStatus()` dies on `theme.closeView('vidRemoteView')` and never reaches the four
  statements after it. With no argument it keeps the meaning `view.close()` already posts — close
  the window the handler is running in.
- **`theme.openViewRelative(id, dx, dy)` places the new window at `dx,dy` skin pixels from the
  opener's top-left**, on its first placement only, in place of the tiler. `Revert` hangs its EQ
  under the player and its playlist beside it entirely with this call. It was deliberately left
  unimplemented while this engine had one window (W50) — aliasing it to `openView` would have
  dropped the displacement silently and taken the member out of the demand tally, which is the trap
  `INERT` exists for. The offset rides the action (`openViewRelative:<dx>,<dy>`), the way
  `setEQBand:<n>` and `playPlaylistItem:<n>` already do, because a host command carries exactly one
  value and the view id is it.
- **`view.close()` closes the calling window.** Closing an auxiliary window leaves the player
  running — still animating, still holding its own overrides — which is what the covered-view stack
  used to simulate. Closing the **player** closes the whole skin UI, panels and all: leaving panels
  up with no player behind them is the W96 shape, and a player that cannot be closed while a panel
  is open is not a player. The macOS close control means the same thing, so the W127 compensation
  (intercept it and pop the stack instead) is gone with the stack.
- **`view.minimize()` miniaturizes the calling window.**

All of it is **live**, not `inert()`. The former deviation recorded here — "an auxiliary panel
covers the player instead of sitting beside it" — is closed, and with it the three defects it
caused: W90 (closing an interior window closes the whole UI), W96 (the skin is empty and shows no
player) and W127 (the macOS close control strands the user). Each existed only because a covered
view had to be simulated.

**`openView` is still not an alias for `setCurrentView`.** The two mean different things to the host
and collapsing them in the object model would erase the distinction before the controller could act
on it — one opens a window, the other replaces one.

Initial load keeps them apart too, and W175 is what it cost when it did not. A view that never
becomes a window can honour neither as a window operation, and both do say which view to show next —
but only `setCurrentView` is a *replacement*, so the last one wins and nothing beside it can be the
player. `openView` is a window each: `WMPMainWindowController.windowlessSuccessors` makes the
earliest of them in the skin's declaration order the player and replays the rest against it once it
is on screen. A windowless view reached through `openView` at any other time is the same case: it
never becomes a window, and its host commands run against whoever asked for it.

## `theme.loadPreference`

`loadPreference(name)` returns the skin-scoped value previously written through
`savePreference(name, value)`. An absent key answers **`"--"`**, WMP's sentinel for an authored
default that has never been saved; it is distinct from a key explicitly saved as an empty string.
Skins branch on that distinction — `Plus! Professional` uses
`loadPreference("vidRightDrawer") != "--"` to choose its saved drawer state (W76).

## `mediacenter`

WMP's Media Center host object: the video surface, the visualization ("effects") selection, and the
shell's own localised strings. It was the largest single thing stopping a handler in this corpus —
**159 `ReferenceError: Can't find variable: mediacenter` across 110 of the 179 measured archives**,
each one killing an `OnLoad` on whichever line first touched it (W37).

**Seven of its nine members are `inert()`, and that is the finding rather than a shortcut.** There
is no video surface to zoom (`imageSourceWidth`/`Height` already answer 0 for the same reason) and
no high-contrast mode. Nothing behind those has a host to be live about.

**`effectType` and `effectPreset` are the two that left that class (W101).** The `<EFFECTS>` rect
they select for is hosted now, so they answer `WMPEffectSelection` — what is actually being drawn —
and a write posts a `setEffectType`/`setEffectPreset` host command instead of storing session state.
96 archives bind them straight onto the rect (`currentEffectType="wmpprop:mediacenter.effectType"`),
so this is the corpus's own selector and not a menu this engine invented.

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
| `effectType` | live | the id of the effect the rect is drawing: `bars`, `projectm`, `geiss`, `tripex`. Writable |
| `effectPreset` | live | the preset within that effect — ProjectM's preset, Geiss's and Tripex's effect. Writable |
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
- **It became a route to the visualization subsystem only once there was one to route to.**
  `effectType`/`effectPreset` naming a real NullPlayer visualization was a capability rather than a
  member — it needed an `<EFFECTS>` that could host one and a snapshot field to answer from. W101
  built both: `WMPEffectsSurfaceView` hosts `VisualizationGLView` in the authored rect and
  `WMPHostSnapshot.effects` is what these two read. Until then the honest answer was a stored
  string, because a mapping with nothing behind it makes the demand disappear while nothing changes
  on screen.

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
