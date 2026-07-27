import AppKit

/// Mode-neutral runtime for Cava spectrum analyzer: owns the render model and builds/handles the
/// right-click menu. Contains no skin-specific code so both UI modes can reuse it. It is the menu
/// target itself (an NSObject with @objc actions); the view only supplies `onNeedsDisplay`/`onClose`.
final class CavaPresenter: NSObject {
    private let scope: CavaSettings.Scope
    private let renderModel: CavaRenderModel

    /// Invoked on the main thread whenever the view should repaint (content-rect only).
    var onNeedsDisplay: (() -> Void)?
    /// Invoked when the whole window (chrome + background) must repaint, e.g. a transparency change.
    var onNeedsFullDisplay: (() -> Void)?
    /// Invoked when the user chooses Close (the view closes its window).
    var onClose: (() -> Void)?

    init(scope: CavaSettings.Scope = .cavaWindow) {
        self.scope = scope
        self.renderModel = CavaRenderModel(scope: scope)
        super.init()
        renderModel.onNeedsDisplay = { [weak self] in
            self?.onNeedsDisplay?()
        }
    }

    var barArrays: [[Float]] { renderModel.barArrays }
    var mode: CavaSettings.Mode { renderModel.mode }
    var barCount: Int { renderModel.barCount }
    var lowGradientColor: NSColor { CavaSettings.effectiveLowColor(for: scope) }
    var highGradientColor: NSColor { CavaSettings.effectiveHighColor(for: scope) }

    // MARK: Lifecycle

    func start() { renderModel.start() }
    func stop() { renderModel.stop() }
    func settingsDidChange() { renderModel.settingsDidChange() }

    // MARK: Settings

    func setMode(_ mode: CavaSettings.Mode) {
        CavaSettings.setMode(mode, for: scope)
        renderModel.settingsDidChange()
    }

    /// Toggle between mono and stereo (used by the window double-click).
    func toggleMode() {
        setMode(mode == .mono ? .stereo : .mono)
    }

    /// Apply one of the named gradient presets by index (marks colors as user-customized).
    func applyColorScheme(_ index: Int) {
        guard CavaSettings.colorSchemes.indices.contains(index) else { return }
        let scheme = CavaSettings.colorSchemes[index]
        CavaSettings.setLowGradientColor(scheme.low, for: scope)
        CavaSettings.setHighGradientColor(scheme.high, for: scope)
        CavaSettings.setHasCustomColors(true, for: scope)
        onNeedsDisplay?()
    }

    /// Revert to the skin-derived default gradient (classic green / modern primary→accent).
    func useSkinDefaultColors() {
        CavaSettings.setHasCustomColors(false, for: scope)
        onNeedsDisplay?()
    }

    func toggleTransparency() {
        guard scope == .cavaWindow else { return }
        CavaSettings.transparentBackground.toggle()
        (onNeedsFullDisplay ?? onNeedsDisplay)?()
    }

    /// Restore the exposed tuning knobs (bars, smoothing, bass tilt) to factory defaults.
    func resetTuning() {
        CavaSettings.resetTuning(scope: scope)
        renderModel.settingsDidChange()
    }

    // MARK: Menu actions

    @objc private func modeAction(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? CavaSettings.Mode else { return }
        setMode(mode)
    }

    @objc private func colorSchemeAction(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        applyColorScheme(index)
    }

    @objc private func matchSkinAction(_ sender: NSMenuItem) { useSkinDefaultColors() }

    @objc private func transparencyAction(_ sender: NSMenuItem) { toggleTransparency() }

    @objc private func barCountAction(_ sender: NSMenuItem) {
        guard let count = sender.representedObject as? Int else { return }
        CavaSettings.setBarCount(count, for: scope)
        renderModel.settingsDidChange()
    }

    @objc private func smoothingAction(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        CavaSettings.setNoiseReduction(value, for: scope)
        renderModel.settingsDidChange()
    }

    @objc private func bassTiltAction(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        CavaSettings.setBassTilt(value, for: scope)
        renderModel.settingsDidChange()
    }

