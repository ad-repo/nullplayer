import AVFoundation
import AppKit
import Accelerate
import CoreAudio
import AudioToolbox
import AudioStreaming

// MARK: - Notifications

extension Notification.Name {
    /// Posted when new PCM audio data is available for visualization
    /// userInfo contains: "pcm" ([Float]), "sampleRate" (Double)
    static let audioPCMDataUpdated = Notification.Name("audioPCMDataUpdated")

    /// Posted when new spectrum data is available for visualization
    /// userInfo contains: "spectrum" ([Float]) - 75 bands normalized 0-1
    static let audioSpectrumDataUpdated = Notification.Name("audioSpectrumDataUpdated")

    /// Posted when playback state changes (playing, paused, stopped)
    /// userInfo contains: "state" (PlaybackState)
    static let audioPlaybackStateChanged = Notification.Name("audioPlaybackStateChanged")
    
    /// Posted when the current track changes
    /// userInfo contains: "track" (Track?) - may be nil when playback stops
    static let audioTrackDidChange = Notification.Name("audioTrackDidChange")
}

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
    
    /// Limiter for anti-clipping protection when EQ boosts are applied
    /// Uses Apple's built-in AUDynamicsProcessor Audio Unit
    private let limiterNode: AVAudioUnitEffect = {
        let componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: componentDescription)
    }()
    
    /// Current audio file (for local files)
    private var audioFile: AVAudioFile?
    
    /// Streaming audio player (for HTTP URLs like Plex) - uses AudioStreaming library
    /// This routes audio through AVAudioEngine so EQ affects streaming audio
    private var streamingPlayer: StreamingAudioPlayer?
    private var isStreamingPlayback: Bool = false
    private var isLoadingNewStreamingTrack: Bool = false
    
    /// Current playback state
    private(set) var state: PlaybackState = .stopped {
        didSet {
            delegate?.audioEngineDidChangeState(state)
            // Post notification for visualization and other observers
            NotificationCenter.default.post(
                name: .audioPlaybackStateChanged,
                object: self,
                userInfo: ["state": state]
            )
        }
    }
    
    /// Current track
    private(set) var currentTrack: Track? {
        didSet {
            delegate?.audioEngineDidChangeTrack(currentTrack)
            // Post notification for views that need to observe track changes
            NotificationCenter.default.post(
                name: .audioTrackDidChange,
                object: self,
                userInfo: currentTrack != nil ? ["track": currentTrack!] : nil
            )
        }
    }
    
    /// Playlist of tracks
    private(set) var playlist: [Track] = []
    
    /// Current track index in playlist
    private(set) var currentIndex: Int = -1
    
    /// Volume level (0.0 - 1.0)
    var volume: Float = 0.2 {
        didSet {
            // Apply volume with normalization gain for local playback
            applyNormalizationGain()
            streamingPlayer?.volume = volume
            
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
            // Apply to both players since they alternate during crossfades
            playerNode.pan = balance
            crossfadePlayerNode.pan = balance
        }
    }
    
    /// Shuffle enabled
    var shuffleEnabled: Bool = false
    
    /// Repeat mode
    var repeatEnabled: Bool = false
    
    /// Gapless playback mode - pre-schedules next track for seamless transitions
    var gaplessPlaybackEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(gaplessPlaybackEnabled, forKey: "gaplessPlaybackEnabled")
            // If enabling and currently playing, schedule next track
            if gaplessPlaybackEnabled && state == .playing {
                scheduleNextTrackForGapless()
            }
        }
    }
    
    /// Volume normalization - analyzes and normalizes track loudness
    var volumeNormalizationEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(volumeNormalizationEnabled, forKey: "volumeNormalizationEnabled")
            // Recalculate normalization for current track
            if volumeNormalizationEnabled {
                applyNormalizationGain()
            } else {
                normalizationGain = 1.0
                applyNormalizationGain()
            }
        }
    }
    
    /// Current normalization gain factor (1.0 = no change)
    private var normalizationGain: Float = 1.0
    
    /// Target loudness level for normalization (in dB, typical is -14 LUFS for streaming)
    private let targetLoudnessDB: Float = -14.0
    
    // MARK: - Sweet Fades (Crossfade)
    
    /// Sweet Fades (crossfade) enabled - smooth transition between tracks
    var sweetFadeEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(sweetFadeEnabled, forKey: "sweetFadeEnabled")
            NSLog("AudioEngine: Sweet Fades %@", sweetFadeEnabled ? "enabled" : "disabled")
        }
    }
    
    /// Crossfade duration in seconds (default 5s)
    var sweetFadeDuration: TimeInterval = 5.0 {
        didSet {
            UserDefaults.standard.set(sweetFadeDuration, forKey: "sweetFadeDuration")
            NSLog("AudioEngine: Sweet Fades duration set to %.1fs", sweetFadeDuration)
        }
    }
    
    /// Whether a crossfade is currently in progress
    private var isCrossfading: Bool = false
    
    /// Timer for volume ramping during crossfade
    private var crossfadeTimer: Timer?
    
    /// Secondary player node for crossfade (local files)
    private let crossfadePlayerNode = AVAudioPlayerNode()
    
    /// Audio file for crossfade player
    private var crossfadeAudioFile: AVAudioFile?
    
    /// Secondary streaming player for crossfade
    private var crossfadeStreamingPlayer: StreamingAudioPlayer?
    
    /// Track index of the incoming crossfade track
    private var crossfadeTargetIndex: Int = -1
    
    /// Track whether primary or crossfade player is currently "active" for local playback
    /// When a crossfade completes, the crossfade player becomes the primary
    private var crossfadePlayerIsActive: Bool = false
    
    /// Pre-scheduled next file for gapless playback
    private var nextScheduledFile: AVAudioFile?
    private var nextScheduledTrackIndex: Int = -1
    
    /// Generation counter to track which completion handler is valid
    /// Incremented on each seek/load to invalidate old completion handlers
    private var playbackGeneration: Int = 0
    
    /// Debounce work item for streaming seeks to prevent rapid seek overload
    private var streamingSeekWorkItem: DispatchWorkItem?
    
    /// Work item for resetting the seeking flag after a delay
    private var streamingSeekResetWorkItem: DispatchWorkItem?
    
    /// Flag to track if we're in the middle of a seek operation
    private var isSeekingStreaming: Bool = false
    
    /// Timer for time updates
    private var timeUpdateTimer: Timer?
    
    /// Spectrum analyzer data (75 bands for Winamp-style visualization)
    private(set) var spectrumData: [Float] = Array(repeating: 0, count: 75)
    
    /// Raw PCM audio data for waveform visualization (mono, normalized -1 to 1)
    private(set) var pcmData: [Float] = Array(repeating: 0, count: 512)
    
    /// PCM sample rate for visualization timing
    private(set) var pcmSampleRate: Double = 44100
    
    /// FFT setup for spectrum analysis
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 512  // ~11.6ms at 44.1kHz (reduced from 2048 for lowest latency)
    
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
        engine.attach(crossfadePlayerNode)  // For Sweet Fades crossfade
        engine.attach(eqNode)
        engine.attach(limiterNode)
        
        // Get the standard format from the mixer
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        
        // Create a mixer node to combine both player nodes before EQ
        // Signal flow: playerNode ─┐
        //                          ├─► mixerNode ─► eqNode ─► limiter ─► output
        //  crossfadePlayerNode ────┘
        let mixerNode = AVAudioMixerNode()
        engine.attach(mixerNode)
        
        // Connect both players to the mixer
        engine.connect(playerNode, to: mixerNode, format: mixerFormat)
        engine.connect(crossfadePlayerNode, to: mixerNode, format: mixerFormat)
        
        // Connect mixer to EQ to limiter to output
        engine.connect(mixerNode, to: eqNode, format: mixerFormat)
        engine.connect(eqNode, to: limiterNode, format: mixerFormat)
        engine.connect(limiterNode, to: engine.mainMixerNode, format: mixerFormat)
        
        // Configure limiter for transparent anti-clipping
        configureLimiter()
        
        // Set initial volume (didSet doesn't fire for default value)
        playerNode.volume = volume
        crossfadePlayerNode.volume = 0  // Start silent
        
        // EQ is disabled (bypassed) by default - user must enable it
        eqNode.bypass = true
        
        // Load audio preferences
        loadAudioPreferences()
        
        // Prepare engine
        engine.prepare()
    }
    
    /// Configure the limiter Audio Unit for transparent anti-clipping protection
    private func configureLimiter() {
        let audioUnit = limiterNode.audioUnit
        
        // AUDynamicsProcessor parameters (from AudioUnitParameters.h):
        // kDynamicsProcessorParam_Threshold = 0 (dB, -40 to 20)
        // kDynamicsProcessorParam_HeadRoom = 1 (dB, 0.1 to 40)
        // kDynamicsProcessorParam_ExpansionRatio = 2 (1 to 50)
        // kDynamicsProcessorParam_AttackTime = 4 (seconds, 0.0001 to 0.2)
        // kDynamicsProcessorParam_ReleaseTime = 5 (seconds, 0.01 to 3)
        // kDynamicsProcessorParam_MasterGain = 6 (dB, -40 to 40)
        // kDynamicsProcessorParam_CompressionAmount = 1000 (read-only, dB)
        
        // Set threshold close to 0 dB to catch peaks before clipping
        AudioUnitSetParameter(audioUnit, 0, kAudioUnitScope_Global, 0, -1.0, 0)
        
        // Set headroom (how much above threshold before limiting kicks in hard)
        AudioUnitSetParameter(audioUnit, 1, kAudioUnitScope_Global, 0, 1.0, 0)
        
        // Expansion ratio = 1 (no expansion, only compression/limiting)
        AudioUnitSetParameter(audioUnit, 2, kAudioUnitScope_Global, 0, 1.0, 0)
        
        // Fast attack time (1ms) for transparent limiting
        AudioUnitSetParameter(audioUnit, 4, kAudioUnitScope_Global, 0, 0.001, 0)
        
        // Medium release time (50ms)
        AudioUnitSetParameter(audioUnit, 5, kAudioUnitScope_Global, 0, 0.05, 0)
        
        // No makeup gain
        AudioUnitSetParameter(audioUnit, 6, kAudioUnitScope_Global, 0, 0.0, 0)
        
        NSLog("AudioEngine: Limiter configured for anti-clipping protection")
    }
    
    /// Load audio quality preferences from UserDefaults
    private func loadAudioPreferences() {
        gaplessPlaybackEnabled = UserDefaults.standard.bool(forKey: "gaplessPlaybackEnabled")
        volumeNormalizationEnabled = UserDefaults.standard.bool(forKey: "volumeNormalizationEnabled")
        sweetFadeEnabled = UserDefaults.standard.bool(forKey: "sweetFadeEnabled")
        // Load sweet fade duration with default of 5.0 seconds
        let savedDuration = UserDefaults.standard.double(forKey: "sweetFadeDuration")
        sweetFadeDuration = savedDuration > 0 ? savedDuration : 5.0
    }
    
    private func setupEqualizer() {
        // Configure each EQ band for graphic EQ behavior
        // Use low shelf for bass, high shelf for treble, and parametric for mids
        for (index, frequency) in Self.eqFrequencies.enumerated() {
            let band = eqNode.bands[index]
            
            // First band (60Hz): low shelf for bass control
            // Last band (16kHz): high shelf for treble control
            // Middle bands: parametric with wide bandwidth
            if index == 0 {
                band.filterType = .lowShelf
            } else if index == 9 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
            
            band.frequency = frequency
            // Use wider bandwidth (2.0 octaves) for more audible effect
            // Narrower bandwidth at higher frequencies for precision
            band.bandwidth = index < 5 ? 2.0 : 1.5
            band.gain = 0.0       // Flat by default
            band.bypass = false   // Individual bands active when EQ is enabled
        }
        
        // EQ node is bypassed by default - user must enable via EQ window
        eqNode.bypass = true
    }
    
    private func setupSpectrumAnalyzer() {
        // Create FFT setup
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        
        // Note: The tap will be installed when loading a track with the correct format
        // Initial tap installation is deferred until we have an actual audio file
    }
    
    /// Install or reinstall the spectrum analyzer tap with the given format
    private func installSpectrumTap(format: AVAudioFormat?) {
        // Remove existing tap if any
        playerNode.removeTap(onBus: 0)
        
        // Install new tap - use nil format to let AVAudioEngine auto-detect the correct format
        playerNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: nil) { [weak self] buffer, _ in
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
        
        // Store raw PCM data for waveform visualization (before windowing)
        // Downsample to 512 samples for efficient storage and lowest latency
        let pcmSize = min(512, samples.count)
        let pcmStride = samples.count / pcmSize
        var pcmSamples = [Float](repeating: 0, count: pcmSize)
        for i in 0..<pcmSize {
            pcmSamples[i] = samples[i * pcmStride]
        }
        let bufferSampleRate = buffer.format.sampleRate
        
        // Post notification for low-latency visualization (direct from audio tap)
        NotificationCenter.default.post(
            name: .audioPCMDataUpdated,
            object: self,
            userInfo: ["pcm": pcmSamples, "sampleRate": bufferSampleRate]
        )
        
        // Also store in property for legacy access
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pcmSampleRate = bufferSampleRate
            self.pcmData = pcmSamples
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
                    sum += magnitudes[j]  // Use linear magnitudes, not log
                    count += 1
                }
                
                newSpectrum[band] = sum / count
            }
        }
        
        // Find peak magnitude for normalization
        let peakMag = newSpectrum.max() ?? 1.0
        guard peakMag > 0 else { return }
        
        // Normalize relative to peak and apply curve for visual dynamics
        for i in 0..<bandCount {
            let normalized = newSpectrum[i] / peakMag
            // Apply power curve to spread out values (0.5 = square root for more dynamics)
            newSpectrum[i] = pow(normalized, 0.4)
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

            // Post notification for low-latency spectrum updates
            NotificationCenter.default.post(
                name: .audioSpectrumDataUpdated,
                object: self,
                userInfo: ["spectrum": self.spectrumData]
            )
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
            // Streaming playback via AudioStreaming (with EQ support)
            NSLog("play(): Starting streaming playback via AudioStreaming (state: %@)", String(describing: streamingPlayer?.state ?? .stopped))
            
            // If streaming player is stopped (not paused), we need to reload the URL
            // resume() only works on a paused player, not a stopped one
            if let playerState = streamingPlayer?.state, playerState == .stopped || playerState == .error {
                NSLog("play(): Streaming player is stopped/error - reloading track")
                // Reload the current track to restart playback
                if currentIndex >= 0 && currentIndex < playlist.count {
                    loadTrack(at: currentIndex)
                    // play() will be called again after loadTrack completes and starts playing
                    return
                }
            }
            
            streamingPlayer?.resume()
            playbackStartDate = Date()
            state = .playing
            startTimeUpdates()
            
            // Report resume to Plex
            if let track = currentTrack {
                PlexPlaybackReporter.shared.trackDidResume(at: currentTime)
            }
            
            // Report resume to Subsonic
            SubsonicPlaybackReporter.shared.trackResumed()
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
                
                // Report resume to Plex (local files won't have plexRatingKey so this is a no-op)
                if let track = currentTrack {
                    PlexPlaybackReporter.shared.trackDidResume(at: currentTime)
                }
                
                // Report resume to Subsonic
                SubsonicPlaybackReporter.shared.trackResumed()
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
        let pausePosition = currentTime
        if let startDate = playbackStartDate {
            _currentTime += Date().timeIntervalSince(startDate)
        }
        playbackStartDate = nil
        
        if isStreamingPlayback {
            streamingPlayer?.pause()
        } else {
            playerNode.pause()
        }
        state = .paused
        stopTimeUpdates()
        
        // Report pause to Plex
        PlexPlaybackReporter.shared.trackDidPause(at: pausePosition)
        
        // Report pause to Subsonic
        SubsonicPlaybackReporter.shared.trackPaused()
    }
    
    func stop() {
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
        // If casting is active, stop casting as well
        if isCastingActive {
            Task {
                await CastManager.shared.stopCasting()
            }
        }
        
        stopLocalOnly()
    }
    
    /// Stop local playback without affecting cast session
    /// Used when loading new tracks while casting - we want to keep the cast session active
    private func stopLocalOnly() {
        // Capture position before stopping for Plex reporting
        let stopPosition = currentTime
        
        // Increment generation to invalidate completion handlers
        playbackGeneration += 1
        let currentGeneration = playbackGeneration
        
        if isStreamingPlayback {
            streamingPlayer?.stop()
        } else {
            playerNode.stop()
        }
        
        playbackStartDate = nil
        _currentTime = 0  // Reset to beginning
        lastReportedTime = 0
        state = .stopped
        stopTimeUpdates()
        
        // Report stop to Plex (not finished - user manually stopped)
        PlexPlaybackReporter.shared.trackDidStop(at: stopPosition, finished: false)
        
        // Report stop to Subsonic
        SubsonicPlaybackReporter.shared.trackStopped()
        
        // Clear spectrum analyzer
        clearSpectrum()
        
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
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
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
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
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
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
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
        
        // Get duration for clamping
        let currentDuration = duration
        
        // Guard against seeking when duration is unknown
        guard currentDuration > 0 else {
            NSLog("AudioEngine: Cannot seek - duration is 0 or unknown")
            return
        }
        
        // Clamp time to valid range
        // Use 1.0s buffer for streaming (seeking too close to EOF can crash the player)
        // Use 0.5s buffer for local files
        let eofBuffer: TimeInterval = isStreamingPlayback ? 1.0 : 0.5
        let seekTime = max(0, min(time, currentDuration - eofBuffer))
        
        if isStreamingPlayback {
            // Streaming playback - seek via AudioStreaming with debouncing
            // Cancel any pending seek and reset work items to prevent stale closures
            streamingSeekWorkItem?.cancel()
            streamingSeekResetWorkItem?.cancel()
            
            // Update UI immediately for responsiveness
            lastReportedTime = seekTime
            
            // If already seeking, just update the target and return
            // The debounced work item will use the latest value
            if isSeekingStreaming {
                NSLog("AudioEngine: Seek debounced - already seeking, will seek to %.2f", seekTime)
                // Schedule the actual seek after a short delay
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.isSeekingStreaming = true
                    NSLog("AudioEngine: Executing debounced seek to %.2f", seekTime)
                    self.streamingPlayer?.seek(to: seekTime)
                    // Schedule reset with a cancellable work item
                    self.scheduleSeekingReset()
                }
                streamingSeekWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
                return
            }
            
            // First seek - execute immediately
            isSeekingStreaming = true
            NSLog("AudioEngine: Seeking streaming to %.2f", seekTime)
            streamingPlayer?.seek(to: seekTime)
            
            // Reset seeking flag after a delay to allow player to stabilize
            scheduleSeekingReset()
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
    
    /// Schedule a cancellable reset of the isSeekingStreaming flag
    /// This ensures old reset closures don't fire when new seeks come in
    private func scheduleSeekingReset() {
        // Cancel any existing reset work item
        streamingSeekResetWorkItem?.cancel()
        
        // Create a new cancellable reset work item
        let resetItem = DispatchWorkItem { [weak self] in
            self?.isSeekingStreaming = false
        }
        streamingSeekResetWorkItem = resetItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: resetItem)
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
            // Get time from streaming player
            return streamingPlayer?.currentTime ?? 0
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
            // Get duration from streaming player, fall back to track metadata
            let streamDuration = streamingPlayer?.duration ?? 0
            return streamDuration > 0 ? streamDuration : (currentTrack?.duration ?? 0)
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
        
        // Update playback state and start UI updates
        state = .playing
        startTimeUpdates()
        
        // Notify delegate of track change
        delegate?.audioEngineDidChangeTrack(currentTrack)
        delegate?.audioEngineDidUpdateTime(current: position, duration: duration)
    }
    
    /// Pause cast playback time tracking
    func pauseCastPlayback() {
        // Save current interpolated position
        if let startDate = castPlaybackStartDate {
            castStartPosition += Date().timeIntervalSince(startDate)
        }
        castPlaybackStartDate = nil
        
        // Update state
        state = .paused
    }
    
    /// Resume cast playback time tracking
    func resumeCastPlayback() {
        castPlaybackStartDate = Date()
        
        // Update state
        state = .playing
    }
    
    /// Stop cast playback and resume local playback at current position
    /// - Parameter resumeLocally: If true, resume local playback from current cast position
    func stopCastPlayback(resumeLocally: Bool = false) {
        // Save current position before clearing cast state
        let currentPosition = castStartPosition
        if let startDate = castPlaybackStartDate {
            // Add elapsed time since last position update
            let elapsed = Date().timeIntervalSince(startDate)
            let position = currentPosition + elapsed
            
            if resumeLocally, let track = currentTrack {
                // Resume local playback from current position
                castPlaybackStartDate = nil
                castStartPosition = 0
                
                // Load and seek to position
                if let index = playlist.firstIndex(where: { $0.id == track.id }) {
                    currentIndex = index
                    loadTrack(at: index)
                    seek(to: position)
                    play()
                    return
                }
            }
        }
        
        // Default behavior - just stop
        castPlaybackStartDate = nil
        castStartPosition = 0
        state = .stopped
        stopTimeUpdates()
    }
    
    /// Decay spectrum to empty when not playing locally
    private func decaySpectrum() {
        var hasData = false
        for i in 0..<spectrumData.count {
            spectrumData[i] *= 0.85  // Gradual decay
            if spectrumData[i] > 0.01 {
                hasData = true
            } else {
                spectrumData[i] = 0
            }
        }
        
        // Only update delegate if there's still data decaying
        if hasData {
            delegate?.audioEngineDidUpdateSpectrum(spectrumData)
            NotificationCenter.default.post(
                name: .audioSpectrumDataUpdated,
                object: self,
                userInfo: ["spectrum": spectrumData]
            )
        }
    }
    
    /// Clear spectrum immediately
    private func clearSpectrum() {
        for i in 0..<spectrumData.count {
            spectrumData[i] = 0
        }
        delegate?.audioEngineDidUpdateSpectrum(spectrumData)
        NotificationCenter.default.post(
            name: .audioSpectrumDataUpdated,
            object: self,
            userInfo: ["spectrum": spectrumData]
        )
    }
    
    private func startTimeUpdates() {
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = self.currentTime
            let trackDuration = self.duration
            self.lastReportedTime = current
            self.delegate?.audioEngineDidUpdateTime(current: current, duration: trackDuration)
            
            // Update Plex playback position (for scrobble threshold detection)
            PlexPlaybackReporter.shared.updatePosition(current)
            
            // Update Subsonic playback position (for scrobbling)
            if let track = self.currentTrack,
               let subsonicId = track.subsonicId,
               let serverId = track.subsonicServerId {
                SubsonicPlaybackReporter.shared.updatePlayback(
                    trackId: subsonicId,
                    serverId: serverId,
                    position: current,
                    duration: trackDuration
                )
            }
            
            // Decay spectrum when not playing locally (casting or stopped)
            if self.isCastingActive || self.state != .playing {
                self.decaySpectrum()
            }
            
            // Check if we should start crossfade (Sweet Fades)
            if self.sweetFadeEnabled && !self.isCrossfading && !self.isCastingActive && self.state == .playing {
                let timeRemaining = trackDuration - current
                if timeRemaining > 0 && timeRemaining <= self.sweetFadeDuration {
                    self.startCrossfade()
                }
            }
            
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
        
        // Check if we're currently casting - we want to keep the cast session active
        let wasCasting = isCastingActive
        
        // Stop current local playback (but don't disconnect from cast device if casting)
        if wasCasting {
            // Just stop local playback, keep cast session
            stopLocalOnly()
            stopStreamingPlayer()
            isStreamingPlayback = false
        } else {
            stop()
            stopStreamingPlayer()
            isStreamingPlayback = false
        }
        
        playlist.removeAll()
        playlist.append(contentsOf: tracks)
        
        if !tracks.isEmpty {
            currentIndex = 0
            
            if wasCasting {
                // When casting, don't set up local playback - just set the track metadata
                // and cast to the active device
                let track = playlist[currentIndex]
                currentTrack = track
                _currentTime = 0
                lastReportedTime = 0
                
                NSLog("loadTracks: casting is active, casting new track '%@'", track.title)
                Task {
                    do {
                        try await CastManager.shared.castNewTrack(track)
                    } catch {
                        NSLog("loadTracks: failed to cast new track: %@", error.localizedDescription)
                        // Fall back to local playback if casting fails
                        await MainActor.run {
                            self.loadTrack(at: self.currentIndex)
                            self.play()
                        }
                    }
                }
            } else {
                // Normal local playback
                NSLog("loadTracks: loading track at index %d", currentIndex)
                loadTrack(at: currentIndex)
                play()
            }
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
        stopStreamingPlayer()
        isStreamingPlayback = false
        
        // Clear any pre-scheduled gapless track (we're loading a new track explicitly)
        nextScheduledFile = nil
        nextScheduledTrackIndex = -1
        
        do {
            let newAudioFile = try AVAudioFile(forReading: track.url)
            NSLog("loadLocalTrack: file loaded successfully, format: %@", newAudioFile.processingFormat.description)
            
            // Install spectrum analyzer tap
            installSpectrumTap(format: nil)
            
            audioFile = newAudioFile
            currentTrack = track
            _currentTime = 0  // Reset time for new track
            lastReportedTime = 0
            
            // Analyze and apply volume normalization if enabled
            if volumeNormalizationEnabled {
                analyzeAndApplyNormalization(file: newAudioFile)
            } else {
                normalizationGain = 1.0
                applyNormalizationGain()
            }
            
            // Increment generation to invalidate any old completion handlers
            playbackGeneration += 1
            let currentGeneration = playbackGeneration
            
            NSLog("loadLocalTrack: Stopping playerNode and scheduling file...")
            playerNode.stop()
            playerNode.scheduleFile(audioFile!, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.handlePlaybackComplete(generation: currentGeneration)
                }
            }
            
            // Pre-schedule next track for gapless playback
            if gaplessPlaybackEnabled {
                scheduleNextTrackForGapless()
            }
            
            // Report track start to Plex (no-op for local files without plexRatingKey)
            PlexPlaybackReporter.shared.trackDidStart(track, at: 0)
            
            // Report track start to Subsonic
            if let subsonicId = track.subsonicId,
               let serverId = track.subsonicServerId,
               let trackDuration = track.duration {
                SubsonicPlaybackReporter.shared.trackStarted(trackId: subsonicId, serverId: serverId, duration: trackDuration)
            }
            
            NSLog("loadLocalTrack: file scheduled, EQ bypass = %d, normGain = %.2f", eqNode.bypass, normalizationGain)
        } catch {
            NSLog("loadLocalTrack: FAILED - %@", error.localizedDescription)
        }
    }
    
    private func loadStreamingTrack(_ track: Track) {
        NSLog("loadStreamingTrack: %@ - %@", track.artist ?? "Unknown", track.title)
        NSLog("  URL: %@", track.url.absoluteString)
        
        // Stop local playback
        playerNode.stop()
        audioFile = nil
        isStreamingPlayback = true
        
        // Set flag before starting new track - EOF callbacks from old track should be ignored
        isLoadingNewStreamingTrack = true
        
        // DON'T call stop() before play() - the AudioStreaming library handles this internally.
        // Calling stop() explicitly causes a race condition where the async stop callback
        // fires AFTER play(url:) is called, cancelling the newly queued track.
        
        // Create streaming player if needed
        if streamingPlayer == nil {
            streamingPlayer = StreamingAudioPlayer()
            streamingPlayer?.delegate = self
        }
        
        // Sync EQ settings from main EQ to streaming player
        syncEQToStreamingPlayer()
        
        // Set volume
        streamingPlayer?.volume = volume
        
        currentTrack = track
        _currentTime = 0
        lastReportedTime = 0
        
        // Increment generation
        playbackGeneration += 1
        
        // Start playback through the streaming player (routes through AVAudioEngine with EQ)
        streamingPlayer?.play(url: track.url)
        
        // Set state to playing immediately so play() doesn't try to reload
        state = .playing
        playbackStartDate = Date()
        startTimeUpdates()
        
        // Clear the loading flag after a brief delay to ensure EOF callback has passed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isLoadingNewStreamingTrack = false
        }
        
        // Report track start to Plex
        PlexPlaybackReporter.shared.trackDidStart(track, at: 0)
        
        // Report track start to Subsonic
        if let subsonicId = track.subsonicId,
           let serverId = track.subsonicServerId,
           let trackDuration = track.duration {
            SubsonicPlaybackReporter.shared.trackStarted(trackId: subsonicId, serverId: serverId, duration: trackDuration)
        }
        
        NSLog("  Created StreamingAudioPlayer, starting playback with EQ")
    }
    
    /// Sync EQ settings from the main engine's EQ to a streaming player's EQ
    /// - Parameter player: The streaming player to sync, or nil to sync to the primary streaming player
    private func syncEQToStreamingPlayer(_ player: StreamingAudioPlayer? = nil) {
        let sp = player ?? streamingPlayer
        guard let targetPlayer = sp else { return }
        
        var bands: [Float] = []
        for i in 0..<10 {
            bands.append(eqNode.bands[i].gain)
        }
        
        targetPlayer.syncEQSettings(bands: bands, preamp: eqNode.globalGain, enabled: !eqNode.bypass)
    }
    
    private func stopStreamingPlayer() {
        streamingPlayer?.stop()
        // Note: We keep the streamingPlayer instance for reuse
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
        // Report track finished to Plex (natural end)
        let finishPosition = duration
        PlexPlaybackReporter.shared.trackDidStop(at: finishPosition, finished: true)
        
        // Report track finished to Subsonic (track stopped is called since it finished)
        SubsonicPlaybackReporter.shared.trackStopped()
        
        // Check if we have a gaplessly pre-scheduled next track (local files)
        if gaplessPlaybackEnabled && nextScheduledFile != nil && nextScheduledTrackIndex >= 0 {
            // Gapless transition - the next file is already scheduled
            currentIndex = nextScheduledTrackIndex
            audioFile = nextScheduledFile
            currentTrack = playlist[currentIndex]
            _currentTime = 0
            lastReportedTime = 0
            
            // Clear the pre-scheduled track
            nextScheduledFile = nil
            nextScheduledTrackIndex = -1
            
            // Notify delegate of track change
            delegate?.audioEngineDidChangeTrack(currentTrack)
            
            // Report new track to Plex
            PlexPlaybackReporter.shared.trackDidStart(currentTrack!, at: 0)
            
            // Report new track to Subsonic
            if let track = currentTrack,
               let subsonicId = track.subsonicId,
               let serverId = track.subsonicServerId,
               let trackDuration = track.duration {
                SubsonicPlaybackReporter.shared.trackStarted(trackId: subsonicId, serverId: serverId, duration: trackDuration)
            }
            
            // Apply normalization for the new track
            if volumeNormalizationEnabled {
                analyzeAndApplyNormalization(file: audioFile!)
            }
            
            // Schedule the next track for gapless
            scheduleNextTrackForGapless()
            
            NSLog("Gapless transition to: %@", currentTrack?.title ?? "Unknown")
            return
        }
        
        // Check if we have a gaplessly pre-scheduled streaming track
        // AudioStreaming library automatically plays the queued track, we just need to update metadata
        if gaplessPlaybackEnabled && isStreamingPlayback && streamingPlayer?.hasQueuedTrack == true && nextScheduledTrackIndex >= 0 {
            // Streaming gapless transition - the player already started the queued track
            currentIndex = nextScheduledTrackIndex
            currentTrack = playlist[currentIndex]
            _currentTime = 0
            lastReportedTime = 0
            
            // Clear the pre-scheduled track index
            nextScheduledTrackIndex = -1
            streamingPlayer?.clearQueue()  // Reset queue state (track already playing)
            
            // Notify delegate of track change
            delegate?.audioEngineDidChangeTrack(currentTrack)
            
            // Report new track to Plex
            PlexPlaybackReporter.shared.trackDidStart(currentTrack!, at: 0)
            
            // Report new track to Subsonic
            if let track = currentTrack,
               let subsonicId = track.subsonicId,
               let serverId = track.subsonicServerId,
               let trackDuration = track.duration {
                SubsonicPlaybackReporter.shared.trackStarted(trackId: subsonicId, serverId: serverId, duration: trackDuration)
            }
            
            // Schedule the next track for gapless
            scheduleNextTrackForGapless()
            
            NSLog("Streaming gapless transition to: %@", currentTrack?.title ?? "Unknown")
            return
        }
        
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
    
    // MARK: - Gapless Playback
    
    /// Pre-schedule the next track for gapless playback
    private func scheduleNextTrackForGapless() {
        guard gaplessPlaybackEnabled else { return }
        
        // Don't queue if Sweet Fades is enabled - it handles transitions
        guard !sweetFadeEnabled else {
            NSLog("Gapless: Skipping - Sweet Fades enabled")
            return
        }
        
        // Don't queue when casting - playback is remote
        guard !isCastingActive else {
            NSLog("Gapless: Skipping - casting is active")
            return
        }
        
        guard !repeatEnabled || shuffleEnabled else {
            // For repeat single track, we'll handle it in trackDidFinish
            return
        }
        
        let nextIndex = calculateNextTrackIndex()
        guard nextIndex >= 0 && nextIndex < playlist.count else {
            // No next track to schedule
            nextScheduledFile = nil
            nextScheduledTrackIndex = -1
            streamingPlayer?.clearQueue()
            return
        }
        
        let nextTrack = playlist[nextIndex]
        
        if isStreamingPlayback {
            // Streaming gapless - only if next track is also streaming
            let nextIsStreaming = nextTrack.url.scheme == "http" || nextTrack.url.scheme == "https"
            guard nextIsStreaming else {
                NSLog("Gapless: Next track is local file, can't queue for streaming gapless")
                return
            }
            
            streamingPlayer?.queue(url: nextTrack.url)
            nextScheduledTrackIndex = nextIndex
            NSLog("Gapless: Queued streaming track: %@", nextTrack.title)
        } else {
            // Local file gapless
            guard nextTrack.url.isFileURL else {
                NSLog("Gapless: Next track is streaming, can't queue for local gapless")
                return
            }
            
            do {
                let nextFile = try AVAudioFile(forReading: nextTrack.url)
                
                // Schedule the next file to play after the current one
                // Use the currently active player node
                let activePlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
                activePlayer.scheduleFile(nextFile, at: nil, completionHandler: nil)
                
                nextScheduledFile = nextFile
                nextScheduledTrackIndex = nextIndex
                
                NSLog("Gapless: Pre-scheduled next track: %@", nextTrack.title)
            } catch {
                NSLog("Gapless: Failed to pre-schedule next track: %@", error.localizedDescription)
                nextScheduledFile = nil
                nextScheduledTrackIndex = -1
            }
        }
    }
    
    /// Calculate the index of the next track based on shuffle/repeat settings
    private func calculateNextTrackIndex() -> Int {
        guard !playlist.isEmpty else { return -1 }
        
        if shuffleEnabled {
            return Int.random(in: 0..<playlist.count)
        } else {
            let next = currentIndex + 1
            return next < playlist.count ? next : -1
        }
    }
    
    // MARK: - Sweet Fades (Crossfade)
    
    /// Start crossfade to the next track
    private func startCrossfade() {
        guard !isCrossfading else { return }
        guard !isCastingActive else { return }
        
        // Don't crossfade in repeat-one mode (unusual UX)
        if repeatEnabled && !shuffleEnabled {
            NSLog("Sweet Fades: Skipping crossfade - repeat single mode")
            return
        }
        
        let nextIndex = calculateNextTrackIndex()
        guard nextIndex >= 0 && nextIndex < playlist.count else {
            NSLog("Sweet Fades: No next track available")
            return
        }
        
        let nextTrack = playlist[nextIndex]
        
        // Check if next track is same source type (can't crossfade mixed sources)
        let currentIsStreaming = isStreamingPlayback
        let nextIsStreaming = nextTrack.url.scheme == "http" || nextTrack.url.scheme == "https"
        
        guard currentIsStreaming == nextIsStreaming else {
            NSLog("Sweet Fades: Skipping crossfade - mixed source types")
            return
        }
        
        // Check track duration is sufficient (must be at least 2x fade duration)
        if let nextDuration = nextTrack.duration, nextDuration < sweetFadeDuration * 2 {
            NSLog("Sweet Fades: Skipping crossfade - next track too short (%.1fs < %.1fs)", nextDuration, sweetFadeDuration * 2)
            return
        }
        
        isCrossfading = true
        crossfadeTargetIndex = nextIndex
        NSLog("Sweet Fades: Starting crossfade to '%@'", nextTrack.title)
        
        if isStreamingPlayback {
            startStreamingCrossfade(to: nextTrack, nextIndex: nextIndex)
        } else {
            startLocalCrossfade(to: nextTrack, nextIndex: nextIndex)
        }
    }
    
    /// Start crossfade for local file playback
    private func startLocalCrossfade(to nextTrack: Track, nextIndex: Int) {
        do {
            let nextFile = try AVAudioFile(forReading: nextTrack.url)
            
            // Determine which player is currently active and which will be the crossfade target
            let outgoingPlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
            let incomingPlayer = crossfadePlayerIsActive ? playerNode : crossfadePlayerNode
            
            // Schedule on incoming player
            incomingPlayer.stop()
            incomingPlayer.volume = 0
            incomingPlayer.scheduleFile(nextFile, at: nil) {
                // This fires when the incoming track finishes
                // We handle track completion in completeCrossfade
            }
            
            // Start the incoming player
            incomingPlayer.play()
            
            // Store the file for later
            if crossfadePlayerIsActive {
                audioFile = nextFile
            } else {
                crossfadeAudioFile = nextFile
            }
            
            // Start volume ramp
            startCrossfadeVolumeRamp(
                outgoingVolume: { v in
                    outgoingPlayer.volume = v
                },
                incomingVolume: { v in
                    incomingPlayer.volume = v
                },
                completion: { [weak self] in
                    self?.completeCrossfade(nextFile: nextFile, nextIndex: nextIndex)
                }
            )
        } catch {
            NSLog("Sweet Fades: Failed to load next track: %@", error.localizedDescription)
            isCrossfading = false
            crossfadeTargetIndex = -1
        }
    }
    
    /// Start crossfade for streaming playback
    private func startStreamingCrossfade(to nextTrack: Track, nextIndex: Int) {
        // Create secondary streaming player if needed
        if crossfadeStreamingPlayer == nil {
            crossfadeStreamingPlayer = StreamingAudioPlayer()
            // Note: We don't set delegate - we handle state internally during crossfade
        }
        
        // Sync EQ settings to crossfade player
        syncEQToStreamingPlayer(crossfadeStreamingPlayer)
        
        // Start next track at volume 0
        crossfadeStreamingPlayer?.volume = 0
        crossfadeStreamingPlayer?.play(url: nextTrack.url)
        
        // Start volume ramp
        startCrossfadeVolumeRamp(
            outgoingVolume: { [weak self] v in
                self?.streamingPlayer?.volume = v
            },
            incomingVolume: { [weak self] v in
                self?.crossfadeStreamingPlayer?.volume = v
            },
            completion: { [weak self] in
                self?.completeStreamingCrossfade(nextIndex: nextIndex)
            }
        )
    }
    
    /// Perform volume ramping during crossfade
    private func startCrossfadeVolumeRamp(
        outgoingVolume: @escaping (Float) -> Void,
        incomingVolume: @escaping (Float) -> Void,
        completion: @escaping () -> Void
    ) {
        let startTime = Date()
        let fadeDuration = sweetFadeDuration
        let interval: TimeInterval = 0.05  // 50ms updates for smooth fading
        let targetVolume = volume
        
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / fadeDuration)
            
            // Equal-power crossfade curve for perceptually smooth transition
            // outVol = cos(progress * π/2), inVol = sin(progress * π/2)
            let angle = progress * .pi / 2
            let outVol = Float(cos(angle)) * targetVolume
            let inVol = Float(sin(angle)) * targetVolume
            
            outgoingVolume(outVol)
            incomingVolume(inVol)
            
            if progress >= 1.0 {
                timer.invalidate()
                self.crossfadeTimer = nil
                completion()
            }
        }
        
        // Use .common mode so timer fires during menu tracking
        RunLoop.main.add(timer, forMode: .common)
        crossfadeTimer = timer
    }
    
    /// Complete local file crossfade
    private func completeCrossfade(nextFile: AVAudioFile, nextIndex: Int) {
        // Stop outgoing player
        let outgoingPlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
        outgoingPlayer.stop()
        outgoingPlayer.volume = 0
        
        // Swap which player is active
        crossfadePlayerIsActive.toggle()
        
        // Update state
        audioFile = nextFile
        currentIndex = nextIndex
        currentTrack = playlist[nextIndex]
        _currentTime = 0
        lastReportedTime = 0
        playbackStartDate = Date()
        
        // Reset crossfade state
        isCrossfading = false
        crossfadeTargetIndex = -1
        
        // Notify delegate
        delegate?.audioEngineDidChangeTrack(currentTrack)
        
        // Report to Plex/Subsonic
        if let track = currentTrack {
            PlexPlaybackReporter.shared.trackDidStart(track, at: 0)
            
            if let subsonicId = track.subsonicId,
               let serverId = track.subsonicServerId,
               let trackDuration = track.duration {
                SubsonicPlaybackReporter.shared.trackStarted(trackId: subsonicId, serverId: serverId, duration: trackDuration)
            }
        }
        
        // Apply normalization for new track
        if volumeNormalizationEnabled {
            analyzeAndApplyNormalization(file: nextFile)
        }
        
        // Schedule next track for gapless (if enabled and Sweet Fades won't take over)
        if gaplessPlaybackEnabled && !sweetFadeEnabled {
            scheduleNextTrackForGapless()
        }
        
        NSLog("Sweet Fades: Crossfade complete, now playing: %@", currentTrack?.title ?? "Unknown")
    }
    
    /// Complete streaming crossfade
    private func completeStreamingCrossfade(nextIndex: Int) {
        // Stop outgoing player
        streamingPlayer?.stop()
        
        // Swap players - crossfade player becomes primary
        let oldPrimary = streamingPlayer
        streamingPlayer = crossfadeStreamingPlayer
        crossfadeStreamingPlayer = oldPrimary
        
        // Set delegate on new primary player
        streamingPlayer?.delegate = self
        crossfadeStreamingPlayer?.delegate = nil
        
        // Update state
        currentIndex = nextIndex
        currentTrack = playlist[nextIndex]
        _currentTime = 0
        lastReportedTime = 0
        playbackStartDate = Date()
        
        // Reset crossfade state
        isCrossfading = false
        crossfadeTargetIndex = -1
        
        // Notify delegate
        delegate?.audioEngineDidChangeTrack(currentTrack)
        
        // Report to Plex/Subsonic
        if let track = currentTrack {
            PlexPlaybackReporter.shared.trackDidStart(track, at: 0)
            
            if let subsonicId = track.subsonicId,
               let serverId = track.subsonicServerId,
               let trackDuration = track.duration {
                SubsonicPlaybackReporter.shared.trackStarted(trackId: subsonicId, serverId: serverId, duration: trackDuration)
            }
        }
        
        NSLog("Sweet Fades: Streaming crossfade complete, now playing: %@", currentTrack?.title ?? "Unknown")
    }
    
    /// Cancel an in-progress crossfade (called on seek, skip, stop)
    private func cancelCrossfade() {
        guard isCrossfading else { return }
        
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        
        // Stop incoming track/player
        if isStreamingPlayback {
            crossfadeStreamingPlayer?.stop()
            crossfadeStreamingPlayer?.volume = 0
            // Restore primary player volume
            streamingPlayer?.volume = volume
        } else {
            // Stop the incoming player
            let incomingPlayer = crossfadePlayerIsActive ? playerNode : crossfadePlayerNode
            incomingPlayer.stop()
            incomingPlayer.volume = 0
            
            // Restore outgoing player volume
            let outgoingPlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
            outgoingPlayer.volume = volume
        }
        
        isCrossfading = false
        crossfadeTargetIndex = -1
        NSLog("Sweet Fades: Crossfade cancelled")
    }
    
    // MARK: - Volume Normalization
    
    /// Analyze audio file and apply normalization gain
    private func analyzeAndApplyNormalization(file: AVAudioFile) {
        guard volumeNormalizationEnabled else {
            normalizationGain = 1.0
            applyNormalizationGain()
            return
        }
        
        // Analyze the file's peak and RMS levels
        let (peakDB, rmsDB) = analyzeAudioLevels(file: file)
        
        // Calculate gain needed to reach target loudness
        // Use RMS as a rough estimate of perceived loudness
        let gainNeededDB = targetLoudnessDB - rmsDB
        
        // Limit the gain to prevent excessive boost or cut
        // Max boost: +12 dB, Max cut: -12 dB
        let clampedGainDB = max(-12.0, min(12.0, gainNeededDB))
        
        // Also ensure we don't clip - reduce gain if peaks would exceed 0 dB
        let peakAfterGain = peakDB + clampedGainDB
        let finalGainDB: Float
        if peakAfterGain > -0.5 {
            // Would clip, reduce gain to leave 0.5 dB headroom
            finalGainDB = clampedGainDB - (peakAfterGain + 0.5)
        } else {
            finalGainDB = clampedGainDB
        }
        
        // Convert dB to linear gain
        normalizationGain = pow(10.0, finalGainDB / 20.0)
        
        NSLog("Normalization: peak=%.1fdB, rms=%.1fdB, gain=%.1fdB (%.2fx)", 
              peakDB, rmsDB, finalGainDB, normalizationGain)
        
        applyNormalizationGain()
    }
    
    /// Analyze audio file and return (peak dB, RMS dB)
    private func analyzeAudioLevels(file: AVAudioFile) -> (Float, Float) {
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(min(file.length, Int64(format.sampleRate * 30)))  // Analyze up to 30 seconds
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return (0, -20)  // Default values if analysis fails
        }
        
        // Save current position
        let savedPosition = file.framePosition
        file.framePosition = 0
        
        do {
            try file.read(into: buffer)
        } catch {
            file.framePosition = savedPosition
            return (0, -20)
        }
        
        // Restore position
        file.framePosition = savedPosition
        
        guard let channelData = buffer.floatChannelData else {
            return (0, -20)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        
        var peak: Float = 0
        var sumSquares: Float = 0
        var sampleCount: Int = 0
        
        for channel in 0..<channelCount {
            for frame in 0..<frameLength {
                let sample = abs(channelData[channel][frame])
                peak = max(peak, sample)
                sumSquares += sample * sample
                sampleCount += 1
            }
        }
        
        let rms = sqrt(sumSquares / Float(max(1, sampleCount)))
        
        // Convert to dB (avoid log of 0)
        let peakDB = peak > 0 ? 20 * log10(peak) : -96
        let rmsDB = rms > 0 ? 20 * log10(rms) : -96
        
        return (peakDB, rmsDB)
    }
    
    /// Apply the current normalization gain to the player
    private func applyNormalizationGain() {
        // Apply normalization by adjusting the EQ's global gain
        // This preserves the user's volume setting while normalizing
        let baseVolume = volume
        let normalizedVolume = baseVolume * normalizationGain
        
        // Clamp to valid range
        let finalVolume = max(0, min(1, normalizedVolume))
        
        // Apply to the currently active player (may be crossfade player after a crossfade)
        let activePlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
        activePlayer.volume = finalVolume
        
        // Note: For streaming, normalization is not applied (would require re-analysis)
    }
    
    // MARK: - Equalizer
    
    /// Set EQ band gain (-12 to +12 dB)
    func setEQBand(_ band: Int, gain: Float) {
        guard band >= 0 && band < 10 else { return }
        let clampedGain = max(-12, min(12, gain))
        eqNode.bands[band].gain = clampedGain
        // Sync to streaming player
        streamingPlayer?.setEQBand(band, gain: clampedGain)
    }
    
    /// Get EQ band gain
    func getEQBand(_ band: Int) -> Float {
        guard band >= 0 && band < 10 else { return 0 }
        return eqNode.bands[band].gain
    }
    
    /// Set preamp gain (-12 to +12 dB)
    func setPreamp(_ gain: Float) {
        let clampedGain = max(-12, min(12, gain))
        eqNode.globalGain = clampedGain
        // Sync to streaming player
        streamingPlayer?.setPreamp(clampedGain)
    }
    
    /// Get preamp gain
    func getPreamp() -> Float {
        return eqNode.globalGain
    }
    
    /// Enable/disable equalizer
    func setEQEnabled(_ enabled: Bool) {
        eqNode.bypass = !enabled
        // Sync to streaming player
        streamingPlayer?.setEQEnabled(enabled)
    }
    
    /// Check if equalizer is enabled
    func isEQEnabled() -> Bool {
        return !eqNode.bypass
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
        stopStreamingPlayer()
        isStreamingPlayback = false
        playlist.removeAll()
        currentIndex = -1
        currentTrack = nil
        audioFile = nil
        
        // Stop Plex playback tracking
        PlexPlaybackReporter.shared.stopTracking()
        
        // Stop Subsonic playback tracking
        SubsonicPlaybackReporter.shared.trackStopped()
        
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
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
        guard index >= 0 && index < playlist.count else {
            NSLog("playTrack: invalid index %d (playlist count: %d)", index, playlist.count)
            return
        }
        
        NSLog("playTrack: playing track at index %d", index)
        
        // Check if we're currently casting
        let wasCasting = isCastingActive
        
        currentIndex = index
        
        if wasCasting {
            // When casting, don't set up local playback - just update track metadata and cast
            let track = playlist[index]
            currentTrack = track
            _currentTime = 0
            lastReportedTime = 0
            
            NSLog("playTrack: casting is active, casting track at index %d", index)
            Task {
                do {
                    try await CastManager.shared.castNewTrack(track)
                } catch {
                    NSLog("playTrack: failed to cast track: %@", error.localizedDescription)
                    // Fall back to local playback if casting fails
                    await MainActor.run {
                        self.loadTrack(at: index)
                        self.play()
                    }
                }
            }
        } else {
            loadTrack(at: index)
            play()
        }
    }
    
    // MARK: - Playlist Sorting
    
    /// Sort criteria for playlist
    enum SortCriteria {
        case title
        case filename
        case path
        case duration
        case artist
        case album
    }
    
    /// Sort the playlist by the specified criteria
    func sortPlaylist(by criteria: SortCriteria, ascending: Bool = true) {
        // Remember current track
        let currentTrackURL = currentIndex >= 0 && currentIndex < playlist.count ? playlist[currentIndex].url : nil
        
        // Sort the playlist
        playlist.sort { track1, track2 in
            let comparison: ComparisonResult
            
            switch criteria {
            case .title:
                comparison = track1.displayTitle.localizedCaseInsensitiveCompare(track2.displayTitle)
            case .filename:
                comparison = track1.url.lastPathComponent.localizedCaseInsensitiveCompare(track2.url.lastPathComponent)
            case .path:
                comparison = track1.url.path.localizedCaseInsensitiveCompare(track2.url.path)
            case .duration:
                let d1 = track1.duration ?? 0
                let d2 = track2.duration ?? 0
                comparison = d1 < d2 ? .orderedAscending : (d1 > d2 ? .orderedDescending : .orderedSame)
            case .artist:
                let a1 = track1.artist ?? ""
                let a2 = track2.artist ?? ""
                comparison = a1.localizedCaseInsensitiveCompare(a2)
            case .album:
                let a1 = track1.album ?? ""
                let a2 = track2.album ?? ""
                comparison = a1.localizedCaseInsensitiveCompare(a2)
            }
            
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        
        // Restore current index
        if let url = currentTrackURL {
            currentIndex = playlist.firstIndex(where: { $0.url == url }) ?? -1
        }
        
        delegate?.audioEngineDidChangePlaylist()
    }
    
    /// Shuffle the playlist (randomize order)
    func shufflePlaylist() {
        // Remember current track
        let currentTrackURL = currentIndex >= 0 && currentIndex < playlist.count ? playlist[currentIndex].url : nil
        
        // Shuffle
        playlist.shuffle()
        
        // Restore current index
        if let url = currentTrackURL {
            currentIndex = playlist.firstIndex(where: { $0.url == url }) ?? -1
        }
        
        delegate?.audioEngineDidChangePlaylist()
    }
    
    /// Reverse the playlist order
    func reversePlaylist() {
        // Remember current track
        let currentTrackURL = currentIndex >= 0 && currentIndex < playlist.count ? playlist[currentIndex].url : nil
        
        // Reverse
        playlist.reverse()
        
        // Restore current index
        if let url = currentTrackURL {
            currentIndex = playlist.firstIndex(where: { $0.url == url }) ?? -1
        }
        
        delegate?.audioEngineDidChangePlaylist()
    }
}

