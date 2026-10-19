## PiOnNeR_AMP2 (`PionNer_AMP2.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `PionNer_AMP2.wal` · 907,329 B · SHA-256 `da7ce1d26262a3b5…` · author "Marcelo Caetano Martins Muniz", version 2.0 · from archive.org `winampskin_PionNer_AMP2_updated`
- **Measured:** 2026-10-14 · harness `5578de74` — **headless structural pass only**, plus one live look at the spectrum window for #556; see *Not measured*
- **Grade: B (provisional · confidence: low)** — from a headless pass; nobody has used this skin. Everything it declares routes and resolves, and it calls no unimplemented script method. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.
- **Skinned:** `fully-skinned` · compatibility level `degraded` (a diagnostic count, not a quality signal)

**Known outstanding:**

- 1 object a script hooks the mouse on that markup hit-testing rejects (`main/normal` `Layer#popup`)
- synthesis reports `wasabi.standardframe.nostatusbar` as resolving no artwork, so the synthesized playlist and library windows may draw plain — its frame groupdefs paint only through a child `<group id="wasabi.frame.layout">`. Unconfirmed live

**Measured status:**

```
shape        separateWindows, 4 containers (main, Manual, nullplayer.playlist, nullplayer.library), 5 layouts, 148 scene nodes total
main window  419x194 (shade 451x21)
embedded     none
own window   playlist, library (synthesized); Manual (a skin window)
classic      equalizer, video, visualization — the skin declares no equalizer, video, or visualization surface
hosted       11 wear the skin frame, 0 fall back to classic
clickable    1 rejected (main/normal Layer#popup)
scripts      8 programs loaded, 0 reported a failed handler
unsupported  none
artwork      105 resolved, 0 unresolved ids
findings     0 error, 2 warning, 0 info
```

**#556 (2026-10-14, confirmed live on the spectrum window).** One of the two reporting skins for
*"large transparent space at the bottom of the window"*. Its frame states its client as `19,43,-38,-77`
(status) and `23,43,-42,-56` (no status), and paints **no `background=`**: a 43px title band against a
13px bezel. Mirroring the title band onto the bottom left 30px of desktop under every hosted window,
and centring the sides (23 against 19) a 4px column on the right. It now takes the no-status frame at
the skin's own rect — see `reference/components.md` → *A frame that builds its own client still costs
the window*.

### Not measured

No click pass, no motion ladder, no menu walk, and no coverage figure. The only live look was the
hosted spectrum window. Every other number above is a **declaration count from one headless render at
rest** — it says a thing exists, never that it is drawn right or that it responds.
