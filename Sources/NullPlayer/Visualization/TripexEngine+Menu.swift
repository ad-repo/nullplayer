import AppKit

/// Tripex's own items in the shared visualization menu (`VisualizationContextMenu`), below the
/// presets and cycle every engine shares. Tripex effects own most parameters internally, so this
/// surfaces the meaningful engine-level levers instead of fake per-effect controls. The items
/// target the engine, so a host needs no Tripex-specific actions.
extension TripexEngine {
    func addMenuItems(to menu: NSMenu) {
        menu.addItem(item("Randomize Effect Settings", #selector(reconfigureAction)))

        let intensityMenu = NSMenu()
        let currentIntensity = intensityScale
        for value: Float in [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0] {
            let choice = item("\(value)x", #selector(setIntensityAction))
            choice.tag = Int((value * 100).rounded())
            choice.state = abs(currentIntensity - value) < 0.01 ? .on : .off
            intensityMenu.addItem(choice)
        }
        let intensityItem = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
        intensityItem.submenu = intensityMenu
        menu.addItem(intensityItem)

        menu.addItem(item("Show Audio Info", #selector(toggleAudioInfoAction)))
        menu.addItem(item("Show Help Overlay", #selector(toggleHelpAction)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func reconfigureAction() { reconfigure() }
    @objc private func toggleAudioInfoAction() { toggleAudioInfo() }
    @objc private func toggleHelpAction() { toggleHelp() }

    @objc private func setIntensityAction(_ sender: NSMenuItem) {
        let value = Float(sender.tag) / 100
        intensityScale = value
        UserDefaults.standard.set(value, forKey: DefaultsKey.intensityScale)
    }
}
