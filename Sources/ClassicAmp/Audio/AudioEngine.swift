import AVFoundation
import AppKit

/// Audio playback state
enum PlaybackState {
    case stopped
    case playing
    case paused
}

/// Delegate protocol for audio engine events
protocol AudioEngineDelegate: AnyObject {
    func audioEngineDidChangeState(_ state: PlaybackState)
    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval)
    func audioEngineDidChangeTrack(_ track: Track?)
    func audioEngineDidUpdateSpectrum(_ levels: [Float])
}

/// Core audio engine using AVAudioEngine for playback and DSP
class AudioEngine {
    
    // MARK: - Properties
    
    weak var delegate: AudioEngineDelegate?
    
    /// The AVAudioEngine instance
    private let engine = AVAudioEngine()
    
    /// Audio player node
    private let playerNode = AVAudioPlayerNode()
    
    /// 10-band equalizer
    private let eqNode = AVAudioUnitEQ(numberOfBands: 10)
    
    /// Current audio file
    private var audioFile: AVAudioFile?
    
    /// Current playback state
    private(set) var state: PlaybackState = .stopped {
        didSet {
            delegate?.audioEngineDidChangeState(state)
        }
    }
    
    /// Current track
    private(set) var currentTrack: Track? {
        didSet {
            delegate?.audioEngineDidChangeTrack(currentTrack)
        }
    }
    
    /// Playlist of tracks
    private(set) var playlist: [Track] = []
    
    /// Current track index in playlist
    private(set) var currentIndex: Int = -1
    
    /// Volume level (0.0 - 1.0)
    var volume: Float = 1.0 {
        didSet {
            playerNode.volume = volume
        }
    }
    
    /// Balance (-1.0 left, 0.0 center, 1.0 right)
    var balance: Float = 0.0 {
        didSet {
            playerNode.pan = balance
        }
    }
    
    /// Shuffle enabled
    var shuffleEnabled: Bool = false
    
    /// Repeat mode
    var repeatEnabled: Bool = false
    
    /// Timer for time updates
    private var timeUpdateTimer: Timer?
    
    /// Standard Winamp EQ frequencies
    static let eqFrequencies: [Float] = [
        60, 170, 310, 600, 1000,
        3000, 6000, 12000, 14000, 16000
    ]
    
    // MARK: - Initialization
    
    init() {
        setupAudioEngine()
        setupEqualizer()
    }
    
    deinit {
        timeUpdateTimer?.invalidate()
        engine.stop()
    }
    
    // MARK: - Setup
    
