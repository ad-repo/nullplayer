## Angren Thoron (`Angrenthoron.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen:** 2026-10-25, headless (intake #3).
- **The null content groups are the skin's own leftovers.** Its player, EQ and Thinger frames name
  `player.content.group`, `eq.normal.content.group` and `thinger.content.group`, which no file
  defines (only `pledit.content.group` exists), so `standardframe.maki` gets null for them. Every
  one of those layouts draws its controls directly, so nothing is missing on screen.
- **Time and title overlap as authored.** `xml/player-normal.xml` puts the timer at `x=21 y=17
  w=64 h=24` and the songticker at `x=16 y=16 w=200 h=14` — one box over the other in the
  background's single display band (y≈15–47). The script that might have moved one of them is
  commented out (`<!--script id="main" file="scripts/main.maki" /-->`) and the archive ships no
  `main.maki`; only `standardframe.maki` is present, and there is no screenshot. Reported live
  2026-10-26; Winamp would draw the same from these files, so it stays as authored.
