import AppKit

/// Shared menu builder for Tripex-specific configuration UI.
///
/// Tripex (ben-marsh/tripex) exposes only navigation + toggle controls —
/// individual effects own their parameters internally, so the menu surface
/// is materially smaller than GeissMenuBuilder.
///
/// Surface:
///   - Current effect (label, disabled)
///   - Next / Previous / Random / Reconfigure
///   - Hold (toggle, persists `tripex.heldEffect` state implicitly via core)
///   - Show Audio Info / Show Help (toggle overlays)
///   - Effects submenu — checked entry tracks `currentEffectIndex`
final class TripexMenuBuilder {

    static func addTripexConfigMenuItems(to menu: NSMenu, target: AnyObject, visualizationView: VisualizationGLView) {
        let currentIndex = visualizationView.currentTripexEffectIndex
        let count = visualizationView.tripexEffectCount

        let currentName: String
        if currentIndex >= 0 && currentIndex < count {
            currentName = visualizationView.tripexEffectName(at: currentIndex)
        } else {
            currentName = "(starting)"
        }

        let currentItem = NSMenuItem(title: "Effect: \(currentName)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        menu.addItem(NSMenuItem.separator())

        let nextItem = NSMenuItem(title: "Next Effect", action: #selector(TripexMenuTarget.nextTripexEffectAction(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        nextItem.target = target
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(title: "Previous Effect", action: #selector(TripexMenuTarget.previousTripexEffectAction(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        prevItem.target = target
        menu.addItem(prevItem)

        let randomItem = NSMenuItem(title: "Random Effect", action: #selector(TripexMenuTarget.randomTripexEffectAction(_:)), keyEquivalent: "r")
        randomItem.target = target
        menu.addItem(randomItem)

        let reconfigureItem = NSMenuItem(title: "Reconfigure Effect", action: #selector(TripexMenuTarget.reconfigureTripexAction(_:)), keyEquivalent: "")
        reconfigureItem.target = target
        menu.addItem(reconfigureItem)

        menu.addItem(NSMenuItem.separator())

        let holdItem = NSMenuItem(title: "Hold Current Effect", action: #selector(TripexMenuTarget.toggleTripexHoldAction(_:)), keyEquivalent: "h")
        holdItem.target = target
        menu.addItem(holdItem)

        let audioInfoItem = NSMenuItem(title: "Show Audio Info", action: #selector(TripexMenuTarget.toggleTripexAudioInfoAction(_:)), keyEquivalent: "")
        audioInfoItem.target = target
        menu.addItem(audioInfoItem)

        let helpItem = NSMenuItem(title: "Show Help Overlay", action: #selector(TripexMenuTarget.toggleTripexHelpAction(_:)), keyEquivalent: "?")
        helpItem.target = target
        menu.addItem(helpItem)

        if count > 0 {
            menu.addItem(NSMenuItem.separator())
            let effectsMenu = NSMenu()
            for index in 0..<count {
                let name = visualizationView.tripexEffectName(at: index)
                let item = NSMenuItem(title: name.isEmpty ? "Effect \(index + 1)" : name,
                                      action: #selector(TripexMenuTarget.selectTripexEffectFromMenu(_:)),
                                      keyEquivalent: "")
                item.target = target
                item.tag = index
                item.state = (index == currentIndex) ? .on : .off
                effectsMenu.addItem(item)
            }
            let effectsMenuItem = NSMenuItem(title: "Effects", action: nil, keyEquivalent: "")
            effectsMenuItem.submenu = effectsMenu
            menu.addItem(effectsMenuItem)
        }
    }
}

@objc(TripexMenuTarget) protocol TripexMenuTarget: AnyObject {
    func nextTripexEffectAction(_ sender: NSMenuItem)
    func previousTripexEffectAction(_ sender: NSMenuItem)
    func randomTripexEffectAction(_ sender: NSMenuItem)
    func reconfigureTripexAction(_ sender: NSMenuItem)
    func toggleTripexHoldAction(_ sender: NSMenuItem)
    func toggleTripexAudioInfoAction(_ sender: NSMenuItem)
    func toggleTripexHelpAction(_ sender: NSMenuItem)
    func selectTripexEffectFromMenu(_ sender: NSMenuItem)
}
