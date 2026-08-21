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
- [x] **B3. `PAN` — the balance slider.** ~~`updateSlider` already handles `SEEK` and `VOLUME`; this
      is the third case, against `AudioEngine`'s balance~~ — **closed in Phase 37.** The corpus scan
      puts it at **8 declarations in 7 of the 17 skins** (multipass ships two — a real slider and a
      ghosted LED twin over the same rect), all horizontal, none declaring `low`/`high`. Three parts:
      1. **The drag** — `WinampModernPanAction` converts between the engine's −1…+1 balance and the
         slider's 0…1 position, and both edges go through it, so the thumb and the drag cannot
         disagree about where the centre is.
      2. **The thumb** — the renderer values a `PAN` slider from `host.balance`, not from its own
         `value=`, which is what makes a balance changed anywhere else move the skin's slider (and
         what keeps multipass's two stacked balance sliders showing the same position). Before this
         every balance slider in the corpus drew its thumb pinned at hard left.
      3. **`onSetPosition` on a drag** — Wasabi moves the object's own 0…255 position when the user
         drags it and tells the skin; nothing in the view did either, for *any* slider. Skins hang
         their only feedback off that handler: multipass prints "Balance: Left +40%" on its song
         ticker from it and nowhere else. Only an actual change notifies, as in Wasabi — skins pair
         sliders that write each other's position from their own handler.
      Residue: `AudioEngine.balance` is deliberately not persisted, so a skin's balance slider starts
      centred on each launch, as the rest of the app does
- [x] **B4. `valign` in `drawText`.** ~~Text is always vertically centred. Defix's songticker asks
      for `valign="top"`, its cassette labels for `center`~~ — **closed in Phase 38.** The corpus scan
      puts it at **63 declarations across 9 of the 17 skins** — 54 `top`, 8 `center`, 1 `bottom` —
      and it is not only Defix: every readout on Nokia 5220's screen and multipass's whole display
      ask for `top`. Three parts:
      1. **The attribute** — `WasabiTextMetrics.VerticalAlignment` decodes it and answers one offset
         down from the box's top edge. `center` is the default *and* the fallback for anything
         unrecognised, because that is what Wasabi does with a value it does not know.
      2. **The Core Text path** — the inset that used to be `(height − cell) / 2` is now that offset,
         still clamped at zero so a string taller than its own box starts at the top rather than
         above it.
      3. **The bitmap-font sheet path** — which was pinned to `frame.minY`, i.e. `valign="top"` and
         nothing else. Every sheet-drawn readout that asked for nothing (and every playlist row
         NullPlayer draws into a skin's own list) therefore sat half a box too high; those now centre.
         Clamped and rounded: a sheet whose glyphs are taller than the box keeps their tops (which is
         what leaves Love is War Miku's preferences labels exactly where they were), and a run lands
         on a whole pixel so an LED readout is not resampled into a blur.
      Verified with a 17-skin render sweep, before and after: **16 of 122 rendered images changed,
      across 10 skins**, and a per-pixel diff mask confirms every one of them is text moving — no
      artwork, geometry or animation frame shifted. (Anexa's `main-shade` also differs run to run on
      its own: the clock face reads wall time.)
      Residue: `<Wasabi:Text>` (3 declarations, Anexa) is a XUI type we do not draw as text at all,
      so its `valign` is moot until that type renders; `valign` on a `<layer>` (mmd3, ZDL) is inert
      here as in Wasabi
- [x] **B5. The `VIS_*` / `PE_*` / `VID_*` / `CB_*` host actions.** ~~`VIS_MENU`/`_NEXT`/`_PREV`/`_CFG`
      (16 uses), `PE_ADD`/`_REM`/`_SEL`/`_MISC`/`_LIST` (33), `VID_FS`/`_TV`/`_MISC` (14),
      `CB_NEXT`/`_PREV` (12)~~ — **closed in Phase 39.** The corpus scan puts the demand higher than
      recorded: **108 declarations in 11 of the 17 skins** (`VIS_*` 27 in 5, `PE_*` 39 in 7, `VID_*`
      28 in 5 — the count had missed `VID_1X`/`VID_2X` entirely — and `CB_*` 14 in 4). Decoded in one
      place (`WinampModernHostAction`), so what we answer and what we do not is a list rather than a
      scattering of `case` labels. Four parts:
      1. **`VIS_*`** — `VIS_NEXT`/`VIS_PREV` step *the visualization the user is looking at*: the
         visualization window's presets when it is open (which is what Defix's Previous/Next pair
         beside a Presets button is asking for), otherwise the mode of the skin's own `<vis>` boxes,
         analyzer → oscilloscope → off, written to **every** `<vis>` in the graph so a skin's other
         layouts are not left on the mode the user just stepped away from. `VIS_MENU` is that list
         plus the host's Visualizations menu; `VIS_CFG` the options of the current one; `VIS_FS`
         opens the visualization window fullscreen.
      2. **`PE_*`** — Winamp's five playlist menus, against the shared `AudioEngine`: the same calls
         the classic playlist window's ADD/REM/SEL/MISC/LIST buttons make. `PE_LISTOFLISTS` is the
         same menu as `PE_LIST`.
      3. **A multi-row selection**, which `PE_SEL`'s Select All / Invert and `PE_REM`'s Crop need and
         the embedded playlist did not have: `playlistSetSelection` / `playlistRemoveRows` on the host
         seam, `selectedRows` on the snapshot (defaulted from the anchor, so every existing caller
         and test is unchanged), and the renderer highlights all of them. `selectedIndex` is still the
         anchor a click, the Delete key and a script mean by "the selection".
      4. **`VID_FS` / `VID_MISC`** — the video window's fullscreen and **its own context menu** (audio
         and subtitle pickers included), popped under the skin's button. Both inert with no video
         window: there is nothing to make fullscreen, and an empty one is a black rectangle.
      Three families are **accepted and inert with a recorded reason** rather than approximated:
      `VID_1X`/`VID_2X` (nothing in our video window reads a native size to scale from),
      `VID_TV` (no internet-TV source) and `CB_*` (a `componentbucket` here holds no icons to
      scroll) — each records itself once in the skin's diagnostics, so the demand shows up in a
      compatibility report instead of reading as a dead button of unknown cause.
      Verified with the click probe, which gained a **`CLICK markup action:`** line for exactly this:
      a plain toolbar button has no script, so its seven handler counts are all zero and its `action=`
      *is* its whole behaviour — the probe could not see it at all. micro's five playlist buttons,
      Love is War Miku's four VIS and five VID buttons now report the family that answers them
      (`host=playlistAdd`, `host=inert(no internet TV source in NullPlayer)`, …). 17 new unit tests.
      Residue: presenting an `NSMenu` runs AppKit's own tracking loop, so the menus themselves are
      covered by their commands' tests and not headlessly, the same boundary Phase 36 drew
