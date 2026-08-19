## Defix Hi-End 200 (`Defix Hi-END 200.WAL`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

**Fixture note:** the archive ships `screenshot.png`, but it is a 275×116 skin-browser thumbnail of the
whole three-window arrangement, not a reference render — good enough to settle *what the skin looks
like* (wood-panelled player flanked by two speaker cabinets), not to measure against.

**Reference (2026-08-18, from the user):** https://www.youtube.com/watch?v=nrqwCf3KxUw — a YouTube
demo of this skin running in Winamp, and the only artifact that shows it in motion, and it settles two things nothing in the archive can. **The cassette
reels do spin during playback**, and **everything the skin draws animates** — reels, VU needles, level
bars and the speaker cones. So every "static" verdict on those objects is a real defect, not an
undriven measurement. A skin's own thumbnail cannot answer this class of question.

**Shape of the skin:** separate windows — `main` (406×355) plus `pledit`, `SUI` (its media
library/browser/visualization window, 800×600), two `SPEAKER` cabinets, `Config` (an About page),
`browserpro`, `searchresults` and `notifier`. The equalizer is synthesized. Almost everything the skin
draws is script-driven: a global `<scripts>` block in `skin.xml` (`CORE_SCRIPT.maki`, 47 KB) plus a
55 KB main-layout script.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-08-17 (Phase 25): `degraded`, **0 errors and
0 unsupported methods at startup**; the remaining findings are duplicate ids and optional missing
bitmaps. `main/normal` 406×355, 69 nodes.

### Working

- **The wood panel and the framed windows** — see the trap below; this is the skin's whole look.
- **The SUI body** — the tab strip switches between Media Library, Visualization and Explorer, and
  the Media Library tab hosts NullPlayer's embedded library through the holder it declares. This was
  read as a "guilist gap" for two phases on the strength of a blank dump; the body is a
  `<windowholder>` on the media-library GUID, and the render harness cannot draw AppKit content, so
  the dump is blank for a surface that works. Three separate defects kept the strip inert — see the
  traps below.
- **The display** — the audio-cassette visualizer (its shipped default, one of nine styles), the song
  ticker on the cassette label, the time readout, and the Shuffle / Repeat / Kbps / Extension
  readouts, one variant at a time.
- **The SUI tab strip** — Media Library / Visualization / Explorer, each sized to its own label.
- Transport, seek and volume with their scales, the playlist window with its own titlebar buttons,
  both speaker cabinets, the About page.

### Not implemented or knowingly wrong

- **Its songticker never scrolls, and no UI here can change that.** The skin registers
  `Disable`/`Modern`/`Classic Songticker Scrolling` with `newAttribute` for **Winamp's** preferences
  dialog — they appear nowhere in its own Skin Settings window — and ships `Disable = 1`, which its
  `onDataChanged` applies as `ticker="off"`. The engine handles all three values; there is simply no
  way to reach the setting. Do not "fix" the ticker code for this.
- **Its `<Browser>` explorer tab** — the Explorer tab's content is a `<Browser>` control (Winamp
  embeds Internet Explorer and points it at a file path). The tab switches and its chrome draws; the
  browser pane itself is empty, and hosting a real web view for untrusted skin content is outside the
  sandbox this engine is built on.
- **Layer FX — all eight display styles animate as of Phase 28** (live runs: 2026-08-18 *P-402 VU and
  Technics VU work, all others are frozen* → 2026-08-19 *they are all working*). The two that always
  worked are `<animatedlayer>` frame strips (`LAYOUT1/LVL/`) driven by `gotoFrame`; every other one is
  a **rotation** through `fx_onGetPixelR` — the four needle styles (`LAYOUT1/Vu2/`) and the cassette
  reels (`CASROLL`/`CASROLR`). Three separate defects had to be fixed before any of them moved, and
  each hid the next: the warp was never run; `onSetVisible` was never dispatched when a window was
  shown, which is what switches the reels' FX on and starts their timer; and the needles' `onTimer`
  aborted every tick on the unimplemented `sqrt`. A fourth, an integer-truncating unary minus in the
  interpreter, left the needle with exactly two positions once it did move.
  Measured grids: reels 1×1 and 4×4, needles 6×6. Reels step 5°/8° every 33 ms; the needle updates
  every ~17 ms.
