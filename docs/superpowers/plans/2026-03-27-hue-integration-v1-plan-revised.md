# Hue Integration v1 Plan (Dedicated Window + Music Reactive)

## Summary
- Add a single-bridge, local-network Hue integration to NullPlayer using an OpenAPI-generated Swift client (from OpenHue) wrapped by app-specific services.
- Ship a dedicated Hue Control window (not menu-only) with core light controls plus music-reactive mode.
- v1 reactive mode uses grouped REST only. Entertainment API (DTLS/UDP) is deferred to v2.
- Feature is available at first launch but idle until the user pairs a bridge.

## Feature List (v1)
- Bridge discovery and pairing:
  1. Discover bridge via mDNS (`_hue._tcp`) with discovery endpoint fallback.
  2. Guided push-link flow to obtain/store Hue application key.
  3. Reconnect automatically to last paired bridge.
- Core Hue controls:
  1. Show rooms/zones and grouped lights.
  2. On/off, brightness, color temperature, color (for color-capable lights).
  3. Scene activation per room/zone.
  4. Live state sync from Hue event stream.
- Music-reactive controls:
  1. Reactive enable/disable toggle.
  2. Mode: `Fallback Group Reactive` (v1 only; Entertainment mode deferred to v2).
  3. Intensity and speed controls.
- Reliability UX:
  1. Clear connection/auth/error states.
  2. Retry and re-pair actions.
  3. Command coalescing to prevent bridge overload.

## Implementation Changes

### Hue subsystem (`Sources/NullPlayer/Hue/`)
1. `HueManager` — singleton service facade (pattern: `CastManager.swift`). Owns discovery, auth, state, and reactive sub-services.
2. `HueBridgeDiscoveryService` — mDNS via `NWBrowser` + discovery endpoint fallback.
3. `HueAuthService` — push-link handshake, app-key storage and lifecycle.
4. `HueStateStore` — cached resources with event-stream-applied updates. May be an internal type on `HueManager` rather than a standalone file.
5. `HueCommandQueue` — rate limiting, dedupe, coalescing. May be an internal type on `HueManager` rather than a standalone file.
6. `HueReactiveEngine` — maps audio features to grouped-light REST commands.

`HueEntertainmentEngine` (DTLS/UDP session lifecycle) is **deferred to v2**.

### Public app-facing types
1. `HueConnectionState` (`disconnected`, `discovering`, `awaitingLinkButton`, `connected`, `error`).
2. `HueReactiveMode` (`off`, `groupFallback`). `entertainment` case added in v2.
3. `HueControlTarget` (`room`, `zone`, `groupedLight`, `light`).
4. `HueCapabilityFlags` (color/colorTemp/dimming support).

### API and networking
- Resources from generated client: `light`, `grouped_light`, `room`, `zone`, `scene`.
- Event stream: `/clip/v2/eventstream` (SSE, `text/event-stream`). Reconnect strategy: 2 s fixed retry, capped at 30 s exponential backoff after consecutive failures.
- **TLS trust**: Hue bridges use a self-signed certificate issued by the Signify root CA. Use a dedicated `URLSession` with a custom `URLSessionDelegate` that pins against the published Signify bridge root CA certificate. Do not use the shared `URLSession.shared`.
- All REST calls go through `HueCommandQueue`, which enforces the 10 req/sec global cap.

### Required system changes
- `Info.plist`: add `_hue._tcp` to `NSBonjourServices` (alongside existing `_googlecast._tcp`, `_airplay._tcp`, `_raop._tcp`) — required for `NWBrowser` mDNS on macOS.
- `Info.plist`: confirm `NSLocalNetworkUsageDescription` is present (mDNS triggers the local network permission prompt on first use).

### Dedicated window
1. Add `HueControlWindowController` + `HueControlView` in `Windows/HueControl/`. Follow the `NSWindowController + NSView` pattern from `Windows/ModernEQ/` and `Windows/ModernSpectrum/`.
2. Layout sections: connection header, targets list (scrollable; minimum window height 480 pt), control panel, scenes, reactive panel, diagnostics line.
3. `HueControlWindowController` is **mode-independent** (shown in both classic and modern UI). Register it directly in `WindowManager` without a provider protocol, guarded by `isHueAvailable` (paired state), not by `isModernUIEnabled`.
4. Add menu entry in `AppDelegate.swift` as a new top-level **Lights** menu (or under an existing "Windows" menu if one is added). Do **not** add to `buildMenuBarOutputMenu()` in `ContextMenuBuilder.swift` — that menu is scoped to audio output devices only.

