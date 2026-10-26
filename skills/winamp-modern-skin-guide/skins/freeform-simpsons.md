## Freeform Simpsons (`Freeform_Simpsons_Skin.wal`)

*Per-skin notes, not a graded report. Index: [skins.md](../skins.md) · a full report: `/wal-skin-report <skin.wal>`.*

- **Seen:** 2026-10-26, live (intake #3, the user's UI round).
- **The Enable/Hide checkboxes are `embed_xui` wrappers.** `T3:Checkbox` embeds `checkbox.toggle`;
  the skin-level `simpsons.maki` (`options.m`) binds `onActivate` to each wrapper and shows or hides
  a character from it. The event now crosses the seam — [scripting.md](../reference/scripting.md)
  § *A wrapper's activation is its button's* — so ticking a box hides its character (headless:
  `options/normal@44,85` hides the logo).
- **"Hide All" sits under "Enable Homer Dancing" as authored.** The checkbox is at `y="194"` in
  `options.content.visuals`; the button hangs from the box bottom at `y="-110" relaty="1"`. In a
  329px title box they clear only if the content is ≤12px shorter than the box. Our inset (18 top,
  24 total) was retried at 12/12: it cleared this page but pushed BLAKK's, Styx's and Core-X5's first
  rows into their box borders, and no height-only change keeps Panther's bottom-anchored
  "Start Wizard" inside its box. Reported 2026-10-26; the button takes the click there.
- The `wasabi.button.checkbox` bitmaps are Winamp's, not the skin's, so the boxes draw our fallback.
