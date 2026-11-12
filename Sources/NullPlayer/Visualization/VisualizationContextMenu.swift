import AppKit

/// What the shared menu needs from whoever owns the engine. Every method is an action a menu item
/// targets, so the protocol is `@objc`: the builder makes its selectors against *this* type, which is
/// what lets one menu serve unrelated views. The presets and cycle every engine shares target the
/// engine view itself (`VisualizationGLView+Presets`), so no host repeats them.
@objc(VisualizationMenuTarget) protocol VisualizationMenuTarget: GeissMenuTarget, TripexMenuTarget {
    func setCurrentPresetAsDefault(_ sender: NSMenuItem?)
    func setCurrentPresetRatingFromMenu(_ sender: NSMenuItem)
    func toggleCurrentPresetFavorite(_ sender: NSMenuItem?)
    func selectFavoritePresetFromMenu(_ sender: NSMenuItem)
    func switchVisualizationEngine(_ sender: NSMenuItem)
    func setAudioSensitivity(_ sender: NSMenuItem)
    func setBeatSensitivityAction(_ sender: NSMenuItem)
    func togglePerformanceMode(_ sender: NSMenuItem?)
    func toggleFullscreenAction(_ sender: NSMenuItem?)
    func closeWindow(_ sender: NSMenuItem?)
}

/// The visualization context menu — one copy, for every view that owns a `VisualizationGLView`.
///
/// It was written twice, identically, in `ProjectMView` and `ModernProjectMView`, and a third caller
/// arrived with B20a: the visualization engine hosted inside a `.wal` skin's own AVS window. That one
/// got a short hand-written menu instead, and the first thing reported against it was that its menu
/// was "truncated" next to the one the visualization window has — which is exactly what a second,
/// drifting copy of a menu looks like from the outside. So the menu moved here and all three build
/// the same one.
///
/// Every engine gets the same menu: the running preset, Next / Previous / Random and the preset
/// list (`VisualizationGLView+Presets`), the auto-cycle (`VisualizationPresetCycler`), then that
/// engine's own items, then the engine picker, sensitivity, quality and the window items. The target
/// supplies the engine (`visualizationGLView`) and the host actions; whether a window-level
/// Fullscreen / Close item makes sense comes in as `Options`.
enum VisualizationContextMenu {

    /// What the menu shows but does not own.
    struct Options {
        /// A window-level item is only offered to something that has a window of its own to do it
        /// with. The embedded skin surface has neither — its "window" is a box inside the skin's.
        var showsFullscreen = true
        var showsClose = true
        /// Visualization Engine ▸ — off where the host has its own picker: a `.wmz` / Sonique
        /// effects slot lists the engines in its Effect menu, among its own effects.
        var showsEnginePicker = true
        /// Cast Visualization ▸ — only the Classic and Modern Visualizations windows opt in.
        var showsCast = false
    }

    /// Winamp's own five-star string, used in the preset titles.
    static func starString(for rating: Int) -> String {
        let clamped = min(5, max(0, rating))
        return String(repeating: "⭐", count: clamped) + String(repeating: "☆", count: 5 - clamped)
    }

