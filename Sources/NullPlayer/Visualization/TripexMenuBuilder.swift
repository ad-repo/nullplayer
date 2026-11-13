import AppKit

/// Tripex's own items in the shared visualization menu (`VisualizationContextMenu`), below the
/// presets and cycle every engine shares. Tripex effects own most parameters internally, so this
/// surfaces the meaningful engine-level levers instead of fake per-effect controls.
enum TripexMenuBuilder {

    static func addTripexConfigMenuItems(to menu: NSMenu, target: AnyObject, visualizationView: VisualizationGLView) {
        let reconfigureItem = NSMenuItem(title: "Randomize Effect Settings", action: #selector(TripexMenuTarget.reconfigureTripexAction(_:)), keyEquivalent: "")
        reconfigureItem.target = target
        menu.addItem(reconfigureItem)

        let intensityMenu = NSMenu()
        let currentIntensity = visualizationView.tripexIntensityScale
        for (title, value) in [("0.25x", 0.25), ("0.5x", 0.5), ("1.0x", 1.0), ("1.5x", 1.5), ("2.0x", 2.0), ("3.0x", 3.0), ("4.0x", 4.0)] {
            let item = NSMenuItem(title: title, action: #selector(TripexMenuTarget.setTripexIntensity(_:)), keyEquivalent: "")
            item.target = target
            item.tag = Int((value * 100).rounded())
            item.state = abs(currentIntensity - Float(value)) < 0.01 ? .on : .off
            intensityMenu.addItem(item)
        }
        let intensityMenuItem = NSMenuItem(title: "Intensity", action: nil, keyEquivalent: "")
        intensityMenuItem.submenu = intensityMenu
        menu.addItem(intensityMenuItem)

        let audioInfoItem = NSMenuItem(title: "Show Audio Info", action: #selector(TripexMenuTarget.toggleTripexAudioInfoAction(_:)), keyEquivalent: "")
        audioInfoItem.target = target
        menu.addItem(audioInfoItem)

        let helpItem = NSMenuItem(title: "Show Help Overlay", action: #selector(TripexMenuTarget.toggleTripexHelpAction(_:)), keyEquivalent: "")
        helpItem.target = target
        menu.addItem(helpItem)
    }
}

@objc(TripexMenuTarget) protocol TripexMenuTarget: AnyObject {
    func reconfigureTripexAction(_ sender: NSMenuItem)
    func toggleTripexAudioInfoAction(_ sender: NSMenuItem)
    func toggleTripexHelpAction(_ sender: NSMenuItem)
    func setTripexIntensity(_ sender: NSMenuItem)
}

extension TripexEngine {
    func addMenuItems(to menu: NSMenu, target: VisualizationMenuTarget, glView: VisualizationGLView) {
        TripexMenuBuilder.addTripexConfigMenuItems(to: menu, target: target, visualizationView: glView)
    }
}
