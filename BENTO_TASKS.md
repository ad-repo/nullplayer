# Big Bento Modern (`.wal`) — backlog

The four variants: `Big Bento Modern`, `Big Bento Modern Light`,
`Big Bento Modern Windows 10 edition`, `Big Bento Modern Windows 10 edition Light`.

Split out of `TASKS.md` on 2026-08-23, which had accumulated four Bento sections (B35–B38) and
carries the rest of the `.wal` engine backlog. **Both files are tracked in git.** Anything here that
turns out not to be Bento-specific belongs back in `TASKS.md`; anything durable that is learned here
belongs in the skill —
`skills/winamp-modern-skin-guide/skins/big-bento-modern.md` for facts about this skin, the
`reference/` file that owns the concept for anything wider.

Skill: [skins/big-bento-modern.md](skills/winamp-modern-skin-guide/skins/big-bento-modern.md).

---

## Open

- [ ] **BB1. `instantiate` — superseded by BB7, which corrects it.** Read **BB7** instead. This entry
      described the method as `instantiate(groupdef_id, index)` with "nine call sites" and called it
      a real engine capability rather than an arity question. The MAKI source says otherwise on all
      three counts (2026-08-23), and the engine already does the part this entry assumed was
      missing. The number is kept, not reused, so the correction is traceable.

- [ ] **BB2. The embedded library tab is unstyled** (was B37.5). The SUI tab below the player shows
      NullPlayer's own source bar and monospace tab row (`Source: Local Files`,
      Artists/Albums/Folders/…) rather than anything drawn in the skin's palette. **Not started**:
      this is a host-surface styling question, not a skin-script one, and it does not reproduce
      headlessly (the harness sets no component host). Compare against how cPro-Bento and Defix host
      the same surface before deciding whether it is a Bento-specific gap or the general fallback.

- [ ] **BB3. Bitmap overrides in the two Light overlays do not win.** Measured 2026-08-23 and
      recorded as a trap in the skill, never filed here. The Light editions ship light versions of
      ~30 of the *same* `window/*.png` the base declares (`frames.png`, `equalizer.png`,
      `no_alb_art_*.png`), but a `<bitmap file="window/frames.png">` declared in **base** XML
      resolves relative to that XML first, so it loads the **base's** artwork; only the `@SKINPATH@`
      fallback would reach the overlay's copy. The editions still read as light because their
      palette comes from `color-presets.xml` / `system-colors.xml` and the gamma model, so this is
      cosmetic today. **Do not** fix it by flipping `resolveSkinResource`'s order without a full
      corpus sweep — the relative-first order exists for authored subfolders.

- [ ] **BB4. Live QA of B38.4 / the rest of B38.3 — RAN, AND IT FAILED (2026-08-23).** B38.1 and
      B38.2 were confirmed on screen by the user; the B38.4 dispatch-binding fix and the four methods
      behind it were verified only headlessly and by a 300-image pixel diff. They do **not** hold in
      the running app. The user's screenshot of the header is timestamped 19:10 and the debug build
      it came from is 18:53 — the same working tree that contains every B37/B38 change — so this is
      not a stale binary. Still wrong on screen: a full-width cover-flow strip crosses the panel, the
      details column is squashed rather than laid out, and the album art is drawn twice (**BB6**).
      What *did* hold: the file-info panel fills its lines, though with the wrong content (**B39**).
      Re-measure **live**, not headlessly — B38 already established that three of its five defects
      never reproduced in the harness — with `WINAMP_MODERN_DEBUG_HOLDERS=1` and
      `WINAMP_MODERN_DEBUG_CLICK` + `WINAMP_MODERN_CALL_TRACE=1`. Treat the headless pass as
      necessary and not sufficient for anything in this panel.

- [ ] **BB5. `@HAVE_LIBRARY@`** — carried over from B36's follow-up because it is not Bento-only.
      A second unresolved token, never used as a path so the VFS never sees it
      (`<script … param="@HAVE_LIBRARY@">` here; `default_visible="@HAVE_LIBRARY@"` on the
      media-library container in Styx, Shield_Amp, S7Reflex, Defix). Winamp substitutes `1`; doing so
      is a *behaviour* change — four skins would start opening a library window — and needs its own
      live QA. **If this is picked up, move it to `TASKS.md` first**: four of the five skins it
      affects are not Bento.

