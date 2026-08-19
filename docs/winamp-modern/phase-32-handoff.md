# Winamp Modern (`.wal`) — Phase 32 Handoff

**For:** the agent picking up `.wal` work after Phase 32

**From:** Phase 32 (colour themes: the picker that never existed)

**Date:** 2026-08-19

Read first:

- `skills/winamp-modern-skin-guide/reference/rendering.md` §*Colour themes* → *The picker* — the
  engine contract this phase added
- `skills/winamp-modern-skin-guide/reference/harness.md` — the new `WINAMP_MODERN_RENDER_THEMES=1`
  probe, which is the only reproducible route to a skin's colour-theme facts
- `skills/winamp-modern-skin-guide/skins.md` — the measured per-skin table this phase re-derived

---

## 0. What this phase was

The *back* half of colour themes had worked since Phase 4: the catalog, the `(4096+v)/4096` gamma
transform, the coordinator that recolours every window at once, the MAKI accessors. What was missing
was everything a user touches. `<ColorThemes:List>` is an **unregistered XUI tag** — the widget lives
inside Winamp, only the tag ships in a `.wal` — so it expanded to a leaf object with no bitmap, which
`isRenderable` rejected (drew nothing) and `isInteractive` rejected (unclickable). Every colour-theme
screen in every skin was an empty box, and the `colorthemes_switch` / `_next` / `_previous` host
actions were unimplemented, with `action_target=` read nowhere in the codebase.

## 1. What was built

- `WasabiColorThemeList.swift` — per-object list state (selection, scroll, seeding), keyed by
  `WasabiObjectID`, modelled on the embedded-playlist row machinery.
- `WasabiRenderer` — `drawColorThemeList`, both hit-test predicates, the public accessors, and
  `actionTarget(of:)`, which resolves `action_target=` with `findObject`'s **wide** semantics (own
  container subtree, then the whole graph).
- `WinampModernMainView` — click to select, double-click to apply, wheel to scroll; the three host
  actions; the popup fallback; the Color-Themes preferences GUID mapped to that same popup.
- `ContextMenuBuilder` / `WindowManager` — a host **Color Themes** submenu, gated on more than one
  theme, for the skins that ship no picker at all.
- An artwork-less `<Wasabi:Button text="…">` is drawn as a bordered label (§5 of the plan). No `.wal`
  ships `wasabi.button.*` art; it lives inside Winamp.

## 2. The measurement, and where the plan's table was wrong

`WINAMP_MODERN_RENDER_THEMES=1` prints, per skin: the catalog; every `<ColorThemes:List>` **in the
graph** with its container and `visible=`; every list in the drawn scene with its resolved frame; and
every `colorthemes_*` action with the object its `action_target` resolves to. Run it over the whole
corpus:

```sh
for w in ~/Library/Application\ Support/NullPlayer/WinampModernSkins/*.[wW][aA][lL]; do
  WINAMP_MODERN_WAL="$w" WINAMP_MODERN_RENDER_THEMES=1 swift test --filter WinampModernRenderDumpTests
done
```

Three corrections to the plan's table, all of them the probe's:

- **Defix ships a real picker** — a `<ColorThemes:List id="picker">` in its `Config` window, under a
  "Color Themes" heading with a `Switch to selected Color Theme` button. The long-standing "its colour
  themes are unreachable" note in `skins/defix-hi-end-200.md` was written before any probe could see
  one. It is now deleted, and the window renders correctly headlessly.
- **multipass ships no list at all.** Its three buttons carry markup actions (`colorthemes_switch` /
  `_previous` / `_next`) whose `action_target="player.colorthemes"` resolves to **nothing** — the group
  is never instantiated. Prev/next work regardless (they step the applied theme); switch takes the
  popup route.
- **Anexa ships no picker** — 11 themes, no list, no action. It belongs with micro, T800 and ZDL in the
  host-menu group, not with the skins that have their own screen.

A **scene-only** probe is not enough and the first version of this one was: a picker usually lives in a
drawer or a window that starts closed, so three skins measured as "no picker" until the probe learned
to walk the whole graph. If you add a probe for a widget, walk the graph *and* the scene.

§0 of the plan asked whether any picker is MAKI-driven rather than markup-driven — the scope risk that
would have needed list-object methods backed in the VM. It is not: every measured picker is markup plus
a host action, multipass included.

## 3. Verified

- `swift test --filter WinampModern` — 338 tests, 0 failures (9 skipped: the fixture-gated ones).
- `WinampModernPhase32Tests` — list populates in document order, row hit test, narrow *and* wide
  `action_target`, the unresolvable target, next/previous wrapping, seeding and scrolling, activation
  persisting to `appearance/theme` across a reload, the empty name list for a skin with no gammasets
  (which is what makes the menu's `> 1` gate correct), and the text button.
- Rendered headlessly and looked at: **mmd3** `ctsbig` (82 rows, applied theme highlighted, the Switch
  button drawn), **CornerAmp** `colorthemes` (5 rows + Switch/Prev/Next), **Defix** `Config` (5 rows +
  its switch button), **Rika** `Message` (10 rows).

## 4. Left open

- **No scrollbar, anywhere.** The renderer has no scrollbar support at all, so a `<Wasabi:Scrollbar>`
  beside a theme list is inert; the wheel is the only way down an 82-row list. Opening scrolled to the
  applied theme is the mitigation. A report of "the theme list's scrollbar does nothing" routes here,
  not to a fresh investigation.
- **Itemskin and Overdrive_2 do not load at all** — `resourceMissing` on `xml/eq.xml` and
  `xml/pledit-elements.xml` respectively. Two of the skins the host menu was built for, and neither can
  be reached until the load failure is fixed. Unrelated to colour themes; not touched here.
- **A script-driven `leftClick()` on a colour-theme button loses the object.** The runtime's
  `actionRequested` callback is `(action, param)` and carries no sender, so such a click falls back to
  "the only list in the scene". That is correct for every measured skin (a scene has at most one list),
  but a skin with two lists in one window driven from a script would misroute; widen the callback if one
  ever turns up.
- **cPro-Bento's list did not appear in the drawn scene** headlessly (it is in the graph, `visible=1`,
  in a drawer that is not open at launch). It is on the manual-QA list.
- The live pass in `manual-qa-checklist.md` §*The colour-theme picker* has not been run yet.
