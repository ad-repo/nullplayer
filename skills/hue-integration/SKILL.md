---
name: hue-integration
description: Philips Hue bridge discovery, pairing, TLS pinning, CLIP v2 control flow, scene/target mapping, event stream sync, and music-reactive behavior. Use when working on Hue discovery/pairing, light controls, scenes, or reactive mode.
---

# Hue Integration

NullPlayer integrates with Philips Hue bridges over the local network using CLIP v2 resources plus a dedicated Hue control window.

## Architecture

| File | Purpose |
|------|---------|
| `Hue/HueManager.swift` | Singleton facade for discovery, auth, connection state, resource refresh, command dispatch, and reactive orchestration |
| `Hue/HueBridgeDiscoveryService.swift` | Bridge discovery via Bonjour (`_hue._tcp`) with cloud discovery fallback (`https://discovery.meethue.com/`) |
| `Hue/HueAuthService.swift` | Pairing/link-button workflow and credential lifecycle |
| `Hue/HueBridgeSession.swift` | Dedicated pinned `URLSession` + TLS validation delegate for bridge trust |
| `Hue/HueCommandQueue.swift` | Command coalescing + rate limiting (global and per-slider target) |
| `Hue/HueReactiveEngine.swift` | Spectrum-driven reactive output (brightness + CCT + XY) |
| `Hue/Generated/OpenHueGeneratedClient.swift` | REST client for CLIP v2 resources and writes |
| `Hue/Generated/OpenHueGeneratedModels.swift` | Decodable resource models and envelope parsing |
| `Windows/HueControl/HueControlView.swift` | AppKit controls for discovery/pairing/target/scene/light state |
| `Windows/HueControl/HueControlWindowController.swift` | Hue window host/lifecycle |
| `App/WindowManager.swift` | Hue window visibility, restore, always-on-top behavior integration |
| `App/ContextMenuBuilder.swift` | Window/menu actions + top-level menu wiring |
| `App/AppDelegate.swift` | Top-level **Lights** menu registration |

## Control Surface and Entry Points

- Main menu: `Lights` top-level menu.
- Context menu windows section: `Hue Control`.
- Programmatic window entry: `WindowManager.showHueControlWindow()`.
- First-open behavior: tries `reconnectLastPairedBridgeIfAvailable()` then starts discovery if bridge list is empty.

## Connection Model

`HueConnectionState`:
- `disconnected`
- `discovering`
- `awaitingLinkButton`
- `connected`
- `error`

Notifications:
- `.hueStateDidChange`
- `.hueConnectionStateDidChange`

Both are posted from `HueManager` and consumed by `HueControlView`.

## Discovery and Pairing Flow

1. `HueManager.beginDiscovery()`
2. `HueBridgeDiscoveryService.discover()` starts Bonjour browse (`_hue._tcp`, `local.`) via `NWBrowser`.
3. Each service is resolved through `NWConnection` to host/port + bridge id.
4. If mDNS is slow/fails, cloud fallback queries `https://discovery.meethue.com/`.
5. User selects bridge and triggers `HueManager.pair(with:)`.
6. `HueAuthService.pair()` calls `POST /api` with:
   - `devicetype`
   - `generateclientkey: true`
7. On success, app key + bridge ID/IP are saved and connection proceeds to resource refresh.

## Credential and Persistence Keys

Keychain (generic string storage):
- `hue_app_key`
- `hue_bridge_id`
- `hue_bridge_ip`

UserDefaults:
- `hue_selected_target_id`
- `hue_reactive_mode`
- `hue_reactive_intensity`
- `hue_reactive_speed`
- `hue_scene_assignments_v1`

## CLIP v2 Resource Usage

Read resources:
- `/clip/v2/resource/light`
- `/clip/v2/resource/grouped_light`
- `/clip/v2/resource/room`
- `/clip/v2/resource/zone`
- `/clip/v2/resource/device`
- `/clip/v2/resource/scene`

Write resources:
- `PUT /clip/v2/resource/light/{id}`
- `PUT /clip/v2/resource/grouped_light/{id}`
- Optional scene recall endpoint exists in client: `PUT /clip/v2/resource/scene/{id}`.