---

## Open — the header / Multi Content View and the settings surface (filed 2026-08-23)

Research pass over the four variants' **top area** and their **customization surfaces**, prompted by
live QA of the header. Plan: `~/.claude/plans/abundant-pondering-hamster.md`. Every finding below was
verified against source; where something is unmeasured it says so.

**Three findings from this pass are engine-wide and live in `TASKS.md`, not here** — the `B*` series,
so the numbers do not collide: **B39** (`setText` vs `display=` — the repeated song title),
**B40** (`navigateUrl` policy and `ML_SendTo` — the dead lyrics/video buttons), and
**B41** (`getMonitorWidth`/`getMonitorHeight`). Bento is only where they were found. The `BB`
numbers below run contiguously `BB6`–`BB15`; the plan file used a different provisional numbering for
the same items, so cite these, not the plan's.

**One thing to read before starting any of these:** the user's summary was *"enabling the settings
might be the key to understand what this skin can do."* That is right. These are **WACUP-era** skins,
not stock Winamp, and most of what they can do is switched on from a config surface that is inert
today. **BB7** is the item that unlocks it.

**The WebKit sequencing gate is satisfied (2026-08-23).** Browser windows and tabs now host a real,
ephemeral `WKWebView`, with a visible search/address field, policy-gated navigation, `url=`/`home=`
initialization and VFS-only local resources. This gives `B40` and the reader's `browser_search` an
internal destination, but their global/action routing remains separate work. Big Bento declares a genuine
`<Browser id="browserpro.browser" … url=""/>` in `reader.xml:90`, with a `reader.mode` two-state
button toggling *Web Reader ↔ Internet Browser*, an *Open in Default Browser* button, and a
`browserpro` provider-list container. The remaining reader gap is its list/action machinery, not the
web surface itself. cPro-Bento's engine-one SUI also has a reachable v1 Browser tab whose
`<Winamp:Browser home="http://www.skinconsortium.com/">` now initializes correctly; that historical
server currently returns an empty reply, which the surface reports as *Page unavailable*.
`BB11`'s `getItemLabel` is the same reader's list, so it may fall out of that work rather than this
backlog.

### Tier 1 — reported defects

- [ ] **BB7. `Group.instantiate(groupdef, count)` — supersedes and corrects BB1.** Three things BB1
      got wrong, from the MAKI source (`scripts/config_vscrollbars.m:47`, in the author's own
      comment):
      ```maki
      Group g1 = grplst.instantiate(param, 1); // "1" here is the amount of times the group
      Group g2 = grplst.instantiate(param2, 1); //  will be instantiated
      ```
      The second argument is a **count**, not an index. The receiver is a **`GroupList`**, not a
      plain `Group`. And there are **two** call sites in **one** script — `config_vscrollbars.maki`
      is the only file in the skin that mentions `instantiate` at all. BB1's "nine call sites" are
      nine *declarations of that same script* (`config.xml` ×8 + `player-normal-sui.xml` ×1), each
      with its own `param="part1;part2"`.
      **The engine already does the hard part.** `newGroup` and `newGroupAsLayout`
      (`WinampModernScriptRuntime.swift:2388`, `:2413`) both go through
      `loadedSkin.runtime.instantiateGroup` → `instantiateGroupAtRuntime`
      (`WasabiSkinInitializer.swift:580`), which expands a groupdef under an arbitrary parent, runs
      `applyMetaCommands`, binds the subtree's scripts and defers their start via
      `pendingRuntimeGroups` so a script never runs before its group is attached. Runtime graph
      construction, the layout pass and teardown are solved — which is exactly the thing BB1 said
      had to be decided first. What is left is the `Group`/`GroupList`-side method, the loop over
      `count`, and whatever `<grouplist>` needs to be a receiver.
      Unblocks the config window's **nine option pages** and the SUI's **equalizer tab** in one go,
      and is why all four variants still report compatibility level `unsupported` although they draw.