### Audio integration for reactive mode
1. Register `HueReactiveEngine` as a spectrum consumer via `audioEngine.addSpectrumConsumer("hueReactive")` when reactive mode is enabled; call `removeSpectrumConsumer("hueReactive")` when disabled. Without registration, `audioSpectrumDataUpdated` is never posted during streaming playback (`AudioEngine.swift:408-415`).
2. Consume `audioSpectrumDataUpdated` notification (`userInfo["spectrum"]` = `[Float]`, 75 bands, 0–1 normalized). Band partitioning: bands 0–9 → bass energy, 10–29 → mid energy, 30–74 → high energy (sum per region, normalized by region width). Beat confidence: flux-based onset detection (frame-to-frame sum-of-positive-differences on bass region, threshold at 1.5× rolling mean).
3. Apply smoothing (exponential moving average, α = 0.3) and hysteresis (min 80 ms between state transitions) to avoid flicker.
4. Map derived energy to grouped light brightness/color via `HueCommandQueue` REST calls at ≤ 8 Hz.

### Persistence
1. App key + bridge IP/ID: `KeychainHelper.setString(forKey: "hue_app_key")` and `setString(forKey: "hue_bridge_id")` (generic API at `KeychainHelper.swift:250-289`).
2. Selected target, reactive mode, intensity, speed: `UserDefaults.standard.set(_:forKey:)` directly on change (pattern from `SpectrumView.swift`, `VisualizationGLView.swift`).

### Safety/rate strategy
1. REST write cap: 10 req/sec global (Hue CLIP v2 limit).
2. Slider/color drags coalesced to max 5 updates/sec per target.
3. Reactive loop capped at 4–8 Hz updates.

### OpenHue client generation
- Generated source is pre-committed to `Sources/NullPlayer/Hue/Generated/` (not a build-time step).
- Regenerate manually when updating the OpenHue spec version: `swift run openapi-generator generate -i openapi.yaml -g swift5 -o Sources/NullPlayer/Hue/Generated/`.
- Commit the regenerated files; do not add the generator to the build graph.

## Test Plan
- Unit tests:
  1. Discovery result parsing and bridge selection.
  2. Auth/link flow state transitions.
  3. Capability mapping (light/group/scene metadata to UI flags).
  4. Command queue coalescing/rate-limit behavior.
  5. Reactive band-partition and onset-detection logic.
  6. Spectrum consumer registration/deregistration on reactive mode toggle.
- Integration tests (using diyHue or Bifrost-class emulator):
  1. API contract tests for discovery, auth, and control paths.
  2. Event-stream reconnect: drop stream mid-session, verify reconnect within 2 s, state reconciled after reconnect.
  3. Failure injection: auth expiry (expect `awaitingLinkButton` transition), bridge unreachable (expect `error` state and retry UI).
- Manual QA:
  1. Real bridge pairing from clean install; verify local network permission prompt appears.
  2. Core controls across white-only and color lights.
  3. Scene activation correctness by room/zone.
  4. Reactive mode: enable during music playback, verify lights respond to bass/beat.
  5. Long session stability while playing local and streaming tracks.

## Assumptions and Defaults
- Single bridge only in v1.
- Excludes cloud remote access, sensor/switch configuration, and automation/rule editing.
- Entertainment API (DTLS/UDP) deferred to v2; grouped REST is the only reactive path in v1.
- Feature is idle at launch (no mDNS browsing until user opens the Hue window or triggers discovery). No auto-connect on startup until at least one bridge has been paired.
- Open-source reference stack:
  1. OpenHue spec/client generation for API surface.
  2. Home Assistant/aiohue and node-hue-api as behavior/reference patterns.
  3. diyHue/Bifrost-class emulators for integration testing.
