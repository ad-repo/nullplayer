# Handoff — Big Bento Modern's visualization surfaces (2026-08-24)

> **SUPERSEDED 2026-08-24 — do not start here.** Everything durable in this file has been folded into
> its permanent home and, where it was wrong, corrected:
>
> | Was here | Now in |
> |---|---|
> | §1 what the user wants, §3.1–3.3 the `{0000000A}` model | `TASKS.md` → **BB9**, `skills/winamp-modern-skin-guide/reference/components/visualization.md` |
> | §3.2 what the component box should draw | `reference/components/visualization.md` → *The analyzer a `<component>` box draws* |
> | §3.4 the stretched pane drawing over the file info | **BB9** — cause measured since (`mcvcore`'s 700 ms one-shot); see `skins/big-bento-modern.md` → *BB9* |
> | §3.7 the undraggable splitter | **BB21, fixed** — `reference/rendering/frame-splitter.md` → *What outranks a splitter on its own grab strip* |
> | §3.8 the harness geometry blind spot | **BB20, fixed** — `reference/harness.md` |
> | §3.9 measurement notes | `reference/harness.md` |
> | §4 the hex-colour change | still uncommitted in `WasabiRenderer.swift`, with its sweep warning intact |
>
> §2 and §6 are kept as a process record. §3.5 (visualizations start intermittently) is the one
> finding here that has **not** been diagnosed or filed anywhere else.

Written at the end of a session that **failed**. Read the first two sections before touching code:
they are what the session got wrong, and repeating any of them will cost the same day again.

---

## 1. What the user wants

Big Bento Modern has **three placements** for a `{0000000A-000C-0010-FF7B-01014263450C}`
visualization component. In the skin's own settings they appear under *Visualization* as
`Open in Big Component View`, `Open in Multi Content View (stretched)` and
`Open in Multi Content View (mini)`.

| Placement | Where it is | XML | **Wanted** |
|---|---|---|---|
| Visualization tab ("Big Component View") | the SUI tab | `wdh.vis.object`, `player-normal-sui.xml:198` | **NullPlayer's visualization** — ProjectM / Geiss / Tripex |
| Mini | small box in the top panel, album-art sized (186×185) | `info.component.vis`, `player-normal-mcv.xml:135–138` | **NullPlayer's visualization** — ProjectM / Geiss / Tripex |
| Stretched | wide pane across the top panel | `info.component.vis.full`, `player-normal-mcv.xml:141–156` | **A spectrum analyzer** |

**Terminology, because it is the whole source of confusion.** In NullPlayer *visualization* means
ProjectM/MilkDrop, Geiss, Tripex — the preset-based full-window visualizer. *Spectrum analyzer* is a
different thing: the bar analyzer. Winamp does **not** draw that distinction in its skin vocabulary,
and this document uses NullPlayer's meanings throughout.

The user is confident from Winamp screenshots that the stretched pane shows a spectrum analyzer.
That is consistent with how Winamp works and is **not** contradicted by the markup — see §3.1.

Additional requirements stated during the session:

- **The tab and the stretched pane must work at the same time.** They currently cannot; see §3.3.
- The analyzer must not draw **on top of** the file-info panel. See §3.4.
- Visualizations load **intermittently** — often dead until you switch engines. See §3.5. This is
  reported for NullPlayer's own visualization window and mini too, not only inside a `.wal` skin.

---

## 2. What this session got wrong

All of this is reverted. It is recorded so the next agent does not re-derive it as a good idea.

1. **Started from the backlog's framing and never dropped it.** `TASKS.md` BB9 said "the
   visualization pane is missing — probably a setting the user cannot reach". Every user report was
   bent to fit that. It was the wrong problem. BB9 has been rewritten (§5).

2. **Treated the skin's markup as more authoritative than the user's screenshots.** When the user
   said the stretched pane is a spectrum analyzer, the session argued three separate times that
   `{0000000A}` is "Winamp's MilkDrop slot", citing the skin's `MILKDROP` preset-folder button as
   proof. That reasoning is wrong — see §3.1 — and it wasted most of the session.

3. **Fixed in the order defects were easy to find in source, not in the order that changes the
   screen.** Four changes, each a real defect, none the one being looked at:
   - a splitter-drag fix (reverted),
   - gating the GL surface off per holder (reverted),
   - making a `<component>` box borrow a `<vis>`'s colours (reverted — this is what produced the
     giant white slabs over the file info),
   - hex colour parsing (**kept** — see §4).

