#if DEBUG
import AppKit

/// `WINAMP_MODERN_DEBUG_CLICK=auto`: click every clickable object in the main window's current layout,
/// two seconds apart, through `WinampModernMainView.debugClick`, and log one `WM-SMOKE|key=value|…` row
/// per object with what changed, its keys in `fields` order. `scripts/wal_live_smoke.sh` drives it and
/// turns the rows into a TSV, reading each value by its key; see `harness.md` § *Driving a click in the
/// running app*.
///
/// Clickable means a markup `action=` or a script left-press hook. A slider takes its value on press
/// and drag, which `debugClick` (the release path) never replays, so a slider is dragged
/// (`WinampModernMainView.debugDrag`) to a quarter of the way along its long axis. Window commands that would end the
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

    /// The keys of a `WM-SMOKE|` row, in order. A row the sweep did not click carries the first three
    /// and `note`; the rest read `-`. `changed` is the verdict: what moved, or `nochange`.
    private static let fields = ["idx", "object", "action", "point", "volume", "play", "position", "track",
                                 "eq", "layout", "windows", "main", "note", "changed"]
    /// The playhead's own drift over one click's settle time (`step`'s 1.2 s), which is not a seek.
    private static let positionDrift: ClosedRange<TimeInterval> = -0.5...2.5
    private static let skippedActions: Set<String> = ["CLOSE", "MINIMIZE", "EXIT", "QUIT", "EJECT"]
    private static let probeVolume = 0.5
    /// The sweep keeps itself alive until `done`.
    private static var running: WinampModernDebugClickSweep?

    private weak var view: WinampModernMainView?
    /// The skin's container id for one of its auxiliary windows, nil for any other window.
    private let containerID: (NSWindow) -> String?
    private let targets: [Target]
    private let startLayout: String
    private let startVolume: Double
    /// Put back at the end, with the volume: the EQ sliders and switches write the user's settings.
    private let startEQ: WinampModernEQSnapshot?
    private var menuOpened = false
    private var modalOpened = false
    private weak var openMenu: NSMenu?
    private var menuObserver: NSObjectProtocol?

    static func start(on view: WinampModernMainView, containerID: @escaping (NSWindow) -> String?) {
        let startVolume = view.host.volume
        view.host.volume = probeVolume
        let sweep = WinampModernDebugClickSweep(view: view, startVolume: startVolume, containerID: containerID)
        running = sweep
        sweep.step(0)
    }

    private init(view: WinampModernMainView, startVolume: Double, containerID: @escaping (NSWindow) -> String?) {
        self.view = view
        self.startVolume = startVolume
        self.containerID = containerID
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
        let identity = ["idx": "\(index + 1)", "object": target.label, "action": target.action]
        guard let point, skip == nil else {
            Self.log(identity.merging(["note": skip ?? ""]) { $1 })
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
        if let dragEnd { view.debugDrag(fromSkinPoint: point, to: dragEnd) } else { view.debugClick(atSkinPoint: point) }
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
            let changed = [
                // At the row's two decimals: a host's float round trip is not a volume change.
                ("volume", (before.volume * 100).rounded() != (after.volume * 100).rounded()),
                ("play", before.play != after.play),
                ("position", !Self.positionDrift.contains(after.position - before.position)),
                ("track", before.track != after.track), ("eq", before.eq != after.eq),
                ("layout", before.layout != after.layout), ("windows", !windows.isEmpty),
                ("main", before.mainOnScreen != after.mainOnScreen),
                ("menu", self.menuOpened), ("modal", self.modalOpened),
            ].filter(\.1).map(\.0)
            Self.log(identity.merging([
                "point": "\(Int(point.x)),\(Int(point.y))" + (dragEnd.map { ">\(Int($0.x)),\(Int($0.y))" } ?? ""),
                "volume": String(format: "%.2f>%.2f", before.volume, after.volume),
                "play": "\(before.play)>\(after.play)",
                "position": String(format: "%.1f>%.1f", before.position, after.position),
                "track": "\(before.track)>\(after.track)",
                "eq": "\(before.eq)>\(after.eq)",
                "layout": "\(before.layout)>\(after.layout)",
                "windows": windows.isEmpty ? "-" : windows,
                "main": "\(before.mainOnScreen ? 1 : 0)>\(after.mainOnScreen ? 1 : 0)",
                "note": notes.joined(separator: ","),
                "changed": changed.isEmpty ? "nochange" : changed.joined(separator: ","),
            ]) { $1 })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.step(index + 1) }
        }
    }

    /// One `WM-SMOKE|` row: every key in `fields` order, `-` for one the row does not carry.
    private static func log(_ values: [String: String]) {
        NSLog("%@", "WM-SMOKE|" + fields.map { "\($0)=\(values[$0] ?? "-")" }.joined(separator: "|"))
    }

    private static func quarterPoint(along frame: CGRect) -> CGPoint {
        frame.width >= frame.height ? CGPoint(x: frame.minX + frame.width / 4, y: frame.midY)
            : CGPoint(x: frame.midX, y: frame.minY + frame.height / 4)
    }

    private func snapshot(_ view: WinampModernMainView) -> Snapshot {
        // A skin window is named by its container id (`stick`), anything else by title or class.
        var windows: [ObjectIdentifier: String] = [:]
        for window in NSApp.windows where window.isVisible && window.alphaValue > 0
            && !window.ignoresMouseEvents {  // not a skin's drop-shadow window
            let name = containerID(window) ?? (window.title.isEmpty ? "\(type(of: window))" : window.title)
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