Event stream probes (in order):
- `/eventstream/clip/v2`
- `/clip/v2/eventstream`

If event stream returns 4xx, manager stops retrying stream and continues with polling-style resource refreshes triggered by manual actions.

## Target Resolution Model

`HueControlTarget`:
- `room`
- `zone`
- `groupedLight`
- `light`

Command routing:
- `light` targets write to `light/{id}`.
- `room`, `zone`, and `groupedLight` targets write to `grouped_light/{id}`.

Important behavior in current `HueControlView`:
- UI filters to room targets only (`manager.targets.filter { $0.targetType == .room }`).
- Room-level controls and the Individual Lights section are enabled only when `selectedTarget?.targetType == .room`.
- If room → grouped-light mapping is missing, controls can appear active but commands no-op due to unresolved command ID.

## Individual Light Controls

After a scene is applied (or any time a room is selected), the **Individual Lights** section in `HueControlView` shows a scrollable list of per-light rows, one per light in the selected room.

### Per-light row capabilities
Each `HueLightRowView` renders controls based on the light's `HueCapabilityFlags`:
- **All lights**: power toggle + light name
- `supportsDimming`: brightness slider (1–100)
- `supportsColorTemperature && !supportsColor`: Color Temperature slider (153–500 mirek)
- `supportsColor`: Color well (NSColorWell, opens system color picker)

### HueManager API for individual lights
```swift
manager.lightsForSelectedRoom() -> [HueTarget]   // lights in the selected room, sorted by name
manager.state(forTarget: HueTarget) -> HueLightState?
manager.setPower(on: Bool, for: HueTarget)
manager.setBrightness(_ pct: Double, for: HueTarget)
manager.setColorTemperature(mirek: Int, for: HueTarget)
manager.setColor(x: Double, y: Double, for: HueTarget)
```
All per-target `set*` methods delegate to `sendStateCommand`, which uses `"\(target.id):\(dedupeKey)"` — so cross-light coalescing is prevented automatically.

### CIE 1931 XY ↔ NSColor conversion
Color picker display and submission use the Hue-recommended wide-gamut D65 matrices. Both conversion functions are private file-scope helpers at the bottom of `HueControlView.swift`:
- `nsColor(fromHueXY:)` — XY → XYZ (Y=1) → inverse wide-gamut matrix → sRGB gamma → `NSColor`
- `hueXY(from:)` — `NSColor` → sRGB → linearise → wide-gamut forward matrix → CIE xy

### Rebuild strategy
- Light rows are rebuilt (full teardown + recreate) only when the set of light IDs changes (room switch or bridge resource refresh).
- On `.hueStateDidChange` within the same room, only `row.update(state:isConnected:)` is called — rows and sliders persist, preventing jitter during drags.
- Each `HueLightRowView` owns its own `isProgrammaticUpdate` flag independent of the parent view.

## Scene Handling Details

- Scene list is sourced from bridge scenes.
- Manager computes scene group affinity using room/zone/light relationships.
- Applying a scene for room targets can use per-light action payload synthesis:
  - Extract mutable action payloads from scene actions.
  - Resolve room light IDs.
  - Prefer color templates for color-capable lights and CCT templates for white lights.
  - Fallback to non-chromatic templates.
- Scene assignments can be pinned per target via `hue_scene_assignments_v1`.

## Command Queue and Rate Strategy

`HueCommandQueue` (actor):
- Dedupe key per target+control channel (e.g. power/brightness/color).
- Global interval: `0.1s` (10 req/s cap).
- Slider-like per-target interval: `0.2s` (5 req/s per target).
- Latest command for same dedupe key overwrites pending command.
- Failures are logged but not surfaced as thrown errors to UI callers.

When debugging "controls do nothing", this swallowed error behavior is a primary suspect; inspect logs first.

## Reactive Mode (v1 Group Fallback)

Reactive mode currently supports:
- `off`
- `groupFallback`

Data source:
- `audioSpectrumDataUpdated` notification.
- `userInfo["spectrum"]` expected as 75-band `[Float]`.

