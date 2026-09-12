# WMP WOW and TruBass

Read this before changing the WMP enhanced-audio controls or their DSP. These are independent
approximations, not the licensed SRS algorithms shipped in Windows Media Player.

## Sources and intended sound

- [Stereo butterfly discussion](https://forum.pdpatchrepo.info/topic/9645/stereo-butterfly-effect-aka-the-wmp-srs-wow-effect): the requested WOW model mixes inverted mono back into stereo. This changes the mid/side ratio. It does not synthesize spatial information from mono.
- [SRS low-frequency enhancement design, US6285767B1](https://patents.google.com/patent/US6285767B1/en), especially figures 12–15: a low-bass envelope controls enhancement of existing mid-bass content; speaker size changes the filter bank. This is the basis for our TruBass approximation. No exact WMP source or tuning was found.
- [Microsoft EQUALIZERSETTINGS](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/equalizersettings-element) defines the skin API. [speakerSize](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/equalizersettings-speakersize) is **0 headphones, 1 normal, 2 large**. Do not infer this order from the pictures. [truBassLevel](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/equalizersettings-trubasslevel) ranges from 0 to 100, defaults to 50, and is gated by enhancedAudio.

## Ownership and control path

`Audio/WMPWOWAudioUnit.swift` contains the butterfly kernel, custom AU and `WMPWOWController`.
`Audio/WMPTruBassDSP.swift` contains the bass filter bank. These files live by the audio engine because
both playback pipelines use them; no skin parsing or AppKit code runs in their render callback.

The skin uses `eq.enhancedAudio`, `eq.wowLevel`, `eq.truBassLevel`, `eq.speakerSize`, and the read-only
`eq.currentSpeakerName`. They reach `WMPObjectModel`, then four typed commands through
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

Initial session settings: enhancements off, both strengths 50, headphones. The controller owns
session state across track, stream and skin changes. It does not persist preferences across app
launches and does not reuse or overwrite graphic-EQ, tuning, or normalization preferences.

## Graph integration and mode isolation

The existing Reference Tuning controller is the ownership model: one local node and one independent
node for every primary or Sweet Fades streaming player. The controller keeps weak streaming references.
New streaming nodes inherit all current settings immediately.

- Local: player nodes → mixer → reference tuning → graphic EQ → WOW/TruBass → main mixer.
- Streaming: existing balance → graphic EQ → reference tuning → WOW/TruBass, attached through
  AudioStreaming's `attach(node:)`. Streaming tempo remains owned by AudioStreaming's rate node.
- Local graph reconnect and disconnect include the enhancement node, so device changes and sleep
  rebuilds cannot strand the effect outside the graph.

`AudioEngine` seeds the controller's active gate from the stored WMP controller family.
`WindowManager.uiMode` updates it on every mode assignment; host writes also require the WMP family.
The node remains connected to avoid rebuilding a playing graph on every toggle/mode change, but
receives zero effect targets outside WMP. After the short ramp, dry samples pass through exactly and
filter work is skipped. Retained WMP settings never activate effects in Classic, Original or WAL.

These shared paths are necessary: a skin view or host adapter can send controls but cannot transform
rendered audio. A spectrum tap is an observation path, not an output effect. Editing graphic-EQ bands
would overwrite unrelated user settings. The dedicated AU avoids both alternatives.

Remote casting passes media URLs to another renderer and does not include this DSP. VLC video audio
also bypasses these AVAudioEngine pipelines. This feature applies to local audio files and HTTP audio
streams, not remote speakers or VLC video sound.

## Butterfly DSP

With `a = 0.8 * wowLevel / 100` and `M = (L + R) / 2`:

```
Lout = L - a*M
Rout = R - a*M
```

The side signal is unchanged; the centre is attenuated by `1-a`. The 0.8 ceiling is our tuning choice,
leaving 20% of the centre at maximum instead of cancelling vocals outright. This can reduce perceived
volume and centred bass. Identical stereo channels stay centred and get quieter; a true one-channel
bus skips widening. There is no claim of exact SRS response or added mono width.
Each output's coefficient magnitudes sum to one, so this operation cannot increase a bounded input's
sample peak. WOW alone needs no clipping or automatic gain compensation. The target slews at
`1/(0.020*sampleRate)` per sample; returning to zero restores exact dry values.

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

Only the added bass contribution is restricted to the available shared L/R headroom. Existing
out-of-range input receives no additional bass. The original signal is not globally limited and the
L−R difference stays intact. At high levels this bounds the enhancement nonlinearly and may alter its
timbre; it is not a transparent mastering limiter. Off/zero bass contributes exactly zero. Filter
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

Validation on 2026-09-12: the full suite completed 2,221 tests with 18 opt-in skips and no failures.
The eight enhancement tests include owned-buffer mono/5.1 passthrough and rendered bass decay with
upstream silence flags. The installed `9SeriesDefault.wmz` passed graph loading and script geometry
at three sizes. Its separate optional transport-map pixel test failed (hit 75 versus expected 70);
this overlapping-control hit-test result was not changed as part of the audio implementation.
No listening comparison against the original Windows DSP was performed.
