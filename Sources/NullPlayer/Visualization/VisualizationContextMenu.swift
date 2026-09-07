import AppKit

/// The visualization context menu — one copy, for every view that owns a `VisualizationGLView`.
///
/// It was written twice, identically, in `ProjectMView` and `ModernProjectMView`, and a third caller
/// arrived with B20a: the visualization engine hosted inside a `.wal` skin's own AVS window. That one
/// got a short hand-written menu instead, and the first thing reported against it was that its menu
/// was "truncated" next to the one the visualization window has — which is exactly what a second,
/// drifting copy of a menu looks like from the outside. So the menu moved here and all three build
/// the same one.
///
/// The target supplies the engine (`visualizationGLView`) and every action; the caller's own state
/// that the menu only *displays* — the preset cycle mode and interval, and whether a window-level
/// Fullscreen / Close item makes sense — comes in as `Options`.
/// What the shared menu needs from whoever owns the engine. Every method is an action a menu item
/// targets, so the protocol is `@objc`: the builder makes its selectors against *this* type, which is
/// what lets one menu serve three unrelated views.
@objc(VisualizationMenuTarget) protocol VisualizationMenuTarget: GeissMenuTarget, TripexMenuTarget {
    func nextPresetAction(_ sender: NSMenuItem?)
    func previousPresetAction(_ sender: NSMenuItem?)
    func randomPresetAction(_ sender: NSMenuItem?)
    func setCurrentPresetAsDefault(_ sender: NSMenuItem?)
    func setCurrentPresetRatingFromMenu(_ sender: NSMenuItem)
    func toggleCurrentPresetFavorite(_ sender: NSMenuItem?)
    func selectFavoritePresetFromMenu(_ sender: NSMenuItem)
    func selectPresetFromMenu(_ sender: NSMenuItem)
    func setCycleModeOff(_ sender: NSMenuItem?)
    func setCycleModeCycle(_ sender: NSMenuItem?)
    func setCycleModeRandom(_ sender: NSMenuItem?)
    func setCycleInterval(_ sender: NSMenuItem)
    func switchVisualizationEngine(_ sender: NSMenuItem)
    func setAudioSensitivity(_ sender: NSMenuItem)
    func setBeatSensitivityAction(_ sender: NSMenuItem)
    func togglePerformanceMode(_ sender: NSMenuItem?)
    func toggleFullscreenAction(_ sender: NSMenuItem?)
    func closeWindow(_ sender: NSMenuItem?)
    func nextGeissEffectAction(_ sender: NSMenuItem?)
    func previousGeissEffectAction(_ sender: NSMenuItem?)
    func randomGeissEffectAction(_ sender: NSMenuItem?)
    func selectGeissEffectFromMenu(_ sender: NSMenuItem)
}

enum VisualizationContextMenu {

    /// What the menu shows but does not own.
    struct Options {
        var cycleMode: VisualizationCycleMode = ProjectMPresetCycleSettings.defaultMode
        var cycleInterval: TimeInterval = ProjectMPresetCycleSettings.defaultInterval
        var tripexCycleMode: VisualizationCycleMode = .cycle
        var tripexCycleInterval: TimeInterval = 30
        /// A window-level item is only offered to something that has a window of its own to do it
        /// with. The embedded skin surface has neither — its "window" is a box inside the skin's.
        var showsFullscreen = true
        var showsClose = true
    }

