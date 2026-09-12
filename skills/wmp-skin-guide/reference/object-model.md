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

5. **`WMPImage_AlbumArtLarge` and `WMPImage_AlbumArtSmall` are WMP-owned pseudo-resources.** They
   resolve before archive lookup and are backed only by the current track's artwork, asynchronously
   loaded by the WMP session from local tags, supported servers, or a stream artwork URL. They are
   200px and 75px square respectively, preserve aspect ratio, and draw transparent until artwork
   arrives. The skin never receives a URL, token, `Track`, or any other host object. No other
   `WMPImage_*` spelling is accepted: in particular `WMPImage_AdBanner` remains unresolved because
   NullPlayer has no equivalent surface.

## Elements

Every element id is a global, and a write to one of its properties mutates the retained graph and
marks it dirty. Element state lives for the whole session: that is the difference between a click
that toggles a pane and a click that does nothing.

The **property** surface is open — a WMP element carries far more properties than this engine draws,
and refusing `hoverFontStyle` on a `TEXT` would abort the handler that sets it, which in Corona is
the whole of `InitControls`. An unauthored, undrawn property is stored and answers `inert`, so the
census can rank "properties skins set that nothing renders" instead of losing them.

### The `<EQUALIZERSETTINGS>` element

`enable` / `enabled` is handled at load time as declared host state: it turns NullPlayer's existing
equalizer on or off. `enableSplineTension`, `splineTension`, and `bypass` have no corresponding DSP
control here. They retain authored and script-written values so a skin can round-trip its own state,
but every read and write is recorded as `INERT` and produces neither a host command nor a scene
mutation (W134). In particular, `bypass` is not silently treated as the inverse of `enable`.

`eq.enhancedAudio`, `wowLevel`, `truBassLevel`, `speakerSize`, and `currentSpeakerName` are live
audio-enhancement members; see [audio-enhancements.md](audio-enhancements.md) for their typed command
path and the temporary -1 speaker-cycle rule. They are separate from the inert spline/bypass fields.

### The `<EFFECTS>` element

`EFFECTS` and `WMPEFFECTS` are the same surface and both map to `.effects`. Only the second was ever
a kind, and 183 uses across 166 of 177 archives spell it the first way, so the visualization surface
of nearly the whole corpus fell to `.unknown` and was hosted on nothing (W101).

Four members answer live, off `WMPHostSnapshot.effects`, and they are the same selection
`mediacenter` holds:

| Member | Answers | Reach |
|---|---|---|
| `currentEffectType` | the effect's id; writable, and a write commands the host | 66 archives |
| `currentPreset` | the preset number within that effect; writable | 66 |
| `currentEffectTitle` | the title a skin draws beside the rect | 61 |
| `currentPresetTitle` | the running engine's own preset name | 42 |

and three methods cycle it: `next()` (82 archives), `previous()` (74) and `nextPreset()` (4).
`settings()` (9) is **not** implemented — it opens WMP's own visualizer property sheet, which has no
counterpart here. A skin's authored type (`spikes`, `ambience`, `random`) names a WMP visualizer this
player does not have, so it selects nothing and the read-back answers what is really on screen.

Still unhonoured on the element: `windowed` (125 archives), `allowAll` (11), `clippingColor` (44) and
`clippingImage` (12).

### Playlist kinds

`WMPElementKind` models three spellings and they are not interchangeable. `PLAYLIST` and
`ITEMSPLAYLIST` are both **lists** and both map to `.playlist`; `DROPDOWNPLAYLIST` is a chooser and
maps to `.dropdownPlaylist`, which is hosted as an `NSPopUpButton`.

**`ITEMSPLAYLIST` maps onto `.playlist` wholesale, and the corpus is the evidence rather than the
name** (W97). 13 of the 179 measured archives declare one — `corona`, `Optik`, `anemone`, `aoe`,
`bluegrid`, `cerulean`, `claw`, `Cubist`, `gadget`, `gnome`, `modernblue`, `pharaoh`, `polygon` —
and **not one declares a `PLAYLIST` beside it**, so it is the only playlist those skins have. Every
one authors list geometry (226x174, 187x139, 155x116 …) and `PLAYLIST`'s own attribute vocabulary:
`backgroundColor`, `foregroundColor`, `itemPlayingColor`, `backgroundImage`. A separate kind would
have bought nothing. While it fell to `.unknown` it never became a `WMPWidget`, so W93's routing —
which correctly stands NullPlayer's own playlist aside whenever the skin declares one — left those
users with an empty drawer.

`dropdownVisible` (12 of the 13) asks for a playlist *chooser* above the rows. It is unhonoured
here exactly as it is on `PLAYLIST`, because it needs `player.mediaCollection` — that is W66's
question, and faking it with playlists this player invented is the thing W66 exists to refuse.

**Recognition for routing is deliberately wider than the modelled kinds.** `WMPSkinSurfaces` matches
on the authored tag, so any tag ending in `PLAYLIST` counts as a skin-owned playlist even before it
is a kind here. What decides routing is what the skin *declares*, not how much of it this engine
hosts today — and keeping the two rules separate is what stops a future spelling from opening a
second, foreign-looking window on top of a drawer the skin draws itself.

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
  141. See `harness.md` § *Counting a tag across the corpus*. Dropping a
  name can only turn a currently-tallied call back into a silent empty string.

