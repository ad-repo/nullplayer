# Debugging harness

Reference for the `winamp-modern-skin-guide` skill. **This is the canonical probe and environment-variable reference** — every other document points here.

## Debugging a skin

(Debugging *one* skin is below. For work spanning many skins — ranking what to implement next,
finding what a skin contains that we have never rendered — use
[triage-playbook.md](../triage-playbook.md) instead.)

**Start with [skins.md](../skins.md) if the report names a skin we have measured** — it records what
already works, what is knowingly missing, and the traps that skin sets.

**Then the compatibility report.** `WinampModernLoadedSkin.compatibilityReport` (and
`compatibilityReport(withRuntime:)`) aggregates load diagnostics plus the runtime's unsupported-method
tally into de-duplicated categories (`archive`, `resources`, `groups`, `scripts`,
`unsupportedMethods`, `other`) with a coarse level (`.full` / `.degraded` / `.unsupported`). In DEBUG
builds the main window controller logs it after `scripts.start()` whenever the level is not `.full`.
The `unsupportedMethods` bucket is the **measured-demand list** for what to implement next.

**Then look at the pixels.** Structural assertions (graph built, scripts ran, node counts) cannot see
a rendering bug: a vertical-flip and a wrong crop origin survived 490+ green tests because nothing
ever rendered a frame. `WinampModernRenderDumpTests` renders every container/layout of a real skin to
PNG and reports the scene:

```sh
WINAMP_MODERN_WAL=/path/Skin.wal \
WINAMP_MODERN_RENDER_DUMP=/tmp/render \
  swift test --filter WinampModernRenderDumpTests
```

Optional env switches, all off by default:

