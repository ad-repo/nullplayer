# `.wmz` compact mode and script-resized windows

Moved verbatim from `reference/rendering.md` § *Static scene and image contracts* on 2026-09-25; the router is
`reference/rendering.md`. Before an engine-wide change here, check the counter-evidence table in
`reference/skins/README.md`.

- **Compact mode is authored by 11 archives, and the button every skin has is not it — audited 2026-09-12.**
  The corpus splits three ways and conflating them wastes a session. **Real compact toggles: 11 skins**, by two
  mechanisms — a switch to a smaller view (`corona`, `9SeriesDefault` → `viewTiny`; `Main_Street` slim/mini;
  `T3-Skynet_Media_Player`; `digitaldj`; `holiday_skin`; `portals`) and an in-place `view.width`/`view.height`
  write (`Cablemusic`, `Goo`, `iconic`, `Melvin`). Every one of them was clicked in the running app with a track
  playing and **10 of the 11 change the window**: 859x468→596x468, 593x600→475x373, 324x253→163x114,
  288x255→79x70, 440x336→280x130, 516x496→214x49, 317x330→400x81. `portals` is the exception and its cause is not compact mode:
  the walk opened the wrong view (**W153**, closed 2026-09-13) and the right one turned out to drag the window
  instead of clicking (**W154**). `digitaldj` works from `DigitalDJMid` and not from `DigitalDJ`, which is W152. **The
  five *"Return to Player/Main Mode"* buttons are video-mode returns, not compact** (`Plus! Professional`,
  `QuickSilver` ×2, `TripleX` ×2, `xXx_night_vision_redx`) and all reach `setCurrentView` cleanly. **And the
  button the reporter meets in nearly every skin is `view.returnToMediaCenter()` — 162 archives, 196
  controls, 179 of them tooltipped "Return to full mode".** It toggles the Library Browser (opens when hidden, closes when visible) since W100 closed on
  2026-09-13; before that it was dead in every one of them, which is why *"the compact button does nothing"*
  was that button and not compact mode. Name the skin and check it against this list before reading such a
  report as a compact defect.
  **This button's glyph is not its meaning, and a report about it is usually about the glyph
  (W176).** Re-derived 2026-09-19 over the 185 installed archives: **204 controls in 169 archives**,
  and *every one* tooltipped some spelling of "Return To Full Mode". **139 of them are
  `<BUTTONELEMENT>` with no image at all** — a mapping colour on a shared bitmap — 61 are
  `<BUTTON>` and 4 are bare `<RETURNBUTTON>`. Of the 65 that name a file the stems are
  `full`/`fullmode`/`max`/`fullbutton`, **and 5 are `close*`**: the notice-view close boxes, which
  is why those five now close their window instead (W176). So the same call wears a maximize box, a
  full-mode arrow, an unmarked colour region and, in five skins, an X — and a reporter naming the
  icon is not naming the control. **Read the authored `id` and `upToolTip` off `WMP_RENDER_PROBE`
  before believing any report that identifies one of these by what it looks like.**

  **`WALL-E` is the worked case, and the lesson is the button order rather than this button.** Its
  `mainView` system strip is **minimize, full mode, close** left to right at `305,4` / `333,4` /
  `361,4` — Windows order, where macOS puts close leftmost. Read left to right as macOS, that gives
  *"the X to close maps to minimize and the minimize maps to library toggle"*, which is what it was
  reported as. All three are correct: `WMP_RENDER_CLICK` at each centre hits the button under it,
  the bitmaps are a dash on the left and a red X on the right as authored, and driven live the X
  leaves 0 windows with the process alive while the dash leaves `AXMinimized=true` with 1. A
  `.wmz` is a Windows skin and orders its title strip the Windows way; **check the strip's order
  before reading a report that names two of its buttons.**

  Rapid library toggles require `WMPMainView.acceptsFirstMouse` so the click after the library
  takes focus still activates the skin control, and WMP-only `animationBehavior = .none` in
  `WindowManager.showPlexBrowser` so native window animations do not race visibility. Verified
  on New Super Mario Bros with six consecutive clicks about 0.3 seconds apart, then user-confirmed.
  **A window bigger than the compact artwork is not a defect here**: `corona`'s `viewTiny` is authored 596x498 and
  draws a 346x103 mini player into it, exactly as its markup asks — WMP shapes that window with the transparency
  key and this engine leaves it transparent, which looks the same. Measure the window, not the ink.

