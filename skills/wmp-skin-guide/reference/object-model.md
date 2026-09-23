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

## What a property read answers, and who wins

Three rules, each of which was a live defect first:

1. **An element answers the geometry it is *drawn* at.** Every transaction is handed
   `WMPScene.scriptGeometry` — the local frame of every node the last scene resolved — and element
   state is synced from it before anything runs. WMP's `element.height` includes a height that came
   from background artwork or an alignment stretch, and a script tests exactly that: Corona's
   `ResizeY` animates `svVideo` to 0 and **gives up on the first tick if it reads 0 to begin with**,
   which is what an authored-attributes-only model reports for an element sized by its bitmap.
2. **A script value outranks the markup.** `visible` is resolved from the override before the
   authored attribute — Corona's `SetPane` switches its video and visualization panes purely by
   writing `vid.visible` / `vis.visible`, and a builder reading only markup draws whichever the
   author left on.
3. **A script value outranks the artwork's natural size.** The intrinsic size of a background bitmap
   fills in an *unstated* dimension; it never overwrites one the skin computed. It did, and every
   rebuild stamped 241 px back over the height the script had just set.
4. **Artwork is a scripted property like any other, and the view root is not an exception.**
   `WMPSceneBuilder.resolveResource` used to read the authored attribute alone, so images were the
   single property class the override path skipped while geometry, colours, slider metrics and text
   all went through it (W75). `Alienware Invader` hides its whole player behind a 568-frame intro
   whose every tick is `mainBack.backgroundImage = "png24/intro_anim_f<N>.png"`, and its `mainView`
   drew **nothing at all** until the override was consulted. Three rules the fix is made of, and each
   is a way of getting it wrong:
   - The override carries an **authored path string**, so it resolves through
     `archive.resolve(_:relativeTo:)` under the same provider rules as markup. It is not a file path
     and it is not trusted.
   - A path the skin does not contain **warns (`WMP0023`) and leaves the authored artwork in place**.
     A mistyped frame name must never blank a node that has something to draw.
   - `""` is an **authored absence**, not a missing file: it clears that name the way an absent
     attribute does, which is how every store-thumbnail `previewView` drops its splash bitmap
     alongside the zero-size collapse. `view.backgroundImage` is on the `view` compatibility list for
     that reason — the view root resolves it like any other node, so the tally must not call it
     unknown.

   The image store keys its cache on the canonical resource path, so a scripted swap is a different
   key and a different decode; the scene owns no image state of its own.

6. **A host path has more than one resolution, and a member being live does not make the binding
   live (W162).** `player.status` reaches the skin three ways — the object-model member
   (`metadata.value = player.status`), the `wmpprop:player.status` binding a `<TEXT>` authors, and
   the `status_onchange` argument — answered by `WMPObjectModel.readPlayer`,
   `WMPObservablePropertyRegistry.value(path:kind:snapshot:)` and
   `WMPMainWindowController.arguments(for:_:)` respectively. All three read
   `WMPHostSnapshot.statusText`, which is where a new host string belongs: it was possible for the
   member to answer and the readout to stay blank because the registry had no case for the path, and
   that is exactly how `Windows_XP_Media_Center_Edition`'s `STATUS:` line shipped empty. **Adding a
   host property means checking all three**, and any new one has to state whether an event argument
   exists for it at all.

   The wording is WMP's status-bar sentence — `Playing`, `Paused`, `Stopped`, and `Ready` before
   anything is open — and it is free to be a sentence because **not one of the corpus's 128 uses
   compares it against a literal**. Every one prints it, either into a readout or in front of the
   track name. **There is no `Buffering (n%)` case** although WMP spells one:
   `snapshot.bufferingProgress` is 0-100 with 100 meaning *full* and nothing outside the harness
   writes it, so a `< 100` test would report every skin permanently buffering on the default `0`.

7. **`WMPImage_AlbumArtLarge` and `WMPImage_AlbumArtSmall` are WMP-owned pseudo-resources.** They
   resolve before archive lookup and are backed only by the current track's artwork, asynchronously
   loaded by the WMP session from local tags, supported servers, or a stream artwork URL. They are
   200px and 75px square respectively, preserve aspect ratio, and draw transparent until artwork
   arrives. The skin never receives a URL, token, `Track`, or any other host object. No other
   `WMPImage_*` spelling is accepted: in particular `WMPImage_AdBanner` remains unresolved because
   NullPlayer has no equivalent surface.

8. **`player.fullScreen` is the Player's own member, and `playState` tells the truth while a media
   opens (2026-09-20).** Two halves of one live defect, reported as *"when i start the video the
   video player window does not open"* and *"the video adjustment drawer is open by default"* on
   `ALXMorph`.

   - **`player.fullScreen` (read and write).** It existed only on the `<VIDEO>` element, so the
     Player spelling was `UNRECOGNISED` — and an unrecognised member **throws and takes the rest of
     the handler with it**. `alienware.js`'s `onChangeVidPlayerState()` reaches
     `if(!player.fullScreen){ checkSnapStatus(); }` from `onLoadVid()`, so the four statements after
     it never ran, `toggleVidDrawer('0')` among them — which is the call that closes the video
     settings drawer at load. **35 of the installed archives read or write it**, every
     Alienware/ALX frame among them. The read answers `snapshot.video.fullScreen`; the write posts
     the same `setVideoFullScreen` host command the element's own `fullScreen` write does, so the
     two spellings drive one picture.
   - **`WMPHostSnapshot.State.transitioning` → `playState` 9 (`psTransitioning`).** VLC reports no
     picture size for a few hundred milliseconds after `play`, and the engine was calling that
     interval `playing`. A `.wmz` that checks — and this family is the corpus's most-shared example
     — reads `playState == 3` with `imageSourceWidth == 0`, concludes the media has no picture, and
     calls `view.close()` **in the `onLoad` of the window the app has just opened for it**: the
     skin's video window opened and shut itself inside 200 ms and the user saw nothing open at all.
     The state is emitted only from the local-video branch of `WMPAudioEngineHost.snapshot`, while
     `video.isPlaying` is true and `hasVideoOutput`/`presentationSize` are not yet; it answers as
     *running* everywhere else in this engine (`State.isRunning` — transport availability, the
     `<EFFECTS>` tap, the unskinned player), so the only thing that can see it is a skin asking
     `player.playState`. The `playstatechange` edge to `playing` on the tick the decoder answers is
     what then reveals the picture, which is WMP's own sequence.

   **The lesson worth keeping: deferring the open is not the fix, and it deadlocks.** The first
   attempt held the reveal back until the picture had a size — and VLC produces no output until it
   has a window, so the window waited on a picture that was waiting on the window, and the view
   never opened again in any run. The engine has to open the window and *describe the state
   honestly*; it must not wait for a decoder it is starving.

## An unanswered `wmpenabled:` can delete a control, not grey it (W255)

`WMPObservablePropertyRegistry` owns both `wmpprop:` and `wmpenabled:`, and its `enabled` table is a
literal `switch` over paths with `default: return nil`. `unansweredValue` turns that nil into
`.bool(false)` — the right default, because a control this engine cannot drive should look dead
rather than claim a feature that is not there.

**What that default does not account for is a control that mirrors `visible` onto its own `enabled`.**
`Revert` authors

```xml
<slider id="seek" enabled="wmpenabled:player.controls.seek" visible="wmpprop:seek.enabled" … />
```

A `visible="wmpprop:<element>.<property>"` is answered from the skin's own graph by
`WMPSceneBuilder.mirroredVisibility` — **150 of the corpus's `visible="wmpprop:…"` attributes name an
element rather than a host path** — and here the element it names is the slider itself. So the false
`enabled` became a false `visible`, and the builder deletes a node whose `visible` override is false:
`vwPlayer` built **12 nodes with no `slider` among them**. Not a greyed-out seek bar. No seek bar.

Two consequences worth carrying:

- **A missing control and a dead control are the same bug here.** When a report says a control *is
  not there*, the `enabled` table is on the list of places to look, not just the hit map and the
  layout. `WMP_RENDER_PROBE` answers it in one run: the node is simply absent from the dump.
- **WMP spells some capabilities twice and a skin may author either.** `IWMPControls` carries both
  `currentPosition` and `seek`; the table answered the first and defaulted the second. Before adding
  a row, check whether the capability already has a sibling spelling that *is* answered, and gate
  both on the same snapshot quantity so they can never disagree.

Reach, over 185 archives, decoding script text the way `WMPTextDecoder` does (the census matches
tags, never binding paths, so this needs the script-text scan in `harness.md`):
`pause` 151 uses / 125 skins, `play` 36/30, `stop` 21/17, `previous` and `next` 11/10 each,
`currentposition` 6/6, `fastforward` and `fastreverse` 3/3 each, **`seek` 2/2 — and those two are
`Revert` and `Revert (1)`, the same markup, so one skin.**

## Elements

Every element id is a global, and a write to one of its properties mutates the retained graph and
marks it dirty. Element state lives for the whole session: that is the difference between a click
that toggles a pane and a click that does nothing.

The **property** surface is open — a WMP element carries far more properties than this engine draws,
and refusing `hoverFontStyle` on a `TEXT` would abort the handler that sets it, which in Corona is
the whole of `InitControls`. An unauthored, undrawn property is stored and answers `inert`, so the
census can rank "properties skins set that nothing renders" instead of losing them.

### The `<VIDEOSETTINGS>` element (W103)

