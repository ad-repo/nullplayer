# AIMP skin family — backlog

The only backlog for the AIMP skin family. Read `skills/aimp-skin-guide/SKILL.md` before picking
anything up; the family pattern is `skills/skin-subsystem-blueprint`.

- **Done** rows are numbered `A<n>` in the order they landed; the next free number is A29.
- **Next** is ranked by how many corpus skins a row reaches, measured by the census
  (`reference/harness.md`); a row moves to Done, numbered, in the change that closes it.

## Done

- A1 Loader and model: `.acs5`, `.acs4`, `.acs4proj`; `ACLIMG32`; `SXML`/`BXML`/text XML; bounded by
  `AIMPSkinPolicy` (`AM0001`–`AM0011`).
- A2 Static renderer: item docking and flow, `PlaceInfo`, nine-slice, buttons, captions, sliders,
  filmstrip sliders, visibility bindings with expressions.
- A3 In-app probe: census and render (`reference/harness.md`). Kanono and Vega MP-120 render close
  to their screenshots; Soot does not (script-driven).
- A4 Deck corpus (2026-10-31): 45 non-4K deck skins from the aimp.ru catalog with their screenshots
  (`~/projects/aimp-skin-lab/corpus/shots`). 12 `.acs5` and 18 `.acs4` installed in the corpus
  folder; 16 `.acs3` set aside. 27 of 30 render.
- A5 The mode: `PlayerUIMode.aimp` / `PlayerUIControllerFamily.aimp` (single canvas, own runtime);
  `AIMPSkinMainWindowController` (a `SingleCanvasMainWindow`) and `AIMPSkinMainView`; hover and
  pressed frames; actions mapped to NullPlayer (`AIMPSkinAudioEngineHost`); volume and seek drags;
  `.acs5`/`.acs4`/`.zip` import; the Skins › AIMP submenu. Auxiliary windows: the shared
  controllers in the neutral style, as Audion's.

- A6 Skin state and scripts: tab pages turned by keys, `Schema.xml` providers evaluated
  (`AIMPSkinDataflow`), `DigitsDisplay`, text templates, resource aliases, and a first FastScript
  interpreter (`AIMPSkinScript`). Vega: cassette stickers change with the tape-type keys, the song
  shows on the cassettes that print it, and the tape counter runs.

- A7 Corpus batch (2026-10-31), ranked by how many skins each item reached:
  - all 30 decks render (`.myimg`, AM0005/AM0007 measured, zero-size docked items);
  - control types: `TimeDisplay`, `SpectrumDisplay`, `Gauge`, `Animator`, nested controls;
  - interaction: hit masks (the frame left after whole `FramesPerState` runs), tab selectors,
    script event handlers, script counters, skin timers (`LogicalOperatorTimer`);
  - FastScript: scopes, nested routines, `with`, loops, `exit`, `const`, arrays, sets, math,
    `Delete`, indexed properties (`Data.Spectrum[ch, i]`). Every corpus script runs
    (`AIMP_RENDER_SCRIPTS=1`);
  - scripts drive the EQ (`BandValueN`, `PreampValue`), balance, speed, effects; handlers run on
    track start/finish and on bound values; visualization handlers kick speaker cones and fade
    color-music lamps;
  - companion windows (speakers, amplifiers, EQ units, remotes, color music) beside the deck;
  - `EqualizerDisplay`, `CoverArtDisplay`, `IsActive` (pointer over), tooltips from `Hint`;
  - actions: open files, DSP/EQ window, seek, speed, stay on top, track info.

- A8 `.acs3` (2026-11-01): the container (keys from the name when there is no preview) and
  `ASEIMG32` images; 15 of the 16 corpus decks render close to their screenshots. Panels docked
  side by side size the window (Sony ES-Style Silver 2).

