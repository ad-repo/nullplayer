# Async Local Track Transitions Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the two remaining synchronous `AVAudioFile(forReading:)` calls (auto-advance and Sweet Fades) off the main thread onto `deferredIOQueue` so NAS stalls don't freeze the UI.

**Architecture:** `trackDidFinish` auto-advance calls a new private helper `advanceToLocalTrackAsync(at:)` that routes local tracks to the existing `loadLocalTrackForImmediatePlayback`. `startLocalCrossfade` wraps its file open in `deferredIOQueue.async` guarded by a new `crossfadeFileLoadToken`.

**Tech Stack:** Swift, AVFoundation (`AVAudioFile`, `AVAudioPlayerNode`), GCD (`DispatchQueue`)

**Spec:** `docs/superpowers/specs/2026-03-14-async-local-track-transitions-design.md`

---

## Chunk 1: Auto-Advance

### Task 1: Add `advanceToLocalTrackAsync` helper and wire it into `trackDidFinish`

**Files:**
- Modify: `Sources/NullPlayer/Audio/AudioEngine.swift`
  - Add helper ~line 3316 (just after `trackDidFinish` closing brace)
  - Modify `trackDidFinish` lines 3288–3314 (the three `loadTrack(at:); play()` call sites)

No unit tests are added — `AVAudioFile` interactions require real audio hardware; this matches the pattern for all existing audio engine changes.

- [ ] **Step 1: Read the current `trackDidFinish` advance block**

  Open `Sources/NullPlayer/Audio/AudioEngine.swift` and read lines 3288–3315 to confirm the exact text before editing. You should see:

  ```swift
  if repeatEnabled {
      if shuffleEnabled {
          // Repeat mode + shuffle: pick a random track
          currentIndex = Int.random(in: 0..<playlist.count)
          loadTrack(at: currentIndex)
          play()
      } else {
          // Repeat mode: loop current track
          loadTrack(at: currentIndex)
          play()
      }
  } else {
      // No repeat mode: check if we're at the end of playlist
      if shuffleEnabled {
          // Shuffle without repeat: could play random tracks but eventually should stop
          // For simplicity, just stop after current track
          stop()
      } else if currentIndex < playlist.count - 1 {
          // More tracks to play
          currentIndex += 1
          loadTrack(at: currentIndex)
          play()
      } else {
          // End of playlist, stop playback
          stop()
      }
  }
  ```

- [ ] **Step 2: Replace the advance block in `trackDidFinish`**

  Use the exact text above (including all inline comments) as `old_string`. Replace with:

  ```swift
  if repeatEnabled {
      if shuffleEnabled {
          // Repeat mode + shuffle: pick a random track
          currentIndex = Int.random(in: 0..<playlist.count)
          advanceToLocalTrackAsync(at: currentIndex)
      } else {
          // Repeat mode: loop current track
          advanceToLocalTrackAsync(at: currentIndex)
      }
  } else {
      // No repeat mode: check if we're at the end of playlist
      if shuffleEnabled {
          // Shuffle without repeat: stop after current track
          stop()
      } else if currentIndex < playlist.count - 1 {
          // More tracks to play
          currentIndex += 1
          advanceToLocalTrackAsync(at: currentIndex)
      } else {
          // End of playlist, stop playback
          stop()
      }
  }
  ```

- [ ] **Step 3: Add `advanceToLocalTrackAsync` helper**

  Immediately after the closing `}` of `trackDidFinish` (currently line 3315), insert:

  ```swift

  /// Advance playback to the track at `index` after a natural EOF.
  /// Local audio files are opened asynchronously on deferredIOQueue to avoid
  /// blocking the main thread on NAS/network-mounted volumes.
  /// Streaming tracks and placeholders fall through to the synchronous loadTrack path.
  private func advanceToLocalTrackAsync(at index: Int) {
      guard index >= 0, index < playlist.count else { return }
      let nextTrack = playlist[index]
      if nextTrack.url.isFileURL && nextTrack.mediaType != .video {
          // Defensive guard: loadLocalTrackForImmediatePlayback bypasses loadTrack's
          // isLoadingTrack sentinel. Guard here in case a concurrent loadTrack call is
          // on the same run-loop turn (both run on main thread, so this is advisory).
          guard !isLoadingTrack else { return }
          _ = stopRadioIfLoadingNonRadioContent(incomingTrackURL: nextTrack.url,
                                                context: "trackDidFinish")
          loadLocalTrackForImmediatePlayback(nextTrack, at: index)
      } else {
          // Streaming tracks, placeholders (about:blank URL fails isFileURL),
          // and video files use the existing synchronous path.
          loadTrack(at: index)
          play()
      }
  }
  ```

