import Foundation
import AVFoundation
import AudioStreaming
import Accelerate

/// Delegate protocol for streaming audio player events
protocol StreamingAudioPlayerDelegate: AnyObject {
    func streamingPlayerDidChangeState(_ state: AudioPlayerState)
    func streamingPlayerDidFinishPlaying()
    func streamingPlayerDidUpdateSpectrum(_ levels: [Float])
    func streamingPlayerDidUpdatePCM(_ samples: [Float])
    func streamingPlayerDidDetectFormat(sampleRate: Int, channels: Int)
    func streamingPlayerDidEncounterError(_ error: AudioPlayerError)
    func streamingPlayerDidReceiveMetadata(_ metadata: [String: String])
}

/// Wrapper around AudioStreaming's AudioPlayer that provides EQ and spectrum analysis
/// for HTTP streaming audio (e.g., Plex content)
class StreamingAudioPlayer {
    
    // MARK: - Properties
    
    weak var delegate: StreamingAudioPlayerDelegate?
    
    /// The underlying AudioStreaming player
    private let player: AudioPlayer
    
    /// 10-band equalizer attached to the player
    private let eqNode: AVAudioUnitEQ
    
    /// FFT setup for spectrum analysis
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 2048
    
    /// Spectrum data (75 bands for Winamp-style visualization)
    private(set) var spectrumData: [Float] = Array(repeating: 0, count: 75)
    
    /// Running peak averages for adaptive spectrum normalization (per frequency region)
    /// Index 0 = bass (bands 0-24), 1 = mid (bands 25-49), 2 = treble (bands 50-74)
    private var spectrumRegionPeaks: [Float] = [0.0, 0.0, 0.0]
    
    /// Whether we've reported format info for the current track
    private var hasReportedFormat: Bool = false
    
    /// Pre-computed frequency weights for spectrum analyzer (light compensation)
    private static let spectrumFrequencyWeights: [Float] = {
        // Generate weights for 75 bands spanning 20Hz-20kHz logarithmically
        // Light compensation - let bass punch through
        let bandCount = 75
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        
        return (0..<bandCount).map { band in
            let freqRatio = Float(band) / Float(bandCount - 1)
            let freq = minFreq * pow(maxFreq / minFreq, freqRatio)
            
            // Minimal frequency weighting - just slight sub-bass reduction
            if freq < 40 {
                return 0.70  // Sub-bass: light reduction
            } else if freq < 100 {
                return 0.85  // Bass: very light reduction
            } else if freq < 300 {
                return 0.92  // Low-mid: minimal reduction
            } else {
                return 1.0   // Everything else: full level
            }
        }
    }()
    
    /// Standard Winamp EQ frequencies
    static let eqFrequencies: [Float] = [
        60, 170, 310, 600, 1000,
        3000, 6000, 12000, 14000, 16000
    ]
    
    /// Current playback state
    var state: AudioPlayerState {
        player.state
    }
    
    /// Current playback time in seconds
    var currentTime: TimeInterval {
        player.progress
    }
    
    /// Total duration in seconds
    var duration: TimeInterval {
        player.duration
    }
    
    /// Volume level (0.0 - 1.0)
    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    
    /// Playback rate (1.0 = normal speed)
    var rate: Float {
        get { player.rate }
        set { player.rate = newValue }
    }
    
    // MARK: - Initialization
    
    init() {
        // Create the player
        player = AudioPlayer()
        
        // Create and configure the EQ
        eqNode = AVAudioUnitEQ(numberOfBands: 10)
        setupEQ()
        
        // Attach EQ to the player's audio graph
        player.attach(node: eqNode)
        
        // Set up spectrum analysis
        setupSpectrumAnalyzer()
        
        // Set up player delegate
        player.delegate = self
        
        NSLog("StreamingAudioPlayer: Initialized with EQ")
    }
    
    deinit {
        fftSetup = nil
        player.stop()
    }
    
    // MARK: - Setup
    
    private func setupEQ() {
        // Configure each EQ band for graphic EQ behavior
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
            band.bandwidth = index < 5 ? 2.0 : 1.5
            band.gain = 0.0
            band.bypass = false   // Individual bands active when EQ is enabled
        }
        
