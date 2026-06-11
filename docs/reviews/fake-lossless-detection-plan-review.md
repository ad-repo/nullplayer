# Plan Review: Fake Lossless Detection Reporting

**Reviewed:** 2026-06-09
**Verdict:** **Sound-with-fixes** — the architecture is correct and well-grounded in existing patterns, but two issues are blocking (modal UI cannot show async results; bit-depth + 48k heuristics are unsound) and several DSP details will cause false positives if shipped as written.

The plan is unusually well-aligned with the codebase: integration points, the background-queue + token-guard pattern, cache keying, and menu wiring all map to proven precedents. The gaps are in (a) the async-result → modal-dialog handoff, (b) feasibility/cost of remote stream decode, and (c) DSP correctness/false-positive control.

---

## Blocking (fix before building)

### B1. The Now Playing dialog is a synchronous modal — "analyzing…" is a dead state
`showLocalTrackInfo` and all four service paths build an `NSAlert` and call `alert.runModal()` synchronously (ContextMenuBuilder.swift:3467; service routers at :3138/:3226/:3281/:3337, all via `showAudioTrackInfo` at :3106). Analysis runs async for up to 90s. If the user opens the dialog before analysis finishes, the modal shows "analyzing…" and **can never refresh** — the result lands after the modal has already rendered.
**Fix:** Pick one and write it into the plan: (a) non-modal floating panel that observes `.losslessAuthenticityDidChange`; (b) a "Refresh" affordance / re-open-to-update model; or (c) for the common local-file case, await a short bounded analysis before building the alert. Option (a) is the only one that matches the plan's "analyzing…" copy.

### B2. Bit-depth detection cannot work from the Float32 decode path
The plan decodes PCM to **Float32 mono** for FFT, then asks `bitDepthSuspicion` to detect "24-bit nominal but 16-bit-quantized" by inspecting low bits. Once `AVAudioFile` decodes to Float32, the source integer LSB structure is gone — you cannot recover "lower 8 bits are zero" from a Float32 sample stream. Also note `Track` has **no `bitDepth` or `codec` field** (verified — only `bitrate`, `sampleRate`, `contentType`, `channels`).
**Fix:** Either (a) add a separate raw-integer read path (open the file with an Int32/Int16 format or read `CMSampleBuffer`s) feeding a dedicated bit-depth check, or (b) cut `bitDepthSuspicion` from v1 and the −15 penalty with it. Given v1 scope, dropping it is the cleaner call; reintroduce later with the integer path.

### B3. The 48 kHz upsample heuristic is a false-positive trap
"48k with no energy above ~20 kHz ⇒ weaker upsample suspicion (−20 candidate)" penalizes normal content. The overwhelming majority of legitimate 48k masters (anything from video, most digital masters) have nothing above 20 kHz **by design**. This will wrongly ding genuine files.
**Fix:** Remove the 48k upsample check entirely. Keep the defensible 88.2/96k "no content above 22.05 kHz while 2–16 kHz active" check (that 44.1k→hi-res tell is real).

---

## Important (accuracy / correctness — fix before shipping)

### I1. vDSP FFT magnitude scaling and Nyquist packing are unspecified
`vDSP_fft_zrip` is in-place split-complex with a forward scale of 2N and packs the **Nyquist real component into `imaginary[0]`**. The plan's `20*log10(max(mag,1e-12))` defines dB thresholds (−55, −45 dB offsets) without stating the normalization they're relative to.
**Fix:** Normalize magnitude by `1/(2N)` (≈ −42 dB for N=16384) before the log, and special-case DC (`real[0]`) and Nyquist (`imaginary[0]`) so `sqrt(re²+im²)` doesn't conflate them. Document that every threshold is defined against the normalized output.

### I2. Mono downmix can manufacture a false cutoff
Averaging L+R cancels out-of-phase HF content (intensity stereo, hard-panned cymbals). A genuine 320 kbps or lossless stereo track can show a false "cutoff < 17 kHz" in the mono sum.
**Fix:** Use **per-channel max magnitude** (or run the FFT per channel and take the max band energy) instead of an L+R average. Costs a second FFT or split-complex unpack; worth it to remove a real false-positive source.

### I3. Hann window energy compensation
The Hann window has ~0.5 coherent gain; band energies come out ~6 dB low and uncompensated, making genuine band-limited material look *more* band-limited.
**Fix:** Divide by the window's coherent gain before the log, or explicitly document that all thresholds were corpus-tuned with Hann applied (and then they must actually be tuned that way).

### I4. Penalty stacking double-counts a single phenomenon
A brickwall low-pass trips *cutoff < 17k* (−35), *low highBandEnergyRatio* (−20), and *sharp slope* (−15) simultaneously — −70 for what is essentially one observation. Genuine band-limited content (vinyl rips, pre-90s masters, spoken word, intentionally dull mixes) gets pushed into "very low" wrongly.
**Fix:** Treat the spectral-shape penalties as one composite with a cap (e.g. max −45 for "brickwall evidence"), keeping ultrasonic/upsample as a separate orthogonal axis. State the stacking model explicitly in the plan.

