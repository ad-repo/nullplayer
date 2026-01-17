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
        menu.addItem(buildWindowItem("Media Library", visible: wm.isMediaLibraryVisible, action: #selector(MenuActions.toggleMediaLibrary)))
        menu.addItem(buildWindowItem("Plex Browser", visible: wm.isPlexBrowserVisible, action: #selector(MenuActions.togglePlexBrowser)))
        
        let milkdrop = NSMenuItem(title: "Milkdrop", action: nil, keyEquivalent: "")
        milkdrop.isEnabled = false
        menu.addItem(milkdrop)
        
        menu.addItem(NSMenuItem.separator())
        
        // Skins submenu
        menu.addItem(buildSkinsMenuItem())
        
        // Options submenu
        menu.addItem(buildOptionsMenuItem())
        
        // Plex submenu
        menu.addItem(buildPlexMenuItem())
        
        // Playback submenu
        menu.addItem(buildPlaybackMenuItem())
        
        // Output Device submenu
        menu.addItem(buildOutputDeviceMenuItem())
        
        // Casting submenu
        menu.addItem(buildCastingMenuItem())
        
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
        
        // Base Skin
        let baseSkin = NSMenuItem(title: "<Base Skin>", action: #selector(MenuActions.loadBaseSkin), keyEquivalent: "")
        baseSkin.target = MenuActions.shared
        menu.addItem(baseSkin)
        
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
        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()
        
        // Skins submenu (nested)
        let skinsItem = NSMenuItem(title: "Skins", action: nil, keyEquivalent: "")
        skinsItem.submenu = buildSkinsSubmenu()
        optionsMenu.addItem(skinsItem)
        
        optionsMenu.addItem(NSMenuItem.separator())
        
        // Time display mode
        let wm = WindowManager.shared
        
        let timeElapsed = NSMenuItem(title: "Time elapsed", action: #selector(MenuActions.setTimeElapsed), keyEquivalent: "")
        timeElapsed.target = MenuActions.shared
        timeElapsed.state = wm.timeDisplayMode == .elapsed ? .on : .off
        optionsMenu.addItem(timeElapsed)
        
        let timeRemaining = NSMenuItem(title: "Time remaining", action: #selector(MenuActions.setTimeRemaining), keyEquivalent: "")
        timeRemaining.target = MenuActions.shared
        timeRemaining.state = wm.timeDisplayMode == .remaining ? .on : .off
        optionsMenu.addItem(timeRemaining)
        
        optionsMenu.addItem(NSMenuItem.separator())
        
        // Double Size
        let doubleSize = NSMenuItem(title: "Double Size", action: #selector(MenuActions.toggleDoubleSize), keyEquivalent: "")
        doubleSize.target = MenuActions.shared
        doubleSize.state = wm.isDoubleSize ? .on : .off
        optionsMenu.addItem(doubleSize)
        
        optionsMenu.addItem(NSMenuItem.separator())
        
        // Repeat/Shuffle
        let engine = wm.audioEngine
        
        let repeatItem = NSMenuItem(title: "Repeat", action: #selector(MenuActions.toggleRepeat), keyEquivalent: "")
        repeatItem.target = MenuActions.shared
        repeatItem.state = engine.repeatEnabled ? .on : .off
        optionsMenu.addItem(repeatItem)
        
        let shuffleItem = NSMenuItem(title: "Shuffle", action: #selector(MenuActions.toggleShuffle), keyEquivalent: "")
        shuffleItem.target = MenuActions.shared
        shuffleItem.state = engine.shuffleEnabled ? .on : .off
        optionsMenu.addItem(shuffleItem)
        
        optionsItem.submenu = optionsMenu
        return optionsItem
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
    
    private static func buildPlaybackMenuItem() -> NSMenuItem {
        let playbackItem = NSMenuItem(title: "Playback", action: nil, keyEquivalent: "")
        let playbackMenu = NSMenu()
        
        // Transport controls
        let previous = NSMenuItem(title: "Previous", action: #selector(MenuActions.previous), keyEquivalent: "")
        previous.target = MenuActions.shared
        playbackMenu.addItem(previous)
        
        let play = NSMenuItem(title: "Play", action: #selector(MenuActions.play), keyEquivalent: "")
        play.target = MenuActions.shared
        playbackMenu.addItem(play)
        
        let pause = NSMenuItem(title: "Pause", action: #selector(MenuActions.pause), keyEquivalent: "")
        pause.target = MenuActions.shared
        playbackMenu.addItem(pause)
        
        let stop = NSMenuItem(title: "Stop", action: #selector(MenuActions.stop), keyEquivalent: "")
        stop.target = MenuActions.shared
        playbackMenu.addItem(stop)
        
        let next = NSMenuItem(title: "Next", action: #selector(MenuActions.next), keyEquivalent: "")
        next.target = MenuActions.shared
        playbackMenu.addItem(next)
        
        playbackMenu.addItem(NSMenuItem.separator())
        
        // Seek controls
        let back5 = NSMenuItem(title: "Back 5 seconds", action: #selector(MenuActions.back5Seconds), keyEquivalent: "")
        back5.target = MenuActions.shared
        playbackMenu.addItem(back5)
        
        let fwd5 = NSMenuItem(title: "Fwd 5 seconds", action: #selector(MenuActions.fwd5Seconds), keyEquivalent: "")
        fwd5.target = MenuActions.shared
        playbackMenu.addItem(fwd5)
        
        playbackMenu.addItem(NSMenuItem.separator())
        
        // Track skip controls
        let back10 = NSMenuItem(title: "10 tracks back", action: #selector(MenuActions.back10Tracks), keyEquivalent: "")
        back10.target = MenuActions.shared
        playbackMenu.addItem(back10)
        
        let fwd10 = NSMenuItem(title: "10 tracks fwd", action: #selector(MenuActions.fwd10Tracks), keyEquivalent: "")
        fwd10.target = MenuActions.shared
        playbackMenu.addItem(fwd10)
        
        playbackItem.submenu = playbackMenu
        return playbackItem
    }
    
    // MARK: - Casting Submenu
    
    private static func buildCastingMenuItem() -> NSMenuItem {
        let castingItem = NSMenuItem(title: "Casting", action: nil, keyEquivalent: "")
        let castingMenu = NSMenu()
        
        let castManager = CastManager.shared
        let activeSession = castManager.activeSession
        
        // Ensure discovery is running when menu is built
        if !castManager.isDiscovering {
            castManager.startDiscovery()
        }
        
        // Debug: Log device counts
        let chromecastDevices = castManager.chromecastDevices
        let sonosDevices = castManager.sonosDevices
        let tvDevices = castManager.dlnaTVDevices
        NSLog("ContextMenuBuilder: Building Casting menu - Chromecast: %d, Sonos: %d, TVs: %d", 
              chromecastDevices.count, sonosDevices.count, tvDevices.count)
        
        // Chromecast section
        if !chromecastDevices.isEmpty {
            let headerItem = NSMenuItem(title: "Chromecast", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            castingMenu.addItem(headerItem)
            
            for device in chromecastDevices {
                let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device
                deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                castingMenu.addItem(deviceItem)
            }
            
            castingMenu.addItem(NSMenuItem.separator())
        }
        
        // Sonos section
        if !sonosDevices.isEmpty {
            let headerItem = NSMenuItem(title: "Sonos", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            castingMenu.addItem(headerItem)
            
            for device in sonosDevices {
                let deviceItem = NSMenuItem(title: "  \(device.name)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device
                deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                castingMenu.addItem(deviceItem)
            }
            
            castingMenu.addItem(NSMenuItem.separator())
        }
        
        // TVs section (DLNA)
        if !tvDevices.isEmpty {
            let headerItem = NSMenuItem(title: "TVs", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            castingMenu.addItem(headerItem)
            
            for device in tvDevices {
                let displayName = device.manufacturer != nil ? "\(device.name) [\(device.manufacturer!)]" : device.name
                let deviceItem = NSMenuItem(title: "  \(displayName)", action: #selector(MenuActions.castToDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device
                deviceItem.state = (activeSession?.device.id == device.id) ? .on : .off
                castingMenu.addItem(deviceItem)
            }
            
            castingMenu.addItem(NSMenuItem.separator())
        }
        
        // No devices found message
        if chromecastDevices.isEmpty && sonosDevices.isEmpty && tvDevices.isEmpty {
            let noDevicesItem = NSMenuItem(title: "(No Chromecast/Sonos/DLNA devices found)", action: nil, keyEquivalent: "")
            noDevicesItem.isEnabled = false
            castingMenu.addItem(noDevicesItem)
            
            // Add hint
            let hintItem = NSMenuItem(title: "(AirPlay devices are in Output Device menu)", action: nil, keyEquivalent: "")
            hintItem.isEnabled = false
            castingMenu.addItem(hintItem)
            
            castingMenu.addItem(NSMenuItem.separator())
        }
        
        // Stop Casting (only shown when casting)
        if castManager.isCasting {
            let stopCastingItem = NSMenuItem(title: "Stop Casting", action: #selector(MenuActions.stopCasting), keyEquivalent: "")
            stopCastingItem.target = MenuActions.shared
            if let session = castManager.activeSession {
                stopCastingItem.title = "Stop Casting to \(session.device.name)"
            }
            castingMenu.addItem(stopCastingItem)
        }
        
        // Refresh Devices
        let refreshItem = NSMenuItem(title: "Refresh Devices", action: #selector(MenuActions.refreshCastDevices), keyEquivalent: "")
        refreshItem.target = MenuActions.shared
        castingMenu.addItem(refreshItem)
        
        castingItem.submenu = castingMenu
        return castingItem
    }
    
    // MARK: - Output Device Submenu
    
    private static func buildOutputDeviceMenuItem() -> NSMenuItem {
        let outputItem = NSMenuItem(title: "Output Device", action: nil, keyEquivalent: "")
        let outputMenu = NSMenu()
        
        let manager = AudioOutputManager.shared
        let coreAudioDevices = manager.outputDevices
        let airPlayDevices = manager.discoveredAirPlayDevices
        let currentDeviceID = WindowManager.shared.audioEngine.currentOutputDeviceID
        
        // System Default option
        let defaultItem = NSMenuItem(title: "System Default", action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
        defaultItem.target = MenuActions.shared
        defaultItem.representedObject = nil as AudioDeviceID?
        defaultItem.state = currentDeviceID == nil ? .on : .off
        outputMenu.addItem(defaultItem)
        
        // Local/wired devices
        let localDevices = coreAudioDevices.filter { !$0.isWireless }
        if !localDevices.isEmpty {
            outputMenu.addItem(NSMenuItem.separator())
            
            for device in localDevices {
                let deviceItem = NSMenuItem(title: device.name, action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device.id
                deviceItem.state = (currentDeviceID == device.id) ? NSControl.StateValue.on : NSControl.StateValue.off
                outputMenu.addItem(deviceItem)
            }
        }
        
        // Core Audio wireless devices
        let coreAudioWireless = coreAudioDevices.filter { $0.isWireless }
        
        // Combined wireless: Core Audio wireless + discovered AirPlay
        let hasWireless = !coreAudioWireless.isEmpty || !airPlayDevices.isEmpty
        
        if hasWireless {
            outputMenu.addItem(NSMenuItem.separator())
            
            // Create AirPlay submenu
            let airplayItem = NSMenuItem(title: "AirPlay", action: nil, keyEquivalent: "")
            let airplayMenu = NSMenu()
            
            // Core Audio wireless devices (already connected)
            for device in coreAudioWireless {
                let deviceItem = NSMenuItem(title: device.name, action: #selector(MenuActions.selectOutputDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device.id
                deviceItem.state = (currentDeviceID == device.id) ? NSControl.StateValue.on : NSControl.StateValue.off
                airplayMenu.addItem(deviceItem)
            }
            
            // Discovered AirPlay devices (need to connect via Sound Settings)
            for device in airPlayDevices {
                let deviceItem = NSMenuItem(title: device.name, action: #selector(MenuActions.selectAirPlayDevice(_:)), keyEquivalent: "")
                deviceItem.target = MenuActions.shared
                deviceItem.representedObject = device.name
                airplayMenu.addItem(deviceItem)
            }
            
            airplayItem.submenu = airplayMenu
            outputMenu.addItem(airplayItem)
        }
        
        // Sound Settings option
        outputMenu.addItem(NSMenuItem.separator())
        let soundSettings = NSMenuItem(title: "Sound Settings...", action: #selector(MenuActions.openSoundSettings), keyEquivalent: "")
        soundSettings.target = MenuActions.shared
        outputMenu.addItem(soundSettings)
        
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
    
    @objc func loadSkin(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        WindowManager.shared.loadSkin(from: url)
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
    
    // MARK: - Exit
    
    @objc func exit() {
        NSApp.terminate(nil)
    }
}
