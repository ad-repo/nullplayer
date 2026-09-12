# The Plus! family

A **family dossier**, not a skin one — the exception the README's "one file per `.wmz`" rule earns,
because every defect found in these archives so far has been an *idiom* shared across several of
them rather than a property of one. A reporter's instinct on 2026-09-12 named it before the engine
did: *"all plus skins seem to have unique issues I suspect they are a different sub family of
skins"*. That is correct, and this file is what it costs to not rediscover it.

## What it is

The 13 archives shipped with **Microsoft Plus! for Windows XP** and **Plus! Digital Media Edition**
(2002), against the WMP 8/9 skin SDK. Installed corpus:

```
Plus! Aquarium      Plus! Hard Boiled    Plus! Nature       Plus! Pulsar      Plus! Space
Plus! Bionic Dot    Plus! HueShifter     Plus! Plasma Ball  Plus! SlimLine
Plus! da Vinci      Plus! Mecha          Plus! Professional Plus!_The_Bionic_Dot
```

`Plus! Bionic Dot` and `Plus!_The_Bionic_Dot` are **two archives of the same skin** (`bionic.wms`,
268 entries; `bionic_d.wms`, 240). A count of "skins affected" that treats them as two is inflated by
one; a fix must still be verified against both, because their node numbering differs.

**All 13 load.** Measured 2026-09-12 with `WMP_SKIN=<corpus dir>`, every one parses
`utf16LittleEndian` and renders every view it declares.

### Two sub-shapes inside the family, and they behave differently

| | Single-view | Multi-view |
|---|---|---|
| Archives | Aquarium, da Vinci, Hard Boiled, HueShifter, Nature, Plasma Ball, SlimLine, Space | Bionic Dot (×2), Mecha, Professional, Pulsar |
| Views | 1–2 | 3–5 (`mainView`, `plView`, `videoView`, `eqView`) |
| Nodes | 53–83 | 137–271 |
| `<EFFECTS>` tag | `WMPEFFECTS` | `EFFECTS` |
| View ids | `view-2`, `eggSkin`, `BubbleSkin`, `hueshifterSkin`, `perfectSkin` | `mainView` + siblings |

**Both spellings of the effects tag live in this family**, which is worth knowing before grepping:
`WMPElementKind` once mapped only `wmpeffects`, and the 166 archives spelling it the other way fell
to `.unknown` and were never widgets (W101).

## What it exercises that little else does

- **Panes hidden by a fade rather than by `visible`.** 7 widget elements in 6 archives sit inside a
  fully transparent subtree; 5 of the 6 are Plus!. Nothing else in the corpus hides a hosted surface
  this way at any scale. Command: see *Fading* below.
- **Containers that shape their children by a mask instead of occluding them with paint.** 2 of the
  corpus's 30 keyed `<EFFECTS>` containers carry a third pixel state, and **both are Plus!** —
  `Plus! Bionic Dot`'s `main_vis_back.png` and `Plus! Professional`'s `vis_mask_s.png`. The family
  names the asset outright: `Egg_Body_Mask.gif`, `body_Mask.gif`, `green_body_MASK.gif`,
  `perfect_tray_shape_mask.gif`, `vis_mask_s.png`.
- **Stacked full-body colour variants cross-faded by script.** Bionic Dot carries seven complete
  `main_body_<colour>.png` bodies plus matching button sets and frame rings, switched by
  `switchThemes(themeID++)` writing `alphaBlend` on each. This is the same mechanism `xsn_sports`
  uses for its window ring (W145) and it is not unique to that skin.

## Defects it found

### W146 — a faded-shut pane was hosted anyway

*"bionic dot spectrum is displaying as rectangle on top of the player and look bad it should be
layered in the opening"*. `alphaBlend` inherits and paint honoured it; hosted `NSView`s did not.
Archived in `docs/wmp-skin/wmp-backlog-archive.md` § *Phase 21*.

**The family-wide shape:** `Plus! Bionic Dot` (×2), `Plus! Professional`, `Plus! HueShifter`,
`Plus! Plasma Ball`, `Plus! Pulsar`, and the non-Plus! `Halloween` — which is almost certainly a
Bionic Dot derivative, on the evidence of an identically named `visMask`/`visEffects` pair.

### W147 — the visualizer was clipped to a rectangle, not the lens

*"the spectrum is just slapped on top of the UI covering controls"*. Same archive entry. The rule
that came out of it is in `../../SKILL.md` § *Drawing the skin's own controls*, and **the guard on it
is Cerulean** — a two-state keyed container means the opposite of a three-state one.

## Ruled out — do not chase these again

- **The dancer is not ours and is not in the archive.** Reference screenshots of Bionic Dot show a
  dancing figure standing in the lens. That is **Plus! Dancer**, a separate Microsoft *Plus! for
  Windows XP* product that overlays a character on top of Windows Media Player; it is not a
  visualization and not a skin asset. Checked 2026-09-12: no Plus! archive contains any
  character/dancer asset. The animated GIFs some of them do ship are unrelated —
  `img_animation_diamond.gif` etc. (Aquarium), `playback_anim.gif`/`vis_animation.gif` (Pulsar),
  `anim_booster_*.gif` (Space). The thin waveform behind the figure in those screenshots is WMP's own
  visualization, which is the slot NullPlayer's effects fill.
- **A stopped Bionic Dot showing no visualizer and a greyed vis button is correct, not a defect.**
  `checkPlayerState()` runs `visMask.alphaBlendTo(0,500)` and `visButton.enabled = false` whenever
  `player.controls.isAvailable("Stop")` is false. Patching the markup *or* the script to force the
  pane open does not open it in the harness — that is the script runtime getting this right.

## Open, measured, unfixed

- **`mediaSwitcherView` renders at 0x0** in `Plus! Mecha` (`future.wms`) and `Plus! Professional`
  (`base.wms`) — 1 node, 0 commands. `WMP_RENDER_APPKIT` reports `SKIPPED canvas=0x0`. Not yet
  investigated; no reported symptom attached to it.
- **`Plus! Space`'s `btnBoosterLeft`/`btnBoosterRight` are unresolved for size**, and they are the
  two buttons whose artwork is `anim_booster_*.gif`. The booster animation is therefore unverified.
- **Unresolved counts on the multi-view mains run 8–10** (Bionic Dot 8, Mecha 10, Professional 8,
  Pulsar 10). Most are the benign population `../harness.md` already names — sizeless `<TEXT>` and
  `<SUBVIEW>` nodes that exist only to carry `toolTip` strings (`plShow`, `plHide`, `toolTipSub`,
  `vidToolTips`, `vidSize*`). **Do not open a row on the count itself**; name the node first.

## The instruments to reach for

```bash
# Which Plus! surfaces are faded shut, and which are shaped by a mask.
WMP_SKIN="$HOME/Library/Application Support/NullPlayer/WMPSkins" \
WMP_RENDER_HOST=playing WMP_RENDER_PROBE=all \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 \
  | grep "WIDGET .*effects" | grep -E "alpha=|mask="
```

`WMP_RENDER_HOST=playing` is not optional for this family. Half of what these skins do is conditional
on `checkPlayerState()`, and the default stopped host shows a legitimately empty player that is
indistinguishable from a broken one. See `../harness.md`.
