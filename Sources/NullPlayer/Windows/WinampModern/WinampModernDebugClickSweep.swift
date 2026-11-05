#if DEBUG
import AppKit

/// `WINAMP_MODERN_DEBUG_CLICK=auto`: click every clickable object in the main window's current layout,
/// two seconds apart, through `WinampModernMainView.debugClick`, and log one `WM-SMOKE|…` row per click
/// with what changed. `scripts/wal_live_smoke.sh` drives it and turns the rows into a TSV; see
/// `harness.md` § *Driving a click in the running app*.
///
/// Clickable means a markup `action=` or a script left-press hook. A slider takes its value on press
/// and drag, which `debugClick` (the release path) never replays, so a slider is driven through the
/// view's own `mouseDown`/`mouseDragged`/`mouseUp` to a quarter of the way along its long axis. Window commands that would end the
/// run (close, minimize, quit) and `EJECT`'s modal file panel are skipped; a menu or modal alert a click
/// pops up is dismissed and noted. Between clicks the sweep puts back the starting layout and resumes playback,
/// and the run starts from volume 0.5 so a control that pins it to either end shows. (Not reset per
/// click: a skin's mute re-asserts 0 on every volume change, which would mark every later row.)
final class WinampModernDebugClickSweep {
    private struct Target {
        let object: WasabiObject
        let label: String
        let action: String
    }

    private struct Snapshot {
        let volume: Double
        let play: String
        let position: TimeInterval
        let track: String
        let eq: String
        let layout: String
        let windows: [ObjectIdentifier: String]
        let mainOnScreen: Bool
    }

    private static let skippedActions: Set<String> = ["CLOSE", "MINIMIZE", "EXIT", "QUIT", "EJECT"]
    private static let probeVolume = 0.5
    /// The sweep keeps itself alive until `done`.
    private static var running: WinampModernDebugClickSweep?

    private weak var view: WinampModernMainView?
    private let targets: [Target]
    private let startLayout: String
    private let startVolume: Double
    /// Put back at the end, with the volume: the EQ sliders and switches write the user's settings.
    private let startEQ: WinampModernEQSnapshot?
    private var menuOpened = false
    private var modalOpened = false
    private weak var openMenu: NSMenu?
    private var menuObserver: NSObjectProtocol?

    static func start(on view: WinampModernMainView) {
        let startVolume = view.host.volume
        view.host.volume = probeVolume
        let sweep = WinampModernDebugClickSweep(view: view, startVolume: startVolume)
        running = sweep
        sweep.step(0)
    }

