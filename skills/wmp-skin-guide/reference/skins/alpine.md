# `Alpine7618_v09`

## What it is

A 2001 car-stereo faceplate ("Alpine Amp", Kid Afrika, beta 0.7). One 517x412 view whose artwork
fills only the bottom ~150 px; the top is transparent and holds four same-size panels (465x322 at
28,10): `VisPanel`, `VidPanel`, `PLPanel` and `EQPanel`, all authored `visible="false"`. The tabs
under the knob open them through `Alpine.js` (`ShowVIS`/`ShowPL`/`ShowEQ`/`ShowVideo`, each with a
`Hide…` twin on a latched `…down` button). CR-only line endings and duplicate attributes (see
`../loading.md`).

## What it exercises that little else does

- **Two `<EFFECTS>` in one view, both live at once**: a 150x26 one in the LCD (175,365) and a 362x211
  one in `VisPanel` (50,72 in the panel). 8 corpus views author two; this is the one reported with
  both showing. Count: a regex scan of every installed `.wms` for `<(wmp)?effects` per `<view`,
  2026-09-25.
- **A host-bound `visible` inside a closed panel**: both effects nodes say
  `visible="wmpenabled:player.controls.stop"`, so they turn on with playback whatever their panel
  is doing.

## Defects it found

- **W301**: *"there is no control for it and the viz shows in 2 places"*. A binding's `true` was read
  as a script show and escaped the hidden `VisPanel` (W263's pass-through), so the panel visualizer
  floated over the transparent top half as soon as a track played.
- **W302**: once W301 was fixed, the open panel showed **black** with its visualizer running
  underneath. Every surface was cut at the earliest split (the LCD's), so `vis_panel.bmp`'s opaque
  black centre went into the overlay above the second surface.

- **W303**: *"you can only drag the main window several inches from the screen top"*. The drag clamp
  and AppKit both measured the 412-tall frame, whose top ~258 rows are empty while the drawers are
  shut. The drawn top is now what reaches the menu bar; see `../windows/placement.md` § *Window placement
  and recovery*.
- **W304**: *"the faceplate text is misaligned in multiple ways"*. The LCD's `fontFace="Quartz"` is
  the archive's own `Quartz.TTF`, never loaded, so it drew in Helvetica; see `WMPSkinFonts`. The
  only corpus archive that ships a font.
- **W305**: `Vol:` read `20.000000000000004` in a 28 px box; `settings.volume` is an integer now.

## What was ruled out

- The big picture is **not** NullPlayer's own visualization window: it is 362x211, which is
  `VisPanel`'s `<EFFECTS>`, at the panel's offset.
- The panel is not missing its control. The tab labelled **VIDEO** is the red `btn_vis_map.bmp`
  band and runs `ShowVIS()`; the film-reel icon to its left is `Vidup` → `ShowVideo()`.

## How to drive it

- Launch: `skills/app-control/scripts/launch.sh Alpine7618_v09`.
- VIS tab (`ShowVIS`, then `HideVIS` on the second click): window origin + **(91, 367)**. The group
  is at 78,333 and red spans x 1-26, y 4-64 in `btn_vis_map.bmp`.
- Checked by eye: capture the window with `winhelper capture-all`, which should be 1034x824 at 2x.
