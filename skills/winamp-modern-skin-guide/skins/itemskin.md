# Itemskin

A glass-framed skin whose component windows are built in an unusual way, and the reason B69 exists.

- **Grade: C (provisional · confidence: low)** — from a headless pass; nobody has driven this skin. Calls 1 unimplemented maki method(s) ×4 (`setchecked`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Known outstanding:**

- 3 bitmap id(s) it references do not resolve, leaving a visible gap: `player.main.extras.textbox.left`, `player.songinfo.stereo`, `player.songinfo.stereomono`
- unimplemented MAKI: `setchecked` ×4
- 2 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 2 error-severity load finding(s)

Loads as of Phase 35; its notifier preferences draw as of B66, on their own background as of B90; its
frames find their content as of B69 (2026-08-29); **its playlist window opens as of B112 (2026-09-04)**;
**its audio is audible as of B111 (2026-09-04)** —
until then it silenced the player, and it is the only skin in the corpus that could.

## The shape of this skin

Fourteen containers, and they come in **pairs**. For each component window there is a *content*
container holding nothing but the component, and a *chrome* container holding the frame artwork:

| Component | Content container | Chrome container |
|---|---|---|
| Playlist | `PLEdit` → `normal`, 6 nodes, `playlist` holder at (33, 55, 264, 45) | `cont.clear.pl` → `layout.clear.pl`, 40 nodes |
| Video | `Video` → `normal`, 6 nodes, `video` holder at (27, 40, 277, 71) | `cont.clear.vd` → `layout.clear.vd`, 15 nodes |
| Library | `MLibrary` → `normal`, 6 nodes, `library` holder at (33, 55, 594, 182) | `cont.clear.ml` → `layout.clear.ml`, 26 nodes |
| AVS | `AVS_window` → `normal`, 6 nodes, `visualization` holder at (27, 40, 277, 71) | `cont.clear.avs` → `layout.clear.avs`, 15 nodes |
| (Devices) | `DLibrary` → `normal`, 6 nodes | `cont.clear.dl` → `layout.clear.dl`, 10 nodes |

Plus `main` (normal / mini / Equalizer), `cont.clear.static`, `opensource_notifier` and
`opensource_notifier_prefs`. The equalizer is **embedded** in `main`'s `Equalizer` layout, not a window.

The content window declares `desktopalpha="0"` and the chrome window `desktopalpha="1"`; the chrome
containers are all `default_visible="0"` and `dynamic="1"`, and the frame script brings its own on
screen with `newDynamicContainer` + `show()`.

The pairing is done entirely by the skin. Each content layout carries one custom standard frame —
`<Wasabi:StandardFrame:PL>`, `:VD`, `:ML`, `:AVS`, `:DL`, declared as groupdefs in `xml/window.xml`
with an `xuitag` and a `scripts/standardframe*.maki`. Each of those scripts:

- `onScriptLoaded` — `newDynamicContainer("cont.clear.<x>")`, `getContainer("<content>")`, resolve both
  layouts, start a 10 ms timer.
- `onTimer` — if the content layout is visible, `show()` the chrome layout and
  `chrome.resize(content.getLeft(), content.getTop(), content.getWidth(), content.getHeight())`;
  otherwise hide it and stop the timer.
- `onMove` / `onResize` **on the chrome** — the same call in reverse, so dragging the frame pulls the
  content window along.
- `onSetVisible` — start or stop the timer with the window.

## Traps this skin sets

- **The chrome window is the visible half, so a window that should be closed is reported as the
  chrome container.** B97's "black panel with `FS`/`1X`/`2X`/`OPTIONS`" is `cont.clear.vd`, but
  nothing opened `cont.clear.vd` — the *host* opened `Video`, and the frame script's `onSetVisible`
  brought its chrome up alongside. Read the pair, not the container that is drawn: the startup catalog
  logging `video=declared:Video` was the correct answer, not the discrepancy it looked like. (B97's
  actual cause was a remembered window state; see
  [`reference/components.md`](../reference/components.md) → *`default_visible="1"`*.)
- **Its PL frame script closes its own content window, and only that one does.** Of the six
  `standardframe*.maki`, `standardframePL.maki` alone answers `onSetVisible(0)` with
  `PLEdit.normal.hide()` *as well as* `cont.clear.pl.hide()` + `Timer.stop()`. That made it the skin
  that found B112: `hide()` writes `visible="0"` on the layout, the host never cleared it when the
  window was reopened, and because the flag also gates the `onSetVisible` walk the frame script was
  never told the window came back — an empty, frameless box with no way to recover. Read the
  bytecode, not the symptom: the missing `cont.clear.pl` looked like a `newDynamicContainer` seam
  (B110) and was not — that call was answered correctly throughout. See
  [`reference/scripting.md`](../reference/scripting.md) → *`onSetVisible` — a window a script closes
  has to be reopened*.
- **Its library now wears the *AVS* frame, and `cont.clear.ml` is dead.** The borrowed-frame pass
  (3edf3765, 2026-09-04) rewrote `MLibrary`'s `Wasabi:StandardFrame:ML` to `:AVS` because the ML
  frame costs rows on every screen for a window whose contents are entirely ours. So a probe that
  expects `MLibrary`↔`cont.clear.ml` reads this skin wrong today: the live pairing is
  `MLibrary`↔`cont.clear.avs`, `AVS_window`↔`cont.clear.avs#2`, and our own hosted windows take
  further copies.
- **Two windows per component is not a defect.** A probe that counts windows, or that expects a
  component window to have chrome of its own, reads this skin wrong. `PLEdit/normal` having 6 scene
  nodes is correct; its 40-node frame is a different container.
- **`getLeft()`/`getTop()` here are cross-window reads.** Both receivers are layouts, so both answer 0
  (their canvas origin), and the write is a desktop coordinate. That mismatch is what left every frame
  parked where the tiler put it while its content sat elsewhere — the whole of B69. The fix is on the
  write; see [`reference/scripting.md`](../reference/scripting.md) → *Writing back the position a
  window just read*. **Do not** make a layout report its desktop position instead.
- **The frame window is the only draggable half.** The content window is a transparent box around a
  component holder and has no handle, so `onMove` on the chrome is the only route the pair moves by.
  It was never dispatched at all before B69.
- **A pinned move must not be clamped on screen.** The tiler had already put `MLibrary`'s right edge
  past the visible frame; clamping the frame window — the only one of the pair a script moves — left it
  82px short of its content, which reads as a rendering offset rather than a placement one.
- **Its notifier preferences point `background=` at a file, not at an id.**
  `<layout background="notifier\config.png">` (`notifier/notifier.xml:98`), written from the skin
  root while the declaration sits in `notifier/`. It is the corpus's only path-form layout background,
  and it is what made this the reported skin for B90 — a layout's background *is* the window's
  backing, so reading only the id form left the whole 300x422 window **82.6% transparent**. Winamp
  takes either form; see [`reference/rendering.md`](../reference/rendering.md).
- **`<include file="xml/eq.xml">` names a file the archive does not ship.** Skipped with a warning
  since Phase 35; Winamp does the same. This skin and Overdrive_2 are why B1 was closed.
- **It is the corpus's only skin that can mute the host, and it did.** `scripts/playerVolumeExtra.maki`
  binds `onToggle` on `volume.mute` and `volume.att` to `setVolume`, and its `onVolumeChanged`
  deactivates both buttons on **every** volume change. They are already off, so in Winamp those writes
  are silent; dispatching `onToggle` unconditionally ran the false branch —
  `setVolume(savedVolume)`, an uninitialised `0` — and `setVolume` re-raised `onVolumeChanged`. The
  host volume went to zero at load, the slider could not lift it, and the zero was persisted. B111
  fixed the rule (`setActivated` notifies only on an actual change); see
  [`compatibility/maki-surface.md`](../compatibility/maki-surface.md) → *A write that changes nothing
  is not an event*. **Reporting note:** the symptom is "audio does not work", the markup is innocent
  (`<Togglebutton id="volume.mute" />` has no image, action or coordinates — a 0×0 object nobody can
  click), and the disassembly is innocent too, because the skin never calls `setVolume` at load.
  `WINAMP_MODERN_CALL_TRACE=1` in the running app is what named it.
- **Its gold list colour is the tell for B113.** Reported 2026-09-04 as *"is there a filter in front
  of the displays?"* — library, playlist and readouts all a dark, muddy olive. Two wrong answers
  before the right one: the skin's first `<gammaset>` is an empty `(default)`, which looks like a
  missing amplification and is not (an empty set named "default" is the author asking for the
  artwork as drawn — 6 corpus skins do it). The real cause was one link of one chain:
  `wasabi.list.text` `80,70,0` is drawn for `wasabi.list.background` **`220,175,0`**, gold, and we
  were painting it on `wasabi.edit.background` `42,42,42` — 1.52:1. **Fixed 2026-09-04**, engine-wide
  (11 corpus skins), see [`../reference/rendering/colour.md`](../reference/rendering/colour.md) →
  *A list plate and a text-field plate are different surfaces*. This skin is also the reason the
  `editBackground` role exists: its settings page is the corpus's best drop-down fixture, and the
  first pass recoloured it gold and then flipped its labels dark-on-dark.
- **Its compatibility level reads `unsupported` although the skin draws.** The notifier script wants
  `getPath` and `setChecked`; the player is unaffected.

## Knowingly missing

- The library frame's inner `wasabi.frame.layout.mlibrary` group paints a `basetexture` strip over the
  left of the hosted library surface, and the group's background tints the rest of it. Its two layers
  are `stretch="-2"` / `sysregion="-2"` with `w="0"`, so this is a layer-sizing question, not a
  placement one. Open; found during B69's live QA, 2026-08-29.
- Nothing beyond the render sweep and B66/B69's live launches has been measured. No
  `/wal-skin-report` run yet.