// MARK: - StreamingAudioPlayerDelegate

extension AudioEngine: StreamingAudioPlayerDelegate {
    func streamingPlayerDidChangeState(_ state: AudioPlayerState) {
        // Map AudioStreaming state to our PlaybackState
        switch state {
        case .playing:
            self.state = .playing
            playbackStartDate = Date()
            isSeekingStreaming = false  // Clear seeking flag on successful playback
        case .paused:
            self.state = .paused
        case .stopped:
            self.state = .stopped
            isSeekingStreaming = false
            // Cancel any pending reset work item
            streamingSeekResetWorkItem?.cancel()
            streamingSeekResetWorkItem = nil
        case .error:
            NSLog("AudioEngine: Streaming player entered error state")
            self.state = .stopped
            isSeekingStreaming = false
            // Cancel any pending seeks and reset work items
            streamingSeekWorkItem?.cancel()
            streamingSeekWorkItem = nil
            streamingSeekResetWorkItem?.cancel()
            streamingSeekResetWorkItem = nil
        default:
            // bufferingStart, bufferingEnd, ready, etc. - don't change our state
            break
        }
    }
    
    func streamingPlayerDidFinishPlaying() {
        // Handle track completion - advance to next track
        // Note: We call trackDidFinish() directly instead of handlePlaybackComplete()
        // because the streaming player's state change callback (.stopped) fires BEFORE
        // this callback, so self.state is already .stopped by the time we get here.
        // 
        // IMPORTANT: When loading a new track, the old track's EOF callback fires
        // even though we intentionally stopped it. The isLoadingNewStreamingTrack flag
        // is set before stopping and cleared after the new track starts.
        guard !isLoadingNewStreamingTrack else {
            NSLog("AudioEngine: Ignoring EOF during track switch")
            return
        }
        NSLog("AudioEngine: Streaming track finished, advancing playlist")
        trackDidFinish()
    }
    
