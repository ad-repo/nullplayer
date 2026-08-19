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
`browserpro`, `searchresults` and `notifier`. **The equalizer is the classic fallback, not a
synthesized window** — the catalog says so in as many words (`equalizer=classic(the skin declares no
equalizer surface)`), because this skin declares no equalizer surface *and* no `EQ_BAND`/`EQ_PREAMP`/
`<eqvis>` control for one to be recognised from, so nothing qualifies for synthesis. Its `EQSwitch`
proxy carries `action="TOGGLE" param="Eq"`, an id nothing in the skin declares.

Almost everything the skin draws is script-driven: a global `<scripts>` block in `skin.xml` (`CORE_SCRIPT.maki`, 47 KB) plus a
55 KB main-layout script.

**Measured status** — `WINAMP_MODERN_RENDER_DUMP`, 2026-08-19 (`/wal-skin-report`, harness
`c1373bb5`, SHA-256 `fac516d2…3bc78e`): `degraded`, **0 errors and 0 unsupported methods at startup**;
the remaining findings are duplicate ids and optional missing bitmaps. `main/normal` 406×355, 69 nodes,
35 bitmaps resolved and none missing. **All 50 script programs ran with `failed=-`.** Coverage
**271/432 declared objects ever rendered (~63%)** — the unexplored set is dominated by the seven
non-default display styles, which have no headless route in (below). **Grade B, confidence medium.**

### Working

- **The wood panel and the framed windows** — see the trap below; this is the skin's whole look.
- **The SUI body** — the tab strip switches between Media Library, Visualization and Explorer, and
  the Media Library tab hosts NullPlayer's embedded library through the holder it declares. This was
  read as a "guilist gap" for two phases on the strength of a blank dump; the body is a
  `<windowholder>` on the media-library GUID, and the render harness cannot draw AppKit content, so
  the dump is blank for a surface that works. Three separate defects kept the strip inert — see the
  traps below.
- **The display** — the audio-cassette visualizer (its shipped default, one of eight styles), the song
  ticker on the cassette label, the time readout, and the Shuffle / Repeat / Kbps / Extension
  readouts, one variant at a time.
- **The SUI tab strip** — Media Library / Visualization / Explorer, each sized to its own label.
- Transport, seek and volume with their scales, the playlist window with its own titlebar buttons,
  both speaker cabinets, the About page.
- **The four round buttons and their assignment menu** (Phase 31, partial — see the open bugs at the
  end of this section). `player.ButCd` holds `ConfBT1..4` at `(25|74|123|172, 231, 36, 40)`. Each is
  *user-assignable*: right-clicking one pops the skin's own `PopupMenu` — `Video`, `Playlist Editor`,
  `Media Library`, `Equalizer`, `Visualization`, `Explorer window` — and the pick is stored as
  `MainBtn<N>` under the skin's `Winamp Defix` private-string section, which also selects the button's
  artwork (`PLAYER.But.{pl,eq,ml,vd,vs,br}.norm`). Left-clicking then opens the assigned window.
  Confirmed live 2026-08-19: the menu appears on all four, and the windows mostly open.

  **The six assignments do not resolve alike, and that is the thing to know before touching this.**
  Only two reach a host action at all:

  | `MainBtn<N>` | What the left-click actually requests |
  |---|---|
  | `PL` | `PLSBt.leftClick()` → `TOGGLE guid:{45f3f7c1-…}` — a host action |
  | `EQ` | `EQSwitch.leftClick()` → `TOGGLE Eq` — a host action |
  | `ML` / `VS` / `BR` / `Video` | the skin's **own** `sendAction("opentab", …)` to `SUI/normal/sui.content`, answered by `skin.xml`'s `onAction` with `getContainer("SUI").show()` + `switchToLayout` |

  `PLSBt` and `EQSwitch` are 0×0 invisible proxy buttons in the same group, carrying the real
  `action`/`param` in markup; the visible button never carries one. So "the button does nothing" has
  three possible causes here — the menu, the proxy hop, or the container show — and they are not the
  same bug.

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
  `McIntosh MC2KW Amplifier VU`, `P-402 VU`, `Technics VU` — **eight, not nine**: they sit contiguous
  in `MAIN_LAYOUT_1_SCRIPT.maki`'s string table with sequential index bytes, and `LAYOUT1/Vu2/` ships
  exactly four needles and four scales. It binds **no control in the skin** to
  any of them, because in Winamp they appear in the preferences dialog. All the artwork ships
  (`LAYOUT1/Vu2/` four needles + four scales, `LAYOUT1/LVL/` Technics and RT level strips,
  `LAYOUT1/CAS/` 57 cassette bodies). **The eight are not registered into one section**: six are under
  `Visualizer [{E9C2D926-…-85E31755A4C4}]`, but `Ovis 1` and `Ovis 2` are under
  `{E9C2D926-…-85E31755A4CD}` — one hex digit apart, the skin's own typo, and the same catch-all
  section that holds `12`, `31`, `find Remaining`, `Bg Chng` and `SCALING Chng`. **Confirmed live
  2026-08-19: `Ovis 1` and `Ovis 2` show under the raw GUID, not under Visualizer.** That is the
  skin's own bug faithfully reproduced — do not "fix" it by re-homing them.
