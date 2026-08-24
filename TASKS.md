# Winamp 5.x Modern Skins (`.wal`) — Wasabi XML + MAKI UI System

Plan: `~/.claude/plans/i-want-to-support-frolicking-rabbit.md`

Add a fourth persisted UI mode `winampModern` backed by a third controller family that loads and
runs Winamp 5.x `.wal` skins (Wasabi XML/XUI renderer + MAKI bytecode runtime). Implemented phase by
phase; stop after each phase for review.

> **Phases 0A–34, 39–48, 51 are all closed.** Bugs B1–B13, B19–B20, B20a, B22, B23, B24, B26–B31
> are closed (**B23a is not** — see Tier 3). B32 is closed, below. **B35–B38 moved to
> `BENTO_TASKS.md`** on 2026-08-23 and are not repeated here. Everything else still open is below;
> each closed item's details live in git history.
>
> **There are exactly two backlogs, and both are tracked in git** (they were gitignored until
> 2026-08-23): this file for the `.wal` engine, and **`BENTO_TASKS.md`** for the Big Bento Modern
> family, which had grown to four sections of this one. Bug numbers do not collide — `B*` here,
> `BB*` there. A task that turns out to affect skins beyond Bento belongs here; add and update tasks
> in one of these two files and nowhere else. The old third copy
> `docs/winamp-modern/open-items.md` was deleted on 2026-08-23 after every item unique to it was
> audited: B19 (`ea4d9472`) and B22 (`df9d1028`) had shipped, and B23a was carried over below. Do
> not recreate it.

---

## B32 — `cfgattrib` toggles show no state, and crossfade drives nothing

mmd3's Crossfade / Shuffle / Repeat buttons are `cfgattrib`-bound togglebuttons whose *only* on-screen
indication is a pair of `ghost="1"` layers (`*Led`, `*Dis`) whose alpha `playertools.m` sets from
`getActivated()` and from `<toggle>.onActivate(int)`. Probe (`RENDER_PROBE=main/normal`): all three
buttons `activated=0`, all six indicator layers `alpha=0`, script ran clean (`failed=-`). Two root
causes, both engine-wide:

1. `getActivated()` reads `attributes["activated"]`, which `toggleConfigAttribute` deliberately never
   writes — so a config-bound button always reports off.
2. `onActivate` is dispatched from nowhere in the engine, so no skin's activation indicator can move.

And shuffle/repeat are stored **twice** (the config attribute, plus `host.shuffleEnabled` toggled by an
`xmlID`-matching special case in `performAction`), so the two drift the moment either side changes.

Corpus demand (30 installed skins): `{45F3F7C1…};Repeat` ×52, `;Shuffle` ×50,
`{FC3EAF78…};Enable crossfading` ×32, `{F1239F09…};Crossfade time` ×12. 8 skins reference `onActivate`.

- [x] **B32.1 `WinampModernConfigBridge`** — table of well-known `{GUID};Key` attributes that are
      *host state*, not skin-private storage: Shuffle, Repeat, Enable crossfading, Crossfade time.
      Read/write through the host; everything else keeps hitting `WinampModernConfiguration`.
- [x] **B32.2 Host crossfade surface** — `crossfadeEnabled` / `crossfadeSeconds` on
      `WinampModernHost`, backed by `AudioEngine.sweetFadeEnabled` / `sweetFadeDuration`, with
      inert defaults in the protocol extension for the harness/test hosts.
- [x] **B32.3 Route reads through the bridge** — `configValue(of:)`, `getcurcfgval`, and
      `getActivated()` on a config-bound object all answer the bridged value.
- [x] **B32.4 Route writes through the bridge** — `setConfigAttribute` writes host state for a
      bridged key, and still notifies `onDataChanged` exactly once.
- [x] **B32.5 Dispatch `onActivate`** — on a real change of activation, from `toggleActivation`,
      `setactivated`, and `toggleConfigAttribute` (to *every* object bound to that attribute, since
      mmd3 declares the same button in `normal`, `shade` and `shade2`).
- [x] **B32.6 Drop the `xmlID` shuffle/repeat special case** in `WinampModernMainView.performAction`
      — with B32.1 in place it double-toggles.
