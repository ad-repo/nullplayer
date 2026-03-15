# Design: Async Local Track Transitions (Auto-Advance & Sweet Fades)

**Date:** 2026-03-14
**Status:** Approved
**File:** `Sources/NullPlayer/Audio/AudioEngine.swift`

## Problem

Two code paths open `AVAudioFile` synchronously on the main thread, risking UI stalls on NAS/network-mounted libraries:

1. **Auto-advance** — `trackDidFinish()` calls `loadTrack(at:)` → `loadLocalTrack()` → `AVAudioFile(forReading:)` on the main thread (via the EOF completion handler dispatched to main).
2. **Sweet Fades** — `startLocalCrossfade()` calls `AVAudioFile(forReading: nextTrack.url)` synchronously on the main thread, triggered by the periodic timer.

The deferred infrastructure (`deferredIOQueue`, `deferredLocalTrackLoadToken`, `loadLocalTrackForImmediatePlayback`) already exists and is used by direct playlist clicks. These two paths were not migrated.

## Approach

**Auto-advance:** Call `loadLocalTrackForImmediatePlayback` directly from `trackDidFinish` for local tracks. Streaming tracks keep `loadTrack(at:); play()` unchanged. An explicit `guard !isLoadingTrack` is added before the call so the concurrent-load guard from `loadTrack` is not bypassed.

Note: `loadLocalTrackForImmediatePlayback` calls `play()` in its async callback — the separate `play()` call that follows `loadTrack` in the current code is **not** carried over for the async path. This is intentional: calling `play()` immediately after an async-dispatched open would start the player before any file is scheduled.

**Sweet Fades:** Add `private var crossfadeFileLoadToken: UInt64 = 0`. In `startLocalCrossfade`, move the `AVAudioFile(forReading:)` call to `deferredIOQueue.async`. Proceed with schedule/ramp on the main thread once the file is ready.

Token semantics for auto-advance: `deferredLocalTrackLoadToken` is shared with direct-click loads. A user direct-click increments the token, cancelling any pending auto-advance open. This is correct — user intent wins.

## Design

### 1. Auto-Advance (`trackDidFinish`)

`trackDidFinish` currently has four `loadTrack(at:); play()` call sites for local tracks (repeat+shuffle, repeat-single, normal advance, and a streaming-advance path — the `!repeatEnabled && shuffleEnabled` branch calls `stop()` and is not changed).

For each local-track call site, replace `loadTrack(at: nextIndex); play()` with:

```swift
let nextTrack = playlist[nextIndex]
if nextTrack.url.isFileURL && nextTrack.mediaType != .video {
    guard !isLoadingTrack else { return }
    _ = stopRadioIfLoadingNonRadioContent(incomingTrackURL: nextTrack.url, context: "trackDidFinish")
    loadLocalTrackForImmediatePlayback(nextTrack, at: nextIndex)
} else {
    loadTrack(at: nextIndex)
    play()
}
```

`currentIndex` is mutated before this block (same as today). `loadLocalTrackForImmediatePlayback` then validates `self.currentIndex == index` in its callback — that check passes because we already set `currentIndex = nextIndex` before calling the function.

**Placeholder tracks:** A streaming placeholder's URL is `about:blank`, which fails `isFileURL`, so it falls through to the `loadTrack` branch where the existing `isStreamingPlaceholder` handling already lives. No change needed there.

Guards inherited from `loadLocalTrackForImmediatePlayback`:
- `deferredLocalTrackLoadToken == token` — cancels if a newer load supersedes this one
- `currentIndex == index` — cancels if playlist position changed
- `playlist[index].id == expectedTrackID` — cancels if playlist was mutated

Guard added in `trackDidFinish`:
- `guard !isLoadingTrack` — defensive check against a concurrent `loadTrack` call on the same run-loop turn. Both `trackDidFinish` and `loadTrack` run on the main thread so they cannot truly be concurrent; this guard is advisory. `loadLocalTrackForImmediatePlayback` does not set `isLoadingTrack`, so the flag returns to `false` immediately after the guard passes — this is correct and intentional.

`stopRadioIfLoadingNonRadioContent` call: `loadTrack` calls this to tear down RadioManager when a radio station is playing and a local track is about to load. Bypassing `loadTrack` would leave `RadioManager.isActive == true` in a stale state. The explicit call here preserves that behaviour.

Side-effects: `loadLocalTrackForImmediatePlayback` calls `prepareForLocalTrackLoad()` which resets spectrum peaks and stops the streaming player. For local→local auto-advance these are no-ops (no streaming player active, spectrum resets are cosmetic). This is the same behaviour as the existing `loadLocalTrack` path and is not a regression.

### 2. Sweet Fades (`startLocalCrossfade`)

Add `private var crossfadeFileLoadToken: UInt64 = 0` alongside the other crossfade state vars.

`isCrossfading = true` is already set by `startCrossfade()` before it calls `startLocalCrossfade` — this prevents duplicate crossfade attempts for the full duration of the async open (which may be several seconds on a slow NAS). This is a behavioural change from today: previously `isCrossfading` was set and immediately cleared if the synchronous open failed; now it remains `true` until the async open resolves. The consequence is that the periodic timer cannot retry a failed crossfade until the open resolves. On slow NAS, this extends the retry window. This is acceptable — a stalled open is a better experience than repeated fast-fail retries.

Replace the synchronous `do { let nextFile = try AVAudioFile(forReading: nextTrack.url) ... } catch { ... }` block with:

```swift
crossfadeFileLoadToken &+= 1
let token = crossfadeFileLoadToken

deferredIOQueue.async { [weak self] in
    guard let self else { return }
    do {
        let nextFile = try AVAudioFile(forReading: nextTrack.url)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.crossfadeFileLoadToken == token,
                  self.isCrossfading else { return }
            // ... existing schedule/ramp logic (incomingPlayer.scheduleFile,
            //     startCrossfadeVolumeRamp, etc.) ...
        }
    } catch {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.crossfadeFileLoadToken == token,
                  self.isCrossfading else { return }
            NSLog("Sweet Fades: Failed to load next track: %@", error.localizedDescription)
            self.isCrossfading = false
            self.crossfadeTargetIndex = -1
        }
    }
}
```

Both the success and error paths check `isCrossfading` in addition to the token. If a direct user action calls `resetLocalCrossfadeStateForDirectPlayback()` (which clears `isCrossfading`) while the open is in flight, both callbacks are silently suppressed — no spurious log message, no double-reset.

### 3. No changes to streaming paths

`startStreamingCrossfade`, `completeStreamingCrossfade`, and the streaming branch of `trackDidFinish` are unaffected.

## Error Handling

- **Auto-advance open failure**: `loadLocalTrackForImmediatePlayback` calls `handleLocalTrackLoadFailure` on error, which logs and skips to next — existing behaviour unchanged.
- **Sweet Fades open failure**: Reset `isCrossfading = false` and `crossfadeTargetIndex = -1`. The periodic timer will attempt `startCrossfade()` again on the next tick once `isCrossfading` is clear.

## Testing

Manual QA on NAS:
- Auto-advance: play track to end on NAS volume, confirm next track starts without UI freeze
- Repeat single: confirm loop continues without UI freeze
- Sweet Fades: confirm crossfade initiates and completes without UI freeze
- Direct click during pending auto-advance open: confirm direct click wins (token cancels the in-flight open)

No unit tests added — AVAudioFile interactions require real files; the existing pattern has no unit tests.

## Files Changed

- `Sources/NullPlayer/Audio/AudioEngine.swift` — two focused changes, no new files
