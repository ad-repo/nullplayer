# Playback State Follow-Ups

## Summary

The sleep/wake timer fix in this change is intentionally conservative. It stops local playback time from counting system sleep as active playback, but it does not resolve the broader playback-state and restore inconsistencies in the current architecture.

## Observed Current Behavior

- Local playback time is derived from wall-clock elapsed time using `playbackStartDate`.
- Streaming playback time comes from the streaming player, not the local wall-clock path.
- Cast playback has its own wake-handling and interpolation logic separate from local playback.
- Restore behavior mixes track loading, playback start, pause, and seek sequencing.
- `wasPlaying` is persisted in app state, but the restore pipeline has historically depended on source-specific side effects rather than treating it as the single source of truth.

## Why The Conservative Fix Stops Short

- The sleep/wake fix only freezes and resumes the local wall-clock timer. It does not replace the underlying local timing model.
- Restore behavior is still implemented through existing playback primitives, which means the exact startup sequence remains dependent on whether the source is local, streaming, radio, or a placeholder that resolves asynchronously.
- Cast and local playback still use separate sleep/wake strategies, which may drift further apart over time.
- Time and playback transitions are still difficult to unit test because the engine is tightly coupled to `Date()`, timers, and live playback objects.

## Recommended Future Direction

- Introduce a clearer playback-clock abstraction for local playback instead of deriving elapsed time directly from wall-clock state in multiple places.
- Separate restore concerns into explicit operations:
  - restore playlist
  - restore selected track
  - restore position
  - restore desired playback state
- Make `wasPlaying` the single restore-state input, independent of track source.
- Review local, streaming, and cast timing paths together so sleep/wake, buffering, seek, and resume semantics are consistent.
- Increase testability by isolating time calculations from live timers and playback backends.

## Risks If Left As-Is

- Future fixes may continue to patch individual playback sources instead of converging on one model.
- Restore behavior can remain source-dependent and surprising, especially for placeholder-backed streaming tracks.
- Regressions around sleep, wake, seek, and resume may be harder to catch because the timing logic is spread across multiple code paths.
- Cast and local playback may continue to diverge in subtle ways around buffering and lifecycle transitions.