**94 uses across 94 of 177 archives**, one per skin, 93 of them in a view of their own — the
brightness / contrast / hue / saturation panel. The corpus's own tooltip vocabulary is unambiguous
about what the sliders are: `brightness` 80, `hue` 80, `saturation` 79, `contrast` 78, plus
`reset …` ×20 each. **NullPlayer's video path exposes none of the four, so this is a decision, not
drawing work**: either `inert()` — the trap `INERT` exists for — or add the four controls to the
video path and bind them honestly. **Do not resolve them to a value this player never applies**; a
slider that moves and changes nothing is the worse of the two outcomes. It has been answerable since
W102 landed: the video path exists, so the question is what to bind, not whether there is anything
to bind to.

### The `<NETWORK>` element (W104)

**6 uses across 4 of 177 archives**, the smallest surface in the corpus. `<NETWORK>` is an object,
not a control — it authors no attributes at all corpus-wide, so `WMPSceneBuilder.isNonLayout`
treating it as non-layout is correct and stays.

**The element is the smallest surface here; the members read off it are not, and the two must not be
confused.** Measured 2026-09-21 over 184 archives and 400 script/markup files, decoding each the way
`WMPTextDecoder` does (156 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM) and matching
`\bnetwork\s*\.\s*(member)` — the census matches a *tag* and can never answer this, so it needs the
script-text scan in `harness.md` § *Grepping the corpus's script text*:

| Member | uses | archives | Answers |
|---|---:|---:|---|
| `downloadProgress` | 58 | 42 | `bufferingProgress`'s field (**W104**; was unrecognised) |
| `bufferingProgress` | 26 | 11 | the field, which nothing in this app writes |
| `receptionQuality` | 9 | 4 | the field, which nothing in this app writes |
| `bitRate` | 9 | 8 | live, from `Track.bitrate` (W-`Cablemusic`) |
| `bandWidth` | 9 | 7 | inert `0` |
| `sourceProtocol` | 6 | 3 | inert `""` |
| `maxBitRate` | 3 | 3 | inert `0` (**W104**; was unrecognised) |
| `framesSkipped` / `lostPackets` / `receivedPackets` | **0** | 0 | inert `0`, no reader in the corpus |

**Split a member count by resolution path before ranking it.** `downloadProgress`'s 58 looks like 42
archives of broken handlers and is one: **55 of the uses are `wmpprop:` bindings**, which
`WMPPropertyRegistry` has resolved since W93 — a separate resolution of the same path from
`WMPObjectModel.readNetwork`. Only **3 script reads, all in `tubeframe.wmz`**, ever reached the
switch that was aborting. The earlier claim here that `downloadProgress` and `bufferingProgress`
"already resolve" cited `WMPPropertyRegistry` and was true of a `<TEXT value="wmpprop:…">` binding
and false of every script read, which is why the defect survived a reading of this file.

**`bufferingProgress` is answered, and it is a dead `0`.** Nothing in the app writes the field
(`WMPHost.swift`), so `downloadProgress` now answers zero too — and in `tubeframe` that is *visibly*
wrong rather than merely absent: its `GetMetaData` prints `downloadProgress + "% downloaded"`
whenever the value is under 100, so the readout reads `Playing: 0% downloaded` instead of falling
through to its `bitRate` branch. That was taken deliberately over a constant `100`, which is the
truer answer for a player where the media has always fully arrived but would flip ~36 archives'
buffer bars from empty to full off one unmeasured constant. **The trap `WMPHost.statusText` names in
prose is now reached rather than predicted**: a `< 100` test against a field nobody writes reports
every skin permanently buffering. Making the field live is what corrects both readouts together, and
it is the option below.

**Feed it from the streaming player's own statistics, never from Flow.** `Windows/NetworkMonitor`
measures *interface* throughput for the whole machine, a different quantity from this stream's
bitrate and buffer, and wiring one to the other would draw a confident wrong number. Flow is still
the right *window* for it — 4 skins declare a network view and nothing else in this app claims that
menu slot — but the object and the window are two separate answers.

### The `<EQUALIZERSETTINGS>` element

`enable` / `enabled` is handled at load time as declared host state: it turns NullPlayer's existing
equalizer on or off. `enableSplineTension`, `splineTension`, and `bypass` have no corresponding DSP
control here. They retain authored and script-written values so a skin can round-trip its own state,
but every read and write is recorded as `INERT` and produces neither a host command nor a scene
mutation (W134). In particular, `bypass` is not silently treated as the inverse of `enable`.

`eq.enhancedAudio`, `wowLevel`, `truBassLevel`, `speakerSize`, and `currentSpeakerName` are live
audio-enhancement members; see [audio-enhancements.md](audio-enhancements.md) for their typed command
path and the temporary -1 speaker-cycle rule. They are separate from the inert spline/bypass fields.

#### The `eq` object and the element are one surface (W39)

`eq` is a bound global on the path `eq`, not an element lookup, so `eq.enableSplineTension` reaches
`readEqualizer` and never `<EQUALIZERSETTINGS>`'s own property table. Both spellings now answer the
same values: the object stores the spline pair in its own session map and defaults it from
`defaultInertEqualizerSettingsValue`, so a skin cannot see the two disagree.

**Store an inert value rather than answering a constant when the corpus reads it back.** `Back to
the Future Trilogy`'s `checkSplineTension()` clears its three grouping buttons and then tests
`eq.enableSplineTension && eq.splineTension==2` to light one; a constant lights the same button
whichever the user pressed. `false`/`0` is the honest default — independent sliders is what this
player's equaliser does — and it is what the lit button then says.

**Crossfade is not an inert candidate, and checking whether the player already has the feature is
the step W39 was ranked without.** WMP's crossfade is this player's Sweet Fades under another name,
so `eq.crossFade` and `eq.crossFadeWindow` bind to `AudioEngine.sweetFadeEnabled` and
`sweetFadeDuration`, and `eq.normalization` to `volumeNormalizationEnabled`. The row had called the
whole class an `inert()` candidate; `speakerSize`, its headline member at 18 skins, had in fact been
live since the WOW/TruBass work landed.

Re-measured 2026-09-22 over 184 archives with the script-text scan in
[`harness.md`](harness.md) § *Grepping the corpus's script text* — the census matches a tag and can
never see a member read:

| Member | uses | archives | Answers |
|---|---:|---:|---|
| `crossFade` | 123 | 38 | `sweetFadeEnabled` |
| `enableSplineTension` | 68 | 51 | `INERT`, stored |
| `splineTension` | 56 | 48 | `INERT`, stored |
| `crossFadeWindow` | 40 | 35 | `sweetFadeDuration`, **milliseconds** |
| `normalization` | 1 | 1 | `volumeNormalizationEnabled` |

**"Both spellings" now means any name the skin gave the element — closed with W256, 2026-09-22.**
The routing was `case "eq": return readEqualizer(name)` on the *path*, so a skin whose
`<EQUALIZERSETTINGS>` is named anything else never reached `readEqualizer` at all: `ElvisEQS.gainLevel1`
landed in the element's own property bag, changed no audio, and — the half that is visible on screen —
the band slider bound to `wmpprop:ElvisEQS.gainLevel1` never moved, because *that* binding resolves
from the host. Reported live as "an equaliser slider cannot be dragged" on `elvis`. Two seams carry
it, and neither adds a case per member:

- `WMPObservablePropertyRegistry.init` folds a binding path whose first segment names a declared
  `<EQUALIZERSETTINGS>` to `eq`, so `eqBand`, every `eq.` case and `hostRoots` are untouched.
- `WMPObjectModel`'s `read`/`write`/`call` route an `element:` receiver of kind `.equalizerSettings`
  to the equaliser, **falling through to the element when the equaliser answers `unrecognised`** — a
  handler dies on its first unrecognised member, so the open element surface has to stay.

**`enableSplineTension`, `splineTension` and `bypass` are excluded and stay the element's.** They are
`inertEqualizerSettingsProperties`: bookkeeping with no DSP behind it whose *authored* value a skin
reads straight back (W134). Routing them answers the session's defaults over the markup, which is a
named `<EQUALIZERSETTINGS>` losing its own attributes — and
`testUnsupportedEqualizerSettingsRoundTripAsInertState` fails the moment it is tried.

**The reach is 7 of the 184 measured archives, not the 14 stated here before 2026-09-22.**
`elvis` (`ElvisEQS`), `TDK` (`eqsettings`) and `Gorillaz`/`Navigator`/`Ursula`/`robbie`/`v2_underworld`
(`equal`). The seven names withdrawn — `Frostbite` (`eq2`), both Bionic Dots (`eq22`), `Plus! Hard
Boiled` (`eggEQS`), `Plus! HueShifter`, `Plus! Plasma Ball`, `Plus! SlimLine` — declare **no
`<EQUALIZERSETTINGS>` at all**; `Frostbite` ships `eq2_slider.png`, so the 14 was a filename match.
Reproduce with `python3 scripts/wmp_slider_drag_census.py` (population C), which **reads the bytes
rather than grepping them**: see § *A corpus number taken with `grep` is not a corpus number* in
[`harness.md`](harness.md).

`eq.gainLevels(band) = value` (`Compact`, `Charlies_Angels_Full_Throttle`) stays unrecognised: it is
assignment to the result of a call and not valid JScript, so answering it would be answering a typo.