- [ ] **BB8. `ColorMgr.getGammaSet(name).apply()` — the 77-theme colour picker does nothing.**
      `config_color_themes_switcher.m` applies a theme with
      `ctbg01 = ColorMgr.getGammaSet(ctname); ctbg01.apply();` — **77 call sites** in that file and 77
      more in `config_color_themes_switcher_light.m`, one per shipped theme
      (`xml/color-presets.xml`, ~2998 lines, 34 gammagroups each). None of `ColorMgr`, `getGammaSet`
      or `apply` exists in the runtime (all grep to 0 in `WinampModernScriptRuntime.swift`).
      The destination already does: `WasabiColorThemeCatalog` (`WasabiRenderer.swift:103`) holds the
      sets and tracks `activeTheme`, and `System.setColorTheme` routes through `themeSwitchRequested`
      (`:2339`). So this is a **binding** job, not a rendering one.
      **Bind `ColorMgr` by class GUID, not by method name** — `MakiClassGUID.runtimeBound` /
      `seedHostSingletons`, the pattern `PlEdit` uses. `apply` is exactly the kind of short name that
      belongs to several classes, and registering it by name would re-declare it with the wrong arity
      and desynchronise the interpreter's stack in unrelated skins. See `reference/scripting.md` →
      *`PlEdit` — the playlist-editor API*, which records that failure mode. Check first whether any
      other corpus skin reaches the catalog this way.

- [ ] **BB6. The album art is drawn twice.** `info.component.albumbg`
      (`xml/player-normal-mcv.xml:920`) holds a **second** `winamp.albumart` at `relatw="2"
      relath="2"` with `alpha="100"` — an oversized, dimmed backdrop meant to sit behind the panel,
      centred by `centerobject.maki`. On screen it is a small crisp copy to the right of the real
      cover instead. Three candidates, none measured yet: `relatw`/`relath` greater than 1 as a
      *multiplier* of the parent, the ghost/alpha not being applied, and `centerobject.maki`'s
      positioning. **Measure before theorising** — `WINAMP_MODERN_RENDER_PROBE=main/normal` plus
      `WINAMP_MODERN_RENDER_BITMAPS=1`. Note there is a third, legitimate `winamp.albumart2` in
      `info.component.cover2` used by the SUI playlist tab; do not confuse it for the duplicate.

- [ ] **BB9. The visualization pane is missing — probably a setting the user cannot reach.**
      `mcvcore.m` picks the MCV's pane from config attributes it registers itself (`ic_fileinfo`,
      `ic_vis`, `ic_cover_fileinfo`, `ic_vis_fileinfo`) and the `...` button's popup is where a user
      flips them (`mcvcore.m:256`, `:266–267`). B38.4 already established that at the defaults the
      skin takes the album-art branch and hides `info.component.vis` — so "the spectrum analyzer is
      missing" is most likely **correct default behaviour that cannot currently be switched off**,
      which routes straight back to BB7 and B40. Confirm the shipped defaults with
      `WINAMP_MODERN_RENDER_SETTINGS=1`, then drive the popup live (`WINAMP_MODERN_DEBUG_CLICK` +
      `WINAMP_MODERN_CALL_TRACE=1`) — `PopupMenu`'s `addCommand`/`addSubMenu`/`checkCommand`/
      `popAtMouse` **are** implemented (`WinampModernScriptRuntime.swift:1979–1983`, `3039–3065`), so
      do not assume that button is dead until it is measured.
      Then the separate question: does an embedded `<component hold="guid:{0000000A-…}">` in the
      **player body** — as against a dedicated container — get a visualization surface from us at all?
      That is the same shape as the open **B23a** (BLAKK) in `TASKS.md`, and both **B23a** and **B16**
      warn that our holder probes go blind on exactly this case. Fix the probe first.

### Tier 2 — the settings surfaces themselves

