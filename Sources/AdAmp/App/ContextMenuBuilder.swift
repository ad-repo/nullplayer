import AppKit
import CoreAudio

/// Builds the shared right-click context menu for all Winamp windows
class ContextMenuBuilder {
    
    // MARK: - Main Menu Builder
    
    static func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let wm = WindowManager.shared
        
        // Play submenu
        menu.addItem(buildPlayMenuItem())
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
        
        // Options submenu
        menu.addItem(buildOptionsMenuItem())
        
        // Local Library submenu
        menu.addItem(buildLocalLibraryMenuItem())
        
        // Plex submenu
        menu.addItem(buildPlexMenuItem())
        
        // Output Devices submenu (includes local, AirPlay, and casting)
        menu.addItem(buildOutputDevicesMenuItem())
        
        menu.addItem(NSMenuItem.separator())
        
        // Double Size
        let doubleSize = NSMenuItem(title: "Double Size", action: #selector(MenuActions.toggleDoubleSize), keyEquivalent: "")
        doubleSize.target = MenuActions.shared
        doubleSize.state = wm.isDoubleSize ? .on : .off
        menu.addItem(doubleSize)
        
        // Always on Top
        let alwaysOnTop = NSMenuItem(title: "Always on Top", action: #selector(MenuActions.toggleAlwaysOnTop), keyEquivalent: "")
        alwaysOnTop.target = MenuActions.shared
        alwaysOnTop.state = wm.isAlwaysOnTop ? .on : .off
        menu.addItem(alwaysOnTop)
        
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
    
    // MARK: - Play Submenu
    
    private static func buildPlayMenuItem() -> NSMenuItem {
        let playItem = NSMenuItem(title: "Play", action: nil, keyEquivalent: "")
        let playMenu = NSMenu()
        
        let fileItem = NSMenuItem(title: "File...", action: #selector(MenuActions.openFile), keyEquivalent: "")
        fileItem.target = MenuActions.shared
        playMenu.addItem(fileItem)
        
        let folderItem = NSMenuItem(title: "Folder...", action: #selector(MenuActions.openFolder), keyEquivalent: "")
        folderItem.target = MenuActions.shared
        playMenu.addItem(folderItem)
        
        playItem.submenu = playMenu
        return playItem
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
        
        // Load Skin...
        let loadSkin = NSMenuItem(title: "Load Skin...", action: #selector(MenuActions.loadSkinFromFile), keyEquivalent: "")
        loadSkin.target = MenuActions.shared
        menu.addItem(loadSkin)
        
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
        if availableSkins.isEmpty {
            let noSkins = NSMenuItem(title: "(No skins found)", action: nil, keyEquivalent: "")
            noSkins.isEnabled = false
            menu.addItem(noSkins)
        } else {
            for skin in availableSkins {
                let skinItem = NSMenuItem(title: skin.name, action: #selector(MenuActions.loadSkin(_:)), keyEquivalent: "")
                skinItem.target = MenuActions.shared
                skinItem.representedObject = skin.url
                menu.addItem(skinItem)
            }
        }
        
        return menu
    }
    
    // MARK: - Options Submenu
    
    private static func buildOptionsMenuItem() -> NSMenuItem {
        let optionsItem = NSMenuItem(title: "Playback Options", action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        
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
        
        let trackCount = MediaLibrary.shared.tracksSnapshot.count
        
        // Library info header
        let infoItem = NSMenuItem(title: "\(trackCount) tracks in library", action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        libraryMenu.addItem(infoItem)
        
        libraryMenu.addItem(NSMenuItem.separator())
        
        // Backup Library
        let backupItem = NSMenuItem(title: "Backup Library...", action: #selector(MenuActions.backupLibrary), keyEquivalent: "")
        backupItem.target = MenuActions.shared
        libraryMenu.addItem(backupItem)
        
        // Restore Library submenu
        let restoreItem = NSMenuItem(title: "Restore Library", action: nil, keyEquivalent: "")
        let restoreMenu = NSMenu()
        
        // Restore from File option
        let restoreFromFile = NSMenuItem(title: "From File...", action: #selector(MenuActions.restoreLibraryFromFile), keyEquivalent: "")
        restoreFromFile.target = MenuActions.shared
        restoreMenu.addItem(restoreFromFile)
        
        // List available backups
        let backups = MediaLibrary.shared.listBackups()
        if !backups.isEmpty {
            restoreMenu.addItem(NSMenuItem.separator())
            
            let backupsHeader = NSMenuItem(title: "Recent Backups", action: nil, keyEquivalent: "")
            backupsHeader.isEnabled = false
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
        
        let isLinked = PlexManager.shared.isLinked
        
        // Link/Unlink account
        if isLinked {
            let accountName = PlexManager.shared.account?.username ?? "Account"
            let accountItem = NSMenuItem(title: "✓ \(accountName)", action: nil, keyEquivalent: "")
            accountItem.isEnabled = false
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
    
    // MARK: - Playback Submenu
    // MARK: - Output Devices Submenu (Unified)
    
    private static func buildOutputDevicesMenuItem() -> NSMenuItem {
        let outputItem = NSMenuItem(title: "Output Devices", action: nil, keyEquivalent: "")
        let outputMenu = NSMenu()
        
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
        localHeader.isEnabled = false
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
            
            // Connected AirPlay devices (via Core Audio)
            if !coreAudioWireless.isEmpty {
                let connectedHeader = NSMenuItem(title: "Connected", action: nil, keyEquivalent: "")
                connectedHeader.isEnabled = false
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
                availableHeader.isEnabled = false
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
        
        // ========== Cast Devices Section ==========
        let chromecastDevices = castManager.chromecastDevices
        let sonosDevices = castManager.sonosDevices
        let tvDevices = castManager.dlnaTVDevices
        let hasCastDevices = !chromecastDevices.isEmpty || !sonosDevices.isEmpty || !tvDevices.isEmpty
        let activeSession = castManager.activeSession
        
        outputMenu.addItem(NSMenuItem.separator())
        
        // Cast Devices submenu
        let castItem = NSMenuItem(title: "Cast Devices", action: nil, keyEquivalent: "")
        let castMenu = NSMenu()
        
        if hasCastDevices {
            // Chromecast section
            if !chromecastDevices.isEmpty {
                let chromecastHeader = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
                chromecastHeader.isEnabled = false
                castMenu.addItem(chromecastHeader)
                
                for device in chromecastDevices {
                    let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                    deviceItem.target = MenuActions.shared
                    deviceItem.representedObject = device
                    deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                    castMenu.addItem(deviceItem)
                }
            }
            
            // Sonos section
            if !sonosDevices.isEmpty {
                if !chromecastDevices.isEmpty {
                    castMenu.addItem(NSMenuItem.separator())
                }
                
                let sonosHeader = NSMenuItem(title: "Sonos", action: nil, keyEquivalent: "")
                sonosHeader.isEnabled = false
                castMenu.addItem(sonosHeader)
                
                for device in sonosDevices {
                    let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                    deviceItem.target = MenuActions.shared
                    deviceItem.representedObject = device
                    deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                    castMenu.addItem(deviceItem)
                }
            }
            
            // DLNA TVs section
            if !tvDevices.isEmpty {
                if !chromecastDevices.isEmpty || !sonosDevices.isEmpty {
                    castMenu.addItem(NSMenuItem.separator())
                }
                
                let tvHeader = NSMenuItem(title: "TVs (DLNA)", action: nil, keyEquivalent: "")
                tvHeader.isEnabled = false
                castMenu.addItem(tvHeader)
                
                for device in tvDevices {
                    let displayName = device.manufacturer != nil ? "\(device.name) [\(device.manufacturer!)]" : device.name
                    let deviceItem = NSMenuItem(title: "  \(displayName)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                    deviceItem.target = MenuActions.shared
                    deviceItem.representedObject = device
                    deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                    castMenu.addItem(deviceItem)
                }
            }
        } else {
            let noDevicesItem = NSMenuItem(title: "(Searching for devices...)", action: nil, keyEquivalent: "")
            noDevicesItem.isEnabled = false
            castMenu.addItem(noDevicesItem)
        }
        
        // Cast controls
        castMenu.addItem(NSMenuItem.separator())
        
        // Stop Casting (only shown when casting)
        if castManager.isCasting {
            let stopCastingItem = NSMenuItem(title: "Stop Casting", action: #selector(MenuActions.stopCasting), keyEquivalent: "")
            stopCastingItem.target = MenuActions.shared
            if let session = activeSession {
                stopCastingItem.title = "Stop Casting to \(session.device.name)"
            }
            castMenu.addItem(stopCastingItem)
        }
        
        // Refresh Devices
        let refreshItem = NSMenuItem(title: "Refresh Devices", action: #selector(MenuActions.refreshCastDevices), keyEquivalent: "")
        refreshItem.target = MenuActions.shared
        castMenu.addItem(refreshItem)
        
        castItem.submenu = castMenu
        outputMenu.addItem(castItem)
        
        outputItem.submenu = outputMenu
        return outputItem
    }
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
    
    // MARK: - Options
    
    @objc func setTimeElapsed() {
        WindowManager.shared.timeDisplayMode = .elapsed
    }
    
    @objc func setTimeRemaining() {
        WindowManager.shared.timeDisplayMode = .remaining
    }
    
    @objc func toggleDoubleSize() {
        WindowManager.shared.isDoubleSize.toggle()
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
    
    @objc func toggleBrowserArtworkBackground() {
        WindowManager.shared.showBrowserArtworkBackground.toggle()
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
    
    // MARK: - Exit
    
    @objc func exit() {
        NSApp.terminate(nil)
    }
}