    private init(view: WinampModernMainView, startVolume: Double) {
        self.view = view
        self.startVolume = startVolume
        startEQ = view.componentHost?.equalizerSnapshot()
        startLayout = view.renderer.activeLayoutID
        targets = Self.targets(in: view)
        NSLog("WM-SMOKE start layout=%@ targets=%d", startLayout, targets.count)
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
        ) { [weak self] note in
            self?.menuOpened = true
            self?.openMenu = note.object as? NSMenu
        }
    }

    /// One target per object, in draw order.
    private static func targets(in view: WinampModernMainView) -> [Target] {
        let renderer = view.renderer
        var seen = Set<WasabiObjectID>()
        return renderer.sceneNodes().compactMap { node in
            let object = node.object
            guard renderer.isVisible(object), seen.insert(object.stableID).inserted else { return nil }
            let action = object.attributes["action"].map {
                WasabiClickAction.split(action: $0, parameter: nil).action.uppercased()
            }
            guard action != nil || view.scripts.hasPressBinding(for: object, button: .left) else { return nil }
            return Target(object: object, label: "\(object.typeName)#\(object.xmlID ?? "-")",
                          action: action.flatMap { $0.isEmpty ? nil : $0 } ?? "-")
        }
    }

    /// A point the hit test returns for `object` now: the centre, else the first of a 5x5 grid over
    /// its visible box (an arc or ring has nothing at its centre). Aimed when it is clicked, not when
    /// the run starts, because an earlier click can move it: Fantana's drawer slide carries the
    /// transport 70 px down, and buttons aimed at the start hit the drawer it uncovered (B370).
    private static func point(on object: WasabiObject, in view: WinampModernMainView) -> CGPoint? {
        let renderer = view.renderer
        guard let node = renderer.sceneNodes().first(where: { $0.object === object }) else { return nil }
        let box = node.frame.intersection(node.clip)
        guard !box.isEmpty else { return nil }
        var candidates = [CGPoint(x: box.midX, y: box.midY)]
        for row in 0..<5 { for column in 0..<5 {
            candidates.append(CGPoint(x: box.minX + box.width * (CGFloat(column) + 0.5) / 5,
                                      y: box.minY + box.height * (CGFloat(row) + 0.5) / 5))
        } }
        return candidates.first { renderer.object(at: $0) === object }
    }

    private func step(_ index: Int) {
        guard let view, index < targets.count else { return finish() }
        let target = targets[index]
        let point = Self.point(on: target.object, in: view)
        let skip = Self.skippedActions.contains(target.action) ? "skip" : point == nil ? "unreachable" : nil
        guard let point, skip == nil else {
            let fields = [String(index + 1), target.label, target.action] + Array(repeating: "-", count: 9) + [skip ?? ""]
            NSLog("%@", "WM-SMOKE|" + fields.joined(separator: "|"))
            return step(index + 1)
        }
        let before = snapshot(view)
        menuOpened = false
        modalOpened = false
        // A popped menu or a modal alert holds the main thread inside `debugClick`, and GCD does not
        // run during menu tracking; a timer in the common modes (event tracking, modal panel) does.
        let unblock = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.openMenu?.cancelTracking()
            if NSApp.modalWindow != nil {
                self?.modalOpened = true
                NSApp.abortModal()
            }
        }
        RunLoop.main.add(unblock, forMode: .common)
        let dragEnd = target.object.tag.is(.slider)
            ? view.renderer.frame(of: target.object).map(Self.quarterPoint) : nil
        if let dragEnd { drag(view, from: point, to: dragEnd) } else { view.debugClick(atSkinPoint: point) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let view = self.view else { return self?.finish() ?? () }
            let after = self.snapshot(view)
            var notes: [String] = []
            if self.menuOpened { notes.append("menu") }
            if self.modalOpened { notes.append("modal") }
            if after.layout != self.startLayout, view.activateLayout(id: self.startLayout) {
                view.renderer.persistActiveLayout()
                notes.append("restored-layout")
            }
            if before.play == "playing", after.play != "playing" {
                view.host.play()
                notes.append("resumed")
            }
            let windows = Set(before.windows.keys).symmetricDifference(after.windows.keys).map { id in
                after.windows[id].map { "+\($0)" } ?? "-\(before.windows[id] ?? "?")"
            }.sorted().joined(separator: ",")
            let fields = [
                "\(index + 1)", target.label, target.action,
                "\(Int(point.x)),\(Int(point.y))" + (dragEnd.map { ">\(Int($0.x)),\(Int($0.y))" } ?? ""),
                String(format: "%.2f>%.2f", before.volume, after.volume),
                "\(before.play)>\(after.play)",
                String(format: "%.1f>%.1f", before.position, after.position),
                "\(before.track)>\(after.track)",
                "\(before.eq)>\(after.eq)",
                "\(before.layout)>\(after.layout)",
                windows.isEmpty ? "-" : windows,
                "\(before.mainOnScreen ? 1 : 0)>\(after.mainOnScreen ? 1 : 0)",
                notes.joined(separator: ","),
            ]
            NSLog("%@", "WM-SMOKE|" + fields.joined(separator: "|"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.step(index + 1) }
        }
    }

    private static func quarterPoint(along frame: CGRect) -> CGPoint {
        frame.width >= frame.height ? CGPoint(x: frame.minX + frame.width / 4, y: frame.midY)
            : CGPoint(x: frame.midX, y: frame.minY + frame.height / 4)
    }

    /// Press at `start`, drag to `end` and release there, as real events through the view's handlers.
    private func drag(_ view: WinampModernMainView, from start: CGPoint, to end: CGPoint) {
        guard let window = view.window else { return }
        func event(_ type: NSEvent.EventType, at skin: CGPoint) -> NSEvent? {
            let location = view.convert(view.viewRect(fromSkin: CGRect(origin: skin, size: .zero)).origin, to: nil)
            return NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                      clickCount: 1, pressure: 1)
        }
        event(.leftMouseDown, at: start).map(view.mouseDown)
        event(.leftMouseDragged, at: end).map(view.mouseDragged)
        event(.leftMouseUp, at: end).map(view.mouseUp)
    }

    private func snapshot(_ view: WinampModernMainView) -> Snapshot {
        // A skin window is named by its container id (`stick`), anything else by title or class.
        let containers = (view.window?.windowController as? WinampModernMainWindowController)?
            .auxiliaryContainers ?? []
        var windows: [ObjectIdentifier: String] = [:]
        for window in NSApp.windows where window.isVisible && window.alphaValue > 0
            && !window.ignoresMouseEvents {  // not a skin's drop-shadow window
            let name = containers.first { $0.window === window }?.containerID
                ?? (window.title.isEmpty ? "\(type(of: window))" : window.title)
            windows[ObjectIdentifier(window)] = "\(name)(\(Int(window.frame.width))x\(Int(window.frame.height)))"
                .replacingOccurrences(of: "|", with: "/")
        }
        let main = view.window
        let track = String((view.host.trackPath as NSString).lastPathComponent.prefix(40))
            .replacingOccurrences(of: "|", with: "/")
        // On/off, auto, preamp, and a checksum of the bands: enough to say whether any of them moved.
        let eq = view.componentHost.map { host -> String in
            let snapshot = host.equalizerSnapshot()
            let bands = snapshot.bandGainsDB.enumerated().reduce(0) { $0 + ($1.offset + 1) * Int(($1.element * 10).rounded()) }
            return String(format: "e%da%dp%+.1fb%d", snapshot.enabled ? 1 : 0, snapshot.auto ? 1 : 0,
                          Double(snapshot.preampDB), bands)
        } ?? "-"
        return Snapshot(volume: view.host.volume, play: "\(view.host.playbackState)",
                        position: view.host.currentTime, track: track.isEmpty ? "-" : track, eq: eq,
                        layout: view.renderer.activeLayoutID,
                        windows: windows, mainOnScreen: main?.isVisible == true && (main?.alphaValue ?? 0) > 0)
    }

    private func finish() {
        view?.host.volume = startVolume
        if let startEQ, let host = view?.componentHost {
            host.equalizerSetAuto(startEQ.auto)
            host.equalizerSetEnabled(startEQ.enabled)
            host.equalizerSetPreampDB(startEQ.preampDB)
            startEQ.bandGainsDB.enumerated().forEach { host.equalizerSetBandGainDB($0.offset, gainDB: $0.element) }
        }
        menuObserver.map(NotificationCenter.default.removeObserver)
        NSLog("WM-SMOKE done targets=%d", targets.count)
        Self.running = nil
    }
}
#endif
