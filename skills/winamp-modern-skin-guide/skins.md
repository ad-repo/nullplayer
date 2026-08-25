# Per-skin status

What each measured `.wal` fixture actually does in NullPlayer today, and what is still missing **for
that skin**. The engine-wide surface is [compatibility.md](compatibility.md); this file is the
skin-by-skin view, because a `.wal` skin exercises an arbitrary slice of Wasabi and two skins can fail
in completely different ways while the compatibility report says the same thing about both.

Nothing third-party is committed — every skin here is user-supplied. See
[manual-qa-checklist.md](manual-qa-checklist.md) for how to run one.

**How a skin's file gets written.** Run `/wal-skin-report <skin.wal>` (`skills/wal-skin-report`) — it
measures the skin in a fixed order and emits the full structured report; `skins/<skin>.md` is the
durable summary distilled from it, not a second measurement. The report is a snapshot and lives
outside the repo; the trap list and the "knowingly missing" list belong in the skin's file.

**Keep this current.** When a phase closes on a skin, update its row below *and* its file: the phase
it was fixed in, what came alive, and what is knowingly left. A skin's own `screenshot.png`, when the archive ships one,
is the reference to compare against.

**Colour themes, measured (Phase 32, `WINAMP_MODERN_RENDER_THEMES=1`).** Themes / `<ColorThemes:List>`
objects in the graph / `colorthemes_*` actions: mmd3 82/4/4 · multipass 58/1/3 (**corrected in Phase 33** — the
Phase 32 measurement read 58/0/3 and concluded the skin ships no list; it ships one, in a groupdef
only `System.newGroupAsLayout` instantiates, and that method was refused) · winampmodern566 44/1/5 ·
micro 24/0/0 · Anexa 11/0/0 · Rika 10/1/0 · cPro-Bento 6/1/3 · Defix 5/1/1 · CornerAmp 5/1/3 ·
T800 2/0/0 · ZDL 1/0/0 · Love is War Miku, Sony Walkman, Nokia 5220 0/0/0. **Ujola Cat 19/1/1** (Phase 34). **Itemskin and Overdrive_2 load as of
Phase 35** (they were `resourceMissing` on `xml/eq.xml` and `xml/pledit-elements.xml`); their theme
counts above are the pre-Phase-35 reading and neither ships a picker.

**The equalizer events, measured (Phase 41, `WINAMP_MODERN_RENDER_EQ`).** Five of the 17 skins handle
`onEqBandChanged` / `onEqPreampChanged` and all five answer now: multipass (14 `ledfillbar` programs
per event, band **and** preamp) · mmd3 (`skin.xml`, band only — it handles no preamp event) · Rika
(`eq.xml`, both) · winampmodern566 (`configdrawer.xml`, both) · Overdrive_2 (`scripts.xml`, band). The
other twelve declare neither handler.

**The keyboard, measured (Phase 43, `WINAMP_MODERN_RENDER_KEY`).** `System.onKeyDown` carries Winamp's
accelerator *string*. **Three** of the 17 skins bind one — multipass (`skin.xml`, `alt+g` → EQ
drawer) · winampmodern566 (five programs; `alt+g` → EQ drawer, `ctrl+w` → shade the active window,
`alt+a` → the album-art window) · Defix (`PLAYLIST_WINDOW.xml`, `esc` → close the playlist search
line, and it runs no `complete;` so the key still falls through). Rika and T800 count in a grep of
the backlog's five but do **not**: they ship Winamp's stock `playlisteditor.maki`, whose `onKeyDown`
is the *edit control's* (`onKeyDown(Int vkcode)` — a GUI receiver and an integer), and neither skin
loads that program at all, because their playlist windows are ours. The other twelve declare none.

**Windows a skin opens with itself, measured (Phase 40, `default_visible="1"` on an auxiliary
container).** 10 containers in 8 of the 17 skins: Defix `Config` + `pledit` · winampmodern566 `Pledit`
+ `winamp.albumart` · Ujola Cat `PLEdit` + `ujolaCat` · ZDL `EQ` + `thinger` · Overdrive_2 `Pledit` ·
Love is War Miku `notifier` (**suppressed** — host-managed transient) · Rika and T800 `Warp Browser`
(**opened** — real embedded browser). The other nine skins declare it nowhere.

