# cPro2 — Styler (Normal / Radiance / Touchscreen)

`cPro2_Styler_by_Victhor.wal`, `cPro2_Styler_Radiance_by_Victhor.wal`,

- **Grade: C (provisional · confidence: medium)** — from a headless pass; nobody has driven this skin. Calls 3 unimplemented maki method(s) ×20 (`enumitem`, `enumobject`, `getnumobjects`); dispatch is fail-closed, so each call abandons its whole handler. A provisional letter is worth about ±1 (see [skin-compatibility.md](../../../docs/winamp-modern/skin-compatibility.md)); a driven `/wal-skin-report` replaces it.

**Known outstanding:**

- 6 hover/pressed-state bitmap(s) do not resolve, so those controls give no visual feedback: `playback.button.mute.over.0`, `playback.button.rep.over.0`, `playback.button.shuf.over.0`, `s.button.mute.over.0`
- unimplemented MAKI: `enumitem` ×2, `enumobject` ×14, `getnumobjects` ×4
- 9 object(s) a script hooks the mouse on that markup hit-testing rejects — they may not respond to a click
- 3 error-severity load finding(s)

`cPro2_Styler_Touchscreen_by_Victhor.wal`, v1.00 — Victhor's 2014 "more than a skin, a project"
release, shipped with 70 PSDs and a replace-the-graphics tutorial. All three are **ClassicPro
`engine="two"`** skins (`load-two_alpha.xml`), so the engine has to be imported; without it the
archive is inert markup. The skins that found B144.

## The shape of these skins

`skin.xml` is nine lines of substance: a `warning.maki` version check, `colors.xml`,
`colorthemes.xml`, and the engine's `load-two_alpha.xml`. Everything else — every window, every
script, the whole info/seeker panel — is the engine's. What makes each variant its own skin is
`ClassicPro.xml`, a `<TextSettings>` block of `<Style id="…">` rows that `read-classicpro.maki`
replays onto named engine objects with `setXmlParam`, plus its artwork and 66 colour themes.

The three differ only in those styles and their bitmaps. Fonts are `century_gothic.ttf` for
everything on the info panel (`cpro2.font.infoseek.*`) and `Gabriola.ttf` for the shade line.

## Traps these skins set

- **`display=` on the info panel's texts is not a display binding — it is the author's right-margin
  knob.** `ClassicPro.xml` says so in a comment: *"Use the display param to move the text away from
  the right side… this is only applicable on the 'timebig', 'bitrate' and 'news'"*. Styler writes
  `display="4"` on the clock and `display="5"` on the bitrate and news rows, and `info-text.m` reads
  them back with `stringToInteger(getXmlParam("display"))`. Touchscreen writes *negative* ones
  (`-2`, `-1`). Anything that treats the attribute as a readout binding, or that refuses an
  unrecognised value, silently moves the whole row.
- **The panel's layout is arithmetic over `getTextWidth()`, with no slack anywhere.** The total time
  goes at `trackTime.getTextWidth() - 4 + 21` inside a box that starts at 21 and is
  `getTextWidth()` wide; the bitrate group is `getTextWidth() + 18` around a right-aligned
  `w="-5" relatw="1"` whose left 20px hold the stereo icon. Measured as the drawn ink, the separator
  lands on the last digit and the bitrate string backs into the icon — B144, and the reason
  `getTextWidth()` carries a +4 box margin. See
  [`../reference/rendering/text.md`](../reference/rendering/text.md) → *`getTextWidth()` carries the
  box's own margin*.
- **The clock's group is 20px and its text box is 22.** `<group id="two.info.text.time" … h="50"
  relath="2"/>` is half the 40px info panel, and the engine's `<text id="two.info.text.tracktime"
  y="1" h="22">` (Styler moves it to `y="2"` and raises the font to 24) overhangs it. There is no
  room for a line drawn even a pixel low, which is what made this the skin that found the vertical
  centring rule — see [`../reference/rendering/text.md`](../reference/rendering/text.md) → *A line is
  centred in the cell the skin declared*.
- **`ClassicPro.xml`'s styles arrive *after* `info-text.maki` has already laid the panel out.**
  `read-classicpro.maki` is declared in a top-level `<scripts>` block in `files-two.xml`, which the
  engine includes after `player.xml` — so the group scripts run first, in Winamp too. The clock row
  recovers because `System.onShowLayout` re-runs its handler; the bitrate row's `updateInfo()` only
  re-runs on `onTitleChange` or its 2s `recheck` timer, so at load its `display` reads `""` and the
  row sits 5px right until the next track change. Cosmetic, not the reported defect, and not fixed.

## The reference

Victhor's project page carries **1:1** Winamp screenshots of all three variants
(`deviantart.com/victhor/art/cPro2-Styler-Skin-project-468424123`). Scale is confirmable from the
artwork: the info panel is exactly 40px tall there and the `channels.2` stereo sprite exactly 13px
wide, matching `infoseek.png`. That is what settled B144 — both numbers in it were read out of those
pixels, not reasoned about. The archive's own `screenshot.png` is a 275x116 marketing thumbnail and
is useless for measurement.

## Knowingly missing

- The song title bleeds sideways out of its box on the Touchscreen variant instead of being cut or
  tickered — B87's widened horizontal clip, not specific to this skin.
- GDI synthesises bold for a face with no bold cut and macOS does not, so every `bold="1"` string
  here draws lighter and ~2px narrower than the reference. Cosmetic.
- No `/wal-skin-report` run yet.
