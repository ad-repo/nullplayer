import AppKit

/// Shared menu builder for Geiss-specific configuration UI.
/// Used by both classic ProjectMView and modern ModernProjectMView to avoid duplication.
final class GeissMenuBuilder {

    /// Add Geiss configuration menu items to a context menu.
    /// Appends after the Effects submenu: toggles, sensitivity/gamma/auto-switch submenus, and randomize action.
    static func addGeissConfigMenuItems(to menu: NSMenu, target: AnyObject, visualizationView: VisualizationGLView) {
        menu.addItem(NSMenuItem.separator())

        // Toggles: Beat Detection, Sync Color to Sound, Slide Shift, Mode Lock, Palette Lock
        let currentConfig = visualizationView.getGeissConfig()

        let beatDetectionItem = NSMenuItem(
            title: "Beat Detection",
            action: #selector(GeissMenuTarget.toggleBeatDetection(_:)),
            keyEquivalent: ""
        )
        beatDetectionItem.target = target
        beatDetectionItem.state = (currentConfig?.beatDetection ?? true) ? .on : .off
        menu.addItem(beatDetectionItem)

        let syncColorItem = NSMenuItem(
            title: "Sync Color to Sound",
            action: #selector(GeissMenuTarget.toggleSyncColorToSound(_:)),
            keyEquivalent: ""
        )
        syncColorItem.target = target
        syncColorItem.state = (currentConfig?.syncColorToSound ?? false) ? .on : .off
        menu.addItem(syncColorItem)

        let slideShiftItem = NSMenuItem(
            title: "Slide Shift",
            action: #selector(GeissMenuTarget.toggleSlideShift(_:)),
            keyEquivalent: ""
        )
        slideShiftItem.target = target
        slideShiftItem.state = (currentConfig?.slideShift ?? true) ? .on : .off
        menu.addItem(slideShiftItem)

        let modeLockItem = NSMenuItem(
            title: "Mode Lock",
            action: #selector(GeissMenuTarget.toggleModeLock(_:)),
            keyEquivalent: ""
        )
        modeLockItem.target = target
        modeLockItem.state = (currentConfig?.modeLocked ?? false) ? .on : .off
        menu.addItem(modeLockItem)

        let paletteLockItem = NSMenuItem(
            title: "Palette Lock",
            action: #selector(GeissMenuTarget.togglePaletteLock(_:)),
            keyEquivalent: ""
        )
        paletteLockItem.target = target
        paletteLockItem.state = (currentConfig?.paletteLocked ?? false) ? .on : .off
        menu.addItem(paletteLockItem)

        // Submenu: Geiss Sensitivity
        let sensitivityValues: [Float] = [0.25, 0.5, 1.0, 2.0, 3.0, 4.0]
        let sensitivityMenu = NSMenu()
        let currentSensitivity = currentConfig?.sensitivity ?? 0.20
        for val in sensitivityValues {
            let item = NSMenuItem(
                title: String(format: "%.2f×", val),
                action: #selector(GeissMenuTarget.setSensitivity(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = Int(val * 100)  // Encode as int for tag
            item.state = abs(currentSensitivity - val) < 0.01 ? .on : .off
            sensitivityMenu.addItem(item)
        }
        let sensitivityMenuItem = NSMenuItem(title: "Geiss Sensitivity", action: nil, keyEquivalent: "")
        sensitivityMenuItem.submenu = sensitivityMenu
        menu.addItem(sensitivityMenuItem)

        // Submenu: Gamma
        let gammaValues = [0, 25, 50, 100, 150, 200]
        let gammaFactors = ["1.00×", "1.25×", "1.50×", "2.00×", "2.50×", "3.00×"]
        let gammaMenu = NSMenu()
        let currentGamma = currentConfig?.gamma ?? 10
        for (i, val) in gammaValues.enumerated() {
            let item = NSMenuItem(
                title: gammaFactors[i],
                action: #selector(GeissMenuTarget.setGamma(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = val
            item.state = (currentGamma == val) ? .on : .off
            gammaMenu.addItem(item)
        }
        let gammaMenuItem = NSMenuItem(title: "Gamma", action: nil, keyEquivalent: "")
        gammaMenuItem.submenu = gammaMenu
        menu.addItem(gammaMenuItem)

        // Submenu: Auto-Switch
        let autoSwitchValues = [5, 15, 30, 60, 120]
        let autoSwitchMenu = NSMenu()
        let currentAutoSwitch = currentConfig?.autoSwitchSeconds ?? 550
        for val in autoSwitchValues {
            let item = NSMenuItem(
                title: String(format: "%ds", val),
                action: #selector(GeissMenuTarget.setAutoSwitch(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = val
            item.state = (currentAutoSwitch == val) ? .on : .off
            autoSwitchMenu.addItem(item)
        }
        let autoSwitchMenuItem = NSMenuItem(title: "Auto-Switch", action: nil, keyEquivalent: "")
        autoSwitchMenuItem.submenu = autoSwitchMenu
        menu.addItem(autoSwitchMenuItem)

        // Submenu: visMode
        let visModeTitles = ["Wave", "Spectrum"]
        let visModeMenu = NSMenu()
        let currentVisMode = currentConfig?.visMode ?? 0
        for (i, title) in visModeTitles.enumerated() {
            let item = NSMenuItem(
                title: title,
                action: #selector(GeissMenuTarget.setVisMode(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = i
            item.state = (currentVisMode == i) ? .on : .off
            visModeMenu.addItem(item)
        }
        let visModeMenuItem = NSMenuItem(title: "Waveform Mode", action: nil, keyEquivalent: "")
        visModeMenuItem.submenu = visModeMenu
        menu.addItem(visModeMenuItem)

        // Action: Randomize Palette
        let randomizePaletteItem = NSMenuItem(
            title: "Randomize Palette",
            action: #selector(GeissMenuTarget.randomizePalette(_:)),
            keyEquivalent: ""
        )
        randomizePaletteItem.target = target
        menu.addItem(randomizePaletteItem)
    }
}

/// Helper protocol that views implementing Geiss menu handlers should conform to.
@objc(GeissMenuTarget) protocol GeissMenuTarget: AnyObject {
    var visualizationGLView: VisualizationGLView? { get }

    func toggleBeatDetection(_ sender: NSMenuItem)
    func toggleSyncColorToSound(_ sender: NSMenuItem)
    func toggleSlideShift(_ sender: NSMenuItem)
    func toggleModeLock(_ sender: NSMenuItem)
    func togglePaletteLock(_ sender: NSMenuItem)
    func setSensitivity(_ sender: NSMenuItem)
    func setGamma(_ sender: NSMenuItem)
    func setAutoSwitch(_ sender: NSMenuItem)
    func setVisMode(_ sender: NSMenuItem)
    func randomizePalette(_ sender: NSMenuItem)
}
