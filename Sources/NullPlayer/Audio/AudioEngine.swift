import AVFoundation
import AppKit
import Accelerate
import CoreAudio
import AudioToolbox
import AudioStreaming
import NullPlayerCore

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

    /// Posted when playback option state changes (repeat, shuffle, gapless, normalization, crossfade)
    static let audioPlaybackOptionsChanged = Notification.Name("audioPlaybackOptionsChanged")
    
    /// Posted when the current track changes
    /// userInfo contains: "track" (Track?) - may be nil when playback stops
    static let audioTrackDidChange = Notification.Name("audioTrackDidChange")
    
    /// Posted when a track fails to load
    /// userInfo contains: "track" (Track), "error" (Error), "message" (String)
    static let audioTrackDidFailToLoad = Notification.Name("audioTrackDidFailToLoad")
    
    /// Posted when BPM detection updates
    /// userInfo contains: "bpm" (Int) - 0 means no confident reading
    static let bpmUpdated = Notification.Name("bpmUpdated")
    
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
    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error)
}

/// Core audio engine using AVAudioEngine for playback and DSP
class AudioEngine {

    static var isHeadless = false

    struct LocalPlaybackSleepClockState: Equatable {
        let currentTime: TimeInterval
        let playbackStartDate: Date?
        let suspendedForSleep: Bool
    }

    private struct ShufflePlaybackStateSnapshot {
        let order: [Int]
        let position: Int
        let pendingRepeatOrder: [Int]?
    }

    static func freezeLocalPlaybackClockForSleep(
        currentTime: TimeInterval,
        playbackStartDate: Date,
        now: Date
    ) -> LocalPlaybackSleepClockState {
        LocalPlaybackSleepClockState(
            currentTime: currentTime + now.timeIntervalSince(playbackStartDate),
            playbackStartDate: nil,
            suspendedForSleep: true
        )
    }

    static func resumeLocalPlaybackClockAfterSleep(
        currentTime: TimeInterval,
        suspendedForSleep: Bool,
        state: PlaybackState,
        now: Date
    ) -> LocalPlaybackSleepClockState {
        guard suspendedForSleep, state == .playing else {
            return LocalPlaybackSleepClockState(
                currentTime: currentTime,
                playbackStartDate: nil,
                suspendedForSleep: false
            )
        }

        return LocalPlaybackSleepClockState(
            currentTime: currentTime,
            playbackStartDate: now,
            suspendedForSleep: false
        )
    }

    // MARK: - Properties

    weak var delegate: AudioEngineDelegate?
    
    /// The AVAudioEngine instance
    private let engine = AVAudioEngine()
    
    /// Audio player node
    private let playerNode = AVAudioPlayerNode()
    
    /// Active EQ layout. Classic mode keeps the legacy 10-band layout; modern mode uses 21 bands.
    private let activeEQConfiguration: EQConfiguration

    /// Equalizer
    private let eqNode: AVAudioUnitEQ
    
    /// Mixer node to combine player nodes (class property for graph rebuilding)
    private let mixerNode = AVAudioMixerNode()
    
    /// Current audio file (for local files)
    private var audioFile: AVAudioFile?
    
    /// Streaming audio player (for HTTP URLs like Plex) - uses AudioStreaming library
    /// This routes audio through AVAudioEngine so EQ affects streaming audio
    private var streamingPlayer: StreamingAudioPlayer?
    private var isStreamingPlayback: Bool = false
    private var isLoadingNewStreamingTrack: Bool = false
    
    /// Guard against concurrent loadTrack() calls which can cause both local and streaming players to be active
    private var isLoadingTrack: Bool = false

    /// Background queue for non-critical local/NAS file I/O (normalization analysis, gapless pre-open).
    private let deferredIOQueue = DispatchQueue(label: "NullPlayer.AudioEngine.deferredIO", qos: .userInitiated)

    /// Token used to invalidate stale in-flight normalization analyses.
    private var normalizationAnalysisToken: UInt64 = 0

    /// Token used to invalidate stale in-flight gapless pre-schedule requests.
    private var gaplessPreparationToken: UInt64 = 0

    /// Token used to invalidate stale deferred local track loads triggered by direct user selection.
    private var deferredLocalTrackLoadToken: UInt64 = 0

    /// Temp file copied from a network-mounted volume for the current track.
    /// Using a local copy prevents AVAudioPlayerNode's render pre-fetch thread from doing
    /// NAS reads during playback, which causes dropouts on any network latency spike.
    private var tempPlaybackFileURL: URL?

    /// Temp file for the gaplessly pre-scheduled next track (NAS copy).
    /// Promoted to tempPlaybackFileURL on gapless transition; cleaned up otherwise.
    private var tempGaplessFileURL: URL?


    /// Tracks whether the local playback clock was intentionally frozen for a sleep cycle.
    private var suspendedLocalPlaybackClockForSleep = false

    /// In-flight placeholder resolution tasks keyed by playlist index.
    private var placeholderResolutionTasks: [Int: Task<Void, Never>] = [:]

    /// One-shot stale URL refresh guard for the current playback attempt.
    private var staleStreamingRefreshRetriedServiceIdentity: String?
    
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
            // Reset BPM detector for new track
            bpmDetector.reset()
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

    /// Stable shuffled traversal state used for auto-advance and manual next/previous.
    private var shufflePlaybackOrder: [Int] = []
    private var shufflePlaybackPosition: Int = -1
    private var pendingRepeatShuffleOrder: [Int]?
    
