# Rendering Audion faces

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

This file will own `AudionFaceHostState`, `AudionFaceInteractionState`, `AudionFaceScene` and
`AudionFaceRenderer` — the one draw path the harness and the screen share.

## Sections to come

- *Draw order* — base, animation, time digits, track digits, indicators, buttons, labels; mask last.
- *Images* — nearest-neighbour throughout, integer scale, the button-state precedence.
- *Mask* — `base-alpha` or `inactive-alpha`, anchored bottom-left, never stretched; the decision to
  use `inactive-alpha` while the window is not key (Phase 4).
- *Digits and indicators* — elapsed `mm:ss`, the real track index, NET/MP3/CD/CDDB and play/pause.
- *Text* — CoreText adapted from FaceKit's `draw(text:…)`, mid-string truncation, the marquee
  (80-frame startup, 2 frames per pixel, 60 px gap), Reduce Motion.
- *Departures from FaceKit* — each one, with its oracle classification. The table starts in the
  decision record § *Deliberate departures from FaceKit*.