- [x] **B32.7 `cfgattrib` sliders** — a slider bound to an attribute (mmd3 `sCrossfade`, `high="20"`)
      must read its thumb from the value and write the value on a drag, in its own `low…high` unit
      rather than 0…255, so `onSetPosition` hands the skin the seconds it prints.
- [x] **B32.8 Verify** — `RENDER_CLICK` + `CALL_TRACE` on all three buttons: `setalpha(255.0)` on the
      indicator layers, `CLICK chain: … -> skin.xml.onactivate`. 1004 tests green, golden images
      green, 30-skin render sweep green (multipass improved degraded→full). Live on mmd3 via
      `WINAMP_MODERN_DEBUG_CLICK`: SHUFFLE/REPEAT lamps + words light, CROSSFADE lights and logs
      `AudioEngine: Sweet Fades enabled`.
- [x] **B32.10 The other direction.** Nothing observes `audioPlaybackOptionsChanged`, so shuffle
      toggled from NullPlayer's own menu moves the host and leaves the skin's lamp stale — the very
      drift the bridge exists to remove. Re-dispatch `onActivate` (and `onSetPosition` for a bound
      slider) for a bridged attribute whose value moved from outside the skin.
- [x] **B32.9 Land the findings** — `reference/rendering.md` (two new sections: the host-owned
      attributes, and `onActivate`), `compatibility/maki-surface.md` (`onActivate` row),
      `SKILL.md` (two routing rows, two section-map rows, file-map row), `skins.md` (mmd3 row —
      mmd3 has no `skins/mmd3.md` yet, so the summary table is where this landed), `CHANGELOG`.

Deferred, not in scope: `{280876CF…};Always on top` (×9) could bridge to
`WindowManager.isAlwaysOnTop` the same way; `{0000000A…};Random` (×15) is AVS preset randomisation,
correctly skin-private.

---

## Big Bento Modern — moved out of this file

**B35, B36, B37 and B38 are not here any more.** All four were the same skin family, and together
they were most of this file. They live in **`BENTO_TASKS.md`** — closed history and open items
(`BB1`–`BB5`) — under the same rules as this file, and tracked in git the same way.

Two notes for whoever reads this next:

- **`BB5` (`@HAVE_LIBRARY@`) is not Bento-only.** It also affects Styx, Shield_Amp, S7Reflex and
  Defix. Move it back into this file if it is picked up.
- **Nothing else moved.** Bug numbers stay unique across both files: `B*` is this file's series,
  `BB*` is Bento's. Do not reuse B35–B38.
- **Three items came back the other way on 2026-08-23.** The Bento header/settings research pass
  turned up three findings that are not Bento-specific — Bento is only where they were found — so
  they are **B39, B40 and B41** in *Tier 1* below, not `BB*`. `BENTO_TASKS.md` skips the three `BB`
  numbers the plan had given them, exactly as this file skips B35–B38.

---

## Open backlog

### Tier 1

These three came out of the Big Bento Modern header/settings research on 2026-08-23
(plan: `~/.claude/plans/abundant-pondering-hamster.md`) and are **here rather than in
`BENTO_TASKS.md` because none of them is Bento-specific** — Bento is only where they were found.
The Bento-only findings from the same pass are `BB6`–`BB15` there.

- [ ] **B39. A script's `setText()` must beat the object's `display=` binding.** Big Bento Modern
      draws the same song title on four stacked lines, and the skin's author documents the mechanism
      in the markup (`xml/player-normal-mcv.xml:378`):
      ```xml
      <!-- Victhor trick: display="SONGNAME" is used so ticker=1 actually works
           (the actual content of the text is set by script) -->
      <Text id="text" … display="SONGNAME" ticker="1" …/>
      ```
      That groupdef backs all **17** `Bento:InfoLine` objects (title, artist, album, track, year,
      genre, disc, albumartist, composer, publisher, format, comment, bpm, sname, surl, filepath,
      rating). Every one declares `display="SONGNAME"` **purely to enable tickering**, and
      `fileinfo.m` then fills each with `setText()` (~20 call sites).
      In our engine the two fight and the binding always wins:
      `WasabiTextMetrics.bound()` (`WasabiTextMetrics.swift:229`) answers `host.trackDisplayTitle`
      for `case "songname"` unconditionally, while `setText`
      (`WinampModernScriptRuntime.swift:2646`) writes `attributes["text"]` — which `bound()` reads
      **only in its `default:` branch**, i.e. only for an object with no `display=` at all. So all 17
      lines render the display title. **The layout is correct; only the content is wrong**, which is
      why it reads as "the title is repeated" rather than as a broken panel.
      The rule: a **non-empty** script `setText` overrides the `display=` binding; `setText("")`
      reverts to it. The revert half is not optional — MMD3's ticker fires `setText("")` a second
      after a `setAlternateText` and expects the bound title back (see the comment at `:2648`).
      Keep the override off the XML `text` attribute, the way `scriptAlternateTextKey` already does,
      so a skin cannot declare it in markup.
      **Sweep the corpus for every object carrying both a `display=` and a script `setText` before
      landing this** — it changes what any such object draws, in every skin, not just this one.

