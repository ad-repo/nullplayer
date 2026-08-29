# MAKI scripting

Reference for the `winamp-modern-skin-guide` skill: the bytecode VM, script-built UI, rotary maps, and the host data scripts read.

### MAKI

`MakiBytecodeParser` reads the `FG` compiled-script format (classes, methods, typed
variables/constants, bindings, instructions); `MakiInterpreter` executes it. The opcode surface is
**demand-driven** — opcodes were added because a measured target skin needed them, and unsupported
opcodes **fail closed** rather than becoming silent no-ops.

A missing method aborts only the script event that hit it — the rest of the skin's scripts still run
and the failure is collected into the compatibility report. It cannot be finer-grained than that:
call sites carry no argument count, so without a signature the stack cannot be unwound.

**"Only the event that hit it" is not a small blast radius when the event is `onScriptLoaded`.** A
skin does its wiring there: a script that aborts on its third line never places the widgets its last
forty lines position. Big Bento Modern (B36/B37) is the worst measured case — one unimplemented
method, `System.getSettingsPath()`, appeared near the top of 23 of its `onScriptLoaded` handlers
(the skin probes `<settings>/WACUP_Tools/koopa.ini` to see whether it is running under WACUP), and
those 23 aborts were the single cause of *five separately reported rendering defects*: a menu bar
whose five items drew on top of each other, an album-art panel that stayed black, empty time
readouts, a WACUP logo drawn over the Winamp one, and a search panel that never hid itself.

The lesson for triage: when several unrelated-looking surfaces in one skin are all wrong,
`RENDER_SCRIPTS=1` and read the `failed=` column **before** measuring any of them. Five symptoms with
one cause is the normal shape here, not the exception — and each of the five would otherwise have
been chased as a widget-layout bug. Implementing `getSettingsPath` then surfaced three more methods
that had been masked behind it (`getAutoHeight`, `getGuid`, `scrollToPercent`); expect to iterate.

A program the parser cannot read at all is dropped the same way (Phase 35): `WinampModernScriptRuntime`
records its diagnostic and keeps the programs it *could* read, rather than failing the skin. One
unreadable script used to cost the whole skin — which is how `Overdrive_2` stayed invisible after its
include defect was fixed.

**Two MAKI layouts share one version word.** A pre-5.0 `mc.exe` wrote `0x0403` files that differ from
the modern form in two ways, and nothing in the header distinguishes them — `Overdrive_2` ships four
ordinary programs and one of these (`scripts/seek.maki`, 2001) side by side:

| | modern | pre-5.0 |
|---|---|---|
| class GUID table | `count`, then `count`×16 bytes | **absent** — the count is not written either; the method table follows the header word directly |
| variable record | 14 bytes, trailing `global` + `system` | **13 bytes**, that pair replaced by one `object` flag |
| the System object | the variable with `system=1` | variable **0** (the first one a MAKI program declares) |

`MakiBytecodeParser` tries the modern reading and **retries** in the legacy one when it fails, so a
genuinely corrupt file still reports its own error. With no class GUIDs, a call dispatches on its
*name* (which the interpreter already does for an out-of-range class index) and `MakiProgram
.classGUID(atIndex:)` tells a `PopupMenu` from everything else by the method names declared against
the class — everything else becomes a generic dynamic object, which is what a `Map` needs anyway.

> **Gotcha:** `MakiInterpreter.dispatcher` is `weak` (the runtime owns the dispatcher). If you
> construct an interpreter in a test with a temporary dispatcher, it deallocates immediately and
> `execute` silently returns at its `guard let dispatcher` without running an instruction — the test
> then passes for the wrong reason. Bind the dispatcher to a local first.

