import AppKit

/// Shared menu builder for Met Museum Art visualization settings
///
/// Surfaces configuration for:
/// - Department selection
/// - Slideshow interval
/// - Transition mode and duration
/// - Aspect ratio
/// - Audio effects toggles
/// - Cache clear action
final class MetMuseumMenuBuilder {

    static func addMetMuseumEffectsMenuItems(to menu: NSMenu,
                                              target: AnyObject,
                                              visualizationView: VisualizationGLView?) {
        // Read config once at the top
        let config = (visualizationView?.currentEngine as? MetMuseumEngine)?.getConfig()

        // Department selector
        let deptItem = NSMenuItem(title: "Department", action: nil, keyEquivalent: "")
        let deptMenu = NSMenu()
        deptItem.submenu = deptMenu

        // Extract current state from config
        let currentDeptID = config?.departmentID

        // Build menu based on department state
        if let engine = visualizationView?.currentEngine as? MetMuseumEngine {
            switch engine.departmentsState {
            case .loading:
                let loadingItem = NSMenuItem(title: "Loading departments…", action: nil, keyEquivalent: "")
                loadingItem.isEnabled = false
                deptMenu.addItem(loadingItem)

                let randomItem = NSMenuItem(title: "Random / All",
                                           action: #selector(MetMuseumMenuTarget.selectMetMuseumDepartment(_:)),
                                           keyEquivalent: "")
                randomItem.target = target
                randomItem.tag = -1
                randomItem.state = (currentDeptID == nil) ? .on : .off
                deptMenu.addItem(randomItem)

            case .loaded(let depts):
                let randomItem = NSMenuItem(title: "Random / All",
                                           action: #selector(MetMuseumMenuTarget.selectMetMuseumDepartment(_:)),
                                           keyEquivalent: "")
                randomItem.target = target
                randomItem.tag = -1
                randomItem.state = (currentDeptID == nil) ? .on : .off
                deptMenu.addItem(randomItem)

                deptMenu.addItem(NSMenuItem.separator())

                for dept in depts {
                    let item = NSMenuItem(title: dept.displayName,
                                         action: #selector(MetMuseumMenuTarget.selectMetMuseumDepartment(_:)),
                                         keyEquivalent: "")
                    item.target = target
                    item.tag = dept.id
                    item.state = (currentDeptID == dept.id) ? NSControl.StateValue.on : NSControl.StateValue.off
                    deptMenu.addItem(item)
                }

            case .failed:
                let randomItem = NSMenuItem(title: "Random / All",
                                           action: #selector(MetMuseumMenuTarget.selectMetMuseumDepartment(_:)),
                                           keyEquivalent: "")
                randomItem.target = target
                randomItem.tag = -1
                randomItem.state = (currentDeptID == nil) ? .on : .off
                deptMenu.addItem(randomItem)
            }
        }

        menu.addItem(deptItem)
        menu.addItem(NSMenuItem.separator())

        // Slideshow interval submenu
        let intervalMenu = NSMenu()
        let currentInterval = config?.intervalSeconds ?? 30.0

        for (label, seconds) in [
            ("10 seconds", 10.0),
            ("20 seconds", 20.0),
            ("30 seconds", 30.0),
            ("60 seconds", 60.0),
            ("2 minutes", 120.0),
            ("5 minutes", 300.0),
            ("10 minutes", 600.0)
        ] {
            let item = NSMenuItem(title: label,
                                 action: #selector(MetMuseumMenuTarget.setMetMuseumInterval(_:)),
                                 keyEquivalent: "")
            item.target = target
            item.tag = Int(seconds)
            item.state = (abs(currentInterval - seconds) < 0.5) ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalMenuItem = NSMenuItem(title: "Slideshow Interval", action: nil, keyEquivalent: "")
        intervalMenuItem.submenu = intervalMenu
        menu.addItem(intervalMenuItem)

        // Transition mode submenu
        let transMenu = NSMenu()
        let currentMode = config?.transitionMode ?? .crossfade

        for mode in MetMuseumEngine.TransitionMode.allCases {
            let label = mode.displayLabel
            let item = NSMenuItem(title: label,
                                 action: #selector(MetMuseumMenuTarget.setMetMuseumTransitionMode(_:)),
                                 keyEquivalent: "")
            item.target = target
            item.representedObject = mode.rawValue
            item.state = (mode == currentMode) ? .on : .off
            transMenu.addItem(item)
        }
        let transMenuItem = NSMenuItem(title: "Transition", action: nil, keyEquivalent: "")
        transMenuItem.submenu = transMenu
        menu.addItem(transMenuItem)

        // Transition duration submenu
        let durationMenu = NSMenu()
        let currentDuration = config?.transitionDurationSeconds ?? 1.5

        for (label, seconds) in [
            ("0.5 seconds", 0.5),
            ("1 second", 1.0),
            ("1.5 seconds", 1.5),
            ("2 seconds", 2.0),
            ("3 seconds", 3.0)
        ] {
            let item = NSMenuItem(title: label,
                                 action: #selector(MetMuseumMenuTarget.setMetMuseumTransitionDuration(_:)),
                                 keyEquivalent: "")
            item.target = target
            item.tag = Int(seconds * 100)
            item.state = (abs(currentDuration - seconds) < 0.05) ? .on : .off
            durationMenu.addItem(item)
        }
        let durationMenuItem = NSMenuItem(title: "Transition Duration", action: nil, keyEquivalent: "")
        durationMenuItem.submenu = durationMenu
        menu.addItem(durationMenuItem)

        // Aspect ratio submenu
        let aspectMenu = NSMenu()
        let currentAspect = config?.aspectMode ?? .fit

        for mode in MetMuseumEngine.AspectMode.allCases {
            let label = mode.displayLabel
            let item = NSMenuItem(title: label,
                                 action: #selector(MetMuseumMenuTarget.setMetMuseumAspectMode(_:)),
                                 keyEquivalent: "")
            item.target = target
            item.representedObject = mode.rawValue
            item.state = (mode == currentAspect) ? .on : .off
            aspectMenu.addItem(item)
        }
        let aspectMenuItem = NSMenuItem(title: "Aspect Ratio", action: nil, keyEquivalent: "")
        aspectMenuItem.submenu = aspectMenu
        menu.addItem(aspectMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Audio-Modulated Effects toggle
        let audioReactiveEnabled = config?.audioReactiveEffects ?? false
        let audioEffectsItem = NSMenuItem(title: "Audio-Modulated Effects",
                                         action: #selector(MetMuseumMenuTarget.toggleMetMuseumAudioReactive(_:)),
                                         keyEquivalent: "")
        audioEffectsItem.target = target
        audioEffectsItem.state = audioReactiveEnabled ? .on : .off
        menu.addItem(audioEffectsItem)

        // Beat-Triggered Changes toggle
        let beatTriggeredEnabled = config?.beatTriggeredChanges ?? false
        let beatTriggeredItem = NSMenuItem(title: "Beat-Triggered Changes",
                                          action: #selector(MetMuseumMenuTarget.toggleMetMuseumBeatTriggered(_:)),
                                          keyEquivalent: "")
        beatTriggeredItem.target = target
        beatTriggeredItem.state = beatTriggeredEnabled ? .on : .off
        menu.addItem(beatTriggeredItem)

        // Pause Slideshow When Audio Paused toggle
        let pauseOnAudioPauseEnabled = config?.pauseOnAudioPause ?? false
        let pauseOnAudioItem = NSMenuItem(title: "Pause Slideshow When Audio Paused",
                                         action: #selector(MetMuseumMenuTarget.toggleMetMuseumPauseOnAudioPause(_:)),
                                         keyEquivalent: "")
        pauseOnAudioItem.target = target
        pauseOnAudioItem.state = pauseOnAudioPauseEnabled ? .on : .off
        menu.addItem(pauseOnAudioItem)

        // Show Artist & Title toggle
        let showAttributionEnabled = config?.showAttribution ?? false
        let attributionItem = NSMenuItem(title: "Show Artist & Title",
                                        action: #selector(MetMuseumMenuTarget.toggleMetMuseumShowAttribution(_:)),
                                        keyEquivalent: "")
        attributionItem.target = target
        attributionItem.state = showAttributionEnabled ? .on : .off
        menu.addItem(attributionItem)

        menu.addItem(NSMenuItem.separator())

        // Cache clear
        let cacheItem = NSMenuItem(title: "Clear Image Cache",
                                  action: #selector(MetMuseumMenuTarget.clearMetMuseumCache(_:)),
                                  keyEquivalent: "")
        cacheItem.target = target
        menu.addItem(cacheItem)
    }
}

// MARK: - Display Labels

extension MetMuseumEngine.TransitionMode {
    var displayLabel: String {
        switch self {
        case .crossfade: return "Crossfade"
        case .kenBurns: return "Ken Burns"
        case .beatCut: return "Beat-Synced Cut"
        case .slide: return "Slide"
        }
    }
}

extension MetMuseumEngine.AspectMode {
    var displayLabel: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }
}

/// Protocol for objects that handle Met Museum visualization menu actions
@objc(MetMuseumMenuTarget) protocol MetMuseumMenuTarget: AnyObject {
    func selectMetMuseumDepartment(_ sender: NSMenuItem)
    func setMetMuseumInterval(_ sender: NSMenuItem)
    func setMetMuseumTransitionMode(_ sender: NSMenuItem)
    func setMetMuseumTransitionDuration(_ sender: NSMenuItem)
    func setMetMuseumAspectMode(_ sender: NSMenuItem)
    func toggleMetMuseumAudioReactive(_ sender: NSMenuItem)
    func toggleMetMuseumBeatTriggered(_ sender: NSMenuItem)
    func toggleMetMuseumPauseOnAudioPause(_ sender: NSMenuItem)
    func toggleMetMuseumShowAttribution(_ sender: NSMenuItem)
    func clearMetMuseumCache(_ sender: NSMenuItem)
}
