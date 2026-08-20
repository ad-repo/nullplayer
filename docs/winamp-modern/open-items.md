# Winamp Modern (`.wal`) — Open Items

**Compiled:** 2026-08-19, after Phase 33 · **Audience:** whoever picks this subsystem up next

This is the **tracked** copy and the source of truth. `TASKS.md` (the local, gitignored working
checklist) carries the same list against the phase history it came out of; if the two ever disagree,
this file wins, because it is the one a fresh clone has.

Phases 0A–33 are all closed. Everything below is what survived a walk of every unchecked item left in
`TASKS.md` after Phase 33: each was verified against the current code, and the ones already fixed by a
later phase (`rectrgn`, Layer FX, `getVisBand`'s scale, `colorthemes_switch`, artwork-less
`<Wasabi:Button>`), answered by live QA, or stale were closed there rather than carried here.

Related: `skills/winamp-modern-skin-guide/triage-playbook.md` (how to work the long tail, and §4b's
copy of the head of this table), `INDEX.md` (the per-phase records).

---

## The list

**Ordered by suspected bang for buck** — impact across the measured
17-skin corpus divided by expected effort — not by area. Nothing here is claimed; take the top item.

Measurement basis: the 17 installed `.wal` skins, the render sweep at `RENDER_CLOCK=3`, and the
`action="…"` corpus scan from Phase 33. Skin counts are from those, not estimates.

## Tier 1 — small change, disproportionate payoff

- [x] **B1. Tolerate a missing `<include>` instead of failing the whole skin.** ~~`Itemskin.wal` and
      `Overdrive_2.wal` — 2 of 17 skins — do not load at all~~ — **closed in Phase 35.** Both now
      load and render, so the corpus is 17 skins wide for the first time since Phase 19. It took
      three changes, because each one uncovered the next abort behind it:
      1. the include expander records a **warning** and skips an include naming a file the skin does
         not ship, instead of failing the load — the same tolerance `WasabiSkinInitializer` already
         applies to a missing bitmap, cursor or TTF. Scoped to the skin mount: an include that climbs
         into another mount (`@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml`) is a
         ClassicPro skin whose engine is not installed, and that stays a hard, nameable failure
         rather than a skin that loads and draws almost nothing;
      2. a **script the parser cannot read** is dropped with its diagnostic instead of failing the
         skin, matching what the event dispatch already did for a script that fails while *running*;
      3. `Overdrive_2/scripts/seek.maki` (2001) is written in a **pre-5.0 MAKI layout** under the same
         version word as its four modern siblings: no class GUID table, and 13-byte variable records
         whose trailing `global`/`system` pair is one `object` byte. `MakiBytecodeParser` retries in
         that layout when the strict read fails; a class code that resolves to nothing dispatches by
         method name, and `new` picks a popup menu vs. a generic dynamic object from the method names
         declared against the class. All five of the skin's programs now load and run.
      Residue, both small: Itemskin's notifier wants `getPath` and `setChecked` (which is why its
      compatibility level reads `unsupported` while it renders fine), and Overdrive_2's playlist
      window is the one its skipped `pledit-elements.xml` would have furnished
- [x] **B2. `dblclickaction=` / `rightclickaction=` attributes.** ~~Read nowhere, so `TRACKINFO`
      (6 skins) and `TRACKMENU` (5) are unreachable~~ — **closed in Phase 36.** The corpus scan found
      the demand was more than twice what was recorded: **62 declarations across 9 of the 17 skins**,
      because the same two attributes carry every skin's *winshade* switch
      (`dblclickaction="SWITCH;shade"` — mmd3, multipass, winampmodern566, ZDL, Overdrive_2). Three
      parts:
      1. **Decoding** — `WasabiClickAction` (`WinampModernClickActions.swift`) reads the pair and
         splits the `ACTION;PARAM` spelling that 45 of the 62 uses are written in. The split is
         applied in the view's action switch, so it also serves `action="SWITCHTO;…"`; an explicit
         `dblclickparam=`/`rightclickparam=` still wins, and only the first `;` separates.
      2. **Reachability** — a `<text>` carrying only `dblclickaction` is none of the interactive types
         and has no `action=`, so the hit test never reached it: every song title's click fell through
         to the background layer behind it. `isInteractive` now accepts either attribute. `ghost="1"`
         still outranks both, which is what keeps multipass's ghosted playlist ticker transparent.
      3. **The two commands** — `TRACKINFO` opens a File Info **sheet** for the playing track (never
         `runModal()`: the action is reachable from a script, and a modal loop an untrusted skin can
         enter at will is a hang), `TRACKMENU` opens a track menu — File Info / Copy Title / Reveal in
         Finder — at the pointer. `SYSMENU` keeps the host's main menu; the two are different menus in
         Winamp too.
      Verified with `RENDER_CLICK`, which now prints `CLICK dblclickaction:` / `CLICK rightclickaction:`
      for the object it hits. Residue: winampmodern566's `dblclickaction="WA5:Prefs" dblclickparam="42"`
      is decoded and inert — it addresses a Winamp preferences page we have no dialog for
- [ ] **B3. `PAN` — the balance slider (6 skins).** `updateSlider` already handles `SEEK` and
      `VOLUME`; this is the third case, against `AudioEngine`'s balance. Near-trivial, and it is a
      control the user can see doing nothing
