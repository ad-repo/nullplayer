# `.wmz` input: hit testing, clicks, keys and transport

Moved verbatim from `SKILL.md` on 2026-09-24.

## Which control a click reaches

**Three rules decide it, and each was measured against the corpus rather than reasoned from the SDK
(W148).** `WMP_RENDER_OCCLUDED=1` is the instrument and `reference/harness.md` describes it; the
report that produced them is *"plus pulsar skin seems to ignore most clicks despite showing hover
graphics"*. Hover and click take the same path, so a control that highlights and does nothing is not
a dispatch defect — it is a control the pointer never reached at all.

- **Order by the paint traversal, not by `zIndex`.** `WMPHitMetadata.paintOrder` is the position
  `WMPSceneBuilder.walk` had reached, which is the order `commands` is already built in: DFS,
  siblings sorted by `zIndex`, negative-z children ahead of their parent's artwork. Sorting the flat
  `hits` array on the authored `zIndex` compares literals from unrelated branches — the same
  flattening `cerulean` rules out for paint. `Plus! Pulsar` is the worked case.
- **A control is its artwork, not its rectangle.** `WMPHitCoverage` falls a click through a pixel
  the skin keyed out of the node's own sprite, exactly as `mappingImage` already does per colour for
  a `<BUTTONGROUP>`'s children. `Navigator` states the intent outright: its `progress` slider spans
  the whole player and `progress_map.bmp` has holes cut in it where the close, full-mode and
  visualization buttons sit. **Two guards, and both cost controls when they were missing** — a
  sprite with *nothing* opaque in it is a hit catcher rather than a shape (`holiday_skin`, `Grinch`
  and `Josie_and_the_Pussycats` build whole transports that way, 104 controls across 21 archives),
  and a node with a `mappingImage` takes its region from the *map*, never from its art.