    @MainActor
    static func build(target: VisualizationMenuTarget, options: Options) -> NSMenu {
        let menu = NSMenu()
        let glView = target.visualizationGLView
        let currentEngineType = glView?.currentEngineType ?? .projectM

        if let glView {
            // ProjectM rates its presets: read once, for the preset titles and its own items.
            let rated = currentEngineType == .projectM && glView.isProjectMAvailable
                ? RatedPresets(glView: glView) : nil
            addPresets(to: menu, glView: glView, rated: rated)
            menu.addItem(.separator())
            addCycle(to: menu, glView: glView)
            menu.addItem(.separator())
            let extrasStart = menu.numberOfItems
            switch currentEngineType {
            case .projectM:
                if let rated { addProjectMRatings(to: menu, target: target, glView: glView, rated: rated) }
            case .goom, .smear:
                break
            case .geiss:
                GeissMenuBuilder.addGeissConfigMenuItems(to: menu, target: target, visualizationView: glView)
            case .tripex:
                TripexMenuBuilder.addTripexConfigMenuItems(to: menu, target: target, visualizationView: glView)
            case .avs:
                (glView.currentEngine as? AvsEngine)?.addMenuItems(to: menu)
            case .corona:
                (glView.currentEngine as? CoronaEngine)?.addMenuItems(to: menu)
            }
            if menu.numberOfItems > extrasStart { menu.addItem(.separator()) }
        }

        if options.showsEnginePicker {
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
        }
        
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
        if currentEngineType == .projectM, glView?.isProjectMAvailable == true {
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

        if options.showsCast, let glView { menu.addItem(glView.castMenuItem()) }

        if options.showsClose {
            menu.addItem(NSMenuItem.separator())
            // Close
            let closeItem = NSMenuItem(title: "Close", action: #selector(VisualizationMenuTarget.closeWindow(_:)), keyEquivalent: "")
            closeItem.target = target
            menu.addItem(closeItem)
        }
        
        return menu
    }

    /// The block every engine shares: the running preset, stepping, and the full list. ProjectM
    /// rates its presets, so its titles carry the stars.
    private static func addPresets(to menu: NSMenu, glView: VisualizationGLView, rated: RatedPresets?) {
        let count = glView.enginePresetCount
        let current = glView.currentEnginePresetIndex
        func title(_ index: Int) -> String {
            let name = glView.enginePresetName(at: index)
            let shown = name.isEmpty ? "Preset \(index + 1)" : name
            guard let rated, rated.ratings.indices.contains(index) else { return shown }
            return "\(shown) [\(starString(for: rated.ratings[index]))]"
        }

        let header = current.map { "Preset: \(title($0)) (\($0 + 1)/\(count))" } ?? "Preset: (none)"
        let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        for (title, action, key) in [("Next Preset", #selector(VisualizationGLView.nextPresetMenuAction(_:)), ""),
                                     ("Previous Preset", #selector(VisualizationGLView.previousPresetMenuAction(_:)), ""),
                                     ("Random Preset", #selector(VisualizationGLView.randomPresetMenuAction(_:)), "r")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = glView
            item.isEnabled = count > 0
            menu.addItem(item)
        }

        guard count > 0 else { return }
        let list = NSMenu()
        for index in 0..<count {
            let item = NSMenuItem(title: title(index), action: #selector(VisualizationGLView.selectPresetMenuAction(_:)), keyEquivalent: "")
            item.target = glView
            item.tag = index
            item.state = index == current ? .on : .off
            list.addItem(item)
        }
        let listItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        listItem.submenu = list
        menu.addItem(listItem)
    }

    /// The running engine's auto-cycle (`VisualizationPresetCycler`), the same for every engine.
    private static func addCycle(to menu: NSMenu, glView: VisualizationGLView) {
        let cycler = glView.presetCycler
        for (title, mode, key) in [("Manual Only", VisualizationCycleMode.off, ""), ("Auto-Cycle", .cycle, "c"), ("Auto-Random", .random, "")] {
            let item = NSMenuItem(title: title, action: #selector(VisualizationGLView.setCycleModeMenuAction(_:)), keyEquivalent: key)
            item.target = glView
            item.representedObject = mode.rawValue
            item.state = cycler.mode == mode ? .on : .off
            menu.addItem(item)
        }

        let intervals = NSMenu()
        for seconds in VisualizationCycleSettings.intervals {
            let title = seconds < 60 ? "\(Int(seconds)) seconds" : "\(Int(seconds / 60)) minute\(seconds > 60 ? "s" : "")"
            let item = NSMenuItem(title: title, action: #selector(VisualizationGLView.setCycleIntervalMenuAction(_:)), keyEquivalent: "")
            item.target = glView
            item.tag = Int(seconds)
            item.state = abs(cycler.interval - seconds) < 0.5 ? .on : .off
            intervals.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Cycle Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervals
        menu.addItem(intervalItem)
    }

    /// ProjectM's presets by index: each path as the ratings store keys it, and its rating.
    private struct RatedPresets {
        let paths: [String]
        let ratings: [Int]

        init(glView: VisualizationGLView) {
            paths = (0..<glView.presetCount).map { (glView.presetPath(at: $0) as NSString).standardizingPath }
            let byPath = ProjectMPresetRatingsStore.shared.ratings(forPresetPaths: paths)
            ratings = paths.map { byPath[$0] ?? 0 }
        }
    }

    /// ProjectM's own items: its default preset, ratings and favorites.
    private static func addProjectMRatings(to menu: NSMenu, target: VisualizationMenuTarget,
                                           glView: VisualizationGLView, rated: RatedPresets) {
        let ratingsStore = ProjectMPresetRatingsStore.shared
        let presetCount = rated.paths.count
        let currentPresetIndex = glView.currentEnginePresetIndex
        let currentRating = currentPresetIndex.map { rated.ratings[$0] } ?? 0

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
        let isCurrentPresetFavorite = currentPresetIndex.map { ratingsStore.isFavorite(forPresetPath: rated.paths[$0]) } ?? false
        let toggleFavoriteItem = NSMenuItem(
            title: isCurrentPresetFavorite ? "Remove Current Preset from Favorites" : "Add Current Preset to Favorites",
            action: #selector(VisualizationMenuTarget.toggleCurrentPresetFavorite(_:)),
            keyEquivalent: ""
        )
        toggleFavoriteItem.target = target
        toggleFavoriteItem.isEnabled = presetCount > 0
        favoritesMenu.addItem(toggleFavoriteItem)

        let favoritePaths = ratingsStore.favoritePresetPaths(forPresetPaths: rated.paths)
        if !favoritePaths.isEmpty {
            favoritesMenu.addItem(NSMenuItem.separator())
            for (i, path) in rated.paths.enumerated() where favoritePaths.contains(path) {
                let title = "\(glView.presetName(at: i)) [\(starString(for: rated.ratings[i]))]"
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
    }
}
