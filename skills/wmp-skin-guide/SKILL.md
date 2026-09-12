---
name: wmp-skin-guide
description: Windows Media Player .wmz/.wms skin engine, bounded loading, retained graph, compatibility reporting, rendering, the persistent JScript runtime and host object model, and WMP-specific app-mode integration.
---

# Windows Media Player skin engine

Read this skill before changing `Sources/NullPlayer/WMPSkin/` or
`Sources/NullPlayer/Windows/WMPSkin/`. The current security decisions and locked limits are in
`phase-0-decision-record.md`.

**The script runtime and everything skin JScript can reach is `reference/object-model.md`.** It is
the canonical reference for the persistent `JSContext`, the three member resolutions
(`ok`/`INERT`/`UNRECOGNISED`), element and expression semantics, and how to add a member without
making the demand tally lie.

**Not every skin in the corpus is work.** `scripts/wmp_corpus_exclusions.txt` is the blacklist both
corpus scripts read, and a skin belongs on it when no work in this engine changes its outcome —
`Darkling` is authored against WMP's Party Mode host and draws its own "designed for Party Mode"
panel without one, exactly as real WMP does. An excluded archive never ranks work; see
`reference/harness.md`.

**A skin that has taught this engine something has a dossier: `reference/skins/`.** One file per
`.wmz` that produced two or more unrelated defects, or one no probe could see — what it exercises,
what it found, **what was ruled out**, and the decoded coordinates that reach its controls.
`reference/skins/README.md` says when to write one and what belongs in it, and carries the
counter-evidence table: the skins that disagree with a change that looked right, and the rule each
one holds down. Check that table before landing an engine-wide change.

**Measure before you reason.** `reference/harness.md` is the canonical probe and corpus reference —
every env-var flag, the line grammar, `scripts/wmp_skin_census.sh`, `scripts/wmp_render_sweep.sh`,
`scripts/wmp_markup_census.sh`, and the traps those scripts enforce. No other file restates a command; add a flag there in the same
change that adds it. The ranked backlog it feeds is `WMP_TASKS.md` at the repo root, and a closed
entry moves to `docs/wmp-skin/wmp-backlog-archive.md` in the same change that closes it.

**The `phase-*-handoff.md` files are unverified narrative.** Check every claim in them against the
code before relying on it: phase 7 asserts that WMP "remains explicitly unavailable in release/MAS
products through `AppCapabilities.wmpSkinMode`", and `AppCapabilities.supports` returns `true`
unconditionally unless `EDITION_CUSTOM` is defined, which nothing defines. That is a false claim,
not a self-qualified one. The census likewise found their corpus numbers wrong in both directions —
see `reference/harness.md` § "What the harness measured".

## Isolation boundary

WMP is an independent skin engine. Keep engine/model work in `WMPSkin/`, AppKit work in
`Windows/WMPSkin/`, and tests/fixtures under the WMP test paths. Do not teach Classic, Original, or
Winamp Modern types about WMP markup. Change shared application files only when no WMP-owned seam can
satisfy the requirement; keep that seam minimal, gate it explicitly on the WMP controller family,
and prove all existing modes retain their behavior. Record every shared path and the rejected local
alternatives in the phase handoff.

Never put WMP input work on the main thread. Archive validation/inflation, decoding, XML/graph/report
construction, image work, expressions, and script evaluation run on a WMP-owned background
executor — the script context has its own serial queue, so a skin that loops forever wedges that
queue and nothing else. Never use `DispatchQueue.main.sync`. Hand only completed immutable snapshots and typed host
commands to `MainActor`, where the work is limited to AppKit presentation.

WMP owns a dedicated app-authored unskinned player. On a fresh public-release profile with no
persisted mode and before the user has downloaded/imported a skin, launch that WMP view. Missing,
deleted, corrupt, or rejected selections also recover to it while remaining in `.wmp`. Never use an
Original/Classic/Winamp Modern controller, preference, `skin.json`, or artwork as WMP's default or
fallback. Existing users keep their persisted mode.

## Loader contracts

- `WMPPhase0Limits` and stable codes `WMP0001`–`WMP0020` are locked. Production loading must preserve
  their meanings and reject metadata bounds before decompressing payloads. One amendment exists:
  `WMP0005`'s 200:1 ratio is tested only on entries expanding past `entryCompressionRatioFloorBytes`
  (1 MiB), because a ratio is not the quantity a bomb is dangerous in and flat-colour BMPs are not
  bombs — see Amendment 1 in `phase-0-decision-record.md`. It is not a precedent: **never relax a
  limit to make a skin load.** That one held only because the limit was mis-specified against its
  own threat model, and it was argued about the threat rather than about the skins.
- Archive paths normalize Windows separators, use Unicode-composed case-insensitive lookup, and
  reject absolute paths, drive prefixes, traversal, symlinks, collisions, excess wrapper depth, and
  CRC failure. The provider is read-only and never extracts to disk.
- A skin contains exactly one unambiguous `.wms` at root or under one wrapper directory. Resources
  resolve relative to the declaring file and then the skin root, never outside the provider.
- Text decoding is BOM-aware UTF-8/UTF-16LE/UTF-16BE, then a **positional** BOM-less UTF-16 sniff,
  then a deterministic Windows-1252 fallback for unmarked legacy WMP text. Do not guess other ANSI
  code pages, shell out to `iconv`, accept malformed surrogates, or allow embedded NULs.
- XML is parsed by a hand-rolled lenient parser, **not** `XMLParser` — libxml2 aborts on a duplicate
  attribute before the delegate runs, which rejected 4 of 14 archives. It retains authored
  tag/attribute spelling, **attribute document order**, and source locations while bounding depth and
  node count. Unknown elements stay in the graph for compatibility reporting.
- `reference/loading.md` is the contract for both: what is tolerated, what stays fatal, and the two
  things (attribute order, CR-only line endings) that look cosmetic and are not.
- Attribute parsing classifies expressions, bindings, handlers, colors, and resources without
  executing skin code. `res://` and optional missing artwork warn; path escapes and required missing
  scripts fail.
- **TEXT colour roles follow interaction state.** Resolve `hoverForegroundColor` and
  `hoverBackgroundColor` only while the TEXT hit target is hovered, then fall back to the normal
  roles; resolve `disabledFontStyle` only while disabled, then fall back to `fontStyle`. Use
  `WMPAttributeParser.color(from:)` for every role so named SDK colours stay consistent (W131).
- Graph IDs and registry order are deterministic. Duplicate authored IDs are retained and warned,
  not silently collapsed.

Skin JScript runs in one persistent in-process `JSContext` per skin session, on a WMP-owned serial
queue, with the object model as the security boundary — see Amendment 2 in
`phase-0-decision-record.md` for why the helper process was retired and what that costs. An in-app
`WKWebView` remains prohibited.

## Static scene and image contracts

- **A view is sized like any other node: authored literal, then script override, then the natural
  size of its own `backgroundImage`.** WMP skins routinely author `<VIEW backgroundImage="...">` with
  no width or height — the window *is* the bitmap — and demanding a positive literal at the root was
  the largest single cause of a skin that loaded and then drew nothing (89 views across 48 skins).
  The same artwork fallback already applied to every non-root node. **A view with no size and no
  artwork of its own is then sized by the union of the subtree it can place from literals and
  artwork alone** — `iconic` hangs its whole player off one `<SUBVIEW backgroundImage="base.gif">`.
  That union descends into a container whose own size is unknown and ignores `visible`, because a
  skin authors every wrapper hidden and turns one on in `onLoad`. Anything needing script
  contributes nothing, and the builder never invents geometry.
- **A view with nothing to draw is `0x0`, not a rejection, and a literal or scripted zero is an
  authored answer.** A `.wmz` names views that are never windows: 25 corpus skins author a
  `controlView` holding only `<player>` and a hidden `<video>` so an `onLoad` can run with host
  bindings and no window, and `pharaoh` writes the same idea as `<view id="vGhost" width="0"
  height="0">` whose handler redirects. Rejecting them was the last of `WMP0032`. The builder still
  invents nothing — the honest size of empty content is empty — and **`WMPMainWindowController` is
  what refuses to make a window out of it**: initial load walks its candidate list (persisted view,
  then `vPlayer`, then document order) running each view's script and following its `setCurrentView`
  until a view has a canvas, and `switchView` runs a windowless view's script, honours its host
  commands, and stays where it is. `WMPRenderer` still refuses a non-positive canvas; a zero-area
  scene must never reach it.