    /// Volume level (0.0 - 1.0)
    var volume: Float = 0.2 {
        didSet {
            // Apply volume with normalization gain for local playback
            applyNormalizationGain()
            streamingPlayer?.volume = volume
            
            // Apply volume to video player
            if !AudioEngine.isHeadless {
                WindowManager.shared.setVideoVolume(volume)
            }
            
            // Send volume to cast device if any casting is active (audio or video)
            if isAnyCastingActive {
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
    var shuffleEnabled: Bool = false {
        didSet {
            if shuffleEnabled {
                rebuildShufflePlaybackOrder(anchoredAt: currentIndex)
            } else {
                clearShufflePlaybackState()
            }
            notifyPlaybackOptionsChanged()
        }
    }
    
    /// Repeat mode
    var repeatEnabled: Bool = false {
        didSet {
            notifyPlaybackOptionsChanged()
        }
    }
    
    /// Gapless playback mode - pre-schedules next track for seamless transitions
    var gaplessPlaybackEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(gaplessPlaybackEnabled, forKey: UserDefaults.Keys.gaplessPlaybackEnabled)
            // If enabling and currently playing, schedule next track
            if gaplessPlaybackEnabled && state == .playing {
                scheduleNextTrackForGapless()
            }
            notifyPlaybackOptionsChanged()
        }
    }
    
    /// Volume normalization - analyzes and normalizes track loudness
    var volumeNormalizationEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(volumeNormalizationEnabled, forKey: UserDefaults.Keys.volumeNormalizationEnabled)
            // Recalculate normalization for current track
            if volumeNormalizationEnabled {
                applyNormalizationGain()
            } else {
                normalizationGain = 1.0
                applyNormalizationGain()
            }
            notifyPlaybackOptionsChanged()
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
            UserDefaults.standard.set(sweetFadeEnabled, forKey: UserDefaults.Keys.sweetFadeEnabled)
            Log.audio.infoPublic("AudioEngine: Sweet Fades \(sweetFadeEnabled ? "enabled" : "disabled")")
            notifyPlaybackOptionsChanged()
        }
    }
    
    /// Crossfade duration in seconds (default 5s)
    var sweetFadeDuration: TimeInterval = 5.0 {
        didSet {
            UserDefaults.standard.set(sweetFadeDuration, forKey: UserDefaults.Keys.sweetFadeDuration)
            Log.audio.infoPublic("AudioEngine: Sweet Fades duration set to \(String(format: "%.1f", sweetFadeDuration))s")
            notifyPlaybackOptionsChanged()
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

    /// Secondary guard for stale in-flight Sweet Fades file opens.
    /// Incremented on each `startLocalCrossfade` call so a late-arriving callback can
    /// detect it has been superseded. Primary cancellation signal is `isCrossfading`:
    /// both guards must pass before a deferred callback modifies engine state.
    private var crossfadeFileLoadToken: UInt64 = 0

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
    
    /// Spectrum analyzer data (75 bands for classic skin-style visualization)
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
    
    /// Current spectrum normalization mode (cached from UserDefaults, updated via notification)
    private var spectrumNormalizationMode: SpectrumNormalizationMode = .accurate
    
    /// Real-time BPM detector for tempo display
    private let bpmDetector = BPMDetector()
    
    
    /// Raw PCM audio data for waveform visualization (mono, normalized -1 to 1)
    private(set) var pcmData: [Float] = Array(repeating: 0, count: 512)
    
    /// PCM sample rate for visualization timing
    private(set) var pcmSampleRate: Double = 44100
    
    /// Reusable userInfo dict for PCM notifications (avoids per-callback allocation)
    private var pcmUserInfo: [String: Any] = [:]

    /// Reusable 576-sample stereo waveform buffers for vis_classic exact mode
    private var waveformLeftU8 = [UInt8](repeating: 128, count: 576)
    private var waveformRightU8 = [UInt8](repeating: 128, count: 576)
    private var waveformUserInfo: [String: Any] = [:]
    private var waveformLeftRing = [Float](repeating: 0, count: 8192)
    private var waveformRightRing = [Float](repeating: 0, count: 8192)
    private var waveformRingReadIndex = 0
    private var waveformRingWriteIndex = 0
    private var waveformRingCount = 0

    /// FFT setup for spectrum analysis
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 2048  // Match streaming FFT for consistent display
    
    // MARK: - Spectrum Update Throttling (Memory Optimization)
    
    /// Last time spectrum notification was posted (throttle to 60Hz max)
    private var lastSpectrumUpdateTime: CFAbsoluteTime = 0
    private let spectrumUpdateInterval: CFAbsoluteTime = 1.0 / 60.0  // 60Hz max
    
    /// Flag to coalesce main queue PCM dispatches
    private var pendingPcmUpdate = false
    
    // MARK: - Spectrum Consumer Tracking

    /// Spectrum consumers — FFT is skipped entirely when this set is empty
    private var spectrumConsumers = Set<String>()
    
    /// Live waveform consumers — 576-sample waveform chunk generation is skipped entirely when this set is empty.
    private var waveformConsumers = Set<String>()

    /// Cached value of modernUIEnabled to avoid 60x/sec UserDefaults reads
    private var isModernUIEnabled: Bool

    var eqConfiguration: EQConfiguration {
        activeEQConfiguration
    }

    func addSpectrumConsumer(_ id: String) {
        spectrumConsumers.insert(id)
        streamingPlayer?.spectrumNeeded = !spectrumConsumers.isEmpty
    }

    func removeSpectrumConsumer(_ id: String) {
        spectrumConsumers.remove(id)
        streamingPlayer?.spectrumNeeded = !spectrumConsumers.isEmpty
    }

    var spectrumNeeded: Bool { !spectrumConsumers.isEmpty }

    func addWaveformConsumer(_ id: String) {
        waveformConsumers.insert(id)
        streamingPlayer?.waveformNeeded = !waveformConsumers.isEmpty
    }

    func removeWaveformConsumer(_ id: String) {
        waveformConsumers.remove(id)
        streamingPlayer?.waveformNeeded = !waveformConsumers.isEmpty
    }

    var waveformNeeded: Bool { !waveformConsumers.isEmpty }

    // MARK: - Pre-allocated FFT Buffers (Memory Optimization)

    /// Pre-allocated buffers to avoid per-callback allocations
    private var fftSamples = [Float](repeating: 0, count: 2048)
    private var fftWindow = [Float](repeating: 0, count: 2048)
    private var fftRealIn = [Float](repeating: 0, count: 2048)
    private var fftImagIn = [Float](repeating: 0, count: 2048)
    private var fftRealOut = [Float](repeating: 0, count: 2048)
    private var fftImagOut = [Float](repeating: 0, count: 2048)
    private var fftMagnitudes = [Float](repeating: 0, count: 1024)
    private var fftLogMagnitudes = [Float](repeating: 0, count: 1024)
    private var fftNewSpectrum = [Float](repeating: 0, count: 75)
    private var fftPcmSamples = [Float](repeating: 0, count: 512)
    
    /// Pre-computed frequency weights for spectrum analyzer (light compensation)
    private let spectrumFrequencyWeights: [Float] = {
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
    /// Pink noise has magnitude ∝ 1/sqrt(f), bandwidth ∝ f for log bands
    /// Scaling by sqrt(bandwidth) gives: 1/sqrt(f) × sqrt(f) = constant (flat)
    private let spectrumBandwidthScales: [Float] = {
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
    
    /// Tap for audio analysis
    private var analysisTap: AVAudioNodeTapBlock?
    
    /// Current output device ID (nil = system default)
    private(set) var currentOutputDeviceID: AudioDeviceID?
    
    /// Whether audio casting is currently active (playback controlled by CastManager)
    var isCastingActive: Bool {
        CastManager.shared.isCasting
    }
    
    /// Whether video casting is active (from video player)
    var isVideoCastingActive: Bool {
        if AudioEngine.isHeadless { return false }
        return WindowManager.shared.isVideoCastingActive
    }
    
    /// Whether any casting (audio or video) is active
    var isAnyCastingActive: Bool {
        isCastingActive || isVideoCastingActive
    }
    
    // MARK: - Initialization
    
    init() {
        let modernUIEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.modernUIEnabled)
        isModernUIEnabled = modernUIEnabled
        activeEQConfiguration = EQConfiguration.forModernUI(modernUIEnabled)
        eqNode = AVAudioUnitEQ(numberOfBands: activeEQConfiguration.bandCount)

        // Initialize cached normalization mode from UserDefaults
        if let saved = UserDefaults.standard.string(forKey: UserDefaults.Keys.spectrumNormalizationMode),
           let mode = SpectrumNormalizationMode(rawValue: saved) {
            spectrumNormalizationMode = mode
        }
        
        // Observe audio device configuration changes FIRST
        // This handles format mismatches when output device changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
        
        // Observe spectrum settings changes to update cached normalization mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpectrumSettingsChanged),
            name: NSNotification.Name("SpectrumSettingsChanged"),
            object: nil
        )

        // Keep cached isModernUIEnabled in sync when user toggles UI mode
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleModernUIChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        setupAudioEngine()
        setupEqualizer()
        setupSpectrumAnalyzer()
        
        // Restore saved output device (notification handler will rebuild graph if needed)
        restoreSavedOutputDevice()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timeUpdateTimer?.invalidate()
        mixerNode.removeTap(onBus: 0)  // Changed from playerNode - tap is now on mixerNode
        engine.stop()
        // FFT setup is automatically released when set to nil
        fftSetup = nil
    }

    private func notifyPlaybackOptionsChanged() {
        NotificationCenter.default.post(name: .audioPlaybackOptionsChanged, object: self)
    }

    private func captureShufflePlaybackState() -> ShufflePlaybackStateSnapshot {
        ShufflePlaybackStateSnapshot(
            order: shufflePlaybackOrder,
            position: shufflePlaybackPosition,
            pendingRepeatOrder: pendingRepeatShuffleOrder
        )
    }

    private func restoreShufflePlaybackState(_ snapshot: ShufflePlaybackStateSnapshot) {
        shufflePlaybackOrder = snapshot.order
        shufflePlaybackPosition = snapshot.position
        pendingRepeatShuffleOrder = snapshot.pendingRepeatOrder
    }

    private func clearShufflePlaybackState() {
        shufflePlaybackOrder.removeAll()
        shufflePlaybackPosition = -1
        pendingRepeatShuffleOrder = nil
    }

    private func isValidShuffleOrder(_ order: [Int], count: Int) -> Bool {
        guard order.count == count else { return false }
        return Set(order) == Set(0..<count)
    }

    private func rebuildShufflePlaybackOrder(anchoredAt index: Int?) {
        guard shuffleEnabled, !playlist.isEmpty else {
            clearShufflePlaybackState()
            return
        }

        var indices = Array(0..<playlist.count)
        if let index, index >= 0, index < playlist.count {
            indices.removeAll { $0 == index }
            indices.shuffle()
            shufflePlaybackOrder = [index] + indices
            shufflePlaybackPosition = 0
        } else {
            indices.shuffle()
            shufflePlaybackOrder = indices
            shufflePlaybackPosition = -1
        }

        pendingRepeatShuffleOrder = nil
    }

    private func startShufflePlaybackCycle(preferredIndices: [Int]? = nil) -> Int? {
        guard shuffleEnabled, !playlist.isEmpty else { return nil }

        let validPreferredIndices = (preferredIndices ?? Array(playlist.indices))
            .filter { $0 >= 0 && $0 < playlist.count }
        let deduplicatedPreferredIndices = Array(NSOrderedSet(array: validPreferredIndices)) as? [Int] ?? validPreferredIndices
        let preferredPool = deduplicatedPreferredIndices.isEmpty ? Array(playlist.indices) : deduplicatedPreferredIndices
        guard let startIndex = preferredPool.randomElement() else { return nil }

        let preferredSet = Set(preferredPool)
        var remainingPreferred = preferredPool.filter { $0 != startIndex }
        remainingPreferred.shuffle()

        var remainingOther = playlist.indices.filter { index in
            index != startIndex && !preferredSet.contains(index)
        }
        remainingOther.shuffle()

        shufflePlaybackOrder = [startIndex] + remainingPreferred + remainingOther
        shufflePlaybackPosition = 0
        pendingRepeatShuffleOrder = nil
        return startIndex
    }

    private func invalidateShufflePlaybackStateAfterPlaylistMutation() {
        guard shuffleEnabled else {
            clearShufflePlaybackState()
            return
        }

        rebuildShufflePlaybackOrder(anchoredAt: currentIndex)
    }

    private func ensureShufflePlaybackOrderAligned(anchoredAt index: Int?) {
        guard shuffleEnabled else {
            clearShufflePlaybackState()
            return
        }
        guard !playlist.isEmpty else {
            clearShufflePlaybackState()
            return
        }

        if !isValidShuffleOrder(shufflePlaybackOrder, count: playlist.count) {
            rebuildShufflePlaybackOrder(anchoredAt: index)
            return
        }

        if let index, index >= 0, index < playlist.count {
            guard let position = shufflePlaybackOrder.firstIndex(of: index) else {
                rebuildShufflePlaybackOrder(anchoredAt: index)
                return
            }
            shufflePlaybackPosition = position
        }

        if let pendingRepeatShuffleOrder,
           !isValidShuffleOrder(pendingRepeatShuffleOrder, count: playlist.count) {
            self.pendingRepeatShuffleOrder = nil
        }
    }

    private func makeRepeatedShuffleOrder(avoidingImmediateRepeatOf index: Int?) -> [Int] {
        var order = Array(0..<playlist.count)
        order.shuffle()

        if let index, order.count > 1, order.first == index {
            let swapIndex = Int.random(in: 1..<order.count)
            order.swapAt(0, swapIndex)
        }

        return order
    }

    private func preparedRepeatShuffleOrder() -> [Int] {
        if let pendingRepeatShuffleOrder,
           isValidShuffleOrder(pendingRepeatShuffleOrder, count: playlist.count) {
            return pendingRepeatShuffleOrder
        }

        let order = makeRepeatedShuffleOrder(avoidingImmediateRepeatOf: currentIndex)
        pendingRepeatShuffleOrder = order
        return order
    }

    private func alignShufflePlaybackPositionForSelectedTrack(_ index: Int) {
        guard shuffleEnabled else { return }

        ensureShufflePlaybackOrderAligned(anchoredAt: index)
        if let position = shufflePlaybackOrder.firstIndex(of: index) {
            shufflePlaybackPosition = position
            pendingRepeatShuffleOrder = nil
        } else {
            rebuildShufflePlaybackOrder(anchoredAt: index)
        }
    }

    private func anchorShufflePlaybackOrder(at index: Int) {
        guard shuffleEnabled else { return }
        rebuildShufflePlaybackOrder(anchoredAt: index)
    }

    private func commitShufflePlaybackAdvance(to index: Int) {
        guard shuffleEnabled else { return }
        guard index >= 0 && index < playlist.count else {
            clearShufflePlaybackState()
            return
        }

        ensureShufflePlaybackOrderAligned(anchoredAt: currentIndex)

        if shufflePlaybackPosition >= 0,
           shufflePlaybackPosition + 1 < shufflePlaybackOrder.count,
           shufflePlaybackOrder[shufflePlaybackPosition + 1] == index {
            shufflePlaybackPosition += 1
            pendingRepeatShuffleOrder = nil
            return
        }

        if let pendingRepeatShuffleOrder,
           isValidShuffleOrder(pendingRepeatShuffleOrder, count: playlist.count),
           pendingRepeatShuffleOrder.first == index {
            shufflePlaybackOrder = pendingRepeatShuffleOrder
            shufflePlaybackPosition = 0
            self.pendingRepeatShuffleOrder = nil
            return
        }

        if let position = shufflePlaybackOrder.firstIndex(of: index) {
            shufflePlaybackPosition = position
            pendingRepeatShuffleOrder = nil
        } else {
            rebuildShufflePlaybackOrder(anchoredAt: index)
        }
    }

    private func nextShuffleIndexForPlaybackAdvance() -> Int? {
        guard !playlist.isEmpty else { return nil }

        ensureShufflePlaybackOrderAligned(anchoredAt: currentIndex)

        if currentIndex < 0 || currentIndex >= playlist.count {
            if shufflePlaybackOrder.isEmpty {
                rebuildShufflePlaybackOrder(anchoredAt: nil)
            }
            guard let first = shufflePlaybackOrder.first else { return nil }
            shufflePlaybackPosition = 0
            pendingRepeatShuffleOrder = nil
            return first
        }

        if shufflePlaybackPosition >= 0,
           shufflePlaybackPosition + 1 < shufflePlaybackOrder.count {
            shufflePlaybackPosition += 1
            pendingRepeatShuffleOrder = nil
            return shufflePlaybackOrder[shufflePlaybackPosition]
        }

        guard repeatEnabled else { return nil }

        let nextOrder = preparedRepeatShuffleOrder()
        guard let first = nextOrder.first else { return nil }
        shufflePlaybackOrder = nextOrder
        shufflePlaybackPosition = 0
        pendingRepeatShuffleOrder = nil
        return first
    }

    private func nextShuffleIndexForManualNavigation() -> Int? {
        guard !playlist.isEmpty else { return nil }

        ensureShufflePlaybackOrderAligned(anchoredAt: currentIndex)

        if currentIndex < 0 || currentIndex >= playlist.count {
            if shufflePlaybackOrder.isEmpty {
                rebuildShufflePlaybackOrder(anchoredAt: nil)
            }
            guard let first = shufflePlaybackOrder.first else { return nil }
            shufflePlaybackPosition = 0
            pendingRepeatShuffleOrder = nil
            return first
        }

        if shufflePlaybackPosition >= 0,
           shufflePlaybackPosition + 1 < shufflePlaybackOrder.count {
            shufflePlaybackPosition += 1
            pendingRepeatShuffleOrder = nil
            return shufflePlaybackOrder[shufflePlaybackPosition]
        }

        let nextOrder = makeRepeatedShuffleOrder(avoidingImmediateRepeatOf: currentIndex)
        guard let first = nextOrder.first else { return nil }
        shufflePlaybackOrder = nextOrder
        shufflePlaybackPosition = 0
        pendingRepeatShuffleOrder = nil
        return first
    }

    private func previousShuffleIndexForManualNavigation() -> Int? {
        guard !playlist.isEmpty else { return nil }

        ensureShufflePlaybackOrderAligned(anchoredAt: currentIndex)

        if currentIndex < 0 || currentIndex >= playlist.count {
            if shufflePlaybackOrder.isEmpty {
                rebuildShufflePlaybackOrder(anchoredAt: nil)
            }
            guard !shufflePlaybackOrder.isEmpty else { return nil }
            shufflePlaybackPosition = shufflePlaybackOrder.count - 1
            pendingRepeatShuffleOrder = nil
            return shufflePlaybackOrder[shufflePlaybackPosition]
        }

        if shufflePlaybackPosition > 0 {
            shufflePlaybackPosition -= 1
            pendingRepeatShuffleOrder = nil
            return shufflePlaybackOrder[shufflePlaybackPosition]
        }

        guard !shufflePlaybackOrder.isEmpty else { return nil }
        shufflePlaybackPosition = shufflePlaybackOrder.count - 1
        pendingRepeatShuffleOrder = nil
        return shufflePlaybackOrder[shufflePlaybackPosition]
    }

    private func peekNextShuffleIndexForPlayback() -> Int? {
        guard !playlist.isEmpty else { return nil }

        ensureShufflePlaybackOrderAligned(anchoredAt: currentIndex)

        if currentIndex < 0 || currentIndex >= playlist.count {
            return shufflePlaybackOrder.first
        }

        if shufflePlaybackPosition >= 0,
           shufflePlaybackPosition + 1 < shufflePlaybackOrder.count {
            return shufflePlaybackOrder[shufflePlaybackPosition + 1]
        }

        guard repeatEnabled else { return nil }
        return preparedRepeatShuffleOrder().first
    }
    
    @objc private func handleSpectrumSettingsChanged() {
        if let saved = UserDefaults.standard.string(forKey: UserDefaults.Keys.spectrumNormalizationMode),
           let mode = SpectrumNormalizationMode(rawValue: saved) {
            spectrumNormalizationMode = mode
        }
    }

    @objc private func handleSystemWillSleep() {
        guard state == .playing,
              !isStreamingPlayback,
              !isCastingActive,
              let startDate = playbackStartDate else {
            return
        }

        let clockState = Self.freezeLocalPlaybackClockForSleep(
            currentTime: _currentTime,
            playbackStartDate: startDate,
            now: Date()
        )
        _currentTime = clockState.currentTime
        lastReportedTime = clockState.currentTime
        playbackStartDate = clockState.playbackStartDate
        suspendedLocalPlaybackClockForSleep = clockState.suspendedForSleep
        stopTimeUpdates()
    }

    @objc private func handleSystemDidWake() {
        guard suspendedLocalPlaybackClockForSleep else { return }

        let clockState = Self.resumeLocalPlaybackClockAfterSleep(
            currentTime: _currentTime,
            suspendedForSleep: suspendedLocalPlaybackClockForSleep,
            state: state,
            now: Date()
        )
        let shouldRestartTimeUpdates = state == .playing && clockState.playbackStartDate != nil
        _currentTime = clockState.currentTime
        lastReportedTime = clockState.currentTime
        playbackStartDate = clockState.playbackStartDate
        suspendedLocalPlaybackClockForSleep = clockState.suspendedForSleep

        if shouldRestartTimeUpdates {
            startTimeUpdates()
        }
    }

    @objc private func handleModernUIChanged() {
        isModernUIEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.modernUIEnabled)
    }

    // MARK: - Setup
    
    private func setupAudioEngine() {
        // Attach nodes
        engine.attach(playerNode)
        engine.attach(crossfadePlayerNode)  // For Sweet Fades crossfade
        engine.attach(eqNode)
        engine.attach(mixerNode)  // Class property for graph rebuilding
        
        // Get the standard format from the mixer
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        
        // Signal flow: playerNode ─┐
        //                          ├─► mixerNode ─► eqNode ─► output
        //  crossfadePlayerNode ────┘
        
        // Connect both players to the mixer
        engine.connect(playerNode, to: mixerNode, format: mixerFormat)
        engine.connect(crossfadePlayerNode, to: mixerNode, format: mixerFormat)
        
        // Connect mixer to EQ to output
        engine.connect(mixerNode, to: eqNode, format: mixerFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: mixerFormat)
        
        // Player nodes stay at unity gain (1.0) - volume applied at mainMixerNode
        // This ensures the spectrum tap captures volume-independent audio
        playerNode.volume = 1.0
        crossfadePlayerNode.volume = 0  // Still starts silent for crossfade
        
        // Apply initial volume to mainMixerNode (after EQ/limiter, before output)
        engine.mainMixerNode.outputVolume = volume
        
        // EQ is disabled (bypassed) by default - user must enable it
        eqNode.bypass = true
        
        // Load audio preferences
        loadAudioPreferences()
        
        // Prepare engine
        engine.prepare()
    }
    
    /// Load audio quality preferences from UserDefaults
    private func loadAudioPreferences() {
        gaplessPlaybackEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.gaplessPlaybackEnabled)
        volumeNormalizationEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.volumeNormalizationEnabled)
        sweetFadeEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.sweetFadeEnabled)
        // Load sweet fade duration with default of 5.0 seconds
        let savedDuration = UserDefaults.standard.double(forKey: UserDefaults.Keys.sweetFadeDuration)
        sweetFadeDuration = savedDuration > 0 ? savedDuration : 5.0
    }
    
    // MARK: - Audio Configuration Change Handling
    
    /// Handle audio configuration changes (device format changes)
    /// Called when AVAudioEngine detects a configuration change (e.g., device sample rate changed)
    @objc private func handleAudioConfigChange(_ notification: Notification) {
        Log.audio.infoPublic("AudioEngine: Configuration change detected, rebuilding audio graph")
        // CRITICAL: Must use async to avoid deadlock
        // The notification fires on an internal dispatch queue
        DispatchQueue.main.async { [weak self] in
            self?.rebuildAudioGraph()
        }
    }
    
    /// Rebuild the audio graph with the new output format
    /// Called after a device change that affects the audio format
    private func rebuildAudioGraph() {
        let wasPlaying = state == .playing
        let currentPosition = currentTime
        
        // Get new format from the updated output device
        let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        Log.audio.infoPublic("AudioEngine: Rebuilding graph with format: \(mixerFormat.description)")
        
        // Reconnect all nodes with new format
        engine.connect(playerNode, to: mixerNode, format: mixerFormat)
        engine.connect(crossfadePlayerNode, to: mixerNode, format: mixerFormat)
        engine.connect(mixerNode, to: eqNode, format: mixerFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: mixerFormat)

        // Re-schedule current audio if we were playing local files
        if wasPlaying && !isStreamingPlayback, let file = audioFile {
            do {
                try engine.start()
                
                // Schedule from current position
                let sampleRate = file.processingFormat.sampleRate
                let framePosition = AVAudioFramePosition(currentPosition * sampleRate)
                let remainingFrames = file.length - framePosition
                
                guard remainingFrames > 0 else {
                    Log.audio.infoPublic("AudioEngine: No remaining frames after config change")
                    return
                }
                
                // Increment generation to invalidate old completion handlers
                playbackGeneration += 1
                let currentGeneration = playbackGeneration
                
                playerNode.scheduleSegment(file,
                    startingFrame: framePosition,
                    frameCount: AVAudioFrameCount(remainingFrames),
                    at: nil,
                    completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.handlePlaybackComplete(generation: currentGeneration)
                        }
                    }
                playerNode.play()
                playbackStartDate = Date()
                suspendedLocalPlaybackClockForSleep = false
                _currentTime = currentPosition
                state = .playing
                
                Log.audio.infoPublic("AudioEngine: Resumed playback from \(String(format: "%.2f", currentPosition))s after config change")
            } catch {
                Log.audio.errorPublic("AudioEngine: Failed to restart after config change: \(error.localizedDescription)")
            }
        } else if wasPlaying && isStreamingPlayback {
            // For streaming, just restart the engine - StreamingAudioPlayer manages its own state
            do {
                try engine.start()
                Log.audio.infoPublic("AudioEngine: Restarted engine for streaming after config change")
            } catch {
                Log.audio.errorPublic("AudioEngine: Failed to restart engine for streaming: \(error.localizedDescription)")
            }
        }
    }
    
    /// Restore saved output device preference
    private func restoreSavedOutputDevice() {
        guard let savedDeviceUID = UserDefaults.standard.string(forKey: UserDefaults.Keys.selectedOutputDeviceUID) else {
            return
        }
        
        // Find device by UID
        let devices = AudioOutputManager.shared.outputDevices
        guard let device = devices.first(where: { $0.uid == savedDeviceUID }) else {
            Log.audio.infoPublic("AudioEngine: Saved output device not found")
            return
        }
        
        Log.audio.infoPublic("AudioEngine: Restoring saved output device: \(device.name)")
        setOutputDevice(device.id)
    }
    
    private func setupEqualizer() {
        // Configure each EQ band for graphic EQ behavior
        // Use low shelf for bass, high shelf for treble, and parametric for mids
        for (index, frequency) in activeEQConfiguration.frequencies.enumerated() {
            let band = eqNode.bands[index]
            
            // First band: low shelf for bass control
            // Last band: high shelf for treble control
            // Middle bands: parametric for 1/3-octave shaping
            if index == 0 {
                band.filterType = .lowShelf
            } else if index == activeEQConfiguration.bandCount - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
            
            band.frequency = frequency
            band.bandwidth = band.filterType == .parametric ? activeEQConfiguration.parametricBandwidth : 1.0
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
        // Tap on mixerNode (not playerNode) to capture BOTH players during crossfade
        mixerNode.removeTap(onBus: 0)
        
        // Install new tap on mixerNode - captures combined audio from both player nodes
        // This ensures visualization works during crossfade and regardless of which player is active
        mixerNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: nil) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard spectrumNeeded || waveformNeeded else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)
        let bufferSampleRate = buffer.format.sampleRate

        if waveformNeeded {
            enqueueWaveformSamplesAndPost(
                channelData: channelData,
                channelCount: channelCount,
                frameCount: frameCount,
                sampleRate: bufferSampleRate
            )
        }

        guard spectrumNeeded, frameCount >= fftSize, let fftSetup = fftSetup else { return }
        
        // Throttle updates to 60Hz max to prevent memory buildup
        let now = CFAbsoluteTimeGetCurrent()
        let shouldUpdate = now - lastSpectrumUpdateTime >= spectrumUpdateInterval
        guard shouldUpdate else { return }
        lastSpectrumUpdateTime = now
        
        // Get audio samples (mono mix if stereo) - use pre-allocated buffer
        if channelCount == 1 {
            memcpy(&fftSamples, channelData[0], fftSize * MemoryLayout<Float>.size)
        } else {
            // Mix stereo to mono
            for i in 0..<fftSize {
                fftSamples[i] = (channelData[0][i] + channelData[1][i]) / 2.0
            }
        }
        
        // Feed BPM detector with raw mono samples (before windowing) — modern UI only
        if isModernUIEnabled {
            fftSamples.withUnsafeBufferPointer { ptr in
                if let base = ptr.baseAddress {
                    bpmDetector.process(samples: base, count: fftSize, sampleRate: buffer.format.sampleRate)
                }
            }
        }
        
        // Store raw PCM data for waveform visualization (before windowing)
        // Downsample to 512 samples for efficient storage and lowest latency
        let pcmSize = 512
        let pcmStride = fftSize / pcmSize
        for i in 0..<pcmSize {
            fftPcmSamples[i] = fftSamples[i * pcmStride]
        }
        
        // Post notification for low-latency visualization (direct from audio tap)
        // Copy to avoid data races since we reuse the buffer
        let pcmCopy = Array(fftPcmSamples)
        pcmUserInfo["pcm"] = pcmCopy
        pcmUserInfo["sampleRate"] = bufferSampleRate
        NotificationCenter.default.post(
            name: .audioPCMDataUpdated,
            object: self,
            userInfo: pcmUserInfo
        )

        // Also store in property for legacy access - coalesce dispatches
        if !pendingPcmUpdate {
            pendingPcmUpdate = true
            let pcmForMain = pcmCopy
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pendingPcmUpdate = false
                self.pcmSampleRate = bufferSampleRate
                self.pcmData = pcmForMain
            }
        }
        
        // Apply Hann window - use pre-allocated buffers
        vDSP_hann_window(&fftWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(fftSamples, 1, fftWindow, 1, &fftSamples, 1, vDSP_Length(fftSize))
        
        // Perform FFT - use pre-allocated buffers
        // Zero out imagIn (realIn gets samples)
        memset(&fftImagIn, 0, fftSize * MemoryLayout<Float>.size)
        memcpy(&fftRealIn, &fftSamples, fftSize * MemoryLayout<Float>.size)
        
        vDSP_DFT_Execute(fftSetup, &fftRealIn, &fftImagIn, &fftRealOut, &fftImagOut)
        
        // Calculate magnitudes - use pre-allocated buffer
        for i in 0..<fftSize / 2 {
            fftMagnitudes[i] = sqrt(fftRealOut[i] * fftRealOut[i] + fftImagOut[i] * fftImagOut[i])
        }
        
        // Convert to dB and normalize - use pre-allocated buffer
        var one: Float = 1.0
        vDSP_vdbcon(fftMagnitudes, 1, &one, &fftLogMagnitudes, 1, vDSP_Length(fftSize / 2), 0)
        
        // Map to 75 bands (classic skin-style) using logarithmic frequency mapping
        // Zero out pre-allocated buffer
        let bandCount = 75
        memset(&fftNewSpectrum, 0, bandCount * MemoryLayout<Float>.size)
        
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
                
                // Peak aggregation per band (BeSpec approach).
                // RMS averaging dilutes treble: a high-freq band with 80 mostly-empty bins
                // averages to near zero. Peak picks the loudest component, giving treble
                // equal standing with bass.
                var peakMag: Float = 0
                for bin in startBin...endBin {
                    if fftMagnitudes[bin] > peakMag { peakMag = fftMagnitudes[bin] }
                }

                // BeSpec calibration: HANN_CORRECTION (2.0) × energy-preserving FFT scale (1/√N).
                let bespecFactor: Float = 2.0 / sqrt(Float(fftSize))
                let calibratedMag = peakMag * bespecFactor
                let dB = 20.0 * log10(max(calibratedMag, 1e-10))

                let ceiling: Float = 0.0
                let floor: Float = -20.0
                let normalized = (dB - floor) / (ceiling - floor)
                
                fftNewSpectrum[band] = max(0, min(1.0, normalized))
            } else {
                // Adaptive/Dynamic modes - interpolate at center frequency
                let exactBin = centerFreq / binWidth
                let lowerBin = max(0, Int(exactBin))
                let upperBin = min(lowerBin + 1, fftSize / 2 - 1)
                let fraction = exactBin - Float(lowerBin)
                let interpMag = fftMagnitudes[lowerBin] * (1.0 - fraction) + fftMagnitudes[upperBin] * fraction
                
                // Apply bandwidth scaling and frequency weighting
                let bandMagnitude = interpMag * spectrumBandwidthScales[band]
                fftNewSpectrum[band] = bandMagnitude * spectrumFrequencyWeights[band]
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
                globalPeak = max(globalPeak, fftNewSpectrum[i])
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
                    let normalized = min(1.0, fftNewSpectrum[i] / referenceLevel)
                    fftNewSpectrum[i] = pow(normalized, 0.5)  // Square root curve for dynamics
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
                    regionPeak = max(regionPeak, fftNewSpectrum[i])
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
                    let normalized = min(1.0, fftNewSpectrum[i] / referenceLevel)
                    fftNewSpectrum[i] = pow(normalized, 0.5)  // Square root curve
                }
            }
        }
        
        // Smooth with previous values (decay) and update on main thread
        // Copy spectrum data to avoid data races since we reuse the buffer
        let spectrumCopy = Array(fftNewSpectrum)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for i in 0..<bandCount {
                // Fast attack, smooth decay for all modes
                if spectrumCopy[i] > self.spectrumData[i] {
                    self.spectrumData[i] = spectrumCopy[i]
                } else {
                    self.spectrumData[i] = self.spectrumData[i] * 0.90 + spectrumCopy[i] * 0.10
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

    private func enqueueWaveformSamplesAndPost(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard channelCount > 0 else { return }
        for i in 0..<frameCount {
            let left = channelData[0][i]
            let right = channelCount > 1 ? channelData[1][i] : left
            appendWaveformSample(left: left, right: right)
        }
        postAvailableWaveformChunks(sampleRate: sampleRate)
    }

    private func appendWaveformSample(left: Float, right: Float) {
        if waveformRingCount == waveformLeftRing.count {
            waveformRingReadIndex = (waveformRingReadIndex + 1) % waveformLeftRing.count
            waveformRingCount -= 1
        }

        waveformLeftRing[waveformRingWriteIndex] = left
        waveformRightRing[waveformRingWriteIndex] = right
        waveformRingWriteIndex = (waveformRingWriteIndex + 1) % waveformLeftRing.count
        waveformRingCount += 1
    }

    private func postAvailableWaveformChunks(sampleRate: Double) {
        let chunkSize = waveformLeftU8.count
        while waveformRingCount >= chunkSize {
            var index = waveformRingReadIndex
            for i in 0..<chunkSize {
                let leftInt = Int((waveformLeftRing[index] * 127.0) + 128.0)
                let rightInt = Int((waveformRightRing[index] * 127.0) + 128.0)
                waveformLeftU8[i] = UInt8(clamping: leftInt)
                waveformRightU8[i] = UInt8(clamping: rightInt)
                index += 1
                if index == waveformLeftRing.count {
                    index = 0
                }
            }

            waveformRingReadIndex = index
            waveformRingCount -= chunkSize

            waveformUserInfo["left"] = waveformLeftU8
            waveformUserInfo["right"] = waveformRightU8
            waveformUserInfo["sampleRate"] = sampleRate
            NotificationCenter.default.post(
                name: .audioWaveform576DataUpdated,
                object: self,
                userInfo: waveformUserInfo
            )
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        // If video casting is active, forward to video player
        if isVideoCastingActive {
            guard !AudioEngine.isHeadless else { return }
            WindowManager.shared.toggleVideoCastPlayPause()
            return
        }

        // If local video playback is active, don't start audio playback
        // (video has its own playback controls via the video player window)
        if !AudioEngine.isHeadless && WindowManager.shared.isVideoActivePlayback {
            Log.audio.infoPublic("play(): Local video is active - ignoring audio play request")
            return
        }
        
        // If audio casting is active, forward command to CastManager
        if isCastingActive {
            Task {
                try? await CastManager.shared.resume()
            }
            return
        }

        if state != .playing {
            staleStreamingRefreshRetriedServiceIdentity = nil
        }
        
        guard currentTrack != nil || !playlist.isEmpty else { return }
        
        if currentTrack == nil && !playlist.isEmpty {
            if shuffleEnabled {
                currentIndex = startShufflePlaybackCycle() ?? 0
            } else {
                currentIndex = 0
                alignShufflePlaybackPositionForSelectedTrack(currentIndex)
            }
            loadTrack(at: currentIndex)
            if currentTrack == nil,
               currentIndex >= 0,
               currentIndex < playlist.count,
               playlist[currentIndex].isStreamingPlaceholder {
                currentTrack = playlist[currentIndex]
                resolvePlaceholderTrackAndOptionallyPlay(at: currentIndex, autoPlayOnSuccess: true)
                return
            }
        }

        if let track = currentTrack {
            if track.isStreamingPlaceholder,
               currentIndex >= 0 && currentIndex < playlist.count {
                resolvePlaceholderTrackAndOptionallyPlay(at: currentIndex, autoPlayOnSuccess: true)
                return
            }

            let trackIsStreaming = track.url.scheme == "http"
                || track.url.scheme == "https"
                || track.isStreamingPlaceholder
            let hasStreamingPlayer = streamingPlayer != nil
            let hasLocalAudioFile = audioFile != nil
            let needsPipelineReload = Self.shouldReloadPlaybackPipelineForCurrentTrack(
                trackURL: track.url,
                isStreamingPlayback: isStreamingPlayback,
                hasStreamingPlayer: hasStreamingPlayer,
                hasLocalAudioFile: hasLocalAudioFile,
                isStreamingPlaceholder: track.isStreamingPlaceholder
            )

            if needsPipelineReload {
                // Resolve stale playback pipeline state before resuming.
                // This prevents local/streaming mismatches after cast handoffs.
                let reloadIndex: Int
                if currentIndex >= 0 && currentIndex < playlist.count && playlist[currentIndex].id == track.id {
                    reloadIndex = currentIndex
                } else if let foundIndex = playlist.firstIndex(where: { $0.id == track.id }) {
                    currentIndex = foundIndex
                    reloadIndex = foundIndex
                } else {
                    Log.audio.errorPublic("play(): unable to reload current track '\(track.title)' - not found in playlist")
                    return
                }

                NSLog("play(): reloading track due to pipeline mismatch (trackStreaming=%d, isStreamingPlayback=%d, hasStreamingPlayer=%d, hasAudioFile=%d)",
                      trackIsStreaming ? 1 : 0,
                      isStreamingPlayback ? 1 : 0,
                      hasStreamingPlayer ? 1 : 0,
                      hasLocalAudioFile ? 1 : 0)
                loadTrack(at: reloadIndex)

                // Streaming load starts playback internally.
                if trackIsStreaming { return }
            }
        }
        
        if isStreamingPlayback {
            // Streaming playback via AudioStreaming (with EQ support)
            Log.audio.infoPublic("play(): Starting streaming playback via AudioStreaming (state: \(String(describing: streamingPlayer?.state ?? .stopped)))")
            
            // If streaming player is stopped (not paused), we need to reload the URL
            // resume() only works on a paused player, not a stopped one
            if let playerState = streamingPlayer?.state, playerState == .stopped || playerState == .error {
                Log.audio.infoPublic("play(): Streaming player is stopped/error - reloading track")
                // Reload the current track to restart playback
                if currentIndex >= 0 && currentIndex < playlist.count {
                    loadTrack(at: currentIndex)
                    // play() will be called again after loadTrack completes and starts playing
                    return
                }
            }
            
            streamingPlayer?.resume()
            playbackStartDate = Date()
            suspendedLocalPlaybackClockForSleep = false
            state = .playing
            startTimeUpdates()
            
            // Report resume to Plex
            if let track = currentTrack {
                PlexPlaybackReporter.shared.trackDidResume(at: currentTime)
            }
            
            // Report resume to Subsonic
            SubsonicPlaybackReporter.shared.trackResumed()
            
            // Report resume to Jellyfin
            JellyfinPlaybackReporter.shared.trackResumed()

            // Report resume to Emby
            EmbyPlaybackReporter.shared.trackResumed()
        } else {
            // Local file playback via AVAudioEngine
            // Ensure we have a valid audio file loaded before attempting to play
            guard audioFile != nil else {
                Log.audio.errorPublic("play(): No audio file loaded - cannot start local playback")
                return
            }
            
            do {
                if !engine.isRunning {
                    try engine.start()
                }
                
                // Reinstall spectrum tap if it was removed during pause
                // The tap is removed on pause to save CPU from FFT processing
                installSpectrumTap(format: nil)
                
                playerNode.play()
                playbackStartDate = Date()  // Start tracking time
                suspendedLocalPlaybackClockForSleep = false
                state = .playing
                startTimeUpdates()
                
                // Report resume to Plex (local files won't have plexRatingKey so this is a no-op)
                if currentTrack != nil {
                    PlexPlaybackReporter.shared.trackDidResume(at: currentTime)
                }
                
                // Report resume to Subsonic
                SubsonicPlaybackReporter.shared.trackResumed()

                // Report resume to Jellyfin
                JellyfinPlaybackReporter.shared.trackResumed()

                // Report resume to Emby
                EmbyPlaybackReporter.shared.trackResumed()
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }
    }
    
    func pause() {
        Log.audio.infoPublic("AudioEngine.pause() called - isVideoCastingActive=\(isVideoCastingActive ? 1 : 0), isCastingActive=\(isCastingActive ? 1 : 0)")
        
        // If video casting is active, forward to video player
        if isVideoCastingActive {
            guard !AudioEngine.isHeadless else { return }
            WindowManager.shared.toggleVideoCastPlayPause()
            return
        }

        // If audio casting is active, forward command to CastManager
        if isCastingActive {
            Log.audio.infoPublic("AudioEngine.pause() - forwarding to CastManager")
            Task {
                do {
                    try await CastManager.shared.pause()
                    Log.audio.infoPublic("AudioEngine.pause() - CastManager.pause() completed")
                } catch {
                    Log.audio.errorPublic("AudioEngine.pause() - CastManager.pause() failed: \(error.localizedDescription)")
                }
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
        suspendedLocalPlaybackClockForSleep = false
        
        if isStreamingPlayback {
            streamingPlayer?.pause()
        } else {
            playerNode.pause()
            // Remove spectrum tap when paused to save CPU (FFT is expensive)
            // Tap will be reinstalled when playback resumes
            mixerNode.removeTap(onBus: 0)  // Changed from playerNode - tap is now on mixerNode
        }
        state = .paused
        stopTimeUpdates()
        
        // Report pause to Plex
        PlexPlaybackReporter.shared.trackDidPause(at: pausePosition)
        
        // Report pause to Subsonic
        SubsonicPlaybackReporter.shared.trackPaused()
        
        // Report pause to Jellyfin
        JellyfinPlaybackReporter.shared.trackPaused()

        // Report pause to Emby
        EmbyPlaybackReporter.shared.trackPaused()
    }

    func stop() {
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
        // If playing radio, notify RadioManager of manual stop (prevents auto-reconnect)
        if RadioManager.shared.isActive {
            RadioManager.shared.stop()
        }
        
        // If casting is active, handle stop based on device type
        if isCastingActive {
            Task {
                await CastManager.shared.handleStopForActiveDevice()
            }
        }
        
        stopLocalOnly()
    }
    
    /// Stop local playback without affecting cast session
    /// Used when loading new tracks while casting - we want to keep the cast session active
    private func stopLocalOnly() {
        // Invalidate any in-flight deferred local loads so they cannot restart playback after stop.
        deferredLocalTrackLoadToken &+= 1

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
        resetLocalCrossfadeStateForDirectPlayback()
        
        playbackStartDate = nil
        suspendedLocalPlaybackClockForSleep = false
        _currentTime = 0  // Reset to beginning
        lastReportedTime = 0
        state = .stopped
        stopTimeUpdates()
        
        // Report stop to Plex (not finished - user manually stopped)
        PlexPlaybackReporter.shared.trackDidStop(at: stopPosition, finished: false)
        
        // Report stop to Subsonic
        SubsonicPlaybackReporter.shared.trackStopped()
        
        // Report stop to Jellyfin
        JellyfinPlaybackReporter.shared.trackStopped()

        // Report stop to Emby
        EmbyPlaybackReporter.shared.trackStopped()

        // Clear spectrum analyzer
        clearSpectrum()
        
        // Notify delegate of reset time
        delegate?.audioEngineDidUpdateTime(current: 0, duration: duration)
        
        // Reset to beginning (local files only)
        if !isStreamingPlayback, let file = audioFile {
            playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handlePlaybackComplete(generation: currentGeneration)
                }
            }
        }
    }
    
    /// Stop local playback when casting starts
    /// Fully stops streaming connections (important for Subsonic/Navidrome concurrent stream limits)
    /// but preserves track metadata and position for casting to use
    func stopLocalForCasting() {
        Log.audio.infoPublic("AudioEngine: stopLocalForCasting - releasing streaming connection for cast")
        
        // Save current position before stopping
        let currentPosition = currentTime
        if let startDate = playbackStartDate {
            _currentTime += Date().timeIntervalSince(startDate)
        }
        playbackStartDate = nil
        suspendedLocalPlaybackClockForSleep = false

        // Invalidate pending completion handlers so stale callbacks can't restart local flow
        playbackGeneration += 1

        // Force-stop any in-progress crossfade before casting handoff.
        // This avoids mixed local+cast playback when crossfade players are active.
        resetLocalCrossfadeStateForDirectPlayback()

        // Fully stop ALL local playback paths (primary + crossfade, local + streaming).
        // This ensures no local audio leaks while cast playback is active.
        //
        // Set flag before stopping the streaming player. AudioStreaming fires an EOF callback
        // when stop() is called (even for intentional stops), which would trigger
        // RadioManager.streamDidDisconnect → scheduleReconnect. That reconnect can fire
        // while the Sonos session is still connecting (isCastingActive is still false),
        // causing loadTracks to restart local radio while Sonos also plays the stream.
        isLoadingNewStreamingTrack = true
        streamingPlayer?.stop()
        playerNode.stop()

        // Clear the flag after a brief delay (enough for the EOF callback to have fired)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isLoadingNewStreamingTrack = false
        }
        
        state = .stopped
        stopTimeUpdates()
        
        // Don't report to Plex/Subsonic as "stopped" - casting is taking over playback
        // Don't clear spectrum or reset track metadata - casting needs it
        
        Log.audio.infoPublic("AudioEngine: Local playback stopped for casting, position preserved: \(String(format: "%.1f", currentPosition))s")
    }
    
    func previous() {
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
        guard !playlist.isEmpty else { return }
        
        // When casting local files, block rapid clicks - only accept if not already casting
        if isCastingActive && CastManager.shared.isLocalFileCastInProgress() {
            Log.audio.infoPublic("AudioEngine: previous() blocked - local file cast in progress")
            return
        }
        
        // Capture previous index before changing (for rollback on cast failure)
        let previousIndex = currentIndex
        let previousTrack = currentTrack
        let shuffleSnapshot = captureShufflePlaybackState()
        
        if shuffleEnabled {
            guard let previousShuffleIndex = previousShuffleIndexForManualNavigation() else { return }
            currentIndex = previousShuffleIndex
        } else {
            currentIndex = (currentIndex - 1 + playlist.count) % playlist.count
        }
        
        // When casting, cast the new track instead of playing locally
        if isCastingActive {
            let track = playlist[currentIndex]
            let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
            
            // For local files, defer UI update until cast completes (prevents UI jumping during rapid clicks)
            // For streaming, update immediately since there's no async delay
            if !isLocalFile {
                currentTrack = track
            }
            
            Task {
                do {
                    try await CastManager.shared.castNewTrack(track)
                    // For local files, update UI after successful cast
                    if isLocalFile {
                        await MainActor.run {
                            self.currentTrack = track
                        }
                    }
                } catch {
                    Log.audio.errorPublic("AudioEngine: previous() cast failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.currentIndex = previousIndex
                        self.currentTrack = previousTrack
                        self.restoreShufflePlaybackState(shuffleSnapshot)
                    }
                }
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
        
        // When casting local files, block rapid clicks - only accept if not already casting
        if isCastingActive && CastManager.shared.isLocalFileCastInProgress() {
            Log.audio.infoPublic("AudioEngine: next() blocked - local file cast in progress")
            return
        }
        
        // Capture previous index before changing (for rollback on cast failure)
        let previousIndex = currentIndex
        let previousTrack = currentTrack
        let shuffleSnapshot = captureShufflePlaybackState()
        
        if shuffleEnabled {
            guard let nextShuffleIndex = nextShuffleIndexForManualNavigation() else { return }
            currentIndex = nextShuffleIndex
        } else {
            currentIndex = (currentIndex + 1) % playlist.count
        }
        
        // When casting, cast the new track instead of playing locally
        if isCastingActive {
            let track = playlist[currentIndex]
            let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
            
            // For local files, defer UI update until cast completes (prevents UI jumping during rapid clicks)
            // For streaming, update immediately since there's no async delay
            if !isLocalFile {
                currentTrack = track
            }
            
            Task {
                do {
                    try await CastManager.shared.castNewTrack(track)
                    // For local files, update UI after successful cast
                    if isLocalFile {
                        await MainActor.run {
                            self.currentTrack = track
                        }
                    }
                } catch {
                    Log.audio.errorPublic("AudioEngine: next() cast failed: \(error.localizedDescription)")
                    await MainActor.run {
                        self.currentIndex = previousIndex
                        self.currentTrack = previousTrack
                        self.restoreShufflePlaybackState(shuffleSnapshot)
                    }
                }
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
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
        guard !playlist.isEmpty else { return }
        
        // When casting local files, block rapid clicks - only accept if not already casting
        if isCastingActive && CastManager.shared.isLocalFileCastInProgress() {
            Log.audio.infoPublic("AudioEngine: skipTracks() blocked - local file cast in progress")
            return
        }
        
        if shuffleEnabled {
            // In shuffle mode, skip one at a time (next/previous handle casting)
            for _ in 0..<abs(count) {
                if count > 0 { next() } else { previous() }
            }
            return
        }
        
        // Capture previous index before changing (for rollback on cast failure)
        let previousIndex = currentIndex
        
        // Calculate new index with wraparound
        var newIndex = currentIndex + count
        while newIndex < 0 { newIndex += playlist.count }
        newIndex = newIndex % playlist.count
        
        currentIndex = newIndex
        
        // When casting, cast the new track instead of playing locally
        if isCastingActive {
            let track = playlist[currentIndex]
            let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
            
            // For local files, defer UI update until cast completes (prevents UI jumping during rapid clicks)
            // For streaming, update immediately since there's no async delay
            if !isLocalFile {
                currentTrack = track
            }
            
            Task {
                do {
                    try await CastManager.shared.castNewTrack(track)
                    // For local files, update UI after successful cast
                    if isLocalFile {
                        await MainActor.run {
                            self.currentTrack = track
                        }
                    }
                } catch {
                    Log.audio.errorPublic("AudioEngine: skipTracks() cast failed: \(error.localizedDescription)")
                    // Restore index on failure to keep playlist navigation consistent
                    if isLocalFile {
                        await MainActor.run {
                            self.currentIndex = previousIndex
                        }
                    }
                }
            }
            return
        }
        
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
            Log.audio.errorPublic("AudioEngine: Cannot seek - duration is 0 or unknown")
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
            delegate?.audioEngineDidUpdateTime(current: seekTime, duration: currentDuration)

            // If already seeking, just update the target and return
            // The debounced work item will use the latest value
            if isSeekingStreaming {
                Log.audio.infoPublic("AudioEngine: Seek debounced - already seeking, will seek to \(String(format: "%.2f", seekTime))")
                // Schedule the actual seek after a short delay
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    self.isSeekingStreaming = true
                    Log.audio.infoPublic("AudioEngine: Executing debounced seek to \(String(format: "%.2f", seekTime))")
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
            Log.audio.infoPublic("AudioEngine: Seeking streaming to \(String(format: "%.2f", seekTime))")
            streamingPlayer?.seek(to: seekTime)
            
            // Reset seeking flag after a delay to allow player to stabilize
            scheduleSeekingReset()
        } else {
            // Local file playback - seek via AVAudioEngine
            guard let file = audioFile else { return }
            
            let wasPlaying = state == .playing
            
            // Ensure crossfade player is stopped and reset to playerNode as primary
            // (after a completed crossfade, crossfadePlayerNode may be the active player)
            if crossfadePlayerIsActive {
                crossfadePlayerNode.stop()
                crossfadePlayerNode.volume = 0
                crossfadePlayerIsActive = false
            }
            
            _currentTime = seekTime
            lastReportedTime = seekTime  // Keep in sync
            playbackStartDate = nil  // Will be set when play resumes
            suspendedLocalPlaybackClockForSleep = false
            
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
                                       frameCount: AVAudioFrameCount(remainingFrames), at: nil,
                                       completionCallbackType: .dataPlayedBack) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.handlePlaybackComplete(generation: currentGeneration)
                }
            }
            
            // Resume if was playing
            if wasPlaying {
                playbackStartDate = Date()  // Start tracking from seek position
                suspendedLocalPlaybackClockForSleep = false
                playerNode.play()
                startTimeUpdates()  // Ensure timer is running for UI updates
            } else {
                // Notify delegate of new position so UI updates while paused
                // (e.g. after seek-on-restore: playTrack→pause→seek, timer is stopped so no periodic update fires)
                delegate?.audioEngineDidUpdateTime(current: seekTime, duration: currentDuration)
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
    /// Whether we've received the first status update from Chromecast (prevents UI flash before sync)
    private var castHasReceivedStatus: Bool = false
    
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
    /// Note: Prefer initializeCastPlayback() for new casts to avoid flash on slow networks
    /// Scan forward from currentIndex for the first Sonos-compatible track.
    /// Updates currentIndex and returns the track, or nil if none found.
    func advanceToFirstSonosCompatibleTrack() -> Track? {
        var idx = currentIndex + 1
        while idx < playlist.count {
            let candidate = playlist[idx]
            if CastManager.isSonosCompatible(candidate, allowUnknownSampleRate: true) {
                currentIndex = idx
                currentTrack = candidate
                return candidate
            }
            NSLog("AudioEngine: Skipping '%@' (%@) — not supported by Sonos",
                  candidate.title, candidate.url.pathExtension)
            idx += 1
        }
        return nil
    }

    func startCastPlayback(from position: TimeInterval = 0) {
        castStartPosition = position
        castPlaybackStartDate = Date()
        castHasReceivedStatus = true  // Immediate start means we skip waiting for status
        _currentTime = position
        lastReportedTime = position
        suspendedLocalPlaybackClockForSleep = false
        
        // Update playback state and start UI updates
        state = .playing
        startTimeUpdates()
        
        // Report cast playback start to Plex (for dashboard "Now Playing" and scrobbling)
        if let track = currentTrack {
            PlexPlaybackReporter.shared.trackDidStart(track, at: position)
        }
        
        // Notify delegate of track change
        delegate?.audioEngineDidChangeTrack(currentTrack)
        delegate?.audioEngineDidUpdateTime(current: position, duration: duration)
    }
    
    /// Initialize cast playback tracking without starting the timer
    /// Called when casting starts - actual playback timer begins when Chromecast reports PLAYING state
    /// This prevents clock sync issues when buffering (especially for 4K on slow networks)
    func initializeCastPlayback(from position: TimeInterval = 0) {
        castStartPosition = position
        // Don't set castPlaybackStartDate yet - wait for PLAYING status from Chromecast
        castPlaybackStartDate = nil
        // Reset status flag - UI won't update time until we receive first Chromecast status
        castHasReceivedStatus = false
        _currentTime = position
        lastReportedTime = position
        suspendedLocalPlaybackClockForSleep = false
        
        // Set state to playing so UI shows cast mode, but timer won't advance until we get PLAYING status
        state = .playing
        startTimeUpdates()
        
        // Report cast playback start to Plex (for dashboard "Now Playing" and scrobbling)
        if let track = currentTrack {
            PlexPlaybackReporter.shared.trackDidStart(track, at: position)
        }
        
        // Notify delegate of track change (but not time - wait for Chromecast status)
        delegate?.audioEngineDidChangeTrack(currentTrack)
    }
    
    /// Pause cast playback time tracking
    func pauseCastPlayback() {
        // Save current interpolated position
        if let startDate = castPlaybackStartDate {
            castStartPosition += Date().timeIntervalSince(startDate)
        }
        castPlaybackStartDate = nil
        
        // Report pause to Plex
        PlexPlaybackReporter.shared.trackDidPause(at: castStartPosition)
        
        // Update state
        state = .paused
    }
    
    /// Reset cast time to 0 but keep cast session active
    /// Used when user presses stop - allows playing another track without re-selecting device
    func resetCastTime() {
        // Report stop to Plex before resetting position
        PlexPlaybackReporter.shared.trackDidStop(at: castStartPosition, finished: false)
        
        castStartPosition = 0
        castPlaybackStartDate = nil
        // Keep castHasReceivedStatus true so UI updates work when playing again
        state = .stopped
    }
    
    /// Resume cast playback time tracking
    func resumeCastPlayback() {
        castPlaybackStartDate = Date()
        
        // Report resume to Plex
        PlexPlaybackReporter.shared.trackDidResume(at: castStartPosition)
        
        // Update state
        state = .playing
    }
    
    /// Update cast position from Chromecast status updates
    /// This syncs the local time tracking with the actual position from the cast device
    func updateCastPosition(currentTime: TimeInterval, isPlaying: Bool, isBuffering: Bool) {
        guard isCastingActive else { return }
        
        // Mark that we've received status from Chromecast (enables UI time updates)
        let isFirstStatus = !castHasReceivedStatus
        castHasReceivedStatus = true
        
        // Sync position from Chromecast
        castStartPosition = currentTime
        
        if isBuffering {
            // During buffering, pause interpolation to prevent drift
            // This is critical for 4K on slow networks where buffering can take a long time
            castPlaybackStartDate = nil
            // Keep state as .playing so UI shows cast mode, but timer won't advance
        } else if isPlaying {
            // Playing - start/restart interpolation from this position
            // This is when we actually start the timer (may be first time after buffering completes)
            castPlaybackStartDate = Date()
            state = .playing
        } else {
            // Paused - stop interpolation
            castPlaybackStartDate = nil
            state = .paused
        }
        
        // Update reported time for UI sync
        _currentTime = currentTime
        lastReportedTime = currentTime
        suspendedLocalPlaybackClockForSleep = false
        
        // On first status, immediately update delegate with correct position
        if isFirstStatus {
            delegate?.audioEngineDidUpdateTime(current: currentTime, duration: duration)
        }
    }
    
    /// Stop cast playback and resume local playback at current position
    /// - Parameter resumeLocally: If true, resume local playback from current cast position
    func stopCastPlayback(resumeLocally: Bool = false) {
        // Stop timer FIRST to prevent any flashing during state transition
        stopTimeUpdates()
        
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
                castHasReceivedStatus = false
                
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
        castHasReceivedStatus = false
        state = .stopped
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
        spectrumRegionPeaks = [0.0, 0.0, 0.0]  // Reset adaptive peaks for new track
        spectrumRegionReferenceLevels = [0.0, 0.0, 0.0]
        spectrumGlobalPeak = 0.0  // Reset global adaptive peak
        spectrumGlobalReferenceLevel = 0.0
        delegate?.audioEngineDidUpdateSpectrum(spectrumData)
        NotificationCenter.default.post(
            name: .audioSpectrumDataUpdated,
            object: self,
            userInfo: ["spectrum": spectrumData]
        )
    }
    
    private func startTimeUpdates() {
        // Invalidate any existing timer before creating a new one to prevent duplicate timers
        stopTimeUpdates()
        
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // When casting, skip time updates until we've received first status from Chromecast
            // This prevents showing stale/incorrect time before sync (flash issue on slow networks)
            if self.isCastingActive && !self.castHasReceivedStatus {
                return
            }
            
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
            
            // Update Jellyfin playback position (for scrobbling)
            if let track = self.currentTrack,
               let jellyfinId = track.jellyfinId,
               let serverId = track.jellyfinServerId {
                JellyfinPlaybackReporter.shared.updatePlayback(
                    trackId: jellyfinId,
                    serverId: serverId,
                    position: current,
                    duration: trackDuration
                )
            }

            // Update Emby playback position (for scrobbling)
            if let track = self.currentTrack,
               let embyId = track.embyId,
               let serverId = track.embyServerId {
                EmbyPlaybackReporter.shared.updatePlayback(
                    trackId: embyId,
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
                Log.audio.infoPublic("AudioEngine: Cast track finished, advancing to next")
                self.castTrackDidFinish()
            }
        }
        // Add to common modes so it runs during menu tracking and other modal states
        RunLoop.main.add(timer, forMode: .common)
        timeUpdateTimer = timer
    }
    
    /// Handle cast track completion - advance to next track
    private func castTrackDidFinish() {
        // Report track finished to Plex (natural end)
        PlexPlaybackReporter.shared.trackDidStop(at: duration, finished: true)

        // Record to radio history (track actually finished playing via cast)
        if let finishedTrack = currentTrack {
            switch finishedTrack.playHistorySource {
            case .plex:      PlexRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .subsonic:  SubsonicRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .jellyfin:  JellyfinRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .emby:      EmbyRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .local, .radio:
                LocalRadioHistory.shared.recordTrackPlayed(finishedTrack)
            }
        }

        // Play event (analytics) — inline to survive quit
        if let finishedTrack = currentTrack {
            let trackId = finishedTrack.playHistoryTrackIdentifier
            let eventId = MediaLibraryStore.shared.insertPlayEvent(
                trackId: trackId,
                trackURL: finishedTrack.url.isFileURL ? finishedTrack.url.absoluteString : nil,
                title: finishedTrack.title,
                artist: finishedTrack.artist,
                album: finishedTrack.album,
                genre: finishedTrack.genre,
                playedAt: Date(),
                durationListened: finishedTrack.duration ?? 0,
                source: finishedTrack.playHistorySource.rawValue,
                skipped: false)
            if let eventId, finishedTrack.genre == nil || finishedTrack.genre?.isEmpty == true {
                Task.detached(priority: .utility) { [track = finishedTrack] in
                    await GenreDiscoveryService.shared.enrichPlayEvent(
                        id: eventId, title: track.title, artist: track.artist, album: track.album)
                }
            }
        }

        // Prevent multiple calls
        castPlaybackStartDate = nil
        
        // Capture previous index before any changes (for rollback on cast failure)
        let previousIndex = currentIndex
        let previousTrack = currentTrack
        let shuffleSnapshot = captureShufflePlaybackState()
        
        if repeatEnabled {
            if shuffleEnabled {
                // Repeat mode + shuffle: follow the shuffled cycle, skipping Sonos-incompatible formats
                let isSonos = CastManager.shared.isCastingToSonos
                var foundCompatibleTrack = false
                while let nextIndex = nextShuffleIndexForPlaybackAdvance() {
                    currentIndex = nextIndex
                    if !isSonos || CastManager.isSonosCompatible(playlist[nextIndex], allowUnknownSampleRate: true) {
                        foundCompatibleTrack = true
                        break
                    }
                    NSLog("AudioEngine: Skipping '%@' (%@) — not supported by Sonos",
                          playlist[nextIndex].title,
                          playlist[nextIndex].url.pathExtension)
                }
                if !foundCompatibleTrack {
                    Task { await CastManager.shared.stopCasting() }
                    return
                }
            }
            // Cast the same or new random track
            let track = playlist[currentIndex]
            let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
            
            // For local files, defer UI update until cast completes
            if !isLocalFile {
                currentTrack = track
            }
            
            Task {
                do {
                    try await CastManager.shared.castNewTrack(track)
                    if isLocalFile {
                        await MainActor.run {
                            self.currentTrack = track
                        }
                    }
                } catch {
                    Log.audio.errorPublic("castTrackDidFinish: failed to cast: \(error.localizedDescription)")
                    await MainActor.run {
                        self.currentIndex = previousIndex
                        self.currentTrack = previousTrack
                        self.restoreShufflePlaybackState(shuffleSnapshot)
                    }
                }
            }
        } else if !playlist.isEmpty {
            if shuffleEnabled {
                // Shuffle without repeat: advance through the current shuffled cycle once
                let isSonos = CastManager.shared.isCastingToSonos
                var foundCompatibleTrack = false
                while let nextIndex = nextShuffleIndexForPlaybackAdvance() {
                    currentIndex = nextIndex
                    if !isSonos || CastManager.isSonosCompatible(playlist[nextIndex], allowUnknownSampleRate: true) {
                        foundCompatibleTrack = true
                        break
                    }
                    NSLog("AudioEngine: Skipping '%@' (%@) — not supported by Sonos",
                          playlist[nextIndex].title,
                          playlist[nextIndex].url.pathExtension)
                }
                if !foundCompatibleTrack {
                    Task { await CastManager.shared.stopCasting() }
                    return
                }
                let track = playlist[currentIndex]
                let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
                
                // For local files, defer UI update until cast completes
                if !isLocalFile {
                    currentTrack = track
                }
                
                Task {
                    do {
                        try await CastManager.shared.castNewTrack(track)
                        if isLocalFile {
                            await MainActor.run {
                                self.currentTrack = track
                            }
                        }
                    } catch {
                        Log.audio.errorPublic("castTrackDidFinish: failed to cast shuffle: \(error.localizedDescription)")
                        await MainActor.run {
                            self.currentIndex = previousIndex
                            self.currentTrack = previousTrack
                            self.restoreShufflePlaybackState(shuffleSnapshot)
                        }
                    }
                }
            } else if currentIndex < playlist.count - 1 {
                // More tracks to play — advance, skipping Sonos-incompatible formats
                currentIndex += 1
                let isSonos = CastManager.shared.isCastingToSonos
                while currentIndex < playlist.count {
                    if !isSonos || CastManager.isSonosCompatible(playlist[currentIndex], allowUnknownSampleRate: true) { break }
                    NSLog("AudioEngine: Skipping '%@' (%@) — not supported by Sonos",
                          playlist[currentIndex].title,
                          playlist[currentIndex].url.pathExtension)
                    currentIndex += 1
                }
                guard currentIndex < playlist.count else {
                    Task { await CastManager.shared.stopCasting() }
                    return
                }
                let track = playlist[currentIndex]
                let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
                
                // For local files, defer UI update until cast completes
                if !isLocalFile {
                    currentTrack = track
                }
                
                Task {
                    do {
                        try await CastManager.shared.castNewTrack(track)
                        if isLocalFile {
                            await MainActor.run {
                                self.currentTrack = track
                            }
                        }
                    } catch {
                        Log.audio.errorPublic("castTrackDidFinish: failed to cast next: \(error.localizedDescription)")
                        await MainActor.run {
                            self.currentIndex = previousIndex
                            self.currentTrack = previousTrack
                            self.restoreShufflePlaybackState(shuffleSnapshot)
                        }
                    }
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
        Log.audio.infoPublic("loadFiles: \(urls.count) URLs")
        
        // Quick validate files (checks existence and extension - fast)
        // Full format validation happens at playback time
        let validation = AudioFileValidator.quickValidate(urls: urls)
        
        // Notify about invalid files
        if validation.hasInvalidFiles {
            AudioFileValidator.notifyInvalidFiles(validation.invalidFiles)
        }
        
        let tracks = validation.validURLs.compactMap { Track(lightweightURL: $0) }
        Log.audio.infoPublic("loadFiles: \(tracks.count) tracks created (\(validation.invalidFiles.count) invalid)")
        loadTracks(tracks)
        enrichPlaylistDurationsAsync(for: tracks.map(\.id))
    }

    static func shouldStopRadioForIncomingTrack(
        isRadioActive: Bool,
        currentStationURL: URL?,
        incomingTrackURL: URL?
    ) -> Bool {
        guard isRadioActive else { return false }
        guard let stationURL = currentStationURL, let incomingTrackURL else { return true }
        return stationURL != incomingTrackURL
    }

    static func shouldReloadPlaybackPipelineForCurrentTrack(
        trackURL: URL,
        isStreamingPlayback: Bool,
        hasStreamingPlayer: Bool,
        hasLocalAudioFile: Bool,
        isStreamingPlaceholder: Bool = false
    ) -> Bool {
        let trackIsStreaming = isStreamingPlaceholder
            || trackURL.scheme == "http"
            || trackURL.scheme == "https"
        return (trackIsStreaming && (!isStreamingPlayback || !hasStreamingPlayer)) ||
            (!trackIsStreaming && (isStreamingPlayback || !hasLocalAudioFile))
    }

    static func shouldAttemptStreamingURLRefreshAfterError(
        track: Track?,
        isRadioActive: Bool,
        previouslyRetriedServiceIdentity: String?
    ) -> Bool {
        guard !isRadioActive,
              let track,
              !track.isStreamingPlaceholder,
              track.url.scheme == "http" || track.url.scheme == "https",
              let serviceIdentity = track.streamingServiceIdentity else {
            return false
        }
        return previouslyRetriedServiceIdentity != serviceIdentity
    }

    @discardableResult
    private func stopRadioIfLoadingNonRadioContent(incomingTrackURL: URL?, context: String) -> Bool {
        let shouldStopRadio = Self.shouldStopRadioForIncomingTrack(
            isRadioActive: RadioManager.shared.isActive,
            currentStationURL: RadioManager.shared.currentStation?.url,
            incomingTrackURL: incomingTrackURL
        )

        if shouldStopRadio {
            Log.audio.infoPublic("\(context): stopping RadioManager (loading non-radio content)")
            RadioManager.shared.stop()
        }

        return RadioManager.shared.isActive && !shouldStopRadio
    }
    
    /// Load tracks with metadata (for Plex and other sources with pre-populated info)
    func loadTracks(_ tracks: [Track]) {
        Log.audio.infoPublic("loadTracks: \(tracks.count) tracks, currentTrack=\(currentTrack?.title ?? "nil")")
        
        // Filter out missing local files (remote URLs pass through)
        var missingCount = 0
        let validTracks = tracks.filter { track in
            // Remote URLs (Plex/Subsonic streams) don't need file existence check
            if track.url.scheme == "http" || track.url.scheme == "https" {
                return true
            }
            // Local file - check existence
            if FileManager.default.fileExists(atPath: track.url.path) {
                return true
            }
            missingCount += 1
            return false
        }
        
        // Show single alert if any files were missing
        if missingCount > 0 {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Files Not Found"
                alert.informativeText = missingCount == 1
                    ? "1 file could not be found and was skipped."
                    : "\(missingCount) files could not be found and were skipped."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
        
        Log.audio.infoPublic("loadTracks: \(validTracks.count) valid tracks (\(missingCount) skipped)")
        
        let isRadioContent = stopRadioIfLoadingNonRadioContent(
            incomingTrackURL: validTracks.first?.url,
            context: "loadTracks"
        )
        
        // Check if we're currently casting - we want to keep the cast session active
        let wasCasting = isCastingActive
        
        // Stop current local playback (but don't disconnect from cast device if casting)
        if wasCasting {
            // Just stop local playback, keep cast session
            stopLocalOnly()
            stopStreamingPlayer()
            isStreamingPlayback = false
        } else if isRadioContent {
            // For radio content, stop local playback but don't call stop()
            // which would call RadioManager.stop() and break radio tracking
            stopLocalOnly()
            stopStreamingPlayer()
            isStreamingPlayback = false
        } else {
            stop()
            stopStreamingPlayer()
            isStreamingPlayback = false
        }
        
        playlist.removeAll()
        playlist.append(contentsOf: validTracks)

        let zeroDurationLocalIDs = validTracks.filter { (($0.duration ?? 0) == 0) && $0.url.isFileURL }.map(\.id)
        enrichPlaylistDurationsAsync(for: zeroDurationLocalIDs)

        if !validTracks.isEmpty {
            if shuffleEnabled {
                currentIndex = startShufflePlaybackCycle() ?? 0
            } else {
                currentIndex = 0
                invalidateShufflePlaybackStateAfterPlaylistMutation()
            }
            
            if wasCasting {
                // When casting, don't set up local playback - just set the track metadata
                // and cast to the active device
                let track = playlist[currentIndex]
                let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
                
                // For local files, defer UI update until cast completes (prevents UI jumping during rapid clicks)
                // For streaming, update immediately since there's no async delay
                if !isLocalFile {
                    currentTrack = track
                }
                _currentTime = 0
                lastReportedTime = 0
                
                Log.audio.infoPublic("loadTracks: casting is active, casting new track '\(track.title)' (local=\(isLocalFile ? 1 : 0))")
                Task {
                    do {
                        try await CastManager.shared.castNewTrack(track)
                        // For local files, update UI after successful cast
                        if isLocalFile {
                            await MainActor.run {
                                self.currentTrack = track
                            }
                        }
                    } catch {
                        Log.audio.errorPublic("loadTracks: failed to cast new track: \(error.localizedDescription)")
                        // Fall back to local playback if casting fails
                        await MainActor.run {
                            self.loadTrack(at: self.currentIndex)
                            self.play()
                        }
                    }
                }
            } else {
                // Normal local playback
                Log.audio.infoPublic("loadTracks: loading track at index \(currentIndex)")
                loadTrack(at: currentIndex)
                play()
            }
        } else {
            invalidateShufflePlaybackStateAfterPlaylistMutation()
        }
        
        delegate?.audioEngineDidChangePlaylist()
    }
    
    func loadFolder(_ url: URL) {
        LocalFileDiscovery.discoverMediaURLsAsync(from: [url], includeVideo: false) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            // loadFiles will call the delegate
            self.loadFiles(urls)
        }
    }
    
    /// Append files to the playlist without starting playback
    func appendFiles(_ urls: [URL]) {
        // Quick validate files (checks existence and extension - fast)
        // Full format validation happens at playback time
        let validation = AudioFileValidator.quickValidate(urls: urls)
        
        // Notify about invalid files
        if validation.hasInvalidFiles {
            AudioFileValidator.notifyInvalidFiles(validation.invalidFiles)
        }
        
        let tracks = validation.validURLs.compactMap { Track(lightweightURL: $0) }
        playlist.append(contentsOf: tracks)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
        enrichPlaylistDurationsAsync(for: tracks.map(\.id))
    }
    
    /// Fills in duration for tracks that have duration == nil.
    /// Looks up each URL in the MediaLibrary in-memory index first (instant, no I/O).
    /// Falls back to AVAudioFile only for tracks not in the library — done off the main thread.
    private func enrichPlaylistDurationsAsync(for trackIDs: [UUID]) {
        guard !trackIDs.isEmpty else { return }
        let idsToEnrich = Set(trackIDs)

        // Snapshot tracks needing enrichment from the main actor.
        let snapshots: [(id: UUID, url: URL)] = playlist.compactMap { t in
            guard idsToEnrich.contains(t.id), (t.duration ?? 0) == 0, t.url.isFileURL else { return nil }
            return (id: t.id, url: t.url)
        }
        guard !snapshots.isEmpty else { return }

        // Try the MediaLibrary in-memory index first — O(1) per track, no disk I/O.
        var durations: [UUID: TimeInterval] = [:]
        var needsFileIO: [(id: UUID, url: URL)] = []
        for item in snapshots {
            if let lib = MediaLibrary.shared.findTrack(byURL: item.url), lib.duration > 0 {
                durations[item.id] = lib.duration
            } else {
                needsFileIO.append(item)
            }
        }

        // Apply library hits immediately on the main thread.
        applyDurationUpdates(durations)

        // For anything not in the library, fall back to AVAudioFile on a background thread.
        guard !needsFileIO.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            var fileDurations: [UUID: TimeInterval] = [:]
            for item in needsFileIO {
                guard let af = try? AVAudioFile(forReading: item.url) else { continue }
                let dur = Double(af.length) / af.processingFormat.sampleRate
                if dur > 0 { fileDurations[item.id] = dur }
            }
            guard !fileDurations.isEmpty else { return }
            await MainActor.run { [weak self] in
                self?.applyDurationUpdates(fileDurations)
            }
        }
    }

    /// Replaces playlist tracks whose UUIDs appear in `durations` with copies carrying the real duration.
    /// Must be called on the main thread.
    private func applyDurationUpdates(_ durations: [UUID: TimeInterval]) {
        guard !durations.isEmpty else { return }
        var changed = false
        for (idx, track) in playlist.enumerated() {
            guard let dur = durations[track.id] else { continue }
            playlist[idx] = Track(
                id: track.id, url: track.url, title: track.title,
                artist: track.artist, album: track.album, duration: dur,
                bitrate: track.bitrate, sampleRate: track.sampleRate,
                channels: track.channels, plexRatingKey: track.plexRatingKey,
                plexServerId: track.plexServerId, subsonicId: track.subsonicId,
                subsonicServerId: track.subsonicServerId, jellyfinId: track.jellyfinId,
                jellyfinServerId: track.jellyfinServerId, embyId: track.embyId,
                embyServerId: track.embyServerId, artworkThumb: track.artworkThumb,
                mediaType: track.mediaType, genre: track.genre,
                contentType: track.contentType
            )
            changed = true
        }
        if changed { delegate?.audioEngineDidChangePlaylist() }
    }

    /// Append tracks to the playlist without starting playback
    /// Used for restoring streaming tracks from saved state
    func appendTracks(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        playlist.append(contentsOf: tracks)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
    }
    
    /// Set the playlist from pre-built Track objects without starting playback.
    /// Unlike setPlaylistFiles (which takes URLs), this accepts Track objects directly,
    /// preserving metadata and streaming IDs. Used by state restoration to maintain
    /// playlist ordering when mixing local and streaming tracks.
    func setPlaylistTracks(_ tracks: [Track]) {
        Log.audio.infoPublic("setPlaylistTracks: \(tracks.count) tracks")
        playlist.removeAll()
        playlist.append(contentsOf: tracks)
        currentIndex = -1  // No track selected
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
        let missingDuration = tracks.filter { ($0.duration ?? 0) == 0 && $0.url.isFileURL }.map(\.id)
        enrichPlaylistDurationsAsync(for: missingDuration)
    }
    
    /// Select a track by index for display without loading or playing it.
    /// Used during state restoration when the real stream URL is pending an async fetch.
    func selectTrackForDisplay(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        currentIndex = index
        currentTrack = playlist[index]
        state = .stopped
        _currentTime = 0
        lastReportedTime = 0
        delegate?.audioEngineDidChangeTrack(currentTrack)
    }

    /// Replace a track at a specific index without affecting playback.
    /// Used to swap placeholder tracks with fully-resolved streaming tracks
    /// during state restoration.
    func replaceTrack(at index: Int, with track: Track) {
        guard index >= 0 && index < playlist.count else { return }
        playlist[index] = track
        delegate?.audioEngineDidChangePlaylist()
    }

    private func resolvePlaceholderTrackAndOptionallyPlay(at index: Int, autoPlayOnSuccess: Bool) {
        guard index >= 0 && index < playlist.count else { return }
        let placeholder = playlist[index]
        guard placeholder.isStreamingPlaceholder else {
            if autoPlayOnSuccess {
                loadTrack(at: index)
                if state != .playing {
                    play()
                }
            }
            return
        }

        guard placeholder.isResolvableStreamingServiceTrack else {
            let message = "Cannot refresh streaming URL for \(placeholder.title)"
            let error = NSError(
                domain: "AudioEngine",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
            notifyTrackLoadFailure(track: placeholder, error: error, message: message)
            return
        }

        if placeholderResolutionTasks[index] != nil {
            Log.audio.infoPublic("AudioEngine: placeholder resolve already in progress for index \(index)")
            return
        }

        Log.audio.infoPublic("AudioEngine: resolving placeholder track '\(placeholder.title)' at index \(index)")
        let task = Task { [weak self] in
            guard let self else { return }
            let resolvedTrack = await StreamingTrackResolver.resolve(placeholder)

            await MainActor.run {
                self.placeholderResolutionTasks[index] = nil
                guard index >= 0 && index < self.playlist.count else { return }

                // Only replace if the same placeholder is still at this index.
                guard self.playlist[index].id == placeholder.id,
                      self.playlist[index].isStreamingPlaceholder else {
                    return
                }

                guard let resolvedTrack else {
                    let message = "Cannot refresh streaming URL for \(placeholder.title)"
                    let error = NSError(
                        domain: "AudioEngine",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                    self.notifyTrackLoadFailure(track: placeholder, error: error, message: message)
                    return
                }

                self.replaceTrack(at: index, with: resolvedTrack)
                if self.currentIndex == index {
                    self.loadTrack(at: index)
                    if autoPlayOnSuccess && self.state != .playing {
                        self.play()
                    }
                }
            }
        }

        placeholderResolutionTasks[index] = task
    }
    
    /// Insert tracks immediately after the current position.
    /// If nothing is playing (currentIndex == -1), inserts at index 0.
    /// Starts playback if playlist was empty and startPlaybackIfEmpty is true.
    func insertTracksAfterCurrent(_ tracks: [Track], startPlaybackIfEmpty: Bool = true) {
        guard !tracks.isEmpty else { return }
        
        // When casting local files, block rapid clicks - only accept if not already casting
        if isCastingActive && CastManager.shared.isLocalFileCastInProgress() {
            Log.audio.infoPublic("AudioEngine: insertTracksAfterCurrent() blocked - local file cast in progress")
            return
        }
        
        let wasEmpty = playlist.isEmpty
        let insertIndex = currentIndex >= 0 ? currentIndex + 1 : 0
        
        // Insert tracks at the calculated position
        playlist.insert(contentsOf: tracks, at: insertIndex)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        
        // No need to adjust currentIndex - we're inserting AFTER current
        
        // Start playback if playlist was empty
        if wasEmpty && startPlaybackIfEmpty {
            if shuffleEnabled {
                let insertedIndices = Array(insertIndex..<(insertIndex + tracks.count))
                currentIndex = startShufflePlaybackCycle(preferredIndices: insertedIndices) ?? 0
            } else {
                currentIndex = 0
                alignShufflePlaybackPositionForSelectedTrack(currentIndex)
            }
            
            // Check if we're currently casting
            let wasCasting = isCastingActive
            
            if wasCasting {
                // When casting, don't set up local playback - just update track metadata and cast
                let track = playlist[currentIndex]
                let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
                
                // For local files, defer UI update until cast completes (prevents UI jumping during rapid clicks)
                // For streaming, update immediately since there's no async delay
                if !isLocalFile {
                    currentTrack = track
                }
                _currentTime = 0
                lastReportedTime = 0
                
                Log.audio.infoPublic("insertTracksAfterCurrent: casting is active, casting track at index \(currentIndex) (local=\(isLocalFile ? 1 : 0))")
                Task {
                    do {
                        try await CastManager.shared.castNewTrack(track)
                        // For local files, update UI after successful cast
                        if isLocalFile {
                            await MainActor.run {
                                self.currentTrack = track
                            }
                        }
                    } catch {
                        Log.audio.errorPublic("insertTracksAfterCurrent: failed to cast track: \(error.localizedDescription)")
                        // Fall back to local playback if casting fails
                        await MainActor.run {
                            self.loadTrack(at: self.currentIndex)
                            self.play()
                        }
                    }
                }
            } else {
                loadTrack(at: currentIndex)
                play()
            }
        }
        
        delegate?.audioEngineDidChangePlaylist()
    }
    
    /// Insert tracks after current position and immediately play the first inserted track.
    /// This is the "Play Now" / "Jump the Line" behavior - adds to queue and starts playing immediately.
    func playNow(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        
        // When casting local files, block rapid clicks - only accept if not already casting
        if isCastingActive && CastManager.shared.isLocalFileCastInProgress() {
            Log.audio.infoPublic("AudioEngine: playNow() blocked - local file cast in progress")
            return
        }

        _ = stopRadioIfLoadingNonRadioContent(
            incomingTrackURL: tracks.first?.url,
            context: "playNow"
        )
        
        let insertIndex = currentIndex >= 0 ? currentIndex + 1 : 0
        
        // Insert tracks at the calculated position
        playlist.insert(contentsOf: tracks, at: insertIndex)
        
        // Jump to and play the first inserted track
        if shuffleEnabled {
            let insertedIndices = Array(insertIndex..<(insertIndex + tracks.count))
            currentIndex = startShufflePlaybackCycle(preferredIndices: insertedIndices) ?? insertIndex
        } else {
            currentIndex = insertIndex
            alignShufflePlaybackPositionForSelectedTrack(insertIndex)
        }
        
        // Check if we're currently casting
        let wasCasting = isCastingActive
        
        if wasCasting {
            // When casting, don't set up local playback - just update track metadata and cast
            let track = playlist[currentIndex]
            let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
            
            // For local files, defer UI update until cast completes (prevents UI jumping during rapid clicks)
            // For streaming, update immediately since there's no async delay
            if !isLocalFile {
                currentTrack = track
            }
            _currentTime = 0
            lastReportedTime = 0
            
            Log.audio.infoPublic("playNow: casting is active, casting track at index \(currentIndex) (local=\(isLocalFile ? 1 : 0))")
            Task {
                do {
                    try await CastManager.shared.castNewTrack(track)
                    // For local files, update UI after successful cast
                    if isLocalFile {
                        await MainActor.run {
                            self.currentTrack = track
                        }
                    }
                } catch {
                    Log.audio.errorPublic("playNow: failed to cast track: \(error.localizedDescription)")
                    // Fall back to local playback if casting fails
                    await MainActor.run {
                        self.loadTrack(at: self.currentIndex)
                        self.play()
                    }
                }
            }
        } else {
            loadTrack(at: currentIndex)
            play()
        }
        
        delegate?.audioEngineDidChangePlaylist()
    }
    
    /// Set the playlist files without starting playback (for state restoration)
    /// This clears the existing playlist and populates it with the given files,
    /// but does NOT load or play any track.
    func setPlaylistFiles(_ urls: [URL]) {
        Log.audio.infoPublic("setPlaylistFiles: \(urls.count) URLs")
        
        // Filter out missing local files (remote URLs pass through)
        var missingCount = 0
        let validURLs = urls.filter { url in
            // Remote URLs (Plex/Subsonic streams) don't need file existence check
            if url.scheme == "http" || url.scheme == "https" {
                return true
            }
            // Local file - check existence
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            missingCount += 1
            return false
        }
        
        Log.audio.infoPublic("setPlaylistFiles: \(validURLs.count) valid URLs (\(missingCount) missing)")
        
        let tracks = validURLs.compactMap { Track(lightweightURL: $0) }

        // Clear and set playlist without loading or playing
        playlist.removeAll()
        playlist.append(contentsOf: tracks)
        currentIndex = -1  // No track selected
        invalidateShufflePlaybackStateAfterPlaylistMutation()

        delegate?.audioEngineDidChangePlaylist()
        enrichPlaylistDurationsAsync(for: tracks.map(\.id))
    }
    
    private func loadTrack(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }

        // Any explicit track load supersedes pending deferred local-load completions.
        deferredLocalTrackLoadToken &+= 1
        
        // Prevent concurrent loads - skip if already loading to avoid dual playback
        guard !isLoadingTrack else {
            Log.audio.infoPublic("loadTrack: Blocked - already loading a track")
            return
        }
        isLoadingTrack = true
        defer { isLoadingTrack = false }
        
        let track = playlist[index]
        if staleStreamingRefreshRetriedServiceIdentity != nil,
           staleStreamingRefreshRetriedServiceIdentity != track.streamingServiceIdentity {
            staleStreamingRefreshRetriedServiceIdentity = nil
        }

        // Skip about:blank placeholder tracks — streaming URL not yet resolved via async fetch
        if track.isStreamingPlaceholder {
            Log.audio.infoPublic("loadTrack: skipping placeholder track '\(track.title)' — waiting for async URL fetch")
            return
        }

        _ = stopRadioIfLoadingNonRadioContent(
            incomingTrackURL: track.url,
            context: "loadTrack"
        )

        // Route video tracks to the video player
        if track.mediaType == .video {
            Log.audio.infoPublic("AudioEngine: Routing video track to video player: \(track.title)")
            currentTrack = track
            currentIndex = index
            _currentTime = 0
            lastReportedTime = 0
            
            // Stop any audio playback and reset streaming state
            if isStreamingPlayback {
                streamingPlayer?.stop()
            } else {
                playerNode.stop()
            }
            isStreamingPlayback = false  // Reset to neutral state for video playback
            
            // Route to video player via WindowManager
            guard !AudioEngine.isHeadless else { return }
            DispatchQueue.main.async {
                WindowManager.shared.playVideoTrack(track)
            }
            return
        }

        // Stop video playback before loading audio track
        // This ensures the user's intent to play audio takes precedence
        if !AudioEngine.isHeadless && WindowManager.shared.isVideoActivePlayback {
            Log.audio.infoPublic("loadTrack: Stopping video playback before loading audio track")
            WindowManager.shared.stopVideo()
        }
        
        // Check if this is a remote URL (streaming)
        if track.url.scheme == "http" || track.url.scheme == "https" {
            loadStreamingTrack(track)
        } else {
            if !loadLocalTrack(track) {
                // File doesn't exist or failed to load - skip to next track silently
                Log.audio.errorPublic("loadTrack: Failed to load track at index \(index), skipping to next")
                if index + 1 < playlist.count {
                    currentIndex = index + 1
                    // Must clear isLoadingTrack before recursive call (defer hasn't run yet)
                    isLoadingTrack = false
                    loadTrack(at: currentIndex)
                }
                // If no more tracks, just stop (don't start playback)
            }
        }
    }
    
    private func loadLocalTrackForImmediatePlayback(_ track: Track, at index: Int) {
        Log.audio.infoPublic("loadLocalTrackForImmediatePlayback: \(track.url.lastPathComponent)")

        // Invalidate any prior deferred local opens; only latest selection should win.
        deferredLocalTrackLoadToken &+= 1
        let token = deferredLocalTrackLoadToken
        let expectedTrackID = track.id

        // Invalidate outgoing completion handlers now so stale EOF callbacks are ignored.
        playbackGeneration += 1
        let currentGeneration = playbackGeneration

        // Stop video playback before loading audio track.
        if !AudioEngine.isHeadless && WindowManager.shared.isVideoActivePlayback {
            Log.audio.infoPublic("loadLocalTrackForImmediatePlayback: Stopping video playback before loading audio track")
            WindowManager.shared.stopVideo()
        }

        currentTrack = track
        _currentTime = 0
        lastReportedTime = 0
        state = .stopped
        stopTimeUpdates()

        prepareForLocalTrackLoad()

        let openStart = CFAbsoluteTimeGetCurrent()
        deferredIOQueue.async { [weak self] in
            guard let self else { return }

            do {
                // For network-mounted volumes, copy the file to a local temp path before
                // scheduling. AVAudioPlayerNode.scheduleFile reads from disk continuously
                // via an internal pre-fetch thread — any NAS latency spike drains its ring
                // buffer and produces an audible dropout. Playing from a local copy avoids
                // all NAS I/O on the audio render path.
                var tempURL: URL? = nil
                let playbackURL: URL
                let isLocalVolume = (try? track.url.resourceValues(
                    forKeys: [.volumeIsLocalKey]
                ))?.volumeIsLocal ?? true

                if !isLocalVolume {
                    let fileSize = (try? track.url.resourceValues(
                        forKeys: [.fileSizeKey]
                    ))?.fileSize ?? 0
                    // Skip copy for very large files (>300 MB) to avoid excessive startup delay.
                    if fileSize <= 300 * 1024 * 1024 {
                        let ext = track.url.pathExtension
                        let candidate = URL(fileURLWithPath: NSTemporaryDirectory())
                            .appendingPathComponent("nullplayer-\(UUID().uuidString).\(ext)")
                        let copyStart = CFAbsoluteTimeGetCurrent()
                        try FileManager.default.copyItem(at: track.url, to: candidate)
                        NSLog(
                            "loadLocalTrackForImmediatePlayback: Copied NAS '%@' to temp in %.3fs",
                            track.url.lastPathComponent,
                            CFAbsoluteTimeGetCurrent() - copyStart
                        )
                        tempURL = candidate
                    } else {
                        NSLog(
                            "loadLocalTrackForImmediatePlayback: Skipping NAS copy for large file '%@' (%lld MB)",
                            track.url.lastPathComponent,
                            Int64(fileSize) / (1024 * 1024)
                        )
                    }
                }
                playbackURL = tempURL ?? track.url

                let newAudioFile = try AVAudioFile(forReading: playbackURL)
                let openElapsed = CFAbsoluteTimeGetCurrent() - openStart
                NSLog(
                    "loadLocalTrackForImmediatePlayback: Opened '%@' in %.3fs",
                    track.url.lastPathComponent,
                    openElapsed
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        if let tmp = tempURL { try? FileManager.default.removeItem(at: tmp) }
                        return
                    }
                    guard self.deferredLocalTrackLoadToken == token,
                          index >= 0,
                          index < self.playlist.count,
                          self.currentIndex == index,
                          self.playlist[index].id == expectedTrackID else {
                        if let tmp = tempURL { try? FileManager.default.removeItem(at: tmp) }
                        return
                    }

                    self.tempPlaybackFileURL = tempURL
                    self.commitShufflePlaybackAdvance(to: index)
                    self.commitLoadedLocalTrack(newAudioFile, track: track, generation: currentGeneration)
                    self.play()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.deferredLocalTrackLoadToken == token else { return }
                    self.handleLocalTrackLoadFailure(track: track, error: error)
                }
            }
        }
    }

    @discardableResult
    private func loadLocalTrack(_ track: Track) -> Bool {
        Log.audio.infoPublic("loadLocalTrack: \(track.url.lastPathComponent)")

        // Any synchronous load supersedes deferred opens.
        deferredLocalTrackLoadToken &+= 1

        // Invalidate outgoing completion handlers before opening a replacement file.
        playbackGeneration += 1
        let currentGeneration = playbackGeneration

        prepareForLocalTrackLoad()

        do {
            let openStart = CFAbsoluteTimeGetCurrent()
            let newAudioFile = try AVAudioFile(forReading: track.url)
            let openElapsed = CFAbsoluteTimeGetCurrent() - openStart
            Log.audio.infoPublic("loadLocalTrack: Opened '\(track.url.lastPathComponent)' in \(String(format: "%.3f", openElapsed))s")

            commitLoadedLocalTrack(newAudioFile, track: track, generation: currentGeneration)
            return true
        } catch {
            handleLocalTrackLoadFailure(track: track, error: error)
            return false
        }
    }

    private func prepareForLocalTrackLoad() {
        // Clean up temp files from previous NAS copies.
        if let tmp = tempPlaybackFileURL {
            try? FileManager.default.removeItem(at: tmp)
            tempPlaybackFileURL = nil
        }
        if let tmp = tempGaplessFileURL {
            try? FileManager.default.removeItem(at: tmp)
            tempGaplessFileURL = nil
        }

        // Stop any streaming playback.
        stopStreamingPlayer()
        isStreamingPlayback = false
        suspendedLocalPlaybackClockForSleep = false

        // Reset crossfade state and force local primary node to audible unity gain.
        // Rapid source switches can otherwise leave playerNode.volume at 0.
        resetLocalCrossfadeStateForDirectPlayback()
        playerNode.stop()

        // Reset AudioEngine's adaptive normalization peaks for clean start.
        // When streaming was active, AudioEngine just forwarded StreamingAudioPlayer's
        // pre-normalized data without updating its own peaks. These stale peaks
        // would cause erratic spectrum levels when switching back to local.
        spectrumGlobalPeak = 0.0
        spectrumGlobalReferenceLevel = 0.0
        spectrumRegionPeaks = [0.0, 0.0, 0.0]
        spectrumRegionReferenceLevels = [0.0, 0.0, 0.0]

        // Reset spectrum analyzer state when switching sources.
        NotificationCenter.default.post(name: NSNotification.Name("ResetSpectrumState"), object: nil)

        // Clear any pre-scheduled gapless track (we're loading a new track explicitly).
        nextScheduledFile = nil
        nextScheduledTrackIndex = -1
    }

    private func commitLoadedLocalTrack(_ newAudioFile: AVAudioFile, track: Track, generation: Int) {
        Log.audio.infoPublic("loadLocalTrack: file loaded successfully, format: \(newAudioFile.processingFormat.description)")

        // Install spectrum analyzer tap.
        installSpectrumTap(format: nil)

        audioFile = newAudioFile
        currentTrack = track
        _currentTime = 0
        lastReportedTime = 0

        // Analyze and apply volume normalization asynchronously to avoid blocking
        // UI/playback startup on slow disks or NAS volumes.
        if volumeNormalizationEnabled {
            analyzeAndApplyNormalization(file: newAudioFile, generation: generation)
        } else {
            normalizationGain = 1.0
            applyNormalizationGain()
        }

        Log.audio.infoPublic("loadLocalTrack: Stopping playerNode and scheduling file...")
        playerNode.stop()
        playerNode.scheduleFile(newAudioFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handlePlaybackComplete(generation: generation)
            }
        }

        // Pre-schedule next track for gapless playback.
        if gaplessPlaybackEnabled {
            scheduleNextTrackForGapless()
        }

        // Report track start to Plex (no-op for local files without plexRatingKey).
        PlexPlaybackReporter.shared.trackDidStart(track, at: 0)

        // Report track start to Subsonic.
        if let subsonicId = track.subsonicId,
           let serverId = track.subsonicServerId,
           let trackDuration = track.duration {
            SubsonicPlaybackReporter.shared.trackStarted(trackId: subsonicId, serverId: serverId, duration: trackDuration)
        }

        // Report track start to Jellyfin.
        if let jellyfinId = track.jellyfinId,
           let serverId = track.jellyfinServerId,
           let trackDuration = track.duration {
            JellyfinPlaybackReporter.shared.trackStarted(trackId: jellyfinId, serverId: serverId, duration: trackDuration)
        }

        // Report track start to Emby.
        if let embyId = track.embyId,
           let serverId = track.embyServerId,
           let trackDuration = track.duration {
            EmbyPlaybackReporter.shared.trackStarted(trackId: embyId, serverId: serverId, duration: trackDuration)
        }

        Log.audio.infoPublic("loadLocalTrack: file scheduled, EQ bypass = \(eqNode.bypass), normGain = \(String(format: "%.2f", normalizationGain))")
    }

    private func handleLocalTrackLoadFailure(track: Track, error: Error) {
        let fileExtension = track.url.pathExtension.lowercased()
        var errorMessage = "Failed to load '\(track.url.lastPathComponent)': \(error.localizedDescription)"

        // Add format-specific hints.
        if fileExtension == "wav" {
            errorMessage += " (WAV files with compressed audio or unusual formats may not be supported)"
        }

        Log.audio.errorPublic("loadLocalTrack: FAILED to load file")
        Log.audio.infoPublic("  File: \(track.url.lastPathComponent)")
        Log.audio.infoPublic("  Extension: \(fileExtension)")
        Log.audio.errorPublic("  Error: \(error.localizedDescription)")
        if let nsError = error as NSError? {
            Log.audio.infoPublic("  Error domain: \(nsError.domain), code: \(nsError.code)")
        }

        stopPlaybackOnError()
        notifyTrackLoadFailure(track: track, error: error, message: errorMessage)
    }
    
    /// Stop playback completely when a track fails to load
    private func stopPlaybackOnError() {
        playerNode.stop()
        resetLocalCrossfadeStateForDirectPlayback()
        audioFile = nil
        currentTrack = nil
        _currentTime = 0
        lastReportedTime = 0
        state = .stopped
        suspendedLocalPlaybackClockForSleep = false
        stopTimeUpdates()
    }
    
    /// Notify delegate and post notification when a track fails to load
    private func notifyTrackLoadFailure(track: Track, error: Error, message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.audioEngineDidFailToLoadTrack(track, error: error)
            
            NotificationCenter.default.post(
                name: .audioTrackDidFailToLoad,
                object: self,
                userInfo: ["track": track, "error": error, "message": message]
            )
        }
    }
    
    private func loadStreamingTrack(_ track: Track) {
        Log.audio.infoPublic("loadStreamingTrack: \(track.artist ?? "Unknown") - \(track.title)")
        Log.audio.infoPublic("  URL: \(track.url.redacted)")
        
        // Stop local playback and REMOVE spectrum tap (streaming player has its own)
        playerNode.stop()
        mixerNode.removeTap(onBus: 0)  // Critical: remove local spectrum tap
        audioFile = nil
        isStreamingPlayback = true
        
        // Reset spectrum analyzer state when switching sources
        NotificationCenter.default.post(name: NSNotification.Name("ResetSpectrumState"), object: nil)
        
        // Set flag before starting new track - EOF callbacks from old track should be ignored
        isLoadingNewStreamingTrack = true
        
        // DON'T call stop() before play() - the AudioStreaming library handles this internally.
        // Calling stop() explicitly causes a race condition where the async stop callback
        // fires AFTER play(url:) is called, cancelling the newly queued track.
        
        // Create streaming player if needed
        if streamingPlayer == nil {
            streamingPlayer = StreamingAudioPlayer(eqConfiguration: activeEQConfiguration)
            streamingPlayer?.delegate = self
            streamingPlayer?.spectrumNeeded = spectrumNeeded
            streamingPlayer?.waveformNeeded = waveformNeeded
            streamingPlayer?.isModernUIEnabled = isModernUIEnabled
        }
        
        // Sync EQ settings from main EQ to streaming player
        syncEQToStreamingPlayer()
        
        // Set volume
        streamingPlayer?.volume = volume
        
        currentTrack = track
        _currentTime = 0
        lastReportedTime = 0

        // Re-activate RadioManager if the URL belongs to a known station but radio isn't active.
        // This handles playlist replay and state-restore paths that bypass RadioManager.play(station:).
        RadioManager.shared.reactivateIfNeeded(for: track.url)

        // Increment generation
        playbackGeneration += 1

        // Start playback through the streaming player (routes through AVAudioEngine with EQ)
        streamingPlayer?.play(url: track.url)
        
        // Set state to playing immediately so play() doesn't try to reload
        state = .playing
        playbackStartDate = Date()
        suspendedLocalPlaybackClockForSleep = false
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
        
        // Report track start to Jellyfin
        if let jellyfinId = track.jellyfinId,
           let serverId = track.jellyfinServerId,
           let trackDuration = track.duration {
            JellyfinPlaybackReporter.shared.trackStarted(trackId: jellyfinId, serverId: serverId, duration: trackDuration)
        }

        // Report track start to Emby
        if let embyId = track.embyId,
           let serverId = track.embyServerId,
           let trackDuration = track.duration {
            EmbyPlaybackReporter.shared.trackStarted(trackId: embyId, serverId: serverId, duration: trackDuration)
        }

        Log.audio.infoPublic("  Created StreamingAudioPlayer, starting playback with EQ")
    }
    
    /// Sync EQ settings from the main engine's EQ to a streaming player's EQ
    /// - Parameter player: The streaming player to sync, or nil to sync to the primary streaming player
    private func syncEQToStreamingPlayer(_ player: StreamingAudioPlayer? = nil) {
        let sp = player ?? streamingPlayer
        guard let targetPlayer = sp else { return }
        
        var bands: [Float] = []
        for i in 0..<activeEQConfiguration.bandCount {
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
        // Safety guard: if a crossfade is in progress, ignore stray completion callbacks
        // (the crossfade handles the transition via completeCrossfade/completeStreamingCrossfade)
        guard !isCrossfading else {
            Log.audio.infoPublic("trackDidFinish: Ignoring during crossfade")
            return
        }
        
        // Report track finished to Plex (natural end)
        let finishPosition = duration
        PlexPlaybackReporter.shared.trackDidStop(at: finishPosition, finished: true)
        
        // Report track finished to Subsonic (track stopped is called since it finished)
        SubsonicPlaybackReporter.shared.trackStopped()
        
        // Report stop to Jellyfin
        JellyfinPlaybackReporter.shared.trackStopped()

        // Report stop to Emby
        EmbyPlaybackReporter.shared.trackStopped()

        // Record to radio history (track actually finished playing)
        if let finishedTrack = currentTrack {
            switch finishedTrack.playHistorySource {
            case .plex:      PlexRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .subsonic:  SubsonicRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .jellyfin:  JellyfinRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .emby:      EmbyRadioHistory.shared.recordTrackPlayed(finishedTrack)
            case .local, .radio:
                LocalRadioHistory.shared.recordTrackPlayed(finishedTrack)
            }
        }

        // Record play event to analytics
        if let finishedTrack = currentTrack {
            let trackId = finishedTrack.playHistoryTrackIdentifier
            let eventId = MediaLibraryStore.shared.insertPlayEvent(
                trackId: trackId,
                trackURL: finishedTrack.url.isFileURL ? finishedTrack.url.absoluteString : nil,
                title: finishedTrack.title,
                artist: finishedTrack.artist,
                album: finishedTrack.album,
                genre: finishedTrack.genre,
                playedAt: Date(),
                durationListened: finishedTrack.duration ?? 0,
                source: finishedTrack.playHistorySource.rawValue,
                skipped: false)
            if let eventId, finishedTrack.genre == nil || finishedTrack.genre?.isEmpty == true {
                Task.detached(priority: .utility) { [track = finishedTrack] in
                    await GenreDiscoveryService.shared.enrichPlayEvent(
                        id: eventId, title: track.title, artist: track.artist, album: track.album)
                }
            }
        }

        // Check if we have a gaplessly pre-scheduled next track (local files)
        if gaplessPlaybackEnabled && nextScheduledFile != nil && nextScheduledTrackIndex >= 0 {
            // Gapless transition - the next file is already scheduled
            currentIndex = nextScheduledTrackIndex
            commitShufflePlaybackAdvance(to: currentIndex)
            audioFile = nextScheduledFile
            currentTrack = playlist[currentIndex]
            _currentTime = 0
            lastReportedTime = 0
            
            // Clear the pre-scheduled track
            nextScheduledFile = nil
            nextScheduledTrackIndex = -1

            // Promote gapless temp file: delete old primary temp, adopt gapless temp as new primary
            if let oldTemp = tempPlaybackFileURL { try? FileManager.default.removeItem(at: oldTemp) }
            tempPlaybackFileURL = tempGaplessFileURL
            tempGaplessFileURL = nil

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
            
            // Report track start to Jellyfin
            if let track = currentTrack,
               let jellyfinId = track.jellyfinId,
               let serverId = track.jellyfinServerId,
               let trackDuration = track.duration {
                JellyfinPlaybackReporter.shared.trackStarted(trackId: jellyfinId, serverId: serverId, duration: trackDuration)
            }

            // Report track start to Emby
            if let track = currentTrack,
               let embyId = track.embyId,
               let serverId = track.embyServerId,
               let trackDuration = track.duration {
                EmbyPlaybackReporter.shared.trackStarted(trackId: embyId, serverId: serverId, duration: trackDuration)
            }

            // Apply normalization for the new track
            if volumeNormalizationEnabled {
                analyzeAndApplyNormalization(file: audioFile!)
            }
            
            // Schedule the next track for gapless
            scheduleNextTrackForGapless()
            
            Log.audio.infoPublic("Gapless transition to: \(currentTrack?.title ?? "Unknown")")
            return
        }
        
        // Check if we have a gaplessly pre-scheduled streaming track
        // AudioStreaming library automatically plays the queued track, we just need to update metadata
        if gaplessPlaybackEnabled && isStreamingPlayback && streamingPlayer?.hasQueuedTrack == true && nextScheduledTrackIndex >= 0 {
            // Streaming gapless transition - the player already started the queued track
            currentIndex = nextScheduledTrackIndex
            commitShufflePlaybackAdvance(to: currentIndex)
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
            
            // Report track start to Jellyfin
            if let track = currentTrack,
               let jellyfinId = track.jellyfinId,
               let serverId = track.jellyfinServerId,
               let trackDuration = track.duration {
                JellyfinPlaybackReporter.shared.trackStarted(trackId: jellyfinId, serverId: serverId, duration: trackDuration)
            }

            // Report track start to Emby
            if let track = currentTrack,
               let embyId = track.embyId,
               let serverId = track.embyServerId,
               let trackDuration = track.duration {
                EmbyPlaybackReporter.shared.trackStarted(trackId: embyId, serverId: serverId, duration: trackDuration)
            }

            // Schedule the next track for gapless
            scheduleNextTrackForGapless()
            
            Log.audio.infoPublic("Streaming gapless transition to: \(currentTrack?.title ?? "Unknown")")
            return
        }
        
        if repeatEnabled {
            if shuffleEnabled {
                // Repeat mode + shuffle: follow the shuffled cycle, reshuffling only after a full pass
                guard let nextIndex = peekNextShuffleIndexForPlayback() else {
                    stop()
                    return
                }
                currentIndex = nextIndex
                advanceToLocalTrackAsync(at: currentIndex)
            } else {
                // Repeat mode: loop current track
                advanceToLocalTrackAsync(at: currentIndex)
            }
        } else {
            // No repeat mode: check if we're at the end of playlist
            if shuffleEnabled {
                guard let nextIndex = peekNextShuffleIndexForPlayback() else {
                    stop()
                    return
                }
                currentIndex = nextIndex
                advanceToLocalTrackAsync(at: currentIndex)
            } else if currentIndex < playlist.count - 1 {
                // More tracks to play
                currentIndex += 1
                advanceToLocalTrackAsync(at: currentIndex)
            } else {
                // End of playlist, stop playback
                stop()
            }
        }
    }

    /// Advance playback to the track at `index` after a natural EOF.
    /// Local audio files are opened asynchronously on deferredIOQueue to avoid
    /// blocking the main thread on NAS/network-mounted volumes.
    /// Streaming tracks and placeholders fall through to the synchronous loadTrack path.
    private func advanceToLocalTrackAsync(at index: Int) {
        guard index >= 0, index < playlist.count else { return }
        let nextTrack = playlist[index]
        if nextTrack.url.isFileURL && nextTrack.mediaType != .video {
            // Defensive guard: loadLocalTrackForImmediatePlayback bypasses loadTrack's
            // isLoadingTrack sentinel. Guard here in case a concurrent loadTrack call is
            // on the same run-loop turn (both run on main thread, so this is advisory).
            guard !isLoadingTrack else { return }
            _ = stopRadioIfLoadingNonRadioContent(incomingTrackURL: nextTrack.url,
                                                  context: "trackDidFinish")
            loadLocalTrackForImmediatePlayback(nextTrack, at: index)
        } else {
            // Streaming tracks, placeholders (about:blank URL fails isFileURL),
            // and video files use the existing synchronous path.
            commitShufflePlaybackAdvance(to: index)
            loadTrack(at: index)
            play()
        }
    }

    // MARK: - Gapless Playback
    
    /// Pre-schedule the next track for gapless playback
    private func scheduleNextTrackForGapless() {
        gaplessPreparationToken &+= 1
        guard gaplessPlaybackEnabled else { return }
        
        // Don't queue if Sweet Fades is enabled - it handles transitions
        guard !sweetFadeEnabled else {
            Log.audio.infoPublic("Gapless: Skipping - Sweet Fades enabled")
            return
        }
        
        // Don't queue when casting - playback is remote
        guard !isCastingActive else {
            Log.audio.infoPublic("Gapless: Skipping - casting is active")
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
                Log.audio.infoPublic("Gapless: Next track is local file, can't queue for streaming gapless")
                return
            }
            
            streamingPlayer?.queue(url: nextTrack.url)
            nextScheduledTrackIndex = nextIndex
            Log.audio.infoPublic("Gapless: Queued streaming track: \(nextTrack.title)")
        } else {
            // Local file gapless
            guard nextTrack.url.isFileURL else {
                Log.audio.infoPublic("Gapless: Next track is streaming, can't queue for local gapless")
                return
            }

            // Clear the currently prepared local file while we asynchronously prepare the next one.
            nextScheduledFile = nil
            nextScheduledTrackIndex = -1

            let token = gaplessPreparationToken
            let expectedPlaybackGeneration = playbackGeneration
            let expectedCurrentIndex = currentIndex
            let nextTrackURL = nextTrack.url
            let nextTrackTitle = nextTrack.title

            deferredIOQueue.async { [weak self] in
                guard let self else { return }
                let openStart = CFAbsoluteTimeGetCurrent()
                do {
                    // Apply the same NAS copy logic as the primary load path so that
                    // gapless track boundaries are also free of render-thread NAS reads.
                    var gaplessTempURL: URL? = nil
                    let isLocalVolume = (try? nextTrackURL.resourceValues(
                        forKeys: [.volumeIsLocalKey]
                    ))?.volumeIsLocal ?? true

                    if !isLocalVolume {
                        let fileSize = (try? nextTrackURL.resourceValues(
                            forKeys: [.fileSizeKey]
                        ))?.fileSize ?? 0
                        if fileSize <= 300 * 1024 * 1024 {
                            let ext = nextTrackURL.pathExtension
                            let candidate = URL(fileURLWithPath: NSTemporaryDirectory())
                                .appendingPathComponent("nullplayer-\(UUID().uuidString).\(ext)")
                            try FileManager.default.copyItem(at: nextTrackURL, to: candidate)
                            NSLog("Gapless: Copied NAS '%@' to temp in %.3fs",
                                  nextTrackTitle, CFAbsoluteTimeGetCurrent() - openStart)
                            gaplessTempURL = candidate
                        }
                    }

                    let playbackURL = gaplessTempURL ?? nextTrackURL
                    let nextFile = try AVAudioFile(forReading: playbackURL)
                    let elapsed = CFAbsoluteTimeGetCurrent() - openStart
                    Log.audio.infoPublic("Gapless: Opened next track '\(nextTrackTitle)' in \(String(format: "%.3f", elapsed))s")
                    DispatchQueue.main.async { [weak self] in
                        guard let self else {
                            if let tmp = gaplessTempURL { try? FileManager.default.removeItem(at: tmp) }
                            return
                        }
                        guard self.gaplessPreparationToken == token,
                              self.playbackGeneration == expectedPlaybackGeneration,
                              self.currentIndex == expectedCurrentIndex,
                              self.gaplessPlaybackEnabled,
                              !self.sweetFadeEnabled,
                              !self.isCastingActive,
                              !self.isStreamingPlayback else {
                            if let tmp = gaplessTempURL { try? FileManager.default.removeItem(at: tmp) }
                            return
                        }

                        // Discard any previous pending gapless temp before storing the new one.
                        if let prev = self.tempGaplessFileURL { try? FileManager.default.removeItem(at: prev) }
                        self.tempGaplessFileURL = gaplessTempURL

                        let activePlayer = self.crossfadePlayerIsActive ? self.crossfadePlayerNode : self.playerNode
                        activePlayer.scheduleFile(nextFile, at: nil, completionHandler: nil)
                        self.nextScheduledFile = nextFile
                        self.nextScheduledTrackIndex = nextIndex
                        Log.audio.infoPublic("Gapless: Pre-scheduled next track: \(nextTrackTitle)")
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        guard self.gaplessPreparationToken == token else { return }
                        Log.audio.errorPublic("Gapless: Failed to pre-schedule next track: \(error.localizedDescription)")
                        self.nextScheduledFile = nil
                        self.nextScheduledTrackIndex = -1
                    }
                }
            }
        }
    }
    
    /// Calculate the index of the next track based on shuffle/repeat settings
    private func calculateNextTrackIndex() -> Int {
        guard !playlist.isEmpty else { return -1 }
        
        if shuffleEnabled {
            return peekNextShuffleIndexForPlayback() ?? -1
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
            Log.audio.infoPublic("Sweet Fades: Skipping crossfade - repeat single mode")
            return
        }
        
        let nextIndex = calculateNextTrackIndex()
        guard nextIndex >= 0 && nextIndex < playlist.count else {
            Log.audio.infoPublic("Sweet Fades: No next track available")
            return
        }
        
        let nextTrack = playlist[nextIndex]
        
        // Check if next track is same source type (can't crossfade mixed sources)
        let currentIsStreaming = isStreamingPlayback
        let nextIsStreaming = nextTrack.url.scheme == "http" || nextTrack.url.scheme == "https"
        
        guard currentIsStreaming == nextIsStreaming else {
            Log.audio.infoPublic("Sweet Fades: Skipping crossfade - mixed source types")
            return
        }
        
        // Check track duration is sufficient (must be at least 2x fade duration)
        if let nextDuration = nextTrack.duration, nextDuration < sweetFadeDuration * 2 {
            Log.audio.infoPublic("Sweet Fades: Skipping crossfade - next track too short (\(String(format: "%.1f", nextDuration))s < \(String(format: "%.1f", sweetFadeDuration * 2))s)")
            return
        }
        
        isCrossfading = true
        crossfadeTargetIndex = nextIndex
        Log.audio.infoPublic("Sweet Fades: Starting crossfade to '\(nextTrack.title)'")
        
        if isStreamingPlayback {
            startStreamingCrossfade(to: nextTrack, nextIndex: nextIndex)
        } else {
            startLocalCrossfade(to: nextTrack, nextIndex: nextIndex)
        }
    }
    
    private func startLocalCrossfade(to nextTrack: Track, nextIndex: Int) {
        // Open the next track's file off the main thread — synchronous AVAudioFile opens
        // on NAS/network volumes block the main thread for seconds.
        // isCrossfading = true was already set by startCrossfade() before calling us,
        // so the periodic timer cannot start a duplicate crossfade while the open is in flight.
        crossfadeFileLoadToken &+= 1
        let token = crossfadeFileLoadToken

        deferredIOQueue.async { [weak self] in
            guard let self else { return }
            do {
                let nextFile = try AVAudioFile(forReading: nextTrack.url)
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.crossfadeFileLoadToken == token,
                          self.isCrossfading else { return }

                    // Invalidate the outgoing player's completion handler from loadLocalTrack()
                    // so it doesn't call trackDidFinish() when the outgoing track's audio finishes
                    self.playbackGeneration += 1
                    let currentGeneration = self.playbackGeneration

                    // Determine which player is currently active and which will be the crossfade target
                    let outgoingPlayer = self.crossfadePlayerIsActive ? self.crossfadePlayerNode : self.playerNode
                    let incomingPlayer = self.crossfadePlayerIsActive ? self.playerNode : self.crossfadePlayerNode

                    // Schedule on incoming player with proper completion handler
                    // Uses .dataPlayedBack so trackDidFinish fires when this track ends after crossfade
                    incomingPlayer.stop()
                    incomingPlayer.volume = 0
                    incomingPlayer.scheduleFile(nextFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.handlePlaybackComplete(generation: currentGeneration)
                        }
                    }

                    // Start the incoming player
                    incomingPlayer.play()

                    // Store the file for later
                    if self.crossfadePlayerIsActive {
                        self.audioFile = nextFile
                    } else {
                        self.crossfadeAudioFile = nextFile
                    }

                    // Start volume ramp
                    self.startCrossfadeVolumeRamp(
                        outgoingVolume: { v in outgoingPlayer.volume = v },
                        incomingVolume: { v in incomingPlayer.volume = v },
                        completion: { [weak self] in
                            self?.completeCrossfade(nextFile: nextFile, nextIndex: nextIndex)
                        }
                    )
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.crossfadeFileLoadToken == token,
                          self.isCrossfading else { return }
                    Log.audio.errorPublic("Sweet Fades: Failed to load next track: \(error.localizedDescription)")
                    self.isCrossfading = false
                    self.crossfadeTargetIndex = -1
                }
            }
        }
    }
    
    /// Start crossfade for streaming playback
    private func startStreamingCrossfade(to nextTrack: Track, nextIndex: Int) {
        // Invalidate any stale completion handlers (defense-in-depth for streaming path)
        playbackGeneration += 1
        
        // Rebuild the secondary streaming player for each crossfade.
        // Reusing a previously stopped AudioStreaming graph can leave AVAudioUnitEQ
        // parameter objects pointing at invalid state, which crashes during EQ sync.
        crossfadeStreamingPlayer?.delegate = nil
        crossfadeStreamingPlayer?.stop()
        crossfadeStreamingPlayer = StreamingAudioPlayer(eqConfiguration: activeEQConfiguration)
        // Note: We don't set delegate - we handle state internally during crossfade
        
        // Sync EQ settings to crossfade player
        syncEQToStreamingPlayer(crossfadeStreamingPlayer)
        
        // Start next track at volume 0
        crossfadeStreamingPlayer?.volume = 0
        crossfadeStreamingPlayer?.play(url: nextTrack.url)
        
        // Start volume ramp - multiply crossfade values by master volume
        // (unlike local playback where mainMixerNode handles master volume,
        // streaming players need volume incorporated into the crossfade)
        let masterVolume = volume
        startCrossfadeVolumeRamp(
            outgoingVolume: { [weak self] v in
                guard let self, self.isCrossfading else { return }
                self.streamingPlayer?.volume = masterVolume * v
            },
            incomingVolume: { [weak self] v in
                guard let self, self.isCrossfading else { return }
                self.crossfadeStreamingPlayer?.volume = masterVolume * v
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
        // Note: Crossfade ramps between 0 and 1.0 (unity) for relative mixing
        // Actual output volume is controlled by mainMixerNode.outputVolume
        
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            let progress = min(1.0, elapsed / fadeDuration)
            
            // Normalized equal-power crossfade to prevent volume peaks
            // Standard equal-power: cos(angle) + sin(angle) peaks at 1.414 at midpoint
            // We normalize so the sum is always 1.0, preventing clipping while
            // maintaining the smooth perceptual balance of equal-power curves
            let angle = progress * .pi / 2
            let rawOut = Float(cos(angle))
            let rawIn = Float(sin(angle))
            let sum = rawOut + rawIn  // Ranges from 1.0 to ~1.414 back to 1.0
            let outVol = rawOut / sum  // Normalized: sum always = 1.0
            let inVol = rawIn / sum
            
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
        
        // Ensure the now-active player is at unity volume
        // (mainMixerNode.outputVolume controls actual output level)
        let activePlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
        activePlayer.volume = 1.0
        
        // Record outgoing track to radio history (track finished via crossfade)
        if let outgoingTrack = currentTrack {
            switch outgoingTrack.playHistorySource {
            case .plex:      PlexRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .subsonic:  SubsonicRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .jellyfin:  JellyfinRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .emby:      EmbyRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .local, .radio:
                LocalRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            }
        }

        // Record play event to analytics (track finished via crossfade)
        if let outgoingTrack = currentTrack {
            let trackId = outgoingTrack.playHistoryTrackIdentifier
            let eventId = MediaLibraryStore.shared.insertPlayEvent(
                trackId: trackId,
                trackURL: outgoingTrack.url.isFileURL ? outgoingTrack.url.absoluteString : nil,
                title: outgoingTrack.title,
                artist: outgoingTrack.artist,
                album: outgoingTrack.album,
                genre: outgoingTrack.genre,
                playedAt: Date(),
                durationListened: outgoingTrack.duration ?? 0,
                source: outgoingTrack.playHistorySource.rawValue,
                skipped: false)
            if let eventId, outgoingTrack.genre == nil || outgoingTrack.genre?.isEmpty == true {
                Task.detached(priority: .utility) { [track = outgoingTrack] in
                    await GenreDiscoveryService.shared.enrichPlayEvent(
                        id: eventId, title: track.title, artist: track.artist, album: track.album)
                }
            }
        }

        // Update state
        audioFile = nextFile
        currentIndex = nextIndex
        commitShufflePlaybackAdvance(to: nextIndex)
        currentTrack = playlist[nextIndex]
        _currentTime = 0
        lastReportedTime = 0
        playbackStartDate = Date()
        suspendedLocalPlaybackClockForSleep = false
        
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
            
            // Report track start to Jellyfin
            if let jellyfinId = track.jellyfinId,
               let serverId = track.jellyfinServerId,
               let trackDuration = track.duration {
                JellyfinPlaybackReporter.shared.trackStarted(trackId: jellyfinId, serverId: serverId, duration: trackDuration)
            }

            // Report track start to Emby
            if let embyId = track.embyId,
               let serverId = track.embyServerId,
               let trackDuration = track.duration {
                EmbyPlaybackReporter.shared.trackStarted(trackId: embyId, serverId: serverId, duration: trackDuration)
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
        
        Log.audio.infoPublic("Sweet Fades: Crossfade complete, now playing: \(currentTrack?.title ?? "Unknown")")
    }
    
    /// Complete streaming crossfade
    private func completeStreamingCrossfade(nextIndex: Int) {
        // Nil delegate BEFORE stopping to prevent stale synchronous callbacks
        // (stop can trigger .stopped state change on the delegate)
        streamingPlayer?.delegate = nil
        streamingPlayer?.stop()
        
        // Swap players - crossfade player becomes primary
        let oldPrimary = streamingPlayer
        streamingPlayer = crossfadeStreamingPlayer
        crossfadeStreamingPlayer = oldPrimary
        
        // Set delegate on new primary player
        streamingPlayer?.delegate = self
        streamingPlayer?.spectrumNeeded = spectrumNeeded
        streamingPlayer?.waveformNeeded = waveformNeeded
        streamingPlayer?.isModernUIEnabled = isModernUIEnabled
        // crossfadeStreamingPlayer (old primary) already has nil delegate from above
        
        // Restore primary player to master volume (crossfade ended at masterVolume * 1.0)
        streamingPlayer?.volume = volume
        
        // Record outgoing track to radio history (track finished via streaming crossfade)
        if let outgoingTrack = currentTrack {
            switch outgoingTrack.playHistorySource {
            case .plex:      PlexRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .subsonic:  SubsonicRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .jellyfin:  JellyfinRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .emby:      EmbyRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            case .local, .radio:
                LocalRadioHistory.shared.recordTrackPlayed(outgoingTrack)
            }
        }

        // Record play event to analytics (track finished via streaming crossfade)
        if let outgoingTrack = currentTrack {
            let trackId = outgoingTrack.playHistoryTrackIdentifier
            let eventId = MediaLibraryStore.shared.insertPlayEvent(
                trackId: trackId,
                trackURL: outgoingTrack.url.isFileURL ? outgoingTrack.url.absoluteString : nil,
                title: outgoingTrack.title,
                artist: outgoingTrack.artist,
                album: outgoingTrack.album,
                genre: outgoingTrack.genre,
                playedAt: Date(),
                durationListened: outgoingTrack.duration ?? 0,
                source: outgoingTrack.playHistorySource.rawValue,
                skipped: false)
            if let eventId, outgoingTrack.genre == nil || outgoingTrack.genre?.isEmpty == true {
                Task.detached(priority: .utility) { [track = outgoingTrack] in
                    await GenreDiscoveryService.shared.enrichPlayEvent(
                        id: eventId, title: track.title, artist: track.artist, album: track.album)
                }
            }
        }

        // Update state
        currentIndex = nextIndex
        commitShufflePlaybackAdvance(to: nextIndex)
        currentTrack = playlist[nextIndex]
        _currentTime = 0
        lastReportedTime = 0
        playbackStartDate = Date()
        suspendedLocalPlaybackClockForSleep = false

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

            // Report track start to Jellyfin
            if let jellyfinId = track.jellyfinId,
               let serverId = track.jellyfinServerId,
               let trackDuration = track.duration {
                JellyfinPlaybackReporter.shared.trackStarted(trackId: jellyfinId, serverId: serverId, duration: trackDuration)
            }

            // Report track start to Emby
            if let embyId = track.embyId,
               let serverId = track.embyServerId,
               let trackDuration = track.duration {
                EmbyPlaybackReporter.shared.trackStarted(trackId: embyId, serverId: serverId, duration: trackDuration)
            }
        }

        Log.audio.infoPublic("Sweet Fades: Streaming crossfade complete, now playing: \(currentTrack?.title ?? "Unknown")")
    }
    
    /// Cancel an in-progress crossfade (called on seek, skip, stop)
    private func cancelCrossfade() {
        guard isCrossfading else { return }
        
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        
        // Invalidate any completion handlers from the crossfade immediately
        // (defense-in-depth: callers also increment generation, but this closes any gap)
        playbackGeneration += 1
        
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
            
            // Restore outgoing player volume to unity (mainMixerNode controls actual volume)
            let outgoingPlayer = crossfadePlayerIsActive ? crossfadePlayerNode : playerNode
            outgoingPlayer.volume = 1.0
        }
        
        isCrossfading = false
        crossfadeFileLoadToken &+= 1  // cancel any in-flight deferredIOQueue file open
        crossfadeTargetIndex = -1
        // Reset to playerNode as primary (crossfade was incomplete, outgoing player continues)
        crossfadePlayerIsActive = false
        Log.audio.infoPublic("Sweet Fades: Crossfade cancelled")
    }

    /// Reset all crossfade internals and restore direct local playback defaults.
    /// This is used when loading/stopping tracks to prevent stale crossfade state
    /// from leaving local playback silent after rapid source switches.
    private func resetLocalCrossfadeStateForDirectPlayback() {
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        isCrossfading = false
        crossfadeFileLoadToken &+= 1  // cancel any in-flight deferredIOQueue file open
        crossfadeTargetIndex = -1

        crossfadeStreamingPlayer?.stop()
        crossfadeStreamingPlayer?.volume = 0
        crossfadePlayerNode.stop()
        crossfadePlayerNode.volume = 0
        crossfadeAudioFile = nil
        crossfadePlayerIsActive = false

        // Local playback is scheduled on playerNode; keep it at unity gain.
        playerNode.volume = 1.0
    }
    
    // MARK: - Volume Normalization
    
    /// Analyze audio file and apply normalization gain asynchronously.
    /// Uses a separate file handle so playback startup stays responsive.
    private func analyzeAndApplyNormalization(file: AVAudioFile, generation: Int? = nil) {
        guard volumeNormalizationEnabled else {
            normalizationGain = 1.0
            applyNormalizationGain()
            return
        }

        let analysisURL = file.url
        let expectedGeneration = generation ?? playbackGeneration
        normalizationGain = 1.0
        applyNormalizationGain()

        normalizationAnalysisToken &+= 1
        let token = normalizationAnalysisToken

        deferredIOQueue.async { [weak self] in
            guard let self else { return }
            Log.audio.infoPublic("Normalization: starting analysis for '\(analysisURL.lastPathComponent)'")
            let analysisStart = CFAbsoluteTimeGetCurrent()
            do {
                let analysisFile = try AVAudioFile(forReading: analysisURL)
                let openElapsed = CFAbsoluteTimeGetCurrent() - analysisStart
                Log.audio.infoPublic("Normalization: opened '\(analysisURL.lastPathComponent)' in \(String(format: "%.3f", openElapsed))s")

                let (peakDB, rmsDB) = self.analyzeAudioLevels(file: analysisFile)
                let totalElapsed = CFAbsoluteTimeGetCurrent() - analysisStart
                Log.audio.infoPublic("Normalization: analysis for '\(analysisURL.lastPathComponent)' complete in \(String(format: "%.3f", totalElapsed))s total (open=\(String(format: "%.3f", openElapsed))s)")
                let gain = self.calculateNormalizationGain(peakDB: peakDB, rmsDB: rmsDB)

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.normalizationAnalysisToken == token,
                          self.volumeNormalizationEnabled,
                          self.playbackGeneration == expectedGeneration,
                          self.currentTrack?.url == analysisURL,
                          !self.isStreamingPlayback else { return }
                    self.normalizationGain = gain
                    self.applyNormalizationGain()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.normalizationAnalysisToken == token,
                          self.currentTrack?.url == analysisURL else { return }
                    Log.audio.infoPublic("Normalization: analysis skipped for '\(analysisURL.lastPathComponent)': \(error.localizedDescription)")
                    self.normalizationGain = 1.0
                    self.applyNormalizationGain()
                }
            }
        }
    }

    private func calculateNormalizationGain(peakDB: Float, rmsDB: Float) -> Float {
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

        let gain = pow(10.0, finalGainDB / 20.0)
        NSLog("Normalization: peak=%.1fdB, rms=%.1fdB, gain=%.1fdB (%.2fx)",
              peakDB, rmsDB, finalGainDB, gain)
        return gain
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
            let readStart = CFAbsoluteTimeGetCurrent()
            try file.read(into: buffer)
            let readElapsed = CFAbsoluteTimeGetCurrent() - readStart
            NSLog("Normalization: read %d frames (%.1fs audio) from '%@' in %.3fs",
                  frameCount, Double(frameCount) / format.sampleRate,
                  file.url.lastPathComponent, readElapsed)
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
        // Apply combined volume + normalization to mainMixerNode
        // This is AFTER the visualization tap, so spectrum is volume-independent
        let finalVolume = max(0, min(1, volume * normalizationGain))
        engine.mainMixerNode.outputVolume = finalVolume
        
        // Note: playerNode stays at unity (1.0) for volume-independent visualization
        // Note: For streaming, normalization is not applied (would require re-analysis)
    }
    
    // MARK: - Equalizer
    
    /// Set EQ band gain (-12 to +12 dB)
    func setEQBand(_ band: Int, gain: Float) {
        guard band >= 0 && band < activeEQConfiguration.bandCount else { return }
        let clampedGain = max(-12, min(12, gain))
        eqNode.bands[band].gain = clampedGain
        // Sync to streaming player
        streamingPlayer?.setEQBand(band, gain: clampedGain)
    }
    
    /// Get EQ band gain
    func getEQBand(_ band: Int) -> Float {
        guard band >= 0 && band < activeEQConfiguration.bandCount else { return 0 }
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
        // Get the actual device ID to use
        let targetDeviceID: AudioDeviceID
        if let deviceID = deviceID {
            targetDeviceID = deviceID
        } else {
            // Use system default
            guard let defaultID = AudioOutputManager.shared.getDefaultOutputDeviceID() else {
                Log.audio.errorPublic("AudioEngine: Failed to get default output device")
                return false
            }
            targetDeviceID = defaultID
        }
        
        // Get the audio unit from the output node
        guard let outputUnit = engine.outputNode.audioUnit else {
            Log.audio.errorPublic("AudioEngine: Failed to get output audio unit")
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
            Log.audio.errorPublic("AudioEngine: Failed to set output device: \(status)")
            return false
        }
        
        currentOutputDeviceID = deviceID
        
        // Update the AudioOutputManager's selection
        AudioOutputManager.shared.selectDevice(deviceID)
        
        // Save device UID for restoration on next launch
        if let deviceID = deviceID,
           let device = AudioOutputManager.shared.outputDevices.first(where: { $0.id == deviceID }) {
            UserDefaults.standard.set(device.uid, forKey: UserDefaults.Keys.selectedOutputDeviceUID)
            Log.audio.infoPublic("AudioEngine: Saved output device preference: \(device.name) (\(device.uid))")
        } else {
            // System default - clear the preference
            UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.selectedOutputDeviceUID)
            Log.audio.infoPublic("AudioEngine: Cleared output device preference (using system default)")
        }
        
        // The AVAudioEngineConfigurationChange notification will fire if the format changed,
        // and handleAudioConfigChange will rebuild the audio graph and resume playback
        
        return true
    }
    
    /// Get the current output device
    func getCurrentOutputDevice() -> AudioOutputDevice? {
        guard let deviceID = currentOutputDeviceID else { return nil }
        return AudioOutputManager.shared.outputDevices.first { $0.id == deviceID }
    }
    
    
    // MARK: - Playlist Management
    
    func clearPlaylist() {
        Log.audio.infoPublic("clearPlaylist: isStreamingPlayback=\(isStreamingPlayback)")
        placeholderResolutionTasks.values.forEach { $0.cancel() }
        placeholderResolutionTasks.removeAll()
        staleStreamingRefreshRetriedServiceIdentity = nil
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
        
        // Report stop to Jellyfin
        JellyfinPlaybackReporter.shared.trackStopped()

        // Report stop to Emby
        EmbyPlaybackReporter.shared.trackStopped()

        Log.audio.infoPublic("clearPlaylist: done, playlist count=\(playlist.count)")
        clearShufflePlaybackState()
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
                invalidateShufflePlaybackStateAfterPlaylistMutation()
                loadTrack(at: currentIndex)
            } else {
                currentIndex = -1
                clearShufflePlaybackState()
            }
        } else if index < currentIndex {
            currentIndex -= 1
            invalidateShufflePlaybackStateAfterPlaylistMutation()
        } else {
            invalidateShufflePlaybackStateAfterPlaylistMutation()
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
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        
        delegate?.audioEngineDidChangePlaylist()
    }
    
    func playTrack(at index: Int) {
        // Cancel any in-progress crossfade
        cancelCrossfade()
        
        guard index >= 0 && index < playlist.count else {
            Log.audio.infoPublic("playTrack: invalid index \(index) (playlist count: \(playlist.count))")
            return
        }
        
        // When casting local files, block rapid clicks - only accept if not already casting
        if isCastingActive && CastManager.shared.isLocalFileCastInProgress() {
            Log.audio.infoPublic("AudioEngine: playTrack() blocked - local file cast in progress")
            return
        }
        
        Log.audio.infoPublic("playTrack: playing track at index \(index)")
        
        // Check if we're currently casting
        let wasCasting = isCastingActive
        
        currentIndex = index
        if shuffleEnabled {
            anchorShufflePlaybackOrder(at: index)
        } else {
            alignShufflePlaybackPositionForSelectedTrack(index)
        }
        staleStreamingRefreshRetriedServiceIdentity = nil
        let track = playlist[index]

        if track.isStreamingPlaceholder {
            currentTrack = track
            _currentTime = 0
            lastReportedTime = 0
            state = .stopped
            resolvePlaceholderTrackAndOptionallyPlay(at: index, autoPlayOnSuccess: true)
            return
        }
        
        if wasCasting {
            // When casting, don't set up local playback - just update track metadata and cast
            let isLocalFile = track.url.scheme != "http" && track.url.scheme != "https"
            
            // For local files, defer UI update until cast completes (prevents UI jumping during rapid clicks)
            // For streaming, update immediately since there's no async delay
            if !isLocalFile {
                currentTrack = track
            }
            _currentTime = 0
            lastReportedTime = 0
            
            Log.audio.infoPublic("playTrack: casting is active, casting track at index \(index) (local=\(isLocalFile ? 1 : 0))")
            Task {
                do {
                    try await CastManager.shared.castNewTrack(track)
                    // For local files, update UI after successful cast
                    if isLocalFile {
                        await MainActor.run {
                            self.currentTrack = track
                        }
                    }
                } catch {
                    Log.audio.errorPublic("playTrack: failed to cast track: \(error.localizedDescription)")
                    // Fall back to local playback if casting fails
                    await MainActor.run {
                        self.loadTrack(at: index)
                        self.play()
                    }
                }
            }
        } else {
            _ = stopRadioIfLoadingNonRadioContent(
                incomingTrackURL: track.url,
                context: "playTrack"
            )

            let isDirectLocalAudio = track.url.isFileURL && track.mediaType != .video
            if isDirectLocalAudio {
                loadLocalTrackForImmediatePlayback(track, at: index)
            } else {
                loadTrack(at: index)
                play()
            }
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
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        
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
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        
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
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        
        delegate?.audioEngineDidChangePlaylist()
    }

#if DEBUG
    func debugStartShuffleCycleForTesting(at index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        currentIndex = index
        currentTrack = playlist[index]
        rebuildShufflePlaybackOrder(anchoredAt: index)
    }

    func debugStartPreferredShuffleCycleForTesting(_ indices: [Int]) -> Int? {
        let selectedIndex = startShufflePlaybackCycle(preferredIndices: indices)
        if let selectedIndex {
            currentIndex = selectedIndex
            currentTrack = playlist[selectedIndex]
        }
        return selectedIndex
    }

    func debugSelectTrackForShuffleTesting(_ index: Int) {
        guard index >= 0 && index < playlist.count else { return }
        currentIndex = index
        currentTrack = playlist[index]
        if shuffleEnabled {
            anchorShufflePlaybackOrder(at: index)
        } else {
            alignShufflePlaybackPositionForSelectedTrack(index)
        }
    }

    func debugPeekNextShuffleIndexForPlayback() -> Int? {
        peekNextShuffleIndexForPlayback()
    }

    func debugAdvanceShuffleIndexForPlayback() -> Int? {
        guard let nextIndex = nextShuffleIndexForPlaybackAdvance() else { return nil }
        currentIndex = nextIndex
        currentTrack = playlist[nextIndex]
        return nextIndex
    }
#endif
}

// MARK: - StreamingAudioPlayerDelegate

extension AudioEngine: StreamingAudioPlayerDelegate {
    func streamingPlayerDidChangeState(_ state: AudioPlayerState) {
        // During crossfade, ignore stopped/error from the outgoing player
        // to prevent corrupting playback state mid-crossfade
        if isCrossfading {
            switch state {
            case .stopped, .error:
                Log.audio.infoPublic("AudioEngine: Ignoring streaming state \(String(describing: state)) during crossfade")
                return
            default:
                break
            }
        }
        
        // Map AudioStreaming state to our PlaybackState
        switch state {
        case .playing:
            self.state = .playing
            playbackStartDate = Date()
            suspendedLocalPlaybackClockForSleep = false
            isSeekingStreaming = false  // Clear seeking flag on successful playback
            
            // Notify RadioManager that stream connected successfully
            if RadioManager.shared.isActive {
                RadioManager.shared.streamDidConnect()
            }
        case .paused:
            self.state = .paused
        case .stopped:
            self.state = .stopped
            isSeekingStreaming = false
            // Cancel any pending reset work item
            streamingSeekResetWorkItem?.cancel()
            streamingSeekResetWorkItem = nil
        case .error:
            Log.audio.infoPublic("AudioEngine: Streaming player entered error state")
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
            Log.audio.infoPublic("AudioEngine: Ignoring EOF during track switch")
            return
        }
        
        // During crossfade, the outgoing streaming player fires EOF - ignore it
        // (the crossfade handles the transition via completeStreamingCrossfade)
        guard !isCrossfading else {
            Log.audio.infoPublic("AudioEngine: Ignoring streaming EOF during crossfade")
            return
        }
        
        // For radio streams, don't advance - let RadioManager handle reconnection
        if RadioManager.shared.isActive {
            Log.audio.infoPublic("AudioEngine: Radio stream ended - delegating to RadioManager for reconnect")
            RadioManager.shared.streamDidDisconnect(error: nil)
            return
        }
        
        Log.audio.infoPublic("AudioEngine: Streaming track finished, advancing playlist")
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
        pcmUserInfo["pcm"] = pcmData
        pcmUserInfo["sampleRate"] = pcmSampleRate
        NotificationCenter.default.post(
            name: .audioPCMDataUpdated,
            object: self,
            userInfo: pcmUserInfo
        )
    }
    
    func streamingPlayerDidDetectFormat(sampleRate: Int, channels: Int) {
        // Update current track with format info detected from the stream
        // This fills in sample rate for Plex tracks which don't have it in metadata
        guard let track = currentTrack else { return }
        
        // Only update if not already set
        if track.sampleRate == nil || track.channels == nil {
            Log.audio.infoPublic("AudioEngine: Detected stream format - sampleRate: \(sampleRate), channels: \(channels)")
            
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
                plexRatingKey: track.plexRatingKey,
                plexServerId: track.plexServerId,
                subsonicId: track.subsonicId,
                subsonicServerId: track.subsonicServerId,
                jellyfinId: track.jellyfinId,
                jellyfinServerId: track.jellyfinServerId,
                embyId: track.embyId,
                embyServerId: track.embyServerId,
                artworkThumb: track.artworkThumb,
                mediaType: track.mediaType,
                genre: track.genre,
                contentType: track.contentType
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
    
    func streamingPlayerDidEncounterError(_ error: AudioPlayerError) {
        // Handle streaming errors gracefully
        // The error callback fires BEFORE the state changes to .error
        // so we handle recovery here

        // AudioStreaming fires this delegate method multiple times for a single error.
        // If a refresh is already in-flight for this track, suppress duplicate callbacks.
        if let identity = currentTrack?.streamingServiceIdentity,
           staleStreamingRefreshRetriedServiceIdentity == identity {
            Log.audio.infoPublic("AudioEngine: Ignoring duplicate streaming error - \(String(describing: error))")
            return
        }

        Log.audio.infoPublic("AudioEngine: Streaming error - \(String(describing: error))")

        // Check if this is a radio stream - let RadioManager handle reconnection
        if RadioManager.shared.isActive {
            Log.audio.infoPublic("AudioEngine: Radio stream error - delegating to RadioManager for reconnect")
            RadioManager.shared.streamDidDisconnect(error: error)
            return
        }

        let errorDescription = String(describing: error)
        if Self.shouldAttemptStreamingURLRefreshAfterError(
            track: currentTrack,
            isRadioActive: RadioManager.shared.isActive,
            previouslyRetriedServiceIdentity: staleStreamingRefreshRetriedServiceIdentity
        ), let failingTrack = currentTrack,
           let retryIdentity = failingTrack.streamingServiceIdentity,
           currentIndex >= 0 {
            staleStreamingRefreshRetriedServiceIdentity = retryIdentity
            let retryIndex = currentIndex
            Log.audio.infoPublic("AudioEngine: attempting one-time stream URL refresh for '\(failingTrack.title)'")

            Task { [weak self] in
                guard let self else { return }
                if let refreshedTrack = await StreamingTrackResolver.resolve(failingTrack),
                   refreshedTrack.url.path != failingTrack.url.path {
                    await MainActor.run {
                        guard retryIndex >= 0 && retryIndex < self.playlist.count else { return }
                        // Ensure we're still looking at the same logical service track.
                        guard self.playlist[retryIndex].streamingServiceIdentity == retryIdentity else { return }
                        self.replaceTrack(at: retryIndex, with: refreshedTrack)
                        if self.currentIndex == retryIndex {
                            self.loadTrack(at: retryIndex)
                        }
                    }
                } else {
                    // Resolve returned nil or the same file path — token refresh won't help
                    // (file is corrupt or permanently unavailable). Advance to next track.
                    await MainActor.run {
                        self.handleStreamingErrorFallback(error, errorDescription: errorDescription)
                    }
                }
            }
            return
        }

        handleStreamingErrorFallback(error, errorDescription: errorDescription)
    }

    private func handleStreamingErrorFallback(_ error: AudioPlayerError, errorDescription: String) {
        let isPacketTableError = errorDescription.contains("packet table")
            || errorDescription.contains("streamParseBytesFailure")
        let isCodecError = errorDescription.contains("codecError")

        if isPacketTableError || isCodecError {
            if isPacketTableError {
                Log.audio.infoPublic("AudioEngine: M4A parsing error - file may not be optimized for streaming")
            } else {
                Log.audio.infoPublic("AudioEngine: Codec error - file is corrupt or unplayable, advancing")
            }

            // Show error in marquee briefly, then advance to next track
            if let track = currentTrack {
                let errorMessage = "Cannot play: \(track.title) (format not supported for streaming)"
                NotificationCenter.default.post(
                    name: .audioTrackDidFailToLoad,
                    object: self,
                    userInfo: ["track": track, "error": error, "message": errorMessage]
                )
            }

            // Advance to next track after a brief delay to let error state settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                // Only advance if we're still in error/stopped state
                if self.state == .stopped {
                    Log.audio.infoPublic("AudioEngine: Auto-advancing after streaming error")
                    self.next()
                }
            }
        }
    }
    
    func streamingPlayerDidReceiveMetadata(_ metadata: [String: String]) {
        // Forward ICY metadata to RadioManager for radio streams
        if RadioManager.shared.isActive {
            RadioManager.shared.streamDidReceiveMetadata(metadata)
        }
    }
}
