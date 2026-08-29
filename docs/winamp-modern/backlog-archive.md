# Winamp Modern backlog archive

Closed backlog history moved from `TASKS.md` and `BENTO_TASKS.md`. Entries below preserve the original text verbatim except for relative link targets adjusted to this directory; the added archive heading records the id, title, and close date. The live, reach-ranked backlog is [`TASKS.md`](../../TASKS.md).

## B41 (implementation) — `getMonitorWidth` / `getMonitorHeight` answer the player's own display — shipped 2026-08-26

Moved out of `TASKS.md`, where it had been sitting as a closed `- [x]` item under an otherwise open
entry. **B41 itself remains open** for its manual two-display check; only this half is done.

`getMonitorWidth()` / `getMonitorHeight()` are zero-argument integer System methods. The runtime's
earlier compatibility stub always read `NSScreen.main`, which is the primary display rather than
necessarily the display containing the skin. The window controller now supplies the frame of the
screen containing the `.wal` player, including during startup before the borderless player becomes
`NSApp.mainWindow`. Values are AppKit **logical screen points**, matching the runtime's other desktop
coordinates; they are never multiplied by `backingScaleFactor`, because Retina backing pixels do not
belong in MAKI geometry. Fractional values floor, invalid/non-positive values answer zero, and values
beyond MAKI's signed integer range clamp. `WinampModernPhase78Tests` covers dispatch, numeric
boundaries, unsupported-demand accounting and teardown.

## B64 — Anexa: the progress bar was invisible unless it was full — closed 2026-08-28

Reported live: *"the progress/seek bar only shows when it is 100% full. otherwise it is invisible but
functional"*. Anexa draws both its main and its shade progress bar as a `<layer>` clipped by a region
map. **Two independent faults were stacked on it, and both produce the same empty bar**, so fixing
either alone changes nothing on screen.

1. **`System.onSeek` had no arity.** The only thing that ever fills the bar is the skin calling its
   own system handler from a 99 ms timer (`UpateTimer.onTimer() { System.onSeek(getPosition()); }`).
   `onseek` was missing from `dispatchableEventArity`; dispatch is fail-closed, so the call abandoned
   the whole `onTimer` at its first statement. The bar was only ever *seen* full because `onStop`
   sets the region to 255 — the one path that still ran. Nothing dispatches `onSeek`; it is callable
   only, because the one corpus handler drives itself.

2. **The playback clock answered seconds.** Behind that, the skin scales with
   `int devby = len/255; setRegionFromMap(map, pos/devby, 1)`, and in seconds `devby` narrows to
   **0** for every track under 4:15 and takes the script's own `if (devby <= 0) return;`. The unit is
   **milliseconds**: `getPosition`, `getPlayItemLength`, `seekTo`, `integerToTime`'s argument and the
   `length` metadata key all moved together, through one `WinampModernScriptRuntime.milliseconds(_:)`.

**It fixed one other skin.** Styx's notifier formats its length by hand from
`getPlayItemLength()/1000`, which was 0 in seconds, so it took its own `else` and printed the title
with no duration. Traced before/after through the render harness: `settext(… Display    )` →
`settext(… Display (4:05))`. Shield_Amp ships the same notifier code and is **not** fixed — its
`onScriptLoaded` still aborts on `setChecked`, so the notifier never initialises at all.

Everything else in the corpus is invariant: every other `getPosition`/`getPlayItemLength` call site in
the 19 skins that ship `.m` sources is either a ratio of the two or feeds `integerToTime`, and the
family moved as one. 16 of the 35 installed skins are compiled-only and could not be scanned that way.

`WinampModernB64Tests` covers both halves; the durable rule is in
[`compatibility/maki-surface.md`](../../skills/winamp-modern-skin-guide/compatibility/maki-surface.md)
→ *Time is milliseconds*, and the method that settled the unit is in
[`triage-playbook.md`](../../skills/winamp-modern-skin-guide/triage-playbook.md) → *A unit is settled
by the minority*.

## B63 — cPro-Bento: the clock froze during a film, and the video window popped out on a tab switch — closed 2026-08-28

Reported live: "when you play video in the cpro_bento skin, it displays properly in the tab but the
timer is in a paused state despite it running. if I switch tabs the video pops out rather than be
hidden".

Two unrelated defects behind one report.

**The frozen clock.** `WindowManager.videoPlaybackDidStart()` *pauses* `AudioEngine` for the whole of
a film, and `WinampModernAudioEngineHost` answered `playbackState`, `currentTime`, `duration` and
`trackTitle` from the engine alone — so the skin read "paused, 0:00" while the picture played in its
own tab. Classic and Original never had this because their views substitute
`WindowManager.isVideoActivePlayback` at every draw; the `.wal` host had no equivalent. Fixed with a
`videoSession` provider on the host, the one seam every `.wal` readout, script binding and
`getPlayItemMetaDataString` key already goes through, so the renderer's clock and a script's
`timeelapsed` cannot disagree. Keyed on the video's **title**, not on `isVideoActivePlayback`, whose
`isVideoOutputVisible` term goes false the moment the picture is unparked — precisely the state a film
running behind another tab is in. A video session posts no transitions of its own (`videoPlaybackDidStart`
fires once and nothing reports a pause), so `WinampModernMainView.updateTime` compares the state each
tick and calls `updatePlaybackState()` when it moved; that is what repaints a paused film's transport
artwork and delivers `onPause` / `onResume` to the skin's scripts.

**The escaping window.** A holder leaving the scene ran `unmountFromHolder()` → `detachVideoOutput()`,
which unparks *revealing* NullPlayer's own video window. That is right for a skin's video **window**
closing (B20), and wrong for a **tab**: cPro-Bento's tab strip removes and restores that holder all
session long, so leaving the Video tab threw our window out over the skin. `unmountFromHolder()` now
unparks and stays hidden — the film plays on, unseen — while `prepareForUITeardown()` keeps the reveal,
because a scene that is going has no tab to come back to. `reconcileHostedSurfaces` re-parks the
picture when the holder *reappears*: that is the only moment that can, since the other parking route
runs on a **play** call and the film has been playing all along.

Durable rules landed in
[`reference/components/video.md`](../../skills/winamp-modern-skin-guide/reference/components/video.md)
(*The picture's clock is not the audio engine's*, *A holder leaving is a tab switch, not the end of the
film*), with the unmount/teardown split cross-referenced from
[`reference/components.md`](../../skills/winamp-modern-skin-guide/reference/components.md). The same
file's stale "never embedded" routing bullet was corrected — B23 made cPro-Bento's tab the embedded
case. Regression coverage is `WinampModernPhase79Tests`; `swift test` 1368 passing. Confirmed live by the
reporter.

## B62 — cPro-Bento: three buttons blacked out under the pointer, and the corner bolt did nothing — closed 2026-08-28

Reported live: "there are 3 unimplemented buttons on cpro__bento skin. the bottom 2 on the right and
the button next to the volume. they just turn black when you mouse over them. the winamp logo on the
far right corner does nothing".

Four faults, three of them one root cause.

**The blacking out.** `mute`, `shuffle` and `repeat` are `<nstatesbutton>`s whose `image`,
`hoverImage` and `downImage` are all *prefixes* (`image="mute.1." hoverimage="mute.2."`, bitmaps
`mute.1.0` … `mute.3.1`). Only `image` was suffixed with the state, so hover and press named ids
nothing answered; an unresolved id draws nothing, and on this skin what showed through was its black
display. Fixed in `WasabiSceneRenderer.resolvedBitmapID`, which now owns the whole choice for the
type and falls back pressed → hover → rest state → bare base.