- **All seven non-cassette styles are one group.** `player.display.VU2` is declared once and placed
  once (`visible="0"`, 263×79) holding `SCALE`, `needleL`/`needleR`, `VUSDW` and the `LVLleft`/
  `LVLright` frame strips; the script picks children and swaps `image` on them. The full disassembly
  (`WINAMP_MODERN_RENDER_DISASM=@MAIN_LAYOUT_1.xml`) holds five distinct artwork blocks —
  `needleimgDef`+`SCALE1DEFBT`, `needleimgDef`+`SCALE2DEFLR`, `NEEDLE1MC`+`SCALE3MC`,
  `RT_Left`/`RT_Right`, and `Technics1_*` — so two of the eight names share a block with a variation.
  **Which two is unsettled**; selecting `Ovis 1`/`Ovis 2` live and looking is the cheapest answer.
- **`SCALENEON` and `needleimgNEON` are dead artwork.** Both bitmaps are declared
  (`LAYOUT1/VU2/SCALENEON.PNG`, `NEONNeedle.PNG`) and **no script references either** — zero hits for
  `NEON` in the full disassembly of `MAIN_LAYOUT_1.xml`. Nothing we do can show them; they are a
  fifth needle style the author cut. They are now listed in **Winamp Modern → Skin Settings...**
  along with the songticker modes below and the rest of the 32 options this skin registers
  (`WINAMP_MODERN_RENDER_SETTINGS=1` prints them). Whether picking one actually changes the display
  is the live pass.
- **Its two speaker cabinets are opened from the host's Skin Windows menu** (Phase 27). The skin
  declares `SPEAKER 1`, `SPEAKER 2` and `Config name="Skin Settings"` and binds no button to the two
  speakers — in Winamp they live in Winamp's own Windows menu. **`Config` is the exception, and this
  file used to say otherwise:** `<button id="CONF" action="TOGGLE" param="Config" x="272" y="282"
  w="74" h="74" rectrgn="1"/>` is the round button at the bottom-right of the main window, and its
  `param` is a **container id**, and **it works — confirmed live 2026-08-19.** Markup
  `TOGGLE param=<container id>` opens the window. It cannot be measured headlessly at all (see the
  trap below), so the harness is silent on it, not negative.
