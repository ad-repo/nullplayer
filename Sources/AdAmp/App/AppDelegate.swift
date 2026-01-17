import AppKit

/// Main application delegate for AdAmp
/// Manages application lifecycle and window coordination
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var windowManager: WindowManager!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set the application dock icon
        setupDockIcon()
        
        // Configure KSPlayer for FFmpeg-only playback
        VideoPlayerWindowController.configureKSPlayer()
        
        // Initialize the window manager
        windowManager = WindowManager.shared
        
        // Set up audio engine delegate
        windowManager.audioEngine.delegate = self
        
        // Load skin from environment variable if set (for testing)
        if let skinPath = ProcessInfo.processInfo.environment["ADAMP_SKIN"] {
            let skinURL = URL(fileURLWithPath: skinPath)
            windowManager.loadSkin(from: skinURL)
        }
        
        // Show the main player window
        windowManager.showMainWindow()
        
        // Bring app to foreground after windows are created
        NSApp.activate(ignoringOtherApps: true)
        windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        
        // Set up the application menu
        setupMainMenu()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Save state before quitting
        windowManager.saveWindowPositions()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running even if windows are closed (like classic Winamp)
        return false
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        return true
    }
    
    // MARK: - Dock Icon Setup
    
    private func setupDockIcon() {
        // Load the app icon from the Resources bundle
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }
    
    // MARK: - Menu Setup
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // Application menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About AdAmp", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit AdAmp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        
        fileMenu.addItem(withTitle: "Open File...", action: #selector(openFile), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Open Folder...", action: #selector(openFolder), keyEquivalent: "O")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Load Skin...", action: #selector(loadSkin), keyEquivalent: "")
        
        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        
        viewMenu.addItem(withTitle: "Main Window", action: #selector(toggleMainWindow), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Playlist", action: #selector(togglePlaylist), keyEquivalent: "2")
        viewMenu.addItem(withTitle: "Equalizer", action: #selector(toggleEqualizer), keyEquivalent: "3")
        viewMenu.addItem(withTitle: "Media Library", action: #selector(toggleMediaLibrary), keyEquivalent: "l")
        viewMenu.addItem(withTitle: "Plex Browser", action: #selector(togglePlexBrowser), keyEquivalent: "p")
        
        // Plex menu
        let plexMenuItem = NSMenuItem()
        mainMenu.addItem(plexMenuItem)
        
        let plexMenu = NSMenu(title: "Plex")
        plexMenuItem.submenu = plexMenu
        
        plexMenu.addItem(withTitle: "Link Plex Account...", action: #selector(linkPlexAccount), keyEquivalent: "")
        plexMenu.addItem(withTitle: "Unlink Account", action: #selector(unlinkPlexAccount), keyEquivalent: "")
        plexMenu.addItem(NSMenuItem.separator())
        plexMenu.addItem(withTitle: "Show Plex Browser", action: #selector(togglePlexBrowser), keyEquivalent: "")
        
        // Playback menu
        let playbackMenuItem = NSMenuItem()
        mainMenu.addItem(playbackMenuItem)
        
        let playbackMenu = NSMenu(title: "Playback")
        playbackMenuItem.submenu = playbackMenu
        
        playbackMenu.addItem(withTitle: "Play", action: #selector(play), keyEquivalent: "x")
        playbackMenu.addItem(withTitle: "Pause", action: #selector(pause), keyEquivalent: "c")
        playbackMenu.addItem(withTitle: "Stop", action: #selector(stop), keyEquivalent: "v")
        playbackMenu.addItem(NSMenuItem.separator())
        playbackMenu.addItem(withTitle: "Previous", action: #selector(previous), keyEquivalent: "z")
        playbackMenu.addItem(withTitle: "Next", action: #selector(next), keyEquivalent: "b")
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    // MARK: - Menu Actions
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "AdAmp"
        alert.informativeText = "A classic Winamp clone for macOS\nVersion 1.0"
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    @objc private func showPreferences() {
        // TODO: Implement preferences window
    }
    
    @objc private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            windowManager.audioEngine.loadFiles(urls)
        }
    }
    
    @objc private func openFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK, let url = panel.url {
            windowManager.audioEngine.loadFolder(url)
        }
    }
    
    @objc private func loadSkin() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.init(filenameExtension: "wsz")!]
        
        if panel.runModal() == .OK, let url = panel.url {
            windowManager.loadSkin(from: url)
        }
    }
    
    @objc private func toggleMainWindow() {
        windowManager.toggleMainWindow()
    }
    
    @objc private func togglePlaylist() {
        windowManager.togglePlaylist()
    }
    
    @objc private func toggleEqualizer() {
        windowManager.toggleEqualizer()
    }
    
    @objc private func toggleMediaLibrary() {
        windowManager.toggleMediaLibrary()
    }
    
    @objc private func togglePlexBrowser() {
        windowManager.togglePlexBrowser()
    }
    
    @objc private func linkPlexAccount() {
        windowManager.showPlexLinkSheet()
    }
    
    @objc private func unlinkPlexAccount() {
        // Confirm before unlinking
        let alert = NSAlert()
        alert.messageText = "Unlink Plex Account?"
        alert.informativeText = "This will remove your Plex account from AdAmp. You can link it again later."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Unlink")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            windowManager.unlinkPlexAccount()
        }
    }
    
    @objc private func play() {
        windowManager.audioEngine.play()
    }
    
    @objc private func pause() {
        windowManager.audioEngine.pause()
    }
    
    @objc private func stop() {
        windowManager.audioEngine.stop()
    }
    
    @objc private func previous() {
        windowManager.audioEngine.previous()
    }
    
    @objc private func next() {
        windowManager.audioEngine.next()
    }
}

// MARK: - AudioEngineDelegate

extension AppDelegate: AudioEngineDelegate {
    func audioEngineDidChangeState(_ state: PlaybackState) {
        windowManager.mainWindowController?.updatePlaybackState()
    }
    
    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        windowManager.mainWindowController?.updateTime(current: current, duration: duration)
    }
    
    func audioEngineDidChangeTrack(_ track: Track?) {
        windowManager.mainWindowController?.updateTrackInfo(track)
    }
    
    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        windowManager.mainWindowController?.updateSpectrum(levels)
    }
    
    func audioEngineDidChangePlaylist() {
        windowManager.playlistWindowController?.reloadPlaylist()
    }
}
