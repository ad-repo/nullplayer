# `.wmz` object model: event arguments and the keyboard

Moved verbatim from `reference/object-model.md` on 2026-09-25; that file is the router. Read it first.

## Event arguments

**A `<PLAYER>` event handler is a statement written against a named argument, and the name has to be
bound or the handler dies on its first line.** Corona authors
`playstatechange="OnPlayStateChangeTransport(NewState);OnPlayStateChange();"` and
`status_onchange="OnStatusChangeTransport(status);"`; with neither name bound both threw
`ReferenceError` and everything after the first call was lost — including the line that turns its
`<WMPEFFECTS>` pane on, which is why that skin showed no visualization at all.

`WMPJScriptEvent.Handler` carries the arguments and `WMPScriptContext` binds them as globals for the
duration of that one handler, then clears them — the same shape a control's bare `value` uses, and
for the same reason: a stale `NewState` left standing would be read by an unrelated later handler
instead of failing honestly.

| Event | Argument | Value |
|---|---|---|
| `openstatechange` | `NewState` | the `os*` open state, the same number `player.openState` answers |
| `playstatechange` | `NewState` | the `ps*` play state, the same number `player.playState` answers |
| `status_onchange` | `status` | `player.status`, the same sentence `WMPHostSnapshot.statusText` answers |
| `currenteffecttype_onchange` | `currentEffectType` | the selected effect's stable id, the same string `<EFFECTS>.currentEffectType` answers |
| `currentposition_onchange` | `currentPosition` | the playback position in seconds, the same number `player.controls.currentPosition` answers |
| `currentpreset_onchange` | `currentPreset` | the selected effect preset's index, the same number `<EFFECTS>.currentPreset` answers |

**They belong to the handler and not to the transaction.** One refresh raises `openstatechange` and
`playstatechange` together and `NewState` is a *different* enumeration in each, so a single binding
for the whole transaction would be wrong for one of the two. Measured demand is small — 6 of the 180
installed archives name `NewState` in a handler attribute and 5 name `status` — and the cost of not
having it was every statement after the first in those skins.

**An ambient `<attribute>_onchange` handler reads the attribute by its own authored name**, and it
is the same binding for the same reason: 68 of the corpus's 77 `currentEffectType_onchange` uses are
`mediacenter.effectType=currentEffectType`, which without the name bound is a `ReferenceError` on
the first statement. `currentMedia` and `currentPlaylist` are deliberately **not** bound — WMP's are
objects, this engine has no JS object to stand for either, and all 77 of their corpus sources call a
skin function (`updateAlbumArt()`, `getVisMeta()`, `updateMetadata('playlist')`) rather than reading
the bare name. Binding a scalar in their place would answer a question the skin never asked.

**The whole `event` object is bound as of W121, closed 2026-09-22.** WMP binds one `event`
object per handler with the modifier and key state on it.
`value_onchange="toolTip = Math.round(value); if (!event.shiftKey) eq.gainLevel9 = value;"` is the
shape — an equaliser band that skips its write while shift is held, which is how the Skins Factory
family links its ten bands. **30 handlers across that family** were measured 2026-09-09 as
`value_onchange: ReferenceError: Can't find variable: event`; the other event kinds are unmeasured.
Surfaced by W51 rather than caused by it: those handlers had never run at all before the host-driven
direction was raised. The same gap applies to the user-driven direction and to
`onkeydown`/`onkeypress`, **whose half closed with W53 on 2026-09-22 — `event.keyCode` is bound, see
below.** Bind the rest the way the bare `value` and the
named arguments above are bound — for the duration of that one handler, then cleared. **Count the
whole class first**: sweep the corpus's handler attributes for `event.` and split by event kind,
since the modifier state a mouse handler wants and the `keyCode` a key handler wants come from
different places.

### The rest of the `event` object (W121)

