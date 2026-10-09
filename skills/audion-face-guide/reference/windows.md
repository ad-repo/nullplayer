# Audion face windows: the face's own, and NullPlayer's beside it

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

This file will own `Windows/AudionFace/` and every gated seam in shared code. The policy these
implement is `docs/audion-face/phase-0-decision-record.md` § *Auxiliary-window policy* and
§ *Button mapping*.

## Sections to come

- *Shared-code seams* — each change to shared code, its gate, and the local alternative rejected.
  Required by the isolation rule; a seam is recorded in the change that adds it.
- *The face window* — hit testing, drag, docking
- *Sliders* — the volume and position popups
- *NullPlayer's windows beside a face* — palette, legibility, the route to a track, placement
- *Docking*