- [ ] **Step 4: Build and confirm no errors**

  ```bash
  swift build 2>&1 | grep -E "error:|Build complete"
  ```

  Expected: `Build complete!`

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/NullPlayer/Audio/AudioEngine.swift
  git commit -m "Async auto-advance: open next local track on deferredIOQueue via advanceToLocalTrackAsync"
  ```

---

## Chunk 2: Sweet Fades

### Task 2: Add `crossfadeFileLoadToken` and make `startLocalCrossfade` async

**Files:**
- Modify: `Sources/NullPlayer/Audio/AudioEngine.swift`
  - Add token var ~line 268 (after `crossfadePlayerIsActive`)
  - Replace body of `startLocalCrossfade` ~lines 3479–3527

- [ ] **Step 1: Add `crossfadeFileLoadToken` state variable**

  After line 268 (`private var crossfadePlayerIsActive: Bool = false`), insert:

  ```swift

  /// Token used to invalidate stale in-flight Sweet Fades file opens.
  private var crossfadeFileLoadToken: UInt64 = 0
  ```

- [ ] **Step 2: Read the current `startLocalCrossfade` function**

  Read lines 3477–3528 to confirm the exact text. You should see the function starting with the `private func startLocalCrossfade` signature, then a `do {` block with a synchronous `try AVAudioFile(forReading: nextTrack.url)` call.

- [ ] **Step 3: Replace the entire `startLocalCrossfade` function**

  Replace the entire function (signature through closing `}`) with the async version below. Use the block starting with `/// Start crossfade for local file playback` as `old_string`:

  ```swift
  /// Start crossfade for local file playback
  private func startLocalCrossfade(to nextTrack: Track, nextIndex: Int) {
      do {
          let nextFile = try AVAudioFile(forReading: nextTrack.url)

          // Invalidate the outgoing player's completion handler from loadLocalTrack()
          // so it doesn't call trackDidFinish() when the outgoing track's audio finishes
          playbackGeneration += 1
          let currentGeneration = playbackGeneration

          // Determine which player is currently active and which will be the crossfade target
          let outgoingPlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
          let incomingPlayer = crossfadePlayerIsActive ? playerNode : crossfadePlayerNode

          // Schedule on incoming player with proper completion handler
          // Uses .dataPlayedBack so trackDidFinish fires when this track ends after crossfade
          incomingPlayer.stop()
          incomingPlayer.volume = 0
          incomingPlayer.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
              DispatchQueue.main.async {
                  self?.handlePlaybackComplete(generation: currentGeneration)
              }
          }

          // Start the incoming player
          incomingPlayer.play()

          // Store the file for later
          if crossfadePlayerIsActive {
              audioFile = nextFile
          } else {
              crossfadeAudioFile = nextFile
          }

          // Start volume ramp
          startCrossfadeVolumeRamp(
              outgoingVolume: { v in
                  outgoingPlayer.volume = v
              },
              incomingVolume: { v in
                  incomingPlayer.volume = v
              },
              completion: { [weak self] in
                  self?.completeCrossfade(nextFile: nextFile, nextIndex: nextIndex)
              }
          )
      } catch {
          NSLog("Sweet Fades: Failed to load next track: %@", error.localizedDescription)
          isCrossfading = false
          crossfadeTargetIndex = -1
      }
  }
  ```

  Replace with:

  ```swift
  private func startLocalCrossfade(to nextTrack: Track, nextIndex: Int) {
      // Open the next track's file off the main thread — synchronous AVAudioFile opens
      // on NAS/network volumes block the main thread for seconds.
      // isCrossfading = true was already set by startCrossfade() before calling us,
      // so the periodic timer cannot start a duplicate crossfade while the open is in flight.
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

                  // Invalidate the outgoing player's completion handler from loadLocalTrack()
                  // so it doesn't call trackDidFinish() when the outgoing track's audio finishes
                  self.playbackGeneration += 1
                  let currentGeneration = self.playbackGeneration

                  // Determine which player is currently active and which will be the crossfade target
                  let outgoingPlayer = self.crossfadePlayerIsActive ? self.crossfadePlayerNode : self.playerNode
                  let incomingPlayer = self.crossfadePlayerIsActive ? self.playerNode : self.crossfadePlayerNode

                  // Schedule on incoming player with proper completion handler
                  // Uses .dataPlayedBack so trackDidFinish fires when this track ends after crossfade
                  incomingPlayer.stop()
                  incomingPlayer.volume = 0
                  incomingPlayer.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                      DispatchQueue.main.async {
                          self?.handlePlaybackComplete(generation: currentGeneration)
                      }
                  }

                  // Start the incoming player
                  incomingPlayer.play()

                  // Store the file for later
                  if self.crossfadePlayerIsActive {
                      self.audioFile = nextFile
                  } else {
                      self.crossfadeAudioFile = nextFile
                  }

                  // Start volume ramp
                  self.startCrossfadeVolumeRamp(
                      outgoingVolume: { v in outgoingPlayer.volume = v },
                      incomingVolume: { v in incomingPlayer.volume = v },
                      completion: { [weak self] in
                          self?.completeCrossfade(nextFile: nextFile, nextIndex: nextIndex)
                      }
                  )
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
  }
  ```

