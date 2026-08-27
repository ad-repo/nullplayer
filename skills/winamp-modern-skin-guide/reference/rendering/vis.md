#### `<vis mode>` — the skin says whether it wants a visualization at all

`1` = **spectrum analyzer**, `2` = **oscilloscope**, `0`/`3` = **off**; an undeclared mode is the
analyzer. A skin's own menu script pins the pairing: Love is War Miku's `visualizer.maki` writes
`bandwidth` (`wide`/`thin`) then `setMode(1)` for its *Spectrum Analyzer* commands and `oscstyle`
(`Solid`/`Dots`/`Lines`) then `setMode(2)` for its *Oscilloscope* ones. Reversed, every skin drew the
other visualization than the one its menu had just asked for, and this skin's shipped default
(`Visualizer Mode` = 1) came up as a scope where its own screenshot shows bars.

MMD3 ships `mode="3"` and its `ShowVISBg` switches between all three, because for six of its nine
display styles the box is filled by the skin's *own* animated layer and the vis must be silent.
Ignoring the mode painted our bars straight over the skin's artwork. `setMode` writes the same
attribute, so honouring it in the renderer is the whole implementation.

A `<vis ghost="1">` takes **no** clicks — Love is War Miku puts an invisible `<layer rectrgn="1">`
beside it as the click target instead, so the menu is reached through that, not the box.

#### The oscilloscope reads PCM, and the host has always had it (B51)

`mode="2"` is drawn from Winamp's own `visdata` waveform — 576 `UInt8` samples per channel centred on
128, **left channel only**, one column per pixel of box width. The mirrored second box is the *skin's*
job (`fliph`), not the renderer's.

It was a spectrum-derived zigzag for a long time on the stated premise that *"the host publishes a
spectrum, not raw PCM"*. **That premise was false the whole time**: `AudioEngine` posts exactly this
array on `.audioWaveform576DataUpdated`, consumer-gated, and vis_classic and the waveform views were
already consuming it. The lesson is the general one — *check what the host already publishes before
building a substitute for it*; a placeholder that survives long enough acquires a rationale.

**The tap is demand-gated and the demand is graph state.** `WinampModernWaveformTap` runs only while
some `<vis>` in the graph asks for a PCM-fed mode — **any**, not all: one scope among five analyzers
still needs it. `WasabiSceneRenderer` recomputes that against the graph's `mutationGeneration` (the
key `sceneNodes()` already uses) and pushes it to the host only on a change. `mutationGeneration` is
the right key because **`mode` has two writers**: `setVisualizationAttribute`, and MAKI's `setMode` /
`setXmlParam` writing the object directly — and a skin's own visualization menu is entirely the
second kind, so anything keyed on the setter alone would miss it.

**Chunks are queued and played out in real time, not overwritten.** `processAudioBuffer` runs once per
2048-frame buffer (~46 ms) and posts every 576-sample chunk it can from inside that one call, so they
arrive three or four at a time. Keeping only the newest discarded three quarters of the audio and left
the survivors 46 ms apart — which reads as a scope that jumps, and is a *discarded-data* problem, not
a frame-rate one. The queue is capped (6 chunks ≈ 78 ms) so the trace cannot drift behind the music,
and a read is a pure function of the clock so every box in a frame draws the same chunk. The renderer
takes the waveform **once per frame** for the same reason: two boxes reading microseconds apart can
straddle a 13 ms boundary, and in Big Bento's butterfly that is a mirror that does not mirror.

Every other `<vis>` attribute is read too — `oscstyle`, `coloring`, `peaks`, `falloff`,
`peakfalloff`, `colorosc1`…`5` — see `compatibility/wasabi-surface.md` for the list and the measured
0…4 falloff scale. **Both falloffs are per second, not per draw**: draws are not a clock (the vis
clock below drops frames when a scene is expensive), so a per-draw constant would make
"Slower…Faster" mean different things on different skins, window widths and splitter positions.

#### What the analyzer actually draws (Phase 34)

Three rules, all of them measured on Ujola Cat, all of them engine-wide:

