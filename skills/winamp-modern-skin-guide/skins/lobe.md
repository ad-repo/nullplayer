# LOBE

`Lobe.wal` · 605,554 B · SHA-256 `cfc66ef5…9e2e98a7` · author "boostr29", version 1.0.
First measured 2026-08-21 (`/wal-skin-report`, harness `108e4ea5`) — **grade D at measurement,
**C after B27/B28** (confirmed live the same day); confidence medium.
No `screenshot.png` and no readme in the archive, so no reference exists to check semantics against.

A four-pod chrome player: a central body with a seek pod, a component-bucket pod, and two drawers
that slide out. `separateWindows`, four declared containers (`main`, `Color Themes`, `Pledit`,
`Equalizer`) plus the synthesized library. 13 MAKI programs, all of which parse and run — **no handler
fails**. 43 colour themes.

## State

The skin **draws correctly and animates correctly** — the ticker scrolls, the time readout runs, and
both "vis" pods follow the audio (they are `<animatedlayer>` frame strips driven by `vis.maki`, not a
visualization component; Lobe declares neither a `<vis>` box nor an AVS holder). The equalizer window
draws and all ten bands plus preamp follow the host.

It **was** input that was broken. B27 fixed ten of the thirteen dead controls and the reporter
confirmed live 2026-08-21 that they all work. The one whole window that was missing is back (B26).

## What is knowingly missing

- ~~**The About / Colour Themes / manual window does not exist.**~~ — **closed by B26**
  (2026-08-21). Its container declares six layouts (`about1`…`about6`) and none is named `normal`, so
  `WasabiSceneRenderer.init` threw and `setupAuxiliaryContainers` silently `continue`d past it: the
  43-theme picker, the `colorthemes_switch` button and the four manual pages were unreachable by
  every route. A container with no `normal` layout now opens in its **first** one, Winamp's rule, and
  all six pages render (the picker lists 43). Its **Skin Windows** entry reads *LOBE* — the
  container's own `name`. Live verification of the `CT` button and Switch is still owed.
- ~~**13 of 23 main-window controls are dead where a user aims.**~~ — **closed by B27**
  (2026-08-21, confirmed live). Lobe draws every button as a glassy disc whose maximum alpha is
  **79/255**, with the glyph engraved at alpha **3**, and the hit test required `alpha > 8`, so a
  click aimed at the icon fell through to the layer behind it. The region floor is now `alpha > 0`,
  Wasabi's own rule. Ten came alive: `previous`, `stop`, `Close`, `minimize`, `opacscale`, `pl`,
  `ml`, `Repeat`, `Shuffle`, `Crossfade`. **This skin is the diagnosis** — see
  [reference/rendering.md](../reference/rendering.md); `toggle-always-on-top` uses the same artwork
  and always worked, because `rectrgn="1"` skips the test, and that is the control experiment.
- **The seek dial and the volume strip work as of B30** (2026-08-21), reported live as "the volume
  and seek sliders do not work". Neither is a `<slider>`: each is an `<AnimatedLayer>` inside a placed
  group (`seeker` at 210,10 · `cb` at 273,66) whose script samples a `Map` at
  `x - anim.getLeft(), y - anim.getTop()`. We handed the handler the **canvas** point, so the dial
  sampled (213, 26) of a 48×35 map — zero everywhere — and both controls drove 0. Mouse events now
  carry the receiver's **parent-relative** point. Measured: a click at canvas (240, 51) reads
  `getValue(3, 16) = 205` → `seekTo(196.9)` on a 245 s track and the skin's own ticker reads
  *Seek 3:16 / 4:05 (80%)*; (320, 114) on the volume strip reads 61 → *Vol 23%*.
- **The seek dial is live on the ring, dead at its centre, top and bottom** — the 13 frames of
  `seeker.png` are all transparent there, so this survives `alpha > 0`. Faithful: the ring is the
  control, and it is what the script's map is drawn for.
- **The thinger's `cb_prev`/`cb_next` arrows stay unhittable at rest, correctly** — see the traps
  below.
