#### `<Wasabi:Frame>` — the splitter that builds its own children

Most objects are declared where they appear. A frame is not: it **names** two groups and instantiates
them itself (`WasabiFrame`). cPro-Bento's entire body is one —
`left="centro.components" right="centro.playlist1" from="right" width="200"` — so treating it as an
ordinary group left the library tree, the playlist and the tab strip out of the graph completely.

- `left`/`right` → vertical divider; `top`/`bottom` → horizontal. The pair present decides the axis;
  `orientation=` is written both ways (`vertical`, `v`, `h`) and is not trusted on its own.
- `from` is the edge the divider is measured from (`left`/`top`/`right`/`bottom`, often abbreviated).
  **The pane *opposite* `from` absorbs any extra width**, which routinely reads as a defect on a
  wide window: Big Bento's `from="left"` pins the divider near the left edge and lets the
  right-hand playlist-info pane take the rest, and its `maxwidth="-300"` says so out loud.
  cPro-Bento is the same attribute the other way round (`from="right" width="200"`), which
  confirms the reading. Check `from` before calling a lopsided split wrong.
- The offset is seeded from `width`/`height` and thereafter owned by the `position` attribute, which
  `setPosition()` writes. **On a frame, `getPosition`/`setPosition` are the divider offset**, not a
  slider value — ClassicPro closes its side view with `setPosition(0)` and asks `getPosition()==0`.
- Layout is expressed by writing the panes' *own* geometry attributes, so `WasabiGeometrySpec`
  resolves them like anything else and a parent resize needs no frame-specific code. A pane that
  would go negative collapses to zero instead of flipping inside out.
- The divider is draggable. Its 8px grab strip (`frameDividers()`) takes the resize cursor and wins
  the hit test over whatever is beneath it; a drag rewrites `position` through the same
  `setPosition` path a script uses, so the panes re-lay out and hosted subviews follow.
  `minwidth`/`maxwidth` bound it — skins spell them that way for a horizontal frame too
  (ClassicPro's `centro.plframe`), and a **negative** limit is measured from the far edge
  (`maxwidth="-224"` = "always leave 224px for the other pane"). `jump` (snapping) is not honoured.
  **When a skin declares both spellings, the split axis's own name wins** (BB32): Big Bento's
  `playlist.dualwnd` is horizontal and carries `minheight="100"` beside a leftover `minwidth="313"`,
  and reading the first name found made 313 the floor for a *height* — one drag snapped the
  album-art pane to a third of the window with no way back. The width names stay as the fallback,
  which is all `centro.plframe` ever needed.
- A divider pushed flush with an edge (`setPosition(0)`, how ClassicPro closes its side view) offers
  no grab strip, so a closed split cannot be reopened by dragging where it used to be.

##### Where the user left the divider survives a relaunch — where the *skin* put it does not (B44, 2026-08-24)

Nothing a `.wal` skin's own state amounted to used to survive a quit. The graph is reseeded from the
markup every load and the skin's scripts then re-run their own `setPosition`, so a splitter dragged
wide came back narrow. It stayed invisible for the whole B35–BB22 run because of what it hides: Big
Bento's header analyzers (B43) live past the divider's default column, so on a fresh launch nobody had
ever seen them.

The rule is narrow on purpose. **Only a drag is stored** — `persistFramePosition(of:)` is called from
mouse-up and from nowhere else. A script moving its own splitter is the *author's* layout speaking:
Bento's `setPosition(434)` with `from="left"` genuinely ships "narrow player, wide playlist" and pins
the left pane at 434 however large the window grows, and there is no clamping bug on our side to fix.
Storing that would freeze the opening layout into a preference the user never expressed, and
overriding it outright is not ours to do. This is also why it is **not** a `WasabiSkinQuirks` entry:
that file's bar is *arithmetic the skin gets wrong, derivable from the skin's own numbers*, and this
fails both halves.

- Stored in the skin's existing namespaced configuration (`WinampModernConfiguration`, the same store
  behind `setPrivateInt`) under section `@nullplayer.frames`, keyed **`container-id/frame-id`**. Those
  are the two names that survive a reload; `stableID` is a per-load counter and would address a
  different object next launch. A frame with no `id` is skipped rather than given a positional key a
  markup edit would silently reassign.
