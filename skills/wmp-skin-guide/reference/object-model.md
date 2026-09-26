# The `.wmz` script runtime and host object model

**This file is the canonical reference for what skin JScript can reach.** `WMPObjectModel.swift` is
the executable source of truth; this explains the shape, the rules, and how to add a member without
making the demand tally lie. The probe flags that measure it are in `reference/harness.md`.

---

## The shape

One persistent `JSContext` per **skin session**, on one WMP-owned serial queue
(`WMPScriptContext`). Inside it:

- the skin's own `.js` programs, evaluated **once** at session start, in declaration order;
- every element id of the current view as a global, backed by live element state;
- `player`, `player.controls`, `player.settings`, `player.currentMedia`, `player.currentPlaylist`,
  `player.network`, `eq`, `theme`, `view`, `mediacenter`;
- WMP's own enumeration constants (`osMediaOpen`, `psPlaying`, …) as globals;
- `setTimeout` / `setInterval` / `clearTimeout` / `clearInterval`, host-executed and bounded;
- nothing else. `ActiveXObject`, `WScript`, `Enumerator`, `VBArray` and `GetObject` are explicitly
  undefined, and a bare JavaScriptCore global has no `fetch`, `require`, `XMLHttpRequest` or file
  API of its own.

`WMPScriptRuntime` is the actor around it: one transaction at a time, expressions then handlers,
returning a `WMPScriptOutput` of scene overrides, host commands, timer requests, diagnostics and the
call trace. Reads answer off an immutable `WMPHostSnapshot`; writes become typed host commands the
main actor applies. Nothing in the model touches `AudioEngine`, AppKit or the file system.

**Why it is in-process at all** — and what that costs — is Amendment 2 in
`docs/wmp-skin/phase-0-decision-record.md`. Read it before changing the boundary.

---

## The three resolutions

Every member access is recorded as one of these, and `WMP_CALL_TRACE` prints them as `ok`, `INERT`
and `UNRECOGNISED`:

| Resolution | Meaning | What happens |
|---|---|---|
| `live` | a real host value or a real effect | answers, or posts a command |
| `inert` | recognised, answered, nothing behind it | answers a documented default; **counted separately** |
| `unrecognised` | not implemented | throws, aborting *that handler only*, and is tallied as demand |

`inert` exists because of the most expensive class of phantom bug this subsystem can carry: a member
that is recognised and returns something plausible disappears from the demand tally and reads, from
every instrument, exactly like a working one. Some members cannot be anything else — `theme.loadString`
names a string inside `wmploc.dll`, which does not exist on macOS — so they answer and say so.

**The rules that follow from that:**

1. **Do not add a member you cannot implement.** If it has no host behind it, mark it `inert()`.
2. **Unimplemented is a queue, not a set.** Each member added lets the scripts run further and
   surfaces the next one. Re-measure with `WMP_CALL_TRACE=1` after every change; never work down a
   static list.
3. **Fail closed per handler, never per session.** There is no `scriptsDisabled`. A skin puts its
   whole startup in one handler, so one missing member already costs many unrelated features; a
   session-wide kill switch made that invisible instead of visible.
4. **Member lookup is case-insensitive.** WMP's objects are IDispatch and the corpus spells the same
   member both ways in one file (`player.currentMedia.getItemInfo` and
   `player.currentmedia.getiteminfo`). A case-sensitive bridge answers `undefined` for a call that
   works in WMP.

---

## Where the rest of the script runtime and host object model lives

Split out of this file by topic on 2026-09-25, sections moved verbatim. A reference to
`object-model.md` § *<section>* names a section that now lives in the file this table gives for it.

| File | Sections it holds |
|---|---|
| [`object-model/reads.md`](object-model/reads.md) | Who wins a property read — script, markup, host — and an unanswered `wmpenabled:` |
| [`object-model/elements.md`](object-model/elements.md) | `<VIDEOSETTINGS>`, `<NETWORK>`, `<EQUALIZERSETTINGS>` and the `eq` object, `<EFFECTS>`, playlist kinds |
| [`object-model/library.md`](object-model/library.md) | `playlistCollection`/`mediaCollection` (W136): how it is built and refreshed, `currentPlaylist`, panes and choosers, search, the 0.25 s budget |
| [`object-model/methods.md`](object-model/methods.md) | Methods and tweens (W194), `theme.openView`/`openViewRelative`/`closeView`, `theme.loadPreference`, `mediacenter`, `theme.openDialog` |
| [`object-model/events.md`](object-model/events.md) | Event arguments, the rest of the `event` object (W121), the keyboard (W53) |
| [`object-model/handlers.md`](object-model/handlers.md) | Unqualified names in a handler (W216/W256), a view's own `scriptFile` (W204/W257), wrong-case calls (W42), ambient `_onchange`, geometry expressions, timers, `sourceURL` (W41) |
| [`object-model/classification.md`](object-model/classification.md) | Recognising an event is not dispatching it, unclassified dispatch sites (W56), *Verified **not** gaps*, `INERT` members |

## Adding a member

1. Measure first: `WMP_CALL_TRACE=1` over the corpus, and take the top `UNRECOGNISED` row. Check
   `object-model/classification.md` § *Verified **not** gaps* before you open anything — the author-typo list there is the largest
   single false lead in the whole scan.
2. Implement it in `WMPObjectModel` — `live` if there is a host behind it, `inert()` if there is
   not, and leave it out entirely if neither is honest. **A writable `live` member stores the
   clamped write in `snapshot` as well as queuing the host command**, because host commands apply
   only after the handler returns: WMP's idiom is write, then read back in the same handler to clamp
   and redraw. `player.settings.volume` queued the command alone, so `Asimov_Radio`'s `SetVolume`
   clamped against, and lit its bars from, the value before the click (W280). `balance`, `mute`
   and `controls.currentPosition` still have that shape; no skin has been measured depending on it.
   **A WMP `long` is read as an integer**: `settings.volume` and `settings.balance` round
   `snapshot × 100`, in the object model and the `wmpprop:` registry alike — `0.2 * 100` is
   `20.000000000000004`, which `Alpine7618_v09` drew as `20.0…` clipped in its volume box (W305).
3. Add it to `WMPJScriptCompatibility.members` in the same change; that table is what the census's
   static `UNKNOWN member` tally is measured against.
4. Re-measure. The next member is now visible; the list you started from is already stale.