4. **Never established what "correct" looks like** before changing things, so there was no way to
   tell a fix from a change. **Get a reference first**: a Winamp screenshot of Bento with the
   visualization in the stretched pane settles size, band count, colours, and whether the file info
   is replaced or shared.

5. **Invested in tests, skill docs, a CHANGELOG entry and three backlog entries around an unverified
   change.** The user has asked repeatedly for the opposite: build the smallest change, hand it over,
   and write nothing until they confirm on screen. This is now a memory
   (`verify-before-investing`).

6. **Ran a debug build with a `.wal` skin loaded and left it running**, then asked the user about
   "broken visualizations" while what they were looking at was that debug process. Kill
   `.build/arm64-apple-macosx/debug/NullPlayer` before asking anyone to judge behaviour.

---

## 3. Findings worth keeping — the gotchas

### 3.1 `{0000000A}` is a plugin *host*, not "MilkDrop's box" — and we hardwired it

This is the central misunderstanding, and the actual bug.

`{0000000A-000C-0010-FF7B-01014263450C}` is Winamp's **visualization plugin host**. What renders in
it is whichever visualization plugin is currently selected, and Winamp's default there is its own
**built-in spectrum analyzer**. MilkDrop/AVS appears only when the user has selected it — which is
why Bento ships a `MILKDROP` preset-folder button under the stretched pane (`vis.full.buttons`,
script param `vis.prog.button,vis.prog.button,MILKDROP|MILKDROP|Milkdrop2 Presets folder`) *and* why
the user's screenshots show an analyzer there. Both are true. The button is for when MilkDrop is the
selection; it is not evidence that MilkDrop is the default.

NullPlayer gets this wrong in a way that makes the user's request impossible to satisfy today:

- `WinampModernMainView.reconcileHostedSurfaces()` mounts `componentHost.makeVisualizationSurface()`
  over **every** `.visualization` holder, unconditionally.
- `VisualizationEngineType` is `projectM` / `geiss` / `tripex` (`Visualization/VisualizationEngine.swift:94–100`).
  **There is no analyzer in the engine list.**

So a spectrum analyzer in a `{0000000A}` slot is not a setting nobody has found — it is unreachable
by construction. Any fix has to give that slot a way to be the analyzer.

The pieces already exist: `WasabiSceneRenderer.drawComponent` → `.visualization` already paints into
that box, and is suppressed only because a GL surface was mounted over it
(`hostedVisualizationHolders`). What it paints is not usable as-is — see §3.2.

### 3.2 `drawVisualizationBars` is a placeholder, not an analyzer

`WasabiRenderer.drawVisualizationBars` is twelve lines: 64 flat bars in one hardcoded green
(`NSColor(red: 0.3, green: 0.9, blue: 0.4)`), no skin colours, no peak caps, no falloff, no modes.
It was only ever meant to keep a `<component>` box from being empty.

The **real** analyzer renderer is `drawVisualization(_ object:frame:context:)`, which honours
`colorband1..16`, `colorallbands`, `colorosc1..5`, `colorbandpeak` (with decaying caps), `bandwidth`
and the object's `gammagroup`. It takes its styling from a `<vis>` **element**, so a `<component>`
box has none of those attributes.

**Do not** make the component box borrow a nearby `<vis>`'s attributes. That was tried this session
and it is what produced the screenshot the user called "complete shit": `bandwidth="wide"` is 19
bands, which is right for the skin's own 144px boxes and gives enormous slabs across a ~1400px pane.
Band count has to suit the box, and the mode/palette question needs a real answer rather than a
donor.

Bento's own analyzer offers eight modes from `visualizer.maki`'s right-click menu — *No
Visualization, Thick Bands, Thin Bands, Spectrum Analyzer, Lines, Dots, Solid, Oscilloscope* — plus
*Show Peaks*, *Show Grid* and two falloff speeds. We render analyzer and oscilloscope only.

### 3.3 All three placements are live at once, and one cached GL surface was hiding it

