# `.wmz` script transactions, tweens and visibility

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

- **The skin's own JScript is ES3, and `JSContext` is not — `WMPJScriptDialect` is where that is reconciled (W86).** WMP9's `corona_tiny.js` chains its compact-mode animation by appending a timer event to the array its `TimerDispatch` is enumerating with `for-in`. JScript visits the appended index; JavaScriptCore snapshots and does not, so the chained event was dropped on the tick it was registered and the whole WMP9 family could neither collapse its video panel nor get back to `vPlayer`. Corona's 2002 script splices the array instead and is unaffected, which is what made `corona` the control and `9SeriesDefault` the case. The rewrite is bounded, skips strings/comments/regex literals, and leaves a program with no `for-in` byte-identical; **3 of 180 archives use `for-in` at all and one depends on the live semantic**, so the corpus sweep is the proof it changed nothing else. **Before ranking a "the script runs and nothing happens" defect, ask whether the handler depends on an ES3 semantic** — no headless probe here can see that class, and the live `INPUT script-diag` line stays silent because nothing throws. And when you add to this file's scanner: **test a CRLF fixture.** Swift folds `"\r\n"` into one `Character` that is not `"\n"`, and the first version of the rewrite silently did nothing to the entire corpus for that reason while every LF-only unit test passed.

- **A `<property>_onchange` fires in the same transaction as the write that triggered it, and the view's `JScript:` geometry expressions are *not* re-run to achieve the same thing.** A `.wmz` animates by writing geometry once per timer tick, so a pane positioned off a moving one has to move in the same frame; letting it catch up on the next transaction tore the compact view into two visible halves that closed four seconds later (W87). Only what the skin declared is raised — 16 geometry `_onchange` attributes across 6 archives — bounded and once per property per transaction, so two panes positioned off each other cannot loop. **Re-resolving the expression set after the handlers is the tempting general form and it is wrong**: those attributes are an initial layout rather than a live binding, and several read the property they write (`left="JScript:svBottomLeft.width-left"`), so re-running them moved 175 of 545 corpus images and shattered `Back to the Future Trilogy`'s `videoView` and `ALXMorph`'s frame. That is what a sweep is for; it was reverted on the measurement, not on taste.

- **A tween's endpoint is not readable by the rest of the handler that started it (W112).** WMP
  animates `moveTo`/`resizeTo`/`alphaBlendTo` over the call's duration argument, so an element's
  `left` still answers where it *is* for the remaining statements — and skins are written against
  exactly that. `Cablemusic`'s playlist tab is `onClick="PlayListMove();HidePlist();"`: the first
  slides the drawer, the second reads `subPlayList.left` to decide whether it is now open or shut.
  With the endpoint applied inside the call that read answered the destination, so closing the
  drawer never hid the playlist and it stayed over the player forever — reported as "the playlist is
  always showing". **A duration of zero is not a tween** and applies immediately, which is what
  `movePlayButton()`'s `moveTo(x, 116, 0)` toggle depends on.

- **And the tween now runs for the duration it was given, but only where something is drawing
  frames (W194).** For four phases the endpoint landed at the handler boundary and the completion
  was raised in the same transaction, so a 1,000 ms slide took one frame and nothing in the corpus
  ever animated — reported against `Compact`'s drawers as *"its not a smooth opening"*. **The
  decision is made per transaction, not per call**: `WMPScriptRuntime.transact(animatesTweens:)` is
  a caller promising a frame clock, and only a window has one. A render dump, the corpus census and
  the windowless dispatcher (W89) do not, and for them the call behaves exactly as it did before —
  endpoint at the handler boundary (W38), completion from it (W55) — so **the settled state is
  identical either way and every measurement taken against a headless probe still holds**. That is
  also why a sweep cannot see this row at all; it is drivable only live.
  With a clock, `WMPObjectModel` holds the motion as a `WMPScriptTween` (channels with `from`/`to`,
  duration, completion event), the runtime keeps it per view scope, and
  `WMPMainWindowController.startTweenLoop` steps it at 30 fps through
  `WMPScriptRuntime.tweenFrame` — a real transaction per frame, so the interpolated value is
  written through the object model, becomes a mutation and therefore a scene override, and the
  element reads where it *is* mid-slide. Three things still arrive instantly under a clock, each
  because a frame would be a guess: a duration of zero, a channel already at its destination (its
  completion is raised at once, or a sequence chained off a no-op move would stall), and a channel
  whose current value the model does not hold — which is why `alphaBlendTo` on an **unauthored**
  `alphaBlend` still arrives rather than fading, and the ALX family keeps the subtrees it depends on
  arriving. A later call on the same element and property **replaces** the one running, so a drawer
  re-toggled mid-slide reverses from wherever it is.
  **The callback is the load-bearing half.** Moving `onEndMove` from end-of-handler to end-of-tween
  changes when 36 views chain their next step: `Compact` shrinks its own window inside
  `Playlist_OnEndMove`, so the window now shrinks a beat after the drawer starts closing, which is
  what WMP does.

