# WMP WOW and TruBass

Read this before changing the WMP enhanced-audio controls or their DSP. These are independent
approximations, not the licensed SRS algorithms shipped in Windows Media Player.

## Sources and intended sound

- [Stereo butterfly discussion](https://forum.pdpatchrepo.info/topic/9645/stereo-butterfly-effect-aka-the-wmp-srs-wow-effect): the originally requested WOW model mixes inverted mono back into stereo. It changes the mid/side ratio, and it does not synthesize spatial information from mono. **We no longer implement it that way** — taken literally it is a volume fader; see *Butterfly DSP*.
- [FFmpeg `af_extrastereo`](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_extrastereo.c) (LGPL) is the arithmetic we do use, and [Airwindows Srsly3](https://github.com/airwindows/airwindows) (MIT) is the closest open model of an actual SRS box. NullPlayer is GPL-3.0-only, so both are license-compatible to borrow from; [Calf](https://github.com/calf-studio-gear/calf)'s bass enhancer is GPL-2.1-**only** and therefore read-only for us.
- [SRS low-frequency enhancement design, US6285767B1](https://patents.google.com/patent/US6285767B1/en), especially figures 12–15: a low-bass envelope controls enhancement of existing mid-bass content; speaker size changes the filter bank. This is the basis for our TruBass approximation. No exact WMP source or tuning was found.
- [Microsoft EQUALIZERSETTINGS](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/equalizersettings-element) defines the skin API. [speakerSize](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/equalizersettings-speakersize) is **0 headphones, 1 normal, 2 large**. Do not infer this order from the pictures. [truBassLevel](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/equalizersettings-trubasslevel) ranges from 0 to 100, defaults to 50, and is gated by enhancedAudio.

## Ownership and control path

`Audio/WMPWOWAudioUnit.swift` contains the butterfly kernel, custom AU and `WMPWOWController`.
`Audio/WMPTruBassDSP.swift` contains the bass filter bank. These files live by the audio engine because
both playback pipelines use them; no skin parsing or AppKit code runs in their render callback.

The skin uses `eq.enhancedAudio`, `eq.wowLevel`, `eq.truBassLevel`, `eq.speakerSize`, and the read-only
`eq.currentSpeakerName`. Those five reach `WMPObjectModel`, then four typed commands through
`WMPMainWindowController` and `WMPAudioEngineHost`. Bound slider writes have matching
`WMPTransportAction.boundAction` entries. `WMPEqualizerSnapshot` and `WMPObservablePropertyRegistry`
return the same state to bindings; `WMPJScriptCompatibility` lists the implemented members.

Skin script writes update the transaction snapshot immediately. This matters for both
`eq.enhancedAudio = !eq.enhancedAudio` and the corpus's speaker-cycle idiom:

```js
if (eq.speakerSize == 2) eq.speakerSize = -1;
eq.speakerSize++;
```

The temporary -1 exists only in the script transaction; it sends no engine command. The following
increment sends 0. Clamping -1 to 0 immediately would skip headphones on every wrap.
Non-finite numeric writes are ignored; levels clamp to 0–100 and committed speaker indices to 0–2.

`eq.crossFade`, `eq.crossFadeWindow` and `eq.normalization` are **not** part of this DSP; see
*Graph integration and mode isolation* below.

Defaults: enhancements off, both strengths 50, headphones. The controller persists all four values
in UserDefaults (`srsEnabled`, `srsWOWLevel`, `srsTruBassLevel`, `srsSpeakerSize`) when `AudioEngine`
constructs it with `.standard`; tests construct it without defaults. It does not reuse or overwrite
graphic-EQ, tuning, or normalization preferences.

**Playback Options ▸ SRS** is the app-wide surface: WOW Effect and TruBass level submenus (Off / 25 /
50 / 75 / 100) and a Headphones toggle (speaker 0 ↔ 1). A level shows Off unless `enabled` and above
zero. Because one `enabled` flag gates both effects, `WMPWOWController.setMenuLevel` zeroes the
other effect when a level is chosen while disabled, and the flag follows whether either level is
above zero.

## Graph integration and mode isolation

The existing Reference Tuning controller is the ownership model: one local node and one independent
node for every primary or Sweet Fades streaming player. The controller keeps weak streaming references.
New streaming nodes inherit all current settings immediately.

- Local: player nodes → mixer → EQ profile → reference tuning → graphic EQ → WOW/TruBass → main mixer.
- Streaming: existing balance → EQ profile → graphic EQ → reference tuning → WOW/TruBass, attached
  through AudioStreaming's `attach(node:)`. Streaming tempo remains owned by AudioStreaming's rate node.
- Local graph reconnect and disconnect include the enhancement node, so device changes and sleep
  rebuilds cannot strand the effect outside the graph.
- **Failed-graph replacement reuses this node; every other local node is new.** `localNode` is a
  `let`, so `replaceFailedAudioGraph` does not replace it, and `reconnectAudioGraph` re-attaches it
  to the new `AVAudioEngine`. That works only because the failed engine has been released by then,
  which detaches its nodes: `testReplacementCarriesTheSRSNodeIntoTheNewGraph` passes for both
  failure stages. Hold any strong reference to the old engine (a test that kept `localNode.engine`
  did) and the attach throws on every retry — recovery stays deferred and the graph never comes
  back. Not seen in the app (checked 2026-10-10). If it ever is, make it `private(set) var` with a
  `replaceLocalNode()`, as `PitchTuningController` and `EQProfileController` do.

**Crossfade is not part of this, and the contrast is the rule.** A `.wmz`'s crossfade button reaches
`eq.crossFade` / `eq.crossFadeWindow`, which bind straight to `AudioEngine.sweetFadeEnabled` and
`sweetFadeDuration` — the same app-wide Sweet Fades every other skin family drives from its own menu
— and `eq.normalization` binds to `volumeNormalizationEnabled` the same way. Those three
`WMPTransportAction` cases carry **no `.wmp` gate**, and `.setEQEnabled` beside them is the existing
precedent. The WOW group is likewise ungated: it is the app-wide SRS option from Playback Options,
and gating it would be scoping a preference the user shares. The only translation is units: WMP states the window in
**milliseconds** (the corpus writes 7000), `sweetFadeDuration` is seconds, and that conversion lives
at the host boundary in `WMPAudioEngineHost` and nowhere else. See
[object-model/elements.md](object-model/elements.md) § *The `eq` object and the element are one surface (W39)*.

There is no mode gate: the effect runs in every skin family whenever SRS is enabled. The node
remains connected to avoid rebuilding a playing graph on every toggle, and receives zero effect
targets while disabled. After the short ramp, dry samples pass through exactly and filter work is
skipped.

These shared paths are necessary: a skin view or host adapter can send controls but cannot transform
rendered audio. A spectrum tap is an observation path, not an output effect. Editing graphic-EQ bands
would overwrite unrelated user settings. The dedicated AU avoids both alternatives.

Remote casting passes media URLs to another renderer and does not include this DSP. VLC video audio
also bypasses these AVAudioEngine pipelines. This feature applies to local audio files and HTTP audio
streams, not remote speakers or VLC video sound.

## Butterfly DSP

Widening **adds the side signal**; it does not subtract the mid. With
`a = 1.4 * wowLevel / 100` and `S = (L - R) / 2`:

```
Lout = L + a*S
Rout = R - a*S
```

`Lout + Rout == L + R` for every sample, so the centre — where a mix keeps most of its level —
survives the whole slider travel, and mono passes through bit-exact. Side gain reaches `1 + a`,
2.4x at WOW 100. FFmpeg's `af_extrastereo` (LGPL) is the same arithmetic and defaults to 2.5;
Airwindows' MIT-licensed Srsly/Srsly2/Srsly3 model SRS boxes with narrow mid and side EQ bands
instead, and stage `gainM`/`gainS` so widening cannot decay into a level change. Both are worth
reading before retuning this. No open-source implementation of the actual SRS WOW exists — it was
licensed IP, and the `srs-audio-sandbox` GitHub org is promotional, not source.

**The original implementation widened by cancelling the centre** (`Lout = L - a*M`), which raises
the mid/side ratio purely by discarding mid: at WOW 100 a centred mix lost 80% of its level and
mono was attenuated 80% for no width at all. The slider was a volume fader. If a future change
proposes reaching width by touching the mid, that is this defect returning.

Only side content above `WMPWOWKernel.wideningCutoff` (180 Hz, one-pole) is added. Deep bass carries
no usable image, and widening it spends the headroom that bounds everything above it. The coefficient
is recomputed only when the sample rate changes, never inside the sample loop.

Unlike the old kernel, coefficient magnitudes no longer sum to one, so the addition **is** clamped —
`WMPWOWKernel.boundedWidening` mirrors `boundedAddition`, but the addition is antisymmetric so both
channels constrain it. Zero always lies inside that interval for in-range input, so clamping can only
shorten the widening, never invert the image; over-range input is widened not at all. Raising the
ceiling further trades reach for how often loud, already-wide frames hit that clamp.

Because the addition is filtered, it is phase-shifted rather than a scaled copy: **an individual
sample's L-R may narrow in passing.** Width is an energy property of a block here, and tests must
measure it that way. The target slews at `1/(0.020*sampleRate)` per sample; returning to zero
restores exact dry values and clears the filter state so no stale bass returns after a bypass.

## TruBass DSP choices

Our implementation uses five unity-peak second-order band-pass biquads at 60, 100, 150, 200 and 250 Hz
(Q=1). A 100 Hz low-pass biquad (Q≈0.707) supplies the control envelope. These digital filters,
10 ms attack/100 ms release envelope followers, and the following gain limits are our implementation
choices, not recovered WMP coefficients.

Each band's extra gain is `min(3, subEnvelope / max(0.001, bandEnvelope))`, weighted by one quarter
and the 0–1 TruBass strength. Normal speakers select the four upper bands, large speakers the four
lower bands. Headphones interpolate those responses equally. Speaker selection crossfades the
60/250 Hz weights rather than changing live coefficients. Both that weight and strength slew over
20 ms full scale. Coefficients are rebuilt only when render resources are allocated for a new rate.

The detector reads the original mid signal **before widening**; the common bass contribution is added
after widening. Thus WOW does not starve TruBass's detector. Mono can receive bass enhancement;
multichannel buses pass through. This design reinforces existing content rather than synthesizing a
complete harmonic series from a pure sub-bass tone.

Only the added bass contribution is restricted to the available shared L/R headroom, and it is
restricted by **moving a gain, not by reshaping the waveform** — `limitedAddition`, not the raw
`boundedAddition`. The gain falls immediately to whatever the current sample allows, so the hard
bound still holds exactly for in-range input, and recovers over 150 ms. The original signal is not
globally limited and the L−R difference stays intact; it is not a transparent mastering limiter, and
a loud passage audibly ducks the enhancement rather than distorting it.

**This is the fix for "TruBass distorts below half strength."** Applying the bound per sample is a
clipper: it flat-topped the added bass wherever the mix was loud, and over-range input — a hot master,
or a graphic-EQ boost ahead of us — dropped the addition to zero outright, switching the bass on and
off sample by sample around every peak. Measured on 50 Hz under a 1 kHz tone at TruBass 40, THD was
1.0% at 0.99 peak and 2.6% at 1.15; with the gain limiter all three cases sit under 0.5%. The drive is
what makes this reachable so early: on a kick the addition peaks near 36% of the input peak at TruBass
40, roughly +3 dB of bass into a master with none to spare. If the enhancement ever needs to be
stronger on loud material, the drive is the number to revisit — clamping harder is what caused this. Off/zero bass contributes exactly zero. Filter
state is cleared on the fully dry path to prevent stale bass from returning after a long bypass.

## Render and verification invariants

The custom AU accepts matching, noninterleaved Float32 bus formats. It preallocates scratch buffers
for `maximumFramesToRender` during resource allocation, supplies their memory when the caller passes
null output pointers, and propagates input-render errors. It performs no file I/O, dispatch, logging
or deliberate allocation in the sample loop. Control settings are one coherent lock-protected value;
the render thread uses only `withLockIfAvailable`, retaining its previous target on contention.
Filter histories and smoothing state belong exclusively to each node's render thread.

`WMPWOWTests` covers butterfly math, bounded peaks, exact dry samples, ramping, script commands,
speaker wrap, bass response, and offline AU rendering. Preserve offline rendering tests when changing
graph integration: a kernel test cannot detect a silent or unconnected AU. Run focused tests, the
WMP suite/corpus checks, then `swift test` and `git diff --check`. Offline tests verify rendered PCM,
not subjective equivalence to WMP; listen to stereo and mono music when tuning the sound.

For a control defect visible only in the running skin, follow the owning skill's **Debugging a live
defect** route and `reference/harness.md`. Inspect the script command and snapshot before changing DSP.

**Neither of the two defects found live in Halo 2's equaliser was in this DSP, and the trace that
said so is `WMP_SEEK_TRACE=1`**: it prints one `performSlider` per drag point and the host command
each one posted, so a bar that disagrees with the sound is separated from a control that never
reached the host in a single drag. Both fixes are in `SKILL.md` — the `eq.enhancedAudio` binding
never re-settling after the skin's own `setSrsEffect()`, and the filmstrip indexed from the wrong
end. Check the command and the drawn frame before the filters.

Validation on 2026-09-13: the full suite completed 2,251 tests with 18 opt-in skips and no failures.
The eight enhancement tests include owned-buffer mono/5.1 passthrough and rendered bass decay with
upstream silence flags. The installed `9SeriesDefault.wmz` passed graph loading and script geometry
at three sizes. Its separate optional transport-map pixel test failed (hit 75 versus expected 70);
this overlapping-control hit-test result was not changed as part of the audio implementation.
No listening comparison against the original Windows DSP was performed.
