# The `.wmz` harness — canonical probe reference

**This file is the only place a `.wmz` probe flag or corpus command is documented.** Every other
file, comment and handoff points here and never restates a command. When you add a flag, add it
here in the same change.

Everything below runs headlessly through `swift test`. Nothing here is compiled into the app.

---

## Why the harness exists

Structural and load-time cleanliness measure almost nothing. The `.wal` subsystem paid for that
first: *a vertical-flip and a wrong crop origin survived 490+ green tests because nothing ever
rendered a frame.* `.wmz` reached 6,044 lines of engine with every real-skin test `XCTSkip`ped, so
`swift test` stayed green while 4 of 14 corpus archives were being rejected outright.

So: **you cannot rank work you cannot measure**, and a probe is not trusted about an absence until
it has been shown reporting a presence.

---

## The corpus

Installed skins live outside the repo, matching the `.wal` convention:

```
~/Library/Application Support/NullPlayer/WMPSkins/
```

`WMPSkinImporter.swift` installs there. Archives are never committed; only per-skin `.md` notes are.

**Enumeration rule.** `*.[wW][mM][zZ]`, `-type f`. A bare `*.wmz` drops an upper-case spelling and a
bare `*` picks up directories. Every script **prints the count it measured and never asserts a fixed
one** — the corpus moves, and a document quoting a frozen number goes wrong in a way that looks
right. Each row carries a sha256 so byte-identical archives under two filenames are visible as
duplicates instead of counted twice.

**The measured corpus is 179, not the 180 in `WMPSkins/`.** `scripts/wmp_corpus_exclusions.txt`
holds `Darkling.wmz`, and § *`scripts/wmp_corpus_exclusions.txt`* below says why and what qualifies.
An excluded archive is not a defect and never ranks work. **The corpus grew from 14 archives to 180
on 2026-09-07**; it reads 184 from 2026-09-18 and 185 from 2026-09-19 as new archives landed, which
is why every count on this page carries the archive number it was taken over.

**Two byte-identical archives were deleted. Five *name*-similar pairs were kept deliberately** —
`Ginger Man`/`Ginger_man`, `QuickSilver`/`QuickSilver (2)`, `Revert`/`Revert (1)`,
`Project Gotham Racing 2`/`Project Gotham Racing 2 (1)`, `The Unit`/`TheUnit` — because they are
different releases of the same skin with differing `.wms` and `.js`, and are separate test cases.

### A corpus number taken with `grep` is not a corpus number

**`grep` decides a `.wms` is binary and prints nothing, exiting 0.** About half the corpus's
definitions are cp1252 and carry a `0xA9` copyright sign in the header comment of the very first
line, which is not valid UTF-8; in a UTF-8 locale `grep` then reports *"binary file matches"* at
best and, piped or with `-h`, silently prints nothing at all. A scan built that way does not fail —
it produces a smaller number and a clean exit.

Two backlog claims were written from exactly that and both were false (2026-09-22):

- W256's row stated `anemone.wms` *"contains no `<equalizerSettings>` and not one `slider` element
  at all"*. It has `<EQUALIZERSETTINGS id="eq" enabled="true"/>` and **ten** `<SLIDER>` bands, and
  the row's whole "two different surfaces" framing rested on the absence.
- The same row's *"19 archives have no `<equalizerSettings>`"* is **99 of 184** when the bytes are
  read, and `object-model.md`'s *"14 name it something other than `eq`"* is **7**.

So: **decode the bytes, do not grep them.** `scripts/wmp_markup_census.sh` already strips each
`.wms` to ASCII first and is safe; for anything else use **`scripts/wms_grep.py <regex>`**, which
decodes every `.wms`/`.js` entry the way `WMPTextDecoder` does and ends on a denominator line (see
§ *The committed scripts*). An ad-hoc scan must otherwise read the entry out of the archive in Python
(or pass `grep -a`, which is the weaker fix — it still mis-splits UTF-16). Everything in
§ *Numbers that are void, and why* applies to anything a bare `grep` produced.

### Counting a tag across the corpus

**Check `object-model.md` § *Verified **not** gaps* before you rank anything a scan turns up.** The
author-typo class there — `scrollingAmmount`, `horizontalAlignemnt`, `donwImage`, `tootip`, `hegiht`,
`visilble` — is the largest single false lead in the whole scan, and WMP ignores an unknown attribute
too, so matching one would be less faithful rather than more.

`scripts/wmp_markup_census.sh <outdir> <tag-or-attribute ...>` is the instrument, and it is the only
one to use. It matches `<NAME[[:space:]/>]`, so `VIDEO` does not catch `<VIDEOSETTINGS>`, and it
strips each `.wms` to ASCII first for the two traps in its own header comment (grep goes silent on a
UTF-16 file; a tag is spread over many lines).

**Do not write your own scanner for this, and distrust any number that came from one.** The surface
inventory in `SKILL.md` was first measured by an ad-hoc Python scan trying `utf-8-sig`, then
`utf-16`, then `cp1252` — and **`bytes.decode('utf-16')` does not fail on Windows-1252 text**. Any
even-length cp1252 `.wms` decodes to silent garbage, so the tag is simply absent from the result:
`activate.wmz` reported zero `<EFFECTS>` elements and has one, and the corpus totals came out
**151 / 138 skins where the census says 183 / 166**. Every count was low, none was obviously wrong,
and the error was invisible until two instruments were compared. If a scan of your own is genuinely
unavoidable, decode the way `WMPTextDecoder` does — BOM first, then a **positional** BOM-less UTF-16
sniff, then Windows-1252 — and reconcile it against the census before recording a number anywhere.

**Grepping the corpus's *script text* is a different job, and the same decode trap ends it.**
Neither census reads `.wms`/`.js` as program text, so a question like "is this name ever read as a
property rather than called as a method" needs its own scan — that is the check that made W128 safe
to land. Extract with Python's `zipfile` (it refuses `Need_for_Speed_Underground.wmz` and
`SplinterCellWMPSkin.wmz`, whose local headers `WMPArchiveHeaderRepair` exists to fix, so **177 of
180**, and every count is a floor), then decode each file the way `WMPTextDecoder` does before
matching anything. The W128 scan was run twice because the first pass decoded as
`utf-8, errors="replace"`: **153 of the 392 script files are UTF-16**, they became null-interleaved
mojibake, no pattern matched in any of them, and the result — 141 uses — looked entirely plausible
beside the correct 376. The mix, for calibration: 153 UTF-16-with-BOM, 143 cp1252, 87 UTF-8, 9
UTF-8-with-BOM. **A scan of script text that did not print its own encoding breakdown has not earned
its number.**

**Three counts landed with W163–W166 came from scans of that shape**, and each states its own
denominator because none of them is a tag the census can match:

| Count | What it enumerates |
|---|---|
| **7 archives, 0 `scriptFile`** | archives shipping a `.js` that no `scriptFile` names — the shell form, and the two ways it fails silently (`LC_ALL=C`, and stripping NULs), are in `reference/loading.md` § *The script a skin never names* |
| **1 archive, 3 attributes** | `wmpprop:` bound to a colour, matching `([A-Za-z]+[Cc]olor)\s*=\s*"\s*wmpprop:` over every `.wms` — `Colorchooser` and nothing else |
| **17 views, 4 mismatched** | views declaring a literal `width`/`height` **and** a resolvable background image, with the BMP/PNG header read for its real size — the 4 are `Colorchooser`, `Cubist`, `Radio`, `Tomb Raider 2` |
| **7 archives, 58 assignments** | `\.\s*zIndex\s*=` over `.wms` **and** `.js` together, because the write is as often in an inline handler as in a program |
| **58 uses, 42 archives** | `player.network.downloadProgress` and the rest of the `<NETWORK>` member surface (W104), matching `\bnetwork\s*\.\s*([A-Za-z_]\w*)` over `.wms` **and** `.js` — the census matches a *tag* and cannot see a member read. **Split the total by resolution path before ranking it**: 55 of the 58 are `wmpprop:` bindings the registry already resolved and only 3 script reads, in one archive, reached the object model. A member count that is not split reads as 42 broken archives when it is one. Encoding breakdown 2026-09-21 over 184 archives / 400 files: 156 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM |
| **970 uses, 135 archives** | `<attr>=""` — an attribute authored with an **empty value** (W241). The census matches a *name*, never a value, so this needed its own scan, and the scan needs the tag grammar rather than a flat grep: `x = ""` inside a `<SCRIPT>` body is a script assignment and not authored markup. Count attributes **inside a tag span** only, skip script bodies, and print the encoding breakdown (2026-09-20: 81 UTF-16-BOM / 75 cp1252 / 19 UTF-8 / 9 UTF-8-BOM over the 182 measured). Reconciles with the census's `flat/*.txt` to the exact total, which is the check worth repeating — the flat files keep attribute values, so grepping them is the cheap second opinion the rule above asks for |

The last is the one to copy the shape of: a property a skin writes from script is not findable by
scanning markup alone, and scanning only `.js` would have missed `Colorchooser`, whose whole
`openstatechange` handler is inline.

**Views are the one thing the census does not count**, so the per-view numbers in `reference/windows.md`
§ *Ask what the skin provides* (595 views across 179 archives; which surface lives in which view;
`openView` targets by name) came from splitting each `.wms` on `<VIEW` with that decoder. Re-derive
them the same way and state the denominator, exactly as every other count on this page does.

---

## The probe flags

Unless explicitly labeled app-only, these flags are read by
`WMPRenderDumpTests/testSweepsSkinOrCorpus` (`Tests/NullPlayerAppTests/WMPRenderDumpTests.swift`).
Live-app flags such as `WMP_BORDER_TRACE` and `WMP_CAPTION_TRACE` require the DEBUG app and emit
through `NSLog`; setting them on the test probe does not exercise their instrumentation.

