# Sonos: Auto-Skip Unsupported Lossless Formats

## Phase 1 — CastManager.swift
- [x] Add `isCastingToSonos` computed property (`.sonos` only, not `.dlnaTV`)
- [x] Add `contentTypeToExtension(_:)` private static helper
- [x] Add `sonosUnsupportedExtensions`, `sonosMaxSampleRate`, `sonosLosslessExtensions` constants
- [x] Add `isSonosCompatible(_:)` static method (extension check + contentType fallback + sample rate gate)

## Phase 2 — AudioEngine.swift: auto-advance
- [x] Modify normal advance path in `castTrackDidFinish()` — forward scan skipping incompatible tracks
- [x] Modify repeat+shuffle path in `castTrackDidFinish()` — bounded random retry
- [x] Modify shuffle-without-repeat path in `castTrackDidFinish()` — bounded random retry

## Phase 3 — AudioEngine.swift: cast-start check (gap B)
- [x] Add compatibility check at cast start so first track is skipped if incompatible

## Phase 4 — Build & verify
- [x] Build (`./scripts/kill_build_run.sh`)