- `-1` is the "never dragged" sentinel, because **`0` is a legal stored position**: ClassicPro closes
  its side view with `setPosition(0)` and a user may leave it closed.
- Restored from `layoutNodes()`, not `sceneNodes()` — Wasabi lays a hidden object out anyway, and a
  splitter inside a drawer that happened to be shut at quit still has a position the user set.
- **Also restored on every layout activation**, not only at launch: `persistableFrames()` sees the
  *active* layout only, so a divider dragged in a layout the user switched to later was stored and
  then never put back (B44a).
- The stored offset is **re-clamped against the box as it is now**. A negative `maxwidth` is measured
  from the far edge, so an offset that was legal in a wide window is out of bounds in a narrow one.
- **The ordering trap, and it is the whole difficulty.** The skin's `setPosition` runs at load, so a
  restore has to land after the scripts settle or it is simply stomped — the same trap B38.2 hit. Each
  view restores its own splitters in `scriptsDidStart()`, *before* the seeding resize dispatch, so a
  script whose state is only assigned in `onResize` is told the geometry the user actually left. That
  is enough when the skin calls `setPosition` from `onScriptLoaded`, which is the common case and
  Bento's. It is **not** enough when the call comes from a timer, so the window controller re-asserts
  once at 1.0s — comfortably past the 700 ms one-shot Bento's own `mcvcore` starts (BB9). The
  re-assert **re-reads the store** rather than replaying what it restored, so a divider dragged inside
  that first second is not pulled back to where the window opened.

##### What else the host remembers about a skin, and what it must not (B44a, 2026-08-24)

The splitter is one entry in a short list, and the list is short for a reason: **a skin's own
preferences already survive on their own.** `setPrivateInt`/`setPrivateString` and `cfgattrib` write
straight into the same namespaced store, so anything a skin chose to remember about itself already
works. What the *engine* owns is only what lives in the object graph, which is rebuilt from the markup
on every load. All of it is collected in `WinampModernSkinState`:

| State | Section | Key | Written when |
|---|---|---|---|
| A `<Wasabi:Frame>`'s divider offset | `@nullplayer.frames` | `container-id/frame-id` | mouse-up on the divider |
| Which layout a container is on (shade) | `@nullplayer.layouts` | `container-id` | a `SWITCH` on a control the user clicked |
| Whether one of the skin's windows is open | `@nullplayer.windows` | `container-id` | a menu item, a skin button, a close box |

Two things are deliberately **not** in it. The active colour theme is already persisted by
`WasabiColorThemeList` under `appearance/theme` — check before duplicating it. And a window's frame on
screen belongs to the *player's* window rather than to the skin, so it goes through `AppStateManager`
with everything else the app restores (with `clampRestoredFrame`, R1).

###### …but a `.wal` window's *size* is still the skin's (BB2c, 2026-08-25)

"The frame belongs to the player" is right about the **position** and wrong about the **size**, and
the difference is not cosmetic. A `.wal` window is sized by the skin's layout: Big Bento Modern's
`main/normal` is 1536×878, winampmodern566's is 354×280, and each declares its own resize range.
`AppState.mainWindowFrame` is one global key, so a size saved under one skin was restored under the
next — after the skin had already sized the window correctly, so the restore *won*.

It reads on screen as the skin coming apart into two windows: winampmodern566 anchors its titlebar to
the top and its player bar to the bottom, so at 1536×878 they sit at opposite ends of a near-empty
window. There is no clamp to catch it either, because 566 declares `max=16384x16384` and is genuinely
meant to widen — `clampRestoredFrame` had nothing to reject.