Extending the API: add to `signature(for:)` **and** the matching system/GUI/object dispatch path
together, so argument counts and return kinds stay explicit. Add a regression test with each method.
Use the measured-demand signal rather than porting reference stubs blindly — see
[Debugging](#debugging-a-skin) below.

> **Gotcha:** a method with a `signature(for:)` entry but a stubbed dispatch case is **invisible to
> the compatibility report** — it looks implemented and returns a plausible value. `newgroup`
> returned `.null` this way, and the report showed zero script findings while the entire Winamp
> Modern window body was missing. If you cannot implement a method, leave it out of `signature(for:)`
> so the demand tally records it.

> **Gotcha:** the blocking list is a **queue, not a set**. Each method you add lets its script run
> further and reach the next thing it needs, so the report after a fix names methods the report
> before it could not have known about. cPro-Bento took three full rounds (9 methods → 4 → 0).
> Re-measure after every change; never work down a static list.

> **Gotcha: a float constant is two 16-bit halves, and the high half must be widened before it is
> shifted.** `(0x80 | (initial2 & 0x7f)) << 16` on a `UInt16` shifts the implicit leading one and every
> stored bit clean out of the word and leaves only `initial1`, so **every** float and double in every
> script decoded to a fraction of its value. Nothing failed and nothing was reported: Love is War
> Miku's volume step (2.55 of 255) arrived as 0.003, so the buttons ran their whole handler, called
> `setVolume`, and moved the level by nothing. Scripts reach for floats rarely enough that this
> survived every phase — assume any *arithmetic* result is untested until a skin has been watched
> doing the arithmetic.

MAKI's casts are System methods (`System.Integer(v)`, `Float`, `String`, `Boolean`), and a script
reaches for them wherever it mixes a float with an int-typed API — which is exactly where the volume
path runs.

**Opcodes are exercised at the same rate as methods** — that is, barely, until a script gets far
enough to use one. `delete` (opcode 97) consumed its operand for eight phases before anything reached
it. `delete obj` is an **expression**: the compiler emits `push; delete; pop`, so the opcode must
leave the value for the statement's own discard pop. When you first unblock a batch of scripts,
expect the *next* failure to be an interpreter bug rather than a missing method.

**A parse failure is worse than a runtime one** — it kills the whole skin, not one event. Opcode 104
(dynamic `Member` access) carries an immediate shaped like a variable record's first two bytes: a
type offset, then an "is object" flag. `Member GuiObject Tab.left;` therefore compiles to
`0x0100 | classIndex` (265 in ClassicPro's `CproTabs.maki`), which read as a plain value kind is an
"unknown value type" and fails the parse. Object members carry their class GUID through to the
member's storage.

#### Script-built UI: `onSetXuiParam` and `System.newGroup`

Winamp Modern's window frames are **hollow XML**. `Wasabi:MainFrame:NoStatus` ships only titlebar and
menubar chrome; the entire client area comes from its `content=` param at runtime:

1. The object is created from the groupdef, and its script (`standardframe.maki`) is bound to it.
2. `onScriptLoaded` fires (a **System** event) and the script caches `getScriptGroup()`.
3. Each XML attribute is delivered as `onSetXuiParam(name, value)`.
4. The handler for `content` calls `System.newGroup(id)`, which expands that groupdef as a child of
   the calling script's own group; the script then positions it with `setXmlParam`.

Three ordering rules make or break this:

- `onSetXuiParam` is a **System** event, not a GUI-object event, and each XUI instance has its own
  program instance. Dispatch it only to programs whose `ownerID` is that object, or one frame's
  `content` reaches all of them.
- It must run **after** `onScriptLoaded`. The handler binds to the script-group variable that
  `getScriptGroup()` populates during `onScriptLoaded`; dispatched earlier, no binding matches and
  every param is silently dropped.
- A **skin-level `<scripts>` block loads last** — after every object's `onScriptLoaded` *and* after the
  params. It sits at the end of `skin.xml`, which is where Winamp reads it, and it is the one script
  that may assume the rest of the skin is configured. Defix's lays out its whole SUI tab strip as
  `label.getAutoWidth() + 20` per tab; run before the labels arrived as params, all five tabs came out
  at that bare 20px, stacked at the left edge. `start()` therefore runs object-owned scripts, then
  `deliverXUIParams`, then the skin-level ones — do not collapse it back into one pass.
- **`notify="key,value"`** on a group instance delivers `onSetXuiParam("key", "value")` even when the
  instance tag is `<group>`, not the XUI tag name. Lobe's Pledit uses
  `<group id="wasabi.standardframe.statusbar" notify="content,pledit.normal.content.group">` — the
  standard frame script needs `content` to call `newGroup`, but `deliverXUIParams` only sends
  attributes for XUI-tag instances. `notify` is parsed separately and fires on any object with scripts.

`<script param="…">` may carry Winamp's markup macros rather than a path. The expanded XML document
resolves `@HAVE_LIBRARY@` to `1` (we host a library surface) before initialization, and leaves
anything unknown untouched; the VFS is not involved. Defix's global script reads
`stringToInteger(getParam())` as "is there a media library?" and drops the tab when told there is not.
See [loading.md](loading.md) for the document-wide rule; four other skins use the same macro on a
container attribute instead of a script.

`WasabiSkinRuntime.instantiateGroup` performs the expansion (set by `WasabiSkinInitializer`, so
runtime growth shares the load-time VFS, limits, and object budget). Scripts declared inside the new
subtree are parsed and started via `startScripts(addedBeneath:)`, bounded by `maximumRuntimePrograms`
and by `maximumRuntimeScriptStartDepth` (a new subtree's `onScriptLoaded` may instantiate more groups;
ClassicPro nests two levels — the SUI builds the tab strip, which builds each tab).

**`newGroup` is only half of it.** Wasabi instantiates in two steps, and a skin that uses both needs
both:

```c
Tab tabI = newGroup("cpro.tab");   // created under the *calling script's* group
tabI.init(tabHolder);              // moved where it actually belongs
```

- `init(parent)` **reparents**. Treating it as a no-op left every cPro-Bento tab in the wrong parent,
  so each tab button's `setDispatcher(getScriptGroup().getParent())` addressed an object nothing was
  listening on — the tab strip had never worked in any version.
- The new subtree's own scripts must start on **attachment**, not on creation: a script's first act is
  to look around from its own group (`getScriptGroup()`, `getParent()`, `findObject`), and started
  before `init` it sees the wrong parent. Groups wait in `pendingRuntimeGroups`; one that never gets an
  `init` (Winamp Modern's frames simply leave theirs where `newGroup` put them) starts anyway once the
  outermost dispatch unwinds.
- That nested `onScriptLoaded` is dispatched to a **subset** of programs while the outer one is still
  on the stack, so the re-entrancy guard is keyed by dispatch scope as well as by (target, event) —
  otherwise the outer dispatch swallows it and every runtime-created control comes up unbound.

#### `GroupList.instantiate` — the list that builds its own entries

The **other** runtime expansion, and a different receiver from `System.newGroup`:

```maki
Group g1 = grplst.instantiate(param, 1);   // "1" here is the amount of times the group
Group g2 = grplst.instantiate(param2, 1);  //  will be instantiated
```

That comment is the author's own, in Big Bento Modern's `config_vscrollbars.m`. Three things it
settles, each of which a first reading of the call site got wrong: the second argument is a **count**,
not an index; the receiver is a `<GroupList>`, not a plain group; and the result is usually *not used*
— the call is made for its side effect on the list.

A `<GroupList>` is a **vertical stack**, and the two things a groupdef cannot carry have to be stamped
onto each entry as it is added:

- **Width.** The entries declare `h=` and no `w=` at all, because the list is expected to size them.
  Left at its markup geometry an entry is zero-width — and its own contents, which are relative to it
  (`w="-203" relatw="1"`), are *negative*, not small. Each entry is set to `x="0" w="0" relatw="1"`.
- **Top.** Every entry would otherwise land at `y=0` and cover the one before it. The offset is the
  sum of the earlier entries' **declared** heights. Declared, not resolved: they are stacked before
  any layout pass has run, so a resolved frame exists for at most what is already on screen, and it is
  the declared number the author sizes the page around — the same number the page's scrollbar script
  compares its `param`'s third token against to decide whether to show itself at all.

Everything else is `newGroup`'s machinery unchanged: `instantiateGroup` does the expansion, the new
subtree's scripts wait in `pendingRuntimeGroups` and start on attachment, and the count is bounded
(64) on top of the shared object budget because it is skin input.

**This is how a WACUP-era skin ships its options.** Big Bento Modern's nine config pages and its SUI
equalizer tab are each an empty `<GroupList>` plus a scrollbar in XML; every control on them lives in
a `…part1` / `…part2` groupdef that one script expands here. Before the method existed the pages had
no content and the whole four-variant family reported compatibility level `unsupported` although it
drew perfectly well. Expect a cascade behind it (`getApplicationPath` was the next domino): a page
that has never been built has scripts that have never run.

#### Binding a host singleton by class GUID

`System` is not the only global a skin's `std.mi` declares. `PlEdit` (the playlist editor) and
`ColorMgr` (the colour-theme manager) are system-flagged globals of their *own* classes, and the
engine binds them by class GUID rather than by the names they answer to. Four things make that work,
and each of them is a way to get it silently wrong:

1. **`MakiClassGUID.runtimeBound` is a carve-out, not an allow-list.** The parser seeds a
   system-flagged global with the `System` object *unless* its class is in that set, in which case it
   leaves it null for `seedHostSingletons` to fill. Forget the carve-out and the global keeps the
   System object: every call on it falls through to `invokeSystem`, reports the method unsupported,
   and aborts the handler.
2. **The stored constant is the canonical form; the *input* is the raw one.** `signature(for:classGUID:)`
   receives the class table's raw value and folds it itself. `MakiClassGUID.canonical` is an
   **involution** — folding an already-folded constant hands back the raw form — so comparing against
   a pre-folded value matches nothing, and matches nothing *quietly*.
3. **The GUID the interpreter passes is the method's *declaring* class**, not the receiver
   variable's. That is what makes a short verb bindable at all: `apply` can be given an arity because
   it is gated to `GammaSet`, and a method of the same name on another class still gets `nil`.
4. **Gate the name even when the corpus says it is unique today.** `apply` appears on exactly one
   class across the installed skins; registering it globally would still be wrong, because a wrong
   arity is the one error the interpreter cannot recover from — it leaves values on the stack and
   desynchronises everything after the call. Fail-closed costs one handler; a wrong arity costs the
   rest of the program.

To find the GUID: dump `program.classes` and the `isSystem`/`isGlobal` variables of a program that
calls the method. The class table is binary, so `strings` on the `.maki` shows the method names and
never the GUIDs.

`ColorMgr.getGammaSet(name)` hands back a `GammaSet` carrying only that name; `apply()` on it routes
through `themeSwitchRequested` — the same route `System.setColorTheme` already takes, deliberately,
so the two cannot disagree about the active theme. A name the skin does not ship is answered with the
object anyway and `apply()` is inert: refusing at `getGammaSet` would abort the caller's whole
handler over one bad name.

#### Rotary controls: `Map`

A `Map` is a bitmap the script samples rather than draws: `getValue(x, y)` returns the pixel value at
a point (MMD3's `map.png` is a 44×44 grayscale sweep of the knob's angle) and `inRegion(x, y)` says
whether the point is on the control. `new Map` and `new Timer` produce the same kind of dynamic
object — class GUIDs are not in the archive — so an object becomes a map on its first `loadMap`.
Knob scripts mix `getMousePosX()` with the x/y of a mouse event in one expression, so the cursor
position is reported in **skin pixels**, not screen points; UI Size never enters the script's world.

**The two are not the same space, and that is why the expression exists.** `getMousePos*` is the
window's canvas; a mouse event's x/y are relative to the **receiver's parent** — the same origin
`getLeft()`/`getTop()` answer from. Every rotary control in the corpus is written that way:

```c
// LOBE and Rika, in the handler itself:
float v = map.getValue(x - anim.getLeft(), y - anim.getTop());   // → the object's own pixels
// mmd3, shipped as source in scripts/volumebasstreble.m:
WinX = getMousePosX() - x + Volume.getLeft() + (Volume.getWidth()/2);   // → the knob in cursor space
```

`getMousePosX() - x` is the parent's origin, which is the conversion mmd3 needs and the reason the
subtraction is written at all. Sending the canvas point made LOBE's seek dial sample (213, 26) of a
48×35 map — zero everywhere — so its dial seeked to 0 and its volume strip set 0 (B30, 2026-08-21;
Styx's volume knob was the same). mmd3's own knob group is at (0, 0), which is why the two
conventions agreed there and this survived 50 phases. Converted once, in
`WinampModernMainView.dispatch`, so every mouse event (and the `RENDER_CLICK` probe) uses it.

A `Map` is also a general **image-inspection** object, not only a knob lookup: `getWidth`/`getHeight`
size things from artwork, and `getARGBValue(x, y, channel)` reads whole pixels — ClassicPro derives
its visualization colour bands this way (`colorbandpeak="r,g,b"` from channels **2, 1, 0**, i.e. the
index is BGRA). And `loadMap` takes **either a resource id or a VFS path**; ClassicPro's "is the
plugin installed?" probe is the path form (a 1×1 `installed.png`, checked with `getWidth() != 1`).
Supporting only ids made cPro-Bento conclude the engine was missing and try to switch skins.

#### Asking a skin what it actually shipped

Engines are written to run against skins that omit optional pieces, and they ask two questions:

- **`isInvalid()`** — is this object real? True for a null receiver *and* for an object whose declared
  bitmap never resolved. ClassicPro probes for optional artwork by declaring a hidden layer over it
  (`<layer id="read.bg.left" image="player.left.alt" visible="0"/>`) and asking that layer. Answering
  "valid" for a skin that ships no `mainframe_lr.png` sent `player.maki` on to swap the window frame
  over to bitmaps that do not exist — visible as holes punched through the window's edges.
- **`getCurCfgVal()`** — the value of the config attribute the object is bound to via
  `cfgattrib="{GUID};Name"`. The GUID is the section key, the same addressing `getItemByGuid` uses.

#### Monitor dimensions are logical desktop coordinates

`System.getMonitorWidth()` / `getMonitorHeight()` answer the whole display containing the skin's
**player window**, not unconditionally `NSScreen.main`. That distinction is observable as soon as the
player moves to a secondary display: Big Bento uses the width to size its right-side playlist and
uses both dimensions for notifier placement.

The values are AppKit **logical screen points**. Do not multiply `NSScreen.frame` by
`backingScaleFactor`; Retina backing pixels are a rendering detail and would put the monitor in a
different coordinate space from the runtime's other desktop values. This is separate from a view's
canvas coordinates: mouse/object geometry remains in skin pixels and UI Size is applied at the view
boundary. A System monitor call has no GUI receiver from which the runtime can discover a window, so
`WinampModernMainWindowController` supplies the active player's screen through
`monitorSizeRequested`; the runtime's `NSScreen.main` lookup is only an unwired/headless fallback.

MAKI exposes signed integers, so fractional AppKit dimensions floor, non-finite or non-positive
values become zero, and oversized values clamp to `Int32.max` rather than trapping during conversion.

#### Track metadata the skins actually read

Skins do not call dedicated bitrate/sample-rate APIs. `songinfo.maki` lowercases
`System.getSongInfoText()` and pulls values out around the literals `kbps`, `khz`, and the channel
words. The units must be **attached to the number** (`320kbps`, `44khz`) — a space between them and
the fields stay empty. `WinampModernHost.songInfoText` builds this; `trackDisplayTitle` supplies the
`"Artist - Title"` a song ticker shows (`trackTitle` alone drops the artist).

A skin reads that string through a `<text display="songinfo">`, so that binding must carry
`songInfoText` and not the artist/album, or its KBPS/KHZ fields stay empty however good the parse is.

For the *per-field* tags — the ones a file-info panel prints a line each for — a skin calls
`System.getPlayItemMetaDataString(key)`. That table lives on the host
(`WinampModernHost.playItemMetadata(forKey:)`) and is documented once, in
[compatibility/maki-surface.md](../compatibility/maki-surface.md). Two things to carry away before
you go there: `""` means "hide this line", so an unanswerable field must never get a placeholder;
and everything past title/artist/album comes from the **library row** for the playing file, because
a `Track` does not carry them. That is also why a skin can show a full panel for a local file and a
four-line one for a Plex stream without anything being broken.

A `songticker` carries no `text`/`default` attribute — its content **is** the current track, and it
scrolls by default. `ticker="bounce"` slides to the end and back; any other enabled value scrolls
continuously and is drawn twice with a gap so it never blanks between cycles. Both the TrueType and
bitmap-font paths share `tickerMotion(for:overflow:textWidth:)`.

#### `getAutoWidth()` / `getAutoHeight()` measure the string; they never read the box back

A `<text>` carries two different sizes — the **box** it was declared with (`w`/`h`, often
`relatw="1"` and therefore its parent's) and the **line** its string occupies. `getAuto*` is the
line's, always, and answering with the declared attribute instead is a feedback loop waiting for a
skin that sizes a container from a label inside it. Big Bento Modern is that skin: `tabcontrol.maki`
sets each SUI tab to `4 * label.y + label.getAutoHeight()` where the label is declared `h="60"` inside
a 60-tall tab, so the declared height fed itself back in and every tab came out 96 — icons stretched
1.66×, strip drifting 37px per tab (BB24). The order for both is: an `autowidthsource` /
`autoheightsource` object first, then — for `text` and `songticker` — the measurement, then the
declared attribute and the artwork for everything else. A **group** still answers from its declared
size; only text objects measure.

**The stock skin is the second instance, and it was invisible for eight phases.** Winamp Modern's
titlebar centres its title and sizes the two streaks either side of it from
`title.getAutoWidth()`, where the title is declared `w="50"` and carries a *different string in every
window* (`WINAMP`, `VISUALIZER`, `VIDEO`, `:componentname`). Every window was laid out as though its
title were 50px wide; the playlist's is 75. Nothing looked broken — the streaks flanked a plausible
box — which is the shape to expect from this defect: a fixed `w` on a text object is usually a
placeholder, and a layout built on it is wrong by however far the string misses it.

**`fontsize` *is* the line height.** Winamp hands that number to GDI as the font's cell height, so a
script reads back exactly the number the skin wrote — not a value derived from the face's metrics.
CoreText's ascender−descender+leading for the same label answers 25 against Winamp's 24, which is
invisible in one control and a pixel of drift per tab in a strip of seven. The point size the
*drawing* uses is the other number, 0.8 of this one (`pixelHeightToPointSize`), because the em GDI
renders inside that cell is smaller than the cell. `WasabiTextMetrics.pixelHeight(of:)` and
`pointSize(of:)` are the two, and a bitmap font answers from its own `charheight + vspacing` before
either.

#### What a text object shows: `setText` beats `display=`, and `setText("")` gives it back

Four things can answer for one `<text>`, and the order between them is the whole rule.
`WasabiTextMetrics.content(of:host:)` resolves it, and every reader goes through that one function —
the renderer, `getText()`, `getTextWidth()`, `getAutoWidth()`:

1. **The playlist status line** (`id="PE_Info"` or `display="PE_Info"`) — always the host's line.
2. **`setAlternateText`**, while it is non-empty.
3. **`setText`**, while it is non-empty.
4. **`display=`**, else the XML `text`/`default` literal, else `alternatetext` as a placeholder.

Rule 3 is the one that is easy to get wrong, because in Winamp there is no precedence at all: a
`display=` binding *writes* the object's text when its value changes, so whatever was written last is
what shows. Resolving the binding live on every draw instead — which is what this engine does — makes
the binding win forever unless a script's write is allowed to outrank it. **B39** was that bug. Big
Bento Modern declares `display="SONGNAME"` on all 17 of its `Bento:InfoLine` objects *purely so
`ticker="1"` works*, says so in the markup (the "Victhor trick", `xml/player-normal-mcv.xml:378`), and
fills each line from `fileinfo.m`; every line drew the song title, which reads on screen as a repeated
title rather than as a broken panel.

**The revert half is not optional, and it is the commoner pattern.** A sweep of the 36 installed skins
found 13 that call `setText` on a display-bound object, and most are a transient readout laid over the
songticker — MMD3's SEEK/VOLUME/BASS/TREBLE, Styx's and Ebonite's seek and volume overlays,
BLAKK's stick — taken back down with `setText("")` a moment later.

**A non-empty override stands until the script clears it — it does not expire when the bound value
moves.** That is deliberate and the corpus decided it: micro's `oldtimer.m` overrides a
`display="time"` timer every 20 ms to draw the old Winamp `00:00` format, and Ebonite's `clock.m` puts
a wall clock over the same binding while stopped. An expiry-on-change would flicker both between two
formats. Nothing gets pinned to a stale value in exchange, because every non-reverting writer in the
corpus rewrites on the next track change (Anaheim's `metadata.m`, Nokia's `display.m`, both from
`onTitleChange`).

The override lives on `WasabiTextMetrics.scriptTextKey` — its own key, not a Wasabi attribute name —
for the same reason `scriptAlternateTextKey` does: a skin must not be able to declare an override in
markup, where `text=` keeps its own meaning as the literal an unbound object draws. `setText` writes
the XML attribute too, so anything reading it directly (a `<Wasabi:Button>` label) still follows the
script.

#### `onTextChanged` is how a skin learns a host readout moved

Winamp's `Text` raises `onTextChanged(newtext)` whenever its content changes, and skins use it as the
*only* signal that a host-supplied value is worth re-reading. A skin may put no logic in `onTimer` at
all and still update constantly.

`WinampModernScriptRuntime.refreshBoundText()` polls the objects whose content comes from the host — a
`display=` binding, a `songticker`, the playlist status line — and raises the event on the ones that
moved. The window controller drives it from its host-state hooks (track change, playback state, the
clock tick), which is exactly when a bound readout can change. Literals are deliberately excluded: a
`<text text="Add">` cannot change, and firing for one would be a lie.

The **first observation of real content fires too**. Winamp raises the event when a readout goes from
nothing to something, and a skin whose readouts are written only from this handler has no other way to
learn its opening value — seeding silently (the first thing this code did) meant a queue that was
already populated before the first poll never produced a change, so the readouts stayed blank for the
whole session. Empty content still says nothing.

**Why this matters more than it looks:** Defix's playlist box writes its `Items:` and `Time:` readouts
from a subroutine whose only caller is `onTextChanged`. Reading the disassembly carelessly makes it
look like `onTimer` work — the two handlers are adjacent, and `op25` is a **call** into the shared
block, not a jump within one handler. Undispatched, the whole readout was unreachable code.

#### The mouse wheel is a *layout* event, and it carries two arguments

`onMouseWheelUp` / `onMouseWheelDown` are how a skin scrolls anything it draws itself — a settings
page, a drawer, a custom list. Two measured facts, both easy to get wrong:

- **The arity is two, not one.** Read off two independent skins' bytecode: Big Bento Modern's
  `config_vscrollbars` (`@638`) and cPro-Bento's `centro.multidrawer` (`@1091`) both open with two
  `op3` stores. Wasabi documents them as `(clicks, lines)`; neither corpus consumer *reads* them —
  both relay them straight into `sendAction`'s `p1`/`p2` — so the names come from the API and the
  count comes from the bytecode. A wrong arity is the one error the interpreter cannot recover from.
- **The binding is on the layout, not on the control under the pointer.** All **84** `onMouseWheel*`
  bindings across the five corpus skins that declare them land on `layout#normal` or `layout#shade`.
  Each script then decides whether the turn was meant for it with `isMouseOverRect()` — which reads
  the live pointer position, so it needs a window and answers `false` headlessly. Big Bento declares
  `config_vscrollbars` **nine times**, once per settings page, so nine handlers run per notch and
  eight correctly do nothing. Dispatching to the object under the pointer reaches none of them.

`WinampModernMainView.scrollWheel` therefore handles NullPlayer's own surfaces first (the colour-theme
list, the playlist holder) and then dispatches to `renderer.layout`, treating a nonzero handler count
as consumed. Before that the wheel never reached a skin at all and Big Bento's settings pages had no
working scroll — everything below the fold was unreachable (BB19).

> **`WINAMP_MODERN_RENDER_EVENTS=onmousewheelup` measures half of this and no more.** It calls
> `dispatch` itself, so it proves the bindings exist, the arity unwinds and nothing aborts — it does
> **not** go through the view, and `isMouseOverRect` is false with no window. A nonzero count is not
> a working scrollbar.

#### `embed_xui` — the wrapper **is** the control, and must not keep a second copy of its value

A `<groupdef embed_xui="slider">` wraps a control and speaks for it. Three things follow, and Big
Bento Modern's settings scrollbar needed all three before it would scroll at all (BB19) — each was
broken on its own, and each fix looked like it had done nothing until the next one landed:

- **The range declared on the wrapper is the embedded control's range.**
  `<SC:VScrollBar low="0" high="100">` around a bare `<slider>` means that slider counts 0…100. Left
  on Winamp's 0…255 default, every number the skin read was on the wrong scale: the page computes
  `scrollToPercent(99 - position)`, and positions of 113/118/123 made that *negative on every press*.
- **`getPosition`/`setPosition` on the wrapper address the embedded control.** The skin's up/down
  buttons move the **inner** `<slider>` (`cscrollbar.maki`) while the page reads the **wrapper**
  (`vscroll.getPosition()`). Two objects with two values drift permanently — the page read `0`
  however far the bar had been dragged.
- **Value events cross the seam.** `onSetPosition`/`onSetFinalPosition`/`onPostedPosition` are
  forwarded to the embedding owner alongside the pointer set, so a script bound to either one hears
  the control move exactly once.
- **`getText`/`setText`/`getTextWidth` follow the same link** — the value in question is a string
  rather than a number, and everything above applies unchanged (B40). Big Bento Modern's file-info
  lines are the proof from the text side: `<groupdef id="bento.infodisplay.line" embed_xui="text"
  xuitag="Bento:InfoLine">` wraps a `<Text id="text">`, `fileinfo.maki` fills the **inner** text,
  and `fileinfo_lyrics_finder.maki` reads the **wrapper** with `getText()` to build its search
  string. Kept apart, the reader answered `""` and the lyrics button searched the web for the bare
  word "lyrics" — a symptom that looks like a broken browser and is nothing of the kind. Measuring
  the wrapper is just as wrong: it draws nothing itself, so `getTextWidth()` on it is the width of
  an empty string.

Two related rules that fell out of the same investigation:

- **`setPosition` clamps to the declared `low…high`.** Every scrollbar in the corpus steps its slider
  relative to itself (`setPosition(getPosition() + 5)`); unclamped, the up button walks off the end
  and never comes back. A slider that declares *neither* bound is left alone — Anaheim's brightness
  slider is `low="-4096" high="4096"` and must not be fenced into 0…255.
- **A vertical slider driving nothing of its own starts at `high`**, the top of its travel. Read as
  `0`, Big Bento's pages opened by computing `scrollToPercent(99 - 0)` — 99%, their own bottom — and
  seven of its nine settings pages launched scrolled to the end of themselves. Only a slider with no
  `action` is seeded; a seek or volume slider is told its position by the host.

#### Scrolling: `scrollToPercent` is a viewport offset, not a layout change

`scrollToPercent(p)` parks a container's contents at `p`% of their travel — `0` is the top — and the
renderer turns it into an offset applied to the children when the scene nodes are **built**, so
drawing, clipping and hit testing all follow from one place (a control scrolled halfway up the page
is clickable where it is drawn and nowhere else). Travel is whatever the children overflow the
container by, so a page whose content fits never moves however hard a skin scrolls it — one rule
serves a long settings page and a short one with no per-page configuration.

Every route a user has ends at this one call: the scrollbar's drag (`onSetPosition`), its up/down
buttons, and the wheel. While it was an accepted no-op, *nothing* scrolled by any means.

#### A layout must not be left with no way to seek

A script's `hide()` can strand the user. An invisible object is not hit-testable, so a layout that
ends an event with **no visible control carrying a positional host action** has lost that action and
cannot get it back — nothing is left to click in order to re-show anything.

`settleStrandedControls` undoes exactly that hide. Three things about its shape are load-bearing:

- **It settles, it does not veto.** A skin that swaps one control for another writes
  `a.hide(); b.show();`, and at the moment of the hide `b` is still hidden — a call-time veto would
  refuse a perfectly good swap and leave both on screen. The check runs where `onResize` already
  settles, once the outermost event unwinds, by which time `b` is up.
- **It restores through `setVisible`, not by writing the attribute.** The `onSetVisible(1)` that
  dispatches is what puts a skin's *mirrored* objects back. Big Bento mirrors `progressbar` and
  `player.seek.bg` to its seeker's visibility, so the skin's own mirror undoes itself.
- **Only positional actions** (`SEEK` today). Transport buttons are swapped constantly
  (`play.hide(); pause.show()`) and have a paired counterpart; a seek bar has none. Protecting `PLAY`
  would restore a play button every time a track started. Extend the set when a measured skin strands
  another action, not on principle.

The measured case is Big Bento Modern (BB16). `seek.maki` binds all seven handlers to
`Slider#seeker.ghost` and its `onLeftButtonUp` calls `hide()` on that same object — a duplicate
`findObject("seeker.ghost")` where **stock Winamp Modern's** version of the same script reaches for a
*readout* (`player.seekbar.pos`) that does not exist in the layout, so the call is a no-op on null
there. One press-release took the whole seek bar out and seeking stopped working until a track change.
**Defix Hi-END runs the identical script and never trips the rule**, because its `<Slider id="seeker">`
stays visible and still carries the action — which is the point: the rule keys on a property of the
*layout*, not on which skin it is.

#### An event handler is also a method, on every kind of receiver

A script may **call** one of its own event handlers instead of waiting for the event, and the corpus
does this constantly — ClassicPro's `beat.m` re-solves its geometry with `frameGroup.onResize(0, 0,
w, h)`, its `eq.m` labels the bands by calling `System.onEqFreqChanged(freqmode)`. `dispatchableEventArity`
is the table of names this is allowed for, and it is explicit because an unknown arity would
desynchronise the interpreter's stack.

The table is consulted on **three** receivers, and all three have to be wired or the idiom fails on
whichever one is missing: a GUI object, `System`, and a **dynamic** object — the runtime-created
`Timer` / `Map` / `Region` / config family. The dynamic route was the one that was missing.

`Timer.onTimer()` is the common case: *run the timer's body now, don't wait for the next tick*. Big
Bento Modern's songticker answers `sendAction("cancelinfo")` — which `seek.maki` posts on every
mouse-up and on `onSetFinalPosition` — with exactly that call, to put the song title back the instant
a seek preview ends. Unimplemented, the call threw and took the **whole** `onAction` handler with it,
so the ticker stayed stuck on `Seek: 1:13/4:05 (30%)`. The tell in the click probe is a chain ending
`… -> player-normal-group.xml.onaction!FAILED` with an `unsupportedScriptCapability` finding naming an
`on*` method — an unsupported *event name* in that list means a missing dispatch route, not a missing
feature.

`attribute.onDataChanged()` is the other common case, and the one with teeth: it is how a skin
**applies its stored settings at load**. A `cfgattrib` handler only ever fires on a *change*, so a
skin whose layout depends on an option has no other way to reach the state the option describes on a
launch where nobody touched it — Big Bento Modern's `pledit` ends `onScriptLoaded` with exactly that
call, and it drives the enlarged playlist, the album-art pane and the search box together. It was in
the method table with an arity but *not* in `dispatchableEventArity`, so it fell through to a
`return .null` and the whole settings pass was silently skipped (BB32).

**An inert handler call is not a no-op — it is a wrong value, later.** The damage here was not the
missing layout: it was that `playlist.dualwnd` therefore kept its markup seed, and the same script's
`onScriptUnloading` persists `getPosition()` into the skin's own config. One quit wrote that seed
over the skin's own 335px default, permanently, and every later enlarge honoured it. When a skin
saves a value it read back from us, a call we answered with nothing becomes a value we invented. Look
for the save side (`onScriptUnloading`, an `onDataChanged` collapse branch) before concluding an
unimplemented method is cosmetic.

#### Two handlers for one event: a repeat runs once, two *different* bodies both run

A program can declare the same (object, event) pair twice, and what to do about it depends entirely
on whether the two bodies are the same handler.

`MakiProgram.dispatchBindings` keeps every binding **except** one whose body repeats an earlier body
for the same (variable, event) pair; `bindings` keeps them all, for the harness. Bodies are compared
by shape: a body runs from its entry point to the next entry point the program declares, jump targets
are taken relative to the entry point, and **variable indices are renumbered by first appearance**,
because the compiler gives each copy of a repeated handler its own temporaries.

- **The repeat.** Defix's `MAIN_LAYOUT_1` declares `ConfBT2.onLeftClick()` **twice** — the same 125
  instructions reading the same config string, one copy through `v586` and the other through `v591`.
  Running both fired the button's whole action twice per click, and because the action is a *toggle*
  the two cancelled: the playlist window flashed open and shut on every press, and an open one
  refused to close. **The render harness could not see it** — it owns no windows, so the doubled
  toggle measured as one clean `CLICK action:` line. It was found by driving the click in the running
  app with `WINAMP_MODERN_DEBUG_CLICK` + `WINAMP_MODERN_CALL_TRACE`.
- **The two real handlers.** Big Bento's `mcvcore` declares `System.onScriptLoaded()` twice with
  bodies that have nothing in common: the first finds every object of the Multi Content View and
  decides which of the album-art and visualization panes to show, the second starts a timer. The
  earlier "keep the last binding" rule shadowed the first, so **every** object variable in that
  script stayed null, both panes stayed in the scene, and the visualization box drew black over the
  cover art (B38.4). One skin's rule had silently become the other skin's bug.

`WINAMP_MODERN_RENDER_SCRIPTS=bindings` prints `@<entry point>` and `(shadowed)` per binding, which is
how the two shapes are told apart without reading bytecode.

#### `PlEdit` — the playlist-editor API

`std.mi` declares **`PlEdit`** as a host-owned global exactly as it declares `System`, and skins call a
dozen methods on it: the queue's length and current entry, an entry's title/length/filename/metadata,
and the edits behind a playlist context menu.

**The gap was not the methods — it was which variable is `System`.** The compiler marks *every*
host-owned global with the variable record's `system` flag, and `MakiBytecodeParser` read that flag as
"this **is** the System object". So every `PlEdit.getCurrentIndex()` in the corpus arrived as a call
**on System**, and failed there as an unknown System method. That is why Defix's `getcurrentindex` gap
surfaced on interaction and not at load, and it is why implementing the methods alone would have
changed nothing. The parser now carves out the classes the runtime binds itself
(`MakiClassGUID.runtimeBound`) and `WinampModernScriptRuntime.seedHostSingletons` binds them by class;
a system-flagged global of any *other* class keeps the System object it always had, so nothing that
worked before became a null receiver.

**The API is keyed on `PlEdit`'s class GUID, not registered by name.** Half of these names belong to
other classes — `getLength` is an `animatedlayer`'s **frame count** (no arguments, an integer;
ClassicPro's `beat.m` reads it 28 times), `getTitle` a container's caption, `clear` a list's.
Registering `PlEdit`'s `getLength(track)` by name would have re-declared the animated one with the
wrong arity and desynchronised the interpreter's stack in skins that have nothing to do with
playlists.

| Method | Arity | Answers |
|---|---|---|
| `getCurrentIndex()` / `getNumTracks()` | 0 | the playing row (0-based, −1 for none) and the queue length |
| `getTitle(t)` | 1 | the entry's display title — the same string the drawn list shows |
| `getLength(t)` | 1 | **a string**, `m:ss`, and **empty** when unknown — ClassicPro tests it against `""` before bracketing it |
| `getFileName(t)` | 1 | the entry's path (or URL for a stream) |
| `getMetaData(t, field)` | 2 | `title` / `artist` / `album` / `filename` / `length`, empty otherwise |
| `playTrack(t)` / `removeTrack(t)` / `showTrack(t)` | 1 | play, remove, scroll-to |
| `moveTo(from, to)` | 2 | reorder — **two** arguments, see below |
| `showCurrentlyPlayingTrack()` / `clear()` | 0 | scroll to the playing row; empty the queue |

`System.getPlaylistIndex()` (0 args) is a *System* method, not `PlEdit`'s, and **six of the seventeen
skins** ask for it — the most demanded unimplemented method in the corpus. Winamp's own notifier shows
it as `getPlaylistIndex() + 1 + " of " + getPlaylistLength()`, which pins both the base and the
pairing. `showCurrentlyPlayingEntry()` (0 args) is the same request made of the playlist **widget**;
Itemskin and micro reach it through `findObject`, so it is a GUI method with a receiver.

**`moveTo` is why the arities are measured and not ported.** It reads like a one-argument "scroll to"
and is `moveTo(from, to)`: Defix's *Move selected to top* passes a literal `0` for the first selected
row and then a running counter, its *to bottom* passes `getNumTracks() - 1`. Count the net pushes
between the receiver and the call — the compiler emits the receiver first, then one push per argument
in **reverse**, so `arguments[0]` is the first declared argument.

**What is deliberately left out.** `PlEdit.enqueueFile(path)` (cPro-Bento) and `System.playFile(path)`
(T800) take a **filesystem path from the skin**, which is a sandbox policy question rather than an
arity one, so they stay out of `signature(for:)` and their demand keeps being recorded. `clear()` is
implemented and they are not, which would be a hazard if anything reached both — cPro-Bento's
`extendedbuttons.m` is the only caller and it early-returns on `ClassicProFile.findFiles`'s bounded
`-1` long before the `clear()`.

Drive it headlessly with `WINAMP_MODERN_RENDER_PLAYLIST` — see [harness.md](harness.md).

#### The equalizer tells the skin it moved

`onEqBandChanged(band, value)` and `onEqPreampChanged(value)` are the EQ's `onVolumeChanged`: Winamp
raises them whenever the equalizer moves, **whoever** moved it. Five of the 17 skins handle them
(multipass, mmd3, Rika, winampmodern566, Overdrive_2) and each drives its own EQ readout from nowhere
else, so before Phase 41 those readouts followed the skin's own drag and no other route.

`WinampModernScriptRuntime.refreshEqualizerState()` is the single funnel and it dispatches **only what
changed**. Everything comes through it — the skin's slider drag, `System.setEqBand`/`setEqPreamp`
(which announce themselves as `setVolume` does), the skin's preset menu, `EQ_AUTO`, every
playback-state hook, and a 1 Hz safety poll beside `refreshBoundText`. The poll is what catches the
routes nothing calls back on: a preset applied from the menu bar, the classic equalizer window's
sliders, a restored session. As with `onTextChanged`, the first observation announces rather than
seeding silently.

Two things the corpus pins down and a reimplementation must not guess:

- **The value is MAKI's −127…127**, the scale `getEqBand` answers in — Rika slices a region map at
  `128 - value` and would read off the end of the image on any other. `band` is **0-based**; the XML
  `param=` on an `EQ_BAND` control is **1-based** (`WinampModernEQAction` owns that conversion, and it
  is the reason all three of the renderer, the view and the script bridge decode through one place).
- **Some skins never read the arguments.** multipass's eleven `ledfillbar` bars re-read their
  `parentslider`'s position from the handler instead, so every `EQ_BAND`/`EQ_PREAMP` slider's 0…255
  position is synced from the host *before* the events go out. The renderer has always drawn the thumb
  from the host; this is the script's view of it catching up.

Drive it headlessly with `WINAMP_MODERN_RENDER_EQ` — see [harness.md](harness.md).

#### The keyboard is a string, and a borderless window has to ask for it

`System.onKeyDown` hands the script **one string** — Winamp's own accelerator name, `"alt+g"`,
`"ctrl+w"`, `"esc"` — not a virtual keycode. Every handler in the corpus compares it against a
**lowercase** literal, and two of the three compare without normalising first (winampmodern566's
`strKey == "alt+a"`, Defix's `strKey == "esc"`; only multipass runs it through `strLower` first), so
an `"Alt+G"` would miss all of them. `WinampModernKeyAccelerator` builds the string; macOS modifiers
map literally, in the order `ctrl+alt+shift+`, because winampmodern566 reads the prefix positionally
(`strLeft(strKey, 4) == "ctrl"`).

**Command is deliberately not folded onto `ctrl`.** ⌘W closes a window on this platform and ⌘A selects
all; letting a skin's `ctrl+w` shadow the app's own menu equivalents is a capability no skin asked for,
so a ⌘-carrying event produces no accelerator at all.

**`complete;` is the consumption signal.** MAKI's opcode 40 is not control flow — the compiler emits it
before the handler's own return — so the interpreter just counts it, and `dispatchKeyDown` reports
whether the count moved. A handler that ran and matched none of its branches never reaches one, and
the key falls through to the responder chain. Defix's `esc` handler has no `complete;` at all.

> **A borderless `NSWindow` is refused the keyboard.** `canBecomeKey` defaults to false without a
> title bar, so `NSView.keyDown` is never called however willingly the view takes first responder —
> which is the whole reason this event was unreachable, not the dispatch. `WinampModernSkinWindow`
> overrides it, exactly as `BorderlessWindow` already does for the modern-skin windows. The view then
> accepts first responder unconditionally and treats `keyDown` as a *fall-through*: the playlist's
> Delete first (still gated on a clicked row), then the skin, then `super`.

A skin that means *one* window gates its handler on `isActive()` — the event reaches every program in
the skin whatever window is focused, as in Winamp. See [compatibility/maki-surface.md](../compatibility/maki-surface.md).

Drive it with `WINAMP_MODERN_RENDER_KEY` (harness) or `WINAMP_MODERN_DEBUG_KEY` (the app) — see
[harness.md](harness.md).

### Writing back the position a window just read is not a move

`resize(getLeft(), getTop(), w, h)` is how a skin resizes a window while leaving it where it is, and
the two halves of it have to agree about the space they are in. They did not: `getLeft()`/`getTop()`
on a **layout** answer its own canvas origin — 0 — while the `x`/`y` a `resize()` writes are pushed
out to the desktop as absolute screen coordinates. A skin handing back what it just read therefore
parked its window in the top-left corner of the monitor. Big Bento Modern does exactly this from
`pledit.maki` every time the side playlist opens (B61).

**It is fixed on the write, not on the read.** `applyContainerGeometry` takes the origin the object
reported *before* the write (`reportedOrigin`) and skips `containerMoveRequested` when the new `x`/`y`
are that same pair. Only the round trip is recognised, never the value — a script that writes a
position it did not read is still a move, whatever that position is, which is what keeps Big Bento's
search-results popup landing under its search box (BB31).

**Do not "fix" this by making a layout report its desktop position instead.** It is the obvious move
and it is wrong: a layout is the space every object inside it is laid out in, and skins do arithmetic
across that boundary. multipass positions its side drawers from `layoutMainNormal.getLeft()`, and
adding the window's desktop origin there moved every drawer *and its hover region* off the artwork it
belongs to — drawers that could not be opened and fired from inches away. `newgroupaslayout` depends
on the same 0 (see its note in `WinampModernScriptRuntime`). A `<container>` is different: it has no
layout space of its own, so it does report the host's desktop origin, via `containerOriginQuery` →
`WinampModernMainWindowController.winampScreenOrigin` — the exact inverse of the point
`containerMoveRequested` accepts. The graph's `x`/`y` are only the fallback there, because they hold
the last position a *script* wrote and go stale the moment the user drags the window, `place`, the
tiler or state restoration moves it.

**The other half of the same asymmetry is the *cross-window* round trip** (B69). A skin can draw one
window's chrome in a *second* window and keep the two laid over each other:

```
chrome.resize(content.getLeft(), content.getTop(), content.getWidth(), content.getHeight())
```

Both receivers are layouts, so both read 0, and the write above was suppressed as "unmoved" — the
frame stayed wherever the tiler had parked it while the content window sat somewhere else on screen.
Recognised on the write, the same way: `borrowedWindowOrigin` remembers the origin the last window
object *reported* along with the desktop origin it actually sits at, and when that exact pair is
handed to `resize()` on a **different** window object, the point is re-expressed in the reader's
space. The record is spent by the write that uses it, so a stale read cannot pin a later write that
only happens to name the same coordinates, and a value the script did not read is still a plain move.

Such a move is **pinned**, and a pin is not clamped to the visible frame — `containerMoveRequested`
carries the flag. Clamping it is what pulled Itemskin's library frame 82px off its content window: the
tiler had already put the content window's right edge past the screen, and only the frame — the one of
the pair a script moves — was pushed back.

### `onMove()` is dispatched to the window objects only

A resize is a change *inside* the scene, so `onResize` reaches every object whose own box moved. A
move is not: nothing inside the window changed position relative to anything else, so `onMove()`
(arity 0) is addressed at the `<container>` and its active layout and at nothing else
(`dispatchWindowMove`). It fires from `WinampModernMainWindowController.windowDidMove`, so every route
that moves a `.wal` window reaches it — the user's drag, `place`, the tiler, state restoration.

It went undispatched entirely until B69. Six corpus skins bind it (Ebonite, Itemskin, Defix, both Big
Bentos, winampmodern566), and for Itemskin it is what lets the user drag a frame window at all: without
it the frame came away from its content and the frame script's 10 ms sync timer snapped it back a frame
later.

### gotoTarget animation

`setTargetX/Y/W/H/A` + `setTargetSpeed` + `gotoTarget()` animates an object toward its target
values using exponential ease-out (`factor = 1 - pow(1 - speed, dt / 0.020)`, frame-rate-independent
against Winamp's 20ms tick). Implemented in `startTargetAnimation` / `tickTargetAnimation` in
`WinampModernScriptRuntime.swift`.

**speed = 0 means instant.** Skins use `setTargetSpeed(0)` for snap-to-target (Anaheim's hover
controls: speed=0 to show, speed=0.5 to fade). The code checks `rawSpeed <= 0` at the top and snaps
immediately — copy targets to actuals, fire `ontargetreached`, no timer.

**Unset target properties stay at their current value.** When a script calls `gotoTarget` without
setting `setTargetA`, the target alpha must be the object's current alpha, not 0. `targetAttr`
defaults to `"0"` (correct for x/y/w/h) but wrong for alpha (would fade everything to invisible).
The fix: `targetAlpha` uses `object.attributes["targeta"].flatMap(Double.init) ?? ca` where `ca` is
the current alpha (defaulting to 255). The speed=0 snap path already handled this correctly with
`?? object.attributes["alpha"] ?? "255"`.

**Alpha inheritance cascades to children.** `WasabiSceneNode.inheritedAlpha` propagates through the
scene tree during `append()`. The main `draw` method sets `context.setAlpha(alphaFraction *
inheritedAlpha)` once; per-drawer methods must NOT override it with their own `setAlpha` call or the
inheritance is lost.