- **The speaker cones do not animate, and the cabinets render very dark — confirmed live 2026-08-19.**
  What is measured about it so far:
  - `SPEAKER.maki` **is bound**, twice, one per cabinet (two programs whose handler set is exactly
    `ondatachanged,onscriptloaded,onscriptunloading,onsetvisible,ontimer`, `failed=-`). Only
    `onscriptloaded` has ever run headlessly; `onSetVisible` — which starts the `getVisBand` timer —
    and `onTimer` have not. Do not go looking for an unbound script.
  - `SpeakerVis` is `autoplay="0"`, 264×264, image `RT_Speaker` = `DATA/SpAnim.png`, 264×6600 —
    **25 frames**, drawn *under* the `Rm_Speaker`/`Lm_Speaker` rim overlay (`SpRM.png` is a ring with
    a transparent centre).
  - **The harness renders the cabinet correctly**: wood panel, cone, tweeter — and its hash is
    identical on a clean profile (`defaults delete com.apple.dt.xctest.tool`) and after driving
    `onsetvisible`/`onplay`. So "very dark" is a live-only difference, and two obvious suspects are
    already eliminated: it is **not** the colour theme (`*Default` applies `Global.Speaker`
    `value="-800,0,0" gray="1"`, and the harness applies that too — the catalog defaults to the first
    gammaset) and **not** the `BG` background preference (the harness resolves `BG1_*` with or without
    a stored value).
  - **`getVisBand` was on a linear scale, and that is why they looked dead (fixed 2026-08-19).**
    Measured live with `WINAMP_MODERN_CALL_TRACE=1` while a track played: `getVisBand(0,0)` ran
    **min 0, max 39, mean 4, p50 1** out of 255, and the 25-frame cone spent **96.5%** of the track on
    frame 0 — its rest position, which also reads as "dark". The same mistake Phase 29 found in the VU
    meter, in the other tap: a linear FFT magnitude scaled by 255, where the artwork is cut for a
    logarithmic sweep. `visByte(forMagnitude:)` now maps through `20·log10` over a 60 dB window. Same
    skin, same track, after: **mean 139, max 232, frames 10–15**.
  - **But the animation is still nearly invisible, and that is the artwork.** The 25 frames of
    `DATA/SpAnim.png` differ from the rest frame by a **mean of 0.2–0.4% brightness and at most 5.5%**
    (measured per pixel). On a near-black cone that is imperceptible. The engine now feeds the meter
    correctly and there is very little to see; do not go looking for a further engine defect here
    without an external reference showing the cone visibly moving in Winamp.
  - **The cabinet renders correctly** — captured from the running app and compared against the skin's
    own `screenshot.png`: wood panel, detailed cone, tweeter, port. The cone is black because the art
    is black. "Very dark" is the artwork, not a gamma or background fault; the colour theme and the
    `BG` preference were both eliminated by measurement.
  - **`setScale` appears in `SPEAKER.maki` but is never called at runtime** (0 calls in a full live
    trace) — it is on the configurator's scaling path, not the cone's. A strict `strings` match also
    hides `gotoFrame` here, because method names in the table carry a trailing index byte
    (`gotoFrame)`); grep loosely or you will conclude the script cannot animate at all.
  - **Measured working in the harness, 2026-08-19** (needs a live confirmation): with
    `WINAMP_MODERN_RENDER_SHOW=SPEAKER1` the cabinet's script runs
    `onscriptloaded,onsetvisible,ontimer` with `failed=-`, and the rendered cone **changes with the
    level** — three distinct hashes at `RENDER_VU=0.0 / 0.5 / 1.0`. Two instrument gaps hid this
    completely: the harness could not *open* a `default_visible="0"` window (so `onSetVisible` never
    fired and the timer never started), and its injected spectrum was a **constant** ramp, which pins
    a `getVisBand`-driven meter to one frame however well it works. Both are fixed in
    `reference/harness.md`.
  - **Root cause found and fixed, 2026-08-19.** Phase 29 named it and it was right: auxiliary
    container windows install **no repaint route at all** (`drivesScripts: false` skipped
    `graphDidMutate`/`repaintRequested`/`objectRepaintRequested`, and those are single-owner). MAKI
    timers belong to the *runtime*, so `SPEAKER.maki`'s `onTimer` fired and stepped `SpeakerVis`
    perfectly well — the graph updated and no window was ever told to redraw. Auxiliary views now
    register a container-scoped repaint sink
    (`WinampModernScriptRuntime.addAuxiliaryRepaintSink`), so a mutation reaches the window that owns
    the object without dragging every other window into the main window's 30 Hz Layer FX repaint.
    **This is the same bug as the playlist box below** — one cause, two symptoms.
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
- **`getcurrentindex` is missing** (measured 2026-08-19). It does not appear at load — the startup
  report is still 0 unsupported methods — but **every** click on the four round buttons raises it.
  The textbook case of the queue-not-a-set rule: nothing sees it until something drives the event.
  What its result feeds is unknown; `WINAMP_MODERN_RENDER_DISASM=getcurrentindex` would say.