`WinampModernComponentBridge.makeVisualizationSurface()` returns **one** surface per skin and re-serves
it, deliberately, so a layout switch does not stand up a second engine. The consequence nobody had
seen: with three `{0000000A}` holders visible simultaneously, only one can ever hold the picture and
the other two sit empty — which reads as "the tab works and the mini doesn't".

The moment the GL surface was gated off and the box fell back to engine-drawn bars, all three drew.
That is the proof they are all live. **The user wants the tab and the stretched pane working at the
same time**, so a per-holder surface is needed, not the single cache. Weigh that against why the
cache exists (two GL contexts, two display links, two spectrum-tap consumers against the same audio),
and note §3.5 — more engines may make the intermittent-start problem worse.

### 3.4 The stretched pane draws over the file-info panel

`info.component.vis.full` and `info.component.infodisplay` are visible at the same time, so the
analyzer paints on top of the track text and the album art. In Winamp the stretched pane *replaces*
the file info. This is a placement/exclusivity problem in the Multi Content View and it is
**independent of anything this session changed** — it predates the whole session. `mcvcore` is the
script that owns the MCV's pane choice.

Note that headlessly only **one** `VIS holder` is ever reported, so this does not reproduce in the
render dump. It has to be measured live (`WINAMP_MODERN_DEBUG_HOLDERS=1`).

### 3.5 Visualizations start intermittently

Reported by the user against their own build: visualizations often do not run until you switch
engines. `reference/harness.md` already documents the shape — an engine will not start in a window
that is not on screen yet, and nothing restarts one that never started (the display-link lifetime
trap; `WINAMP-MODERN-VIS: resume … visible=<0/1> rendering=<0/1>` is the line to look at). **Not
diagnosed this session.** It may or may not be related to §3.3.

### 3.6 Inline colours can be hex, and we only parsed `r,g,b`

`WasabiSceneRenderer.color(_:)` split on commas and fell back to `unparseableColor` — which is
**white** — for anything else. Bento writes all 22 of its analyzer colours as `#rrggbb`
(`colorband1="#5a5490"` … `colorband16="#bda4fc"`), so the skin's purple analyzer drew as white
everywhere it appeared, including its own header boxes. Fixed; see §4.

Worth knowing generally: **an unparseable colour fails to white, silently.** A skin drawing
white-on-white is a parser question before it is an artwork question.

### 3.7 Bento's header analyzer is behind a splitter that cannot be dragged

Separate from everything above, and **unfixed** (the fix was reverted):

Bento declares six `<vis>` boxes in the player header (`main.vis`, `main.vis2` and two mirrors, plus
an `.alt` pair — `player-normal-group.xml:200–341`). `visualizer.maki`'s `onResize` shows them only
when its `w` argument exceeds 730 (`.alt`: 705). That width is the `player.mainframe.big` divider,
which the skin's own script clamps up to `minwidth="434"` at load — so the analyzer needs a splitter
drag to appear.

The splitter cannot be dragged. `WinampModernMainView.mouseDown` claims a divider only when
`renderer.object(at:) == nil`, and Bento covers every pixel of its window with
`<layer id="player.resizer.disable" … move="1" alpha="0">` plus four alpha-0
`player.mainframe.grabber.mousetrap*` layers on the seam itself. So every press drags the window,
while `resetCursorRects` shows a resize cursor over that same seam.

A patch that keys the rule on interactivity instead of emptiness is at
`scratchpad/bb9-revert.patch` (also carries the reverted tests and docs). **It was never confirmed on
screen** and should be re-derived rather than trusted. Note also that it was never established
whether Winamp starts Bento with a narrow player pane at all — if it does not, the real defect is the
divider's *position*, not its draggability.

### 3.8 Harness blind spot — geometry inside `onScriptLoaded`

`WinampModernRenderDumpTests` installs `runtime.resolvedGeometryRequested` inside its per-container
loop, long after `try runtime.start()`. Skins do nearly all layout in `onScriptLoaded`, so during it
every `getWidth`/`getLeft`/`getGuiW` falls back to the raw markup attribute — `0` for a
`w="0" relatw="1"` group. Bento's visualizer measured `getwidth() -> 0` headlessly against `346`
live. **Both values hide the analyzer, so the harness agreed with the symptom for the wrong reason.**