| Variable | Effect |
|---|---|
| `WINAMP_MODERN_ENGINE` | import + mount the ClassicPro engine first (cPro skins) |
| `WINAMP_MODERN_RENDER_PROBE=<container>/<layout>` | dump every scene node: type, id, frame, clip, bitmap, attributes |
| `WINAMP_MODERN_RENDER_BITMAPS=1` | count resolved bitmaps and list any that fail to load |
| `WINAMP_MODERN_RENDER_XUI=1` | list objects with scripts and whether their events bind |
| `WINAMP_MODERN_RENDER_CLOCK=<seconds>` | pin the animation/ticker clock; render two values to prove motion |
| `WINAMP_MODERN_RENDER_MINIMUM=1` | name the objects that set each layout's protective minimum |
| `WINAMP_MODERN_RENDER_CLICKABLE=1` | objects the markup-only hit test rejects but a script hooks the mouse on |
| `WINAMP_MODERN_RENDER_CLICK=<container>/<layout>@x,y[;x,y…]` | drive a click and report what it hit, its handler counts, **every attribute it changed anywhere in the graph**, the whole chain of handlers it set off, the menu a right-click builds, and a compatibility report taken *after*. Several points are driven **in order** — how you check that a second click undoes the first. Seven events, in the order the view sends them: `onleftbuttondown`, `onleftbuttondblclk`, `onleftbuttonup`, `onleftclick`, **`onrightbuttondown`**, `onrightbuttonup`, **`onrightclick`**. It also prints **`CLICK action:`** — the host action the click ends in — and **`CLICK window:`** — a container the skin asked to show or hide. Those last three lines are Phase 31 additions, and each of them was a defect the probe could not see: a skin that hangs its menu off the right-button *down*, a button that reaches its target through an invisible proxy's `leftClick()`, and a skin that opens its own window with `getContainer(id).show()` rather than an action. **The popup presenter here answers 0** ("the user picked nothing"), so a run that needs a menu *pick* must be given one |
| `CLICK toggled <id> activated=<0\|1>` (printed, not a variable) | the click flipped a togglebutton and sent it `onToggle`, mirroring what the view does. Phase 33 — a skin can hang a whole drawer off that event, and while the probe drove only the seven mouse events it reported a working toggle as seven zero counts |
| `WINAMP_MODERN_RENDER_CLICK_WATCH=<id>,<id>` | where those objects ended up after the click, changed or not — for "it opened, but in the wrong place" |
| `WINAMP_MODERN_RENDER_SIZE=<W>x<H>` | resize the layout (clamped, as a drag is) before measuring, so a defect can be reproduced at the user's window size. It resizes the *canvas* only — the app dispatches `onResize` on a real drag, so pair it with `RENDER_EVENTS=onresize` (applied after the resize) or a script-driven layout stays at its old width |
| `WINAMP_MODERN_RENDER_EVENTS=[<container>/<layout>@]onresize,onplay,…` | drive events in order before measuring, each at its real target with its real arity. **`onresize` first** for any ClassicPro skin: much of its state is only ever assigned there |
| `WINAMP_MODERN_RENDER_SCRIPTS=1` (or `=bindings`) | per program: owner, source, declared handlers, which events actually **ran**, and which failed with what. `=bindings` adds what every handler is bound to *right now* and each script group's ancestor chain |
| `WINAMP_MODERN_RENDER_DISASM=<method>` | the instructions around every call site of a method — how an unknown **arity** is settled, by counting the net pushes between the receiver and the call |
| `WINAMP_MODERN_RENDER_DISASM=@<source>` | the **whole** listing for every program whose path matches: each handler's entry point, every instruction, constants and method names resolved. Variable values are read *after* the run, so a `vN=null` at a `findObject` is a lookup that failed. This is how Winamp Modern's titlebar layout was recovered — an arity fits in an 8-instruction window, a layout routine does not |
| `WINAMP_MODERN_RENDER_SETTINGS=1` | every option the skin registered with `newAttribute` — item name, section GUID, current and default value. What the host's **Skin Settings** window will offer, and the only headless way to see options a skin registers for Winamp's preferences dialog and binds no control to |
| `WINAMP_MODERN_RENDER_THEMES=1` | the whole colour-theme picture: the catalog (count, names, active, default), every `<ColorThemes:List>` **in the graph** (with its container and `visible=`) and in the drawn scene (with its resolved frame and row count), and every object carrying a `colorthemes_*` action with the object its `action_target` resolves to. The only reproducible route — a `.wal` is a compressed NSIS archive, so `strings … \| grep -i colorthemes` answers 0 for skins that ship a full picker. Needs no `WINAMP_MODERN_RENDER_DUMP` |
| `WINAMP_MODERN_RENDER_FX[=play]` | every layer whose script has switched **Layer FX** on: grid, flags, and where the evaluated mesh samples its corners from. A mesh that is not the identity is a layer that is actually moving. `=play` tells the skin a track started first, because a meter's FX is switched on from playback |
| `WINAMP_MODERN_RENDER_FX_SPIN=<seconds>` | samples every warped layer's angle at 60 Hz, printing the wall-clock step between updates and how far it turned. This is how "the animation is rough" is split into *the script's cadence* and *our frame rate* — a smooth meter is a small, even step at an even interval |
| `WINAMP_MODERN_RENDER_SHOW=<container>[,<container>]` | open auxiliary windows the way the user does from **Skin Windows**, dispatching `onSetVisible` to them and settling again afterwards. Without it the harness only ever sees the windows a skin opens by default, so a defect confined to one that ships `default_visible="0"` — Defix's speaker cabinets, whose `getVisBand` timer *starts* from `onSetVisible` — is invisible to every other probe |
| `WINAMP_MODERN_RENDER_VU=<level>` | inject a program level per channel (0…1) for `getLeftVUMeter`/`getRightVUMeter`; `sweep` oscillates 0…1 at 0.5 Hz. The harness has no audio, so without it every meter reads silence and a needle's travel cannot be measured. It also **scales the injected spectrum**, because meters that read `getVisBand` rather than the VU (Defix's speaker cones) sit on one frame against the harness's otherwise-constant ramp and measure as dead at every level |
| `WINAMP_MODERN_RENDER_CONFIG=<section>;<key>=<value>[\|…]` | write skin configuration **before** the scripts start — where the app reads it from, since the value is persisted. How a skin option that changes what is drawn (Defix's eight display styles) is selected without a GUI. Note it *stays* set for later runs, and a skin may keep its own private copy (Defix: `CurVuVis`) |
| `WINAMP_MODERN_RENDER_TIME=<frames>` (+ `_SCALE=2`, `_CLIP=1`) | ms/frame for a full repaint. `_SCALE=2` is the number that matters — it is the Retina backing store the app actually pays for; `_CLIP=1` measures the same frame clipped to the warped layers' rects. Defix, after Phase 29's pre-scaled artwork cache: **3.5 ms at 2×** idle, 5.4 ms with both reels warping, 4.4 ms clipped (it was 19.3 / 6.9 when every bitmap was resampled to the backing scale on every frame) |
| `WINAMP_MODERN_DRAW_PROFILE=1` | per-object draw cost, top 8 — which node costs the frame, without a sampling profiler |
| `WINAMP_MODERN_FX_TRACE=1` | every `fx_*` call with its receiver: which layers a skin warps, and **when** it switches them on |
| `WINAMP_MODERN_CALL_TRACE=1` | every MAKI method call with its arguments and result |
| `WINAMP_MODERN_VU_LOG=1` | **live**, not headless: once a second, the arriving buffer's peak and RMS, the tap cadence, how many ~13 ms blocks it was split into, and the 0…255 byte range the skin receives across them. `peak` against `blockRange` is the whole diagnosis for "the meter doesn't follow peaks and valleys" — a wide block range with a flat needle is a skin-side ballistics question, a narrow one is a measurement question. `RENDER_VU` exercises only the half of the path *above* the meter |
| `WINAMP_MODERN_MAKI_TRACE=<program>` | every bytecode instruction of the matching programs, with the top of the value stack. The last resort, and the only thing that finds a wrong *result* from a handler that does not fail — it is how an integer-truncating unary minus was found collapsing a needle's angle to two positions |
| `WINAMP_MODERN_RENDER_SETTLE=<seconds>` | pump the run loop before dumping, so timer-driven state has happened — and **between driven clicks**, because a skin that gates a transition on a timer (`if (anim.isRunning()) return; anim.start();`, Defix's tab switch) never releases the gate without one, and a working control measures as one that only responds the first time |


Timing probes need an optimized build: `swift test -Xswiftc -O --filter WinampModernRenderDumpTests`
(a debug build is ~6× slower and will mislead you; `swift test -c release` does not compile, because
the test target uses `#if DEBUG` hooks). Two things that waste an afternoon: `cd`-ing out of the repo
before `swift test` fails silently when the output is piped to `grep`, and the harness's skin
configuration persists in the **xctest** UserDefaults domain between runs
(`defaults delete com.apple.dt.xctest.tool` resets it).

Use the probe to answer "is it missing art, bad geometry, or a script that never ran" before changing
renderer code — `BITMAPS … missing=` distinguishes an unresolved resource from one that draws wrongly.

**A dead control is usually a dead script, not a bad hit test.** `RENDER_CLICK` answers that in one
run: it prints the object under the point, `bindings=`, and the handler count for each mouse event.
`hits togglebutton#… bindings=false` with `onleftclick -> 0` means the script that should have hooked
it never ran.

> **Do not read `RENDER_XUI`'s `onscriptloaded=false` as "the script never ran."** It reports per-object
> *bindings*, and on cPro-Bento it says `false` for **every** object in the skin, `layout id=normal`
> included — whose scripts demonstrably run. An earlier phase pinned the inert tab strip on exactly
> that misreading and chased the wrong thing for two phases; the real cause was `Group.init(parent)`
> being a no-op. `RENDER_SCRIPTS` is the probe that observes execution, and `RENDER_CLICK`'s handler
> chain is the one that shows where a message stops.

**A control that responds but changes nothing is a chain that stops partway.** `RENDER_CLICK` prints
the chain (`CproTabButton.onleftbuttonup -> CproTabs.onaction -> CentroSUI.onaction`) and every
attribute the click moved. A chain that ends one hop early is a missing script-to-script route; a click
that changes the right attributes but nothing on screen is a renderer gap.

> **Gotcha:** the harness must install an `NSGraphicsContext` around `renderer.draw`. `drawText` ends
> in `NSString.draw(in:withAttributes:)`, which renders into the *current* `NSGraphicsContext`, not
> the `CGContext` it was handed. Without it every TrueType/system-font string is silently dropped from
> the dump while the real app (always inside `NSView.draw`) shows them — the harness lies to you.

> **`CLICK_WATCH`'s `frame=not laid out` is a harness artifact, not a dead surface.** The harness
> renders each container standalone and keeps no live container-visibility model, so a markup
> `TOGGLE param=<container id>` has nothing to move headlessly: the watched container reads
> `frame=not laid out state=[]` however well the button works. Check it against a container you know
> is fine — Defix's `pledit` is `default_visible="1"` and prints exactly the same. The
> `changed container#X visible=…` lines you *do* see come from a **script** writing a graph
> attribute, which is a different mechanism; do not read one as evidence and the other as its
> absence. A markup `TOGGLE` to a container id can only be judged in the app — and it does work
> there: Defix's `CONF` button (`action="TOGGLE" param="Config"`) opens its Skin Settings window,
> confirmed live 2026-08-19, while measuring as stone dead headlessly.

> **A bare `RENDER_CLOCK` ladder is not a motion verdict for a skin whose FX is switched on from
> playback.** Defix's six windows hash identical at t = 0 / 0.25 / 1 / 4 with `SETTLE=3`, and its
> reels are nonetheless warping — the FX is switched on from `onPlay`, which the ladder never sends.
> Pair the ladder with `RENDER_FX=play`, and read a flat ladder as "nothing time-driven **at rest**".

`RENDER_SETTLE` is usually the difference between a dump that means something and one that does not:
Love is War Miku's whole opening animation (the display panel sliding to `y=84`, the character to
`x=129`) runs on a 300ms timer, so without it the dump shows a scene the user never sees. And the
load-time compatibility report is **clean** for anything a click reaches — a handler that fails on a
missing method records nothing until something drives the event, which is why `RENDER_CLICK` prints its
own report afterwards.

> **An object a script creates is invisible to every walk — the graph one included.** The Phase 32
> theme probe walked the whole graph precisely so a picker inside a closed drawer would still be
> counted, and it *still* reported "multipass ships no `<ColorThemes:List>`". The list is real
> (`xml/player-normal.xml:262`); it lives in a groupdef whose only instantiation site is a
> `System.newGroupAsLayout` call, and that call was being refused. Nothing in the document, the graph
> or the scene showed it, because it had never been built. Two rules follow: read a "the skin does not
> ship X" verdict against `RENDER_SCRIPTS` **first** — a skin whose startup aborted ships nothing it
> would have built; and a `SETTLE`d run after a click sees more of a skin than any static walk does
> (multipass goes from 54 graph nodes to 118 when its drawer opens).

**The dump only ever renders a skin's *initial* state.** A defect a script mutation introduces later
(a font swapped at runtime, an object shown after a click) is invisible to it. `WinampModernCrashRepro`
is the opt-in harness for that case: it fires every standard event at every object in graph order,
redrawing after each, then sweeps the clock. It was written for a live-run crash it still does not
reproduce — extend it rather than starting over.

> **Anything a skin controls can reach CoreText, and a nil there kills the process.**
> `NSString.size(withAttributes:)` aborts with `attempt to insert nil object` if any attribute value
> is null — inside `NSView.draw`, so it is an app crash, not a bad frame. AppKit/CoreText
> constructors are imported as non-optional but can still return null, and **only an `Optional`
> binding sees it** (`let font: NSFont? = …`). `WasabiResources.font` therefore returns `NSFont?`,
> point sizes are clamped to a finite 1…256, and a skin TrueType with no PostScript name is rejected.
> Apply the same discipline to any new skin-derived value handed to a system API.

`WinampModernRenderPixelTests` is the synthetic guard for all of the above: a banded atlas whose crop
origin, upright orientation, tiling, and `fitparent` sizing are asserted per pixel. When you touch
`WasabiSceneRenderer`, verify a fix *fails* without the change before trusting it.

Load a developer archive directly (DEBUG builds):

```sh
./.build/debug/NullPlayer -uiMode winampModern -winampModernSkinPath /abs/path/Skin.wal
```

This still goes through `WinampModernSkinLoader` and its VFS — it is an acceptance hook, not a
filesystem bypass.

Run the engine tests:

```sh
swift test --filter WinampModern              # all synthetic coverage, headless
swift test --filter WinampModernPhase7Tests   # fuzz / stress / limits
```

Opt-in tests against user-supplied skins (nothing third-party is committed, so these skip unless the
env var is set):

```sh
WINAMP_MODERN_WAL=/path/CornerAmp_Redux.wal swift test --filter WinampModernPhase3Tests
WINAMP_MODERN_WAL=/path/WinampModern.wal     swift test --filter WinampModernPhase4Tests
WINAMP_MODERN_ENGINE=/path/ClassicPro_2.01.exe \
  WINAMP_MODERN_WAL=/path/cPro__Bento.wal    swift test --filter WinampModernPhase6Tests
```

Each phase expects a specific fixture — Phase 4 asserts Winamp Modern's 354×280 geometry, so
cPro-Bento is the wrong fixture for it.

---

## Debugging a live defect: what this subsystem taught the hard way

A GUI-only report ("the playlist shows no data", "the speakers don't animate") cost **three wrong
mechanisms in a row** before instrumentation settled it in one run. The rules below are the cheap
version of that afternoon.

### Instrument before you reason

Reading the skin's disassembly and the engine source and *deducing* the mechanism was wrong three
times. `WINAMP_MODERN_CALL_TRACE=1` on the running app answered it every time, in one launch:

```sh
WINAMP_MODERN_SHOW_WINDOWS=SPEAKER1,SPEAKER2 WINAMP_MODERN_CALL_TRACE=1 \
  ./.build/debug/NullPlayer -uiMode winampModern -winampModernSkinPath "/abs/Skin.wal" > /tmp/x.log 2>&1
```

Then count, don't read: `grep -c 'CALL-TRACE getvisband' /tmp/x.log`, and histogram the results. A
method being *called* proves nothing; what it *returns* is the finding.

### The measurement that finds scale bugs

**Histogram the frames a meter actually uses against the frames it has.** A healthy meter spreads;
a broken one piles on one:

```sh
grep -oE 'CALL-TRACE gotoframe\([0-9]+\)' /tmp/x.log | grep -oE '[0-9]+' | sort -n | uniq -c
```

Defix's cone: **frame 0 for 96.5% of a track**, out of 25 frames. That is a *scale* bug, not a dead
script — the script was running perfectly and being handed numbers at the bottom of its range. Two
have now been found this way (`getLeftVUMeter`, Phase 29; `getVisBand`, Phase 30), and one is still
open: the `<vis>` analyzer reads the raw levels directly as a fraction of height, so a full-scale
band draws at ~15%.

**Any host number handed to skin artwork must be in the unit the artwork is cut for.** Winamp's meter
values are vis bytes on a logarithmic sweep; a linear magnitude × 255 is the recurring mistake.

### When a fix changes nothing on screen, look for the *next* fault

Defix's playlist readouts had **four** independent faults stacked on them: the `display="PE_Info"`
binding, an unimplemented `getPlaylistLength`, an undispatched `onTextChanged`, and auxiliary windows
having no repaint route. Any one of them alone kept the box blank, so the first two fixes looked like
no change at all and read as "wrong fix". Re-measure after each one instead of reverting it.

### Reading MAKI disassembly without fooling yourself

- **`op25` is a call, `op33` a return.** A block sitting after a handler's `op33` is often a
  *subroutine*, entered from somewhere else entirely. Defix's playlist readouts live in one whose only
  caller is `onTextChanged`; read carelessly it looks like `onTimer` work, and the `onTimer` beside it
  merely stops a spinner.
- **Attributing an instruction to "the last `--- handler ---` above it" is wrong** for shared
  subroutines. Find the callers: `grep -oE '[0-9]+: op[0-9]+ -> <target>'`.
- **`strings` on a `.maki` hides method names**, because the constant pool stores a trailing index
  byte: `gotoFrame` appears as `gotoFrame)`. An anchored `^gotoFrame$` finds nothing and invites the
  conclusion that the script cannot animate at all. Grep loosely.

### Look at the running app

`screencapture -x -R<x>,<y>,<w>,<h> out.png` against the window bounds from System Events settles a
"it looks wrong" report in seconds, and the skin's own `screenshot.png` is the reference to compare
it against. Defix's speaker cabinet turned out to render **correctly** — the cone is black because the
art is black — which retired "very dark" as a defect and left the real question (does it move?) in
focus.

### The order that made Phase 33 cheap

multipass went from "a static picture, nothing works" to a `full`-compatibility skin in one session.
Not because the bugs were easy — there were seven, in four different layers — but because of the
order they were found in. Reuse it.

1. **Read the skin's own `.m` sources when the archive ships them.** multipass ships all fourteen.
   The whole diagnosis is `system.m`'s eleven-initialiser `onScriptLoaded` and line 72 of
   `drawers.m`; disassembly would have taken an afternoon to reach the same sentence. Check for
   `scripts/*.m` before `RENDER_DISASM`.
2. **`RENDER_SCRIPTS` first, always.** One `failed=… does not support method 'x'` line explained
   every symptom in the report at once. A skin whose startup aborted does not *have* features to
   debug, and any conclusion about what it "ships" drawn before that line is checked is worthless
   (Phase 32 recorded a real widget as absent for exactly this reason).
3. **Fix the abort, then re-measure before touching anything else.** Six of the seven faults only
   became *visible* after the one above them was gone: the abort hid the dead togglebutton, which hid
   the invisible seek bar, which hid its unclickable region, which hid the VM's integer division.
   Peeling in order costs one measurement each; guessing at the stack costs a rewrite.
4. **Ask what *kind* of object the skin built a control from before concluding it has none.**
   "There's no seek bar" — there is; it is an `<animatedlayer>` plus a `Map`, not a `<slider>`, and
   nothing that greps for `slider` will ever find it.
5. **Corroborate a VM-semantics decision in a second, unrelated codebase.** "Is MAKI's `/` integer
   division?" was settled by finding `integerToString(newvol / 255 * 100) + "%"` in ClassicPro's
   engine — a different author, the same idiom, and under integer division both are `0%`. One skin is
   an anecdote; two independent ones are the language's semantics.
6. **A one-skin fix is a claim about every skin: run the sweep.** The division fix turned out to
   repair cPro-Bento's `Volume: 0%`, MMD3's volume bar and two skins' slider fills. The same sweep is
   what proves a change *didn't* break the other sixteen — and note that one skin (Anexa's shade)
   renders differently run-to-run on an unchanged build, so diff the sweep against itself before
   reading a difference as a regression.
7. **Corpus-scan the attribute, not the button.** "This button does nothing" was `action="SYSMENU"`;
   grepping the 17 installed skins for `action="…"` found nine dead buttons across five skins and
   listed exactly what is still inert. One grep turns a bug report into a coverage decision.

### A blind instrument reads as a working feature

Three of this subsystem's probes were silently blind, and each one made a real defect look absent:

| Blind spot | Symptom it produced | Fixed by |
|---|---|---|
| Could not open a `default_visible="0"` window | Speaker cones unmeasurable; `onSetVisible` never fired | `RENDER_SHOW` |
| Injected spectrum was a **constant** ramp | Cones identical at every level, so "dead" | `RENDER_VU` now scales it |
| No component host, so `PE_Info` never *changed* | `onTextChanged` could never be observed | harness stands a synthetic queue |

When a probe says "nothing is happening", check that the probe can see the thing happening at all.