- **Vis colours take the object's `gammagroup`.** `colorband1`…`16`, `colorallbands`, `colorbandpeak`
  and `colorosc1`…`5` are usually inline `r,g,b` triples, and the named-resource path
  (`resolvedColor`) leaves an inline triple untinted — so an analyzer stays its declared colour while
  the skin recolours around it. Resolve them through `objectColor(_:gammaGroup:)`, which hands a named
  `<color>` back to `resolvedColor` so a themed colour is never tinted twice. Ujola Cat declares all
  22 of its vis colours inline under `gammagroup="Energy"`, and its author's one request was to go and
  play with the skin's colour themes. **`<eqvis>` is deliberately left out**: that skin's own comment
  reads *"note: eqvis doesn't support gammagroup; known bug"* and works around it with white — which
  is Winamp's behaviour, so matching it is correct.
- **Bar height is a decibel, not a magnitude.** `host.spectrumLevels` is a linear FFT magnitude, and
  scaling it straight to the box puts ordinary music along the floor. Map it through
  `WinampModernScriptRuntime.visByte(forMagnitude:)` — 20·log10 over a 60 dB window — the same
  function `getVisBand` and the VU meters answer in, so the drawn analyzer and a skin's scripted
  meters can never disagree about the same audio. (Phase 29 fixed the VU meter, Phase 30 `getVisBand`;
  the drawn analyzer was the third and last site.)
- **`bandwidth` picks the band *count*.** `wide` is 19 bands, `thin` up to 75, each collapsed from the
  tap by max-per-bucket and clamped so a bar is at least 1px wide. It used to pick only the bar
  *thickness* while the bars stayed one per FFT bin, so every skin drew the same 64 hairlines — and
  silently dropped the top 11 of the tap's 75 bands. Bars are laid out on **whole pixels**: at a
  fractional slot the 1px gap antialiases into a smear and a `wide` row reads as one solid block.

`colorbandpeak` is the falling cap over each bar, held at the running max and decayed a fixed amount
per draw, and painted in the band's own colour when the skin declares no peak colour.

#### NullPlayer's own analyzers in a skin's `<vis>` box (B53, 2026-08-26)

The `<vis>` box stays the skin's — its geometry, its colours, its `mode` — and **what paints it** is a
per-skin choice between three engines, all `WasabiVisRenderer` implementations behind B51's seam:

| Choice | Engine | Input |
|---|---|---|
| `Skin's Own` (default) | `WasabiBuiltInVisRenderer` — Winamp's analyzer and oscilloscope | spectrum bands / the 576-sample tap |
| `Cava` | `CavaVisRenderer`, a `CavaPresenter` on the `winampModernVisBox` scope | its own full-stereo tap |
| `vis_classic` | `VisClassicVisRenderer`, scope `winampModernVisBox` | **B51's existing 576-sample tap** — no second audio consumer |

Selection lives on `WasabiSkinRuntime.spectrumAnalyzer` (skin-wide, beside `componentBucket`, because
one skin draws its `<vis>` in several containers) and persists per skin in `@nullplayer.vis` /
`engine`, stored **by name** so a list reorder cannot re-point it. The default is always the skin's
own: a skin looks the way its author drew it until the user says otherwise.

**Two of the skin's compositional habits do not transfer, and both are decided in `WasabiRenderer`.**
`fliph` is dropped for a non-skin engine (`flipTransform(…, suppressHorizontal:)`) — Winamp's
butterfly mirrors a row of *bands*, and a mirrored frequency sweep runs backwards. And a **run** of
adjacent boxes is handed the whole run's rect with a clip to each box
(`visualizationRows(boxes:)` — same top edge, same height, touching within 2px), so Big Bento's
`main.vis` + `main.vis2` show one continuous analyzer instead of two copies of the same one. Its 10px
`flipv` reflection strips are a run of their own and still reflect.

**vis_classic processes once per buffer, draws once per box.** `processAndDraw` runs the FFT *and*
ages the core's bar/peak decay, so calling it per box would make the falloff a function of how many
boxes a skin declares. An identical input buffer means "another box of the same frame" — the renderer
samples the waveform once per frame — and takes `drawAtSize` instead.

##### Gain: three engines, one loudness — where to tune it