- [ ] **B40. Global browser routing remains denied, and that is why some skin buttons "do nothing".**
      `System.navigateUrl` / `System.navigateUrlBrowser` remain null-returning no-ops. The object-level
      `<browser>.navigateUrl` form now routes to that object's policy-gated WebKit surface, but global
      calls and `sui.sendAction("browser_search", …)` still need an explicit destination. The cost is
      that part of a skin's web-facing feature set presents as dead
      controls: Big Bento Modern alone has **92 `navigateUrl` call sites**, and its two magnifier
      buttons are the lyrics finder (Google/Bing) and the YouTube search
      (`fileinfo_lyrics_finder.m`).
      This is a **policy decision, not a bug** — but it is *less* open than it first looks, because
      **the skin already exposes the choice as a setting** and expects the host to honour it. Big
      Bento's Web Content config page declares
      `{0E17DBEA-9398-49e6-AE6F-3AB17D001DF3};Use Default Browser to open links` against a
      *"Web Reader (Internal Browser)"* alternative (`config.xml:1161–1172`), plus a Google/Bing
      choice. So the shape is: honour that attribute — external goes to `NSWorkspace`, internal goes
      to the in-app web view — rather than inventing a blanket rule. Keep the first-use confirmation
      for the external path; the URL is skin-chosen.
      **The WebKit prerequisite is complete** (2026-08-23): browser windows and tabs now provide the
      internal target. B40 is therefore unblocked, but still needs the skin's internal-vs-default
      browser setting and an explicit route to the intended browser object.
      One smaller piece of the same surface, independent of the browser work: `ML_SendTo` (Big
      Bento's `sendTo` button) is not in `WinampModernHostActions.swift` at all — wire it or mark it
      explicitly `.inert` with a reason, the way `CB_*` and `VID_TV` are.

- [ ] **B41. `getMonitorWidth()` / `getMonitorHeight()`.** Absent from the runtime; called from Big
      Bento's `sc_aerosnap.m`, `notifier.m` and `pledit.m`, where they drive AeroSnap edge-snapping
      and notifier placement. Cheap to answer from `NSScreen`, but **decide which coordinate space
      first**: scripts are deliberately held to the skin's own pixel grid (UI Size is applied at the
      view's drawing/input boundary and `getscale` answers 1, Phase 10), so a raw backing-store
      number here would put a skin's own arithmetic in a different space from everything else it
      measures.

- [x] **B42. `relat*` is `atoi(value) != 0`, not `== 1`. Done 2026-08-24.** `WasabiGeometry`'s flag
      reader accepted only `1`/`true`/`yes`, so every other number fell back to **absolute** geometry.
      Found live on Big Bento Modern, where it reads as *the album cover drawn twice*: the dimmed
      oversized backdrop in `info.component.albumbg` is `w="99" h="100" relatw="2" relath="2"`, and
      read as absolute it draws at a literal 99×100 — a small crisp second copy beside the real
      cover. Filed as BB6 against the album-art code; the cause was three layers away, in the
      geometry parser.
      Corpus: Big Bento Modern + its Windows 10 edition (1 declaration each, inherited by both Light
      overlays through the base's XML), Ebonite_2_1 (6), The_Nokia_5220 (2). corneramp_redux and
      Shield_Amp ship a literal `relatw="%"`, which `atoi` reads as 0 and which therefore stays
      absolute — unchanged.
      **A percentage reading is wrong**, though it fits Bento's `99`/`100` and Ebonite's `85`/`93`:
      Ebonite's own `group w="0" h="0" relatw="2"` would collapse to nothing at 0%, and `relatw="5"`
      is not a percentage. Landed in `reference/loading.md` → *Retained graph and coordinates*.
      `swift test` 1067 pass, 8 new in `WinampModernPhase56Tests`; corpus sweep pixel-diffed.

- [x] **B43. `fliph` / `flipv` were ignored engine-wide. Fixed 2026-08-24, confirmed live.**
      Neither attribute appeared anywhere in `Sources/`. Found live on Big Bento Modern, where the
      header analyzer group is a **butterfly**: `main.vis` (`fliph="1"`) and `main.vis2` sit side by
      side at 144px each so the two meet low-frequency-to-low-frequency in the middle, with
      `main.vis.mirror` / `main.vis.mirror2` (`flipv="1" alpha="110" ghost="1"`) as a dimmed 10px
      reflection under each. Ignored, that drew two identical copies with a seam and two reflections
      that were not reflected — reported as *"another bug is there are 2 of them"*, and the two **are**
      the skin's intent.
      Implemented at the one seam every kind of drawing passes through
      (`WasabiRenderer.draw(_ node:…)` → `applyFlip`), not in the bitmap path: the attribute belongs to
      the object, not to one way of filling it — the same lesson `alpha` taught in the two lines above
      it. Deliberately **after** both clips, so a flipped object cannot escape its box and a region
      mask stays where its author put it. `WasabiGeometrySpec.flag(_:)` was extracted from the
      initializer's closure so the flips read `"1"` exactly as `relat*` does (B42) rather than growing
      a second interpretation.
      Corpus: **all 16 declarations are on `<vis>`** and nothing else — Big Bento Modern + its Windows
      10 edition (4 each, inherited by both Light overlays), Styx (4, a 2×2 quad covering all four
      flip combinations — the strongest test case), multipass (2), Enkera (1),
      Nullsoft.Winamp.2000.SP4.Lite (1). So the general implementation costs no extra blast radius
      today, but a `<layer fliph="1">` is legal Wasabi and would have silently drawn unflipped.
      **Not verifiable headlessly:** Styx's quad is in a closed drawer, and Bento's group is gated
      behind `visualizer.maki`'s 730px player width — which `from="left"` pins at 434 at every window
      size (see B44), so no probe can reach either. Confirmed on screen by the user instead.
      `swift test` 1115 pass (11 new, `WinampModernPhase61Tests`), asserting the property that makes
      this safe: a flip is an **involution about the object's own frame**, so it cannot translate
      content out of its box.
      **Sweep: 290 images, 288 identical.** Anexa's `main-shade` is the known nondeterministic one.
      The other is a *correct* change and worth reading before it is mistaken for a regression:
      `Nullsoft.Winamp.2000.SP4.Lite`'s `xml/video.xml` declares the **same** `<vis id="shade.vis">`
      **twice** in the identical box — same colours, `mode="2" oscstyle="lines"` — with the second
      carrying `flipv="1"`. That is the classic Winamp mirrored scope, a trace and its reflection
      about the centre line. Ignoring the flag made the two coincide exactly, so it drew as one thin
      trace (mean vertical span 4.6px); mirrored, the pair spans 12.5px and reads as the intended
      symmetric double trace. Same idea as Bento's header, reached by a different route.
      **Method lesson, and it nearly cost a false regression:** this skin is an **NSIS** archive, not
      a zip, so the `unzip`-based corpus text scan skipped it silently — 35 skins in, 34 directories
      out — and it was the *one* skin the first scan claimed had no flip declarations while being the
      one image in the sweep that changed. A corpus scan that shells out to `unzip` under-reports; use
      `7zz`, and check the extracted directory count against the skin count. Landed in
      `reference/harness.md`.

### Tier 2

- [ ] **B33. An unclosed tag at EOF kills the whole skin.** `Shield_Amp` is the only skin of the 30
      installed that fails to load at all: `WalXML.swift:218` throws `malformedXML` "Unclosed
      <container> tag" on `opensource_notifier/notifier.xml`, pulled in by an `<include>` from
      `skin.xml:36`. The skin's own bug — that file opens two `<container>`s, closes one, and ends on
      `<script file="…"/>` — but Winamp loads it, and our parser is documented as *lenient*. The
      engine rule is that malformed optional input should **warn, not fail**.
      The fix looks cheap and safe: nodes are attached to their parent (or to `roots`) at **open**
      time, not at close, so by the time the `guard stack.isEmpty` runs the tree is already complete
      and correct — the unclosed container simply has all its children. Replace the throw with a
      warning `WalDiagnostic` at the open tag's location and return `roots`. `maximumDepth` already
      bounds how much can be left open, so nothing about the sandbox changes.
      Verify with the render sweep (Shield_Amp should go from `testok=0` to rendering its surfaces)
      and confirm no skin that currently loads changes. Consider a fixture: a synthetic `.wal` whose
      XML ends mid-tree, asserting it loads with a diagnostic rather than throwing.

- [ ] **B21. `enqueueFile` / `playFile` — skin-supplied path ingest.** `PlEdit.enqueueFile(path)`
      (cPro-Bento) and `System.playFile(path)` (T800) hand the host a filesystem path the *skin*
      chose. Deliberately left out of B8: it is a sandbox policy decision (what may a script add to
      the queue, and from where), not an arity question. Note `clear()` **is** implemented and these
      are not — safe today only because cPro-Bento's one caller early-returns on
      `ClassicProFile.findFiles`'s bounded `-1` long before its `PlEdit.clear()`. Decide the policy
      before implementing either, and check that pairing again

### Tier 3 — narrow, latent, or a decision rather than code

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
- [ ] **B23a. `.visualization` embedded in a player (BLAKK).** Carried over from the deleted
      `open-items.md`, which is the only place it was ever tracked. BLAKK reaches a visualization
      holder **in its player** and declares no AVS container, so its engine could live in that box
      instead of our own window. Deliberately left alone by B23 — no report, no measurement of what
      the box should show. Still true as of 2026-08-23: `BLAKK/xml/blakk-remote.xml:88` declares
      `<groupdef id="blakk.component.vis"><component id="vis" w="144" h="125" …
      hold="guid:{0000000A-000C-0010-FF7B-01014263450C}"/></groupdef>`, placed at `x="8" y="34"`
      inside `blakk.remote-avsgroup.group` with its own `VIS_Menu` / `VIS_Prev` / random-preset
      controls alongside.
      **Do not be reassured by the corpus table.** `reference/components.md:664` reads "8 of the 31
      installed skins… none embeds the component in the player," and BLAKK is absent from it — that
      is a probe blind spot, not a contradiction. The holder lives in the `remote` layout
      (`blakk-remote.xml:113`), not the default `boombox` one, so a visibility-filtered `VIS holder`
      sweep never sees it. Identical to the failure mode B23 already recorded for
      `VIDEO holder … hidden`, and exactly what B16 warns about. Fixing the probe to print a hidden
      holder is probably the first step, and would also re-answer B16.
- [ ] **B34. The thinger is empty in every skin that has one.** `<componentbucket>` is Winamp's
      scrolling strip of *installed component* icons (Media Library, AVS, plugin buttons) — click an
      icon to open that component, and the `<text display="componentbucket">` beside it names the
      focused one. NullPlayer hosts playlist/EQ/library surfaces but publishes no **icon set** for a
      bucket to enumerate, so every bucket draws empty, its caption stays blank, and
      `CB_NEXT`/`CB_PREV`/`CB_NEXTPAGE`/`CB_PREVPAGE` are `.inert(reason: "component bucket holds no
      icons to scroll")` in `WinampModernHostActions.swift:66`. Correct-and-recorded today, not a
      defect — this item is the feature that would make it real.
      Corpus demand, measured 2026-08-23 over all 40 `.wal`s (35 installed + 5 in `~/Downloads`):
      **14 skins**, splitting into two roles. *Thinger* (12, `CB_NEXT`/`CB_PREV`) — Mini_Me_2 ×10
      (one bucket per skin variant, `skin1thinger`…), mmd3 ×3 (`normal` + both shades), Lobe ×2,
      then boom_by_adil_daqyn, Capsule_II, corneramp_redux, Hoop_Life_WA3, Media_Whore, Overdrive_2,
      Styx, ZDL_Reel-To-Reel, Lapis_Lazuli ×1. *Config-drawer paging* (2, `CB_*PAGE`) —
      winampmodern566 and S7Reflex, already recorded in `skins/winamp-modern-stock.md:88`.
      Three traps worth knowing before starting:
      - **Four skins put the thinger in its own container**, not the player body —
        boom_by_adil_daqyn and corneramp_redux declare `<container id="Thinger" default_visible="0">`,
        ZDL and Lapis_Lazuli have dedicated thinger layouts. Those present as an empty *window* off
        Skin Windows, not a dead widget. ZDL's `EQ` + `thinger` pair is at `skins.md:46`
      - **Lapis_Lazuli declares a bucket with no arrows at all**, so it needs the icons but exercises
        no scroll path — the cheapest render-only check
      - **Lobe's arrows are correctly unhittable at rest** (`skins/lobe.md:100`): its thinger group
        sits at z-order 10–11 behind `metalbg` at 68. Do not read that as a regression when the
        icons land
      One icon set published from the component registry lights all 14 up at once; none needs
      skin-specific work. Verify with the render sweep plus a live check on mmd3 (in-body circle) and
      corneramp_redux (own container).

### B25 — The startup `autoopen` fallback forces a tab open behind the skin's back

`WinampModernMainWindowController.revealEmbeddedSurface` falls back to `openHolders`, which walks up
from an `autoopen="1"` holder writing `visible="1"` onto every hidden ancestor. At launch on
cPro-Bento this fires for the library (`WinampModern reveal library … opened=1`): the SUI's own tab
bookkeeping never learns that tab was opened, because the app opened it directly on the graph.

It exists because ClassicPro's `onGetCancelComponent` no-ops at startup (`active_tab` is already 0
while `centro.library` has never been shown). **With the MAKI `NULL` coercion fix in place that no
longer holds:** run with the fallback disabled and cPro-Bento's library tab renders correctly at
startup on its own. So the workaround now looks obsolete for this skin while still desynchronising
the skin's state.

- [ ] Measure which corpus skins actually depend on `openHolders` (B23's video reveal is one caller;
      the Skin Windows menu and a script's `TOGGLE guid:…` are others)
- [ ] Decide: drop the fallback, or keep it and make it reversible (record what was forced and put it
      back when the skin switches away)
- [ ] Verify the startup library tab, the video tab reveal, and the Skin Windows menu on cPro-Bento
      and on a skin with a declared container, before and after

---

## Pending live verification

These items are code-complete and passing tests, but have not yet been verified in the running app.
Big Bento's own pending verification is `BB4` in `BENTO_TASKS.md`, not here.

- [x] **B32.10 verified 2026-08-23:** manual QA on mmd3 passed — the lamps and display
      words follow both the skin's own buttons and the Playback menu, and crossfade drives Sweet
      Fades. B32 is closed.

- [ ] **B23 harness:** `VIDEO holder` line should print for an embedded holder too (it prints per
      container/layout today and the tab's group is hidden at load)
- [ ] **B24 verify:** Live on cPro-Bento: Media Library → Playlist → Media Library → Playlist, and
      the Video tab
- [ ] **B26 verify on Lobe:** the `CT` button opens the window, the picker lists 43, Switch applies one
- [ ] **B26 verify on BLAKK and Ebonite_2_1:** the player opens at all, and its other layouts
      (`remote`/`stick`, `compact`/`mini`) still switch from whatever the skin binds them to
- [ ] **B28 verify:** Live on Lobe **and** on a tall skin (cPro-Bento), for the visualization and
      library windows, at 1× and 2×. Note Lobe cannot exercise the library half — its catalog reads
      `library=synthesized:nullplayer.library`, so the surface coordinator opens the skin's own
      synthesized window and never reaches `rightDockedSideFrame`. That half needs a skin whose
      catalog reads `library=classic(...)`
- [ ] **B30 verify on LOBE:** drag the dial and the volume strip
- [ ] **B30 verify on Styx** (volume) and **mmd3** (knobs unchanged — its group is at the origin)
- [ ] **B31 verify on Lobe:** the Pledit window shows playlist content