- **And `load` carries a clock too, which is the half W194 left out (W253).** It was enabled on the
  click and view-timer paths only, so a tween a skin authored in its `onLoad` still landed its
  endpoint in one frame — `Revert (1)`'s `onLoad="vwPlayer_OnLoad();alphaBlendTo(40,9000);"` is the
  clean case, a nine-second fade to translucent that arrived fully faded before the window was ever
  shown. **`WMPMainWindowController` has two load sites and the row named the wrong one**: ~1348 is
  `theme.openView`, the skin's *extra* windows, while the player itself opens on the skin-load walk
  at ~404. Both now pass `animatesTweens:` and call `startTweenLoop`; fixing only the first
  compiled, passed, and changed nothing on screen. `WMP_LOAD_TWEENS=0` is the A/B and
  `WMP_TWEEN_TRACE=1` the instrument — see `reference/harness.md`.
  **W194's stated risk did not materialise, and it was measured rather than reasoned about**: an
  `onLoad` sequence chained through `onEndMove` now presents its pre-tween state and completes a
  beat later, exactly as WMP does. Ten skins A/B'd at t=16 s — `9SeriesDefault`, `corona`,
  `Back to the Future Trilogy`, `Plus! Professional`, `TripleX for XP`, `US Marine Corps`, `WoW`,
  `Rave-MP`, `Revert` — settle byte-identical at identical window sizes.
  **`Alienware Invader` is the one that cannot be A/B'd this way and is the trap worth keeping**:
  it differed, and four runs of it produce four distinct hashes because its intro never settles, so
  the diff is the skin's own animation and not the change. Its ON run ran **zero** tweens, which is
  what says so. A skin that never settles needs a same-mode control before any comparison is read.
  **The corpus numbers on this row are void.** `WMP_TASKS.md` carried 108 of 184 archives and a
  static walk of `onLoad` handlers gives 67; both count markup rather than execution. `Blinx`'s only
  `moveTo` sits inside a `/* */` block, and a walk that follows every call from `onLoad` follows
  branches that never run. Only `WMP_TWEEN_TRACE` can count this, per skin, and it has not been run
  corpus-wide.

- **WMP's `event` object is a global, and 84 of 185 archives read it (W184).** `Compact`'s drawer
  handlers open `view.maxWidth = event.screenWidth` from a plain function call, and its view root
  reads the same thing from a `jscript:` attribute where no event exists at all — so it is bound
  like `player` and `theme`, not like a handler argument. `screenWidth`/`screenHeight` answer the
  window's display (a fixed 1920x1080 headlessly, so a sweep reads the same on every machine) and
  `shiftKey`/`ctrlKey`/`altKey` answer the dispatching event. **`keyCode` stays unrecognised on
  purpose** — 433 uses across 79 archives, and nothing here dispatches `onKeyDown`, so answering `0`
  would tell every one of those handlers that a key it never saw was pressed. A member that cannot
  be answered honestly belongs in the demand tally, not in a default.

- **A call that lands its endpoint completes in the same transaction, and a skin's sequence is
  chained from that completion (W55).** *Superseded in one direction by W194 above: under a frame
  clock the completion is raised when the tween ends instead, and everything below still describes
  the headless path and the mechanism both share.* `moveTo`/`alphaBlendTo` have applied their
  endpoint immediately since W38, so the step that follows was the missing half: `onEndMove` is 247 uses
  across 113 archives, `onEndAlphaBlend` 50 / 21, and **`onEndResize` is zero, so it is deliberately
  not implemented.** `WMPScriptContext.raiseCompletionHandlers` raises them before the geometry
  cascade, bounded and once per `(element, event)`. **The template Microsoft shipped is built out of
  this**: `toggleVidDrawer()` slides the drawer and `onEndMove="checkVidDrawer()"` is the only thing
  that shows or hides its contents, so without it 36 corpus views drew a drawer's controls stranded
  outside a drawer that had already slid shut — and seven views (the `US …` military family,
  `Secura`, `Stars and Stripes`) drew a closed shell with no player in it at all. **Landing this
  removes an accidental compensation, so budget for what it uncovers**: where a drawer fails to open
  for an unrelated reason, the user now sees an empty drawer rather than usable controls in the
  wrong place. `onDragEnd` is the input-side sibling, raised from `WMPMainView.mouseUp` for a
  captured slider, and it is one of the two places a seek commits — see W156 above for the other and
  for how the engine chooses between them. See `reference/object-model.md` § *Methods*, and
  `reference/harness.md` for why an image-only sweep cannot see any of it.

