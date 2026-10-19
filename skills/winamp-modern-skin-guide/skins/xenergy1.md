## XENERGY (`XENERGY1.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `XENERGY1.wal` · 538,428 B · SHA-256 `bc0a6d0371094a63…` · author "daniel sioneanu" (also S7Reflex), version 1.0 · from archive.org `winampskin_XENERGY1`
- **Measured:** 2026-10-14 · harness `5578de74` — **headless structural pass only**, plus one live look at the spectrum window for #556; see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Every surface it declares has a home, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 16 bitmap ids `main/normal` references do not resolve: `player.button.repeat.bg`, `player.button.shuffle.bg`, `player.display.bg.*`, `player.display.{left,center,right}` and their overlays, `player.display.songticker.bg.*`, `player.main.effect.l`, `player.main.sd.l`, `player.visualization.background`. The same family of ids S7Reflex (same author) leaves unresolved; whether they leave a visible gap is unconfirmed
- 5 objects a script hooks the mouse on that markup hit-testing rejects (`main/normal`: `mousetrapTabEQ` and the EQ drawer's `EQ_p12`/`EQ_0`/`EQ_m12` buttons among them)

**Measured status:**

```
shape        separateWindows, 4 containers (main, Pledit, MLibrary, nullplayer.about), 4 layouts, 319 scene nodes total
main window  601x280
embedded     equalizer
own window   playlist (Pledit), library (MLibrary)
classic      video, visualization — the skin declares no video or visualization surface
hosted       11 wear the skin frame, 0 fall back to classic
clickable    5 rejected, all in main/normal
scripts      19 programs loaded, 0 reported a failed handler
unsupported  none
artwork      208 resolved, 16 unresolved ids
findings     0 error, 192 warning, 0 info — 189 of them optional `player/*.png` files the archive does not ship, plus an unclosed `<elements>` in `xml/player-elements.xml`, a skipped `window_menus.xml` include, and `wasabi.list.background` declared twice
```

**#556 (2026-10-14, confirmed live on the spectrum window).** The second reporting skin: its frame
states `6,23,-12,-48` (status) / `6,23,-12,-33` (no status) over a `wasabi.frame.basetexture`
background, and mirroring the 23px title band onto the 10px bottom left a 13px strip of that teal
texture under every hosted window. Fixed by keeping the skin's own top and bottom — see
`reference/components.md` → *A frame that builds its own client still costs the window*.

**Stray `<vis>` line below the player (2026-10-17, fixed, confirmed live).** `main/normal`
declares `<vis id="visual">` at 252x1, y=215, outside the 146px the player and closed drawer
occupy, so it drew a flickering line on the desktop. Fixed by bounding a wrapper group's region to
what it holds — see `reference/rendering/hit-testing.md` → *A wrapper group reaches only as far as
what it holds*. The headless dump cannot show it (a 1px spectrum rounds to nothing); measure the
live window's lowest opaque row instead.

**Census trap.** Run alone (`wal_skin_census.sh --corpus <dir with only this archive>`) its log comes
back `damaged` every time: its last `FINDING` line is written without a newline before XCTest's own
`Test Case … passed` line. The capture is complete; splitting that one line and re-running
`--parse-only` gives the row above.

### Not measured

No click pass, no motion ladder, no menu walk, and no coverage figure. The only live look was the
hosted spectrum window. Every other number above is a **declaration count from one headless render at
rest** — it says a thing exists, never that it is drawn right or that it responds.
