import AppKit

/// Geiss's own items in the shared visualization menu (`VisualizationContextMenu`), below the
/// presets and cycle every engine shares: toggles, sensitivity/gamma/waveform submenus, and
/// randomize palette. Mode Lock and Auto-Switch are not here: Geiss's mode is always locked and
/// the shared preset cycler changes it. The items target the engine, so a host needs no
/// Geiss-specific actions.
extension GeissEngine {
    func addMenuItems(to menu: NSMenu) {
        let config = self.config
        for (title, action, on) in [
            ("Beat Detection", #selector(toggleBeatDetectionAction), config.beatDetection),
            ("Sync Color to Sound", #selector(toggleSyncColorAction), config.syncColorToSound),
            ("Slide Shift", #selector(toggleSlideShiftAction), config.slideShift),
            ("Palette Lock", #selector(togglePaletteLockAction), config.paletteLocked)
        ] {
            let toggle = item(title, action)
            toggle.state = on ? .on : .off
            menu.addItem(toggle)
        }
        // Tags encode each choice: sensitivity × 100, Geiss's gamma value, the waveform mode.
        menu.addItem(submenu("Geiss Sensitivity", #selector(setSensitivityAction),
                             [0.25, 0.5, 1.0, 2.0, 3.0, 4.0].map { (String(format: "%.2f×", $0), Int($0 * 100)) },
                             selected: Int((config.sensitivity * 100).rounded())))
        // Geiss's gamma factor is 1 + gamma / 100; 10 (1.10×) is its default.
        menu.addItem(submenu("Gamma", #selector(setGammaAction),
                             [0, 10, 25, 50, 100, 150, 200].map { (String(format: "%.2f×", 1 + Double($0) / 100), $0) },
                             selected: config.gamma))
        menu.addItem(submenu("Waveform Mode", #selector(setVisModeAction),
                             [("Wave", 0), ("Spectrum", 1)], selected: config.visMode))
        menu.addItem(item("Randomize Palette", #selector(randomizePaletteAction)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ action: Selector, _ choices: [(String, Int)], selected: Int) -> NSMenuItem {
        let submenu = NSMenu()
        for (choiceTitle, tag) in choices {
            let choice = item(choiceTitle, action)
            choice.tag = tag
            choice.state = tag == selected ? .on : .off
            submenu.addItem(choice)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    @objc private func toggleBeatDetectionAction() { editConfig { $0.beatDetection.toggle() } }
    @objc private func toggleSyncColorAction() { editConfig { $0.syncColorToSound.toggle() } }
    @objc private func toggleSlideShiftAction() { editConfig { $0.slideShift.toggle() } }
    @objc private func togglePaletteLockAction() { editConfig { $0.paletteLocked.toggle() } }
    @objc private func setSensitivityAction(_ sender: NSMenuItem) { editConfig { $0.sensitivity = Float(sender.tag) / 100 } }
    @objc private func setGammaAction(_ sender: NSMenuItem) { editConfig { $0.gamma = sender.tag } }
    @objc private func setVisModeAction(_ sender: NSMenuItem) { editConfig { $0.visMode = sender.tag } }
    @objc private func randomizePaletteAction() { randomizePalette() }

    private func editConfig(_ edit: (inout Config) -> Void) {
        var config = self.config
        edit(&config)
        setConfig(config)
        Self.saveConfig(config)
    }
}

// MARK: - Persistence

extension GeissEngine {
    /// The saved configuration, applied to every new engine. `modeLocked` is always on: the preset
    /// cycler, not Geiss's own auto-switch, changes its mode. `VisualizationPreferences`' reset
    /// clears these keys.
    static var savedConfig: Config {
        let defaults = UserDefaults.standard
        func number(_ key: String) -> NSNumber? { defaults.object(forKey: "geiss.\(key)") as? NSNumber }
        return Config(
            sensitivity: number("sensitivity")?.floatValue ?? 0.20,
            gamma: number("gamma")?.intValue ?? 10,
            beatDetection: number("beatDetection")?.boolValue ?? true,
            syncColorToSound: number("syncColorToSound")?.boolValue ?? false,
            slideShift: number("slideShift")?.boolValue ?? true,
            modeLocked: true,
            paletteLocked: number("paletteLocked")?.boolValue ?? false,
            autoSwitchSeconds: number("autoSwitchSeconds")?.intValue ?? 15,
            visMode: number("visMode")?.intValue ?? 0
        )
    }

    private static func saveConfig(_ config: Config) {
        let defaults = UserDefaults.standard
        defaults.set(config.sensitivity, forKey: "geiss.sensitivity")
        defaults.set(config.gamma, forKey: "geiss.gamma")
        defaults.set(config.beatDetection, forKey: "geiss.beatDetection")
        defaults.set(config.syncColorToSound, forKey: "geiss.syncColorToSound")
        defaults.set(config.slideShift, forKey: "geiss.slideShift")
        defaults.set(config.paletteLocked, forKey: "geiss.paletteLocked")
        defaults.set(config.autoSwitchSeconds, forKey: "geiss.autoSwitchSeconds")
        defaults.set(config.visMode, forKey: "geiss.visMode")
    }
}