Implemented today: `moveTo`, `resizeTo`, `alphaBlendTo` (endpoint applied immediately — the tween is
*not* drawn yet, but the **completion now fires**, see below),
`appendItem`/`removeAllItems`/`getItem` on `POPUP`, `setColumnResizeMode` and `setColumnWidth` on the
playlist kinds — `ITEMSPLAYLIST` among them, and it is a modelled `.playlist` kind since W97 —
`next`/`previous`/`nextPreset` on `EFFECTS`, and `close`/`minimize` on the view.

**A call that lands its endpoint completes in the same transaction (W55).** `WMPObjectModel` records
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
raised by `WMPMainView.mouseUp` for a captured slider, which is where a seek is actually committed;
it is authored only on `SLIDER` (125) and `CUSTOMSLIDER` (16).

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

Initial load treats `openView` and `setCurrentView` identically in one place only: the windowless-view
redirect. A view that never becomes a window can honour neither as a window operation, and both are
a request for which view to show next. A windowless view reached through `openView` at any other time
is the same case: it never becomes a window, and its host commands run against whoever asked for it.

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

## Event arguments

**A `<PLAYER>` event handler is a statement written against a named argument, and the name has to be
bound or the handler dies on its first line.** Corona authors
`playstatechange="OnPlayStateChangeTransport(NewState);OnPlayStateChange();"` and
`status_onchange="OnStatusChangeTransport(status);"`; with neither name bound both threw
`ReferenceError` and everything after the first call was lost — including the line that turns its
`<WMPEFFECTS>` pane on, which is why that skin showed no visualization at all.

`WMPJScriptEvent.Handler` carries the arguments and `WMPScriptContext` binds them as globals for the
duration of that one handler, then clears them — the same shape a control's bare `value` uses, and
for the same reason: a stale `NewState` left standing would be read by an unrelated later handler
instead of failing honestly.

| Event | Argument | Value |
|---|---|---|
| `openstatechange` | `NewState` | the `os*` open state, the same number `player.openState` answers |
| `playstatechange` | `NewState` | the `ps*` play state, the same number `player.playState` answers |
| `status_onchange` | `status` | `player.status`, which is inert and empty here |
| `currenteffecttype_onchange` | `currentEffectType` | the selected effect's stable id, the same string `<EFFECTS>.currentEffectType` answers |
| `currentposition_onchange` | `currentPosition` | the playback position in seconds, the same number `player.controls.currentPosition` answers |
| `currentpreset_onchange` | `currentPreset` | the selected effect preset's index, the same number `<EFFECTS>.currentPreset` answers |

**They belong to the handler and not to the transaction.** One refresh raises `openstatechange` and
`playstatechange` together and `NewState` is a *different* enumeration in each, so a single binding
for the whole transaction would be wrong for one of the two. Measured demand is small — 6 of the 180
installed archives name `NewState` in a handler attribute and 5 name `status` — and the cost of not
having it was every statement after the first in those skins.

**An ambient `<attribute>_onchange` handler reads the attribute by its own authored name**, and it
is the same binding for the same reason: 68 of the corpus's 77 `currentEffectType_onchange` uses are
`mediacenter.effectType=currentEffectType`, which without the name bound is a `ReferenceError` on
the first statement. `currentMedia` and `currentPlaylist` are deliberately **not** bound — WMP's are
objects, this engine has no JS object to stand for either, and all 77 of their corpus sources call a
skin function (`updateAlbumArt()`, `getVisMeta()`, `updateMetadata('playlist')`) rather than reading
the bare name. Binding a scalar in their place would answer a question the skin never asked.

**`WMPScriptConstants` carries the whole enumeration for the same reason.** A skin switches over all
of `WMPOpenState`, and one missing global (`osMediaWaiting`, in Corona's case) is a `ReferenceError`
that costs the handler — the W37 class rather than a gap in a table nothing reads.

---

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
attribute changes in a still — so this class is verified through the live loop, `reference/harness.md`
§ *Driving the app*.

**An attribute with no dispatch site stays off `WMPCorpusReportHarness.supportedEvents`**, whatever
its reach — listing one would drop it out of the tally while it still does nothing, which is where
`onResize` sat for three phases. `textWidth_onchange` (21 skins) and `selectedItem_onchange` (12) are
the current examples: this engine moves neither attribute, so neither has anywhere to be raised from.

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

---

## Adding a member

1. Measure first: `WMP_CALL_TRACE=1` over the corpus, and take the top `UNRECOGNISED` row.
2. Implement it in `WMPObjectModel` — `live` if there is a host behind it, `inert()` if there is
   not, and leave it out entirely if neither is honest.
3. Add it to `WMPJScriptCompatibility.members` in the same change; that table is what the census's
   static `UNKNOWN member` tally is measured against.
4. Re-measure. The next member is now visible; the list you started from is already stale.