    private func setupAudioEngine() {
        // Attach nodes
        engine.attach(playerNode)
        engine.attach(eqNode)
        
        // Connect nodes: player -> EQ -> output
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(playerNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        
        // Prepare engine
        engine.prepare()
    }
    
    private func setupEqualizer() {
        // Configure each EQ band
        for (index, frequency) in Self.eqFrequencies.enumerated() {
            let band = eqNode.bands[index]
            band.filterType = .parametric
            band.frequency = frequency
            band.bandwidth = 1.0  // Q factor
            band.gain = 0.0       // Flat by default
            band.bypass = false
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        guard currentTrack != nil || !playlist.isEmpty else { return }
        
        if currentTrack == nil && !playlist.isEmpty {
            currentIndex = 0
            loadTrack(at: currentIndex)
        }
        
        do {
            if !engine.isRunning {
                try engine.start()
            }
            playerNode.play()
            state = .playing
            startTimeUpdates()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func pause() {
        playerNode.pause()
        state = .paused
        stopTimeUpdates()
    }
    
    func stop() {
        playerNode.stop()
        state = .stopped
        stopTimeUpdates()
        
        // Reset to beginning
        if let file = audioFile {
            playerNode.scheduleFile(file, at: nil)
        }
    }
    
    func previous() {
        guard !playlist.isEmpty else { return }
        
        if shuffleEnabled {
            currentIndex = Int.random(in: 0..<playlist.count)
        } else {
            currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        }
        
        loadTrack(at: currentIndex)
        if state == .playing {
            play()
        }
    }
    
    func next() {
        guard !playlist.isEmpty else { return }
        
        if shuffleEnabled {
            currentIndex = Int.random(in: 0..<playlist.count)
        } else {
            currentIndex = (currentIndex + 1) % playlist.count
        }
        
        loadTrack(at: currentIndex)
        if state == .playing {
            play()
        }
    }
    
    func seek(to time: TimeInterval) {
        guard let file = audioFile else { return }
        
        let sampleRate = file.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(time * sampleRate)
        
        playerNode.stop()
        
        let frameCount = AVAudioFrameCount(file.length - framePosition)
        guard frameCount > 0 else { return }
        
        playerNode.scheduleSegment(file, startingFrame: framePosition, frameCount: frameCount, at: nil)
        
        if state == .playing {
            playerNode.play()
        }
    }
    
    // MARK: - Time Updates
    
    var currentTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
    
    var duration: TimeInterval {
        guard let file = audioFile else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
    
    private func startTimeUpdates() {
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.audioEngineDidUpdateTime(current: self.currentTime, duration: self.duration)
        }
    }
    
    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
    
    // MARK: - File Loading
    
    func loadFiles(_ urls: [URL]) {
        let tracks = urls.compactMap { Track(url: $0) }
        playlist.append(contentsOf: tracks)
        
        if currentTrack == nil && !tracks.isEmpty {
            currentIndex = playlist.count - tracks.count
            loadTrack(at: currentIndex)
        }
    }
    
    func loadFolder(_ url: URL) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        
        var urls: [URL] = []
        let audioExtensions = ["mp3", "m4a", "aac", "wav", "aiff", "flac", "ogg", "alac"]
        
        while let fileURL = enumerator.nextObject() as? URL {
            if audioExtensions.contains(fileURL.pathExtension.lowercased()) {
                urls.append(fileURL)
            }
        }
        
        loadFiles(urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }
    
    private func loadTrack(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        
        let track = playlist[index]
        
        do {
            audioFile = try AVAudioFile(forReading: track.url)
            currentTrack = track
            
            playerNode.stop()
            playerNode.scheduleFile(audioFile!, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.trackDidFinish()
                }
            }
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
    
    private func trackDidFinish() {
        if repeatEnabled && !shuffleEnabled {
            // Repeat current track
            loadTrack(at: currentIndex)
            play()
        } else {
            // Play next track
            next()
        }
    }
    
    // MARK: - Equalizer
    
    /// Set EQ band gain (-12 to +12 dB)
    func setEQBand(_ band: Int, gain: Float) {
        guard band >= 0 && band < 10 else { return }
        eqNode.bands[band].gain = max(-12, min(12, gain))
    }
    
    /// Get EQ band gain
    func getEQBand(_ band: Int) -> Float {
        guard band >= 0 && band < 10 else { return 0 }
        return eqNode.bands[band].gain
    }
    
    /// Set preamp gain (-12 to +12 dB)
    func setPreamp(_ gain: Float) {
        eqNode.globalGain = max(-12, min(12, gain))
    }
    
    /// Get preamp gain
    func getPreamp() -> Float {
        return eqNode.globalGain
    }
    
    /// Enable/disable equalizer
    func setEQEnabled(_ enabled: Bool) {
        eqNode.bypass = !enabled
    }
    
    // MARK: - Playlist Management
    
    func clearPlaylist() {
        stop()
        playlist.removeAll()
        currentIndex = -1
        currentTrack = nil
        audioFile = nil
    }
    
    func removeTrack(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        
        playlist.remove(at: index)
        
        if index == currentIndex {
            stop()
            currentTrack = nil
            audioFile = nil
            if !playlist.isEmpty {
                currentIndex = min(index, playlist.count - 1)
                loadTrack(at: currentIndex)
            } else {
                currentIndex = -1
            }
        } else if index < currentIndex {
            currentIndex -= 1
        }
    }
    
    func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < playlist.count,
              destinationIndex >= 0 && destinationIndex < playlist.count else { return }
        
        let track = playlist.remove(at: sourceIndex)
        playlist.insert(track, at: destinationIndex)
        
        // Update current index
        if sourceIndex == currentIndex {
            currentIndex = destinationIndex
        } else if sourceIndex < currentIndex && destinationIndex >= currentIndex {
            currentIndex -= 1
        } else if sourceIndex > currentIndex && destinationIndex <= currentIndex {
            currentIndex += 1
        }
    }
    
    func playTrack(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        currentIndex = index
        loadTrack(at: index)
        play()
    }
}
