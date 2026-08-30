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
Both step tables were reviewed against B73's unclipped input and left as they are — they were cut
against the *shape* of a fall, not against how loud the bands were, so replacing the input did not
move them.

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
- **Bar height is a decibel — measured by the analyzer's own FFT, not by the host's display tap.**
  See *The analyzer runs its own FFT* below. This bullet used to say "map it through
  `visByte(forMagnitude:)`, because `spectrumLevels` is a linear FFT magnitude". That premise was
  false and cost two corrections: the array is already logarithmic *and* already saturating.
- **`bandwidth` picks the band *count*.** `wide` is 19 bands, `thin` up to 75, each collapsed from the
  tap by max-per-bucket and clamped so a bar is at least 1px wide. It used to pick only the bar
  *thickness* while the bars stayed one per FFT bin, so every skin drew the same 64 hairlines — and
  silently dropped the top 11 of the tap's 75 bands. Bars are laid out on **whole pixels**: at a
  fractional slot the 1px gap antialiases into a smear and a `wide` row reads as one solid block.

`colorbandpeak` is the falling cap over each bar, held at the running max and decayed at
`peakfalloff` per second, and painted in the band's own colour when the skin declares no peak colour.
**A cap is drawn only once it has cleared its bar by a visible gap** (`minimumCapGap`, 1pt) rather
than whenever `peaks > bar` — see *The white line across the bar tops* below.

#### The analyzer runs its own FFT (B73, 2026-08-29)

**`host.spectrumLevels` is a display array, not an analysis result**, and every analyzer defect that
survived Phase 34 traced to reading it as though it were one. `AudioEngine` has already taken
`20·log10` of its bins, normalised them, clamped them and smoothed them before any skin sees them.
Measured live with `WINAMP_MODERN_VIS_TRACE=1`: **52 of its 75 bands at exactly 1.0** on a loud
frame, mean 0.98. That single fact is three symptoms — no dynamic range, flat bass (`.accurate`
clamps a 20 dB window with no frequency weighting), and the white line B54 reported. It also made
every `.wal` skin's analyzer depend on `spectrumNormalizationMode`, a preference owned by a different
window's context menu, which silently changed the look of the analyzer twice in one session.

It took two attempts to see that, and the shape of the mistake is worth keeping. First the decibel
curve was *added* (Phase 34), on the premise that the tap was linear. Then it was *removed*
(1b1880aa) once the tap was measured — two compounded logarithms had squeezed the whole 0.1…1.0
range into the top third of the box. Neither attempt was the fix, because both were curves over a
clipped input: **you cannot uncompress a signal that has already been clipped, and a peak-hold over
one can only ever draw a flat line.**

`WinampModernAnalyzerTap` replaces the input. Shaped after `WinampModernWaveformTap` — read that
file's comment first — with the work split across three threads and none of it in the wrong place:

| Thread | Does |
|---|---|
| The audio/posting thread | a lock, two array retains, an unlock. Never `queue: .main`, and **never the FFT** |
| Its own serial `.userInteractive` queue | Hann window, `vDSP_fft_zrip` over 2048 samples, publishes the half-spectrum. Latest-value: a buffer arriving mid-analysis replaces the waiting one rather than queueing, so the bars cannot fall behind the sound |
| The main thread | maps that half-spectrum onto the band count a box asks for — a max per band and a logarithm. Memoized per analysis and per count, so the four boxes of Big Bento's butterfly share one FFT |

**The input is `.audioStereoPCMFullDataUpdated`** — 2048 `Float` per channel, consumer-gated by
`addFullStereoConsumer`, the same tap Cava reads. Deliberately *not* B51's 576-sample `UInt8` visdata
tap: 8-bit quantisation caps the usable range near 48 dB and 576 samples give ~86 Hz bins, which
cannot resolve bass at all. 2048 samples give ~21 Hz bins at full precision.

**One dB mapping, for both analyzer sites** — `WasabiBuiltInVisRenderer.drawAnalyzer` and
`WasabiRenderer.drawVisualizationBars` — so the `<vis>` box and a `{0000000A}` holder can never read
the same audio at different heights again. Three constants, all in the tap, all tuned by eye:

| Constant | Value | What it is |
|---|---|---|
| `fullScaleBandDB` | −30 | the per-band level that fills the box. **Not 0 dBFS**: one FFT band of a full-scale mix sits ~30 dB below full scale, and referencing 0 put the top third of the box out of reach — measured at 0.52–0.64 peaks, a row that never fills its box |
| `windowDB` | 45 | how far below that the floor sits. Narrow on purpose: at 60 dB the room tone before playback drew a third of the way up the box |
| `weightingDBPerOctave` | 3.0, referenced at 1 kHz | the frequency weighting `.accurate` never applied at all. Music is roughly pink, so unweighted the row is a wall of bass with nothing to the right of it |

**The band count is the caller's.** The analysis is log-spaced across 20 Hz–20 kHz for whatever count
it is given, so `bandwidth="thin"` asks for 75 and gets 75 — there is no bucket-collapsing left in
either renderer and no ceiling from whatever resolution another consumer happened to want. (This
changed the pixel columns in a 64px test box from 16 bands to 19; a test sampling a bar had to move
one pixel.)

