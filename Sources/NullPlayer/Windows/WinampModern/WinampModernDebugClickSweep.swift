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
///
/// Then the Library, the one other window an intake checks (`skills/skin-intake` § *The scan*): it is
/// opened the way the Windows menu opens it, its `open` row says what came up (`skin-frame`, `embedded`
/// in another skin window, NullPlayer's `plain-chrome`, or `not-opened`), a skin-frame Library's
/// controls are swept like the main window's, and its `close` row presses its own `CLOSE` control
/// and says whether the window went (`closed`) or stayed (`nochange`; `no-close-control` when it has none).
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
    private static let fields = ["window", "idx", "object", "action", "point", "volume", "play", "position", "track",
                                 "eq", "layout", "windows", "main", "note", "changed"]
    /// The playhead's own drift over one click's settle time (`step`'s 1.2 s), which is not a seek.
    private static let positionDrift: ClosedRange<TimeInterval> = -0.5...2.5
    private static let skippedActions: Set<String> = ["CLOSE", "MINIMIZE", "EXIT", "QUIT", "EJECT"]
    private static let probeVolume = 0.5
    /// The sweep keeps itself alive until `done`.
    private static var running: WinampModernDebugClickSweep?

    /// The window being swept: the main player, then the Library's.
    private weak var view: WinampModernMainView?
    private weak var main: WinampModernMainView?
    private enum Pass: String { case main, library }
    private var pass = Pass.main
    /// The skin's container id for one of its auxiliary windows, nil for any other window.
    private let containerID: (NSWindow) -> String?
    private var targets: [Target]
    private var startLayout: String
    private let startVolume: Double
    /// Put back at the end, with the volume: the EQ sliders and switches write the user's settings.
    private let startEQ: WinampModernEQSnapshot?
    /// The skin's stored settings at the start, put back at the end (B439).
    private let configuration: WinampModernConfiguration?
    private let startConfiguration: [String: Any]
    private var menuOpened = false
    private var modalOpened = false
    private weak var openMenu: NSMenu?
    private var menuObserver: NSObjectProtocol?

    static func start(on view: WinampModernMainView, configuration: WinampModernConfiguration?, containerID: @escaping (NSWindow) -> String?) {
        let startVolume = view.host.volume
        view.host.volume = probeVolume
        let sweep = WinampModernDebugClickSweep(view: view, startVolume: startVolume, configuration: configuration,
                                                containerID: containerID)
        running = sweep
        sweep.step(0)
    }

    private init(view: WinampModernMainView, startVolume: Double, configuration: WinampModernConfiguration?,
                 containerID: @escaping (NSWindow) -> String?) {
        self.view = view
        self.main = view
        self.startVolume = startVolume
        self.containerID = containerID
        startEQ = view.componentHost?.equalizerSnapshot()
        self.configuration = configuration
        startConfiguration = configuration?.storedSnapshot() ?? [:]
        startLayout = view.renderer.activeLayoutID
        targets = Self.targets(in: view)
        NSLog("WM-SMOKE start layout=%@ targets=%d", startLayout, targets.count)
        Self.logHoles(in: view, window: Pass.main.rawValue)
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
        if let hit = candidates.first(where: { renderer.object(at: $0) === object }) { return hit }
        // Battlefield_Vietnam's drawer handle is a 482x200 art whose only uncovered pixels are a
        // chevron a few points wide under the transparent part of the background (B384): no coarse
        // grid lands on it, so scan the box every 3 points before calling the object unreachable.
        // Debug only, and each probe is a full hit test on the main thread.
        for y in stride(from: box.minY + 1, to: box.maxY, by: 3) {
            for x in stride(from: box.minX + 1, to: box.maxX, by: 3) {
                let probe = CGPoint(x: x, y: y)
                if renderer.object(at: probe) === object { return probe }
            }
        }
        return nil
    }

    private static func isOnScreen(_ object: WasabiObject, in view: WinampModernMainView) -> Bool {
        view.renderer.sceneNodes().contains { $0.object === object }
    }

    private func step(_ index: Int) {
        guard let view, index < targets.count else { return pass == .main ? openLibrary() : closeLibrary() }
        let target = targets[index]
        let point = Self.point(on: target.object, in: view)
        let skip = Self.skippedActions.contains(target.action) ? "skip" : point == nil ? "unreachable" : nil
        let identity = ["window": pass.rawValue, "idx": "\(index + 1)", "object": target.label, "action": target.action]
        guard let point, skip == nil else {
            Self.log(identity.merging(["note": skip ?? ""]) { $1 })
            return step(index + 1)
        }
        let before = snapshot(view)
        // What is on screen to click before this press, so a press that hides some of it can be told.
        let laterOnScreen = targets[(index + 1)...].filter { Self.isOnScreen($0.object, in: view) }
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
            guard let self, let view = self.view, let main = self.main else { return self?.finish() ?? () }
            let after = self.snapshot(view)
            var notes: [String] = []
            if self.menuOpened { notes.append("menu") }
            if self.modalOpened { notes.append("modal") }
            if after.layout != self.startLayout, view.activateLayout(id: self.startLayout) {
                view.renderer.persistActiveLayout()
                notes.append("restored-layout")
            }
            if before.play == "playing", after.play != "playing" {
                main.host.play()
                notes.append("resumed")
            }
            // **A press that hides later controls is half of a state pair, and is pressed back.**
            // T3-Amp's Switch Mode swaps the display for its oversized twin, and with it the five
            // controls the walk was still to reach (B433). The twin's own press restores the state.
            if laterOnScreen.contains(where: { !Self.isOnScreen($0.object, in: view) }) {
                view.debugClick(atSkinPoint: point)
                notes.append("pressed-back")
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

    /// One `WM-SMOKE|` row: every key in `fields` order, `-` for one the row does not carry. A `|` in
    /// a value (a skin's XML id can hold one) becomes `/` so it cannot split the row.
    private static func log(_ values: [String: String]) {
        NSLog("%@", "WM-SMOKE|" + fields.map {
            "\($0)=\((values[$0] ?? "-").replacingOccurrences(of: "|", with: "/"))"
        }.joined(separator: "|"))
    }

    /// One `holes` row per swept window that has see-through holes inside its outline: a skin point in
    /// one, how many canvas pixels they cover, and `backed` when the backing that keeps a press there
    /// is up, `unbacked` when a press there would go to the app behind (`WinampModernHoles`).
    private static func logHoles(in view: WinampModernMainView, window: String) {
        guard let holes = view.frames.holes, !holes.isEmpty, let pixel = holes.samplePixel else { return }
        let scale = view.window?.backingScaleFactor ?? 1
        let skin = view.skinPoint(NSPoint(x: CGFloat(pixel.x) / scale, y: CGFloat(pixel.y) / scale))
        log(["window": window, "idx": "holes", "point": "\(Int(skin.x)),\(Int(skin.y))",
             "note": "pixels=\(holes.pixelCount)", "changed": view.showsHoleBacking ? "backed" : "unbacked"])
    }

    private static func quarterPoint(along frame: CGRect) -> CGPoint {
        frame.width >= frame.height ? CGPoint(x: frame.minX + frame.width / 4, y: frame.midY)
            : CGPoint(x: frame.midX, y: frame.minY + frame.height / 4)
    }

    /// Open the Library from a closed start and say what opened; a skin-frame Library is swept next.
    private func openLibrary() {
        let manager = WindowManager.shared
        if manager.isMediaLibraryVisible { manager.toggleMediaLibrary() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let before = Set(Self.visibleWindows().map(ObjectIdentifier.init))
            manager.showMediaLibrary()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                let opened = Self.visibleWindows().filter { !before.contains(ObjectIdentifier($0)) }
                let skinView = opened.lazy.compactMap { Self.skinView(in: $0.contentView) }.first
                let kind = skinView != nil ? "skin-frame"
                    : !opened.isEmpty ? "plain-chrome"
                    : manager.isMediaLibraryVisible ? "embedded" : "not-opened"
                let names = opened.map { "+\(self.containerID($0) ?? ($0.title.isEmpty ? "\(type(of: $0))" : $0.title))"
                    + "(\(Int($0.frame.width))x\(Int($0.frame.height)))" }
                Self.log(["window": "library", "idx": "open", "windows": names.isEmpty ? "-" : names.joined(separator: ","),
                          "note": kind, "changed": manager.isMediaLibraryVisible ? "windows" : "nochange"])
                guard let skinView else {
                    if manager.isMediaLibraryVisible { manager.toggleMediaLibrary() }
                    return self.finish()
                }
                self.pass = .library
                self.view = skinView
                self.startLayout = skinView.renderer.activeLayoutID
                self.targets = Self.targets(in: skinView)
                NSLog("WM-SMOKE library layout=%@ targets=%d", self.startLayout, self.targets.count)
                Self.logHoles(in: skinView, window: Pass.library.rawValue)
                self.step(0)
            }
        }
    }

    /// Press the Library's own close control and say whether its window went.
    private func closeLibrary() {
        let manager = WindowManager.shared
        guard let view, let window = view.window,
              // The first CLOSE that is on screen: Just_Buttons pairs a hidden `Close.inactive` with `Close`.
              let (close, point) = targets.lazy.filter({ $0.action == "CLOSE" })
                  .compactMap({ target in Self.point(on: target.object, in: view).map { (target, $0) } }).first else {
            // A frame with no `CLOSE` art closes from the base rule's invisible corner (B432); press
            // that, through the same chrome hit the window takes.
            guard let view = self.view, let window = view.window, view.needsFallbackClose,
                  case let corner = FallbackCloseArea.rect(in: view.bounds, flipped: view.isFlipped),
                  view.hostChromeHit(at: NSPoint(x: corner.midX, y: corner.midY)) == .close else {
                Self.log(["window": "library", "idx": "close", "note": "no-close-control", "changed": "-"])
                if manager.isMediaLibraryVisible { manager.toggleMediaLibrary() }
                return finish()
            }
            view.requestClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                let closed = !window.isVisible || window.alphaValue == 0
                Self.log(["window": "library", "idx": "close", "object": "fallback-corner", "action": "CLOSE",
                          "note": "fallback-corner", "changed": closed ? "closed" : "nochange"])
                if !closed, manager.isMediaLibraryVisible { manager.toggleMediaLibrary() }
                self?.finish()
            }
            return
        }
        view.debugClick(atSkinPoint: point)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            let closed = !window.isVisible || window.alphaValue == 0
            Self.log(["window": "library", "idx": "close", "object": close.label, "action": close.action,
                      "point": "\(Int(point.x)),\(Int(point.y))", "changed": closed ? "closed" : "nochange"])
            if !closed, manager.isMediaLibraryVisible { manager.toggleMediaLibrary() }
            self?.finish()
        }
    }

    private static func visibleWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 && !$0.ignoresMouseEvents }
    }

    private static func skinView(in view: NSView?) -> WinampModernMainView? {
        guard let view else { return nil }
        if let skin = view as? WinampModernMainView { return skin }
        return view.subviews.lazy.compactMap { skinView(in: $0) }.first
    }

    private func snapshot(_ view: WinampModernMainView) -> Snapshot {
        // A skin window is named by its container id (`stick`), anything else by title or class.
        var windows: [ObjectIdentifier: String] = [:]
        for window in Self.visibleWindows() {  // not a skin's drop-shadow window
            let name = containerID(window) ?? (window.title.isEmpty ? "\(type(of: window))" : window.title)
            windows[ObjectIdentifier(window)] = "\(name)(\(Int(window.frame.width))x\(Int(window.frame.height)))"
                .replacingOccurrences(of: "|", with: "/")
        }
        let main = self.main?.window
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
        main?.host.volume = startVolume
        if let startEQ, let host = main?.componentHost {
            host.equalizerSetAuto(startEQ.auto)
            host.equalizerSetEnabled(startEQ.enabled)
            host.equalizerSetPreampDB(startEQ.preampDB)
            startEQ.bandGainsDB.enumerated().forEach { host.equalizerSetBandGainDB($0.offset, gainDB: $0.element) }
        }
        configuration?.restoreStored(startConfiguration)
        menuObserver.map(NotificationCenter.default.removeObserver)
        NSLog("WM-SMOKE done")
        Self.running = nil
    }
}
#endif