- **`theme.openView` opens an additional window beside the opener; `theme.currentViewID` replaces the calling window's view. A skin's extra views are real windows.** 90 of the 180 archives call `openView`, 579 times. For four phases this engine had exactly one WMP window and the call was reduced to "present the view here and remember the one it covered" (`openedViewStack` / `CoveredView`) — and **that reduction was itself the cause of three reported defects**, not merely a deviation: W90 ("closing an interior window closes the whole UI"), W96 ("the skin is empty and shows no player") and W127 (the macOS close control stranding the user) each existed only because a covered view had to be *simulated*. `WMPViewWindowMaterializer` builds one borderless window per open view, all against **one shared script runtime**, modelled directly on `WinampModernHostedWindowMaterializer` — the only one of the three other families whose recipe transfers, because a `.wmz` view is an arbitrary authored canvas with no stack to join (Halo 2's panels are 406x209 against a 327x294 player). The first view presented binds the app's own window and is **the player**: the `MainWindowProviding` anchor, the restore anchor, the tiler's anchor, and the only presentation that writes `wmpSkinViewID` or is sampled for `WMPSurfacePalette`. **That window is the app's, not the skin's, and ordering it out is what a *close* means and nothing else** — a skin reload and a mode teardown drop its presentation without touching the window, because the caller is about to put a new skin (or the unskinned view) into it. Sharing one `remove` between close and teardown cost exactly that: `AppStateManager.restoreWindowFrames` calls `restoreFrame`, which reloads the skin when one is already loaded, so **every launch with a persisted `.wmz` and a saved frame ordered the main window off screen** with nothing anywhere to put it back. Reported as "main windows launch minimized". An *auxiliary* window is ordered out either way — it belongs to the skin, and a skin going away must not leave its panels behind. `theme.closeView(name)` closes the named window (84 skins, and every one of them had been aborting the handler that called it) and `openViewRelative` places the new window at its authored offset from the opener's top-left (W50 closed). **The drawer exception is what this does not touch**: Corona's sliding playlist and equaliser and NVIDIA's embedded modes are `<SUBVIEW>`s of the presented view's own canvas, never reach `openView`, and behave exactly as they did. See `reference/object-model.md`.
- **The app menu must open a skin-owned auxiliary surface through `openView`, never `switchView`.** The reason has changed and the rule has not: `openView` is the call the skin's *own* button makes, so routing a menu toggle through it means the panel behaves identically however it was opened — its own window, its own close. `switchView` would instead replace the player's view with the panel, which is what it means, and it is not what a menu item asking for a playlist means. `revealSkinSurface` routes every off-screen WMP surface through the `openView` host command. `WindowManager.wmpSkinShowsInActiveView` asks about **any open WMP window**, not the one presented view, so a toggle for a playlist already up reports checked-and-inert rather than opening it twice.
- **Do not mistake an in-place mode for an auxiliary view.** NVIDIA is the counterexample: its playlist and video layouts live inside `mainView`, while its top-right control still calls `view.close()`. There is no window of its own to close, so treating that command like an EQ close hides the player and leaves its last embedded mode as the apparent main window. The guard used to read "nothing has been opened over the player" and now reads "this is the player and it is the only window open" — the same statement in the new vocabulary. NVIDIA's close route instead runs its authored audio transition, first clearing its `videoItem` preference because `audioModeToggle()` otherwise redirects back into video mode. The installed-skin key is `NVIDIA` — `WMPSkinImporter` removes `.wmz` — so a compatibility guard must compare the installed name, not the archive filename. `WMPPhase9Tests.testNVIDIAEmbeddedPlaylistCloseReturnsToAudioMode` holds the route down.
- **A skin sound effect must not abort its state transition.** NullPlayer does not play bundled WMP skin sounds, but `theme.playSound(...)` is an inert host call rather than an unrecognised member: AlienMorph opens its shutter, plays `intro.wav`, then stops its intro timer. Throwing on the sound call skipped the stop and re-toggled the shutter every second.
- **A view the skin never shows can still have to keep running, and a view it only covered has to come back as it was left.** Two different things this engine used to treat the same way — "not the presented view, therefore gone" — and each is a whole class of dead controls. **A windowless view that declares `timerInterval` + `onTimer` is a *dispatcher*** (W89): 24 of the 180 archives author `<view id="controlView" timerInterval="100" onTimer="checkRemoteViewStatus()">` and route their panel, minimize and close buttons through it — the button does not call the host at all, it writes `theme.savePreference('remoteCallPl','true')` and that handler reads it back. Real WMP keeps it open beside the player. `WMPMainWindowController.adoptDispatcher` **scans** for it after presenting; keying it off the candidate walk works only on a profile with no persisted view, because `wmpSkinViewID` is written on every present and the walk then stops at the player. It runs through `WMPScriptRuntime.dispatch`, which commits no overrides and does not consume the observable-property changes — a dispatcher has no window, so it has no scene — and its elements are swapped in and the presented view's swapped back, objects and all, because every view root is called `view`. **And `theme.openView` opens a *second window*: the opener is never touched** (W90). That used to be simulated — the covered view's overrides, its timer period and its animation clock were stashed and a `closeView` return was a *restore* rather than a load, because rebuilding it discarded the overrides its script had accumulated and reinstated the markup `timerInterval` the script had overridden. On `Alienware Invader` that returned to `commands=0` and let the markup's 500 ms re-fire `toggleShutter()` with `introStatus` already true, shuttering the whole player; reported as "closing an interior window closes the whole UI". **The simulation is gone and so is everything built on it** — `CoveredView`, `openedViewStack`, `switchView(to:restoring:)` and `WMPScriptRuntime.prepareForRestore` — because the opener is now genuinely still running in its own window, which is what the restore was imitating. What survives is the primitive underneath: `WMPScriptContext.restoreElements(for:)` swaps each window's live elements in for the length of its own transaction, since one `JSContext` serves them all and every view root is called `view`. A genuine view change still loads exactly like a launch (W46).
- **A view arrived at by a switch loads exactly like one arrived at by launch, and a `.wmz` compact mode is built entirely out of that.** `switchView(to:)` raises `load` on the new view, applies the host commands the handler posts — *after* `apply`, which sets the view timer from markup, so the script's `setViewTimerInterval` is the override and not the other way round — and schedules its `timerRequests`. It did none of the three for a long time (W46), and Corona's `viewTiny` is authored `timerInterval="0"` and animates itself into the mini player from `OnTinyLoad` alone: the switch happened, nothing ran, and the compact view drew **the same artwork at the same size as the player**. The only visible symptom was the playlist and equaliser drawers going away, because `viewTiny`'s markup does not have them. Two consequences bind: the initial-load `collapsed` guard applies here too, since a view can now blank itself in an `onLoad` this path finally runs; and `viewchange` is dispatched only when the markup authors a handler, because a transaction's `timerRequests` are what *that* transaction registered and an unconditional binding-only one posts an empty set that cancels what `load` just scheduled.
- **The skin's own JScript is ES3, and `JSContext` is not — `WMPJScriptDialect` is where that is reconciled (W86).** WMP9's `corona_tiny.js` chains its compact-mode animation by appending a timer event to the array its `TimerDispatch` is enumerating with `for-in`. JScript visits the appended index; JavaScriptCore snapshots and does not, so the chained event was dropped on the tick it was registered and the whole WMP9 family could neither collapse its video panel nor get back to `vPlayer`. Corona's 2002 script splices the array instead and is unaffected, which is what made `corona` the control and `9SeriesDefault` the case. The rewrite is bounded, skips strings/comments/regex literals, and leaves a program with no `for-in` byte-identical; **3 of 180 archives use `for-in` at all and one depends on the live semantic**, so the corpus sweep is the proof it changed nothing else. **Before ranking a "the script runs and nothing happens" defect, ask whether the handler depends on an ES3 semantic** — no headless probe here can see that class, and the live `INPUT script-diag` line stays silent because nothing throws. And when you add to this file's scanner: **test a CRLF fixture.** Swift folds `"\r\n"` into one `Character` that is not `"\n"`, and the first version of the rewrite silently did nothing to the entire corpus for that reason while every LF-only unit test passed.
- **A `<property>_onchange` fires in the same transaction as the write that triggered it, and the view's `JScript:` geometry expressions are *not* re-run to achieve the same thing.** A `.wmz` animates by writing geometry once per timer tick, so a pane positioned off a moving one has to move in the same frame; letting it catch up on the next transaction tore the compact view into two visible halves that closed four seconds later (W87). Only what the skin declared is raised — 16 geometry `_onchange` attributes across 6 archives — bounded and once per property per transaction, so two panes positioned off each other cannot loop. **Re-resolving the expression set after the handlers is the tempting general form and it is wrong**: those attributes are an initial layout rather than a live binding, and several read the property they write (`left="JScript:svBottomLeft.width-left"`), so re-running them moved 175 of 545 corpus images and shattered `Back to the Future Trilogy`'s `videoView` and `ALXMorph`'s frame. That is what a sweep is for; it was reverted on the measurement, not on taste.
- **A tween's endpoint is not readable by the rest of the handler that started it (W112).** WMP
  animates `moveTo`/`resizeTo`/`alphaBlendTo` over the call's duration argument, so an element's
  `left` still answers where it *is* for the remaining statements — and skins are written against
  exactly that. `Cablemusic`'s playlist tab is `onClick="PlayListMove();HidePlist();"`: the first
  slides the drawer, the second reads `subPlayList.left` to decide whether it is now open or shut.
  With the endpoint applied inside the call that read answered the destination, so closing the
  drawer never hid the playlist and it stayed over the player forever — reported as "the playlist is
  always showing". `WMPObjectModel.tween` queues the endpoint and `WMPScriptContext` flushes at each
  handler boundary, so W38 (the endpoint lands this transaction) and W55 (`onEndMove` is raised from
  it) both still hold. **A duration of zero is not a tween** and applies immediately, which is what
  `movePlayButton()`'s `moveTo(x, 116, 0)` toggle depends on.
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
- **Three of the four alignments are margins and `center` is not, and reading it as one cost a whole
  window frame (W143).** `right`, `bottom` and `stretch` say *hold this edge's authored distance to
  the parent's edge* — the delta form, a no-op at the view's own authored size, and what W113's
  `ownAuthoredSize` and `LostPlanet` exist to protect. `center` says the element **stays centred**,
  so its coordinate is `(parent − own) / 2` computed fresh, and the authored coordinate on that axis
  is not an offset into it — which is exactly why a skin that wants a centred piece authors none at
  all. Read as a margin, every one of them collapsed to the parent's origin. **The Alienware/ALX
  frame is built out of this and nothing else**: each of their playlist, equaliser, visualisation and
  video windows hangs its two 175px side columns off `<subview id="plLeftCenter"
  verticalAlignment="center" backgroundImage="f_left_center.png"/>` with no `top`, plus a tile above
  and below at `top="wmpprop:plLeftCenter.top"`, so the columns landed on top of
  `f_top_left.png`/`f_top_right.png` and took the window's whole title bar and the top of its inner
  border with them. Reported as "the playlist and eq windows are not properly constructed … the
  window border and details are not correct and there are large gaps". **The blast radius is the
  measurement, and it is the largest of any single line in this engine: 139 of 535 corpus images
  moved, and every one sampled is a repair** — WALL-E's logo and transport row, `PowerToys`' cancel
  button, `xsn_sports`' progress panel finally sitting over its own pointer arrow, `TripleX`'s
  clipped `X3-080902` readout, the five `US …` video placeholders, `Plus! Pulsar`'s side-drawer tab,
  `Project Gotham Racing 2`'s frame stripes, and `T3-Skynet_Media_Player`, which had been drawing a
  half-width frame with its own buttons outside it. **The axes are independent** (AlienMorph's
  `plRightCenter` is centred vertically and pinned right) and the `isComputed` guard still wins on
  the centred axis, which is what keeps WoW's `left="JScript:view.width-202"` from being counted
  twice. `mainView` is byte-identical across the whole family: a non-resizable player authors no
  centred pieces, so **this class lives entirely in the windows a skin opens beside its player** —
  which is why four phases of `mainView` work never saw it. `WMPAlignmentTests` pins both halves.
- **A number a script writes must reach the drawing, and `<TEXT>` is where it did not (W114).**
  `WMPSceneBuilder.literal(_:_:)` reads the attribute and nothing else — geometry has
  `parseDimension` and a slider has `sliderMetrics`, and the rest had nothing. `Cablemusic` lays its
  readouts out with `txtShowLabel.fontSize = 7` over a markup that says `fontSize="10"`, so every
  label was measured *and* drawn three points too large and "Copyright:" ran out of its 55 px box
  and off the left edge of the LCD it belongs in. `literalNumber` is the override-aware resolver;
  `fontSize`, `scrollingDelay` and `scrollingAmount` go through it, as does the intrinsic text size.
  The object-model half is the same rule: `justification`, `fontFace`, `fontStyle` and `fontSize`
  are **rendered**, so a write to one has to commit as a mutation rather than be stored inert, and
  each was only reaching the scene when the markup happened to author the same attribute.
- **An element's own artwork is drawn at its own size, and the box it does not fill is left to
  whatever is under it (W122).** WMP never scales a `<BUTTON>`'s `image` to the authored frame, and
  a skin that swaps that image from script is written against exactly that: **563 script `.image`
  assignments across 51 of the 180 archives**, of which **23 paint a clock out of digit strips**
  (`drawSeekDigits` / `DrawTimeNormalView`) and **6 give the digit a frame wider than the digit**.
  The ALX/Alienware readout is four `<BUTTON>`s authored the width of a *ten-digit strip* —
  `time1.png` is 250x23 — each inside a 25 px `<SUBVIEW>` that clips it to the first cell, and
  `drawSeekDigits()` then assigns a single 25x23 `time1_<n>.gif` per tick. Scaling that to the 250 px
  frame drew one tenth of one digit blown up ten times: reported as "in all the alien type skins the
  numeric display is illegible". `WMPSceneBuilder` clamps the foreground image command to the
  artwork's natural size, anchored at the frame's top-left, so the smaller bitmap lands where the
  strip's first cell did and the parent's clip is unchanged. **Only the foreground image takes the
  rule** — `backgroundImage` still fills its frame, because a `stretch`-aligned subview grows with a
  resizable window and its background is what covers the delta (`LostPlanet`, in the counter-evidence
  table). **A default-state sweep cannot see the defect and can see the collateral**, which is what
  makes it worth running: the strip *is* the frame until a script swaps it, and `drawSeekDigits()`
  returns early on an empty playlist, so the 545-image corpus capture moved **16 images, none of them
  a clock** — every one an oversized bitmap that had been upscaled and is now crisp (`portals/mode2`,
  the five `US …` `videoUSM` logos, `tubeframe`, `Ice/mainView`), one nondeterministic
  (`Scooby-Doo_2`), and one that is now half-right and is the open row: `Ice/videoView` draws
  `Pl-xp.bmp` as a 196x44 button inside a subview that still stretches the *same* bitmap to 313x144,
  so the two no longer meet.
- **A `<VIDEO>` box shrinks the picture to fit by default and never enlarges it (W102).** The two
  fit flags are independent and neither means crop or fill: `shrinkToFit` governs the picture being
  *reduced*, `stretchToFit` its being *enlarged*, and `maintainAspectRatio` (default true) decides
  whether the two axes scale together. **`shrinkToFit` defaults to true and `stretchToFit` to
  false**, which is not symmetry for its own sake — it is what the corpus is authored against.
  **77 of the 97 sized `<VIDEO>` elements declare no `shrinkToFit` at all and 73 of those are boxes
  under 640x480** (`Heart_Butterfly` is 89x130, `Creed` 131x88, `Cablemusic` 341x215), and **not one
  archive anywhere authors `shrinkToFit="false"`** while 19 author `stretchToFit="true"` and one
  `"false"`. Defaulting the shrink flag off therefore drew every unattributed box at the stream's
  native pixel size, centred and clipped to the middle sliver of a 1080p frame — reported as "the
  video opens at full resolution instead of scaled to the window". The corresponding read defaults
  in `WMPObjectModel` are the same three values, because a skin that reads back a flag it never
  authored must be told what is actually on screen. **This is not `mediacenter.videoShrinkToFit`**,
  which is a different object with its own defaults in `reference/object-model.md`.
- **The picture is lent to the skin as a *child window*, and `isVideoOutputHosted` is our flag while
  being a child is AppKit's fact — they drift apart (W102).** A child window is the isolation that
  makes hosting work at all: VLCKit installs its own output view and sizes that view's *ancestors*,
  so moving `videoPlayerView` into the skin's tree runs the skin's content view away by tens of
  thousands of pixels, while `addChildWindow` keeps a separate layout tree glued to the skin. The
  trap is that the link can go without the flag changing, and `hostOutputWindow` re-parents only when
  `!isVideoOutputHosted`, so nothing puts it back. **Three symptoms that read as three bugs are this
  one cause**: the picture goes black while the audio plays and seeking still works (it fell *behind*
  the skin — a real child window cannot); it lags out of the window frame on a drag (the 10 Hz
  reposition trailing a tick behind); and switching apps fixes it (activation re-collects children).
  `WMPVideoSurface.update` re-asserts the relationship every tick and traces `video reparented` /
  `video reordered above parent` — **if those fire continuously rather than once per incident, the
  repair is masking a call site that keeps breaking the link, and that is the thing to fix.** Suspect
  anything that orders the parked window out: on macOS that drops its parent relationship.
- **Video readiness has two consumers and they need different truths (W124).** `WMPHostSnapshot.video`
  is the live drawable state: when VLC drops `hasVideoOut` or `videoSize` during a same-media vout
  rebuild, it must become empty so `WMPVideoSurface` detaches the child window and releases mouse
  capture. `WMPHostSnapshot.videoEvent` is the last valid state for `videostart`/`videoend` edges,
  latched by media identity and cleared by a media change or `didReachEndOfMedia`. Feeding the
  latched event state back through `video` kept the child window over the skin and made buttons look
  globally dead when the track panel had pointer capture. Test the split state: output teardown
  produces no `videoend`, the surface detaches, and a genuine media end still produces exactly one.
- **A video's natural end is not a manual Next press.** `WindowManager.videoTrackDidFinish`
  routes WMP completion to `AudioEngine.wmpVideoTrackDidFinish`, which shares the audio engine's
  natural-end repeat/shuffle/queue-exhaustion rules without running audio reporters or gapless
  promotion. Manual `next()` wraps unconditionally; using it at EOF looped a one-video playlist
  forever with repeat off. Keep the new callback gated to `.wmp`. Verified live on 2026-09-10 with
  Corona and a 6.29-second local video: EOF stopped playback, and a subsequent Play click replayed
  it and stopped again.
- **A paused film reports no time, and in `.wmz` mode that was the only thing refreshing the host
  (W102).** `videoDidUpdateTime` is driven by VLC's time-changed callback, so a pause silenced the
  whole host tick and the skin went on drawing *and hit-testing* a pause button. What that costs is
  not a stale glyph: the next click's `mousedown` triggers the rebuild that finally sees `paused`,
  the button under the pointer is swapped mid-gesture, and `WMPMainView.mouseUp`'s
  `result.activated == capturedTarget.stableID` guard drops the click — **the click is destroyed by
  the state change it triggered**, reported as "play then pause then play just breaks it".
  `videoDidChangePlaybackState` closes it, gated to the WMP family. **The general rule this leaves:
  any state a skin hit-tests against must be pushed when it changes, never sampled on the next
  rebuild** — a rebuild driven by the very gesture that needs the old geometry will always eat that
  gesture.
- **A text baseline may never sit higher than the face's own ascent (W114).** The rule was
  `max(fontSize, (height + fontSize) / 2)` measured from the box's bottom — fine while every
  `<TEXT>` had a generously tall authored box, and four pixels *above* the box once a text is sized
  by its own glyphs. `CTFontGetAscent` is the floor. It moves nothing that was already inside its
  box and 142 corpus images where text was drawing over the artwork above it.
- **A call that lands its endpoint completes in the same transaction, and a skin's sequence is
  chained from that completion (W55).** `moveTo`/`alphaBlendTo` have applied their endpoint
  immediately since W38, so the step that follows was the missing half: `onEndMove` is 247 uses
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
  captured slider, and it is where a seek commits. See `reference/object-model.md` § *Methods*, and
  `reference/harness.md` for why an image-only sweep cannot see any of it.
- **A `<TEXT>`'s own artwork is its glyphs, and a `<BUTTONGROUP>`'s is its mapping image.** Every
  other node falls back to the natural size of its `backgroundImage`; these two have none, and both
  were the largest starvation classes in the corpus. **1,441 `<TEXT>` nodes across 127 of the 179
  archives** resolved no size — 1,058 of them missing width *and* height — because WMP sizes a text
  from the face and the string and a skin therefore never states it: `Cablemusic`'s script lays out
  ten readouts with `txtShow.top/left/width/fontSize` and no `height`, so the whole
  show/clip/author/copyright block never drew and the report was "there is no track display". A
  width measured from the *current* value is WMP's own behaviour — the box grows with the string, an
  empty value is honestly zero-wide, and it starts drawing on the transaction that gives it one.
  **31 `<BUTTONGROUP>`s across 16 skins** resolved no size for the mirror reason: the group's normal
  state is the window's own background artwork, so the skin authors no `image` and no geometry at
  all, and with no frame the group registered no hit target — every control in it dead while the
  artwork beneath still drew the buttons. `Cablemusic`'s presets, stop, close, minimize, next and
  previous effect, shrink, bandwidth and all three drawer tabs are one such group each: "most
  buttons don't work". The mapping image is definitionally the group's own pixel grid.
- **`STATUSTEXT` and `CURRENTPOSITIONTEXT` are text controls with native WMP values, not unknown
  tags.** Model them as text for intrinsic sizing and paint; synthesize the latter's value from
  `player.controls.currentPositionString`. WMP right-aligns an otherwise-unqualified
  `CURRENTPOSITIONTEXT`, because it is normally the trailing cell beside a scrolling title.
  Cerulean exposed both requirements: omitting the tag removed its clock, and left alignment made
  the clock touch the title.
- **An origin the markup never stated can still have been written by script, and asking the markup
  first meant it never was.** `left`/`top` default to 0 when unauthored — but the check was
  `attribute == nil ? 0 : resolve`, which short-circuited *before* `parseDimension` could look in
  the scene overrides. Size never had the bug, so a script-positioned element came out the right
  size in the wrong place: `Cablemusic`'s two drawers are seventeen station rows each, laid out
  entirely by `InitPrograms()` writing `pr<N>.top`/`.left`, and all thirty-four drew on top of one
  another in the corner of the drawer. Overrides first, then the markup, then the default.
- **WMP spells every transport control twice, and only one half of each pair was ever a kind.**
  `<…ELEMENT>` is a `BUTTONELEMENT` subtype — a colour region of a `BUTTONGROUP`'s mapping image —
  and `<…BUTTON>` is a `BUTTON` subtype with its own artwork and frame. `WMPElementKind` had
  `playElement` but no `playButton`, `pauseButton` but no `pauseElement`, and so on, so half the
  vocabulary fell to `.unknown`: **`PAUSEELEMENT` 80 uses / 69 skins, `PLAYBUTTON` 50 / 45,
  `PREVBUTTON` 50 / 45, `NEXTBUTTON` 49 / 44, `STOPBUTTON` 48 / 42, `MUTEBUTTON` 10 / 9,
  `REPEATBUTTON` 5 / 4.** An unknown kind still paints its `image` and is not interactive, so the
  button **drew and did nothing** and the pointer fell through to whatever overlapped it —
  `WMP_RENDER_CLICK` on `Cablemusic`'s play button answered `hit=ffw`. `MUTEELEMENT`,
  `REPEATELEMENT`, `SHUFFLEELEMENT` and `RETURNELEMENT` are zero in the corpus and are deliberately
  absent: a kind nothing authors is a phantom. The `*ELEMENT` half is `isNonLayout` — but keyed on
  **`mappingColor` under a `BUTTONGROUP`**, not on the kind and not on the attribute alone;
  `polygon` puts a `mappingColor` on a `<SUBVIEW>` with real geometry as a self-mask.
- **A `BUTTONGROUP`'s state artwork is a sheet the size of the whole group, and it is only ever
  painted through the group's mapping mask (W116).** `hoverImage`/`downImage` are the *entire*
  player redrawn with one control lit, and the mask cuts out the region the pointer is over. The
  normal `image` used to be **required** for any of that to happen, so a group that authors none —
  its normal state being the window's own background artwork — fell through to the generic
  single-image path and painted the whole sheet over the window. `Cablemusic`'s is a 593x600 bitmap
  with a dark green surround, so hovering any button in any of its six groups covered the entire
  player: reported as "when you mouse over the compact button there is a huge overlay". The normal
  artwork is now optional and only the mask is required; with no `image` there is nothing to draw
  *under* the lit region, which is correct, because what is under it is the window. **No corpus
  sweep can see this class** — a default-state capture never enters a hover or a down state (W73),
  and the 535-image sweep across this fix is byte-identical. `WMP_RENDER_HOVER` and
  `WMP_RENDER_CLICK` are what measure it.
- **A fix that makes dead code reachable is where a latent trap fires.** Sizing a `BUTTONGROUP` from
  its mapping image reached, for the first time on `Cablemusic`, a
  `Dictionary(uniqueKeysWithValues:)` over the group's `mappingColor`s — and that skin authors
  `bnpb6` and `bnpb7` both as `#00C0FF`, one preset too many for the eight regions its `map.gif`
  has. A dead control became a **crash on load**. WMP takes the first and draws it; so does this.
  **It fired twice**: the same row also made the unmasked state-sheet paint above reachable, and
  that one was invisible to every headless probe. Budget for both shapes whenever a row turns a
  whole class of nodes from unresolved into drawn.
- **A `<TEXT>` is a box, the clip is horizontal, and `scrolling` is what a skin turns on when the
  value overflows it (W94).** Drawing text unclipped let `WoW`'s 77x30 `metadata` readout paint
  "- AC/DC - Shoot to Thrill / Playing" straight across the player's buttons. Three things had to
  land together, and any one alone does nothing: the clip, a marquee driven off the render clock
  with `scrollingDelay`/`scrollingAmount`, and a **measured** `textWidth` on the object model,
  because the skin decides for itself with `metadata.scrolling = (metadata.textWidth >
  metadata.width)` and an answer of 0 says the string fits. `scrolling` is 358 uses across 114 of
  180 archives. **The vertical half of the clip is deliberately left open**: a skin routinely
  authors a row of links shorter than their own line box — `v2_underworld`'s About page is eight of
  them — and this engine's baseline comes from `fontSize` rather than the face's real metrics, so
  clipping to the authored height shaved those to a sliver. Cut the overflow that is measured;
  leave the one that is not. A scrolling text also contributes to `animationCadence`, endlessly and
  bounded to its own box — it is the only animation a skin turns on from script rather than by
  naming a GIF.
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
- **A panel opened with `theme.openView` is not the session's view (W96).** `apply` persisted
  `wmpSkinViewID` on every present, so quitting with a playlist open recorded the playlist; the
  covered view was not persisted, so the next launch restored a panel with no player and no route
  back to one. Reported as "the skin is empty and shows no player or skin windows", and it stranded
  any skin whose panels are `openView` rather than `currentViewID`. Only **the player's own
  presentation** writes the key — a simpler statement of the same rule the `openedViewStack.isEmpty`
  test was making, and one that stops being a special case once the panel has a window of its own.
  The panels themselves are persisted separately (`WMPViewFrameStore.openViews`, plus a per-view
  origin) and restored *before* the load transaction's host commands, so a dispatcher skin that
  re-opens its own panels from `theme.loadPreference` raises the restored window rather than opening
  a second one.
- **An `<EFFECTS>` rect is never shaped by this engine. The skin's own artwork occludes it, through
  plain z-order (W139).** The earlier form of this rule forbade turning "image overlap, z-order,
  alpha, or an artwork's transparent bounds into effects geometry" and named Cerulean and
  Plus! Professional as counter-evidence. **They are the clearest evidence for it, and the rule was
  backwards** — it is why an inscribed-circle clip was invented in place of the occlusion the markup
  already declares. What is still true is the half it was built on: do not *derive a mask* from a
  sibling bitmap, and `clippingColor` applies to a `clippingImage` and not to arbitrary nearby art.
  What was wrong is that z-order is not a derivation at all; it is what the markup says.

  Cerulean, measured from the archive: `face.bmp` has a magenta (`#FF00FF`) hole of 4,264 px over
  x 133..205, y 35..107 — a 73px circle against an ideal 4,185 — and the subview that draws it keys
  that colour out. Inside it, `<effects zIndex="-1" width="103" height="75">` and
  `<button id="bEye" zIndex="-2">`. **A negative `zIndex` means behind the subview's own
  `backgroundImage`.** Back to front: the eye disc, the visualizer filling its full 103×75 rect, then
  `face.bmp` with a hole in it — which is why the brass bezel and all eight rivets survive.
  Plus! Professional is the same mechanism with a tilted oval (`vis_mask_w.png` inside
  `<subview id="visMask" clippingColor="#ff00ff">`). **32 `<EFFECTS>` across 30 skins author a
  negative zIndex**, and no per-skin code renders any of them.

  How it is hosted: **a node's negative-`zIndex` children are walked before it emits its own paints**
  — DFS order cannot express "behind the parent's background" on its own, and getting this wrong is
  what drew Cerulean's bars across the whole face on the first attempt. `WMPWidget.commandSplitIndex`
  then records the index into `WMPScene.commands` the walk had reached when the widget's node was
  visited, `WMPRenderer` rasterizes the scene as two images
  either side of it, and `WMPMainView` hosts the effects surface between them —
  `WMPEffectsSurfaceView` → the "above" overlay `NSImageView` → the interactive widgets, re-enforced
  on every `synchronizeWidgetViews` pass because a plain `addSubview` goes to absolute top. **The
  split is an index and not a zIndex threshold**: `WMPSceneBuilder.walk` sorts only siblings, so
  `commands` is DFS order and a `zIndex = -5` node in one subtree can legitimately follow a
  `zIndex = 10` node in another. `WMPImageStore.clippingMask(for:keyedOut:)` and `WMPColorKey` then
  apply to the overlay for free — no new masking code exists anywhere for this.

  **A skin with no occluding artwork fills its authored rect exactly**: full `width × height`, a
  transparent background, no shape fitting and no aspect letterboxing. Of the 107 `<EFFECTS>` rects
  with numeric dimensions **19 are square, 83 wider than tall and 5 taller**, so a centred `min(w,h)`
  square covered a median 75% of the authored rect and as little as 17% (`Alpine7618_v09`, 150×26),
  and the inscribed circle took ~21% more again.
- **A zero geometry override is a value, not an absence.** Every skin with a store-thumbnail
  `previewView` collapses it in `onLoad` — `view.width = 0; view.height = 0; view.backgroundImage =
  ""; theme.currentViewID = "controlView"` — and Microsoft's own `auto.js` in `Official_Xbox_XP`
  does it with a comment saying so. Discarding a `0` override as "not positive" left 34 corpus
  skins showing a static splash bitmap where the skin had asked for its player.
- **A node draws the artwork a script last gave it, not the one its markup declares.** Images were
  the one property class the script-override path skipped, and `Alienware Invader` — whose whole
  player is behind a 568-frame intro of `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"` —
  drew nothing at all because of it (W75). An override is an authored path string and resolves under
  the same provider rules as markup; one the skin does not contain warns and leaves the authored
  artwork in place; `""` clears the property the way an absent attribute does. The rules and the
  traps are in `reference/object-model.md` § *What a property read answers, and who wins*.
- `WMPSceneBuilder` resolves literal geometry plus the bounded static initial-layout grammar in
  `WMPInitialLayoutExpression`: finite numbers, parentheses, arithmetic, and geometry reads from
  deterministic IDs. `wmpprop:` is accepted only as an alias for that same geometry grammar.
  Calls, assignments, statements, script globals, ambiguous/unknown IDs, cycles, and excessive
  dependency depth stay unresolved *for the scene builder*, which never executes skin code and never
  invents fallback geometry. The general path is the live context in `WMPScriptRuntime`, whose
  resolved values arrive as scene overrides; the static grammar remains the fast, script-free
  evaluator the builder uses before any transaction has run.
- Scene coordinates remain top-left throughout layout, clipping, dirty bounds, hit metadata, and
  paint commands. Core Graphics conversion happens once in `WMPRenderer`; images and text each use
  an explicit counter-transform so pixels and glyphs remain upright.
- The immutable scene owns no `CGImage` or cache state. `WMPImageStore` performs bounded ImageIO
  metadata/decode off-main, supports BMP/GIF/JPEG/PNG, and uses a byte-bounded LRU keyed by canonical
  resource path plus color key.
- **ImageIO is stricter about BMP than Windows is, so a `.bmp` it refuses falls back to
  `WMPBitmapDecoder`** — never to a failure the user sees as a blank skin. Nine of the corpus's
  3,687 bitmaps are rejected by ImageIO alone: eight set `biClrImportant` while `biClrUsed` is zero
  (Windows reads the palette size from `biClrUsed` and treats the other as advisory), and one is a
  BI_RLE8 stream that walks clean and is refused anyway. The fallback runs *only* after ImageIO has
  failed, under the same dimension/pixel/byte bounds, applied before it allocates — an oversized
  bitmap still fails `WMP0034`. Do not "fix" such a file by patching its header, and do not relax a
  limit to admit one.
- **A mapping mask is authored top-left, and the render CTM is y-flipped, so clipping through one
  needs the same counter-flip `drawImage` applies.** `WMPRenderer.clip(to:mask:context:)` owns that;
  it undoes the CTM by hand rather than with `restoreGState`, which would discard the clip too. A
  mask fixture split left/right cannot see this class of bug — split it top/bottom.
- **A node keys out every colour it declares, not one.** `transparencyColor` and `clippingColor` are
  both keys — the second is the colour WMP cuts out of a subview's own artwork to shape it — and a
  subview routinely carries both with *different* values (`Alpine7618_v09` keys `#FF00FF` and
  `#FF0033`). 103 of the 180 archives author clipping attributes, so an engine honouring one key per
  image paints the other as a flat slab over most of the window. `WMPSceneImage.colorKeys` is
  therefore a list, in authored order, and the image-store cache key contains all of it. PNG, GIF
  and BMP color keys compare exact un-premultiplied RGB; JPEG keys allow the bounded 64-value
  compression fringe per channel because lossy decoding turns authored `#FF00FF` into a
  blue-channel ramp (W125, Plus! Professional). Preserve the source alpha of every non-matching
  pixel.
- **Do not generalize Cerulean's keyed-head correction.** Its `face.bmp` in the exact
  `cerulean.wms` definition carries a blue `backgroundColor` that creates a visible rectangular
  fill behind two keyed colours; the compatibility exception suppresses that one fill only. A
  corpus sweep showed that applying the rule to every keyed background erased intentional interiors
  in Claw, Gadget, and Pharaoh. The archive stays byte-for-byte untouched; the narrow renderer
  exception is the compatibility boundary.
- **A node that declares no key at all still gets one: magenta, whatever alpha the sprite carries.**
  WMP's implicit transparency colour (W78, W78a). The corpus is authored against it — 4,979 of its
  6,076 `transparencyColor` declarations (82%, 142 skins) are `#ff00ff`, `Halo 2` keys three
  siblings by hand and leaves `m_trans_no.png` to the default, and `Main_Street` authors one key in
  the whole file. The scene builder decides (`WMPSceneImage.implicitColorKey`, set only when the
  node declares nothing) and the image store applies it. **The sprite's own alpha channel does not
  veto it, and W78 shipped believing it did.** The reasoning was that a PNG or GIF which authored
  transparency has already said what is see-through; the corpus says the alpha channel is an export
  format instead. `scripts/wmp_implicit_key.py --alpha only` measures the complement — 76 references
  across 21 skins and 62 sprites — and **11 of those nodes carry two states of the same button, one
  exported without an alpha channel and one with, holding pixel-for-pixel identical magenta**
  (`Half-Life_2` `m_pause_no.png`/`m_pause_hov.gif`, both 1,394; `Harry_Potter…`
  `bottomgroup_no.png`/`bottomgroup_hover.gif`, both 5,866). Under the veto the normal state keyed
  and the hover state did not, so the button turned magenta under the pointer. **Never pass the
  implicit key on a mapping image, position map or clipping mask**: they are read for their colours,
  and keying one deletes a `#FF00FF` mapping colour from its own map. Measure the class with
  `scripts/wmp_implicit_key.py` before touching the rule; the default removed 315,157 magenta pixels
  across 87 corpus views, and dropping the alpha veto took the corpus residual from 7,253 px across
  15 views to 878 across 2, changing 13 PNGs and nothing else.
- The opt-in render dump writes one untracked PNG per view plus a JSON report. Corpus paths and
  output directories are local inputs/artifacts and must never be staged.

## Phase 3 app integration contracts

- WMP maps to its own `PlayerUIControllerFamily.wmp`; it is neither Classic nor a
  `ModernSkinFamily`. Keep capability and menu exposure DEBUG-only until the public-exposure phase.
- `WMPSkinImporter` owns `Application Support/NullPlayer/WMPSkins`, complete pre-commit validation,
  same-directory atomic replacement, installed enumeration, and the `wmpSkinName` / view selection
  keys. A failed replacement must leave both the installed archive and selection usable.
- `WMPMainWindowController` must first present `WMPUnskinnedMainView`, then swap in only a completed
  static WMP scene. Missing/corrupt selections stay in WMP with an actionable diagnostic. Main-window
  fallback must never instantiate or consult Classic, Original, or Winamp Modern skin machinery.
- Persist WMP skin/view identity separately. Restore WMP geometry only when the exact mode, skin,
  and view match; preserve top-left position safely and do not apply shared UI scaling.
- Teardown is synchronous and idempotent: cancel WMP tasks, clear callbacks and images, then release
  scene, archive, and image-store ownership before the controller is discarded.
- NullPlayer-owned native windows exposed in WMP mode must be hosted in WMP-owned chrome derived
  from the active `.wmz`: borders, colors, title/window controls, metrics, resize affordances, and
  docking treatment. Never fall back to another skin family's controller or chrome. Missing skin
  chrome uses only an app-authored WMP-neutral fallback. **This shipped on 2026-09-09 and the
  "hide or disable it until it has a host" clause is spent** — `AuxiliaryControllerStyle.wmpUnavailable`
  is gone. How it works is *NullPlayer's own windows beside a skin* below.

## NullPlayer's own windows beside a skin

Landed 2026-09-09. A `.wmz` has no frame system to mount a foreign window in — no
`<Wasabi:StandardFrame>` a playlist can be dropped into — so NullPlayer's own windows are
app-authored chrome *coloured* from the skin instead. Four things carry it, and the last two were
found by looking at the screen rather than by reasoning.

- **The seam is family-neutral, and it is the one `.wal` already had.** `SkinnedSurfaceStyle` /
  `SkinnedSurfaceChrome` (in `App/Skinning/`, formerly `WinampModernSurfaceStyle`/`Chrome`) are built
  from `SkinnedSurfaceRoles` — seven colours and nothing else — so neither engine knows the other's
  markup. `.wal` derives the roles from a `WasabiPalette`, `.wmz` from `WMPSurfacePalette`, and both
  reach the views through **one** property, `WindowManager.hostedSurfaceStyle`, a `switch` on the
  controller family. The `.wal` names survive as typealiases, so no `.wal` call site moved.
- **The palette is declaration-first and then measured off the artwork.**
  `PLAYLIST` (`backgroundColor`, `foregroundColor`, `itemPlayingColor`,
  `itemPlayingBackgroundColor`) → `VIEW`/`SUBVIEW` background plus `TEXT` foreground → the **dominant
  opaque colour of the presented view's own rendered bitmap** → an app-authored WMP-neutral pair.
  The sampling step is not a nicety: measured over the 177 readable archives on 2026-09-11, **165
  declare a background colour and 171 a foreground** now that the parser accepts the SDK's named
  colours as well as `#RRGGBB`. Counts per role are in `WMPSurfacePalette`'s own doc
  comment, next to the scan that produced them.
- **Every foreground goes through the legibility guard, against the ground it is actually drawn on.**
  `SkinnedSurfaceStyle.legible`, the same WCAG 3.0:1 bar `.wal` uses — but it is load-bearing here in
  a way it is not there, because a `.wms` declares colour per *element*: the ground can come from a
  `VIEW` and the lettering from a `PLAYLIST` three levels down that was never drawn on it, and a
  sampled ground is one no author ever chose text against. Guard each role separately: the playing
  row's text sits on the window background until the row is *also* selected, the selection's text on
  the highlight. Guarding both against one background leaves an unreadable current track, which is
  what the reporter saw.
- **A skin-owned `PLAYLIST` is an AppKit overlay, so it needs the WMP palette directly.**
  `WMPMainWindowController` sets `WMPMainView.surfaceStyle` before installing native widgets and
  `WMPPlaylistSurfaceView` uses it for its ground, selected row, current row, and all three text
  roles. Leaving its historical hard-coded black/white colours produced a foreign black rectangle
  in Cerulean even though `ITEMSPLAYLIST backgroundColor="#9AACDB"` was declared. Do not route this
  through Classic or Winamp Modern state; it is WMP-owned surface state.
- **A `.wmz` main window's width is not a zoom.** `playlistChromeScale` is
  `mainWindow.width / Skin.baseMainSize.width` — true of a *classic* player, whose 275px grid means
  its width is the size the user chose. A `.wmz` main window is the skin's own canvas: Corona's is
  596px, so our playlist drew its title and every row at 2.2x and the reporter's words were "the
  windows and title fonts are huge". It now falls back to the app's own scale in WMP mode, and
  `PlaylistView.scaleFactor` and the playlist's snapped default width route through that same
  property so the three cannot drift apart.

### Ask what the skin provides before opening a window of your own

**The corpus declares six surfaces and this engine hosts two.** Measured 2026-09-09 over the 179
archives and their 595 views — `views` counts views declaring the surface, `own view` counts skins
that put it somewhere other than the view they open on:

| Surface | views | skins | own view | Hosted |
|---|---:|---:|---:|---|
| `<VIDEO>` / `<WMPVIDEO>` | 268 | 170 | 165 | no (W9 removed the opaque placeholder; W102 is the row) |
| `<EFFECTS>` / `<WMPEFFECTS>` | 178 | 171 | 144 | yes — this player's own visuals in the authored rect (W101) |
| `<PLAYLIST>` family | 175 | 170 | 162 | yes |
| `<EQUALIZERSETTINGS>` | 170 | 163 | 147 | yes — the skin's own bound sliders are the equaliser |
| `<VIDEOSETTINGS>` | 94 | 94 | 93 | no (W103) |
| `<NETWORK>` | 6 | 4 | 4 | object-only, and correctly so (W104) |

**`WMPSkinSurface` models the playlist and the equaliser, and its doc comment used to claim there
was nothing else to model.** There is: the visualizer and the video window are surfaces this app has
its own window for and 170 skins declare themselves, so the menu toggles for those open ours over
the skin's own — the same defect W93 opened for the playlist. **Adding a routing case before the
surface is hosted trades a duplicate window for an empty drawer**, which is why the routing row
(W105) is ranked behind the hosting rows and not with them. W101 has landed, so `.visualization` is
the case that may now be added; `.video` still waits on W102.

**A `.wmz` also authors windows this player has no content for at all**, and they are not defects:
`infoView` (45 `openView` calls across the corpus) is the skin's own about/links/gallery panel,
`contentView` (24) a promotional content viewer, `vidRemoteView`/`remoteView` a floating remote, and
`previewView` (16 skins), `mediaSwitcherView` (21) and `versionView`/`upgradeView` are opened by the
*host*, not the user — a skin-chooser thumbnail, a media-type switch, and a "you need a newer
player" notice. `controlView` (24 skins) is the windowless dispatcher described above. None of these
wants NullPlayer content mapped into it; leave them to the skin.

**171 of the 180 corpus skins declare a playlist and 164 an equaliser** (164 declare both), so for
those two surfaces NullPlayer's window is the *fallback*, not the default — opening it
unconditionally puts a second, differently-styled playlist over nearly every skin in the corpus.
`WMPSkinSurfaces` reads what the skin declares and `WindowManager.routeWMPSkinSurface` takes the
toggle first, exactly as `routeWinampModernSurface` does for `.wal`. Three shapes, and routing has to
answer all three — the corpus splits almost evenly between the first two (87 / 84):

| The skin declares it… | What the toggle does |
|---|---|
| in the view on screen (Corona's drawer) | nothing opens; the menu item is checked and inert, because the thing it names is already there |
| in another view (WoW's `plView`) | opens that view, the way the skin's own button does through `theme.openView` |
| nowhere (9 skins for playlist, 16 for EQ) | NullPlayer's window opens, in the palette chrome above |

**Match on the authored tag, not only on `WMPElementKind`.** `ITEMSPLAYLIST` is a playlist the object
model does not model yet — Corona's drawer is one — so a kind-only test reports that skin as owning
no playlist and opens ours on top of it. What decides this routing is what the skin *declares*, not
how much of it this engine hosts today.

The restore path passes `switchingViews: false`: a saved session must never move the user to a
different view at launch.

## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and the
process section it points at — `winamp-modern-skin-guide/reference/harness.md`
§ *Debugging a live defect* — which is the reference implementation of that workflow. The 2026-09-07
session that produced the fixes below spent hours rediscovering five rules already written there.

**The reproduction loop itself is `reference/harness.md` § *Driving the app*** — select the skin,
launch the debug build, ask `WMP_RENDER_PROBE` where the control is and click that frame with a
`CGEvent`, then capture the window and look at it. (The `INPUT` trace this loop used to read was
removed on 2026-09-11 for being unreadable live — see `reference/harness.md`.) Three of the four
defects in the compact-mode report were app-path defects a render sweep can never see, and each took
one launch once the loop existed. The same section carries the two things that decided those fixes:
how to reduce a skin's own script to a standalone `JSContext` repro, and why a fix that closes the
report while moving images elsewhere in the corpus is the wrong fix.

The ones that cost the most, in WMP terms:

- **Number the transactions before theorising about one.** Two rounds of inference off the raw
  `INPUT` trace named the wrong cancellation check for W88 and produced a fix that was a no-op; one
  temporary `txn <n>` pair named the right one in a single launch. `reference/harness.md`
  § *Driving the app*.
- **A green corpus sweep used to say nothing about AppKit; now it says one thing.**
  `WMP_RENDER_APPKIT=1` runs the real `NSView.draw` of the view and every overlay over it and diffs
  it against a second pass with the overlays hidden. **Start a live report here**: if the view diffs
  to zero, the defect is not the overlays and not compositing, and the scene is where to look. It
  cleared `ALXMorph/mainView` in one run. What it still does not reach is the window's shape and
  shadow (the window server), hover, a timer and live playback — W73.
- **Compare `WMPRenderer`'s own image against a screen capture of the same window rect.** Agreement
  means the defect is in the scene; disagreement means it is in the overlays or compositing. That one
  comparison ended the hunt, and `WMP_RENDER_APPKIT` is that comparison made automatic and
  corpus-wide. **Do not do it by hand against a raw screen capture unless you have to**: the two
  images go through different colour spaces, and reading that difference as a defect is what
  reported 6.8% of the *control* skin as broken.
- **A probe scoped differently from the engine reports the difference as a defect.** Both geometry
  evaluators are scoped to one `VIEW`; the `EXPR` probe walked the whole graph, so every other view's
  expressions were printed under this view's name and refused by an evaluator that could not answer
  them. That read as *82% of the corpus's expressions never reach the live evaluator* — 34,314 rows
  — and cost a whole handoff, whose worked case turned out to be a `plView` node quoted under
  `mainView`. Scoped the way the engine is, the corpus reads **7,569 / 7,569**. Before believing a
  probe about a population, check it is asking the same question the engine answers;
  `reference/harness.md` § *After the cascade* has the numbers and the check that holds it.
- **Expressions are not what starves a view — three engine rules were.** `starved.tsv` did not move
  by one row when the above was corrected, and `Cablemusic/mainview` — 63 unresolved nodes then, 8
  now — declares no geometry expressions at all. What it declares is unsized `<TEXT>`, unsized
  `<BUTTONGROUP>` and mapping-region `<…ELEMENT>` nodes, and those three accounted for **83% of the
  corpus's 2,380 unresolved nodes** (2026-09-09). `WMP_RENDER_UNRESOLVED` is the flag that says so;
  the count alone names nothing, which is why the file ranked views for two phases and nobody could
  take a row off the top of it. A high `unresolved` ratio also does not mean a blank window: two of the three worst-ranked
  views render substantially. See W68 and W75.
- **A ratio, not a count, ranks a starved view.** `unresolved > 0` is true of most views in the
  corpus, including corona's. `starved.tsv` from the census is the ranking; a raw count ranked
  nothing and hid ALXMorph for three phases.
- **Confirm the skin *and the view* before diagnosing.** `wmpSkinViewID` is persisted on every
  present, and Corona's compact view renders almost identically to its player.
- **"The wrong button responds" is two questions, and the harness answers one of them for free.**
  Scan the control with `WMP_RENDER_CLICK` and decode its mapping image independently: if every hit
  *and* every miss lands where the map's colour bands are, hit testing is exonerated and the defect
  is in what gets painted (W47 was a mirrored mask clip). Doing that first turned a vague live report
  into a one-line fix.

## Presenting a skin in a window

Learned by driving the real app on 2026-09-07, after a headless sweep said everything was fine. Each
of these was invisible to the harness and visible in the first minute of live QA.

- **A skinned WMP window carries no macOS shadow.** It is genuinely shaped — Corona is transparent
  across the 250 px its playlist slides into and the 124 px its equaliser drops into — and AppKit
  caches a borderless window's shadow from whatever content it last saw. On a shape that changes with
  every drawer and every repaint that goes stale, and a stale shadow over a transparent region reads
  as a dark box the size of the window. `invalidateShadow()` on each present fixed it, then on each
  frame change fixed it again, then playback's continuous repaints brought it back a third time. So
  `hasShadow` is **off** while a skin is shown and on for the opaque app-authored player. There is no
  drop shadow in Windows Media Player to lose.
- **A script transaction repaints in full.** The dirty region cannot be derived from what a handler
  *wrote*: it writes `svEqualizer.top` and a whole subtree moves that it never mentioned, and a
  `SUBVIEW` carries no hit metadata at all, so the narrowed bounds collapse to roughly the button
  that was clicked. Partial repaints belong to hover and slider drags, where only artwork state
  changes — and there the dirty rect must union the **old and the new** frame of every node whose
  geometry moved. Unioning only the old one erases correctly and paints only the overlap; unioning
  neither never erases, and a closed drawer stays on screen forever.
- **A new scene needs a layout pass.** The AppKit overlays are positioned in `layout()`, which AppKit
  will not run just because a scene arrived, so an equaliser the skin slid away keeps its old frame.
- **The overlays are not in the dumped PNG.** The renderer draws the scene; playlist, equaliser,
  popup, effects and video are `NSView`s hosted over it, and `WMPVideoPlaceholderView` and
  `WMPEffectsSurfaceView` both paint an opaque background. A skin can dump a perfect frame and look
  wrong on screen. `WMP_RENDER_PROBE`'s `WIDGET` line reports where the scene put them, and
  **`WMP_RENDER_APPKIT` is what actually runs their `draw(_:)`** — it hosts the scene in a real
  `WMPMainView`, `cacheDisplay`s it twice (once with the overlays hidden), and reports what the
  AppKit layer added. `outside=` is the number that ranks: an overlay inside its own widget frame is
  the hosting working. Corpus-wide that is **two views in one skin** (W74), which is the whole of
  this class in the default state. The overlays still ignore `WMPWidget.clipRect`, which is what
  W74 is.
- **An overlay fills `bounds`, never `dirtyRect`.** AppKit is free to hand a view a dirty rect
  larger than itself, and it does: the 320x240 `WMPEffectsSurfaceView` was called with
  `{{-269, -26}, {596, 468}}` — the whole window in its own coordinates — and a layer-backed view
  does not clip that (`masksToBounds` is false). `dirtyRect.fill()` therefore painted the spectrum
  pane's translucent wash over the entire skin, reported as "a giant black box over the player".
  Both `WMPEffectsSurfaceView` and `WMPPlaylistSurfaceView` had it. It only appears once the overlay
  exists, and the overlay only exists after a skin reload with a track playing, which is why it read
  as "switching skins causes it".
- **The selected view is persisted on every present, and Corona's route into its compact view is an
  unnamed button inside the equaliser drawer.** Land in `viewTiny` and it is restored on every
  launch; it also renders almost identically to `vPlayer`, so there is no visual signal that it
  happened. Confirm skin *and* view before diagnosing anything in this engine.

- **`.wmz` mode must offer a route to a track.** The auxiliary NullPlayer windows stay hidden here
  until they have WMP-owned chrome, so the skin's own Open button — `theme.openDialog('FILE_OPEN')` —
  is the only one. Before it was implemented the only way to start playback was to leave WMP mode and
  come back, which is not a mode.

## Phase 4 input and transport contracts

- `WMPMappingImage` stores canonical, un-premultiplied RGB plus alpha in authored top-left row
  order. Alpha-zero and unregistered colors never hit. Sample by scaling the original unclipped
  control frame into mapping pixels; apply inherited clipping as a separate hit-test gate.
- Mapping-image child bounds are only rejection/dirty metadata. Irregular regions may have empty
  corners inside their bounding box, so activation always samples an exact pixel. Cache mapping
  buffers through `WMPImageStore` with a byte bound and a key containing canonical path plus the
  color-to-node assignment.
- `WMPHitTester` walks reverse z/document order. Mapped unknown/transparent pixels fall through to
  lower controls; disabled controls do not intercept input. Window dragging is reached only after
  interactive hit testing returns no target.
- Mouse capture belongs to the pressed node until release or cancellation. Activation requires an
  inside release on that same node. Seek/volume/balance continue tracking while captured; scan
  commands always stop on release, cancellation, or teardown.
- Normal, hover, down/sticky, and disabled artwork selection is resolved off-main by rebuilding an
  immutable scene. AppKit invalidates only the union of changed control frames while retaining the
  full last rendered image.
- `WMPHost` is a main-actor, typed command/snapshot boundary. `WMPAudioEngineHost` clamps all numeric
  values and exposes metadata, time strings, playlist position, command-enabled state, shuffle,
  repeat, mute, volume, and balance without exposing `AudioEngine` to skin code. JScript remains
  disabled; Phase 4 recognizes semantic transport elements and only a small exact allowlist of
  literal transport statements.
- Both the skinned and app-authored unskinned WMP players use this same host. Custom-drawn controls
  publish accessibility children with stable `wmp.*` identifiers.
- **A skin switches the equaliser on in its markup, and it is the only place it ever does (W117).**
  `<equalizerSettings id="eq" enable="true"/>` is authored by **148 of the 180 archives**; exactly
  **one** skin (`gnome`) ever writes `eq.enabled` from script, and **no archive anywhere authors
  `"false"`**. `EQUALIZERSETTINGS` has been a non-layout element since W65 — correctly, it has no
  geometry — so nothing read its attributes at all, and the engine's equaliser node stayed bypassed
  under every skin in the corpus: a band bound to `wmpprop:eq.gainLevelN` dragged, wrote, reached
  `AudioEngine.setEQBand`, and was inaudible. `WMPDeclaredHostState.equalizerEnabled` reads it; both
  spellings count (`enable` 88 skins, `enabled` 57) and only a **literal** decides, because a
  `wmpprop:` binding asks the host what the host is about to be told. **Apply it once per skin load,
  not in `apply(skin:…)`** — that re-runs on every `switchView` and would undo a user who turned the
  equaliser off. The 19 skins with band sliders and no declaration are covered by
  `WMPAudioEngineHost.engageEqualizer`: a band, preamp or preset write engages a bypassed equaliser,
  which is what `EQView`, `ModernEQView` and `WinampModernComponentBridge` already do on a preset and
  the only route a `.wmz` with no toggle of its own has. The enable state is global and persisted, so
  a `.wmz` turning it on carries into the other skin modes exactly as the equalizer window does.
  **Before ranking a "the control moves and nothing happens" defect, ask whether the markup declared
  a host state nothing reads** — this class is invisible to every image sweep and to the call trace
  alike: there is no script call to trace.

## Script, expression, and binding contracts

- `WMPScriptRuntime` is the only production route for skin JScript: one persistent `JSContext` per
  skin session, one transaction at a time, expressions then handlers. `reference/object-model.md`
  is the contract for what it exposes; do not add a member without reading its rules.
- A skin's programs evaluate once per session, **after** the view's elements are installed as
  globals and the host objects are bound, because skins run top-level code that touches both.
- Fail closed per handler, never per session: an unrecognised member aborts that one handler and is
  tallied as measured demand. There is no session-wide script kill switch — a skin puts its whole
  startup in one handler, and a kill switch makes that invisible rather than visible.
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
- **Hover is two events and a gate.** Crossing from one control to another raises `onMouseOut` on
  the node left *before* `onMouseOver` on the node reached — a skin that fades a readout in on entry
  never fades it back out otherwise — and nothing is raised while the pointer stays inside the same
  node. Unlike every other dispatch site, a hover edge runs a transaction **only where the markup
  authored a handler for it** (`WMPMainWindowController.hoverEvents`): the pointer crosses a whole
  row of buttons on the way to the one it wants, and a transaction rebuilds and re-renders the
  entire scene. Hover *artwork* is unaffected by any of this — it never went through script.
  Measure it with `WMP_RENDER_HOVER`; `onmousemove`, `ondblclick`, `onfocus` and `onblur` are the
  same shape and still unraised.

## Drawing the skin's own controls

- **The skin draws its controls; an AppKit overlay is only for what the scene genuinely cannot
  paint.** What is left hosted is `PLAYLIST`, `DROPDOWNPLAYLIST`, `EFFECTS`, `EDITBOX`, `LISTBOX`
  and `POPUP`. `VIDEO` is not: its placeholder filled every `<VIDEO>` frame with opaque black over
  the artwork of 166 of 177 archives, and an audio player has nothing to put there instead. Adding
  an overlay back needs the same argument — name what the renderer cannot draw.
- **A popup's height is a host metric when the markup omits it.** Measured 2026-09-10 over 177
  readable archives, both `DROPDOWNPLAYLIST`s (Corona and 9SeriesDefault) and all four `POPUP`s
  omit `height`; they have no artwork from which the generic geometry path can infer one. Their
  `NSPopUpButton` host measures 24 points high, so `WMPWidgetKind.intrinsicHeight` supplies exactly
  that value only for an unauthored, unoverridden height. The scene builder remains off-main and
  does not construct AppKit controls; an authored or scripted height wins.
- **The visualization surface is this player's own visuals in the rect the skin authored (W101).**
  `WMPEffectsSurfaceView` draws compact WMP-native **Spikes**, **Bars**, **Ambience**, **Cava**, and
  **vis_classic** directly. Cava uses its actual presenter/full-stereo tap and vis_classic uses its
  actual waveform/profile core, each with a WMP-only preference scope. Their right-click controls are
  therefore the real Cava tuning menu and vis_classic profile menu, not inert replicas.
  `WMPEffectSelection` is the one place the choice lives, because 96 archives bind
  `currentEffectType` to `wmpprop:mediacenter.effectType`. Three rules it is built on: **nothing
  playing draws nothing at all** (the skin's own screen artwork stands); **the surface never takes a
  click**, because 51 archives wire an `onClick` on `<EFFECTS>` and that handler belongs to scene hit
  testing; and **the skin's selector is not the app's preference** — cycling from the rect, its menu,
  or the left/right keys never writes `visualizationEngineType`, which the visualization window and
  menu bar share.
  **Do not fill the widget's rectangle.** The effect is composited over the scene, and its untouched
  pixels must stay transparent: every renderer draws into the full authored rect and the skin's own
  artwork is what shapes it, through the z-order split above. **A suite renderer needs two extra
  conversions:** Cava's shared drawer assumes a y-up AppKit host and vis_classic emits top-row-first
  BGRA, so both require a local y-flip inside the flipped WMP view. Test the effect with a real skin
  at playback and inspect the AppKit-hosted frame; a static render dump cannot show its pixels.
- **The ban on hosting ProjectM / Geiss / Tripex in the slot is reversed, and this records why
  (W140).** The rule read: *it must never host ProjectM, Geiss, Tripex, or any other standalone
  visualization window in that slot*, with the black panels reported in Asimov Radio and Cerulean as
  its evidence, and `WMPEffectsSurfaceView.makeEngineView()` / `applyPreset(to:engine:)` were left in
  the file as dead code with zero call sites.

  **Those black panels were the occlusion defect, not the engines.** `WMPMainView` blitted the whole
  scene as one flattened image and hosted every widget above it with a plain `addSubview`, so nothing
  a skin drew could ever cover the surface. An opaque renderer that nothing can occlude *is* a black
  rectangle over the artwork — it would have been one whatever was drawing in it. With the split
  above, the artwork composites over the rect and opacity stops mattering; WMP's own visualizers were
  opaque too.

  What does not change: **the selection stays WMP-session-scoped** — a skin cycling `visEffects`
  never writes `visualizationEngineType`, which is why `switchEngine(to:forceReload:)` grew a
  `persistPreference` parameter rather than the surface calling it as the visualization window does
  — and **`VisualizationGLView` is not mounted live between the two raster layers**. A legacy CGL
  drawable's ordering against sibling `CALayer`s is not guaranteed the way normal layer z-order is,
  and its own `CVDisplayLink` clock tears against the overlay's alpha-blended edge. Do not mount it
  live "just to try"; that is what produced the black panels the first time.

  **How the three are hosted.** `WMPEffectsSurfaceView` builds a `VisualizationGLView` and never adds
  it to the hierarchy: its display link never starts, and a 30fps timer pulls one frame at a time
  through `renderOffscreenImage(pixelWidth:pixelHeight:)` — an FBO render plus `glReadPixels` — which
  `draw(_:)` presents like any other picture. **The GL path takes no y-flip**, where vis_classic
  does: `glReadPixels` returns rows bottom-first, a `CGImage` calls row 0 its top, and this view is
  flipped, so the two reversals cancel. The view's frame is set in **points** before each pull, not
  pixels — `initializeEngineOnRenderThread` sizes the engine from `convertToBacking(bounds)`, so a
  frame in pixels creates the engine at twice the surface it renders into. The readback is verified
  headlessly by `WMPPhase7Tests.testOffscreenEngineReadbackProducesAnImage`, which is the only thing
  in the suite that drives an `NSOpenGLView` outside a window.
- **PCM arrives on the audio thread and an overlay must not hop to the main actor to take it.**
  `.audioPCMDataUpdated` is posted from inside `AudioEngine.processAudioBuffer`; a
  `MainActor.assumeIsolated` in that observer is a `dispatch_assert_queue` failure and the process
  traps the moment a surface exists and a track plays. The WMP effect surface retains the latest
  spectrum snapshot and schedules its AppKit redraw on the main actor.
- **A semantic slider tag is itself a binding, and its range is part of what the tag says (W118).**
  `<SLIDER value="wmpprop:player.settings.balance">` states where a control reads; `<BALANCESLIDER>`
  states the same thing by *being* one, so a skin that uses the tag authors no `value` and usually no
  `min`. Two defaults then collided: `sliderMetrics` falls back to *the value of a slider nobody has
  told anything is its own minimum*, on a range defaulting to 0-100 — so **15 of the corpus's 16
  balance sliders drew their thumb at the bottom of the track, which on balance is hard left**,
  reported live as "balance is fully to the left by default on all skins". `VOLUMESLIDER` (31 uses /
  23 skins) drew empty and `SEEKSLIDER` (18 / 15) stuck at the track start for exactly the same
  reason; balance is the one where the wrong end of the track *means* something, which is why it is
  the one that got reported. `WMPObservablePropertyRegistry.implicit` synthesizes the binding the tag
  stands for, so the value arrives through the same coalesced, echo-guarded path an authored
  `wmpprop:` does and follows the host live. **The seek slider needs both halves**: WMP puts its
  position on the track in *seconds*, so `max` is synthesized onto `player.currentMedia.duration` and
  `value` onto `player.controls.currentPosition` — two paths the registry already answers, rather
  than a new percent path it does not. Ranges stay in `sliderMetrics.defaultRange(for:)`, which is
  `-100…100` for `.balanceSlider` and 0-100 for every other kind. An authored attribute always wins:
  one corpus balance slider states its own `value` and keeps it. **And a skin says the same thing a
  second way, by the range it declares (W120): 73 sliders across 61 of the 177 measurable archives
  author `max="wmpprop:player.currentMedia.duration"` and no `value` at all** — 58 as
  `<CUSTOMSLIDER>`, 15 as `<SLIDER>`, and no script in any of them ever writes one. That is the
  corpus's own seek bar, the way the Plus!, Xbox, Alienware, BlueCrush, Halo and Catwoman families
  all write it, and `positionSliderPaths` reads it: a control whose far end is the end of the track
  *is* a position control. Without it the filmstrip sat on frame 0 for the length of the track and
  the digit strips a skin positions from `value_onchange` sat with it — reported as "the clock does
  not work and seek does not work" and measured, seeded, as 68 rows across 52 skins moving off
  frame 0. **The other half of that report is the same slider read from the other direction (W51): a
  control is bound both ways, so the *host* moving it raises `value_onchange` too.** The user-driven
  half closed with W52; this is how a seek bar's readout follows playback and how a preset moving
  ten gains re-runs each band's handler. `Catwoman` draws its clock as four digit filmstrips
  positioned by `value_onchange="drawSeekDigits(value)"`, so until the handler was raised the slider
  tracked the song and the clock sat at zero. Two things make it safe rather than a feedback loop,
  and both were measured before it was written: **the registry only reports values that actually
  moved**, so a write-back handler (`eq.gainLevel1=value`, 2,141 of the 2,488 host-bound sliders
  carry one) hands the host the number it just gave and produces an identical snapshot; and **every
  one of the 19 handlers on a position-bound slider is a readout painter** — `drawSeekDigits(value)`
  ×17, `DrawTimeNormalView(value)`, `seek2.value=seek.value` — so nothing re-seeks. It is bounded
  like the two cascades beside it: only what the markup authored, only `value`, once per element per
  transaction, raised *before* the completion and geometry cascades so a repaint that writes
  geometry still propagates in the same frame. Its side effect is honest new demand rather than
  regression: 42 handlers that never ran now run and 30 of them abort on `event.shiftKey`, an
  **`event` object in a handler** that nothing binds on either direction of `change`. **The audio was never wrong** here —
  `AudioEngine.balance` defaults to centre and `performSlider` already wrote `fraction × 2 − 1` — so
  the whole defect was a drawn thumb lying about a centred pan, and no sweep of default-state images
  could have called it one.
- **A slider is a track plus a thumb the scene places**, and `WMPSliderMetrics` owns that geometry
  alone so each of its rules is testable: `borderSize` is dead track at *both* ends (171 skins),
  a **vertical** slider's maximum is at the **top** (1,312 of 1,968 `direction` attributes are
  vertical — every equaliser band is one), and the same metrics read the pointer back so a drag runs
  along the axis the skin authored. `foregroundImage` is the filled part of the track, cropped
  rather than scaled, and `useForegroundProgress="true"` (46 skins) redirects that fill to
  `foregroundProgress` — a buffer bar behind a thumb showing position, which are different numbers.
- **A `.wmz` says where a slider writes by binding its value, not by choosing a tag.** 163 skins
  author a plain `<SLIDER value="wmpprop:player.settings.volume">` rather than `<VOLUMESLIDER>`, so
  `WMPTransportAction.boundAction` maps the declared `wmpprop:` path to the action. Adding a bindable
  host property means adding it to `WMPObservablePropertyRegistry` *and* deciding whether writing it
  back is an action — one without the other is a control that moves and does nothing.
- **`EQUALIZERSETTINGS` is a settings object, not a control.** 163 skins author it and none give it
  geometry; the skin's own ten bound sliders *are* the equaliser. It is `isNonLayout`, like
  `<player>` and `<network>`.
- **`alphaBlend` is 0-255, inherits down the subtree, and 717 of its 778 corpus uses are `"0"`** —
  an element the skin hides and fades in later. A zero-alpha node still lays out, so its geometry
  stays readable, but it must not reach the command list at all: leaving it there put invisible
  artwork inside `visibleBounds` and every dirty rect derived from it. Honouring it changed what
  several skins draw, because the engine had been painting the topmost of eight stacked shells
  rather than the one authored visible — and it makes `alphaBlendTo` (W38) load-bearing, since a
  skin that fades its own panels in now shows less until that lands.
- **`passthrough="true"` (82 skins) is drawn and never hit.** A decorative overlay registered as a
  hit target swallows the controls beneath it.
- **`TEXT` reads `fontFace`, not `fontType`** — 109 skins against 21 — and `fontStyle` is a *set*
  (`"UNDERLINE, bold"` is authored), not one word. `fontSmoothing="false"` (95 skins) is a readout
  drawn as pixels; antialiasing it turns a 6 px digit into grey mush.
- **A `CUSTOMSLIDER` is the size of its `positionImage`, and its `image` is a filmstrip.** This was
  read out of the art rather than assumed, and `WMPPositionMap` carries the evidence:
  `ALXMorph/seek_map.png` is 86x10 whose columns step 0, 2, 5 … 252 — a **greyscale ramp whose
  luminance is the fraction** — against a `seek.png` of 86x600, sixty frames stacked vertically;
  its `volume_map.png` is a 72x38 arc against a 2232x38 strip of thirty-one frames laid out
  horizontally. So the strip's axis comes from whichever one is a whole multiple of the map, the
  value picks the frame, and a drag reads its value out of the map — which is the whole point of the
  element: its track need not be a straight line. Sizing one from `image` makes it 2,232 px wide.
- **`clippingImage` shapes an element, and it is what makes a shaped window shaped.** 25 skins
  author a non-empty one and every one of them declares a `clippingColor` beside it, which is what
  the mask keys out. Before it, `TDK`, `elvis`, `Secura`, `portals` and the six `US *` service skins
  all drew a black or grey rectangle behind their round artwork.
- **A mask buffer's row zero is the authored top row.** A `CGImage` drawn into a bitmap context
  arrives that way round — `WMPMappingImage` says so in as many words — so "correcting for
  CoreGraphics" by reversing the rows mirrors the mask and clips the half it should keep. That is
  W47 arriving by a second route, and only a **top/bottom** fixture can see it: a left/right one is
  identical under a vertical flip, and so is a horizontal position ramp.
- **`cursor` names a shape, not a file, in 2,246 of its 2,319 non-empty uses.** Classifying them all
  as artwork made every named cursor a *missing bitmap* (`BITMAPS … missing=hand sizenwse` across
  145 skins) and hid the name from the builder, which reads literals. `WMPAttributeParser` decides
  from the value; the ~70 `.cur`/`.ani` files stay resources and resolve to no cursor (W67).
- **Animation lives in the renderer, not the scene.** `WMPRenderer.render(clock:)` picks the frame,
  so a 10 fps GIF costs a re-render rather than a rebuild — a rebuild runs the skin's script
  transaction, which must not happen ten times a second. 90 of the 180 archives carry a multi-frame
  GIF (2,166 files). `animationCadence(for:)` gives the repaint loop its period *and* the union of
  only the animated frames, because repainting a whole window for one blinking LED is the difference
  between a skin that animates and one that burns a core. **A render dump is a still, so without
  `WMP_RENDER_CLOCK` an animation is unfalsifiable** — frame zero looks exactly like an engine that
  never animates.
- **The rate a user sees is not the rate `ANIMATION` reports, and nothing headless can tell them
  apart (W142).** Reported live as "the animation fps is low in general". `WMP_ANIM_TRACE=1`
  separated two independent causes on its first line — `want=25.0fps got=20.0fps frames=21
  restarts=10 sleep=42.3ms render=4.5ms` — and both are about *when* a frame is drawn, so a dump,
  a cadence line and a corpus sweep are all blind to them.
  * **A rebuild must not restart the repaint loop.** `startAnimation` runs on every rebuild and a
    `.wmz` rebuilds constantly — AlienMorph's 100 ms view timer alone restarted it ten times a
    second — and each cancel discarded a partly-elapsed sleep, so a 40 ms frame period inside a
    100 ms rebuild window landed exactly two frames per window. The loop now keeps running while
    `WMPViewPresentation.animationCadence` compares equal to the new one, and renders
    `activeScene` rather than the scene it was started with: a rebuild replaces *what* it draws
    without interrupting *when*. **That equality is the fix**, so anything that makes an unchanged
    animation produce an unequal cadence silently restores the defect.
  * **Frames are scheduled against the animation epoch, not "now + period".** `Task.sleep`
    overshoots and the render after it is serial, so a period per frame accumulated both into
    every interval. Deadlines off the epoch absorb them and are the same clock
    `WMPImageAnimation.frame(at:)` picks a frame with; falling a whole period behind skips to the
    next boundary rather than bursting.
- **A GIF delay of 0 or 1 cs means "as fast as possible", and the browser's answer to it is not
  this corpus's answer (W142).** `WMPImageStore.animationFloor` floors them at 0.0667s (15 fps);
  the browser convention of 0.1s was the largest single cause of "the animations are slow".
  **768 of the 2,166 multi-frame GIFs, across 62 of the 90 skins that animate, author a minimum
  delay of 0 or 1 cs, and 625 of those author nothing else** — at 0.1s `AlienMorph`'s 119-frame
  shutter took 11.9 seconds to open. **679 of the 768 are one-shot**, so this number is choosing
  how long a *transition* takes, not how fast a loop spins, and only one endless corpus GIF is
  short enough for the rate to read as a flicker. The floor itself is set **by eye against the
  running app** and there is no measurement that can set it — the file said "as fast as possible".
  0.04s was tried first, argued from the delays the corpus authors when it names one, and was
  reported too fast on sight. Do not re-derive it from the corpus; that argument is what produced
  0.04.
- **A `<POPUP>` is an equaliser preset menu and its items come from the skin's own script.** All four
  corpus popups call `appendItem` in an `onLoad` and apply the choice through
  `eq.currentPreset`; `WMPScriptOutput.listItems` carries them out of the transaction, because the
  markup names none of them. The four hardcoded entries that used to be shown were in no skin.
- **An `<EDITBOX>`'s `value` is a string.** Nine of the corpus's ten are `plSearchEdit`, a playlist
  search field whose `onKeyUp` reads it straight back, so it needs its own text path
  (`setWidgetText`) rather than the numeric `setWidgetValue`.

## Phase 6 widget and view contracts

- `WMPScene.widgets` is immutable semantic metadata for accessibility and native surfaces. AppKit
  overlays are created only after a completed scene arrives and are replaced with the scene.
- Playlist snapshots are capped at 4,096 rows. Selection, scrolling, play, removal, and movement use
  typed host actions; scripts receive plain copied item values, never `Track` objects.
- WMP exposes ten EQ gains. `WMPAudioEngineHost` uses `EQBandRemapper` at the boundary when the live
  engine is in its 21-band layout; every write remains clamped to ±12 dB.
- `EFFECTS`/`WMPEFFECTS` hosts the visualization surface. Its single ref-counted spectrum consumer
  must be registered only while an effects surface exists in the active view and removed on
  switch/teardown.
- `VIDEO`/`WMPVIDEO` draw nothing — the placeholder that painted them opaque black over the skin's
  own artwork is gone (W9). WMP plug-ins, ActiveX, DLLs, and arbitrary media surfaces remain denied.
- A view switch cancels capture and outgoing timers, stops continuous commands, clears view-local
  overrides, resolves off-main, preserves safe top-left, applies per-skin/view size, atomically swaps
  scene/native/accessibility state, then dispatches the view event.
- Auxiliary NullPlayer windows stay hidden in WMP mode until they have WMP-owned chrome. Never expose
  them through another skin family's provider or artwork.

## Verification

Use the committed original fixtures in `Tests/NullPlayerAppTests/Fixtures/WMPSkin/`. Run focused WMP
tests first, the user-supplied `WMP_TEST_WMZ` corpus check when available, then full `swift test` and
`git diff --check`. Do not commit third-party skins or build a DMG unless the user requests it.

## Phase 8 public exposure contracts

- The full edition supports `.wmp` in debug and release builds. A custom edition still decides
  through `EditionPolicy`; do not bypass that capability seam.
- `PlayerUIMode.stored(in:)` defaults to `.wmp` only when neither the current mode key nor the legacy
  `modernUIEnabled` key exists. Every persisted four-mode choice and both legacy Boolean values are
  upgrade inputs and remain authoritative.
- Keep `-uiMode wmp -wmpSkinPath /absolute/skin.wmz` available in packaged builds as a diagnostic
  launch hook. It imports through the production bounded importer and grants no direct file access to
  skin script.
- Public UI owns import, installed-skin selection, selected-skin removal, authored view selection,
  unskinned recovery, and bounded JSON compatibility-report export. Archive removal never deletes
  the user's original downloaded file.
- User support instructions live in `docs/wmp-skin/user-guide.md`; the exact implemented object-model
  contract stays in `docs/wmp-skin/compatibility.md`.

## Phase 7 hardening contracts

- `WMPCorpusReportHarness` is the reusable corpus seam. It emits archive hashes/facts, compatibility
  demand and unknowns, diagnostics, cold/warm load plus render/layout/hit metrics, and confidence.
  It must never serialize local input paths, source text, archive payloads, pixels, or screenshots.
- Keep reports outside the repository. `WMP_CORPUS_PATH` selects an external corpus directory and
  `WMP_CORPUS_REPORT_DIR` selects an external report directory for the opt-in Phase 7 test.
- Fuzz/mutation outcomes are success or `WMPFailure`; exercise archive metadata/payloads, strict
  text, XML, attributes/colors, mapping images, image decode, and bridge bounds.
- Render at the window's current backing scale and rebuild when backing properties change. Keep 1×
  and 2× correctness in original-fixture tests; never add real-skin goldens.
- Corpus-driven compatibility defaults must remain narrow. Empty optional images warn; text outside
  UTF-8/UTF-16/Windows-1252 and malformed duplicate-attribute XML remain typed rejections unless the
  security contract and compatibility rationale are deliberately amended.