The app is the model: `wireContainerCallbacks` installs the closure *before* `scripts.start()` and
consults every container's renderer. Fixing the harness will move images in the 288-image sweep —
that is expected, not a regression.

### 3.9 Measurement notes that cost time

- `WINAMP_MODERN_RENDER_SET`'s section is the **GUID**, not the item name the settings dump prints
  first. With the name it writes nowhere and reports `handlers=0`.
- Bento keeps two options apart by **trailing spaces**: `Visualization ` (one space) in
  `{8D3829F9-…}`, `Visualization  ` (two) in `{6A619628-…}`. Get it wrong and the write is lost.
- The visualizer's own options — *Alt Visualizer*, *Visualizer Mode*, *show Peaks/Lines*, the two
  falloffs — are `System.getPrivateInt("Big Bento Modern", …)`, **not** registered settings, so their
  absence from `WINAMP_MODERN_RENDER_SETTINGS=1` is not a defect.
- The MCV defaults are `[{6A619628-…}] Visualization   = 0`, `[{8D3829F9-…}] Visualization  = 0`,
  `Album Art = 1`. Flipping one runs 25 `onDataChanged` handlers and the dump then prints
  `VIS holder main/normal: vis(447, 50, 1074, 147)`. The plumbing works; the question is what fills it.

---

## 4. State of the tree

One uncommitted change, kept because it is independent and confirmed on screen:

- `Sources/NullPlayer/WinampModern/WasabiRenderer.swift` — `hexColor(_:)` plus its use in
  `color(_:)`. Parses `#rrggbb` and the three-digit shorthand. Builds clean.

**It has no test and no documentation, deliberately** — the user asked that nothing be written until
they confirm a change works. They have seen the analyzer turn purple, so the change does what it
claims; whether it stays is their call.

> **DO NOT COMMIT THIS WITHOUT THE CORPUS SWEEP.** `color(_:)` is the parser behind *every inline
> colour attribute in every `.wal` skin* — not just `<vis>`. Anything that previously wrote a `#`
> value was silently resolving to white, and now resolves to the colour it asked for. That is
> correct, and it will change pixels in skins that have nothing to do with Bento. Run the 288-image
> render sweep pixel-diffed against a build of `HEAD` and **inspect every changed image** before
> committing:
>
> ```sh
> defaults delete com.apple.dt.xctest.tool     # skin config persists in the xctest domain
> WINAMP_MODERN_RENDER_DUMP=/tmp/after swift test --filter WinampModernRenderDumpTests
> ```
>
> Diff in **RGB, never RGBA** (`getbbox()` on an RGBA difference answers from the alpha band and every
> dump is opaque, so it reports identical images that look nothing alike). Discount Anexa's
> `main-shade`, which differs between two runs of the same binary. Both halves of the pair must be
> taken with nothing else run in between — any probe that calls `runtime.start()` writes skin
> configuration and contaminates the second half. See `reference/harness.md`.

Everything else from this session is reverted. `scratchpad/bb9-revert.patch` holds the splitter work
if any of it is wanted later.

---

## 5. Corrections to the archived Bento backlog

`BB9` as written is misleading and has been rewritten in place. For the record, what was wrong with it:

- It called this "the visualization pane is missing — **probably a setting the user cannot reach**".
  The defaults are reachable and the plumbing works. The real defect is that the slot can only ever
  be ProjectM (§3.1).
- It asked "does an embedded `<component hold=…>` in the player body get a visualization surface from
  us at all?" — **yes**, measured. That question is closed.
- It pointed at BB7 and B40 as the route. Neither is involved.
- It cited `mcvcore.m:256`, `:266–267`. **The skin ships no `.m` sources** — only compiled `.maki`.
  Those line numbers refer to nothing in the archive.

BB20 (harness geometry, §3.8) and BB21 (this work, §3.1) are filed there as follow-ups.

---

## 6. Working agreement for whoever picks this up

The user was explicit, more than once:

- Make the **smallest** change, build it, and hand it over. Say what to look for and what would
  falsify it.
- **Write nothing** — no tests, no skill docs, no CHANGELOG, no backlog updates — until they have
  confirmed it on screen.
- Do not argue markup against what they are looking at. If they conflict, the screen is the fact and
  the markup needs a better reading.
