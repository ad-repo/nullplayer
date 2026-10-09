# Audion face windows: the face's own, and NullPlayer's beside it

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

This file will own `Windows/AudionFace/` and every gated seam in shared code.

## Sections to come

- *Shared-code seams* — each `WindowManager`, `ContextMenuBuilder`, `AppStateManager`,
  `AppDelegate`, `PlayerUIMode` and `AppCapabilities` change, its gate, and the local alternative
  rejected. Required by the isolation rule; a seam is recorded in the change that adds it.
- *The face window* — borderless and clear; hit test by mask alpha, then control rects, then
  `drag.png`; manual drag through `windowWillStartDragging`/`windowWillMove`/`windowDidFinishDragging`.
- *Sliders* — the volume (19×96) and position (192×19) popups ported from `AudionSliderWindow`.
- *NullPlayer's windows beside a face* — `AudionFacePalette` → `SkinnedSurfaceStyle`, `legible`,
  the route to a track, placement once on first show (`AUDION_PLACE_TRACE`).
- *Docking* — a snap target in `managedWindowRecords`, not a centre-stack member.

The policy these implement is `docs/audion-face/phase-0-decision-record.md` § *Auxiliary-window
policy*.
