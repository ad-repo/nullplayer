# `.wmz` object model: elements

Moved verbatim from `reference/object-model.md` on 2026-09-25; that file is the router. Read it first.

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
script-text scan in `harness/corpus.md` § *Grepping the corpus's script text*:

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
audio-enhancement members; see [audio-enhancements.md](../audio-enhancements.md) for their typed command
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
[`harness/corpus.md`](../harness/corpus.md) § *Grepping the corpus's script text* — the census matches a tag and can
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
[`harness/corpus.md`](../harness/corpus.md).

**`eq` itself falls through to the element named `eq` (W309).** `eq` is bound as a host global
over any element of that name, so a member the equaliser does not answer — `eq.visible = false` —
came back unrecognised and killed the handler. `US Army`'s `playlistpop()`, `banan()` and `eqpop()`
set their open flag *after* that line, so every toggle opened its pane and never closed it.
`WMPObjectModel.get`/`set`/`invoke` now retry an unrecognised `eq` member against `element:eq`
(`shadowedElement`). In WMP `eq` is only ever the element: `<equalizerSettings id="eq">` in most
skins, a `<SUBVIEW id="eq">` in `Navigator`, whose `eq.visible` writes now really hide that panel.
`python3 scripts/wms_grep.py -c '\beq\.(visible|enabled|alphablend|moveto)\b'` reaches 10
archives: `Navigator`, `Stars and Stripes`, the five `US …`, `Josie_and_the_Pussycats`, `Grinch`
and `gnome`.

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

`dropdownVisible` (12 of the 13) asks for a playlist *chooser* above the rows. The playlists it would
list are answered since W136 (`object-model/library.md` § *The library*), but no chooser is drawn for the attribute yet, on
`ITEMSPLAYLIST` or on `PLAYLIST`.

**Recognition for routing is deliberately wider than the modelled kinds.** `WMPSkinSurfaces` matches
on the authored tag, so any tag ending in `PLAYLIST` counts as a skin-owned playlist even before it
is a kind here. What decides routing is what the skin *declares*, not how much of it this engine
hosts today — and keeping the two rules separate is what stops a future spelling from opening a
second, foreign-looking window on top of a drawer the skin draws itself.