- [ ] **B4. `valign` in `drawText`.** Text is always vertically centred. Defix's songticker asks for
      `valign="top"`, its cassette labels for `center`. Cheap, and text placement is visible in every
      skin — worth a sweep afterwards
- [ ] **B5. The `VIS_*` / `PE_*` / `VID_*` / `CB_*` host actions.** `VIS_MENU`/`_NEXT`/`_PREV`/`_CFG`
      (16 uses), `PE_ADD`/`_REM`/`_SEL`/`_MISC`/`_LIST` (33), `VID_FS`/`_TV`/`_MISC` (14),
      `CB_NEXT`/`_PREV` (12). Each is a few lines against machinery NullPlayer already has, and each
      is a button a user can press. Do them as one batch and re-run the click probe per skin
- [ ] **B6. `default_visible="1"` on an auxiliary container.** Defix's `Config` window opens *with*
      the skin in Winamp; here it is only reachable. The attribute is parsed nowhere — the window
      controller has the seam already (it can force a container visible for the harness)

## Tier 2 — real work, several skins each

- [ ] **B7. Dispatch `onEqBandChanged` / `onEqPreampChanged` (5 skins:** multipass, mmd3, Rika,
      winampmodern566, Overdrive_2**).** Their EQ readouts — multipass's eleven `ledfillbar` bars —
      follow the skin's own drags but not a change made from the menu bar, a preset, or another
      window. Needs a host→script notification on the EQ path, which is the same shape as
      `onVolumeChanged`
- [ ] **B8. The playlist-editor script API** (`getCurrentIndex`, `getNumTracks`, `playTrack`,
      `removeTrack`, `showTrack`, `getMetaData`, …). Defix's known `getcurrentindex` gap is one of
      these; it surfaces on interaction rather than at load, which is why it reads as an intermittent
      defect. Confirm the arities against the MAKI method tables (`RENDER_DISASM`) before implementing
      — a wrong arity desynchronises the interpreter's stack
- [ ] **B9. `onKeyDown` (5 skins:** multipass, Defix, Rika, T800, winampmodern566**).** Needs a
      first-responder seam in the view and a keycode mapping. No reported symptom yet, which is why it
      sits below the rest of Tier 2 despite the skin count
- [ ] **B10. Golden-image regression cover for the render sweep.** The evidence that a rendering
      change does not disturb the other sixteen skins is a **manual** 17-skin sweep — nothing in CI
      catches a third skin regressing, and every rendering phase pays that cost again by hand (this
      one did). Commit synthetic fixtures that exercise group clipping, frame slicing, animated-layer
      framing and text placement, and assert their pixels. Also folds in the Phase 25 regression tests
      (25.1–25.5) that were never written
- [ ] **B11. Defix's configurator, the rest of it** — the 31 backgrounds, the nine display styles, the
      songticker mode. The pages exist and are reachable; they are undriven, and the songticker mode
      is registered only for Winamp's own preferences dialog, so the skin's `Disable = 1` default
      cannot be changed from anywhere (which is why its ticker does not scroll). Includes the harness
      note that a timer can undo a page switch mid-sequence — understand that before trusting a
      multi-click run
- [ ] **B12. `setScale`** — the configurator's seven 100–300% window-scaling buttons are inert.
      Decide first whether it drives our own UI Size or a skin-local scale; the two must not fight

## Tier 3 — narrow, latent, or a decision rather than code

- [x] **B13. The `<vis>` analyzer's scale.** ~~It reads raw levels as a fraction of height~~ —
      **closed in Phase 34**: the analyzer is on `visByte(forMagnitude:)`, the same dB curve
      `getLeftVUMeter` (Phase 29) and `getVisBand` (Phase 30) answer in, so the drawn bars and a
      skin's scripted meters cannot disagree about the same audio. `bandwidth` now picks Winamp's band
      *count* (19 wide / 75 thin) instead of only the bar thickness, and `colorbandpeak` caps are
      drawn. **Still open, split out as B13b:** the other level-reading skins (mmd3's knobs) have not
      been checked for the same over-read
- [ ] **B14. `<Wasabi:TabSheet>`** (mmd3's winshade sidecar) — a real widget, not a shell, so it needs
      a body rather than a synthesis rule. One measured skin
- [ ] **B15. `wasabi.panel` / `wasabi.objectframe.group` bodies.** Every measured use is inside a
      `modal`/`static` frame that synthesis never selects, so there is still nothing on screen to fix.
      Wait for a skin that shows one
- [ ] **B16. `VISCON`** — a container scripts bind to that `RENDER-DUMP containers` never lists. Find
      out why; it may be a probe blind spot rather than an engine gap, and blind probes have made real
      defects look absent three times in this subsystem
- [ ] **B17. `WasabiSurfaceInventory`'s last-wins groupdef map.** The redefined-id defect fixed in
      Phase 19, one layer up. No measured skin is affected — it changes nothing for T800 — so this is
      a correctness tidy-up, not a fix
- [ ] **B18. The classic UI's minimize mask.** `miniaturizeAllManagedWindows` calls `miniaturize(nil)`
      on windows whose masks lack `.miniaturizable`, which is the bug modern's minimize had. Parity
      item, outside the `.wal` subsystem
- [ ] **B19. `<Browser>` (the Explorer tab) — decide and document.** An embedded web view for
      untrusted skin content is outside the sandbox and should almost certainly stay that way. The
      task is to write it down as a permanent, deliberate gap in `compatibility.md` and stop carrying
      it as an open item
