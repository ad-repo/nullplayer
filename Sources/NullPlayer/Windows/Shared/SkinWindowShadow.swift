import AppKit
import QuartzCore

/// The window a skinned window's drop shadow is drawn in. Its own class so `WindowManager` can
/// exempt it by type, and its own title so agent tooling can recognise it in the window list.
final class SkinShadowWindow: NSWindow {
    /// The fixed title `winhelper` filters on. Never shown: the window has no title bar.
    static let marker = "NullPlayer.SkinShadow"

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.transient, .ignoresCycle]
        // It follows its parent in and out; a fade of its own would leave it trailing behind.
        animationBehavior = .none
        title = Self.marker
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.contentsGravity = .resize
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// **Wherever its parent is, never where AppKit would rather it were.** A skin window may sit
    /// above the menu bar by its own transparent rows (`WMPSkinWindow.constrainFrameRect`), and the
    /// default constraint pushed this one back below it: dragging `BlueCrush_MP7` up to the screen
    /// top left the shadow — knockout and all — 165 pt below the skin as a second outline of it.
    /// This covers a frame set on the shadow itself; AppKit still clamps it when it carries the
    /// child along with a moving parent, and `SkinWindowShadow.reassert()` puts it back from the
    /// parent's `didMoveNotification` in the same turn (measured: one `reassert frame` per drag
    /// step while the skin is above the screen top, none below it).
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// **A macOS-style drop shadow for a shaped `.wmz` or `.wal` window, built from the window's own
/// shape so it can never go stale.**
///
/// Those windows keep `hasShadow = false`. AppKit builds a borderless window's shadow from a cached
/// copy of what it last drew, and these windows change shape — drawers slide, panes open, the view
/// switches — so the cached shadow went stale and read as a dark box the size of the window, and
/// `invalidateShadow()` on every present and frame change did not hold against playback repaints.
/// Instead the shadow is a click-through child window ordered `.below` the skin, holding a blurred
/// copy of the skin's alpha with the shape itself knocked back out. It is rebuilt only when the
/// shape's bytes change, never on a repaint that left the outline alone.
///
/// **It looks after itself.** `attach` hands it the window and a `shape` to pull the outline from;
/// from then on it watches the window's move, key, resize and occlusion notifications and the
/// preference, and repairs its own link, order and frame. The owner's one job is
/// `invalidateShape` when its content may have moved the outline. A pull waits for the window to be
/// on screen, for the previous build to land and for `minimumInterval`, so any number of
/// invalidations cost one pull of the newest shape.
@MainActor
final class SkinWindowShadow {
    /// One key for both families. Default on.
    nonisolated static let isEnabledDefaultsKey = "skinWindowShadows"
    nonisolated static let enabledDidChange = Notification.Name("NullPlayer.skinWindowShadowsDidChange")

    /// Close to an inactive macOS window's shadow, tuned on screen beside a Classic window.
    nonisolated static let blur: CGFloat = 12
    nonisolated static let offset = CGSize(width: 0, height: -4)
    nonisolated static let opacity: CGFloat = 0.35
    /// At least `blur * 2 + |offset|`, so the blur is never clipped at the shadow window's edge.
    nonisolated static let pad: CGFloat = 30

    nonisolated static var isEnabledPreference: Bool {
        get { UserDefaults.standard.object(forKey: isEnabledDefaultsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: isEnabledDefaultsKey)
            NotificationCenter.default.post(name: enabledDidChange, object: nil)
        }
    }

    nonisolated static let isTraceEnabled = ProcessInfo.processInfo.environment["NP_SKIN_SHADOW_TRACE"] == "1"

