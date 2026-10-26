## Abducted (`Abducted.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen:** 2026-10-26, live (intake #3, the user's UI round). Accepted as authored.
- **The "Change Mode" down arrow is dead, as authored.** `normal.button.switch` is
  `action="SWITCH" param="stick"`, but the container's layouts are `normal`, `stick1` and
  `plshade`: the author renamed the stick layout and every loaded script followed (`openstick.m`,
  `stick_botdraw.m`, `Resize2Full.m` all ask for `stick1`); only the button and the unloaded
  `main.m` still say `stick`. The way back (`stick.button.switch`, `param="normal"`) is right.
  A unique-prefix fallback would reach `stick1` and match no other skin in gold/silver/bronze —
  96 skins name a missing layout, nearly all a shade button with no shade layout — but it is not
  evidence of Winamp, so it was declined.
- **The notifier holds for 20s, as authored.** It is the skin's own `opensource_notifier`
  container (not `notifier`, so the host's toast handling does not apply); `opensource_notifier.m`
  fades it in, holds on its `Stay` timer and fades it out. Its unload saves the hold as
  `StayTime*4/1000` against a load of `position/2*1000` ms, so the stored value doubles each
  session (8, 16, 32 …) until `stay.slider`'s `high="40"` clamps it at 20s.