**Video windows, measured (Phase 47 / B20, `VIDEO holder` in the render dump).** **15 of the 33
measured skins** declare a `<container>` for the video component, and all of them now host the real
picture — parked as a child window over the box the skin draws (see
[reference/components.md](reference/components.md) for why it is a child window and not a subview).
By box width: hatsune_miku_5 429×340 · Ujola Cat 390×91 · mmd3 375×190 · winampmodern566 342×232 ·
multipass 332×113 · corneramp_redux 310×164 · Styx 284×59 · Itemskin 277×71 · Anaheim_Player_01
240×120 · Love is War Miku 240×184 (V2 240×190) · Ebonite_2_1 227×172 · BLAKK 192×125.
**Hoop_Life_WA3 and Media_Whore** declare the container but render **no `<component>` holder**, so
they correctly fall back to NullPlayer's own video window. Only **mmd3 and BLAKK** ask for Winamp's
command bar (`noshowcmdbar=` absent) and both boxes are under its 395pt constraint minimum, so no
corpus skin actually gets one.

**Visualization (AVS) windows, measured (Phase 48 / B20a, `VIS holder` in the render dump).** **8 of
the 31 installed skins** declare a container around the visualization *component*, and all of them now
hold the real engine — ProjectM/MilkDrop, Geiss or Tripex, as a subview at the box the skin draws
(see [reference/components.md](reference/components.md) for why this one is a subview where the video
picture is a parked window). By box size: hatsune_miku_5 `avs` 479×326 · winampmodern566 `AVS`
342×232 · multipass `avs_window` 298×134 · Itemskin `AVS_window` 277×71 · Styx `AVS` 220×200 ·
Anaheim_Player_01 `avs_window` 100×200 · Love is War Miku `avs` 190×84 (V2 190×90). **Confirmed live 2026-08-21** (Bento, both Miku skins, Anaheim, Styx). **These eight are
the live-QA list**, and each is opened from **Skin Windows** (no skin in the corpus
binds a button to its own AVS window, which is why routing alone left them unreachable in the first
live pass). A skin's `<vis>` box is a different surface and stays the
engine-drawn analyzer/oscilloscope. The other 23 skins declare no AVS container and NullPlayer's own
visualization window serves them as before.

**Containers with no `normal` layout, measured (B26, 2026-08-21).** A container used to be opened
only at the layout named `normal` (or its sole layout), and anything else was dropped — the main
window's own renderer included, which failed the whole skin. **Six containers in six skins**:
BLAKK `main` (`boombox`/`remote`/`stick`) and Ebonite_2_1 `main` (`full`/`compact`/`stick`/`mini`/
`minivert`/`narrow`) — **both of those skins showed the load placeholder and now render their
player** — LOBE `Color Themes` (six `about*`), and the wasabi standard `Component` shell in Anexa,
Sony_Walkman and boom (kept out of **Skin Windows**: its `name` is the unresolved `:componenttitle`).
The rule is now the first declared layout, Winamp's own.

