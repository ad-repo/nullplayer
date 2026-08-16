# Winamp Modern (`.wal`) — Phase 13 Handoff

**For:** the agent picking up Winamp Modern work after Phase 13

**From:** Phase 13 (playlist, EQ, and library are now skin-owned surfaces)

**Date:** 2026-08-16

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — the durable guide; Phase 13's architecture is folded in
  (surface routing, pre-graph synthesis, container-scoped callbacks, theme/palette, hosted AppKit)
- `skills/winamp-modern-skin-guide/compatibility.md` — supported surface, the per-skin routing table,
  and what is deliberately inert
- `skills/winamp-modern-skin-guide/manual-qa-checklist.md` — **§4 is the open gate** (see §5 below)
- `TASKS.md` §13 — every step, with what was measured
- `~/.claude/plans/i-want-to-support-frolicking-rabbit.md` Appendix A — the risk register, now with
  R1/R4/R6 closed and R3 partly closed

## 1. What Phase 13 was

Phase 12 left cPro-Bento rendering its body but with the tab content empty, and the Windows menu still
opening classic `.wsz` windows in the middle of a `.wal` skin. Phase 13 made the playlist, equalizer,
and library **surfaces the skin owns**.

Ten commits, one per step, `a18e3798`…`b9ce0805`. 556 → **592 tests**.

| Step | What landed |
|---|---|
| 13.0 | R1: restored-frame clamping + negative-box culling |
| 13.1 | `<component>` recognized as a holder; exact GUID/container classification |
| 13.2 | Pre-graph surface inventory + synthesis of missing windows; xuitag aliases |
| 13.3 | Container-scoped layout callbacks (R6) |
| 13.4 | `WinampModernSurfaceCoordinator` — one catalog for menus, skin buttons, restore |
| 13.5 | Shared `WinampModernThemeCoordinator` + `WasabiPalette` |
| 13.6 | Playlist in the skin's colours and font; `PE_Info`; Delete |
| 13.7 | EQ actions reach the audio; `<eqvis>`; presets menu |
| 13.8 | Typed `WinampModernLibrarySurface` hosting the real browser (R4) |
| 13.9 | Harness assertions + sidecar, docs, register |

Measured routing, all four reference skins:

| Skin | Playlist | Equalizer | Library |
|---|---|---|---|
| cPro-Bento | embedded | embedded (drawer) | embedded (tab) |
| mmd3 | declared `Pledit` | embedded (main-window drawer) | **synthesized** |
| CornerAmp_Redux | declared `Pledit` | declared `eq` | **synthesized** |
| Winamp Modern | declared `Pledit` | embedded | declared `MLibrary` |

## 2. Five things that will bite you if you don't know them

These are the non-obvious findings, in the order they cost time.

**1. The window opened too small because restore wrote over the skin.** Not the UI-Size path — that
only multiplies whatever canvas is current, so it can compound a bad restore but never cause one.
`loadSkin` sizes to the skin's 500×500, then `AppStateManager.restoreWindowFrames` sets the saved
frame verbatim. Proven live by patching a 376×182 frame into `savedAppState` and watching the log.
`MainWindowProviding.clampRestoredFrame` is the seam (a no-op for the fixed-size families).

**2. Winamp defines no equalizer component GUID.** No measured skin contains one. An equalizer is
recognized by its *controls* — `EQ_BAND`, `EQ_PREAMP`, `<eqvis>` — and a synthesized one uses
`guid:eq`. `EQ_TOGGLE`/`EQ_AUTO` deliberately do **not** count: a button that opens the EQ is not an
EQ, and counting it would make every skin look like it already has one.

**3. `EQ_TOGGLE` is not a window command.** It enables and disables *processing*. Ours routed a window
toggle, so ClassicPro's on/off button opened and closed a window and never touched the audio.
Visibility is `TOGGLE guid:eq`, through the coordinator.

