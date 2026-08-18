# Winamp Modern (`.wal`) — Phase 26 Handoff

**For:** the agent picking up Winamp Modern work after Phase 26

**From:** Phase 26 (the Defix Hi-End 200 live-GUI sweep)

**Date:** 2026-08-18

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — durable versions of every finding: the `findObject`
  paragraph under "Retained graph and coordinates", the `embed_xui` bullet under "Initialization
  passes", the group-clipping paragraph above "The protective window minimum", the `rectrgn` bullet
  under "Hit testing: who owns a point", "A `cfgattrib` control has no `action`", "`TOGGLE`'s
  parameter is a component **or a container id**", "`<AlbumArt>` needs a host that actually has the
  cover", and the equalizer bullet under "Synthesizing a missing window"
- `skills/winamp-modern-skin-guide/skins.md` — Defix's row and its **six** traps
- `skills/winamp-modern-skin-guide/manual-qa-checklist.md` — the Defix section
- `TASKS.md` §26 — the itemised list, including everything still owed
- `~/.claude/plans/winamp-modern-phase-26-test-backfill.md` — **the test plan; start here**

## 1. What Phase 26 was

A live GUI session against `Defix Hi-END 200.WAL`, run from the user's own build. Every finding came
from a bug report on screen, and the tests were deliberately deferred ("defer tests to after manual
qa") — so this phase ships nine behaviour changes with two new assertions and four updated ones. That
debt is real and planned, not forgotten.

699 tests (was 697). No new phase file: findings went where their subject lives, as Phase 23 set the
precedent for.

| Symptom | Cause | Fix |
|---|---|---|
| The SUI body is empty below the tabs | **Not** the inherited "guilist gap" — the body is a `<windowholder>` on the media-library GUID; the dump cannot draw AppKit content | three real defects below |
| Every SUI tab dead | `isMouseOverRect` unimplemented, so each tab's `onLeftButtonUp` aborted | implemented, answered in the receiver's **own** window |
| Tabs light up but switch nothing | the core script holds `sui.content` and asks it for a tab in a **sibling** subtree; `findObject` searched descendants only, so all five lookups were null | `findObject` = subtree, then the container |
| …still nothing | the core script hooks `onLeftClick` on the *group*, and `embed_xui` only placed children | mouse events forward to the embedding group |
| Reels painted over the song ticker | a `<group>` is a window in Wasabi and clips; we clipped only on `clipchildren` | a **declared** box clips |
| Two of the four round buttons dead | `rectrgn="1"` made them eligible, then `object(at:)` alpha-tested the artwork anyway and a click through a gap fell to the panel behind | `rectrgn` skips the alpha test |
| The configurator could not be opened | `TOGGLE param="Config"` names a **container**, which the component registry never matches | fall through to a container-id toggle |
| Every switch in the settings window inert | a `cfgattrib` control carries no `action`; the binding is what it does | flip the value **and dispatch `onDataChanged`** |
| No cover art in any skin | `albumArtwork` defaulted to `nil` and the production host never overrode it | sourced from `NowPlayingManager` — **verified on screen** |
| Windows ▸ Equalizer opened a stub | a synthesized EQ container was treated as skin-owned | the equalizer is never synthesized |

## 2. The two things most worth internalising

**A blank dump is not evidence of a missing feature.** Phase 25 concluded Defix's SUI body was a
`guilist` gap, wrote that into `skins.md`, and this phase inherited it as fact. The body is a hosted
component the harness structurally cannot draw. Two phases pointed at the wrong subsystem because a
PNG was read as a capability report. When a dump is empty, check `HOLDERS` before concluding anything.

**Fix the routing, not one of its ends.** The equalizer took two attempts. The first changed the
*catalog* so the menu resolved to the classic window — and left the synthesized container built, which
`routeComponentToggle` still found, so the skin's own button opened the stub. Two routes reach every
surface (the menu through the catalog, a skin button through `routeComponentToggle`) and a fix that
only satisfies one produces a *worse* bug than the original: two controls that disagree.

## 3. Where the risk is

Three of these are engine-wide rules inferred from one skin, and they are invisible to the render
sweep because hit testing, dispatch, and routing all produce identical PNGs:

- **`findObject`** now searches the whole container. Every skin's script lookups changed shape.
- **`embed_xui`** now forwards mouse events. Guarded to the mouse set, but the guard is untested.
- **`rectrgn`** now skips the alpha test. Bounded to objects that have a bitmap.

The rendering changes *are* covered by measurement: 15 skins rendered before and after with the clock
pinned, 13 byte-identical. Do that sweep for any renderer change — and pin the clock, or animation
noise makes every skin look changed (it did, on the first run).

## 4. What is still open

- The **test backfill** — see the plan. `findObject` first.
- `<Browser>` (Defix's Explorer tab) draws nothing; an embedded web view for untrusted skin content is
  outside the sandbox. Currently a documented gap, not a decision anyone has made.
- `valign` is ignored; `drawText` always vertically centres.
- `default_visible="1"` on an auxiliary container is not honoured.
- Defix's songticker mode lives in **Winamp's** preferences, not the skin's configurator, so nothing
  in this app can reach it. The skin ships it disabled, which is why its ticker does not scroll —
  confirm that reading before "fixing" the ticker.
- The configurator's other pages (31 backgrounds, nine display styles, colour themes) are undriven.

## 5. Harness changes you now have

- `CLICK at` prints the hit object's frame and image. This is what identified an intercepting layer,
  and then a stale-scene artifact that looked exactly like one.
- `CLICK cfgattrib` reports a bound control's value either side of the click.
- The run loop is pumped between driven clicks when `RENDER_SETTLE` is set. Defix gates its tab switch
  on `if (anim.isRunning()) return; anim.start();` — without a pump the timer never releases and only
  the first click in a sequence works, so a working control measures as broken. **Caveat:** the pump
  can also let a timer undo a page switch (the Config window returned to its Style page between
  clicks). Understand that before trusting a long multi-click sequence.
- A mouse position is supplied at the click point, so `isMouseOverRect` answers truthfully.