- [ ] **BB10. The gear (host **Skin Settings**) window renders two widget kinds, and hides some
      settings entirely.** Reported by the user as *"most items in the gear settings menu don't work
      or are blank."*
      `Windows/WinampModern/WinampModernSkinSettingsWindowController.swift` (208 lines) builds its
      list from `runtime.presentableSettings` and renders a checkbox when the current value is
      exactly `"0"` or `"1"` (`isToggle`, line 29) and otherwise a bare `NSTextField` (line 126).
      There is no enum, slider, range or colour widget, because `RegisteredSetting` carries no type
      metadata — only section, name and default. Separately, `presentableSettings` filters out every
      setting whose *current value* looks like a GUID (`namesAnItem`), which is right for Winamp's
      config-tree navigation nodes and also hides any legitimately GUID-valued option.
      Decide in this order: **(a)** does this window stay a *fallback* for options no skin control
      binds, once BB7 makes the skin's own nine pages work? It and `config.xml` read and write the
      same store, so BB7 may make it largely redundant for this family and the answer changes how
      much (b) is worth. **(b)** extend `RegisteredSetting` with type/range metadata so an enum is a
      popup and a bounded int is a slider. **(c)** revisit the GUID filter.
      Start by dumping what this skin actually registers: `WINAMP_MODERN_RENDER_SETTINGS=1`.

