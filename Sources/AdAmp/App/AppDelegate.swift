import AppKit
import AVFoundation

/// Main application delegate for AdAmp
/// Manages application lifecycle and window coordination
class AppDelegate: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    
    private var windowManager: WindowManager!
    private var introPlayer: AVAudioPlayer?
    
    /// Whether the app is running in UI testing mode
    private(set) var isUITesting = false
    
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
        
        // Always play intro sound - state will be restored after intro finishes
        playIntro()
    }
    
    // MARK: - UI Testing Mode
    
    /// Set up the app for UI testing
    /// - Skips Plex server auto-connection
    /// - Disables network requests
    /// - Loads test fixtures automatically
    private func setupUITestingMode() {
        isUITesting = true
        NSLog("AdAmp: Running in UI testing mode")
        
        // Set the application dock icon
        setupDockIcon()
        
        // Configure KSPlayer for FFmpeg-only playback
        VideoPlayerWindowController.configureKSPlayer()
        
        // Skip Plex initialization in test mode
        // PlexManager.shared will still be initialized but won't auto-connect
        
        // Initialize the window manager
        windowManager = WindowManager.shared
        
        // Set up audio engine delegate
        windowManager.audioEngine.delegate = self
        
        // Use default skin for consistent test results
        // Don't load custom skins from environment in test mode
        
        // Show the main player window
        windowManager.showMainWindow()
        
        // Bring app to foreground after windows are created
        NSApp.activate(ignoringOtherApps: true)
        windowManager.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        
        // Set up the application menu
        setupMainMenu()
        
        // Skip intro sound in test mode for faster test execution
        NSLog("AdAmp: UI testing mode setup complete")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Save app state if "Remember State" is enabled
        AppStateManager.shared.saveState()
        
        // Save window positions (always saved, used by snapToDefault)
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
    
    // MARK: - Intro Sound
    
    private func playIntro() {
        guard let introURL = Bundle.module.url(forResource: "DJ Mike Llama - Llama Whippin Intro", withExtension: "mp3", subdirectory: "Resources") else {
            return
        }
        
        // Load into playlist and play (updates UI state)
        windowManager.audioEngine.loadFiles([introURL])
        windowManager.audioEngine.play()
        
        // Also play via AVAudioPlayer for reliable audio output
        do {
            introPlayer = try AVAudioPlayer(contentsOf: introURL)
            introPlayer?.delegate = self
            introPlayer?.play()
        } catch {
            print("Failed to play intro: \(error)")
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        NSLog("Intro finished playing")
        // After intro finishes, restore saved state or clear to clean state
        // Must dispatch to main thread since this delegate may be called from audio thread
        DispatchQueue.main.async { [weak self] in
            self?.introPlayer = nil
            self?.windowManager.audioEngine.clearPlaylist()
            
            // Now restore saved state if "Remember State" is enabled
            AppStateManager.shared.restoreState()
        }
    }
    
    // MARK: - Menu Setup
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // Application menu (AdAmp menu)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About AdAmp", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit AdAmp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    // MARK: - Menu Actions
    
    @objc private func showAbout() {
        // Create custom About window
        let windowWidth: CGFloat = 340
        let windowHeight: CGFloat = 440
        
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About AdAmp"
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
        let nameLabel = NSTextField(labelWithString: "AdAmp")
        nameLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 20, y: y - 34, width: windowWidth - 40, height: 34)
        contentView.addSubview(nameLabel)
        y -= 40
        
        // Version
        let versionLabel = NSTextField(labelWithString: "Version 1.0")
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 20, y: y - 18, width: windowWidth - 40, height: 18)
        contentView.addSubview(versionLabel)
        y -= 28
        
        // Tagline
        let taglineLabel = NSTextField(labelWithString: "A loaded Winamp 2 clone for macOS")
        taglineLabel.font = NSFont.systemFont(ofSize: 14)
        taglineLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        taglineLabel.alignment = .center
        taglineLabel.frame = NSRect(x: 20, y: y - 20, width: windowWidth - 40, height: 20)
        contentView.addSubview(taglineLabel)
        y -= 36
        
        // Separator
        let separator = NSBox(frame: NSRect(x: 40, y: y, width: windowWidth - 80, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)
        y -= 20
        
        // Credits
        let creditLabel = NSTextField(labelWithString: "Re-imagined by ad")
        creditLabel.font = NSFont.systemFont(ofSize: 13)
        creditLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        creditLabel.alignment = .center
        creditLabel.frame = NSRect(x: 20, y: y - 18, width: windowWidth - 40, height: 18)
        contentView.addSubview(creditLabel)
        y -= 24
        
        let thanksLabel = NSTextField(labelWithString: "Thanks to Nullsoft and Winamp")
        thanksLabel.font = NSFont.systemFont(ofSize: 12)
        thanksLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        thanksLabel.alignment = .center
        thanksLabel.frame = NSRect(x: 20, y: y - 16, width: windowWidth - 40, height: 16)
        contentView.addSubview(thanksLabel)
        y -= 36
        
        // Buttons
        let buttonWidth: CGFloat = 120
        let buttonHeight: CGFloat = 28
        let buttonSpacing: CGFloat = 12
        let totalButtonWidth = buttonWidth * 2 + buttonSpacing
        let buttonStartX = (windowWidth - totalButtonWidth) / 2
        
        let githubButton = NSButton(frame: NSRect(x: buttonStartX, y: y - buttonHeight, width: buttonWidth, height: buttonHeight))
        githubButton.title = "GitHub"
        githubButton.bezelStyle = .rounded
        githubButton.target = self
        githubButton.action = #selector(openGitHub)
        contentView.addSubview(githubButton)
        
        let linkedinButton = NSButton(frame: NSRect(x: buttonStartX + buttonWidth + buttonSpacing, y: y - buttonHeight, width: buttonWidth, height: buttonHeight))
        linkedinButton.title = "LinkedIn"
        linkedinButton.bezelStyle = .rounded
        linkedinButton.target = self
        linkedinButton.action = #selector(openLinkedIn)
        contentView.addSubview(linkedinButton)
        y -= buttonHeight + 16
        
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
    
}

// MARK: - AudioEngineDelegate

extension AppDelegate: AudioEngineDelegate {
    func audioEngineDidChangeState(_ state: PlaybackState) {
        windowManager.mainWindowController?.updatePlaybackState()
    }
    
    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        // Don't update main window time if video is playing (video has its own time source)
        guard !windowManager.isVideoPlaying else { return }
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