**Both resolution paths have to answer or the control is half-wired.** The corpus idiom is one
sticky button — `onClick="eq.crossFade = !eq.crossFade;eq.crossFadeWindow=7000"` with
`down="wmpprop:eq.crossFade"` — so the write goes through `WMPObjectModel` and the lit state through
`WMPObservablePropertyRegistry`, which is a separate resolution of the same path. A member added to
only one of them fades tracks and never lights, or lights and fades nothing.

**The statement after the read is what an unrecognised member costs.** Six of the 38 crossfade
spellings (`ALXMorph`, `Batman Begins`, `Constantine`, `Disney_Mix_Central`, `Dreamcatcher`,
`KungFuChaos`) put `checkSoundPref('click.wav')` in front of the write, so the throw took the click
sound with it; `Back to the Future Trilogy` aborted *after* clearing all three grouping buttons,
leaving none lit. Evidence: `Tests/NullPlayerAppTests/WMPEqualizerMemberTests.swift`, and a
`WMP_RENDER_CLICK='eqView@106,80'` on `Plus! Professional` now prints `command=setCrossFade value=1`.

### The `<EFFECTS>` element

`EFFECTS` and `WMPEFFECTS` are the same surface and both map to `.effects`. Only the second was ever
a kind, and 183 uses across 166 of 177 archives spell it the first way, so the visualization surface
of nearly the whole corpus fell to `.unknown` and was hosted on nothing (W101).

Four members answer live, off `WMPHostSnapshot.effects`, and they are the same selection
`mediacenter` holds:

| Member | Answers | Reach |
|---|---|---|
| `currentEffectType` | the effect's id; writable, and a write commands the host | 66 archives |
| `currentPreset` | the preset number within that effect; writable | 66 |
| `currentEffectTitle` | the title a skin draws beside the rect | 61 |
| `currentPresetTitle` | the running engine's own preset name | 42 |

and three methods cycle it: `next()` (82 archives), `previous()` (74) and `nextPreset()` (4).
`settings()` (9) is **not** implemented — it opens WMP's own visualizer property sheet, which has no
counterpart here. A skin's authored type (`spikes`, `ambience`, `random`) names a WMP visualizer this
player does not have, so it selects nothing and the read-back answers what is really on screen.

Still unhonoured on the element: `windowed` (125 archives), `allowAll` (11), `clippingColor` (44) and
`clippingImage` (12).

### Playlist kinds

`WMPElementKind` models three spellings and they are not interchangeable. `PLAYLIST` and
`ITEMSPLAYLIST` are both **lists** and both map to `.playlist`; `DROPDOWNPLAYLIST` is a chooser and
maps to `.dropdownPlaylist`, which is hosted as an `NSPopUpButton`.

**`ITEMSPLAYLIST` maps onto `.playlist` wholesale, and the corpus is the evidence rather than the
name** (W97). 13 of the 179 measured archives declare one — `corona`, `Optik`, `anemone`, `aoe`,
`bluegrid`, `cerulean`, `claw`, `Cubist`, `gadget`, `gnome`, `modernblue`, `pharaoh`, `polygon` —
and **not one declares a `PLAYLIST` beside it**, so it is the only playlist those skins have. Every
one authors list geometry (226x174, 187x139, 155x116 …) and `PLAYLIST`'s own attribute vocabulary:
`backgroundColor`, `foregroundColor`, `itemPlayingColor`, `backgroundImage`. A separate kind would
have bought nothing. While it fell to `.unknown` it never became a `WMPWidget`, so W93's routing —
which correctly stands NullPlayer's own playlist aside whenever the skin declares one — left those
users with an empty drawer.

`dropdownVisible` (12 of the 13) asks for a playlist *chooser* above the rows. It is unhonoured
here exactly as it is on `PLAYLIST`, because it needs `player.mediaCollection` — that is W66's
question, and faking it with playlists this player invented is the thing W66 exists to refuse.

**W66 is a `LISTBOX` with a control and nothing to put in it: 8 skins, 16 uses, measured 2026-09-07
over 177 archives.** Every one is `plListBox1`/`plListBox2`, a playlist chooser the skin fills from
script by walking WMP's media collection (`getSelPlaylist()`). The control now exists, draws and
reports its selection; what it cannot do is have rows, because the object model answers nothing for
`player.mediaCollection` — so a skin's `onLoad` appends nothing and the box stays empty. **That is a
host-surface decision — what a `.wmz` may see of this player's library — not drawing work**, and it
is deliberately not faked with rows this player invented. W136 is what answering it would let the
skins actually do.

**Recognition for routing is deliberately wider than the modelled kinds.** `WMPSkinSurfaces` matches
on the authored tag, so any tag ending in `PLAYLIST` counts as a skin-owned playlist even before it
is a kind here. What decides routing is what the skin *declares*, not how much of it this engine
hosts today — and keeping the two rules separate is what stops a future spelling from opening a
second, foreign-looking window on top of a drawer the skin draws itself.

## Methods

The **method** surface is closed. `WMPObjectModel.elementMethodVocabulary` lists the names WMP
defines as element methods; one of those that this engine does not implement stays `unrecognised`
rather than falling into the open property surface. Without that, `svPlaylist.moveTo(…)` reads as an
empty string, dies with a bare `TypeError`, and never appears in the tally that ranks the work.

**The vocabulary is the SDK's element-method list, not a list of names the corpus has been seen to
call (W128).** It is transcribed from the Skin Programming Reference:
[`ambient-attributes`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/ambient-attributes),
[`view-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/view-element),
[`playlist-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/playlist-element),
[`listbox-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/listbox-element),
[`popup-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/popup-element),
[`editbox-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/editbox-element),
[`effects-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/effects-element),
[`buttongroup-element`](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/buttongroup-element).
`VIDEO`, `BUTTON`, `TEXT` and `SUBVIEW` define no methods of their own. Start the next audit from
those pages rather than from a corpus scan — a scan can only find what some skin already calls.