- A14 Scripts the crawl stopped on (2026-11-02): a counter's state parameter under any name,
  units without `Execute`, `var` initializers and parameter defaults (Soot's started at 0),
  `BindingsGetDataAsText3`, neutral `ExecuteColorPicker`/`ApplySkin`/`Randomize`. Crawled scripts:
  3,231 → 3,238 of 3,250 run; the 12 left are docking (`Next` 6).

- A12 The skin's own playlist and library windows (2026-11-02): companions over NullPlayer's
  windows, sizable, maximizable; quick search, playlist and library menus, tabs, vertical scroll
  bars, formatted totals; `AIMPSkinLibrary` groups NullPlayer's library by AIMP's presets for the
  `MLGroupingTree` and `MLTable`. `reference/layout.md` § *Playlist and library windows*.

- A11 Draw order and dynamics (2026-11-01): items' pictures first, then every control, an item's
  own before its children's (the Mayaks' level bars over their meter glass; GX-77's PLM key,
  AIMP-Cassette's keys, Pioneer's cassette title show); unanchored controls with no margins
  centre (every cassette's reel hubs); gauges ease at their `ReactionSpeedLevelUp`/`Down` (Denon
  Classic Style's peak bars); `Checked` reads an action's state (Denon's mute held).
  `PlaylistTabs` draw one lit "Playlist" tab (Sony ES-Style Silver 2's column, GX-77's paper tab).
  Regression renders must compare RGB: `ImageChops.difference(...).getbbox()` on RGBA images
  looks only at alpha.

- A17 AIMP 2 skins (2026-11-02): the `ACSP` package (`.acs`, versions 2 and 3), its Windows bitmaps
  (magenta key, straight alpha), and `main.ini` (both versions' sections, `MainLayout.xml`,
  `PlaylistLayout.xml`) read into the AIMP 3.0 model `AIMPSkinLegacy` builds forms from: the player
  over the docked playlist, all-in-one equalizers in the window, the others a window right of it
  that `EQBtn` opens. 165 of the catalog's 166 render (was 0); the last is a scrambled version
  (`0x20`). The 168 AIMP 3.0 skins render unchanged. `reference/format.md` § *AIMP 2*. Left: AIMP's
  default pictures for objects a skin leaves out (Strong's NEXT and EQ keys show the red
  placeholders under them), the effect sliders (echo, reverb, flanger, chorus), the sleep timer,
  the detached playlist window (`PlsTopDock`), the tray control and quick file info.

- A10 AIMP 3.0 skins (2026-11-01): the `ACS3 02` container, `MySknImg` images, and `MainFrame.xml` +
  `main.ini` read into the form tree (`AIMPSkinLegacy`). Vega AIO v1.01, an all-in-one player with
  its own playlist, renders close to its screenshot. Its window sizes from its right and bottom
  edges; wider, the info panel shows the EQ curve, preamp and EQ switch, then the file details.
  Left: quick search, the second playlist line, `QFI`/`TrayControl`/`DropWheel` frames.

- A9 Polish pass (2026-11-01), from a corpus census of every binding, popup, class and pin:
  skin playlists (embedded and GX-77's window) with scroll bar; popup menus by name (EQ presets,
  Add); held keys (`ActionOnHold`, `ActionOnLongClick`) and release handlers; disabled keys;
  right-click `ContextMenu` values; track details, text providers and template functions; digit
  boxes; selector spreads; masked-slider masks; flat-frame key masks; cover windows as companions;
  oscilloscopes; ratings; `PLWin`/`InfoBox`/`Menu` window names.

- A13 Dock sites and a polish pass from the user's 96 installed skins (2026-11-03): `LayoutDockSite`
  holds the form it names, and scripts dock, undock and move items at run time (`AIMPSkinDockSites`; Bliss Compact Dark, DEFIX Hi-End, KibTech, New.VK,
  Arctur, M.Jukebox, A4's playlists); animators with no `AnimationInterval` hold their first frame
  (RealPlayer 11's VU meter flashed white 20 times a second); one-digit number labels grow left to
  hold the number ("44 kHz", "320 kbps"); `BitRate` read either case; `prvPlayingFileInfo.Duration`;
  Tahoma for unnamed fonts ("M.Library" fits its key); `[COLOR]`/`[B]`/`[I]`/`[U]` text markup;
  `StringOperatorConcatenatorNotificator`, a concatenator with no `Expression`, `%UserTemplateN`;
  playlist fonts given as one value per state (W10's and New.VK's rows were white on white).

- A15 Containers read by their own fields (2026-11-02): the `.acs4`/`.acs3` key comes from the
  scrambled `3SCA` marker in the header, the body from the metadata block's `u32` length, and the
  strings are UTF-16LE (Cyrillic names and descriptions past 255 characters read whole). Every
  `.acs4` and `.acs3` of the crawl opens, with no key search: 61 skins more load (`.acs3` keys 50,
  `.acs4` zlib 7, `.acs5` counts 4); `.acs3` kinds 1/3/5/6 in `reference/format.md` § *Containers*.

- A16 Pictures decode when drawn, within a resident budget, and AIMP 3.0 BMP skins (2026-11-02):
  `AIMPSkinPixelBudget` holds at most `decodedPixels` decoded per skin, letting the least recently
  drawn go; AM0007 now refuses only one image over it. Frames are views into one buffer (a
  side-by-side strip repacked), not copies beside the strip. `.acs3` kind 1's `.bmp` pictures decode
  (`AIMPSkinBitmap`) and take their frames from `main.ini`. 9 of the 10 over-budget decks load
  (Mayak-203: 1.1 Gpx of pictures, ~240 Mpx resident, peak RSS 2.4 GB in the probe, as Technics
  SL-1200's 2.2 GB); the 23 BMP skins render.

- A18 Tab pages, hidden windows, declared placement (2026-11-03): a tabbed group starts on its first
  page not saved hidden, else its first, and a page shows by being active (Unsquareable's playlist
  view, RealPlayer 10–15's equalizer window, Kantaris-Teyp's transport); a window whose items all
  start hidden is sized by them (K-2's open glass lid, LX-tix's equalizer and settings); `Schema.xml`'s
  `Placement` opens a window left of, above, right of or below the deck (K-2's lid and speakers,
  Sharp GF-777's handle and antenna, 27 skins' equalizers); a dock site shows while its form does
  (Telos's transport panel no longer lies under its hidden equalizer) and an empty one is hidden;
  several `laClient` siblings share their parent side by side (Office 2016's ribbon, Red Bias,
  Play Music AIO's header; 134 corpus skins); an unbound `TextDisplay` shows its `Template` (window
  titles and labels: 4,874 displays in 279 skins); `[COLOR=rrggbb]` without `#`, `[URL]` markup.

- A19 Modern-skin layout (2026-11-03): each edge docks its items by `AlignmentLevel` (Denon Classic
  Style's playlist tool bar under its captions, TASCAM CD-RW750's running line inside its frame);
  undocked items run down from the top; several `laClient` items share the row (`ldHorizontal` by
  default, at least what they hold needs); pictureless items are as big as their children laid out;
  key captions centre in
  their content margins; FLAT DARK's caption and
  menu, Red Bias's columns and Soot's transport row lay out. Pictures fill as their `draw` chunk
  says (stretched, tiled, centred: glyphs on flat keys); `BlendingModeOpacity` is a control's
  opacity; tabbed groups follow their `ActivePage` binding (Soot's playlist page). Colours inline
  and through resource chains; `NightMode` from the Mac's appearance (the automatic themes);
  sizable main forms open at their `InitialSize` or docked minimum (Unsquareable, Office 2016,
  Pandemic's playlist); displays wrap (`WordWrap`, `MultiLine`) and size to their text;
  `BlurredGlass` blurs what is under it inside its mask; AIMP's own `@Lng:Section\Key;` strings
  read as words; shared clients hold at least what their children need (LX-tix's info panel);
  `AutoHide` by `AutoHideParentSizeThreshold`, read back by bindings on the next frame; controls
  clip themselves and their children to their `MaskFrame` (A4's glyph keys); a commutator with no
  `Expression` passes its first value; language strings inside bound templates; sizeless tab pages
  fill their group; `CoverArtDisplay` `BlurLevel`; `AutoHide` items show whenever they fit (Soot
  turns all-in-one at 550 px); a provider's `Action` pin is an event, not run at load (Soot's
  volume ring); masks made once per frame and size.

- A20 Fifth review round (behaviour kept, renders unchanged): docking by `Alignment` is one model,
  `AIMPSkinAlignment` (participants, sizes added up, level order, client shares), that the painter's
  layout and item sizes, the renderer's natural and least sizes and AIMP 3.0's translator all
  measure by; `AutoHide` is a docking rule there, no longer a reading of `Visible`; a colour is read
  one way (`AIMPSkin.color(of:)`), AIMP 3.0's and AIMP 2's Delphi colours turned ARGB as their forms
  are read; a frame lays its items out once; blurred covers are made once; Night Mode follows the
  Mac's appearance as it changes; companions open beside the deck by one function.

- A21 Pre-PR quality review, findings 2, 4, 11 and 12 (behaviour kept, renders unchanged on the
  745-skin catalogue): forms, controls and providers read once into typed models
  (`AIMPSkinItem`, `AIMPSkinControl`, `AIMPSkinIndex.Provider`, `AIMPSkinLink`); AIMP actions one
  enum (`AIMPAction`); a frame laid out (`AIMPSkinLayout`), then painted one explicit layer at a
  time, its click targets, tooltips and named rects read from the layout; each item measured once
  a frame; `naturalSize` a plain search with its thresholds in `AIMPSkinPolicy`.

- A22 Pre-PR quality review, findings 7, 8, 9, 14, 15 and 17 (behaviour kept, renders unchanged
  on the 745-skin catalogue): the skin state in three parts (`script`, `animation`, `lists`), a
  layout move any change outside `animation`; the host state split into the engine's
  `AIMPSkinPlayerSnapshot` (its playlist compared by build), the window's `AIMPSkinFrameFeedback`
  and the runtime's match cache, the probe's sample player in the test target; the engine host's
  snapshot a pure read, track starts and finishes counted on the engine's events; the shared types
  `Sendable`, the caches behind `OSAllocatedUnfairLock` but the pixel budget's; node readers
  scoped to AIMP types; `AIMPSkinAlignment` and `AIMPSkinDockSites` named apart; one seek clamp.

- A23 Pre-PR quality review round 2, findings 2–6, 36, 37, the expressions of 9 and the scripts'
  part of 38 (renders unchanged on the 745-skin catalogue, scripts 3,489 of 3,489): each script
  compiled once as the skin loads into a typed tree (`AIMPSkinScript+Syntax`), a tree it does not
  take an `AM0008` warning; one `AIMPSkinScript.Engine` per tick or event owns the state, actions,
  budget and guards (a counter's script that moves its own counter only moves it, in `settle` too;
  AIMP's EQ bands asked for once per NullPlayer band, at the mean of their latest values); a run
  that stops undoes itself; `Unsupported` passes through a skin's `except`, one `finally`;
  `FindObject` resolved once into a `HostObject` and `Set`/`Get` into a `Property`; `prvPitch`'s
  `Set('Position')` moves the speed as its knob does (it was dropped); the built-ins one table;
  `Arguments`, `Data`, `EventData` and `TASEBindings` typed values; binding sets hold
  `AIMPSkinLink`s; `AIMPSkinStep` sorted on the compiled expression, whose operators are enums;
  the harness's dry run in the test target.

- A24 Pre-PR quality review round 2, findings 9 (INI), 10, 11, 12, 29, 30, 32, 33, 34, 39, the
  loader's part of 38 and the cue part of 22 (2026-11-03; renders unchanged on the 745-skin
  catalogue but for seven AIMP 2 spectrums): one byte cursor (`AIMPSkinBytes`), one inflater
  (`AIMPSkinZlib`), one INI reader (`AIMPSkinINI`, case-insensitive: AIMP 2's `[Skin_OPtions]`
  now gives seven skins their declared spectrum colour and bar count); the legacy readers give typed
  `Object`s to one `Translator`; every document read through `AIMPSkinDocuments`, so a malformed
  legacy form is its `AM0009` and a version 3 `.acs` never gets version 2's layout; one
  `AIMPSkinImage` initializer, typed stretch columns, decodes outside the budget's lock, frame
  flags read once when a picture is first laid out (not at load: that cost 25% of load time); `.zip` imports bounded (`AM0012`); the library source apart from the
  engine host, lookups from its build, `LibraryTrack` sorted by `LibraryTextSorter`; dropped cue
  sheets read off main.

- A25 Pre-PR quality review round 2, findings 1, 7, 8, 9 (colour and font), 13, 16 (AIMP's part),
  17, 18, 19, 20, 23 (in part), 24 (in part), 25, 26, 27, 28, 31 (margins), 35 and 38 (menus): the
  frame scheduler keeps one pending input and takes frames by generation; a skin switch stops,
  tears down, installs, then starts; the meter runs with the clock; controls have an identity the
  pointer and gauges key by; the control's class carries its settings and the layout resolves one
  `Look` the painter switches on, over `AIMPSkinCanvas`; bindings resolved once into
  `AIMPSkinSource`; docking and text alignment typed; one colour and one font reader (26 catalogue
  equalizer displays now draw the curve their `ColorCurve` gives as its own value);
  `AIMPSkinCompanionWindows`; form names and popups typed. Renders otherwise unchanged on the
  745-skin catalogue.

- A26 Pascal ranges in `case` labels and sets (`0..9:`, `X in [1..20]`) hold everything between
  their ends, as Pascal's do; they matched their two ends only. 58 scripts in 15 catalogue skins:
  the level meters of Pioneer RT-909, Ода-102, Dual C828 and Orbita-002 stayed dark while playing.

- A27 AIMP apart from shared code (2026-11-03, the owner's choice): other families' code back to
  upstream, AIMP carrying its own copies (`AIMPSkinArtworkLoader`, the EQ popup's preset apply,
  `AIMPSkinMenuItem`, `AIMPSkinDroppedMedia`, `AIMPSkinImporter`'s catalogue). `WindowManager`
  routes the skin's own playlist and library through one AIMP hook (`SkinDrawnLists`); Sonique's
  `SkinDrawnEqualizer` is upstream's. Behaviour and the 745-skin catalogue renders unchanged.
- A28 Review round 3 (2026-11-03, the owner's choice: real defects and speed now, structure deferred):
  one resource resolver for images, colours and fonts (fonts follow `ID` aliases and script
  repoints, keeping their own settings on top); one `@Lng:` expander (an unknown key reads empty);
  display text by the link's typed source (list totals, sleep-timer times); concatenators compared
  by their inputs and read as their text; one operator core for scripts and bindings (bitwise on
  whole numbers, division by zero raises in scripts); item sizes parsed once and measured with
  child and page margins; a main form opens with room for the form docked in it (65 catalogue
  windows no longer cut their playlist); `AIMPSkinCache` computing outside its lock; scripts
  `@MainActor` with a 20,000-step budget. Hit masks measured at 0.6% of draw time and left.

## Corpus survey (2026-11-02)

`scripts/aimp_corpus_crawl.py` over the aimp.ru PC-skins catalog (819 records): 740 new skins
beside the 46 installed, plus 46 duplicates, 67 non-skin records, 3 RAR, 3 failed downloads.
By format: 175 `.acs4`, 169 `.acs3`, 168 AIMP 3.0 `.acs3` (`ACS3 02`), 67 `.acs5`, **166 `ACSP`**.

Load + script census of the 579 AIMP 3–5 skins (probe, no render): **508 load (88%)**, scripts
**3,044 of 3,250 run (93.7%)**. Ranked gaps:

1. ~~**`ACSP` (166, 21% of the catalog): AIMP 2's package.**~~ Done (A17): 165 of 166 render.
2. ~~**`.acs3` keys (50)**~~: done (A15).
3. ~~**Image budget (10 `.acs5`)**~~: 9 done (A16). Left: Reloop RP-7000 GLD 4K,
   whose tone-arm strip alone is 493 Mpx (299,625 × 1,646, frames side by side); it would need
   frames decoded one at a time.
4. ~~**`.acs4` without a zlib stream after the preview (7)**, **`.acs5` entry counts read as garbage
   (4)**~~: done (A15): the metadata length, and UTF-16LE strings.
5. ~~**Scripts (206 failures at the census)**~~: all run (A14; docking verbs with A13). Were: `try` statements 19,
   `StrToInt64` 18, `TASEBindings.Create` 17, `IsLoaded` 17, `Copy` 11, `ColorToARGB` 10, `Now` 8,
   `Self` 6, `ExecuteAction(ActionOnHold)` 6, `PLDock.Parent` 6.

Not yet measured: renders of the crawled corpus (sizes run to 600 MB a skin).

Re-census after A13–A19 (2026-11-03, all 745 crawled skins incl. AIMP 2): **742 load**, scripts
**3,489 of 3,489 run**. Left: Reloop RP-7000 GLD 4K (one 493-Mpx strip), JD_Vifaru (an 85,536-px
slider frame, AM0006), Dark Lagoon (ACSP version byte 0x20).

## Next

1. **Actions with no NullPlayer equivalent:** record (`acPlayerRadioCapture`, 28 skins), A–B repeat
   (8), tag editor, converter, the TrueBass/reverb/echo/chorus/flanger/enhancer knobs. Stay
   no-ops unless NullPlayer gains them.
2. **The skin's own info and lyrics frames**: they open NullPlayer's windows. TC-MR2's skin-drawn
   `Menu` popup likewise. Playlist and library windows are done (A12); left there: the library's
   card view and column choice, bookmarks, the playlist manager, several playlists.
3. **Modern skins** (Soot): `AutoHide`, `LayoutSplitView`, `BlurredGlass`, colouration.
4. **Streaming sources in the skin's library window** (deferred by the user, 2026-11-02): it lists
   NullPlayer's local library only, so a Plex-only user sees "All Tracks 0". Doable without core
   edits: page `PlexManager.fetchTracks(offset:limit:)` once, `convertToTracks`, follow the library
   browser's source; Jellyfin/Emby/Subsonic alike. Not wanted yet.
5. **Scripts moving controls** (`PlaceInfo.Margins.*`: Technics' music-light lamps shuffle,
   speakers' `MagnetRectOffsets`), `RunningLine` scrolling.
6. **Docking at run time:** sites are mounted at load (A13); scripts that move forms between sites
   and windows (`Dock`, `Undock`, `Parent()`: A4 3.2's layouts, Telos, Fantasy, M5, Red Bias) are
   not followed.
7. **Scripts off the main thread.** Frames are drawn on a background queue (`AIMPSkinFrameScheduler`);
   the scripts still run on main (`Engine` and `Run` are `@MainActor`), bounded per tick and per
   event by one shared `AIMPSkinScript.Budget` (20,000 steps, 32 calls deep). Measured over the gate
   corpus in an optimized build, a tick's scripts take at most 1,734 steps and under 1 ms (Technicss),
   typically 0.04 ms; a runaway loop of host calls stops in about 10 ms
   (`AIMPSkinScriptTests.testRunawayHostCallsStopWithinAFrame`), so nothing yet needs them moved.
   Moving them means the runtime's state lives on that queue and main sees snapshots and
   `AIMPSkinCommand`s.
8. **Corpus gaps** (`Corpus survey` above): AIMP's own dialogs (`ApplySkin` and
   `ExecuteColorPicker` finish as no-ops: a colour picker and switching to another AIMP skin by name).
 9. **Code-quality follow-ups** (thermo-nuclear review, 2026-11-02; none blocks merge):
    - form names classified once: `AIMPFormRole` is case-sensitive AIMP names, while
      `AIMPSkinLoader.title(ofForm:)` and `Companion.placement` read skin-chosen names (`EQForm`);
    - `AIMPSkinAudioEngineHost.snapshot()` counting track starts by sampling (belongs in
      `updateTrackInfo`);
    - AIMP's own copies of shared helpers (`AIMPSkinDroppedMedia`, `AIMPSkinMenuItem`,
      `AIMPSkinArtworkLoader`, the EQ preset apply, the skin catalogue): merging each with the other
      families' is the maintainer's call, offered as a follow-up (guide § *Shared code*);
    - round 2 left: a picture's `stretchColumns` as a type (in `AIMPSkinImage`), a non-optional
      runtime for the skinned view, the skin playlist's menu through `PlaylistMenuBuilder` (finding 14), the
      meter's level read without undoing PeppyMeter's mapping (needs `PeppyMeterLevelModel`).
10. **A form's own `Visibility` binding** (`Schema.xml`, 41 forms: Dark v1.7's four windows on
    counters, Romantik 304's playlist on a tab page, Denon Classic Style's units on commutators) is
    not read: those windows follow their `Visible` keys only. AIMP's evidence (RealPlayer's EQ key
    opens a form bound to a page index that stays 0) says the binding sets `Visible` when its value
    changes rather than gating it.
11. **`MagnetRectOffsets`** on the main form: Dual C 846 & CV 1460's window is 608 px tall with its
    top half transparent until the amplifier key shows the amplifier there; AIMP snaps windows to the
    deck's edge 304 px down (the amplifier script moves it). NullPlayer snaps to the frame, so docked
    windows stand clear of the empty half; needs `WindowManager` to take a snap inset.
12. **Counter scripts at load:** a `ScriptableOperatorCounter`'s script runs only when its input
    moves, so the state it sets up for position 0 is never set (LX-tix's `DownPanelView` hides its
    second info panel at 0; both now show side by side). AIMP runs it as the skin loads.
13. **Script leftovers from review round 2:** a script's `ExecuteAction` on a link
    (`AIMPSkinScript+Bindings.swift`, `perform`) is a second "what a link press does" beside
    `AIMPSkinControl+Input`'s `press`; a lamp's `Value = N` (`AIMPSkinControl.selectedPosition`)
    still reads the expression's text, where it could match the compiled tree as `AIMPSkinStep` does;
    animators that keep their own frame are stepped by the script engine (`Engine.visualize`)
    although no script owns them.
14. **Texture tint by `ColorID`:** a texture resource can name a theme colour that AIMP tints it with;
    NullPlayer draws it untinted. M5 (1246) shows its light panels behind its dark-theme text, so the
    info window's title and the bottom bar's icons vanish.
15. **Captions a script sets:** Telos's options form shows `@Lng:48;`, `@Lng:49;`, `@Lng:1;`; text a
    script assigns does not go through the `@Lng:` expander. Bliss AIO's status line lacks its
    `%Bitrate` (a template field not resolved).
16. **Sizing left from review round 3 (C1):** `AIMPSkinRenderer`'s natural-size search, the AIMP 3.0
    translator's synthetic `SizeMinimal` and the list-growth loop are still separate from the one
    measure; Arctur (×3) leaves the natural size before a docked form's minimum is applied.
17. **Structural findings from review round 3** (deferred by the owner, listed in the
    AIMP PR's description): the window layer's frame feedback,
    clock and list interaction (A3–A8, A10); the index built from a half-built copy of itself (B1);
    one value command in one unit (B2, B3); typed property accessors and state records (B7, B9,
    B11–B14, B16); the legacy loader's string round trips and the script decoder (C2, C3); the
    layout's `Look`, key-frame rules, settle loops, raw geometry and painter boilerplate (C5–C11,
    C14, C15).