- [ ] **Step 4: Build and confirm no errors**

  ```bash
  swift build 2>&1 | grep -E "error:|Build complete"
  ```

  Expected: `Build complete!`

- [ ] **Step 5: Commit**

  ```bash
  git add Sources/NullPlayer/Audio/AudioEngine.swift
  git commit -m "Async Sweet Fades: open crossfade file on deferredIOQueue via crossfadeFileLoadToken"
  ```

---

## Chunk 3: Manual QA & Docs

### Task 3: Verify on NAS and update docs

**Files:**
- Modify: `docs/local-library-import-pipeline.md`

- [ ] **Step 1: Build and run the app**

  ```bash
  ./scripts/kill_build_run.sh
  ```

- [ ] **Step 2: Auto-advance QA on NAS**

  With a playlist of local files on a network-mounted volume (`/Volumes/home/` or `/Volumes/ad_itunes/`):
  - Let a track play to its natural end — confirm the next track starts without a UI freeze/beachball
  - Test repeat-single mode (loop): confirm loop continues without freeze
  - Test direct click during auto-advance: click a different track while one is ending — confirm the clicked track wins (auto-advance is cancelled)

- [ ] **Step 3: Sweet Fades QA on NAS**

  Enable Sweet Fades (Preferences → Playback → Sweet Fades). Play local NAS files:
  - Let the crossfade trigger (~5s before track end) — confirm it initiates without a UI freeze
  - Confirm the crossfade completes and the next track plays correctly
  - Click a new track mid-crossfade — confirm the direct click wins cleanly

- [ ] **Step 4: Mark known-remaining-risk as resolved in pipeline doc**

  In `docs/local-library-import-pipeline.md`, update the "Known Remaining Risk" section to document that this risk is now resolved. Replace:

  ```
  ## Known Remaining Risk

  - Some non-direct local transitions still use synchronous `loadTrack -> loadLocalTrack` (for example parts of auto-advance/crossfade paths).
    If NAS stalls are still observed outside direct playlist clicks, migrate those paths to deferred open with the same token model.
  ```

  With:

  ```
  ## NAS Deferred Open — Fully Resolved

  All local file-open paths are now async on `deferredIOQueue`:
  - **Direct click** (`playTrack`): `loadLocalTrackForImmediatePlayback` (existing)
  - **Auto-advance** (`trackDidFinish`): `advanceToLocalTrackAsync` → `loadLocalTrackForImmediatePlayback`
  - **Sweet Fades** (`startLocalCrossfade`): inline `deferredIOQueue.async` with `crossfadeFileLoadToken`
  - **Gapless pre-schedule** (`scheduleNextTrackForGapless`): `deferredIOQueue.async` (existing)

  No synchronous `AVAudioFile(forReading:)` calls remain on the main thread for local playback.
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add docs/local-library-import-pipeline.md
  git commit -m "Docs: mark all NAS deferred-open paths as resolved"
  ```
