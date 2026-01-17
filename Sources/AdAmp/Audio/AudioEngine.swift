import AVFoundation
import AppKit
import Accelerate
import CoreAudio
import AudioToolbox

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
    func audioEngineDidChangePlaylist()
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
    
    /// Current audio file (for local files)
    private var audioFile: AVAudioFile?
    
    /// AVPlayer for streaming URLs
    private var streamPlayer: AVPlayer?
    private var streamPlayerObserver: Any?
    private var isStreamingPlayback: Bool = false
    
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
    var volume: Float = 0.2 {
        didSet {
            playerNode.volume = volume
            streamPlayer?.volume = volume
            
            // Also set volume on cast device if casting
            if isCastingActive {
                Task {
                    try? await CastManager.shared.setVolume(volume)
                }
            }
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
    
    /// Generation counter to track which completion handler is valid
    /// Incremented on each seek/load to invalidate old completion handlers
    private var playbackGeneration: Int = 0
    
    /// Timer for time updates
    private var timeUpdateTimer: Timer?
    
    /// Spectrum analyzer data (75 bands for Winamp-style visualization)
    private(set) var spectrumData: [Float] = Array(repeating: 0, count: 75)
    
    /// FFT setup for spectrum analysis
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 2048
    
    /// Tap for audio analysis
    private var analysisTap: AVAudioNodeTapBlock?
    
    /// Standard Winamp EQ frequencies
    static let eqFrequencies: [Float] = [
        60, 170, 310, 600, 1000,
        3000, 6000, 12000, 14000, 16000
    ]
    
    /// Current output device ID (nil = system default)
    private(set) var currentOutputDeviceID: AudioDeviceID?
    
    /// Whether casting is currently active (playback controlled by CastManager)
    var isCastingActive: Bool {
        CastManager.shared.isCasting
    }
    
    // MARK: - Initialization
    
    init() {
        setupAudioEngine()
        setupEqualizer()
        setupSpectrumAnalyzer()
        restoreSavedOutputDevice()
    }
    
    deinit {
        timeUpdateTimer?.invalidate()
        playerNode.removeTap(onBus: 0)
        engine.stop()
        // FFT setup is automatically released when set to nil
        fftSetup = nil
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
        
        // Set initial volume (didSet doesn't fire for default value)
        playerNode.volume = volume
        
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
    
    private func setupSpectrumAnalyzer() {
        // Create FFT setup
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        
        // Install tap on player node for spectrum analysis
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        
        playerNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount >= fftSize else { return }
        
        // Get audio samples (mono mix if stereo)
        var samples = [Float](repeating: 0, count: fftSize)
        let channelCount = Int(buffer.format.channelCount)
        
        if channelCount == 1 {
            memcpy(&samples, channelData[0], fftSize * MemoryLayout<Float>.size)
        } else {
            // Mix stereo to mono
            for i in 0..<fftSize {
                samples[i] = (channelData[0][i] + channelData[1][i]) / 2.0
            }
        }
        
        // Apply Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))
        
        // Perform FFT
        var realIn = [Float](repeating: 0, count: fftSize)
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        
        realIn = samples
        
        vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, &realOut, &imagOut)
        
        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        
        for i in 0..<fftSize / 2 {
            magnitudes[i] = sqrt(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }
        
        // Convert to dB and normalize
        var logMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        var one: Float = 1.0
        vDSP_vdbcon(magnitudes, 1, &one, &logMagnitudes, 1, vDSP_Length(fftSize / 2), 0)
        
        // Map to 75 bands (Winamp-style)
        let bandCount = 75
        var newSpectrum = [Float](repeating: 0, count: bandCount)
        
        // Logarithmic frequency mapping
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let sampleRate = Float(buffer.format.sampleRate)
        let binWidth = sampleRate / Float(fftSize)
        
        for band in 0..<bandCount {
            // Calculate frequency range for this band (logarithmic)
            let freqRatio = Float(band) / Float(bandCount - 1)
            let freq = minFreq * pow(maxFreq / minFreq, freqRatio)
            
            // Find corresponding FFT bin
            let bin = Int(freq / binWidth)
            
            if bin < fftSize / 2 && bin >= 0 {
                // Average nearby bins for smoother result
                var sum: Float = 0
                var count: Float = 0
                let range = max(1, bin / 10)
                
                for j in max(0, bin - range)..<min(fftSize / 2, bin + range + 1) {
                    sum += logMagnitudes[j]
                    count += 1
                }
                
                // Normalize to 0-1 range (assuming -80dB to 0dB range)
                let db = sum / count
                let normalized = max(0, min(1, (db + 80) / 80))
                newSpectrum[band] = normalized
            }
        }
        
        // Smooth with previous values (decay)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<bandCount {
                // Fast attack, slow decay
                if newSpectrum[i] > self.spectrumData[i] {
                    self.spectrumData[i] = newSpectrum[i]
                } else {
                    self.spectrumData[i] = self.spectrumData[i] * 0.85 + newSpectrum[i] * 0.15
                }
            }
            self.delegate?.audioEngineDidUpdateSpectrum(self.spectrumData)
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        // If casting is active, forward command to CastManager
        if isCastingActive {
            Task {
                try? await CastManager.shared.resume()
            }
            return
        }
        
        guard currentTrack != nil || !playlist.isEmpty else { return }
        
        if currentTrack == nil && !playlist.isEmpty {
            currentIndex = 0
            loadTrack(at: currentIndex)
        }
        
        if isStreamingPlayback {
            // Streaming playback via AVPlayer
            NSLog("play(): Starting streaming playback")
            streamPlayer?.play()
            playbackStartDate = Date()
            state = .playing
            startTimeUpdates()
            NSLog("play(): streamPlayer.timeControlStatus = %d", streamPlayer?.timeControlStatus.rawValue ?? -1)
        } else {
            // Local file playback via AVAudioEngine
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                playerNode.play()
                playbackStartDate = Date()  // Start tracking time
                state = .playing
                startTimeUpdates()
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }
    }
    
    func pause() {
        // If casting is active, forward command to CastManager
        if isCastingActive {
            Task {
                try? await CastManager.shared.pause()
            }
            return
        }
        
        pauseLocalOnly()
    }
    
    /// Pause local playback only (used internally when casting takes over)
    func pauseLocalOnly() {
        // Save current position before pausing
        if let startDate = playbackStartDate {
            _currentTime += Date().timeIntervalSince(startDate)
        }
        playbackStartDate = nil
        
        if isStreamingPlayback {
            streamPlayer?.pause()
        } else {
            playerNode.pause()
        }
        state = .paused
        stopTimeUpdates()
    }
    
    func stop() {
        // If casting is active, stop casting as well
        if isCastingActive {
            Task {
                await CastManager.shared.stopCasting()
            }
        }
        
        // Increment generation to invalidate completion handlers
        playbackGeneration += 1
        let currentGeneration = playbackGeneration
        
        if isStreamingPlayback {
            streamPlayer?.pause()
            streamPlayer?.seek(to: .zero)
        } else {
            playerNode.stop()
        }
        
        playbackStartDate = nil
        _currentTime = 0  // Reset to beginning
        lastReportedTime = 0
        state = .stopped
        stopTimeUpdates()
        
        // Notify delegate of reset time
        delegate?.audioEngineDidUpdateTime(current: 0, duration: duration)
        
        // Reset to beginning (local files only)
        if !isStreamingPlayback, let file = audioFile {
            playerNode.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.handlePlaybackComplete(generation: currentGeneration)
                }
            }
        }
    }
    
    func previous() {
        guard !playlist.isEmpty else { return }
        
        if shuffleEnabled {
            currentIndex = Int.random(in: 0..<playlist.count)
        } else {
            currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        }
        
        // When casting, cast the new track instead of playing locally
        if isCastingActive {
            let track = playlist[currentIndex]
            currentTrack = track
            delegate?.audioEngineDidChangeTrack(track)
            Task {
                try? await CastManager.shared.castNewTrack(track)
            }
            return
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
        
        // When casting, cast the new track instead of playing locally
        if isCastingActive {
            let track = playlist[currentIndex]
            currentTrack = track
            delegate?.audioEngineDidChangeTrack(track)
            Task {
                try? await CastManager.shared.castNewTrack(track)
            }
            return
        }
        
        loadTrack(at: currentIndex)
        if state == .playing {
            play()
        }
    }
    
    /// Seek relative to current position
    /// Uses the last reported time from the delegate (most accurate for UI sync)
    func seekBy(seconds: TimeInterval) {
        let newTime = max(0, min(duration, lastReportedTime + seconds))
        seek(to: newTime)
    }
    
    /// Last time reported to delegate (updated every 0.1s by timer)
    private(set) var lastReportedTime: TimeInterval = 0
    
    /// Skip multiple tracks forward or backward
    func skipTracks(count: Int) {
        guard !playlist.isEmpty else { return }
        
        if shuffleEnabled {
            // In shuffle mode, skip one at a time
            for _ in 0..<abs(count) {
                if count > 0 { next() } else { previous() }
            }
            return
        }
        
        // Calculate new index with wraparound
        var newIndex = currentIndex + count
        while newIndex < 0 { newIndex += playlist.count }
        newIndex = newIndex % playlist.count
        
        currentIndex = newIndex
        loadTrack(at: currentIndex)
        if state == .playing { play() }
    }
    
    /// Track the current playback position (updated during seek)
    private var _currentTime: TimeInterval = 0
    
    /// Reference date when playback started/resumed (for manual time tracking)
    private var playbackStartDate: Date?
    
    func seek(to time: TimeInterval) {
        // If casting is active, forward command to CastManager
        if isCastingActive {
            // Update local tracking immediately for responsive UI
            castStartPosition = time
            castPlaybackStartDate = Date()  // Reset interpolation from seek position
            _currentTime = time
            lastReportedTime = time
            
            Task {
                try? await CastManager.shared.seek(to: time)
            }
            return
        }
        
        // Clamp time to valid range
        let seekTime = max(0, min(time, duration - 0.5))
        
        if isStreamingPlayback {
            // Streaming playback - seek via AVPlayer
            guard let player = streamPlayer else { return }
            
            let cmTime = CMTime(seconds: seekTime, preferredTimescale: 600)
            player.seek(to: cmTime) { [weak self] _ in
                self?.lastReportedTime = seekTime
            }
        } else {
            // Local file playback - seek via AVAudioEngine
            guard let file = audioFile else { return }
            
            let wasPlaying = state == .playing
            
            _currentTime = seekTime
            lastReportedTime = seekTime  // Keep in sync
            playbackStartDate = nil  // Will be set when play resumes
            
            // Increment generation to invalidate old completion handlers
            playbackGeneration += 1
            let currentGeneration = playbackGeneration
            
            // Stop current playback
            playerNode.stop()
            
            // Calculate frame position
            let sampleRate = file.processingFormat.sampleRate
            let framePosition = AVAudioFramePosition(seekTime * sampleRate)
            let remainingFrames = file.length - framePosition
            
            guard remainingFrames > 0 else { return }
            
            // Schedule from the new position with a new completion handler
            playerNode.scheduleSegment(file, startingFrame: framePosition, 
                                       frameCount: AVAudioFrameCount(remainingFrames), at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.handlePlaybackComplete(generation: currentGeneration)
                }
            }
            
            // Resume if was playing
            if wasPlaying {
                playbackStartDate = Date()  // Start tracking from seek position
                playerNode.play()
            }
        }
    }
    
    // MARK: - Time Updates
    
    /// Timestamp when cast playback started (for time interpolation)
    private var castPlaybackStartDate: Date?
    /// Position when cast playback started
    private var castStartPosition: TimeInterval = 0
    
    var currentTime: TimeInterval {
        // When casting, interpolate from start position
        if isCastingActive {
            // If cast playback is active (startDate is set), interpolate
            if let startDate = castPlaybackStartDate {
                let elapsed = Date().timeIntervalSince(startDate)
                let interpolated = castStartPosition + elapsed
                let trackDuration = currentTrack?.duration ?? 0
                // Don't exceed duration
                return trackDuration > 0 ? min(interpolated, trackDuration) : interpolated
            }
            // Cast is paused - return the last saved position
            return castStartPosition
        }
        
        if isStreamingPlayback {
            // Get time from stream player
            guard let player = streamPlayer else { return 0 }
            return CMTimeGetSeconds(player.currentTime())
        } else {
            // Use manual time tracking based on when playback started
            guard state == .playing, let startDate = playbackStartDate else {
                return _currentTime
            }
            
            let elapsed = Date().timeIntervalSince(startDate)
            return _currentTime + elapsed
        }
    }
    
    var duration: TimeInterval {
        // When casting, use track metadata
        if isCastingActive {
            return currentTrack?.duration ?? 0
        }
        
        if isStreamingPlayback {
            // Get duration from stream player
            guard let player = streamPlayer,
                  let item = player.currentItem else {
                // Use track duration if available
                return currentTrack?.duration ?? 0
            }
            let dur = CMTimeGetSeconds(item.duration)
            return dur.isFinite ? dur : (currentTrack?.duration ?? 0)
        } else {
            guard let file = audioFile else { return 0 }
            return Double(file.length) / file.processingFormat.sampleRate
        }
    }
    
    /// Start cast playback time tracking (called when cast playback begins)
    func startCastPlayback(from position: TimeInterval = 0) {
        castStartPosition = position
        castPlaybackStartDate = Date()
        _currentTime = position
        lastReportedTime = position
    }
    
    /// Pause cast playback time tracking
    func pauseCastPlayback() {
        // Save current interpolated position
        if let startDate = castPlaybackStartDate {
            castStartPosition += Date().timeIntervalSince(startDate)
        }
        castPlaybackStartDate = nil
    }
    
    /// Resume cast playback time tracking
    func resumeCastPlayback() {
        castPlaybackStartDate = Date()
    }
    
    /// Stop cast playback time tracking (called when casting stops)
    func stopCastPlayback() {
        castPlaybackStartDate = nil
        castStartPosition = 0
    }
    
    private func startTimeUpdates() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = self.currentTime
            let trackDuration = self.duration
            self.lastReportedTime = current
            self.delegate?.audioEngineDidUpdateTime(current: current, duration: trackDuration)
            
            // When casting, check if track has finished and auto-advance
            if self.isCastingActive, 
               self.castPlaybackStartDate != nil,  // Casting is playing (not paused)
               trackDuration > 0,
               current >= trackDuration - 0.5 {  // Within 0.5s of end
                NSLog("AudioEngine: Cast track finished, advancing to next")
                self.castTrackDidFinish()
            }
        }
        // Add to common modes so it runs during menu tracking and other modal states
        RunLoop.main.add(timer, forMode: .common)
        timeUpdateTimer = timer
    }
    
    /// Handle cast track completion - advance to next track
    private func castTrackDidFinish() {
        // Prevent multiple calls
        castPlaybackStartDate = nil
        
        if repeatEnabled {
            if shuffleEnabled {
                // Repeat mode + shuffle: pick a random track
                currentIndex = Int.random(in: 0..<playlist.count)
            }
            // Cast the same or new random track
            let track = playlist[currentIndex]
            currentTrack = track
            delegate?.audioEngineDidChangeTrack(track)
            Task {
                try? await CastManager.shared.castNewTrack(track)
            }
        } else if !playlist.isEmpty {
            if shuffleEnabled {
                // Shuffle without repeat: stop after current track
                Task {
                    await CastManager.shared.stopCasting()
                }
            } else if currentIndex < playlist.count - 1 {
                // More tracks to play - advance
                currentIndex += 1
                let track = playlist[currentIndex]
                currentTrack = track
                delegate?.audioEngineDidChangeTrack(track)
                Task {
                    try? await CastManager.shared.castNewTrack(track)
                }
            } else {
                // End of playlist - stop casting
                Task {
                    await CastManager.shared.stopCasting()
                }
            }
        }
    }
    
    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
    
    // MARK: - File Loading
    
    func loadFiles(_ urls: [URL]) {
        NSLog("loadFiles: %d URLs", urls.count)
        let tracks = urls.compactMap { Track(url: $0) }
        NSLog("loadFiles: %d tracks created", tracks.count)
        loadTracks(tracks)
    }
    
    /// Load tracks with metadata (for Plex and other sources with pre-populated info)
    func loadTracks(_ tracks: [Track]) {
        NSLog("loadTracks: %d tracks, currentTrack=%@", tracks.count, currentTrack?.title ?? "nil")
        
        // Stop current playback and clear playlist when loading new tracks
        stop()
        stopStreamPlayer()
        isStreamingPlayback = false
        playlist.removeAll()
        
        playlist.append(contentsOf: tracks)
        
        if !tracks.isEmpty {
            currentIndex = 0
            NSLog("loadTracks: loading track at index %d", currentIndex)
            loadTrack(at: currentIndex)
            play()  // Auto-start playback
        }
        
        delegate?.audioEngineDidChangePlaylist()
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
        
        // loadFiles will call the delegate
        loadFiles(urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
    }
    
    /// Append files to the playlist without starting playback
    func appendFiles(_ urls: [URL]) {
        let tracks = urls.compactMap { Track(url: $0) }
        playlist.append(contentsOf: tracks)
        delegate?.audioEngineDidChangePlaylist()
    }
    
    private func loadTrack(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        
        let track = playlist[index]
        
        // Check if this is a remote URL (streaming)
        if track.url.scheme == "http" || track.url.scheme == "https" {
            loadStreamingTrack(track)
        } else {
            loadLocalTrack(track)
        }
    }
    
    private func loadLocalTrack(_ track: Track) {
        NSLog("loadLocalTrack: %@", track.url.lastPathComponent)
        // Stop any streaming playback
        stopStreamPlayer()
        isStreamingPlayback = false
        
        do {
            audioFile = try AVAudioFile(forReading: track.url)
            NSLog("loadLocalTrack: file loaded successfully")
            currentTrack = track
            _currentTime = 0  // Reset time for new track
            lastReportedTime = 0
            
            // Increment generation to invalidate any old completion handlers
            playbackGeneration += 1
            let currentGeneration = playbackGeneration
            
            playerNode.stop()
            playerNode.scheduleFile(audioFile!, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.handlePlaybackComplete(generation: currentGeneration)
                }
            }
            NSLog("loadLocalTrack: file scheduled")
        } catch {
            NSLog("loadLocalTrack: FAILED - %@", error.localizedDescription)
        }
    }
    
    /// KVO observer for player item status
    private var playerItemStatusObserver: NSKeyValueObservation?
    
    private func loadStreamingTrack(_ track: Track) {
        NSLog("loadStreamingTrack: %@ - %@", track.artist ?? "Unknown", track.title)
        NSLog("  URL: %@", track.url.absoluteString)
        
        // Stop local playback
        playerNode.stop()
        audioFile = nil
        isStreamingPlayback = true
        
        // Stop existing stream player
        stopStreamPlayer()
        
        // Create new player item and player
        let playerItem = AVPlayerItem(url: track.url)
        streamPlayer = AVPlayer(playerItem: playerItem)
        streamPlayer?.volume = volume
        
        currentTrack = track
        _currentTime = 0
        lastReportedTime = 0
        
        // Increment generation
        playbackGeneration += 1
        let currentGeneration = playbackGeneration
        
        // Observe player item status to extract audio format info
        playerItemStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self, item.status == .readyToPlay else { return }
            self.extractStreamAudioFormat(from: item)
        }
        
        // Observe when track finishes
        streamPlayerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackComplete(generation: currentGeneration)
        }
        
        NSLog("  Created AVPlayer, ready to play")
    }
    
    /// Extract audio format (sample rate, channels) from a streaming player item
    private func extractStreamAudioFormat(from playerItem: AVPlayerItem) {
        guard let track = currentTrack else { return }
        
        // Only update if we don't already have this info
        guard track.sampleRate == nil || track.channels == nil else { return }
        
        let asset = playerItem.asset
        let audioTracks = asset.tracks(withMediaType: .audio)
        
        guard let audioTrack = audioTracks.first else { return }
        
        let formatDescriptions = audioTrack.formatDescriptions as? [CMFormatDescription]
        guard let formatDesc = formatDescriptions?.first else { return }
        
        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
            let newSampleRate = track.sampleRate ?? Int(asbd.mSampleRate)
            let newChannels = track.channels ?? Int(asbd.mChannelsPerFrame)
            
            // Create updated track with extracted format info
            let updatedTrack = Track(
                id: track.id,
                url: track.url,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                bitrate: track.bitrate,
                sampleRate: newSampleRate,
                channels: newChannels
            )
            
            // Update current track and notify delegate
            currentTrack = updatedTrack
            
            // Update playlist entry too
            if currentIndex >= 0 && currentIndex < playlist.count {
                playlist[currentIndex] = updatedTrack
            }
            
            NSLog("Extracted stream audio format: %d Hz, %d channels", newSampleRate, newChannels)
        }
    }
    
    private func stopStreamPlayer() {
        if let observer = streamPlayerObserver {
            NotificationCenter.default.removeObserver(observer)
            streamPlayerObserver = nil
        }
        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil
        streamPlayer?.pause()
        streamPlayer = nil
    }
    
    /// Handle playback completion with generation check
    private func handlePlaybackComplete(generation: Int) {
        // Ignore if this completion handler is from a stale playback session
        // (e.g., user seeked or loaded a new track since this was scheduled)
        guard generation == playbackGeneration else { return }
        
        // Also ignore if we're not in a playing state (user manually stopped)
        guard state == .playing else { return }
        
        trackDidFinish()
    }
    
    private func trackDidFinish() {
        if repeatEnabled {
            if shuffleEnabled {
                // Repeat mode + shuffle: pick a random track
                currentIndex = Int.random(in: 0..<playlist.count)
                loadTrack(at: currentIndex)
                play()
            } else {
                // Repeat mode: loop current track
                loadTrack(at: currentIndex)
                play()
            }
        } else {
            // No repeat mode: check if we're at the end of playlist
            if shuffleEnabled {
                // Shuffle without repeat: could play random tracks but eventually should stop
                // For simplicity, just stop after current track
                stop()
            } else if currentIndex < playlist.count - 1 {
                // More tracks to play
                currentIndex += 1
                loadTrack(at: currentIndex)
                play()
            } else {
                // End of playlist, stop playback
                stop()
            }
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
    
    // MARK: - Output Device
    
    /// Set the output device for audio playback
    /// - Parameter deviceID: The Core Audio device ID, or nil for system default
    /// - Returns: true if successful, false otherwise
    @discardableResult
    func setOutputDevice(_ deviceID: AudioDeviceID?) -> Bool {
        let wasPlaying = state == .playing
        
        // Stop engine before changing output device
        if engine.isRunning {
            engine.stop()
        }
        
        // Get the actual device ID to use
        let targetDeviceID: AudioDeviceID
        if let deviceID = deviceID {
            targetDeviceID = deviceID
        } else {
            // Use system default
            guard let defaultID = AudioOutputManager.shared.getDefaultOutputDeviceID() else {
                print("Failed to get default output device")
                return false
            }
            targetDeviceID = defaultID
        }
        
        // Get the audio unit from the output node
        guard let outputUnit = engine.outputNode.audioUnit else {
            print("Failed to get output audio unit")
            return false
        }
        
        // Set the output device on the audio unit
        var deviceIDCopy = targetDeviceID
        let status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDCopy,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if status != noErr {
            print("Failed to set output device: \(status)")
            // Try to restart with previous device
            if wasPlaying {
                try? engine.start()
                playerNode.play()
            }
            return false
        }
        
        currentOutputDeviceID = deviceID
        
        // Update the AudioOutputManager's selection
        AudioOutputManager.shared.selectDevice(deviceID)
        
        // Restart engine if it was playing
        if wasPlaying {
            do {
                try engine.start()
                playerNode.play()
            } catch {
                print("Failed to restart audio engine after device change: \(error)")
                return false
            }
        }
        
        return true
    }
    
    /// Get the current output device
    func getCurrentOutputDevice() -> AudioOutputDevice? {
        guard let deviceID = currentOutputDeviceID else { return nil }
        return AudioOutputManager.shared.outputDevices.first { $0.id == deviceID }
    }
    
    /// Restore the saved output device from UserDefaults
    private func restoreSavedOutputDevice() {
        // Check if there's a saved device
        if let savedDevice = AudioOutputManager.shared.currentDeviceID {
            // Delay slightly to ensure engine is fully set up
            DispatchQueue.main.async { [weak self] in
                self?.setOutputDevice(savedDevice)
            }
        }
    }
    
    // MARK: - Playlist Management
    
    func clearPlaylist() {
        NSLog("clearPlaylist: isStreamingPlayback=%d", isStreamingPlayback)
        stop()
        stopStreamPlayer()
        isStreamingPlayback = false
        playlist.removeAll()
        currentIndex = -1
        currentTrack = nil
        audioFile = nil
        NSLog("clearPlaylist: done, playlist count=%d", playlist.count)
        delegate?.audioEngineDidChangePlaylist()
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
        
        delegate?.audioEngineDidChangePlaylist()
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
        
        delegate?.audioEngineDidChangePlaylist()
    }
    
    func playTrack(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        currentIndex = index
        loadTrack(at: index)
        play()
    }
}