        // EQ is bypassed by default - user must enable it
        eqNode.bypass = true
    }
    
    private func setupSpectrumAnalyzer() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        
        // Install frame filter for spectrum analysis
        player.frameFiltering.add(entry: "spectrumAnalyzer") { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
    }
    
    // MARK: - Playback Control
    
    /// Play audio from a URL (local or remote)
    func play(url: URL) {
        NSLog("StreamingAudioPlayer: Playing URL: %@", url.absoluteString)
        hasReportedFormat = false  // Reset for new track
        _hasQueuedTrack = false     // Clear any previous queue state
        player.play(url: url)
    }
    
    /// Pause playback
    func pause() {
        player.pause()
    }
    
    /// Resume playback
    func resume() {
        player.resume()
    }
    
    /// Stop playback
    func stop() {
        player.stop()
        _hasQueuedTrack = false  // Queue is cleared on stop
        clearSpectrum()
    }
    
    /// Seek to a specific time
    /// Note: AudioEngine is responsible for clamping to a safe range before calling this method
    func seek(to time: TimeInterval) {
        NSLog("StreamingAudioPlayer: Seeking to %.2f (duration: %.2f, state: %@)", time, duration, String(describing: state))
        
        // Guard against seeking when player is in a bad state
        guard state != .error else {
            NSLog("StreamingAudioPlayer: Cannot seek - player is in error state")
            return
        }
        
        player.seek(to: time)
    }
    
    // MARK: - Gapless Queue
    
    /// Track whether we have a queued track for gapless playback
    private var _hasQueuedTrack: Bool = false
    
    /// Whether there's a track queued for gapless playback
    var hasQueuedTrack: Bool {
        return _hasQueuedTrack
    }
    
    /// Queue a URL for gapless playback after current track
    /// Uses AudioStreaming's built-in queue API
    func queue(url: URL) {
        NSLog("StreamingAudioPlayer: Queueing URL for gapless: %@", url.absoluteString)
        player.queue(url: url)
        _hasQueuedTrack = true
    }
    
    /// Clear all queued tracks (e.g., when playlist changes or Sweet Fades takes over)
    func clearQueue() {
        NSLog("StreamingAudioPlayer: Clearing queue")
        // AudioStreaming clears queue on stop, but we may be playing
        // The queue is cleared when the current track finishes naturally
        _hasQueuedTrack = false
    }
    
    /// Check if player is in a recoverable state
    var isPlayable: Bool {
        state != .error && state != .disposed
    }
    
    /// Attempt to recover from error state by reloading the current URL
    func attemptRecovery(with url: URL) {
        NSLog("StreamingAudioPlayer: Attempting recovery with URL: %@", url.absoluteString)
        stop()
        play(url: url)
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
        eqNode.globalGain
    }
    
    /// Enable/disable equalizer
    func setEQEnabled(_ enabled: Bool) {
        eqNode.bypass = !enabled
    }
    
    /// Check if equalizer is enabled
    func isEQEnabled() -> Bool {
        !eqNode.bypass
    }
    
    /// Sync EQ settings from another source (e.g., the main AudioEngine's EQ)
    func syncEQSettings(bands: [Float], preamp: Float, enabled: Bool) {
        for (index, gain) in bands.enumerated() {
            setEQBand(index, gain: gain)
        }
        setPreamp(preamp)
        setEQEnabled(enabled)
    }
    
    // MARK: - Spectrum Analysis
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Skip FFT processing when paused or stopped to save CPU
        // The frame filter still receives buffers but we don't need to process them
        guard state == .playing else { return }
        
        guard let channelData = buffer.floatChannelData,
              let fftSetup = fftSetup else { return }
        
        // Report format info once per track
        if !hasReportedFormat {
            hasReportedFormat = true
            let sampleRate = Int(buffer.format.sampleRate)
            let channels = Int(buffer.format.channelCount)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.streamingPlayerDidDetectFormat(sampleRate: sampleRate, channels: channels)
            }
        }
        
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
        
        // Forward PCM data for projectM visualization
        // Downsample to 512 samples for efficient visualization and lowest latency
        let pcmSize = min(512, samples.count)
        let stride = max(1, samples.count / pcmSize)
        var pcmSamples = [Float](repeating: 0, count: pcmSize)
        for i in 0..<pcmSize {
            pcmSamples[i] = samples[i * stride]
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.streamingPlayerDidUpdatePCM(pcmSamples)
        }
        
        // Apply Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))
        
        // Perform FFT
        var realIn = samples
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)
        
        vDSP_DFT_Execute(fftSetup, &realIn, &imagIn, &realOut, &imagOut)
        
        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        for i in 0..<fftSize / 2 {
            magnitudes[i] = sqrt(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }
        
        // Map to 75 bands (Winamp-style)
        let bandCount = 75
        var newSpectrum = [Float](repeating: 0, count: bandCount)
        
        // Logarithmic frequency mapping
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let sampleRate = Float(buffer.format.sampleRate)
        let binWidth = sampleRate / Float(fftSize)
        
        for band in 0..<bandCount {
            let freqRatio = Float(band) / Float(bandCount - 1)
            let freq = minFreq * pow(maxFreq / minFreq, freqRatio)
            let bin = Int(freq / binWidth)
            
            if bin < fftSize / 2 && bin >= 0 {
                var sum: Float = 0
                var count: Float = 0
                let range = max(1, bin / 10)
                
                for j in max(0, bin - range)..<min(fftSize / 2, bin + range + 1) {
                    sum += magnitudes[j]
                    count += 1
                }
                
                // Apply frequency weighting to compensate for bass dominance
                newSpectrum[band] = (sum / count) * Self.spectrumFrequencyWeights[band]
            }
        }
        
        // Per-region normalization so bass doesn't drown out mids/treble
        // Each frequency region (bass, mid, treble) normalizes independently
        let regionRanges = [(0, 25), (25, 50), (50, 75)]  // bass, mid, treble
        
        for (regionIndex, (start, end)) in regionRanges.enumerated() {
            // Find peak in this region
            var regionPeak: Float = 0.0
            for i in start..<end {
                regionPeak = max(regionPeak, newSpectrum[i])
            }
            
            guard regionPeak > 0 else { continue }
            
            // Update adaptive peak for this region
            // Slow rise and slow decay for stable reference level (avoids pumping)
            if regionPeak > spectrumRegionPeaks[regionIndex] {
                spectrumRegionPeaks[regionIndex] = spectrumRegionPeaks[regionIndex] * 0.92 + regionPeak * 0.08
            } else {
                spectrumRegionPeaks[regionIndex] = spectrumRegionPeaks[regionIndex] * 0.995 + regionPeak * 0.005
            }
            
            // Reference level for this region
            let referenceLevel = max(spectrumRegionPeaks[regionIndex] * 0.5, regionPeak * 0.3)
            
            // Normalize bands in this region
            for i in start..<end {
                let normalized = min(1.0, newSpectrum[i] / referenceLevel)
                // Square root curve for good dynamic spread
                newSpectrum[i] = pow(normalized, 0.5)
            }
        }
        
        // Update spectrum data on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<bandCount {
                // Fast attack, smooth decay for visual appeal
                if newSpectrum[i] > self.spectrumData[i] {
                    self.spectrumData[i] = newSpectrum[i]
                } else {
                    self.spectrumData[i] = self.spectrumData[i] * 0.90 + newSpectrum[i] * 0.10
                }
            }
            self.delegate?.streamingPlayerDidUpdateSpectrum(self.spectrumData)
        }
    }
    
    /// Clear spectrum data
    func clearSpectrum() {
        for i in 0..<spectrumData.count {
            spectrumData[i] = 0
        }
        spectrumRegionPeaks = [0.0, 0.0, 0.0]  // Reset adaptive peaks for new track
        delegate?.streamingPlayerDidUpdateSpectrum(spectrumData)
    }
}

