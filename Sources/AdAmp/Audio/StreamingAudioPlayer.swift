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
    
    /// Smoothed reference levels for each region (prevents pulsing from max() jumps)
    private var spectrumRegionReferenceLevels: [Float] = [0.0, 0.0, 0.0]
    
    /// Global adaptive peak for adaptive normalization mode
    private var spectrumGlobalPeak: Float = 0.0
    
    /// Smoothed global reference level (prevents pulsing from max() jumps)
    private var spectrumGlobalReferenceLevel: Float = 0.0
    
    /// Current spectrum normalization mode (read from UserDefaults)
    private var spectrumNormalizationMode: SpectrumNormalizationMode {
        if let saved = UserDefaults.standard.string(forKey: "spectrumNormalizationMode"),
           let mode = SpectrumNormalizationMode(rawValue: saved) {
            return mode
        }
        return .accurate  // Default to accurate for flat pink noise
    }
    
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
    
    /// Pre-computed bandwidth scale factors for flat pink noise display
    private static let spectrumBandwidthScales: [Float] = {
        let bandCount = 75
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let ratio = pow(maxFreq / minFreq, 1.0 / Float(bandCount))
        
        // Reference bandwidth at 1000 Hz for normalization
        let refBandwidth = 1000.0 * (ratio - 1.0)
        
        return (0..<bandCount).map { band in
            let startFreq = minFreq * pow(maxFreq / minFreq, Float(band) / Float(bandCount))
            let endFreq = minFreq * pow(maxFreq / minFreq, Float(band + 1) / Float(bandCount))
            let bandwidth = endFreq - startFreq
            return sqrt(bandwidth / refBandwidth)
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
        
        // Compensate for volume so visualization is volume-independent
        // The frameFiltering tap captures audio after volume is applied, so we divide by volume
        // to recover the original signal level for visualization purposes
        let effectiveVolume = max(0.05, volume)  // Min 5% to avoid extreme amplification
        let volumeCompensation = min(20.0, 1.0 / effectiveVolume)  // Cap at 20x
        if volumeCompensation > 1.0 {
            // Apply compensation using Accelerate for efficiency
            var compensation = volumeCompensation
            vDSP_vsmul(samples, 1, &compensation, &samples, 1, vDSP_Length(fftSize))
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
        
        // Map to 75 bands (Winamp-style) using logarithmic frequency mapping
        let bandCount = 75
        var newSpectrum = [Float](repeating: 0, count: bandCount)
        
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let sampleRate = Float(buffer.format.sampleRate)
        let binWidth = sampleRate / Float(fftSize)
        let normMode = spectrumNormalizationMode
        
        for band in 0..<bandCount {
            // Calculate band edges and center frequency
            let startFreq = minFreq * pow(maxFreq / minFreq, Float(band) / Float(bandCount))
            let endFreq = minFreq * pow(maxFreq / minFreq, Float(band + 1) / Float(bandCount))
            let centerFreq = sqrt(startFreq * endFreq)
            
            if normMode == .accurate {
                // Accurate mode - sum total power across all bins in band, then convert to dB
                // High freq bands have more bins, so total power scales with bandwidth
                let startBin = max(1, Int(startFreq / binWidth))
                let endBin = max(startBin, min(fftSize / 2 - 1, Int(endFreq / binWidth)))
                
                var totalPower: Float = 0
                let binCount = Float(endBin - startBin + 1)
                for bin in startBin...endBin {
                    totalPower += magnitudes[bin] * magnitudes[bin]  // Sum power (mag²)
                }
                
                // Use RMS (average power) to preserve detail in high frequencies
                // Then scale by sqrt(bandwidth) to compensate for pink noise
                let avgPower = totalPower / max(binCount, 1)
                let rmsMag = sqrt(avgPower)
                
                // Apply bandwidth compensation for pink noise flatness
                let bandwidthHz = endFreq - startFreq
                let refBandwidth: Float = 20.0   // Lower ref = more high freq boost
                let bandwidthScale = pow(bandwidthHz / refBandwidth, 0.6)  // Steeper curve for highs
                let scaledMag = rmsMag * bandwidthScale
                
                // Convert to dB (20 * log10 for magnitude)
                let dB = 20.0 * log10(max(scaledMag, 1e-10))
                
                // Map dB range to 0-1 display range
                // For 2048-pt FFT, ~12dB higher than 512-pt
                let ceiling: Float = 40.0    // dB level that maps to 100%
                let floor: Float = 0.0       // dB level that maps to 0%
                let normalized = (dB - floor) / (ceiling - floor)
                newSpectrum[band] = max(0, min(1.0, Float(normalized)))
            } else {
                // Adaptive/Dynamic modes - interpolate at center frequency
                let exactBin = centerFreq / binWidth
                let lowerBin = max(0, Int(exactBin))
                let upperBin = min(lowerBin + 1, fftSize / 2 - 1)
                let fraction = exactBin - Float(lowerBin)
                let interpMag = magnitudes[lowerBin] * (1.0 - fraction) + magnitudes[upperBin] * fraction
                
                // Apply bandwidth scaling and frequency weighting
                let bandMagnitude = interpMag * Self.spectrumBandwidthScales[band]
                newSpectrum[band] = bandMagnitude * Self.spectrumFrequencyWeights[band]
            }
        }
        
        // Apply normalization based on selected mode
        switch normMode {
        case .accurate:
            // dB scaling already applied above - no additional processing needed
            break
            
        case .adaptive:
            // Global adaptive normalization - adapts to overall loudness
            // Preserves relative levels between frequency regions
            var globalPeak: Float = 0
            for i in 0..<bandCount {
                globalPeak = max(globalPeak, newSpectrum[i])
            }
            
            if globalPeak > 0 {
                // Update global adaptive peak (slow rise, slower decay)
                if globalPeak > spectrumGlobalPeak {
                    spectrumGlobalPeak = spectrumGlobalPeak * 0.92 + globalPeak * 0.08
                } else {
                    spectrumGlobalPeak = spectrumGlobalPeak * 0.995 + globalPeak * 0.005
                }
                
                // Target reference level based on adaptive peak
                let targetReferenceLevel = max(spectrumGlobalPeak * 0.5, globalPeak * 0.3)
                
                // Smooth the reference level to prevent pulsing from max() jumps
                spectrumGlobalReferenceLevel = spectrumGlobalReferenceLevel * 0.85 + targetReferenceLevel * 0.15
                let referenceLevel = max(spectrumGlobalReferenceLevel, 0.001)
                
                // Normalize all bands using global reference
                for i in 0..<bandCount {
                    let normalized = min(1.0, newSpectrum[i] / referenceLevel)
                    newSpectrum[i] = pow(normalized, 0.5)  // Square root curve for dynamics
                }
            }
            
        case .dynamic:
            // Per-region normalization - best visual appeal for music
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
                if regionPeak > spectrumRegionPeaks[regionIndex] {
                    spectrumRegionPeaks[regionIndex] = spectrumRegionPeaks[regionIndex] * 0.92 + regionPeak * 0.08
                } else {
                    spectrumRegionPeaks[regionIndex] = spectrumRegionPeaks[regionIndex] * 0.995 + regionPeak * 0.005
                }
                
                // Target reference level for this region
                let targetReferenceLevel = max(spectrumRegionPeaks[regionIndex] * 0.5, regionPeak * 0.3)
                
                // Smooth the reference level to prevent pulsing from max() jumps
                spectrumRegionReferenceLevels[regionIndex] = spectrumRegionReferenceLevels[regionIndex] * 0.85 + targetReferenceLevel * 0.15
                let referenceLevel = max(spectrumRegionReferenceLevels[regionIndex], 0.001)
                
                // Normalize bands in this region
                for i in start..<end {
                    let normalized = min(1.0, newSpectrum[i] / referenceLevel)
                    newSpectrum[i] = pow(normalized, 0.5)  // Square root curve
                }
            }
        }
        
        // Update spectrum data on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<bandCount {
                // Fast attack, smooth decay for all modes
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
        spectrumRegionReferenceLevels = [0.0, 0.0, 0.0]
        spectrumGlobalPeak = 0.0  // Reset global adaptive peak
        spectrumGlobalReferenceLevel = 0.0
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