- **Motion quality — addressed in Phase 29 (2026-08-19).** The choppy cassette and the weak needles
  were reported together but are two unrelated causes, and neither is Layer FX:
  - *Choppy* was the **frame budget**. Two things were eating it. Every bitmap in the window was
    re-filtered to the Retina backing scale on every frame (18.3 ms a frame at 2×; the artwork is now
    kept pre-scaled, taking it to 3.5 ms idle and 5.4 ms with both reels warping), and `updateTime`
    invalidated the *whole window* ten times a second at the audio engine's clock, which silently
    defeated every targeted repaint around it. The reels' own script was stepping evenly the whole
    time — `WINAMP_MODERN_RENDER_FX_SPIN` measured 5°/8° every 33 ms, perfectly regular — so the
    script cadence was never the problem, only the frames carrying it.
  - *Weak* was the **level scale**. The host was measuring RMS; Winamp's VU byte is a peak. Music
    that peaks at full scale sits at 0.05–0.15 RMS, which against this skin's own artwork is the
    bottom sixth of the sweep (measured with `WINAMP_MODERN_RENDER_VU`: 0.1 → 34%, 0.3 → 60%,
    1.0 → 100%). `WinampModernLevelMeter` now measures peak amplitude, which puts loud material at
    0.5–1.0 — the swing the needles are cut for. Live follow-up (2026-08-19): peak alone was
    *better but still not responsive*, because a peak over a whole 50–100 ms tap buffer is nearly a
    constant on this kind of material, and the needles never fell to rest when the music stopped —
    the tap posts nothing at all when playback ends, so the last value stuck. The buffer is now split
    into Winamp-sized ~13 ms blocks played out in step with the audio, and running past the end of
    them is read as silence — confirmed live on the pass after.
    `WINAMP_MODERN_VU_LOG=1` prints what the meter receives off real audio.

  Measurements and what is still open: `docs/winamp-modern/phase-29-handoff.md`.
- **Seven of its eight display styles were unreachable; Phase 27 made them selectable.** The skin
  registers a *Visualizer* item with `newAttribute` carrying eight values — `Audio cassette` (its
  shipped default), `Left Right VU`, `BASS TRIPLE VU`, `Ovis 1`, `Ovis 2`,
  `McIntosh MC2KW Amplifier VU`, `P-402 VU`, `Technics VU` — and binds **no control in the skin** to
  any of them, because in Winamp they appear in the preferences dialog. All the artwork ships
  (`LAYOUT1/Vu2/` four needles + four scales, `LAYOUT1/LVL/` Technics and RT level strips,
  `LAYOUT1/CAS/` 57 cassette bodies). They are now listed in **Winamp Modern → Skin Settings...**
  along with the songticker modes below and the rest of the 32 options this skin registers
  (`WINAMP_MODERN_RENDER_SETTINGS=1` prints them). Whether picking one actually changes the display
  is the live pass.
- **Its two speaker cabinets and its configurator are opened from the host's Skin Windows menu**
  (Phase 27). The skin declares `SPEAKER 1`, `SPEAKER 2` and `Config name="Skin Settings"` and binds
  no button in the skin to any of them — in Winamp they live in Winamp's own Windows menu. Whether
  the cones (`animatedlayer#SpeakerVis`, fed by `getVisBand`) animate is the open live question; their
  timer starts from `onSetVisible`, so nothing about them could be judged until the windows opened.
- **The cassette reels are script-driven plain `<layer>`s and they are confirmed to spin in Winamp**
  (`CASROLL`/`CASROLR`, image `CasR`, inside `LAYOUT_1.CAS.grp`). Whether ours move under live
  playback is still untested — the render harness has no audio and no component host, so it can never
  answer this; drive it in the app.
- **`getVisBand` — implemented in Phase 27**, so the meters this skin draws have a number to move
  to at last: the speaker cones (`animatedlayer#SpeakerVis`), the VU needles and the level bars all
  read it (`SPEAKER.maki`, `VU_LAYOUT_1.maki`). It answers from the shared mono spectrum tap, in
  vis bytes; the harness cannot see it move (no audio), so watch it under playback in the app.
- **`isloading` — implemented in Phase 27** on `<AlbumArt>`, from the host's real artwork-fetch
  state. `PLAYLIST_WINDOW.ontimer` had been aborting on the miss every tick.
- **`setScale` is missing** — the configurator's seven window-scaling buttons (100–300%) are inert.
- **The skin builds no `PopupMenu` of its own; every menu it has is a host action, and none is
  implemented.** `trackmenu`/`trackinfo` (declared as `rightclickaction`/`dblclickaction` on the song
  ticker — both *attributes* are also unsupported), `VIS_Menu`, `VIS_Cfg`, `VIS_Next`, `VIS_Prev`,
  `PE_Add/Rem/Sel/Misc/List`, `ML_SendTo`. `colorthemes_switch` fails the same way, which leaves its
  six colour themes (`*Default`, `Azure`, `McIntosh Lite`, `McIntosh`, `Technics`) unreachable.
