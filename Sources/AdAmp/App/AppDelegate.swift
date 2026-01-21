import AppKit
import AVFoundation

/// Main application delegate for AdAmp
/// Manages application lifecycle and window coordination
class AppDelegate: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate {
    
    private var windowManager: WindowManager!
    private var introPlayer: AVAudioPlayer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
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
        
        // Play intro sound
        playIntro()
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
        NSLog("Intro finished playing, clearing playlist")
        // Clear the playlist and stop when intro finishes - resets UI to clean state
        // Must dispatch to main thread since this delegate may be called from audio thread
        DispatchQueue.main.async { [weak self] in
            self?.windowManager.audioEngine.clearPlaylist()
            self?.introPlayer = nil
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
        let alert = NSAlert()
        alert.messageText = "AdAmp"
        alert.informativeText = "A classic Winamp clone+ for macOS\n\nVersion 1.0\n\nRe-imagined by ad\n\nThanks to Nullsoft and Winamp"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "GitHub")
        alert.addButton(withTitle: "LinkedIn")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/ad-repo") {
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertThirdButtonReturn {
            if let url = URL(string: "https://www.linkedin.com/in/andrew-d-9b83aa148/") {
                NSWorkspace.shared.open(url)
            }
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
