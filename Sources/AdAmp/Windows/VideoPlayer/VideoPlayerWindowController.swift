import AppKit

/// Window controller for video playback
class VideoPlayerWindowController: NSWindowController, NSWindowDelegate {
    
    // MARK: - Properties
    
    private var videoPlayerView: VideoPlayerView!
    
    // MARK: - Initialization
    
    init() {
        // Create a standard window for video playback
        let contentRect = NSRect(x: 0, y: 0, width: 854, height: 480)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.title = "Video Player"
        window.minSize = NSSize(width: 480, height: 270)
        window.isReleasedWhenClosed = false
        window.center()
        
        // Dark appearance for video
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        
        super.init(window: window)
        
        setupVideoView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupVideoView() {
        window?.delegate = self
        
        videoPlayerView = VideoPlayerView(frame: window!.contentView!.bounds)
        videoPlayerView.autoresizingMask = [.width, .height]
        window?.contentView?.addSubview(videoPlayerView)
    }
    
    // MARK: - Playback Control
    
    /// Play a video from URL with optional title
    func play(url: URL, title: String) {
        window?.title = title
        videoPlayerView.play(url: url, title: title)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
    
    /// Play a Plex movie
    func play(movie: PlexMovie) {
        guard let url = PlexManager.shared.streamURL(for: movie) else {
            NSLog("Failed to get stream URL for movie: %@", movie.title)
            return
        }
        play(url: url, title: movie.title)
    }
    
    /// Play a Plex episode
    func play(episode: PlexEpisode) {
        guard let url = PlexManager.shared.streamURL(for: episode) else {
            NSLog("Failed to get stream URL for episode: %@", episode.title)
            return
        }
        let title = "\(episode.grandparentTitle ?? "Unknown") - \(episode.episodeIdentifier) - \(episode.title)"
        play(url: url, title: title)
    }
    
    /// Stop playback
    func stop() {
        videoPlayerView.stop()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        stop()
    }
    
    // MARK: - Keyboard Shortcuts
    
    @objc func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }
}
