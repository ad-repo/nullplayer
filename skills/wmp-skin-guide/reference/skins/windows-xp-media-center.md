# `Windows_XP_Media_Center_Edition` (and `…_-_Enhanced_for_XPS9`)

Two archives, one skin. `Windows_XP_Media_Center_Edition.wmz` and
`Windows_XP_Media_Center_Edition_-_Enhanced_for_XPS9.wmz` share `mc.wms`/`mc.js` almost line for
line — the Enhanced release adds `drawer.wav` and `intro.wav` and a few nodes — so **anything found
in one is in the other**, and a report naming "the 2 windows_xp skins" means this pair. Do not
confuse them with `Windows XP.wmz`, which is a different, unrelated skin (`personal.wms`).

## What it is

TheSkinsFactory, 2002, the same house as `Halo 2` and `Blinx` and with the same markup habits. A
243x270 hand-held player: a display in the middle, two sliding drawers of four buttons each, a
transport wheel, and an arc volume/seek pair. Five views — `mainView`, `plView`, `visView`,
`videoView`, `infoView` — and a two-colour scheme (blue / green) the skin swaps by rewriting every
element's `image`/`hoverImage`/`downImage` from a string table in `mc.js`.

## What it exercises that little else does

- **A one-shot GIF whose last frame is a terminator.** Four of them: `shutter_open.gif`,
  `shutter_close.gif` and their `_g` colour twins, 48 frames of 176x135 each, the 48th a 1x1 block
  disposing to background. This is the archetype of the class `WMPGIFTerminator` exists for — **79
  files across 33 archives**.
- **An animated `<SUBVIEW>` at `zIndex="20"` over the whole display**, whose closed state is held by
  a *separate static child* (`shutterStatic`) the same handler toggles. That pairing is the argument
  for the rule: a skin that needed the animation's last frame would not author the static.
- **A dedicated `STATUS:` readout**, `<TEXT id="status" value="wmpprop:player.status">`, one of only
  **7 archives** that bind that path in markup. It is why W162 was found.
- **A view whose intro is a timer state machine**: `timerInterval="1500" onTimer="introAnim()"`,
  which walks shutter → drawers → enable, rewriting `view.timerInterval` at each step. The right
  drawer's `<BUTTONGROUP enabled="false">` is only enabled by `toggleRightDrawer()`, so **every
  control on that drawer, the equaliser button included, is dead until the intro has run.** Settle
  before probing it.

## Defects it found

### W161 — *"the 2 windows_xp skins the eq does not work"* (2026-09-14)

Not an equaliser defect. `introAnim()` assigns `shutter_open.gif` to `shutterSub` and nothing ever
hides that subview; the engine held the GIF's last composited frame, an opaque blue plate, over
`29,32 176x135`. `eqBack` is `47,45 140x108` — **entirely inside it** — so the equaliser opened, its
ten sliders built and drew, and every pixel of them was covered. So were the metadata, the `STATUS:`
line, the elapsed readout and the seek arc. Cause and rule: `WMPGIFTerminator`.

Note what the symptom did *not* say: the EQ button worked the whole time, and the only visible
response to clicking it was the button's own sticky-down artwork changing in the drawer.

### W162 — the blank `STATUS:` line (2026-09-14)

Found immediately after W161, because the readout only became visible once the shutter cleared.
`player.status` was `inert()` and empty in the object model *and* absent from
`WMPObservablePropertyRegistry`, so both resolutions of the path answered nothing. See
`../object-model/reads.md` § *What a property read answers* rule 6.

## What was ruled out

- **The equaliser wiring.** `WMP_RENDER_CLICK` on the EQ button reported
  `eqBack.visible=true … 12 widgets[slider×11 text×1]` and `unrecognised=[]`, and a `DRAG` on `eq1`
  reported `value 1.273 -> 14 follows-pointer=yes thumb-travel=10`. Everything was working headless.
  Confirmed live afterwards: the band holds its raised position across later host settles, which is
  the round trip through `setEQBand:0` and back through the `wmpprop:eq.gainLevel1` binding.
- **`view.timerInterval` being unrecognised.** The compatibility report lists
  `UNKNOWN member view.timerinterval ×6` for this skin, which looks like it would break the whole
  intro. It does not: `COMPAT`/`UNKNOWN` is a **static markup tally** and disagrees with the runtime.
  `WMP_CALL_TRACE=1` with `WMP_RENDER_SETTLE=8` shows `view.timerinterval write value=0 ok` and
  `rightsetbuttons.enabled write value=true ok`. Read the `CALL` lines, not the `UNKNOWN` lines.
- **The GIF being decoded to the wrong frame.** ImageIO composites correctly here; frame 46 and the
  composited frame 47 are both the opaque blue plate. The engine was drawing exactly what the file
  says. The defect was in holding it at all.
- **"The animation must loop."** It must not. `Halo 2`'s 34-frame `m_shutter_open.gif` was made to
  loop once and slammed shut every 3.4 seconds forever — that is W-era history recorded in
  `WMPImageAnimation.loopCount`, and re-opening it is the wrong direction.
- **A green playlist frame beside a blue player.** Looks like a colour-scheme bug and is not: the
  skin resets `gColor` in the view's `onClose`, so it is what a previous session left behind after an
  unclean exit (a `pkill`). Quit the app properly and it clears. `f_close_no.png` being green
  artwork while `f_close_no_g.png` is the other colour is the author's naming, also not a defect.

## How to drive it

Window is 243x270 at its own origin; scene coordinates are window coordinates.

```bash
skills/app-control/scripts/launch.sh Windows_XP_Media_Center_Edition
```

**Wait ~12 s before clicking anything** — the intro runs 1.5 s + 3.4 s and the drawer buttons are
disabled until it finishes, after which `leftSet` sits at `0,55` and `rightSet` at `204,55` (both
`30x109`, both moved from their authored `18,55` / `186,55` by `toggleLeftDrawer`/`Right`).

Mapping-colour centres, decoded from `m_right_map.png` / `m_left_map.png`, as window coordinates:

| Control | Group | Window point |
|---|---|---|
| Equalizer (`eqButton`) | `rightSet` `#0000ff` | `215,69` |
| Playlist (`plButton`) | `rightSet` `#0033ff` | `217,95` |
| Visualizations (`visButton`) | `rightSet` `#0066ff` | `218,121` |
| Change colour (`ColorButton`) | `rightSet` `#0099ff` | `216,148` |
| Skin info (`infoButton`) | `leftSet` `#0000ff` | `17,69` |
| Shuffle / Repeat | `leftSet` `#0033ff` / `#0066ff` | `15,95` / `14,121` |
| Shutter (`shutterButton`) | `leftSet` `#0099ff` | `16,148` |

With the equaliser open (`eqBack` at `47,45`), band *n* is `left = 13 + 12(n-1)`, `top = 29`,
`7x34` — so `eq1` drags from `63,104` to `63,76` in window coordinates.

Headless, remember to settle or the drawer buttons refuse the click:

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/Windows_XP_Media_Center_Edition.wmz \
WMP_RENDER_SETTLE=8 WMP_CALL_TRACE=1 \
WMP_RENDER_CLICK='mainView@215,69;mainView@63,104>63,90>63,76' \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus
```

**`WMP_RENDER_CLICK` cannot see W161 and never could** — the probe answers from the scene graph, and
the equaliser was in the scene graph the whole time, underneath. The instrument for this class is a
`screencapture` of the live window.