- **An unanswerable `wmpprop:` is not the answer "false", and on `visible` that distinction is a
  whole control (W95).** A path can name a *host* property (`eq.enhancedAudio`) or an *element in
  the skin's own graph* (`plMode.visible`); 1,459 of the corpus's uses resolve to neither today, and
  the registry answered every one with a falsy empty string. The builder deletes a node whose
  `visible` override is false, so `WoW`'s `<PLAYLIST visible="wmpprop:plMode.visible">` — `plMode`
  being a name WMP's own UI owns and this skin never declares — had no paint command, no hosted
  widget and no rows, however many tracks were queued. Reported as "adding to the playlist does not
  work". The rule now has three cases and they were arrived at one sweep each:
  **a host root this engine does not implement stays falsy** (`xsn_sports` hangs its whole SRS WOW
  panel off `visible="wmpprop:eq.enhancedAudio"`, and showing the badge would claim a feature that
  does nothing); **an element the skin *does* declare is mirrored** by `WMPSceneBuilder`, one hop,
  which is what keeps `WoW`'s CD-rip bar hidden behind `wmpprop:playlist2.visible` (150 corpus uses
  of `visible="wmpprop:…"`); **an element it does not declare answers nothing**, leaving the markup's
  own value. Only `visible` declines to default — on every other property the empty string is the
  honest answer, and `wmpenabled:` still disables.

- **A node the script shows is drawn inside a hidden container (W263).** Markup inherits: a
  default-visible child of a `visible="false"` subview stays hidden (2,630 corpus children rely on
  it). An explicit script write of `visible = true` is the node's own answer, though, and the walk
  passes through a hidden ancestor to reach it — the ancestor paints nothing, hits nothing, and
  every child the script did not show stays hidden (`passThroughAncestors` in `WMPSceneBuilder`).
  **Only a show that changes the node's answer counts (W308)**: the node must author a `visible`
  that is not `true` (`"false"`, or a binding). `Gorillaz` writes `vis.visible = true` on a button
  that was never hidden when its left drawer opens, then closes the drawer by hiding `left_ear11`,
  the frame around it; read as an escape, the button floated beside the shut drawer. Blocking at an
  authored-hidden *container* instead is wrong — `US Army`'s Help lives in `help`, authored hidden
  and never shown, and emptied. Every pass-through the corpus needs is an authored-hidden node.
  **And never out of a pane the skin itself closed (W309)**: an ancestor authored hidden that a
  script has shown this session (`WMPSceneOverrides.scriptShown`) and has hidden again closes its
  whole subtree (`closesSubtree`). `US Army`'s `hideinfomode()` hides `infomode` and in the same
  handler sets `infodown2.visible = true` on a scroll arrow inside it; `sflink` sits inside
  `creditsmask`, closed the same way. Both stayed on the face after Info closed. `help`/`credits`
  (never shown) and `Charlies_Angels`' `pos` (authored visible) are not toggles by this rule.
  **Nor out of a pane hidden *after* the show (W311)**: `WMPSceneOverrides.visibleWriteOrder`
  records when each node's `visible` last changed by script, and a shown node escapes only the
  hidden ancestors a script hid before it was shown (an ancestor no script hid counts as before).
  `Navigator`'s `movescren()` shows `vis` inside the authored-visible `visual`, and its
  `showconf()`/`showlist()`/`showlink()` hide `visual` afterwards; read as an escape, the
  visualizer drew over the EQ, playlist and links panes. `Charlies_Angels` is the other order —
  `pos` hidden, then `boxsmall` shown — and still escapes. Only a change of value takes a
  position, so a skin that rewrites the same `visible` on a timer does not reorder anything.
  `Charlies_Angels_Full_Throttle` nests its whole face in `pos`; Gallery hides `pos` and shows
  `boxsmall` (the cut-down face), the wings and the pictures inside it, and the window went empty
  with no way back (Speaker Mode is in a wing). `Stars and Stripes` and its five US-forces siblings
  show Help/Credits text inside `help`/`credits`, which are authored hidden and never shown.
  **A binding's `true` is not a script show (W301).** `wmpprop:`/`wmpenabled:` values land in the
  same `overrides.properties` as script writes, so `WMPSceneOverrides.boundProperties` records which
  addresses a binding wrote last, and a script write clears the mark. Without it
  `visible="wmpenabled:player.controls.pause"` (60 corpus uses) and `…stop` (10) escaped a closed
  panel the moment playback enabled them: `Alpine7618_v09`'s panel visualizer floated over its
  window's transparent top half. A before/after sweep with a playing host over the 50 archives that
  bind `visible` to the player moved 5 skins, each a stray control from a closed panel: `Alpine`,
  `Melvin` (two pause glyphs, from `lefthi` and `little`), `Secura` (the `video` panel's pause over the
  face's stop button), `Creed` (`visual`'s visualizer) and `Charlies_Angels_Full_Throttle`
  (`boxsmall`'s pause in the normal player; it still draws in Gallery, where the script shows
  `boxsmall`).