    /// Winamp's own five-star string, used in the preset titles.
    static func starString(for rating: Int) -> String {
        let clamped = min(5, max(0, rating))
        return String(repeating: "⭐", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }

    static func build(target: VisualizationMenuTarget, options: Options) -> NSMenu {
        let menu = NSMenu()
        let glView = target.visualizationGLView
        let ratingsStore = ProjectMPresetRatingsStore.shared
        
        let currentEngineType = glView?.currentEngineType ?? .projectM
        let isProjectMAvailable = glView?.isProjectMAvailable ?? false
        let isProjectMActive = currentEngineType == .projectM && isProjectMAvailable
        let isGeissActive = currentEngineType == .geiss
        let isTripexActive = currentEngineType == .tripex

        // Preset navigation (only when projectM is available)
        if isProjectMActive {
            let presetName = glView?.currentPresetName ?? "Unknown"
            let currentPresetIndex = glView?.currentPresetIndex ?? 0
            let presetIndex = currentPresetIndex + 1
            let presetCount = glView?.presetCount ?? 0
            let currentPresetPath = glView?.presetPath(at: currentPresetIndex) ?? ""
            let currentRating = ratingsStore.rating(forPresetPath: currentPresetPath)

            let currentPresetItem = NSMenuItem(
                title: "Preset: \(presetName) [\(starString(for: currentRating))] (\(presetIndex)/\(presetCount))",
                action: nil,
                keyEquivalent: ""
            )
            currentPresetItem.isEnabled = false
            menu.addItem(currentPresetItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let nextPresetItem = NSMenuItem(title: "Next Preset", action: #selector(VisualizationMenuTarget.nextPresetAction(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
            nextPresetItem.target = target
            menu.addItem(nextPresetItem)
            
            let prevPresetItem = NSMenuItem(title: "Previous Preset", action: #selector(VisualizationMenuTarget.previousPresetAction(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
            prevPresetItem.target = target
            menu.addItem(prevPresetItem)
            
            let randomPresetItem = NSMenuItem(title: "Random Preset", action: #selector(VisualizationMenuTarget.randomPresetAction(_:)), keyEquivalent: "r")
            randomPresetItem.target = target
            menu.addItem(randomPresetItem)
            
            menu.addItem(NSMenuItem.separator())
            
            let setDefaultItem = NSMenuItem(title: "Set Current to Default", action: #selector(VisualizationMenuTarget.setCurrentPresetAsDefault(_:)), keyEquivalent: "")
            setDefaultItem.target = target
            setDefaultItem.isEnabled = presetCount > 0
            menu.addItem(setDefaultItem)

            let rateCurrentMenu = NSMenu()
            for rating in 0...5 {
                let title = rating == 0
                    ? "Clear Rating (\(starString(for: 0)))"
                    : "\(rating) Gold (\(starString(for: rating)))"
                let item = NSMenuItem(title: title, action: #selector(VisualizationMenuTarget.setCurrentPresetRatingFromMenu(_:)), keyEquivalent: "")
                item.target = target
                item.tag = rating
                item.state = currentRating == rating ? .on : .off
                rateCurrentMenu.addItem(item)
            }
            let rateCurrentMenuItem = NSMenuItem(title: "Rate Current Preset", action: nil, keyEquivalent: "")
            rateCurrentMenuItem.submenu = rateCurrentMenu
            menu.addItem(rateCurrentMenuItem)

            let favoritesMenu = NSMenu()
            let isCurrentPresetFavorite = ratingsStore.isFavorite(forPresetPath: currentPresetPath)
            let toggleFavoriteTitle = isCurrentPresetFavorite
                ? "Remove Current Preset from Favorites"
                : "Add Current Preset to Favorites"
            let toggleFavoriteItem = NSMenuItem(
                title: toggleFavoriteTitle,
                action: #selector(VisualizationMenuTarget.toggleCurrentPresetFavorite(_:)),
                keyEquivalent: ""
            )
            toggleFavoriteItem.target = target
            toggleFavoriteItem.isEnabled = presetCount > 0
            favoritesMenu.addItem(toggleFavoriteItem)

            let presetPaths = (0..<presetCount).map { glView?.presetPath(at: $0) ?? "" }
            let ratingsByPath = ratingsStore.ratings(forPresetPaths: presetPaths)
            let favoritePaths = ratingsStore.favoritePresetPaths(forPresetPaths: presetPaths)

            if !favoritePaths.isEmpty {
                favoritesMenu.addItem(NSMenuItem.separator())
                for i in 0..<presetCount {
                    let name = glView?.presetName(at: i) ?? "Preset \(i + 1)"
                    let path = (presetPaths[i] as NSString).standardizingPath
                    guard favoritePaths.contains(path) else { continue }
                    let rating = ratingsByPath[path] ?? 0
                    let title = "\(name) [\(starString(for: rating))]"
                    let item = NSMenuItem(title: title, action: #selector(VisualizationMenuTarget.selectFavoritePresetFromMenu(_:)), keyEquivalent: "")
                    item.target = target
                    item.representedObject = path
                    item.state = (i == currentPresetIndex) ? .on : .off
                    favoritesMenu.addItem(item)
                }
            }

            let favoritesMenuItem = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            favoritesMenuItem.submenu = favoritesMenu
            menu.addItem(favoritesMenuItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // Cycle mode options
            let cycleOffItem = NSMenuItem(title: "Manual Only", action: #selector(VisualizationMenuTarget.setCycleModeOff(_:)), keyEquivalent: "")
            cycleOffItem.target = target
            cycleOffItem.state = options.cycleMode == .off ? .on : .off
            menu.addItem(cycleOffItem)
            
            let cycleSeqItem = NSMenuItem(title: "Auto-Cycle", action: #selector(VisualizationMenuTarget.setCycleModeCycle(_:)), keyEquivalent: "c")
            cycleSeqItem.target = target
            cycleSeqItem.state = options.cycleMode == .cycle ? .on : .off
            menu.addItem(cycleSeqItem)
            
            let cycleRandItem = NSMenuItem(title: "Auto-Random", action: #selector(VisualizationMenuTarget.setCycleModeRandom(_:)), keyEquivalent: "")
            cycleRandItem.target = target
            cycleRandItem.state = options.cycleMode == .random ? .on : .off
            menu.addItem(cycleRandItem)
            
            // Cycle interval submenu
            let intervalMenu = NSMenu()
            for (name, seconds) in [("5 seconds", 5.0), ("10 seconds", 10.0), ("20 seconds", 20.0), ("30 seconds", 30.0), ("60 seconds", 60.0), ("2 minutes", 120.0)] {
                let item = NSMenuItem(title: name, action: #selector(VisualizationMenuTarget.setCycleInterval(_:)), keyEquivalent: "")
                item.target = target
                item.tag = Int(seconds)
                item.state = abs(options.cycleInterval - seconds) < 0.5 ? .on : .off
                intervalMenu.addItem(item)
            }
            let intervalMenuItem = NSMenuItem(title: "Cycle Interval", action: nil, keyEquivalent: "")
            intervalMenuItem.submenu = intervalMenu
            menu.addItem(intervalMenuItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // Presets submenu - list all available presets
            if presetCount > 0 {
                let presetsMenu = NSMenu()

                for i in 0..<presetCount {
                    let name = glView?.presetName(at: i) ?? "Preset \(i + 1)"
                    let path = presetPaths[i]
                    let rating = ratingsByPath[path] ?? 0
                    let title = "\(name) [\(starString(for: rating))]"
                    let presetItem = NSMenuItem(title: title, action: #selector(VisualizationMenuTarget.selectPresetFromMenu(_:)), keyEquivalent: "")
                    presetItem.target = target
                    presetItem.tag = i
                    presetItem.state = (i == (glView?.currentPresetIndex ?? -1)) ? .on : .off
                    presetsMenu.addItem(presetItem)
                }
                
                let presetsMenuItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
                presetsMenuItem.submenu = presetsMenu
                menu.addItem(presetsMenuItem)
                
                menu.addItem(NSMenuItem.separator())
            }
        } else if isGeissActive {
            addGeissEffects(to: menu, target: target)
        } else if isTripexActive {
            addTripexEffects(to: menu, target: target, options: options)
        }

        // Visualization Engine selector
        let engineMenu = NSMenu()

        for engineType in VisualizationType.allCases {
            let item = NSMenuItem(
                title: engineType.displayName,
                action: #selector(VisualizationMenuTarget.switchVisualizationEngine(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = engineType
            item.state = (currentEngineType == engineType) ? .on : .off
            engineMenu.addItem(item)
        }

        let engineMenuItem = NSMenuItem(title: "Visualization Engine", action: nil, keyEquivalent: "")
        engineMenuItem.submenu = engineMenu
        menu.addItem(engineMenuItem)

        menu.addItem(NSMenuItem.separator())
        
        // Audio Sensitivity submenu (PCM gain multiplier)
        let audioSensMenu = NSMenu()
        let currentPCMGain = glView?.pcmGain ?? 1.0
        for (name, value) in [("Low (0.5x)", 5), ("Normal (1.0x)", 10), ("High (1.5x)", 15), ("Intense (2.0x)", 20), ("Max (3.0x)", 30)] {
            let item = NSMenuItem(title: name, action: #selector(VisualizationMenuTarget.setAudioSensitivity(_:)), keyEquivalent: "")
            item.target = target
            item.tag = value
            item.state = abs(currentPCMGain - Float(value) / 10.0) < 0.05 ? .on : .off
            audioSensMenu.addItem(item)
        }
        let audioSensMenuItem = NSMenuItem(title: "Audio Sensitivity", action: nil, keyEquivalent: "")
        audioSensMenuItem.submenu = audioSensMenu
        menu.addItem(audioSensMenuItem)
        
        // Beat Sensitivity submenu (projectM beat detection threshold) - only for ProjectM
        if isProjectMActive {
            let beatSensMenu = NSMenu()
            let currentBeatSens = glView?.normalBeatSensitivity ?? 1.0
            for (name, value) in [("Low (0.5)", 5), ("Normal (1.0)", 10), ("High (1.5)", 15), ("Max (2.0)", 20)] {
                let item = NSMenuItem(title: name, action: #selector(VisualizationMenuTarget.setBeatSensitivityAction(_:)), keyEquivalent: "")
                item.target = target
                item.tag = value
                item.state = abs(currentBeatSens - Float(value) / 10.0) < 0.05 ? .on : .off
                beatSensMenu.addItem(item)
            }
            let beatSensMenuItem = NSMenuItem(title: "Beat Sensitivity", action: nil, keyEquivalent: "")
            beatSensMenuItem.submenu = beatSensMenu
            menu.addItem(beatSensMenuItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Performance mode toggle
        let isLowPower = glView?.isLowPowerMode ?? true
        let perfModeItem = NSMenuItem(
            title: isLowPower ? "Quality: Optimized (30fps)" : "Quality: Full (60fps)",
            action: #selector(VisualizationMenuTarget.togglePerformanceMode(_:)),
            keyEquivalent: "p"
        )
        perfModeItem.target = target
        menu.addItem(perfModeItem)

        // Fullscreen option
        if options.showsFullscreen {
            let fullscreenItem = NSMenuItem(title: "Fullscreen", action: #selector(VisualizationMenuTarget.toggleFullscreenAction(_:)), keyEquivalent: "f")
            fullscreenItem.target = target
            menu.addItem(fullscreenItem)
        }

        if options.showsClose {
            menu.addItem(NSMenuItem.separator())
            // Close
            let closeItem = NSMenuItem(title: "Close", action: #selector(VisualizationMenuTarget.closeWindow(_:)), keyEquivalent: "")
            closeItem.target = target
            menu.addItem(closeItem)
        }
        
        return menu
    }

    private static func addGeissEffects(to menu: NSMenu, target: VisualizationMenuTarget) {
        let glView = target.visualizationGLView
        let currentEffectName = glView?.currentGeissEffectName ?? "Mode 0"
        let effectCount = glView?.geissEffectCount ?? 0
        let currentEffectItem = NSMenuItem(
            title: "Effect: \(currentEffectName)",
            action: nil,
            keyEquivalent: ""
        )
        currentEffectItem.isEnabled = false
        menu.addItem(currentEffectItem)
        menu.addItem(NSMenuItem.separator())

        let nextEffectItem = NSMenuItem(title: "Next Effect", action: #selector(VisualizationMenuTarget.nextGeissEffectAction(_:)), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        nextEffectItem.target = target
        menu.addItem(nextEffectItem)

        let prevEffectItem = NSMenuItem(title: "Previous Effect", action: #selector(VisualizationMenuTarget.previousGeissEffectAction(_:)), keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        prevEffectItem.target = target
        menu.addItem(prevEffectItem)

        let randomEffectItem = NSMenuItem(title: "Random Effect", action: #selector(VisualizationMenuTarget.randomGeissEffectAction(_:)), keyEquivalent: "r")
        randomEffectItem.target = target
        menu.addItem(randomEffectItem)

        if effectCount > 0 {
            menu.addItem(NSMenuItem.separator())
            let effectsMenu = NSMenu()
            for index in 0..<effectCount {
                let name = glView?.geissEffectName(at: index) ?? "Mode \(index + 1)"
                let item = NSMenuItem(title: name, action: #selector(VisualizationMenuTarget.selectGeissEffectFromMenu(_:)), keyEquivalent: "")
                item.target = target
                item.tag = index
                item.state = name == currentEffectName ? .on : .off
                effectsMenu.addItem(item)
            }
            let effectsMenuItem = NSMenuItem(title: "Effects", action: nil, keyEquivalent: "")
            effectsMenuItem.submenu = effectsMenu
            menu.addItem(effectsMenuItem)
        }

        if let glView = glView {
            GeissMenuBuilder.addGeissConfigMenuItems(to: menu, target: target, visualizationView: glView)
        }
    }

    private static func addTripexEffects(to menu: NSMenu, target: VisualizationMenuTarget,
                                        options: Options) {
        guard let glView = target.visualizationGLView else { return }
        let mode: TripexCycleMode
        switch options.tripexCycleMode {
        case .off:    mode = .off
        case .cycle:  mode = .cycle
        case .random: mode = .random
        }
        TripexMenuBuilder.addTripexConfigMenuItems(to: menu,
                                                   target: target,
                                                   visualizationView: glView,
                                                   cycleMode: mode,
                                                   cycleInterval: options.tripexCycleInterval)
    }
}
