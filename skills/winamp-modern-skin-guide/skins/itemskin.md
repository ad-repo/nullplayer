# Itemskin

A glass-framed skin whose component windows are built in an unusual way, and the reason B69 exists.
Loads as of Phase 35; its notifier preferences draw as of B66; its frames find their content as of
B69 (2026-08-29).

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
- **`<include file="xml/eq.xml">` names a file the archive does not ship.** Skipped with a warning
  since Phase 35; Winamp does the same. This skin and Overdrive_2 are why B1 was closed.
- **Its compatibility level reads `unsupported` although the skin draws.** The notifier script wants
  `getPath` and `setChecked`; the player is unaffected.

## Knowingly missing

- The library frame's inner `wasabi.frame.layout.mlibrary` group paints a `basetexture` strip over the
  left of the hosted library surface, and the group's background tints the rest of it. Its two layers
  are `stretch="-2"` / `sysregion="-2"` with `w="0"`, so this is a layer-sizing question, not a
  placement one. Open; found during B69's live QA, 2026-08-29.
- Window *regions* are not applied (the `sysregion="-2"` masks describe a hole the chrome window does
  not actually have), which is the same gap Ujola Cat records.
- Nothing beyond the render sweep and B66/B69's live launches has been measured. No
  `/wal-skin-report` run yet.