    func streamingPlayerDidUpdateSpectrum(_ levels: [Float]) {
        // Forward spectrum data from streaming player to delegate
        spectrumData = levels
        delegate?.audioEngineDidUpdateSpectrum(levels)
        NotificationCenter.default.post(
            name: .audioSpectrumDataUpdated,
            object: self,
            userInfo: ["spectrum": levels]
        )
    }
    
    func streamingPlayerDidUpdatePCM(_ samples: [Float]) {
        // Forward PCM data from streaming player for projectM visualization
        // Copy samples into pcmData, adjusting size as needed
        let copyCount = min(samples.count, pcmData.count)
        for i in 0..<copyCount {
            pcmData[i] = samples[i]
        }
        // Zero out remainder if samples is smaller
        for i in copyCount..<pcmData.count {
            pcmData[i] = 0
        }
        
        // Post notification for low-latency visualization
        // Use pcmData (not samples) to ensure consistency with stored property
        NotificationCenter.default.post(
            name: .audioPCMDataUpdated,
            object: self,
            userInfo: ["pcm": pcmData, "sampleRate": pcmSampleRate]
        )
    }
    
    func streamingPlayerDidDetectFormat(sampleRate: Int, channels: Int) {
        // Update current track with format info detected from the stream
        // This fills in sample rate for Plex tracks which don't have it in metadata
        guard let track = currentTrack else { return }
        
        // Only update if not already set
        if track.sampleRate == nil || track.channels == nil {
            NSLog("AudioEngine: Detected stream format - sampleRate: %d, channels: %d", sampleRate, channels)
            
            // Create updated track with format info
            let updatedTrack = Track(
                id: track.id,
                url: track.url,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                bitrate: track.bitrate,
                sampleRate: track.sampleRate ?? sampleRate,
                channels: track.channels ?? channels,
                plexRatingKey: track.plexRatingKey
            )
            
            currentTrack = updatedTrack
            
            // Update playlist entry as well
            if currentIndex >= 0 && currentIndex < playlist.count {
                playlist[currentIndex] = updatedTrack
            }
            
            // Notify delegate of track update (for UI refresh)
            delegate?.audioEngineDidChangeTrack(updatedTrack)
        }
    }
}