`AppState.winampModernSkinName` records which skin the frame was saved under, and
`AppStateManager.mainFrameForRestore` keeps the saved **origin** while substituting the loaded skin's
**own size** whenever the two names differ. A state written before that key existed decodes as `nil`,
which never matches, so old preferences self-correct on the next launch.

**The same rule was missing on the live mode switch (B49, 2026-08-25).** Launch restore was fixed
here; `WindowManager.recreateModeDependentLayout` was still stamping the *outgoing* mode's whole
frame onto the freshly created target-mode window, so `.wal` (Ebonite, 197×297) → Classic drew the
275×116 classic skin scaled down inside a 197×297 box. Same shape of defect, same fix —
`WindowManager.mainFrameForModeSwitch(outgoing:ownSize:)` keeps the origin and takes the incoming
window's own size — and a test asserts it agrees with `mainFrameForRestore` on the same input, so the
two paths cannot drift. Details in the `ui-guide` skill's live-switch section. **The lesson to carry:
a "keep position, not size" rule has to be applied at *every* point that re-stamps a saved frame**;
fixing the restore path alone left the switch path wrong for months.

Two things worth knowing when this class of bug is suspected again:

- **The dev loop manufactures it.** `kill_build_run.sh` does `pkill -9`, which never writes saved
  state, while `winampModernSkinName` is written the moment a skin is selected. So the frame in
  preferences routinely belongs to a *different* skin than the one that will load.
- **The harness cannot see it.** Scene geometry is correct headlessly (`RENDER-DUMP main/normal:
  354x280` before and after); the defect lives entirely in the window layer. `resizeWindow` logs
  `WinampModern R1: resizeWindow(…) reason=…` in DEBUG, and comparing that line against the window's
  size afterwards is what separates "the skin asked for the wrong size" from "something overwrote it".

The write points are the whole design. **Every one of them is a user gesture**, and a script's
`setPosition`, `switchToLayout` or `hide()` writes nothing — that is the skin describing *this* run.
The layout entry is the one where the distinction takes care: a `SWITCH` click action is a control the
user pressed, while `scripts.layoutSwitchRequested` is the skin's own `switchToLayout` and is
ambiguous (a skin switches its own layout both at load and from its own click handlers), so only the
former records. Restoring a layout is also the one entry **not** re-asserted a second later the way a
divider is: switching layout resizes the window and rebuilds the scene, and doing that a second after
launch would read as the player flinching, so a skin that switches its own layout from a timer keeps
the last word.

##### What outranks a splitter on its own grab strip (BB21, 2026-08-24)

"The cursor changes but it drags the whole window" is the signature of this one, and it is a hit-test
question, not a frame question. A grab strip spans the full height of its frame, so it crosses
whatever the skin laid over that column — cPro's tab strip runs straight through the 8px seam, and a
control the user can see must always win. The old rule was simply "the divider claims the click when
`object(at:)` is nil", and that is too generous: Big Bento Modern covers **every pixel of its window**
with `<layer id="player.resizer.disable" move="1" alpha="0">` plus four alpha-0
`player.mainframe.grabber.mousetrap*` layers laid directly on the seam. The splitter never claimed a
single press, so every drag moved the window while `resetCursorRects` promised a resize.

`renderer.objectOverridingDivider(at:)` is the rule instead. Two things do **not** outrank a splitter:

- **an object the user cannot see** (`alpha="0"`) — a mousetrap, not a control;
- **a surface whose only interactivity is `move="1"`** — window dragging, which is exactly the gesture
  a splitter exists to reinterpret over its own strip. An object that also carries an action, or is a
  button or a slider, keeps its claim.

It applies only inside a divider's grab rect. Big Bento's own `mousetrap3`/`mousetrap4` are
`alpha="255"` and sit *above and below* the strip, so they are untouched — check a blocking layer's
alpha and rect before widening this rule.

