## Winamp Modern (`winampmodern566.wal`) — the stock 5.x skin

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

**Shape of the skin:** separate windows — `main` (354×280) plus declared `Pledit`, `MLibrary`,
`Video`, `AVS`, `winamp.albumart` and `notifier` containers. The main window is **hollow XML**: the
whole client area is built at runtime by `standardframe.maki` from its `content=` XUI param.

### Working

- The frame, the script-built body, the playlist and library windows (Phase 13).
- **The config drawer** — the `CONFIG` button at the bottom right slides it open, revealing the
  equalizer (preamp + 10 bands with the dB scale, ON / AUTO / PRESETS), the crossfade controls, and the
  EQ / Options / Color Themes tab strip. Phase 24; it had never opened in any version.
- **The titlebar** — title centred on the window with a decorative streak flanking it either side, at
  every width. Phase 24, and the last of this skin's error-severity findings: the skin now loads at
  `degraded`, not `unsupported`.
- **Its host-action toolbars** (Phase 39) — 22 declarations, the widest demand in the corpus: the
  playlist window's ADD / REM / SEL / MISC / LIST (and its `PE_LISTOFLISTS`, which opens the same
  menu), the visualization window's Fullscreen / Prev / Next / Menu, and the video window's
  Fullscreen / Options.

### The titlebar streaks: laid out by the script, not by the markup

Worth knowing because it looked for two phases like a *rendering* problem. `titlebar.maki` lays out
all three pieces in one routine — called from `onResize`, `onTextChanged` and `onSetXuiParam` — and
every position is derived from the centred title:

```
titleX  = layout.clientToScreenX((layoutW − title.getAutoWidth()) / 2)   // → window-client space
titleX  = titlebargroup.screenToClientX(titleX) − titlebargroup.getLeft() // → group-local
title.x = titleX                       streakLeft.x  = padTitleLeft
streakLeft.w  = titleX − padTitleLeft  streakRight.x = titleX + titleW + 1
streakRight.w = −(titleX + titleW + padTitleRight + 2), relatw="1"
```

The markup's `x="0" w="95"` / `x="155" relatw="1"` values are only what the streaks wear until that
routine first runs. Two things had to be true before it could:

- **`clientToScreenX`/`screenToClientX` must exist** — they abort the handler otherwise — **and must
  convert relative to the receiver's parent**. Here both objects hang off the layout, so the round trip
  returns the input and the script's own `− getLeft()` is the group correction. See
  `compatibility.md`; the reading is pinned by ClassicPro's call sites, not by this one.
- **`instanceid` must name the instance.** Both streaks are instantiations of one `wasabi.titlebar.streak`
  groupdef and are told apart *only* by `instanceid`. While that was ignored, the script's
  `findObject("wasabi.titlebar.streak.left")` returned null for both, so the streaks kept their declared
  slot while the title centred itself — landing underneath them, reading "WI…". That was the whole of
  the symptom this skin was documented with, and it was never about the streak *geometry*.

Measured after the fix: at 354px the left streak is 20–152, the title 152–202, the right streak
203–309; at 500px they follow the title to 20–225 / 225–275 / 276–455.

- **Colour themes** (Phase 32) — the config drawer's *Color Themes* tab lists all 44, and `Switch`,
  previous and next all work. Its shade-layout arrows target a `<ColorThemes:Mgr>` rather than the
  list; they step the applied theme directly, so they work without it.

- **Its playlist and album-art windows open with the skin, where the skin puts them** (Phase 40).
  `Pledit` is `default_visible="1" default_x="354" default_y="0"` and `winamp.albumart` is
  `default_visible="1" default_x="354" default_y="165" nomenu="1"` — measured from a player declared at
  the origin, so both are placed relative to the player's actual top-left: the playlist beside it, the
  album art under the playlist. This is the skin whose arrangement made `default_x`/`default_y` worth
  reading at all; stacking every window under the player put the album art two windows down from where
  it belongs.

- **Its EQ drawer follows the equalizer** (Phase 41) — `configdrawer.xml` handles both
  `onEqBandChanged` and `onEqPreampChanged`, and they are dispatched now, so the drawer's display
  follows a preset, the menu bar, the classic equalizer window and a restored session as well as its
  own sliders.

- **Its keyboard shortcuts answer** (Phase 43). Five programs bind `System.onKeyDown`, and it is the
  only skin in the corpus whose handlers gate on `isActive()` — a System event reaches every program
  whatever window is focused, so `pledit-normal.xml`'s `Ctrl+W` asks whether *its* window has the
  keyboard before switching that container between `shade` and `normal`. `alt+g` toggles the EQ
  drawer's config attribute (from `player-normal-group.xml`, the same shortcut multipass uses),
  `alt+a` the album-art window (`albumart.xml`). Its `onAccelerator(a, b, c)` — the menu-hotkey
  channel, three string arguments — is a separate event and is still not dispatched.

### Not implemented or knowingly wrong

- The 1px `window.titlebar.title.overlay` layer keeps its declared slot instead of being stretched over
  the title. The script resolves it with `title.findObject("window.titlebar.title.overlay")` — a lookup
  *inside* the title object it just resolved, which finds nothing. Matching Winamp here would mean
  inventing lookup semantics for a 1px decorative sliver; measured and left alone.
- Its EQ drawer's crossfade and EQ buttons shift 14px once `onResize` runs — the layout its own script
  computes, and invisible until the drawer is opened.
- The config drawer's `cb_nextpage`/`cb_prevpage` scroll arrows, and the video window's `VID_1X` /
  `VID_2X` / `VID_TV`, are accepted and inert with a recorded reason (Phase 39): its
  `<componentbucket>` holds no icons here, and our video window has neither native-size sizing nor an
  internet-TV source.

### Role in the implementation

**Compatibility expansion.** Renders: window chrome, menubar, display (timer, song ticker,
bitrate/sample rate, spectrum), transport, sliders. Normal (354×280) and shade (354×25) switch
through script dispatch; resize clamps; theme switching restores. Client area is built at runtime
from the frame's `content=` param