- [x] **B6. `default_visible="1"` on an auxiliary container.** ~~Defix's `Config` window opens *with*
      the skin in Winamp; here it is only reachable. The attribute is parsed nowhere~~ — **closed in
      Phase 40.** The corpus scan puts the demand at **10 containers in 8 of the 17 skins**, not one:
      Defix's `Config` *and* its `pledit`, winampmodern566's `Pledit` + `winamp.albumart`, Ujola Cat's
      `PLEdit` + `ujolaCat`, ZDL's `EQ` + `thinger`, Overdrive_2's `Pledit`, plus the two suppressed
      cases below. Four parts:
      1. **The attribute** — decoded in `WinampModernContainerTopology` with everything else a
         container declares (`opensByDefault`), applied by the controller right after
         `scriptsDidStart()` so a window that opens at load is told `onSetVisible` with its geometry
         already dispatched, and opened **non-activating** — the player belongs in front after a load.
      2. **A default, not a command** — what the user last decided about that window wins over it
         (`opensAtLoad(opensByDefault:remembered:)`), stored in the **skin's own** namespaced
         configuration, so a settings window they closed does not reopen at every launch. That was the
         objection that kept this unimplemented for eight phases, and it is answered rather than
         accepted. Only explicit routes record — a menu item, a skin button, a close box; a script's
         own `show()`/`hide()` describes this run, not the next one.
      3. **`default_x` / `default_y`** — the arrangement the skin ships. Winamp reads them as desktop
         coordinates around a player at the origin, so they are applied relative to the *player's own*
         declared origin, in skin pixels, y flipped, scaled by UI Size (`arrangedOrigin`). Winamp
         Modern's playlist lands beside the player and its album art under that, instead of every
         window stacking below the player as before.
      4. **Two suppressions**, each recorded once in the skin's diagnostics and neither of them
         blocking the window (menu, skin button and script still open it): a `notifier`/`tooltip`
         container (Winamp's track-change toaster is driven by a host subsystem we do not implement —
         Love is War Miku's would sit on screen all session reading "Nothing / Next track"), and a
         container holding a `<browser>` (Rika's and T800's 860×704 "HOME" window, which the sandboxed
         engine opens as an empty frame).
      Verified live on Defix 2026-08-20 — configurator and playlist editor both on screen at launch —
      and in the harness, which now opens a `default_visible` window itself and prints
      `DEFAULT-VISIBLE <id> suppressed: <reason>` for one it will not. 7 new unit tests.
      Residue: the *user's* half of the persistence (close it, relaunch, it stays closed) is covered by
      its precedence and storage tests rather than by a GUI run

## Tier 2 — real work, several skins each

- [x] **B7. Dispatch `onEqBandChanged` / `onEqPreampChanged` (5 skins:** multipass, mmd3, Rika,
      winampmodern566, Overdrive_2**).** ~~Their EQ readouts — multipass's eleven `ledfillbar` bars —
      follow the skin's own drags but not a change made from the menu bar, a preset, or another
      window~~ — **closed in Phase 41.** Four parts:
      1. **The arities, measured** (`RENDER_DISASM=@<xml>` on all five): `onEqBandChanged(band, value)`
         opens with two argument stores in every one of them, `onEqPreampChanged(value)` with one. Both
         are registered in `dispatchableEventArity`, so a script may also *call* its own handler to
         reuse it, as MMD3 already does with `onSetPosition`.
      2. **The value scale, measured too.** Rika slices a region map at `128 - value`
         (`loadFromMap` → `setRegion`), which pins it to MAKI's −127…127 — the same scale `getEqBand`
         has answered in since Phase 21, so a skin's readout and its own query cannot disagree.
      3. **One funnel, `WinampModernScriptRuntime.refreshEqualizerState()`**, dispatching only what
         actually moved. Every route goes through it: the skin's own slider drag, `System.setEqBand` /
         `setEqPreamp` (which announce themselves exactly as `setVolume` does), the skin's preset menu,
         `EQ_AUTO`, every playback-state hook, and a 1 Hz safety poll beside `refreshBoundText` — which
         is what catches the routes that call back nowhere: a preset, the menu bar, the classic
         equalizer window, a restored session. Eleven integer compares, and silent when nothing moved.
         The first observation *does* announce, because a skin whose readout is written from this
         handler has no other way to learn its opening value (the rule `onTextChanged` already follows).
      4. **The sliders a skin reads instead of the event.** multipass's eleven `ledfillbar` bars ignore
         both arguments and re-read their `parentslider`'s position, so every `EQ_BAND`/`EQ_PREAMP`
         slider's 0…255 position is synced from the host **before** the events go out. The renderer has
         always drawn the thumb from the host; this is the *script's* view of it catching up.
      Verified in the harness with a new probe, `WINAMP_MODERN_RENDER_EQ=<band>=<value>[,…]`, which
      drives an equalizer change from outside the skin and prints the handlers it reached: all five
      skins answer (multipass 14 `ledfillbar` programs per event, mmd3 `skin.xml` — band only, it
      handles no preamp event — Rika `eq.xml`, winampmodern566 `configdrawer.xml`, Overdrive_2
      `scripts.xml`), and the driven band lands on the right slider (band 3 → `param="4"`, since the
      XML parameter is 1-based). 9 new unit tests.
      Residue: the drawn LED bars themselves are a GUI check — the app was confirmed to load and run
      multipass with the poll live, but "drag the classic EQ, watch the skin's bars follow" is manual QA
- [x] **B8. The playlist-editor script API** (`getCurrentIndex`, `getNumTracks`, `playTrack`,
      `removeTrack`, `showTrack`, `getMetaData`, …) — ~~Defix's known `getcurrentindex` gap is one of
      these; it surfaces on interaction rather than at load, which is why it reads as an intermittent
      defect~~ — **closed in Phase 42.** Five parts:
      1. **The cause was not the methods.** `std.mi` declares `PlEdit` as a host-owned global exactly
         as it declares `System`, and the compiler marks **both** with the variable record's `system`
         flag. `MakiBytecodeParser` read that flag as "this *is* the System object", so every
         `PlEdit.getCurrentIndex()` in the corpus arrived as a call **on System** and failed there as
         an unknown System method — which is why it surfaced on interaction and not at load, and why
         implementing the methods alone would have changed nothing. The parser now carves out the
         classes the runtime binds itself (`MakiClassGUID.runtimeBound`); a system-flagged global of
         any *other* class keeps the System object it always had, so nothing that worked before became
         a null receiver.
      2. **The arities, measured** off the corpus's own call sites, not ported from a header:
         `getCurrentIndex`/`getNumTracks`/`showCurrentlyPlayingTrack`/`clear` 0,
         `getTitle`/`getLength`/`getFileName`/`playTrack`/`removeTrack`/`showTrack` 1,
         `getMetaData(track, field)` and **`moveTo(from, to)`** 2. `moveTo` is the one that pays for
         the measurement — it reads like a one-argument "scroll to", and Defix's *Move selected to
         top* proves the second argument by passing a literal 0 and then a running counter.
         `getLength` returns a **string** (`m:ss`, empty when unknown): ClassicPro tests it against
         `""` before bracketing it.
      3. **Keyed on `PlEdit`'s class GUID, not registered by name.** Half these names belong to other
         classes — `getLength` is an `animatedlayer`'s frame count, which ClassicPro's `beat.m` reads
         28 times. Registering by name would have re-declared that one with the wrong arity.
      4. **`System.getPlaylistIndex()`** (6 of 17 skins — the most demanded unimplemented method in the
         corpus) and the widget's own `showCurrentlyPlayingEntry()` (Itemskin, micro).
      5. **A duplicate-handler bug found while verifying it, and fixed.** Defix's `MAIN_LAYOUT_1`
         declares `ConfBT2.onLeftClick()` **twice**, byte for byte; the engine ran both, so that round
         button's assigned action — a *toggle* — fired twice and the two cancelled. Reported live:
         "the playlist opens and immediately closes when you use the main button; if it's open it also
         won't close." Winamp keeps one handler per (object, event) and `MakiProgram.dispatchBindings`
         now does too. **The render harness structurally could not see this** (no windows, so a doubled
         toggle prints as one clean action); it was found by driving the click in the running app with
         the new `WINAMP_MODERN_DEBUG_CLICK` hook.
      Verified live on Defix 2026-08-20 (`getNumTracks() -> 24`, per-row `getMetaData`, one toggle per
      click) and in the harness with a new probe, `WINAMP_MODERN_RENDER_PLAYLIST=<count>[,current=<n>]`,
      which stands a synthetic queue behind the component seam before the scripts start — the only way
      the API can be exercised headlessly, and it fills the drawn playlist panel that has always come
      out blank. 18 new unit tests; the 17-skin sweep is unchanged.
      Residue: `PlEdit.enqueueFile(path)` (cPro-Bento) and `System.playFile(path)` (T800) are left out
      — path ingest is a sandbox policy decision, not an arity question, and their demand keeps being
      recorded. Filed as B21. Defix's `ML` round button not opening the library until another window
      has been opened once is a separate, still-open defect — filed as B22
- [x] **B9. `onKeyDown`** — ~~5 skins: multipass, Defix, Rika, T800, winampmodern566; needs a
      first-responder seam in the view and a keycode mapping~~ — **closed in Phase 43.** Five parts:
      1. **It is a string, not a keycode.** Winamp hands `System.onKeyDown` its own accelerator
         *name* — `"alt+g"`, `"ctrl+w"`, `"esc"` — and every handler in the corpus opens with one
         string store and compares it against a **lowercase** literal
         (`RENDER_DISASM=@<xml>` on all three that bind one). Two of the three compare without
         normalising first — winampmodern566's `strKey == "alt+a"`, Defix's `strKey == "esc"`; only
         multipass runs `strLower` — so an `"Alt+G"` would miss every one of them. There was never a
         keycode mapping to write. `WinampModernKeyAccelerator` builds the string: macOS modifiers map
         literally in the order `ctrl+alt+shift+`, which is not cosmetic — winampmodern566 reads the
         prefix positionally (`strLeft(strKey, 4) == "ctrl"`).
      2. **The seam was not first responder — it was `canBecomeKey`.** A borderless `NSWindow` is
         refused the keyboard by AppKit, so `NSView.keyDown` was never called however willingly the
         view took focus. `WinampModernSkinWindow` overrides it, exactly as `BorderlessWindow` already
         does for the modern-skin windows; the view then accepts first responder unconditionally and
         treats `keyDown` as a *fall-through* — the playlist's Delete first (still gated on a clicked
         row), then the skin, then `super`, so menu equivalents keep working (⌘Q verified live).
      3. **`complete;` is the consumption signal.** MAKI's opcode 40 is not control flow — the compiler
         emits it before the handler's own return — so the interpreter counts it and `dispatchKeyDown`
         reports whether the count moved. A handler that ran and matched no branch never reaches one
         and the key falls through; Defix's `esc` handler carries none at all, which is why "the
         handler ran" and "the key was swallowed" are two different measurements.
      4. **`isActive()`, implemented because the corpus gates on it.** A System event reaches every
         program whatever window is focused (Winamp does it that way too), so winampmodern566's
         playlist asks whether *its* window has the keyboard before acting on `ctrl+w`. It walks up to
         the object's container and asks the host; unimplemented before this, and fail-closed dispatch
         aborted the whole handler on it. Defix calls it too.
      5. **The corpus count was three, not five.** Rika and T800 ship Winamp's stock
         `playlisteditor.maki`, whose `onKeyDown` is the **edit control's**
         (`editcontrol.onKeyDown(Int vkcode)` — a GUI receiver and an integer, a different event), and
         neither skin loads that program at all, because their playlist windows are ours. Both measure
         `handlers=0`.
      Verified live 2026-08-20 with a real Option-G keystroke on multipass (its EQ drawer opens and
      closes) and on winampmodern566 (`alt+g`, `ctrl+w` shading the focused window, `alt+a`), and in
      the harness with a new probe, `WINAMP_MODERN_RENDER_KEY=<accel>[,<accel>]`, plus
      `WINAMP_MODERN_DEBUG_KEY` for the running app. 12 new unit tests; the 18-skin render sweep is
      pixel-identical.
      Residue: `onAccelerator(a, b, c)` — the menu-hotkey channel, three string arguments — is a
      separate event and is still not dispatched (winampmodern566's playlist and library declare one).
      A skin cannot register a shortcut with the host either; only keys arriving at a skin window are
      offered
- [x] **B10. Golden-image regression cover for the render sweep.** ~~The evidence that a rendering
      change does not disturb the other sixteen skins is a **manual** 17-skin sweep — nothing in CI
      catches a third skin regressing~~ — **closed in Phase 44.** Five synthetic scenes
      (`WinampModernGoldenImageTests`) are rendered whole and compared against committed PNGs in
      `Tests/NullPlayerAppTests/Goldens/WinampModern/`, one per mechanism the manual sweep exists to
      protect: **group clipping** (Defix's reels over the song ticker), **frame slicing** (cPro-Bento's
      collapsed pane painting over the volume slider), **animated-layer framing** (a meter cutting the
      wrong row of its sheet), **bitmap-font text placement** (align × valign) and **`alpha` on every
      object** (Phase 25.1). Three things make them committable and stable:
      1. **The fixtures are built in code** — a 64×64 atlas of flat colour cells and a bitmap font
         whose glyph cells are flat colours keyed to their position in the sheet — so nothing
         third-party is committed and "which glyph landed where" is readable straight off the pixels.
      2. **A whole canvas is the assertion**, not a handful of probe points: a defect anywhere in the
         frame fails, which is the property the manual sweep had and `WinampModernRenderPixelTests`
         (four points of three scenes) does not.
      3. **Deterministic by construction** — every sprite blits at natural size and the animation
         clock is pinned, so the per-channel tolerance (2) absorbs a resampler edge and nothing else.
      Each golden was verified to **fail** under a deliberately reintroduced regression before being
      trusted (`isSizedGroup` → false; the animation row → 0; the bitmap-font `valign` offset → top;
      `WasabiFrame.dividerHalfThickness` → 2), and to fail nowhere else. `WINAMP_MODERN_GOLDEN_UPDATE=1`
      regenerates them; a mismatch writes `<scene>.actual.png` and `<scene>.diff.png` (differing pixels
      in red) to `WINAMP_MODERN_GOLDEN_DUMP` or the temporary directory.
      Also folds in the **Phase 25 regression tests (25.1–25.5)**, which that phase deferred to a live
      QA pass that closed without them: alpha parsing at its edges, `setXmlParam`'s image-valued keys
      as a *load* (unresolvable or empty leaves the artwork it had; a registered id, colour included,
      applies; a non-image key is written whatever it says), `getExtension`, Layer FX accepted-and-inert
      without a recorded unsupported call, `newDynamicContainer`, `setFontSize`, navigation denied
      quietly, `hasVideoSupport() == false`, the skin-level `<scripts>` block running **after** every
      object script and its XUI params, and `@HAVE_LIBRARY@` expanding to 1 while an unknown macro
      passes through. 16 new unit tests (5 golden scenes + 11); the full suite is 904 tests green.
      Residue: the goldens cover the renderer, not the **window layer** — a defect that only exists
      once a scene is inside an `NSWindow` (Phase 42's doubled playlist toggle) still needs
      `WINAMP_MODERN_DEBUG_CLICK` in the app. And the 17-skin sweep is still the acceptance gate for a
      change to real artwork; what CI now catches is the *mechanism* regressing under it
- [x] **B11. Defix's configurator, the rest of it** — ~~the 31 backgrounds, the nine display styles,
      the songticker mode; the pages exist and are reachable but undriven~~ — **closed in Phase 45.**
      One engine defect, one instrument gap, and three measurements:
      1. **`ConfigAttribute.setData` was a second write route, and the wrong one.** A skin registers
         the same attribute once **per script**, so every window holds its own object for it; the
         script route dispatched `onDataChanged` to the *calling* object alone while
         `setConfigAttribute` (the host's Skin Settings window, and a `cfgattrib` control) had
         broadcast to every holder since Phase 27. Defix's **31 backgrounds** are a stored `BG` id
         plus a pulse on `Bg Chng`, and five windows' `STANDARDFRAME` scripts re-image nine frame
         slices each from that pulse — so *Body material* repainted the configurator's own window and
         left the player, both cabinets, the playlist and the library wearing the old wood panelling.
         `setData` now goes through the one route. **Change sticker** (31 `ICON*` on the main window's
         `LayCON`/`LayPIC`) and the three-page `◀`/`▶` switch were already sound.
      2. **The display styles work, and two of the eight are the skin's own dead entries.** Six give
         six distinct scenes; `Ovis 1`/`Ovis 2` store `CurVuVis = 4`/`5` into an **empty branch** of
         the apply routine, which settles the long-open "which two share an artwork block" question —
         neither does. Same family as `SCALENEON`.
      3. **The songticker mode was never unreachable** — that claim predated Phase 27's Skin Settings
         window and was never re-measured. *Modern* → `ticker="bounce"`, *Classic* → `ticker="scroll"`.
         The three are a radio group the **skin** does not enforce and whose handler tests `Disable`
         first, so *Modern* with `Disable` still ticked measures `off`; Winamp offers the same three
         checkboxes, and no host heuristic should guess the grouping.
      New probe: **`WINAMP_MODERN_RENDER_SET=<section>;<key>=<value>`** writes a registered setting
      *after* the skin is up, through `setConfigAttribute` — the only headless route to a display
      style, because `RENDER_CONFIG` seeds the store before `onScriptLoaded` and Defix reads its own
      `CurVuVis` copy. Two harness traps found and fixed with it: the clicked container is now dumped
      **first** (a click on the configurator changed five windows that had already been written), and
      the dump wires `configStateProvider` like both app paths do (nine indicators read `OFF` against
      three settings that ship as `1` — a blind instrument reporting a defect the app does not have).
      A multi-click burst also needs `RENDER_SETTLE`, or one click in twelve leaves no write.
      3 new unit tests; 907 green; the 21-skin render sweep is pixel-identical (one PNG, Anexa's
      `main-shade`, hashes differently on every run of the same build and is pixel-identical — the
      encoder, not the renderer). **Confirmed live 2026-08-20**: one click on *Body material* in the
      running app wrapped `BG31 → BG1` and changed the playlist window's frame on screen.
      Residue: the seven scaling buttons were still inert; closed as B12 in Phase 46. The live pass
      is the QA checklist item, not a probe
- [x] **B12. `setScale`** — ~~the configurator's seven 100–300% window-scaling buttons are inert~~ —
      **closed in Phase 46.** The decision first, because the code follows from it: `setScale` drives
      **our own UI Size**, and there is no skin-local scale at all. A `.wal` scene is laid out on the
      skin's pixel grid and `WinampModernMainView` applies UI Size at its drawing and input
      boundaries (Phase 10); a second, layout-local scale would be a rival for the same pixels, and
      the two would fight over every window's size. So `getScale()` still answers **1** — the
      layout's own scale really is 1 however large it is drawn, which is also what ClassicPro's
      resize arithmetic (in skin pixels, multiplied by it) needs.
      What the skin actually does, measured (`RENDER_DISASM=@skin.xml`): each button stores a
      percentage with `System.setPrivateInt(getSkinName(), "SCALING", n)` and pulses `SCALING Chng`;
      an if-chain then re-reads the stored value and calls `layout.setScale(1 / 1.25 / 1.5 / 1.75 /
      2 / 2.5 / 3)`. It is registered **once per script**, so one click produces **nine** identical
      requests across five scripts — one per window the skin owns. That is the whole reason this is
      one global request and not nine local ones, and the runtime forwards every one: the host
      de-duplicates, because `WindowManager.uiScaleLevel` ignores a write of the level it is at.
      Three things the shape of the fix turns on:
      1. **The ladder gained 175%, 250% and 300%.** Snapping to the old top of 200% collapsed three
         of the seven buttons onto one level — seven controls, four outcomes. They are ordinary UI
         Size rows now, available in every mode.
      2. **A load-time request cannot be acted on.** `loadSkin` runs from the window controller's own
         initializer, so `WindowManager.mainWindowController` is not assigned yet and
         `applyDoubleSize` would return having changed nothing while the level it was handed stuck —
         a permanent desync. Defix calls `setScale` from `onScriptLoaded`, so this is the normal
         case. It is held and applied one runloop turn after the skin is up, which is also *before*
         `AppStateManager` restores a saved UI Size — so an explicitly saved level still has the last
         word over the skin's stored one, and a skin switch does not carry the old skin's request in.
      3. **Accepted, never refused, on a non-layout receiver.** Refusing a method aborts the handler
         that called it, which is how one missing call took multipass's entire `onScriptLoaded` with
         it in Phase 33.
      New harness line: **`SCALE request <factor> -> <level>%`**, printed for every call and named as
      the level the app would snap to (a button asking for 250% must not read as one asking for 200%);
      the harness owns no windows and this is the only headless view of the request. Verified by
      driving each of the seven buttons in `Config/normal` — one button per x, the right factor, the
      right level, nine lines each. 8 new unit tests; 915 green. **Manual QA in the running app:
      good, 2026-08-20.**
      Residue: **`onScale`** — the layout event Wasabi raises when a scale changes — is still not
      dispatched. Measured demand is Ebonite's `standardframe.m`, which uses it to keep two layouts in
      step; our one global scale already does that, so there is nothing for it to fix today. Also
      measured while here: Ebonite and boom (`prefs.m`) are the only other corpus skins that call
      `setScale`, both on a layout, so the receiver rule covers every measured use. And note the trap
      that hid them — a compiled `.maki` carries a trailing index byte after each method name, so a
      strict `grep setScale` over the corpus finds only the skins that shipped uncompiled `.m` source
- [x] **B20. Host the video player in the skin's own video window.** ~~Five of the 17 skins declare a
      full `<container id="video">` and it is decoration over an empty box~~ — **closed in Phase 47**,
      and it is **15 of the 33 measured skins**, not five. The decision the whole thing turns on:
      the picture is **not** a subview of the skin. Moving `VideoPlayerView` into the holder is the
      `.library` seam's shape and it does not survive contact with the video engine — VLCKit installs
      its own output view under the player's host view and sizes *that view's ancestors*, so the skin
      window's content view ran away at +46pt per layout pass (372 → 14,219 in 80ms) and the picture
      never appeared until something else forced a relayout. The surface holds a **black box the skin
      lays out**; `VideoPlayerWindowController` parks its **own window** over it with
      `addChildWindow`. A child window has its own layout tree, so the decoder cannot reach the
      skin's, and it follows the parent's moves, hides and closes for free — which is also the
      lifetime answer: a layout, skin or mode switch *unparks* a still-playing film instead of
      tearing the player down with the window.
      **The trap that cost three wrong fixes: `setFrame` refuses silently.** A window whose content
      carries required Auto Layout constraints has a minimum size derived from them, and AppKit
      returns a larger frame with no error. `VideoControlBarView`'s required chain sums to exactly
      **395pt** — the same +46 as the runaway — so every parked frame narrower than that was widened
      and the picture ran out through the skin's chrome. A *hidden* view's constraints are still
      live, so the bar now leaves the view hierarchy, and the surface gates it on the box: in only
      when the holder asked for it **and** the box is at least the bar's own `fittingSize`. Only mmd3
      and BLAKK ask for the bar and both boxes are under 395pt, so no corpus skin gets one.
      `VID_1X` / `VID_2X` are live (12 declarations, inert since Phase 39) — they size the skin's
      window so the box is the stream's own pixels times N, clamped to the visible screen as well as
      the layout's range. `.video` is a **routed** surface but not a **managed** one: never
      synthesized, never embedded (Winamp Modern's player declares an invisible in-player holder that
      would otherwise win and leave the real video window empty). Casting is untouched — every
      `play*` returns before the video controller when a device is active. New harness line
      **`VIDEO holder <container>/<layout>: <id><frame> cmdbar=<0/1>`**, and a container that routes
      with no holder (Hoop_Life_WA3, Media_Whore) correctly falls back to our own window. 915 green.
      **Confirmed live 2026-08-21** on multipass: picture in the box on play, asked frame granted.

- [x] **B20a. Host the real visualization engine in the skin's own AVS window.** ~~Eight skins
      declare a `<container>` for the visualization component and every one of them is a second,
      larger copy of the spectrum analyzer~~ — **closed in Phase 48.** The measurement first, with
      the new `VIS holder` / `VIS box` harness lines: **8 of the 31 installed skins** declare a
      container whose body is a `<component param="{0000000A-000C-0010-FF7B-01014263450C}">` —
      Anaheim_Player_01 `avs_window` 100×200 · hatsune_miku_5 `avs` 479×326 · Itemskin `AVS_window`
      277×71 · Love is War Miku `avs` 190×84 (V2 190×90) · multipass `avs_window` 298×134 · Styx
      `AVS` 220×200 · winampmodern566 `AVS` 342×232. That holder is Winamp's *plugin* surface, the
      box AVS and MilkDrop drew into, and it now holds NullPlayer's own visualization stack —
      ProjectM/MilkDrop, Geiss, Tripex — with the same engine preference, preset store and
      Visualizations menu as our own window. A `<vis>` box is a different thing (Winamp's built-in
      analyzer/oscilloscope) and stays engine-drawn, which is what keeps every render sweep and
      golden image measuring the same picture.
      **The finding that shaped it: there was no way to open one of these windows at all.** A
      container carrying a `component=` GUID is deliberately kept out of the Skin Windows menu
      (`isListedInWindowMenu` requires `kind == nil`) so a routed surface cannot be reached twice —
      and nothing routed `.visualization`. So it joins `.video` as a **routed but not managed**
      surface: never synthesized, never embedded, `.declaredContainer` or `.classicFallback` only.
      `showProjectM`/`toggleProjectM` route through the catalog first, so **Show Visualizations
      Window**, a skin's own `TOGGLE guid:vis` and the `VIS_*` toolbar buttons all reach the same
      window. `showProjectMFullscreen` and the coordinator's own fallback take `routeToSkin: false` —
      a borderless `.wal` container has no fullscreen of its own to enter.
      Unlike the video picture this one **is** a subview: `VisualizationGLView` is a self-contained
      `NSOpenGLView` that sizes no ancestor, so the `.library` seam's shape works here where it did
      not for VLCKit. Its `hitTest` returns nil, so the skin keeps every click over the box — which
      is how a right-click on the box opens the engine's own controls. The renderer is told which
      holders the view layer filled (`hostedVisualizationHolders`) and paints those black instead of
      drawing bars underneath a live engine; headless, that set is empty and the analyzer is still
      what a `<component>` box holds.
      **Live pass 2026-08-21 found two things, both fixed in the same phase.** *(1) The windows could
      not be opened.* `isListedInWindowMenu` keeps any container with a `component=` GUID out of the
      Skin Windows menu so a routed surface is not reachable twice — and measured, **no corpus skin
      binds a button to its AVS window** (all eight are named, none is `nomenu`, hatsune_miku_5's
      player carries only `eq`/`pl`/`ml`). So routing alone left "I cannot find a visualization
      window", with only cPro-Bento working because its holder is script-built inside the SUI body.
      The menu rule now admits `windowMenuRoutedKinds` (`.visualization`, `.video`) and
      `toggleSkinWindow` routes those two through the coordinator, so the menu entry and the
      Visualizations menu reach one window. *(2) The menu was truncated.* Reported against Bento: the
      surface had a short hand-written menu beside the visualization window's full one. The window
      menu was itself written **twice**, identically, in `ProjectMView` and `ModernProjectMView`; all
      three now build `VisualizationContextMenu` from one `VisualizationMenuTarget`, with `Options`
      for the cycle state and for whether Fullscreen/Close apply.
      **Second live pass, same day, three more.** *(1) Two visualization windows at once.* Miku's AVS
      window carries a `VIS_FS` button **inside** it (5 of the 8 do), and `VIS_FS` opened
      NullPlayer's own window with a second engine while the skin's box kept rendering. `VIS_FS` on a
      hosted surface now moves the `VisualizationGLView` itself into a borderless `.screenSaver`
      window and back (Esc / `f` / double-click) — one view, two homes, no second engine — and ours
      and the skin's are made mutually exclusive besides: `isProjectMVisible` answers for either,
      each hides the other before showing, a visible window of ours wins `toggleProjectM`, and a skin
      that owns the surface takes it over at load. *(2) A misformed box.* Anaheim's `avs_window`
      declares `default_w="120"` under `minimum_w="180"` (Styx's `AVS`: 300×300 under 400×230), and
      the window opened at the default while its frame art was laid out for the minimum, so the
      chrome was cut off. `defaultSize` now clamps to the skin's **declared** minimum — 4 layouts in
      219 change, 2 of them these AVS windows. *(3) The Miku skins bind no button to the window
      itself*, which the Skin Windows entry from the first pass is the answer to.
      **Third live pass: every AVS window was black except Bento's** — screenshot showed Miku's window
      open, chrome perfect, box black (which itself proved the *hosted* path was live: an unhosted box
      draws bars). `VisualizationGLView.startRendering()` refuses while `window.isVisible` is false,
      and nothing restarts a link that never started — an aux container window is created hidden and
      ordered in later, so the surface made during its first layout pass was refused once and never
      asked again. Bento was unaffected because its holder is in the main player window. The surface
      now has `resumeRendering()`, called after the window is ordered in (`setSceneVisible`, which
      forces the layout pass first, and `setAuxiliaryWindow`), plus a DEBUG `WINAMP-MODERN-VIS:
      resume …` line carrying window visibility, the box, the engine and whether frames are running.
      **Fourth pass: the keyboard.** The visualization window answers ←/→ (shift = hard cut), R, F, P,
      C and Esc; the embedded surface answered none of them — a skin's window offers nothing but its
      five buttons, so that is the whole keyboard for it. `WinampModernMainView.keyDown` now offers a
      key the *skin* did not claim to the hosted surface, and the fullscreen window hands it the whole
      map. Also corrected: the minimum clamp changes **11 layouts in 4 skins**, not the 4 first
      reported (the scan's regex dropped every skin whose filename contains a space) — both Miku
      skins' `avs` is 200×150 against a declared 400×300, which is the window size in the live
      screenshot. The `VIS_NEXT`/`VIS_PREV`/`VIS_FS` buttons themselves are confirmed reaching
      `visualizationNext`/`Previous`/`Fullscreen` under `RENDER_CLICK`.
      926 green. **Confirmed live 2026-08-21** across Bento, both Miku skins, Anaheim and Styx: the
      engine draws in the skin's own window, its `VIS_*` buttons and the visualization keyboard drive
      it, `VIS_FS` fills the screen from the skin's box, and only one visualization window is ever up.

- [ ] **B21. `enqueueFile` / `playFile` — skin-supplied path ingest.** `PlEdit.enqueueFile(path)`
      (cPro-Bento) and `System.playFile(path)` (T800) hand the host a filesystem path the *skin*
      chose. Deliberately left out of B8: it is a sandbox policy decision (what may a script add to
      the queue, and from where), not an arity question. Note `clear()` **is** implemented and these
      are not — safe today only because cPro-Bento's one caller early-returns on
      `ClassicProFile.findFiles`'s bounded `-1` long before its `PlEdit.clear()`. Decide the policy
      before implementing either, and check that pairing again
- [ ] **B22. Defix's `ML` round button needs another window opened first.** Reported live 2026-08-20:
      the media library will not open from the button until some other window has been opened once,
      after which it works every time. The branch is
      `getContainer("SUI").getLayout("normal").findObject("sui.content").sendAction("opentab","ML")`,
      and the SUI's `onAction` answers `isVisible() -> 1` then `getContainer("sui").hide()` — it
      believes the tab it was asked for is already showing. The `isVisible()` receiver is **not** the
      container (no `containerVisibilityQuery` is consulted), so it is reading a graph `visible`
      attribute on a tab page nothing has initialised yet. Same family as the Phase 31 "round buttons
      re-assign but mis-target after the swap" item; drive it with `WINAMP_MODERN_DEBUG_CLICK` +
      `WINAMP_MODERN_CALL_TRACE`

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
