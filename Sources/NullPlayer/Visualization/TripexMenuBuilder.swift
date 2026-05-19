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

    static func addTripexConfigMenuItems(to menu: NSMenu,
                                         target: AnyObject,
                                         visualizationView: VisualizationGLView,
                                         cycleMode: TripexCycleMode = .cycle,
                                         cycleInterval: TimeInterval = 30.0) {
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

        // Menu items use empty keyEquivalents — bare-key shortcuts
        // (→ / ← / R) are wired directly in ProjectMView.keyDown,
        // mirroring the ProjectM/Geiss control scheme.
        let nextItem = NSMenuItem(title: "Next Effect", action: #selector(TripexMenuTarget.nextTripexEffectAction(_:)), keyEquivalent: "")
        nextItem.target = target
        menu.addItem(nextItem)

        let prevItem = NSMenuItem(title: "Previous Effect", action: #selector(TripexMenuTarget.previousTripexEffectAction(_:)), keyEquivalent: "")
        prevItem.target = target
        menu.addItem(prevItem)

        let randomItem = NSMenuItem(title: "Random Effect", action: #selector(TripexMenuTarget.randomTripexEffectAction(_:)), keyEquivalent: "")
        randomItem.target = target
        menu.addItem(randomItem)

        let reconfigureItem = NSMenuItem(title: "Reconfigure Effect", action: #selector(TripexMenuTarget.reconfigureTripexAction(_:)), keyEquivalent: "")
        reconfigureItem.target = target
        menu.addItem(reconfigureItem)

        menu.addItem(NSMenuItem.separator())

        // Cycle controls — mirror ProjectM's Manual/Auto-Cycle/Auto-Random
        // + Cycle Interval submenu for a uniform UX across engines.
        let cycleOffItem = NSMenuItem(title: "Manual Only", action: #selector(TripexMenuTarget.setTripexCycleModeOff(_:)), keyEquivalent: "")
        cycleOffItem.target = target
        cycleOffItem.state = cycleMode == .off ? .on : .off
        menu.addItem(cycleOffItem)

        let cycleSeqItem = NSMenuItem(title: "Auto-Cycle", action: #selector(TripexMenuTarget.setTripexCycleModeCycle(_:)), keyEquivalent: "")
        cycleSeqItem.target = target
        cycleSeqItem.state = cycleMode == .cycle ? .on : .off
        menu.addItem(cycleSeqItem)

        let cycleRandItem = NSMenuItem(title: "Auto-Random", action: #selector(TripexMenuTarget.setTripexCycleModeRandom(_:)), keyEquivalent: "")
        cycleRandItem.target = target
        cycleRandItem.state = cycleMode == .random ? .on : .off
        menu.addItem(cycleRandItem)

        let intervalMenu = NSMenu()
        for (name, seconds) in [("5 seconds", 5.0), ("10 seconds", 10.0), ("20 seconds", 20.0), ("30 seconds", 30.0), ("60 seconds", 60.0), ("2 minutes", 120.0)] {
            let item = NSMenuItem(title: name, action: #selector(TripexMenuTarget.setTripexCycleIntervalFromMenu(_:)), keyEquivalent: "")
            item.target = target
            item.tag = Int(seconds)
            item.state = abs(cycleInterval - seconds) < 0.5 ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalMenuItem = NSMenuItem(title: "Cycle Interval", action: nil, keyEquivalent: "")
        intervalMenuItem.submenu = intervalMenu
        menu.addItem(intervalMenuItem)

        menu.addItem(NSMenuItem.separator())

        let audioInfoItem = NSMenuItem(title: "Show Audio Info", action: #selector(TripexMenuTarget.toggleTripexAudioInfoAction(_:)), keyEquivalent: "")
        audioInfoItem.target = target
        menu.addItem(audioInfoItem)

        let helpItem = NSMenuItem(title: "Show Help Overlay", action: #selector(TripexMenuTarget.toggleTripexHelpAction(_:)), keyEquivalent: "")
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

/// Tripex cycle mode — mirrors ProjectM's PresetCycleMode for uniform UX.
enum TripexCycleMode {
    case off, cycle, random
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

    func setTripexCycleModeOff(_ sender: Any?)
    func setTripexCycleModeCycle(_ sender: Any?)
    func setTripexCycleModeRandom(_ sender: Any?)
    func setTripexCycleIntervalFromMenu(_ sender: NSMenuItem)
}
