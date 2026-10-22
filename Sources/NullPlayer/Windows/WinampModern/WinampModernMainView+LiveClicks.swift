import AppKit

#if DEBUG
/// `WINAMP_MODERN_LIVE_CLICKS=<seconds>@<x>,<y>[;…]`, debug builds: click the main window at view
/// point `x,y` (top-left origin, the same points `winhelper capture` measures at 1x) that many
/// seconds after it first gets a window, through the window's own `sendEvent`.
/// `<seconds>@move:<dx>,<dy>` moves the window by that many points instead (y down), which is what
/// links a background window's drop shadow when it can never become key.
///
/// Posted events never reach the app while the screen is locked or a screen saver runs, so this is
/// the way to drive a live window with nobody at the machine. Pair it with
/// `WINAMP_MODERN_ASSUME_VISIBLE=1`, or the hidden window paints nothing.
extension WinampModernMainView {
    private static var liveClicksScheduled = false

    func scheduleLiveClicksOnce() {
        guard !Self.liveClicksScheduled,
              let spec = ProcessInfo.processInfo.environment["WINAMP_MODERN_LIVE_CLICKS"] else { return }
        Self.liveClicksScheduled = true
        for entry in spec.split(separator: ";") {
            let parts = entry.split(separator: "@")
            let isMove = parts.last?.hasPrefix("move:") ?? false
            let point = parts.last?.replacingOccurrences(of: "move:", with: "")
                .split(separator: ",").compactMap { Double($0) } ?? []
            guard parts.count == 2, let delay = Double(parts[0]), point.count == 2 else {
                NSLog("[live-click] cannot read %@", String(entry))
                continue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let window = self.window else { return }
                guard isMove else { return self.postLiveClick(at: NSPoint(x: point[0], y: point[1])) }
                NSLog("[live-click] %@ moved by (%.0f,%.0f)", window.title, point[0], point[1])
                window.setFrameOrigin(NSPoint(x: window.frame.minX + point[0], y: window.frame.minY - point[1]))
            }
        }
    }

    private func postLiveClick(at topLeft: NSPoint) {
        guard let window else { return }
        let location = convert(NSPoint(x: topLeft.x, y: bounds.height - topLeft.y), to: nil)
        NSLog("[live-click] %@ at view (%.0f,%.0f)", window.title, topLeft.x, topLeft.y)
        // A move first, as a real pointer makes: a skin's hover handlers show controls that are
        // hidden until then (Anaheim's mini wheel).
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)
            else { continue }
            window.sendEvent(event)
        }
    }
}
#endif
