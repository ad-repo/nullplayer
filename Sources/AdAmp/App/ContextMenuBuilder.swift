import AppKit

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
        
        let milkdrop = NSMenuItem(title: "Milkdrop", action: nil, keyEquivalent: "")
        milkdrop.isEnabled = false
        menu.addItem(milkdrop)
        
        menu.addItem(NSMenuItem.separator())
        
        // Skins submenu
        menu.addItem(buildSkinsMenuItem())
        
        // Options submenu
        menu.addItem(buildOptionsMenuItem())
        
        // Playback submenu
        menu.addItem(buildPlaybackMenuItem())
        
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
    
    // MARK: - Exit
    
    @objc func exit() {
        NSApp.terminate(nil)
    }
}