**4. Revealing an embedded surface takes both halves of the Wasabi contract.**
`System.onGetCancelComponent(guid, true)` is the event, and ClassicPro *does* handle it — but only
`if (active_tab != 0)`, and its `active_tab` is already 0 at startup, so it concludes it is already
showing the library while `centro.library` has never been shown. The other half is
`windowholder autoopen="1"`: the holder opens its own surroundings. Implemented as
`openHolders(for:in:)`. Dispatching the event alone leaves the tab empty and looks like a rendering
bug.

**5. mmd3 declares `wasabi.standardframe.*` with no `xuitag`.** In real Winamp the standard library
supplies the tag and the skin only overrides the definition. Without the alias, mmd3's playlist window
is a frame that instantiates nothing — 5 scene nodes, a white rectangle. With it, 51.
`registerXUITagAlias` only fills an *unclaimed* tag pointing at an *existing* groupdef, and runs before
the artwork-less shells are seeded, so a skin's own `xuitag=` always wins.

## 3. Architecture you need before changing anything here

**Synthesis is pre-graph, and must stay that way.** `WinampModernSurfaceInventory` walks the expanded
document *before* `WasabiSkinInitializer`, because (a) synthetic XML has to go through the same
registration/validation/instantiation/script-binding passes as the skin's own, and (b) reading the
live graph would mistake cPro's script-built holders for missing surfaces. It declines readily —
ambiguity suppresses synthesis, because a duplicate skin window is a much worse failure than a classic
fallback.

**One catalog, four outcomes.** `WinampModernSurfaceCoordinator` resolves embedded → declared →
synthesized → classic fallback, and `WindowManager`'s `show*`/`toggle*`/`is*Visible` consult it first.
The fallback has its own entry point (`showClassicSurfaceForWinampModern`) because the public toggles
consult the coordinator and would route straight back. **No borrowed provider adapters were created**
— consulting the coordinator inside the existing entry points leaves `playlistWindowController` and
friends nil for skin-owned surfaces, which keeps embedded surfaces out of docking and persistence by
construction and avoids the teardown-ordering hazard an adapter would have added.

**Hosted AppKit content is reconciled from `layout()`, never `draw`.** Creating and adding a subview
inside a draw cycle is a re-entrant hierarchy mutation. A script mutating the graph
(`graphDidMutate`) or switching layout sets `needsLayout`, because a script can create or reveal a
holder. Surfaces are told `prepareForUITeardown()` *before* their view leaves the hierarchy.

**Layout callbacks are container-addressed.** One skin has one runtime and several windows; without
the container id a playlist script resizing itself resized the player. The controller installs both
callbacks **before `scripts.start()`** — a skin that resizes from `onScriptLoaded` does it during
`start()`.

## 4. Verification as it stands

- `swift test` → **592 pass**, 9 opt-in skipped. New: `WinampModernPhase13Tests` (36).
- Release build (`-c release`) compiles — closes **R21**.
- Render harness prints the reconciled catalog and the holders found per layout, writes a
  `surfaces.txt` sidecar beside the PNGs, and asserts the invariants (an embedded surface is never
  also synthesized; an SUI skin is never synthesized into; a synthesized container must have opened).
  It now falls back to the installed engine store, so a cPro dump needs no `WINAMP_MODERN_ENGINE`:

  ```sh
  WINAMP_MODERN_WAL="$HOME/Library/Application Support/NullPlayer/WinampModernSkins/mmd3.wal" \
  WINAMP_MODERN_RENDER_DUMP=/tmp/dump \
  swift test --filter WinampModernRenderDumpTests
  ```

- Verified live by the implementing agent, on cPro-Bento only: Windows → Library Browser routes into
  the skin with no duplicate window; the real browser renders in the Media Library tab against a live
  Plex server; the R1 restore path. DEBUG builds log the resolved catalog at load
  (`WinampModern surfaces [skin.wal]: playlist=… equalizer=… library=…`) and every window resize with
  its cause (`WinampModern R1: resizeWindow(…) reason=…`) — those two lines answer most "why is it
  doing that" questions without a debugger.

