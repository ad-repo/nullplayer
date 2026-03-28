# Hue Integration v1 Plan (Dedicated Window + Music Reactive)

## Summary
- Add a single-bridge, local-network Hue integration to NullPlayer using an OpenAPI-generated Swift client (from OpenHue) wrapped by app-specific services.
- Ship a dedicated Hue Control window (not menu-only) with core light controls plus music-reactive mode.
- Use Entertainment API when available, with automatic fallback to grouped reactive REST control when unavailable/failing.
- Ship on by default.

## Feature List (v1)
- Bridge discovery and pairing:
1. Discover bridge via mDNS and discovery endpoint fallback.
2. Guided push-link flow to obtain/store Hue application key.
3. Reconnect automatically to last paired bridge.
- Core Hue controls:
1. Show rooms/zones and grouped lights.
2. On/off, brightness, color temperature, color (for color-capable lights).
3. Scene activation per room/zone.
4. Live state sync from Hue event stream.
- Music-reactive controls:
1. Reactive enable/disable toggle.
2. Mode selector: `Entertainment` and `Fallback Group Reactive`.
3. Intensity and speed controls.
4. Auto fallback status indicator when Entertainment is unavailable.
- Reliability UX:
1. Clear connection/auth/error states.
2. Retry and re-pair actions.
3. Command coalescing to prevent bridge overload.

## Implementation Changes
- Add Hue subsystem (`Sources/NullPlayer/Hue/`) with these interfaces/types:
1. `HueManager` (singleton service facade, similar role to CastManager).
2. `HueBridgeDiscoveryService` (mDNS + discovery fallback).
3. `HueAuthService` (push-link handshake, app-key lifecycle).
4. `HueStateStore` (cached resources + event-stream-applied updates).
5. `HueCommandQueue` (rate limiting, dedupe, coalescing).
6. `HueReactiveEngine` (maps audio features to Hue targets).
7. `HueEntertainmentEngine` (stream session lifecycle; availability checks).
- Public app-facing types to add:
1. `HueConnectionState` (`disconnected`, `discovering`, `awaitingLinkButton`, `connected`, `error`).
2. `HueReactiveMode` (`off`, `entertainment`, `groupFallback`).
3. `HueControlTarget` (`room`, `zone`, `groupedLight`, `light`).
4. `HueCapabilityFlags` (color/colorTemp/dimming/entertainment support).
- API/resource scope used from generated client:
1. `light`, `grouped_light`, `room`, `zone`, `scene`, `entertainment_configuration`.
2. Event stream endpoint for push updates (`/clip/v2/eventstream`).
- Dedicated window:
1. Add `HueControlWindowController` + `HueControlView`.
2. Sections: connection header, targets list, control panel, scenes, reactive panel, diagnostics line.
3. Add menu entry to open the Hue window from Output menu.
- Audio integration for reactive mode:
1. Consume existing audio notifications (`audioSpectrumDataUpdated` + waveform path as needed).
2. Derive low/mid/high energy + beat confidence.
3. Apply smoothing/hysteresis to avoid flicker.
4. Entertainment path first; if unavailable/fails, switch to grouped REST updates automatically.
- Persistence:
1. Store app key + bridge identity via existing keychain helper.
2. Persist selected target, last reactive mode, intensity, speed in user defaults.
- Safety/rate strategy:
1. REST write cap: 10 req/sec global.
2. Slider/color drags coalesced to max 5 updates/sec per target.
3. Fallback reactive loop capped at 4-8 Hz updates.
4. Entertainment loop runs independently with watchdog and auto-recover.

## Test Plan
- Unit tests:
1. Discovery result parsing and bridge selection.
2. Auth/link flow state transitions.
3. Capability mapping (light/group/scene metadata to UI flags).
4. Command queue coalescing/rate-limit behavior.
5. Reactive mapping and fallback switching logic.
- Integration tests:
1. OpenHue emulator-based API contract tests for discovery/auth/control paths.
2. Event-stream reconnect and state reconciliation tests.
3. Failure injection: dropped stream, auth expiry, bridge unreachable.
- Manual QA:
1. Real bridge pairing from clean install.
2. Core controls across white-only and color lights.
3. Scene activation correctness by room/zone.
4. Entertainment start/stop, then forced fallback behavior.
5. Long session stability while playing local and streaming tracks.

## Assumptions and Defaults
- Scope is single bridge only in v1.
- Scope excludes cloud remote access, sensor/switch configuration, and automation/rule editing.
- Reactive mode defaults to Entertainment if available, otherwise automatic grouped fallback.
- Feature ships enabled by default with explicit in-app status/errors and reconnect tools.
- Open-source acceleration stack:
1. OpenHue spec/client generation for API surface.
2. Home Assistant/aiohue and node-hue-api as behavior/reference patterns.
3. diyHue/Bifrost-class emulators for integration testing.