**The rule the audit established: a method outside the vocabulary is invisible to the tally, not
merely unimplemented.** It reaches the open property surface instead, answers `""`, and the call
dies as a bare `TypeError` — the same abort at the same statement, but classified as an *inert
property* rather than as unrecognised method demand, so it ranks in Tier 2b ("recognised, answered,
nothing behind it") when it belongs in Tier 2a. `view.returnToMediaCenter` is the evidence: it had
to be found by a live reporter (W100) because `WMP_CALL_TRACE` could not see it, and
`WMP_CALL_TRACE` is what every row in `WMP_TASKS.md` is ranked from.

Two consequences bind any change to this set:

* **Widening it implements nothing.** `elementMethod(_:_:)` stays the kind-aware authority on what
  actually runs, and `implementedElementMethods` on what the census counts as answered.
  `WMPJScriptCompatibility.members["element"]` is derived from the latter, not from the vocabulary —
  which is why `setFocus` is in the vocabulary and correctly absent from the compatibility table.
* **A name is only ever added, never removed.** The vocabulary gates *reads* as well as calls:
  `readElement` consults it only after `element.properties`, `element.authored` and
  `standardElementProperties`, so an authored or already-written name still answers, but an
  **unauthored bare property read** of a vocabulary name aborts its handler. Before adding a name,
  grep the extracted corpus scripts for `\.<name>\s*[^(]` and confirm the hits are calls or host
  receivers. W128 found exactly one read class — `mediacenter.effectType`, 376 uses across 130
  archives — and it is a host receiver answered by `readMediaCenter` before the element path, so it
  was safe. **Decode the corpus the way `WMPTextDecoder` does when you run that grep**: the first
  W128 scan read every file as UTF-8 and silently skipped the 153 of 392 that are UTF-16, reporting
  141. See `harness.md` § *Counting a tag across the corpus*. Dropping a
  name can only turn a currently-tallied call back into a silent empty string.

Implemented today: `moveTo`, `resizeTo`, `alphaBlendTo` (**animated over the duration they name
wherever a frame clock is driving them, and applied instantly everywhere else — see *Tweens* below**),
`appendItem`/`removeAllItems`/`getItem` on `POPUP`, `setColumnResizeMode` and `setColumnWidth` on the
playlist kinds — `ITEMSPLAYLIST` among them, and it is a modelled `.playlist` kind since W97 —
`next`/`previous`/`nextPreset` on `EFFECTS`, and `close`/`minimize`/`size` on the view.

**`view.size(corner)` is the resize grip, and on a `.wmz` window it is the only resize there is**
(W193). 235 calls in 88 of the 185 installed archives, authored as
`onMouseDown="view.size('bottomright')"` on a small corner button: `bottomright` in 86 archives,
`topright` in 4, `right` in 3, and `bottom`/`bottomleft`/`left`/`topleft` in 2 each — `Revert` is
the only skin that authors all seven. The window is borderless and has no OS frame, so while this
was inert the user reached for the macOS window edge instead, which skips whatever the skin wraps
around its own resize: `Compact`'s `DoSize()` pins both drawers to their edges for the duration and
unpins them after, and a window widened any other way leaves the drawer behind.

It posts `sizeWindow` with the corner as its value, and `WMPMainView.beginScriptResize(corner:)`
arms the **same** edge drag the window's own resize band runs — one clamp against the view's
`minWidth`/`maxWidth`, one anchored edge, one relayout. Two gates are all it adds: `scene.isResizable`
(the permission the band already asks for — all 88 archives author `resizAble="true"`, so it costs
the corpus nothing), and the left button must still be down, because the call arrives from an
asynchronous script transaction and a quick click's command can land after the release, where arming
a drag would resize the window on whatever the user pressed next. `WMPMainView.mouseUp` no longer
returns early while a target is captured: the grip is a real element, so it has an `onMouseUp` and
an `onClick` to raise and a pressed state to drop.

**What this cannot reproduce is WMP's blocking call.** In WMP `view.size` returns when the drag
ends, so `DoSize()`'s unpin runs afterwards; here a transaction completes before its commands are
applied, so both brackets have already landed when the drag starts. The drag is right, the
bracketing is early, and no arrangement of this pipeline changes that.

### Tweens (W194)

**A duration animates only where something is drawing frames, and the decision is made per
transaction.** `WMPScriptRuntime.transact(animatesTweens:)` is the caller promising a clock. Only a
window has one: `WMPMainWindowController` passes it on the **click and view-timer paths**, and
nothing else does — not a render dump, not the corpus census, not the windowless dispatcher (W89),
and not the load, resize or close paths, where an `onLoad` sequence chained through `onEndMove` has
to have finished before the first present. Without a clock the call behaves exactly as it did before
this row, so **the settled state is identical either way** and no headless measurement on this
subsystem moved. The corollary is that no probe here can see the row at all; it is drivable only in
the running app.

With a clock, `WMPObjectModel.tweenGroup` emits a `WMPScriptTween` — the channels it is moving with
their `from` and `to`, the duration, and the completion event — and writes nothing. The runtime holds
the live set per view scope; `WMPMainWindowController.startTweenLoop` drives
`WMPScriptRuntime.tweenFrame` at 30 fps until the output stops reporting `hasActiveTweens`. **A frame
is a real transaction**: the interpolated value goes through the object model, becomes a mutation and
therefore a scene override, and the element reads where it *is* mid-slide, which is what W112 is
about. Motion is linear — WMP's own easing is undocumented and the corpus slides drawers over two to
four hundred milliseconds. The last frame writes the endpoint itself rather than an interpolation
near it, so a drawer rests on the pixel the skin named.

Three things still arrive instantly under a clock, each because a frame would be a guess:

* **A duration of zero**, which is never a tween and must be readable by the rest of the handler.
* **A channel already at its destination.** Its completion is raised at once, or a sequence chained
  off a no-op move would stall waiting for a frame with nothing to draw.
* **A channel whose current value the model does not hold.** `left`/`top`/`width`/`height` are
  synced from the scene each transaction so they are always there; `alphaBlend` is absent unless
  authored or previously written, and an absent one *inherits* (`WMPSceneBuilder.inheritedAlpha`),
  so the only number a fade could start from is the opaque default. `alphaBlendTo` on an unauthored
  `alphaBlend` therefore arrives rather than fading — which is what the Alienware/ALX family's
  `m_anim_*` subtrees depend on.

A later call on the same element and property **replaces** the one running, so a drawer re-toggled
mid-slide reverses from wherever it currently is. `WMPScriptRuntime.cancelTweens(for:)` and
`discardView` drop a view's motion outright: a view that stops existing has no motion to finish.

**The callback is the load-bearing half of this row, not the tween.** Moving `onEndMove` from
end-of-handler to end-of-tween changes when 36 views chain their next step, and `Compact` shrinks its
own window inside `Playlist_OnEndMove` — so the window now shrinks a beat after the drawer starts
closing, which is what WMP does. `Tests/NullPlayerAppTests/WMPTweenTests.swift` pins both halves,
starting with the no-clock invariant.

**A call that lands its endpoint completes in the same transaction (W55).** *Under a frame clock the
completion is raised at the end of the tween instead; everything here describes the mechanism both
paths share and the timing of the headless one.* `WMPObjectModel` records
`(stableID, event)` on every `moveTo` and `alphaBlendTo`; `WMPScriptContext.raiseCompletionHandlers`
turns each into the `onEndMove`/`onEndAlphaBlend` the markup authored, before the geometry cascade so
a chained step's writes still propagate, bounded by `WMPPhase0Limits.expressionPasses` and once per
`(element, event)` so a handler that moves something again cannot spin. WMP tweens over the call's
third argument and completes when the tween ends; this engine arrives instantly, so the honest
completion is now. **`onEndResize` is deliberately absent: zero archives author one**, so it would be
a dispatch site with nothing to prove it. Measured over 179 archives: `onEndMove` 247 uses / 113
skins, `onEndAlphaBlend` 50 / 21.

Without this a skin's sequence stopped after step one, and the drawer template Microsoft shipped is
built out of it: `toggleVidDrawer()` slides the drawer and `onEndMove="checkVidDrawer()"` is the only
thing that shows or hides its contents. 36 corpus views were drawing a drawer's controls stranded
outside a drawer that had already slid shut.

**An event handler reads its target's `value` as a bare name.** WMP evaluates a handler against the
element that raised it. `WMPScriptContext` binds that one identifier for the duration of the event
and clears it after, rather than scoping the whole element: 111 of the 141 `onDragEnd` sources are
`player.controls.currentPosition = value`, and a bare *assignment* like `toolTip='Seek'` (6 uses)
creates a global and costs nothing either way — so only reads were ever blocked, and `with(element)`
would change name resolution for every handler in the corpus to buy those six. `onDragEnd` itself is
raised by `WMPMainView.mouseUp` for a captured slider; it is authored only on `SLIDER` (125) and
`CUSTOMSLIDER` (16). **A seek commits on release and nowhere else (W156)**, and the release is where
the engine decides whether the skin committed it: a transaction that posts `seekSeconds` owns the
seek, and one that does not hands it back to `WMPMainWindowController`, which commits the value the
pointer left. See `SKILL.md`.

`WMPObjectModel.implementedElementMethods` is the flat set of those names, and
`WMPJScriptCompatibility.members["element"]` is derived from it rather than restating it. That
matters as much as the implementation: the corpus census classifies a member against that table, so
one the runtime answers and the table does not know is measured as demand for something that already
works. `moveTo` and `resizeTo` were counted that way from Phase 3 until W38 closed, which is part of
why `alphaBlendTo` read as the largest row on the backlog.

`alphaBlendTo(target, ms)` writes `alphaBlend`, which is the same property the scene builder inherits
down a subtree, so a faded-in container brings its children back with it. Two details are
load-bearing:

* `alphaBlend` is in `standardElementProperties` — a write commits as a mutation even on an element
  whose markup never authored it — but deliberately **not** in `standardNumericProperties`, because
  an unset numeric property answers 0 and an unset `alphaBlend` is 255. `readElement` holds that
  default. A skin stepping its own alpha (`x.alphaBlendTo(x.alphaBlend - 64, 200)`) would otherwise
  start from invisible and never come back.
* The endpoint is clamped to 0-255. The builder normalises by dividing by 255, so an unclamped
  endpoint would multiply a subtree's inherited alpha past opaque.

`textWidth` is **measured**, not stored. It is the one element property whose answer this engine has
to compute, because 92 of the 180 archives use it to decide whether to marquee —
`metadata.scrolling = (metadata.textWidth > metadata.width)` is the idiom, and `WoW` runs it on every
metadata change. Falling into the open property surface answered the unset-numeric `0`, so every one
of those skins concluded its text fits and the marquee could never start. It measures the element's
*live* `value` in its live `fontFace`/`fontSize`/`fontStyle` through `WMPTextMetrics`, which is the
same code the renderer lays the line out with — the comparison has to be against what is drawn, and
a second measurement path would drift from it. `scrolling`, `scrollingDelay` and `scrollingAmount`
are in `standardElementProperties`/`standardNumericProperties` for the reason `alphaBlend` is:
`WoW`'s markup authors the two numbers and never `scrolling`, so a write to it would otherwise be
stored inert and never reach the scene.

`scrollingDelay` remains the skin's authored value in the object model, but the renderer follows
WMP's timing contract: a value below the 30 ms minimum falls back to the 85 ms default. It must not
be clamped to 30 ms or rendered at the invalid value. Plus! Professional authors `10`; treating it
literally scrolls at 200 px/s instead of WMP's roughly 24 px/s at its authored two-pixel step
(W126).

`setColumnWidth` is recognised so it stops aborting the handler that calls it, and counted
**`inert()`**: nothing draws playlist columns. `setColumnResizeMode` predates the `inert` convention
and is still counted live; that is a known inconsistency, not a statement that a resize mode does
anything.

## `theme.openView`, `theme.openViewRelative` and `theme.closeView`

WMP opens the named view as an **additional** window beside the opener and leaves the opener alone;
only `theme.currentViewID` *replaces* a view. That is what this engine now does.
`WMPViewWindowMaterializer` builds one borderless `NSWindow` per open view, all rendering and taking
input against **one shared script runtime**; the first view presented binds the app's own window and
is the player. `openView` posts its own `openView` host command and the controller materializes a
window for it; the calling window's scene is untouched, so — unlike `setCurrentView` — the command
does **not** report "switched view" and the transaction that posted it still draws.

Measured over the 180 installed archives: `openView` 579 uses across **90** skins, `view.close()`
424 across 170, `theme.closeView(name)` 183 across **84**, `theme.currentViewID` 196 across 68,
`theme.openViewRelative` 8 across 2 (`Revert`).

- **`theme.closeView(name)` closes the window showing that view**, and is a silent no-op when it is
  not open. It used to be unrecognised, which aborted the handler on that statement: `Halo 2`'s
  `checkRemoteViewStatus()` dies on `theme.closeView('vidRemoteView')` and never reaches the four
  statements after it. With no argument it keeps the meaning `view.close()` already posts — close
  the window the handler is running in.
- **`theme.openViewRelative(id, dx, dy)` places the new window at `dx,dy` skin pixels from the
  opener's top-left**, on its first placement only, in place of the tiler. `Revert` hangs its EQ
  under the player and its playlist beside it entirely with this call. It was deliberately left
  unimplemented while this engine had one window (W50) — aliasing it to `openView` would have
  dropped the displacement silently and taken the member out of the demand tally, which is the trap
  `INERT` exists for. The offset rides the action (`openViewRelative:<dx>,<dy>`), the way
  `setEQBand:<n>` and `playPlaylistItem:<n>` already do, because a host command carries exactly one
  value and the view id is it.
- **`view.close()` closes the calling window.** Closing an auxiliary window leaves the player
  running — still animating, still holding its own overrides — which is what the covered-view stack
  used to simulate. Closing the **player** closes the whole skin UI, panels and all: leaving panels
  up with no player behind them is the W96 shape, and a player that cannot be closed while a panel
  is open is not a player. The macOS close control means the same thing, so the W127 compensation
  (intercept it and pop the stack instead) is gone with the stack.
- **`view.minimize()` miniaturizes the calling window.**

All of it is **live**, not `inert()`. The former deviation recorded here — "an auxiliary panel
covers the player instead of sitting beside it" — is closed, and with it the three defects it
caused: W90 (closing an interior window closes the whole UI), W96 (the skin is empty and shows no
player) and W127 (the macOS close control strands the user). Each existed only because a covered
view had to be simulated.

**`openView` is still not an alias for `setCurrentView`.** The two mean different things to the host
and collapsing them in the object model would erase the distinction before the controller could act
on it — one opens a window, the other replaces one.

Initial load keeps them apart too, and W175 is what it cost when it did not. A view that never
becomes a window can honour neither as a window operation, and both do say which view to show next —
but only `setCurrentView` is a *replacement*, so the last one wins and nothing beside it can be the
player. `openView` is a window each: `WMPMainWindowController.windowlessSuccessors` makes the
earliest of them in the skin's declaration order the player and replays the rest against it once it
is on screen. A windowless view reached through `openView` at any other time is the same case: it
never becomes a window, and its host commands run against whoever asked for it.

## `theme.loadPreference`

`loadPreference(name)` returns the skin-scoped value previously written through
`savePreference(name, value)`. An absent key answers **`"--"`**, WMP's sentinel for an authored
default that has never been saved; it is distinct from a key explicitly saved as an empty string.
Skins branch on that distinction — `Plus! Professional` uses
`loadPreference("vidRightDrawer") != "--"` to choose its saved drawer state (W76).

## `mediacenter`

WMP's Media Center host object: the video surface, the visualization ("effects") selection, and the
shell's own localised strings. It was the largest single thing stopping a handler in this corpus —
**159 `ReferenceError: Can't find variable: mediacenter` across 110 of the 179 measured archives**,
each one killing an `OnLoad` on whichever line first touched it (W37).

**Seven of its nine members are `inert()`, and that is the finding rather than a shortcut.** There
is no video surface to zoom (`imageSourceWidth`/`Height` already answer 0 for the same reason) and
no high-contrast mode. Nothing behind those has a host to be live about.

**`effectType` and `effectPreset` are the two that left that class (W101).** The `<EFFECTS>` rect
they select for is hosted now, so they answer `WMPEffectSelection` — what is actually being drawn —
and a write posts a `setEffectType`/`setEffectPreset` host command instead of storing session state.
96 archives bind them straight onto the rect (`currentEffectType="wmpprop:mediacenter.effectType"`),
so this is the corpus's own selector and not a menu this engine invented.

What it is **not** is a stub that answers a constant. Skins round-trip these — `Plus! Professional`
writes `mediacenter.effectPreset = visEffects.currentPreset` in one view and reads it back into a
control in another — so a write stores **session state** and the next read answers it, exactly as
`player.settings.autoStart` does. A constant would break the read-back while looking identical from
every instrument.

The corpus asks for exactly these nine names and **never uses `mediacenter` as a bare identifier**,
so the table below is the whole object. A tenth name stays `unrecognised` and ranks itself.

| Member | Default | Why that default |
|---|---|---|
| `videoZoom` | `100` | WMP's own 100%. Nothing is scaled; the number is what a skin's zoom readout prints |
| `videoStretchToFit` | `false` | nothing is fitted to anything |
| `videoShrinkToFit` | `false` | as above. Corpus use is write-only |
| `effectType` | live | the id of the effect the rect is drawing: `bars`, `projectm`, `geiss`, `tripex`. Writable |
| `effectPreset` | live | the preset within that effect — ProjectM's preset, Geiss's and Tripex's effect. Writable |
| `showTitles` | `false` | no titles are drawn over a video that does not exist |
| `showEffects` | `true` | the effects surface *is* always drawn, so `myeffect.visible = mediacenter.showEffects` is right |
| `contrastMode` | `""` | no high-contrast mode. The corpus tests it `== "BW"` / `== "WB"` and falls through to its normal path |
| `getNamedString(name)` | `""` | the same `wmploc.dll` string table `theme.loadString` names, reached by a second route (`BuyMusicButton`, `BuyMusicURL`, `PLCID` — the WMP store's own resources) |

`contrastMode` is the host's accessibility setting and is **read-only in WMP too**, so a write to it
stays `unrecognised` rather than being quietly accepted.

Two things this deliberately does not do:

- **It does not answer the paren form.** Nine skins author
  `currentEffectType="jscript:mediacenter.effectType();"` on a `<WMPEFFECTS>`, which WMP accepts
  because IDispatch allows a property get with parentheses and JavaScriptCore does not. The
  expression fails, costs itself alone, and is tallied as an `expression-error` — visible, on an
  attribute this engine's one effects surface does not read anyway.
- **It became a route to the visualization subsystem only once there was one to route to.**
  `effectType`/`effectPreset` naming a real NullPlayer visualization was a capability rather than a
  member — it needed an `<EFFECTS>` that could host one and a snapshot field to answer from. W101
  built both: `WMPEffectsSurfaceView` hosts `VisualizationGLView` in the authored rect and
  `WMPHostSnapshot.effects` is what these two read. Until then the honest answer was a stored
  string, because a mapping with nothing behind it makes the demand disappear while nothing changes
  on screen.

---

## `theme.openDialog`

`FILE_OPEN` posts an `openFileDialog` host command and answers the empty string, counted **inert**.
WMP hands the chosen path back to the script synchronously; an `NSOpenPanel` is main-actor work that
the script queue must never block on (`DispatchQueue.main.sync` is banned in this subsystem), so the
host opens the picker and plays the result while the skin's own `player.URL = newFile` line does
nothing. It is not cosmetic: **WMP mode has no other route to a track**, because the auxiliary
NullPlayer windows stay hidden until they have WMP-owned chrome, and before this the only way to
start playback was to leave WMP mode and come back.

---

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

**The keyboard is bound and the rest of the `event` object is W121.** WMP binds one `event`
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

**The hole this work found, and it hid the dispatch site completely.** `WMPMainView` took first
responder on `mouseDown` and nowhere else, so a window that had never been clicked received no key
event at all and every one of the corpus's 1,052 key handlers was unreachable — the same hole `.wal`
had until Phase 43. Verifying W53 in the running app printed *nothing* until a click went in first.
`viewDidMoveToWindow` now claims the keyboard when nothing in the window holds it, so a hosted
`<EDITBOX>` or playlist surface that has been clicked into keeps it. **A dispatch site nothing can
reach measures exactly like one that does not exist** — which is this file's own rule about
recognising an event, one step further out.

---

## An unqualified name in a handler resolves against its own element first (W216)

In WMP an event handler's unqualified names resolve against the element the handler is **on**, before
anything else. It is why one file writes `visEffects.next()` in one place and a bare `next()` in
another and expects both to work, and why `<BUTTONELEMENT onClick="player.settings.mute = down">`
reads the button it is written on.

**Closed 2026-09-22.** A markup handler is evaluated inside `with (__wmpWrap('element:<owner>'))` —
the same scope a geometry expression gets — at all four dispatch sites in `WMPScriptContext`: the
event, `value_onchange`, `<attribute>_onchange` and the completion cascade. It is **not** wrapped in
a function: a handler's `var` is the skin's global (`corona` declares `g_playlistIsVisible` in one
handler and reads it in every other), and a `with` block keeps it there. The `value` and
`<attribute>` globals the call sites bind stay, because they are bound for the element that *raised*
the event, which is not always the one the handler is written on.

**What made it safe is `WMPObjectModel.recognises`, and it was wrong at both edges.** The `with`
proxy asks it for every identifier, and it is deliberately narrower than the open property surface
the read path answers with — an element that claims every name swallows the skin's own functions.
The corpus sweep found both corrections; neither was visible from the code:

- **An authored *handler* attribute is not a name the element owns.** A `<VIEW onLoad="OnLoad();">`
  authors `onload`, so the element answered the bare `OnLoad` with the attribute's own text and
  `corona`'s entire startup died on `OnLoad is not a function`. `recognises` now declines any
  `on*`/`*_onchange` name; WMP raises those, it does not expose them as properties.
- **The computed properties `readElement` answers from the host must be claimed.** `textWidth`, the
  `<EFFECTS>` selection (`currentEffectType`, `currentPreset`, and the two titles) and the `<VIDEO>`
  flags are not authored and not standard, so a bare `textWidth` threw while `metadata.textWidth`
  beside it answered — `Asia`'s `onEndMove="scrolling = textWidth > width"`, which is how a marquee
  decides to scroll at all. `computedElementProperties` is that list and lives next to
  `readElement`; **a computed property added there and not here is readable qualified and invisible
  bare.**

**Measured 2026-09-21 over the 184-archive corpus** with
`python3 scripts/wmp_handler_scope_census.py`, which scans the decoded script text — the census
drives `onLoad` and this demand is in `onClick`, which is the W100 blind spot — and repairing the
`01 00 01 00` local headers the way `WMPArchiveHeaderRepair` does, without which
`Need_for_Speed_Underground` and `SplinterCellWMPSkin` drop out silently. The scan's encoding
breakdown, which a correct one reproduces: 158 UTF-16-BOM / 146 cp1252 / 89 UTF-8 / 9 UTF-8-BOM.

| half of the class | measured |
|---|---|
| unqualified **call** — the recorded row | **31 uses / 20 archives**: `previous()` 10, `next()` 8, `alphaBlendTo` 4, `nextEffect` 1. Resolving a handler through the call graph (handler → the skin's own function, three levels) adds **nothing**: the idiom is written in the attribute itself. |
| unqualified **property**, net of the `value` and `<attr>_onchange` globals already bound | **255 unresolved reads + 249 silent writes / 100 archives**: `down` 196/89, `toolTip=` 114/40, `left`/`top` 108/9, `width` 34/25, `scrolling` 20/17 |

**The call half is the row and is not what carries it.** `player.settings.mute = down` on a sticky
mute button is 89 archives on its own; before this a read threw
`ReferenceError: Can't find variable: down` — so the button latched and the player never muted —
while a write silently made a global and never reached the element, which is `toolTip='Seek'` and
`scrolling=false` reporting success and changing nothing.

Reproduce either half with `WMP_RENDER_CLICK`: `circle` at `vMain@69,68` (the visualizer fringe)
posts `command=stepEffect value=-1`, and `9SeriesDefault` at `vPlayer@394,309` — the mute button's
mapping colour, found the way harness.md § *Auditing one authored control* prescribes, **median
pixel, never the first** — posts `command=setMute value=1`. Both printed the `ReferenceError` on the
`CLICK` line before. The corpus sweep across the change is **551 of 553 images identical and every
structural invariant byte-identical**; the two that moved are `Revert (1)`, whose authored idle fade
now runs, and `Scooby-Doo_2`, which differs run to run on its own `Math.random()`. Corpus
handler-errors went 69 → 68 — three gone, two new on `Asia`'s own double-escaped `textWidth&gt;width`
that only became reachable once the statement before it ran.
`Tests/NullPlayerAppTests/WMPHandlerElementScopeTests.swift` holds both halves and both guards.

### The element has to have an address, and the authored `id` is not one (W256)

**Both the `with` scope above and the bound `value` global were keyed on `event.targetID`, which is
the skin's own `id` attribute — and the corpus leaves it off wherever it has no script that needs to
name the element.** `anemone`'s ten equaliser bands are
`<SLIDER value_onchange="eq.gainLevel1=value;">` with no `id` at all, so the handler ran with no
scope and no `value`: `eq.gainLevel1 = value` wrote **null** on every move of the drag, the band
never changed, and the thumb settled straight back onto the host's unchanged gain. Reported live as
"an equaliser slider cannot be dragged".

`WMPJScriptEvent` now carries `targetStableID` beside `targetID`, and `WMPScriptContext.perform`
resolves the raising element by stable id where the markup named none. **The dispatch sites already
knew it** — `WMPMainWindowController.handlers(in:event:targetStableID:)` selects the handlers by
stable id, because an element's identifier is not unique across views (W89) — so this is telling the
runtime what the caller had in hand, not a new lookup.

Measured 2026-09-22 over the 184-archive corpus with
`python3 scripts/wmp_slider_drag_census.py` (populations A and A'), which reads each `.wms` out of
its archive — never `grep`, see harness.md § *A corpus number taken with `grep` is not a corpus
number*:

| class | measured |
|---|---|
| `value_onchange` with no `id` — the reported case | **70 nodes / 35 of 184 archives** |
| any handler with no `id` — the scope half | **1,667 nodes / 101 archives** |

**A handler with no address is invisible to every other instrument**: it dispatches, it runs, it
throws nothing, and `SCRIPT-DIAG` stays silent — the only signature is the *argument* the host
command carries. `Tests/NullPlayerAppTests/WMPEqualizerSliderDragTests.swift` asserts the argument
and keeps the control that shows the null.

## A view runs the functions its own `scriptFile` names (W204/W257)

**One `JSContext` serves the whole skin, so two views that each declare their own `.js` and define
the same top-level name collide: the program evaluated last wins every call, in every view.** WMP
gives each view the scope its own `scriptFile` list builds. `Plus! SlimLine` is the case that
reported it — `perfect.js` on `perfectSkin`, `perfectV.js` on `perfectVSkin`, 17 names in common —
and the horizontal view therefore ran the vertical view's `Init()`, whose `EndVideo()` calls
`switchSkin('perfectVSkin')` and put the skin straight back where it had come from.

`WMPScriptContext` records the top-level functions each program defines as it evaluates them, marks
the names **two or more** programs define, and rebinds only those to the installed view's own
programs whenever a view is installed, restored, or run as a windowless dispatcher
(`applyFunctionScope`). Within one view's own list the later program still wins, which is
evaluation order and unchanged.

**The three things it leaves alone are the contract, not omissions:**

- a name exactly **one** program defines stays shared and reaches every view — a skin whose views
  deliberately share a helper is relying on that;
- a view that declares no `scriptFile` of its own keeps the skin's last-loaded binding;
- **non-function globals are one variable in one scope**, here as in the markup. `perfect.js`'s
  `var currView = "perfectSkin"` and `perfectV.js`'s `"perfectVSkin"` are still the same variable.
  No corpus skin has been shown to need otherwise, and two views' `Init`s writing one flag is also
  how these skins share state — measure a case before scoping values (W204).

A case-folded alias from the section below follows the function it aliases when a view rebinds it.

**It reaches 7 of 184 archives** — `Plus! SlimLine` (17 contested names), `holiday_skin` (22),
`Sports` (6), `pharaoh` (2), `portals` (2), `corona` and `9SeriesDefault` (1). That census is worth
re-reading before trusting a re-run of it: the first pass tried UTF-16 before UTF-8 and accepted any
decode with no NUL bytes, so two plain CP1252 `.js` files came back as mojibake with zero functions
in them and the answer was 3 archives instead of 7. Sniff the BOM; a decoder that cannot fail is
the same trap as a `grep` that prints nothing (W256).

`WMP_VIEW_SCRIPT_SCOPE=0` restores the pre-W257 last-program-wins binding — the A/B, in one binary.


## A skin's own function, called in the wrong case (W42)

**JavaScriptCore resolves a global by exact spelling, so a skin that misspells the case of its own
function throws `ReferenceError` and loses every statement after it in that handler.** `elvis.js`'s
`Init()` calls `UpdateMetaData()` against `function UpdateMetadata` on line 17: what went with it
was the rest of `Init` — the two `setColumnResizeMode` calls, the volume slider's position, the
video/visualization pane and `OnPlayStateChange()`. `TDK.wms` binds `onLoad="onLoadVideo();"`
against `function OnLoadVideo`, and six archives bind `onClose="onCloseVideo();"` against
`function OnCloseVideo`.

`WMPScriptContext.aliasCaseFoldedGlobals` installs an alias, and it is **last resort, never a
fold**: only for a spelling that resolves to nothing at all, only when exactly one global
case-folds to it, and only when that global is a function. Element ids cannot be aliased into —
they are objects — and a member call (`player.controls.Play()`) belongs to rule 4's
case-insensitive lookup rather than here.

It runs in two places because the corpus writes the call site in two places. A markup handler is
scanned in `evaluate` before it runs; a **program** is scanned only after the whole set has
evaluated, because the declaration a call needs is usually further down the same file — scanning
`elvis.js` before it ran would have found nothing.

**Three archives declare two top-level names that differ only in case, and they are the reason the
alias is last resort rather than a fold.** `Kids` has both `StartVideo` and `startVideo` with
different bodies, `Cablemusic` has `startProgram`/`StartProgram`, `HOB` has `eqIsOpen`/`EQIsOpen`.
Every one of their call sites resolves exactly, so none of them reaches this path at all, and an
ambiguous fold is declined even if one did.

Measured 2026-09-22 over 184 archives: **16 hold a call site that resolves only case-folded** —
`elvis`, `Plus! HueShifter`, `TDK`, `portals`, `deepbluesomething`, `Secura`, `activate`, `anemone`,
`modernblue`, `holiday_skin`, `Stars and Stripes` and the five-skin US military family. The corpus
sweep across the change is **550 of 553 images identical**, the two that moved being `elvis` and
`Plus! HueShifter` drawing the metadata their handlers now reach, and the third `Scooby-Doo_2`,
which differs run to run on its own `Math.random()` and was cleared with a same-mode control.

**What this does not do is empty the class, and that is the expected shape** (rule 2: unimplemented
is a queue). Each of the four skins that advanced now stops at its *next* genuine gap: `elvis`
`elvis.js:17` → `:21` on `volume_slider`, `Plus! HueShifter` `:15` → `:19`, `TDK` line 2 → 188 on
`g_fUserHasSized`. Those names exist nowhere in their archives in any spelling, so they still throw,
and so does `Plus! Plasma Ball`'s `UpdateMetaData` — **a name no spelling reaches is not this
defect, and inventing a no-op for it is the `inert()` phantom this file exists to prevent.**
`Tests/NullPlayerAppTests/WMPScriptRuntimeTests.swift` holds both call-site halves and all three
guards.


## Ambient `<attribute>_onchange` handlers

**The SDK defines an `_onchange` handler for every attribute of most elements, not a list of five**
(*Ambient Event Handlers*: "when a skin attribute changes value, an event occurs… the name of the
event handler is the name of the attribute followed by `_onchange`"). It is **three** pieces, and
each one is a separate place a name can go missing:

1. **Classification** — `WMPAttributeParser.parse` makes any `*_onchange` attribute a `.handler`.
   A name missing here is not a handler that fails; it is markup classified as a literal, invisible
   to the dispatcher *and* to the `UNKNOWN event` tally. That is the state 387 handlers across 104
   of the 177 measured archives sat in until W129.
2. **Collection** — `WMPScriptViewPlan.attributeChangeHandlers`, keyed by folded attribute, holding
   the **authored** spelling beside the source because the handler reads the attribute by name.
   `value` is deliberately absent: it has its own map and its own two directions (W51/W52), and
   collecting it twice raises it twice in one transaction. The general rule is matched *after* the
   `value_onchange`/`onChange` case for exactly that reason.
3. **Dispatch**, of which there are two, and a name needs the right one:
   * *Element side* — `WMPScriptContext.raiseAttributeChangeHandlers`, in the same transaction as
     the write, bounded the way W87's cascade is: only what the markup declared, each
     `(element, attribute)` at most once, never a re-resolve of the expression set.
   * *Host side* — `WMPMainWindowController.refreshHostState`, off the snapshot diff, for the four
     attributes of the *player* that no script writes and that move underneath the skin:
     `currentPosition` (105 uses / 81 skins), `currentEffectType` (77 / 65), `currentPlaylist`
     (65 / 48), `currentPreset` (40 / 30), `currentMedia` (12 / 9).

**A host attribute needs something to call `refreshHostState` before any of this fires.** Every
other path into it is a track, a 10 Hz clock tick, a transport action or a file open, and the
effect selection is none of them: choosing a visualization from NullPlayer's own menu goes through
`WMPEffectSelection`, so the controller observes `WMPEffectSelection.didChange` explicitly. With a
track playing the position tick hides the gap — the event lands inside 100 ms and looks immediate —
and with the player stopped nothing would have been raised at all. **Check what refreshes the
snapshot before adding a host-side `_onchange`**; a diff nothing runs is a dispatch site that is not
one.

**The failure mode of all three is silence.** Nothing throws, so no diagnostic appears anywhere: the
readout simply keeps the value it loaded with. A headless capture cannot see it either — no
attribute changes in a still — so this class is verified through the live loop, `reference/harness.md`
§ *Driving the app*.

**An attribute with no dispatch site stays off `WMPCorpusReportHarness.supportedEvents`**, whatever
its reach — listing one would drop it out of the tally while it still does nothing, which is where
`onResize` sat for three phases. `textWidth_onchange` (21 skins) and `selectedItem_onchange` (12) are
the current examples: this engine moves neither attribute, so neither has anywhere to be raised from.

**A write-back is safe when the host setter is idempotent, and that is a thing to check rather than
assume.** All 40 `currentPreset_onchange` uses are `mediacenter.effectPreset=currentPreset` — the
handler handing the host back the number it was just given — which settles only because
`WMPEffectSelection.setPreset` early-returns on an unchanged value. A setter that re-applied would
have restarted the visualizer on every preset change instead. Same argument as W51's write-backs,
made at the host rather than at the registry.

**Reading a handler's reach is not reading its result, and W129 is the case that proves it.** Of the
four host attributes, only `currentEffectType_onchange` moves a pixel today: `setVisEffectsText()`
paints `visEffectName.value = currentEffectTitle + " - " + currentPresetTitle`, both of which W101
implemented. The other three were talked about as visible and are not — 96 of the 105
`currentPosition_onchange` uses are `seek.value = player.controls.currentPosition`, a number **W120
already supplies** from the declared range, and all 9 `currentMedia_onchange` uses are
`updateAlbumArt()`, whose body is `backgroundImage = "WMPImage_AlbumArtLarge"`, a WMP built-in
pseudo-resource this engine does not resolve. **Read the handler's body before naming a skin to look
at**; the census says a skin asks, never that anything answers.

---

## Geometry expressions

A `JScript:` geometry attribute is evaluated in the real context, so `view.width - svMain.left`
works because `view` and `svMain` are the same live objects the handlers see, and
`Half(view.width)` works because the skin's own `.js` declared `Half`.

Two rules that are not obvious and are both paid for:

- **The owning element is in scope.** Corona's `width="JScript:svBottomLeft.width-left;"` means
  *this* element's `left`. The expression is evaluated inside `with (thisElement)`, and the proxy's
  `has` trap answers **only** for properties the element genuinely owns — not the open surface —
  because an element that claims every identifier swallows the skin's own functions. That exact
  mistake made `GetEqSliderLeft(1)` resolve to an empty string and cost all ten equaliser sliders
  their geometry.
- **A trailing semicolon is authored.** The corpus writes `JScript:view.width-svMain.left;`, which
  is a syntax error inside a `return (…)`.

Expressions resolve in dependency order, measured by running them once and recording what each one
read. A failing expression costs **itself and nothing else**, and a cycle costs only the keys inside
it. The model this replaced emptied the whole ordered list on any single failure (W21).

---

## Timers

There are **two** kinds and a skin uses both.

`setTimeout`/`setInterval` record a bounded request and keep the **function**, not its text: the
request's `source` is `__wmpTimer:<token>` and firing it invokes the stored closure. Re-evaluating a
function's text — all a stateless runtime could do — loses every variable it captured, which is most
of what a skin's timers are for. Count and minimum period stay inside `WMPPhase0Limits`.

**`view.timerInterval` is the other one, and it is how a `.wmz` animates.** It is a host timer, not a
scene property: a write posts `setViewTimerInterval` and the controller runs a repeating task that
dispatches the view's authored `onTimer` handlers at that period, with zero stopping it. The view's
markup `timerInterval` starts it before any script runs. Corona's compact view collapses its video
panel entirely through this — `RegisterTimerEvent` then `view.timerInterval = leastInterval` — and its
player view declares `timerInterval="4000"` to drive its transport readouts. Wiring `setTimeout` and
not this left both views frozen in their authored state with no diagnostic anywhere to say why.

**An `onTimer` with no `timerInterval` beside it ticks at WMP's default second, not never (W260).**
The SDK's default for the attribute is 1000 ms, and a view that asks for the event and leaves the
period unstated is asking for that — which is exactly the period a clock wants.
`authoredTimerInterval` answered `0` for an absent attribute and **every caller reads `0` as "this
view has no timer"**, so the handler was registered and never once raised. `Stealth` writes its
elapsed readout from `OnTimerTick()` and nothing else, so it sat at the authored `00:00` through a
whole track while the visualizer ran beside it — reported as the skin not playing at all, which is
the shape of this class: *nothing on screen says the timer is the thing that is missing.*
**7 views in 7 archives** author it (`Stealth`, `digitaldj`, `Revert`, `Revert (1)`, `Grinch`,
`Erektorset`, `Josie_and_the_Pussycats`), against 199 views / 90 archives that state a period;
measured 2026-09-22 over 184.

**An authored `0` still means off**, and must stay off — that is WMP's meaning for it and the corpus
writes it deliberately (`corona`'s `viewTiny` opens stopped and starts its own clock from a script).
Only an *absent* attribute takes the default, and only where the view authors the handler, so a view
with no `onTimer` keeps costing nothing.

---

## `sourceURL` is spelled the way WMP spells it (W41)

**Every corpus consumer of `player.currentMedia.sourceURL` classifies the string rather than opening
it, and every classifier is written against Windows syntax** — `cd:` for a disc, a backslash for a
file, anything else for the network. A macOS `file:///Users/…` matches none of them, so the member
resolved, the handler ran to the end, and **nine archives lit their *network* lamp for every local
track**, two of them with a buffering readout behind it. The member has answered since W115; the
value was the whole of what was left under the row.

So the conversion lives at the host boundary — `WMPAudioEngineHost.sourceURLSpelling`, the same seam
that states `crossFadeWindow` in milliseconds because WMP does. A file URL is stated as the
drive-rooted path a Windows player would state; **nothing else is touched**, because an `http://`,
`mms://` or server URL is already the string WMP would report. Nothing in this engine reads the value
back — it is a readout, never a route to the file.

Re-measured 2026-09-22 over 184 archives with the `WMPTextDecoder` decode: **19 uses / 14 archives**,
against the "4 skins" the row carried. The split is what makes the spelling decidable rather than a
matter of taste:

| Idiom | Archives | Needs |
|---|---:|---|
| `search(/cd:/i)` then `search(/\\/i)` — the CD/local/network lamp | 8 | a backslash |
| the same, but `search(/:\\/i)` (`Kids`) | 1 | the drive colon too |
| `indexOf('http')` (`Cablemusic`) | 1 | either spelling works |
| `search('://')` to drop URLs from a query (`digitaldj`) | 1 | **not** `file://` |
| `item(0).sourceURL.indexOf('wmpdvd:')` (`Compact`) | 1 | a playlist item's real URL |
| displayed, as the last-resort middle line (`Revert`) | 2 | a path a person can read |

**A playlist item's `sourceURL` answered the item's *title*** until the same change —
`WMPPlaylistItemSnapshot` carried no URL at all — which is what `Compact` and `digitaldj` were
testing. `name` is the title; `sourceURL` is the URL, spelled as above.

**The two host paths that rebuild `metadata` must carry it.** A local film rebuilt the struct with a
title only and dropped the source with it, so every classifier read a film as a stream; the cast path
has no URL to state and honestly states none.

---

## Recognising an event is not dispatching it

**`WMPAttributeValue.handlerNames` decides what becomes a `.handler` at all, and
`WMPCorpusReportHarness.supportedEvents` decides what counts as implemented.** An event needs a name
in the first **and a dispatch site** to be either. Neither list was ever printed by the harness, so
the whole class of "events the markup declares and nothing ever raises" was invisible:
`WMPCompatibilityReport` collected the counts and compared them, and `compatibilityLines` emitted
only tags and members. That is how `onResize` sat unrecognised through three phases. It is now
`UNKNOWN event <name> ×<n>`.

**Do not add a name to `handlerNames` or `supportedEvents` without its dispatch site.** A recognised
event nothing raises drops out of the tally while still doing nothing — exactly the state `onResize`
was in. Classification is one line; the dispatch site is the real cost, and it is different per
event.

Measured 2026-09-08 over the 179 archives: **4,114 uses**, down from 6,823 (see `harness.md` for
what W51/W52 drained, and for why the distinct-*name* count is not the figure to quote). `onresize`
is absent from that list because it closed in the same change that added the instrument;
`value_onchange`, `openstate_onchange` and `playstate_onchange` are absent because they are now
accepted spellings of events this engine does dispatch. Reproduce with
`scripts/wmp_render_sweep.sh capture <dir> --allow-dirty` and tally `UNKNOWN event` in
`<dir>/raw.txt` by name and by containing `SKIN` block.

---

## A dispatch site with no classification is as silent as the inverse (W56)

**The rule above has a second direction, and it cost this engine 151 handlers.**
`handlers(in:event:)` has accepted `positionchange` wherever it raises `change` since W119 — a
comment there explains the alias and names the corpus — but **`onpositionchange` was never in
`handlerNames`**, so no attribute ever became a `.handler` under that name and the alias could
never match. The site was live, reachable and correct; nothing could arrive at it. In the running
app the symptom is a dispatch line that looks like a working one:

```
[wmp/dispatch] change targetID=volume stable=20 view=TubeFrameView handlers=0
```

`handlers=0` beside a `targetID` whose markup plainly authors a handler is this class, and it reads
identically to a control whose skin authored nothing. **Read a `handlers=0` against the node's own
attributes**, the same check `WMP_RENDER_CLICK`'s `handlers=0` already needs.

**Re-measured 2026-09-22 over the 182 readable archives: 151 uses across 42 archives**, every one
on a `SLIDER` (91) or a `CUSTOMSLIDER` (60) — `wmp_markup_census.sh <outdir> onpositionchange`, then
split by element with a decoder rather than `grep`.

**It is a user gesture, not the clock, and that is W119 staying shut.** `change` is raised only from
`WMPMainView.performSlider` and the popup/listbox selects; the position tick raises `hostsettle` and
`currentposition_onchange`, neither of which is in the alias set. The tick was spelled
`positionchange` once, and classifying this name is precisely the change that would have made that
spelling live again — `testAClockTickDoesNotRaiseASlidersPositionChange` is the guard.

**A correction the fix forced, and it is the more useful half.** The W119 comment in
`refreshHostState` states that a clock tick "was raising all of them ten times a second". It never
could have: the attribute was not a handler, so the tick reached nothing. The rename to `hostsettle`
was right for other reasons and is what makes this fix safe, but **the stated cause was never
verified** — a claim about a handler that was never classified is a claim about markup nothing ran.

### What a binding was already carrying, and what it was not

**Do not read "the event never ran" as "the control did nothing".** `WMPTransportAction.boundAction(for:)`
maps a slider's `value="wmpprop:…"` straight to the host, so for most of these the host effect was
already happening by another route and only the rest of the handler was lost. Split over the 151:

| | uses | what was lost |
|---|---:|---|
| slider **has** a `wmpprop:` value binding | **124** | the rest of the handler — almost always a tooltip the skin writes (`updateSeekToolTip()`, `tooltip = 'Volume = ' + …`) |
| slider has **no** binding | **27** | the handler was the only route: 25 `seek` sliders' tooltips, and `tubeframe`'s `TruBass`/`SrsWow`, the only two where the **host effect itself** never happened |

This is why a live A/B on a volume or balance slider proves nothing — it moves either way. The
signature that separates them is the tooltip: 25 archives author `toolTip="Seek"` and rewrite it to
`MM:SS / total` from this handler, so a seek bar whose tooltip is still the word is the before-state.

**The 124 now write the host twice per drag step**, once through the binding and once through the
script. Every corpus case writes the same property with the same value, so it is idempotent — but a
slider that fights the pointer is what a counter-example to that would look like.

---

## Verified **not** gaps — check this before opening a row

These were `WMP_TASKS.md` § *2c-note* until 2026-09-19; they rank nothing and cannot be taken, so
they live here with the rest of the documented refusals.

The SDK conformance audit (2026-09-11) disproved nine candidate gaps, and **that is the more valuable
half of it**: each is a plausible-looking gap that would otherwise cost a session to chase. Check
this list before opening a row that came from reading the SDK against a corpus scan.

* **`onresize` is dispatched.** `WMPMainWindowController.swift:1162` builds the event as `"resize"`;
  handler names are stored with the `on` prefix stripped, so grepping the sources for `onresize`
  finds only the census table. 47 uses / 19 skins already work.
* **`nineGridMargins`, `resizeImages`, `elementType`, `bottom`, `right`, `accDescription`** — ambient
  attributes with **zero corpus uses**. Absent from the engine and correctly so.
* **`moveSizeTo` and `slideTo`** — ambient methods, **zero calls** corpus-wide. (`resizeTo` is also
  zero and is implemented anyway.) All three are in the vocabulary after W128, which costs nothing:
  the vocabulary is the SDK's list, not a demand tally.
* **`<COLUMN>`, `<ITEM>`, `<SETTINGS>`** — SDK elements with zero corpus uses.
* **`eq.reset()` / `eq.nextPreset()` / `eq.previousPreset()`** — 104 / 91 / 87 skins, and all three
  are implemented (`WMPObjectModel.swift:811-817`). A naive receiver-filtered scan reports them as
  missing; they are not.
* **`scrollingAmmount` / `scrolingDelay` (25 skins, 54 uses), `horizontalAlignemnt` (3), `donwImage`,
  `tootip`, `hegiht`, `visilble`** — **author typos**, copy-pasted across the Plus! family. WMP
  ignores an unknown attribute too, so matching them would be *less* faithful, not more. This is the
  largest single false lead in the whole scan.
* **`transparencyColor="white"` / `clippingColor="white"` (10 / 7 skins)** — feared to be losing the
  declared key to the implicit magenta default. Traced: `colors(_:names:)`
  (`WMPSceneBuilder.swift:820`) delegates to the name-aware `color(_:names:)`, so `declared` is
  non-empty and `implicitColorKey` stays nil (`WMPSceneBuilder.swift:761`). Correct today.
* **`mediacenter.effectType` read as a property (376 uses / 192 files / 130 archives)** — checked while landing W128
  because `effectType` is an SDK `EFFECTS` *method* and the vocabulary gates reads. Every use is on
  the `mediacenter` host receiver, answered by `readMediaCenter` before the element path. Not a gap
  and not a regression risk.
* **`<CONTROLS>` (77 skins), `<VIDEOSETTINGS>` (84), `windowed` (114), `allowAll`,
  `dropDownVisible` (114)** — real gaps, but already tracked as W103 and the documented
  refusals in this file (`<CONTROLS>`/`<VIDEOSETTINGS>` were W111, moved to
  `LOW_QUALITY_TASKS.md` 2026-09-19 — they cost no pixels and no longer rank anything). Not
  re-opened.

---

## Recognised, answered, and nothing behind them (`INERT`)

This was `WMP_TASKS.md` § *2b* until 2026-09-19. It ranks nothing: it is the tier you do not take
runtime work from.

These do **not** stop a handler; they are the ranked list of "properties skins set that nothing
renders", which is Phase 5 rendering work rather than runtime work. Top by skins:
`playlist1.itemPlayingColor` / `.itemPlayingBackgroundColor` / `.disabledItemColor` (15 each),
`timeN.upToolTip` (10 each), the `playlist1.itemSelected*` family (9 each). Full column:
`inert_calls` in `census.tsv`. `vidback.alphaBlendTo` (14) was the second row here and is gone:
W38 made it live, and `setColumnWidth` joined this tier in its place — recognised so it stops
aborting its handler, counted `inert()` because nothing draws playlist columns.

---

## Adding a member

1. Measure first: `WMP_CALL_TRACE=1` over the corpus, and take the top `UNRECOGNISED` row. Check
   § *Verified **not** gaps* before you open anything — the author-typo list there is the largest
   single false lead in the whole scan.
2. Implement it in `WMPObjectModel` — `live` if there is a host behind it, `inert()` if there is
   not, and leave it out entirely if neither is honest.
3. Add it to `WMPJScriptCompatibility.members` in the same change; that table is what the census's
   static `UNKNOWN member` tally is measured against.
4. Re-measure. The next member is now visible; the list you started from is already stale.
