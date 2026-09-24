# `.wmz` script, expression, and binding contracts

Moved verbatim from `SKILL.md` on 2026-09-24. The object model these contracts drive is
`reference/object-model.md`.

## Script, expression, and binding contracts

- `WMPScriptRuntime` is the only production route for skin JScript: one persistent `JSContext` per
  skin session, one transaction at a time, expressions then handlers. `reference/object-model.md`
  is the contract for what it exposes; do not add a member without reading its rules.
- A skin's programs evaluate once per session, **after** the view's elements are installed as
  globals and the host objects are bound, because skins run top-level code that touches both.
- Fail closed per handler, never per session: an unrecognised member aborts that one handler and is
  tallied as measured demand. There is no session-wide script kill switch — a skin puts its whole
  startup in one handler, and a kill switch makes that invisible rather than visible.
- **A handler's scope starts at the element it is written on (W216).** A markup handler runs inside
  `with (__wmpWrap('element:<owner>'))`, so `previous()`, `down` and `toolTip='Seek'` mean the
  element's own method and properties — the corpus writes it that way in 20 archives for calls and
  100 for properties. **The arbiter is `WMPObjectModel.recognises`, not the open read surface**, and
  the two rules it enforces are what make the scope safe: an element never claims its own
  `on*`/`*_onchange` attribute names (a `<VIEW onLoad="OnLoad();">` would otherwise swallow the
  skin's `OnLoad` function), and it *does* claim the computed properties `readElement` answers from
  the host, which `computedElementProperties` lists beside it — **a computed property added to one
  and not the other is readable qualified and invisible bare**. See
  `reference/object-model.md` § *An unqualified name in a handler resolves against its own element
  first (W216)*.
- **An inert member that answers a constant is still a phantom.** `mediacenter` was the largest
  cause of a dead handler in the corpus — 159 `ReferenceError`s across 110 of 179 archives (W37) —
  and every one of its nine members is honestly `inert()`: there is no video surface, one effect
  with no type and no presets, no high-contrast mode. But skins *round-trip* these, writing
  `mediacenter.effectPreset` in one view and reading it back in another, so an inert member stores
  session state and answers what was written. A constant looks identical from every instrument and
  is wrong. See `reference/object-model.md` § `mediacenter`.
- **Closing the biggest row raises the ones behind it, and the capture must show both.** W37 took
  the runtime error class 252 → 127 while distinct causes went *up*, 41 → 55: handlers that died on
  their first missing member now reach their second. Never read one row falling as progress without
  re-measuring the whole table in the same capture, and never read lost pixels as a regression
  before finding the statement that hid them — a script that finally runs is a script that finally
  hides panes. `reference/harness.md` § *After W37*.
- **A host command is the script's output, not the drawing's, and it is applied when the
  transaction returns rather than after the scene is presented (W88).** The build and the render are
  the slow half of a transaction, so a view timer that fires during them cancels the task — right
  for the drawing, because a newer transaction is already building a newer scene, and it used to
  discard the commands with it. `Alienware Invader` is what that cost: its 568-frame intro ends on
  the heaviest tick in the skin — `toggleShutter()` swaps `mainBack` to `main_back.png`, turns
  `mainBackGroup1` on and posts `view.timerInterval = 0` — and building that one frame decodes the
  whole player's artwork, overrunning the 50 ms period. The reveal was never presented and the `0`
  never applied, so the timer kept firing with the skin's own `introStatus` now true and the very
  next tick took the *other* branch of `toggleShutter()`, closing the shutter it had just opened.
  Reported live as "it opens to reveal the controls and then closes and stops responding".
  **A transaction that has returned from `transact` has already committed its writes to the runtime,
  so anything downstream of it is not optional.** A command that switches views owns everything
  after it, so this transaction's scene is abandoned rather than drawn over the new view's.
- Authored handlers are selected **per view**. A `.wmz` declares every view in one file, so an
  unscoped scan runs another view's `onLoad` against elements that do not exist in this one.
- Expression reads form a per-view dependency graph. Resolve in stable topological order and commit
  one immutable scene. Missing/ambiguous IDs, cross-view reads, cycles, non-finite values, negative
  sizes, and depth/pass overflow never partially update the visible scene.
- Resizes evaluate from proposed view dimensions off-main. AppKit keeps drawing the last scene until
  the resolved replacement is complete; never synchronously rendezvous with script work.
- `WMPObservablePropertyRegistry` owns both `wmpprop:` and `wmpenabled:`. Coalesce host snapshots,
  retain committed values across batches, and tag origins so script echoes cannot create feedback.
- Host timers enforce the Phase 0 count and period limits. Preferences are bounded and namespaced by
  the SHA-256 of skin archive contents; reset only the active skin namespace.
- Dispatch authored handlers in document order. Host changes use open, play, status, position, mode,
  buffering, then reception order; input uses mouse-down, mouse-up, click/change semantics from the
  Phase 4 capture model.
- **A clock tick is not `status_onchange`, and a transaction's timers are a delta rather than the
  live set (W119).** Both were one path — `refreshHostState` — and both only bite while a track is
  playing, which is why no capture in this harness could see either: every probe ran against a
  stopped, empty-playlist `WMPHostSnapshot()` until `WMP_RENDER_HOST` existed. **`status_onchange`
  means the status *string* changed**, and `player.status` is inert and empty here; raising it on
  every 100 ms position tick made **70 of the 177 measurable archives** re-run their metadata
  handler ten times a second, and since **all 75 authored sources are metadata updaters** — 35 of
  them `updateMetadata()`, whose body is `metadata.value = player.status` — the track readout was
  blanked continuously. Reported as no track information under `9SeriesDefault`, whose
  `ShowStatus(player.status)` drew an empty metadata line beside a correct clock. A tick now raises
  `positionchange`, **a name no archive authors** (0 uses), so it resolves to no handler and is the
  binding-only transaction that lets the 108 archives' elapsed readout and the 89 archives' seek
  slider settle; a `duration` change is a media opening rather than a clock ticking and keeps the
  status raise. And **a transaction that registered no `setTimeout` must not cancel the ones already
  running**: `timerRequests` is what *that* transaction asked for, so replacing the set wholesale
  killed every script timer in the skin within 100 ms of pressing play, and restarted the survivors'
  sleeps from zero. `applyTimerDelta` adds, honours `clearTimeout` (the context reports cleared
  tokens too, because a cleared token can belong to a transaction long past), leaves a running token
  alone, retires a one-shot when it fires, and bounds the *resulting* set. `dispatchTimer` applies
  the delta as well — the WMP idiom is a callback that ends by registering the next step, and
  dropping that made a chain fire once. **Before ranking a "it works until you press play" defect,
  ask what the host refresh is dispatching ten times a second.**
- **An open state and a play state are two different quantities, and pausing changes only one of
  them (W170).** `openstatechange` and `playstatechange` were raised together off `snapshot.state`,
  so every pause told the skin a media had just opened. **109 of the 180 installed archives author
  `OpenState_onchange`** and three answer it by playing — `Plus! HueShifter`, `Plus! Plasma Ball` and
  `Plus! SlimLine` share an `OnOpenStateChange` whose `osMediaOpen` arm ends in
  `player.controls.play()` — so 16 ms after every pause the skin restarted playback, and after a
  stop the re-play found the player stopped and **reloaded the track from zero**. Reported live as
  *"pressing pause does not pause the stream"*, then *"stop does not stop"*. Each event now rides its
  own quantity: `WMPMainWindowController.stateEdgeEvents` compares `state` for one and
  `openState` — derived from whether anything is open, the same derivation `arguments(for:)` and the
  object model use — for the other. **Raising an event for a quantity that did not change is not a
  harmless extra**: the handler behind it is written to act, and here it acted by playing.
  **It is also the sharpest case yet of what a corpus sweep cannot see**, and the reason the rule is
  extracted as a static rather than left inline: the harness seeds *one* host snapshot and never
  transitions, so this edge is never computed headlessly, and the click sweep reported `action=pause`
  dispatched correctly in all 149 skins it drove. The measurement is the app's own log — a
  `pause` immediately followed by `play(): Starting streaming playback`. It reproduces only through
  the streaming path (a Plex/Jellyfin track); with a local file the same re-play lands on an
  already-loaded engine and is invisible, which is how a first live pass cleared it wrongly.
- **A new media opening is an open edge even though the open state never left `osMediaOpen`
  (W275).** `openState(for:)` answers `osMediaOpen` for as long as the queue is non-empty, and WMP
  steps through `osMediaChanging` … `osMediaOpen` for every track, so an audio track change raised no
  `openstatechange` at all. `pharaoh` writes its title only from `OnOpenStateChange`, so after a Clear
  and re-add it read "Stopped" through any number of played tracks. `stateEdgeEvents` now also raises
  it when a media is open and **`metadata.sourceURL` changed, or `playlistIndex` and the metadata
  changed together** — the tracks of one cue sheet share a file. Neither half alone qualifies: a sort
  or move changes the index with nothing opened, and a stream's ICY title changes the metadata with
  nothing opened. **Next while stopped opens a media too**, so the three Plus! skins whose
  `osMediaOpen` arm calls `player.controls.play()` start playback there — WMP's own behaviour for
  them. Measured live on a 3-track cue with an A/B switch: off, the clock reset on every next and the
  title stayed on the first track. `WMP_VIDEO_TRACE`'s `VIDEOEDGE` line does not print for this
  edge — it fires only when the state, the `os*` number or the picture size moves.
- **Hover is two events and a gate.** Crossing from one control to another raises `onMouseOut` on
  the node left *before* `onMouseOver` on the node reached — a skin that fades a readout in on entry
  never fades it back out otherwise — and nothing is raised while the pointer stays inside the same
  node. Unlike every other dispatch site, a hover edge runs a transaction **only where the markup
  authored a handler for it** (`WMPMainWindowController.hoverEvents`): the pointer crosses a whole
  row of buttons on the way to the one it wants, and a transaction rebuilds and re-renders the
  entire scene. Hover *artwork* is unaffected by any of this — it never went through script.
  Measure it with `WMP_RENDER_HOVER`; `onmousemove`, `ondblclick`, `onfocus` and `onblur` are the
  same shape and still unraised.

### A `<TEXT>` is sized by its glyphs, including on the frame before any layout exists

`WMPScriptContext.perform` syncs every element's `left/top/width/height` from **the layout the skin
is currently drawn at**. On the opening transaction there is no such layout, so the sync is skipped
and every geometry property an element did not author falls through to the object model. For a
`<TEXT>` the honest answer there is not the unset-numeric 0: a text node is sized by its own glyphs,
and `WMPObjectModel` measures it the way `WMPSceneBuilder.intrinsicTextSize` does — **trimmed**,
because `literalString` trims and a frame the script runtime computes has to agree with the frame
the builder lays out. An authored dimension, a script assignment and a real laid-out frame all still
win; the measurement is only ever the answer for a dimension nothing else has stated.

Three rules come out of W218, and the first is the one worth carrying to unrelated work:

- **A defect that repairs itself on the first interaction is still a defect, and the corpus sweep is
  the only instrument that sees it.** `Colorchooser` chains its five transport buttons
  `left="jscript:<prev>.left+<prev>.width"`; with every width answering 0 they stacked on one pixel,
  the webdings glyphs overprinted, and the first click anywhere in that row fired **previous**
  because `prevbutton` is last in z-order. The relayout that click triggers is the first one there
  is, so the row is correct from the second click onward. Hand-testing cannot reproduce it — the
  reporter tried and could not — and `reference/skins/colorchooser.md` had filed it as *not a
  defect* on the strength of the mechanism alone.
- **`WMP_RENDER_SETTLE` does not stand in for an event.** Settling pumps the run loop and drives
  `onTimer`; it does not raise the input that creates the first layout. A cold `WMP_RENDER_CLICK`,
  one point per process, is what distinguishes "correct" from "correct after one wasted click".
- **Frame 0 is a state a user is always in.** A skin gets exactly one first frame and the first
  click lands on it, so a rule that only holds from the second transaction holds for nobody.