**Re-measured 2026-09-22 over 184 archives** with `wmp_handler_scope_census.py`'s decoder — never
`grep` — there are **1,249 `event.` reads** a handler can reach. `keyCode` is 1,025 of them (W53),
and `shiftKey` (85 uses / 5 archives), `screenHeight` (65/6), `ctrlKey` (6/3) and `screenWidth` (3/1)
were already answered. **The row's own stated reach was the wrong idiom**: its "30 handlers across
the Skins Factory equaliser family" is `value_onchange`/`ondragend` reading `event.shiftKey`, live
since W184, so the row ranked a class that already worked. Re-measure a row whose evidence predates
a change to the same subsystem.

The residue was **65 uses across 3 archives**, and each one takes a whole control surface with it,
because a handler dies on its first unrecognised member:

| Member | Uses / archives | What it costs |
|---|---|---|
| `srcElement` | 34 / 1 | `Cablemusic`'s eighteen station buttons *and* eighteen presets share one handler each and ask which was pressed |
| `button` | 15 / 1 | `digitaldj`'s list boxes, spinners and comparison toggles are `if (event.button != 1) return;` |
| `clientX`/`clientY` | 16 / 1 | `LostPlanet`'s `menuTicker()` opens and closes its drop-down from the pointer on every tick |

**`srcElement` answers the element object**, resolved by the markup's own id and then by stable id —
the same precedence `WMPScriptContext`'s `eventOwner` uses, because an identifier is not unique
across views (W89). `.id` is only the member the corpus happens to read first.

**`button` is IE's numbering, which WMP inherits: 1 left, 2 right, 4 middle.** Every corpus
comparison is `== 1` or `!= 1`. Only the left button reaches a script event at all, because
`WMPMainView` overrides `mouseDown` and not `rightMouseDown` — so the constant is a measurement,
not a guess. It is carried on the event rather than derived from the event's *name*, so the day a
secondary button is dispatched the answer moves with it.

**`clientX`/`clientY` is set on every transaction, not only a mouse one**, because WMP's `event` is
ambient rather than per-dispatch — that is the whole reason `LostPlanet`'s timer can work. It is
read live at dispatch like `currentEventModifiers`, and for the same reason: the callbacks that
raise these transactions have no `NSEvent` of their own.

**All four answer absent rather than zero outside their transaction** — W260's rule, which `keyCode`
already applied. `null` matches no numeric case, fails `== 1`, passes `!= 1`, and the member still
*resolves*, so a handler reading it from a timer or a host event runs on instead of dying with a
`ReferenceError`.

**No headless instrument reaches any of the three skins**: two are `onMouseDown` and
`WMP_RENDER_CLICK` raises only `onClick`, and the third needs a timer tick with a live pointer.

**A test trap this row left behind, and it produced a live false pass.** Two transactions raised
against one `WMPScriptRuntime` do not re-run the handler for a second target — the reused runtime
answers the first target's result to both, so every negative case passes regardless of the
implementation. **Use a fresh runtime per case** in any test that varies the event's target.