- **The playlist box's readouts were blank — two separate causes, both fixed 2026-08-19.** The user
  reported it as "the playlist window shows art but not the track information", and noticed that
  enabling *Two infoboxes in the playlist* makes the second box show it. That second box is a
  different group (`playlist.component.FileInfo`, off by default); the *first* box
  (`playlist.component.PlaylistInfo`) is the **playlist** box, and it is the one that was broken:
  - **`a3` — "Items: N"** comes from `System.getPlaylistLength()`, **not** from `PE_Info`. The method
    was unimplemented, and the call sits *before* the write, so it aborted the whole `onTimer` and
    the readout never appeared. Implemented, answering from the same snapshot `PE_Info` uses.
  - **`a1` — "Time: …"** comes from `getToken(info.input.getText(), "/", 1)`, where `info.input` is
    `<text id="info.input" display="PE_Info" w="0" h="0" visible="0"/>` — a hidden feed. The engine
    matched the status line on **`id="PE_Info"` only**, so this read empty. It now matches
    `display="PE_Info"` too, which is the form the **stock Winamp Modern skin also uses**
    (`<text id="PLTime" display="PE_Info"/>`) — so its playlist time had been silently blank as well.
  - **The `/` in the info line is inferred, not verified.** Defix takes token 1 of a `/` split, so the
    separator has to be `/`; `WinampModernPlaylistSnapshot.infoLine` now emits `N items/h:mm:ss`
    instead of `N items, h:mm:ss`. A capture of Winamp's own playlist showing that field would settle
    it, and that one line is the only place to change.
  - **`onTextChanged` was the missing piece, and it took three attempts to see it.** The subroutine
    that writes both readouts (instructions 3165–3241) has exactly **one** caller: `onTextChanged`
    calls it (`op25` is a call, not a jump). The `onTimer` sitting beside it only stops a spinner and
    returns at 3164. The engine never dispatched `onTextChanged` at all, so the subroutine was
    unreachable and the two method-level fixes above changed nothing on screen.
    `WinampModernScriptRuntime.refreshBoundText()` now polls host-bound text (a `display=` binding, a
    songticker, the status line — never a literal, which cannot change) and raises
    `onTextChanged(newtext)` on the ones that moved, driven from the controller's host-state hooks.
    **Verified on the real skin**: `a3` → `Items: 3`, `a1` → `Time: 6:00`.
  - **And it still could not have appeared**, because `pledit` is an auxiliary container and those
    windows installed no repaint route (see the speaker cones above), so even a correct write was
    never painted. Four separate faults stacked on one readout — the binding, the missing method, the
    undispatched event, and the missing repaint — and any one of them alone kept it blank.
- **`getcurrentindex` is on the playlist window's hover and click paths**, not its timer
  (`ontargetreached`, `onenterarea`, `onleftbuttondown`, `onrightbuttondown`, `onrightclick` — never
  `ontimer`, checked in the disassembly). So it does not block the readouts above, but it does abort
  those handlers; with `RENDER_SETTLE=2` it takes the whole skin's report to `unsupported`.
- **Clicking the time readout does nothing, and it should toggle elapsed/remaining** (confirmed live
  2026-08-19). `text#timer` is this skin's one `CLICKABLE` miss — `WINAMP_MODERN_RENDER_CLICKABLE=1`
  reports `text#timer(292,26,96,31)`, an object a script hooks the mouse on that the markup hit test
  rejects. The intent is unambiguous: `MAIN_LAYOUT_1_SCRIPT.maki` carries `Time elapsed`,
  `Time remaining` and a registered `find Remaining` setting. A real dead control — and the
  `CLICKABLE` probe named it before the user did, which is the argument for running that probe.
