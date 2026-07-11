---
name: flow
description: Flow network throughput window — live download/upload meter, interface selection, single-height center-stack docking, classic/modern window controllers, and rendering behavior.
---

# Flow Network Monitor Window

Flow is a dockable network throughput meter available in classic and modern UI.

## Source Project

- Upstream reference/source project: `https://github.com/programmersd21/flow`
- License: MIT, bundled at `Sources/NullPlayer/Resources/ThirdPartyLicenses/Flow_LICENSE.txt`
- Third-party notice registration: `scripts/third_party_components.tsv` entry `flow`
- NullPlayer's implementation is a Swift/AppKit integration adapted for the classic and modern window stacks; keep user-facing credits in the third-party notices rather than duplicating them in window chrome.

## User Behavior

- Open from the `Windows` menu or the main-window context menu as **Flow**.
- Shows one direction at a time: download or upload.
- Double-click anywhere in the window body to toggle download/upload.
- The entire non-control face drags the window; see the ui-guide window-dragging requirement.
- Right-click opens the Flow menu:
  - Network interfaces, with the selected interface checked
  - **Next Interface**
  - **Show Upload View** or **Show Download View**
  - **Close**
- The selected download/upload view persists in `UserDefaults` under `NetworkMonitorDisplayDirection`.
- The selected network interface persists via `NetworkThroughputMonitor.selectedInterfaceDefaultsKey`.

## Window Layout

- Flow participates in the center window stack managed by `WindowManager`.
- It is a single-height stack window, matching the Spectrum/Waveform baseline height.
- PeppyMeter uses a taller `1.75x` landscape stack height; do not reuse PeppyMeter sizing for Flow.
- Classic uses `SkinElements.SpectrumWindow.windowSize` / `minSize`.
- Modern uses `ModernSkinElements.spectrumWindowSize` / `spectrumMinSize`.
- Restored Flow frames are normalized to the current single-height stack height so older double-height saved frames collapse to the current layout.

## Key Source Files

| File | Purpose |
|------|---------|
| `Utilities/NetworkThroughputMonitor.swift` | Network byte counters, interface selection, history, daily totals, snapshots |
| `Windows/NetworkMonitor/NetworkMonitorDrawing.swift` | Shared Flow content renderer and download/upload view persistence |
| `Windows/NetworkMonitor/NetworkMonitorView.swift` | Classic chrome, hit testing, context menu, double-click direction toggle |
| `Windows/NetworkMonitor/NetworkMonitorWindowController.swift` | Classic window lifecycle, monitor start/stop, default frame |
| `Windows/ModernNetworkMonitor/ModernNetworkMonitorView.swift` | Modern chrome, docking masks, context menu, double-click direction toggle |
| `Windows/ModernNetworkMonitor/ModernNetworkMonitorWindowController.swift` | Modern window lifecycle, monitor start/stop |
| `App/NetworkMonitorWindowProviding.swift` | Classic/modern provider abstraction |
| `App/WindowManager.swift` | Show/toggle Flow, center-stack sizing, restored-frame normalization |

## Rendering Notes

- `NetworkMonitorRenderState` smooths displayed download/upload values toward the latest snapshot.
- `NetworkMonitorDrawing.drawContent` advances both directions every frame, but draws only the selected direction.
- Flow intentionally does not draw an inner rounded panel border. The outer window chrome is the only border.
- Do not shrink the modern Flow content rect with an additional outer padding/gutter. That creates the old heavy-border appearance. Keep the content rect at the shared chrome inset and put any spacing inside `NetworkMonitorDrawing` instead.
- Classic Flow uses tighter content insets than modern so the meter fills the classic skin interior.
- Modern Flow uses the standard auxiliary chrome inset without an extra window-specific gutter. Metal Flow also expands through joined edges so its interior edge matches the thinner Metal border used by the other dockable windows.
- Tiny mode renders a compact single-line rate for the selected direction.

## Monitoring Lifecycle

- `showWindow` starts the monitor and refreshes interfaces.
- Occlusion, miniaturize, and deminiaturize notifications keep monitoring active only while visible.
- `prepareForUITeardown()` calls `tearDownMonitoring()` through `NetworkMonitorWindowProviding`.
- Interface refreshes are done on demand before menu display to avoid unnecessary per-frame interface enumeration on the main thread.

## Implementation Checks

- Keep classic and modern behavior paired; both views should support the same Flow-specific menu items and double-click toggle.
- Do not add Flow to audio-consumer or render-loop systems; it reads network counters only.
- When changing stack height rules, verify `centerStackHeightMultiplier(for:)`, `applyCenterStackSizingConstraints`, and `normalizedCenterStackRestoredFrame`.
- Build with `swift build`.