**`WMPScriptConstants` carries the whole enumeration for the same reason.** A skin switches over all
of `WMPOpenState`, and one missing global (`osMediaWaiting`, in Corona's case) is a `ReferenceError`
that costs the handler — the W37 class rather than a gap in a table nothing reads.

---

## The keyboard: one number, and the skin before the built-in (W53)

**WMP hands a key handler a Windows virtual key code, and that is the whole contract.** It is the
opposite shape to the `.wal` one in `WinampModernKeyAccelerator`, which produces the string
`"alt+g"` because every Wasabi handler compares a string; every WMP handler compares an integer.
Measured 2026-09-22 over 184 archives, `event.keyCode` is **405 of the 409** `event.` reads in a key
handler or a function one calls (`event.shiftKey` is the other 4), and the literals it is compared
against are VK values. `WMPVirtualKeyCode` maps macOS keycodes onto them and is deliberately free of
`NSEvent` at its core, so the mapping is testable without a window.

**Reach, re-measured with the decoder rather than `grep`:** `onkeydown` **530 uses / 80 archives**,
`onkeypress` **422 / 74**, `onkeyup` **100 / 33** — authored on `VIEW` (400, the skin's hotkeys),
`CUSTOMSLIDER` (290) and `BUTTON` (209), the controls the keys steer. Reproduce with
`scripts/wmp_handler_scope_census.py`'s decoder over each `.wms` tag span; the row's recorded
501/78 was a hand count and short.

**One transaction per keystroke, carrying both events' handlers.** WMP raises `onkeydown` and
`onkeypress` for one press, and dispatching them as two transactions would cancel the first before
it ran — the hazard `onSliderRelease` documents. They share the one `event.keyCode`, and **that is
measured rather than assumed**: every letter tested in an `onkeypress` handler is tested in both
cases (`case 88: case 120:` for X, `case 90: case 122:` for Z, and the same for B, C, F, L, P, V),
72 times each, so the uppercase half is the VK and every one of them matches. `onkeyup` compares
only `13`, which is `VK_RETURN` and the carriage return alike, and `onkeydown` compares the arrows
and space, which have no character form at all. One number answers all three events; a second would
only be a second thing to get wrong.

**The skin goes first and the engine's own keyboard is the fallback.** `WMPMainView` steps a focused
slider on the arrows and activates a focused button on space and Return, and it does so because
nothing used to raise the skin's own handlers. Running both is one keypress acting twice — and worse
than twice: `Age_of_Mythology_MP7` deliberately maps right/down to *quieter* on its volume slider
where the built-in step has right/up hardcoded to *louder*, so the two pull in opposite directions.
**66 of 184 archives** author a key handler on a `SLIDER` or `CUSTOMSLIDER`, so this is the common
case. `WMPMainView.onKeyEvent` answers **synchronously, from the loaded skin's graph**, whether a
handler was authored — `keyDown` has to decide now whether to fall through — which is
`handlerOwnsAction` asked of the markup rather than of the hit target.

**The focused control or the view, never both**, for the same reason: a skin hangs its hotkeys on
the `<VIEW>` and its stepping on the control, and raising one press on both runs a global hotkey
alongside the control's own handling of it. The focused control is asked first; the view answers
what it declines.

**Tab stays the engine's, ahead of the skin.** It is the focus ring rather than a key a skin acts
on, and no corpus handler compares `VK_TAB` at all. A skin swallowing it would strand the keyboard
on whichever control happened to hold focus.

**Absent is not zero.** Outside a keystroke `event.keyCode` answers `null`, which matches no numeric
`case` and compares false against every literal in the corpus — and the member still *resolves*, so
a handler reading it from a timer or a host event runs on rather than dying with a `ReferenceError`.
`0` would be VK_NULL, a number a `switch` can match. Same rule as W260's `timerInterval`.

**A skin may write it, for its own dispatch** (W266). The Xbox skins' `resetCode()` runs
`event.keycode = 65` on every 400 ms `onTimer`, and threw every tick while the member was read-only.
`WMPObjectModel.write` stores the value in `eventKeyCode`, which every `beginTransaction` resets, so
later reads in the same handler see it and the next event does not. The other `event` members stay
read-only.

**The hole this work found, and it hid the dispatch site completely.** `WMPMainView` took first
responder on `mouseDown` and nowhere else, so a window that had never been clicked received no key
event at all and every one of the corpus's 1,052 key handlers was unreachable — the same hole `.wal`
had until Phase 43. Verifying W53 in the running app printed *nothing* until a click went in first.
`viewDidMoveToWindow` now claims the keyboard when nothing in the window holds it, so a hosted
`<EDITBOX>` or playlist surface that has been clicked into keeps it. **A dispatch site nothing can
reach measures exactly like one that does not exist** — which is this file's own rule about
recognising an event, one step further out.

---