- **A button is every state sprite it authors, not the one it is drawing (W306).** The pointer
  sees the hover sprite, so that is the shape it aims at: `xsn_sports`' `visDrawerButton` is a 13x7
  arrow in `image`/`downImage` under a 19x13 `hoverImage`/`hoverDownImage` tab, opaque edge to edge,
  and a press on the tab's margin hit nothing (`raw=-#-`, 8 of 8 with the drawer open). Coverage for
  any node but a `<BUTTONGROUP>`, `<SUBVIEW>` or `<VIEW>` is the union of `image`, `downImage`,
  `hoverImage` and `hoverDownImage`, each placed at natural size, top-left, as the foreground path
  draws it. **Only a node that already has a shape widens** — a union only adds pixels, and a hit
  catcher (fully transparent `image`) keeps its whole rect whatever its hover sprite is. **It is
  cached** (`WMPImageStore.stateCoverage`, keyed by the paints and the frame's size): a scene is
  rebuilt on every host tick, and re-sampling four sprites per button cost `Secura` a core, which
  showed as every click landing a click late. Measured over 179 archives with
  `WMP_RENDER_OCCLUDED=1`: no `lost` count moved; ten skins changed, all classified — `Zengarden`'s
  `pausebutton` now covers its stacked `Playb` while playing (the visible one), `Scooby-Doo_2`'s
  colour button's glow reaches into `infoButton`'s keyed corner, the rest are masks becoming whole
  rects. **The release half** is `WMPMainView.mouseUp`: a release inside the captured target's frame
  where no other control answers is a release over it.
- **A hosted surface is its picture, and its picture ends where the skin paints over it (W213).**
  `<EFFECTS>` and `<VIDEO>` already rank last, which keeps the controls drawn over them; what
  ranking cannot give back is the artwork *between* those controls, which is not a control at all.
  `circle`'s `<EFFECTS>` is `jscript:vMain.width` by `jscript:vMain.height` — the whole player — so
  every press answered "visualization" and **the window could not be dragged**.
  `WMPHitCoverageBuilder.surfaceCoverage` reads the layer `commandSplitIndex` already separates for
  drawing and leaves the surface reachable only where it can be seen. **The half that decides the
  corpus is that a command paints only where the shapes it is inside keep it**: `clippingColor` keys
  a container's shape and never its artwork (W169), so `cerulean`'s `face.bmp` is opaque `#FF0000`
  across its own lens and only the container's region mask opens the hole. Read without the masks it
  buried the surfaces of `cerulean`, `aoe`, `claw`, `gadget` and `pharaoh`. Measured over the 184
  installed archives: the `rect-only` set is identical to the baseline — no control lost — and 20
  surfaces tighten. A **windowed** surface is excluded: nothing the skin paints is drawn over it.
- **A `CUSTOMSLIDER`'s `positionImage` is the authority on its region, and the colours the node
  keys out are not part of it (W150).** `WMPPositionMap` marked only *alpha-zero* pixels as outside
  the control, and `Plus! Pulsar`'s `seek_map.png` marks the 66% of its 79x136 square that is not
  the arc as opaque `#ff00ff` — averaged to a luminance that is a fraction of `0.667`, so two thirds
  of the seek control answered "seek to 67%". Coverage for such a node comes from the **map**, never
  from the sprite: `seek.png` is a 13-frame filmstrip whose opaque area is a property of the frame
  the current value selects, and deriving the region from it cost the arc 577 of its own pixels —
  the soft edges a pointer aims for. Measured before landing: **173 corpus sliders declare a key on
  a node with a position image and not one of them is a grey**, so no ramp value can be clipped by
  this.
- **A slider's region is the track it authored, not the artwork drawn in it (W256).** Every other
  control is its artwork; for a slider that rule reads the **thumb**, because a `<SLIDER>` paints a
  thumb at the current value and nothing else unless the skin gave it a track sprite. `elvis`'s
  eight bands are `<slider width="10" height="75" thumbImage="elvis_eqknob.gif">` with no track, so
  coverage claimed the 11x12 knob: four fifths of each band rejected the pointer, the press fell
  through to the tray's `<buttonGroup>` behind it, and pressing the track **dragged the window**.
  Driven live, `eq1` was the front-most candidate at the press point and lost on coverage alone.
  WMP moves the thumb to wherever the track is clicked, so the frame *is* the control — the skin
  authored a 10x75 box because that is the box it wants pressed. **A `CUSTOMSLIDER` is the
  exception and keeps its position map**, which is a better answer than the frame rather than a
  worse one (W150). **Reach: 448 sliders across 41 of 184 archives** paint a thumb and no track, measured
  2026-09-22 by `python3 scripts/wmp_slider_drag_census.py` (population B).
- **Whatever advertises a control must agree with the hit tester.** `resetCursorRects` and the
  `stringForToolTip` widget fallback both scanned bounding boxes, so Pulsar's dead corners kept a
  hand cursor and a "Seek" tip over pixels that hit nothing — reported as *"a clickable artifact to
  the right of the seek that does nothing"*. Both now consult `WMPHitCoverage`; the cursor is added
  as one rect per run of covered pixels per scanline, because `addCursorRect` is a list AppKit scans
  and an arc is ~136 bands where a pixel mask would be thousands. **A new surface that reads
  `hit.frame` to offer the user something inherits this bug** — ask coverage too.
- **A control the pointer is holding is the user's, and the host does not write to it (W151).**
  `WMPPropertyRegistry.positionSliderPaths` gives any slider whose `max` binds to
  `player.currentMedia.duration` an *implicit* `value` binding to `player.controls.currentPosition`
  — that is W128 and it is right, or the filmstrip never advances. But it settles on **every**
  transaction, including the one the release raises, and a skin that commits its seek by reading the
  control back (`onmouseup="player.controls.currentPosition=seekMain.value;"`) therefore seeks to
  wherever the track already was. `changes(for:origin:holding:)` skips `value` for held elements —
  only `value`, so `enabled` and `max` still settle — and `sliderCaptureActive` suppresses the two
  position events that raise the skin's own write-back. **Reach: 148 sliders across 112 of the 180
  archives**, every one whose `max` binds to the duration *and* which commits in its own handler. A
  slider with a `value` binding to a transport path is immune and is **not** the test:
  `performSlider` commits those natively through `WMPTransportAction.boundAction`, which is why
  `Plus! Pulsar`'s volume arc always worked while its identical seek arc did nothing.
- **A seek is committed once, on release — every other slider action is continuous (W156).**
  `WMPMainView.performSlider` runs from `mouseDragged`, so a `.seek` used to reach
  `AudioEngine.seek` on every mouse-move: **21 commits across a 200 px drag**, each one a
  `playerNode.stop()` and a reschedule with no ramp, which is what *"a harsh audio artifact at the
  time adjustment"* was. It is now held in `pendingSeek` and handed to `onSliderRelease` at
  `mouseUp` (`cancelInputCapture` drops it — a cancelled drag asks for no seek). Volume, balance and
  the equaliser bands still commit per move; a volume drag the user cannot hear is a broken control.
  **Who commits it is decided after the skin's own handlers have run, never from the markup**:
  `WMPMainWindowController` awaits the release transaction and commits `pendingSeek` only if that
  transaction posted no `seekSeconds` (`scriptDidCommitSeek`). Both halves are load-bearing — 111 of
  the corpus's 141 `onDragEnd` sources are `player.controls.currentPosition = value` and would
  otherwise be seeked twice, while a bare `<SEEKSLIDER>` authors no release handler at all and has
  no other committer. **The thumb is not deferred, only the audio**: `widgetValues` and
  `onElementValueChanged` are untouched and W151's hold keeps the position binding off the user's
  value. **The skin the report blamed was not the difference.** `New Super Mario Bros` was reported
  harsh and `corona` clean; driven live, they are identical — 21 commits apiece, Mario through its
  `value` binding and corona through `target.action` — and the markup changes only the 22nd. How
  harsh it sounds is the material and the distance dragged, not the authoring.
- **A `<PROGRESSBAR>` is a slider the pointer moves.** `WMPMainView.holdsValue` is the one test
  for "this press writes `value`", and it used to be `kind.contains("slider")`, which a
  `progressBar` fails. **12 of the corpus's 14 `<PROGRESSBAR>`s are seek bars** — `max` bound to
  `player.currentMedia.duration` and `onmouseup="player.controls.currentPosition=progress.value;"`,
  several with `cursor="hand"` (`cyberchannel`, `Official_Xbox_MP71`/`_XP`, `XBOX`, `The Unit`,
  `TheUnit`, `The_Sentinel_v.1.0`, `Ursula`, `Mandalay`, `v2_underworld`, `Ducky`); the other two
  are `digitaldj`'s `visible="false"` query meters. A press never moved `value`, so that handler read
  the live position back and seeked to where the track already was — "the seek bar does nothing".
  Counted with `scripts/wms_grep.py -i -c '<progressbar'` and the element bodies read by hand.
  Pinned by `WMPSliderCommitTests.testAProgressBarTakesThePointersValue`.
- **A release with nothing pressed raises no `mouseup`.** `handlers(in:event:targetID:)` reads a nil
  target as *every node in the view* — right for host events, wrong for a pointer. A press on a
  greyed-out control (W154/W313) captures nothing and starts no drag, so its release went out
  untargeted and ran every `onmouseup` the view authors: on `cyberchannel` a press on Play while
  playing ran the seek bar's commit, a seek to the current second and an audible hiccup. `mousedown`
  was never raised untargeted, so the pair is now symmetric. Pinned by
  `testAReleaseWithNothingPressedRaisesNoMouseUp`.
- **A transport element that issues its own command in `onClick` owns the click, and the engine must
  not post the command as well (W243).** `<NEXTELEMENT onClick="player.controls.next()">` says the
  same thing twice — the kind carries `.next` and the handler calls it — and `WMPMainView.mouseUp`
  raised the handler *and* applied `WMPHitTarget.action`, so **one click on `ALXMorph`'s Next
  advanced two tracks** of a three-index cue (First → Second → Third, 10 ms apart, driven live).
  `WMPTransportAction.handlerOwnsAction` decides it at scene build and the flag rides on the hit and
  on every mapping child; the keyboard activation path had the mirror defect — it posted the action
  and never ran the handler at all. **Reach: 73 elements across 19 of 182 archives** (`next` 17 uses
  / 16 skins, `previous` 15 / 14, `play` 20 / 19, `stop` 14 / 13, `pause` 7 / 7), counted over
  `wmp_markup_census.sh`'s flat files. **It is a dedupe and not "an authored handler wins"**: three
  corpus elements author a handler that only plays a sound and rely on the tag for the transport.
  **Since W265 a plain `<BUTTON>` whose action was *derived* from its own literal is owned by the
  handler too** — W243 had exempted it, and it doubled on **108 of 179 archives**; the derived action
  is kept only for the sticky latch and the enabled state. This is the rule `dispatchScriptEvent`
  already applied to `<RETURNBUTTON>`, where `anemone` and `modernblue` spell
  `view.returnToMediaCenter()` themselves. **Why it outlived every headless sweep:**
  `WMP_RENDER_CLICK` runs the authored handler and prints its host command and never applies
  `action`, so the probe shows one command where the app sent two — `harness/probe-flags.md` § *The probe flags*
  states the gap on the flag itself. The symptoms are shaped like the engine losing a click, not
  doubling one: `play`/`pause`/`stop` are idempotent and hide it, a `sticky` toggle driven this way
  returns to where it started, and only `next`/`previous` show the skip.
- **Mute and its button, driven live on `Frostbite` and `Plus! Professional` (W265).** Three defects
  stood behind "the mute button never shows down while muted", and the first meant it never muted:
  - `Frostbite`'s `<BUTTON sticky="true" down="wmpprop:player.settings.mute"
    onClick="player.settings.mute = !player.settings.mute">` (the corpus idiom — **50 archives** bind
    `down` that way) posted the derived `.toggleMute` *and* ran the handler, which read the
    pre-click snapshot and unmuted 5 ms later. See the W243 bullet above.
  - **A muted host reports the level it was muted from, not zero.** `WMPAudioEngineHost` mutes by
    zeroing the output (engine, local video and cast alike) and used to report that zero as
    `settings.volume`. WMP keeps the volume while muted, and `Frostbite`'s knob binds
    `wmpprop:player.settings.volume` with a `value_onchange` that ends `player.settings.mute = false`,
    so the settle after every mute moved the knob and unmuted ~40 ms later. `muteLatched` holds the
    pre-mute level for the readback; any volume write clears it, and a slider dragged to zero still
    reads zero.
  - **`<MUTEBUTTON>`, `<REPEATBUTTON>` and `<SHUFFLEBUTTON>` are sticky unless they author
    `sticky="false"`.** One of their 14 corpus uses (`QuickSilver`'s mute) says `sticky`, and
    `WMPMainView.refreshHostState` latches only sticky hits from the host, so `Plus! Professional`'s
    mute never drew `downImage`.

  None of it has a headless signature: `WMP_RENDER_CLICK` never applies the hit's action and a sweep's
  host never mutes, and no shipped trace prints a host command. Drive it with `WMP_CLICK_TRACE=1`
  (one `click` per press), listen for the silence, and read the down face off a `winhelper capture`
  taken with the pointer moved away — a capture under the pointer shows the hover face.
- **A control the host has greyed out is still a control, and the window does not move under it
  (W154).** `WMPMainView.interactiveTarget` answers `nil` for a disabled target exactly as it does
  for bare artwork, and `mouseDown` reads that as "no control here" — so pressing a greyed transport
  button **dragged the whole player**. Reported on `portals/mode1`, where a press on play with an
  empty playlist moved the window from `680,279` to `374,509`; `refreshHostState` disables every
  transport child while `player.controls.play` is unavailable, which is most of the corpus's
  five-button `<BUTTONGROUP>`s on a cold start. A disabled target now swallows the press. **An
  authored `enabled="false"` is not this case and still drags**, because those never reach the hit
  tester at all — which is what keeps `portals`' own 305x400 decorative `main_button` backdrop
  movable, and is the distinction to preserve if this is ever touched again.
- **A control a binding has switched off is the same case, and `hitTest` never returns it (W313).**
  The W154 check only asks whether `hitTest` found something, and `hitTest` skips every disabled hit —
  so `KungFuChaos`' speaker button, `enabled="wmpprop:eq.enhancedAudio"`, dragged the EQ window with
  SRS WOW off. The only visible symptom was the **docked-group highlight**: the EQ touches the
  library window, so a press that starts a drag outlines that window for as long as it is held. The
  builder marks a hit `greyedOut` when it is disabled by an override or the host rather than by a
  literal `enabled="false"`, and `WMPHitTester.isGreyedOutControl(at:)` makes `mouseDown` swallow a
  press on one. Pinned by `testPressOnABindingDisabledControlDoesNotDragTheWindow`, which also keeps
  the authored case draggable.
- **The view itself is never a press target (2026-09-26).** `authorsInputHandler` makes any node
  with a mouse handler a hit, and that includes the root `<VIEW>` — which sits under every control,
  so it answered every press nothing else took and `WALL-E` could not be dragged from anywhere
  (`raw=view#mainView … interactive=yes` on every press under `WMP_CLICK_TRACE=1`). The view stays
  in the hit map so its `onMouseOver`/`onMouseOut` still fire; `WMPMainView.mouseDown` drops a
  `view` target and drags the window instead. **Reach: 2 of 179 archives** — `WALL-E`'s `mainView`
  and `Revert`'s `vwPlayer`, both hover-only; no corpus view authors `onClick`/`onMouseDown`.
  Pinned by `testPressOnAViewWithAHoverHandlerDragsTheWindow`.
- **`host.snapshot` is computed live and carries the clock, so never diff it across a transaction
  (W157).** `WMPAudioEngineHost.snapshot` reads `engine.currentTime` on every access; two readings
  taken either side of a 10 ms transaction always differ while a track plays. `dispatchScriptTransaction`
  used to end on `if host.snapshot != hostStateBeforeCommands { refreshHostState() }` to notice a
  host its own commands had moved, and with playback that fired on **every** pass — raising
  `currentposition_onchange`, which dispatched another transaction, whose defer raised another.
  Measured live on `NVIDIA`, release: **39.9 refreshes/s from that defer against 9.9/s from the real
  10 Hz tick**, every one of them from a transaction that posted zero commands. It is now taken only
  when `output.hostCommands` is non-empty. Anything that wants "did the host move" must compare the
  fields it cares about, never the whole snapshot.
- **A transaction whose overrides are unchanged has nothing to draw, and must not build a scene
  (W158).** `transact` returns the view's **cumulative** committed overrides, so equality with
  `presentation.sceneOverrides` means every geometry value, property and `wmpprop:` binding resolved
  as it already had — `WMPSceneBuilder.build` takes no host snapshot, so there is no third input
  except a `LISTBOX`'s script-filled rows (`presentation.presentedListItems`). Without the skip, a
  skin's own `onTimer` cost a full rebuild and full-window re-render per tick whatever its handler
  did: **442 `timerInterval`/`onTimer` uses across 91 archives**, and `NVIDIA`'s 100 ms timer alone
  redrew an identical 730x574 playlist ten times a second. Stopped, all of its ticks now skip (CPU
  22% → 9.5%); *playing*, none of them do, and that is correct — the trace names what moves and it is
  the seek slider's bound `value` at 16/s. **Repainting the whole view because one clock digit moved
  is the remaining cost and it is a dirty-region problem, not this one.**
- **Measure a `.wmz` perf claim in release, and say which build it came from.** A debug scene build
  is ~31 ms where release is ~4.6 ms, which is the difference between "the playlist runs at 1 fps"
  (debug, arrivals beating completion so nearly every transaction is cancelled mid-flight) and "it
  runs at 22" (release, same code, same skin, same track). Both readings above are real; only one of
  them is what a user sees.
  **Its limit is total starvation, and a readout is where it shows.** A transaction whose build
  and render outlast the clock tick is cancelled by the next tick every time, so nothing it carries
  ever presents: `cyberchannel` (debug, 2x) resolved `position.value` to `0:01`, `0:02`… on every
  tick and drew `0:00` for the whole track, because its render took ~90 ms against a 100 ms tick.
  Counting `build` against `rendered cancelled=` around the `Task.isCancelled` guard showed 25
  builds and 24 cancellations. The fix was the cost (`WMPRenderer.paintedMask`, see
  `rendering/video.md`), not the cancellation; release was not measured.
- **Two ordering traps live in `dispatchScriptTransaction`, and both give plausible wrong answers.**
  It **cancels the presentation's previous script task**, so dispatching two events back to back
  loses the first — put both handler sets in one event. And it only *creates* a task, so anything
  that must outlive the transaction (releasing a hold, clearing a gate) has to `await
  presentation.scriptTask?.value`, not simply follow the call.
- **A key handler owns an arrow only where it compares that arrow.** `WMPMainView.keyDown` offers
  every key to the skin before the hosted `<EFFECTS>` surface's own keys (up/down pick the effect,
  left/right step inside it), and the offer must be answered synchronously, from the markup.
  "A handler is authored" was that answer, and **68 of the 154 archives with an `<EFFECTS>` hang a
  letter-hotkey handler on its view** (`onKeyPress="viewHotKeys();"`) that never compares `37`…`40`
  — so on those skins every arrow was claimed and the visualization keys did nothing (`Halloween`,
  2026-09-24). `WMPKeyHandlerScan` reads the handler and the bare functions it calls for a literal
  comparison of the arrow's VK; only arrows are scanned, and every other key a handler is authored
  for stays the skin's. The arrow handlers the corpus does write are on sliders (`volKey(event)`)
  and on views with no `<EFFECTS>` (`viewResizer(event)`), and they keep their keys. **Comments are
  stripped before the scan** (`withoutComments`; string literals kept, so a URL's `//` survives): a
  function it cannot find claims the key, and `Age_of_Mythology_MPXP`'s `viewHotKeys` carries a
  commented-out `videoZoom();` whose body calls an undefined `updateZoomToolTip` — every arrow was
  claimed through dead code (2026-09-26). **Live check:**
  `WMP_CLICK_TRACE=1` prints `offer keydown keyCode=38 targetID=view … authored=0` on such a skin,
  and a `[wmp/pref] … currenteffecttype_onchange` line follows each up/down press.
- **`<EFFECTS>` and `<VIDEO>` are fallbacks, never blockers.** Both are click-through by design —
  `WMPEffectsSurfaceView.hitTest` returns `nil` — but 51 skins wire an `onClick` on the effects node,
  so they rank last rather than not at all. Both are routinely the largest node in their view and
  declared late, so paint order alone buries whatever is drawn over them: `Alienware Invader`'s
  rating stars, `Radio`'s equalizer sliders, `XBOX`'s `xDown`.

Net over the 180-archive corpus, `WMP_RENDER_HOST=playing`: **112 controls in 33 archives recovered,
11 lost**. W149 closed all of them as not defects (2026-09-24): each is lost only in the load-time
layout — a closed drawer, a stacked twin running the same handler, a container whose element still
answers, a clipped sprite frame — see `harness/sweep-limits.md` § *The residue `WMP_RENDER_OCCLUDED` does not
explain (W149)*.

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
- **A skin's own name for its `<EQUALIZERSETTINGS>` is another spelling of `eq` (W256).** `eq` is a
  bound global on the *path* `eq`, so `<equalizerSettings id="ElvisEQS">` was an ordinary element:
  `ElvisEQS.gainLevel1 = value` landed in its own property bag, reached no audio, and the band
  slider bound to `wmpprop:ElvisEQS.gainLevel1` never moved, because that binding resolves from the
  host. The name is folded to `eq` in `WMPObservablePropertyRegistry.init` for bindings and routed
  in `WMPObjectModel`'s read/write/call for script; `enableSplineTension`, `splineTension` and
  `bypass` stay the element's bookkeeping (W134). Reach **7 of 184 archives**; the full rule and the
  numbers it replaces are `reference/object-model/elements.md` § *The `eq` object and the element are one
  surface (W39)*.
