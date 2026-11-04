import AppKit

/// A skin's companion windows (speakers, amplifier, equalizer, its own playlist and library) by
/// form name, each drawn by its own view from the skin's one runtime: made with the skin and gone
/// with it, shown while the skin's state has them visible and not docked, opened beside the deck
/// once and then where the user leaves them, and sized to what their form draws.
@MainActor
final class AIMPSkinCompanionWindows {
    private var windows: [String: (window: SkinnedBorderlessWindow, view: AIMPSkinMainView)] = [:]
    /// Companions placed beside the deck once; after that the user's place stands.
    private var placed: Set<String> = []
    /// The deck's window delegate, which receives the companions' window events too.
    private weak var delegate: NSWindowDelegate?

    init(delegate: NSWindowDelegate) {
        self.delegate = delegate
    }

    var all: [NSWindow] { windows.values.map(\.window) }

    /// Closes the outgoing skin's windows and makes `skin`'s (none for nil), drawing from `runtime`
    /// like `main`, whose menus they share. `changed` runs when what one draws changes.
    func rebuild(_ skin: AIMPSkin?, runtime: AIMPSkinRuntime?, like main: AIMPSkinMainView, changed: @escaping () -> Void) {
        for companion in windows.values {
            companion.window.orderOut(nil)
            companion.window.delegate = nil
            companion.view.runtime = nil
        }
        windows = [:]
        placed = []
        for companion in skin?.companions ?? [] where companion.opensWindow {
            let view = AIMPSkinMainView()
            view.formName = companion.name
            view.runtime = runtime
            view.uiScale = main.uiScale
            view.extraMenuItems = main.extraMenuItems
            // Teac Audio System's PRESETS key is on its equalizer window.
            view.popupMenu = main.popupMenu
            // A window of its own, not a child of the deck's: `WindowManager` docks, snaps,
            // minimizes and orders it beside the deck (`managedAuxiliaryWindows`), and its pass over
            // the deck's child windows would otherwise detach it (`updateDockedChildWindows`).
            let window = SkinnedBorderlessWindow(contentRect: NSRect(origin: .zero, size: view.displaySize),
                                                 styleMask: [.borderless, .miniaturizable], backing: .buffered, defer: true)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.title = companion.title
            window.delegate = delegate
            window.contentView = view
            view.onDisplaySizeChange = { [weak window, weak view] in
                guard let window, let view else { return }
                Self.fit(window, to: view)
            }
            view.onContentChange = changed
            windows[companion.name] = (window, view)
        }
    }

    /// Shows the companions `flow` has visible and hides the rest, while the deck (`main`) shows.
    /// Units that draw nothing on their own (Denon's, already part of its main form) never show.
    func update(_ flow: AIMPSkinDataflow, beside main: NSWindow) {
        for (name, companion) in windows {
            // A docked form shows in its site instead (`AIMPSkinDockSites`).
            let wanted = main.isVisible && flow.isVisible(name) && !flow.isDocked(name) && companion.view.hasContent
            guard wanted != companion.window.isVisible else { continue }
            guard wanted else {
                companion.window.orderOut(nil)
                continue
            }
            // Off screen it was not drawn (`AIMPSkinRuntime.tick`): it shows a frame of now.
            companion.view.renderNow()
            Self.fit(companion.window, to: companion.view)
            if !placed.contains(name), let form = flow.skin.companions.first(where: { $0.name == name }) {
                placed.insert(name)
                place(companion.window, as: form, beside: main, scale: companion.view.uiScale)
            }
            if companion.window.isMiniaturized { companion.window.deminiaturize(nil) } else { companion.window.orderFront(nil) }
        }
    }

    /// The UI scale changed: every companion draws and fits at it.
    func apply(scale: CGFloat) {
        for companion in windows.values {
            companion.view.uiScale = scale
            Self.fit(companion.window, to: companion.view)
        }
    }

    /// Sizes `window` to what `view` shows at its scale, holding its top-left corner: the deck's and
    /// every companion's fit.
    static func fit(_ window: NSWindow, to view: AIMPSkinMainView) {
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(NSSize(width: view.displaySize.width * view.uiScale, height: view.displaySize.height * view.uiScale))
        window.setFrameTopLeftPoint(topLeft)
        window.invalidateSkinShadowShape("fit")
    }

    /// Opens the companion's window beside the deck (`AIMPSkin.Companion.origin`), kept on the
    /// deck's screen: beside a deck that fills it, it would open off it (Red Bias 2.0's skin settings
    /// under its 1,030-px window).
    private func place(_ window: NSWindow, as companion: AIMPSkin.Companion, beside main: NSWindow, scale: CGFloat) {
        var frame = window.frame
        frame.origin = companion.origin(size: frame.size, beside: main.frame, scale: scale)
        if let screen = (main.screen ?? NSScreen.main)?.visibleFrame { frame = WindowPlacement.rescued(frame, into: screen) }
        window.setFrameOrigin(frame.origin)
    }

    /// Moves the shown companions hanging under `old`'s bottom edge, and any hanging under those, by
    /// the change in that edge (GX-F90's AMP key grows the deck over the playlist under it).
    func followBottomEdge(of old: NSRect, to new: NSRect) {
        let shift = new.minY - old.minY
        guard shift != 0 else { return }
        var edges = [old]
        var moved = Set<ObjectIdentifier>()
        while let edge = edges.popLast() {
            for companion in windows.values where companion.window.isVisible && !moved.contains(ObjectIdentifier(companion.window)) {
                let frame = companion.window.frame
                guard abs(frame.maxY - edge.minY) <= 2, frame.maxX > edge.minX, frame.minX < edge.maxX else { continue }
                moved.insert(ObjectIdentifier(companion.window))
                edges.append(frame)
                companion.window.setFrameOrigin(NSPoint(x: frame.minX, y: frame.minY + shift))
            }
        }
    }

    /// The companion windows that draw anything, checked while shown, for the context menu (AIMP
    /// lists them in its own); choosing one shows or hides it through `toggle`.
    func menuItems(_ flow: AIMPSkinDataflow, toggle: @escaping (String, Bool) -> Void) -> [NSMenuItem] {
        flow.skin.companions.compactMap { companion in
            guard let shown = windows[companion.name], shown.view.hasContent else { return nil }
            let visible = flow.isVisible(companion.name)
            let item = AIMPSkinMenuItem(title: companion.title) { toggle(companion.name, !visible) }
            item.state = visible ? .on : .off
            return item
        }
    }
}