### I5. Remote stream decode is feasible for services but unproven for radio — and uncosted
Good news: `WaveformCacheService` already uses `AVAssetReader` successfully on Plex/Subsonic/Jellyfin/Emby service URLs (WaveformCacheService.swift:316), so service-stream analysis has a real precedent — the plan's "AVFoundation decode from URL" is not hand-waved for those. **But** local-file `AVAudioFile(forReading:)` is local-only, icy/shoutcast radio streams are chunked/non-seekable and have **no precedent** for `AVAssetReader`, and a second out-of-band fetch competes with playback bandwidth.
**Fix:** (a) State that local files use `AVAudioFile`, services use `AVAssetReader`/`AVURLAsset` (cite the WaveformCacheService precedent), radio is best-effort and degrades to `failed`/`inconclusive` on decode failure or timeout. (b) Define the 90s/80MB bound precisely: read-up-to-N-bytes-then-abort vs. give-server-N-seconds. (c) Confirm auth headers/proxy URLs survive the separate asset read.

### I6. Toggle persistence diverges from the comparable feature
The plan stores `fakeLosslessReportingEnabled` in UserDefaults only. The analogous `volumeNormalizationEnabled` is **both** UserDefaults *and* session `AppState` (AppStateManager.swift:206/261/301/656).
**Fix:** Match the normalization precedent (add to AppState) unless session-erasure is deliberate — if deliberate, note why in the plan.

### I7. Test suite misses the cases most likely to break
The synthetic-scorer tests are a good start, but the highest-value regression guards are absent.
**Fix:** Add: out-of-phase stereo HF (must NOT yield a false cutoff once I2 is fixed); naturally band-limited genuine content (vinyl/speech must land at `inconclusive`/`moderate`, not "very low"); brickwall exactly at the 19.5 kHz boundary; an FFT-scale/window regression that pins the dB normalization from I1/I3. Confirm the scorer is cleanly separable from decode (the plan assumes "pure scorer on Float arrays" — make that separation explicit in the API).

---

## Suggestions (non-blocking)

- **S1 — Missing symbol:** `Notification.Name.losslessAuthenticityDidChange` doesn't exist yet (add near AudioEngine.swift:26). Note the plan also says to post `.audioPlaybackOptionsChanged` on toggle — keep both: the dedicated notification drives the (non-modal) UI from B1; the options notification updates menu state.
- **S2 — Cache thread-safety:** Reuse the `WaveformCacheService` keying pattern (local: path+size+mtime; service: identity+bitrate+sampleRate). `FileManager.attributesOfItem` is fine synchronously on main, but the in-memory dictionary is written from the background queue — guard it with a serial queue or lock.
- **S3 — Whole-file vs. sampled:** 90s ≈ ~480 frames at hop 8192 — far above the 20-frame floor, so sampling is plentiful. Drop or down-scope `Coverage.wholeFile`; it adds cost without accuracy for this purpose.
- **S4 — Corpus validation:** The −55/−45 dB offsets and classification bands (85/60/35) are reasonable but currently unjustified. Before trusting the % confidence, validate against a small labeled corpus (lossy, hi-res-genuine, upsampled, vinyl, naturally-dull genuine). Without it, expect a meaningful false-positive rate on legitimate material.

---

## What the plan gets right

- **Integration points are accurate:** `commitLoadedLocalTrack(_:track:generation:)` (:3991) receives `generation`; `loadStreamingTrack` increments `playbackGeneration` after `currentTrack = track` (:4144→:4153); `stop()` also bumps it (:2053) giving free invalidation. `Track.id` (UUID), `channels`, `bitrate`, `sampleRate`, `contentType`, `isRadioStream`, `streamingServiceIdentity`, `isStreamingPlayback` all exist as assumed.
- **The async pattern is the proven one:** `deferredIOQueue.async { … DispatchQueue.main.async { guard token/generation/currentTrack/toggle … } }` mirrors `analyzeAndApplyNormalization` (:5107) almost exactly — including a separate read handle rather than reusing the playback file. Keeping `losslessAnalysisToken` separate from the normalization/playback tokens is the right call.
- **Routing-filter-not-proof framing is correct and important** — metadata gates "should we analyze," PCM evidence decides. The "confidence, not verified" language and the explicit `inconclusive` cap for sparse/band-limited content are the right guardrails.
- **Menu and info-dialog insertion points are real and unambiguous** (Audio Quality Options at :891; per-service info functions with clear "after audio format fields" slots).
- **Scope discipline:** no SQLite/library-column changes in v1, best-effort remote that never blocks playback — both sensible.
- **DSP skeleton is standard:** windowed FFT, band binning, RMS-floor gating, frame-count flooring is the textbook transcode-detection approach.

---

## Recommended next steps

1. Resolve B1 by choosing the non-modal observer UI (or bounded-await for local) and rewrite the UI section accordingly.
2. Cut `bitDepthSuspicion` (B2) and the 48k upsample check (B3) from v1; keep the 88.2/96k ultrasonic check.
3. Pin the DSP contract: vDSP scale normalization + Nyquist handling (I1), per-channel max instead of mono average (I2), Hann compensation (I3), composite-capped spectral penalty (I4). Write these into the algorithm section so they're not left to implementation.
4. Specify the remote-decode mechanism explicitly (services via `AVAssetReader` per WaveformCacheService; radio best-effort→`failed`) and the exact 90s/80MB semantics (I5).
5. Decide toggle persistence (I6) and expand the test list (I7) before implementation starts.
