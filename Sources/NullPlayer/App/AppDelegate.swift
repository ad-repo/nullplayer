import AppKit

/// Main application delegate for NullPlayer
/// Manages application lifecycle and window coordination
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var windowManager: WindowManager!
    private var dynamicMenuBuilders: [ObjectIdentifier: () -> NSMenu] = [:]
    
    /// Whether the app is running in UI testing mode
    private(set) var isUITesting = false
    
    /// Files to open after app finishes launching (when opened via double-click before app is ready)
    private var pendingFilesToOpen: [URL] = []
    
    /// Whether the app has finished launching and is ready to handle file opens
    private var isAppReady = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for UI testing mode
        if CommandLine.arguments.contains("--ui-testing") {
            setupUITestingMode()
            return
        }
        
        // Set the application dock icon
        setupDockIcon()
        
        // Configure KSPlayer for FFmpeg-only playback
        VideoPlayerWindowController.configureKSPlayer()
        
        // Initialize Plex manager early to start preloading library data
        // Accessing .shared triggers the singleton init which loads saved account and starts preload
        _ = PlexManager.shared
        
        // Initialize the window manager
        windowManager = WindowManager.shared
        
        // Initialize Now Playing integration for Discord Music Presence and media controls
        NowPlayingManager.shared.setup()
        
        // Set up audio engine delegate
        windowManager.audioEngine.delegate = self
        // Main window always shows a mini spectrum overlay — register as permanent consumer
        windowManager.audioEngine.addSpectrumConsumer("mainWindowSpectrum")

        // Load skin from environment variable if set (for testing)
        #if DEBUG
        if let skinPath = ProcessInfo.processInfo.environment["NULLPLAYER_SKIN"] {
            let skinURL = URL(fileURLWithPath: skinPath)
            windowManager.loadSkin(from: skinURL)
        }
        #endif
        
        // Classic mode: spectrum transparent backgrounds always start off.
        // Waveform transparency is guarded by isRunningModernUI in WaveformAppearancePreferences,
        // so no reset is needed there.
        if !windowManager.isModernUIEnabled {
            UserDefaults.standard.set(false, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.transparentBgKey)
            UserDefaults.standard.set(false, forKey: VisClassicBridge.PreferenceScope.mainWindow.transparentBgKey)
        }

        // Initialize modern skin engine if modern mode is enabled
        if windowManager.isModernUIEnabled {
            ModernSkinEngine.shared.loadPreferredSkin()
        }
        
        // Show the main player window
        windowManager.showMainWindow()
        
        // Bring app to foreground after windows are created
        NSApp.activate(ignoringOtherApps: true)
        windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        
        // Set up the application menu
        setupMainMenu()

        // Start cast discovery from app lifecycle, not from menu construction.
        CastManager.shared.startDiscovery()
        
        // Restore settings state (skin, volume, EQ, windows)
        AppStateManager.shared.restoreSettingsState()
        
        // Mark app as ready for file opens
        isAppReady = true
        
        // If files were passed at launch (double-clicked to open), play them
        if !pendingFilesToOpen.isEmpty {
            processPendingFiles()
        } else {
            // Restore playlist state
            AppStateManager.shared.restorePlaylistState()
        }
    }
    
    // MARK: - UI Testing Mode
    
    /// Set up the app for UI testing
    /// - Skips Plex server auto-connection
    /// - Disables network requests
    /// - Loads test fixtures automatically
    private func setupUITestingMode() {
        isUITesting = true
        NSLog("NullPlayer: Running in UI testing mode")
        
        // Set the application dock icon
        setupDockIcon()
        
        // Configure KSPlayer for FFmpeg-only playback
        VideoPlayerWindowController.configureKSPlayer()
        
        // Skip Plex initialization in test mode
        // PlexManager.shared will still be initialized but won't auto-connect
        
        // Initialize the window manager
        windowManager = WindowManager.shared
        
        // Initialize Now Playing integration (still useful in test mode for media key handling)
        NowPlayingManager.shared.setup()
        
        // Set up audio engine delegate
        windowManager.audioEngine.delegate = self
        windowManager.audioEngine.addSpectrumConsumer("mainWindowSpectrum")

        // Use default skin for consistent test results
        // Don't load custom skins from environment in test mode
        
        // Show the main player window
        windowManager.showMainWindow()
        
        // Bring app to foreground after windows are created
        NSApp.activate(ignoringOtherApps: true)
        windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        
        // Set up the application menu
        setupMainMenu()

        // Skip network discovery in UI testing mode.
        
        // Mark app as ready for file opens
        isAppReady = true
        
        NSLog("NullPlayer: UI testing mode setup complete")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop any active casting (video or audio)
        // Use sync version to avoid deadlock - async stopCasting() uses MainActor.run
        // which can't execute while main thread is blocked waiting for completion
        CastManager.shared.stopCastingSync()
        
        // Save app state if "Remember State" is enabled
        AppStateManager.shared.saveState()
        
        // Save window positions (always saved, used by snapToDefault)
        windowManager.saveWindowPositions()

        // Flush WAL to disk before exit so history survives hard shutdown / reboot
        MediaLibraryStore.shared.checkpoint()
        MediaLibraryStore.shared.close()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running even if windows are closed (like classic classic player)
        return false
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        return true
    }
    
    // MARK: - File Open Handling
    
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        
        // Filter to audio files only
        let audioURLs = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "alac"].contains(ext)
        }
        
        guard !audioURLs.isEmpty else {
            NSApp.reply(toOpenOrPrint: .failure)
            return
        }
        
        // If app isn't ready yet (called before applicationDidFinishLaunching completes),
        // store the files to be opened once the app is ready
        guard isAppReady else {
            pendingFilesToOpen.append(contentsOf: audioURLs)
            NSApp.reply(toOpenOrPrint: .success)
            return
        }
        
        // Load files into the audio engine
        windowManager.audioEngine.loadFiles(audioURLs)
        windowManager.audioEngine.play()
        
        NSApp.reply(toOpenOrPrint: .success)
    }
    
    /// Process files that were queued before app finished launching
    private func processPendingFiles() {
        guard !pendingFilesToOpen.isEmpty else { return }
        
        let filesToOpen = pendingFilesToOpen
        pendingFilesToOpen = []
        
        // Load and play the files
        windowManager.audioEngine.loadFiles(filesToOpen)
        windowManager.audioEngine.play()
    }
    
    // MARK: - Dock Icon Setup
    
    private func setupDockIcon() {
        // In a proper .app bundle, CFBundleIconFile in Info.plist registers AppIcon.icns
        // automatically — setting applicationIconImage would override it with a plain PNG
        // and produce a mis-sized dock icon. Only set it in SPM dev builds (bare executable)
        // where no .icns exists in the bundle.
        guard Bundle.main.url(forResource: "AppIcon", withExtension: "icns") == nil else { return }
        if let iconURL = BundleHelper.url(forResource: "AppIcon", withExtension: "png"),
           let iconImage = NSImage(contentsOf: iconURL) {
            iconImage.size = NSSize(width: 128, height: 128)
            NSApplication.shared.applicationIconImage = iconImage
        }
    }
    
    // MARK: - Menu Setup
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // Application menu (NullPlayer menu)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(
            withTitle: "About nullPlayer",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit nullPlayer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        addDynamicTopLevelMenu(title: "Windows", to: mainMenu, builder: ContextMenuBuilder.buildMenuBarWindowsMenu, refreshOnOpen: true)
        addDynamicTopLevelMenu(title: "Skins", to: mainMenu, builder: ContextMenuBuilder.buildMenuBarUIMenu, refreshOnOpen: true)
        addDynamicTopLevelMenu(title: "Playback", to: mainMenu, builder: ContextMenuBuilder.buildMenuBarPlaybackMenu, refreshOnOpen: true)
        addDynamicTopLevelMenu(title: "Visuals", to: mainMenu, builder: ContextMenuBuilder.buildMenuBarVisualsMenu, refreshOnOpen: true)
        addDynamicTopLevelMenu(title: "Libraries", to: mainMenu, builder: ContextMenuBuilder.buildMenuBarLibrariesMenu, refreshOnOpen: true)
        addDynamicTopLevelMenu(title: "Output", to: mainMenu, builder: ContextMenuBuilder.buildMenuBarOutputMenu, refreshOnOpen: true)
        
        NSApplication.shared.mainMenu = mainMenu
    }

    private func addDynamicTopLevelMenu(title: String, to mainMenu: NSMenu, builder: @escaping () -> NSMenu, refreshOnOpen: Bool = false) {
        let topLevelItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        mainMenu.addItem(topLevelItem)

        let submenu = builder()
        submenu.title = title
        if refreshOnOpen {
            submenu.delegate = self
            dynamicMenuBuilders[ObjectIdentifier(submenu)] = builder
        }
        topLevelItem.submenu = submenu
    }
    
    // MARK: - Menu Actions
    
    @objc private func showAbout() {
        // Create custom About window
        let windowWidth: CGFloat = 340
        let windowHeight: CGFloat = 516
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About nullPlayer"
        window.isMovableByWindowBackground = true
        window.center()
        
        // Dark background
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor
        window.contentView = contentView
        
        var y: CGFloat = windowHeight - 30
        
        // App icon
        let iconSize: CGFloat = 96
        let iconView = NSImageView(frame: NSRect(x: (windowWidth - iconSize) / 2, y: y - iconSize, width: iconSize, height: iconSize))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)
        y -= iconSize + 16
        
        // App name
        let nameLabel = NSTextField(labelWithString: "nullPlayer")
        nameLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 20, y: y - 34, width: windowWidth - 40, height: 34)
        contentView.addSubview(nameLabel)
        y -= 40
        
        // Version
        let versionLabel = NSTextField(labelWithString: "Version \(BundleHelper.appVersion)")
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 20, y: y - 18, width: windowWidth - 40, height: 18)
        contentView.addSubview(versionLabel)
        y -= 28
        
        // Tagline
        let taglineLabel = NSTextField(wrappingLabelWithString: "A throwback player for modern personal media")
        taglineLabel.font = NSFont.systemFont(ofSize: 14)
        taglineLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        taglineLabel.alignment = .center
        taglineLabel.frame = NSRect(x: 20, y: y - 40, width: windowWidth - 40, height: 40)
        contentView.addSubview(taglineLabel)
        y -= 50
        
        // Separator
        let separator = NSBox(frame: NSRect(x: 40, y: y, width: windowWidth - 80, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)
        y -= 20
        
        // Credits
        let thanksLabel = NSTextField(labelWithString: "Please add a ⭐ star ⭐ on github")
        thanksLabel.font = NSFont.systemFont(ofSize: 15)
        thanksLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        thanksLabel.alignment = .center
        thanksLabel.frame = NSRect(x: 20, y: y - 18, width: windowWidth - 40, height: 18)
        contentView.addSubview(thanksLabel)
        y -= 36

        // // sthanks
        // let sthanksLabel = NSTextField(labelWithString: "Thanks to u/SpaXter25 for QE and PD")
        // sthanksLabel.font = NSFont.systemFont(ofSize: 12)
        // sthanksLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        // sthanksLabel.alignment = .center
        // sthanksLabel.frame = NSRect(x: 20, y: y - 16, width: windowWidth - 40, height: 16)
        // contentView.addSubview(sthanksLabel)
        // y -= 36
        
        // Buttons (3 on one row)
        let buttonWidth: CGFloat = 90
        let buttonHeight: CGFloat = 28
        let buttonSpacing: CGFloat = 10
        let totalButtonWidth = buttonWidth * 3 + buttonSpacing * 2
        let buttonStartX = (windowWidth - totalButtonWidth) / 2
        
        let githubButton = NSButton(frame: NSRect(x: buttonStartX, y: y - buttonHeight, width: buttonWidth, height: buttonHeight))
        githubButton.title = "GitHub"
        githubButton.bezelStyle = .rounded
        githubButton.contentTintColor = .white
        githubButton.wantsLayer = true
        githubButton.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1.0).cgColor
        githubButton.layer?.cornerRadius = 5
        githubButton.target = self
        githubButton.action = #selector(openGitHub)
        contentView.addSubview(githubButton)
        
        let linkedinButton = NSButton(frame: NSRect(x: buttonStartX + buttonWidth + buttonSpacing, y: y - buttonHeight, width: buttonWidth, height: buttonHeight))
        linkedinButton.title = "LinkedIn"
        linkedinButton.bezelStyle = .rounded
        linkedinButton.contentTintColor = .white
        linkedinButton.wantsLayer = true
        linkedinButton.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1.0).cgColor
        linkedinButton.layer?.cornerRadius = 5
        linkedinButton.target = self
        linkedinButton.action = #selector(openLinkedIn)
        contentView.addSubview(linkedinButton)
        
        let redditButton = NSButton(frame: NSRect(x: buttonStartX + (buttonWidth + buttonSpacing) * 2, y: y - buttonHeight, width: buttonWidth, height: buttonHeight))
        redditButton.title = "Reddit"
        redditButton.bezelStyle = .rounded
        redditButton.contentTintColor = .white
        redditButton.wantsLayer = true
        redditButton.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1.0).cgColor
        redditButton.layer?.cornerRadius = 5
        redditButton.target = self
        redditButton.action = #selector(openReddit)
        contentView.addSubview(redditButton)
        y -= buttonHeight + 12
        
        // Disclaimer
        let disclaimerLabel = NSTextField(wrappingLabelWithString: "This is a clean room project")
        disclaimerLabel.font = NSFont.systemFont(ofSize: 12)
        disclaimerLabel.textColor = NSColor(white: 0.4, alpha: 1.0)
        disclaimerLabel.alignment = .center
        disclaimerLabel.frame = NSRect(x: 20, y: y - 28, width: windowWidth - 40, height: 28)
        contentView.addSubview(disclaimerLabel)
        y -= 36
        
        // OK button (centered, prominent)
        let okButton = NSButton(frame: NSRect(x: (windowWidth - buttonWidth) / 2, y: y - buttonHeight, width: buttonWidth, height: buttonHeight))
        okButton.title = "OK"
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"  // Enter key closes
        okButton.target = self
        okButton.action = #selector(closeAboutWindow)
        contentView.addSubview(okButton)
        
        // Store window reference and show
        aboutWindow = window
        window.level = .modalPanel  // Ensure dialog appears above floating windows
        window.makeKeyAndOrderFront(nil)
    }
    
    private var aboutWindow: NSPanel?
    
    @objc private func closeAboutWindow() {
        aboutWindow?.close()
        aboutWindow = nil
    }
    
    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/ad-repo") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openLinkedIn() {
        if let url = URL(string: "https://www.linkedin.com/in/andrew-d-9b83aa148/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openReddit() {
        if let url = URL(string: "https://www.reddit.com/r/NullPlayer/") {
            NSWorkspace.shared.open(url)
        }
    }
    
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let builder = dynamicMenuBuilders[ObjectIdentifier(menu)] else { return }

        let rebuiltMenu = builder()
        menu.removeAllItems()

        while let item = rebuiltMenu.items.first {
            rebuiltMenu.removeItem(item)
            menu.addItem(item)
        }
    }
}

// MARK: - AudioEngineDelegate

extension AppDelegate: AudioEngineDelegate {
    func audioEngineDidChangeState(_ state: PlaybackState) {
        windowManager.mainWindowController?.updatePlaybackState()
    }
    
    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        // Don't update main window time if video session is active (video has its own time source)
        guard !windowManager.isVideoActivePlayback else { return }
        windowManager.mainWindowController?.updateTime(current: current, duration: duration)
        windowManager.updateWaveformTime(current: current, duration: duration)
    }
    
    func audioEngineDidChangeTrack(_ track: Track?) {
        windowManager.mainWindowController?.updateTrackInfo(track)
        windowManager.updateWaveformTrack(track)
    }
    
    func audioEngineDidUpdateSpectrum(_ levels: [Float]) {
        windowManager.mainWindowController?.updateSpectrum(levels)
    }
    
    func audioEngineDidChangePlaylist() {
        windowManager.playlistWindowController?.reloadPlaylist()
    }
    
    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error) {
        // Log the failure - UI notification is handled via NotificationCenter
        NSLog("AppDelegate: Failed to load track '%@': %@", track.title, error.localizedDescription)
    }
}
