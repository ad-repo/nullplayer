import AppKit
import AVFoundation
import CoreAudio

/// Builds the shared right-click context menu for all skin windows
class ContextMenuBuilder {
    
    // MARK: - Main Menu Builder
    
    static func buildMenu(includeOutputDevices: Bool = true, includeRepeatShuffle: Bool = true) -> NSMenu {
        let menu = NSMenu()
        let wm = WindowManager.shared

        // Now Playing
        let aboutPlaying = NSMenuItem(title: "Now Playing…", action: #selector(MenuActions.showAboutPlaying), keyEquivalent: "")
        aboutPlaying.target = MenuActions.shared
        let hasAudioContent = wm.audioEngine.currentTrack != nil
        let hasVideoContent = wm.currentVideoTitle != nil
        aboutPlaying.isEnabled = hasAudioContent || hasVideoContent
        menu.addItem(aboutPlaying)
        menu.addItem(NSMenuItem.separator())

        if includeRepeatShuffle {
            let repeatItem = NSMenuItem(title: "Repeat", action: #selector(MenuActions.toggleRepeat), keyEquivalent: "")
            repeatItem.target = MenuActions.shared
            repeatItem.state = wm.audioEngine.repeatEnabled ? .on : .off
            menu.addItem(repeatItem)

            let shuffleItem = NSMenuItem(title: "Shuffle", action: #selector(MenuActions.toggleShuffle), keyEquivalent: "")
            shuffleItem.target = MenuActions.shared
            shuffleItem.state = wm.audioEngine.shuffleEnabled ? .on : .off
            menu.addItem(shuffleItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Output Devices submenu
        if includeOutputDevices {
            menu.addItem(buildOutputDevicesMenuItem())
            menu.addItem(NSMenuItem.separator())
        }

        // Display toggles
        let alwaysOnTop = NSMenuItem(title: "Always On Top", action: #selector(MenuActions.toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTop.target = MenuActions.shared
        alwaysOnTop.state = wm.isAlwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTop)

        let doubleSize = NSMenuItem(title: "Large UI", action: #selector(MenuActions.toggleDoubleSize), keyEquivalent: "")
        doubleSize.target = MenuActions.shared
        doubleSize.state = wm.isDoubleSize ? .on : .off
        menu.addItem(doubleSize)

        menu.addItem(buildWindowLockMenuItem())
        menu.addItem(NSMenuItem.separator())

        // Window actions
        let snapToDefault = NSMenuItem(title: "Snap To Default", action: #selector(MenuActions.snapToDefault), keyEquivalent: "")
        snapToDefault.target = MenuActions.shared
        menu.addItem(snapToDefault)

        let minimizeAll = NSMenuItem(title: "Minimize All", action: #selector(MenuActions.minimizeAllWindows), keyEquivalent: "")
        minimizeAll.target = MenuActions.shared
        menu.addItem(minimizeAll)
        menu.addItem(NSMenuItem.separator())

        // Settings
        let rememberState = NSMenuItem(title: "Remember State", action: #selector(MenuActions.toggleRememberState), keyEquivalent: "")
        rememberState.target = MenuActions.shared
        rememberState.state = AppStateManager.shared.isEnabled ? .on : .off
        menu.addItem(rememberState)
        menu.addItem(NSMenuItem.separator())

        // Exit
        let exit = NSMenuItem(title: "Exit", action: #selector(MenuActions.exit), keyEquivalent: "")
        exit.target = MenuActions.shared
        menu.addItem(exit)

        menu.autoenablesItems = false
        return menu
    }

    // MARK: - Menu Bar Builders

    /// Builds the top-level "Windows" menu content for the macOS menu bar.
    static func buildMenuBarWindowsMenu() -> NSMenu {
        let menu = NSMenu()
        let wm = WindowManager.shared

        menu.addItem(buildWindowItem("Main Window", visible: wm.mainWindowController?.window?.isVisible ?? false, action: #selector(MenuActions.toggleMainWindow)))
        menu.addItem(buildWindowItem("Equalizer", visible: wm.isEqualizerVisible, action: #selector(MenuActions.toggleEQ)))
        menu.addItem(buildWindowItem("Playlist Editor", visible: wm.isPlaylistVisible, action: #selector(MenuActions.togglePlaylist)))
        menu.addItem(buildWindowItem("Waveform", visible: wm.isWaveformVisible, action: #selector(MenuActions.toggleWaveform)))
        menu.addItem(buildWindowItem("Library Browser", visible: wm.isPlexBrowserVisible, action: #selector(MenuActions.togglePlexBrowser)))
        if wm.isRunningModernUI {
            menu.addItem(buildWindowItem("Play History", visible: wm.isLibraryHistoryVisible,
                                         action: #selector(MenuActions.toggleLibraryHistory)))
        }
        menu.addItem(buildWindowItem("ProjectM", visible: wm.isProjectMVisible, action: #selector(MenuActions.toggleProjectM)))
        menu.addItem(buildWindowItem("Debug Console", visible: wm.isDebugWindowVisible, action: #selector(MenuActions.toggleDebugConsole)))

        menu.addItem(NSMenuItem.separator())

        let alwaysOnTop = NSMenuItem(title: "Always On Top", action: #selector(MenuActions.toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTop.target = MenuActions.shared
        alwaysOnTop.state = wm.isAlwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTop)

        if wm.isModernUIEnabled {
            let hideTitleBars = NSMenuItem(title: "Hide Title Bars", action: #selector(MenuActions.toggleHideTitleBars), keyEquivalent: "")
            hideTitleBars.target = MenuActions.shared
            hideTitleBars.state = wm.hideTitleBars ? .on : .off
            menu.addItem(hideTitleBars)
        }

        let doubleSize = NSMenuItem(title: "Large UI", action: #selector(MenuActions.toggleDoubleSize), keyEquivalent: "")
        doubleSize.target = MenuActions.shared
        doubleSize.state = wm.isDoubleSize ? .on : .off
        menu.addItem(doubleSize)

        menu.addItem(buildWindowLockMenuItem())

        let snapToDefault = NSMenuItem(title: "Snap To Default", action: #selector(MenuActions.snapToDefault), keyEquivalent: "")
        snapToDefault.target = MenuActions.shared
        menu.addItem(snapToDefault)

        let minimizeAll = NSMenuItem(title: "Minimize All Windows", action: #selector(MenuActions.minimizeAllWindows), keyEquivalent: "")
        minimizeAll.target = MenuActions.shared
        menu.addItem(minimizeAll)

        menu.addItem(NSMenuItem.separator())

        let rememberState = NSMenuItem(title: "Save State on Exit", action: #selector(MenuActions.toggleRememberState), keyEquivalent: "")
        rememberState.target = MenuActions.shared
        rememberState.state = AppStateManager.shared.isEnabled ? .on : .off
        menu.addItem(rememberState)

        menu.autoenablesItems = false
        return menu
    }

    /// Builds the top-level "UI" menu content for the macOS menu bar.
    static func buildMenuBarUIMenu() -> NSMenu {
        let menu = buildUIMenu()
        menu.autoenablesItems = false
        return menu
    }

    /// Builds the top-level "Playback" menu content for the macOS menu bar.
    static func buildMenuBarPlaybackMenu() -> NSMenu {
        let menu = NSMenu()
        let wm = WindowManager.shared

        let aboutPlaying = NSMenuItem(title: "About Playing", action: #selector(MenuActions.showAboutPlaying), keyEquivalent: "")
        aboutPlaying.target = MenuActions.shared
        let hasAudioContent = wm.audioEngine.currentTrack != nil
        let hasVideoContent = wm.currentVideoTitle != nil
        aboutPlaying.isEnabled = hasAudioContent || hasVideoContent
        menu.addItem(aboutPlaying)
        menu.addItem(NSMenuItem.separator())

        let optionsMenu = buildOptionsMenu()
        moveMenuItems(from: optionsMenu, to: menu)

        menu.addItem(NSMenuItem.separator())

        let rememberState = NSMenuItem(title: "Remember State On Quit", action: #selector(MenuActions.toggleRememberState), keyEquivalent: "")
        rememberState.target = MenuActions.shared
        rememberState.state = AppStateManager.shared.isEnabled ? .on : .off
        menu.addItem(rememberState)

        menu.autoenablesItems = false
        return menu
    }

    /// Builds the top-level "Visuals" menu content for the macOS menu bar.
    static func buildMenuBarVisualsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(buildVisualizationsMenuItem())
        menu.addItem(buildSpectrumAnalyzerMenuItem())
        menu.autoenablesItems = false
        return menu
    }

    /// Builds the top-level "Libraries" menu content for the macOS menu bar.
    static func buildMenuBarLibrariesMenu() -> NSMenu {
        let menu = buildLibrariesMenu()
        menu.autoenablesItems = false
        return menu
    }

    /// Builds the top-level "Output" menu content for the macOS menu bar.
    static func buildMenuBarOutputMenu() -> NSMenu {
        let menu = buildMenuBarOutputDevicesMenu()
        menu.autoenablesItems = false
        return menu
    }

    // MARK: - Modern Skins Menu

    /// Public access to a modern-skins-only menu (used by modern skin SK button)
    static func buildModernSkinsMenu() -> NSMenu {
        let modernMenu = NSMenu()
        modernMenu.autoenablesItems = false

        let isModern = WindowManager.shared.isModernUIEnabled

        // Last used modern skin for quick switch (shown at top when in classic mode)
        let lastModernSkin = UserDefaults.standard.string(forKey: "modernSkinName")
        if !isModern {
            let switchItem = NSMenuItem(
                title: "Switch to Modern" + (lastModernSkin.map { " (\($0))" } ?? ""),
                action: #selector(MenuActions.setModernMode),
                keyEquivalent: ""
            )
            switchItem.target = MenuActions.shared
            modernMenu.addItem(switchItem)
            modernMenu.addItem(NSMenuItem.separator())
        }

        let loadModernSkin = NSMenuItem(title: "Load Skin...", action: #selector(MenuActions.loadModernSkinFromFile), keyEquivalent: "")
        loadModernSkin.target = MenuActions.shared
        modernMenu.addItem(loadModernSkin)
        modernMenu.addItem(NSMenuItem.separator())

        // Modern skin list
        let modernSkins = ModernSkinEngine.shared.loader.availableSkins()
        let currentModernSkin = ModernSkinEngine.shared.currentSkinName

        if modernSkins.isEmpty {
            let noSkins = NSMenuItem(title: "No skins available", action: nil, keyEquivalent: "")
            noSkins.isEnabled = false
            modernMenu.addItem(noSkins)
        } else {
            for skinInfo in modernSkins {
                let item = NSMenuItem(title: skinInfo.name, action: #selector(MenuActions.selectModernSkin(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = skinInfo.name
                if isModern && skinInfo.name == currentModernSkin {
                    item.state = .on
                }
                modernMenu.addItem(item)
            }
        }

        modernMenu.addItem(NSMenuItem.separator())

        // Open modern skins folder
        let openModernFolder = NSMenuItem(title: "Open Skins Folder...", action: #selector(MenuActions.openModernSkinsFolder), keyEquivalent: "")
        openModernFolder.target = MenuActions.shared
        modernMenu.addItem(openModernFolder)

        return modernMenu
    }
    
    // MARK: - Window Toggle Items
    
    private static func buildWindowItem(_ title: String, visible: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = MenuActions.shared
        item.state = visible ? .on : .off
        return item
    }

    private static func buildWindowLockMenuItem() -> NSMenuItem {
        let isLocked = WindowManager.shared.isWindowLayoutLocked
        let title = isLocked ? "Unlock Connected Windows" : "Lock Connected Windows"
        let item = NSMenuItem(title: title, action: #selector(MenuActions.toggleWindowLayoutLock), keyEquivalent: "")
        item.target = MenuActions.shared
        return item
    }

    private static func moveMenuItems(from source: NSMenu, to destination: NSMenu) {
        while let item = source.items.first {
            source.removeItem(item)
            destination.addItem(item)
        }
    }

    // MARK: - UI Submenu (unified Modern/Classic with skin selection)
    
    private static func buildUIMenu() -> NSMenu {
        let uiMenu = NSMenu()
        uiMenu.autoenablesItems = false
        
        let isModern = WindowManager.shared.isModernUIEnabled
        
        // --- Modern submenu ---
        let modernItem = NSMenuItem(title: "Modern", action: nil, keyEquivalent: "")
        let modernMenu = NSMenu()
        modernMenu.autoenablesItems = false
        
        // Last used modern skin for quick switch (shown at top when in classic mode)
        let lastModernSkin = UserDefaults.standard.string(forKey: "modernSkinName")
        if !isModern {
            let switchItem = NSMenuItem(
                title: "Switch to Modern" + (lastModernSkin.map { " (\($0))" } ?? ""),
                action: #selector(MenuActions.setModernMode),
                keyEquivalent: ""
            )
            switchItem.target = MenuActions.shared
            modernMenu.addItem(switchItem)
            modernMenu.addItem(NSMenuItem.separator())
        }

        let loadModernSkin = NSMenuItem(title: "Load Skin...", action: #selector(MenuActions.loadModernSkinFromFile), keyEquivalent: "")
        loadModernSkin.target = MenuActions.shared
        modernMenu.addItem(loadModernSkin)
        modernMenu.addItem(NSMenuItem.separator())
        
        // Modern skin list
        let modernSkins = ModernSkinEngine.shared.loader.availableSkins()
        let currentModernSkin = ModernSkinEngine.shared.currentSkinName
        
        if modernSkins.isEmpty {
            let noSkins = NSMenuItem(title: "No skins available", action: nil, keyEquivalent: "")
            noSkins.isEnabled = false
            modernMenu.addItem(noSkins)
        } else {
            for skinInfo in modernSkins {
                let item = NSMenuItem(title: skinInfo.name, action: #selector(MenuActions.selectModernSkin(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = skinInfo.name
                if isModern && skinInfo.name == currentModernSkin {
                    item.state = .on
                }
                modernMenu.addItem(item)
            }
        }
        
        modernMenu.addItem(NSMenuItem.separator())
        
        // Open modern skins folder
        let openModernFolder = NSMenuItem(title: "Open Skins Folder...", action: #selector(MenuActions.openModernSkinsFolder), keyEquivalent: "")
        openModernFolder.target = MenuActions.shared
        modernMenu.addItem(openModernFolder)
        
        // Active indicator on the submenu item
        if isModern { modernItem.state = .on }
        modernItem.submenu = modernMenu
        uiMenu.addItem(modernItem)
        
        // --- Classic submenu ---
        let classicItem = NSMenuItem(title: "Classic", action: nil, keyEquivalent: "")
        let classicMenu = NSMenu()
        classicMenu.autoenablesItems = false
        
        // Last used classic skin for quick switch (shown at top when in modern mode)
        let lastClassicSkinPath = UserDefaults.standard.string(forKey: "lastClassicSkinPath")
        if isModern {
            let lastSkinName = lastClassicSkinPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            let switchItem = NSMenuItem(
                title: "Switch to Classic" + (lastSkinName.map { " (\($0))" } ?? ""),
                action: #selector(MenuActions.setClassicMode),
                keyEquivalent: ""
            )
            switchItem.target = MenuActions.shared
            classicMenu.addItem(switchItem)
            classicMenu.addItem(NSMenuItem.separator())
        }
        
        // Load Skin...
        let loadSkin = NSMenuItem(title: "Load Skin...", action: #selector(MenuActions.loadSkinFromFile), keyEquivalent: "")
        loadSkin.target = MenuActions.shared
        classicMenu.addItem(loadSkin)
        
        // Get More Skins...
        let getMoreSkins = NSMenuItem(title: "Get More Skins...", action: #selector(MenuActions.getMoreClassicSkins), keyEquivalent: "")
        getMoreSkins.target = MenuActions.shared
        classicMenu.addItem(getMoreSkins)
        
        classicMenu.addItem(NSMenuItem.separator())
        
        // Default Skin (Silver)
        let defaultSkinItem = NSMenuItem(title: "Default Skin (Silver)", action: #selector(MenuActions.loadDefaultClassicSkin), keyEquivalent: "")
        defaultSkinItem.target = MenuActions.shared
        // Show checkmark if using the bundled default skin (no custom skin path)
        if !isModern && WindowManager.shared.currentSkinPath == nil {
            defaultSkinItem.state = .on
        }
        classicMenu.addItem(defaultSkinItem)
        
        classicMenu.addItem(NSMenuItem.separator())
        
        // Available classic skins from Skins directory
        let currentSkinPath = WindowManager.shared.currentSkinPath
        let availableSkins = WindowManager.shared.availableSkins()
        if !availableSkins.isEmpty {
            for skin in availableSkins {
                let skinItem = NSMenuItem(title: skin.name, action: #selector(MenuActions.selectClassicSkin(_:)), keyEquivalent: "")
                skinItem.target = MenuActions.shared
                skinItem.representedObject = skin.url
                // Show checkmark for current skin
                if !isModern, let currentPath = currentSkinPath, currentPath == skin.url.path {
                    skinItem.state = .on
                }
                classicMenu.addItem(skinItem)
            }
        } else {
            let noSkins = NSMenuItem(title: "No skins installed", action: nil, keyEquivalent: "")
            noSkins.isEnabled = false
            classicMenu.addItem(noSkins)
        }
        
        // Active indicator on the submenu item
        if !isModern { classicItem.state = .on }
        classicItem.submenu = classicMenu
        uiMenu.addItem(classicItem)
        
        return uiMenu
    }
    
    // MARK: - Visualizations Submenu
    
    private static func buildVisualizationsMenuItem() -> NSMenuItem {
        let visItem = NSMenuItem(title: "Visualizations", action: nil, keyEquivalent: "")
        visItem.submenu = buildVisualizationsMenu()
        return visItem
    }

    private static func buildVisualizationsMenu() -> NSMenu {
        let visMenu = NSMenu()
        visMenu.autoenablesItems = false
        
        let wm = WindowManager.shared
        
        // Show preset count (can be determined without window open)
        let counts = ProjectMWrapper.staticPresetCounts
        let totalPresets = counts.bundled + counts.custom
        
        if totalPresets > 0 {
            let infoText: String
            if counts.custom > 0 {
                infoText = "\(totalPresets) presets (\(counts.bundled) bundled, \(counts.custom) custom)"
            } else {
                infoText = "\(totalPresets) presets (bundled)"
            }
            
            let infoItem = NSMenuItem(title: infoText, action: nil, keyEquivalent: "")
            visMenu.addItem(infoItem)
            visMenu.addItem(NSMenuItem.separator())
        } else if wm.isProjectMVisible && !wm.isProjectMAvailable {
            // Only show error if window is open but projectM failed to initialize
            let unavailableItem = NSMenuItem(title: "projectM not available", action: nil, keyEquivalent: "")
            visMenu.addItem(unavailableItem)
            visMenu.addItem(NSMenuItem.separator())
        }
        
        // Add Presets Folder...
        let addFolderItem = NSMenuItem(title: "Add Presets Folder...", action: #selector(MenuActions.addVisualizationsFolder), keyEquivalent: "")
        addFolderItem.target = MenuActions.shared
        visMenu.addItem(addFolderItem)
        
        // Show Presets Folder (only if custom folder is set)
        if ProjectMWrapper.hasCustomPresetsFolder {
            let showFolderItem = NSMenuItem(title: "Show Custom Presets Folder", action: #selector(MenuActions.showVisualizationsFolder), keyEquivalent: "")
            showFolderItem.target = MenuActions.shared
            visMenu.addItem(showFolderItem)
            
            // Remove Custom Folder
            let removeFolderItem = NSMenuItem(title: "Remove Custom Folder", action: #selector(MenuActions.removeVisualizationsFolder), keyEquivalent: "")
            removeFolderItem.target = MenuActions.shared
            visMenu.addItem(removeFolderItem)
        }
        
        // Rescan Presets
        let rescanItem = NSMenuItem(title: "Rescan Presets", action: #selector(MenuActions.rescanVisualizations), keyEquivalent: "")
        rescanItem.target = MenuActions.shared
        visMenu.addItem(rescanItem)
        
        visMenu.addItem(NSMenuItem.separator())
        
        // Show Bundled Presets in Finder
        let showBundledItem = NSMenuItem(title: "Show Bundled Presets", action: #selector(MenuActions.showBundledPresets), keyEquivalent: "")
        showBundledItem.target = MenuActions.shared
        visMenu.addItem(showBundledItem)
        
        return visMenu
    }
    
    // MARK: - Options Submenu
    
    private static func buildOptionsMenu() -> NSMenu {
        let optionsMenu = NSMenu()
        optionsMenu.autoenablesItems = false
        
        let wm = WindowManager.shared
        let engine = wm.audioEngine
        
        // Time display mode
        let timeElapsed = NSMenuItem(title: "Time elapsed", action: #selector(MenuActions.setTimeElapsed), keyEquivalent: "")
        timeElapsed.target = MenuActions.shared
        timeElapsed.state = wm.timeDisplayMode == .elapsed ? .on : .off
        optionsMenu.addItem(timeElapsed)
        
        let timeRemaining = NSMenuItem(title: "Time remaining", action: #selector(MenuActions.setTimeRemaining), keyEquivalent: "")
        timeRemaining.target = MenuActions.shared
        timeRemaining.state = wm.timeDisplayMode == .remaining ? .on : .off
        optionsMenu.addItem(timeRemaining)
        
        optionsMenu.addItem(NSMenuItem.separator())
        
        // Repeat/Shuffle
        let repeatItem = NSMenuItem(title: "Repeat", action: #selector(MenuActions.toggleRepeat), keyEquivalent: "")
        repeatItem.target = MenuActions.shared
        repeatItem.state = engine.repeatEnabled ? .on : .off
        optionsMenu.addItem(repeatItem)
        
        let shuffleItem = NSMenuItem(title: "Shuffle", action: #selector(MenuActions.toggleShuffle), keyEquivalent: "")
        shuffleItem.target = MenuActions.shared
        shuffleItem.state = engine.shuffleEnabled ? .on : .off
        optionsMenu.addItem(shuffleItem)

        let radioItem = NSMenuItem(title: "Radio", action: nil, keyEquivalent: "")
        let radioMenu = NSMenu()
        radioMenu.autoenablesItems = false

        let radioArtistLimitItem = NSMenuItem(title: "Max Tracks Per Artist", action: nil, keyEquivalent: "")
        let radioArtistLimitMenu = NSMenu()
        radioArtistLimitMenu.autoenablesItems = false
        let currentRadioArtistLimit = RadioPlaybackOptions.maxTracksPerArtist
        for limit in RadioPlaybackOptions.maxTracksPerArtistChoices {
            let title: String
            if limit == RadioPlaybackOptions.unlimitedMaxTracksPerArtist {
                title = "Unlimited"
            } else if limit == 1 {
                title = "1 track"
            } else {
                title = "\(limit) tracks"
            }
            let item = NSMenuItem(title: title, action: #selector(MenuActions.setRadioMaxTracksPerArtist(_:)), keyEquivalent: "")
            item.target = MenuActions.shared
            item.representedObject = limit
            item.state = currentRadioArtistLimit == limit ? .on : .off
            radioArtistLimitMenu.addItem(item)
        }
        radioArtistLimitItem.submenu = radioArtistLimitMenu
        radioMenu.addItem(radioArtistLimitItem)

        let radioPlaylistLengthItem = NSMenuItem(title: "Playlist Length", action: nil, keyEquivalent: "")
        let radioPlaylistLengthMenu = NSMenu()
        radioPlaylistLengthMenu.autoenablesItems = false
        let currentRadioPlaylistLength = RadioPlaybackOptions.playlistLength
        for limit in RadioPlaybackOptions.playlistLengthChoices {
            let item = NSMenuItem(
                title: "\(limit.formatted()) tracks",
                action: #selector(MenuActions.setRadioPlaylistLength(_:)),
                keyEquivalent: ""
            )
            item.target = MenuActions.shared
            item.representedObject = limit
            item.state = currentRadioPlaylistLength == limit ? .on : .off
            radioPlaylistLengthMenu.addItem(item)
        }
        radioPlaylistLengthItem.submenu = radioPlaylistLengthMenu
        radioMenu.addItem(radioPlaylistLengthItem)

        radioMenu.addItem(NSMenuItem.separator())

        // Group all source-specific radio history entries under one parent item.
        let radioHistoryItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let radioHistoryMenu = NSMenu()
        radioHistoryMenu.autoenablesItems = false

        // Plex Radio History (only when Plex is connected)
        if PlexManager.shared.isLinked {
            let historyItem = NSMenuItem(title: "Plex", action: nil, keyEquivalent: "")
            let historyMenu = NSMenu()
            historyMenu.autoenablesItems = false

            let intervalItem = NSMenuItem(title: "History Interval", action: nil, keyEquivalent: "")
            let intervalMenu = NSMenu()
            intervalMenu.autoenablesItems = false

            let currentInterval = PlexRadioHistory.shared.retentionInterval
            for interval in PlexRadioHistoryInterval.allCases {
                let item = NSMenuItem(
                    title: interval.displayName,
                    action: #selector(MenuActions.setPlexRadioHistoryInterval(_:)),
                    keyEquivalent: ""
                )
                item.target = MenuActions.shared
                item.representedObject = interval.rawValue
                item.state = currentInterval == interval ? .on : .off
                intervalMenu.addItem(item)
            }
            intervalItem.submenu = intervalMenu
            historyMenu.addItem(intervalItem)
            historyMenu.addItem(NSMenuItem.separator())

            let viewItem = NSMenuItem(
                title: "View Radio History...",
                action: #selector(MenuActions.viewPlexRadioHistory),
                keyEquivalent: ""
            )
            viewItem.target = MenuActions.shared
            historyMenu.addItem(viewItem)

            let clearItem = NSMenuItem(
                title: "Clear Radio History...",
                action: #selector(MenuActions.clearPlexRadioHistory),
                keyEquivalent: ""
            )
            clearItem.target = MenuActions.shared
            historyMenu.addItem(clearItem)

            historyItem.submenu = historyMenu
            radioHistoryMenu.addItem(historyItem)
        }

        // Subsonic Radio History (shown whenever at least one server has been configured)
        if !SubsonicManager.shared.servers.isEmpty {
            let historyItem = NSMenuItem(title: "Subsonic", action: nil, keyEquivalent: "")
            let historyMenu = NSMenu()
            historyMenu.autoenablesItems = false

            let intervalItem = NSMenuItem(title: "History Interval", action: nil, keyEquivalent: "")
            let intervalMenu = NSMenu()
            intervalMenu.autoenablesItems = false
            let currentInterval = SubsonicRadioHistory.shared.retentionInterval
            for interval in SubsonicRadioHistoryInterval.allCases {
                let item = NSMenuItem(title: interval.displayName, action: #selector(MenuActions.setSubsonicRadioHistoryInterval(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = interval.rawValue
                item.state = currentInterval == interval ? .on : .off
                intervalMenu.addItem(item)
            }
            intervalItem.submenu = intervalMenu
            historyMenu.addItem(intervalItem)
            historyMenu.addItem(NSMenuItem.separator())

            let viewItem = NSMenuItem(title: "View Radio History...", action: #selector(MenuActions.viewSubsonicRadioHistory), keyEquivalent: "")
            viewItem.target = MenuActions.shared
            historyMenu.addItem(viewItem)

            let clearItem = NSMenuItem(title: "Clear Radio History...", action: #selector(MenuActions.clearSubsonicRadioHistory), keyEquivalent: "")
            clearItem.target = MenuActions.shared
            historyMenu.addItem(clearItem)

            historyItem.submenu = historyMenu
            radioHistoryMenu.addItem(historyItem)
        }

        // Jellyfin Radio History (shown whenever at least one server has been configured)
        if !JellyfinManager.shared.servers.isEmpty {
            let historyItem = NSMenuItem(title: "Jellyfin", action: nil, keyEquivalent: "")
            let historyMenu = NSMenu()
            historyMenu.autoenablesItems = false

            let intervalItem = NSMenuItem(title: "History Interval", action: nil, keyEquivalent: "")
            let intervalMenu = NSMenu()
            intervalMenu.autoenablesItems = false
            let currentInterval = JellyfinRadioHistory.shared.retentionInterval
            for interval in JellyfinRadioHistoryInterval.allCases {
                let item = NSMenuItem(title: interval.displayName, action: #selector(MenuActions.setJellyfinRadioHistoryInterval(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = interval.rawValue
                item.state = currentInterval == interval ? .on : .off
                intervalMenu.addItem(item)
            }
            intervalItem.submenu = intervalMenu
            historyMenu.addItem(intervalItem)
            historyMenu.addItem(NSMenuItem.separator())

            let viewItem = NSMenuItem(title: "View Radio History...", action: #selector(MenuActions.viewJellyfinRadioHistory), keyEquivalent: "")
            viewItem.target = MenuActions.shared
            historyMenu.addItem(viewItem)

            let clearItem = NSMenuItem(title: "Clear Radio History...", action: #selector(MenuActions.clearJellyfinRadioHistory), keyEquivalent: "")
            clearItem.target = MenuActions.shared
            historyMenu.addItem(clearItem)

            historyItem.submenu = historyMenu
            radioHistoryMenu.addItem(historyItem)
        }

        // Emby Radio History (shown whenever at least one server has been configured)
        if !EmbyManager.shared.servers.isEmpty {
            let historyItem = NSMenuItem(title: "Emby", action: nil, keyEquivalent: "")
            let historyMenu = NSMenu()
            historyMenu.autoenablesItems = false

            let intervalItem = NSMenuItem(title: "History Interval", action: nil, keyEquivalent: "")
            let intervalMenu = NSMenu()
            intervalMenu.autoenablesItems = false
            let currentInterval = EmbyRadioHistory.shared.retentionInterval
            for interval in EmbyRadioHistoryInterval.allCases {
                let item = NSMenuItem(title: interval.displayName, action: #selector(MenuActions.setEmbyRadioHistoryInterval(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = interval.rawValue
                item.state = currentInterval == interval ? .on : .off
                intervalMenu.addItem(item)
            }
            intervalItem.submenu = intervalMenu
            historyMenu.addItem(intervalItem)
            historyMenu.addItem(NSMenuItem.separator())

            let viewItem = NSMenuItem(title: "View Radio History...", action: #selector(MenuActions.viewEmbyRadioHistory), keyEquivalent: "")
            viewItem.target = MenuActions.shared
            historyMenu.addItem(viewItem)

            let clearItem = NSMenuItem(title: "Clear Radio History...", action: #selector(MenuActions.clearEmbyRadioHistory), keyEquivalent: "")
            clearItem.target = MenuActions.shared
            historyMenu.addItem(clearItem)

            historyItem.submenu = historyMenu
            radioHistoryMenu.addItem(historyItem)
        }

        // Local Radio History
        do {
            let historyItem = NSMenuItem(title: "Local", action: nil, keyEquivalent: "")
            let historyMenu = NSMenu()
            historyMenu.autoenablesItems = false

            let intervalItem = NSMenuItem(title: "History Interval", action: nil, keyEquivalent: "")
            let intervalMenu = NSMenu()
            intervalMenu.autoenablesItems = false
            let currentInterval = LocalRadioHistory.shared.retentionInterval
            for interval in LocalRadioHistoryInterval.allCases {
                let item = NSMenuItem(title: interval.displayName, action: #selector(MenuActions.setLocalRadioHistoryInterval(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = interval.rawValue
                item.state = currentInterval == interval ? .on : .off
                intervalMenu.addItem(item)
            }
            intervalItem.submenu = intervalMenu
            historyMenu.addItem(intervalItem)
            historyMenu.addItem(NSMenuItem.separator())

            let viewItem = NSMenuItem(title: "View Radio History...", action: #selector(MenuActions.viewLocalRadioHistory), keyEquivalent: "")
            viewItem.target = MenuActions.shared
            historyMenu.addItem(viewItem)

            let clearItem = NSMenuItem(title: "Clear Radio History...", action: #selector(MenuActions.clearLocalRadioHistory), keyEquivalent: "")
            clearItem.target = MenuActions.shared
            historyMenu.addItem(clearItem)

            historyItem.submenu = historyMenu
            radioHistoryMenu.addItem(historyItem)
        }

        radioHistoryItem.submenu = radioHistoryMenu
        radioMenu.addItem(radioHistoryItem)

        radioItem.submenu = radioMenu
        optionsMenu.addItem(radioItem)
        
        optionsMenu.addItem(NSMenuItem.separator())
        
        // Audio Quality Options
        let gaplessItem = NSMenuItem(title: "Gapless Playback", action: #selector(MenuActions.toggleGaplessPlayback), keyEquivalent: "")
        gaplessItem.target = MenuActions.shared
        gaplessItem.state = engine.gaplessPlaybackEnabled ? .on : .off
        optionsMenu.addItem(gaplessItem)
        
        let normalizeItem = NSMenuItem(title: "Volume Normalization", action: #selector(MenuActions.toggleVolumeNormalization), keyEquivalent: "")
        normalizeItem.target = MenuActions.shared
        normalizeItem.state = engine.volumeNormalizationEnabled ? .on : .off
        optionsMenu.addItem(normalizeItem)
        
        optionsMenu.addItem(NSMenuItem.separator())
        
        // Sweet Fades (Crossfade) toggle
        let sweetFadeItem = NSMenuItem(title: "Sweet Fades (Crossfade)", action: #selector(MenuActions.toggleSweetFade), keyEquivalent: "")
        sweetFadeItem.target = MenuActions.shared
        sweetFadeItem.state = engine.sweetFadeEnabled ? .on : .off
        optionsMenu.addItem(sweetFadeItem)
        
        // Duration submenu (only shown if Sweet Fades enabled)
        if engine.sweetFadeEnabled {
            let durationItem = NSMenuItem(title: "Fade Duration", action: nil, keyEquivalent: "")
            let durationMenu = NSMenu()
            durationMenu.autoenablesItems = false
            
            for duration in [1.0, 2.0, 3.0, 5.0, 7.0, 10.0] {
                let item = NSMenuItem(
                    title: "\(Int(duration))s",
                    action: #selector(MenuActions.setSweetFadeDuration(_:)),
                    keyEquivalent: ""
                )
                item.target = MenuActions.shared
                item.representedObject = duration
                item.state = engine.sweetFadeDuration == duration ? .on : .off
                durationMenu.addItem(item)
            }
            
            durationItem.submenu = durationMenu
            optionsMenu.addItem(durationItem)
        }
        
        optionsMenu.addItem(NSMenuItem.separator())
        
        // Visual Options
        let artworkBgItem = NSMenuItem(title: "Browser Album Art Background", action: #selector(MenuActions.toggleBrowserArtworkBackground), keyEquivalent: "")
        artworkBgItem.target = MenuActions.shared
        artworkBgItem.state = wm.showBrowserArtworkBackground ? .on : .off
        optionsMenu.addItem(artworkBgItem)

        return optionsMenu
    }
    
    // MARK: - Main Window Visualization Submenu
    
    /// Returns the submenu content for Main Window visualization settings
    private static func buildMainVisualizationSubmenu() -> NSMenu {
        let visMenu = NSMenu()
        visMenu.autoenablesItems = false
        
        let currentMode = UserDefaults.standard.string(forKey: "mainWindowVisMode")
            .flatMap { MainWindowVisMode(rawValue: $0) } ?? .spectrum
        
        // Mode submenu
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        modeMenu.autoenablesItems = false
        
        for mode in MainWindowVisMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(MenuActions.setMainVisMode(_:)), keyEquivalent: "")
            item.target = MenuActions.shared
            item.representedObject = mode
            item.state = (currentMode == mode) ? .on : .off
            // Disable modes whose shader file is missing
            if let qualityMode = mode.spectrumQualityMode,
               !SpectrumAnalyzerView.isShaderAvailable(for: qualityMode) {
                item.isEnabled = false
            }
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        visMenu.addItem(modeItem)
        
        // Responsiveness submenu
        let responsivenessItem = NSMenuItem(title: "Responsiveness", action: nil, keyEquivalent: "")
        let responsivenessMenu = NSMenu()
        responsivenessMenu.autoenablesItems = false
        
        let currentDecay = UserDefaults.standard.string(forKey: "mainWindowDecayMode")
            .flatMap { SpectrumDecayMode(rawValue: $0) } ?? .snappy
        
        for mode in SpectrumDecayMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(MenuActions.setMainVisResponsiveness(_:)), keyEquivalent: "")
            item.target = MenuActions.shared
            item.representedObject = mode
            item.state = (currentDecay == mode) ? .on : .off
            responsivenessMenu.addItem(item)
        }
        responsivenessItem.submenu = responsivenessMenu
        visMenu.addItem(responsivenessItem)
        
        // Normalization submenu (not shown for Fire mode)
        if currentMode != .fire {
            let normItem = NSMenuItem(title: "Normalization", action: nil, keyEquivalent: "")
            let normMenu = NSMenu()
            normMenu.autoenablesItems = false
            
            let currentNorm = UserDefaults.standard.string(forKey: "mainWindowNormalizationMode")
                .flatMap { SpectrumNormalizationMode(rawValue: $0) } ?? .accurate
            
            for mode in SpectrumNormalizationMode.allCases {
                let item = NSMenuItem(title: "\(mode.displayName) - \(mode.description)", action: #selector(MenuActions.setMainVisNormalization(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = mode
                item.state = (currentNorm == mode) ? .on : .off
                normMenu.addItem(item)
            }
            normItem.submenu = normMenu
            visMenu.addItem(normItem)
        }
        
        // Flame Style submenu (only when Fire mode active)
        if currentMode == .fire {
            let flameStyleItem = NSMenuItem(title: "Flame Style", action: nil, keyEquivalent: "")
            let flameStyleMenu = NSMenu()
            flameStyleMenu.autoenablesItems = false
            
            let currentStyle = UserDefaults.standard.string(forKey: "mainWindowFlameStyle")
                .flatMap { FlameStyle(rawValue: $0) } ?? .inferno
            
            for style in FlameStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(MenuActions.setMainVisFlameStyle(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = style
                item.state = (currentStyle == style) ? .on : .off
                flameStyleMenu.addItem(item)
            }
            
            flameStyleItem.submenu = flameStyleMenu
            visMenu.addItem(flameStyleItem)
            
            // Fire Intensity submenu
            let flameIntensityItem = NSMenuItem(title: "Fire Intensity", action: nil, keyEquivalent: "")
            let flameIntensityMenu = NSMenu()
            flameIntensityMenu.autoenablesItems = false
            
            let currentIntensity = UserDefaults.standard.string(forKey: "mainWindowFlameIntensity")
                .flatMap { FlameIntensity(rawValue: $0) } ?? .mellow
            
            for intensity in FlameIntensity.allCases {
                let item = NSMenuItem(title: intensity.displayName, action: #selector(MenuActions.setMainVisFlameIntensity(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = intensity
                item.state = (currentIntensity == intensity) ? .on : .off
                flameIntensityMenu.addItem(item)
            }
            
            flameIntensityItem.submenu = flameIntensityMenu
            visMenu.addItem(flameIntensityItem)
        }
        
        // Lightning Style submenu (only when Lightning mode active)
        if currentMode == .electricity {
            let lightningStyleItem = NSMenuItem(title: "Lightning Style", action: nil, keyEquivalent: "")
            let lightningStyleMenu = NSMenu()
            lightningStyleMenu.autoenablesItems = false
            
            let currentStyle = UserDefaults.standard.string(forKey: "mainWindowLightningStyle")
                .flatMap { LightningStyle(rawValue: $0) } ?? .classic
            
            for style in LightningStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(MenuActions.setMainVisLightningStyle(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = style
                item.state = (currentStyle == style) ? .on : .off
                lightningStyleMenu.addItem(item)
            }
            
            lightningStyleItem.submenu = lightningStyleMenu
            visMenu.addItem(lightningStyleItem)
        }
        
        // Matrix sub-menus (only when Matrix mode active)
        if currentMode == .matrix {
            // Matrix Color submenu
            let matrixColorItem = NSMenuItem(title: "Matrix Color", action: nil, keyEquivalent: "")
            let matrixColorMenu = NSMenu()
            matrixColorMenu.autoenablesItems = false
            
            let currentMatrixColor = UserDefaults.standard.string(forKey: "mainWindowMatrixColorScheme")
                .flatMap { MatrixColorScheme(rawValue: $0) } ?? .classic
            
            for scheme in MatrixColorScheme.allCases {
                let item = NSMenuItem(title: scheme.displayName, action: #selector(MenuActions.setMainVisMatrixColor(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = scheme
                item.state = (currentMatrixColor == scheme) ? .on : .off
                matrixColorMenu.addItem(item)
            }
            
            matrixColorItem.submenu = matrixColorMenu
            visMenu.addItem(matrixColorItem)
            
            // Matrix Intensity submenu
            let matrixIntensityItem = NSMenuItem(title: "Matrix Intensity", action: nil, keyEquivalent: "")
            let matrixIntensityMenu = NSMenu()
            matrixIntensityMenu.autoenablesItems = false
            
            let currentMatrixIntensity = UserDefaults.standard.string(forKey: "mainWindowMatrixIntensity")
                .flatMap { MatrixIntensity(rawValue: $0) } ?? .subtle
            
            for intensity in MatrixIntensity.allCases {
                let item = NSMenuItem(title: intensity.displayName, action: #selector(MenuActions.setMainVisMatrixIntensity(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = intensity
                item.state = (currentMatrixIntensity == intensity) ? .on : .off
                matrixIntensityMenu.addItem(item)
            }
            
            matrixIntensityItem.submenu = matrixIntensityMenu
            visMenu.addItem(matrixIntensityItem)
        }

        // vis_classic profile controls (only when vis_classic mode active)
        if currentMode == .visClassicExact {
            let profilesMenuItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
            let profilesMenu = NSMenu()
            profilesMenu.autoenablesItems = false

            let currentName = VisClassicBridge.lastProfileName(for: .mainWindow)
            let profiles = VisClassicBridge.availableProfilesCatalog()
            if profiles.isEmpty {
                let none = NSMenuItem(title: "No Profiles", action: nil, keyEquivalent: "")
                none.isEnabled = false
                profilesMenu.addItem(none)
            } else {
                for entry in profiles {
                    let item = NSMenuItem(title: entry.name, action: #selector(MenuActions.loadMainVisClassicProfile(_:)), keyEquivalent: "")
                    item.target = MenuActions.shared
                    item.representedObject = entry.name
                    item.state = (entry.name == currentName) ? .on : .off
                    profilesMenu.addItem(item)
                }
            }

            profilesMenuItem.submenu = profilesMenu
            visMenu.addItem(profilesMenuItem)
            visMenu.addItem(NSMenuItem.separator())

            let fitEnabled = VisClassicBridge.fitToWidthDefault(for: .mainWindow)
            let fitItem = NSMenuItem(title: "Fit to Width", action: #selector(MenuActions.toggleMainVisClassicFitToWidth), keyEquivalent: "")
            fitItem.target = MenuActions.shared
            fitItem.state = fitEnabled ? .on : .off
            visMenu.addItem(fitItem)

            let transparentBgEnabledMain = VisClassicBridge.transparentBgDefault(for: .mainWindow)
            let transparentBgItemMain = NSMenuItem(title: "Transparent Background", action: #selector(MenuActions.toggleMainVisClassicTransparentBg), keyEquivalent: "")
            transparentBgItemMain.target = MenuActions.shared
            transparentBgItemMain.state = transparentBgEnabledMain ? .on : .off
            visMenu.addItem(transparentBgItemMain)

            let nextItem = NSMenuItem(title: "Next Profile", action: #selector(MenuActions.nextMainVisClassicProfile), keyEquivalent: "")
            nextItem.target = MenuActions.shared
            visMenu.addItem(nextItem)

            let prevItem = NSMenuItem(title: "Previous Profile", action: #selector(MenuActions.previousMainVisClassicProfile), keyEquivalent: "")
            prevItem.target = MenuActions.shared
            visMenu.addItem(prevItem)

            let importItem = NSMenuItem(title: "Import INI...", action: #selector(MenuActions.importMainVisClassicProfile), keyEquivalent: "")
            importItem.target = MenuActions.shared
            visMenu.addItem(importItem)

            let exportItem = NSMenuItem(title: "Export Current INI...", action: #selector(MenuActions.exportMainVisClassicProfile), keyEquivalent: "")
            exportItem.target = MenuActions.shared
            visMenu.addItem(exportItem)
        }
        
        return visMenu
    }
    
    // MARK: - Spectrum Analyzer Submenu
    
    private static func buildSpectrumAnalyzerMenuItem() -> NSMenuItem {
        let spectrumItem = NSMenuItem(title: "Spectrum Analyzer", action: nil, keyEquivalent: "")
        spectrumItem.submenu = buildSpectrumAnalyzerMenu()
        return spectrumItem
    }

    private static func buildSpectrumAnalyzerMenu() -> NSMenu {
        let spectrumMenu = NSMenu()
        spectrumMenu.autoenablesItems = false
        
        // ---- Main Window sub-section ----
        let mainWindowItem = NSMenuItem(title: "Main Window", action: nil, keyEquivalent: "")
        mainWindowItem.submenu = buildMainVisualizationSubmenu()
        spectrumMenu.addItem(mainWindowItem)
        
        // ---- Spectrum Window sub-section ----
        let spectrumWindowItem = NSMenuItem(title: "Spectrum Window", action: nil, keyEquivalent: "")
        let spectrumWindowMenu = NSMenu()
        spectrumWindowMenu.autoenablesItems = false
        
        // Window toggle (show/hide)
        let wm = WindowManager.shared
        let toggleItem = NSMenuItem(
            title: wm.isSpectrumVisible ? "Hide Window" : "Show Window",
            action: #selector(MenuActions.toggleSpectrum),
            keyEquivalent: ""
        )
        toggleItem.target = MenuActions.shared
        spectrumWindowMenu.addItem(toggleItem)
        spectrumWindowMenu.addItem(NSMenuItem.separator())
        
        // Mode submenu
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        modeMenu.autoenablesItems = false
        
        let currentQuality = UserDefaults.standard.string(forKey: "spectrumQualityMode")
            .flatMap { SpectrumQualityMode(rawValue: $0) } ?? .classic
        
        for mode in SpectrumQualityMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(MenuActions.setSpectrumQuality(_:)), keyEquivalent: "")
            item.target = MenuActions.shared
            item.representedObject = mode
            item.state = (currentQuality == mode) ? .on : .off
            // Disable modes whose shader file is missing
            if !SpectrumAnalyzerView.isShaderAvailable(for: mode) {
                item.isEnabled = false
            }
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        spectrumWindowMenu.addItem(modeItem)
        
        // Responsiveness submenu
        let responsivenessItem = NSMenuItem(title: "Responsiveness", action: nil, keyEquivalent: "")
        let responsivenessMenu = NSMenu()
        responsivenessMenu.autoenablesItems = false
        
        let currentDecay = UserDefaults.standard.string(forKey: "spectrumDecayMode")
            .flatMap { SpectrumDecayMode(rawValue: $0) } ?? .snappy
        
        for mode in SpectrumDecayMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(MenuActions.setSpectrumResponsiveness(_:)), keyEquivalent: "")
            item.target = MenuActions.shared
            item.representedObject = mode
            item.state = (currentDecay == mode) ? .on : .off
            responsivenessMenu.addItem(item)
        }
        responsivenessItem.submenu = responsivenessMenu
        spectrumWindowMenu.addItem(responsivenessItem)
        
        // Normalization submenu
        let normItem = NSMenuItem(title: "Normalization", action: nil, keyEquivalent: "")
        let normMenu = NSMenu()
        normMenu.autoenablesItems = false
        
        let currentNorm = UserDefaults.standard.string(forKey: "spectrumNormalizationMode")
            .flatMap { SpectrumNormalizationMode(rawValue: $0) } ?? .accurate
        
        for mode in SpectrumNormalizationMode.allCases {
            let item = NSMenuItem(title: "\(mode.displayName) - \(mode.description)", action: #selector(MenuActions.setSpectrumNormalization(_:)), keyEquivalent: "")
            item.target = MenuActions.shared
            item.representedObject = mode
            item.state = (currentNorm == mode) ? .on : .off
            normMenu.addItem(item)
        }
        normItem.submenu = normMenu
        spectrumWindowMenu.addItem(normItem)
        
        // Flame Style submenu (only when Fire mode active)
        if currentQuality == .flame {
            let flameStyleItem = NSMenuItem(title: "Flame Style", action: nil, keyEquivalent: "")
            let flameStyleMenu = NSMenu()
            flameStyleMenu.autoenablesItems = false
            
            let currentStyle = UserDefaults.standard.string(forKey: "flameStyle")
                .flatMap { FlameStyle(rawValue: $0) } ?? .inferno
            
            for style in FlameStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(MenuActions.setSpectrumFlameStyle(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = style
                item.state = (currentStyle == style) ? .on : .off
                flameStyleMenu.addItem(item)
            }
            
            flameStyleItem.submenu = flameStyleMenu
            spectrumWindowMenu.addItem(flameStyleItem)
            
            // Flame Intensity submenu
            let flameIntensityItem = NSMenuItem(title: "Fire Intensity", action: nil, keyEquivalent: "")
            let flameIntensityMenu = NSMenu()
            flameIntensityMenu.autoenablesItems = false
            
            let currentIntensity = UserDefaults.standard.string(forKey: "flameIntensity")
                .flatMap { FlameIntensity(rawValue: $0) } ?? .mellow
            
            for intensity in FlameIntensity.allCases {
                let item = NSMenuItem(title: intensity.displayName, action: #selector(MenuActions.setSpectrumFlameIntensity(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = intensity
                item.state = (currentIntensity == intensity) ? .on : .off
                flameIntensityMenu.addItem(item)
            }
            
            flameIntensityItem.submenu = flameIntensityMenu
            spectrumWindowMenu.addItem(flameIntensityItem)
        }
        
        // Lightning Style submenu (only when Lightning mode active)
        if currentQuality == .electricity {
            let lightningStyleItem = NSMenuItem(title: "Lightning Style", action: nil, keyEquivalent: "")
            let lightningStyleMenu = NSMenu()
            lightningStyleMenu.autoenablesItems = false
            
            let currentStyle = UserDefaults.standard.string(forKey: "lightningStyle")
                .flatMap { LightningStyle(rawValue: $0) } ?? .classic
            
            for style in LightningStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(MenuActions.setSpectrumLightningStyle(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = style
                item.state = (currentStyle == style) ? .on : .off
                lightningStyleMenu.addItem(item)
            }
            
            lightningStyleItem.submenu = lightningStyleMenu
            spectrumWindowMenu.addItem(lightningStyleItem)
        }
        
        // Matrix sub-menus (only when Matrix mode active)
        if currentQuality == .matrix {
            // Matrix Color submenu
            let matrixColorItem = NSMenuItem(title: "Matrix Color", action: nil, keyEquivalent: "")
            let matrixColorMenu = NSMenu()
            matrixColorMenu.autoenablesItems = false
            
            let currentMatrixColor = UserDefaults.standard.string(forKey: "matrixColorScheme")
                .flatMap { MatrixColorScheme(rawValue: $0) } ?? .classic
            
            for scheme in MatrixColorScheme.allCases {
                let item = NSMenuItem(title: scheme.displayName, action: #selector(MenuActions.setSpectrumMatrixColor(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = scheme
                item.state = (currentMatrixColor == scheme) ? .on : .off
                matrixColorMenu.addItem(item)
            }
            
            matrixColorItem.submenu = matrixColorMenu
            spectrumWindowMenu.addItem(matrixColorItem)
            
            // Matrix Intensity submenu
            let matrixIntensityItem = NSMenuItem(title: "Matrix Intensity", action: nil, keyEquivalent: "")
            let matrixIntensityMenu = NSMenu()
            matrixIntensityMenu.autoenablesItems = false
            
            let currentMatrixIntensity = UserDefaults.standard.string(forKey: "matrixIntensity")
                .flatMap { MatrixIntensity(rawValue: $0) } ?? .subtle
            
            for intensity in MatrixIntensity.allCases {
                let item = NSMenuItem(title: intensity.displayName, action: #selector(MenuActions.setSpectrumMatrixIntensity(_:)), keyEquivalent: "")
                item.target = MenuActions.shared
                item.representedObject = intensity
                item.state = (currentMatrixIntensity == intensity) ? .on : .off
                matrixIntensityMenu.addItem(item)
            }
            
            matrixIntensityItem.submenu = matrixIntensityMenu
            spectrumWindowMenu.addItem(matrixIntensityItem)
        }

        // vis_classic profile controls (only when vis_classic mode active)
        if currentQuality == .visClassicExact {
            let profilesMenuItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
            let profilesMenu = NSMenu()
            profilesMenu.autoenablesItems = false

            let currentName = VisClassicBridge.lastProfileName(for: .spectrumWindow)
            let profiles = VisClassicBridge.availableProfilesCatalog()
            if profiles.isEmpty {
                let none = NSMenuItem(title: "No Profiles", action: nil, keyEquivalent: "")
                none.isEnabled = false
                profilesMenu.addItem(none)
            } else {
                for entry in profiles {
                    let item = NSMenuItem(title: entry.name, action: #selector(MenuActions.loadVisClassicProfile(_:)), keyEquivalent: "")
                    item.target = MenuActions.shared
                    item.representedObject = entry.name
                    item.state = (entry.name == currentName) ? .on : .off
                    profilesMenu.addItem(item)
                }
            }

            profilesMenuItem.submenu = profilesMenu
            spectrumWindowMenu.addItem(profilesMenuItem)
            spectrumWindowMenu.addItem(NSMenuItem.separator())

            let fitEnabled = VisClassicBridge.fitToWidthDefault(for: .spectrumWindow)
            let fitItem = NSMenuItem(title: "Fit to Width", action: #selector(MenuActions.toggleVisClassicFitToWidth), keyEquivalent: "")
            fitItem.target = MenuActions.shared
            fitItem.state = fitEnabled ? .on : .off
            spectrumWindowMenu.addItem(fitItem)

            let transparentEnabled = VisClassicBridge.transparentBgDefault(for: .spectrumWindow)
            let transparentItem = NSMenuItem(title: "Transparent Background", action: #selector(MenuActions.toggleVisClassicTransparentBg), keyEquivalent: "")
            transparentItem.target = MenuActions.shared
            transparentItem.state = transparentEnabled ? .on : .off
            spectrumWindowMenu.addItem(transparentItem)

            let nextItem = NSMenuItem(title: "Next Profile", action: #selector(MenuActions.nextVisClassicProfile), keyEquivalent: "")
            nextItem.target = MenuActions.shared
            spectrumWindowMenu.addItem(nextItem)

            let prevItem = NSMenuItem(title: "Previous Profile", action: #selector(MenuActions.previousVisClassicProfile), keyEquivalent: "")
            prevItem.target = MenuActions.shared
            spectrumWindowMenu.addItem(prevItem)

            let importItem = NSMenuItem(title: "Import INI...", action: #selector(MenuActions.importVisClassicProfile), keyEquivalent: "")
            importItem.target = MenuActions.shared
            spectrumWindowMenu.addItem(importItem)

            let exportItem = NSMenuItem(title: "Export Current INI...", action: #selector(MenuActions.exportVisClassicProfile), keyEquivalent: "")
            exportItem.target = MenuActions.shared
            spectrumWindowMenu.addItem(exportItem)
        }
        
        spectrumWindowItem.submenu = spectrumWindowMenu
        spectrumMenu.addItem(spectrumWindowItem)
        
        return spectrumMenu
    }

    static func buildWaveformWindowContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let rerender = NSMenuItem(title: "Re-render Waveform", action: #selector(MenuActions.rerenderCurrentWaveform), keyEquivalent: "")
        rerender.target = MenuActions.shared
        menu.addItem(rerender)

        let clearCache = NSMenuItem(title: "Clear Cached Waveform", action: #selector(MenuActions.clearCurrentWaveformCache), keyEquivalent: "")
        clearCache.target = MenuActions.shared
        menu.addItem(clearCache)

        menu.addItem(NSMenuItem.separator())

        let cuePoints = NSMenuItem(title: "Show CUE Points", action: #selector(MenuActions.toggleWaveformCuePoints), keyEquivalent: "")
        cuePoints.target = MenuActions.shared
        cuePoints.state = UserDefaults.standard.bool(forKey: "waveformShowCuePoints") ? .on : .off
        menu.addItem(cuePoints)

        let transparentBackground = NSMenuItem(title: "Transparent Background", action: #selector(MenuActions.toggleWaveformTransparentBackground), keyEquivalent: "")
        transparentBackground.target = MenuActions.shared
        transparentBackground.state = WindowManager.shared.isWaveformTransparentBackgroundEnabled() ? .on : .off
        menu.addItem(transparentBackground)

        let hideTooltip = NSMenuItem(title: "Hide Waveform Tooltip", action: #selector(MenuActions.toggleWaveformTooltip), keyEquivalent: "")
        hideTooltip.target = MenuActions.shared
        hideTooltip.state = UserDefaults.standard.bool(forKey: "waveformHideTooltip") ? .on : .off
        menu.addItem(hideTooltip)

        return menu
    }
    
    // MARK: - Libraries Submenu

    private static func buildLibrariesMenu() -> NSMenu {
        let librariesMenu = NSMenu()
        librariesMenu.addItem(buildLocalLibraryMenuItem())
        librariesMenu.addItem(buildPlexMenuItem())
        librariesMenu.addItem(buildSubsonicMenuItem())
        librariesMenu.addItem(buildJellyfinMenuItem())
        librariesMenu.addItem(buildEmbyMenuItem())
        return librariesMenu
    }

    // MARK: - Local Library Submenu

    private static func buildLocalLibraryMenuItem() -> NSMenuItem {
        let libraryItem = NSMenuItem(title: "Local Library", action: nil, keyEquivalent: "")
        let libraryMenu = NSMenu()
        libraryMenu.autoenablesItems = false
        
        let store = MediaLibraryStore.shared
        let trackCount = store.trackCount()
        let movieCount = store.movieCount()
        let episodeCount = store.episodeCount()
        let totalLocalItems = trackCount + movieCount + episodeCount
        
        // Library info header
        let infoItem = NSMenuItem(
            title: "\(totalLocalItems) items (\(trackCount) tracks, \(movieCount) movies, \(episodeCount) episodes)",
            action: nil,
            keyEquivalent: ""
        )
        libraryMenu.addItem(infoItem)
        
        libraryMenu.addItem(NSMenuItem.separator())
        
        // Backup Library
        let backupItem = NSMenuItem(title: "Backup Library...", action: #selector(MenuActions.backupLibrary), keyEquivalent: "")
        backupItem.target = MenuActions.shared
        libraryMenu.addItem(backupItem)
        
        // Restore Library submenu
        let restoreItem = NSMenuItem(title: "Restore Library", action: nil, keyEquivalent: "")
        let restoreMenu = NSMenu()
        restoreMenu.autoenablesItems = false
        
        // Restore from File option
        let restoreFromFile = NSMenuItem(title: "From File...", action: #selector(MenuActions.restoreLibraryFromFile), keyEquivalent: "")
        restoreFromFile.target = MenuActions.shared
        restoreMenu.addItem(restoreFromFile)
        
        // List available backups
        let backups = MediaLibrary.shared.listBackups()
        if !backups.isEmpty {
            restoreMenu.addItem(NSMenuItem.separator())
            
            let backupsHeader = NSMenuItem(title: "Recent Backups", action: nil, keyEquivalent: "")
            restoreMenu.addItem(backupsHeader)
            
            // Show up to 10 most recent backups
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            
            for backup in backups.prefix(10) {
                let creationDate = (try? backup.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                let dateString = creationDate.map { dateFormatter.string(from: $0) } ?? "Unknown date"
                let backupName = backup.deletingPathExtension().lastPathComponent
                
                let backupMenuItem = NSMenuItem(title: "\(backupName) (\(dateString))", action: #selector(MenuActions.restoreLibraryFromBackup(_:)), keyEquivalent: "")
                backupMenuItem.target = MenuActions.shared
                backupMenuItem.representedObject = backup
                restoreMenu.addItem(backupMenuItem)
            }
        }
        
        restoreItem.submenu = restoreMenu
        libraryMenu.addItem(restoreItem)
        
        libraryMenu.addItem(NSMenuItem.separator())
        
        // Show Library Location
        let showLibraryItem = NSMenuItem(title: "Show Library in Finder", action: #selector(MenuActions.showLibraryInFinder), keyEquivalent: "")
        showLibraryItem.target = MenuActions.shared
        libraryMenu.addItem(showLibraryItem)
        
        // Show Backups Folder
        let showBackupsItem = NSMenuItem(title: "Show Backups Folder", action: #selector(MenuActions.showBackupsInFinder), keyEquivalent: "")
        showBackupsItem.target = MenuActions.shared
        libraryMenu.addItem(showBackupsItem)
        
        libraryMenu.addItem(NSMenuItem.separator())

        // Manage Watch Folders
        let manageFoldersItem = NSMenuItem(title: "Manage Folders...", action: #selector(MenuActions.manageFolders), keyEquivalent: "")
        manageFoldersItem.target = MenuActions.shared
        libraryMenu.addItem(manageFoldersItem)

        libraryMenu.addItem(NSMenuItem.separator())

        // Clear Library submenu (with confirmations)
        let clearItem = NSMenuItem(title: "Clear...", action: nil, keyEquivalent: "")
        let clearMenu = NSMenu()
        clearMenu.autoenablesItems = false

        let clearMusicItem = NSMenuItem(title: "Clear Music...", action: #selector(MenuActions.clearLocalMusic), keyEquivalent: "")
        clearMusicItem.target = MenuActions.shared
        clearMusicItem.isEnabled = trackCount > 0
        clearMenu.addItem(clearMusicItem)

        let clearMoviesItem = NSMenuItem(title: "Clear Movies...", action: #selector(MenuActions.clearLocalMovies), keyEquivalent: "")
        clearMoviesItem.target = MenuActions.shared
        clearMoviesItem.isEnabled = movieCount > 0
        clearMenu.addItem(clearMoviesItem)

        let clearTVItem = NSMenuItem(title: "Clear TV...", action: #selector(MenuActions.clearLocalTV), keyEquivalent: "")
        clearTVItem.target = MenuActions.shared
        clearTVItem.isEnabled = episodeCount > 0
        clearMenu.addItem(clearTVItem)

        clearMenu.addItem(NSMenuItem.separator())

        let clearAllItem = NSMenuItem(title: "Clear Everything...", action: #selector(MenuActions.clearLibrary), keyEquivalent: "")
        clearAllItem.target = MenuActions.shared
        clearAllItem.isEnabled = totalLocalItems > 0
        clearMenu.addItem(clearAllItem)

        clearItem.submenu = clearMenu
        libraryMenu.addItem(clearItem)
        
        libraryItem.submenu = libraryMenu
        return libraryItem
    }
    
    // MARK: - Plex Submenu
    
    private static func buildPlexMenuItem() -> NSMenuItem {
        let plexItem = NSMenuItem(title: "Plex", action: nil, keyEquivalent: "")
        let plexMenu = NSMenu()
        plexMenu.autoenablesItems = false
        
        let isLinked = PlexManager.shared.isLinked
        
        // Link/Unlink account
        if isLinked {
            let accountName = PlexManager.shared.account?.username ?? "Account"
            let accountItem = NSMenuItem(title: "✓ \(accountName)", action: nil, keyEquivalent: "")
            plexMenu.addItem(accountItem)
            
            let unlinkItem = NSMenuItem(title: "Unlink Account", action: #selector(MenuActions.unlinkPlexAccount), keyEquivalent: "")
            unlinkItem.target = MenuActions.shared
            plexMenu.addItem(unlinkItem)
        } else {
            let linkItem = NSMenuItem(title: "Link Plex Account...", action: #selector(MenuActions.linkPlexAccount), keyEquivalent: "")
            linkItem.target = MenuActions.shared
            plexMenu.addItem(linkItem)
        }
        
        plexMenu.addItem(NSMenuItem.separator())
        
        // Servers submenu (if linked)
        if isLinked && !PlexManager.shared.servers.isEmpty {
            let serversItem = NSMenuItem(title: "Servers", action: nil, keyEquivalent: "")
            let serversMenu = NSMenu()
            serversMenu.autoenablesItems = false
            
            for server in PlexManager.shared.servers {
                let serverItem = NSMenuItem(title: server.name, action: #selector(MenuActions.selectPlexServer(_:)), keyEquivalent: "")
                serverItem.target = MenuActions.shared
                serverItem.representedObject = server.id
                serverItem.state = server.id == PlexManager.shared.currentServer?.id ? .on : .off
                serversMenu.addItem(serverItem)
            }
            
            serversItem.submenu = serversMenu
            plexMenu.addItem(serversItem)
            
            // Libraries submenu
            if !PlexManager.shared.availableLibraries.isEmpty {
                let librariesItem = NSMenuItem(title: "Libraries", action: nil, keyEquivalent: "")
                let librariesMenu = NSMenu()
                librariesMenu.autoenablesItems = false
                
                for library in PlexManager.shared.availableLibraries {
                    let libraryItem = NSMenuItem(title: library.title, action: #selector(MenuActions.selectPlexLibrary(_:)), keyEquivalent: "")
                    libraryItem.target = MenuActions.shared
                    libraryItem.representedObject = library.id
                    libraryItem.state = library.id == PlexManager.shared.currentLibrary?.id ? .on : .off
                    librariesMenu.addItem(libraryItem)
                }
                
                librariesItem.submenu = librariesMenu
                plexMenu.addItem(librariesItem)
            }
            
            plexMenu.addItem(NSMenuItem.separator())
        }
        
        // Refresh Servers (if linked but no servers showing)
        if isLinked {
            let refreshItem = NSMenuItem(title: "Refresh Servers", action: #selector(MenuActions.refreshPlexServers), keyEquivalent: "")
            refreshItem.target = MenuActions.shared
            plexMenu.addItem(refreshItem)
            
            plexMenu.addItem(NSMenuItem.separator())
        }
        
        // Show Plex Browser
        let browserItem = NSMenuItem(title: "Show Plex Browser", action: #selector(MenuActions.togglePlexBrowser), keyEquivalent: "")
        browserItem.target = MenuActions.shared
        browserItem.state = WindowManager.shared.isPlexBrowserVisible ? .on : .off
        browserItem.isEnabled = isLinked
        plexMenu.addItem(browserItem)
        
        plexItem.submenu = plexMenu
        return plexItem
    }
    
    // MARK: - Subsonic Submenu
    
    private static func buildSubsonicMenuItem() -> NSMenuItem {
        let subsonicItem = NSMenuItem(title: "Navidrome/Subsonic", action: nil, keyEquivalent: "")
        let subsonicMenu = NSMenu()
        subsonicMenu.autoenablesItems = false
        
        let servers = SubsonicManager.shared.servers
        let currentServer = SubsonicManager.shared.currentServer
        
        // Add Server / Manage Servers
        if servers.isEmpty {
            let addItem = NSMenuItem(title: "Add Server...", action: #selector(MenuActions.addSubsonicServer), keyEquivalent: "")
            addItem.target = MenuActions.shared
            subsonicMenu.addItem(addItem)
        } else {
            // Connection status
            switch SubsonicManager.shared.connectionState {
            case .connected:
                if let server = currentServer {
                    let statusItem = NSMenuItem(title: "✓ Connected to \(server.name)", action: nil, keyEquivalent: "")
                    subsonicMenu.addItem(statusItem)
                }
            case .connecting:
                let statusItem = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
                subsonicMenu.addItem(statusItem)
            case .error:
                let statusItem = NSMenuItem(title: "⚠ Connection Error", action: nil, keyEquivalent: "")
                subsonicMenu.addItem(statusItem)
            case .disconnected:
                let statusItem = NSMenuItem(title: "Not Connected", action: nil, keyEquivalent: "")
                subsonicMenu.addItem(statusItem)
            }
            
            subsonicMenu.addItem(NSMenuItem.separator())
            
            // Servers submenu
            let serversItem = NSMenuItem(title: "Servers", action: nil, keyEquivalent: "")
            let serversMenu = NSMenu()
            serversMenu.autoenablesItems = false
            
            for server in servers {
                let serverItem = NSMenuItem(title: server.name, action: #selector(MenuActions.selectSubsonicServer(_:)), keyEquivalent: "")
                serverItem.target = MenuActions.shared
                serverItem.representedObject = server.id
                serverItem.state = server.id == currentServer?.id ? .on : .off
                serversMenu.addItem(serverItem)
            }
            
            serversMenu.addItem(NSMenuItem.separator())
            
            let addServerItem = NSMenuItem(title: "Add Server...", action: #selector(MenuActions.addSubsonicServer), keyEquivalent: "")
            addServerItem.target = MenuActions.shared
            serversMenu.addItem(addServerItem)
            
            let manageItem = NSMenuItem(title: "Manage Servers...", action: #selector(MenuActions.manageSubsonicServers), keyEquivalent: "")
            manageItem.target = MenuActions.shared
            serversMenu.addItem(manageItem)
            
            serversItem.submenu = serversMenu
            subsonicMenu.addItem(serversItem)
            
            subsonicMenu.addItem(NSMenuItem.separator())
            
            // Disconnect option (if connected)
            if currentServer != nil {
                let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(MenuActions.disconnectSubsonic), keyEquivalent: "")
                disconnectItem.target = MenuActions.shared
                subsonicMenu.addItem(disconnectItem)
                
                subsonicMenu.addItem(NSMenuItem.separator())
            }
        }
        
        // Music folders submenu (if more than one folder)
        let musicFolders = SubsonicManager.shared.musicFolders
        if musicFolders.count > 1 {
            let foldersItem = NSMenuItem(title: "Music Folders", action: nil, keyEquivalent: "")
            let foldersMenu = NSMenu()
            foldersMenu.autoenablesItems = false
            
            let allItem = NSMenuItem(title: "All Folders", action: #selector(MenuActions.selectSubsonicMusicFolder(_:)), keyEquivalent: "")
            allItem.target = MenuActions.shared
            allItem.representedObject = Optional<String>.none as Any
            allItem.state = SubsonicManager.shared.currentMusicFolder == nil ? .on : .off
            foldersMenu.addItem(allItem)
            foldersMenu.addItem(NSMenuItem.separator())
            
            for folder in musicFolders {
                let folderItem = NSMenuItem(title: folder.name, action: #selector(MenuActions.selectSubsonicMusicFolder(_:)), keyEquivalent: "")
                folderItem.target = MenuActions.shared
                folderItem.representedObject = folder.id
                folderItem.state = folder.id == SubsonicManager.shared.currentMusicFolder?.id ? .on : .off
                foldersMenu.addItem(folderItem)
            }
            
            foldersItem.submenu = foldersMenu
            subsonicMenu.addItem(foldersItem)
            
            subsonicMenu.addItem(NSMenuItem.separator())
        }
        
        // Refresh Library
        let refreshItem = NSMenuItem(title: "Refresh Library", action: #selector(MenuActions.refreshSubsonicLibrary), keyEquivalent: "")
        refreshItem.target = MenuActions.shared
        refreshItem.isEnabled = currentServer != nil
        subsonicMenu.addItem(refreshItem)
        
        // Show in Browser
        let browserItem = NSMenuItem(title: "Show in Library Browser", action: #selector(MenuActions.showSubsonicInBrowser), keyEquivalent: "")
        browserItem.target = MenuActions.shared
        browserItem.isEnabled = currentServer != nil
        subsonicMenu.addItem(browserItem)
        
        subsonicItem.submenu = subsonicMenu
        return subsonicItem
    }
    
    // MARK: - Jellyfin Submenu
    
    private static func buildJellyfinMenuItem() -> NSMenuItem {
        let jellyfinItem = NSMenuItem(title: "Jellyfin", action: nil, keyEquivalent: "")
        let jellyfinMenu = NSMenu()
        jellyfinMenu.autoenablesItems = false
        
        let servers = JellyfinManager.shared.servers
        let currentServer = JellyfinManager.shared.currentServer
        
        // Add Server / Manage Servers
        if servers.isEmpty {
            let addItem = NSMenuItem(title: "Add Server...", action: #selector(MenuActions.addJellyfinServer), keyEquivalent: "")
            addItem.target = MenuActions.shared
            jellyfinMenu.addItem(addItem)
        } else {
            // Connection status
            switch JellyfinManager.shared.connectionState {
            case .connected:
                if let server = currentServer {
                    let statusItem = NSMenuItem(title: "✓ Connected to \(server.name)", action: nil, keyEquivalent: "")
                    jellyfinMenu.addItem(statusItem)
                }
            case .connecting:
                let statusItem = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
                jellyfinMenu.addItem(statusItem)
            case .error:
                let statusItem = NSMenuItem(title: "⚠ Connection Error", action: nil, keyEquivalent: "")
                jellyfinMenu.addItem(statusItem)
            case .disconnected:
                let statusItem = NSMenuItem(title: "Not Connected", action: nil, keyEquivalent: "")
                jellyfinMenu.addItem(statusItem)
            }
            
            jellyfinMenu.addItem(NSMenuItem.separator())
            
            // Servers submenu
            let serversItem = NSMenuItem(title: "Servers", action: nil, keyEquivalent: "")
            let serversMenu = NSMenu()
            serversMenu.autoenablesItems = false
            
            for server in servers {
                let serverItem = NSMenuItem(title: server.name, action: #selector(MenuActions.selectJellyfinServer(_:)), keyEquivalent: "")
                serverItem.target = MenuActions.shared
                serverItem.representedObject = server.id
                serverItem.state = server.id == currentServer?.id ? .on : .off
                serversMenu.addItem(serverItem)
            }
            
            serversMenu.addItem(NSMenuItem.separator())
            
            let addServerItem = NSMenuItem(title: "Add Server...", action: #selector(MenuActions.addJellyfinServer), keyEquivalent: "")
            addServerItem.target = MenuActions.shared
            serversMenu.addItem(addServerItem)
            
            let manageItem = NSMenuItem(title: "Manage Servers...", action: #selector(MenuActions.manageJellyfinServers), keyEquivalent: "")
            manageItem.target = MenuActions.shared
            serversMenu.addItem(manageItem)
            
            serversItem.submenu = serversMenu
            jellyfinMenu.addItem(serversItem)
            
            jellyfinMenu.addItem(NSMenuItem.separator())
            
            // Disconnect option (if connected)
            if currentServer != nil {
                let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(MenuActions.disconnectJellyfin), keyEquivalent: "")
                disconnectItem.target = MenuActions.shared
                jellyfinMenu.addItem(disconnectItem)
                
                jellyfinMenu.addItem(NSMenuItem.separator())
            }
        }
        
        // Music libraries submenu (if more than one music library)
        let musicLibs = JellyfinManager.shared.musicLibraries
        if musicLibs.count > 1 {
            let musicLibItem = NSMenuItem(title: "Music Libraries", action: nil, keyEquivalent: "")
            let musicLibMenu = NSMenu()
            musicLibMenu.autoenablesItems = false
            
            let allItem = NSMenuItem(title: "All Libraries", action: #selector(MenuActions.selectJellyfinMusicLibrary(_:)), keyEquivalent: "")
            allItem.target = MenuActions.shared
            allItem.representedObject = Optional<String>.none as Any
            allItem.state = JellyfinManager.shared.currentMusicLibrary == nil ? .on : .off
            musicLibMenu.addItem(allItem)
            musicLibMenu.addItem(NSMenuItem.separator())
            
            for lib in musicLibs {
                let libItem = NSMenuItem(title: "\(lib.name) (Music)", action: #selector(MenuActions.selectJellyfinMusicLibrary(_:)), keyEquivalent: "")
                libItem.target = MenuActions.shared
                libItem.representedObject = lib.id
                libItem.state = lib.id == JellyfinManager.shared.currentMusicLibrary?.id ? .on : .off
                musicLibMenu.addItem(libItem)
            }
            
            musicLibItem.submenu = musicLibMenu
            jellyfinMenu.addItem(musicLibItem)
            
            jellyfinMenu.addItem(NSMenuItem.separator())
        }
        
        // Video libraries submenu (if multiple video libraries)
        let videoLibs = JellyfinManager.shared.videoLibraries
        if videoLibs.count > 1 {
            let videoLibItem = NSMenuItem(title: "Video Libraries", action: nil, keyEquivalent: "")
            let videoLibMenu = NSMenu()
            videoLibMenu.autoenablesItems = false
            
            for lib in videoLibs {
                let libItem = NSMenuItem(title: lib.name, action: #selector(MenuActions.selectJellyfinVideoLibrary(_:)), keyEquivalent: "")
                libItem.target = MenuActions.shared
                libItem.representedObject = lib.id
                let isMovieLib = lib.id == JellyfinManager.shared.currentMovieLibrary?.id
                let isShowLib = lib.id == JellyfinManager.shared.currentShowLibrary?.id
                libItem.state = (isMovieLib || isShowLib) ? .on : .off
                videoLibMenu.addItem(libItem)
            }
            
            videoLibItem.submenu = videoLibMenu
            jellyfinMenu.addItem(videoLibItem)
            
            jellyfinMenu.addItem(NSMenuItem.separator())
        }
        
        // Refresh Library
        let refreshItem = NSMenuItem(title: "Refresh Library", action: #selector(MenuActions.refreshJellyfinLibrary), keyEquivalent: "")
        refreshItem.target = MenuActions.shared
        refreshItem.isEnabled = currentServer != nil
        jellyfinMenu.addItem(refreshItem)
        
        // Show in Browser
        let browserItem = NSMenuItem(title: "Show in Library Browser", action: #selector(MenuActions.showJellyfinInBrowser), keyEquivalent: "")
        browserItem.target = MenuActions.shared
        browserItem.isEnabled = currentServer != nil
        jellyfinMenu.addItem(browserItem)
        
        jellyfinItem.submenu = jellyfinMenu
        return jellyfinItem
    }

    // MARK: - Emby Submenu

    private static func buildEmbyMenuItem() -> NSMenuItem {
        let embyItem = NSMenuItem(title: "Emby", action: nil, keyEquivalent: "")
        let embyMenu = NSMenu()
        embyMenu.autoenablesItems = false

        let servers = EmbyManager.shared.servers
        let currentServer = EmbyManager.shared.currentServer

        // Add Server / Manage Servers
        if servers.isEmpty {
            let addItem = NSMenuItem(title: "Add Server...", action: #selector(MenuActions.addEmbyServer), keyEquivalent: "")
            addItem.target = MenuActions.shared
            embyMenu.addItem(addItem)
        } else {
            // Connection status
            switch EmbyManager.shared.connectionState {
            case .connected:
                if let server = currentServer {
                    let statusItem = NSMenuItem(title: "✓ Connected to \(server.name)", action: nil, keyEquivalent: "")
                    embyMenu.addItem(statusItem)
                }
            case .connecting:
                let statusItem = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
                embyMenu.addItem(statusItem)
            case .error:
                let statusItem = NSMenuItem(title: "⚠ Connection Error", action: nil, keyEquivalent: "")
                embyMenu.addItem(statusItem)
            case .disconnected:
                let statusItem = NSMenuItem(title: "Not Connected", action: nil, keyEquivalent: "")
                embyMenu.addItem(statusItem)
            }

            embyMenu.addItem(NSMenuItem.separator())

            // Servers submenu
            let serversItem = NSMenuItem(title: "Servers", action: nil, keyEquivalent: "")
            let serversMenu = NSMenu()
            serversMenu.autoenablesItems = false

            for server in servers {
                let serverItem = NSMenuItem(title: server.name, action: #selector(MenuActions.selectEmbyServer(_:)), keyEquivalent: "")
                serverItem.target = MenuActions.shared
                serverItem.representedObject = server.id
                serverItem.state = server.id == currentServer?.id ? .on : .off
                serversMenu.addItem(serverItem)
            }

            serversMenu.addItem(NSMenuItem.separator())

            let addServerItem = NSMenuItem(title: "Add Server...", action: #selector(MenuActions.addEmbyServer), keyEquivalent: "")
            addServerItem.target = MenuActions.shared
            serversMenu.addItem(addServerItem)

            let manageItem = NSMenuItem(title: "Manage Servers...", action: #selector(MenuActions.manageEmbyServers), keyEquivalent: "")
            manageItem.target = MenuActions.shared
            serversMenu.addItem(manageItem)

            serversItem.submenu = serversMenu
            embyMenu.addItem(serversItem)

            embyMenu.addItem(NSMenuItem.separator())

            // Disconnect option (if connected)
            if currentServer != nil {
                let disconnectItem = NSMenuItem(title: "Disconnect", action: #selector(MenuActions.disconnectEmby), keyEquivalent: "")
                disconnectItem.target = MenuActions.shared
                embyMenu.addItem(disconnectItem)

                embyMenu.addItem(NSMenuItem.separator())
            }
        }

        // Music libraries submenu (if more than one music library)
        let musicLibs = EmbyManager.shared.musicLibraries
        if musicLibs.count > 1 {
            let musicLibItem = NSMenuItem(title: "Music Libraries", action: nil, keyEquivalent: "")
            let musicLibMenu = NSMenu()
            musicLibMenu.autoenablesItems = false

            let allItem = NSMenuItem(title: "All Libraries", action: #selector(MenuActions.selectEmbyMusicLibrary(_:)), keyEquivalent: "")
            allItem.target = MenuActions.shared
            allItem.representedObject = Optional<String>.none as Any
            allItem.state = EmbyManager.shared.currentMusicLibrary == nil ? .on : .off
            musicLibMenu.addItem(allItem)
            musicLibMenu.addItem(NSMenuItem.separator())

            for lib in musicLibs {
                let libItem = NSMenuItem(title: "\(lib.name) (Music)", action: #selector(MenuActions.selectEmbyMusicLibrary(_:)), keyEquivalent: "")
                libItem.target = MenuActions.shared
                libItem.representedObject = lib.id
                libItem.state = lib.id == EmbyManager.shared.currentMusicLibrary?.id ? .on : .off
                musicLibMenu.addItem(libItem)
            }

            musicLibItem.submenu = musicLibMenu
            embyMenu.addItem(musicLibItem)

            embyMenu.addItem(NSMenuItem.separator())
        }

        // Video libraries submenu (if multiple video libraries)
        let videoLibs = EmbyManager.shared.videoLibraries
        if videoLibs.count > 1 {
            let videoLibItem = NSMenuItem(title: "Video Libraries", action: nil, keyEquivalent: "")
            let videoLibMenu = NSMenu()
            videoLibMenu.autoenablesItems = false

            for lib in videoLibs {
                let libItem = NSMenuItem(title: lib.name, action: #selector(MenuActions.selectEmbyVideoLibrary(_:)), keyEquivalent: "")
                libItem.target = MenuActions.shared
                libItem.representedObject = lib.id
                let isMovieLib = lib.id == EmbyManager.shared.currentMovieLibrary?.id
                let isShowLib = lib.id == EmbyManager.shared.currentShowLibrary?.id
                libItem.state = (isMovieLib || isShowLib) ? .on : .off
                videoLibMenu.addItem(libItem)
            }

            videoLibItem.submenu = videoLibMenu
            embyMenu.addItem(videoLibItem)

            embyMenu.addItem(NSMenuItem.separator())
        }

        // Refresh Library
        let refreshItem = NSMenuItem(title: "Refresh Library", action: #selector(MenuActions.refreshEmbyLibrary), keyEquivalent: "")
        refreshItem.target = MenuActions.shared
        refreshItem.isEnabled = currentServer != nil
        embyMenu.addItem(refreshItem)

        // Show in Browser
        let browserItem = NSMenuItem(title: "Show in Library Browser", action: #selector(MenuActions.showEmbyInBrowser), keyEquivalent: "")
        browserItem.target = MenuActions.shared
        browserItem.isEnabled = currentServer != nil
        embyMenu.addItem(browserItem)

        embyItem.submenu = embyMenu
        return embyItem
    }

    // MARK: - Output Devices Submenu (Unified)
    
    /// Public access to the output devices menu (used by modern skin CAST button)
    static func buildOutputDevicesMenu() -> NSMenu {
        let item = buildOutputDevicesMenuItem()
        return item.submenu ?? NSMenu()
    }

    private static func buildMenuBarOutputDevicesMenu() -> NSMenu {
        let outputMenu = NSMenu()
        outputMenu.autoenablesItems = false

        let audioManager = AudioOutputManager.shared
        let castManager = CastManager.shared
        let coreAudioDevices = audioManager.outputDevices
        let airPlayDevices = audioManager.discoveredAirPlayDevices
        let currentDeviceID = WindowManager.shared.audioEngine.currentOutputDeviceID

        // Local Audio
        outputMenu.addItem(NSMenuItem(title: "Local Audio", action: nil, keyEquivalent: ""))

        let defaultItem = NSMenuItem(title: "System Default", action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
        defaultItem.target = MenuActions.shared
        defaultItem.representedObject = nil as AudioDeviceID?
        defaultItem.state = currentDeviceID == nil ? .on : .off
        outputMenu.addItem(defaultItem)

        let localDevices = coreAudioDevices.filter { !$0.isWireless }
        for device in localDevices {
            let deviceItem = NSMenuItem(title: device.name, action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
            deviceItem.target = MenuActions.shared
            deviceItem.representedObject = device.id
            deviceItem.state = currentDeviceID == device.id ? .on : .off
            outputMenu.addItem(deviceItem)
        }

        // AirPlay
        let coreAudioWireless = coreAudioDevices.filter { $0.isWireless }
        if !coreAudioWireless.isEmpty || !airPlayDevices.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())

            let airPlayItem = NSMenuItem(title: "AirPlay", action: nil, keyEquivalent: "")
            let airPlayMenu = NSMenu()
            airPlayMenu.autoenablesItems = false

            if !coreAudioWireless.isEmpty {
                airPlayMenu.addItem(NSMenuItem(title: "Connected", action: nil, keyEquivalent: ""))
                for device in coreAudioWireless {
                    let deviceItem = NSMenuItem(title: device.name, action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
                    deviceItem.target = MenuActions.shared
                    deviceItem.representedObject = device.id
                    deviceItem.state = currentDeviceID == device.id ? .on : .off
                    airPlayMenu.addItem(deviceItem)
                }
            }

            if !airPlayDevices.isEmpty {
                if !coreAudioWireless.isEmpty {
                    airPlayMenu.addItem(NSMenuItem.separator())
                }

                airPlayMenu.addItem(NSMenuItem(title: "Available (Connect in Sound Settings)", action: nil, keyEquivalent: ""))
                for device in airPlayDevices {
                    let deviceItem = NSMenuItem(title: device.name, action: #selector(MenuActions.selectAirPlayDevice(_:)), keyEquivalent: "")
                    deviceItem.target = MenuActions.shared
                    deviceItem.representedObject = device.name
                    airPlayMenu.addItem(deviceItem)
                }
            }

            airPlayMenu.addItem(NSMenuItem.separator())
            let settingsItem = NSMenuItem(title: "Sound Settings...", action: #selector(MenuActions.openSoundSettings), keyEquivalent: "")
            settingsItem.target = MenuActions.shared
            airPlayMenu.addItem(settingsItem)

            airPlayItem.submenu = airPlayMenu
            outputMenu.addItem(airPlayItem)
        }

        // Sonos
        let sonosRooms = castManager.sonosRooms
        if !sonosRooms.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())

            let sonosItem = NSMenuItem(title: "Sonos", action: nil, keyEquivalent: "")
            let sonosMenu = NSMenu()
            sonosMenu.autoenablesItems = false

            let castTargetUDN = castManager.activeSession?.device.id
            let isCastingToSonos = castManager.activeSession?.device.type == .sonos

            for room in sonosRooms {
                let isChecked: Bool
                if isCastingToSonos, let targetUDN = castTargetUDN {
                    if room.id == targetUDN {
                        isChecked = true
                    } else if room.groupCoordinatorUDN == targetUDN {
                        isChecked = true
                    } else if room.isGroupCoordinator {
                        let targetRoom = sonosRooms.first { $0.id == targetUDN }
                        isChecked = targetRoom?.groupCoordinatorUDN == room.id
                    } else {
                        isChecked = false
                    }
                } else {
                    isChecked = castManager.selectedSonosRooms.contains(room.id)
                }

                let toggleInfo = SonosRoomToggle(
                    roomUDN: room.id,
                    roomName: room.name,
                    coordinatorUDN: castTargetUDN ?? room.groupCoordinatorUDN ?? sonosRooms.first?.id ?? "",
                    coordinatorName: room.groupCoordinatorName ?? sonosRooms.first?.name ?? "",
                    isCurrentlyInGroup: isChecked,
                    isCoordinator: room.id == castTargetUDN
                )

                // Match the context menu behavior: toggling a room keeps the Sonos submenu open.
                let roomItem = NSMenuItem()
                roomItem.view = SonosRoomCheckboxView(info: toggleInfo, isChecked: isChecked, menu: sonosMenu)
                sonosMenu.addItem(roomItem)
            }

            sonosMenu.addItem(NSMenuItem.separator())

            if isCastingToSonos {
                let stopItem = NSMenuItem(title: "🔴 Stop Casting", action: #selector(MenuActions.stopCasting), keyEquivalent: "")
                stopItem.target = MenuActions.shared
                sonosMenu.addItem(stopItem)
            } else {
                let castItem = NSMenuItem(title: "🟢 Start Casting", action: #selector(MenuActions.castToSonosRoom(_:)), keyEquivalent: "")
                castItem.target = MenuActions.shared
                sonosMenu.addItem(castItem)
            }

            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(MenuActions.refreshSonosRooms), keyEquivalent: "")
            refreshItem.target = MenuActions.shared
            sonosMenu.addItem(refreshItem)

            sonosItem.submenu = sonosMenu
            outputMenu.addItem(sonosItem)
        }

        // Other cast devices
        let activeSession = castManager.activeSession

        if !castManager.chromecastDevices.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())
            outputMenu.addItem(NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: ""))

            for device in castManager.chromecastDevices {
                let deviceItem = NSMenuItem(title: device.name, action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device
                deviceItem.state = activeSession?.device.id == device.id ? .on : .off
                outputMenu.addItem(deviceItem)
            }
        }

        if !castManager.dlnaTVDevices.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())
            outputMenu.addItem(NSMenuItem(title: "TVs (DLNA)", action: nil, keyEquivalent: ""))

            for device in castManager.dlnaTVDevices {
                let displayName = device.manufacturer != nil ? "\(device.name) [\(device.manufacturer!)]" : device.name
                let deviceItem = NSMenuItem(title: displayName, action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device
                deviceItem.state = activeSession?.device.id == device.id ? .on : .off
                outputMenu.addItem(deviceItem)
            }
        }

        if !castManager.chromecastDevices.isEmpty || !castManager.dlnaTVDevices.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())

            if let activeDevice = activeSession?.device {
                let activeItem = NSMenuItem(title: "Stop Casting to \(activeDevice.name)", action: #selector(MenuActions.stopCasting), keyEquivalent: "")
                activeItem.target = MenuActions.shared
                outputMenu.addItem(activeItem)
            }

            let refreshCastItem = NSMenuItem(title: "Refresh Cast Devices", action: #selector(MenuActions.refreshCastDevices), keyEquivalent: "")
            refreshCastItem.target = MenuActions.shared
            outputMenu.addItem(refreshCastItem)
        }

        return outputMenu
    }
    
    private static func buildOutputDevicesMenuItem() -> NSMenuItem {
        let outputItem = NSMenuItem(title: "Output Devices", action: nil, keyEquivalent: "")
        let outputMenu = NSMenu()
        outputMenu.autoenablesItems = false
        
        let audioManager = AudioOutputManager.shared
        let castManager = CastManager.shared
        let coreAudioDevices = audioManager.outputDevices
        let airPlayDevices = audioManager.discoveredAirPlayDevices
        let currentDeviceID = WindowManager.shared.audioEngine.currentOutputDeviceID
        
        // Ensure cast discovery is running
        if !castManager.isDiscovering {
            castManager.startDiscovery()
        }
        
        // ========== Local Audio Section ==========
        let localHeader = NSMenuItem(title: "Local Audio", action: nil, keyEquivalent: "")
        outputMenu.addItem(localHeader)
        
        // System Default option
        let defaultItem = NSMenuItem(title: "  System Default", action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
        defaultItem.target = MenuActions.shared
        defaultItem.representedObject = nil as AudioDeviceID?
        defaultItem.state = currentDeviceID == nil ? .on : .off
        outputMenu.addItem(defaultItem)
        
        // Local/wired devices
        let localDevices = coreAudioDevices.filter { !$0.isWireless }
        for device in localDevices {
            let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
            deviceItem.target = MenuActions.shared
            deviceItem.representedObject = device.id
            deviceItem.state = (currentDeviceID == device.id) ? .on : .off
            outputMenu.addItem(deviceItem)
        }
        
        // ========== AirPlay Section ==========
        let coreAudioWireless = coreAudioDevices.filter { $0.isWireless }
        let hasAirPlay = !coreAudioWireless.isEmpty || !airPlayDevices.isEmpty
        
        if hasAirPlay {
            outputMenu.addItem(NSMenuItem.separator())
            
            // AirPlay submenu
            let airplayItem = NSMenuItem(title: "AirPlay", action: nil, keyEquivalent: "")
            let airplayMenu = NSMenu()
            airplayMenu.autoenablesItems = false
            
            // Connected AirPlay devices (via Core Audio)
            if !coreAudioWireless.isEmpty {
                let connectedHeader = NSMenuItem(title: "Connected", action: nil, keyEquivalent: "")
                airplayMenu.addItem(connectedHeader)
                
                for device in coreAudioWireless {
                    let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
                    deviceItem.target = MenuActions.shared
                    deviceItem.representedObject = device.id
                    deviceItem.state = (currentDeviceID == device.id) ? .on : .off
                    airplayMenu.addItem(deviceItem)
                }
            }
            
            // Discovered AirPlay devices (need to connect via Sound Settings)
            if !airPlayDevices.isEmpty {
                if !coreAudioWireless.isEmpty {
                    airplayMenu.addItem(NSMenuItem.separator())
                }
                
                let availableHeader = NSMenuItem(title: "Available (Connect in Sound Settings)", action: nil, keyEquivalent: "")
                airplayMenu.addItem(availableHeader)
                
                for device in airPlayDevices {
                    let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.selectAirPlayDevice(_:)), keyEquivalent: "")
                    deviceItem.target = MenuActions.shared
                    deviceItem.representedObject = device.name
                    airplayMenu.addItem(deviceItem)
                }
            }
            
            // Sound Settings shortcut within AirPlay menu
            airplayMenu.addItem(NSMenuItem.separator())
            let airplaySettings = NSMenuItem(title: "Sound Settings...", action: #selector(MenuActions.openSoundSettings), keyEquivalent: "")
            airplaySettings.target = MenuActions.shared
            airplayMenu.addItem(airplaySettings)
            
            airplayItem.submenu = airplayMenu
            outputMenu.addItem(airplayItem)
        }
        
        // ========== Sonos Submenu with flat checkbox list ==========
        let rooms = castManager.sonosRooms
        NSLog("ContextMenuBuilder: sonosRooms count = %d", rooms.count)
        for room in rooms {
            NSLog("ContextMenuBuilder: Room '%@' isCoord=%d isInGroup=%d", room.name, room.isGroupCoordinator ? 1 : 0, room.isInGroup ? 1 : 0)
        }
        if !rooms.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())
            
            let sonosItem = NSMenuItem(title: "Sonos", action: nil, keyEquivalent: "")
            let sonosMenu = NSMenu()
            sonosMenu.autoenablesItems = false
            
            // Determine checkbox state based on whether we're casting
            let castTargetUDN = castManager.activeSession?.device.id
            let isCastingToSonos = castManager.activeSession?.device.type == .sonos
            
            for room in rooms {
                var isChecked = false
                
                if isCastingToSonos, let targetUDN = castTargetUDN {
                    // WHILE CASTING: checked = receiving audio from cast session
                    // Direct match: this room is the cast target
                    if room.id == targetUDN {
                        isChecked = true
                    }
                    // This room's coordinator is the cast target
                    else if room.groupCoordinatorUDN == targetUDN {
                        isChecked = true
                    }
                    // This room IS a coordinator and has the cast target as a member
                    else if room.isGroupCoordinator {
                        let targetRoom = rooms.first { $0.id == targetUDN }
                        if targetRoom?.groupCoordinatorUDN == room.id {
                            isChecked = true
                        }
                    }
                } else {
                    // NOT CASTING: checked = room is selected for future cast
                    isChecked = castManager.selectedSonosRooms.contains(room.id)
                }
                
                let toggleInfo = SonosRoomToggle(
                    roomUDN: room.id,
                    roomName: room.name,
                    coordinatorUDN: castTargetUDN ?? room.groupCoordinatorUDN ?? rooms.first?.id ?? "",
                    coordinatorName: room.groupCoordinatorName ?? rooms.first?.name ?? "",
                    isCurrentlyInGroup: isChecked,
                    isCoordinator: room.id == castTargetUDN
                )
                
                // Use custom view that keeps menu open when clicked
                let roomItem = NSMenuItem()
                roomItem.view = SonosRoomCheckboxView(info: toggleInfo, isChecked: isChecked, menu: sonosMenu)
                sonosMenu.addItem(roomItem)
            }
            
            sonosMenu.addItem(NSMenuItem.separator())
            
            // Cast controls
            if isCastingToSonos {
                let stopItem = NSMenuItem(title: "🔴 Stop Casting", action: #selector(MenuActions.stopCasting), keyEquivalent: "")
                stopItem.target = MenuActions.shared
                sonosMenu.addItem(stopItem)
            } else {
                let castItem = NSMenuItem(title: "🟢 Start Casting", action: #selector(MenuActions.castToSonosRoom(_:)), keyEquivalent: "")
                castItem.target = MenuActions.shared
                sonosMenu.addItem(castItem)
            }
            
            // Refresh
            let refreshItem = NSMenuItem(title: "Refresh", action: #selector(MenuActions.refreshSonosRooms), keyEquivalent: "")
            refreshItem.target = MenuActions.shared
            sonosMenu.addItem(refreshItem)
            
            sonosItem.submenu = sonosMenu
            outputMenu.addItem(sonosItem)
        }
        
        // ========== Other Cast Devices ==========
        let chromecastDevices = castManager.chromecastDevices
        let tvDevices = castManager.dlnaTVDevices
        let activeSession = castManager.activeSession
        
        // Chromecast (if any)
        if !chromecastDevices.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())
            let chromecastHeader = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
            outputMenu.addItem(chromecastHeader)
            
            for device in chromecastDevices {
                let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device
                deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                outputMenu.addItem(deviceItem)
            }
        }
        
        // DLNA TVs (if any)
        if !tvDevices.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())
            let tvHeader = NSMenuItem(title: "TVs (DLNA)", action: nil, keyEquivalent: "")
            outputMenu.addItem(tvHeader)
            
            for device in tvDevices {
                let displayName = device.manufacturer != nil ? "\(device.name) [\(device.manufacturer!)]" : device.name
                let deviceItem = NSMenuItem(title: "  \(displayName)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device
                deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                outputMenu.addItem(deviceItem)
            }
        }
        
        outputItem.submenu = outputMenu
        return outputItem
    }
    
    // MARK: - Sonos Groups Submenu
}

// MARK: - Custom Checkbox View (keeps menu open on click)

/// A custom view for menu items that toggles a checkbox without closing the menu
class SonosRoomCheckboxView: NSView {
    private let checkbox: NSButton
    private let info: SonosRoomToggle
    private weak var parentMenu: NSMenu?
    
    init(info: SonosRoomToggle, isChecked: Bool, menu: NSMenu?) {
        self.info = info
        self.parentMenu = menu
        
        checkbox = NSButton(checkboxWithTitle: info.roomName, target: nil, action: nil)
        checkbox.state = isChecked ? .on : .off
        checkbox.font = NSFont.menuFont(ofSize: 0)
        
        // Calculate frame size based on checkbox
        checkbox.sizeToFit()
        let frame = NSRect(x: 0, y: 0, width: checkbox.frame.width + 32, height: 22)
        
        super.init(frame: frame)
        
        checkbox.frame.origin = NSPoint(x: 16, y: (frame.height - checkbox.frame.height) / 2)
        checkbox.target = self
        checkbox.action = #selector(checkboxClicked(_:))
        
        addSubview(checkbox)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func checkboxClicked(_ sender: NSButton) {
        let isNowChecked = sender.state == .on
        
        // Toggle the selection state
        let castManager = CastManager.shared
        let isCastingToSonos = castManager.activeSession?.device.type == .sonos
        
        NSLog("SonosRoomCheckboxView: Toggled '%@' to %d, isCasting=%d", 
              info.roomName, isNowChecked ? 1 : 0, isCastingToSonos ? 1 : 0)
        
        if isCastingToSonos {
            // WHILE CASTING: toggle actually joins/unjoins the Sonos group
            Task {
                do {
                    if !isNowChecked {
                        // Check if we're unchecking the current coordinator
                        let isCoordinator = info.roomUDN == castManager.activeSession?.device.id
                        
                        if isCoordinator {
                            // Unchecking the coordinator - check if other rooms remain
                            let groupRooms = castManager.getRoomsInActiveCastGroup()
                            let otherRooms = groupRooms.filter { $0 != info.roomUDN }
                            
                            if otherRooms.isEmpty {
                                // Only room in group - just stop casting
                                NSLog("SonosRoomCheckboxView: Unchecking sole coordinator '%@' - stopping cast", info.roomName)
                                await castManager.stopCasting()
                            } else {
                                // Transfer playback to next remaining room
                                let newCoordinator = otherRooms[0]
                                let remainingOthers = Array(otherRooms.dropFirst())
                                NSLog("SonosRoomCheckboxView: Transferring cast from '%@' to room %@ (+%d others)",
                                      info.roomName, newCoordinator, remainingOthers.count)
                                try await castManager.transferSonosCast(
                                    fromCoordinator: info.roomUDN,
                                    toRoom: newCoordinator,
                                    otherRooms: remainingOthers
                                )
                            }
                            // Close menu after coordinator change to force UI refresh on next open
                            await MainActor.run {
                                self.parentMenu?.cancelTracking()
                            }
                            return
                        }
                        
                        // Not the coordinator - just unjoin this room from the group
                        NSLog("SonosRoomCheckboxView: Removing '%@' from cast group", info.roomName)
                        try await castManager.unjoinSonos(zoneUDN: info.roomUDN)
                    } else {
                        // Was unchecked, now checked - join to active cast
                        if let coordinatorUDN = castManager.activeSession?.device.id {
                            NSLog("SonosRoomCheckboxView: Adding '%@' to cast group", info.roomName)
                            try await castManager.joinSonosToGroup(
                                zoneUDN: info.roomUDN,
                                coordinatorUDN: coordinatorUDN
                            )
                        }
                    }
                    
                    // Refresh topology to update UI
                    await castManager.refreshSonosGroups()
                    NSLog("SonosRoomCheckboxView: Toggle complete for '%@'", info.roomName)
                    
                } catch {
                    NSLog("SonosRoomCheckboxView: Toggle failed for '%@': %@", info.roomName, error.localizedDescription)
                    // Revert checkbox state on error
                    await MainActor.run {
                        sender.state = isNowChecked ? .off : .on
                    }
                    // If we can't control the Sonos, the session is effectively broken
                    // Clean up to prevent local+cast conflict and show error
                    await castManager.stopCasting()
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Sonos Unavailable"
                        alert.informativeText = "Lost connection to Sonos: \(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        } else {
            // NOT CASTING: just toggle selection state (stored locally)
            if isNowChecked {
                castManager.selectedSonosRooms.insert(info.roomUDN)
                NSLog("SonosRoomCheckboxView: Selected '%@' for casting", info.roomName)
            } else {
                castManager.selectedSonosRooms.remove(info.roomUDN)
                NSLog("SonosRoomCheckboxView: Deselected '%@' for casting", info.roomName)
            }
        }
        
        // Keep menu open by canceling the close - the menu stays open because we're in a custom view
    }

}

/// Info for toggling a room in/out of a group
struct SonosRoomToggle {
    let roomUDN: String
    let roomName: String
    let coordinatorUDN: String
    let coordinatorName: String
    let isCurrentlyInGroup: Bool
    let isCoordinator: Bool
}

/// Info about a Sonos zone for grouping menu actions (legacy)
struct SonosGroupingInfo {
    let zoneUDN: String
    let zoneName: String
    let coordinatorUDN: String
    let coordinatorName: String
    let isCurrentlyInGroup: Bool
    let isCoordinator: Bool
}

/// Action for simplified room grouping
struct SonosRoomAction {
    enum ActionType {
        case leave
        case join(coordinatorUDN: String, coordinatorName: String)
    }
    
    let roomUDN: String
    let roomName: String
    let action: ActionType
}