Signal processing in `HueReactiveEngine`:
- Band partitions:
  - 0-9 bass
  - 10-29 mid
  - 30-74 high
- Bass spectral flux for onset/beat confidence.
- Rolling mean threshold (`1.5x`) for beat gating.
- EMA smoothing (`alpha = 0.3`).
- Hysteresis (`>= 80ms`) for beat state transitions.
- Dispatch cap based on speed setting (`4-8 Hz`).

Output mapping:
- Brightness 0...1
- Mirek 153...500 (warm/cool bias from bass/high balance)
- XY color lane from spectral tilt

Commands are still sent through `HueCommandQueue`.

## TLS and Session Security

Hue traffic must use a dedicated session from `HueBridgeSessionFactory.makePinnedSession(...)`.

Trust behavior:
- Attempts to anchor trust against embedded Signify root cert.
- Verifies expected bridge identity from certificate summary.
- If embedded root cert fails to decode, implementation currently falls back to identity-only match (fail-open vs strict pinning).

Practical implications:
- In strict-security contexts, treat root-cert decode failures as release blockers.
- For debugging/local development, identity-only fallback preserves functionality.

## "Controls Do Nothing" Triage Runbook

1. Confirm target resolution:
   - Verify selected target has a valid command resource ID (`groupedLightID` for room/zone targets).
2. Confirm paired credentials:
   - `currentBridge` present
   - `appKey` present
3. Validate connection state:
   - Must be `connected` after `refreshResources`.
4. Check command queue logs:
   - `HueCommandQueue: command failed for key ...`
5. Check HTTP failure logs:
   - `OpenHueGeneratedClient: <METHOD> <PATH> failed with HTTP ...`
6. Check scene/action diagnostics:
   - Missing actions, missing lights for room, or unsupported action payload.
7. Check TLS diagnostics:
   - Trust failures / bridge ID mismatch.
8. Check event stream status:
   - 4xx disables stream loop; state sync then depends on explicit refresh calls.

## Common Failure Classes

- Bridge discovered but not paired (missing app key).
- App key stored for old bridge IP after network topology change.
- Room has no resolvable grouped light service.
- UI restricted to room-only targets when resource graph is incomplete.
- Command failures hidden by queue logging-only behavior.
- TLS identity mismatch when expected bridge ID differs from cert summary token.

## Debug Logging Hotspots

- `HueManager`:
  - Discovery lifecycle
  - Pair/connect/refresh failures
  - Scene filter/application diagnostics
  - Event stream retries and disablement
- `OpenHueGeneratedClient`:
  - HTTP status/body snippets for failed requests
  - Decode failures on `POST /api` pairing
- `HueCommandQueue`:
  - Command execution failures per dedupe key
- `HueBridgeDiscoveryService`:
  - Bonjour browse/resolve/fallback state
- `HueBridgeTLSPinningDelegate`:
  - Trust evaluation and bridge-id mismatch details

## Integration Guardrails

- Keep Hue window mode-independent (works in both classic and modern UI modes).
- Keep discovery lazy (no startup browse unless user opens Hue controls or explicitly triggers discovery).
- Never route Hue actions through output-device menus; keep controls under `Lights` and dedicated Hue window.
- Preserve rate limiting/coalescing before adding higher-frequency effects.

## Testing Checklist

Manual:
1. Fresh install: local network permission prompt appears.
2. Discovery via mDNS on same LAN.
3. Pairing succeeds only after bridge link button press.
4. Room power/brightness/CCT/color well writes apply and UI state refreshes.
5. Scene activation for room targets applies expected visual state.
6. Individual Lights section appears after room selection; per-light controls match each light's capabilities.
7. Color well shows the correct hue after a scene is applied; picking a new color sends correct XY to the bridge.
8. Reactive mode responds while local/streaming playback is active.
9. Forget/reconnect flows recover cleanly.

Integration/unit targets to prioritize:
1. Resource graph mapping (room/zone/device/light/grouped_light relationships).
2. Command queue dedupe/rate enforcement.
3. Scene payload synthesis against mixed color + white bulb groups.
4. Event stream fallback/reconnect behavior.
5. TLS identity matching and root-cert parse regression tests.
