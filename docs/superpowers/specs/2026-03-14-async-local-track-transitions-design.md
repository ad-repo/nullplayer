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

**Option A** (selected): Reuse `loadLocalTrackForImmediatePlayback` for auto-advance; inline `deferredIOQueue.async` with a dedicated token for Sweet Fades.

Rationale: Auto-advance and direct-click are the same operation (open file → commit → play), so sharing the existing function is semantically correct and avoids duplication. Sweet Fades has a different state machine (needs the file before starting the volume ramp, guarded by `isCrossfading`) so it warrants its own inline block.

## Design

### 1. Auto-Advance (`trackDidFinish`)

Replace all three `loadTrack(at:); play()` call sites for local tracks with `loadLocalTrackForImmediatePlayback(nextTrack, at: nextIndex)`.

Call sites:
- Repeat + shuffle: `currentIndex = random; loadTrack(at: currentIndex); play()`
- Repeat single: `loadTrack(at: currentIndex); play()`
- Normal advance: `currentIndex += 1; loadTrack(at: currentIndex); play()`

For each: extract `nextIndex` and `nextTrack` before branching, guard that the track is a local file URL, then call `loadLocalTrackForImmediatePlayback`. Streaming tracks keep their existing path (`loadTrack(at:); play()`).

Token semantics: `deferredLocalTrackLoadToken` is shared with direct-click loads. A user direct-click increments the token, cancelling any pending auto-advance open — correct behavior, user intent wins.

Existing guards in `loadLocalTrackForImmediatePlayback` cover all race conditions:
- `deferredLocalTrackLoadToken == token` — cancels if superseded
- `currentIndex == index` — cancels if playlist position changed
- `playlist[index].id == expectedTrackID` — cancels if playlist mutated

No new state needed.

### 2. Sweet Fades (`startLocalCrossfade`)

Add `private var crossfadeFileLoadToken: UInt64 = 0` alongside the other crossfade state vars.

Replace the synchronous `do { let nextFile = try AVAudioFile(forReading: nextTrack.url) ... } catch { ... }` block with:

```
crossfadeFileLoadToken &+= 1
let token = crossfadeFileLoadToken
deferredIOQueue.async { [weak self] in
    guard let self else { return }
    do {
        let nextFile = try AVAudioFile(forReading: nextTrack.url)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.crossfadeFileLoadToken == token,
                  self.isCrossfading else { return }
            // ... existing schedule/ramp logic ...
        }
    } catch {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.crossfadeFileLoadToken == token else { return }
            NSLog("Sweet Fades: Failed to load next track: %@", error.localizedDescription)
            self.isCrossfading = false
            self.crossfadeTargetIndex = -1
        }
    }
}
```

`isCrossfading = true` is set before the dispatch (existing behaviour), preventing duplicate crossfade attempts while the open is in flight. The token prevents a stale open callback from completing a crossfade that was cancelled or superseded.

### 3. No changes to streaming paths

`startStreamingCrossfade`, `completeStreamingCrossfade`, and the streaming branch of `trackDidFinish` are unaffected.

## Error Handling

- **Auto-advance open failure**: `loadLocalTrackForImmediatePlayback` calls `handleLocalTrackLoadFailure` on error, which logs and skips to next — existing behaviour, no change.
- **Sweet Fades open failure**: Reset `isCrossfading = false` and `crossfadeTargetIndex = -1`. The periodic timer will attempt `startCrossfade()` again on the next tick if still in range — same fallback as today.

## Testing

Manual QA on NAS:
- Auto-advance: play track to completion on NAS volume, confirm next track starts without UI freeze
- Repeat single: confirm loop continues without freeze
- Sweet Fades: confirm crossfade initiates and completes without UI freeze
- Direct click during pending auto-advance open: confirm direct click wins

No unit tests added (AVAudioFile interactions require real files; the existing pattern has no unit tests).

## Files Changed

- `Sources/NullPlayer/Audio/AudioEngine.swift` — two focused changes, no new files