- **No reference screenshots are committed** (R20 stays open): every fixture is third-party artwork
  the repo deliberately does not carry. Capture them locally into an ignored directory.

## 5. Open — start here

### A. Live QA (the actual gate)

`manual-qa-checklist.md` **§4 was rewritten for this phase** and is the gate on **R17** and the
Experimental label. Nothing in it has been run by a human. Highest-value unknowns, in order:

1. **EQ audibility from a skin slider** — the round trip is unit-tested against a fake host, but
   nobody has dragged mmd3's band 1 and heard it.
2. **The synthesized library window on mmd3 and CornerAmp** — it renders in the harness with the
   skin's own frame; it has never been opened in the app.
3. **Everything at UI Size ≠ 100%**, especially clicking inside the embedded library at 200%.
4. Mode switching with audio playing, and with a cast active (**R18**).

### B. Group clipping — the open half of R1

At its layout minimum cPro no longer *scrambles* (negative boxes are culled) but still **overlaps**:
the tab strip paints over the transport, because a group does not clip its children — we clip only on
`clipchildren="1"`, while Wasabi's real container windows clip.

Reproduce it in about a minute (no screenshot is committed — these are third-party skin pixels):

```sh
# force an undersized restored frame, then launch and look
python3 - <<'EOF'
import subprocess, json, plistlib
d = plistlib.loads(subprocess.run(["defaults","export","NullPlayer","-"],capture_output=True).stdout)
st = json.loads(d["savedAppState"])
st["mainWindowFrame"] = "{{700, 400}, {376, 182}}"
st["uiScaleLevel"] = "100"
subprocess.run(["defaults","write","NullPlayer","savedAppState","-data",
                json.dumps(st).encode().hex()], check=True)
EOF
./scripts/kill_build_run.sh --debug
```

(Back up `savedAppState` first — the same script without the two assignments prints the original.)
The DEBUG log lines `WinampModern R1: …` show the restore and every resize with its reason.

This was Appendix A's second candidate fix and was deliberately left alone: clipping every group is a
global rendering change that needs its own measured pass across all four skins (compare node counts
and PNGs before/after, the way 13.0 and 13.1 did). **Do that as its own step, not as a drive-by.**

### C. Still open from earlier phases

- **R2** — `wasabi.*` shells render empty. The largest remaining *visual* gap; unfixable without
  artwork we will not bundle.
- **R3 (remainder)** — the playlist and EQ are engine-drawn. They now use the skin's colours and font,
  but not its list bitmaps, scrollbars, or EQ thumbs.
- **R5** — splitter *dragging*; `minwidth`/`maxwidth`/`jump` parsed but unenforced.
- **R9** — stock Winamp Modern still blocks on `clienttoscreenx`, `snapadjust`, `debugstring`.
- **R10/R11/R12** — `XmlDoc` inert; `getCurrentTrackRating` a 0 stub; `WinampConfigGroup` setters absent.
- **R15** — the Phase 11 `drawText` crash is still unreproduced. Phase 13 added a *new* text path
  (`drawSurfaceText`) that deliberately resolves a bitmap-font id to a glyph sheet rather than handing
  it to CoreText, which is the shape of that crash — worth keeping in mind if it recurs.
- **R16** — the harness renders only a skin's initial state.
- **R19/R20** — no GUI profiling; no reference screenshots captured.

### D. A note on method

Two phases running, the discipline that worked was: **measure, change one thing, re-measure across all
four skins.** Every claim in the Phase 13 commits ("5 nodes change", "5 → 51 nodes", "no duplicate
containers") came from a dump diff, not from reasoning. The harness makes that cheap; use it before
and after, and put the numbers in the commit message.