    @objc private func resetAction(_ sender: NSMenuItem) { resetTuning() }

    @objc private func closeAction(_ sender: NSMenuItem) { onClose?() }

    // MARK: Menu building

    /// Build the right-click menu. `showTransparency` gates the modern-only transparency toggle.
    func buildMenu(showTransparency: Bool) -> NSMenu {
        let menu = NSMenu()

        addCheckItem(to: menu, title: "Mono", action: #selector(modeAction(_:)),
                     represented: CavaSettings.Mode.mono, checked: mode == .mono)
        addCheckItem(to: menu, title: "Stereo", action: #selector(modeAction(_:)),
                     represented: CavaSettings.Mode.stereo, checked: mode == .stereo)

        menu.addItem(.separator())

        menu.addItem(colorSubmenuItem())

        if showTransparency && scope == .cavaWindow {
            addCheckItem(to: menu, title: "Transparent Background",
                         action: #selector(transparencyAction(_:)), represented: nil,
                         checked: CavaSettings.transparentBackground)
        }

        menu.addItem(.separator())

        menu.addItem(barsSubmenuItem())
        menu.addItem(valueSubmenuItem(title: "Smoothing", presets: CavaSettings.smoothingPresets,
                                      current: CavaSettings.noiseReduction(for: scope),
                                      action: #selector(smoothingAction(_:))))
        menu.addItem(valueSubmenuItem(title: "Bass", presets: CavaSettings.bassTiltPresets,
                                      current: CavaSettings.bassTilt(for: scope),
                                      action: #selector(bassTiltAction(_:))))

        let resetItem = NSMenuItem(title: "Reset to Defaults", action: #selector(resetAction(_:)), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "Close", action: #selector(closeAction(_:)), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        return menu
    }

    private func addCheckItem(to menu: NSMenu, title: String, action: Selector,
                              represented: Any?, checked: Bool) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    private func colorSubmenuItem() -> NSMenuItem {
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        let usingSkin = !CavaSettings.hasCustomColors(for: scope)

        addCheckItem(to: colorMenu, title: "Match Skin", action: #selector(matchSkinAction(_:)),
                     represented: nil, checked: usingSkin)
        colorMenu.addItem(.separator())

        // A preset shows a checkmark only when it is the active user pick (not in Match Skin mode).
        let selectedScheme = usingSkin ? nil : CavaSettings.currentColorSchemeIndex(for: scope)
        for (i, scheme) in CavaSettings.colorSchemes.enumerated() {
            let item = NSMenuItem(title: scheme.name, action: #selector(colorSchemeAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = i
            item.state = (selectedScheme == i) ? .on : .off
            item.image = Self.swatch(low: scheme.low, high: scheme.high)
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        return colorItem
    }

    private func barsSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Bars", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = CavaSettings.barCount(for: scope)
        for count in CavaSettings.barCountPresets(for: scope) {
            let sub = NSMenuItem(title: "\(count)", action: #selector(barCountAction(_:)), keyEquivalent: "")
            sub.target = self
            sub.representedObject = count
            sub.state = (current == count) ? .on : .off
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    private func valueSubmenuItem(title: String, presets: [(name: String, value: Double)],
                                  current: Double, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (name, value) in presets {
            let sub = NSMenuItem(title: name, action: action, keyEquivalent: "")
            sub.target = self
            sub.representedObject = value
            sub.state = (abs(current - value) < 0.001) ? .on : .off
            submenu.addItem(sub)
        }
        item.submenu = submenu
        return item
    }

    /// A small horizontal low→high gradient swatch shown next to each color preset.
    private static func swatch(low: NSColor, high: NSColor) -> NSImage {
        let size = NSSize(width: 28, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()
        if let gradient = NSGradient(starting: low, ending: high) {
            gradient.draw(in: NSRect(origin: .zero, size: size), angle: 0)
        }
        NSColor.black.withAlphaComponent(0.25).setStroke()
        NSBezierPath(rect: NSRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)).stroke()
        image.unlockFocus()
        return image
    }
}
