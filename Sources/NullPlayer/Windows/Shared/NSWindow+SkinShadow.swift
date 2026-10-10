import AppKit
import ObjectiveC
import QuartzCore

/// **The drop shadow of every skin window whose engine keeps no outline of its own** — Classic,
/// Original, and the windows every family shares (playlist, EQ, library, the visualizers, video).
/// `.wal`, `.wmz` and an Audion face feed `SkinWindowShadow` the outline their engine already has —
/// a face's rendered layer reads as a box under its baked-in shadow, its canvas does not. These take
/// it from what their content view draws. So every skin window casts one shadow, under one
/// "Window Shadows" switch, and a new family's windows join by setting `hasSkinShadow`.
extension NSWindow {
    /// Use in place of `hasShadow` on a skin window: true casts `SkinWindowShadow` from the content
    /// view's rendered alpha, and turns AppKit's own off; false casts none and leaves `hasShadow` to
    /// the owner (Compact Mode borrows a library window and keeps AppKit's, which fades with it).
    /// Only the window's owner sets it; docking hides the shadow without touching it.
    var hasSkinShadow: Bool {
        get { contentShadow?.shadow.isAttached ?? false }
        set {
            guard newValue != hasSkinShadow else { return }
            if newValue {
                hasShadow = false
                let shadow = contentShadow ?? ContentWindowShadow(window: self)
                contentShadow = shadow
                shadow.attach()
            } else {
                contentShadow?.shadow.detach()
            }
        }
    }

    /// The content's outline moved without the window resizing; pull it again.
    func invalidateSkinShadowShape(_ trigger: String) {
        contentShadow?.shadow.invalidateShape(trigger)
    }

    /// **An Original window's drop shadow, given what it is docked to.** A seamless-docking skin
    /// casts one shadow per docked group, so the stack reads as one piece: each window's own would
    /// fall along every seam, across its neighbour. One member casts the union of every member's
    /// outline — the main window when it is in the group, else the lowest window number, so every
    /// member picks the same one — and the rest hide theirs. `cornersChanged` pulls the outline
    /// again: docking squares or rounds a corner without resizing the window.
    /// Any view in the window may call it, since docking is the window's; a window that casts no
    /// skin shadow (a `.wal` hosted window, Compact Mode) ignores it.
    func applyDockingShadow(isDocked: Bool, cornersChanged: Bool) {
        guard let content = contentShadow, content.shadow.isAttached else { return }
        let manager = WindowManager.shared
        // Mid group drag the members move as one, so the group and its shape stand until the drop.
        if !manager.isInGroupDrag(self) {
            let seamless = isDocked && (ModernSkinEngine.shared.currentSkin?.config.window.seamlessDocking ?? 0) > 0
            let members = seamless ? [self] + manager.findDockedWindows(to: self) : [self]
            // ponytail: a group whose caster never calls this (Stats, Sonos) without the main window
            // stays shadowless, as every seamless stack was before; mark participants if that matters.
            let caster = members.first { $0 === manager.mainWindowController?.window }
                ?? members.min { $0.windowNumber < $1.windowNumber } ?? self
            content.cast(for: caster === self ? members : nil)
        }
        if cornersChanged {
            // A hidden member's corners are part of its caster's outline.
            let caster = content.shadow.isSuppressed
                ? NSApp.windows.first { $0.contentShadow?.casts(for: self) == true } : self
            caster?.contentShadow?.shadow.invalidateShape("corners")
        }
    }

    private static var contentShadowKey: UInt8 = 0