    let shadowWindow = SkinShadowWindow()
    /// The fewest seconds between two pulls of `shape`. A `.wal` outline is a render made for the
    /// purpose, on the main thread; a `.wmz` one is the frame the window already presented.
    private let minimumInterval: CFTimeInterval
    private weak var parent: NSWindow?
    private var name = "?"
    private var shape: () -> [CGImage] = { [] }
    private var parentObservers: [NSObjectProtocol] = []
    private var preferenceObserver: NSObjectProtocol?
    /// `isEnabledPreference`, cached from its notification: read on every drag step.
    private var isEnabled = SkinWindowShadow.isEnabledPreference
    /// The parent's `occlusionState`, cached from its notification for the same reason.
    private var isParentOnScreen = false
    private var lastFingerprint: Int?

    init(minimumInterval: CFTimeInterval = 0) {
        self.minimumInterval = minimumInterval
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: Self.enabledDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPreference() }
            }
    }

    deinit {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
        parentObservers.forEach(NotificationCenter.default.removeObserver)
        let window = shadowWindow
        DispatchQueue.main.async {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
    }

    // MARK: Attachment

    /// Whether there is a window to shadow and the preference wants one — the cheap check an owner
    /// makes before doing any work toward `invalidateShape`.
    var isActive: Bool { parent != nil && isEnabled }

    /// Shadow `parent` from now on, pulling its outline from `shape`: layers drawn over each other
    /// at the window's size, whose combined alpha is the shape. `name` is only for the trace.
    /// Attaching again to the same window only takes the new `name` and `shape`.
    func attach(to parent: NSWindow, name: String, shape: @escaping () -> [CGImage]) {
        self.name = name
        self.shape = shape
        guard self.parent !== parent else { reassert(); return }
        detach()
        self.parent = parent
        let center = NotificationCenter.default
        parentObservers.append(center.addObserver(forName: NSWindow.didMoveNotification,
                                                  object: parent, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.reassertAfterMove() }
        })
        for event in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification] {
            parentObservers.append(center.addObserver(forName: event, object: parent, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.reassert() }
            })
        }
        parentObservers.append(center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: parent, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.parentOcclusionDidChange() }
            })
        isParentOnScreen = parent.occlusionState.contains(.visible)
        reassert()
        invalidateShape("attach")
    }

    func detach() {
        parentObservers.forEach(NotificationCenter.default.removeObserver)
        parentObservers.removeAll()
        shadowWindow.parent?.removeChildWindow(shadowWindow)
        shadowWindow.orderOut(nil)
        parent = nil
        pendingTrigger = nil
    }

    /// Put the frame, the link and the order back if anything has moved them. A few compares on the
    /// common path. The level needs nothing: AppKit keeps a child window at its parent's level,
    /// Always on Top included.
    private func reassert() {
        guard let parent, isEnabled, parent.isVisible else { return }
        let frame = parent.frame.insetBy(dx: -Self.pad, dy: -Self.pad)
        if shadowWindow.frame != frame {
            shadowWindow.setFrame(frame, display: false)
            trace("reassert frame \(Int(parent.frame.width))x\(Int(parent.frame.height))")
        }
        if shadowWindow.parent !== parent {
            shadowWindow.parent?.removeChildWindow(shadowWindow)
            parent.addChildWindow(shadowWindow, ordered: .below)
            trace("reassert parent")
        } else if !shadowWindow.isVisible || shadowWindow.orderedIndex < parent.orderedIndex {
            // Order counts from the front, so a smaller index is in front of the parent.
            shadowWindow.order(.below, relativeTo: parent.windowNumber)
            trace("reassert order")
        }
    }

    private var isMoveCheckScheduled = false

    /// **A move is checked a turn late, and only for the frame.** AppKit carries a child window
    /// with its parent *after* posting the parent's `didMove`, so a check made inside the
    /// notification always saw the old frame. It then set the shadow's frame itself and asked
    /// for `orderedIndex`, which lists every window on the system. That was three window-server
    /// round trips per drag step per window, measured as most of the drag handler's time. A move
    /// cannot change the order. One turn later the carry has landed, so the check is a compare
    /// unless AppKit clamped the shadow below the menu bar (`SkinShadowWindow.constrainFrameRect`).
    private func reassertAfterMove() {
        guard !isMoveCheckScheduled else { return }
        isMoveCheckScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.checkFrameAfterMove() }
        }
    }

    private func checkFrameAfterMove() {
        isMoveCheckScheduled = false
        guard let parent, isEnabled, parent.isVisible, shadowWindow.parent === parent else {
            reassert()
            return
        }
        let frame = parent.frame.insetBy(dx: -Self.pad, dy: -Self.pad)
        if shadowWindow.frame != frame {
            shadowWindow.setFrame(frame, display: false)
            trace("reassert frame after move \(Int(parent.frame.width))x\(Int(parent.frame.height))")
        }
    }

    /// A window that comes back on screen also takes the pull it was owed while hidden.
    private func parentOcclusionDidChange() {
        isParentOnScreen = parent?.occlusionState.contains(.visible) ?? false
        reassert()
        pullShapeWhenDue()
    }

    private func applyPreference() {
        isEnabled = Self.isEnabledPreference
        guard parent != nil else { return }
        if isEnabled {
            lastFingerprint = nil
            reassert()
            invalidateShape("enabled")
        } else {
            pendingTrigger = nil
            shadowWindow.parent?.removeChildWindow(shadowWindow)
            shadowWindow.orderOut(nil)
        }
    }

    // MARK: Shape

    /// One serial queue for every window's shape work. A clock-ticking skin hands over a full frame
    /// ten times a second whose outline never moves; checking that on the main thread cost 3.5-10 ms
    /// a tick in a debug build (`corona`, 2026-10-01).
    nonisolated private static let worker = DispatchQueue(label: "NullPlayer.SkinWindowShadow",
                                                         qos: .userInitiated)
    /// Why the shape was last invalidated, while a pull is owed. Only the newest matters.
    private var pendingTrigger: String?
    private var lastPull: CFAbsoluteTime = 0
    private var isPullScheduled = false
    private var isBuilding = false

    private struct ShapeRequest {
        let layers: [CGImage]
        let width: Int
        let height: Int
        let trigger: String
    }

    private enum ShapeResult {
        case failed
        case same
        case rebuilt(fingerprint: Int, image: CGImage?)
    }

    /// The window's outline may have moved. The shape is pulled once the window is on screen, the
    /// previous build has landed and `minimumInterval` has passed since the last pull; the alpha
    /// is compared off the main thread, and the shadow is rebuilt only when it moved.
    func invalidateShape(_ trigger: String) {
        guard isActive else { return }
        pendingTrigger = trigger
        pullShapeWhenDue()
    }

    private func pullShapeWhenDue() {
        guard let trigger = pendingTrigger, let parent, isEnabled, isParentOnScreen,
              !isBuilding, !isPullScheduled else { return }
        let wait = lastPull + minimumInterval - CFAbsoluteTimeGetCurrent()
        if wait > 0 {
            // Leading edge at once, the rest coalesced into one trailing pull that catches the
            // end of an animation.
            isPullScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                MainActor.assumeIsolated {
                    self?.isPullScheduled = false
                    self?.pullShapeWhenDue()
                }
            }
            return
        }
        pendingTrigger = nil
        let started = CFAbsoluteTimeGetCurrent()
        lastPull = started
        let layers = shape()
        guard !layers.isEmpty else { return }
        // Pulling a `.wal` outline is main-thread work the build's own (off-main) timing cannot see.
        let label = Self.isTraceEnabled
            ? trigger + String(format: " pull=%.1fms", (CFAbsoluteTimeGetCurrent() - started) * 1_000)
            : trigger
        startBuild(ShapeRequest(layers: layers,
                                width: max(1, Int(parent.frame.width.rounded())),
                                height: max(1, Int(parent.frame.height.rounded())),
                                trigger: label))
    }

    private func startBuild(_ request: ShapeRequest) {
        isBuilding = true
        let known = lastFingerprint
        Self.worker.async { [weak self] in
            let started = CFAbsoluteTimeGetCurrent()
            let result = Self.shape(request, known: known)
            let milliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1_000
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finishBuild(result, request: request, milliseconds: milliseconds)
                }
            }
        }
    }

    private func finishBuild(_ result: ShapeResult, request: ShapeRequest, milliseconds: Double) {
        isBuilding = false
        defer { pullShapeWhenDue() }
        guard isActive else { return }
        let detail = "\(request.width)x\(request.height) "
            + String(format: "%.1fms", milliseconds) + " trigger=\(request.trigger)"
        switch result {
        case .failed:
            trace("failed \(detail)")
        case .same:
            trace("same \(detail)")
        case .rebuilt(let fingerprint, let image):
            lastFingerprint = fingerprint
            shadowWindow.contentView?.layer?.contents = image
            trace("rebuild \(detail)")
        }
    }

    /// Off the main thread: fingerprint the outline, and build a shadow only for a new one.
    nonisolated private static func shape(_ request: ShapeRequest, known: Int?) -> ShapeResult {
        guard let plane = AlphaPlane(layers: request.layers, width: request.width,
                                     height: request.height) else { return .failed }
        var hasher = Hasher()
        hasher.combine(request.width)
        hasher.combine(request.height)
        plane.bytes.withUnsafeBytes { hasher.combine(bytes: $0) }
        let fingerprint = hasher.finalize()
        if fingerprint == known { return .same }
        return .rebuilt(fingerprint: fingerprint,
                        image: makeShadowImage(plane: plane, blur: blur, offset: offset,
                                               opacity: opacity, pad: pad))
    }

    private func trace(_ message: String) {
        guard Self.isTraceEnabled else { return }
        NSLog("[shadow] %@ %@", name, message)
    }

    // MARK: Pure image work

    /// The shadow for `plane`'s shape, `pad` larger on every side.
    ///
    /// The shape is drawn with a shadow, then cut back out with a **binarized** copy of itself:
    /// a plain `.destinationOut` leaves shadow x (1 - alpha) under translucent art, which would
    /// still darken it from behind. macOS clears its shadow under the whole window shape, and this
    /// matches that — so the only pixels left are the shadow outside the outline.
    nonisolated static func makeShadowImage(plane: AlphaPlane, blur: CGFloat, offset: CGSize,
                                            opacity: CGFloat, pad: CGFloat) -> CGImage? {
        let padding = Int(pad.rounded(.up))
        let width = plane.width + padding * 2
        let height = plane.height + padding * 2
        guard let shape = plane.blackImage(),
              let knockout = plane.blackImage(mappedThrough: knockoutTable),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: padding, y: padding, width: plane.width, height: plane.height)
        context.saveGState()
        context.setShadow(offset: offset, blur: blur,
                          color: CGColor(gray: 0, alpha: opacity))
        context.draw(shape, in: rect)
        context.restoreGState()
        context.setBlendMode(.destinationOut)
        context.draw(knockout, in: rect)
        return context.makeImage()
    }

    /// How much of the shadow a pixel of artwork at `alpha` clears from under itself.
    ///
    /// **Not `alpha > 0`.** `corona` paints its own soft shadow, black at alpha 1-60, 16 pt below
    /// the player's solid edge (measured on a window capture, 2026-10-01). Clearing under every
    /// non-zero pixel cut the real shadow away beneath that invisible glow, and the desktop showed
    /// through as a white band between the skin and its shadow — reported as "a white window
    /// extension, not a shadow". So a faint pixel clears nothing, solid art clears everything, and
    /// translucent art clears in proportion, which still keeps a glass panel from being darkened
    /// from behind.
    nonisolated static func knockoutAlpha(_ alpha: UInt8) -> UInt8 {
        let floor = 16, ceiling = 128
        let value = Int(alpha)
        if value <= floor { return 0 }
        if value >= ceiling { return 255 }
        return UInt8((value - floor) * 255 / (ceiling - floor))
    }

    /// `knockoutAlpha` for every alpha, as the lookup `AlphaPlane.blackImage` takes.
    nonisolated private static let knockoutTable: [UInt8] = (0...255).map { knockoutAlpha(UInt8($0)) }
}