- **`newDynamicContainer` returns the existing container**, so the skin's detachable visualizer and
  second mini-browser share one window rather than opening a copy.

### Traps this skin sets

- **It names its background art from a preference it never seeds.** `getPrivateString(getSkinName(),
  "BG", "")` is `""` on a profile that has not opened the skin's configurator, and every background id
  is built by prefixing it — so the layout is asked for background `""` and the nine frame slices for
  `"" + "_background_material.Element.top.left"`. Winamp keeps the artwork a failed load did not
  replace; taking the writes literally left the player, both speakers, the playlist and the library as
  flat black boxes. That is the rule in `setXmlParam` now: an image-valued param only changes when the
  new id resolves.
- **It shows one readout at a time by moving alphas, not by hiding.** Kbps, KHz and Channels share one
  slot at `alpha="0"`/`145`, as do Extension and Broadcasting. Text that ignored `alpha` printed all of
  them on top of each other.
- **Its global script assumes the skin is already configured.** `CORE_SCRIPT`'s `onScriptLoaded` lays
  out the SUI tab strip as `label.getAutoWidth() + 20` per tab — run before the tab labels arrive as
  XUI params, every tab came out at that bare 20px, stacked at the left edge. A skin-level `<scripts>`
  block loads *after* the objects and their params, which is why `start()` orders it last.
- **`@HAVE_LIBRARY@` is a script param, not a path variable.** The core script reads
  `stringToInteger(getParam())` as "is there a media library?" and drops the Media Library tab when the
  answer is 0 — which the literal string is.
- **Its four round buttons are `rectrgn="1"` outline icons, and two of them were dead.** The hit test
  alpha-tested the artwork even for a declared rect region, so a click through a gap in the icon fell
  onto the `ButtonBG` panel behind. `ConfBT1`/`ConfBT4` never responded; `ConfBT2`/`ConfBT3` did,
  because their artwork is denser under the same point.
- **Those four buttons are user-configurable, and none of them is hard-wired.** Each reads its own
  `getPrivateString(getSkinName(), "MainBtnN", …)` and dispatches on the result — `"PL"` calls
  `PLSBt.leftClick()`, `"EQ"` calls `EQSwitch.leftClick()`, `"ML"`/`"Video"` send `opentab` to
  `sui.content`. `PLSBt` and `EQSwitch` are 0×0 image-less proxy buttons that exist only to carry an
  `action`/`param` pair, so `leftClick()` must run the target's *action*, not just dispatch its
  `onLeftClick`. The XML defaults are PL / EQ / ML / Video, but the script rewrites the images, so what
  a button does is not what its markup says.
- **`findObject` is the *wide* lookup.** The core script holds `sui.content` and asks it for
  `switch.ml` — a tab button in `grid.s2`, a **sibling** subtree. Answered from descendants alone all
  five tab lookups returned null, so the script bound its click handlers to nothing. `findObject`
  searches the receiver's subtree first and then the rest of the container; `getObject` stays narrow.
- **`embed_xui` says which object *is* the XUI.** `bento.tabbutton` embeds its `mousetrap` button and
  the core script hooks `onLeftClick` on the **group** (`switch.ml`), so the child's pointer events
  have to be carried up to the embedding group or the tab lights up and nothing else happens.
- **The tab switch is gated on a timer**: `if (anim.isRunning()) return; anim.start();`. The app has a
  run loop and the timer stops itself; the render harness does not, so without pumping the run loop
  between driven clicks only the *first* tab click ever appears to work. That is a harness artifact —
  do not chase it in the engine (`RENDER_CLICK` now pumps when `RENDER_SETTLE` is set).
- **A group is a window and clips.** The cassette display is a 263×79 group holding a 117×117 reel
  bitmap; unclipped, both reels spilled 53px below the cassette and painted over the song ticker,
  leaving the title readable only in the gaps between them.
- **One refused method costs the whole window.** Every early defect here was a handler aborting
  partway: `getExtension` took the main layout's display with it, `fx_setGridSize` the VU meter,
  `newDynamicContainer` → `setFontSize` → `navigateUrl` → `hasVideoSupport` the global script, each
  surfacing only once the one before it was implemented.