    private var contentShadow: ContentWindowShadow? {
        get { objc_getAssociatedObject(self, &Self.contentShadowKey) as? ContentWindowShadow }
        set { objc_setAssociatedObject(self, &Self.contentShadowKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

/// A `SkinWindowShadow` whose outline is the window's content view, rendered.
@MainActor
private final class ContentWindowShadow {
    let shadow = SkinWindowShadow()
    private weak var window: NSWindow?
    private var skinObservers: [NSObjectProtocol] = []

    init(window: NSWindow) {
        self.window = window
        skinObservers = [Notification.Name.classicSkinDidChange, ModernSkinEngine.skinDidChangeNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                // A turn late: the views' own observers of an Original skin change, which mark the
                // new skin for drawing, may run after this one.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.shadow.invalidateShape("skin") } }
            }
        }
    }

    deinit {
        skinObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// A docked window this one casts the group shadow for, at its frame relative to this one's origin.
    private struct Member: Equatable {
        weak var window: NSWindow?
        let frame: CGRect

        static func == (lhs: Member, rhs: Member) -> Bool { lhs.window === rhs.window && lhs.frame == rhs.frame }
    }

    /// Every window the shadow outlines, this one included; empty for this window's outline alone.
    private var group: [Member] = []

    func attach() {
        guard let window else { return }
        shadow.attach(to: window) { [weak self, weak window] in
            guard let self, let window else { return [] }
            return (self.group.isEmpty ? Self.outline(of: window) : self.groupOutline()).map { [$0] } ?? []
        }
    }

    /// Cast the shadow of the docked `members`, this window among them, or none while another
    /// member casts it. A new group or a member moved within it pulls the outline again.
    func cast(for members: [NSWindow]?) {
        guard let window else { return }
        // Hidden before the shape changes and shown after, so no pull outlines the wrong group.
        if members == nil { shadow.isSuppressed = true }
        let origin = window.frame.origin
        let next = members.flatMap { $0.count > 1 ? $0 : nil }?
            .map { Member(window: $0, frame: $0.frame.offsetBy(dx: -origin.x, dy: -origin.y)) } ?? []
        if next != group {
            group = next
            shadow.outlineBounds = next.map(\.frame).reduce(nil) { $0?.union($1) ?? $1 }
            shadow.invalidateShape("group")
        }
        shadow.isSuppressed = members == nil
    }

    func casts(for window: NSWindow) -> Bool {
        group.contains { $0.window === window }
    }

    /// Every member's outline at its place in the group. The knockout clears the whole union, so
    /// the order members overlap in on screen does not matter.
    private func groupOutline() -> CGImage? {
        guard let bounds = shadow.outlineBounds,
              let context = CGContext(data: nil, width: max(1, Int(bounds.width.rounded())),
                                      height: max(1, Int(bounds.height.rounded())), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        for member in group {
            guard let window = member.window, let outline = Self.outline(of: window) else { continue }
            context.draw(outline, in: member.frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY))
        }
        return context.makeImage()
    }

    /// The content view's layer tree drawn at one pixel per point: the alpha is all the shadow reads.
    /// Pending drawing lands first, so every pull — a resize, a new skin, a face's frame — reads the
    /// content at its current size and state, never the last frame shown. An opaque window's outline
    /// is its frame, whatever it shows — a video layer renders nothing.
    private static func outline(of window: NSWindow) -> CGImage? {
        guard let view = window.contentView, let layer = view.layer else { return nil }
        let width = max(1, Int(view.bounds.width.rounded())), height = max(1, Int(view.bounds.height.rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        if window.isOpaque {
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
        window.displayIfNeeded()
        context.scaleBy(x: CGFloat(width) / max(1, layer.bounds.width), y: CGFloat(height) / max(1, layer.bounds.height))
        layer.render(in: context)
        fillGPULayers(under: layer, root: layer, in: context)
        return context.makeImage()
    }

    /// `render(in:)` draws nothing for a layer the GPU fills — the Metal visualizers, projectM's GL —
    /// so each one that shows is filled solid, or a visualizer reaching its window's edge would cast
    /// no shadow there. A Metal layer made translucent (a transparent-background mode) is left out:
    /// it means the desktop to show through. A GL layer has no such switch; `isOpaque` stays false
    /// on one that draws opaque frames. `convert` places it as `render(in:)` does, flips included.
    private static func fillGPULayers(under layer: CALayer, root: CALayer, in context: CGContext) {
        for sublayer in layer.sublayers ?? [] where !sublayer.isHidden && sublayer.opacity > 0 {
            if let metal = sublayer as? CAMetalLayer {
                if metal.isOpaque { context.fill(root.convert(metal.bounds, from: metal)) }
            } else if sublayer is CAOpenGLLayer {
                context.fill(root.convert(sublayer.bounds, from: sublayer))
            } else {
                fillGPULayers(under: sublayer, root: root, in: context)
            }
        }
    }
}
