import Accelerate
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
    /// parent's `windowDidMove` in the same turn (measured: one `reassert frame` per drag step
    /// while the skin is above the screen top, none below it).
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

    static let isTraceEnabled = ProcessInfo.processInfo.environment["NP_SKIN_SHADOW_TRACE"] == "1"

    let shadowWindow = SkinShadowWindow()
    private weak var parent: NSWindow?
    private var name = "?"
    /// The shape last handed over, kept so enabling the preference can build without waiting for
    /// the skin to repaint.
    private var lastLayers: [CGImage] = []
    private var lastFingerprint: Int?
    private var observers: [NSObjectProtocol] = []
    private var levelObservation: NSKeyValueObservation?

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: Self.enabledDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPreference() }
            })
        // Always on Top writes this key and then re-levels every managed window; the shadow is not
        // one of them, so it re-copies its parent's level a turn later.
        levelObservation = UserDefaults.standard.observe(\.isAlwaysOnTop, options: []) {
            [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.reassert() } }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        levelObservation?.invalidate()
        let window = shadowWindow
        DispatchQueue.main.async {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
    }

    // MARK: Attachment

    var isAttached: Bool { parent != nil }

    /// Bind to `parent` for its lifetime on screen. `name` is only for the trace.
    func attach(to parent: NSWindow, name: String) {
        self.name = name
        if self.parent !== parent {
            detach()
            self.parent = parent
        }
        guard Self.isEnabledPreference else { return }
        updateFrame(parentFrame: parent.frame, trigger: "attach")
        if !lastLayers.isEmpty, lastFingerprint == nil {
            update(layers: lastLayers, parentFrame: parent.frame, trigger: "attach")
        }
    }

    func detach() {
        shadowWindow.parent?.removeChildWindow(shadowWindow)
        shadowWindow.orderOut(nil)
        parent = nil
    }

    /// Put the link, the order and the level back if anything has moved them. A pointer compare on
    /// the common path; the shadow has no timer, so these calls are the only thing that repairs it.
    func reassert() {
        guard let parent, Self.isEnabledPreference else { return }
        guard parent.isVisible else { return }
        if shadowWindow.parent !== parent {
            shadowWindow.parent?.removeChildWindow(shadowWindow)
            parent.addChildWindow(shadowWindow, ordered: .below)
            trace("reassert parent")
        } else if !shadowWindow.isVisible || shadowWindow.orderedIndex < parent.orderedIndex {
            // Order counts from the front, so a smaller index is in front of the parent.
            shadowWindow.order(.below, relativeTo: parent.windowNumber)
            trace("reassert order")
        }
        if shadowWindow.level != parent.level {
            shadowWindow.level = parent.level
            trace("reassert level")
        }
        let frame = parent.frame.insetBy(dx: -Self.pad, dy: -Self.pad)
        if shadowWindow.frame != frame {
            shadowWindow.setFrame(frame, display: false)
            trace("reassert frame")
        }
    }

    private func applyPreference() {
        guard let parent else { return }
        if Self.isEnabledPreference {
            lastFingerprint = nil
            attach(to: parent, name: name)
        } else {
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
    private var isBuilding = false
    /// The newest shape not yet looked at. Only the latest matters, so a request that arrives
    /// while one is in flight replaces any other that is waiting.
    private var pendingRequest: ShapeRequest?

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

    /// The window's shape may have changed: `layers` are drawn over each other at the window's
    /// size, and their combined alpha is the outline. Re-frames at once; the alpha is compared off
    /// the main thread, and the shadow is rebuilt only when it moved.
    func update(layers: [CGImage], parentFrame: NSRect, trigger: String) {
        lastLayers = layers
        guard parent != nil, Self.isEnabledPreference, !layers.isEmpty else { return }
        updateFrame(parentFrame: parentFrame, trigger: trigger)
        pendingRequest = ShapeRequest(layers: layers,
                                      width: max(1, Int(parentFrame.width.rounded())),
                                      height: max(1, Int(parentFrame.height.rounded())),
                                      trigger: trigger)
        startNextBuild()
    }

    private func startNextBuild() {
        guard !isBuilding, let request = pendingRequest else { return }
        pendingRequest = nil
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
        defer { startNextBuild() }
        guard parent != nil, Self.isEnabledPreference else { return }
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
        guard let plane = alphaPlane(of: request.layers, width: request.width,
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

    /// Fit the shadow around `parentFrame`. The layer stretches what it last built until the next
    /// shape update, so a live resize costs nothing but this.
    func updateFrame(parentFrame: NSRect, trigger: String = "frame") {
        guard parent != nil, Self.isEnabledPreference else { return }
        let frame = parentFrame.insetBy(dx: -Self.pad, dy: -Self.pad)
        if shadowWindow.frame != frame {
            shadowWindow.setFrame(frame, display: false)
            trace("reframe \(Int(parentFrame.width))x\(Int(parentFrame.height)) trigger=\(trigger)")
        }
        reassert()
    }

    private func trace(_ message: String) {
        guard Self.isTraceEnabled else { return }
        NSLog("[shadow] %@ %@", name, message)
    }

    // MARK: Pure image work

    struct AlphaPlane {
        let width: Int
        let height: Int
        /// One byte per pixel, top row first, `width` bytes a row.
        let bytes: [UInt8]
    }

    /// The combined alpha of `layers`, each drawn to fill `width` x `height`.
    nonisolated static func alphaPlane(of layers: [CGImage], width: Int, height: Int) -> AlphaPlane? {
        guard width > 0, height > 0, !layers.isEmpty,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return nil }
        context.interpolationQuality = .medium
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        for layer in layers { context.draw(layer, in: bounds) }
        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height)
        var bytes = [UInt8](repeating: 0, count: width * height)
        // Bitmap memory is top row first; `bytesPerRow` may be padded.
        for row in 0..<height {
            let source = pointer + row * context.bytesPerRow
            bytes.withUnsafeMutableBufferPointer {
                ($0.baseAddress! + row * width).update(from: source, count: width)
            }
        }
        return AlphaPlane(width: width, height: height, bytes: bytes)
    }

    /// The shadow for `alpha`'s shape, `pad` larger on every side.
    nonisolated static func makeShadowImage(alpha: CGImage, blur: CGFloat, offset: CGSize,
                                            opacity: CGFloat, pad: CGFloat) -> CGImage? {
        guard let plane = alphaPlane(of: [alpha], width: alpha.width, height: alpha.height)
        else { return nil }
        return makeShadowImage(plane: plane, blur: blur, offset: offset, opacity: opacity, pad: pad)
    }

    /// The shape is drawn with a shadow, then cut back out with a **binarized** copy of itself:
    /// a plain `.destinationOut` leaves shadow x (1 - alpha) under translucent art, which would
    /// still darken it from behind. macOS clears its shadow under the whole window shape, and this
    /// matches that — so the only pixels left are the shadow outside the outline.
    nonisolated static func makeShadowImage(plane: AlphaPlane, blur: CGFloat, offset: CGSize,
                                            opacity: CGFloat, pad: CGFloat) -> CGImage? {
        let padding = Int(pad.rounded(.up))
        let width = plane.width + padding * 2
        let height = plane.height + padding * 2
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let shape = rgbaMask(plane, binarized: false),
              let knockout = rgbaMask(plane, binarized: true),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: info)
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

    /// Black at `plane`'s alpha (or at `knockoutAlpha` of it). vImage rather than a
    /// loop: a debug build spent ~20 ms a pass interleaving a 596x468 plane by hand.
    nonisolated private static func rgbaMask(_ plane: AlphaPlane, binarized: Bool) -> CGImage? {
        let count = plane.width * plane.height
        var alpha = plane.bytes
        var zero = [UInt8](repeating: 0, count: count)
        var pixels = [UInt8](repeating: 0, count: count * 4)
        let width = vImagePixelCount(plane.width), height = vImagePixelCount(plane.height)
        let error: vImage_Error = alpha.withUnsafeMutableBytes { alphaBytes in
            zero.withUnsafeMutableBytes { zeroBytes in
                pixels.withUnsafeMutableBytes { pixelBytes in
                    var alphaBuffer = vImage_Buffer(data: alphaBytes.baseAddress, height: height,
                                                    width: width, rowBytes: plane.width)
                    var zeroBuffer = vImage_Buffer(data: zeroBytes.baseAddress, height: height,
                                                   width: width, rowBytes: plane.width)
                    var destination = vImage_Buffer(data: pixelBytes.baseAddress, height: height,
                                                    width: width, rowBytes: plane.width * 4)
                    if binarized {
                        let table = [UInt8](unsafeUninitializedCapacity: 256) { buffer, initialized in
                            for index in 0..<256 { buffer[index] = knockoutAlpha(UInt8(index)) }
                            initialized = 256
                        }
                        let result = vImageTableLookUp_Planar8(&alphaBuffer, &alphaBuffer, table,
                                                               vImage_Flags(kvImageNoFlags))
                        guard result == kvImageNoError else { return result }
                    }
                    // The four planes go in in memory order, so this is R, G, B, A: premultiplied
                    // black is (0, 0, 0, a).
                    return vImageConvert_Planar8toARGB8888(&zeroBuffer, &zeroBuffer, &zeroBuffer,
                                                           &alphaBuffer, &destination,
                                                           vImage_Flags(kvImageNoFlags))
                }
            }
        }
        guard error == kvImageNoError,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: plane.width, height: plane.height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: plane.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}

private extension UserDefaults {
    /// `WindowManager.isAlwaysOnTop`'s key, exposed for key-value observation — `UserDefaults`
    /// posts KVO under the key's own name, so the property has to carry exactly that name.
    @objc dynamic var isAlwaysOnTop: Bool { bool(forKey: "isAlwaysOnTop") }
}