- [ ] **BB11. List accessors: `getItemLabel(i)`, `getItemFocused()`, `setSubItem()`.** All absent from
      the runtime. Called from `reader/main.m` (the skin's own news reader) and `playlistpro.m`.
      Scope which of those lists are actually reachable in our host before implementing any of it —
      the reader may not be.

- [ ] **BB12. The header strip and the seek bar — unexplained, needs a measurement pass.** Two things
      in the user's screenshot that no probe has been pointed at yet, and neither has a filed cause:
      the header strip is flat with no titlebar artwork, and the seek bar under the time readout is a
      solid black bar. Candidates for the first include the **BB3** bitmap-override trap and a frame
      bitmap that simply is not resolving; for the second, a missing background bitmap or an
      unsupported attribute. `WINAMP_MODERN_RENDER_PROBE=main/normal` +
      `WINAMP_MODERN_RENDER_BITMAPS=1`, diffed against the skin's own artwork. **Do not file a cause
      for either until it is measured** — this subsystem has produced three wrong diagnoses from
      unmeasured reasoning already (B36 is the worst of them).

### Tier 3 — real gaps, no reported symptom

- [ ] **BB13. `setClipboardText()`** — absent, so copy-title and copy-path from the skin's own menus
      are inert. Three call sites.
- [ ] **BB14. Animated layout and tab transitions, and easing beyond linear.** Our layout and tab
      switches are instant visibility swaps. Sprite `<AnimatedLayer>`, the
      `setTarget*`/`setTargetSpeed`/`gotoTarget`/`cancelTarget`/`onTargetReached` tween machine and
      timers are all implemented and are what Bento's own animations are built from, so **nothing in
      this family depends on this**. Filed so the absence is recorded rather than rediscovered.
- [ ] **BB15. `parser_*` (XmlDoc) and `shutdown()`** — inert, no measured demand in this family.

**Not open, and not a defect:**

- The Windows 10 edition's zero-byte `window/no_alb_art_shade.png` is the skin's own bug. It degrades
  to a warning and that one placeholder draws nothing, which is the correct outcome.
- The wide-window pane split (B38.5). `from="left"` anchors the divider to the left edge and the right
  pane absorbs the extra width — see B38 below.

---

## Closed

### B35 — The four Big Bento Modern variants fail to load

Plan: `~/.claude/plans/contineu-purring-dove.md`. Three independent root causes: `@SKINSPATH@` is an
undefined path variable (hard `.unresolvedPathVariable`); the two *Light* editions are overlays that
pull six of their eight includes out of the **base** skin's directory through that token; and the
Windows 10 edition ships a zero-byte `window/no_alb_art_shade.png` whose `.invalidImageResource`
fails the entire skin.

- [x] **B35.1 `@SKINSPATH@` → `/Skins`** — define it in `WalVirtualFileSystem.init()` alongside
      `WINAMPPATH` / `DEFAULTSKINPATH` (it is a fixed collection root, not skin-derived).
- [x] **B35.2 Lazy sibling mounts** — `siblingMountResolver` closure + `mountSiblingIfNeeded(for:)`
      on the VFS, consulted **only** when no mount already owns the path, from
      `canonicalExistingPath` (retry once after a mount) and from `expand` (before filtering
      `allLogicalPaths()`). Memoize misses in `failedSiblingNames`; cap at 4 mounts per load.
- [x] **B35.3 Loader supplies the resolver** — `WinampModernSkinLoader.load(from:additionalMounts:)`
      searches the archive's own directory, then `WinampModernSkinImporter.defaultDestinationDirectory()`,
      matching `safeMountName(basename)` case-insensitively; opens each hit with the same
      `archiveLimits`.
- [x] **B35.4 Name the missing base** — new `WalDiagnosticCode.missingRequiredMount`, thrown with
      "This skin requires the skin '<name>' to be installed." so it bypasses the two
      `.resourceMissing` tolerance blocks (`WalXML` include warning, `resolveSkinResource`'s
      `@SKINPATH@` fallback). Categorize as `resources` in `WinampModernCompatibilityReport`.
- [x] **B35.5 Undecodable images degrade** — in `registerResources`, tolerate `.invalidImageResource`
      exactly like `.resourceMissing` for `bitmap`/`cursor`/`bitmapfont`: register without
      `logicalFile` and warn. `.imageDimensionsExceeded` stays fatal.
- [x] **B35.6 Tests** — Phase 2: `@SKINSPATH@` resolves; own-name self-reference needs no resolver;
      sibling `<include>` expands from a `.wal` next door; absent sibling throws
      `.missingRequiredMount` naming it; 4-mount cap; a repeated miss does not re-scan. Phase 7:
      zero-byte bitmap degrades to a warning (tighten
      `testMalformedImageResourceDegradesInsteadOfCrashing`); oversized still throws.
- [x] **B35.7 Verify** — `swift test`, goldens, render-dump per variant with
      `WINAMP_MODERN_RENDER_BITMAPS=1`, then the corpus sweep diffed **by pixels** against a
      pre-change run.
- [x] **B35.8 Land the findings** — `reference/loading.md` (VFS mounts table + *Sibling skin mounts*),
      `compatibility.md`, `skins.md` + new `skins/big-bento-modern.md`, `CHANGELOG`.
- [x] **B35.9 Live QA, 2026-08-23** — done by the user. The skins come up in the running app; the
      window is large because the layout declares `w="1536" h="878"` and the UI was at 150% scale,
      not a defect. Found live: the SUI menu bar draws its five items on top of each other → **B36**.

### B36 — The `<Menu>` XUI does not self-size — **wrong diagnosis; closed 2026-08-23**

The measurement was right and the conclusion was not. All five `Menu` objects did report
`frame=(190, 6, 0, 32)`, but not because the widget fails to self-size: `player.mainmenu` carries the
comment *"Note: Most of the items in this group are placed by script"*, and `mainmenu.maki` measures
each label with `getAutoWidth()` and lays the five out left to right. That script was aborting on
`getSettingsPath` before it reached the layout code. With the method implemented the five place
themselves at x = 190 / 231 / 277 / 350 / 400 with no widget change at all.

- [x] **B36.1/B36.2** Not implemented, and deliberately so — adding label-measuring and `prev`-chain
      placement to the `Menu` widget would have fought a working script. If a skin ever turns up that
      declares `<Menu prev=…>` with no placement script, that is when to build it.
- [x] **B36.3** Corpus check done: `<Menu>` with `prev`/`next` and no geometry appears only in this
      family. Pixel-diffed render sweep clean apart from the intended changes (see B37).

Follow-up, **not** in this change: `@HAVE_LIBRARY@` — carried to **BB5** above.

### B37 — Big Bento Modern renders wrong in the app (live, 2026-08-23) — **done 2026-08-23**

B35 made all four variants **load**; this was the list of what was wrong once they were on screen.
Five separately reported symptoms, and **one cause behind four of them**: 23 of the skin's
`onScriptLoaded` handlers aborted on `System.getSettingsPath()` (the skin probes
`<settings>/WACUP_Tools/koopa.ini` to sniff for WACUP near the top of nearly every script), so the
layout work in the rest of each handler never ran. `RENDER_SCRIPTS=1`'s `failed=` column says this in
one line per script and should have been the first probe, not `RENDER_PROBE`.

- [x] **B37.1 The menu bar items overlap** — fixed by `getSettingsPath`; see **B36**, whose proposed
      widget rule was the wrong fix.
- [x] **B37.2 The song ticker overruns its box** — `InfoDisplay` is clipped to its own 237px box, and
      always was (`drawText` does `context.clip(to: frame)`). What the screenshot showed was the box
      *empty of a time readout beside it*, plus the title drawn full-size across a display panel that
      had nothing else in it. With B37.3 fixed the panel reads `1:13` / `1:13 / 4:05` / title, and the
      title stops at the panel edge. No renderer change was needed.
- [x] **B37.3 The two display panels left of the ticker are empty** — the `display=` binding table
      knew only `time` / `songname` / `songinfo` / `PE_Info`. This skin asks for `TIMEELAPSED`,
      `SONGLENGTH`, `SONGTITLE` and `SONGSAMPLERATE`, which fell through to the literal `text=`.
      Added those plus `songartist` / `songalbum` / `songbitrate` / `artistname` (the whole corpus
      census) and `timerhours`. Also fixed, unreported: Ebonite_2_1 and Enkera's KBPS/KHZ readouts
      and mmd3's playlist-shade song length, all blank for the same reason.
- [x] **B37.4 The album-art panel is a solid black square** — the cover script aborted on
      `getAutoHeight` (masked behind `getSettingsPath`); it now draws its `no_alb_art` placeholder.
- **B37.5 The embedded library is unstyled** — the one item of B37 that did not close. It is
  **BB2** in *Open* above; do not track it here.

Two further fixes fell out, neither on the original list:

- **`offsetx`/`offsety` on a `<text>` were ignored.** They shift the string inside its own box without
  moving the box, and Big Bento's SUI tab captions are `offsetx="35"` — which is what puts them clear
  of the icon in icons+text mode and *outside the clip* in the 40px icons-only mode. Unblocking the
  tab script made every caption draw over its own icon until this was honoured. Six declarations in
  the whole corpus, all in this family.
- **The shade titlebar drew "WACUP" over "WINAMP".** Same `getSettingsPath` cause: the probe now
  answers "not WACUP" and the logo stays hidden.

Verified: `swift test` (1022, 0 failures, 13 new in `WinampModernPhase53Tests`) and the 30-skin,
289-image render sweep pixel-diffed against a pre-change build — 19 images changed, all four Bento
variants (intended), Ebonite_2_1 / Enkera / mmd3 (the readout fixes above, inspected), and Anexa's
`main-shade`, which differs between two runs of the *same* binary. Live QA on the four variants is
still outstanding.

**Follow-up, not in this change: `instantiate`** — carried to **BB1** above.

### B38 — Big Bento Modern, live defects found in QA (2026-08-23) — **closed**

Found by the user driving the app after B36/B37 landed. Neither of the first two reproduces in the
render harness, so both were diagnosed from the app's own `#if DEBUG` logging.

- [x] **B38.1 The window goes undraggable after shade → normal.** `shouldDragWindow(from:)` honoured
      `move="1"` on `<group>` only — 421 of the **981** declarations across the 30 installed skins,
      on 14 element types (`rect` 233, `layer` 151, `text` 66, `grid` 36, `grouplist` 34). Big
      Bento's titlebar is `<grid … move="1">` over `<rect id="vic_mover" move="1" fitparent="1">`, so
      the window could only be dragged wherever a bare background happened to be topmost, and a trip
      through shade changed which object that was. Now honoured on any non-control element; controls
      are excluded (17 declarations) because a button that both acts and drags eats its own click.
      Confirmed fixed live.
- [x] **B38.2 The playlist and the media library draw on top of each other at launch.** Two causes,
      one behind the other:
      1. `openHolders` — the `autoopen` fallback — forces a holder's hidden ancestors visible without
         knowing the other six tab pages exist (`sui.components` holds seven `<group visible="0">`).
         A restored session with both a playlist and a library window revealed both. It now reverts
         what it previously forced.
      2. That alone was not enough, and the log said why: **the skin's script opens its tab on its
         own timer, ~0.6s after our reveals.** All four launch reveals legitimately fell through to
         the fallback (the tab genuinely was not open *yet*), we forced the library page, and then
         `suicore.maki` opened the playlist it had decided on all along — with no idea a second page
         was open. So exclusivity is re-checked on every layout pass and always resolves the same
         way: **the page we forced yields to the page the skin opened.** Confirmed fixed live.
- [x] **B38.3 `getTextWidth` unsupported.** It aborted `onTextChanged` — the one handler that runs on
      every track change. (Distinct from `getAutoWidth`: how wide the string *draws*, not how wide
      the object wants to be. Skins compare the two to decide whether a caption fits.) **The rest of
      it**, found when B38.4 let the Multi Content View run: the file-info panel's `onSetVisible` —
      the handler that fills every line of it — then aborted on **`getDecoderName`**, and behind that
      on `getPath`, `getIdealVideoWidth` and `removePath` in turn. All four implemented; the panel
      now fills. `getDecoderName` answers the codec NullPlayer is decoding, `getPath`/`removePath`
      are pure string splits of a path the host already handed out, and the video pair answer 0 for
      the same reason `hasVideoSupport` is false. `getPlayItemMetaDataString("filename")` — which
      those splits are called on — now answers the playing item's location.
      *The harness could not see any of this*: `onTextChanged` is polled by the window controller, so
      `WINAMP_MODERN_RENDER_TEXT=1` was added to drive it (with `RENDER_PLAYLIST`, since both of this
      skin's bound text objects are `PE_Info` feeds).
- [x] **B38.4 The visualization box draws black over the album art.** The skin picks between the two
      panes from config attributes it registers itself, and at the defaults hides
      `info.component.vis`. That branch is in `mcvcore`'s **first** `System.onScriptLoaded()` — and
      the script declares a **second** one, so the "keep the last binding per (object, event)" rule
      introduced for Defix in Phase 42 shadowed it and *none* of `mcvcore` ran. The rule now drops
      only a binding whose **body repeats** an earlier one for the same pair (compared with jump targets relative to the
      entry point and variable slots renumbered, because the compiler gives each copy its own
      temporaries); two different bodies are two real handlers and both run. Defix's duplicated
      `ConfBT2.onLeftClick` still runs once, so its toggle does not flash.
      Three more things came back with it in the sweep, all previously recorded as fixed and all in
      fact still broken at HEAD: the Multi Content View's info display is laid out instead of sitting
      at its markup `x=80 w=0`, the full-width `info.component.coverflow` leaves the scene, and shade
      mode stops drawing **WACUP** over **WINAMP**.
- [x] **B38.5 The playlist-info panel takes half the top bar — not a defect.** `from="left"` anchors
      the divider to the left edge, so the right pane absorbs the extra width. That is what Wasabi's
      `from` means, what the skin's own `maxwidth="-300"` ("always leave 300 for the other pane") is
      written for, and what its script asks for with `setPosition(434)` against `minwidth="434"`. The
      window is wide because the layout declares `w="1536" h="878"` as its **default**. cPro-Bento's
      `centro.mainframe` is the same attribute the other way round (`from="right" width="200"`, its
      playlist column fixed and the left side growing), which confirms the reading. The huge song
      title is the skin's `fontsize="48"` in a 237px `InfoDisplay`; nothing in the corpus writes
      `fontsize` except `playlistpro.maki`, so no script is meant to shrink it.

Verified: `swift test` 1028 pass; 300-image corpus sweep across all 36 installed skins pixel-diffed
against a build of `HEAD`. 281 identical, 19 changed: the four Bento variants' `main-normal`,
`main-shade` and `searchresults-normal` (all four inspected — the Multi Content View fills, the
WACUP logo goes, and `searchresults` draws the 0 nodes the skin index says it should), Ebonite_2_1 /
Enkera / mmd3 (B38.3's readouts, already inspected in the previous pass) and Anexa's `main-shade`,
which differs between two runs of the same binary. B38.1 and B38.2 confirmed live by the user.