The three measure the same audio on scales that were never meant to agree. Winamp's analyzer maps its
bands through a **decibel** curve (`visByte(forMagnitude:)`), so ordinary music fills the box and it
reads *hot*; Cava normalises linearly under its own slow auto-gain; vis_classic scales against a
canvas cut for a 128px-tall window. Side by side in a 30px skin box, the first is hot and the other
two are cold. Reported live, and settled by eye — which is the only instrument that settles "hot".

**All four numbers live in one place: `WasabiVisStyle.Gain`.** Change them there and nothing else
moves.

| Constant | Value | Applied |
|---|---|---|
| `builtInAnalyzer` | 0.8 | to the band fraction, after the dB byte |
| `builtInOscilloscope` | 1.0 | to the sample excursion, **clamped** to the box so a hot scope flattens instead of drawing outside the author's rect |
| `cava` | 1.45 | to the bars, clamped at 1 |
| `visClassicInput` | 1.6 | to the **input** samples about the 128 centre line — the core runs its own FFT and paints its own bars, so there is no output height to scale without stretching its artwork |

On top of that sits **Sensitivity** (`WinampModernVisSensitivity`), the user's five-step adjustment as
a percentage of the calibration: 60 / 80 / **100** / 130 / 160, so `Normal` is exactly the tuned value
and a step means the same thing for every engine. It is stored **per engine, not per skin** — it
calibrates an engine's own scale, so a Cava turned up once stays up everywhere, which is the opposite
of the engine *choice*. The skin's own engine has one Sensitivity covering both its modes and two
calibrations under it. Reading it is memoized (`invalidateCache()` for tests); a change repaints
through `WindowManager.repaintWinampModernVisualization()`, because the visualization clock only runs
on audio and would otherwise not show the new gain until playback resumed.

##### The menus, and the one that is not ours

Both routes offer the same thing: the engines are **mode rows in one radio group** beside Winamp's own
`Spectrum Analyzer` / `Oscilloscope` / `Off`, followed by the running engine's own settings
(`<Engine> Settings ▸`, or Sensitivity alone for the skin's engine). They are one answer to one
question — what is in this box — so they are one group, and picking a skin mode hands the box back to
Winamp's engine while picking an engine switches a box the skin had turned off back on.

- **Skins → Modern → Spectrum Analyzer** in the menu bar, which no skin can intercept.
- **Right-click on the box**, including on skins that trap that click: a skin's own menu is *ours to
  build* (`presentScriptPopup` turns MAKI's `PopupMenu` tree into an `NSMenu`), so the section is
  inserted into Big Bento's own visualization page. Its `Classic Visualization` row is dropped there —
  it is Winamp's *plugin* switch, which NullPlayer does not host, and it is the same question the
  group now answers.

> **The bug worth remembering.** Our rows leave the script's command id at `0` deliberately —
> "nothing chosen" — and a **submenu parent carries `0` too**, which is exactly what Big Bento's own
> `Spectrum Analyzer ▸` row is. Collecting `0` into "the skin's mode rows" made every pick of ours
> select an engine and then hand the box straight back to the skin's, four milliseconds later, with
> nothing on screen to say why. `commandIDs(of:)` excludes zero.

#### The analyzer a `<component>` box draws (BB9, 2026-08-24)

A `{0000000A}` holder that the view layer has *not* filled with the host's engine draws a spectrum
analyzer — see [components.md](components.md) for which holders those are. It is no longer a
placeholder: the slot's default content in Winamp *is* an analyzer.

`drawVisualizationBars` has **no `<vis>` element** to take its styling from, and deliberately borrows
none:

- **Band count comes from the box** (~1 band per 6pt, clamped to the tap's own resolution), not from a
  donor's `bandwidth`. Borrowing was tried and is wrong — `bandwidth="wide"` is 19 bands, sized for
  that skin's own 144px box, and 19 bands across a 1400px pane is a row of slabs.
- **Colours come from `WasabiPalette`** — the same route every other NullPlayer-owned surface inside a
  `.wal` takes, so a colour-theme switch recolours it with everything else. Bars are a vertical
  gradient from `listText` down toward `contentBackground`; peak caps are `listText`.
- Whole-pixel bar slots and the `<vis>` analyzer's falling caps and decay, sharing the same
  `analyzerPeaks` store — a `<component>` holder and a `<vis>` are different objects, so the keys
  cannot collide.

