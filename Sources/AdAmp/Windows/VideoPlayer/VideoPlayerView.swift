import AppKit
import AVKit
import AVFoundation

/// Video player view using AVKit's AVPlayerView
class VideoPlayerView: NSView {
    
    // MARK: - Properties
    
    private var playerView: AVPlayerView!
    private var player: AVPlayer?
    private var loadingIndicator: NSProgressIndicator?
    private var currentTitle: String = ""
    
    /// Time observer for playback position
    private var timeObserver: Any?
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    deinit {
        removeTimeObserver()
        player?.pause()
        player = nil
    }
    
    // MARK: - Setup
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        
        // Create AVPlayerView
        playerView = AVPlayerView(frame: bounds)
        playerView.autoresizingMask = [.width, .height]
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = true
        playerView.showsFrameSteppingButtons = true
        playerView.showsSharingServiceButton = false
        playerView.allowsPictureInPicturePlayback = true
        addSubview(playerView)
        
        // Create loading indicator
        setupLoadingIndicator()
    }
    
    private func setupLoadingIndicator() {
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.isIndeterminate = true
        indicator.isHidden = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)
        
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        loadingIndicator = indicator
    }
    
    // MARK: - Playback
    
    /// Play video from URL with title
    func play(url: URL, title: String) {
        currentTitle = title
        
        // Show loading indicator
        showLoading(true)
        
        // Clean up existing player
        removeTimeObserver()
        player?.pause()
        
        // Create new player
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        playerView.player = player
        
        // Observe buffering state
        playerItem.addObserver(self, forKeyPath: "status", options: [.new, .initial], context: nil)
        playerItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: .new, context: nil)
        playerItem.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: .new, context: nil)
        
        // Start playback when ready
        if playerItem.status == .readyToPlay {
            showLoading(false)
            player?.play()
        }
        
        NSLog("VideoPlayerView: Playing %@ from %@", title, url.absoluteString)
    }
    
    /// Stop playback
    func stop() {
        removeTimeObserver()
        
        // Remove observers from current item
        if let item = player?.currentItem {
            item.removeObserver(self, forKeyPath: "status")
            item.removeObserver(self, forKeyPath: "playbackBufferEmpty")
            item.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        }
        
        player?.pause()
        player = nil
        playerView.player = nil
        showLoading(false)
    }
    
    /// Toggle play/pause
    func togglePlayPause() {
        guard let player = player else { return }
        
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
    }
    
    /// Seek to time
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    /// Skip forward by seconds
    func skipForward(_ seconds: TimeInterval = 10) {
        guard let player = player,
              let currentTime = player.currentItem?.currentTime() else { return }
        
        let newTime = CMTimeAdd(currentTime, CMTime(seconds: seconds, preferredTimescale: 600))
        player.seek(to: newTime)
    }
    
    /// Skip backward by seconds
    func skipBackward(_ seconds: TimeInterval = 10) {
        guard let player = player,
              let currentTime = player.currentItem?.currentTime() else { return }
        
        let newTime = CMTimeSubtract(currentTime, CMTime(seconds: seconds, preferredTimescale: 600))
        player.seek(to: newTime)
    }
    
    // MARK: - Loading Indicator
    
    private func showLoading(_ show: Bool) {
        DispatchQueue.main.async { [weak self] in
            if show {
                self?.loadingIndicator?.isHidden = false
                self?.loadingIndicator?.startAnimation(nil)
            } else {
                self?.loadingIndicator?.stopAnimation(nil)
                self?.loadingIndicator?.isHidden = true
            }
        }
    }
    
    // MARK: - KVO
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem else { return }
        
        switch keyPath {
        case "status":
            switch item.status {
            case .readyToPlay:
                NSLog("VideoPlayerView: Ready to play")
                showLoading(false)
                player?.play()
            case .failed:
                NSLog("VideoPlayerView: Failed to load - %@", item.error?.localizedDescription ?? "Unknown error")
                showLoading(false)
            case .unknown:
                NSLog("VideoPlayerView: Status unknown")
            @unknown default:
                break
            }
            
        case "playbackBufferEmpty":
            if item.isPlaybackBufferEmpty {
                NSLog("VideoPlayerView: Buffer empty, showing loading")
                showLoading(true)
            }
            
        case "playbackLikelyToKeepUp":
            if item.isPlaybackLikelyToKeepUp {
                NSLog("VideoPlayerView: Buffer filled, hiding loading")
                showLoading(false)
            }
            
        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    // MARK: - Time Observer
    
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Could use this to update progress UI if needed
            _ = self
        }
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    // MARK: - Keyboard Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space - toggle play/pause
            togglePlayPause()
        case 123: // Left arrow - skip back
            skipBackward(10)
        case 124: // Right arrow - skip forward
            skipForward(10)
        case 53: // Escape - exit fullscreen or stop
            if let window = window, (window.styleMask.contains(.fullScreen)) {
                window.toggleFullScreen(nil)
            } else {
                stop()
                window?.close()
            }
        default:
            super.keyDown(with: event)
        }
    }
}
