# Alpha Media Player X5

`Alpha_Media_Player_X5.wal` · author Dmitry Pozdniakov, version 1.1. In the gold corpus (promoted 2026-10-22).

A full-screen single-window SUI: one `main/fullscreen` layout declared 1024×768 (resized to the
canvas, 1229 wide on a 16:10 panel), with every panel — player, playlist, equalizer, library,
visualization, video — a `visible="0"` group the scripts slide in between two "gate" columns. Built
from its own XUI widgets in `xml/common.xml` (`amp:channel.v`, `amp:handle.v`, `amp:switch`,
`amp:button.main`, …). 17 MAKI programs, no source shipped; no handler fails.

## State (2026-10-21, driven live)

Reported live: *"sliders do not all work. some buttons don't work"*, then *"the switch disappears —
for EQ and mute"*. Three engine defects, all fixed and confirmed in the running app:

- **Bass, treble and volume follow the pointer.** Each slider is a `main.c` layer inside an
  `amp:channel.v` widget, bound by the player script in `mediaplayer.separate`, which clamps the
  press's `y` to the channel's top in *that* group (`v144=128`, `v145=418` for volume). Handed the
  widget-relative point, bass and treble pinned at their top and volume landed 128px off. See
  `reference/scripting.md` → *An XUI widget is not a space of its own*.
- **The EQ and Mute levers stay on their switches.** The player script moves the `crandle` layer with
  `setTargetY(getXmlParam("y") - 17)` for on and `setTargetY(getXmlParam("y"))` for off; it needs the
  declared `y=20` back after the lever has moved. See `reference/scripting.md` → *gotoTarget animation*.
- **Mute stays muted.** Its `onVolumeChanged` consumes a guard on the echo of its own `setVolume`
  and un-mutes on any other; the window's poll announced the skin's change a second time. See
  `compatibility/maki-surface.md` → *A write that changes nothing is not an event*.

The playlist buttons (`pe_add`, `pe_rem`, `pe_sel`, `pe_misc`, `pe_list`) are plain markup actions
and answer. Open File / Open Folder are `eject` / `eject_dir`.

## Not verified

- The round **power** and **refresh** buttons inside the player run their handlers, but what each
  should do was not established.
- The equalizer, library, visualization and video panels were not driven; the EQ panel's ten
  `equaliser.channel.N` sliders use the same widget as the player's, so they should follow the
  same fix.

## Traps

- **Hit-testing in the first second is the background.** The panels slide in from timers after load;
  `RENDER_SETTLE=6` before a headless click, or the press lands on `layer#background`.
- **The window is wider than the layout declares.** Live it opens 1659×1037 pt at 135% for a 1229-wide
  canvas; take skin points from the `WINAMP_MODERN_DRAG_TRACE` `down … point=` line rather than from
  a screenshot.
- **Disassemble by the XML path.** The scripts' source is the XML that declares them
  (`RENDER_DISASM=@mediaplayer.xml`, `@common.xml`), not `maki/*.maki`.