**`getVisBand` and the VU meters stay on `spectrumLevels`.** Those are script-facing contracts, and
a second analysis path behind them would be a new way for a skin's scripted meters to disagree with
the host.

**Demand is gated on the graph**, on the same `sceneGeneration` key and beside the waveform demand
(`refreshWaveformDemand` answers both). Two flags rather than one, because a skin can want either
alone: a scope needs the waveform and not the FFT, an analyzer the FFT and not the waveform, and a
box drawn by Cava or vis_classic needs neither — both bring their own input. A `{0000000A}` holder
counts towards the analyzer demand, which is why it is not simply a filter over `<vis>`. It is
computed **whole-graph**, not against this renderer's `hostedVisualizationHolders`: that is view-layer
state, it differs between the renderers of one skin, and they all push to a single host that does not
refcount. Erring towards running the tap is the safe side — the cost is one consumer in
`processAudioBuffer`, not a wrong picture.

#### The low end is narrower than the analysis (2026-08-30)

At 21.5 Hz bins a log-spaced band below ~500 Hz is **narrower than one FFT bin**, and the original
mapping snapped each band to integer bin indices — `Int(lowHz / binWidth)` to
`Int(highHz / binWidth) + 1`. So several neighbouring bass bars read the *identical* bin while the
one band that happened to step across a boundary jumped the whole difference between two bins in a
single bar. A bass note drew as a flat plateau with a cliff beside it: the aggressive jaggedness
that only ever showed in the low end, because that is the only part of the row where a band is
narrower than the analysis.

A band now takes the spectrum **interpolated at its two edge frequencies**, peak-held with every bin
it fully contains. Adjacent bands share an edge and therefore share that value, so the row is
continuous by construction; a band wider than a bin — everything above ~500 Hz — is still the
peak-hold it always was, which is what keeps the top of the row Winamp's.

**The rise is smoothed as well as the fall — but a bar does one or the other, never both.** The
fall was fixed first (`falloff`, per second) and the rise was left assigning the band outright, so a
bar jumped the whole box between two frames and the row read as *frantic* rather than fast.
`WasabiVisStyle.risen` is a one-pole approach with `barAttackSeconds` = 30 ms, engine-wide like the
falloff tables and used by **both** analyzer sites. Short on purpose: two thirds of a jump lands in
the first frame, ~96% by the third, and anything long enough to see as smoothing is long enough to
see as lag.

> **The mistake worth keeping.** The first version subtracted `barStep` and *then* smoothed back up
> toward the band, every frame. Applying both rates at once breaks the invariant the original
> `max(level, bars - barStep)` had — **a bar is never below its own band** — and leaves the two
> settling at an equilibrium the band cannot reach. Measured with `WINAMP_MODERN_VIS_FRAMES=30` at
> the `{0000000A}` site, whose falloff is 10/s: `level=0.752 bar=0.615`, and a band pinned at
> `level=1.000` drew at **0.837** of the box for ever. On screen that is not smoothing, it is a row
> hunting a target it never reaches — reported as jumpy and staggered, and worse than no smoothing
> at all. The shape is `level > previous ? risen(…) : max(level, previous - barStep)`: the fall is
> byte-for-byte what it always was, and only the rise is new.

#### A no-op resize is not free — and the analyzer is where you see it

`WasabiSceneRenderer.resize(to:)` marks **every object in the skin** dirty (1,727 on Big Bento) and
drops the warped and pre-scaled bitmap caches with them, so the next frame re-scales the skin's
whole artwork. It used to do all of that even when the clamped size equalled the size the canvas
already had — and a skin's *own* container animation proposes an unchanged size on most of its
ticks: Big Bento's track notifier slides in and out by writing container geometry from
`tickTargetAnimation`. Every container in one skin shares one object graph, so the cost landed on
the **player's** scene, and the spectrum analyzer stuttered every few seconds while the oscilloscope
and the NullPlayer engines — which repeat their last frame rather than decaying against wall-clock
elapsed — did not show it nearly as clearly.

`resize(to:)` now returns early on an unchanged canvas, and `applyCanvasResize` asks the renderer
*first* so an unchanged tick also skips `invalidateRectCaches` (a full window repaint plus a palette
push to every hosted surface) and `dispatchResize` (`onResize` through the interpreter for every
object in the container). Measured with `WINAMP_MODERN_RESIZE_TRACE=1` + `MUTATION_TRACE`: one
no-op tick cost `writes=5797 writers=1727`; afterwards `WINAMP_MODERN_VIS_STALL=120` reports **no**
late tick at all across 50 s of settled playback.

#### Open: the analyzer's input arrives ten times a second (2026-08-30)

