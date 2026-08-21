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

`<script param="…">` carries Winamp's own macros rather than a path, so it is expanded in
`WasabiSkinInitializer`, not by the VFS: `@HAVE_LIBRARY@` → `1` (we host a library surface), anything
else passed through. Defix's global script reads `stringToInteger(getParam())` as "is there a media
library?" and drops the tab when told there is not.

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

#### Track metadata the skins actually read

Skins do not call dedicated bitrate/sample-rate APIs. `songinfo.maki` lowercases
`System.getSongInfoText()` and pulls values out around the literals `kbps`, `khz`, and the channel
words. The units must be **attached to the number** (`320kbps`, `44khz`) — a space between them and
the fields stay empty. `WinampModernHost.songInfoText` builds this; `trackDisplayTitle` supplies the
`"Artist - Title"` a song ticker shows (`trackTitle` alone drops the artist).

A skin reads that string through a `<text display="songinfo">`, so that binding must carry
`songInfoText` and not the artist/album, or its KBPS/KHZ fields stay empty however good the parse is.

A `songticker` carries no `text`/`default` attribute — its content **is** the current track, and it
scrolls by default. `ticker="bounce"` slides to the end and back; any other enabled value scrolls
continuously and is drawn twice with a gap so it never blanks between cycles. Both the TrueType and
bitmap-font paths share `tickerMotion(for:overflow:textWidth:)`.

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

#### One handler per (object, event)

`MakiProgram.dispatchBindings` keeps the **last** binding a program declares for a given
(variable, event) pair; `bindings` keeps them all, for the harness. Winamp registers a script's
handlers into a per-object event map, so a second declaration of the same pair replaces the first —
and a compiled skin can carry the duplicate. Defix's `MAIN_LAYOUT_1` declares `ConfBT2.onLeftClick()`
**twice**, byte for byte, both bodies ending in that round button's assigned target.

Running both fired the button's whole action twice per click, and because the action is a *toggle*
the two cancelled: the playlist window flashed open and shut on every press, and an open one refused
to close. **The render harness could not see it** — it owns no windows, so the doubled toggle
measured as one clean `CLICK action:` line. It was found by driving the click in the running app with
`WINAMP_MODERN_DEBUG_CLICK` + `WINAMP_MODERN_CALL_TRACE`.

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
