## The video surface — the picture goes in a **child window**, not a subview (B20)

**15 of the 33 measured `.wal` skins declare a `<container>` for the video component** — chrome, a
`ledstatusbar`, the `VID_*` buttons, and a `<component param="{F0816D7B-…}">` holder — and until B20
every one of them was decoration over an empty box: playing a video opened NullPlayer's own window
somewhere else on screen while the skin's stayed shut.

### Why it is not shaped like `.library`

The obvious shape is the library seam's: move the host's view into the skin's holder. **It does not
survive contact with the video engine.** VLCKit installs its own output view under the player's host
view and sizes *that view's ancestors*, so the skin window's content view ran away at +46pt per
layout pass — measured from 372 to 14,219 in 80ms — and the picture did not appear at all until
something else forced a relayout.

So the surface holds only a **black box the skin lays out**, and
`VideoPlayerWindowController` parks its **own window** over that box with `addChildWindow`. AppKit
gives a child window its own layout tree, so nothing the decoder does can reach the skin's, while the
child follows the parent's moves, hides and closes for free. It is also what answers the lifetime
question: the video window is mode-independent and preserved across `reloadUI`, so parking rather
than owning means a layout switch, a skin switch or a mode switch *unparks* it — still playing —
instead of tearing the player down with the skin.

### The trap that cost the most: a window minimum derived from Auto Layout

`window.setFrame` **silently refuses** any size below the minimum AppKit derives from required
constraints in the window's content, and there is no error — the window simply comes back a different
size. `VideoControlBarView` lays its controls out with a required chain
(`10+30+5+30+5+30+5+30+10+50` leading, `10+30+5+30+5+30+10+50+10` trailing) that sums to exactly
**395pt**, so every parked frame narrower than that was quietly widened and the picture ran out
through the skin's own chrome. **A hidden view's constraints are still live** — `isHidden` does not
help; the bar has to leave the view hierarchy.

Two rules follow, and both are load-bearing:

- **`showsControlBar` adds and removes the bar from its superview**, it does not hide it.
- **The surface gates the bar on the box**: it goes in only when the holder asked for it *and* the box
  is at least `controlBarMinimumWidth` (the bar's own `fittingSize`, not a number written down
  twice). Ask for the frame again straight after the bar leaves — the refusal happened while the
  minimum was still in force.

When debugging any "the hosted thing is the wrong size" report, **compare the frame asked for against
`window.frame` afterwards**. A DEBUG log in `updateHostedOutputFrame` does exactly that
(`video: box … refused, window took …`); it is the line that ended this defect after three wrong
theories.

### The rest of the shape

- **Routing.** `.video` is a **routed** surface but not a **managed** one
  (`WinampModernSurfaceInventory.routedKinds` vs `managedKinds`). Never synthesized — a skin that
  draws no video window is served by the host's own. Never embedded — Winamp Modern's player also
  declares an invisible in-player `windowholder` for the component, and resolving there would leave
  the skin's real video window empty. So the catalog only ever answers `.declaredContainer` or
  `.classicFallback`.
- **`autoopen` / `autoclose`.** Playing reveals the skin's video window; stopping hides it and
  unparks, so no child window is left hanging off a skin window a mode switch may take away.
- **Casting never resurrects a local window.** Every `play*` entry point returns before reaching the
  video controller when a cast device is active, so the skin path is never entered.
- **Fullscreen** unparks first (a child window cannot go fullscreen), and re-parks **one runloop turn
  after** `windowDidExitFullScreen` — AppKit is still restoring the window's own frame as the
  notification lands, and re-parenting inside that leaves it parked at the fullscreen size.
- **The box carries no autoresizing mask** and reports its own geometry (`setFrameSize`,
  `setFrameOrigin`, `viewDidMoveToWindow`) so the parked window follows whatever moves it. Pushing
  placement from the layout pass alone leaves the picture behind on every path that moves the box
  without one.
- **Drag and resize zones are off while parked.** Both belong to the free-floating window; inside a
  skin's box they slide or stretch the picture out of the hole it is filling.
- **`VID_1X` / `VID_2X`** were inert before this (nothing read `presentationSize`). They size the
  *skin's* window so the box is the stream's own pixel size times N, clamped to the visible screen as
  well as the layout's range — Winamp's 1x on a 1080p film is a ~1940pt window, which is faithful but
  must not run off the display.
- **A declared container with no holder** (Hoop_Life_WA3, Media_Whore) routes but has no box;
  `hostVideoOutput()` answers false and the host's own window takes it. That is the correct outcome,
  not a gap.

### The corpus, measured

`cmdbar=` is the holder's `noshowcmdbar=` decoded (`WinampModernVideoHolder.showsCommandBar`).

| Skin | Box (skin px) | cmdbar |
|---|---|---|
| hatsune_miku_5 | 429×340 | 0 |
| Ujola Cat | 390×91 | 0 |
| mmd3 | 375×190 | **1** |
| winampmodern566 | 342×232 | 0 |
| multipass | 332×113 | 0 |
| corneramp_redux | 310×164 | 0 |
| Styx | 284×59 | 0 |
| Itemskin | 277×71 | 0 |
| Anaheim_Player_01 | 240×120 | 0 |
| Love is War Miku | 240×184 | 0 |
| Love Is War Miku V2 | 240×190 | 0 |
| Ebonite_2_1 | 227×172 | 0 |
| BLAKK | 192×125 | **1** |
| Hoop_Life_WA3, Media_Whore | declared, **no holder** | — |

Only mmd3 and BLAKK ask for the command bar, and both boxes are under 395pt, so **no skin in the
corpus actually gets one** — the gate decides every measured case in favour of the picture fitting
its box.

