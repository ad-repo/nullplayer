## ONYX V2 (`ONYX V2.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `ONYX V2.wal` · 5,120,339 B · SHA-256 `d14b1895a1958b62…` · skin "Onyx" 1.3 by Parisienne17
  (published on DeviantArt as charlene75017)
- **Driven 2026-10-17** (reporter driving, agent instrumenting; fixes in `ad8cd19a`): seek and volume
  in all six layouts, the File Type readout, the mini player's volume bar, and the visualization
  window's placement. Not graded; no `/wal-skin-report` run.

### Shape

Six player layouts in `main`, each a different player, switched by the skin's own buttons
(`4-switches-buttons.maki`, which ships without source): `starter`, `normal` and `normalvis` (the
820×826 big player, mostly a transparent canvas that leaves room for its EQ drawer), `compact` and
`compactvis` (the 790×698 **oval** player — the "Compact Mode" button, the single ▼ in the big
player's corner), and `shadevis` (the 757×548 mini player — "Mini Mode", the double ▼). The skin is
drawn at roughly twice Winamp's usual scale throughout: a 62px standard-frame title bar with a 46px
title font, 62×32 menu-label bitmaps, and a playlist that declares `minimum_w="900"
minimum_h="900"` — that size is the author's, and Winamp would honour it too.

### What it exercises that nothing else did

Every volume and seek control is a **map slider**: an `<AnimatedLayer>` stepped with `gotoFrame`, and
a `Map` image whose pixel value under the click is the new level (`volumebyframe-notext.m`,
`seekanim-popup.m` and their compact/stick copies). The mini player's volume is the region form
instead — `Region.loadFromMap(map, value, 1)` then `setRegion` (`volumebyregion-infoticker.m`).

### What it found

| Symptom | Engine rule | Where it is written |
|---|---|---|
| Seek arc did nothing in any layout | MAKI integer constants were read as 16 bits (3600000 → 61056), sending every track into the over-an-hour branch, which called the missing `integerToLongTime` and aborted the handler before `seekTo` | `reference/scripting.md` → the integer-constant gotcha; `compatibility/maki-surface.md` → *Time is milliseconds* |
| File Type showed the title's tail, then a Plex token for streams | `getPlayItemString` is the item's location; a stream's location drops its query/user info and takes the server's format | `compatibility/maki-surface.md` → `getPlayItemString` |
| Mini player volume bar had no fill | an animated layer whose box is larger than its whole image draws it at its own size | `reference/rendering.md` → *An `<animatedlayer>` is one frame* |
| Visualization floated loose below the player, and as a 67×72 black square in the mini player | `setXmlParam` x/y offset from a layout read is relative to that window; a layout sized 0×0 stays off screen | `reference/scripting.md` → *Writing back the position a window just read* |

### Traps this skin sets

- **The shipped `.maki` does not match its `.m`.** `seekanim-popup.m` calls `integerToLongTime` only
  for tracks over an hour; the archive's bytecode reached it on a 20-minute track, because of the
  constant above. Read `RENDER_DISASM`, not the source, before reasoning about a branch.
- **A click on a map slider can miss on transparent pixels.** The compact layouts' arcs are thin; aim
  from the map and the animation sheet (an opaque pixel of the last frame), never from a screenshot.
- **The compact layouts point volume *and* seek at one 340×214 map (`essai 2.png`)** larger than
  either control. That is the author's — Winamp reads the same pixels — not an engine defect.
- **`pledit.xml` includes `xml/playlistpro.xml` from inside `xml/`**, so it resolves to
  `xml/xml/playlistpro.xml` and is skipped. The file only defines a Big Bento search box whose script
  is not in the archive and which nothing uses; left alone.
- **`skin.xml` includes `xml/windows_menus.xml`** — a typo for `window_menus.xml`, which
  `standardframe.xml` includes correctly — and a `color-presets.xml` that is not shipped.

### Ruled out

- **Window sizes are not an engine defect.** The census matches every declaration: main 820×826,
  playlist 900×900, library 525×350.
- **The title and menu bar are not oversized by the renderer.** `fontsize="46"` drawn under the GDI
  rule measures slightly *under* Winamp's cap height, and the menu labels are drawn 1:1.
- **The oval interface is not locked** — it is the compact layout, reachable from every other one.

### Not measured

- A live stream through the File Type readout: the rule is unit-tested against Plex, Subsonic,
  Jellyfin, Emby and radio URL shapes, not watched on screen.
- The EQ drawer, the playlist search, and the media library window.