- **A view's own size is the one expression input a handler can change out from under the pass that
  already read it, and the builder can refuse the change (W99).** `WMPScriptContext` resolves the
  `JScript:` geometry before the handlers run — a pane positioned off another must see the frame that
  pane lands at — so a handler that assigns `view.width`/`view.height` leaves every expression
  reading it a transaction stale. **And `canvas = resizeLimits.clamp(…)`, so a view declaring
  `minWidth`/`minHeight` has a floor its own script cannot write through**: `ALXMorph` is
  `<view id="videoView" height="357" minHeight="357">` and `onLoadVid()` assigns 316, which the
  canvas rejects while the script goes on answering it. The transaction now clamps the view element
  to its own limits and re-resolves the expressions against that; `WMPScriptRuntime` reports the
  clamped size as `viewSize`, so the window, the next transaction and the expressions carry one
  number. **Re-resolving against the *raw* assignment instead is the defect with more reach** — it
  walked `Back to the Future Trilogy/videoView` to `x=-94` — which the 20-archive sweep caught and
  no single-skin check would have. `EXPR`'s two columns are the instrument: `->` is the initial
  resolver against the canvas, `live=` is the runtime's, and **a disagreement between them where the
  deps are only `view.width`/`view.height` is this class and nothing else** (corpus-wide: 809 before,
  0 after). **A view with an `onTimer` hides it**, because the next tick opens a transaction at the
  corrected size — `xsn_sports` read as a drawer button drifting 20 px rather than as a broken
  window. 217 corpus views author the shape and **146 have no timer and never correct**, which is
  part of what W68's "draws a shell" has been all along.

- **A script resizing its own window is four separate claims, and `Compact.wmz`'s drawers needed all
  four (W184-W192, 2026-09-16).** They are listed here because each one *renders perfectly* in a
  capture and does nothing on screen: the builder takes its canvas from the script's overrides, so
  every headless probe agrees with the skin while the window stays where it was. **Read `viewSize=`
  on the `CLICK` line, never the picture.**
  1. **One axis is a resize.** `assignedViewSize` demanded an override for *both* `width` and
     `height`; this skin grows only the width for one drawer and only the height for the other, so
     it answered nil and the window never moved (W186).
  2. **The axis the transaction did not assign is the *window's*, not the one left in the
     overrides.** Those are cumulative, so a handler touching only the height re-asserted a width
     from ten minutes ago and undid the user's stretch (W188).
  3. **A script-assigned alignment is anchored at the canvas it was assigned at, and the canvas moves
     *within* the transaction.** `SetAlignment(false)` → `view.width += rightMove` →
     `SetAlignment(true)` is how a skin says *the body keeps its size and the space I just added is
     the drawer's*; measured from the authored size instead, the body stretched over the drawer it
     had opened (W185).
  4. **A piece pinned to an edge rides it through a resize in the same handler.** The same idiom
     with `right`/`bottom` instead — `SnapToVideoSize` — must move the piece, because this engine
     lays out once per transaction and the middle state otherwise never exists. Without it the
     drawer stays put while the window grows past it and **its tab ends up outside the window, where
     nothing can ever click it again** (W192). One archive in the corpus assigns an alignment from
     script, so 3 and 4 can move nothing else.
  Two more from the same report are about *when* the window moves, not what size it takes: a script
  transaction rebuilds at the **window's current size**, never the last scene's (a transaction in
  flight across a user resize otherwise re-presents the stale canvas and stores it, permanently —
  W187); and the frame is set in the **same main-actor turn as `present`**, because resizing ahead
  of the render leaves AppKit stretching the old picture into the new frame — reported as "a big UI
  flash when the drawer opens" (W190). See `reference/skins/compact.md`.

- **`view.size(corner)` blocks in WMP, and a skin's resize bracket is built entirely out of that
  (W225, 2026-09-18).** 235 calls in 88 of the 185 archives, every one of them `onMouseDown`, and
  the statements *after* the call are what the skin does when the drag is over. `Compact`'s
  `DoSize()` pins `playlistDrawer` to `right` and `settingsDrawer` to `bottom` so both ride the
  window's corner, calls it, and unpins them. Nothing here can block, so the pin and the unpin both
  landed before the first pixel moved: the drawers kept their absolute positions while `playerView`
  (`stretch`) grew over them, and their tabs ended up buried under the body where no click could
  reach them. Reported as *"when you stretch compact skin it breaks the drawers and the main body
  will absorb them and also not allow them to close"*. Three claims, and the report needed all three:
  1. **The mutation count is the seam.** `WMPObjectModel.resizeCallMutationIndex` records where the
     call fell; `WMPScriptRuntime` holds the tail and `resumeAfterWindowResize` replays it against
     the size the window finished at. **Gated on `animatesTweens`** for the same reason a tween is
     (W194) — that is the caller promising it is a window, and only a window runs a drag — so a
     render dump, the corpus census and the windowless dispatcher still run the handler straight
     through and every measurement taken against them holds.
  2. **The tail is the *last* word on the release, not the first.** Raised at the top of `mouseUp`,
     it fell straight through into the ordinary control path, whose `mouseup`/`click` dispatch calls
     `presentation.scriptTask?.cancel()`. The unpin lost that race and `playerView` stayed pinned
     `left`/`top` while both drawers stayed pinned to the corner — a player drawn small in the
     top-left with its drawers stranded out at the window's edges, for the rest of the session. It
     is raised from a `defer`.
  3. **Assigning an alignment freezes the element where it is *drawn*, and the extent half of that
     must stay out of the geometry overrides.** WMP re-measures the margins at the write, so the
     unpin must not teleport the drawer back to its authored `left`. But
     `WMPSceneBuilder.ownAuthoredSize` reads the geometry overrides and **is what every child's own
     alignment delta is measured from**: written there, `SetAlignment(true)` made `playerView`'s
     authored 422 read as the 754 it had been dragged to, and its whole chrome — tiles, corners,
     the transport strip — saw a zero delta and collapsed back to the authored arrangement inside a
     754-wide frame while both drawers sat correctly at the edges. Reported as *"the drawer and
     resizing is totally broken in every way"*. The origin half is an ordinary script-assigned
     coordinate; the extent half is `WMPSceneOverrides.scriptAlignmentExtent`, consulted only by the
     `stretch` case. **One archive in the corpus assigns an alignment from script**, so 3 can move
     nothing else — verify with a decoded scan for `.horizontalAlignment =` before touching it.
  **Drivable only live**, and `WMP_RESIZE_TRACE=1` is the instrument: read `release script=true`
  against the `resume` that must follow it. See `reference/skins/compact.md`.