**The frozen artwork.** The state came from an unused `state` attribute, plus an `xmlID.contains
("repeat")` special case. It now resolves from the `cfgattrib` binding (mapping through
`cfgvals="0;1;-1"` **positionally**, so the state is the value's index), then the object's own counted
`value`, then the id. Shuffle and repeat had been driving the engine correctly the whole time — only
their lamps were stuck on state 0, which is why they read as unimplemented.

**The dead mute.** `toggleActivation` accepted only `togglebutton`, so an `nstatesbutton` was never
flipped and `mute_but.onToggle` — which is the entirety of mute's behaviour — never ran. It now
accepts the type and cycles `(value + 1) % nstates`; `setActivated` writes `value` alongside
`activated` so a persisted mute does not come up lit while counting itself on state 0.

**The invisible bolt.** Its markup declares only `hoverImage`, which is why it appeared solely under
the pointer. `player.maki` gives it `image="winamp.logo.1"` only when `loadMap("buttons.png")` reports
332 wide, and `mapLogicalPath` resolved that bare filename beside the *script* — in the engine mount —
rather than in the skin, so `getWidth()` answered 0. Now falls back to `vfs.skinRoot`, requiring the
file to exist at each step.

**And the bolt genuinely did nothing.** It is a multi-button: the right-click menu only records which
of six commands the *left* click runs, and the default is `TOGGLE guid:{D6201408-…}` — About Winamp —
which nothing answered. Routed to NullPlayer's own About panel alongside the existing
colour-themes-preferences GUID case. The other five were measured with a new probe flag,
`WINAMP_MODERN_RENDER_CLICK_PICK` (the harness's popup presenter had always answered 0, "the user
picked nothing", which for a menu whose choice only takes effect on a later click is the same as never
opening it): four work, `ML_SendTo` is deliberately inert. The per-command table is in
[`skins/cpro-bento.md`](../../skills/winamp-modern-skin-guide/skins/cpro-bento.md).

Durable rules landed in [`reference/rendering.md`](../../skills/winamp-modern-skin-guide/reference/rendering.md)
(*An `<nstatesbutton>`'s three artwork attributes are all prefixes*) and
[`reference/loading.md`](../../skills/winamp-modern-skin-guide/reference/loading.md)
(*`loadMap("file.png")` resolves against the skin*). Confirmed live by the reporter.

## B61 — opening Big Bento's side playlist threw the player into the corner of the monitor — closed 2026-08-28

Reported live: "you open the playlist panel and the window repositions to the top corner of the
monitor". Big Bento Modern (Windows 10 edition), side playlist.

**Measured, not reasoned.** `WINAMP_MODERN_PLACE_TRACE=1` printed
`[place/script] o44 -> {0, 128} (was {100, 98})` on the toggle — a *script* move, so neither the
tiler nor `place`. A temporary probe on `resize` named the receiver and the arguments:
`resize on layout id=normal prog=player-normal.xml args=0,0,1536,878` — `pledit.maki` re-placing the
player with `resize(getLeft(), getTop(), w, h)`, both reads answering 0.

**Cause: the read and the write were in different spaces.** `getLeft()`/`getTop()` on a layout answer
its own canvas origin (0); the `x`/`y` a `resize()` writes are pushed to the desktop as absolute
screen coordinates. Handing back what was just read therefore meant "move to 0,0", and the
`moveContainerWindow` clamp landed the player at the top-left of the visible frame.

**Fix.** `applyContainerGeometry` compares the written `x`/`y` against the origin the object reported
*before* the write and skips the move when they are the same pair. Only the round trip is recognised,
never the value, so a script writing a position it did not read — Big Bento's search-results popup
(BB31) — still moves its window. A `<container>`, which has no layout space of its own, now reports
the host's real desktop origin (`containerOriginQuery` → `winampScreenOrigin`), the exact inverse of
the point `containerMoveRequested` accepts; the graph attribute stays as the fallback.

**The wrong fix, shipped and reverted the same day.** Making a *layout* report its desktop position
looks like the principled answer — Wasabi does call a layout a window — and it fixed B61. It also
broke multipass: its side drawers are positioned from `layoutMainNormal.getLeft()`, so every drawer
and its hover region moved off the artwork, reported live as drawers that could not be opened and
that "autosense very strangely". `newgroupaslayout` depends on the same 0. A layout is the space its
children are laid out in, and skins do arithmetic across that boundary; the round-trip problem
belongs on the write side, where it cannot disturb a read.

**Verified in the running app** at two window positions, and confirmed by the reporter for both
skins. Detail in `skills/winamp-modern-skin-guide/reference/scripting.md`.

## B57 — NullPlayer's own windows barely drag inside a skin frame — closed 2026-08-28

### B57

Reported live: the hosted windows were "very hard to drag, the area seems very small". Found by
measuring, with `WinampModernDragProbe` (`WINAMP_MODERN_DRAG_HOSTED`, documented in
`reference/harness.md`), not by reading the markup.

**B55's mistake, in one line.** It read *the skin's frame owns the chrome* as *the frame owns the
drag*, and gave all eight hosted surfaces a `guard hostedContext == nil else { return }` in
`mouseDown`/`mouseDragged`/`mouseUp`. The same view class, standalone in Classic and Original, moves
its window from anywhere in its body — `SpectrumView:365`, `PeppyMeterView:197`. Hosted, every press
in the body was swallowed, and because the surface is a plain AppKit subview of
`WinampModernMainView` the press never reached `shouldDragWindow` either: the whole skin-side drag
policy is bypassed by view mounting.

**What was left, measured across the 36 installed skins.** The frame's title strip, and nothing else:
corneramp_redux 15px, Anexa/Bio-Nid/Rika/T800 18px, cPro-Bento and micro 21px, Core-X5 and S7Reflex
24px, Nullsoft 2000 SP4 Lite 27px, Defix 42px, Big Bento 45px. A strip is a fixed height, so it is a
smaller share of the window the bigger the window: the hosted projectM window (550×580) measured
**6%** draggable on Nullsoft 2000, **4%** on corneramp, against 100% for the same content standalone.
PeppyMeter at 343×254: 13% on Nullsoft, 21% on Lobe, 30% on Defix.

**The fix.** `WinampModernHostedWindowDrag` — the app's own prime-then-move idiom
(`ModernLibraryBrowserView` drags a hidden-title-bar window the same way): primed at `mouseDown`,
becomes a drag after 3pt of travel, moves through `windowWillMove` so snapping and docking are
unchanged, and reports at `mouseUp` whether the press moved the window so the click it would
otherwise have performed is dropped. Wired into all eight surfaces inside their existing
`hostedContext != nil` branches, so Classic and Original are untouched — the rule in
`reference/components.md` → *A frame supplies chrome, not a drag surface*.

The travel threshold is what keeps these surfaces' own gestures: Spectrum's double-click still cycles
quality, Cava's and Flow's still toggle, projectM's still toggles performance mode. Two surfaces are
deliberately narrower than "the whole body": the equalizer drags from its margins only (its bands,
preamp and buttons claim their presses first), and the hosted waveform does not body-drag at all
because its `waveformRect` is the whole view and every press there seeks — its handle is the frame
strip, exactly as it is its own title bar standalone. Both are pinned by
`WinampModernHostedWindowDragTests`.

## B56 — Skin windows spawn on top of each other — closed 2026-08-28

### B56

Winamp Modern has no center stack — a `.wal` skin's windows are whatever shape and size the author
chose — so their arrangement is a **tiling**, generated in one deterministic sweep. It is not a
collision-avoider bolted onto per-window placement: four attempts at that were whack-a-mole, because
the inputs a per-window decision needs do not exist when it runs.

Two measurements settled the design, both on Defix:

- **Nothing decided during skin load can be right.** Containers are created and shown while the skin
  loads, before `WindowManager` reveals the player at its restored frame and before the standard
  frame's layout pass settles sizes. Every window was placed against a player at `{{0,695},{406,355}}`
  that finished at `{{0,677},{426,373}}`, and against its own size ~5% smaller than it ended up.
- **The skin's own `default_x`/`default_y` cannot be the answer.** Defix's put `pledit` at x 822–1228
  and the media library at x 1120–1920 — 108px of overlap before any NullPlayer window is counted.

- [x] **B56.1. `WindowManager.WinampModernTiler`.** Columns run down from the player, each window
      flush under the last; one that will not fit starts the next column right. Fixed order, no
      scoring, no iteration. The player is the anchor and never moves — its frame is restored state.
- [x] **B56.2. `arrangeWindows()` — the single sweep.** Lays out the skin's containers in declaration
      order, then the materialized hosted windows. Called from the `restoreSettingsState` completion
      in `AppDelegate`, the first moment the player's final frame and every final size are known.
- [x] **B56.3. `tiledOrigin(for:avoiding:)` — the open-later path.** Walks the same slot sequence and
      takes the first slot clear of what is on screen, so a window opened from the menu lands where
      the arrangement would have put it without disturbing anything already placed.
- [x] **B56.4. Lay the scene out before choosing a slot.** `setAuxiliaryWindow` forces
      `layoutSubtreeIfNeeded()` first. Placing before it picks a correct slot for a size the window is
      about to stop having — two menu-opened windows overlapped 153×174 under a tiling that cannot
      overlap.
- [x] **B56.5. Classic and Original untouched.** `positionSubWindow` keeps its stack scan verbatim;
      the tiling is an early return gated on `uiMode.controllerFamily == .winampModern`. An earlier
      cut argued a shared resolve was "a no-op" for those modes instead of gating it, and it was not —
      the screen clamp it carried moved Classic's sub-windows. See the rule now at the top of
      `SKILL.md`.
- [x] **B56.6. Verified in the running app** (2026-08-28, Defix, `WINAMP_MODERN_PLACE_TRACE=1`).
      Launch with 5 windows restored, then 2 more opened from the menu: all 7 frames disjoint,
      measured via the accessibility API rather than by eye. Before: the media library overlapped
      three windows on a plain launch.
- [x] **B56.7. Anaheim verified** by the user, 2026-08-28.
- [ ] **B56.8. Remaining checks.** A skin whose playlist is a classic fallback; a Classic regression
      pass (the mode gate should make it a formality); and the arrangement after a live UI-Size
      change, which resizes every window and is the one input the sweep does not re-run for — expect
      that to need the same treatment.

Shipped as a deterministic tiling (`WindowManager.WinampModernTiler`) rather than per-window
collision avoidance; the reasoning and the measurements that ruled the alternatives out are in
[`components.md`](../../skills/winamp-modern-skin-guide/reference/components.md) under "Where a
skin's windows go". Verified in the running app on Defix and Anaheim, 2026-08-28. Regression
coverage: `WinampModernWindowTilingTests` (8 cases; the property test caught a real overlap bug
in the right-edge clamp that the manual pass missed). Remaining verification is tracked as B56a
in [`TASKS.md`](../../TASKS.md).

---

## BB5 — Substitute `@HAVE_LIBRARY@` across markup — closed 2026-08-27

### BB5

- [x] **BB5. `@HAVE_LIBRARY@`** — carried over from B36's follow-up because it is not Bento-only.
      A second unresolved token, never used as a path so the VFS never sees it
      (`<script … param="@HAVE_LIBRARY@">` here; `default_visible="@HAVE_LIBRARY@"` on the
      media-library container in Styx, Shield_Amp, S7Reflex, Defix). Winamp substitutes `1`; doing so
      is a *behaviour* change — four skins would start opening a library window — and needs its own
      live QA. **If this is picked up, move it to `TASKS.md` first**: four of the five skins it
      affects are not Bento.

The earlier Defix repair substituted the macro only when binding a script parameter. BB5 moves the
rule to the expanded XML document, after include expansion and before inventory, synthesis and
initialization, so non-path attributes see the same host capability. Unknown macros remain literal.
Manual QA was accepted on 2026-08-27. Regression coverage:
`WinampModernPhase25RegressionTests.testTheLibraryMacroIsExpandedBeforeContainerTopology`.

Reach command: `rg -i -o '@HAVE_LIBRARY@' "$corpus"` — 6 uses across 6 skins.

---

## B17 — Preserve groupdef redefinition order in the surface inventory — closed 2026-08-27

### B17

- [x] **B17. `WasabiSurfaceInventory`'s last-wins groupdef map.** The redefined-id defect fixed in
      Phase 19, one layer up. No measured skin is affected — it changes nothing for T800 — so this is
      a correctness tidy-up, not a fix

The inventory now retains every definition of a group id in expanded-document order and resolves a
reference to the version in force where that reference occurs, including the initializer's lenient
first-definition fallback for forward references. Template traversal carries the outer instance's
position, while `inherit_group` and `embed_xui` edges resolve at the definition's own position. This
keeps pre-graph surface classification aligned with the live graph and prevents a later group body
from changing an earlier container's embedded/declared/synthesis decision.

Manual no-regression QA was accepted on Big Bento Modern on 2026-08-27. Regression coverage:
`WinampModernPhase13Tests.testInventoryUsesTheGroupDefinitionInForceAtEachReference`.

Reach command: `rg -i -o '<groupdef[^>]*[[:space:]]id="[^"]+"' "$corpus" --glob '*.xml'`;
normalize ids case-insensitively per skin and retain ids declared more than once.

---

## B15 — Render `wasabi.panel` / `wasabi.objectframe.group` bodies — closed 2026-08-27

### B15

- [x] **B15. `wasabi.panel` / `wasabi.objectframe.group` bodies.** Every measured use is inside a
      `modal`/`static` frame that synthesis never selects, so there is still nothing on screen to fix.
      Wait for a skin that shows one

The 36-skin sweep superseded that old reachability note. The original 192 textual matches across 19
skins include conventional bitmap declarations; after comments and resources are excluded, eight
skins contain 19 group instances or inheritance edges. Ebonite 2.1 directly displays object frames
around its RGB Color Changer swatches, palette, and checkbox controls, and BLAKK uses one in its
default-visible Configure window.

Both standard-library shells now contribute a tiled nine-slice `<grid>` that names only the skin's
own conventional artwork: `wasabi.panel.*` with `wasabi.panel.tint` in the middle, and
`wasabi.objectframe.*` with `wasabi.objectframe.center`. Missing artwork still degrades to an empty
grid, and a skin-supplied groupdef continues to win over the shell. Manual QA on Ebonite 2.1 was
accepted 2026-08-27.

Reach command: `rg -i -o 'wasabi\.(panel|objectframe\.group)' "$corpus" --glob '*.xml'`.

---

## BB10 — Typed Skin Settings fallback widgets — closed 2026-08-27

### BB10

- [x] **BB10. The gear (host **Skin Settings**) window renders two widget kinds, and hides some
      settings entirely.** Reported by the user as *"most items in the gear settings menu don't work
      or are blank."*
      `Windows/WinampModern/WinampModernSkinSettingsWindowController.swift` (208 lines) builds its
      list from `runtime.presentableSettings` and renders a checkbox when the current value is
      exactly `"0"` or `"1"` (`isToggle`, line 29) and otherwise a bare `NSTextField` (line 126).
      There is no enum, slider, range or colour widget, because `RegisteredSetting` carries no type
      metadata — only section, name and default. Separately, `presentableSettings` filters out every
      setting whose *current value* looks like a GUID (`namesAnItem`), which is right for Winamp's
      config-tree navigation nodes and also hides any legitimately GUID-valued option.
      Decide in this order: **(a)** does this window stay a *fallback* for options no skin control
      binds, once BB7 makes the skin's own nine pages work? It and `config.xml` read and write the
      same store, so BB7 may make it largely redundant for this family and the answer changes how
      much (b) is worth. **(b)** extend `RegisteredSetting` with type/range metadata so an enum is a
      popup and a bounded int is a slider. **(c)** revisit the GUID filter.
      Start by dumping what this skin actually registers: `WINAMP_MODERN_RENDER_SETTINGS=1`.

Closed without an engine change after live review: the skin's own settings pages already expose the
items and all of them work. The proposed duplicate host controls no longer describe an open defect.

---

## B25 — Remove the startup `autoopen` fallback — closed 2026-08-27

### B25 — The startup `autoopen` fallback forces a tab open behind the skin's back

`WinampModernMainWindowController.revealEmbeddedSurface` falls back to `openHolders`, which walks up
from an `autoopen="1"` holder writing `visible="1"` onto every hidden ancestor. At launch on
cPro-Bento this fires for the library (`WinampModern reveal library … opened=1`): the SUI's own tab
bookkeeping never learns that tab was opened, because the app opened it directly on the graph.

It exists because ClassicPro's `onGetCancelComponent` no-ops at startup (`active_tab` is already 0
while `centro.library` has never been shown). **With the MAKI `NULL` coercion fix in place that no
longer holds:** run with the fallback disabled and cPro-Bento's library tab renders correctly at
startup on its own. So the workaround now looks obsolete for this skin while still desynchronising
the skin's state.

- [x] Measure which corpus skins actually depend on `openHolders` (B23's video reveal is one caller;
      the Skin Windows menu and a script's `TOGGLE guid:…` are others). The 36-skin corpus contains
      99 declarations across 25 skins, but most are bodies of declared component windows. Static
      presence is not evidence that the launch-only embedded-library route needs graph forcing.
- [x] Decide: preserve the already-reversible fallback for explicit menu, script-toggle, and video
      requests; suppress it only for the advisory startup library reveal.
- [x] Verify the startup library tab, the video tab reveal, and the Skin Windows menu on cPro-Bento
      and on a skin with a declared container. Accepted live 2026-08-27.

The surface coordinator now carries the fallback policy into the one embedded reveal route. Its
focused test pins `true` for explicit show/toggle requests and `false` for startup. cPro-Bento's
per-skin notes record why the repaired `NULL` coercion made the launch workaround obsolete.

Reach command: `rg -i -o 'autoopen[[:space:]]*=' "$corpus" --glob '*.xml'`.

---

## B32 — `cfgattrib` toggles show no state, and crossfade drives nothing — closed 2026-08-23

## B32 — `cfgattrib` toggles show no state, and crossfade drives nothing

mmd3's Crossfade / Shuffle / Repeat buttons are `cfgattrib`-bound togglebuttons whose *only* on-screen
indication is a pair of `ghost="1"` layers (`*Led`, `*Dis`) whose alpha `playertools.m` sets from
`getActivated()` and from `<toggle>.onActivate(int)`. Probe (`RENDER_PROBE=main/normal`): all three
buttons `activated=0`, all six indicator layers `alpha=0`, script ran clean (`failed=-`). Two root
causes, both engine-wide:

1. `getActivated()` reads `attributes["activated"]`, which `toggleConfigAttribute` deliberately never
   writes — so a config-bound button always reports off.
2. `onActivate` is dispatched from nowhere in the engine, so no skin's activation indicator can move.

And shuffle/repeat are stored **twice** (the config attribute, plus `host.shuffleEnabled` toggled by an
`xmlID`-matching special case in `performAction`), so the two drift the moment either side changes.

Corpus demand (30 installed skins): `{45F3F7C1…};Repeat` ×52, `;Shuffle` ×50,
`{FC3EAF78…};Enable crossfading` ×32, `{F1239F09…};Crossfade time` ×12. 8 skins reference `onActivate`.

- [x] **B32.1 `WinampModernConfigBridge`** — table of well-known `{GUID};Key` attributes that are
      *host state*, not skin-private storage: Shuffle, Repeat, Enable crossfading, Crossfade time.
      Read/write through the host; everything else keeps hitting `WinampModernConfiguration`.
- [x] **B32.2 Host crossfade surface** — `crossfadeEnabled` / `crossfadeSeconds` on
      `WinampModernHost`, backed by `AudioEngine.sweetFadeEnabled` / `sweetFadeDuration`, with
      inert defaults in the protocol extension for the harness/test hosts.
- [x] **B32.3 Route reads through the bridge** — `configValue(of:)`, `getcurcfgval`, and
      `getActivated()` on a config-bound object all answer the bridged value.
- [x] **B32.4 Route writes through the bridge** — `setConfigAttribute` writes host state for a
      bridged key, and still notifies `onDataChanged` exactly once.
- [x] **B32.5 Dispatch `onActivate`** — on a real change of activation, from `toggleActivation`,
      `setactivated`, and `toggleConfigAttribute` (to *every* object bound to that attribute, since
      mmd3 declares the same button in `normal`, `shade` and `shade2`).
- [x] **B32.6 Drop the `xmlID` shuffle/repeat special case** in `WinampModernMainView.performAction`
      — with B32.1 in place it double-toggles.
- [x] **B32.7 `cfgattrib` sliders** — a slider bound to an attribute (mmd3 `sCrossfade`, `high="20"`)
      must read its thumb from the value and write the value on a drag, in its own `low…high` unit
      rather than 0…255, so `onSetPosition` hands the skin the seconds it prints.
- [x] **B32.8 Verify** — `RENDER_CLICK` + `CALL_TRACE` on all three buttons: `setalpha(255.0)` on the
      indicator layers, `CLICK chain: … -> skin.xml.onactivate`. 1004 tests green, golden images
      green, 30-skin render sweep green (multipass improved degraded→full). Live on mmd3 via
      `WINAMP_MODERN_DEBUG_CLICK`: SHUFFLE/REPEAT lamps + words light, CROSSFADE lights and logs
      `AudioEngine: Sweet Fades enabled`.
- [x] **B32.10 The other direction.** Nothing observes `audioPlaybackOptionsChanged`, so shuffle
      toggled from NullPlayer's own menu moves the host and leaves the skin's lamp stale — the very
      drift the bridge exists to remove. Re-dispatch `onActivate` (and `onSetPosition` for a bound
      slider) for a bridged attribute whose value moved from outside the skin.
- [x] **B32.9 Land the findings** — `reference/rendering.md` (two new sections: the host-owned
      attributes, and `onActivate`), `compatibility/maki-surface.md` (`onActivate` row),
      `SKILL.md` (two routing rows, two section-map rows, file-map row), `skins.md` (mmd3 row —
      mmd3 has no `skins/mmd3.md` yet, so the summary table is where this landed), `CHANGELOG`.

Deferred, not in scope: `{280876CF…};Always on top` (×9) could bridge to
`WindowManager.isAlwaysOnTop` the same way; `{0000000A…};Random` (×15) is AVS preset randomisation,
correctly skin-private.

---

## B50 — Text Size: fix the Defix leak, align the library, add a per-skin control — closed 2026-08-26

## B50 — Text Size: fix the Defix leak, align the library, add a per-skin control

Plan: `~/.claude/plans/implement-claude-plans-there-is-a-proble-glittery-popcorn.md`

`b2980d3a` made the embedded playlist follow the skin's **median declared `fontsize`**. That reads
right on Big Bento Modern (1536×878) and wrong on Defix Hi-END 200, whose `fontsize="19"/"20"`
playlist pane lands on the same 18px cell inside a 406×355 window. And the embedded Media Library
never learned about the new metric at all, so it reads small beside the playlist. One **Text Size**
control per skin drives both, defaulting to an Auto rule keyed on **window size**, not on fonts:

```
auto cell (px) = clamp(canvasHeight / 48, 11, 18)
explicit cell  = 11 * percent / 100          // 100…200%, no 18px cap on an explicit choice
content scale  = cell / 11
```

- [x] **B50.1** New `WinampModern/WinampModernTextScale.swift` — `enum WinampModernTextScale`
      (`auto = 0`, `p100`…`p200`) with `menuTitle`, `cellPixelHeight(canvasHeight:)`,
      `contentScale(canvasHeight:)`, and the auto rule + its two constants documented
- [x] **B50.2** `WasabiTextMetrics` — delete `bodyPixelHeight(near:)` and
      `declaredTextPixelHeights(in:)`; move `maximumBodyPixelHeight` into the new type as the auto cap
- [x] **B50.3** `WasabiRenderer` — `var textScale`; `playlistTextPixelHeight(in:)` becomes
      arithmetic on `canvasSize.height`; drop the `playlistTextPixelHeights` cache. Keep the `holder`
      parameter so the render-dump probe keeps its signature
- [x] **B50.4** `WinampModernSkinState` — fourth entry: section `@nullplayer.text`, key `size`,
      raw percent (`0` = auto), `textScale(in:)` / `setTextScale(_:in:)`; update the doc table
- [x] **B50.5** Library scale — `WinampModernLibrarySurface.applySkinScale` →
      `applyContentScale(_:)` (library protocol only); the surface view stores the pushed value and
      returns it from the `skinScale` closure it hands `PlexBrowserView`; rename
      `WinampModernComponentBridge.skinScaleProvider` to match
- [x] **B50.6** `WinampModernMainView` — one `libraryContentScale` helper, pushed to **all** live
      library surfaces from the `skinScale` observer, `reconcileHostedSurfaces()`,
      `applyCanvasResize` and `activateLayout` (Auto depends on canvas height, so a resize must
      re-push or the library keeps a stale scale)
- [x] **B50.7** Menu — `Text Size` submenu in the Winamp Modern block of `buildUIMenu()`, built like
      `buildUISizeMenuItem`, `Auto (n%)` first; `MenuActions.setWinampModernTextScale(_:)` and the
      `WindowManager` getter/setter pair, guarded at all three layers
- [x] **B50.8** `WinampModernMainWindowController.setTextScale(_:)` — write skin state, set
      `textScale` on the main and **every auxiliary** renderer, repaint, re-push the library scale;
      seed `textScale` at both renderer construction sites; `textScale` / `resolvedTextPercent`
      getters for the menu
- [x] **B50.9** Tests — auto at canvas heights 355 → 11px and 878 → 18px, explicit 200% beating the
      auto cap, skin state round-trip; update `WinampModernRenderDumpTests.swift:1121-1136`
- [x] **B50.10** Docs — `reference/components.md` (window-size rule + the control),
      `skins/big-bento-modern.md`, `skins/defix-hi-end-200.md`, and `reference/harness.md` (whose
      measured-values sentence is stale today: it claims Big Bento `text=22`, which the 18px clamp
      already prevents)
- [x] **B50.11** Verify — **manual QA passed 2026-08-26.** 1263 tests green (12 new in
      `WinampModernPhase71Tests`). Render-dump measured on Auto: Big Bento `main/normal` **18** and
      its own `main/shade` **11** (same skin, two layouts — the rule follows the canvas), Defix
      `pledit` **11**, cPro-Bento / mmd3 / micro / stock Winamp Modern **11**. micro moved 13 → 11,
      which is the intended correction
- [x] **B50.12** Menu ordering (asked for after QA) — the ClassicPro engine leads, as the
      dependency a cPro skin needs before it can run; then Import .wal Skin and Open Skins Folder,
      which are two halves of the same thing rather than one of them stranded at the bottom of the
      menu; then the per-skin group
      — **Text Size**, Color Themes, Skin Settings, Skin Windows — built as a list so its separator
      brackets what was actually added rather than being written inline per conditional block. Text
      Size sits with the skin's own settings rather than with the imports because it is stored per
      skin and changes meaning when the skin does; it is the only unconditional entry in that group,
      the other three depending on the skin declaring one. **The UI menu's four families were also
      reordered** to Classic → Modern → Original → Original-Metal: `buildUIMenu` builds them in
      source order, so the two Original families are held in a `deferredFamilies` list and added
      after the `.wal` block rather than inline. The separator that fenced the `.wal` family off is
      gone — the four are peers

---

## B51 — The `<vis>` oscilloscope draws real PCM, and every `<vis>` attribute is read — closed 2026-08-26

- [x] **B51. The `<vis>` oscilloscope draws real PCM, and every `<vis>` attribute is read.** Done
      2026-08-26, confirmed live ("looks great"). Built the `WasabiVisRenderer` seam B53 now extends,
      the 576-sample waveform tap, the per-second falloff model and the vis box's own 30/60 Hz clock.
      Detail: `reference/rendering.md` → *The oscilloscope reads PCM*, `reference/performance.md` →
      *The visualization has a clock of its own*, and git history

- [x] **B51.1** **Done — measured 0…4.** Settle the numeric range of `falloff`/`peakfalloff` before hardcoding the map —
      `WINAMP_MODERN_RENDER_DISASM=@visualizer` against Big Bento Modern (the plan assumes 0…4 from
      the five menu entries; the values are written by MAKI, not declared in XML)
- [x] **B51.2** **Done.** New `WinampModern/WinampModernWaveformTap.swift` — 576-sample `UInt8` tap modelled on
      `WinampModernLevelMeter`: `queue: nil` observer, copy-under-lock only on the audio thread, and
      a read that decays to flat 128 past `silenceTimeout`. The silence *nudge* moved to the level
      meter — see B51.6
- [x] **B51.3** **Done.** `WinampModernHost`: `waveformSamples` + `setWaveformNeeded(_:)`, backed in
      `WinampModernAudioEngineHost` by a lazy tap beside `levelMeter`, stopped in
      `endVisualizationConsumption`
- [x] **B51.4** **Done.** New `WinampModern/WasabiVisPainter.swift` — `WasabiVisStyle` / `WasabiVisInput` /
      `WasabiVisRenderer`, plus `WasabiBuiltInVisRenderer`: real-PCM scope (left channel, one column
      per pixel), `oscstyle` solid/dots/lines, `colorosc1`…`colorosc5` banded by excursion, `peaks`,
      `coloring` normal/fire/line, and **per-second** bar/peak decay from `falloff`/`peakfalloff`
- [x] **B51.5** **Done.** `WasabiRenderer`: `drawVisualization` decodes the style and delegates; the
      `spectrumLevels` guard moves into the analyzer branch; peak/bar state moves to the renderer;
      cached `needsWaveform` pushed to the host only on change. **Deviation from the plan worth
      recording:** `setVisualizationAttribute` is *not* the only route a `mode` write takes — MAKI's
      `setmode` and `setxmlparam` write the attribute directly, so the cache is keyed on the graph's
      `mutationGeneration` (the same key `sceneNodes()` already uses) rather than on that one setter
- [x] **B51.6** **Done, and it is the second deviation.** The plan put the silence nudge on the
      waveform tap and made it *one* `DispatchQueue.main.async` per transition. Two things are wrong
      with that, and both had to change: (a) one repaint cannot show a *decay* — the bars and caps
      need frames while they fall — and (b) `spectrumLevels` is not cleared on pause, so a repaint
      redraws the same bars forever; the levels have to read silence. And the waveform tap is gated
      on a skin declaring a scope, so an analyzer-only skin would never get a nudge at all, while
      casting never changes `playbackState`. So the transition is reported by
      **`WinampModernLevelMeter.onSilence`** — the one tap that runs for every `.wal` skin, watched by
      a 4 Hz `DispatchSourceTimer` on a private queue, one callback per transition, cleared on the
      next buffer — and `WinampModernMainView.beginVisualizationSilenceDecay` zeroes the levels and
      invalidates the vis rects at the same 60 Hz until `renderer.hasDecayingVisualizationState` says
      nothing is left above the floor (4 s backstop). The controller fans it out to every container's
      view. The audio thread is still not in this path anywhere
- [x] **B51.7** **Done.** `WinampModernHostActionMenus`: Oscilloscope Style, Show Peaks, Analyzer Coloring,
      Analyzer Falloff Speed, Peak Falloff Speed — all through `setVisualizationAttribute`
- [x] **B51.9 — smoothness, without touching the signal.** Pass 1 looked right and moved in steps.
      Two causes, both measured, neither one a case for smoothing the data (explicitly *not* wanted —
      no levelling, no RMS, no interpolation): (a) the boxes repainted only on a spectrum
      notification, and `AudioEngine` taps `mixerNode` with a **2048-frame buffer**, so that is one
      notification per ~46 ms — everything in a `<vis>` moved at **21 fps**; (b) the waveform posts a
      576-sample chunk at a time from inside that single tap call, **three or four in a burst**, and
      the tap kept only the newest — three quarters of the audio discarded, survivors 46 ms apart.
      Fixes: `WinampModernWaveformTap` now **queues** chunks (cap 6 ≈ 78 ms, then drop-oldest and
      resync) and plays them out against the clock at the exact 576/sampleRate rate they were
      recorded at; `WinampModernMainView` gains a **60 Hz visualization clock** that invalidates only
      the vis rects, runs only while there is something to show, and stops itself once the falloff
      has finished. The frame's waveform is sampled **once per frame** in `WasabiRenderer.draw` so
      Big Bento's six boxes cannot straddle a chunk boundary and mirror each other a chunk apart
- [x] **B51.10 — what the clock costs, measured, and the rate that follows from it.** `sample` on the
      running app (Big Bento, vis visible, playing): a vis-rect repaint is **~4 ms**, so 60 Hz is
      ~24% of a core against ~8% at the old 21 fps — **+15 points**. (The 14% in
      `WinampModernMainView.layout()` in the same trace is *not* the clock: `needsLayout` is set on
      graph mutations by the skin's own scripts, `:390`/`:414`. Left alone.) So the clock now runs at
      the rate the content actually changes: **60 Hz only when a `mode="2"` box is on screen** — new
      PCM every 13 ms, and below 60 the trace steps — and **30 Hz otherwise**, because an analyzer's
      bands only move at the FFT's ~21 Hz and frames past 30 animate nothing but falloff between two
      identical sets of bars. It also **skips repaints while the window is occluded** (the timer
      keeps running at ~0.5% so the idle check still retires it) and still stops entirely once the
      falloff is done. Analyzer-only skins — most of the corpus — end up ~4 points over the old
      behaviour rather than 15. A regression the suite caught while doing this: dropping the
      immediate paint from `startVisualizationClock` cost up to 33 ms of hesitation when audio
      started (`WinampModernPhase24Tests.testDeliveringSpectrumLevelsMarksTheViewForRedraw`)
- [x] **B51.8 — confirmed live by the user 2026-08-26** ("looks great"), then smoothness (B51.9) and
      the clock rates (B51.10) on top of it. Tests, skill updates and the changelog followed the QA,
      per the verify-before-investing rule: `WinampModernPhase73Tests` (18 tests — attribute decode
      including the measured 0…4 falloff, the colour steps, the tap's queue/playout/silence, the
      demand gating, and the moved spectrum guard: a scope paints with no spectrum, an analyzer does
      not), 1288 total pass. **The tests caught a real off-by-one**: the playout showed every chunk
      one slot late and skipped the first chunk after silence, because `playoutStart` was being
      treated as "the head becomes current one duration from now" rather than "now". Live QA
      (the plan's Verification section). Built clean; `swift test` 1270 pass.
      Static: `RENDER_DUMP` on stock Winamp Modern, Love is War Miku, Rika (`mode=1`) and mmd3
      (`mode=0` stays off) all render. **Big Bento's own four header boxes cannot be checked
      headlessly** — `main.vis.group` is hidden until the player pane passes 730px and the harness
      cannot drag the divider, so `VIS box` prints nothing for it; that is verification step 1's job

</details>

---

## B52 — A cache nobody trusted: discarded scenes and repeated layout work — closed 2026-08-26

- [x] **B52. A cache nobody trusted: ~460 discarded scenes a second.** Done 2026-08-26, confirmed
      live. Found while measuring B51's clock, not caused by it: `invalidateRectCaches()` threw the
      memoized scene away by hand on every notification, and `tickTargetAnimation` notified on every
      fade tick. `layout()` 9.9% → 1.3% of the main thread. Detail: `reference/performance.md` → *A
      cache nobody trusted*, the `MUTATION_TRACE` row in `reference/harness.md`, and git history

<details>
<summary>B51's task list, kept for the deviations it records</summary>

- [x] **B52. Done 2026-08-26, confirmed live. The counter was the smaller half: the caches were
      being thrown away by hand, ~460 times a second.** Found while measuring B51's repaint clock, not caused by it —
      `sample` on the live app (Big Bento Modern, playing, scope visible, 3744 main-thread samples
      over 5 s): `WinampModernMainView.layout()` is **369 samples (~10% of a core)**, of which
      **345 are `browserNodes()` → `layoutNodes()` → `append`** — a full recursive re-solve of the
      object tree *including hidden nodes*. `layoutNodes()` is memoized against
      `graph.mutationGeneration` + canvas (`WasabiRenderer.swift:930`), so missing that consistently
      means the counter is moving almost every frame. The same counter keys `sceneNodes()`, so the
      scene walk is being redone as well: `renderer.draw` is another 602 samples (~16%), while the
      thing it is drawing — `WasabiBuiltInVisRenderer.drawOscilloscope` — is **7**.
      **The visualization is not the cost; the cache misses are.** Find the writer (a ticker offset,
      a clock, an animation attribute — `WINAMP_MODERN_TRACE_MAKI=1` / `CALL_TRACE` against the
      running player will name it), and either stop it writing an attribute per frame or key the two
      caches on something a cosmetic write does not move. Fixing it speeds up the whole skin, not
      just the `<vis>`. Pre-existing: it was happening at the old ~21 fps too
  - **The writer, named 2026-08-26:** `tickTargetAnimation` (`WinampModernScriptRuntime.swift`) runs
        at **60 Hz per animating object** and calls `notifyGraphDidMutate()` on **every tick** —
        whether or not the tick changed an attribute — which is a full-window `needsLayout` +
        `needsDisplay` and a layout/scene cache miss for a *fade*. Big Bento Modern's InfoDisplay
        rotates its 17 `Bento:InfoLine` rows with a target-alpha fade that never stops while a track
        is loaded, so the skin is in that state permanently. `MUTATION-TRACE` on the running player
        (playing, 12 s): ~8/s of real writes, all `alpha`/`targeta`/`goingtotarget` on
        `infodisplay.line.*` — and 60/s of invalidation on top of them that no probe could see
  - [x] **B52.1** Add a mutation probe — `WINAMP_MODERN_MUTATION_TRACE=1` — that attributes every
        `mutationGeneration` bump to the writer (attribute, object type/id, source) and prints the
        top writers per interval. Instrument before reasoning; prove it prints on a skin that idles
  - [x] **B52.2** Run Big Bento Modern in the app, playing, scope visible, and name the writer(s)
  - [x] **B52.3** Stop the per-frame write at its source: `tickTargetAnimation` now notifies only
        when a tick actually moved an attribute, and an alpha-only tick takes the object-targeted
        repaint seam (`requestRepaint(for:)`) rather than a whole-window relayout
  - [x] **B52.3a** The bigger half, found by the probe: `invalidateRectCaches()` in
        `WinampModernMainView` dropped the renderer's memoized scene on *every* notification, times
        every container window it fans out to — **~460 drops/second** measured. The scene cache is
        keyed on the graph's own generation, so that drop was pure waste. Removed; the genuine
        non-graph inputs (layout switch, resize, theme, playback state, UI Size) keep explicit calls
  - [x] **B52.4** Key the layout/scene caches on a generation a cosmetic write does not move:
        `sceneGeneration` skips `alpha` alone, and `sceneNodes()` re-resolves the inherited product
        over the cached nodes (`withRefreshedAlpha`), the way `withRefreshedBitmapID` already did for
        host-resolved artwork. It was reverted mid-QA on suspicion of the white analyzer flashes and
        **exonerated** — the flashes reproduce on a clean baseline (now B54)
  - [x] **B52.5** The object-targeted repaint seam now covers an object's whole **subtree**
        (`WasabiSceneRenderer.paintedBounds`), because `alpha` is inherited and only a sized group
        clips — repainting a faded group's own rect alone would leave a child hanging outside it
        half-faded
  - [x] **B52.6a** Measured, **analyzer** mode (not the ticket's scope — `drawOscilloscope` was 0
        samples in both runs, so this is like-for-like but not B52's stated condition):
        `layout()` 349 samples (7.9%) -> 69 (1.5%), `browserNodes`->`layoutNodes` 308 (7.0%) -> 61
        (1.3%), main-thread idle 33% -> 62%. `renderer.draw` unchanged (~19%) — that is B51's vis
        clock, not a cache miss
  - [x] **B52.6b** Re-measured in **scope** mode (the ticket's condition; `drawOscilloscope`
        non-zero is the check that it was not the analyzer): `layout()` 9.9% -> **1.3%** of the main
        thread, its `layoutNodes()` -> `append` re-solve 9.2% -> **0.9%**. `renderer.draw` is
        untouched and is now the largest cost in the window — B51's vis clock, not a cache miss
  - [x] **B52.7** Confirmed live by the user 2026-08-26 ("looks fine", scope mode, Big Bento
        Modern playing). `WinampModernPhase74Tests` (7 tests: the generation split, a parent's fade
        reaching its children through a cache that was never rebuilt, the product of two fades, and
        the painted-bounds rule both ways), 1295 total pass. Docs: `reference/performance.md` -> *A
        cache nobody trusted*, the `MUTATION_TRACE` row and the `DEBUG_PLAY` audio note in
        `reference/harness.md`, changelog under Unreleased -> Bug Fixes

</details>

These three came out of the Big Bento Modern header/settings research on 2026-08-23
(plan: `~/.claude/plans/abundant-pondering-hamster.md`) and are **here rather than in
`BENTO_TASKS.md` because none of them is Bento-specific** — Bento is only where they were found.
The Bento-only findings from the same pass are `BB6`–`BB15` there.

---

## B53 — Cava and vis_classic in a skin's `<vis>` box — closed 2026-08-26

### Recently closed — B53

**B53 — NullPlayer's own visualizations, selectable in a skin's `<vis>` box.** Pass 2 of
`~/.claude/plans/i-dont-think-the-velvet-wreath.md`, **narrowed by the user 2026-08-26 to the `<vis>`
box alone** — the spectrum/oscilloscope area the skin draws in its own window. The `{0000000A}`
plugin holder is **not** in scope: it already hosts ProjectM/Geiss/Tripex (B20a), and nothing here
replaces or adds to that. So `VisualizationType` does not widen and no NSView surface is involved;
every engine here is a `WasabiVisRenderer` painting into the scene's `CGContext`, which is the seam
B51 built.

Done 2026-08-26, confirmed live. File names below are as first written; the type was
renamed to `WinampModernSpectrumAnalyzer` during QA, because *visualization engine* already means
ProjectM/Geiss/Tripex in this app and these are spectrum analyzers.

- [x] **B53.1 The selection, and where it lives.** `WinampModern/WinampModernSpectrumAnalyzer.swift` — the
      engine choice (skin / Cava / vis_classic) and a skin-wide holder for it on `WasabiSkinRuntime`,
      beside `componentBucket`: Big Bento draws its `<vis>` in six boxes across several containers
      and they must not disagree about what is drawing. Persisted per skin through
      `WinampModernSkinState` (new section `@nullplayer.vis`), so the skin's own declared mode stays
      the default until the user picks something else
- [x] **B53.2 `CavaVisRenderer`.** New AppKit-side file. Owns a `CavaPresenter` on a **new**
      `CavaSettings.Scope` (its own keys — an embedding must not contaminate the Cava window's
      settings). Two things the plan got wrong and the code confirms: `CavaDrawing.draw` paints with
      `NSColor`/`NSBezierPath`, so the renderer has to push an `NSGraphicsContext` around the scene's
      `CGContext`; and the bars have to follow the box's own `colorband*` while the user has not
      customised Cava's colours, or a dark skin gets a lime-green analyzer
- [x] **B53.3 `VisClassicVisRenderer`.** New `VisClassicBridge.PreferenceScope` case with scoped keys
      (CLAUDE.md: vis_classic state is window-scoped and must not share keys). Fed by the **existing**
      576-sample waveform tap from B51 — it answers `needsWaveform` true, so no second audio tap —
      through `processAndDraw` into an RGBA buffer, wrapped as a `CGImage` and drawn into the box
- [x] **B53.4 `WasabiRenderer` plumbing.** `visRenderer` becomes whichever engine is selected;
      `setVisualizationSuite(_:)` persists it, discards the outgoing engine's state and re-runs
      `refreshWaveformDemand` — whose cache is keyed on the graph's generation and therefore has to be
      invalidated by a suite change too, which no graph write moves. `mode="0"` stays off whatever is
      selected
- [x] **B53.5 The menu.** "Visualization Engine" in `VIS_MENU` / `VIS_CFG`, with the active engine's
      own options under it — Cava's real menu (`CavaPresenter.buildMenu`), vis_classic's profile list.
      Winamp's own attribute items grey out while a non-skin engine draws, on B51's standing rule that
      a menu item which changes nothing on screen is worse than no item
- [x] **B53.6 Reachability.** Big Bento traps right-click on its vis with `main.vis.trigger`, so the
      box's own menu is not a guaranteed route: also put the picker in the Winamp Modern block of
      `buildUIMenu()` beside Text Size (B50.7's shape), and pop the box menu on a right-click over a
      `<vis>` no script has claimed
- [x] **B53.7 Lifecycle.** The Cava tap and the vis_classic core start on the selected engine's first
      draw and stop on a suite change, a skin change and UI teardown (beside
      `endVisualizationConsumption`). An engine nobody selected costs nothing — the B51 gating rule
- [x] **B53.8 Verify — confirmed live by the user 2026-08-26 ("nailed it").** The QA loop found four
      things no headless probe could, and each is recorded where it will be looked for:
      **(a)** un-mirroring left *two copies* of the analyzer, because Big Bento cuts its box in two —
      a suite engine is now handed the run's rect and clipped per box (`visualizationRows`);
      **(b)** the picker was unreachable on the flagship skin, which claims the right button over its
      own visualization — the section is inserted into the skin's own popup, which is ours to build;
      **(c)** picking an engine appeared to do nothing: our rows leave MAKI's command id at `0`, and a
      submenu parent carries `0` too, so the "user picked a skin mode" test matched every pick of ours
      and handed the box back four milliseconds later;
      **(d)** the three engines read at wildly different loudness, settled by eye as a calibration in
      `WasabiVisStyle.Gain` plus a per-engine **Sensitivity** control.
      Tests: `WinampModernPhase75Tests` (17 — persistence and its unknown-name fallback, the run
      geometry, the suppressed `fliph`, the gain/Sensitivity arithmetic including the oscilloscope's
      separate calibration, the input-gain clamp, and the command-id-zero rule). Docs:
      `reference/rendering.md` → *NullPlayer's own analyzers in a skin's `<vis>` box* (with the gain
      table and where to tune it), SKILL.md symptom + concept + file-map rows,
      `skins/big-bento-modern.md`, CHANGELOG under Unreleased → New Features.
      **Corpus sweep** (triage-playbook §6's pre-merge gate for a renderer change), 36 skins /
      310 images, before = `91b87814`, after = `5464bc9c`, clock pinned at 2s, xctest defaults domain
      reset before each half with nothing run in between, compared by **RGB** pixels:
      **275 identical, 35 changed** — and all 34 real ones are *inside a declared `<vis mode="1">`
      box*, checked against each dump's own `VIS box` geometry rather than by eye. That is the 0.8
      analyzer calibration and nothing else: no diff anywhere outside a visualization box, which is
      what the gate is for, since the flip and run-geometry changes are unreachable in the default
      state. The 35th is `Anexa/main-shade`, **confirmed nondeterministic here** — two runs of the
      *same* build differ at (53,35)-(70,63), the region the harness doc already records.
      Note the sweep can exercise **neither new engine**: no env var selects one and both need real
      audio, so their evidence is the live QA above plus `WinampModernPhase75Tests`

---

## B39 — A script's `setText()` must beat the object's `display=` binding — closed 2026-08-24

- [x] **B39. A script's `setText()` must beat the object's `display=` binding. Done 2026-08-24,
      confirmed live.** The override lives on `WasabiTextMetrics.scriptTextKey`, resolved in
      `content(of:host:)` after `setAlternateText` and before the binding; `setText` writes it
      alongside the XML `text` attribute, so a `<Wasabi:Button>` label still follows the script and a
      skin still cannot declare an override in markup. **The corpus sweep ran** (all 36 installed
      skins, XML `display=` objects cross-referenced against every `setText` receiver in the shipped
      `.m` sources): 13 skins affected, and it settled the one open design question — a non-empty
      override **does not expire** when the bound value moves, because micro's `oldtimer.m` and
      Ebonite's `clock.m` both hold a different clock format over a `display="time"` binding and an
      expiry would flicker them. Every non-reverting writer in the corpus rewrites on track change.
      Durable detail: `reference/scripting.md` → *What a text object shows*,
      `compatibility/maki-surface.md`, and the skin's own file. Tests:
      `WinampModernPhase64Tests`. The original report follows.
      Big Bento Modern
      draws the same song title on four stacked lines, and the skin's author documents the mechanism
      in the markup (`xml/player-normal-mcv.xml:378`):
      ```xml
      <!-- Victhor trick: display="SONGNAME" is used so ticker=1 actually works
           (the actual content of the text is set by script) -->
      <Text id="text" … display="SONGNAME" ticker="1" …/>
      ```
      That groupdef backs all **17** `Bento:InfoLine` objects (title, artist, album, track, year,
      genre, disc, albumartist, composer, publisher, format, comment, bpm, sname, surl, filepath,
      rating). Every one declares `display="SONGNAME"` **purely to enable tickering**, and
      `fileinfo.m` then fills each with `setText()` (~20 call sites).
      In our engine the two fight and the binding always wins:
      `WasabiTextMetrics.bound()` (`WasabiTextMetrics.swift:229`) answers `host.trackDisplayTitle`
      for `case "songname"` unconditionally, while `setText`
      (`WinampModernScriptRuntime.swift:2646`) writes `attributes["text"]` — which `bound()` reads
      **only in its `default:` branch**, i.e. only for an object with no `display=` at all. So all 17
      lines render the display title. **The layout is correct; only the content is wrong**, which is
      why it reads as "the title is repeated" rather than as a broken panel.
      The rule: a **non-empty** script `setText` overrides the `display=` binding; `setText("")`
      reverts to it. The revert half is not optional — MMD3's ticker fires `setText("")` a second
      after a `setAlternateText` and expects the bound title back (see the comment at `:2648`).
      Keep the override off the XML `text` attribute, the way `scriptAlternateTextKey` already does,
      so a skin cannot declare it in markup.
      **Sweep the corpus for every object carrying both a `display=` and a script `setText` before
      landing this** — it changes what any such object draws, in every skin, not just this one.

---

## B40 — A skin's web buttons reach the web — closed 2026-08-24

- [x] **B40. A skin's web buttons reach the web. Done 2026-08-24, confirmed live.** `navigateUrl`
      is the **user's** browser and `navigateUrlBrowser` the player's — not two spellings of one
      thing — and both are now typed rather than inert: every skin-authored address passes through
      `WinampModernWebNavigationPolicy` (HTTP/HTTPS with a real host, nothing else), the internal one
      reaches the scene's own `<browser>` (a visible one preferred over one in a closed tab), and the
      external one is gated by a first-use sheet naming the URL, remembered per skin, one question at
      a time, never `runModal`.
      **The skin's setting did not need reading.** Bento's Web Content page (`Use Default Browser to
      open links`, its own default `1`) is read by the skin's *own* script, which then calls
      `navigateUrl` on one branch and `sendAction` on the other — so honouring the setting **is**
      answering both routes. Same for the engine: `Default Search Engine: Google`/`Bing` is the
      skin's registration, and `preferredSearchEngine` reads it (DuckDuckGo when a skin names none,
      matching the internal browser's own start page).
      **Four faults sat on these buttons, and each alone was enough to make them look broken.** Only
      the first was the one this task named:
      1. `System.urlEncode` did not exist. It sits *inside* the expression that builds the address,
         so the unsupported method aborted the handler one layer before any navigation.
      2. `browser_search` carries **terms**, `browser_navigate` carries a **URL** — measured off the
         bytecode, not assumed. Read alike, a search becomes `https://<terms>`. Terms are decoded
         once before being re-encoded, since the skin encodes each term itself.
      3. A **scheme-less address is a web address**, not a skin-local path. Bento's reader writes
         `www.google.com/search?q=…` and hands it to `<browser>.navigateUrl`; `destination(for:)`
         found no scheme and looked for a hostname in the WAL VFS, where it can only ever be missing
         — *"The skin-local page could not be found"*, and nothing reached WebKit.
      4. **`getText`/`setText` did not follow `embed_xui`.** The search string is built from the
         *display lines*, not from metadata: `getText()` on the `Bento:InfoLine` wrapper, whose text
         lives on the inner `<Text id="text">` that `fileinfo.maki` fills. The wrapper answered `""`
         and the button searched for the bare word "lyrics" — a text bug wearing a browser bug's
         clothes, and the only one live QA could see. `getPosition`/`setPosition` had followed the
         link since BB19; the text methods never did.
      Also: a skin's own reader answers `browser_search`/`browser_navigate` itself, so the host route
      is a **fallback** taken only when no script handled the action — otherwise the same surface
      loads twice with a URL the skin did not choose. `ML_SendTo` is accepted and `.inert` with a
      reason (7 declarations: Bento ×2 per edition, Defix ×1); NullPlayer publishes no Send To
      targets.
      **Method note for the next reader:** the harness had already printed the answer
      (`navigateurl(www.google.com/search?q=  lyrics)`) one pass before it was believed — it was
      explained away as a synthetic-track artifact. *When a trace shows a handler running, what it is
      being handed is the finding.* Durable detail: `reference/components.md` → *The four routes a
      skin reaches the web by*, `reference/scripting.md` → *`embed_xui`*, `compatibility/maki-surface.md`,
      `skins/big-bento-modern.md`. Tests: `WinampModernPhase66Tests`.

---

## B42 — `relat*` is `atoi(value) != 0`, not `== 1` — closed 2026-08-24

- [x] **B42. `relat*` is `atoi(value) != 0`, not `== 1`. Done 2026-08-24, confirmed live
      2026-08-25** (in BB4's re-run: one crisp cover over a dimmed backdrop wash). `WasabiGeometry`'s flag
      reader accepted only `1`/`true`/`yes`, so every other number fell back to **absolute** geometry.
      Found live on Big Bento Modern, where it reads as *the album cover drawn twice*: the dimmed
      oversized backdrop in `info.component.albumbg` is `w="99" h="100" relatw="2" relath="2"`, and
      read as absolute it draws at a literal 99×100 — a small crisp second copy beside the real
      cover. Filed as BB6 against the album-art code; the cause was three layers away, in the
      geometry parser.
      Corpus: Big Bento Modern + its Windows 10 edition (1 declaration each, inherited by both Light
      overlays through the base's XML), Ebonite_2_1 (6), The_Nokia_5220 (2). corneramp_redux and
      Shield_Amp ship a literal `relatw="%"`, which `atoi` reads as 0 and which therefore stays
      absolute — unchanged.
      **A percentage reading is wrong**, though it fits Bento's `99`/`100` and Ebonite's `85`/`93`:
      Ebonite's own `group w="0" h="0" relatw="2"` would collapse to nothing at 0%, and `relatw="5"`
      is not a percentage. Landed in `reference/loading.md` → *Retained graph and coordinates*.
      `swift test` 1067 pass, 8 new in `WinampModernPhase56Tests`; corpus sweep pixel-diffed.

---

## B43 — `fliph` / `flipv` were ignored engine-wide — closed 2026-08-24

- [x] **B43. `fliph` / `flipv` were ignored engine-wide. Fixed 2026-08-24, confirmed live.**
      Neither attribute appeared anywhere in `Sources/`. Found live on Big Bento Modern, where the
      header analyzer group is a **butterfly**: `main.vis` (`fliph="1"`) and `main.vis2` sit side by
      side at 144px each so the two meet low-frequency-to-low-frequency in the middle, with
      `main.vis.mirror` / `main.vis.mirror2` (`flipv="1" alpha="110" ghost="1"`) as a dimmed 10px
      reflection under each. Ignored, that drew two identical copies with a seam and two reflections
      that were not reflected — reported as *"another bug is there are 2 of them"*, and the two **are**
      the skin's intent.
      Implemented at the one seam every kind of drawing passes through
      (`WasabiRenderer.draw(_ node:…)` → `applyFlip`), not in the bitmap path: the attribute belongs to
      the object, not to one way of filling it — the same lesson `alpha` taught in the two lines above
      it. Deliberately **after** both clips, so a flipped object cannot escape its box and a region
      mask stays where its author put it. `WasabiGeometrySpec.flag(_:)` was extracted from the
      initializer's closure so the flips read `"1"` exactly as `relat*` does (B42) rather than growing
      a second interpretation.
      Corpus: **all 16 declarations are on `<vis>`** and nothing else — Big Bento Modern + its Windows
      10 edition (4 each, inherited by both Light overlays), Styx (4, a 2×2 quad covering all four
      flip combinations — the strongest test case), multipass (2), Enkera (1),
      Nullsoft.Winamp.2000.SP4.Lite (1). So the general implementation costs no extra blast radius
      today, but a `<layer fliph="1">` is legal Wasabi and would have silently drawn unflipped.
      **Not verifiable headlessly:** Styx's quad is in a closed drawer, and Bento's group is gated
      behind `visualizer.maki`'s 730px player width — which `from="left"` pins at 434 at every window
      size (see B44), so no probe can reach either. Confirmed on screen by the user instead.
      `swift test` 1115 pass (11 new, `WinampModernPhase61Tests`), asserting the property that makes
      this safe: a flip is an **involution about the object's own frame**, so it cannot translate
      content out of its box.
      **Sweep: 290 images, 288 identical.** Anexa's `main-shade` is the known nondeterministic one.
      The other is a *correct* change and worth reading before it is mistaken for a regression:
      `Nullsoft.Winamp.2000.SP4.Lite`'s `xml/video.xml` declares the **same** `<vis id="shade.vis">`
      **twice** in the identical box — same colours, `mode="2" oscstyle="lines"` — with the second
      carrying `flipv="1"`. That is the classic Winamp mirrored scope, a trace and its reflection
      about the centre line. Ignoring the flag made the two coincide exactly, so it drew as one thin
      trace (mean vertical span 4.6px); mirrored, the pair spans 12.5px and reads as the intended
      symmetric double trace. Same idea as Bento's header, reached by a different route.
      **Method lesson, and it nearly cost a false regression:** this skin is an **NSIS** archive, not
      a zip, so the `unzip`-based corpus text scan skipped it silently — 35 skins in, 34 directories
      out — and it was the *one* skin the first scan claimed had no flip declarations while being the
      one image in the sweep that changed. A corpus scan that shells out to `unzip` under-reports; use
      `7zz`, and check the extracted directory count against the skin count. Landed in
      `reference/harness.md`.

---

## B44 — Skin-scoped persistence of skin config — closed 2026-08-24

- [x] **B44. Skin-scoped persistence of skin config — first slice done 2026-08-24, confirmed live.**
      The splitter position is the slice that landed; the item as filed is wider than it and the rest
      stays open (see the follow-up below). Nothing a `.wal` skin's own state amounted to survived a
      relaunch: every launch reseeds the graph from the markup and then re-runs the skin's own
      `setPosition`, so Big Bento's player/playlist divider dragged wide came back narrow.
      **The rule, and it is the whole design: only a drag is stored.** `persistFramePosition(of:)` is
      called from mouse-up and nowhere else. A script moving its own splitter is the *author's* layout
      speaking — Bento's `setPosition(434)` with `from="left"` genuinely ships "narrow player, wide
      playlist" and there is no clamping bug on our side — so that is left exactly as written. Not a
      `WasabiSkinQuirks` entry: that file's bar is *arithmetic the skin gets wrong, derivable from the
      skin's own numbers*, and this fails both halves.
      Stored in the skin's existing namespaced `WinampModernConfiguration` (the store behind
      `setPrivateInt`) under section `@frame`, keyed `container-id/frame-id` — the two names that
      survive a reload, where `stableID` is a per-load counter. `-1` is the "never dragged" sentinel
      because **`0` is a legal position** (ClassicPro closes its side view with `setPosition(0)`).
      Restored from `layoutNodes()` so a splitter in a shut drawer is not lost, and re-clamped against
      the box *as it is now*, since a negative `maxwidth` is measured from the far edge.
      **The ordering trap was the difficulty**, and it is the same one B38.2 hit: the skin's own
      `setPosition` runs at load, so a restore before it is simply stomped. Each view restores in
      `scriptsDidStart()` *before* the seeding resize dispatch, and the controller re-asserts once at
      1.0s for the case where the skin's call comes from a timer instead (Bento's `mcvcore` starts a
      700 ms one-shot, BB9). The re-assert **re-reads the store** rather than replaying, so a drag
      inside that first second is not pulled back.
      Rule: `reference/rendering.md` → *Where the user left the divider survives a relaunch — where the
      skin put it does not*. `swift test` 1125 pass (10 new, `WinampModernPhase62Tests`).

---

## B44a — The rest of skin-scoped persistence — closed 2026-08-24

- [x] **B44a. The rest of skin-scoped persistence. Measured and closed 2026-08-24 — the list is
      shorter than it looked.** The framing that settles it: **a skin's own preferences already
      survive**. `setPrivateInt`/`setPrivateString` and `cfgattrib` write straight into the same
      namespaced store, so anything a skin chose to remember about itself has always worked. Only what
      lives in the **object graph** needs saving, because that is what is rebuilt from the markup on
      every load — and that is a three-row table, now collected in `WinampModernSkinState`:

      | State | Section | Written when |
      |---|---|---|
      | A `<Wasabi:Frame>`'s divider offset | `@nullplayer.frames` | mouse-up on the divider (B44) |
      | Which layout a container is on (shade) | `@nullplayer.layouts` | a `SWITCH` the user clicked (new) |
      | Whether one of the skin's windows is open | `@nullplayer.windows` | a menu item, skin button or close box (already existed, Phase 40/B6) |

      Two candidates were **dropped after measuring**, and both were already done elsewhere: the
      active colour theme is persisted by `WasabiColorThemeList` under `appearance/theme`, and a
      window's frame on screen belongs to the *player's* window rather than to the skin, so it goes
      through `AppStateManager` with `clampRestoredFrame` (R1). A `<ColorThemes:List>` row selection is
      transient — applying it is what matters, and applying goes through the theme.
      **Two things actually changed.** *Layout persistence* is new: a window left shaded comes back
      shaded, restored right after `scripts.start()` so the skin's own `switchToLayout` has had its say
      first. Deliberately **not** re-asserted at 1.0s the way a divider is — switching layout resizes
      the window and rebuilds the scene, and doing that a second after launch would read as the player
      flinching. And a **gap in B44's own slice** is fixed: `persistableFrames()` sees the active
      layout only, so a divider dragged in a layout the user switched to later was stored and then
      never put back; `activateLayout` now restores that layout's own splitters.
      The window-visibility code moved onto the shared store unchanged (same section string, so no
      stored state is orphaned), and B44's section was renamed `@frame` → `@nullplayer.frames` to match
      it. **That last one resets a divider dragged before this landed, once.**
      Rules: `reference/rendering.md` → *What else the host remembers about a skin, and what it must
      not*. `swift test` 1131 pass (16 in `WinampModernPhase62Tests`).
      **Confirmed live by the user, 2026-08-24** — the shade round trip, the splitter in a non-default
      layout, and the negative case (skins never touched open unchanged).

---

## B33 — An unclosed tag at EOF kills the whole skin — closed 2026-08-24

- [x] **B33. An unclosed tag at EOF kills the whole skin — done 2026-08-24.** `Shield_Amp` was the
      only skin of the 30 installed that failed to load at all: `WalXML` threw `malformedXML`
      "Unclosed <container> tag" on `opensource_notifier/notifier.xml`, pulled in by an `<include>`
      from `skin.xml:36`. The skin's own bug — that file opens two `<container>`s, closes one, and
      ends on `<script file="…"/>` — but Winamp loads it, and our parser is documented as *lenient*.
      The engine rule is that malformed optional input should **warn, not fail**.
      It was as cheap as it looked. Nodes are attached to their parent (or to `roots`) at **open**
      time, not at close, so by the time the `guard stack.isEmpty` runs the tree is already complete
      and correct — the unclosed container simply has all its children. The throw is now a warning
      `WalDiagnostic` at the open tag's location; `maximumDepth` still bounds how much can be left
      open, so nothing about the sandbox changed. `parse` returns `WalParsedXML { roots, diagnostics }`
      rather than `[WalXMLNode]` so the warning can reach the compatibility report through
      `WalXMLDocumentLoader.loadFile`. Deliberately still strict: an **unexpected closing** tag
      (`</b>` matching nothing — no corpus skin does it, and the tree it would leave is ambiguous),
      unterminated comments/declarations/tags/attribute values, and every depth and node-count bound.
      Verified: Shield_Amp `testok=0` → **9 surfaces**, and a sweep of all 35 installed `.wal`s shows
      every previously-loading skin dumping the same count with no new diagnostic — the new code path
      is only reachable where the parser used to throw outright. `swift test` 1138 pass (7 in
      `WinampModernPhase63Tests`, including the synthetic truncated-`.wal` fixture).
      Rules: `reference/loading.md` → *What the XML parser tolerates, and what it still rejects*.
      **Confirmed live by the user, 2026-08-24.**
      Found by its sweep, filed rather than folded in: **B45**.

---

## B34 — The thinger is empty in every skin that has one — closed 2026-08-25

- [x] **B34. The thinger is empty in every skin that has one. Done 2026-08-25, confirmed live on
      mmd3 and the Nullsoft SP4 Lite Thinger window.** `<componentbucket>` is Winamp's
      scrolling strip of *installed component* icons (Media Library, AVS, plugin buttons) — click an
      icon to open that component, and the `<text display="componentbucket">` beside it names the
      focused one. NullPlayer hosts playlist/EQ/library surfaces but publishes no **icon set** for a
      bucket to enumerate, so every bucket draws empty, its caption stays blank, and
      `CB_NEXT`/`CB_PREV`/`CB_NEXTPAGE`/`CB_PREVPAGE` are `.inert(reason: "component bucket holds no
      icons to scroll")` in `WinampModernHostActions.swift:66`. Correct-and-recorded today, not a
      defect — this item is the feature that would make it real.
      Corpus demand, measured 2026-08-23 over all 40 `.wal`s (35 installed + 5 in `~/Downloads`):
      **14 skins**, splitting into two roles. *Thinger* (12, `CB_NEXT`/`CB_PREV`) — Mini_Me_2 ×10
      (one bucket per skin variant, `skin1thinger`…), mmd3 ×3 (`normal` + both shades), Lobe ×2,
      then boom_by_adil_daqyn, Capsule_II, corneramp_redux, Hoop_Life_WA3, Media_Whore, Overdrive_2,
      Styx, ZDL_Reel-To-Reel, Lapis_Lazuli ×1. *Config-drawer paging* (2, `CB_*PAGE`) —
      winampmodern566 and S7Reflex, already recorded in `skins/winamp-modern-stock.md:88`.
      Three traps worth knowing before starting:
      - **Four skins put the thinger in its own container**, not the player body —
        boom_by_adil_daqyn and corneramp_redux declare `<container id="Thinger" default_visible="0">`,
        ZDL and Lapis_Lazuli have dedicated thinger layouts. Those present as an empty *window* off
        Skin Windows, not a dead widget. ZDL's `EQ` + `thinger` pair is at `skins.md:46`
      - **Lapis_Lazuli declares a bucket with no arrows at all**, so it needs the icons but exercises
        no scroll path — the cheapest render-only check
      - **Lobe's arrows are correctly unhittable at rest** (`skins/lobe.md:100`): its thinger group
        sits at z-order 10–11 behind `metalbg` at 68. Do not read that as a regression when the
        icons land
      One icon set published from the component registry lights all 14 up at once; none needs
      skin-specific work. Verify with the render sweep plus a live check on mmd3 (in-body circle) and
      corneramp_redux (own container).
      **The corpus count above is wrong, and this is how (re-measured 2026-08-25).** It was taken by
      grepping the shipped XML files; a `.wal` draws only what its **include graph** reaches from
      `skin.xml`, and three skins ship a thinger they never include — `corneramp_redux`
      ("CornerAmp has never had the thinger but you can add it if you like", `skin.xml:26`), `Bio-Nid`
      and `Rika`. Those three have nothing to fix and nothing to see. Two more corrections: the
      include paths are **relative to the including file**, so a closure that only tries the literal
      string finds one skin in thirty-six; and `Lapis_Lazuli.wal` wraps its whole skin in a
      `Lapis_Lazuli/` subfolder, so it has no top-level `skin.xml` at all and is not installed.
      Live buckets in the **installed** set are seven: mmd3 ×3, Lobe ×2 (one `vertical="1"`),
      Overdrive_2, ZDL_Reel-To-Reel (own `thinger` container), Styx (in an `alpha="0"` drawer),
      S7Reflex (`CB_*PAGE`, vertical), Nullsoft.Winamp.2000.SP4.Lite (own Thinger window, `w="-31"
      relatw="1"` — the whole five-icon set at once, and the best single live check). Uninstalled but
      live in `~/Downloads`: Mini_Me_2 ×10, Media_Whore, Capsule_II, Hoop_Life_WA3 (vertical, 36×100),
      boom_by_adil_daqyn.
      Implementation checklist (2026-08-25):
      - [x] `WinampModernComponentBucket.swift` — the published icon set (one per hostable Winamp
            component), the pure box layout (`spacing`/`leftmargin`/`rightmargin`/`vertical`), and the
            skin-wide scroll/focus state on `WasabiSkinRuntime`
      - [x] Renderer: draw the strip, make a bucket renderable + interactive, hit-test an icon,
            scroll by item and by page
      - [x] `<text display="componentbucket">` reads the focused icon's name
      - [x] Click an icon → `routeComponentToggle`; hover moves the focus (and the caption)
      - [x] `CB_NEXT`/`CB_PREV`/`CB_NEXTPAGE`/`CB_PREVPAGE` stop being `.inert` and scroll the strip
      - [x] Manual verification, mmd3 — confirmed by the user 2026-08-25
      - [x] Manual verification, own-window case: Nullsoft.Winamp.2000.SP4.Lite (Thinger).
            *Not* corneramp_redux — it includes no thinger, which is why it showed nothing
      - [x] Tests (`WinampModernComponentBucketTests`, 14), skill docs (`reference/components.md`
            → *The component bucket*, `SKILL.md` routing + section + file map, `compatibility.md`,
            `compatibility/wasabi-surface.md`, `skins.md`, `skins/lobe.md`,
            `skins/winamp-modern-stock.md`), CHANGELOG

---

## B46 — `getPlayItemMetaDataString` coverage — closed 2026-08-24

- [x] **B46. `getPlayItemMetaDataString` answers four keys, so most of a file-info panel stays
      blank.** **Done.** The key table moved onto the host
      (`WinampModernHost.playItemMetadata(forKey:)`) so the harness and every test double answer as
      the live app does, and the runtime's four-case switch is now a one-line delegation to it. The
      tags past title/artist/album come from the library row for the playing file, looked up once per
      track id. The key set and its **units** were measured, not guessed: the union of the
      `getPlayItemMetaDataString` call sites across the 36 installed skins and Big Bento's compiled
      `fileinfo.maki` string table — which pins `length` to whole seconds (every caller wraps it in
      `integerToTime(stringToInteger(…))`) and `stereo`/`vbr` to flags (compared against `"1"`).
      **The open question is settled the way the user called it**: a streaming track answers from
      what the `Track` carries rather than going empty, and radio adds the four `stream*` fields from
      `RadioManager.currentStation` (`streamtitle` read live, never cached, since ICY changes it
      within one track).
      **The note's claim about ratings was wrong and checking the app corrected it** — NullPlayer has
      drawn a 0–5 star row for every source all along, on an internal 0–10 scale, so `rating` is
      answered and `getCurrentTrackRating`/`setCurrentTrackRating`/`onCurrentTrackRated` are wired.
      `setCurrentTrackRating` had not been in the method table at all, so a star click threw
      `unsupported` and aborted the rest of the handler. The per-source conversions moved out of
      `ModernLibraryBrowserView` into a shared `TrackRatingService`, which fixed a real bug on the
      way: the ART-mode star row had no Emby branch, so rating an Emby track updated the display and
      silently never saved. Only **Publisher**, `vbr` and `streamtype` stay empty, as explicit cases.
      Durable detail: `compatibility/maki-surface.md` → `getPlayItemMetaDataString` (the full table),
      `reference/components.md`, `reference/scripting.md`, `skins/big-bento-modern.md`. Tests:
      `WinampModernPhase65Tests`. The original report follows. Found by B39's live QA on 2026-08-24: with the `setText` precedence fixed, Big Bento's
      panel fills Title, Artist, Album and File Path and nothing else — even though **… → File Info
      Components** shows Year, Genre, Track #, Disc, Album Artist, Composer, Publisher, Decoder,
      Comment, BPM and Song Rating all ticked (the skin's own `newAttribute` defaults are `"1"` for
      every one of them; the menu is right, the data is missing).
      `WinampModernScriptRuntime.swift:2448` answers `title`, `artist`, `album`, `filename` and
      returns `""` for everything else; `fileinfo.maki` reads an empty field as "nothing to show" and
      hides that line, so a dozen enabled components are invisible. **Engine-wide, not Bento** — any
      skin's file-info surface asks for the same keys.
      The data mostly exists but not on the path the host adapter uses: `Track` carries only `genre`,
      while `MediaLibrary.MediaItem` has `albumArtist`, `trackNumber`, `discNumber`, `year`,
      `composer`, `comment`, `bpm`, `grouping`, `musicalKey`, `isrc` and `copyright`. So the work is a
      library lookup by URL behind `WinampModernHost`, plus `contentType`/bitrate for *Decoder*
      (`getDecoderName` already answers a codec name — reuse it rather than inventing a second
      answer). Two are expected to stay empty and should be **said** to stay empty rather than faked:
      **Publisher**, which is not stored, and **Song Rating**, where Bento wants Winamp's 0–5 star
      field and our Plex/Subsonic rating is a different concept (`getCurrentTrackRating` already
      answers 0 for the same reason).
      Decide first: a **streaming** track (radio, Plex, Jellyfin, Emby) has no library row. Answering
      empty and letting the lines hide is the honest default and matches what Winamp does with a
      shoutcast stream; falling back to whatever the server sent is the alternative. Not settled.

---

## B48 — Text NullPlayer draws on its own surfaces is unreadable in most skins — closed 2026-08-25

- [x] **B48. Text NullPlayer draws on its own surfaces is unreadable in most skins. Done 2026-08-25, confirmed live on Big Bento and Ebonite.** Reported live
      2026-08-25 (*"the playlist highlighter is white and the text underneath is also light"*,
      *"black titlebars with black title text"*, *"white text on light background"* on Ebonite) and
      then measured across all 36 installed skins. **This is the largest open defect in the `.wal`
      UI, and it is one cause with three faces.**

      **The cause.** `WasabiPalette` resolves each role from its own independent id chain, and
      *nothing ever checks that a foreground and the background it lands on can be seen together*. A
      skin that declares two colour families gets a mongrel pairing: Big Bento takes its highlight
      from `studio.list.item.selected` (orange) and its row text from `wasabi.list.text.selected`
      (pale blue-grey). Winamp never hits this — its Media Library is a native Win32 list where the
      OS guarantees a legible selection.

      **Measured (contrast ratios, corpus of 36).** The pair actually drawn on a selected row is
      `currentText` over `selectionBackground` (`PlexBrowserView.swift:4706`, `4718`, `4847`, `4848`
      — the code already switches text colour on selection; there is **no** missing field for the
      highlight, `currentText` is doing double duty):
      - **23 of 36 skins are unreadable (< 1.5:1) on the highlight**, nine of them at exactly
        **1.00:1** — text and highlight are the same colour. Includes Big Bento ×4, cPro-Bento,
        Defix, Sony_Walkman, BLAKK, both Mikus, Styx, T800, Shield_Amp, Itemskin, micro.
      - Window chrome (`drawWinampModernChrome`): title on the derived `barBackground` is
        **unreadable in 5** (Formamp, Itemskin, Lobe, micro, Nullsoft SP4) and weak (< 3:1) in 22
        more. `dimText` — the inactive title — is the worse half almost everywhere.
      - Reproduce the whole table with `WINAMP_MODERN_RENDER_PALETTE=1` per skin and a contrast
        function over the `PALETTE <role> = rgb(...)` lines; the roles needed are `listText`,
        `currentText`, `selectionBackground`, `contentBackground`.

      **Agreed fix (approved 2026-08-25, not started).** A legibility guarantee in
      `WinampModernSurfaceStyle`, which is the right home because that type already *derives* roles
      by blending "rather than invented" — and because it is **nil in classic mode**, so classic
      cannot be reached by it. For text drawn on a given background, take the first of the skin's own
      colours (`selectionText`, then `listText`, then `contentBackground`) that clears a contrast
      threshold, falling back to black/white only if none does: the skin's intent wins wherever the
      skin gives us something usable. Apply to the selection row **and** to the chrome title.
      - `PlaylistColors` (declared **twice**: `Skin/Skin.swift:120` and
        `NullPlayerCore/Skin/SkinTypes.swift:249`) needs a `selectedText`, defaulting to
        **`currentText`** — that is exactly what the four draw sites read today, so classic `.wsz`
        skins are a **zero-pixel change** and `SkinLoader` needs no edit. Getting the two struct
        declarations out of step is a build error, not a silent regression.
      - `PlexBrowserView` is the only file that draws these (it backs both the classic Library window
        and the embedded `.wal` surface); `PlaylistView` never reads `selectedBackground`.
      - **Watch `PlexBrowserView.swift:4335`** — it draws over
        `selectedBackground.withAlphaComponent(0.5)`, so the guard must judge the *composited*
        colour there or that state stays unreadable while the main one is fixed.
      - **Verify classic is untouched by capture, not by argument**: same `.wsz` skin, Library window
        before and after, byte-identical PNGs.
      - Open question worth measuring rather than assuming: `currentText` means "currently playing"
        on a normal row and "selected" on a highlight. Guarding it for the highlight is right, but a
        skin may still have a hard-to-read currently-playing row on the normal background.

      **Done 2026-08-25.** The guarantee is `WinampModernSurfaceStyle.legible(preferring:on:)` — the
      first of the skin's own colours that clears `minimumContrast` (3.0), black/white only if none
      does — plus the stored `selectedText` role, `legibleDimText(on:)` for inactive titles, and
      `composited(_:over:)` for the half-alpha search field. `PlaylistColors.selectedText` defaults to
      `currentText` in both declarations, so classic is a zero-pixel change by construction.
      12 new tests in `WinampModernPhase68Tests`; full suite 1214 green.

      **What live QA caught that the plan did not.** The first pass fixed the AppKit surfaces and
      *looked* complete — and Big Bento was still grey-on-orange, because the skin's **own** playlist
      panel and `<ColorThemes:List>` are drawn by `WasabiRenderer` straight from `WasabiPalette` and
      never touch a style. That is `WasabiRenderer.legibleRowColor`. Lesson worth keeping: a guard
      placed on the style covers only half the drawn rows in this engine.

      **Formamp: closed as won't-do, measured not assumed.** Reported as *"just black on black"*. Its
      window background is `(0,0,0,206)` — translucent by design, alpha never above 234 — and its
      `<text>` objects declare 80,80,80 / 120,120,120 / 100,100,100 themselves. Over a bright desktop
      the backdrop composites through. Guarding text a skin spelled out for its own controls overrules
      the author (it would also hit Lobe and micro), so the guard stops at surfaces we draw. An
      opaque-background option for translucent skins was offered and declined. Our chrome *inside*
      Formamp is still guarded: 2.16:1 → 3.94:1.

      **The open question stays open**, deliberately: `currentText` on a *normal* row (a
      currently-playing track on the content background) is a separate pairing and was not measured.
      Also not done: the byte-identical classic capture. The zero-pixel claim rests on the defaulted
      field plus `WinampModernSurfaceStyle` being nil in classic, both asserted in tests, and on the
      golden images being green — not on a capture.

---

## B49 — A live UI-mode switch leaves the main window at the outgoing mode's size — closed 2026-08-25

- [x] **B49. A live UI-mode switch leaves the main window at the outgoing mode's size.** Found during
      B26's live QA, 2026-08-25: switching `.wal` (Ebonite, 197×297) → Classic left the classic
      player in a 197×297 window, drawing its 275×116 skin scaled down inside it. Reported as
      *"the main window is tiny in classic mode at 100%"*.

      **Not the saved settings** — both channels were checked and are clean: `savedAppState` is
      mode-gated (`AppStateManager.swift:865`, a mismatch skips frame restoration entirely), and the
      legacy `MainWindowFrame` keys are **write-only** (`restoreWindowPositions()` has no callers).

      **The mechanism is two lines in `WindowManager`:**
      `recreateModeDependentLayout` (**:6167**) stamps the *outgoing* mode's frame onto the freshly
      created target-mode window —
      `mainWindowController?.window?.setFrame(main.frame, display: true)` — and the only thing that
      would then correct it is the UI-Size re-apply in `performReloadUI` (**:6615**), which runs
      **only** `if restoreScaleLevel != .p100`. At 100% nothing ever resizes the window to
      `Skin.mainWindowSize * scale`.
      **Testable prediction: the bug should vanish at any UI Size other than 100%**, because setting
      `uiScaleLevel` triggers `applyDoubleSize`. Confirm that before fixing — it pins the mechanism.

      **Fix**: the BB2c rule, applied to the switch — keep the snapshot's **origin**, take the target
      mode's **own size**, unconditionally rather than only when the scale changed. Note the code
      above the collapse-to-1x already warns about "forcing the old mode's enlarged frames onto
      freshly-created target-mode windows"; it handles *scale* but not the *base size* difference
      between modes. Check every mode pair, not just `.wal`→classic.

      **Done 2026-08-25.** One site: `recreateModeDependentLayout` now calls
      `WindowManager.mainFrameForModeSwitch(outgoing:ownSize:)`, which keeps the snapshot's origin and
      takes the freshly created window's **own** size, anchored top-left — unconditionally, so it no
      longer depends on the `restoreScaleLevel != .p100` re-apply. `showMainWindow` has already sized
      that window to the incoming mode's layout (including
      `normalizeModernMainWindowForHTIfNeeded`), so its current size *is* the target-mode size and no
      per-mode branch is needed; that is what makes it cover every mode pair. 6 tests in
      `WindowRestoreGeometryTests`, both directions plus a height-only pair and an identity case;
      full suite 1220 green. Manually verified by the user.

      **The rule already existed and was applied in only one place.** `AppStateManager.mainFrameForRestore`
      (BB2c) is the same "keep position, substitute the loaded skin's size" rule for *launch restore*.
      A test now asserts the two functions agree on the same input, so the switch path and the restore
      path cannot drift apart again. Worth generalising: when a rule like this lands, grep for every
      site that re-stamps a saved frame rather than fixing the one that was reported.

      **The `!= .p100` prediction was never actually run.** The fix makes the resize unconditional,
      so the prediction stopped being load-bearing — but it was not measured, and the mechanism
      therefore rests on reading the two lines rather than on an observation. If this recurs, run it.

---

## B35 — The four Big Bento Modern variants fail to load — closed 2026-08-23

### B35 — The four Big Bento Modern variants fail to load

Plan: `~/.claude/plans/contineu-purring-dove.md`. Three independent root causes: `@SKINSPATH@` is an
undefined path variable (hard `.unresolvedPathVariable`); the two *Light* editions are overlays that
pull six of their eight includes out of the **base** skin's directory through that token; and the
Windows 10 edition ships a zero-byte `window/no_alb_art_shade.png` whose `.invalidImageResource`
fails the entire skin.

- [x] **B35.1 `@SKINSPATH@` → `/Skins`** — define it in `WalVirtualFileSystem.init()` alongside
      `WINAMPPATH` / `DEFAULTSKINPATH` (it is a fixed collection root, not skin-derived).
- [x] **B35.2 Lazy sibling mounts** — `siblingMountResolver` closure + `mountSiblingIfNeeded(for:)`
      on the VFS, consulted **only** when no mount already owns the path, from
      `canonicalExistingPath` (retry once after a mount) and from `expand` (before filtering
      `allLogicalPaths()`). Memoize misses in `failedSiblingNames`; cap at 4 mounts per load.
- [x] **B35.3 Loader supplies the resolver** — `WinampModernSkinLoader.load(from:additionalMounts:)`
      searches the archive's own directory, then `WinampModernSkinImporter.defaultDestinationDirectory()`,
      matching `safeMountName(basename)` case-insensitively; opens each hit with the same
      `archiveLimits`.
- [x] **B35.4 Name the missing base** — new `WalDiagnosticCode.missingRequiredMount`, thrown with
      "This skin requires the skin '<name>' to be installed." so it bypasses the two
      `.resourceMissing` tolerance blocks (`WalXML` include warning, `resolveSkinResource`'s
      `@SKINPATH@` fallback). Categorize as `resources` in `WinampModernCompatibilityReport`.
- [x] **B35.5 Undecodable images degrade** — in `registerResources`, tolerate `.invalidImageResource`
      exactly like `.resourceMissing` for `bitmap`/`cursor`/`bitmapfont`: register without
      `logicalFile` and warn. `.imageDimensionsExceeded` stays fatal.
- [x] **B35.6 Tests** — Phase 2: `@SKINSPATH@` resolves; own-name self-reference needs no resolver;
      sibling `<include>` expands from a `.wal` next door; absent sibling throws
      `.missingRequiredMount` naming it; 4-mount cap; a repeated miss does not re-scan. Phase 7:
      zero-byte bitmap degrades to a warning (tighten
      `testMalformedImageResourceDegradesInsteadOfCrashing`); oversized still throws.
- [x] **B35.7 Verify** — `swift test`, goldens, render-dump per variant with
      `WINAMP_MODERN_RENDER_BITMAPS=1`, then the corpus sweep diffed **by pixels** against a
      pre-change run.
- [x] **B35.8 Land the findings** — `reference/loading.md` (VFS mounts table + *Sibling skin mounts*),
      `compatibility.md`, `skins.md` + new `skins/big-bento-modern.md`, `CHANGELOG`.
- [x] **B35.9 Live QA, 2026-08-23** — done by the user. The skins come up in the running app; the
      window is large because the layout declares `w="1536" h="878"` and the UI was at 150% scale,
      not a defect. Found live: the SUI menu bar draws its five items on top of each other → **B36**.

---

## B36 — The `<Menu>` XUI does not self-size — wrong diagnosis — closed 2026-08-23

### B36 — The `<Menu>` XUI does not self-size — **wrong diagnosis; closed 2026-08-23**

The measurement was right and the conclusion was not. All five `Menu` objects did report
`frame=(190, 6, 0, 32)`, but not because the widget fails to self-size: `player.mainmenu` carries the
comment *"Note: Most of the items in this group are placed by script"*, and `mainmenu.maki` measures
each label with `getAutoWidth()` and lays the five out left to right. That script was aborting on
`getSettingsPath` before it reached the layout code. With the method implemented the five place
themselves at x = 190 / 231 / 277 / 350 / 400 with no widget change at all.

- [x] **B36.1/B36.2** Not implemented, and deliberately so — adding label-measuring and `prev`-chain
      placement to the `Menu` widget would have fought a working script. If a skin ever turns up that
      declares `<Menu prev=…>` with no placement script, that is when to build it.
- [x] **B36.3** Corpus check done: `<Menu>` with `prev`/`next` and no geometry appears only in this
      family. Pixel-diffed render sweep clean apart from the intended changes (see B37).

Follow-up, **not** in this change: `@HAVE_LIBRARY@` — carried to **BB5** above.

---

## B37 — Big Bento Modern renders wrong in the app — closed 2026-08-23

### B37 — Big Bento Modern renders wrong in the app (live, 2026-08-23) — **done 2026-08-23**

B35 made all four variants **load**; this was the list of what was wrong once they were on screen.
Five separately reported symptoms, and **one cause behind four of them**: 23 of the skin's
`onScriptLoaded` handlers aborted on `System.getSettingsPath()` (the skin probes
`<settings>/WACUP_Tools/koopa.ini` to sniff for WACUP near the top of nearly every script), so the
layout work in the rest of each handler never ran. `RENDER_SCRIPTS=1`'s `failed=` column says this in
one line per script and should have been the first probe, not `RENDER_PROBE`.

- [x] **B37.1 The menu bar items overlap** — fixed by `getSettingsPath`; see **B36**, whose proposed
      widget rule was the wrong fix.
- [x] **B37.2 The song ticker overruns its box** — `InfoDisplay` is clipped to its own 237px box, and
      always was (`drawText` does `context.clip(to: frame)`). What the screenshot showed was the box
      *empty of a time readout beside it*, plus the title drawn full-size across a display panel that
      had nothing else in it. With B37.3 fixed the panel reads `1:13` / `1:13 / 4:05` / title, and the
      title stops at the panel edge. No renderer change was needed.
- [x] **B37.3 The two display panels left of the ticker are empty** — the `display=` binding table
      knew only `time` / `songname` / `songinfo` / `PE_Info`. This skin asks for `TIMEELAPSED`,
      `SONGLENGTH`, `SONGTITLE` and `SONGSAMPLERATE`, which fell through to the literal `text=`.
      Added those plus `songartist` / `songalbum` / `songbitrate` / `artistname` (the whole corpus
      census) and `timerhours`. Also fixed, unreported: Ebonite_2_1 and Enkera's KBPS/KHZ readouts
      and mmd3's playlist-shade song length, all blank for the same reason.
- [x] **B37.4 The album-art panel is a solid black square** — the cover script aborted on
      `getAutoHeight` (masked behind `getSettingsPath`); it now draws its `no_alb_art` placeholder.
- **B37.5 The embedded library is unstyled** — the one item of B37 that did not close. It is
  **BB2** in *Open* above; do not track it here.

Two further fixes fell out, neither on the original list:

- **`offsetx`/`offsety` on a `<text>` were ignored.** They shift the string inside its own box without
  moving the box, and Big Bento's SUI tab captions are `offsetx="35"` — which is what puts them clear
  of the icon in icons+text mode and *outside the clip* in the 40px icons-only mode. Unblocking the
  tab script made every caption draw over its own icon until this was honoured. Six declarations in
  the whole corpus, all in this family.
- **The shade titlebar drew "WACUP" over "WINAMP".** Same `getSettingsPath` cause: the probe now
  answers "not WACUP" and the logo stays hidden.

Verified: `swift test` (1022, 0 failures, 13 new in `WinampModernPhase53Tests`) and the 30-skin,
289-image render sweep pixel-diffed against a pre-change build — 19 images changed, all four Bento
variants (intended), Ebonite_2_1 / Enkera / mmd3 (the readout fixes above, inspected), and Anexa's
`main-shade`, which differs between two runs of the *same* binary. Live QA on the four variants is
still outstanding.

**Follow-up, not in this change: `instantiate`** — carried to **BB1** above.

---

## B38 — Big Bento Modern live defects found in QA — closed 2026-08-23

### B38 — Big Bento Modern, live defects found in QA (2026-08-23) — **closed**

Found by the user driving the app after B36/B37 landed. Neither of the first two reproduces in the
render harness, so both were diagnosed from the app's own `#if DEBUG` logging.

- [x] **B38.1 The window goes undraggable after shade → normal.** `shouldDragWindow(from:)` honoured
      `move="1"` on `<group>` only — 421 of the **981** declarations across the 30 installed skins,
      on 14 element types (`rect` 233, `layer` 151, `text` 66, `grid` 36, `grouplist` 34). Big
      Bento's titlebar is `<grid … move="1">` over `<rect id="vic_mover" move="1" fitparent="1">`, so
      the window could only be dragged wherever a bare background happened to be topmost, and a trip
      through shade changed which object that was. Now honoured on any non-control element; controls
      are excluded (17 declarations) because a button that both acts and drags eats its own click.
      Confirmed fixed live.
- [x] **B38.2 The playlist and the media library draw on top of each other at launch.** Two causes,
      one behind the other:
      1. `openHolders` — the `autoopen` fallback — forces a holder's hidden ancestors visible without
         knowing the other six tab pages exist (`sui.components` holds seven `<group visible="0">`).
         A restored session with both a playlist and a library window revealed both. It now reverts
         what it previously forced.
      2. That alone was not enough, and the log said why: **the skin's script opens its tab on its
         own timer, ~0.6s after our reveals.** All four launch reveals legitimately fell through to
         the fallback (the tab genuinely was not open *yet*), we forced the library page, and then
         `suicore.maki` opened the playlist it had decided on all along — with no idea a second page
         was open. So exclusivity is re-checked on every layout pass and always resolves the same
         way: **the page we forced yields to the page the skin opened.** Confirmed fixed live.
- [x] **B38.3 `getTextWidth` unsupported.** It aborted `onTextChanged` — the one handler that runs on
      every track change. (Distinct from `getAutoWidth`: how wide the string *draws*, not how wide
      the object wants to be. Skins compare the two to decide whether a caption fits.) **The rest of
      it**, found when B38.4 let the Multi Content View run: the file-info panel's `onSetVisible` —
      the handler that fills every line of it — then aborted on **`getDecoderName`**, and behind that
      on `getPath`, `getIdealVideoWidth` and `removePath` in turn. All four implemented; the panel
      now fills. `getDecoderName` answers the codec NullPlayer is decoding, `getPath`/`removePath`
      are pure string splits of a path the host already handed out, and the video pair answer 0 for
      the same reason `hasVideoSupport` is false. `getPlayItemMetaDataString("filename")` — which
      those splits are called on — now answers the playing item's location.
      *The harness could not see any of this*: `onTextChanged` is polled by the window controller, so
      `WINAMP_MODERN_RENDER_TEXT=1` was added to drive it (with `RENDER_PLAYLIST`, since both of this
      skin's bound text objects are `PE_Info` feeds).
- [x] **B38.4 The visualization box draws black over the album art.** The skin picks between the two
      panes from config attributes it registers itself, and at the defaults hides
      `info.component.vis`. That branch is in `mcvcore`'s **first** `System.onScriptLoaded()` — and
      the script declares a **second** one, so the "keep the last binding per (object, event)" rule
      introduced for Defix in Phase 42 shadowed it and *none* of `mcvcore` ran. The rule now drops
      only a binding whose **body repeats** an earlier one for the same pair (compared with jump targets relative to the
      entry point and variable slots renumbered, because the compiler gives each copy its own
      temporaries); two different bodies are two real handlers and both run. Defix's duplicated
      `ConfBT2.onLeftClick` still runs once, so its toggle does not flash.
      Three more things came back with it in the sweep, all previously recorded as fixed and all in
      fact still broken at HEAD: the Multi Content View's info display is laid out instead of sitting
      at its markup `x=80 w=0`, the full-width `info.component.coverflow` leaves the scene, and shade
      mode stops drawing **WACUP** over **WINAMP**.
- [x] **B38.5 The playlist-info panel takes half the top bar — not a defect.** `from="left"` anchors
      the divider to the left edge, so the right pane absorbs the extra width. That is what Wasabi's
      `from` means, what the skin's own `maxwidth="-300"` ("always leave 300 for the other pane") is
      written for, and what its script asks for with `setPosition(434)` against `minwidth="434"`. The
      window is wide because the layout declares `w="1536" h="878"` as its **default**. cPro-Bento's
      `centro.mainframe` is the same attribute the other way round (`from="right" width="200"`, its
      playlist column fixed and the left side growing), which confirms the reading. The huge song
      title is the skin's `fontsize="48"` in a 237px `InfoDisplay`; nothing in the corpus writes
      `fontsize` except `playlistpro.maki`, so no script is meant to shrink it.

Verified: `swift test` 1028 pass; 300-image corpus sweep across all 36 installed skins pixel-diffed
against a build of `HEAD`. 281 identical, 19 changed: the four Bento variants' `main-normal`,
`main-shade` and `searchresults-normal` (all four inspected — the Multi Content View fills, the
WACUP logo goes, and `searchresults` draws the 0 nodes the skin index says it should), Ebonite_2_1 /
Enkera / mmd3 (B38.3's readouts, already inspected in the previous pass) and Anexa's `main-shade`,
which differs between two runs of the same binary. B38.1 and B38.2 confirmed live by the user.

---

## BB1 — `instantiate` — superseded by BB7 — closed 2026-08-24

- [x] **BB1. `instantiate` — superseded by BB7, which corrects it.** Read **BB7** instead. This entry
      described the method as `instantiate(groupdef_id, index)` with "nine call sites" and called it
      a real engine capability rather than an arity question. The MAKI source says otherwise on all
      three counts (2026-08-23), and the engine already does the part this entry assumed was
      missing. The number is kept, not reused, so the correction is traceable. Closed with BB7.

- **BB2. The embedded library tab is unstyled** (was B37.5) — **closed 2026-08-25. Split into BB2a
  (fixed, confirmed live) and BB2b (won't do).** The original entry read as one
  styling job and guessed the palette never reached the surface. It does: `reconcileHostedSurfaces`
  calls `applyPalette(renderer.palette)` when the library surface mounts and again on a theme change,
  `WinampModernSurfaceStyle.background = palette.contentBackground`, and an embedded browser takes its
  list colours from `style.playlistColors`. What is actually wrong is two unrelated things, one small
  and one large, and they should not be done together. Neither reproduces headlessly — the harness
  sets no component host — so both need the running app and a before/after screenshot, not a probe.

---

## BB2a — The embedded library panel is the wrong colour — closed 2026-08-25

- [x] **BB2a. The embedded library panel is the wrong colour. Fixed 2026-08-25, confirmed live.**
      Black, where the skin names a colour. **Neither of the two suspects this entry recorded was
      right** — the `PlayerDisplay` gammagroup leaves (55,57,64) alone, and the list paints
      `playlistColors` as designed. The colour was lost in *resolution*, and three separate faults did
      it, each reaching well past this panel:
      **(1)** a `<color>`'s value may name **another colour resource** (`wasabi.list.text` =
      `color.display`), which was split on commas, came out as one token, and became
      `unparseableColor` — white. That alone made Bento's whole list palette white-on-black.
      **(2)** Wasabi keeps **bitmaps and colours in different tables**, and Bento declares
      `wasabi.list.background` as both a `<color>` (`system-colors.xml:99`) and a tiled `<bitmap>`
      (`system-elements.xml:68`); a flat registry let the bitmap win, and a colour lookup found an
      image with no `color=`, so the chain fell to the black literal — the reported rectangle.
      **(3)** `#rrggbb` was not parsed as a literal, which is a different skin's bug entirely
      (see the Sony_Walkman note below).
      The first step this entry asked for is now a permanent instrument: **`WINAMP_MODERN_RENDER_PALETTE=1`**
      prints every role, every link of its chain and why each one answered — it is what ruled the
      gamma model out in one line. Measured end state: `contentBackground = rgb(55,57,64)`, matching
      `xml/system-colors.xml:30`. Corpus checked as the entry asked: cPro-Bento `rgb(8,9,10)` and
      Defix `rgb(13,17,17)` were already correct, so **the defect was Bento-shaped, but its causes
      were general** — Enkera's entire palette was white for reason (3), and Bento's own Web Reader
      results surface (`<rect color="wasabi.list.background">`, `xml/reader.xml:16`) was a white slab
      for reason (2). `swift test` 1200 pass. Skill: `skins/big-bento-modern.md` → BB2a,
      `reference/rendering.md` → *How a colour resolves*, `reference/harness.md` → `RENDER_PALETTE`.

---

## BB2b — The panel's chrome is structurally foreign — WON'T DO — closed 2026-08-25

- **BB2b. The panel's chrome is structurally foreign — WON'T DO, closed 2026-08-25.** Kept as a
      decision, not a backlog item, so it is not re-proposed. After BB2a the pane takes the skin's
      background, list text, selection and derived bar/border/divider colours, and **that is the
      faithful end state**: Winamp never skinned this surface either — its Media Library is `gen_ml`,
      a native Win32 list the skin only *colours* through its colour themes. What a "chrome-only"
      pass would still change (bar heights, border weight, the boxed tab rectangles) is minor once
      the colours are right, while the one substantial tell — the **monospace font** — is exactly
      what such a pass excludes. Small payoff for real work, so it is not worth doing as scoped.
      **If it is ever reopened, it is the font or nothing**, and the shape of that job is: 11 places
      in `PlexBrowserView` compute a cell width from `SkinElements.TextFont.charWidth` and 24 uses
      consume them, so it is one mode-aware measurement helper behind those 11 — classic arithmetic
      in classic mode, real text measurement in `.wal` mode — not a rewrite of every consumer. The
      file is shared with the classic library window, which is therefore the regression surface and
      belongs in any test plan.

---

## BB2c — A `.wal` main window came back at another skin's size — closed 2026-08-25

- [x] **BB2c. A `.wal` main window came back at another skin's size. Fixed 2026-08-25, confirmed
      live.** Found while QA-ing BB2a and unrelated to it. Reported as *"the title bar split off the
      main body of winampmodern566 into 2 windows and the horizontal size is huge"* — it was one
      window, stretched: 566 anchors its titlebar to the top and its player bar to the bottom, so at
      the wrong size they sit at opposite ends of an empty window. `AppState.mainWindowFrame` is a
      single global key, but a `.wal` window's **size is the skin's**: Big Bento Modern's `main/normal`
      is 1536×878 against 566's 354×280, and the saved frame was Bento's, restored *after* the skin
      had sized the window correctly. `clampRestoredFrame` had nothing to catch because 566 declares
      `max=16384x16384` and is meant to widen. `AppState` now records `winampModernSkinName`, and
      `AppStateManager.mainFrameForRestore` keeps the saved **origin** while taking the loaded skin's
      **own size** whenever the names differ; a pre-existing state decodes as `nil`, never matches, and
      self-corrects on the next launch. **Two things that hid it:** headless geometry is correct
      (`RENDER-DUMP main/normal: 354x280` before and after — the defect is entirely in the window
      layer), and `kill_build_run.sh`'s `pkill -9` never writes saved state while the selected-skin
      preference is written immediately, so the dev loop manufactures the mismatch. Skill:
      `reference/rendering.md` → *…but a `.wal` window's size is still the skin's*.

---

## BB2d — Sony_Walkman's analyzer drew opaque white over its own wordmark — closed 2026-08-25

- [x] **BB2d. Sony_Walkman's analyzer drew opaque white over its own wordmark. Fixed 2026-08-25.**
      Every band is `colorband1="#808589"`. The `#rrggbb` parse existed but was committed **disabled**
      behind `if false` in `8c7e0567` — whose message states it *"lands the inline #rrggbb colour
      parse"* and reports a 288-image sweep including *"Sony_Walkman's analyzer in the grey it asked
      for"*, a result only reachable with it enabled. So the shipped build contradicted its own
      recorded verification; this is the leftover toggle, not a decision. **The sweep that commit
      claimed has now been run**: all 36 installed skins, 310 images, gate on vs. off — 308 identical,
      1 real change (Sony_Walkman's `main-normal`, the intended fix), and `Anexa/main-shade`, which
      differs between two runs of the *same* tree and is the known nondeterministic render that commit
      also named. Skill: `skins.md` → Sony_Walkman.

---

## BB4 — Live QA of B38.4 / the rest of B38.3 — closed 2026-08-25

- [x] **BB4. Live QA of B38.4 / the rest of B38.3 — re-run 2026-08-25, and all three symptoms are
      gone. Confirmed live.** Nothing was fixed for this; the intervening work closed it, which is why
      the entry is kept rather than deleted. Measured on the running app with a track playing, base
      variant and Light, driving the library with `CGEvent` clicks (Albums tab → double-click an
      album) and reading `WINAMP_MODERN_CALL_TRACE=1` + `WINAMP_MODERN_DEBUG_HOLDERS=1`:
      the **cover-flow strip** is gone — `mcvcore` resolves `info.component.coverflow` and hides it,
      and the run ends on `setprivatestring(Big Bento Modern, Component3, File Info)`, the page it is
      meant to pick; the **details column** is laid out, one line each for bitrate/KHZ/stereo, title,
      artist, album and genre; and the **album art draws once**, with the zoomed backdrop as a dimmed
      wash behind the panel — which is the live confirmation **BB6/B42** was waiting for.
      The trace is the finding that matters: `mcvcore` reaches `findobject` on all four MCV pages, the
      album-bg pair, the footer and the menu, then starts its timers — the whole handler, so the
      **B38.4 dispatch-binding fix runs in the app**, not only headlessly.
      Found while measuring, and filed separately: the rating row draws as five dots (**BB26**).
      <details><summary>original entry (the 2026-08-23 failure)</summary>

      B38.1 and B38.2 were confirmed on screen by the user; the B38.4 dispatch-binding fix and the
      four methods behind it were verified only headlessly and by a 300-image pixel diff. They did
      **not** hold in the running app. The user's screenshot of the header is timestamped 19:10 and
      the debug build it came from is 18:53 — the same working tree that contains every B37/B38
      change — so this was not a stale binary. Still wrong on screen: a full-width cover-flow strip
      crosses the panel, the details column is squashed rather than laid out, and the album art is
      drawn twice (**BB6**). What *did* hold: the file-info panel fills its lines, though with the
      wrong content (**B39**). **The lesson stands even though the entry closed clean**: treat a
      headless pass as necessary and not sufficient for anything in this panel — B38 established that
      three of its five defects never reproduced in the harness.
      </details>

---

## BB6 — The album art is drawn twice — closed 2026-08-24

- [x] **BB6. The album art is drawn twice. Fixed 2026-08-24 — as `B42` in `TASKS.md`, because it
      is not a Bento defect.** The cause was `relatw`/`relath` greater than 1 falling back to absolute
      geometry, so the oversized dimmed backdrop drew at its literal `99×100` as a small crisp second
      copy. Reached 5 skins beyond this family. Rule: `reference/loading.md` → the `relat*` flags are
      `atoi(value) != 0`. The three-`albumart` trap this entry warned about is in the skin's own file.
      **Confirmed live 2026-08-25**, in BB4's re-run: one crisp cover, and the backdrop is a dimmed
      wash behind the panel.

---

## BB7 — `GroupList.instantiate(groupdef, count)` — closed 2026-08-24

- [x] **BB7. `GroupList.instantiate(groupdef, count)` — supersedes and corrects BB1. Done
      2026-08-23.** Built the config window's option pages and the SUI equalizer tab, which drew empty
      because the skin declares them as empty `<GroupList>`s and inserts their content by script.
      `getApplicationPath` was the domino behind it. Took the four variants from `unsupported` to
      `degraded`. **Confirmed live** — the EQ tab and all eight `instantiate`-built pages.
      Durable detail: `reference/scripting.md` → *`GroupList.instantiate`*,
      `compatibility/maki-surface.md`, and the skin's own file (which records the arity correction,
      the two call sites, and the three inline pages that make a control group).

---

## BB8 — `ColorMgr.getGammaSet(name).apply()` — closed 2026-08-24

- [x] **BB8. `ColorMgr.getGammaSet(name).apply()` — the 77-theme colour picker. Done 2026-08-24.**
      Bound by class GUID, not by method name; verified end to end against the real skin before any
      test. Not Bento-only — Ebonite_2_1 reaches the catalog the same way, so the surface fact lives
      in `compatibility/maki-surface.md` and the binding mechanics in `reference/scripting.md` →
      *Binding a host singleton by class GUID*. **Not verified live** — the page has content (BB7)
      but has not been clicked in the running app.

---

## BB12 — The header strip and the seek bar — closed 2026-08-24

- [x] **BB12. The header strip and the seek bar — measured 2026-08-24. The seek bar is fixed; the
      header did not reproduce.** The seek bar was a solid black bar because `wdh.waveseeker` — a
      `<windowholder … hold="none"/>` sitting on top of it — was read as an *unknown* component and
      painted an inert slab. `none` means the holder holds nothing. Rule: `reference/components.md` →
      *Component hosting*; the skin's own file records the rect and the corpus scan.
      **The header did not reproduce headlessly** — the dump draws the hamburger, bolt, WINAMP logo
      and all five menu items, and the titlebar art really is a flat four-colour gradient. Neither
      BB3 nor an unresolved frame bitmap is involved. **This half stays open as a live question**:
      re-measure in the running app before filing any cause.
      **The Windows 10 editions' seek bar is still blank, separately** — they ship
      `waveseeker.rounder.bg` as `visible="1"` where the base ships it `visible="0"`, an opaque wash,
      and `seek.maki` runs clean without hiding it. Cause unmeasured; do not guess one.
      `swift test` 1074 pass (7 new, `WinampModernPhase57Tests`); 288-image sweep, 285 identical.
      **Confirmed live by the user, 2026-08-24.**

---

## BB16 — One click on the seek bar hid it — closed 2026-08-24

- [x] **BB16. One click on the seek bar hid it, and then it could not be clicked again. Fixed
      2026-08-24.** Reported live right after BB12 made the bar visible. **Pre-existing, not caused by
      BB12** — it reproduces identically at `HEAD`; the slab had been hiding the bar in *both* states.
      `seek.maki` hides its own only seek slider on mouse-up and mirrors the trough and fill to it, so
      one press-release took the whole bar out — and an invisible object is not hit-testable, so
      seeking stopped working until a track change.
      Fixed by a **stranded-control rule** that keys on the layout, not the skin: a `hide()` leaving a
      layout with no visible control for a positional host action is undone when the event settles.
      Defix runs the identical script and does not trip it. Rule, its three deliberate properties, and
      why stock Winamp Modern is unaffected: `reference/scripting.md` → *A layout must not be left
      with no way to seek*. A second gap fixed in the same path — `Timer.onTimer()` called as a method
      — is in the same file → *An event handler is also a method, on every kind of receiver*.
      `swift test` 1082 pass (8 new, `WinampModernPhase58Tests`); 288-image sweep, 287 identical.
      **Confirmed live by the user, 2026-08-24.**

---

## BB17 — No separate WACUP skin concept — closed 2026-08-24

- [x] **BB17. Should there be a "WACUP skin" concept with its own engine branching? Measured
      2026-08-24 — no.** Closed rather than left open so it is not re-proposed. The finding is durable
      and lives in the skill: **[reference/wacup.md](../../skills/winamp-modern-skin-guide/reference/wacup.md)**
      — how a skin probes for WACUP, why we answer truthfully, what the 69 references in this family
      actually gate (branding), and why the WACUP-only *surfaces* are gated on ordinary settings
      rather than on the dialect.

---

## BB19 — The settings pages could not be scrolled — closed 2026-08-24

- [x] **BB19. The settings pages could not be scrolled. Fixed 2026-08-24, confirmed live.**
      **Seven independent faults, stacked** — the table and the durable rules are in the skin's own
      file (`skins/big-bento-modern.md` → *BB19*) and in `reference/scripting.md` /
      `reference/rendering.md`. In short: the wheel never reached a skin; `scrollToPercent` was a
      no-op; the `embed_xui` seam carried neither the value events nor the declared range; the wrapper
      and its embedded slider kept two separate values; `setPosition` never clamped; and
      **`orientation="v"` was read as horizontal**, so a drag took its value from the pointer's *x*
      across a 16px bar.
      **That last one reaches 8 skins** — Anexa, Enkera, Lobe and The_Nokia_5220 as well as this
      family — whose equalizers could never draw a curve. Verified by driving a −120…+120 sweep
      through `RENDER_EQ`: the thumbs now trace it.
      New probe: `WINAMP_MODERN_RENDER_GEOMETRY=<id>` — the resolved box of a named object and its
      children *including hidden ones*, with content/box/travel. The settings pages live in a closed
      tab, so no existing probe could see them at all.
      `swift test` 1096 pass (15 new across `WinampModernPhase59Tests`); 288-image corpus sweep — 284
      identical, 3 changed and inspected (Anexa's and Lobe's equalizers, cPro-Bento's widget manager,
      all now drawing their vertical sliders on the right axis), plus Anexa's nondeterministic
      `main-shade`.
      **The method lesson is the durable one and it is in `reference/harness.md` → *Ask for the live
      trace first, not fourth*:** five rebuild-and-retest rounds were spent reasoning about which hop
      might be broken, and one `CALL-TRACE` histogram named the cause immediately.

---

## BB20 — The dump harness answers geometry during `onScriptLoaded` — closed 2026-08-24

- [x] **BB20. The dump harness answers markup for every geometry read inside `onScriptLoaded`. Fixed 2026-08-24.**
      The harness now builds a renderer per container *before* `try runtime.start()` and installs a
      `resolvedGeometryRequested` that asks each in turn — the app's own wiring — and the dump loop
      reuses those same instances. Rule: `reference/harness.md` → *The harness answers geometry from
      before `start()`*. 288-image sweep taken across the change; the images that moved are recorded
      under BB22 below.
      <details><summary>original entry</summary>

      Found while measuring BB9, and **not Bento-only** — it affects every skin in the corpus.
      `WinampModernRenderDumpTests` installs `runtime.resolvedGeometryRequested` inside its
      per-container loop, long after `try runtime.start()`. Skins do nearly all of their layout in
      `onScriptLoaded`, so during it `getWidth`/`getLeft`/`getGuiW` fall back to `object.geometry` —
      `0` for a `w="0" relatw="1"` group. Big Bento's visualizer measured `getwidth() -> 0` headlessly
      against `346` in the app; both hide the analyzer, so **the harness agreed with the symptom for
      the wrong reason**. The app is the model: `wireContainerCallbacks` installs the closure *before*
      `scripts.start()` and consults every container's renderer. **Expect the 288-image sweep to
      change** — that is the point, so budget for inspecting the diff.
      </details>

---

## BB21 — Bento's header analyzer splitter — closed 2026-08-24

- [x] **BB21. Bento's header `<vis>` analyzer is behind a splitter that cannot be dragged. Fixed
      2026-08-24, confirmed live.** The divider claimed a press only when nothing interactive sat under
      it, and this skin covers every pixel with `<layer id="player.resizer.disable" move="1"
      alpha="0">` plus four alpha-0 mousetraps on the seam — so the cursor promised a resize and every
      press dragged the window. `renderer.objectOverridingDivider(at:)` is the rule: on a splitter's
      own grab strip an **invisible** object (`alpha="0"`) and a bare **`move="1"`** window-drag
      surface do not outrank it; a button, a slider or anything carrying an action still does. Scoped
      to the grab rect, so cPro's tab strip crossing its seam is unaffected. The skin's own
      `mousetrap3`/`mousetrap4` are `alpha="255"` and sit above and below the strip, and keep their
      claim. Rule: `reference/rendering.md` → *What outranks a splitter on its own grab strip*.
      **This also unblocked the header analyzer** — `visualizer.maki` shows `main.vis.group` only
      above 730px of player width, which is this divider.
      <details><summary>original entry</summary>

      Separate from BB9's panes. Six `<vis>` boxes in `main.vis.group` are shown only when
      `visualizer.maki`'s `onResize` reports more than 730px of player width; that width is the
      `player.mainframe.big` divider, clamped to `minwidth="434"` at load. The divider cannot be
      grabbed: `mouseDown` claims a seam only when `renderer.object(at:) == nil`, and Bento covers
      every pixel with `<layer id="player.resizer.disable" … move="1" alpha="0">` plus four alpha-0
      mousetraps on the seam itself — so every press drags the window while the resize cursor promises
      otherwise. An unconfirmed patch keying the rule on *interactivity* is at
      `scratchpad/bb9-revert.patch`; **it was never verified on screen**, so re-derive rather than
      trust it. Also unestablished: whether Winamp starts Bento with a narrow player pane at all — if
      not, the defect is the divider's *position*, not its draggability.
      </details>

---

## BB22 — The `.wal` window ran at a few frames a second — closed 2026-08-24

- [x] **BB22. The `.wal` window ran at a few frames a second. Fixed 2026-08-24, confirmed live
      ("it looks better").** Six independent costs, none of them the analyzer that was blamed. Four in
      the renderer, measured at `RENDER_TIME_SCALE=2` on `main/normal`: **238 → 37 ms/frame** —
      fully-transparent objects were composited rather than skipped (`player.resizer.disable` alone,
      a window-sized `alpha="0"` mousetrap, cost **42.8 ms/frame** and `focus.dummy` another 42.0);
      the prescale cache's per-entry cap (4 M px) was smaller than a window background at Retina
      (5.3 M) so the entries that matter missed it and were `.high`-resampled every frame
      (`grid#-` 60.5 → 7.0 ms); `drawTiled` blitted up to 8192 tiles per frame instead of one
      `draw(_:in:byTiling:)`; and `updateSpectrum` invalidated at the audio block rate (~75 Hz).
      Two more found by `sample`-ing the process, which is the durable method lesson — `RENDER_TIME`
      measures `renderer.draw` and nothing else, and neither of these was in it:
      `WasabiObjectGraph.objects(xmlID:)` scanned and sorted every object per call **on the playback
      tick** (~10% of the app's busy time in one lookup), and `layoutNodes()` had no cache at all
      while `resolvedGeometry` — every script `getWidth`/`getLeft` — goes through it.
      Rules: `reference/performance.md` → *Profile the process, don't reason about the frame* and
      *Four ways to pay full price for nothing*; `reference/harness.md` → *Profiling the running app*.
      `swift test` 1104 pass (7 new, `WinampModernPhase60Tests`); 288-image sweep 287 identical for
      the graph caches, and 12 images differing by **maxdelta = 1** for the tiling rewrite (one LSB,
      from a single native tiling pass rounding differently than N individually-rounded blits).
      **Still the biggest thing inside `draw`, and unfixed:** text — `drawText` was 339 of 1148 draw
      samples, with `font(identifier:size:traits:)` alone at 96.

---

## BB23 — The play/pause button stuck in paused — closed 2026-08-24

- [x] **BB23. The play/pause button stuck in *paused*. Fixed 2026-08-24.** Reported as *"the 4 bento
      skins the play pause button gets stuck in paused if used"*. The transport is two overlapping
      buttons (`play.track` / `pause.track`, both `.null`-imaged) plus the `animation.play.pause`
      morph, and `animbutton.maki` swaps them at the end of each handler. Every handler aborted
      three calls earlier: `setAutoReplay` had no signature in the method table, and dispatch fails
      closed on a missing signature, so `play.show(); pause.hide()` never ran and `pause.track` — the
      one declared second — stayed on top for ever. One method (`setautoreplay`, arity 1, written to
      the same `autoreplay` attribute the markup carries) also un-aborts `animbutton_main.maki` (the
      display ring) and `notif_playtopause.maki`. Verified on all four variants headlessly:
      `RENDER_EVENTS=onpause` now leaves `play.track visible=1`, `onresume` puts `pause.track` back.
      `swift test` 732 pass. Skill: `skins/big-bento-modern.md` → BB23,
      `compatibility/maki-surface.md` → *Animated layers*, `reference/harness.md` → the blind-spot
      table (`RENDER_SCRIPTS`'s `failed=` is load-time only).

---

## BB24 — The SUI tab icons were stretched vertically — closed 2026-08-24

- [x] **BB24. The SUI tab icons were stretched vertically. Fixed 2026-08-24, confirmed live.**
      Reported as *"on the 4 bento skins, the icons (browser, library, settings, visualizations,
      playlist) on the vertical tab are vertically stretched"*. Not a renderer defect:
      `tabcontrol.maki` sizes each tab to `4 * label.y + label.getAutoHeight()`, and `getAutoHeight()`
      answered the label's **declared** `h="60"` rather than its font, so every tab came out
      `36 + 60 = 96` — the tab's own height fed back into its own sizing. The 258×58 icon is drawn to
      the tab, hence the 1.66× stretch, and the script's `y + h + 1` stacking drifted the strip 37px
      per tab. Two parts: `getAutoWidth`/`getAutoHeight` now measure before falling back to the
      declared `w`/`h` for `text`/`songticker` (a group still answers from its declared size), and
      `lineHeight(of:)` is `fontsize` — the pixel cell height Winamp hands GDI — rather than a
      CoreText line height, which answered 25 and left the tabs 61 tall and still creeping. Measured
      on all four variants: `RENDER_GEOMETRY=sui.tabs` prints `h=60` at `y=4,65,126,187,248,309`
      against `h=96` at `y=4,101,198,295,392,489` before. `swift test` 1184 pass; the Phase 53
      assertion that `getAutoHeight` prefers the declared height was the assumption this corrects, and
      is rewritten. Skill: `skins/big-bento-modern.md` → BB24, `reference/scripting.md` →
      *`getAutoWidth()` / `getAutoHeight()` measure the string*, `SKILL.md` routing table.
      **Corpus sweep run 2026-08-24: 310 images, 300 identical, 10 changed, no regression.** Four are
      the Bento tab strips (the fix), one is Anexa's `main-shade` (documented as nondeterministic at
      exactly that rect — discount it), and **five are `winampmodern566`, which is the same defect
      fixed a second time in the reference skin.** Its titlebar is
      `<text id="window.titlebar.title" w="50" fontsize="14" bold="1" forceuppercase="1">` — one fixed
      placeholder box for a string that is per-window (`WINAMP`, `VISUALIZER`, `VIDEO`, and
      `:componentname` for the playlist and library) — and `titlebar.maki` centres the title and sizes
      the two streaks either side of it from `getAutoWidth()`. That answered the declared **50** for
      every window regardless of the string; it now answers each string. The five changed scenes are
      exactly the five windows that have a title, and the diff is largest on the longest ones
      (`MLibrary` 84px wide, `Pledit` 86px) and 1–2px on `WINAMP`, which is nearest to 50. The user
      checked the running skin and saw no visible difference, which is the expected result for a
      1–2px titlebar shift; it was measured rather than eyeballed. **The menu bar is not affected** —
      `menugroup.*` reaches its label through `autowidthsource="File.txt"`, and `File.txt` is a
      `<layer>`, so it still answers from the artwork.

---

## BB25 — The Web Reader showed a second, inert toolbar — closed 2026-08-24

- [x] **BB25. The Web Reader showed a second, inert toolbar. Fixed 2026-08-24.** The four variants
      inherit the same `centro.browser` group: its `<Browser id="browserpro.browser">` starts 38px
      below a skin-authored Winamp toolbar. NullPlayer already supplies working browser chrome inside
      the hosted WebKit surface, so the exposed skin row duplicated it without a compatible Winamp
      browser backend. The host now fills the exact shared Bento reader parent with WebKit, covering
      that row without changing any `.wal` file; all other browser elements retain their authored
      frames. Pinned by `WinampModernBrowserTests`.

---

## BB27 — The notifier toast draws a giant, jumbled block of text — closed 2026-08-25

- [x] **BB27. The notifier toast draws a giant, jumbled block of text — fixed 2026-08-25, confirmed
      live across all four variants** (*"now it looks correct across all skins"*). Reported with two
      screenshots; they share one `xml/notifier.xml`. **Four defects, three of them engine-wide.**

      **BB27a — the host clamped the toast to 350px.** `setNotifierText` hard-coded the layout width
      to 350, a value chosen for stock Winamp Modern (`w="128"`, text group 33px, genuinely needs
      widening). Bento declares `w="540"` with a 310px text group, so the clamp *shrank* it to 120px
      of room for 46/34/28pt text — the oversized, clipped first screenshot. 350 is now a floor
      (`max(declared, 350)`), never a size.

      **BB27b — a container's own geometry never reached its window.** The real cause, and not
      Bento-specific. Bento's notifier lays itself out from `notifier.maki`: `onTitleChange` starts a
      30 ms poll, the poll runs the layout routine, and that routine reads its four `Notifications`
      settings, hides the album line or the transport row, moves the text group with
      `setXmlParam(x/w)`, measures the result with `getAutoWidth`, and then **sizes and positions its
      own window** — `container.resize(0, 928, 540, 150)` followed by a `setTargetX/Y/W/H` animation
      to `(1207, 928, 711, 150)`. The engine wrote all four as plain attributes on the container,
      which nothing draws and nothing reads: `resize` forwarded to `layoutResizeRequested` only for a
      *layout* receiver, and the target animation had no container path at all. So the toast stayed
      at its declared 540 with the text pinned in the third of it the XML reserves for the album art
      the script had already hidden — the user's "the space to write is only the middle 1/3, I have
      noticed this on other skins". Fixed with `applyContainerGeometry`, called from `resize` and
      from both target-animation paths, plus a new `containerMoveRequested` callback the controller
      answers by setting that window's frame origin (Winamp's top-left screen space flipped into
      AppKit's, clamped to `visibleFrame`).

      **BB27c — the skin laid out a layout no window shows.** Found when BB27a+b were confirmed
      correct headlessly and the live app was unchanged. `isDesktopAlphaAvailable()` answered **true**,
      and Bento's notifier asks it once, takes `getLayout("desktopalpha")`, and addresses *that* layout
      for the rest of the session — it never switches to it, because in Winamp the container is
      already on it. Nothing here activates a `desktopalpha="1"` layout, so every write landed on a
      layout the window never draws while the app went on showing the untouched `normal` one. That is
      why the headless dump was perfect and the screenshot was not. It now answers false — the way the
      engine actually behaves — and `notifier/normal`, the layout on screen, is the one laid out.
      Deliberately split from `istransparencyavailable` / `istransparencysafe` /
      `islayoutanimationsafe`, which stay true: those are about a window's alpha, this one is about a
      second set of artwork.

      **Measured before/after** (`RENDER_SHOW=notifier RENDER_EVENTS=ontitlechange RENDER_SETTLE=1`):
      before, `notifier/normal` 540×150, 22 nodes, title/artist/album stacked on top of each other
      with the transport buttons drawn through the album line. After, 711×150, 24 nodes: album art,
      the playlist position, the orange title, the artist, and the transport row below it, nothing
      overlapping.

      **BB27d — a `<text>` with no `h` was zero pixels tall.** The overlap itself, and engine-wide.
      The geometry resolver defaulted a missing `h` to 0 and the renderer clips to the frame, so such
      a text drew nothing at all — Bento's `title`, `artist` and `album` are all declared that way.
      The host had been papering over it for the notifier alone (`ensureTextHeight`, `fontsize * 1.4`),
      which is 18px taller than the rows the skin is spaced for, so the title box ran down into the
      artist. A missing `h` on a `<text>` now takes the font's line height as its intrinsic height, in
      `WasabiSceneRenderer.append` beside the existing `autoWidth` case — the same number
      `getAutoHeight()` answers, so a script's measurement and the drawn box are one measurement. The
      host patch is deleted.

      **Not a defect: the *Show Playback Controls* switch.** Reported as "the toggle in settings to
      turn them off does not work". It is a mutually-exclusive pair with *Show Album Tag*, enforced
      by the skin's own `ondatachanged` in `skin.xml` — `if (getData()=="0") { setData("1"); return; }`
      — so unticking it alone is refused and re-ticked, while ticking *Show Album Tag* sets it to 0.
      Measured: `RENDER_SET '…;Show Album Tag=1'` writes `Show Playback Controls = 0` in the same
      dispatch, and the toast then draws the album row and no transport row. The engine reproduces
      Winamp here; what the user was actually seeing was BB27b drawing both rows at once.

      **Harness gaps this exposed, both fixed** — `drive(event:)` had no `onshownotification` (the
      only entry into a notifier script), and `RENDER_EVENTS` measured the scene with no settle after
      driving, so a skin that does the work of an event from a timer the handler starts always read
      as a skin whose handler did nothing.

      - [x] 350 is a floor, not a size.
      - [x] `resize` and the target animation reach a container's window.
      - [x] `isDesktopAlphaAvailable()` answers false.
      - [x] A `<text>` with no `h` is one line tall.
      - [x] Harness: `onshownotification`, a settle after `RENDER_EVENTS`, and a non-empty
            artist/album on the render host — with two of three readouts empty a notifier measures as
            one line and no collision between them is visible.
      - [x] `swift test` — 1235 pass, 0 failures, golden images included.
      - [x] **Confirmed live in all four variants on a track change**, 2026-08-25.
      - [x] Regression tests: `WinampModernPhase69Tests`, 9 cases — the auto-height, the row it used
            to overlap, that only `<text>` auto-sizes, the desktop-alpha answer against its three
            neighbours, both container-geometry routes, that a non-container is not a window, and the
            width floor at 128/350/540.
      - [x] Landed: `reference/rendering.md` (two new sections), `reference/components.md` → *Notifier*,
            `reference/harness.md` (`RENDER_EVENTS` settle + `onshownotification`, and the render
            host's metadata), `skins/big-bento-modern.md` → BB27, CHANGELOG.
      - [x] The other notifier skins checked live too — *"now it looks correct across all skins"*,
            2026-08-25. The container-geometry and desktop-alpha routes are engine-wide, so this was
            the outcome to expect, but it is measured rather than assumed.

---

## BB29 — The left tab bar defects — closed 2026-08-25

- [x] **BB29. The left tab bar: a misplaced divider, a dead switch button, and a notched caption edge
      — fixed 2026-08-25, confirmed live** (*"I just tested the feature it worked"*). Reported on all
      four variants as *"a notch to the right of the icon, these don't look uniform and look like an
      artifact"* plus *"a triangle on the left side between the EQ and settings, and when you mouse
      over it draws a darker line"*.

      **One cause behind the triangle.** The strip's three modes (`Tabs: Hidden` / `Tabs: Icons` /
      `Tabs: Icons + Text`) are a radio group of `cfgattrib`s that `loadattribs.maki` registers with a
      `"0"` default each, and `tabswitch.maki` / `tabcontrol.maki` / `tabbutton.maki` are each a
      three-way `if` with **no `else`**. A profile that has never run the skin therefore reads
      all-zero and runs *none* of them, so `tabs.switch` — the divider, whose `x`, images and tooltip
      the icons branch is what sets — kept its markup `x` of 0 and drew over the left edge of the
      icons, wearing the *open* arrow. Its click was dead for the same reason: `onLeftClick` only
      cycles *between* the three states. Seeded now at load, before the scripts run, keyed on the
      skin's own markup (`WinampModernConfigDefaults`). `RENDER_GEOMETRY=sui.content` prints
      `tabs.switch x=55` (base/Light; `50` on the Windows 10 editions) against `x=10` before.

      **The notch was the captions' last pixel column**, and is independent of the mode: `offsetx=35`
      on a box at `x=4` starts each caption on column 39 of the 40px strip, so `V`/`W` painted one
      bright column and the others only antialiasing — hence "not uniform". A left-aligned string
      whose origin lands in the clip's final column is no longer drawn.

      Corpus sweep 2026-08-25: **310 images, 305 identical**, the 4 Bento `main-normal`s the fix,
      Anexa's known-nondeterministic `main-shade` discounted. `swift test` 1246 pass. Skill:
      `skins/big-bento-modern.md` → BB29, `reference/loading.md` → *A skin's settings must start in a
      state its own scripts can express*, `reference/rendering.md` → *`offsetx` / `offsety` move the
      string, not the box*, `SKILL.md` routing table.

---

## BB32 — The enlarged playlist's album art opened half height — closed 2026-08-26

- [x] **BB32. The enlarged playlist's album art opened half height — fixed 2026-08-26, confirmed
      live** (*"it looks good"*). Reported as *"the cover art in the playlist when setting 'show album
      art if playlist is enlarged' is squashed to half size under the playlist panel when it opens"*.
      The pane measured 120px against the skin's own 335px default, so a square cover was stretched
      across a 330×116 strip.

      **Root cause: `attribute.onDataChanged()` was inert.** The skin applies its stored playlist
      settings at load by calling that handler on itself at the end of `onScriptLoaded`.
      `onDataChanged` had an arity in the method table but was missing from `dispatchableEventArity`,
      so it fell through to a `return .null` — the album-art splitter `playlist.dualwnd` was never
      positioned (it kept its `height="120"` markup seed) and the playlist search box never appeared.
      `onScriptUnloading` then saves `getPosition()` into the skin's own `playlist_cover_poppler`, so
      **the first quit persisted the seed over the skin's 335 default, permanently** — and toggling
      the setting could not recover it, because the collapse branch re-saves before it zeroes.

      **A second defect in the same splitter:** `clampedPosition` read `minwidth`/`maxwidth` first
      whatever the axis, so this horizontal frame's `minwidth="313"` beat its own `minheight="100"`
      and one drag snapped the pane to a 313px floor. The axis's own name now wins, width names kept
      as the fallback ClassicPro's `centro.plframe` relies on.

      Measured on a virgin xctest defaults domain with `WINAMP_MODERN_CALL_TRACE=1`:
      `getposition() on Wasabi:Frame#playlist.dualwnd -> 120` then
      `setprivateint(…,playlist_cover_poppler,120)`; after, `335` on both. `RENDER_SETTINGS` cleared
      the obvious suspect in one line — both attributes read `= 1 (default 1)`, so the settings were
      never wrong, only their application.

      **A profile that ran the old build stays poisoned** — the fix honours the stored value rather
      than second-guessing it. Clear `playlist_cover_poppler` for the affected variants, or drag the
      divider once.

      Blast radius measured before shipping: 7 of 35 skins call `onDataChanged()` as a method (the
      four Bento variants, `winampmodern566` ×19, `S7Reflex` ×5, `Ebonite_2_1` ×4). Before/after
      render sweep of the four affected skins: 39 images, 38 pixel-identical; the one change is
      `winampmodern566`'s `Pledit-normal` moving 2px from its own newly-running handler
      (`setxmlparam(y,16)` on `player.content.pl.dummy.group`) — the settings pass working.

      `swift test` 1270 pass (7 new, `WinampModernPhase72Tests`). Skill: `skins/big-bento-modern.md` → BB32,
      `reference/scripting.md` → *An event handler is also a method*, `reference/rendering.md` →
      *`<Wasabi:Frame>`*, `compatibility/maki-surface.md`, CHANGELOG.

---

## BB33 — The elapsed/total time line was neither level nor apart — closed 2026-08-27

- [x] **BB33. The elapsed/total time line was neither level nor apart — fixed 2026-08-27, confirmed
      live** (*"manual qa looks good"*). Reported as *"the min and sec are not even and the slash is
      not even"* on all four variants, with a screenshot: `0:12/ 4:21`, the `/` sitting higher than
      the digits and the elapsed time running into it.

      Reproduced headlessly in one dump (`RENDER_PROBE main/normal`), which is what separated the two
      causes: `SongTime2`/`SongTime3` measured `frame=(…, 99, 84, 30)` against the separator's
      `(…, 95, 11, 30)` — a 4px vertical offset the markup does not declare — while the elapsed box
      (local `0…84`) and the separator's box (`80…91`) overlap by four pixels *by design*.

      **Cause 1, the 4px: `valign="middle"` is not a spelling Wasabi knows, and an unrecognised value
      reads as `top`.** Only an absent `valign` centres. `RENDER_DISASM=@player-normal-group` showed
      the skin's own correction — `songticker.maki` sets `h=30, y=4` (and `setTargetY(4)`) on both
      time readouts and never touches the separator — and `y=4` is exactly `(30 - 21) / 2` for the
      21px line the font gives at `fontsize="22"`. Read `middle` as `center` and that nudge lands on
      top of a centring already done. Nine declarations corpus-wide, eight of them Bento's.

      **Cause 2, the collision: a clock is a run of fields, not a string.** `WasabiTextMetrics.clockRun`
      now lays a time display out as hours/colon/minutes/colon/seconds with the colon in the cell
      `timecolonwidth` sizes, aligns by the room a two-digit minute needs rather than by what is on
      screen, and keeps clear of the edge it aligns against. The author's own `screenshot.png` is the
      ground truth (§4.7): `0:01 / 0:05` with clearance either side of the `/`, and the elapsed's ink
      ending ~11px inside its box — a digit cell plus the inset.

      Blast radius, before/after render sweep of all 35 installed skins (299 images): 27 changed, all
      of them clock-sized boxes, none broken. It caught one thing the Bento fix alone would have hidden
      — skins declaring a colon cell *wider* than the glyph (Sony Walkman, Styx, T800, Nokia 5220,
      corneramp) drew `1: 13`, so a colon now centres in its cell.

      Skill: `reference/rendering.md` → *A clock is a run of fields, not a string* and the `valign`
      bullet (its "an unrecognised value falls back to `center`" line was wrong), CHANGELOG,
      `WinampModernPhase76Tests`.

---

## B55 — Static skin background disappeared after overnight idle — closed 2026-08-27

- [x] **B55. Static skin background disappeared after overnight idle — fixed 2026-08-27.**
      Reported live on Big Bento Modern as the UI returning in separated pieces with its background
      missing. The `.wal` player is a transparent, layer-backed window, and its steady-state clocks,
      tickers and visualizations deliberately invalidate only their own small rectangles. macOS can
      discard the layer's cached static pixels while the window is occluded, miniaturized or the
      display sleeps; without a full invalidation on return, those moving rectangles can be the only
      regions repainted over the transparent window.

      `WinampModernMainWindowController` now forces a full view-subtree repaint when any primary or
      auxiliary skin window becomes visible after occlusion or minimization. It also observes
      `NSWorkspace.didWakeNotification` as a backstop for display wake that leaves AppKit's window
      occlusion state continuously visible. Hosted `.wal` windows apply the same rule in their own
      delegate. The subtree matters: Big Bento's embedded native surfaces must rebuild their cached
      layers along with the custom-drawn background.

      Regression coverage: `WinampModernBackingStoreTests` verifies that the full repaint reaches
      the root skin view, a hosted surface and a nested control.

---

## B47 — Ratio-aware `.wal` bitmap interpolation — closed 2026-08-27

- [x] **B47. Bitmap scaling now chooses its filter from the effective device ratio.** At an exact
      integer UI Size × backing scale, Winamp Modern artwork is drawn nearest-neighbour so icons and
      one-pixel borders keep their authored pixels; fractional scales remain high-quality smooth,
      and an actual downscale is always smooth so source texels are not dropped. The decision is
      scoped deliberately to `WinampModern`: the user rejected changes to classic and native-modern
      modes while this item was under manual QA.

      The first implementation tested `device destination / source bitmap`, which was subtly wrong:
      a skin is allowed to stretch one asset inside an otherwise integer-scaled UI. The final policy
      reads the CTM basis vectors for the UI/device ratio and separately checks the actual device
      destination only for downscaling. The same answer drives the one-time pre-scale cache and the
      direct draw, so cached and uncached frames cannot disagree.

      Manual QA accepted 2026-08-27 on Big Bento Modern at 100%, 125% and 150%. A reported soft
      WINAMP word was traced to the original 79×15 crop in `window/window.png`: it contains authored
      partial-alpha edge pixels, which nearest correctly preserves. The adjacent hamburger's hard
      edges were crisp. Regression coverage is `WinampModernPhase77Tests`.

---

## B55 — Fallback equalizer in the skin's own frame — closed 2026-08-28

- [x] **B55. The fallback equalizer is the only Modern auxiliary window with no skin chrome.**
      Reported live 2026-08-28 on Defix Hi-End 200: the Spectrum Analyzer materializes inside the
      skin's own `<Wasabi:StandardFrame:…>` (wood bezel, skin artwork) while the equalizer is a flat
      palette slab drawn by `EQView.drawWinampModernNormalMode`. Defix declares no equalizer surface
      and no `EQ_BAND`/`EQ_PREAMP`/`<eqvis>`, so it lands on the classic fallback — correct per the
      routing order, but the equalizer is now the only NullPlayer-owned auxiliary window still on the
      Phase 16 palette path rather than the hosted-window path. The old objection (a synthesized
      `<component guid:eq>` holder resolves to the `drawEqualizerComponent` stub, and the menu route
      and the skin's `TOGGLE Eq` route would then disagree) does not apply to a hosted window, which
      mounts the complete `EQView` inside the skin's frame exactly as Spectrum/Cava/Waveform do.

- [x] Add `equalizer` to `WinampModernHostedWindowID` and a `WinampModernHostedWindowRegistry` entry
      (title, `Skin.baseEQSize` geometry, center-stack policy, `makeSurface`)
- [x] Give `EQView` a hosted mode: `configureForHostedSurface`, no title bar/close/window-drag, the
      content scaled into the holder's bounds, `WinampModernHostedSurface` conformance
- [x] Route `showEqualizer`/`toggleEqualizer`/`isEqualizerVisible` through
      `routeWinampModernHostedWindow(.equalizer, …)` after the surface coordinator declines
- [x] Add the `.equalizer` case to `showClassicHostedWindowForWinampModern` and `centerStackKind`
- [x] Move the compact-mode snapshot, detached-frame capture and frame persistence onto an
      `equalizerWindow` accessor so a hosted equalizer is saved and restored like `spectrumWindow`
- [x] Verify the skin's own `TOGGLE Eq` and the Windows menu reach the same window (by construction:
      `routeComponentToggle` → `componentHost.toggleClassicWindow(.equalizer)` →
      `WindowManager.toggleEqualizer()`, the same entry point the menu item uses)
- [x] `swift test` (1344 passed, goldens included), then live QA on Defix and on a skin that declares
      its own equalizer (the declared/embedded routes must be unchanged). **The 17-skin render sweep
      was not run and was judged unnecessary:** nothing in the scene renderer changed — the diff is
      `EQView`, `WindowManager` routing, and one id plus one registry entry, whose only load-time
      effect is an extra *route descriptor* that materializes nothing until the equalizer is opened
- [x] Land the docs: `reference/components.md` (the never-synthesized note and the hosted-window
      list), `skins/defix-hi-end-200.md`, and move B55 to the backlog archive

      **Closed by moving the fallback onto the hosted-window path** rather than by relaxing the
      never-synthesize rule: `WinampModernHostedWindowID.equalizer` plus one registry entry mounts
      the complete `EQView` inside the skin's standard frame, where a synthesized
      `<component guid:eq>` holder would have mounted the `drawEqualizerComponent` stub. The
      equalizer is therefore the one *component kind* in that registry, and it is reached only after
      the surface coordinator's embedded and declared steps decline; `WindowManager.toggleEqualizer()`
      remains the single door, so the Windows menu and a skin's own `TOGGLE Eq` cannot disagree.

      `EQView` gained a hosted mode — no title bar, close button or window drag, since the frame owns
      all three — and a `Metrics` type that spreads the bands, preamp and buttons across whatever
      width the frame gives it. Drawing and hit testing read the same `Metrics`, and the window takes
      the player's width on first materialization only, so a resized window stays resized.

      Manual QA accepted 2026-08-28 on Defix Hi-End 200 (wood frame, 406 wide, bands filling the
      width). CornerAmp Redux re-checked in the same session: `equalizer=declared:eq` and its own
      275×145 window, unchanged. `swift test`: 1344 passed.