- **`setScale` is missing** — the configurator's seven window-scaling buttons (100–300%) are inert.
- **Most of its menus are host actions, and those are still unimplemented.** `trackmenu`/`trackinfo`
  (declared as `rightclickaction`/`dblclickaction` on the song ticker — both *attributes* are also
  unsupported), `VIS_Menu`, `VIS_Cfg`, `VIS_Next`, `VIS_Prev`, `PE_Add/Rem/Sel/Misc/List`,
  `ML_SendTo`. **`colorthemes_switch` works as of Phase 32** — and the skin turned out to ship a real
  picker after all: a `<ColorThemes:List id="picker">` in its `Config` window, under the heading
  "Color Themes", with a `Switch to selected Color Theme` button beneath it. It lists the skin's
  **5 distinct names** (6 `<gammaset>` elements over 197 `<gammagroup>`s; `*Default` is declared
  twice, then `Azure`, `McIntosh Lite`, `McIntosh`, `Technics`). The pre-Phase-32 claim that its
  colour themes were *unreachable* was measured before any probe could see a picker — `RENDER_THEMES`
  is that probe now.

  **This entry used to open "the skin builds no `PopupMenu` of its own", and that was wrong** — it
  builds four, one per round button (below). The claim came from the `RENDER_CLICK` probe reporting
  no menu, and the probe was the thing at fault, not the skin. Do not read a probe's silence as a
  statement about a skin until the probe has been shown to drive the event in question.
- **`newDynamicContainer` returns the existing container**, so the skin's detachable visualizer and
  second mini-browser share one window rather than opening a copy.
- **OPEN (Phase 31, to be returned to): the round buttons mis-target after a re-assignment.** Reported
  live 2026-08-19, after the two fixes above landed. The menu opens and the windows mostly open, but
  **picking an item shuffles the buttons around, and after the shuffle a button does not reliably open
  what its artwork says it opens.** Not yet measured; what is known and what to check first:
  - The script does not simply write the button you right-clicked. Each `onRightButtonDown` reads
    *all four* `MainBtn1..4` values first, and after the pick walks the other three
    (`if MainBtn2 == <picked> then setPrivateString(MainBtn2, <this button's old value>)`) — it is a
    **swap**, deliberately, so no two buttons can hold the same target. The visible re-ordering is
    therefore the skin working as designed; the defect is that what a button *targets* afterwards
    disagrees with what it *draws*.
  - The prime suspect is therefore the read-back path, not the menu: the artwork is set from the
    values in the handler's local variables, while the next left-click re-reads `getPrivateString`.
    If a swap writes one of those two and not the other, or writes them in an order that clobbers,
    artwork and target part company exactly this way.
  - **Measure it with `WINAMP_MODERN_RENDER_CLICK`, not by reading the disassembly.** Drive the
    right-click, then the left-click, on the same point in one run and read the `CLICK action:` /
    `CLICK window:` line — that is what the button resolves to, and it is now printed (below). Set
    the starting assignment with `WINAMP_MODERN_RENDER_CONFIG="Winamp Defix;MainBtn1=ML"`.
    Note the probe's popup presenter answers **0** ("picked nothing"), so a run that needs a *pick*
    has to be given one — teach the presenter to return a chosen id before starting.
  - Remember the config the probe writes persists, in the **test** domain
    (`defaults delete com.apple.dt.xctest.tool`), not the app's.

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
- **`CLICK_WATCH`'s `frame=not laid out` is a harness artifact, not a dead surface.** `CONF` looks
  exactly like a dead control headlessly — `bindings=false`, `onleftclick -> 0`, and
  `watch container#Config frame=not laid out state=[]` on two consecutive clicks. Watch `pledit`, a
  container that is `default_visible="1"` and demonstrably works, and it prints the same thing. The
  `container#SUI visible=0 -> 1` changes the four round buttons *do* produce come from the script
  writing a graph attribute, which is a different mechanism from markup `TOGGLE` routing. Do not read
  the first as evidence and the second as its absence.
- **A bare clock ladder says nothing about this skin's motion.** All six windows hash identical at
  t = 0 / 0.25 / 1 / 4 with `SETTLE=3`, because Layer FX is switched on *from playback*.
  `WINAMP_MODERN_RENDER_FX=play` is what shows the reels warping (grid 4×4, mesh 5×5, non-identity).
- **One refused method costs the whole window.** Every early defect here was a handler aborting
  partway: `getExtension` took the main layout's display with it, `fx_setGridSize` the VU meter,
  `newDynamicContainer` → `setFontSize` → `navigateUrl` → `hasVideoSupport` the global script, each
  surfacing only once the one before it was implemented.