// MARK: - AudioPlayerDelegate

extension StreamingAudioPlayer: AudioPlayerDelegate {
    func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {
        NSLog("StreamingAudioPlayer: Started playing entry: %@", entryId.id)
        delegate?.streamingPlayerDidChangeState(.playing)
    }
    
    func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {
        NSLog("StreamingAudioPlayer: Finished buffering entry: %@", entryId.id)
    }
    
    func audioPlayerStateChanged(player: AudioPlayer, with newState: AudioPlayerState, previous: AudioPlayerState) {
        NSLog("StreamingAudioPlayer: State changed from %@ to %@", String(describing: previous), String(describing: newState))
        delegate?.streamingPlayerDidChangeState(newState)
    }
    
    func audioPlayerDidFinishPlaying(player: AudioPlayer, entryId: AudioEntryId, stopReason: AudioPlayerStopReason, progress: Double, duration: Double) {
        NSLog("StreamingAudioPlayer: Finished playing entry: %@, reason: %@", entryId.id, String(describing: stopReason))
        
        // Only notify if playback finished naturally (not user action)
        if stopReason == .eof {
            delegate?.streamingPlayerDidFinishPlaying()
        }
        
        clearSpectrum()
    }
    
    func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        NSLog("StreamingAudioPlayer: Unexpected error: %@", String(describing: error))
        delegate?.streamingPlayerDidEncounterError(error)
    }
    
    func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {
        NSLog("StreamingAudioPlayer: Cancelled with %d queued items", queuedItems.count)
    }
    
    func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {
        NSLog("StreamingAudioPlayer: Read metadata: %@", metadata.description)
        
        // Forward metadata to delegate (for ICY stream info like current song)
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.streamingPlayerDidReceiveMetadata(metadata)
        }
    }
}