- ~~**The visualization window opens 1200 pt tall.**~~ — **closed by B28** (2026-08-21). Lobe
  declares no visualization surface, so its vis LED opens ours through `toggleProjectM`, and
  `defaultSideWindowHeight` multiplied the skin's own 300 pt canvas by four. The `.winampModern`
  family now measures from classic's 116 pt strip instead — the established 464 pt column at 1× —
  with a screen clamp under it. It was never Lobe-specific: it was every `.wal` skin, and the same
  expression sizes the library window.
- `main/switch`, the compact layout, is **unreachable and abandoned by the author** — settled
  2026-08-21, not an engine gap. A full disassembly of all 13 programs (`RENDER_DISASM=@.xml`, 10,765
  instructions) contains **no layout-switch call of any kind**; the only two `getLayout` calls are
  `sliding`/`sliding2` reaching into `main/switch` to wire its objects. The markup has no
  `SWITCH param="switch"` and no `dblclickaction` anywhere, so the layout's own
  `action="SWITCH" param="normal"` is a way out with no way in. It is also missing 13 bitmaps the
  archive never shipped, which is why it renders as a broken half-drawing.
- Two includes the archive omits (`xml/studio-elements.xml`, `xml/pledit-shade.xml`) and five optional
  bitmaps, all tolerated (B1/Phase 35). The missing `pledit-shade` means no playlist winshade.

## Traps this skin sets

- ~~**`compatibility level=degraded` is a lie here.**~~ — **the count is honest as of B29**
  (2026-08-21). 198 of its 233 findings were `groups/duplicateIdentifier`, every one from Lobe
  including `player-elements.xml` from both `player.xml` and `eq.xml` (and `components-elements.xml`
  from both `about.xml` and `components.xml`) — ordinary Winamp practice. A redefinition now warns
  only when it actually *differs*, and the skin measures **38 findings, 3 of them duplicates**. The
  **level** is still `degraded`, and correctly: the remaining 38 are missing bitmaps and two skipped
  includes, and `.full` means zero findings. Read the findings, not the level.
- **`CLICKABLE` under-reports on Lobe.** It lists only objects a script *also* hooks the mouse on, so
  plain markup buttons — `Close`, `minimize`, `opacscale` — never appear even though they are dead.
  It reported 7; the real count is 13. Drive `RENDER_CLICK` at each control's centre instead.
- **`RENDER_CLICK` reports the topmost *renderable* object, not the rejected one.** Every dead control
  here reads as `hits layer#metalbg` or `hits layer#cblcd` — that is the click falling *through*, not
  a layer stealing it. Check the target's own artwork alpha before theorising about z-order.
- **The `alpha > 0` region floor rests on `ghost="1"`.** Lobe's `*-over.png` / `*-pressed.png` are
  **100 % non-zero alpha** and are drawn directly above each button; they stay out of the way only
  because Lobe marks all of them `ghost="1"`, which `object(at:)` honours before the alpha test. A
  skin that decorates a control with a non-ghost faint overlay is the regression vector for B27, and
  `WasabiRenderer.swift` — every non-ghost `layer` is interactive — is the other half of it. **The
  corpus `CLICKABLE` before/after sweep has now been run** (2026-08-21): 28 skins, 231 layouts,
  124 → 111 rejected-but-scripted objects and **zero rises**, so the vector does not occur in the
  corpus. LOBE itself accounts for two of the three falls (`main/normal` 7 → 1, `main/switch` 4 → 0).
- ~~**`RENDER-DUMP skin windows: ["LOBE"]` over-reports.**~~ — **closed by B26.** It read the raw
  container topology while the app's menu is built from `auxiliaryContainers`, which this container
  never entered; same family as B16, a blind probe making a real defect look absent. The probe now
  applies the same "can a renderer open this?" gate and prints `RENDER-DUMP dropped container:` for
  what it excludes — and this container is no longer excluded.
- The thinger's `cb_prev`/`cb_next` arrows measure as unhittable, and that is **correct**: at rest the
  whole thinger group sits at z-order 10–11, behind `metalbg` at 68. It is a drawer `sliding2.maki`
  slides out.

## Confirmed live

2026-08-21, by the reporter: all ten B27 controls answer in the app.

## Not yet measured

Playlist and library content (no `componentHost` headlessly), the drawers in their slid-out state,
the EQ presets popup, and the complete static method demand of the 13 programs.
