import AppKit
import CoreAudio

/// Builds the shared right-click context menu for all Winamp windows
class ContextMenuBuilder {
    
    // MARK: - Main Menu Builder
    
    static func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let wm = WindowManager.shared
        
        // About Playing (shows current track/video info)
        let aboutPlaying = NSMenuItem(title: "About Playing", action: #selector(MenuActions.showAboutPlaying), keyEquivalent: "")
        aboutPlaying.target = MenuActions.shared
        // Disable if nothing is playing
        let hasAudioContent = wm.audioEngine.currentTrack != nil
        let hasVideoContent = wm.currentVideoTitle != nil
        aboutPlaying.isEnabled = hasAudioContent || hasVideoContent
        menu.addItem(aboutPlaying)
        menu.addItem(NSMenuItem.separator())
        
        // Window toggles
        menu.addItem(buildWindowItem("Main Window", visible: wm.mainWindowController?.window?.isVisible ?? false, action: #selector(MenuActions.toggleMainWindow)))
        menu.addItem(buildWindowItem("Equalizer", visible: wm.isEqualizerVisible, action: #selector(MenuActions.toggleEQ)))
        menu.addItem(buildWindowItem("Playlist Editor", visible: wm.isPlaylistVisible, action: #selector(MenuActions.togglePlaylist)))
        menu.addItem(buildWindowItem("Library Browser", visible: wm.isPlexBrowserVisible, action: #selector(MenuActions.togglePlexBrowser)))
        menu.addItem(buildWindowItem("Milkdrop", visible: wm.isMilkdropVisible, action: #selector(MenuActions.toggleMilkdrop)))
        
        menu.addItem(NSMenuItem.separator())
        
        // Skins submenu
        menu.addItem(buildSkinsMenuItem())
        
        // Visualizations submenu
        menu.addItem(buildVisualizationsMenuItem())
        
        // Options submenu
        menu.addItem(buildOptionsMenuItem())
        
        // Local Library submenu
        menu.addItem(buildLocalLibraryMenuItem())
        
        // Plex submenu
        menu.addItem(buildPlexMenuItem())
        
        // Subsonic submenu
        menu.addItem(buildSubsonicMenuItem())
        
        // Output Devices submenu (includes local, AirPlay, and casting)
        menu.addItem(buildOutputDevicesMenuItem())
        
        menu.addItem(NSMenuItem.separator())
        
        // Always on Top
        let alwaysOnTop = NSMenuItem(title: "Always on Top", action: #selector(MenuActions.toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTop.target = MenuActions.shared
        alwaysOnTop.state = wm.isAlwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTop)
        
        // Remember State on Quit
        let rememberState = NSMenuItem(title: "Remember State on Quit", action: #selector(MenuActions.toggleRememberState), keyEquivalent: "")
        rememberState.target = MenuActions.shared
        rememberState.state = AppStateManager.shared.isEnabled ? .on : .off
        menu.addItem(rememberState)
        
        // Snap to Default
        let snapToDefault = NSMenuItem(title: "Snap to Default", action: #selector(MenuActions.snapToDefault), keyEquivalent: "")
        snapToDefault.target = MenuActions.shared
        menu.addItem(snapToDefault)
        
        menu.addItem(NSMenuItem.separator())
        
        // Exit
        let exit = NSMenuItem(title: "Exit", action: #selector(MenuActions.exit), keyEquivalent: "")
        exit.target = MenuActions.shared
        menu.addItem(exit)
        
        menu.autoenablesItems = false
        return menu
    }
    
    // MARK: - Window Toggle Items
    
    private static func buildWindowItem(_ title: String, visible: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = MenuActions.shared
        item.state = visible ? .on : .off
        return item
    }
    
    // MARK: - Skins Submenu
    
    private static func buildSkinsMenuItem() -> NSMenuItem {
        let skinsItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        skinsItem.submenu = buildSkinsSubmenu()
        return skinsItem
    }
    
    private static func buildSkinsSubmenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // Load Skin...
        let loadSkin = NSMenuItem(title: "Load Skin...", action: #selector(MenuActions.loadSkinFromFile), keyEquivalent: "")
        loadSkin.target = MenuActions.shared
        menu.addItem(loadSkin)
        
        // Get More Skins...
        let getMoreSkins = NSMenuItem(title: "Get More Skins...", action: #selector(MenuActions.getMoreSkins), keyEquivalent: "")
        getMoreSkins.target = MenuActions.shared
        menu.addItem(getMoreSkins)
        
        // Base Skin 1
        let baseSkin1 = NSMenuItem(title: "<Base Skin 1>", action: #selector(MenuActions.loadBaseSkin), keyEquivalent: "")
        baseSkin1.target = MenuActions.shared
        menu.addItem(baseSkin1)
        
        // Base Skin 2
        let baseSkin2 = NSMenuItem(title: "<Base Skin 2>", action: #selector(MenuActions.loadBaseSkin2), keyEquivalent: "")
        baseSkin2.target = MenuActions.shared
        menu.addItem(baseSkin2)
        
        // Base Skin 3
        let baseSkin3 = NSMenuItem(title: "<Base Skin 3>", action: #selector(MenuActions.loadBaseSkin3), keyEquivalent: "")
        baseSkin3.target = MenuActions.shared
        menu.addItem(baseSkin3)
        
        menu.addItem(NSMenuItem.separator())
        
        // Lock Browser/Milkdrop toggle
        let lockToggle = NSMenuItem(title: "Lock Browser/Milkdrop to Default", action: #selector(MenuActions.toggleLockBrowserMilkdrop(_:)), keyEquivalent: "")
        lockToggle.target = MenuActions.shared
        lockToggle.state = WindowManager.shared.lockBrowserMilkdropSkin ? .on : .off
        menu.addItem(lockToggle)
        
        menu.addItem(NSMenuItem.separator())
        
        // Available skins from Skins directory
        let availableSkins = WindowManager.shared.availableSkins()
        if !availableSkins.isEmpty {
            for skin in availableSkins {
                let skinItem = NSMenuItem(title: skin.name, action: #selector(MenuActions.loadSkin(_:)), keyEquivalent: "")
                skinItem.target = MenuActions.shared
                skinItem.representedObject = skin.url
                menu.addItem(skinItem)
            }
        }
        
        return menu
    }
    
    // MARK: - Visualizations Submenu
    
    private static func buildVisualizationsMenuItem() -> NSMenuItem {
        let visItem = NSMenuItem(title: "Visualizations", action: nil, keyEquivalent: "")
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
        } else if wm.isMilkdropVisible && !wm.isProjectMAvailable {
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
        
        visItem.submenu = visMenu
        return visItem
    }
    
    // MARK: - Options Submenu
    
    private static func buildOptionsMenuItem() -> NSMenuItem {
        let optionsItem = NSMenuItem(title: "Playback Options", action: nil, keyEquivalent: "")
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
        
        optionsItem.submenu = optionsMenu
        return optionsItem
    }
    
    // MARK: - Local Library Submenu
    
    private static func buildLocalLibraryMenuItem() -> NSMenuItem {
        let libraryItem = NSMenuItem(title: "Local Library", action: nil, keyEquivalent: "")
        let libraryMenu = NSMenu()
        libraryMenu.autoenablesItems = false
        
        let trackCount = MediaLibrary.shared.tracksSnapshot.count
        
        // Library info header
        let infoItem = NSMenuItem(title: "\(trackCount) tracks in library", action: nil, keyEquivalent: "")
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
        
        // Clear Library (with confirmation)
        let clearItem = NSMenuItem(title: "Clear Library...", action: #selector(MenuActions.clearLibrary), keyEquivalent: "")
        clearItem.target = MenuActions.shared
        clearItem.isEnabled = trackCount > 0
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
    
    // MARK: - Playback Submenu
    // MARK: - Output Devices Submenu (Unified)
    
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
        let sonosDevices = castManager.sonosDevices
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
                        // Was checked, now unchecked - remove from group
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

// MARK: - Menu Actions

/// Singleton to handle menu actions
class MenuActions: NSObject {
    static let shared = MenuActions()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Window Toggles
    
    @objc func toggleMainWindow() {
        WindowManager.shared.toggleMainWindow()
    }
    
    @objc func toggleEQ() {
        WindowManager.shared.toggleEqualizer()
    }
    
    @objc func togglePlaylist() {
        WindowManager.shared.togglePlaylist()
    }
    
    @objc func toggleMediaLibrary() {
        WindowManager.shared.toggleMediaLibrary()
    }
    
    @objc func togglePlexBrowser() {
        WindowManager.shared.togglePlexBrowser()
    }
    
    @objc func toggleMilkdrop() {
        WindowManager.shared.toggleMilkdrop()
    }
    
    // MARK: - About Playing
    
    @objc func showAboutPlaying() {
        let wm = WindowManager.shared
        
        // Check for video first (takes priority if both audio and video are active)
        if let videoController = wm.currentVideoPlayerController,
           wm.isVideoActivePlayback {
            showVideoInfo(videoController)
            return
        }
        
        // Check for audio track
        if let track = wm.audioEngine.currentTrack {
            showAudioTrackInfo(track)
            return
        }
        
        // Nothing playing (shouldn't happen - menu item should be disabled)
        let alert = NSAlert()
        alert.messageText = "Nothing Playing"
        alert.informativeText = "No track or video is currently playing."
        alert.runModal()
    }
    
    private func showVideoInfo(_ controller: VideoPlayerWindowController) {
        let alert = NSAlert()
        
        if let movie = controller.plexMovie {
            // Plex Movie
            alert.messageText = movie.title
            var info = [String]()
            
            if let year = movie.year { info.append("Year: \(year)") }
            if let studio = movie.studio { info.append("Studio: \(studio)") }
            info.append("Duration: \(movie.formattedDuration)")
            info.append("")
            
            // Video/Audio format from media
            if let media = movie.primaryMedia {
                if let resolution = media.videoResolution {
                    var videoInfo = "Resolution: \(resolution)"
                    if let width = media.width, let height = media.height {
                        videoInfo = "Resolution: \(width)x\(height)"
                    }
                    info.append(videoInfo)
                }
                if let videoCodec = media.videoCodec {
                    info.append("Video Codec: \(videoCodec.uppercased())")
                }
                if let audioCodec = media.audioCodec {
                    var audioInfo = "Audio: \(audioCodec.uppercased())"
                    if let channels = media.audioChannels {
                        audioInfo += " (\(formatChannels(channels)))"
                    }
                    info.append(audioInfo)
                }
                if let bitrate = media.bitrate {
                    info.append("Bitrate: \(bitrate) kbps")
                }
            }
            info.append("")
            
            if let contentRating = movie.contentRating {
                info.append("Content Rating: \(contentRating)")
            }
            if let imdbId = movie.imdbId {
                info.append("IMDB: \(imdbId)")
            }
            if let tmdbId = movie.tmdbId {
                info.append("TMDB: \(tmdbId)")
            }
            info.append("")
            
            if let serverName = PlexManager.shared.currentServer?.name {
                info.append("Source: Plex (\(serverName))")
            } else {
                info.append("Source: Plex")
            }
            
            if let summary = movie.summary, !summary.isEmpty {
                info.append("")
                info.append("Summary: \(summary.prefix(200))\(summary.count > 200 ? "..." : "")")
            }
            
            alert.informativeText = info.joined(separator: "\n")
            
        } else if let episode = controller.plexEpisode {
            // Plex Episode
            let showTitle = episode.grandparentTitle ?? "Unknown Show"
            alert.messageText = "\(showTitle) - \(episode.episodeIdentifier)"
            
            var info = [String]()
            info.append("Episode: \(episode.title)")
            if let seasonTitle = episode.parentTitle {
                info.append("Season: \(seasonTitle)")
            }
            info.append("Duration: \(episode.formattedDuration)")
            info.append("")
            
            // Video/Audio format from media
            if let media = episode.media.first {
                if let resolution = media.videoResolution {
                    var videoInfo = "Resolution: \(resolution)"
                    if let width = media.width, let height = media.height {
                        videoInfo = "Resolution: \(width)x\(height)"
                    }
                    info.append(videoInfo)
                }
                if let videoCodec = media.videoCodec {
                    info.append("Video Codec: \(videoCodec.uppercased())")
                }
                if let audioCodec = media.audioCodec {
                    var audioInfo = "Audio: \(audioCodec.uppercased())"
                    if let channels = media.audioChannels {
                        audioInfo += " (\(formatChannels(channels)))"
                    }
                    info.append(audioInfo)
                }
                if let bitrate = media.bitrate {
                    info.append("Bitrate: \(bitrate) kbps")
                }
            }
            info.append("")
            
            if let imdbId = episode.imdbId {
                info.append("IMDB: \(imdbId)")
            }
            info.append("")
            
            if let serverName = PlexManager.shared.currentServer?.name {
                info.append("Source: Plex (\(serverName))")
            } else {
                info.append("Source: Plex")
            }
            
            if let summary = episode.summary, !summary.isEmpty {
                info.append("")
                info.append("Summary: \(summary.prefix(200))\(summary.count > 200 ? "..." : "")")
            }
            
            alert.informativeText = info.joined(separator: "\n")
            
        } else if let url = controller.localVideoURL {
            // Local video file
            alert.messageText = controller.currentTitle ?? url.lastPathComponent
            var info = [String]()
            info.append("Path: \(url.path)")
            info.append("")
            info.append("Source: Local File")
            alert.informativeText = info.joined(separator: "\n")
            
        } else {
            // Unknown video
            alert.messageText = controller.currentTitle ?? "Video"
            alert.informativeText = "Source: Unknown"
        }
        
        alert.runModal()
    }
    
    private func showAudioTrackInfo(_ track: Track) {
        // Check if this is a Plex track - fetch full metadata async
        if let ratingKey = track.plexRatingKey {
            Task {
                await showPlexTrackInfo(track, ratingKey: ratingKey)
            }
            return
        }
        
        // Check if this is a Subsonic track
        if let subsonicId = track.subsonicId {
            showSubsonicTrackInfo(track, subsonicId: subsonicId)
            return
        }
        
        // Local file
        showLocalTrackInfo(track)
    }
    
    @MainActor
    private func showPlexTrackInfo(_ track: Track, ratingKey: String) async {
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        
        var info = [String]()
        
        // Try to fetch full Plex metadata
        var plexTrack: PlexTrack?
        if let client = PlexManager.shared.serverClient {
            plexTrack = try? await client.fetchTrackDetails(trackID: ratingKey)
        }
        
        // Basic info (always available from Track)
        info.append("Title: \(track.title)")
        if let artist = track.artist { info.append("Artist: \(artist)") }
        if let album = track.album { info.append("Album: \(album)") }
        info.append("")
        
        // Duration
        info.append("Duration: \(track.formattedDuration)")
        
        // Extended info from Plex API
        if let pt = plexTrack {
            if let genre = pt.genre { info.append("Genre: \(genre)") }
            if let year = pt.parentYear { info.append("Year: \(year)") }
            if let index = pt.index {
                var trackInfo = "Track: \(index)"
                if let disc = pt.parentIndex { trackInfo += " (Disc \(disc))" }
                info.append(trackInfo)
            }
            info.append("")
            
            // Audio format from media
            if let media = pt.media.first {
                if let codec = media.audioCodec {
                    var formatInfo = "Format: \(codec.uppercased())"
                    if let channels = media.audioChannels {
                        formatInfo += " (\(formatChannels(channels)))"
                    }
                    info.append(formatInfo)
                }
                if let bitrate = media.bitrate {
                    info.append("Bitrate: \(bitrate) kbps")
                }
                // File path from part
                if let part = media.parts.first, let file = part.file {
                    info.append("File: \(file)")
                }
            }
            info.append("")
            
            // Plex-specific metadata
            if let ratingCount = pt.ratingCount, ratingCount > 0 {
                info.append("Last.fm Scrobbles: \(formatNumber(ratingCount))")
            }
            if let userRating = pt.userRating, userRating > 0 {
                info.append("Your Rating: \(formatStarRating(userRating))")
            }
        } else {
            // Fallback to Track model data
            info.append("")
            if let bitrate = track.bitrate { info.append("Bitrate: \(bitrate) kbps") }
            if let sampleRate = track.sampleRate { info.append("Sample Rate: \(sampleRate) Hz") }
            if let channels = track.channels { info.append("Channels: \(formatChannels(channels))") }
        }
        info.append("")
        
        // Source
        if let serverName = PlexManager.shared.currentServer?.name {
            info.append("Source: Plex (\(serverName))")
        } else {
            info.append("Source: Plex")
        }
        
        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }
    
    private func showSubsonicTrackInfo(_ track: Track, subsonicId: String) {
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        
        var info = [String]()
        
        info.append("Title: \(track.title)")
        if let artist = track.artist { info.append("Artist: \(artist)") }
        if let album = track.album { info.append("Album: \(album)") }
        info.append("")
        
        info.append("Duration: \(track.formattedDuration)")
        if let bitrate = track.bitrate { info.append("Bitrate: \(bitrate) kbps") }
        if let sampleRate = track.sampleRate { info.append("Sample Rate: \(sampleRate) Hz") }
        if let channels = track.channels { info.append("Channels: \(formatChannels(channels))") }
        info.append("")
        
        // Source
        if let serverName = SubsonicManager.shared.currentServer?.name {
            info.append("Source: Subsonic (\(serverName))")
        } else {
            info.append("Source: Subsonic")
        }
        info.append("Track ID: \(subsonicId)")
        
        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }
    
    private func showLocalTrackInfo(_ track: Track) {
        let alert = NSAlert()
        alert.messageText = track.displayTitle
        
        var info = [String]()
        
        info.append("Title: \(track.title)")
        if let artist = track.artist { info.append("Artist: \(artist)") }
        if let album = track.album { info.append("Album: \(album)") }
        info.append("")
        
        info.append("Duration: \(track.formattedDuration)")
        info.append("")
        
        // Audio format
        var formatParts = [String]()
        if let sampleRate = track.sampleRate {
            formatParts.append("\(sampleRate / 1000)kHz")
        }
        if let channels = track.channels {
            formatParts.append(formatChannels(channels))
        }
        if !formatParts.isEmpty {
            info.append("Format: \(formatParts.joined(separator: ", "))")
        }
        if let bitrate = track.bitrate { info.append("Bitrate: \(bitrate) kbps") }
        info.append("")
        
        info.append("Path: \(track.url.path)")
        info.append("")
        info.append("Source: Local File")
        
        alert.informativeText = info.joined(separator: "\n")
        alert.runModal()
    }
    
    // MARK: - Formatting Helpers for About Playing
    
    private func formatChannels(_ channels: Int) -> String {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        default: return "\(channels) channels"
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func formatStarRating(_ rating: Double) -> String {
        // Plex uses 0-10 scale (10 = 5 stars)
        let stars = Int(round(rating / 2))
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: 5 - stars)
    }
    
    // MARK: - File Operations
    
    @objc func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        
        if panel.runModal() == .OK {
            WindowManager.shared.audioEngine.loadFiles(panel.urls)
        }
    }
    
    @objc func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK, let url = panel.url {
            WindowManager.shared.audioEngine.loadFolder(url)
        }
    }
    
    // MARK: - Skin Operations
    
    @objc func loadSkinFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "wsz")!]
        
        if panel.runModal() == .OK, let url = panel.url {
            WindowManager.shared.loadSkin(from: url)
        }
    }
    
    @objc func loadBaseSkin() {
        WindowManager.shared.loadBaseSkin()
    }
    
    @objc func loadBaseSkin2() {
        WindowManager.shared.loadBaseSkin2()
    }
    
    @objc func loadBaseSkin3() {
        WindowManager.shared.loadBaseSkin3()
    }
    
    @objc func loadSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        WindowManager.shared.loadSkin(from: url)
    }
    
    @objc func toggleLockBrowserMilkdrop(_ sender: NSMenuItem) {
        WindowManager.shared.lockBrowserMilkdropSkin.toggle()
    }
    
    @objc func getMoreSkins() {
        if let url = URL(string: "https://skins.webamp.org/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Options
    
    @objc func setTimeElapsed() {
        WindowManager.shared.timeDisplayMode = .elapsed
    }
    
    @objc func setTimeRemaining() {
        WindowManager.shared.timeDisplayMode = .remaining
    }
    
    @objc func toggleRepeat() {
        WindowManager.shared.audioEngine.repeatEnabled.toggle()
    }
    
    @objc func toggleShuffle() {
        WindowManager.shared.audioEngine.shuffleEnabled.toggle()
    }
    
    @objc func toggleGaplessPlayback() {
        WindowManager.shared.audioEngine.gaplessPlaybackEnabled.toggle()
    }
    
    @objc func toggleVolumeNormalization() {
        WindowManager.shared.audioEngine.volumeNormalizationEnabled.toggle()
    }
    
    @objc func toggleSweetFade() {
        WindowManager.shared.audioEngine.sweetFadeEnabled.toggle()
    }
    
    @objc func setSweetFadeDuration(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? Double else { return }
        WindowManager.shared.audioEngine.sweetFadeDuration = duration
    }
    
    @objc func toggleBrowserArtworkBackground() {
        WindowManager.shared.showBrowserArtworkBackground.toggle()
    }
    
    @objc func toggleRememberState() {
        AppStateManager.shared.isEnabled.toggle()
        
        // When enabling, immediately save current state to avoid
        // restoring stale state from previous session
        if AppStateManager.shared.isEnabled {
            AppStateManager.shared.saveState()
        }
    }
    
    @objc func toggleAlwaysOnTop() {
        WindowManager.shared.isAlwaysOnTop.toggle()
    }
    
    @objc func snapToDefault() {
        WindowManager.shared.snapToDefaultPositions()
    }
    
    // MARK: - Playback Controls
    
    @objc func previous() {
        WindowManager.shared.audioEngine.previous()
    }
    
    @objc func play() {
        WindowManager.shared.audioEngine.play()
    }
    
    @objc func pause() {
        WindowManager.shared.audioEngine.pause()
    }
    
    @objc func stop() {
        WindowManager.shared.audioEngine.stop()
    }
    
    @objc func next() {
        WindowManager.shared.audioEngine.next()
    }
    
    @objc func back5Seconds() {
        WindowManager.shared.audioEngine.seekBy(seconds: -5)
    }
    
    @objc func fwd5Seconds() {
        WindowManager.shared.audioEngine.seekBy(seconds: 5)
    }
    
    @objc func back10Tracks() {
        WindowManager.shared.audioEngine.skipTracks(count: -10)
    }
    
    @objc func fwd10Tracks() {
        WindowManager.shared.audioEngine.skipTracks(count: 10)
    }
    
    // MARK: - Plex
    
    @objc func linkPlexAccount() {
        WindowManager.shared.showPlexLinkSheet()
    }
    
    @objc func unlinkPlexAccount() {
        let alert = NSAlert()
        alert.messageText = "Unlink Plex Account?"
        alert.informativeText = "This will remove your Plex account from AdAmp. You can link it again later."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Unlink")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            WindowManager.shared.unlinkPlexAccount()
        }
    }
    
    @objc func selectPlexServer(_ sender: NSMenuItem) {
        guard let serverID = sender.representedObject as? String,
              let server = PlexManager.shared.servers.first(where: { $0.id == serverID }) else {
            return
        }
        
        Task {
            do {
                NSLog("MenuActions: Attempting to connect to server '%@'", server.name)
                try await PlexManager.shared.connect(to: server)
                NSLog("MenuActions: Successfully connected to server '%@'", server.name)
                
                // Notify the Plex browser to reload
                await MainActor.run {
                    NotificationCenter.default.post(name: PlexManager.serversDidChangeNotification, object: nil)
                }
            } catch {
                NSLog("MenuActions: Failed to connect to server '%@': %@", server.name, error.localizedDescription)
                
                // Show error to user
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Connect"
                    alert.informativeText = "Could not connect to \(server.name): \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func selectPlexLibrary(_ sender: NSMenuItem) {
        guard let libraryID = sender.representedObject as? String,
              let library = PlexManager.shared.availableLibraries.first(where: { $0.id == libraryID }) else {
            return
        }
        
        PlexManager.shared.selectLibrary(library)
    }
    
    @objc func refreshPlexServers() {
        Task {
            do {
                try await PlexManager.shared.refreshServers()
                print("Plex servers refreshed: \(PlexManager.shared.servers.map { $0.name })")
            } catch {
                print("Failed to refresh Plex servers: \(error)")
                
                // Show error to user
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Refresh Servers"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Subsonic
    
    @objc func addSubsonicServer() {
        WindowManager.shared.showSubsonicLinkSheet()
    }
    
    @objc func manageSubsonicServers() {
        WindowManager.shared.showSubsonicServerList()
    }
    
    @objc func selectSubsonicServer(_ sender: NSMenuItem) {
        guard let serverID = sender.representedObject as? String,
              let server = SubsonicManager.shared.servers.first(where: { $0.id == serverID }) else {
            return
        }
        
        Task {
            do {
                NSLog("MenuActions: Attempting to connect to Subsonic server '%@'", server.name)
                try await SubsonicManager.shared.connect(to: server)
                NSLog("MenuActions: Successfully connected to Subsonic server '%@'", server.name)
                
                await MainActor.run {
                    NotificationCenter.default.post(name: SubsonicManager.serversDidChangeNotification, object: nil)
                }
            } catch {
                NSLog("MenuActions: Failed to connect to Subsonic server '%@': %@", server.name, error.localizedDescription)
                
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Failed to Connect"
                    alert.informativeText = "Could not connect to \(server.name): \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func disconnectSubsonic() {
        SubsonicManager.shared.disconnect()
        NotificationCenter.default.post(name: SubsonicManager.connectionStateDidChangeNotification, object: nil)
    }
    
    @objc func refreshSubsonicLibrary() {
        Task {
            await SubsonicManager.shared.preloadLibraryContent()
            NSLog("MenuActions: Subsonic library refreshed")
        }
    }
    
    @objc func showSubsonicInBrowser() {
        // Show the library browser with Subsonic source selected
        guard let serverId = SubsonicManager.shared.currentServer?.id else { return }
        
        WindowManager.shared.showPlexBrowser()
        
        // Set the browser source to Subsonic
        NotificationCenter.default.post(
            name: NSNotification.Name("SetBrowserSource"),
            object: BrowserSource.subsonic(serverId: serverId)
        )
    }
    
    // MARK: - Output Device
    
    @objc func selectOutputDevice(_ sender: NSMenuItem) {
        let deviceID = sender.representedObject as? AudioDeviceID
        WindowManager.shared.audioEngine.setOutputDevice(deviceID)
    }
    
    @objc func openSoundSettings() {
        // Open System Settings > Sound
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc func selectAirPlayDevice(_ sender: NSMenuItem) {
        // AirPlay devices need to be selected in Sound Settings first
        // Show an alert explaining this
        guard let deviceName = sender.representedObject as? String else { return }
        
        let alert = NSAlert()
        alert.messageText = "Select \(deviceName)"
        alert.informativeText = "To use this AirPlay device, select it in Sound Settings, then choose 'System Default' in AdAmp.\n\nOpening Sound Settings..."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Sound Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openSoundSettings()
        }
    }
    
    // MARK: - Casting
    
    @objc func castToDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? CastDevice else { return }
        
        Task {
            do {
                try await CastManager.shared.castCurrentTrack(to: device)
                NSLog("MenuActions: Started casting to %@", device.name)
            } catch {
                NSLog("MenuActions: Failed to cast: %@", error.localizedDescription)
                
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Casting Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func stopCasting() {
        Task {
            await CastManager.shared.stopCasting()
            NSLog("MenuActions: Stopped casting")
        }
    }
    
    @objc func refreshCastDevices() {
        CastManager.shared.refreshDevices()
        NSLog("MenuActions: Refreshing cast devices")
    }
    
    @objc func refreshSonosRooms() {
        Task {
            await CastManager.shared.refreshSonosGroups()
            NSLog("MenuActions: Refreshed Sonos rooms")
        }
    }
    
    @objc func castToSonosRoom(_ sender: NSMenuItem) {
        let castManager = CastManager.shared
        
        // Check if music is loaded
        guard WindowManager.shared.audioEngine.currentTrack != nil else {
            NSLog("MenuActions: Cannot cast - no music loaded")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "No Music"
                alert.informativeText = "Load a track before casting."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }
        
        // Get selected rooms
        let selectedUDNs = castManager.selectedSonosRooms
        
        // If no rooms selected, show error
        if selectedUDNs.isEmpty {
            NSLog("MenuActions: Cannot cast - no rooms selected")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "No Room Selected"
                alert.informativeText = "Select a room first by checking it in the Sonos menu."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }
        
        // Find a device to cast to
        // sonosRooms has room UDNs, but sonosDevices only has group coordinator devices
        // We need to find a device that matches one of our selected rooms
        let rooms = castManager.sonosRooms
        let devices = castManager.sonosDevices
        
        NSLog("MenuActions: Selected UDNs: %@", selectedUDNs.joined(separator: ", "))
        NSLog("MenuActions: Available devices: %@", devices.map { "\($0.name):\($0.id)" }.joined(separator: ", "))
        NSLog("MenuActions: Available rooms: %@", rooms.map { "\($0.name):\($0.id)" }.joined(separator: ", "))
        
        // Find the first device that matches a selected room
        var targetDevice: CastDevice?
        var targetRoomUDN: String?
        
        for udn in selectedUDNs {
            // First try direct match (room is a coordinator)
            if let device = devices.first(where: { $0.id == udn }) {
                targetDevice = device
                targetRoomUDN = udn
                break
            }
            
            // If no direct match, find by room name
            if let room = rooms.first(where: { $0.id == udn }) {
                if let device = devices.first(where: { $0.name.hasPrefix(room.name) }) {
                    targetDevice = device
                    targetRoomUDN = udn
                    break
                }
            }
        }
        
        // If still no match, just use the first available Sonos device
        // IMPORTANT: Set targetRoomUDN to the device we're actually casting to, not a selected room.
        // This ensures all selected rooms get joined to the group in the loop below.
        // (Previously this was set to selectedUDNs.first, which caused that room to be
        // incorrectly filtered out of the join loop even though it wasn't receiving audio.)
        if targetDevice == nil, let firstDevice = devices.first {
            NSLog("MenuActions: No exact match, using first available device: %@", firstDevice.name)
            targetDevice = firstDevice
            targetRoomUDN = firstDevice.id
        }
        
        guard let device = targetDevice, let firstUDN = targetRoomUDN else {
            NSLog("MenuActions: Could not find any Sonos device to cast to")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "No Device Found"
                alert.informativeText = "Could not find a Sonos device to cast to. Try refreshing."
                alert.alertStyle = .warning
                alert.runModal()
            }
            return
        }
        
        Task {
            do {
                // Start casting to first room
                NSLog("MenuActions: Starting cast to '%@' (id: %@)", device.name, device.id)
                try await castManager.castCurrentTrack(to: device)
                
                // Join additional selected rooms to the group
                let otherUDNs = selectedUDNs.filter { $0 != firstUDN }
                if !otherUDNs.isEmpty {
                    // Wait a moment for cast to establish
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    
                    for udn in otherUDNs {
                        NSLog("MenuActions: Joining room %@ to cast group (coordinator: %@)", udn, device.id)
                        try await castManager.joinSonosToGroup(zoneUDN: udn, coordinatorUDN: device.id)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                    }
                }
                
                // Refresh topology
                await castManager.refreshSonosGroups()
                
            } catch {
                NSLog("MenuActions: Cast to Sonos failed: %@", error.localizedDescription)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Cast Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    // MARK: - Sonos Grouping
    
    @objc func sonosRoomJoinGroup(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SonosRoomAction,
              case .join(let coordinatorUDN, let coordinatorName) = action.action else { return }
        
        Task {
            do {
                NSLog("MenuActions: Joining room '%@' to '%@'", action.roomName, coordinatorName)
                try await CastManager.shared.joinSonosToGroup(
                    zoneUDN: action.roomUDN,
                    coordinatorUDN: coordinatorUDN
                )
                NSLog("MenuActions: '%@' joined '%@'", action.roomName, coordinatorName)
            } catch {
                NSLog("MenuActions: Sonos grouping failed: %@", error.localizedDescription)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Sonos Grouping Failed"
                    alert.informativeText = "Could not join \(action.roomName) to \(coordinatorName): \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    @objc func sonosRoomLeaveGroup(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? SonosRoomAction,
              case .leave = action.action else { return }
        
        Task {
            do {
                NSLog("MenuActions: Making room '%@' standalone", action.roomName)
                try await CastManager.shared.unjoinSonos(zoneUDN: action.roomUDN)
                NSLog("MenuActions: '%@' is now standalone", action.roomName)
            } catch {
                NSLog("MenuActions: Sonos ungrouping failed: %@", error.localizedDescription)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Sonos Ungrouping Failed"
                    alert.informativeText = "Could not make \(action.roomName) standalone: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }
    
    /// Toggle a Sonos room in/out of cast group
    @objc func toggleSonosRoom(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? SonosRoomToggle else {
            NSLog("MenuActions: toggleSonosRoom - no info found")
            return
        }
        
        let castManager = CastManager.shared
        let isCastingToSonos = castManager.activeSession?.device.type == .sonos
        
        NSLog("MenuActions: toggleSonosRoom '%@' isChecked=%d isCasting=%d", 
              info.roomName, info.isCurrentlyInGroup ? 1 : 0, isCastingToSonos ? 1 : 0)
        
        if isCastingToSonos {
            // WHILE CASTING: toggle actually joins/unjoins the Sonos group
            Task {
                do {
                    if info.isCurrentlyInGroup {
                        // Currently receiving audio - remove from group
                        NSLog("MenuActions: Removing '%@' from cast group", info.roomName)
                        try await castManager.unjoinSonos(zoneUDN: info.roomUDN)
                    } else {
                        // Not receiving audio - join to active cast
                        if let coordinatorUDN = castManager.activeSession?.device.id {
                            NSLog("MenuActions: Adding '%@' to cast group", info.roomName)
                            try await castManager.joinSonosToGroup(
                                zoneUDN: info.roomUDN,
                                coordinatorUDN: coordinatorUDN
                            )
                        }
                    }
                    
                    // Refresh topology to update UI
                    await castManager.refreshSonosGroups()
                    NSLog("MenuActions: Toggle complete for '%@'", info.roomName)
                    
                } catch {
                    NSLog("MenuActions: Toggle failed for '%@': %@", info.roomName, error.localizedDescription)
                }
            }
        } else {
            // NOT CASTING: just toggle selection state (stored locally)
            if info.isCurrentlyInGroup {
                castManager.selectedSonosRooms.remove(info.roomUDN)
                NSLog("MenuActions: Deselected '%@' for casting", info.roomName)
            } else {
                castManager.selectedSonosRooms.insert(info.roomUDN)
                NSLog("MenuActions: Selected '%@' for casting", info.roomName)
            }
        }
    }
    
    /// Legacy toggle handler
    @objc func toggleSonosZoneInGroup(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? SonosGroupingInfo else { return }
        
        Task {
            do {
                if info.isCurrentlyInGroup {
                    NSLog("MenuActions: Removing '%@' from group '%@'", info.zoneName, info.coordinatorName)
                    try await CastManager.shared.unjoinSonos(zoneUDN: info.zoneUDN)
                } else {
                    NSLog("MenuActions: Adding '%@' to group '%@'", info.zoneName, info.coordinatorName)
                    try await CastManager.shared.joinSonosToGroup(
                        zoneUDN: info.zoneUDN,
                        coordinatorUDN: info.coordinatorUDN
                    )
                }
            } catch {
                NSLog("MenuActions: Sonos grouping failed: %@", error.localizedDescription)
            }
        }
    }
    
    @objc func ungroupAllSonos() {
        let rooms = CastManager.shared.sonosRooms
        
        // Find rooms that are in groups
        let roomsToUnjoin = rooms.filter { $0.isInGroup }
        
        if roomsToUnjoin.isEmpty {
            NSLog("MenuActions: No rooms to ungroup")
            return
        }
        
        NSLog("MenuActions: Ungrouping %d rooms", roomsToUnjoin.count)
        
        Task {
            // Use actor-isolated storage for thread safety
            actor FailedRoomsCollector {
                var failed: [String] = []
                func add(_ name: String) { failed.append(name) }
                func getAll() -> [String] { failed }
            }
            let collector = FailedRoomsCollector()
            
            for room in roomsToUnjoin {
                do {
                    try await CastManager.shared.unjoinSonos(zoneUDN: room.id)
                    NSLog("MenuActions: Ungrouped '%@'", room.name)
                } catch {
                    NSLog("MenuActions: Failed to ungroup '%@': %@", room.name, error.localizedDescription)
                    await collector.add(room.name)
                }
                
                // Small delay between commands to avoid overwhelming Sonos
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
            }
            
            let failedRooms = await collector.getAll()
            if !failedRooms.isEmpty {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Some Rooms Failed to Ungroup"
                    alert.informativeText = "Failed to ungroup: \(failedRooms.joined(separator: ", "))"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            } else {
                NSLog("MenuActions: All rooms ungrouped successfully")
            }
        }
    }
    
    // MARK: - Local Library
    
    @objc func backupLibrary() {
        do {
            let backupURL = try MediaLibrary.shared.backupLibrary()
            
            let alert = NSAlert()
            alert.messageText = "Library Backed Up"
            alert.informativeText = "Your library has been backed up to:\n\(backupURL.lastPathComponent)"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show in Finder")
            
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.selectFile(backupURL.path, inFileViewerRootedAtPath: backupURL.deletingLastPathComponent().path)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Backup Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
    
    @objc func restoreLibraryFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.title = "Select Library Backup"
        panel.message = "Choose a library backup file to restore"
        
        // Start in backups directory if it exists
        let backupsDir = MediaLibrary.shared.backupsDirectory
        if FileManager.default.fileExists(atPath: backupsDir.path) {
            panel.directoryURL = backupsDir
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            confirmAndRestoreLibrary(from: url)
        }
    }
    
    @objc func restoreLibraryFromBackup(_ sender: NSMenuItem) {
        guard let backupURL = sender.representedObject as? URL else { return }
        confirmAndRestoreLibrary(from: backupURL)
    }
    
    private func confirmAndRestoreLibrary(from url: URL) {
        let currentTrackCount = MediaLibrary.shared.tracksSnapshot.count
        
        let alert = NSAlert()
        alert.messageText = "Restore Library?"
        alert.informativeText = "This will replace your current library (\(currentTrackCount) tracks) with the backup.\n\nA backup of your current library will be created automatically before restoring."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            do {
                try MediaLibrary.shared.restoreLibrary(from: url)
                
                let newTrackCount = MediaLibrary.shared.tracksSnapshot.count
                
                let successAlert = NSAlert()
                successAlert.messageText = "Library Restored"
                successAlert.informativeText = "Your library has been restored with \(newTrackCount) tracks."
                successAlert.alertStyle = .informational
                successAlert.runModal()
            } catch {
                let errorAlert = NSAlert()
                errorAlert.messageText = "Restore Failed"
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .critical
                errorAlert.runModal()
            }
        }
    }
    
    @objc func showLibraryInFinder() {
        MediaLibrary.shared.showLibraryInFinder()
    }
    
    @objc func showBackupsInFinder() {
        MediaLibrary.shared.showBackupsInFinder()
    }
    
    @objc func clearLibrary() {
        let trackCount = MediaLibrary.shared.tracksSnapshot.count
        
        let alert = NSAlert()
        alert.messageText = "Clear Library?"
        alert.informativeText = "This will remove all \(trackCount) tracks from your library. The audio files will NOT be deleted from disk.\n\nA backup will be created automatically before clearing."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Clear Library")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Create backup before clearing
            do {
                try MediaLibrary.shared.backupLibrary(customName: "pre_clear_auto_backup")
            } catch {
                NSLog("Failed to create pre-clear backup: %@", error.localizedDescription)
            }
            
            MediaLibrary.shared.clearLibrary()
            
            let successAlert = NSAlert()
            successAlert.messageText = "Library Cleared"
            successAlert.informativeText = "Your library has been cleared. A backup was saved automatically."
            successAlert.alertStyle = .informational
            successAlert.runModal()
        }
    }
    
    // MARK: - Visualizations
    
    @objc func addVisualizationsFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.title = "Select Visualizations Folder"
        panel.message = "Choose a folder containing .milk preset files"
        panel.prompt = "Add Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            // Count .milk files in the selected folder
            let fileManager = FileManager.default
            var milkCount = 0
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension.lowercased() == "milk" {
                        milkCount += 1
                    }
                }
            }
            
            if milkCount == 0 {
                let alert = NSAlert()
                alert.messageText = "No Presets Found"
                alert.informativeText = "The selected folder doesn't contain any .milk preset files. Please choose a folder with MilkDrop/projectM presets."
                alert.alertStyle = .warning
                alert.runModal()
                return
            }
            
            // Save the custom folder path
            ProjectMWrapper.customPresetsFolder = url.path
            
            // Reload presets
            WindowManager.shared.reloadVisualizationPresets()
            
            let alert = NSAlert()
            alert.messageText = "Presets Added"
            alert.informativeText = "Found \(milkCount) preset files in the selected folder. Presets have been reloaded."
            alert.alertStyle = .informational
            alert.runModal()
            
            NSLog("MenuActions: Added custom visualizations folder: %@", url.path)
        }
    }
    
    @objc func showVisualizationsFolder() {
        guard let customPath = ProjectMWrapper.customPresetsFolder else { return }
        
        let url = URL(fileURLWithPath: customPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    @objc func removeVisualizationsFolder() {
        guard ProjectMWrapper.customPresetsFolder != nil else { return }
        
        let alert = NSAlert()
        alert.messageText = "Remove Custom Presets Folder?"
        alert.informativeText = "This will remove the custom presets folder from AdAmp. The folder and its files will not be deleted from disk.\n\nOnly bundled presets will be available after this."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            ProjectMWrapper.customPresetsFolder = nil
            WindowManager.shared.reloadVisualizationPresets()
            
            NSLog("MenuActions: Removed custom visualizations folder")
        }
    }
    
    @objc func rescanVisualizations() {
        WindowManager.shared.reloadVisualizationPresets()
        
        let info = WindowManager.shared.visualizationPresetsInfo
        let total = WindowManager.shared.visualizationPresetCount
        
        let alert = NSAlert()
        alert.messageText = "Presets Rescanned"
        if info.customPath != nil {
            alert.informativeText = "Found \(total) presets (\(info.bundledCount) bundled, \(info.customCount) custom)"
        } else {
            alert.informativeText = "Found \(total) bundled presets"
        }
        alert.alertStyle = .informational
        alert.runModal()
        
        NSLog("MenuActions: Rescanned visualizations - %d total presets", total)
    }
    
    @objc func showBundledPresets() {
        guard let bundledPath = ProjectMWrapper.bundledPresetsPath else {
            let alert = NSAlert()
            alert.messageText = "Bundled Presets Not Found"
            alert.informativeText = "The bundled presets directory could not be located."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }
        
        let url = URL(fileURLWithPath: bundledPath)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    // MARK: - Exit
    
    @objc func exit() {
        NSApp.terminate(nil)
    }
}