| Flag | Value | What it prints |
|---|---|---|
| `WMP_SKIN` | file **or directory** | the archive(s) to measure — required |
| `WMP_RENDER_DUMP` | directory | one PNG per view; per-skin subdirectory in a sweep |
| `WMP_RENDER_PROBE` | `all` or a view id | `PROBE` — every drawn node's type, id, resolved frame, clip, z, paint and authored attributes; plus a `WIDGET` line per widget — the AppKit-hosted surfaces the scene image does **not** contain. Two fields appear on a `WIDGET` line only when they are not the default, and both are about whether the surface is hosted at all and in what shape: `alpha=` is the container's inherited `alphaBlend` (`alpha=0` is a pane the skin has faded shut — `WMPMainView` hosts no view for it, and without the field such a widget read identically to a live one), and `mask=` names the container artwork a windowless `<EFFECTS>` is clipped to, with its frame and keyed colours. **`shape=` is the other confinement and `offshape=` is the number that ranks it (W198)**: the window's own silhouette — the nearest container's `clippingColor` region, `WMPSceneBuilder.groundShape` — and how many pixels of this widget's visible rect it cuts away. A skin that confines its visualizer by *paint* rather than by shape states no `mask=` at all and every other field on the line reads clean while the surface hangs outside the skin, which is exactly Cerulean's 104 px. `WMP_RENDER_APPKIT`'s `outside=` cannot see this class — the leak is inside the widget's own frame — so `offshape=` is the only field that reports it. It measures what the skin *authored*, not what the engine does with it, so it stays non-zero after the fix: `offshape>0` is a rect to check, not a defect. Confirm which by asking whether the rendered scene is transparent there (it was for 5 of the 6; `pharaoh` is the sixth and is in the W198 row) `WMP_RENDER_APPKIT` installs the same mask provider the controller does, so its `outside=` reading covers the masked surface rather than an unclipped rect |
| `WMP_RENDER_BITMAPS` | `1` | `BITMAPS` — resolved count and every path that failed to load, with `missing=` |
| `WMP_RENDER_OCCLUDED` | `1` | `OCCLUDED` — every control the pointer cannot reach **anywhere in its own frame**, plus a per-view tally. A target is unreachable when no sample of its rect hit-tests back to it: something in front answers everywhere, so the control draws, hovers nothing and clicks nothing. Each line names what answered instead (`by=[…]`) and which rule reached it — `covered-only` is a control the current rule recovered, `rect-only` is one it **lost**, `neither` is dead under both. **`rect-only` is the column that ranks work**: it is the flat-`zIndex`, whole-rectangle hit testing this engine did before W148, and a change that populates it is taking controls away. Sampling is a 17x17 grid over the frame plus, for a `<BUTTONELEMENT>`, the first pixel its mapping colour owns — a mapping child holds an arbitrary region and a grid alone misses a thin one. No headless probe saw this class before it existed: a starved view is `starved.tsv`'s subject, and a *fully laid out* view whose controls are buried is invisible to every count in `RENDER-DUMP`. **What this probe cannot see is a control with no hit entry at all** (W152): it enumerates targets that *have* one and asks who answers instead, so a group whose mapping regions never reached the hit map reads as a clean view here — `digitaldj/DigitalDJ` reports `unreachable-either-way=4 of 92 hits` while its entire transport strip misses every click. Pair it with `WMP_RENDER_CLICK` on a control you decoded yourself before believing a clean line |
| `WMP_RENDER_UNRESOLVED` | `1` | `UNRESOLVED` — one line per node the scene could not place: authored tag, id, and **which dimension** was missing (`width`, `height` or `width+height`). `RENDER-DUMP`'s `unresolved` count is the numerator `starved.tsv` ranks on and it names nothing, so every use of it had been followed by opening the `.wms` and guessing. It is what separated the three populations that count conflates — a `<TEXT>` sized by its own glyphs, a `<BUTTONGROUP>` sized by its mapping image, and a `<PLAYELEMENT>` that is a colour region and was never a box — and each was a rule rather than a skin. **Extended 2026-09-19 for W231 with `parent=`, `geom=`, `bg=` and `kids=`**, because the count is flat and could not say whether 180 unresolved `<SUBVIEW>` nodes were 180 failures or a few containers dragging their subtrees in: `parent=<tag>#<id>@<sid>:resolved|unresolved` says whether the node was already accounted for upstream, `kids=<n>/<m> unresolved <tag>x<n>,…` says how much of the tally below it is this node's doing, `geom=` lists every placement attribute it actually authored (or `none`), and `bg=` names the bitmap — which is load-bearing rather than decoration, because WMP's ambient size default is zero *or the size of the image*, so a node with a bitmap had a size available to it and one without never did |
| `WMP_RENDER_LIMITS` | `1` | `LIMITS` — one line per view answering *will this window come apart if it is dragged or resized?* from the scene alone, with no window and no gesture. `canvas=` the size the scene is built at, `floor=`/`ceiling=` the limits the app gives a window showing it (`WMPWindowSizeLimits.forScene`, **the same derivation the controller applies** — not a second copy, which is how a probe comes to disagree with the app), `resizable=`, and `verdict=ok\|below-floor\|above-ceiling`. **A window forced to a size its scene is not comes apart in a specific way**: the artwork is rasterized at the *scene's* size while the hosted surfaces and `WMPMainView.skinPoint(from:sceneSize:)` — where every click is resolved — come from `bounds / canvasSize`, so the visualization stretches, the skin stays put, and every control moves out from under the pointer. `circle` reported that as two unrelated complaints (W213). **Read `exposed=` and not `verdict=`.** Both sides of the verdict come from the same scene, so it can only say `ok` while the app takes its floor from the scene — a green column there is the invariant holding, not evidence that anything was checked. `exposed=yes` is the independent number: the view is smaller than the *unskinned* player's 440x170 in at least one axis, which is the constant that used to be every skin window's `minSize`. **483 of the corpus's 630 views** (343 fixed / 287 resizable), so a constant floor leaking back in does not break one skin, it breaks three quarters of them. What this cannot see is the disagreement itself, which lives in the window layer: that is `WMP_SIZE_TRACE`'s `MISMATCH` line |
| `WMP_RENDER_SCRIPTS` | `1` | `SCRIPTS`/`SCRIPT` — per program: bytes, declared handlers, and the runtime's availability |
| `WMP_RENDER_EXPR` | `1` | `EXPR` — every `JScript:` geometry expression, its source, both evaluators' values, its dependency order and deps |
| `WMP_CALL_TRACE` | `1` | `CALL`/`CALLS` — every host object-model access with receiver, member, value, and how it resolved: `ok`, `INERT` or `UNRECOGNISED`. **Harness-only: it is read by `WMPRenderDumpTests` and prints nothing in the running app.** Exporting it beside `kill_build_run.sh` produces a silent, empty capture that reads as "no member accesses" — `diagnostics-that-fail-silently`, and it cost a launch on W252. For a live object-model question the app-side instruments are the `*_TRACE` rows below |
| `WMP_RENDER_CLICK` | `<view>@x,y[;x,y…]`, any entry may be a `>`-joined path | `CLICK` — the object hit, handler count, every attribute changed anywhere in the graph, the host command reached, **`viewSize=<W>x<H>` when the handler resized its own window**, and the state after. The size line is not a host command and had to be printed separately: **a `.wmz` compact mode is a script resizing its own window** (W113), carried on `WMPScriptOutput.viewSize`, so before it existed a click that shrank the player printed no command at all and read exactly like an inert one — `Cablemusic`'s Shrink, `Goo`'s and `iconic`'s small-skin toggles and `Melvin`'s all resolve through it and none of them through `command=`. **An entry written `x,y>x,y>x,y` is a drag**: press at the first point, move through the rest, release at the last, with the pointer captured on the object the press landed on. `DRAG` reports the control's direction, range and border, the value and drawn thumb frame at every step, and then the two claims the flag exists to settle — `follows-pointer=yes\|no\|flat` and `thumb-travel=<px>`. `flat` is the one to read for: a value that never moves is trivially monotonic, and a `yes/no` answer alone would call it a pass. **It rebuilds the same `viewID` and never follows a view switch**, so `command=setCurrentView` here proves the switch was requested and nothing about what the user would be looking at afterwards — see § *A live pass is a window frame* | **A `MISS` names why, one `refused=` line per candidate under the pointer** (W152): `refused=<node>#<id> kind=<kind> <reason>`, where the reason is the first rule `WMPHitTester` applied — `disabled`, `clipped`, `not-drawn-here` (artwork coverage), `unmapped-pixel`, `mapped-to-unregistered#<id>`, or `child-disabled#<id>`. It exists because the two instruments either side of a `MISS` are both silent about it: `WMP_RENDER_OCCLUDED` enumerates targets that *have* a hit entry and asks who answers instead, and a bare `MISS` says nothing about a control that reached the hit map and then declined. Both read as "the engine lost this control" and neither is necessarily that — `digitaldj/DigitalDJ`'s whole transport strip misses every click because the skin's own `loadDJ()` disables it until the user picks an access level on its splash, which is one `refused=… disabled` line and was two rounds of theorising about the hit map before it. A point with no candidates prints nothing, which is the honest answer. **It raises `onClick` and only `onClick`**, so a control whose whole behaviour hangs off `onMouseDown` reads as `handlers=0` — indistinguishable from an inert one. Every resize grip in the corpus is that shape (W193: 235 `view.size(corner)` calls, all of them `onMouseDown`), so the grip could not be measured headlessly at all and the row was closed against the running app instead. Read a `handlers=0` line against the node's own attributes before believing it. **It raises the authored handler and never applies `WMPHitTarget.action`, which the app does too** (W243): a `<NEXTELEMENT onClick="player.controls.next()">` prints one `command=next` here while `WMPMainView.mouseUp` sent two, and one click on `ALXMorph`'s Next advanced two tracks. A `CLICK` line is what the *script* asked for, so for any element whose kind carries a transport action read `action=` beside `command=` and treat naming the same thing twice as a doubled press — the app is the only instrument that ever saw it
| `WMP_RENDER_HOVER` | `<view>@x,y[;x,y…]` | `HOVER` — walk the pointer through the points in order and raise the edges each move crosses: an `onMouseOut` on the node left, then an `onMouseOver` on the node entered, through `WMPMainWindowController.handlers(in:event:…)`, the same call the app dispatches through. A move that stays inside the same node prints `inside=… — no edge` and raises nothing, which is the claim worth falsifying: a hover fired per mouse-moved event would be a script transaction per pixel. Separate from `WMP_RENDER_CLICK`'s `>` drag form on purpose — a drag holds a capture and asks what the *value* did, a hover holds nothing and asks which handlers the crossing raised (W54) |
| `WMP_RENDER_APPKIT` | `1` | `APPKIT` — host the scene in the **real `NSView` stack** and report what the AppKit layer adds over the artwork. `outside=` is the number that ranks: an overlay drawing inside its own widget frame is the hosting working, and one drawing anywhere else is the W43 class. `blit=`/`blit-max-delta=` is a second, separate comparison of the renderer's own image against the view's blit of it. Set `WMP_RENDER_APPKIT_DUMP=<dir>` alongside it to write both bitmaps as `<view>-scene.png` and `<view>-hosted.png` when isolating one view. **A scene with an `<EFFECTS>` is two rasters**, `WMPScene.effectsLayers` (W139, per surface since W302), and this probe presents both: the baseline pass hides only `WMPMainView.hostedWidgetViews`, never the artwork overlay, because artwork a skin draws *above* its visualizer is the skin's picture and not something AppKit added over it. `blit=` compares the view against the two layers flattened back together, and a split scene with partially transparent artwork above the effects node reads a small non-zero there — the intermediate premultiplied buffer quantizes, measured at 0.11% of pixels and max-delta 16 on `Plus! Professional/mainView`. Read the shape, as the line has always said |
| `WMP_RENDER_SETTLE` | seconds | run the **view's own timer loop** for that long before measuring — at the period the skin asks for, honouring every `setViewTimerInterval` its handlers post back, rebuilding the scene between ticks |
| `WMP_RENDER_CLOCK` | `<s>[;<s>…]` | seconds into an animation to draw, one PNG per value (suffixed `@t<s>`; a zero clock keeps the original filename). **A render dump is a still, so this flag is the only way an animation is falsifiable** — frame zero is indistinguishable from an engine that never animates. Two pinned values, diffed, are the proof. `ANIMATION <view>: shortestDelay=… bounds=…` reports what the scene actually animates |
| `WMP_RENDER_HOST` | `playing`, or a `key=value` list | seed a **playing** host for the whole run instead of the default stopped one, and print `HOST` per skin saying what was seeded. Everything else in the harness measures a stopped player with an empty playlist, which is the one state a `.wmz`'s transport readouts never show a user: the elapsed readout of **108 archives** is `<TEXT value="wmpprop:player.controls.currentPositionString">` and **89** hang a seek slider off `player.controls.currentPosition` with `max="wmpprop:player.currentMedia.duration"`, and against the default snapshot every one of those resolves to `0:00` on a zero-length track — indistinguishable from an engine that never answers the path at all. Defaults are a track 1:03 into 3:33, one of three in the playlist, half volume, centred, with a title/artist/album; `WMP_RENDER_HOST='t=42,dur=137,state=paused,vol=0.8,title=X'` overrides any field (`state`, `t`/`time`/`position`, `dur`, `vol`, `bal`, `mute`, `shuffle`, `repeat`, `buffering`, `bitrate`, `title`, `artist`, `album`, `tracks`, `index`, `eq`, and **`video=<W>x<H>`**, the decoder's source dimensions). **`video=` is the one field with no resting value at all**: with it unset `snapshot.video` has no picture, every `<VIDEO>` is dark and every script that sizes itself off `player.currentMedia.imageSourceWidth` computes against zero — so a whole family of defects is invisible without it. `WMP_RENDER_HOST='playing,video=2560x1440'` beside `WMP_RENDER_LIMITS=1` is the run that found the display-ceiling defect: 83 views across 80 archives sizing their window to ~2600x1600, against zero views over 1440x810 in the same run without `video=`. Pick dimensions a user would really have — a phone clip, a 1080p rip, a 4K one — because what these scripts multiply is exactly that number. **Read the `HOST` line before reading anything else in such a capture** — a seeded run misread as a default-state one is wrong about every readout in it |
| `WMP_RENDER_SIZE` | `<W>x<H>` | `RESIZE` — lay the view out at its **own** size first, run `onLoad` there, then resize to this and re-drive `onResize`, which is the order a user produces. An expression-driven layout is a *different* layout, not the same one scaled. The transaction runs whether or not the view declares an `onResize`, because an expression re-reads `view.width` either way; `handlers=` is how many the changed-object set actually raised, and `handlers=0` with a skin you know authors one means nothing moved |
| `WMP_CLICK_TRACE` | `1` | `[wmp/click]`, `[wmp/dispatch]` and `[wmp/pref]` — read by **the app**, a DEBUG build. The live answer to *"I clicked it and nothing happened"*, which no headless probe gives: `WMP_RENDER_CLICK` raises `onClick` against the scene it just built and therefore always agrees with the markup. Four lines per gesture — the press (`raw=<kind>#<id> state=<visual> interactive=yes\|NO`), the release (`over=`, `captured=`, `dragging=`), the handler lookup (`<event> targetID= stable= view= handlers=N <sources>`) and the transaction's preference writes. **`interactive=NO` beside a live `raw=` is the silent case worth the flag**: `WMPMainView.interactiveTarget` drops a *disabled* target and `mouseDown` then returns, so a greyed control still hovers and still shows its tooltip while the click goes nowhere. **`raw=` naming a node other than the control under the pointer is the other one** — that is how W149's occluding `<BUTTONGROUP>` was caught live on `Plus! SlimLine`, `raw=buttonGroup#120` where `btnProgress` was drawn. Pair it with `WMP_RENDER_OCCLUDED=1`, which ranks the same class headlessly. **It carries the keyboard too (W53)**: `[wmp/key] <event> mac=<macOS keycode> vk=<virtual key> focused=<id> wired=1` for every key the view sees, and `[wmp/key] offer <event> keyCode= targetID= stable= authored=0\|1` for each element it is offered to — the focused control first, then `targetID=view`. **Both lines print before any decision is taken**, deliberately: an earlier revision traced only the dispatched case, and a keystroke that never reached the view was indistinguishable from one no skin had authored a handler for. `authored=1` is the skin consuming the key; nothing after it means the built-in arrow stepping correctly stood aside. **A library refill prints its own line** (W274): `[wmp/dispatch] cdrommediachange view=<id> playlists=<n> handlers=<n>` when a changed playlist list raises a chooser skin's refill, because that dispatch does not go through `dispatchScriptEvent`; `playlists=` is the catalog the refill is about to read, so a `0` there is a server that has not listed its playlists yet, not a skin that failed to fill |
| `WMP_SCRIPT_TRACE` | `1` | `[wmp/script] <code>: <message>` — read by **the app**, a DEBUG build. Every `WMPJScriptDiagnostic` the running app produces, which the headless probes print as `SCRIPT-DIAG` and the app printed **nowhere**: `recordScriptDiagnostics` stored the text in `lastLoadDiagnostic` for the debug window and nothing else, so a handler throwing in the running app was indistinguishable from one that ran and did nothing. It is how `Plus! SlimLine`'s `onTimer="OnTimerTick();"` was found to name a function the archive declares in no file, throwing roughly three times a second for the life of the session — a `sample` of the app shows that time going into JavaScriptCore's `reportAPIException` → `dladdr`. **A quiet log is a real answer here**, unlike the removed `INPUT` trace: it prints per diagnostic, not per present |
| `WMP_RESIZE_TRACE` | `1` | `[wmp/resize]` — read by **the app**, a DEBUG build, through `stderr`. The skin's own resize bracket, which no other instrument can see: `WMP_RENDER_CLICK` raises `onClick` and every grip in the corpus is `onMouseDown`, and a capture agrees with the skin either way because the builder takes its canvas from the overrides. One `beginScriptResize`/`release script=`/`resumeAfterScriptResize`/`resume … N writes` line per grip drag, a `hold N of M at <canvas>` naming the mutations held past `view.size(corner)` (W225), and a `freeze <node> left=… width=… as <alignment> at <canvas>` per script-assigned alignment. **The pair to read is `release script=true` followed by a `resume`**: a release with no resume is a bracket stranded half-applied, which is a body that stops following the window while its drawers keep tracking the corner. `beginScriptResize REFUSED` names which of the three gates declined. `edge-band press` is the window-edge drag — an affordance this engine adds that WMP has no equivalent of — and the bracket now runs on it too (W227): read it followed by `beginScriptResize ADOPTED`, then `release script=true band=true`, then the `resume`. **Until W227 this line was a lie about the path it names**: a `.wmz` window is `[.borderless, .resizable]`, and `.resizable` alone was enough for AppKit to claim a press near the frame edge in `NSWindow.sendEvent` and run its own resize loop, so for a real drag `WMPMainView` was sent no `mouseDown` at all and printed nothing. A *click* on the same pixel did reach the view, so the line printed only for gestures that resized nothing, and the band read as live for two phases while it had never once run. `WMPSkinWindow.sendEvent` takes the press first now. The general lesson is worth more than the fix: **a trace that only ever fires on the degenerate case looks identical to a trace on a working path** — drive the real gesture and check the instrument printed, per `diagnostics-that-fail-silently` |
| `WMP_BORDER_TRACE` | `1` | `[wmp/border]` — read by **the app**, a DEBUG build, through `NSLog`. One `run` line per pass (`donorBorder=` the four borders this skin adds around a hosted window's interior, `windows=` how many are open) and one line per window (`interior=` the borderless size it is keeping, `border=` top/left/bottom/right, `target=` the size it is being grown to). **This is the instrument that separates the four ways W207 can fail** — the border was never learned, the window was never grown, the resize was misread, or the frame was never rendered at the grown size — and each of the first three has actually happened: empty output meant `apply()` had run once before any hosted window existed; `interior=148x0` meant the interior was being read back against the *donor's* border instead of the one the window is wearing, making every window a fixed point of its own rule; and an analyser that came back `387x219` where its siblings came back `321x145` was the docking pass settling a window one point off our own `setFrame` and that being read as the user's resize. None of the three is visible in a screenshot and none is visible in `HOSTED-FRAME`, which measures a frame for a size it is *given*. **It also carries the W250 hold**: `hold <window> size=<W>x<H> budgetMs=` is a window kept off screen because the skin has no answer for its size yet, and `reveal <window> reason=frame|budget|closed|gone waitedMs=` closes it. `reason=frame` is the skin answering and is the only healthy outcome; `reason=budget` is the backstop firing, which means the user saw the flash anyway — **a run with any `budget` reveal in it is the fix failing, not working**, and the number to read next is the `built`/`prewarmed` timings that ran past it. |
| `WMP_VIDEO_TRACE` | `1` | `VIDEOEDGE` — read by **the app**, a DEBUG build, through `stderr`. One line per host refresh that changes the play state, the open state or the decoder's picture size: `state=`, `openState=`, `imageSource=<W>x<H>`, `latched=` (the `videoEvent` snapshot that survives a vout rebuild) and the `events=` actually raised. **It is the only instrument that reaches the media-open sequence at all** — a sweep seeds one host snapshot and never transitions, so no headless probe sees these edges, and `WMP_CALL_TRACE` above is harness-only. W252 is what it is for: with a real film it printed `state=stopped->transitioning openState=0->13 imageSource=0x0 events=[…, "openstatechange"]` followed by `state=transitioning->playing openState=13->13 imageSource=2560x1440 events=["videostart", "playstatechange"]`, which is the whole defect in two lines — the single `openstatechange` a video raised landed before VLC had reported a size, and the size arriving raised nothing. **Read `openState=` against `imageSource=`, and the pair that matters is a `12->13` edge carrying a non-zero size**; a `13->13` beside a size that just became non-zero is the regression. Needs a genuine film (`scripts/testdata.sh path video-short`, or anything opened from the browser's MOVIES tab — video never goes through `NULLPLAYER_PLAY`; see `app-control`) |
| `WMP_TWEEN_TRACE` | `1` | `[wmp/tween]` — read by **the engine** (`WMPObjectModel.tweenGroup`, `WMPScriptRuntime.transact`) and **the app** (both load sites), through `stderr`, in every build. **The decision, at the point it is made, because a tween has no settled-state signature at all**: with a clock it arrives over the duration and without one it arrives at once, and *both land on the same pixels*, so a render dump, a sweep `compare` and any capture taken after it settles are blind to the difference. Three line kinds — `call <element> duration= clock= animates= channels=[…] resolved=<n>` per `moveTo`/`resizeTo`/`alphaBlendTo`, `drop <element>.<property> … reason=<no-current-value\|already-there>` for a channel that falls back to the instant path, and `transact view= event= clock= frame= registered= live=` per transaction that touches a tween. **`clock=` is the whole instrument**: it is the caller's `animatesTweens:` promise, and `clock=false` on a window path is the W253 defect. It is what caught that row's first attempt being wired to the wrong transaction — `WMPMainWindowController` has **two** load sites, ~404 (the skin-load walk, which opens the player) and ~1348 (`theme.openView`, the skin's extra windows), and fixing only the second compiled, passed its tests, and changed nothing on screen while the captures stayed byte-identical. Count `frame=true` lines to see the loop actually ran |
| `WMP_VIEW_SCRIPT_SCOPE` | `0` | Restore the pre-W257 script binding, where the program evaluated last wins every call in **every** view rather than each view running the functions its own `scriptFile` names. Read by the engine (`WMPScriptContext`), so it works in the app, in `swift test` and in a sweep alike — which makes it the A/B for an engine-wide scope change in one binary. It reaches **6 of 184 archives** and nothing else can tell: a settled sweep across it moves one image (`holiday_skin/Globe`), because the difference is in `onLoad` and in handlers a driven app runs. `=0` also fails `WMPScriptRuntimeTests.testAViewRunsTheFunctionsItsOwnScriptFileDefines`, which is the cheapest proof the switch is wired to the rule it names. |
| `WMP_LOAD_TWEENS` | `0` | Put the `load` transaction back on the instant path — the pre-W253 behaviour, where a tween authored in `onLoad` lands its endpoint in one frame. **An A/B in one binary rather than a baseline build**: on `Revert (1)` (`onLoad="vwPlayer_OnLoad();alphaBlendTo(40,9000);"`) `=1` gives 218 tween frames and nine distinct 1 Hz captures before settling, `=0` gives 2 trace lines and the settled hash from the first capture. The settled state is identical either way, which is the invariant to check when using it |
| `WMP_FRAME_TRACE` | `1` | `[wmp/frame]` — read by **the app**, a DEBUG build, through `NSLog`. The **interval before a frame exists**, which no headless probe can see: a `HOSTED-FRAME` line is written once the artwork is in hand and this whole class of defect is the time before it is. `miss <W>x<H> standin=relaid|none|unrelayable|refused` is a hosted window drawing *without* its own frame — **since 2026-09-23 the healthy answer is `standin=relaid from=<W>x<H>`**, the nearest render of the current skin re-laid out (`WMPHostedFrameRelayout`); `none` and `unrelayable` cost the user palette chrome. A relaid size is memoised, so it traces once per size, not once per draw. With `WMP_FRAME_LIVE_RESIZE=0` the old vocabulary comes back — `scaled`, and `out-of-scale` for the 15% refusal that was the drag flicker; `outgoing` no longer exists. `built <W>x<H> ok= ms=` closes a miss with the round trip, suffixed `drag` (the one-at-a-time drag build) or `staged` (a skin switch's pre-render). `live-resize begin|end depth= at=` brackets a drag; `stage begin auto=`, `stage targets=`, `stage ready|budget ms=` and `commit reason=ready|budget ms= targets= unanswered=` trace a staged skin switch, and **`reason=budget` is the switch failing**. `insets ok= primed= ms=` is the per-skin resolution at load, and `demand <W>x<H>` (W250) is a build asked for because a window is *opening* at that size rather than because it drew there — pair it with the `hold` line in `WMP_BORDER_TRACE` that issued it. **Read the `standin=` tally before the timings**: 250 misses answered `scaled` and 250 answered `none` take the same wall time and look nothing alike on screen. This is the instrument W230 was closed on, and it contradicted the row it closed — the report estimated ~0.5 s and the measurement on `Ice` was **881 ms across four renders** (273/391/424/492 ms), because `HostedWindowBorderLayout` grows the window and every new size is another full donor rebuild. Pair it with `WMP_BORDER_TRACE`, which names the growth that asked for each of those sizes; neither is legible alone. |
| `WMP_FRAME_APPEARANCE` | `0` | Draw the borrowed frame from markup alone — the pre-W145 behaviour, where a skin that picks its frame colour in the donor view's `onLoad` lends its *opening* colour forever. **The A/B switch for W145**, read by the app (`WMPHostedFrameProvider.followsScriptedAppearance`). With `WMP_FRAME_TRACE=1` the change prints `appearance view=<donor> properties=<n> moved=<bool>` at skin load and after every preference write; `properties=0` on every line means the donor's `onLoad` touches no frame artwork and the frame is what markup draws. |
| `WMP_STRIP_TRACE` | `1` | `[wmp/strip] <path> frames= vertical= gradient=<horizontal>\|<positive> anchor=+<forwards>/-<backwards> lit=<yes\|no> descending=<yes\|no>` — one line per filmstrip direction decision, DEBUG builds, headless or app (W307). `lit=` is the brightness/travel reading and `descending=` the answer; they differ only where the middle-frame reading (`anchor=`, three unanimous lines) took a reversal away. A corpus census is `WMP_SKIN=<corpus> WMP_STRIP_TRACE=1` over the render test, tagging lines with the preceding `SKIN` line; a strip whose directional change is not also a `lit=yes` reversal would mean the rule started adding reversals, which it must not |
| `WMP_HOSTED_FRAME_DUMP` (app) | `<dir>` | The **same flag the probe reads, read by the app too** — a DEBUG build writes every frame it caches as `<W>x<H>-frame.png` in that directory, plus a `[wmp/frame] dump <W>x<H> content= over=` line through `NSLog`. The probe's dump answers for a size you *chose*; this one answers for the sizes the running app actually asked for, which is the only way to read a frame against the window wearing it — `SKILL.md` § *Triage a hosted-window defect before choosing a seam* is the fork it exists to settle, and a frame that is broken here is an extraction defect while a clean one over a wrong window is an integration defect. The file name is the window's point size, so a hosted window whose size you do not recognise is a window the border rule grew: pair it with `WMP_BORDER_TRACE`. **`content=` and `over=` are the two numbers no picture carries** — where our content is laid out inside the frame, and whether the frame is painted over it or cut out for it. |
| `WMP_FRAME_PRIME` | `0` | Withhold the primed stand-in and restore the pre-W230 first open, where a hosted window wears palette chrome until a render at its own size lands. **An A/B switch in the same binary, and the only honest way to ask whether a frame that looks wrong looks wrong *because* of the priming.** It earned its place immediately: `Combat_Flight_Simulator_3` was reported broken in the same session the priming landed, and `WMP_FRAME_PRIME=0` showed the identical checkerboard block, dotted top strip and missing side rails — the standing W179/W234 defect, not the new code. A separate baseline build would have answered the same question a worktree and ten minutes later, and `baseline-capture-never-by-stash` rules out the quick way of getting one. |
| `WMP_HOSTED_PREWARM` | `0` | Never build a frame for a window that is not open. Confirm the prewarm ran at all before concluding anything from it: `prewarm queued=<sizes>` at skin load and one `prewarmed <W>x<H> ok= ms=` per size, and then **zero** `miss`/`built` lines when the window is opened. It prewarms only what `hostedWindowRecency` names, so a defaults domain that has never opened a hosted window prewarms nothing and looks identical to `=0`. **Since W250 this is a latency switch, not a correctness one**: the guarantee that a window is never shown wearing palette chrome is `WMP_HOSTED_HOLD`, and turning the prewarm off now lengthens the hold rather than restoring the flash — which makes `=0` the cheapest way to *exercise* the hold on a skin whose frames are all cached. It also goes eight windows deep rather than four, and re-queues sizes learned after the first pass, because at four it covered the library and left the spectrum analyser opening onto the palette. |
| `WMP_HOSTED_PRESIZE` | `0` | Withhold the pre-show growth and restore the pre-W248 open, where a hosted window is ordered front at its own size and grown by `HostedWindowBorderLayout` a runloop turn later — in front of the user. The A/B switch for the half of W248 that is about *when* a window is sized. **Note what it cannot show you**: `[wmp/border]` prints after the positioning either way, so both settings can trace `frame=550x890 target=550x890` while one of them resized on screen and the other did not. The growth is the second of the two jumps; the first is the controller's own `setFrame`, which this trace never sees. **Judge this flag on the screen, not on the trace.** |
| `WMP_FRAME_STANDIN` | `always` | **Only with `WMP_FRAME_LIVE_RESIZE=0`** (the default stand-in is re-laid out and has no tolerance to lift). Restore the pre-W248 stand-in, where a ring was stretched onto any window size while its own render was in flight and only a *panel* was held to 15%. The A/B switch for the half of W248 about what is drawn during the gap, and the one flag here that the trace does answer cleanly: `standin=scaled from=389x247` for a 550x890 window is the stretch, `standin=out-of-scale` is it being refused. |
| `WMP_FRAME_LIVE_RESIZE` | `0` | Restore the pre-2026-09-23 behaviour in one binary: a full donor build per drag pixel, all concurrent; the last render stretched and refused past 15% (palette chrome); and a skin switch adopted at once rather than staged, with no player hold. **The A/B switch for the drag fix**, and it reproduced the reported flicker on the first run: `ALXVortex`, library dragged 180pt — `=0` gave 1032 `standin=out-of-scale`, 900 `scaled`, 24 builds; default gave every miss `relaid` and 2 `built … drag`. It does **not** bring back W248's `outgoing` stand-in, which was removed. **Judge it on captures, not the trace**: `screencapture -x -R <rect>` takes ~110 ms, so two loops started 55 ms apart give ~55 ms spacing through a `winhelper drag`; a `ResizableWindow` edge is live only in the 14pt band at the left edge, the bottom edge, or the bottom 42pt of the right edge (the rest of the right edge is the scrollbar), so drag the left edge. The drag is signalled by `ResizableWindow`'s own `.windowEdgeResizeDidBegin/End` — AppKit's live-resize notifications never fire for these windows — so a drag with no `live-resize begin` line did not hit the edge. |
| `WMP_HOSTED_HOLD` | `0` | Show a hosted window the instant its controller does, restoring the pre-W250 open where it appears wearing NullPlayer's palette chrome and is re-dressed when its frame lands. **The A/B switch for W250**, and the one to reach for whenever a hosted window is reported appearing late or not at all — `=0` separates "the hold is waiting on a frame" from "the window was never opened". What it restores is measurable: `ALXVortex` 2026-09-21, the spectrum analyser opened at 368x145 and drew palette chrome **20 times** over `standin=out-of-scale from=550x893` before its ring landed 263 ms later; two restored windows at launch drew **155** times before the donor's borders had even resolved. |
| `WMP_HOSTED_HOLD_MS` | `<ms>` | How long a held window may stay invisible before it is shown regardless — **and how long a staged skin switch may wait before it commits anyway** (`commit reason=budget`). Default **4000**. It is a backstop, not a budget the common case spends — a settled skin answers immediately and the measured holds are 276 ms (a cold analyser) to 2.09 s (the library at launch, of which 1.4 s is the ring render alone). Set it low to *force* the failure mode and see what the user used to see: `WMP_HOSTED_HOLD_MS=1` reveals every window before its frame and every `reveal` line says `reason=budget`. |
| `WMP_HOSTED_FRAME` | `<W>x<H>` | `HOSTED-FRAME` — the ring this skin lends **NullPlayer's own** windows (`WMPHostedFrameTemplate`), derived and rendered at that window size, with the four insets our chrome lays a hosted window out from: `view=` the donor, `ring=` its piece count, `caption=` the band above the client hole, `left=`/`right=`/`bottom=`, `content=`, and `scaled=yes` where the window is below the donor's own floor. `HOSTED-FRAME none` is a skin that lends nothing. **Every other flag here measures a view of the skin's; this one measures what a skin gives a window it never authored**, and nothing in a render dump shows it — the frame is the donor view re-rendered at our window's size with the skin's own content subtracted out (W209). `caption=` is the number it exists for: our title and close control go in that band, and it is the donor's stretched subview that decides how tall it is. `corner=` is the ring's own top-right corner piece. It bounds nothing — it is kept because it is the measurement that *rejected* two rules: these corners are decorative and mostly transparent, so they come out wider than the border they sit in (202pt on `Star Wars`, 296 on `Half-Life_2`, 190 on `Halo 2`). **Nothing of ours is drawn in the band at all now** — the close is a 40x26 hit area in the window's corner, over whatever × the skin painted there — so `caption=` is read to cap that target's depth, and the `strip=` field that reported the lit title bar inside the band is gone with the rule that read it (`WMP_STRIP_TRACE` too). If a future change needs to know where a ring paints its bar, that is the rule to leave dead: four attempts at inferring a title bar from pixels each shipped and each broke on the next skin. **`WMP_HOSTED_FRAME_SCALE` is not decoration**: this probe renders at 1x by default and the app renders at the screen's backing scale, and the strip rule that used to live here answered `5+12` at 1x and `none` at 2x — a one-pixel specular highlight that averages away at 1x outshone the bar at 2x, so a rule that measured clean in the harness drew the old layout in the app. Measure any pixel-reading change at **both** scales; agreement between them is the check, and a rule that needs the check at all is a rule worth not having. `WMP_CAPTION_TRACE=1` — read by **the app**, a DEBUG build, printed through `NSLog` because a `print` into `kill_build_run.sh --log` is block-buffered and never arrives — prints the close hit rect `SkinnedSurfaceChrome` resolved for each hosted window, plus the `artwork=` size and the `content=` hole it read it against — the hole is the number that separates "the control is misplaced" from "the donor's client panel really is that narrow". Reach for it before measuring a caption off a screenshot: `screencapture -l <id>` on these windows returns an image wider than the window (it picks up what is behind it), so its columns do not line up with window points, though its **rows** do. The player view is ranked last by `derive`, as in the app; here the player is the skin's declared startup view falling back to document order, which is where the app's own candidate walk starts, so a skin whose walk lands elsewhere can name a different donor live  **A skin can lend a *panel* instead of a ring (W207), and `panel=sliced` is that donor class** — one fixed bitmap nine-sliced at the hole its own list sits in, which is how a 2000-era skin draws a drawer (`anemone`'s `trayplaylist.bmp`, 328x261, list at 83,72 155x116). A panel line carries no `min=`: it is sliced, so it fits any window wider than its own borders, and those borders *are* the `caption=`/`left=`/`right=`/`bottom=` fields. Measured at 550x464 over the 185 installed archives: **88 lend a ring, 32 lend a panel, 65 lend nothing**, and the 88 ring lines are byte-identical either side of the change. A `panel=sliced … artwork=none` line is a panel the derivation claimed and the slice rejected — the four margins come from the *resolved* hole, so a donor sized by its own bitmap can only be checked one build later (14 archives; the provider drops the template when that happens, so the window falls back to palette chrome). `WMP_HOSTED_FRAME_DUMP=<dir>` writes the frame itself as `<view>-frame.png`: nothing in a render dump contains it — a ring is the donor view minus its own content and a panel is assembled by us — so before it the numbers on this line were the only evidence, and they cannot see a borrowed glyph, an erased bezel or a seam landing in the wrong place. **Three more fields, all W209.** `gaps=<top>/<left>/<bottom>/<right>` is the longest unbroken run of *bare* edge in a 6pt band, as a fraction of that edge — the only number on the line that can see a frame that came apart, since every other one is derived from markup that resolves perfectly for a donor whose pieces meet only at the skin's own layout. Under the default whole-donor path, gaps no longer reject the ring, but they **do gate span-repair attempts**, using both fractional and absolute-length criteria (W212/W228). Whole-view rendering can still leave script-sized rails short. `refused=ring-open` is unreachable in that default path; the diagnostic `WMP_HOSTED_FRAME_WHOLE=0` assembler can still emit it (21 refusals before the default-path change, 0 after). `whole=yes` says the frame is painted **over** the content with its interior fill erased rather than its client rectangle cut out; `whole=no` is a donor whose interior is a picture, or one where more than 10% of the hole survived the erase, and keeps the cut. `WMP_HOSTED_FRAME_WHOLE=0` restores the piece-selecting assembler the whole-view render replaced and `=1` draws whole but without obeying the donor's declared floor — **the two comparisons every number in [`skins/back-to-the-future-trilogy.md`](skins/back-to-the-future-trilogy.md) was measured against**, and the only reason they still exist. Corpus at 357x238: 88 rings / 40 panels / 0 ring-open refusals by default, against 67 / 40 / 21 with `=0`. |
| `WMP_HOSTED_FRAME_SCALE` | positive finite scale; use `1` and `2` for comparisons | Backing scale passed to hosted-frame rendering. Missing or non-`Double` input defaults to `1`; the flag parser does not itself validate finite/positive values, so do not use invalid numeric values as a supported mode. `WMP_HOSTED_FRAME` dimensions remain **points**. Raster scene dimensions use `ceil(canvasPoints × scale)`, then the frame may be cropped. Exact panel PNGs are rasterized at target size; ring PNGs can retain the cropped donor extent, including below-floor rendering, and are mapped to the requested point size when drawn. Read actual PNG dimensions rather than assuming every dump is requested points × scale. This existing flag is independent of the architecture document's proposed matrix interface. |

### The probes that are not in the test binary

`WMP_PLACE_TRACE=1` is read by **the app** (`WMPViewWindowMaterializer.place`) and prints one
`[wmp/place] <viewID> <frame>` line per auxiliary window, at the moment it is placed and never
again — placement happens once per window, so a window the user has moved is never yanked back.
It is the `.wmz` counterpart of `WINAMP_MODERN_PLACE_TRACE`, and it exists for one question a
screenshot answers badly: **a skin that opens five panels at load has five windows to fit**.

**Since W217 a stranded `.wmz` window is recoverable — Snap To Default has a `.wmz` routine, and
since G2/G3 (2026-09-20) the off-screen safety net and the session restore correction run in `.wmz`
too — so a `[wmp/place]` frame outside every screen is a defect and not merely a warning.** It is
also now transient rather than permanent: the sweep runs after a display change, a UI Size change, a
skin load and the post-restore settle, so a trace taken at placement time can show a frame the app
has already corrected by the time you look at the window. **Read the window back with
`winhelper windows` before calling a `[wmp/place]` line a live defect** — placement and the settled
layout are two different measurements, and only the second is what the user sees. The same flag now
also prints `[place/tile] hosted <frame>` for NullPlayer's own windows opening in WMP mode (they
share the `.wal` tiling branch of `positionSubWindow`) and one `snap-to-default` line per window on
each press. Read the frames back with `app-control`'s `winhelper windows`, never off a screenshot,
and check idempotency by `diff`ing two presses.
`Halo 2`'s `onLoadSkin` opens four from its own preferences plus `mainView`, and the failure mode
is not a wrong-looking window but an invisible one — the tiler walking off the bottom of its column.
A line whose frame is outside every screen is the `rescuedOrigin` fallback failing; a line that
repeats for the same view is placement running twice, which is the bug this flag exists to catch.

```bash
WMP_PLACE_TRACE=1 skills/app-control/scripts/launch.sh <skin>        # log: /tmp/np.log
```

`WMP_SIZE_TRACE=1` is read by **the app** (`WMPMainWindowController.windowDidResize`, DEBUG, through
`NSLog`) and prints one line per resize of a `.wmz` window — the view, the new frame, whether it is
our own scene size landing (`applying=true`), and **the call stack that asked for it**:

```
[wmp/size] <viewID> -> (<W>, <H>) applying=<bool>
<14 frames of backtrace>
```

**The backtrace is the whole instrument, because the question this flag exists for is not what size
the window is — every other probe answers that — but *who* chose it.** W213's third defect was a
`.wmz` player that opened at the skin's 192x82 and was 192x145 a click later, and the size alone is
compatible with four unrelated causes: the skin's own script, a stored size, the scene builder's
clamp, or a pass in `App/` that has no idea a skin is loaded. It was the fourth — one frame named
`WindowManager.tightenClassicCenterStackIfNeeded`, reached from `windowDidFinishDragging`, growing
the window to `Skin.mainWindowSize.height` because `isRunningModernUI` answers false for the WMP
controller. **Two days of reasoning had already produced a guard against the stored size**, which is
a real rule and was not this bug; the trace found the cause on its first run. Reach for it before
theorising about any `.wmz` window that is not the size its markup says, and note the pairing: a
line with `applying=true` is ours settling and is not evidence of anything.

It prints a second kind of line, and that one is a **detector rather than a trace**:
`[wmp/size] MISMATCH <view> canvas=… floor=… verdict=below-floor|above-ceiling` whenever the limits
the app is about to give a window would force it away from its own scene. `WMP_RENDER_LIMITS`
enumerates the scenes where that is structurally possible; this fires when it actually happens, which
is the half no corpus sweep can own.

`WMP_ANIM_TRACE=1` is read by **the app** (`WMPMainWindowController.startAnimation`) and prints what
the repaint loop *achieved* over the last second, once a second per animating window:

```
[wmp/anim] <viewID> want=<n>fps got=<n>fps frames=<n> restarts=<n> sleep=<ms> render=<ms> present=<ms>
```

**`got` against `want` is the whole instrument, and `restarts` is what usually explains the gap.**
A frame rate is not a thing `ANIMATION` or a render dump can show: a dump is a still, and the
cadence line reports what the scene *asked for*, so an engine delivering 60% of it looks identical
to one delivering all of it. This found W142 on the first run — `want=25.0fps got=20.0fps frames=21
restarts=10 sleep=42.3ms render=4.5ms` — and the line carries its own diagnosis: ten restarts a
second is a rebuild cancelling the loop mid-sleep, `sleep` above the requested period is
`Task.sleep` overshoot, and `render` is what a serial render adds to every frame interval.

```bash
WMP_ANIM_TRACE=1 skills/app-control/scripts/launch.sh <skin>        # log: /tmp/np.log
```

**Once a second, never once a frame** — and `restarts` is *why* it can be. The first version reset
its window inside `startAnimation`, which is called by every rebuild, so on `AlienMorph` no window
ever reached a second and **27 seconds of capture produced zero `got=` lines** while printing 267
useless start lines. That is the `INPUT` trace's removal repeating itself inside a new instrument:
a per-frame line in a subsystem that repaints 25x/s is not a trace. Counters live on the
presentation and survive a restart; the restart is counted rather than narrated.

`WMP_SEEK_TRACE=1` is read by **the app** (`WMPMainView`, `WMPMainWindowController`) and prints the
value a dragged slider carries from the pointer to the host command — three lines per *gesture*,
which is what makes it usable where the removed `INPUT` trace was not:

```
[wmp/seek] performSlider seekMain mapped=Optional(0.451) min=0.0 max=1155.23 value=520.99
[wmp/seek] release seekMain#48 value=Optional(520.99) pendingSeek=Optional(...number(0.451))
[wmp/seek] hostCommand seekSeconds=18.95 duration=1155.23      ← the defect, in one line
```

`pendingSeek` on the release line is the seek the whole gesture is asking for, and since W156 it is
the **only** one: a drag prints its `performSlider` lines and then exactly one commit, either the
skin's `hostCommand seekSeconds` or the engine's own. **Count the commits, not the moves** — a
capture with a commit per `performSlider` line is the W156 regression, and it is what a 200 px drag
looked like before: 21 of them in half a second.

**Read the last line against the second.** They disagreed by the whole track on W151, because an
implicit binding settled over the user's value between the release and the handler that read it.
Every link in that chain is plausible in isolation, so this is the instrument for "the control moves
and nothing happens".

**Three traps, each of which looks exactly like "the fix did not work":**

- **A redirected `print` is block-buffered.** The first capture of this trace produced an empty log
  while the app was working perfectly. Live traces write to **stderr** — `WMP_PLACE_TRACE` and
  `WMP_ANIM_TRACE` are read on a terminal, which is why they get away with `print`.
- **The first click on an inactive window is consumed activating it**, so the first whole drag
  raises nothing. `AXRaise` the window, drive one throwaway gesture, then the real one. **And when
  the reporter is at the machine, a posted `CGEvent` reaches nothing at all while their app is
  frontmost** — it fails silently and reads exactly like a dead control, which cost several rounds
  on 2026-09-16. `set frontmost to true` on the debug build's pid immediately before each gesture,
  and re-read the window origin every time: a session shared with a live reporter moves the window
  under you, and a click computed from a stale origin lands on the desktop.
- **A short track cannot show a seek.** Pair it with `NULLPLAYER_PLAY` and something long.
- **Launch a skin with `skills/app-control/scripts/launch.sh <name>`, never by hand.** It prints a
  verified `LAUNCH PASS`. Hand-rolled launches came up on the wrong skin repeatedly: `NULLPLAYER_SKIN`
  is the classic loader and loads nothing for a `.wmz`, and session restoration rewrites
  `wmpSkinName` before the window opens (2026-09-12, 2026-09-23, 2026-09-25).

```bash
WMP_SEEK_TRACE=1 skills/app-control/scripts/launch.sh "Plus! Pulsar"     # log: /tmp/np.log
```

`WMP_WIDGET_TRACE=1` is read by **the app** (`WMPMainView`, `WMPWidgetViews`, `#if DEBUG`, stderr)
and prints the lifetime of every AppKit-hosted widget against the presents that carry it: one
`present src=<initial|load|interaction|transaction|timer|animation> widgets=[<kind>:<stableID>,…]`
line per present, a `create`/`drop` line per hosted view, and a `playlist draw rows=…` line per
redraw of a playlist surface.

**It exists because a pane that opens and then closes itself is invisible to every other
instrument.** `WMP_RENDER_CLICK` rebuilds one scene from one event and says the switch was
requested; nothing headless can see a *second* present, from a different code path, landing 11 ms
later with the state the first one replaced. `claw`'s playlist was reported as "it displays, then
goes black, then displays" and the whole defect is three lines:

```
946.471 present src=transaction  widgets=[playlist:6,text:25]   ← the click: the list opens
946.483 present src=interaction  widgets=[effects:4,text:25]    ← stale overrides: list dropped
946.785 present src=transaction  widgets=[playlist:6,text:25]   ← the list comes back
```

**`src=` is the field to read, and a `drop` followed by a `create` of a different kind is the
signature.** The black frame is not a paint bug: dropping a hosted view and building a new
`WMPEffectsSurfaceView` in its place shows an empty GL surface until its first frame. Read the
sources against each other — an `interaction` or `animation` present that contradicts the last
`transaction` is a repaint built on overrides a script transaction has already replaced
(W223: `renderInteraction` re-checks them, closed 2026-09-17).
**The presents are also a rate measurement**, and `structure=` is what makes them cheap (W224):
`claw` with the list open and no visualizer re-presents 11.8x/s off its scrolling `<TEXT>`, and
before the gate every one of those frames rebuilt the hit tester, re-synced the widgets, reset the
tooltips and cursor rects, rebuilt the accessibility tree and **redrew the whole playlist** — 106
list redraws in 9 s with the list unchanged. A present whose `hits` and `widgets` both equal the
last one's is a new *picture* and nothing else, so all of that is skipped and only the renderer's
frame remains; `WMPPlaylistSurfaceView.update` likewise marks itself dirty only when the rows, the
play marker, the highlight or the scroll position moved. **Read the two together**: with the list
open, `structure=same` on every present and **zero** `playlist draw` lines is the correct capture,
and one `playlist draw` with a changed `selected=` on a track change is the control that proves the
guard is not simply stuck (measured 2026-09-17 on the 3-track cue row).

`NULLPLAYER_PLAY=<audio file>` is read by **the app** (`AppDelegate`, `#if DEBUG`) and enqueues and
plays that file at launch through the same `application(_:openFiles:)` a Finder open takes. **Live QA
needs playback**, and every readout a skin binds to the host — the clock, the seek thumb, the
duration, the title — reads its resting value with an empty playlist; without this, getting a track
into a launched debug build costs a Local Library window and a CGEvent double-click per launch, and
WMP mode's own route to a track is a file dialog. It is the live counterpart of `WMP_RENDER_HOST`:

```bash
skills/app-control/scripts/launch.sh <skin>        # log: /tmp/np.log
```

**`WMP_TRACE_INPUT` and the `INPUT` trace were removed on 2026-09-11.** The instrument had become
unusable as a *live* one and that is the lesson worth keeping: the lines were emitted per present
and per pointer crossing, and a skin repaints at its own cadence — an animated view presents 20x/s,
each present re-running `synchronizeWidgetViews` and the position-change transaction — so three
identical lines a frame buried everything that carried news, and a hover edge with no authored
handler wrote "nothing happened" for every button the pointer passed over on the way to the one it
wanted. Reported live as unreadable log noise, twice, and the second time the answer was to take it
out rather than to filter it.

It *did* find real defects — `hosted=0` through a whole track settled Corona's "no visualization",
and no `hover` lines at all while `dispatch click` worked settled the window-never-key defect on
2026-09-08. **Both were answered by a state that never changed, not by a stream.** If a question
like that comes back, build the instrument that way: a counter, a one-shot, or a line that prints
only on a *change*. Never one per frame, and never one per pointer move. What follows is kept
because the distinctions it records are about the app, not about the trace.

**`action` and `command` are two different inputs and only one of them was ever traced.** `command`
is a host command a *script transaction* posted, so a skin that commits through JScript is visible —
Cablemusic's seek slider posts `seekSeconds` from an `onDragEnd`. A plain transport button goes
`WMPMainView.onAction` → `host.perform` and posted nothing, so it left no line at all. Reading an
absent `command play` as "play was never pressed" is therefore wrong for every skin that binds its
buttons directly, which is most of them. `action` closes that gap; **check both before concluding an
input never arrived.**

`script-diag` is the headless `SCRIPT-DIAG` line, in the app. Without it a handler that throws in
the running app is indistinguishable from one that ran and did nothing — which is the first fork to
close whenever a live defect looks like "the script did not fire". It is also how W86 was separated
from W46: `9SeriesDefault`'s compact-mode handler raises **no** diagnostic, so the handler is fine
and the loss is downstream of it.

`view-timer` is the line that found the dead `onTimer` class: `1000ms` from `apply`, then `0ms` one
line later because `scheduleTimers` cancelled it.

**`animation`'s `clock=` is the line that found the restarting-animation class (2026-09-08), and it
is only readable because it prints the clock rather than the frame.** Reported live as "the
animations keep opening and closing constantly… when you try to interact they are just opening and
closing all the time". `startAnimation` rewound `animationEpoch` on every call, and it is called by
every scene rebuild — a hover repaint, a script transaction, an `onTimer` tick. The trace showed
`epoch-was=0.008s-old` on a view whose script had set `timerInterval="100"`: a 2.16s one-shot intro
restarted ten times a second and never reached its second frame. The second half was invisible until
the epoch was fixed — every rebuild also rendered at the default `clock: 0`, so a transaction painted
frame zero even with the epoch preserved. The clock now belongs to the **view**
(`animationEpochViewID`), and every render of a view that is already animating passes
`animationClock(for:)`. Confirmed live: the clock advances 176.4 → 179.5s across a hover sweep and
two clicks, and four window captures during continuous hover activity are byte-identical.

It is the instrument that found every one of the 2026-09-08 live defects, and each was invisible to
every headless probe here: the window was never key (no `hover` lines at all while `dispatch click`
worked), a script present erased the hover artwork, `<TEXT>` rows were not hit targets, `Halo 2`
presented a thumbnail view its own `onLoad` had blanked, and no view timer in the corpus had ever
fired (`view-timer 1000ms` immediately followed by `view-timer 0ms`). Read once at process start like every other
probe — exporting it at a running app reports nothing.

`WMP_TEST_WMZ` and `WMP_RENDER_DUMP_DIR` are accepted aliases for `WMP_SKIN` and `WMP_RENDER_DUMP`
so the Phase 0–8 handoff docs' invocations still run. Use the names in the table.

One archive:

```bash
WMP_SKIN=~/Library/Application\ Support/NullPlayer/WMPSkins/corona.wmz \
WMP_RENDER_EXPR=1 WMP_CALL_TRACE=1 WMP_RENDER_SCRIPTS=1 \
  swift test --filter WMPRenderDumpTests/testSweepsSkinOrCorpus > /tmp/wmp/corona.txt 2>&1
```

**`WMP_SKIN` takes a directory and sweeps it inside one process invocation.** The `.wal` sweep does
79 archives in ~5 minutes where a shell loop over them took 25, and the test-binary startups were
nearly all of the difference. One invocation also cannot be invalidated halfway — a sweep is a
build, and an edit landing mid-loop silently wrote *empty* captures that then diffed as "everything
changed".

A skin that fails to load prints `SKIN <file> FAILED <error>` and the sweep carries on. One broken
archive must not abandon the rest.

---

## Driving the app: the loop that found the compact-mode class

Three of the four defects in the compact-mode report were invisible to every flag above, because a
**view switch is an app path** — the sweep renders each view independently and never performs one.
The loop below is what reproduced them, and it is cheap enough to be the default response to a
screen-only report rather than a last resort. Nothing in it is committed; rebuild it as needed.

1. **Select the skin and launch the debug build with the trace on** — one line, verified, nothing
   to restore afterwards (`app-control` § Route B):

   ```bash
   WMP_SEEK_TRACE=1 skills/app-control/scripts/launch.sh 9SeriesDefault
   ```

2. **Ask the probe where the control is, then click that frame.** `WMP_RENDER_PROBE` prints every
   drawn node's resolved frame in scene coordinates, which are the window's own top-left
   coordinates — so a `frame=540,304 20x19` is clicked at `(550, 313)` with a `CGEvent` posted at
   the window's origin plus that offset, found through `CGWindowListCopyWindowInfo` filtered on
   owner `NullPlayer`. Guessing from a screenshot wastes a launch per miss; a `BUTTONELEMENT` inside
   a `BUTTONGROUP` has no frame of its own at all and is resolved instead by decoding its
   `mappingColor` out of the group's mapping bitmap and adding the group's origin.

3. **Read `/tmp/app.log`, then capture the window.** `screencapture -o -x -l <windowid>` takes the
   window alone, transparency included. **Check the capture's pixel dimensions before reading the
   picture**: given a window id that has gone stale — the app relaunched, the view switched — it
   does not fail, it silently returns a **full-screen** image, and a screen crop compared against a
   window crop reads as the skin having lost half its artwork. (`-R` is the other half of the same
   trap: it wants `x,y,w,h` with commas and rejects `WxH`.) A window whose own capture is `192x82`
   at 1x and `384x164` at 2x is the one you asked for; anything near the screen's size is not.
   **Never point-sample a 2x capture against a 1x dump either** — a 2x render is not a 1x render
   scaled, and 4,252 opaque pixels came out "differing by >40" on a window with nothing wrong with
   it. Render the dump at the capture's scale, or compare shapes rather than pixels. It is far too slow to film a 250 ms animation — capture the
   *settled* state and use `WMP_RENDER_SETTLE` for the frames in between.

**What the trace settles that a screenshot cannot.** The compact-mode report read as one defect and
was three, and the `INPUT` lines separated them in one launch each: `dispatch load` missing said the
switch never loaded the view (W46); `setViewTimerInterval value=50` immediately followed by
`value=4000` said a chained timer had registered and then been dropped (W86); and `script-diag`
staying silent through all of it said no handler ever threw, which is what moved the search out of
the script and into the engine's own semantics.

### Capturing the hosted windows, one at a time

**Two eliminations come before this loop**, both cheap, both in `SKILL.md` § *Triage a hosted-window
defect before choosing a seam*: check the skin's own window (if it is right, the whole shared engine
is cleared and the defect is hosted-only), then read the frame PNG against the live window (a broken
dump is extraction, a clean dump over a wrong window is integration). Capture the set below to
localise a defect those two steps have already placed — not to go looking for one, and never by
multiplying the skin axis, which measures donors the reporter has already cleared.

**Start with `skills/app-control/scripts/winhelper capture-all <outdir> --pid <pid>`** — one PNG
per on-screen window, each its *own* content (`-l`, so occlusion and see-through holes cannot leak
in), each size-checked, a docked group cropped back to the window, and a non-zero exit naming any
window it could not shoot honestly (`skills/app-control` § Route C). It encodes the first trap
below. The park loop after it is the fallback for the windows `capture-all` refuses as off-screen.

A report about a **borrowed frame** is a report about ten windows, and the capture step has two traps
that each hand back a confident wrong picture (W219-W222, 2026-09-17):

- **`screencapture -o -x -l <id>` returns a full-screen image for a window that is off-screen**, the
  same silent fallback as a stale id, and these windows tile down a column that runs off the bottom
  of the screen the moment more than four are open. Check the capture's pixel size against the
  window's points × the backing scale before reading it, every time.
- **`-R x,y,w,h` picks up whatever is behind the window**, and a hosted window is mostly keyed-out
  artwork, so the window behind reads as *this* window's content: a visualizer showing through a
  transparent hole reads as a ground that was never painted. Park each window alone before shooting
  it — move the others off-screen right (`set position to {1400, 40}` via System Events), put the
  one under test at a fixed origin, `AXRaise` it, capture, then move it away and bring up the next:

```bash
PID=$(pgrep -x NullPlayer | head -1)
pos() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) \
  to tell (first window whose name is \"$1\") to set position to {$2, $3}"; }
skills/app-control/scripts/winhelper windows > /tmp/wins.txt
while read id layer x y w h alpha name; do pos "$name" 1400 40; done < /tmp/wins.txt
while read id layer x y w h alpha name; do
  pos "$name" 60 60; sleep 0.5
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) \
    to tell (first window whose name is \"$name\") to perform action \"AXRaise\""
  screencapture -x -R 60,60,$w,$h "/tmp/w-${name// /_}.png"; pos "$name" 1400 40
done < /tmp/wins.txt
```

**Compare every affected window before classifying the cause.** First compare donor identity,
requested point size, backing scale, frame readiness, and resolved content geometry. Normalize bare
edge fractions into point lengths: W228 left the same approximately 107pt rail gap unrepaired only
at tall library sizes, so a one-window symptom can still be a shared frame defect. Only after those
inputs match should a differing result point toward that window's composition/layout path.
The `TheUnit` report also contained independent frame and layout defects; capture all affected
windows rather than treating the first explanation as sufficient. See
[Alienware Invader's dossier](skins/alienware-invader.md) for the size-dependent counterexample.

Windows are moved back on-screen afterwards. They are the user's.

### Auditing one authored control across the whole corpus

*"Every skin has this button and it does nothing"* is a shape of report the census cannot answer,
and W100 is the worked example: it stood **unmeasured for three days** at a recorded reach of 2
skins and the true number was **162 of 180**. **`scripts/wmp_control_audit.py <member>` runs this
route** (§ *`scripts/wmp_control_audit.py`* says which of its click points to trust); the steps are
kept here because each exists to survive a trap the previous one hides:

1. **Scan the script text, not the census** (`scripts/wms_grep.py` does the decoding and prints the
   breakdown). `wmp_skin_census.sh` drives `onLoad`; a control's
   demand lives in `onClick`, so the sweep never reaches it. That blind spot is *the* reason a
   title-bar button can be authored by 90% of the corpus and tallied at 4%. Decode the way
   `WMPTextDecoder` does and **print the encoding breakdown** — 153 UTF-16-BOM / 145 cp1252 /
   88 UTF-8 / 9 UTF-8-BOM over the 180 archives is the calibration a correct scan reproduces.
2. **Resolve the handler through the call graph, not by matching the attribute.** `onClick` is
   usually a function name — `SwitchSmall()`, `ToggleSuperCompact()` — so a scan for the mechanism
   in the attribute text finds a fraction of the population. Three levels of body substitution was
   enough for this corpus.
3. **Find the clickable point from `WMP_RENDER_PROBE`, per view, for the whole corpus in one
   sweep.** A node with a frame is clicked at its centre. A `<BUTTONELEMENT>` has no frame and is
   resolved through its group's mapping bitmap — and **take the median pixel of the colour, never
   the first**: the first-scanline pixel lands on a stray or an edge and resolves to the *adjacent*
   button, which reads exactly like the engine dispatching the wrong handler. Two skins were
   misdiagnosed that way before the median fixed both.
4. **A `<BUTTONGROUP>` that draws nothing has no `PROBE` line**, so step 3 finds no group to hang
   the mapping decode on — `Cablemusic`'s is invisible for exactly this reason. Fall back to the
   authored `left`/`top` chain, or to a per-skin dossier under `reference/skins/`.
5. **Drive the click and read `unrecognised=`, not the screen.** `WMP_CALL_TRACE=1` alongside
   `WMP_RENDER_CLICK` is what turns "nothing happened" into
   `[handler-error] … unimplemented view.returntomediacenter`. Sampling 15 skins was enough to
   establish the class; the population came from step 1.

**`WMP_RENDER_CLICK` does not follow a view switch.** It rebuilds the *same* `viewID` after every
gesture, so a click posting `command=setCurrentView value=viewTiny` proves the switch was
*requested* and says nothing about what the user would then be looking at. For anything about the
view a skin lands on, the running app is the only arbiter — which is what the loop above is for.

### A live pass is a window frame, before and after

For "does the button change anything", the measurement is `CGWindowListCopyWindowInfo` filtered on
owner `NullPlayer`, read before the click and after it. It is objective, it is two lines of Swift,
and it scales to a skin per launch — eleven skins were audited this way in one pass. A screenshot
diff is the second reading, for the case where the window legitimately does not resize
(`portals`'s two views are both 359x465, and byte-identical captures are what proved that click
dead).

Three traps, all of which produce a confident wrong answer:

- **Check the window size against the view's canvas before believing anything.** A launch that
  failed to select the skin comes up on the unskinned view at **440x170** and looks like a working
  app. Four skins in one loop were driven that way — `zsh` does not word-split an unquoted
  parameter, so `set -- $row` handed the whole line to the first argument — and every "before" and
  "after" agreed, which reads as *the button does nothing* rather than as *no skin is loaded*.
- **`AXRaise` and activate first.** The first click on an inactive window is consumed activating it.
- **Play something.** `NULLPLAYER_PLAY` — a `status_onchange` lands five times a second with a track
  playing and it is what cancelled the click transaction in W113.

### Number the transactions before theorising about one

W88 was diagnosed wrong twice from the trace above, and the second fix was a no-op that produced a
byte-identical run. The line that misled was two `dispatch timer` entries with no `present` between
them, which reads as *the second tick cancelled the first before it ran*. It had not: the first tick
ran and presented normally, and the transaction that died was a later one that got as far as
`render` and was then cancelled at a **second** `guard !Task.isCancelled` — a different line, in a
different half of the function, losing a different thing.

Numbering settled it in one launch. A temporary counter in `dispatchScriptTransaction`, printing a
pair per transaction:

```
INPUT txn 207 begin timer handlers=1
INPUT txn 207 ran superseded=false hostCommands=["setViewTimerInterval=0"] diagnostics=0
INPUT txn 208 begin timer handlers=1          ← 207 never presented, never applied its command
```

`ran superseded=false` with no `command` line after it is the whole diagnosis: the handler ran, was
*not* superseded when it returned, and its output still went nowhere — which points at the code
between `transact` and the present, and nowhere else. `dispatch`/`present`/`command` lines carry no
identity, so any interleaving of them is inferred; a sequence number makes it read.

**Add the counter, take the answer, remove it.** It is not a documented flag, because a permanent
one would have to be — and the thing worth keeping is the technique, not the instrument. When a
transaction-level defect resists two readings of the trace, number them rather than reason harder.

### Measure the mechanism's reach before you fix it

"The timer display and seek/progress are broken in wmp for all skins" was diagnosed three times
before it was diagnosed right, and each wrong answer was a real defect with a reach too small to be
the report. The trace showed 1,352 `status_onchange` transactions in two minutes and a script-timer
set being replaced by every one of them, which is W119 and is genuinely wrong — but the corpus drives
its readouts with `timerInterval`/`onTimer` (**442 uses / 91 skins**), not with `setTimeout`
(**9 / 2**), so "every script timer dies when you press play" could never have been what all skins
had in common. One `python3` pass over the archives' `.js` and `.wms` said so in a minute; without
it, the next hour goes into hardening a path two skins use.

**The reach number is also what makes the fix defensible in the other direction.** W120 landed
because 73 sliders across 61 archives author `max="wmpprop:player.currentMedia.duration"` and no
`value`, and W51 landed because every one of the 19 handlers on a position-bound slider is a readout
painter and none writes the position back — that second measurement is the whole argument that
raising 2,141 write-back handlers cannot loop. Both took one scan of the flattened markup.

### A sweep draws each view once, so it cannot see a per-frame cost

**W155 is the worked case and it cost a live session.** W154 gave every `<BUTTONGROUP>`'s base sheet
a mapping mask; the render sweep said 125 views changed, every structural invariant byte-identical,
and every changed view reviewed as an improvement. All of that was true, and the change still made
the app unusable — because `WMPRenderer` rebuilt the derived mask **per draw**, and a sweep renders
each view exactly once. The second frame is where the cost lives and the sweep never draws one.

The instrument that could see it is `sample` on the running app, and the reading that matters is
*which* thread:

```bash
sample $(pgrep -f "debug/NullPlayer$") 5 -f /tmp/hang.txt
```

**The main thread was idle** — 3513 of 3565 samples in `mach_msg` — while six
`com.apple.root.user-initiated-qos.cooperative` threads sat at 3565/3565 with one symbol at 3510 of
them. `WMPRenderer` runs off-main by design, so a renderer this expensive does not block the UI
thread: it **starves the cooperative pool**, and everything else awaiting that pool stalls behind
it. Reported as the app stuttering and hanging; a main-thread trace would have exonerated the
renderer and sent the search somewhere else entirely. Count the outermost occurrence of a symbol,
never the sum across frames — see the `sample` aggregation rule.

Whenever a change makes work happen on **more** commands, more nodes or more often, the sweep's
green is about correctness only. Time a repeated render of one heavy view before believing it is
free: twenty renders after a warm pass took 173.1 ms each before the cache and 0.3 ms after.

### A dump cannot see a **tween** at all, at any clock (W194)

`WMP_RENDER_CLOCK` pins the *animation* clock — GIF frames — and a tween is not on it. A
`moveTo`/`resizeTo`/`alphaBlendTo` duration animates only for a caller that passes
`animatesTweens`, and every headless path here deliberately does not: a dump, a census sweep and the
windowless dispatcher all get the endpoint applied at the handler boundary and the completion raised
in the same transaction, exactly as before that row. **That is the point** — it is what keeps every
number on this page valid across the change — but it means no capture, at any clock value, can tell
a skin that slides from one that jumps. Drive the running app; `Compact`'s drawers are the case.
`Tests/NullPlayerAppTests/WMPTweenTests.swift` is where the motion itself is falsifiable, because
the runtime's frame step can be called directly.

### A dump cannot see *when* a GIF was entered, and `WMP_RENDER_CLOCK` cannot either

`WMP_RENDER_CLOCK` is what makes an animation falsifiable at all, and it still answers only "what is
drawn at the clock I named". The question it cannot take is whether the engine handed that GIF the
right clock in the first place — which is a whole defect class, because `animationClock` is per
**view** and a skin that assigns a `backgroundImage` GIF from script enters it at whatever the view's
clock already reads (**W182**).

`AlienMorph` is the worked case. Its scene is correct at every settle value — `WMP_RENDER_SETTLE` at
1, 3, 5 and 8s all hold `m_anim_shutter_open.gif`, the view timer does not re-fire — and the
animation still plays from 1.1s in, or not at all, depending on whether anything animated in that
view first. Every instrument on this page reports it healthy.

**Drive the app and measure the span of motion**, not the frames: screen-capture the window's rect
in a tight loop, diff consecutive crops of the animated region, and read the first and last interval
above the noise floor. A full run and a truncated one are 9.80s against 1.73s and unmistakable.
Matching a capture back to a GIF frame index is the tempting version and it misreports — the closing
shutter's last dozen frames are visually identical, so a run that had plainly animated came back as
"frame 91 throughout". The recipe is in `reference/skins/alienmorph.md` § *How to drive it*.

**Closed as W182 on 2026-09-15** — the clock is now per slot (node + resource), and an empty slot
table still renders at the scene clock, which is why every flag on this page is unaffected. The
section stays because the *method* is the reusable part: a timing defect is invisible to everything
here, and the before/after that settles one is a motion span off the running app.

`WMP_ANIM_TRACE=1` is next to this and answers a different question — the rate the loop *achieved*
once it was running (`want=25.0fps got=24.1fps … restarts=1`). It says nothing about which frame the
loop started on, and a truncated animation traces as a perfectly healthy one.

### A sweep runs a stopped player, and a skin can be correct only while stopped

W166 is the worked example and it is the sharpest form of the rule above. `Colorchooser`'s
`checkForContent()` reorders its scene from `playstatechange`, so the defect — an opaque panel
reclassified as artwork over a windowed visualizer, and punched out of a non-opaque window as a
click-through hole — exists **only while a track is playing**. The corpus sweep draws every one of
its 535 images against the default stopped host, which is the one state in which that skin is right.
A clean sweep said nothing at all about it, and would have said the same after the fix.

**`WMP_RENDER_HOST=playing` is not the escape hatch it looks like.** It seeds the snapshot, so every
readout bound to a transport path answers as if a track were open — but it does not raise the
skin's `playstatechange`, and that is where the write lives. The headless capture rendered the panel
correctly while the running window did not, and the gap between those two is what named the cause.

So: **a defect the reporter describes with a verb — *when a track plays*, *after I click*, *once it
opens* — is a live measurement**, and the sweep's role is only to say that nothing else moved.
`NULLPLAYER_PLAY` plus `screencapture` of the window is the instrument; see § *Driving the app*.

### A named skin outranks a corpus sweep

The same report was unfalsifiable until the reporter named one: *"catwoman skin is not fixed"*. A
seeded corpus sweep had already said **88 of the 89 archives that author the elapsed binding draw the
right string**, which is a true measurement and was the wrong question — Catwoman authors no
`currentPositionString` anywhere. Its clock is four digit filmstrips positioned by
`value_onchange="drawSeekDigits(value)"` off a `<CUSTOMSLIDER>` whose value nothing bound, so the
whole readout lived in two mechanisms the sweep was not looking at. **Ask for a skin name before
sweeping**, then read that skin's `.wms` — the markup says what the readout is made of, and the two
defects behind it (W120, W51) were both visible in a single 200-character tag.

### The residue `WMP_RENDER_OCCLUDED` does not explain (W149)

Reproduce with `WMP_SKIN=<corpus> WMP_RENDER_HOST=playing WMP_RENDER_OCCLUDED=1` and read the
`reached=rect-only` lines. **W149 closed every row it named as not a defect** (2026-09-24, 10 rows in
4 archives; `STALKER`'s `blankRate4` had already gone). **The probe tests the load-time layout,
before any script has moved, clipped or swapped a node**, so a `rect-only` row is a question, not a
lost control. Before ranking one, rule out the four shapes W149 found:

- **A closed drawer.** `Sports`' `eq2`–`eq8` sit in `EqVid`, parked behind the main panel under
  `pl2`–`pl4`; `ToggleEqVidView()` moves it clear. Read the container's `moveto` targets.
- **A stacked twin running the same handler.** `anime`'s `plHandle`/`closepl` share a frame and both
  run `togglePlView()`; whichever is on top answers and the click does the same thing.
- **A `<BUTTONGROUP>` container whose element still answers.** `Plus! Professional`'s pause group:
  `WMP_RENDER_CLICK` at its centre reaches the `pauseElement`, `action=pause`. A group with no
  element of its own dispatches nothing however it is ranked.
- **A clipped sprite frame.** `T3-Skynet_Media_Player`'s `timeSign` is a 168-wide strip shown
  through a 14x15 cell; outside the cell it is `clipped`, and inside it the elapsed-time frame is
  all transparency colour, so `not-drawn-here` is right.

Confirm with `WMP_RENDER_CLICK` at the control's drawn pixels and read `hit=`/`refused=`. **Name the
node before ranking the count**, the same rule this file states for `unresolved`.

### Read the probe for what is *absent*

**A widget is not in the PNG, so a sweep that compares only images cannot see one appear or go.**
W55 changed 57 views' widget counts corpus-wide — 1,863 to 1,711 — while moving **22 images**, and
the two facts are not in conflict: playlists, sliders, popups, edit boxes and effects surfaces are
AppKit overlays the scene image never contains. Read `widgets` out of `RENDER-DUMP` and the
`CLICK … after:` tally alongside the image diff, or a drawer that opens onto nothing reads as a
clean sweep. That is the same blind spot W71 measured for overlay *painting*, in a different
direction: W71 asked whether an overlay painted where the scene did not, this asks whether it exists
at all. `CLICK … after:` names the kinds for that reason — Corona's drawer turns on a `PLAYLIST` and
a `DROPDOWNPLAYLIST` in one handler, and a bare count cannot say which one the engine hosted.

**A drag that stops at the last move measures a different engine than the app.** `WMPMainView.mouseUp`
raises `dragend` for a captured slider, so the harness's drag does too, and the host command on that
line is the seek the drag asked for (W55). With no media loaded the snapshot's duration is 0, so the
value is 0 and `follows-pointer` reads `flat`: that is the empty snapshot, not the dispatch. Read
`handlers=` and `commands=[…]` to tell a handler that ran from one that was never found.

`WMP_RENDER_PROBE` is normally read as "is this node's frame right". W95 was found by reading it the
other way: `WoW`'s `plView` printed a `WIDGET` line for its edit box and its list box and **no line
at all** for `playlist1` — no `PROBE` row either, so the node was not merely mispositioned, it was
never in the scene. That is a different class from every defect the probe was built for, and it is
invisible in a screen capture, where a missing control and a control drawn empty look the same: the
authored `backgroundImage` still painted a white slab where the rows should have been.

The check is cheap and worth making the first move on any "this control does nothing" report: grep
the probe for the element's authored id. Nothing back means the walk dropped it, and the reasons it
can are few — a falsy `visible` (an override, a `wmpprop:` binding, or the literal), an empty frame,
or an ancestor that went first. `RENDER-DUMP`'s `N nodes, N commands, N hits, N widgets` counts are
the same signal one level up; a `widgets` count lower than the controls you can see in the markup is
the same finding without needing the id.

**Shorten a long intro with the skin's own preference rather than waiting it out.** `Alienware
Invader` plays 568 frames before it reveals anything, which is minutes per launch in a debug build.
Its own script skips to frame 362 when `theme.loadPreference('soundFX')` is `"false"`, and skin
preferences are plain `UserDefaults` under `wmp.preferences.<sha256 of the .wmz>` in the `NullPlayer`
domain, so `defaults write NullPlayer "wmp.preferences.$SHA" -dict-add soundFX false` cuts the loop
to about a minute. Read the skin's script for the shortcut it already has; do not add an engine flag
for one. **Restore what you changed** — `defaults delete NullPlayer "wmp.preferences.$SHA"` resets
that skin's preferences — and remember the preference dictionary is *evidence* as well as state:
`Alienware Invader`'s held `remoteCallPl/Eq/Vis/Meta = true`, four flags written by buttons and read
by nothing, which is W89 recorded in the user's own defaults.

### Reducing a skin's script to a standalone repro

W86 was a JScript-versus-JavaScriptCore difference inside 200 lines of the skin's own code, and
reading it was not going to settle anything. Extracting it was:

```bash
unzip -p <skin>.wmz corona_tiny.js | iconv -f UTF-16LE -t UTF-8 > tiny.js
```

then evaluating `tiny.js` in a bare `JSContext` under a ~20-line stub of the host objects it
touches (`view`, `theme`, the two subviews) plus a **controllable clock** — override
`Date.prototype.getTime` so the driver, not the wall, decides when a timer event fires — and a loop
that calls the skin's own `TimerDispatch()` at the interval it asks for. That reproduced the defect
exactly (`svVideo.height` stuck at 241, `currentViewID` never set), and changing one `for-in` to an
index loop produced the correct result. **Both halves matter**: a repro that only fails proves you
have *a* bug, not *the* bug. Afterwards the same rig runs the engine's real rewrite output, which is
how the fix was confirmed before the app was ever rebuilt.

### Two hosted-frame fixtures that differ only in pixels are the same skin

`WMPHostedFrameTemplate` is `Equatable` and `WMPHostedFrameProvider.configure(skin:playerViewID:)`
short-circuits on an equal one — `if derived == template, builder != nil { return }` — because a
re-presentation of the skin already loaded must not throw its cache away. A template is identified
by the **node ids** it names, so two test fixtures that differ only in their corner geometry and
their bitmaps derive the *same* template: `configure` returns true, nothing is reset, and the
provider answers the first skin's cached frame. The first draft of `WMPHostedFrameTransitionTests`
did exactly this and failed as *"the new skin's frame never replaced the one held over"*, which
reads like a defect in the code under test and is a defect in the fixture. **A fixture that has to
be a different skin must rename its nodes**, and a test that turns on a skin *change* should assert
the change happened — the incoming frame's `CGImage` is not the outgoing one — rather than trusting
`configure` to have done it. `SkinnedSurfaceFrameArtwork` compares its image by identity, so that
assertion is available and cheap.

### An `INERT` row may be a misclassified `UNRECOGNISED` one

`INERT` means "recognised, answered, and nothing behind it" — Tier 2b, explicitly the tier you do
*not* take runtime work from. But the **open property surface** answers any unknown element property
with `""`/`0` and counts it `inert()`, and a *method* name that is not in
`WMPObjectModel.elementMethodVocabulary` lands there too. So an unimplemented method can sit in the
census as an inert property, and the row that should be ranking real demand ranks nothing.

W128 is the measured case: `plListBox1.deleteAll()` read as `CALL plView pllistbox1.deleteall read
value= INERT` in seven skins, and the audit that found it predicted it would appear *nowhere*. Both
readings were wrong in the same direction — the demand was visible but filed under the tier that
means "ignore me". **When you check whether the engine measures demand for a name, read which word
the trace gives it, not just whether the name appears.** An `INERT` on something that is spelled like
a verb is the shape to distrust.

### The dump is flat, so it cannot answer a layering question

`WMPRenderer.dump` passes `splitAtEffects: false` **on purpose**: a PNG is a picture of the skin's
artwork, the effects surface is an AppKit view that never appears in one, and splitting the list
there would drop everything above the visualizer out of the file. Every dump therefore shows the
whole scene flattened in one pass — including artwork that the running app does *not* draw, because
in the app it lands on the overlay raster hosted above the surface.

W144 cost three rounds of "still broken" to that. The reported defect was a skin drawer's artwork
showing through a windowed visualization; the fix was correct on the second attempt and the dump kept
showing the drawer, because the dump always shows the drawer. **`WMP_RENDER_APPKIT` with
`WMP_RENDER_APPKIT_DUMP=<dir>` is the instrument for anything about layering**: it hosts the real
`NSView` stack and writes `<view>-hosted.png`, which is what the user sees. Combine it with
`WMP_RENDER_CLICK` to capture a state the skin only reaches through a handler.

The general form, which is not only about `<EFFECTS>`: **before believing a render dump has
falsified a fix, ask whether the thing you changed is something a dump can represent at all.**

### `gaps=` cannot see a hosted frame that is wrong everywhere but its edges

`HOSTED-FRAME`'s `gaps=` is the longest unbroken **bare** run in a 6pt band at each of the four
edges. Two things follow, and both were learned the expensive way on 2026-09-17.

- **It cannot see anything further in than 6pt.** `Alienware Invader` read
  `gaps=0.000/0.000/0.000/0.000` at 472x290 while the window on screen carried three white blocks and
  a 54pt opaque column over its content (W212, closed 2026-09-17). A clean `gaps=` is not a clean
  frame — and the mirror holds: `gaps=` was the *only* field that could see the bare band down the
  same skin's rails, which the same fix closed, so neither reading substitutes for the other.
- **Bare means transparent, and a PNG viewer draws transparent and opaque white identically.** This
  donor's border bitmaps carry its interior colour baked in — `f_top_right.png` is a silver band over
  opaque `(255,255,255,255)` — so `WMP_HOSTED_FRAME_DUMP`'s picture looked like a frame full of holes
  and was a frame full of white paint. Two diagnoses were drawn from the picture and both were wrong;
  the third came off the alpha *and* off a node-by-node trace of what the frame build actually drew,
  and found a tile 117pt from where the skin's own window puts it. Read the alpha:

```bash
python3 -c "
from PIL import Image
im=Image.open('/tmp/f/plView-frame.png').convert('RGBA')
print(im.getpixel((950,40)))   # (255,255,255,255) is paint; (0,0,0,0) is a hole
"
```

### A single-transaction sweep cannot measure a per-transaction rule

`wmp_render_sweep.sh` renders each view once, after `onLoad`. A change to what happens on the
*second* and later transactions is therefore invisible to it, and the sweep reports it as a clean
no-op rather than as unmeasured.

W144's expression-stickiness change — an authored `JScript:` geometry expression no longer
re-applies unless its value changed — came out **485 identical, 50 differing, 0 lost, 0 gained**
against the baseline both with and without it, byte for byte, because every one of those 50 came
from the alignment change sitting beside it. The rule it fixed only bites on a view with an
`onTimer`, which the sweep never ticks.

`WMP_RENDER_SETTLE=<seconds>` is the instrument: it runs the view's own timer loop at the period the
skin asks for, and it reproduced the defect on the first run (`visDrawer1` back at its authored
`y=215` after two seconds, having been slid to `265` by `onLoad`). This is the same shape as the
"live QA needs playback" rule — **a byte-identical sweep across a change to timers, hover, drag or
playback is unmeasured, not unchanged.**

### The sweep is the arbiter, including against your own fix

W87 had an obvious general fix — re-resolve the view's `JScript:` geometry expressions after the
handlers run — which closed the reported defect completely and **moved 175 of 545 corpus images**,
shattering two skins that had nothing to do with it. Those attributes are an initial layout, not a
live binding, and several read the property they write. The narrow fix that shipped raises only the
`_onchange` handlers the skin itself declared, and sweeps to 544 of 545 identical.

**A fix that resolves the report and moves things outside it has raised a question, not answered
one.** Here the answer was "wrong fix"; in W143 below it was "right fix, reaching every skin that
needed it". The baseline is the engine's own previous guess, not WMP, so neither reading is the
default — `skin-subsystem-blueprint` § *A sweep diff is unclassified, not a regression* is the method.
Sweep before believing a fix, not only before believing a refactor — and read the `RENDER-DUMP`
counts in the invariants diff, not just the image count: `33 commands / 15 hits → 28 / 8` named the
regressed view before any PNG was opened.

**W143 moved 139 of 535 and was right.** The two are distinguishable without taste, by two things
measured in the same
capture. First, **the invariants**: W87's collateral announced itself as changed `RENDER-DUMP`
counts, and W143's 514 changed invariant lines are *entirely* `loadms` timings and `SCRIPT inline:`
tie-ordering — no view gained or lost a node, command, hit target or canvas, so nothing stopped
resolving and nothing started. A wide image diff with a still invariants diff is a layout rule
reaching everything that authored it. **Both of those noise sources were removed on 2026-09-19, so
a capture taken today cannot produce W143's 514 lines at all**; the rule survives, its reading does
not — see *A sweep has one nondeterministic output* below. Second, **sample across skins unrelated to the report and to
each other, and open them side by side** — ten of the 139, and each one had to be a repair on its own
evidence (a badge centred under its own pointer arrow, a clipped readout made whole, a frame that
had been half its window's width). "Every one I opened looks better" is the claim to make, and it is
only worth anything if the ten were chosen before they were looked at. Neither check is the PNG
count, and the count is what both fixes have in common.

### A sweep has one nondeterministic output, and it is an image

Measured 2026-09-14 by capturing the **same build twice** and comparing the pair — which is the
cheap move that turns "my change did this" into "the harness does this", and costs one 45-second
capture.

- **`Scooby-Doo_2/infoView` differs run to run.** Its `loadInfoPrefs` calls `randomPic()`, which is
  `parseInt(Math.random() * 10)` over five character PNGs. It is the only image in the 535 that
  moves on its own, and it will read as collateral damage from whatever you just changed.
  **Still the only one at 553 images (W241, 2026-09-20)**, where it cost a round of investigation
  anyway: the confirmation is one capture of the *same* tree twice, and it is faster than reasoning
  about why the change could have reached that view.
- **The invariants half used to be mostly noise and is not any more, as of 2026-09-19
  (`d72c3970`).** A no-op change reported hundreds of "changed lines" that were entirely `loadms`
  timings and `SCRIPT inline:` tally **ordering** — the same counts printed in a different sequence,
  from unstable dictionary iteration. Both are fixed: `loadms=` is stripped when `invariants.txt` is
  written (it stays in `raw.txt`/`render.txt`, where the census's per-skin `LOAD` parse reads it,
  and `compare` strips it from both sides so an older baseline is still usable), and the tally
  breaks ties on the name. **Two captures of one unchanged binary now differ by 2 lines**, both the
  `HARNESS` line naming the output directory. A changed invariant line is now evidence.

  Two consequences. **A capture taken before that commit diffs ~39 `SCRIPT inline:` lines against
  any capture taken after it** — a one-time reordering into the new canonical order, not a
  regression. And **the old advice was the wrong half of the problem**: "read the counts, never the
  line total" is how a real regression hides in 500 lines of noise. Read the line total now.

**Predict the diff before running the compare.** For W162 the prediction was "7 archives, the ones
with a markup `wmpprop:player.status` binding"; the answer was 14, and the extra 7 were skins whose
`onLoad` reaches a metadata updater. A prediction that is wrong in the *smaller* direction is
information; being unable to predict at all means the change's reach was never measured.

### Attributing a live report to the change in front of you

**Build a baseline worktree at the parent commit before attributing a live report to your change.**
Three reports on 2026-09-09 were assumed to be W55's and behaved identically at the parent; it cost
one build and moved all three out of that change's ledger.

**A NullPlayer surface wearing a borrowed `.wmz` ring is not the scene, and no scene probe reaches
it.** W177-W179 were reported together on 2026-09-15 and all three closed by 2026-09-19. None was
reachable from `WMP_RENDER_APPKIT`, which measures a skin's *own* views against their scene. W179's
evidence was a `WMP_HOSTED_FRAME` line, a `WMP_HOSTED_FRAME_DUMP` PNG and a capture of the live
library window, **in that order**. Two of its lessons outlived it and are in `SKILL.md`: the ring a
window wears is chosen per *view*, so a defect in the bottom bar can be a defect in donor selection
two steps upstream; and a row's own starting instruction can be stale — W179's named the client
hole, which was already correct. **Re-drive a screen-only row before taking it.**

### A baseline worktree needs the vendored frameworks linked in

**Use `scripts/baseline_worktree.sh [<dir>] [<rev>]`** (defaults `../nullplayer-base`, `HEAD`). It
creates or re-points the worktree, links every `Frameworks/` entry git does not carry, mirrors the
build products the test bundle loads from beside itself, and refuses to finish unless
`git status -- Sources Tests scripts` is clean. The traps it encodes are in its header comment:
`Frameworks/` is only partly tracked, so a fresh worktree fails `no such module 'VLCKit'`; once it
links it dies in `dlopen` because the test bundle's rpath looks beside itself; and **linking the
directory rather than its entries** either lands inside the tracked one as `Frameworks/Frameworks`
or deletes twelve tracked files so `capture` refuses the tree — which reads as a capture that will
not start rather than as a link done wrong (measured 2026-09-21 capturing W216's baseline).

Whether a capture then needs `--allow-dirty` depends on the clone's ignore rules — `.gitignore`'s
`Frameworks/VLCKit.framework/` matches a directory, not the symlink, so the link reads as untracked
unless `.git/info/exclude` covers `Frameworks/` — and the script prints which, listing whatever makes
the tree dirty. When it is needed it is safe **for the baseline worktree only** — the untracked
thing making it dirty is a symlink to a framework. Never pass it to hide real edits.

## The line grammar

Machine-readable, one fact per line, inside a `SKIN <file.wmz>` block. `scripts/wmp_skin_census.sh`
and `scripts/wmp_render_sweep.sh` parse these; do not reword one without updating both.

```
HARNESS <n> archive(s) from <path>
SKIN <file.wmz>
SKIN <file.wmz> FAILED <error>
LOAD definition=<p> encoding=<e> entries=<n> bytes=<n> views=<n> nodes=<n> scripts=<n> resources=<n> loadms=<x>
     loadms= is in raw.txt/render.txt only: a wall clock cannot be diffed, so it is stripped from invariants.txt
FINDING [<severity>] <WMP00xx> ×<n> <message>
COMPAT unknown-tags=<n> unknown-members=<n> unknown-events=<n> resources-missing=<n> resources-unsupported=<n>
UNKNOWN tag <name> ×<n>
UNKNOWN event <name> ×<n>
UNKNOWN member <path> ×<n>
SCRIPTS programs=<n> bytes=<n> runtime=<available|unavailable (why)>
SCRIPT <path>: bytes=<n> handlers=[…]
SCRIPT inline: <event>×<n> …
SCRIPT-DIAG <view> [<code>] <message>
     every diagnostic from every transaction the view ran — onLoad, onVideoStart, the resize
     pass and each settle tick — printed once each. Until 2026-09-24 only the last transaction's
     were printed, so a WMP_RENDER_SETTLE or WMP_RENDER_SIZE run silently dropped every onLoad
     error; a SCRIPT-DIAG count taken with either flag before then is void.
RESIZE <view>: <W>x<H> -> <W>x<H>, handlers=<n>
RENDER-DUMP <view>: <W>x<H>, <n> nodes, <c> commands, <h> hits, <w> widgets, <u> unresolved
RENDER-DUMP <view> FAILED <error>
     one line per view per outcome: its stats, or FAILED when the scene never built at all.
     A refused *write* is a PNG outcome and never a second RENDER-DUMP line — see W245.
ANIMATION <view>: shortestDelay=<s> bounds=<rect>
WIDGET <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> visible=<f|none>
PROBE <view>/<stableID> <kind> id=<id> frame=<f> clip=<c> z=<n> paint=<…> attrs=[…]
BITMAPS <view>: resolved=<n> missing=<space-separated paths>
EXPR <view>/<id>.<prop> #<order>: <source> -> <static> live=<live> deps=[…]
CALL <view> <path> <read|write|invoke> value=<v> <ok|INERT|UNRECOGNISED>
CALLS <view> <path> ×<n> <ok|INERT|UNRECOGNISED>
CLICK <view>@x,y hit=<id>#<stableID> kind=<k> action=<a> sticky=<b> handlers=<n>
CLICK <view>@x,y changed=[…] | command=<…> | unrecognised=[…] | MISS
CLICK <view>@x,y after: <n> commands, <n> widgets[<kind>×<n> …], <n> unresolved
DRAG <view>@x,y>x,y hit=<id>#<sid> kind=<k> slider=<b> direction=<d> min=<m> max=<M> border=<b> steps=<n>
DRAG <view>@x,y>x,y step=<i> at=<x>,<y> value=<v> drawn=<v> thumb=<rect>
DRAG <view>@x,y>x,y dragend handlers=<n> commands=[<action>=<value>,…]
DRAG <view>@x,y>x,y value <v> -> <v> follows-pointer=<yes|no|flat> thumb-travel=<px>
DRAG <view>@x,y>x,y MISS | not-a-slider — no value tracking to measure
HOVER <view>@x,y <onMouseOut|onMouseOver> <id>#<stableID> kind=<k> handlers=<n>
HOVER <view>@x,y <event> changed=[…] | [<code>] <message> | unrecognised=[…] | after: <…>
HOVER <view>@x,y inside=<id>#<stableID> — no edge
HOVER <view>@x,y MISS
APPKIT <view>: <W>x<H>@<n>x differing=<n>/<n> (<pct>) hosted=<n>/<n> outside=<n> (<pct>) max-delta=<n> blit=<n> (<pct>) blit-max-delta=<n> [worst=<rect>]
APPKIT <view>/<stableID> <kind> id=<id> frame=<rect> differing=<n> (<pct>)
APPKIT <view>: SKIPPED <why>
PNG <view>: <filename>
PNG <view> FAILED <error>   the write was refused; the view's own RENDER-DUMP line still stands
```

`APPKIT` is the only line that has run an `NSView.draw`. Everything else in this file measures the
scene; this measures the window. Two things make its numbers trustworthy and both were wrong first:

* **The baseline is a second AppKit pass with the overlays hidden, not the renderer's image.**
  `cacheDisplay` composites through the display's colour space and the renderer's context does not,
  so comparing the two directly is a colour conversion as much as a measurement — it read 6.8% of
  Corona (the control skin) as differing, and 61% of a four-colour fixture, at deltas up to 64. Two
  passes through the *same* path cancel that exactly, and the corpus-wide noise floor is then **zero**,
  not "small".
* **Only a widget that actually hosts an `NSView` explains a difference.** `WMPMainView` builds
  overlays for `playlist`, `dropdownPlaylist`, `popup`, `editBox`, `listBox` and `effects` and no
  others — a slider and a text are drawn by the renderer into the image the view blits — so a
  difference inside a *slider's* frame is a defect, not hosting, and attributing it to the widget it
  happens to sit inside would file it as expected. Keep that list in step with
  `WMPMainView.synchronizeWidgetViews`.

The rep comes back at the display's backing scale, not the view's point size, and so does the image
the app presents (`WMPMainWindowController.renderBackingScale`). Indexing a 2x rep in points reads
the top-left quarter and calls it the window; presenting a 1x image into a 2x rep diffs AppKit's
upscaler against the renderer. Both were made on the way to this line and both look exactly like a
defect in the app.

**`dispatch` prints only when the transaction actually runs.** A gated hover edge with no authored
handler returns without doing anything, and the pointer crosses a whole row of buttons on the way to
the one it wants — tracing before the gate wrote a line per crossing that said "nothing happened".
The `hover <id> -> <id>` crossing line went with it for the same reason. What this costs is the
signature that found the window-never-key defect on 2026-09-08 (*no `hover` lines at all while
`dispatch click` worked*); if that question comes back, the way to ask it is a counter or a
one-shot, not a line per pointer move.

**Three more lines were removed on 2026-09-11, and the reason is worth keeping**:
`widgets hosted=…`, `present <event> …` and `animation <view> …` were printed on every present, and
a skin repaints at its own cadence — an animated view presents 20×/s, and each present re-runs
`synchronizeWidgetViews` and the position-change transaction. Interleaved, they wrote three
identical lines forty times a second and buried every line that carried news, which is the opposite
of what a trace is for. `widgets hosted=` had earned its place once — `hosted=0` through a whole
track settled Corona's "no visualization" by saying the pane was never built — so if that question
comes up again, ask it with a line that prints when the hosted set *changes*, never one per frame.
`WIDGET` still answers the same question from the harness side.

`menu at=` prints the point a right-click landed on and every `<EFFECTS>` frame it was tested
against, which is what decides whether the visualization's own context menu opens.

`WIDGET` is the only line about the AppKit overlays — playlist, equaliser, popup, effects, video —
and they are **not in the dumped PNG at all**: the renderer draws the scene, and these are `NSView`s
hosted over it. A skin can therefore dump a perfect frame and look wrong on screen, which is exactly
what happened on 2026-09-07 (W43, W9). `visible=none` means the scene clipped the widget out; the
overlay is positioned from `frame`, so a widget with `visible=none` that still shows on screen is a
defect in the hosting, not in the scene.

`INERT` is a member that is recognised, answers, and has nothing behind it — `theme.loadString` can
only ever return the empty string, because there is no `wmploc.dll` on macOS. It gets its own word
and its own census column (`inert_calls`) because a stub that reads as working is the most expensive
bug this engine can carry; `reference/object-model.md` is the contract.

`EXPR` reports **both** evaluators: `->` is the static grammar in `WMPInitialLayoutExpression` that
the scene builder uses, and `live=` is the value the real script context produced. `live=-` with
`#-` means the live pass produced nothing for that key. A skin whose static column resolves and whose
live column is empty is not a working skin.

**`EXPR` is scoped to the dumped view, and reading it any other way is how this line lied.** WMP ids
belong to a `VIEW` and so do both evaluators — `WMPScriptViewPlan` collects the view's own subtree,
and `WMPInitialLayoutResolver` refuses a reference that leaves the view it was built for. The probe
used to walk `graph.allNodes`, so every *other* view's expressions were printed under this view's
name, asked of an evaluator that by construction cannot answer them, once per view in the skin.
Corpus-wide that manufactured **34,300 rows** reading `#-` / `live=-` against 7,700 real ones — 82%,
read for a day as an engine defect starving half the corpus — and the same collision by *name* also
credited a sibling's order number to 131 rows that were not evaluated at all, so it lied in both
directions. See `harness-history.md` § *After the cascade* for what the corrected sweep says, and
`testExpressionProbeReportsOnlyTheDumpedViewsOwnExpressions` for the check that holds it.

---

## Input and tooltips the markup authors

Two counts the census does not produce, both measured 2026-09-08, both with a command next to them.

**Nodes that author input on a kind the builder does not treat as a control** — `537` across `143`
of the 179 archives, which is what `WMPSceneBuilder.authorsInputHandler` exists for: `326` `<TEXT>`
across 69 skins, `90` `<EFFECTS>` across 81, `21` `<VIDEO>` across 21, then `stopbutton`,
`progressbar`, `prevbutton`, `playbutton` and `nextbutton` at 12-13 each — transport spellings this
engine still parses as *unknown* kinds, so they are hit targets now and carry no transport action.
`Sports` is the reason it was written: ten `<TEXT>` playlist rows whose `onmouseover` could never
fire because nothing registered them as targets.

```bash
python3 scripts/wmp_input_kinds.py
```

**Tooltips.** Measured with the markup census, whose denominator is 177 — the two repaired-header
archives `unzip` cannot open are outside it:

```bash
scripts/wmp_markup_census.sh /tmp/wmp/markup toolTip upToolTip downToolTip
```

| Attribute | Uses | Skins |
|---|---|---|
| `upToolTip` | 4,712 | 175 of 177 |
| `toolTip` | 3,749 | 174 of 177 |
| `downToolTip` | 517 | 104 of 177 |

None of them reached the screen before 2026-09-08: only widgets answered `stringForToolTip`, and a
skin's controls are `<BUTTON>`s. The tip is resolved per drawn state in `WMPSceneBuilder.toolTip` —
`downToolTip` while the control is down, `upToolTip` otherwise, plain `toolTip` behind both — and
read through the scene overrides, so a script assignment (`alx_dl.wms` writes `toolTip='Volume'`
from its slider's `onMouseUp`) wins over the authored attribute.

## The committed scripts

### `scripts/wmp_skin_census.sh <outdir> [--corpus <dir>] [--allow-dirty] [--parse-only]`

*What is the state of the corpus?* One TSV row per archive: sha256, whether it loaded, the codes it
was rejected for, encoding, view/node/script counts, findings by code, per-view node/command/hit
counts, resolved and missing artwork, the unimplemented tags and host members it demands, and the
git rev it was measured at. This is the only honest source for the reach numbers in `WMP_TASKS.md`
**for anything a view reaches on load**.

**It drives `onLoad` and nothing else, and that bounds every demand number it produces.** A member
called from an `onClick` is invisible here, so a row ranked on this alone is ranked on the subset
of the corpus that runs before the user touches anything: `view.returnToMediaCenter` counted **7**
and is authored by **162 of 180 archives** (W100), and W136's click-handler methods (`copy`,
`deleteSelected`) were ranked on the same blind spot. When a row is about a *control*, the census gives you a floor and § *Auditing one authored
control across the whole corpus* gives you the number.

`--parse-only` re-derives the TSV from a previous run's logs without paying the sweep again — it is
how a parsing change is checked against a capture that is already known-good.

**Check `render.txt` is non-empty before believing a single number out of a capture.** The script
exits **0** on a run that was killed part-way through its own `swift test`, leaving an output
directory that looks exactly like a successful one — `corpus/`, `render.txt`, `render.stderr.txt`
— with `render.txt` at zero lines and no `census.tsv`. Reproduced twice on 2026-09-11 by starting
it detached (`nohup … &`): `render.stderr.txt` ends mid-build (`[1/6] Write swift-version…`), not
after it. The script's header already warns that *a binary that will not compile* writes an empty
capture that diffs as "everything changed"; **a killed run is the same failure with a clean exit
status**, which is worse, because nothing anywhere says so. **Both corpus scripts now write
`<outdir>/INCOMPLETE` when they start and remove it only on reaching `done`** (2026-09-24);
`--parse-only` and `wmp_render_sweep.sh compare` refuse a directory that still carries it, so a
killed run is a refused capture rather than a plausible one. Anything else that reads a capture
should check for the file too. Still run it in the foreground: the marker catches a killed run, it
does not prevent one. A capture from before 2026-09-24 has no marker either way — for one of those,
`wc -l <outdir>/render.txt` and the presence of `census.tsv` are still the check.

It also writes two **ranked promotion files**, every run, and names the worst rows on stdout where
the person who ran it is already looking. Both exist because a number the instrument already
measured and nobody ranked is worse than one it cannot see:

* `starved.tsv` — every view by `unresolved / (nodes + unresolved)`, plus `hits == 0` and
  `commands == 0`. **The rule has to be a ratio, not a count** (W70): `unresolved > 0` is true of
  most views in the corpus, so a raw count ranks nothing. Corona — the skin the reporter called
  working — carries 8 unresolved against 66 nodes on `vPlayer`; ALXMorph carries 15 against 15 and
  draws a shell nothing reacts to. A promoted view is one worth dumping and looking at, never a
  defect on its own: `hits == 0` is correct for a view that is pure artwork.
* `appkit.tsv` — every hosted view by how much of the window an AppKit overlay painted **outside**
  any widget frame (W71), with the magnitude of the worst pixel and the separate blit comparison.
  This is the class that produced W43-W46, and it was invisible to every other instrument here.

### `scripts/wmp_markup_census.sh <outdir> [--corpus <dir>] [name ...]`

*How many skins would this element or attribute reach?* One row per name: uses, skins, and the
denominator it measured. It reads the `.wms` files straight out of the archives rather than through
the engine, so it measures **authored demand** and nothing about the result.

It exists because nothing else can see the Class A case that matters most here: **an attribute the
graph parses and the engine then ignores.** That is not an unknown tag, not an unknown member and
not a diagnostic — it is markup that loads cleanly, reports clean, and changes nothing on screen.
Ranking Phase 5's drawing work needed exactly this number, and `fontFace` is the example that pays
for the script: 109 skins author it, 21 author `fontType`, and the builder read only `fontType`.

Two traps it enforces, both of which produced a confident wrong answer first:

- **`grep` goes silent on these files.** A `.wms` is usually UTF-16 and carries bytes `grep` calls
  binary, and a binary file matched with `-o` prints **nothing at all**. The first run of this census
  returned a full table of zeros that read exactly like "the corpus never uses this". Every file is
  stripped to ASCII before it is counted, and `-a` is passed anyway. This generalizes: any ad-hoc
  scan of `.wms` text needs both.
- **A tag spans many lines.** Corpus markup routinely opens `<SLIDER` and closes `>` six lines
  later, so a per-line scan finds neither the attributes nor the tag. Newlines fold to spaces first.

Its denominator is smaller than the sweep's: `unzip` cannot open the two archives whose local header
signature is overwritten (`WMPArchiveHeaderRepair` handles those and `unzip` does not), so a count
here is short by at most two skins and never long. It prints which ones it dropped.

### `scripts/wms_grep.py [-i] [-l | -c] [--ext wms,js] [--corpus <dir>] <regex>`

*Which archives' markup or script says this?* A regex over every `.wms`/`.js` entry, decoded the way
`WMPTextDecoder` reads it, with the header repair `zipfile` needs for the two `01 00 01 00`
archives and the exclusions applied. Default output is `archive/entry:line: text`; `-l` lists
archives, `-c` counts per archive. It **always** ends with a stderr line giving matches, entries,
archives matched *of archives scanned*, the encoding breakdown, and anything unreadable — a count
without its denominator is what it exists to replace. Checked 2026-09-24 against W266's scan
(`event.keycode =` → the same 3 archives, and it also read the two `.wms` that scan could not) and
against `wmp_markup_census.sh` (`<EQUALIZERSETTINGS` → 163 of 179 against 161 of 177, the difference
being exactly the two archives `unzip` cannot open). Use `wmp_markup_census.sh` for a tag or
attribute tally; use this for everything else — a member name, a handler body, a literal.

The decoding, header repair and exclusion reading live in `scripts/wmp_corpus.py`, and
`wmp_handler_scope_census.py` imports them from there; a new Python corpus scan should too.

### `scripts/wmp_control_audit.py [--render <render.txt>] [--sample N] [--skin <archive>] [-v] <member>`

*Which authored controls reach this member, and where is each one clicked?* § *Auditing one authored
control across the whole corpus* as one command (W267). Steps 1–2 need nothing but the corpus and
take ~2 s: every handler attribute resolved through the skin's functions to three levels, with the
counts by tag, handler, tooltip and "in the first `<VIEW>`", and the encoding breakdown as
calibration. Steps 3–5 need a probe capture, which **the census does not contain** — it never sets
`WMP_RENDER_PROBE` — so without `--render` the script prints the sweep that makes one (~35 s for the
corpus once the tests are built; a directory handed to `WMP_SKIN` must hold copies — the sweep
skips symlinks and reports "No .wmz archives"). `-v` prints one row per control with its point and where the point
came from; `--sample N` prints the `WMP_RENDER_CLICK` + `WMP_CALL_TRACE=1` runs.

**Trust the point by its source column.** Checked 2026-09-25 by clicking every located W100 control
(`returnToMediaCenter`, 199 controls in 165 of 179 archives — the raw `wms_grep.py` count, exactly):

| source | hit the control |
|---|---|
| `probe` — a drawn node's frame centre | 55 of 55 |
| `mapping` — a drawn group's bitmap, median pixel of the colour | 74 of 76 |
| `authored`, `authored-mapping` — the authored `left`/`top` chain | **26 of 65** |
| `none (<why>)` — colour absent from the bitmap, or the bitmap absent from the archive | 3, all real skin defects |

The authored fallback is what step 4 prescribes and it is right less than half the time: it cannot
see alignment, script moves, hidden groups or views the sweep never dumps. The script prints it
flagged unverified and never samples it. The two `mapping` misses are `digitaldj` (its script
disables the transport until the splash is dismissed) and `Plus!_The_Bionic_Dot`, whose
`main_blue_set_map.png` holds `#0066FF` where the click lands and whose group still reports
`unmapped-pixel` — unexplained as of this writing. **W100's own 162/180 is not reproducible**: five
archives joined the corpus after it closed (`Ovoid` and `Raptor` author the button) and `Darkling`
(one control) is now excluded.

### `scripts/png_diff.py <a> <b>` / `<base-dir> <curr-dir> [--summary] [--top N]`

*Which way did this image change?* Per differing pair: `lsb` (maxdelta ≤ 1), `recolour` (alpha band
identical — same silhouette), `moved` (same drawn-pixel count, alpha changed), `gained`/`lost`
(drawn pixels, alpha > 8, went up or down), `size`. It compares every band separately, so neither
Pillow alpha trap below applies. Tree mode prints the same totals as `compare`; `--summary` adds
per-skin counts and lists only `lost`, `gained` and `size`. `wmp_render_sweep.sh compare --summary`
calls it. Exits 1 when anything differs.

### `scripts/baseline_worktree.sh [<dir>] [<rev>]`

The baseline for any before/after pair — see § *A baseline worktree needs the vendored frameworks
linked in*.

### `scripts/wmp_corpus_exclusions.txt`

The blacklist both scripts read before anything measures. Each script links the in-scope archives
into `<outdir>/corpus` (a hard link, because the harness enumerates with `isRegularFile` and a
symlink is not one) and sweeps *that*, so an excluded skin cannot reach a log, a PNG, or a column —
filtering afterwards would still let its diagnostics rank work. Both print what they dropped and the
count they actually measured; the corpus denominator in `WMP_TASKS.md` is that number, not the
directory listing.

A skin belongs here when no work in this engine changes its outcome — not when it is merely broken.
The standing entry is `Darkling.wmz`, authored against WMP's Party Mode host (`PartyMode.*`), which
this player has no equivalent of; its own `OnLoad` catches the missing host and draws a "designed for
Party Mode" panel, exactly as real WMP does outside Party Mode. Record the reason in the file next to
the entry, and treat removing a line as a decision.

### `python3 scripts/wmp_slider_drag_census.py [--corpus <dir>]`

The three W256 populations in one pass, over the installed corpus minus the exclusions:

- **A** — elements authoring a handler and **no `id`** (1,667 nodes / 101 archives), and the
  `value_onchange` subset (70 / 35). These are the handlers that used to run with no bound `value`
  and no element scope; the defect has no signature but the *argument* a host command carries.
- **B** — sliders painting a **thumb and no track** (448 / 41), whose hit region used to be the
  knob. `<CUSTOMSLIDER>` is excluded: its `positionImage` is the authority on its region (W150).
- **C** — archives whose `<EQUALIZERSETTINGS>` is named something other than `eq` (7).

It reads each `.wms` out of its archive rather than grepping it, which is the whole reason it is
committed — see § *A corpus number taken with `grep` is not a corpus number* above. Re-run it before
quoting any of the four numbers.

### `python3 scripts/wmp_implicit_key.py [--corpus <dir>] [--color RRGGBB] [--tsv <file>] [--alpha only|none|any]`

*How much artwork relies on WMP's implicit transparency colour?* Counts drawn sprites that hold
opaque `#FF00FF` pixels and hang off a node declaring neither `transparencyColor` nor
`clippingColor` — the W78 class, and the measurement that had to exist before anything defaulted a
key engine-wide. It reads `.wms` and artwork straight out of the archives, so it measures authored
demand, never a render result.

Measured 2026-09-08 over the 179-archive corpus: **603 node/attribute references across 80 skins and
499 distinct sprites**, of 22,649 drawn artwork references of which 8,833 declare a key themselves.
`--tsv` writes every row, sorted by how many key pixels the sprite holds, which is the order to open
them in. What it does *not* count is a mapping/clipping/position image — read for its colours, never
blitted, and an implicit key there would delete a mapping colour from its own map.

**`--alpha only|none|any` splits the class by whether the sprite authored an alpha channel, and that
split is W78a.** W78 shipped keying only `none` (527 refs / 66 skins / 437 sprites), on the reasoning
that a sprite carrying alpha has already said what is see-through. `--alpha only` measures what that
left behind — **76 references across 21 skins and 62 sprites** — and the falsifying check is not the
count but the pairing: **11 of those nodes hold two states of the same button, one exported without
an alpha channel and one with, with identical magenta counts** (`Half-Life_2`
`m_pause_no.png`/`m_pause_hov.gif`, both 1,394). Under the veto the normal state keyed and the hover
state did not, so the button turned magenta under the pointer. The engine now keys `any`, which is
this script's default so that what it counts is what the engine does. A `key_pixels` count is of
**opaque** key pixels: a partially transparent one is composited paint, and the corpus holds none.

`WoW/mainView`, the residual's headline at 3.5%, was the same thing seen through a `CUSTOMSLIDER`:
`volume_1.png` is a 31-frame filmstrip against an 86x84 `volume_map.png`, and every frame carries the
same flat magenta wedge beside a genuinely antialiased knob. The crop was already correct; only the
wedge was paint that should not have been.

**After the veto came off, the corpus residual is 878 opaque magenta pixels across 2 of 545 views,
and neither is an implicit-key case.** `portals/mode1` (829 px, 0.38%) is a `BUTTONGROUP` declaring
`transparencyColor="#000000"` whose sheet's magenta filler is blitted whole instead of drawn through
its mapping — that is W48(a). `Plus! Pulsar/mainView` (49 px, 0.04%) is a `<button
id="shutterButton">` declaring `transparencyColor="#ffffff"`, so the implicit key correctly stands
aside and real WMP draws the same corner.

**One corpus view is nondeterministic and a PNG-diff sweep will flag it forever.**
`Scooby-Doo_2/infoView` picks its character at random in `scooby.js`: three runs of one binary give
two hashes. Do not read it as collateral from a change.

The companion number, from the markup census's own attribute counts: **4,979 of the 6,076
`transparencyColor` declarations in the corpus (82%, 142 skins) are `#ff00ff`.** That is why the
default is that colour and not another.

### `python3 scripts/wmp_handler_scope_census.py [json-out]`

**What a handler names without qualifying it**, over the installed corpus: every unqualified *call*
of an element-method name — resolved through the skin's own functions to three levels — and every
unqualified *property* reference that names an attribute the handler's own element authored, split
into reads and writes. It is the instrument W216 was measured with (31 calls / 20 archives; 255
reads + 249 writes / 100 archives, 2026-09-21).

**The census cannot answer this and neither can a sweep**: `wmp_skin_census.sh` drives `onLoad`,
this demand is in `onClick`, and that is the blind spot § *Auditing one authored control across the
whole corpus* exists for. So it reads the decoded script text directly, the way `WMPTextDecoder`
does, and **repairs the `01 00 01 00` local file headers the way `WMPArchiveHeaderRepair` does** —
without that, `Need_for_Speed_Underground` and `SplinterCellWMPSkin` are dropped on a `BadZipFile`
and a scan that does not print what it skipped reads as a clean corpus. It prints the **encoding
breakdown as calibration**: a correct run over 184 archives reproduces 158 UTF-16-BOM / 146 cp1252 /
89 UTF-8 / 9 UTF-8-BOM, and a run that does not has decoded something differently from the engine.

**It nets out what the engine already binds** — `value`, and the changing attribute inside an
`<attribute>_onchange` — so the count is the residue a handler cannot reach, not the population of
bare names. Extending it to another class of name means changing `VOCAB` or `is_handler`, both at
the top of the file.

### `scripts/wmp_render_sweep.sh capture|compare`

*Did my change move anything?* `capture` writes the invariant lines **and** every PNG; `compare`
diffs both. Every engine-wide change from Phase 2 onward passes through this. Each changed invariant
line is prefixed with the `[skin]` it belongs to, and the `DIFFER` line names the changed skins —
a `RENDER-DUMP` line carries only a view id. `compare --summary` replaces the per-image list with
`png_diff.py`'s classes.

```bash
scripts/baseline_worktree.sh ../nullplayer-base HEAD
(cd ../nullplayer-base && scripts/wmp_render_sweep.sh capture /tmp/wmp-sweep/base)   # + --allow-dirty if the script says so
# …make the change…
scripts/wmp_render_sweep.sh capture  /tmp/wmp-sweep/curr
scripts/wmp_render_sweep.sh compare  /tmp/wmp-sweep/base /tmp/wmp-sweep/curr
```

**Never capture the baseline with `git stash`** — it relinks `.build` under the user's running app.

**A before/after `wmp_skin_census.sh` pair *is* a render sweep — do not run both.** The census
writes every PNG to `<outdir>/png/<skin>/` with every probe on, so comparing the two `png/` trees by
`sha256` answers the same question `compare` answers, off captures you already paid for. W128 needed
the `UNRECOGNISED` tally *and* proof that nothing moved; one census pair gave both, and a second pair
of sweeps would have been ~10 minutes of rebuild for a duplicate answer. Use `wmp_render_sweep.sh`
when the pixels are the whole question; use the census when you also need the counts.

**A fresh worktree cannot build as-is** — `Frameworks/` is only partly in git — which is what
`scripts/baseline_worktree.sh` exists for; § *A baseline worktree needs the vendored frameworks
linked in* has the traps. The script ends on `git status -- Sources Tests scripts` being clean, the
check that the baseline really is the rev asked for. The manual version of it was confirmed working
2026-09-11 for W128's before/after census — the W76 note in the archive records a pixel comparison
that could not run for exactly this reason.

---

## Traps the scripts enforce, inherited rather than re-earned

- **A sweep is a build — freeze the tree.** `capture` and the census refuse a dirty tree without
  `--allow-dirty`. A binary that will not compile writes an *empty* capture that diffs as
  "everything changed". Never run either while the user may be building: SwiftPM lock contention
  stalls both.
- **Redirect to a file and grep the file.** Piping a long `swift test` into a filter drops lines
  silently. stderr gets its own file.
- **Every harness line is one `write(2)`, never `print`.** `WMPHarnessOutput.emit` takes a lock,
  flushes stdio so XCTest's own lines stay ordered against ours, and writes the line and its
  terminator in a single unbuffered call. It exists because `print` did not: in the 180-archive
  sweep at rev `171cf89a` a `CALL` line and the `SKIN` line opening the next archive landed inside
  one another (`CALL vSKIN Windows_XP_Media_Center_Edition.wmz`) and the **5,087 bytes** that should
  have followed — the rest of that skin's trace, two `PNG` lines and a `RENDER-DUMP` — never reached
  the file. It was byte-identical across two full sweeps and did not reproduce on a two-archive
  corpus, so it was the buffered stream, not the content: what is lost is whatever `stdout` was
  holding. Removing the buffer removes the loss. Do not reintroduce `print` here.
- **The damage detectors stay, and one of them is arithmetic.** A splice is only the *visible* half
  of a lost write, and the invisible half is the common one: that same run lost three blocks and the
  prefix scan saw **one**, because the splice consumes the record prefix that would have betrayed
  it. So both scripts also check each loaded block's view count against the `views=` its own
  `LOAD` line declares (a view that fails to *build* still emits `RENDER-DUMP <view> FAILED`), and
  flag a second `LOAD` inside one block. **Count distinct view ids, not lines.** A view that lays
  out and then fails downstream can emit *two* lines about itself — so when W32 admitted `Nautical`
  (one view, laid out, then `WMP0015` on `vol_slider.bmp`) the arithmetic read 2 against `views=1`
  and called the block damaged when nothing had been lost. Reading a live defect as a lost log block
  is this check's own failure mode, pointed the wrong way, and it survived a solo re-run — which is
  what distinguishes it from a real splice. **The census was fixed at W32 and the sweep was not,
  which cost a quarter of the corpus for a month**: the sweep still counted lines, and a refused PNG
  write printed a second `RENDER-DUMP … FAILED`, so **48 of 184 archives** were flagged until W245
  closed both halves on 2026-09-20 — a refused write is now a `PNG <view> FAILED` line, and the
  sweep counts ids. `WMPDumpLineAccountingTests` pins the emitter, the id counting and the
  short-block case, running the script's own `PYDAMAGED` block rather than a copy of it. Damaged skins are listed in `damaged.txt`, get a row carrying
  identity and nothing else, and are left out of the diff. Re-run one alone with
  `--corpus <a directory holding just that archive>`. Their PNGs are unaffected and still compare.
- **Compare pixels, not alpha.** Pillow 9.5 made `getbbox()` on an RGBA image consider the alpha
  channel alone, and every dump carries alpha, so a change that moved a visible control but left
  alpha untouched came back "identical" across 590 `.wal` images. `alpha_only=False` in
  `wmp_render_sweep.sh` is load-bearing, not tidiness.
- **A `maxdelta` of 1** is an LSB rounding difference, not a regression. The script reports the
  number; a human reads it.
- **The alpha trap has a second door: `ImageChops.difference` on RGBA.** `wmp_render_sweep.sh`
  passes `alpha_only=False` and is safe, but an ad-hoc Pillow comparison written beside it is not:
  `getbbox()` on the *difference image* looks at alpha alone for the same reason, so a colour-only
  change reports "identical". During the Phase 5 sweep that scan found 3 changed images where the
  script found 198. Split the bands: `any(band.getbbox() for band in diff.split())` — or use
  `scripts/png_diff.py`, which does, rather than writing the comparison again.
- **`SCRIPT inline:` used to be emitted in dictionary order and was not stable between runs** — the
  same archive reported the same handler tally in a different order each time (~19 lines per
  capture), inflating the invariants diff with churn that was not a change (W64). **Fixed:**
  `WMPRenderDumpTests.tally` sorts by count and breaks ties on the name, because Swift randomizes
  hash order per process. If reordered tallies ever reappear in a `compare`, that tie-break has
  regressed — read the diff by what the `RENDER-DUMP`, `BITMAPS` and `LOAD` lines say meanwhile.
- **A detector's own false positives cost more than the thing it detects.** The `views=` arithmetic
  silently dropped **48 of 184 archives** from every invariants comparison for a month (W245), and
  the damage it was reporting was not real. Two tells were on the page the whole time and are worth
  reusing on any run-to-run check: **an identical "damaged" set across two runs** is arithmetic, not
  interleaving, because interleaving is not deterministic; and **an exact match between a flagged
  count and an explained one** — 76 flagged lines against 76 known-refused `WMP0035` writes — names
  the cause outright. **Re-measured after the fix, over three consecutive 184-archive captures: 0
  damaged, byte-identical invariants each time, and the prefix-scan arm fired on nothing.** So the
  interleaving these checks were written for is *unfired here*, not disproven — the 180-archive run
  that lost three blocks predates this tree and the buffered `print` that caused it is gone. Both
  arms stay: a hand-deleted `RENDER-DUMP` line is still caught, which is the test that keeps them
  honest.
- **A large image diff is read by looking, and by which way it went.** 198 of 545 changed in the
  Phase 5 sweep. Counting the *drawn* (alpha > 8) pixels in each pair and sorting sorts the whole
  set into "changed colour within the same silhouette" and "lost or gained content", and the second
  list was one skin long — which is the list worth opening. **`compare --summary` does this sort**
  (via `scripts/png_diff.py`): a class per image and only the lost, gained and resized ones listed.

---

## Driving the GUI yourself: two traps that produced wrong conclusions (2026-09-10)

Both cost a stated, confident, wrong answer during W102's live QA. Neither is about the app.

**A synthetic click must set `mouseEventClickState`, or it is not a click.** A `CGEvent` pair of
`.leftMouseDown`/`.leftMouseUp` posted without `e.setIntegerValueField(.mouseEventClickState, 1)`
arrives with `clickCount == 0`. The pointer moves, the hover artwork follows it, `mouseDown` may
even dispatch — and no click is ever synthesised. This was read as *"the skin's play button is dead"*
when it was the tool. **Prove the input arrives before concluding the app ignored it**: click
something with a known trace (`INPUT action <transport>` on any transport button) and see the line
appear. Same rule as every other instrument on this page. A double-click additionally needs
`clickState` 1 then 2 on consecutive down/up pairs.

**A synthetic right-click does not open a contextual menu at all, `clickState` or not.** It produced
no menu and no `INPUT menu` line against `WMPMainView.menu(for:)` — a method a *real* right-click
drives correctly, as the reporter confirmed the same day by using the subtitle menu it serves. That
absence was written up as W125, "no right-click on a `.wmz` reaches `menu(for:)`", and withdrawn:
**the engine defect did not exist.** `INPUT menu` is a fine instrument for a real pointer and worth
nothing under a posted event. Verify menus by hand, or by asking the reporter.

**`screencapture -R <region>` photographs the screen, not the window** — including whatever is on
top of it, which during agent-driven QA is routinely your own terminal. Use `screencapture -l
<windowid>` (id from `CGWindowListCopyWindowInfo`) to capture a window's **own** content regardless
of occlusion. That single distinction is what settled the "video goes black" defect: the window's own
content was the movie, playing, so nothing was wrong with decoding or sizing and the whole question
became compositing. Pair it with the front-to-back order from
`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])` — **pass
`.optionOnScreenOnly`**, because `.optionAll` includes offscreen windows and its ordering means
nothing; reading order out of an `.optionAll` list said the video was in front when it was behind. `winhelper capture` is the checked form of
`-l`, and `winhelper windows` already passes `.optionOnScreenOnly`.

**A parked video window is a child window, so two invariants are free and worth asserting**: a child
is always drawn above its parent, and it moves with its parent atomically. If the picture is behind
the skin, or trails a drag, the parent-child link is gone — do not go looking at VLC. See
`reference/rendering.md` § the `.wmz` video loan.

## Why an instrument gap outranks a skin-side defect

**Manual testing does not scale to this corpus.** 179 skins times sliders, drawers, drags and
animation is not a human-scale job, and Phase 5 shipped its AppKit half unmeasured for exactly that
reason. So **a genuine gap in instrument reach ranks above a skin-side defect when one is found** —
and a probe that reports work already done is a gap in reach exactly as a missing probe is. That is
how a row is ranked in `WMP_TASKS.md`: an instrument gap goes above the skin-side rows, not among them.

## Numbers that are void, and why

A stale number copied forward reads as fresh, and this corpus has produced five classes of number
that must not be scaled, quoted or re-derived. Re-measure instead.

* **Anything measured against the 14-skin denominator.** The corpus grew to 180 on 2026-09-07 and
  none of the earlier numbers were rewritten in place. A count without an archive stamp has not been
  re-measured; re-measure it rather than scaling it.
* **Anything captured before rev `61f8955a`.** The instrument dropped three blocks of its own output
  (W35), so an earlier count is short by an unknown amount rather than merely stale. The distinct-name
  count of the `UNKNOWN event` vocabulary is the visible symptom: **36 blocks were damaged in both
  captures**, so the *edges* of that vocabulary move between runs and the uses figure is the one to
  quote.
* **Any `COMPAT` / `UNKNOWN tag` number taken before 2026-09-19.** W215 closed that day: the corpus's
  unimplemented-tag demand read **1,197 uses and is 258**. Those counts are not merely stale, they
  are *inflated*, and the tags they inflated with were the transport pairs, `customslider` and
  `effects`. The member half of that row did not close and is the larger number now; see the archive.
* **Any view count of 579, 574, 567, 515, 508, 506 or 482.** Re-measured 2026-09-09 over 179
  archives.
* **Any coverage claim made from a sweep `compare` before 2026-09-20.** W245 closed that day: the
  damage detector was flagging **48 of 184 archives** as damaged on every run and `compare` leaves a
  damaged skin's lines out, so an invariants diff from before it saw three quarters of the corpus.
  The PNG comparison was never affected — only the lines.
* **`WMP0035` is harness noise, not a defect, and since W245 it is not a `RENDER-DUMP` line
  either.** Re-measured 2026-09-09: **62 `RENDER-DUMP … FAILED [WMP0035]`** across the 179-archive
  sweep, and every one is a view with no window — `controlView` ×25, `previewView` ×16,
  `mediaSwitcherView` ×12, `view-2` ×3, `versionView` ×3, and
  `vGhost`/`vGhostAutoDetect`/`playview` ×1. **The current number is 76 over 184 archives**
  (2026-09-20), and they print as **`PNG <view> FAILED [WMP0035]`**: the view reports its stats on
  its own `RENDER-DUMP` line and the refused *write* is a `PNG` outcome. Grep the old prefix and you
  will now count zero of them, which is a renamed line rather than a fixed class. That is the windowless class `SKILL.md` describes, whose
  honest size is `0x0` and which `WMPRenderer` correctly refuses; the 25 matches the 25 archives that
  author a `controlView` exactly. A FAILED line on a view that *does* have a canvas is still worth
  chasing. **`WMP0032` and `WMP0033` are both zero corpus-wide** (2026-09-09), so neither a layout
  rejection nor a decode failure can rank anything any more.

**There are no loading rejections left in the corpus.** Load level is a constant, so it cannot rank
anything: every open defect is a rendering or runtime one, and only a dumped PNG or a `SCRIPT-DIAG`
line can see one. A row whose evidence is a census column is by that fact measuring structure, not
result.

### What the ranking files rank, and what they do not

`starved.tsv` and `appkit.tsv` are produced by the census itself rather than by hand, and they
outrank any prose that disagrees. Measured 2026-09-08 over 179 archives and **607 views**: 41 starved
views across 36 skins, 79 with no hit target across 49, 75 drawing nothing across 45, and **two**
views painting outside a widget frame. **That last number is now zero** — both were `Revert`, both
closed 2026-09-19 as W74, re-measured over 184 archives / 629 views. `appkit.tsv` ranks nothing until
a new archive lands.

**`starved.tsv` ranks declared-but-unresolved nodes, not missing pixels, and the two are not the same
view.** Its top rows were opened on 2026-09-08: `Cablemusic/mainview` (ratio 0.64, 63 unresolved)
draws a nearly complete player, and `ALXMorph/mainView` draws its whole shell. A high ratio ranks a
view as *worth dumping*; only the PNG says whether anything is missing. **Dump the view before taking
the row.** The same session ruled out the explanation everyone reaches for first: geometry
expressions. Corpus-wide **7,569 of 7,569** reach the live evaluator, and `Cablemusic/mainview`
declares none at all — see `harness-history.md` § *After the cascade*.

**"Draws nothing" counts an authored blank the same as a starved one, and closing W75 moved it the
wrong way on purpose.** It was 65 views / 37 skins until a scripted `backgroundImage` started
reaching the scene; ten `mediaSwitcherView`s then began obeying their own `view.backgroundImage = ""`
collapse before redirecting, and a view that correctly draws nothing is indistinguishable from a
starved one in this tally. **Settle a `0 commands` view by reading its PNG before opening its
markup**, exactly as with `starved.tsv`.

## Proving the instrument

*When a probe reports nothing, check the probe can see the thing at all.* Three `.wal` harness blind
spots each made a real defect look absent. Four checks run on every plain `swift test`
(`WMPRenderDumpTests`) and are the reason the corresponding sweep columns can be believed:

| Test | Proves |
|---|---|
| `testRenderBitmapsProbeReportsAMissingAsset` | `BITMAPS` names a deliberately renamed asset — the Class C detector actually notices an absence |
| `testRenderProbeReportsResolvedFramesForEveryDrawnNode` | `PROBE` reports the frame a node was *drawn at*, not the one it was authored with |
| `testExpressionProbeReportsSourceAndResolvedValue` | `EXPR` reports both the source text and the value it resolved to |
| `testExpressionProbeReportsOnlyTheDumpedViewsOwnExpressions` | `EXPR` answers for the dumped view **and no other** — a two-view skin reports one row per view. Without it the probe asked one view's evaluator about another view's nodes and printed the refusal as a defect, 34,300 times |
| `testUprightCropColorKeyNestedClipZOrderAndBackingScale` | the renderer's own pixels, at 1× and 2× — the check that nothing else in this table substitutes for |
| `testEmitsEveryLineWholeUnderConcurrentWriters` | eight concurrent writers and 9 KB lines all arrive whole and exactly once — the emitter cannot splice or drop a measurement |
| `testAppKitProbeSeesAnOverlayAndReportsNothingWithoutOne` | `APPKIT` in both directions: a scene with nothing hosted over it diffs to **exactly zero**, and a scene carrying a `PLAYLIST` diffs inside that widget's frame and nowhere else. Without the first half, "no defect" and "blind instrument" print the same line |

`compare` was checked the same way on 2026-09-07: a one-pixel **colour-only** change (alpha
untouched) to one dumped PNG and a one-character change to one invariant line, each reported.

**Measuring an over-keyed artwork: key each bitmap against its own declared colour (W169).** The
instrument that found the largest defect this engine has had was not a probe flag and not the sweep.
For every node declaring both a `clippingImage` and a `clippingColor`, decode its artwork, count the
pixels matching that colour at the *format's* tolerance (64 components for a JPEG,
`WMPColorKey.jpegComponentTolerance`; exact otherwise), and report the share. It ranks the class in
one pass: `Plus! Plasma Ball/eq_panel_normal.jpg` 85.7%, `Plus! HueShifter/hueshifter_top.bmp` 76%,
`TDK/info_bg.jpg` 52.1%, `Plus! SlimLine/perfect_body_normal.jpg` 47.5%, `elvis/elvis_tray.jpg` 39%,
`Plus! Hard Boiled/Egg_Body_Normal.jpg` 27%. **A render dump shows the hole and names nothing**, and
the hole reads as bad artwork or a bad upscale — W160 spent a phase on the second reading. Reach for
this shape whenever a skin looks *degraded* rather than *misplaced*: ask what the engine is deleting
before asking how well it is resampling.

**Two capture traps, both paid for on 2026-09-14.**

* **A 1x render dump is not evidence about Retina sharpness.** The sweep captures at 1x by design,
  so a dump posted beside a reporter's 2x window capture is two different scales compared as if they
  were one — it sent a whole round of this report down a resampling path that had nothing wrong with
  it. For anything about crispness, capture the *same window frame* at 2x before and after, from a
  baseline built in a worktree (`scripts/baseline_worktree.sh`). `plus-family.md` says "never from a 1x render dump" and it means it.
* **`first process whose name is "NullPlayer"` picks the wrong window when two are running.** The
  user's own build is usually up, both restore the same window frame, and three captures in a row
  came back showing the stale one. Get the pid (`pgrep -n -f "uiMode wmp"`), then raise and query by
  `unix id`: `tell application "System Events" to set frontmost of (first process whose unix id is
  <pid>) to true`, read `{position, size}` of its `window 1`, and `screencapture -o -x -R` that rect.
  (`winhelper raise <pid>` and `winhelper capture <id> --pid <pid>` now do both, checked.)
  A bare-binary worktree build also needs `VLCKit.framework` and the vendored dylibs symlinked into
  `.build/arm64-apple-macosx/debug/` beside the binary, or dyld kills it on launch.

**Measuring a transparency key: read the keys out of the markup.** The class W8 counted is scored by
scanning every dumped PNG for *opaque* pixels holding a key colour and reporting any view over 5% of
its area — a census column cannot see it, because a view that draws its key is structurally perfect.
The trap is assuming which colour that is. A magenta-only scan gave 23 views across 21 skins; adding
`#FF0000` gave 37 across 34, with 11 views pure red and no magenta at all. Neither is the rule.
**Score against the set of colours each skin's own `.wms` declares** — `clippingColor` and
`transparencyColor`, both of which a single node commonly carries with *different* values — and
never against a hard-coded palette. Closing W8 under that rule leaves **28 views across 26 skins at
or above 5%**, and every one of them is now a different defect (see W48): artwork whose flat colour
is keyed nowhere in the markup, or a `BUTTONGROUP` blitting its whole sheet.

**Proving `WMP_RENDER_CLOCK` itself.** It was checked the way the table above demands, before any
claim was made from it: `Xbox Live Skin` (whose `intro_anim.gif` is 145 frames) dumped at 0, 1.5 and
3 seconds gives three different images — 4,475 pixels change between the first two and 3,917 between
the second two — and the logo visibly moves. A flag that reported the same PNG three times would
have looked exactly like a working one on the `ANIMATION` line alone.

**Proving the drag probe.** Same rule, and its negative answers are reachable: a drag along Corona's
horizontal volume slider (`vPlayer@415,318>430,318>450,318>475,318`) gives `value 0 -> 100
follows-pointer=yes thumb-travel=48`, and its vertical `eq1` (`286,250>286,230>286,200`) gives
`-14 -> 14 follows-pointer=yes thumb-travel=34` — both axes, value and drawn thumb tracking
together. A drag that never leaves its start point reports `follows-pointer=flat thumb-travel=0`,
and one that starts on a button reports `not-a-slider`, so a mis-aimed probe reads as mis-aimed
rather than as a passing slider. The handler lookup goes through
`WMPMainWindowController.handlers(in:event:…)` — **the app's own matcher, never a second one**: 175
of 179 archives author `value_onchange` rather than `onChange`, and a private lookup here would
report every one of those sliders as having no handler.

**Three things a clean sweep does not prove.** It measures the default state and nothing else — not a
tab, a setting, a drag, a hover, or anything driven by live playback. A structural probe is not a
picture: a node existing says nothing about where it is drawn. And **a correct dumped frame is not a
correct window**: the AppKit overlays, the window's shape and its shadow, and every repaint decision
live outside the renderer. On 2026-09-07 the headless `vPlayer` and `viewTiny` frames were correct in
every state tested while the live app showed a dark box the size of the window, drawers that were
never erased, and a black panel during playback. Only the reporter driving the app found any of them.

`WMP_RENDER_APPKIT` (W71) closes the *overlay* part of that third gap and none of the rest. Window
shape and shadow live in the window server and stay a short, genuinely manual list; so do hover, a
tab, a setting and live playback.

**The playback half is instrumented and the rest is not.** `WMP_RENDER_HOST` seeds a playing host
for a whole sweep and `NULLPLAYER_PLAY` starts a live debug launch on a track — that pair found W119
and W120, two defects in the one state every transport readout in the corpus is authored for and
that no capture had ever entered. **Read the `HOST` line of a capture before anything else in it.**
The AppKit overlay class is now measured and closed (545 hosted views, two defects, both W74, fixed
2026-09-19) and every slider in the corpus is drivable. What no sweep says anything about is still a
tab, a setting, a hover, a drawer, the window's shape and its shadow, and anything driven by live
playback; W69's flicker is in that remainder, which is why it needs its own instrumentation rather
than another sweep.

*(This paragraph and the one above it are what `WMP_TASKS.md`'s W73 carried as a backlog row. It was
moved to `LOW_QUALITY_TASKS.md` on 2026-09-19 because it was a permanently-open caveat rather than a
unit of work — the caveat is true, and this is where it belongs.)*

---

## Past measurements

The dated corpus measurements — what each phase and each class closure measured, rev by rev, from
*What the harness measured on 2026-09-07* to *The transport audit* — are in
[harness-history.md](harness-history.md). They are the baseline a later claim is checked against,
not instructions; read the one a backlog row or a dossier cites.