- **The window edge is ours, and AppKit takes it before the view can (W227).** `WMPMainView` has
  carried a 6pt edge band since W193 and for a real drag it had never run: a `.wmz` window is
  `[.borderless, .resizable]`, and `.resizable` alone is enough for AppKit to claim a press near the
  frame in `NSWindow.sendEvent` and run its own resize loop — the view is sent no `mouseDown`, no
  `mouseDragged` and no `mouseUp`, and the window is resized entirely outside the skin. A *click* on
  the same pixel does reach the view, which is why the band read as live and why `edge-band press`
  only ever printed for gestures that resized nothing. `WMPSkinWindow.sendEvent` claims the press
  first, and only where the view says no control is there, so a control drawn against the window
  edge keeps every pixel it had.
  **What the bare band skipped is the skin's bracket, and the corpus is emphatic about it**: 69 of
  the 87 archives authoring `view.size` run something after the call, and in 68 it is one idiom —
  `saveVidSize()` / `onVidSetSize()` / `g_fUserHasSized = true`, persisting the size the user just
  dragged to. Pulled by the edge, the window resized and the skin forgot it the moment the view
  closed. So the band raises the view's own grip handler (`WMPResizeGrip` names the node; 233 of the
  234 corpus calls are spelled into the handler attribute and the one that is not is `Compact`'s
  `DoSize()`, so it resolves one hop through the skin's scripts), W225's machinery holds the tail,
  and the release replays it. `beginScriptResize` **adopts** a drag already under the pointer rather
  than refusing it: refusing answers `false`, which is the caller's signal that no release is
  coming, and the held tail would then run mid-drag against the size the window started at.

- **`<RETURNBUTTON>` is the command, not a button that happens to be there (W191).** 19 uses across
  15 archives and **15 author no `onClick` at all** — the element's own behaviour is the return to
  the media centre, so treating the kind as an ordinary button left the library unreachable from
  those skins. It posts `toggleLibrary` only when the markup authored nothing: `anemone` and
  `modernblue` spell `view.returnToMediaCenter()` themselves, and doing both toggles it twice.

- **A `.wmz` compact mode is a script resizing its own window, and it is the script's output rather
  than the drawing's (W113).** `SwitchSmall()` writes `view.width = 475; view.height = 373` and
  swaps one shell for another. Three separate things had to hold and none of them did:
  **the view root reads its own size overrides before its markup**, like every other node — the
  literal used to win, so a `<VIEW width="593">` could never be resized by its own script;
  **the size a script assigns is not the size alignment is measured from** — `ownAuthoredSize` stays
  the markup's, because `LostPlanet`'s `onLoadInfo` opens with `view.width = view.minWidth` and
  collapsing the delta to zero stopped its stretch tiles covering the 61 px they were covering,
  punching holes through the window frame; and **it is committed in the uncancellable half of the
  transaction**, beside the host commands, because with a track playing a `status_onchange` lands
  five times a second and cancels the click's task after its render (W88). The overrides had already
  committed, so the *next* rebuild drew the compact player at the old canvas — a 475x373 player in a
  593x600 window, which is the "large overlay" that was reported. `WMPScriptOutput.viewSize` carries
  it, keyed off the **mutations** so an expression-driven `<VIEW width="jscript:…">` — which already
  read the window's current size — is not mistaken for a resize request. A non-positive result is
  not a size: that is the store-thumbnail collapse, and ten more `mediaSwitcherView`s joined the
  documented `WMP0035` windowless class when the override finally reached the view root.