**Unfixed, and measured.** `AudioEngine` installs its mixer tap with `bufferSize: fftSize` (2048),
but that is a *request*: this mixer delivers **4410 frames every 100 ms**
(`WINAMP_MODERN_VIS_GAPS=1` → `buffers=11 rate=10/s frames=[4410x11]`). The full-stereo post keeps
the first 2048 frames and discards the other 2362, so the analyzer gets one spectrum per 100 ms,
computed from 46 ms of it — **10 updates a second against a 30 Hz repaint, and 54% of the audio
never analysed at all.** Between updates the bars only fall, so the row holds, falls, and jumps.

This is also why the **oscilloscope has never had the problem**: `processAudioBuffer` posts *every*
576-sample chunk of the same buffer and `WinampModernWaveformTap` queues them and plays them out, so
the scope sees all of the audio. The analyzer's tap is deliberately latest-value on the stated
premise that a spectrum "barely moves across one 46 ms buffer" — the premise is about a 46 ms buffer
that does not exist here, and 100 ms is a fifth of a bar at 120 bpm.

**The buffer size cannot be asked down — measured, not assumed.** An isolated harness (a player
node into `mainMixerNode`, a tap on the mixer, exactly the app's shape) requesting 512, 1024, 2048
and 4096 gets **4800-frame buffers, 10 a second, in all four cases**: `installTap(bufferSize:)` is a
hint this device ignores completely. So the cadence is a property of AVAudioEngine's tap, not
something a smaller request can fix, and 4410 in the app is the same 100 ms at 44.1 kHz.

**One fix was attempted and reverted.** Publishing the whole buffer on a notification of its own,
windowing it at 50% overlap, and playing the resulting spectra out on the waveform tap's clock was
worse on screen, not better — the playout adds up to a buffer of latency, its interval landed on
almost exactly the 30 Hz read rate so it alternated between repeating and skipping a spectrum, and
an empty `current` before the first advance makes `bands` answer `[]`, which stops the analyzer
drawing at all (Big Bento's butterfly disappeared). Anything attempted here should be judged on
screen before it is kept, and the latency is as visible as the steppiness.

**What is done instead: nothing is faked, the motion is carried.** Two changes, neither of which
adds a millisecond of latency, and together they are what makes a 10 Hz input read as continuous at
30 Hz:

- The window is taken from the **newest** `fftSize` frames of the buffer rather than the oldest, so
  a spectrum is no longer up to 54 ms stale before it is drawn — half the interval between two
  spectra, previously spent for nothing.
- The `{0000000A}` holder's bar falloff is **`Moderate` (4/s), not `Faster` (10/s)**. At 10/s a bar
  falls 0.33 of the box in one 30 Hz frame — more than a step of the input ever is — so every
  downward move landed whole in a single frame and the row stepped at the input's rate on the way
  down while the rise glided over three. Half-smoothed motion reads worse than either.

The bands still change ten times a second; what changed is that the bars no longer arrive at each
new value in one frame.

#### The white line across the bar tops (B54)

Reported live on Big Bento Modern, worse at `bandwidth="thin"`, and **two** causes stacked under one
symptom. The bandwidth clue pointed at geometry and that hypothesis was wrong: it was reported at
`wide` too, where 19 bands in 144px is a 7.6px slot and nothing abuts.

1. **Parked caps.** `peaks[index] = max(bar, peaks - peakStep)` over a clipped input latches every
   band to the identical 1.0 and then bleeds off at 0.35–2.4/s, so the caps sat along the top of the
   box while the bars moved below them. Bandwidth-independent, which is why it showed at `wide`.
   Fixed by the tap above — a cap cannot latch to a clip that no longer exists.
2. **Caps touching their bars.** With the clipping gone the caps tracked the music, and the symptom
   changed rather than vanishing: `peaks > bar` is true the instant a bar falls by a *fraction of a
   pixel*, and the cap it then paints shares an edge with the bar. That is not a floating cap, it is
   a brighter fringe along the top of the row — and at `thin`'s 75 bands in a 144px box the fringe is
   continuous. Hence `WasabiBuiltInVisRenderer.capClears`: a cap draws only with `minimumCapGap`
   (1pt) of clear space above the bar, and otherwise not at all. Both analyzer sites use it.

The lesson is the ordering one. The second cause was invisible while the first was in place — with
every bar pinned at 1.0 the caps were *inside* the bars and `peaks > bar` rarely held — so fixing the
input did not close B54, it uncovered the rest of it.

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

- **Band count comes from the box** (~1 band per 6pt), not from a donor's `bandwidth`. It is no
  longer clamped to the tap's resolution — since B73 the analysis is log-spaced for whatever count it
  is asked for. Borrowing was tried and is wrong — `bandwidth="wide"` is 19 bands, sized for
  that skin's own 144px box, and 19 bands across a 1400px pane is a row of slabs.
- **Colours come from `WasabiPalette`** — the same route every other NullPlayer-owned surface inside a
  `.wal` takes, so a colour-theme switch recolours it with everything else. Bars are a vertical
  gradient from `listText` down toward `contentBackground`; peak caps are `listText`.
- Whole-pixel bar slots and the `<vis>` analyzer's falling caps and decay, sharing the same
  `analyzerPeaks` store — a `<component>` holder and a `<vis>` are different objects, so the keys
  cannot collide.