| Skin | Last worked | State | Biggest gap |
|---|---|---|---|
| Love is War Miku | Phase 39 | renders and drives correctly; its visualization window's **Fullscreen / Prev / Next / Menu** and its video window's **Fullscreen / Options** buttons all answer (Phase 39) | `fliph`; oscilloscope is a mirrored spectrum; its video **1x / 2x / TV** buttons are accepted and inert |
| mmd3 | B32 | text, knobs, drawers, own display all live; **its 82 colour themes list and switch** (in-player drawer + the `ctsbig` window); **its Crossfade / Shuffle / Repeat lamps and display words light** — from its own buttons *and* from the Playback menu — and Crossfade drives NullPlayer's Sweet Fades (B32, GUI-verified 2026-08-23) | other `wasabi.*`-backed widgets still draw empty; no scrollbar on the theme list |
| cPro-Bento (+ ClassicPro engine) | Phase 32 | SUI body drawn and framed, live tabs, beat vis, playlist, embedded library, **script-built menus** | Guilist widgets |
| Winamp Modern (stock) | Phase 43 | frame, script-built body, playlist + library, **EQ drawer**, **centred title + streaks**; its 22 `VIS_*`/`PE_*`/`VID_*` toolbar buttons answer (Phase 39) — the widest host-action demand in the corpus; its **keyboard shortcuts** answer (Phase 43): `Alt+G` toggles the EQ drawer, `Ctrl+W` shades the focused window, `Alt+A` the album-art window. It is the only skin in the corpus whose key handlers gate on `isActive()` | the 1px title overlay keeps its declared slot; its config drawer's `CB_*` scroll arrows stay inert (the bucket holds no icons) |
| CornerAmp Redux | Phase 32 | frame, titles, playlist + EQ, **the `Color Themes` window populates and its Switch / Prev / Next work** | synthesized library window |
| T800 | Phase 32 | per-layout groups, region-clipped volume, drag; its 2 colour themes from the host **Color Themes** menu | ships no picker of its own (as in Winamp) |
| ZDL Reel-To-Reel | Phase 18 | sized from its background art; its 13 `dblclickaction="SWITCH;…"` titlebars switch normal/compact/shade (Phase 36) | — |
| Rika | Phase 32 | loads without its missing TTF; vis colours honoured; its `Color Themes` window lists all 10 and a double-click applies | no Switch button in the skin — double-click is the only in-skin route |
| multipass 1.4 | Phase 43 | **the whole skin**: one refused method aborted `System.onScriptLoaded`, so drawers, seek, time, sliders, notifier, shade, behaviors and style never initialised. All of it now runs; the hover drawers animate, the bottom drawer opens from its toggle, and the 58-theme picker instantiates at (54, 217); its seek bar draws, takes a click across its whole width and seeks; its `≡` main-menu button opens the host menu. **Confirmed live** 2026-08-19 | its eleven `ledfillbar` EQ bars follow a preset, the menu bar and the classic EQ window as of Phase 41, not just its own drags; its balance slider works (Phase 37, `PAN`), readout included; **`Alt+G` opens and closes its EQ drawer** (Phase 43, confirmed live 2026-08-20); the `.wal`'s own Preferences route (`TOGGLE {53DE6284…}`) has no host window |
| Defix Hi-End 200 | Phase 26–31, 43, 45 (**confirmed live** 2026-08-19; measured `/wal-skin-report` 2026-08-19 — **B**, confidence medium) | wood panel + framed windows, cassette display, **live SUI tabs + embedded library**; display styles and songticker modes selectable through **Skin Settings**; **the four round buttons' right-click assignment menu** (Phase 31); **all eight display styles animate smoothly** — needles and cassette reels through Layer FX, level strips through frame strips; frame cost 18.3 → 3.5 ms at Retina scale; VU fed block-played peak amplitude that falls to rest on silence | round buttons re-assign but mis-target after the swap (Phase 31, open); speaker cones static **and cabinets very dark** (live 2026-08-19); time readout click dead; **the whole `PlEdit` playlist API answers as of Phase 42** (`getcurrentindex` closed — the cause was the parser reading every `system`-flagged global as the System object) and **its round buttons no longer open-and-shut their window in one click** (a duplicate `ConfBT2.onLeftClick()` declaration ran twice); **the `ML` round button still needs another window opened once before it works** (open); its bottom-bar **VIS Previous/Next/Presets/Options** and **playlist Add/Rem/Sel/Misc/Manage** buttons answer as of Phase 39; **its `Config` and `pledit` windows open with the skin** as of Phase 40 (confirmed live 2026-08-20); its `esc` key handler runs as of Phase 43 (it closes the playlist search line when that is up, and runs no `complete;`, so the key falls through otherwise); `fx_setBgFx(1)` / `fx_onGetPixelA` accepted and inert; **its configurator drives everything but the scaling buttons as of Phase 45** — the 31 backgrounds now reach all five framed windows (a script's `setData` broadcast to one holder), the 31 stickers, the three pages, six of the eight display styles (`Ovis 1`/`Ovis 2` are the skin's own empty branches) and the songticker modes through Skin Settings — `phase-29-handoff.md` |
| Itemskin | Phase 39 | its ten `VIS_*`/`PE_*`/`VID_*` buttons answer (Phase 39). Loads and renders as of Phase 35 — main, mini and Equalizer layouts, the playlist/video/library/AVS windows and the notifier. Its `<include file="xml/eq.xml">` names a file the archive does not ship and is now skipped with a warning | its notifier script wants `getPath` and `setChecked`, which is why its compatibility level reads `unsupported` although the skin draws; unmeasured beyond the render sweep |
| Shield_Amp | B33 (**confirmed live** 2026-08-24) | **loads for the first time** — it was the only skin of the 30 installed that failed outright, and it now renders all nine of its surfaces: `main/normal` and `main/stick`, the equalizer, AVS, Video, MLibrary, the notifier and its Configuration window. The cause was its own bug — `opensource_notifier/notifier.xml`, `<include>`d from `skin.xml:36`, opens two `<container>`s, closes one, and ends on `<script file="…"/>` — but Winamp loads it and our parser is documented lenient, so an unclosed tag at EOF is now a warning (see [reference/loading.md](reference/loading.md) → *What the XML parser tolerates*) | `RENDER-DUMP dropped container: Pledit (no layout)` — the skin declares a playlist container with no renderable layout, so its `PL` button likely opens nothing (open, found by B33's sweep). Its notifier script wants `setChecked`, `setXmlParam` and `urlEncode`, all inert. Nothing beyond the render sweep and one live launch has been measured |
| Overdrive_2 | Phase 35 | loads and renders for the first time — the speedometer/tachometer face, transport ring and shade layout. All five of its MAKI programs run, including `scripts/seek.maki`, which is written in the pre-5.0 bytecode layout | the playlist window is furnished by the `pledit-elements.xml` it does not ship, so it is near-empty; unmeasured beyond the render sweep |
| Ujola Cat | Phase 34 (**confirmed live** 2026-08-20) | **first measurement.** Both drawers, embedded EQ, the cat window, its 19-theme picker; its seven playlist/video toolbar buttons (Phase 39); **the Color Themes and cat buttons** (they carry no `action` — `Container.toggle()` is their whole behaviour) and the console lamps that follow their windows; the `<vis>` analyzer now follows the colour themes, draws Winamp's bands on a dB scale and paints its peak caps; the framed windows stop painting their `sysregion="-2"` masks — [skins/ujola-cat.md](skins/ujola-cat.md) | the window *region* those masks describe is still not applied (the windows stay rectangular); `<eqvis>` ignores `gammagroup`, as in Winamp |
| LOBE | B26–B28, B30 (**confirmed live** 2026-08-21; measured `/wal-skin-report` 2026-08-21 — **D** at measurement, **C** after) | draws and animates correctly (ticker, time, both level-driven "vis" pods); equalizer window follows the host on all ten bands; **ten dead main-window controls came alive** — this skin is the diagnosis for the `alpha > 0` region floor (B27), its glassy art being max alpha 79 with each glyph engraved at alpha 3 against the old `> 8`; its side windows open at the established 464pt column rather than 4× its own 300pt canvas (B28); **its seek dial and volume strip answer** — both are `Map`-sampling animated layers in placed groups, and mouse events now carry the parent-relative point Wasabi defines (B30) | **its About / Colour Themes / manual window exists again** — six layouts, none named `normal`, so the container used to be dropped silently; a container with no `normal` layout now opens in its first one and all six pages render with the 43-theme picker (B26, live verification owed); the seek dial stays dead at its centre (all 13 frames transparent there); `main/switch` is the author's abandoned work, settled by disassembly — [skins/lobe.md](skins/lobe.md) |
| Big Bento Modern ×4 (base, Light, Windows 10 edition, Windows 10 edition Light) | B35, 2026-08-23 | **all four load and render for the first time** — 38 scenes, 80–82 bitmaps in `main/normal`. Three independent causes each fatal on its own: `@SKINSPATH@` was an undefined path variable; the two *Light* editions are **overlays** that pull 6 of their 8 includes out of the base archive (so the base must be installed, under its own name — a lazily mounted sibling, ≤4 per load); and the Windows 10 edition ships a **zero-byte** `window/no_alb_art_shade.png` that failed the whole skin. The Light editions render in their own light palette against the base's artwork — [skins/big-bento-modern.md](skins/big-bento-modern.md) | **B36/B37, 2026-08-23:** five separately reported defects — an overlapping menu bar, a black album-art panel, empty time readouts, a WACUP logo over the Winamp one, a stale search banner — all had **one** cause: 23 `onScriptLoaded` handlers aborted on `System.getSettingsPath()`, which the skin calls near the top of nearly every script to sniff for WACUP. Fixing it surfaced `getAutoHeight` / `getGuid` / `scrollToPercent` behind it. Plus two independent gaps of our own: the `display=` table did not know `TIMEELAPSED` / `SONGLENGTH` / `SONGTITLE` / `SONGSAMPLERATE`, and `offsetx` on a `<text>` was ignored (which is what hides the SUI tab captions in icons-only mode). `instantiate` was still unimplemented — it gated the config pages and the EQ tab and was why the level read `unsupported` (**BB7, 2026-08-23**: implemented as a `GroupList` method that stacks its entries, with `getApplicationPath` behind it; the level is now `degraded`); bitmap overrides in the overlays do not win (see its file). **B38, 2026-08-23:** live QA found five more. The one with reach beyond this skin: `mcvcore` declares `System.onScriptLoaded()` **twice with different bodies**, and the Phase 42 "keep the last binding per (object, event)" rule shadowed the first — so the whole Multi Content View never ran, and the visualization box drew black over the album art. Only a binding whose *body repeats* an earlier one is dropped now. Behind it, the file-info panel's `onSetVisible` cascaded through `getDecoderName` → `getPath` → `getIdealVideoWidth` → `removePath`. The wide-window pane split turned out not to be a defect. **BB7/BB8, 2026-08-23/24 (both confirmed live):** the nine config pages and the SUI equalizer tab are built — each is an empty `<GroupList>` in markup whose content the skin's script expands with `instantiate`, so the EQ tab drew its preset bar and nothing else; and the 77-theme picker applies a theme, through `ColorMgr.getGammaSet(name).apply()` bound by class GUID. Compatibility level is now **degraded** |

| Sony_Walkman | BB2a, 2026-08-25 | its analyzer draws in the grey it asks for. Every band is declared `colorband1="#808589"`, and `#rrggbb` was parsed by a branch left gated off behind `if false` in `8c7e0567` — whose own commit message says it lands that parse — so all 16 bands fell through to `unparseableColor`, i.e. **opaque white bars straight across the SONY wordmark**. See `reference/rendering.md` → *How a colour resolves* | unmeasured beyond the render sweep; its wasabi standard `Component` shell is one of the six containers with no `normal` layout (B26) |

| Ebonite_2_1 | BB2a follow-up, 2026-08-25 | its embedded/fallback surfaces were **white text on a near-white panel**. It declares `wasabi.list.background` twice — a `<color>` at 70,70,70 (*"lists/trees item background"*) and a `$solid` bitmap at 237,237,237 (*"Tree background bitmap (tile)"*), the tile last — and its `wasabi.list.text` is white. A real `<color>` now outranks a generated bitmap for colour lookups, so the panel is 70,70,70. Opens on `full` (197×297); it declares no `normal` layout (B26) | its five other layouts are unverified live (see the B26 entry in `TASKS.md`); its **selection row is still unreadable** — that is B48, which is corpus-wide |

---

## Where each skin's detail lives

One file per measured skin. A pointer that says "read `skins.md` for skin X" resolves here in one hop.

| Skin | File |
|---|---|
| cPro-Bento (+ ClassicPro engine) | [skins/cpro-bento.md](skins/cpro-bento.md) |
| Winamp Modern (stock 5.x) | [skins/winamp-modern-stock.md](skins/winamp-modern-stock.md) |
| Love is War Miku | [skins/love-is-war-miku.md](skins/love-is-war-miku.md) |
| Defix Hi-End 200 | [skins/defix-hi-end-200.md](skins/defix-hi-end-200.md) |
| multipass 1.4 | [skins/multipass.md](skins/multipass.md) |
| Ujola Cat | [skins/ujola-cat.md](skins/ujola-cat.md) |
| LOBE | [skins/lobe.md](skins/lobe.md) |
| Big Bento Modern (all four variants) | [skins/big-bento-modern.md](skins/big-bento-modern.md) |

The other skins in the table above are rows only, and stay rows until one is measured with
`/wal-skin-report`. When that happens, add `skins/<skin>.md` and a row here.

### Trap index

Every measured skin sets traps that have already cost phases. Each file's **Traps this skin sets**
section is the list; read it *before* changing engine code on that skin's behalf.

- [cPro-Bento](skins/cpro-bento.md#traps-this-skin-sets) — relative geometry, `newGroup`/`init`
  two-step, `RENDER_XUI` misreading, frame-pane clipping
- [Love is War Miku](skins/love-is-war-miku.md#traps-this-skin-sets)
- [Defix Hi-End 200](skins/defix-hi-end-200.md#traps-this-skin-sets) — unseeded background preference,
  alpha-multiplexed readouts, `rectrgn` hit testing, `findObject`'s wide lookup, timer-gated tabs
- [LOBE](skins/lobe.md#traps-this-skin-sets) — `degraded` inflated by legal double-includes,
  `CLICKABLE` under-reporting, `RENDER_CLICK` naming the fall-through and not the rejected control,
  ghost-dependent hover overlays, `skin windows` over-reporting (closed by B26)

## Reference targets

Three skins drove the implementation, in increasing order of demand:

| Target | Role | Detail |
|--------|------|--------|
| **CornerAmp_Redux** | first vertical slice | loads, scripts, renders its 246×228 alpha-shaped layout, button input routed |
| **Winamp Modern** | compatibility expansion | [skins/winamp-modern-stock.md](skins/winamp-modern-stock.md) |
| **cPro-Bento** + ClassicPro engine | north-star | [skins/cpro-bento.md](skins/cpro-bento.md) |

None of these ship with NullPlayer. All fixture-based tests are opt-in behind `WINAMP_MODERN_WAL` /
`WINAMP_MODERN_ENGINE`; everything committed is synthetic and self-authored.
