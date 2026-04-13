import Foundation
import NullPlayerCore

/// Platform-neutral playback facade that owns playlist state and delegates all media I/O
/// to an injected AudioBackend.
public final class AudioEngineFacade: AudioPlaybackProviding, AudioOutputRouting {
    public typealias PlaybackTrack = NullPlayerCore.Track

    // MARK: - Public state

    public weak var delegate: AudioEngineDelegate?

    public private(set) var state: PlaybackState = .stopped
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var playlist: [NullPlayerCore.Track] = []
    public private(set) var currentIndex: Int = -1

    public var currentTrack: NullPlayerCore.Track? {
        guard currentIndex >= 0, currentIndex < playlist.count else { return nil }
        return playlist[currentIndex]
    }

    public var volume: Float = 0.2 {
        didSet {
            volume = max(0, min(1, volume))
            guard loadToken != 0 else { return }
            backend.setVolume(volume, token: loadToken)
        }
    }

    public var balance: Float = 0 {
        didSet {
            balance = max(-1, min(1, balance))
            guard loadToken != 0 else { return }
            backend.setBalance(balance, token: loadToken)
        }
    }

    public var shuffleEnabled: Bool = false {
        didSet {
            if shuffleEnabled {
                rebuildShufflePlaybackOrder(anchoredAt: currentIndex)
            } else {
                clearShufflePlaybackState()
            }
        }
    }

    public var repeatEnabled: Bool = false

    public var gaplessPlaybackEnabled: Bool {
        get { preferences?.gaplessPlaybackEnabled ?? false }
        set {
            preferences?.gaplessPlaybackEnabled = newValue
            refreshNextTrackHint()
        }
    }

    public var volumeNormalizationEnabled: Bool {
        get { preferences?.volumeNormalizationEnabled ?? false }
        set { preferences?.volumeNormalizationEnabled = newValue }
    }

    public var sweetFadeEnabled: Bool {
        get { preferences?.sweetFadeEnabled ?? false }
        set { preferences?.sweetFadeEnabled = newValue }
    }

    public var sweetFadeDuration: TimeInterval {
        get { preferences?.sweetFadeDuration ?? 5.0 }
        set { preferences?.sweetFadeDuration = max(0.1, newValue) }
    }

    public var eqConfiguration: EQConfiguration {
        resolvedEQConfiguration
    }

    public private(set) var spectrumData: [Float] = Array(repeating: 0, count: 75)
    public private(set) var pcmData: [Float] = Array(repeating: 0, count: 512)

    // MARK: - AudioOutputRouting

    public var outputDevices: [AudioOutputDevice] { backend.outputDevices }
    public var currentOutputDevice: AudioOutputDevice? { backend.currentOutputDevice }

    // MARK: - Tokens

    public private(set) var loadToken: UInt64 = 0
    public private(set) var seekToken: UInt64 = 0

    public func isCurrentToken(_ token: UInt64) -> Bool {
        token != 0 && token == loadToken
    }

    // MARK: - Private state

    private let backend: any AudioBackend
    private weak var preferences: PlaybackPreferencesProviding?
    private weak var environment: PlaybackEnvironmentProviding?

    private let resolvedEQConfiguration: EQConfiguration
    private var eqBands: [Float]
    private var eqPreamp: Float = 0
    private var eqEnabled: Bool = false
    private let portableAnalysis = PortableAudioAnalysis()

    private var pendingSeekToken: UInt64?
    private var pendingSeekTarget: TimeInterval?

    private var pendingInitialLoadToken: UInt64?
    private var pendingInitialTime: (current: TimeInterval, duration: TimeInterval)?

    private var lastDeliveredTimeUpdate: Date = .distantPast
    private let delegateTimeCadence: TimeInterval = 0.1

    private var spectrumConsumers = Set<String>()
    private var waveformConsumers = Set<String>()

    /// Stable shuffled traversal state used for auto-advance and manual next/previous.
    private var shufflePlaybackOrder: [Int] = []
    private var shufflePlaybackPosition: Int = -1
    private var pendingRepeatShuffleOrder: [Int]?

    public init(
        backend: any AudioBackend,
        preferences: PlaybackPreferencesProviding? = nil,
        environment: PlaybackEnvironmentProviding? = nil
    ) {
        self.backend = backend
        self.preferences = preferences
        self.environment = environment

        let bandCount = max(1, backend.capabilities.eqBandCount)
        self.eqBands = Array(repeating: 0, count: bandCount)
        self.resolvedEQConfiguration = Self.makeEQConfiguration(forBandCount: bandCount)

        volume = max(0, min(1, volume))
        balance = max(-1, min(1, balance))

        self.backend.eventHandler = { [weak self] event in
            guard let self else { return }
            if Thread.isMainThread {
                self.handleBackendEvent(event)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.handleBackendEvent(event)
                }
            }
        }

        if let selectedOutput = preferences?.selectedOutputDevicePersistentID {
            _ = selectOutputDevice(persistentID: selectedOutput)
        }

        environment?.beginSleepObservation { [weak self] event in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch event {
                case .willSleep:
                    if self.state == .playing {
                        self.pause()
                    }
                case .didWake:
                    break
                }
            }
        }

        backend.prepare()
    }

    deinit {
        backend.eventHandler = nil
    }

    // MARK: - Transport

    public func play() {
        guard !playlist.isEmpty else { return }

        if currentIndex < 0 || currentIndex >= playlist.count {
            if shuffleEnabled {
                currentIndex = startShufflePlaybackCycle() ?? 0
            } else {
                currentIndex = 0
                alignShufflePlaybackPositionForSelectedTrack(currentIndex)
            }
            loadTrack(at: currentIndex, startPaused: false)
            return
        }

        if state == .stopped {
            loadTrack(at: currentIndex, startPaused: false)
            return
        }

        backend.play(token: loadToken)
    }

    public func pause() {
        guard loadToken != 0 else { return }
        backend.pause(token: loadToken)
    }

    public func stop() {
        guard loadToken != 0 else { return }
        backend.stop(token: loadToken)
    }

    public func next() {
        guard let nextIndex = nextIndexForManualNavigation() else { return }
        currentIndex = nextIndex
        loadTrack(at: currentIndex, startPaused: false)
    }

    public func previous() {
        guard let previousIndex = previousIndexForManualNavigation() else { return }
        currentIndex = previousIndex
        loadTrack(at: currentIndex, startPaused: false)
    }

    public func seek(to time: TimeInterval) {
        guard loadToken != 0 else { return }

        seekToken &+= 1
        let clampedTarget = max(0, min(time, duration > 0 ? duration : time))
        pendingSeekToken = seekToken
        pendingSeekTarget = clampedTarget
        backend.seek(to: clampedTarget, token: loadToken)
    }

    public func seekBy(seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    public func skipTracks(count: Int) {
        guard count != 0 else { return }
        guard !playlist.isEmpty else { return }

        if shuffleEnabled {
            for _ in 0..<abs(count) {
                if count > 0 { next() } else { previous() }
            }
            return
        }

        var newIndex = currentIndex + count
        while newIndex < 0 {
            newIndex += playlist.count
        }
        newIndex = newIndex % playlist.count
        playTrack(at: newIndex)
    }

    // MARK: - Playlist management

    public func loadFiles(_ urls: [URL]) {
        let tracks = urls.map { NullPlayerCore.Track(url: $0) }
        loadTracks(tracks)
    }

    public func loadTracks(_ tracks: [NullPlayerCore.Track]) {
        playlist = tracks
        if playlist.isEmpty {
            currentIndex = -1
            clearShufflePlaybackState()
            setStoppedAndNotify(timeReset: true)
            delegate?.audioEngineDidChangePlaylist()
            return
        }

        if shuffleEnabled {
            currentIndex = startShufflePlaybackCycle() ?? 0
        } else {
            currentIndex = 0
            alignShufflePlaybackPositionForSelectedTrack(currentIndex)
        }

        delegate?.audioEngineDidChangePlaylist()
        loadTrack(at: currentIndex, startPaused: false)
    }

    public func appendFiles(_ urls: [URL]) {
        appendTracks(urls.map { NullPlayerCore.Track(url: $0) })
    }

    public func appendTracks(_ tracks: [NullPlayerCore.Track]) {
        guard !tracks.isEmpty else { return }
        playlist.append(contentsOf: tracks)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
    }

    public func loadFolder(_ url: URL) {
        let discovered = discoverPlayableFiles(in: url)
        guard !discovered.isEmpty else { return }
        loadFiles(discovered)
    }

    public func clearPlaylist() {
        let previousToken = loadToken
        loadToken &+= 1
        seekToken &+= 1
        pendingSeekToken = nil
        pendingSeekTarget = nil
        pendingInitialLoadToken = nil
        pendingInitialTime = nil

        if previousToken != 0 {
            backend.stop(token: previousToken)
        }

        playlist.removeAll()
        currentIndex = -1
        clearShufflePlaybackState()
        setStoppedAndNotify(timeReset: true)
        delegate?.audioEngineDidChangeTrack(nil)
        delegate?.audioEngineDidChangePlaylist()
    }

    public func removeTrack(at index: Int) {
        guard index >= 0, index < playlist.count else { return }

        playlist.remove(at: index)

        if playlist.isEmpty {
            clearPlaylist()
            return
        }

        if index == currentIndex {
            currentIndex = min(index, playlist.count - 1)
            invalidateShufflePlaybackStateAfterPlaylistMutation()
            loadTrack(at: currentIndex, startPaused: state != .playing)
        } else if index < currentIndex {
            currentIndex -= 1
            invalidateShufflePlaybackStateAfterPlaylistMutation()
        } else {
            invalidateShufflePlaybackStateAfterPlaylistMutation()
        }

        delegate?.audioEngineDidChangePlaylist()
    }

    public func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < playlist.count else { return }
        guard destinationIndex >= 0, destinationIndex < playlist.count else { return }

        let track = playlist.remove(at: sourceIndex)
        playlist.insert(track, at: destinationIndex)

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

    public func playTrack(at index: Int) {
        guard index >= 0, index < playlist.count else { return }
        currentIndex = index
        if shuffleEnabled {
            anchorShufflePlaybackOrder(at: index)
        } else {
            alignShufflePlaybackPositionForSelectedTrack(index)
        }
        loadTrack(at: index, startPaused: false)
    }

    public func sortPlaylist(by criteria: PlaylistSortCriteria, ascending: Bool) {
        let currentTrackID = currentTrack?.id

        playlist.sort { lhs, rhs in
            let comparison: ComparisonResult
            switch criteria {
            case .title:
                comparison = lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle)
            case .filename:
                comparison = lhs.url.lastPathComponent.localizedCaseInsensitiveCompare(rhs.url.lastPathComponent)
            case .path:
                comparison = lhs.url.path.localizedCaseInsensitiveCompare(rhs.url.path)
            case .duration:
                let lhsDuration = lhs.duration ?? 0
                let rhsDuration = rhs.duration ?? 0
                comparison = lhsDuration < rhsDuration ? .orderedAscending : (lhsDuration > rhsDuration ? .orderedDescending : .orderedSame)
            case .artist:
                comparison = (lhs.artist ?? "").localizedCaseInsensitiveCompare(rhs.artist ?? "")
            case .album:
                comparison = (lhs.album ?? "").localizedCaseInsensitiveCompare(rhs.album ?? "")
            }
            return ascending ? (comparison == .orderedAscending) : (comparison == .orderedDescending)
        }

        restoreCurrentIndex(afterReorderingTrackID: currentTrackID)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
    }

    public func shufflePlaylist() {
        let currentTrackID = currentTrack?.id
        playlist.shuffle()
        restoreCurrentIndex(afterReorderingTrackID: currentTrackID)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
    }

    public func reversePlaylist() {
        let currentTrackID = currentTrack?.id
        playlist.reverse()
        restoreCurrentIndex(afterReorderingTrackID: currentTrackID)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
    }

    public func replaceTrack(at index: Int, with track: NullPlayerCore.Track) {
        guard index >= 0, index < playlist.count else { return }
        playlist[index] = track
        if index == currentIndex {
            duration = track.duration ?? duration
        }
        delegate?.audioEngineDidChangePlaylist()
    }

    public func insertTracksAfterCurrent(_ tracks: [NullPlayerCore.Track], startPlaybackIfEmpty: Bool) {
        guard !tracks.isEmpty else { return }

        let wasEmpty = playlist.isEmpty
        let insertIndex = currentIndex >= 0 ? currentIndex + 1 : 0

        playlist.insert(contentsOf: tracks, at: insertIndex)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()

        if wasEmpty && startPlaybackIfEmpty {
            playTrack(at: 0)
        }
    }

    public func playNow(_ tracks: [NullPlayerCore.Track]) {
        guard !tracks.isEmpty else { return }

        if playlist.isEmpty {
            loadTracks(tracks)
            return
        }

        let insertIndex = currentIndex >= 0 ? currentIndex + 1 : 0
        playlist.insert(contentsOf: tracks, at: insertIndex)
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        delegate?.audioEngineDidChangePlaylist()
        playTrack(at: insertIndex)
    }

    public func setPlaylistTracks(_ tracks: [NullPlayerCore.Track]) {
        playlist = tracks
        currentIndex = -1
        invalidateShufflePlaybackStateAfterPlaylistMutation()
        setStoppedAndNotify(timeReset: true)
        delegate?.audioEngineDidChangePlaylist()
    }

    public func setPlaylistFiles(_ urls: [URL]) {
        setPlaylistTracks(urls.map { NullPlayerCore.Track(url: $0) })
    }

    public func selectTrackForDisplay(at index: Int) {
        guard index >= 0, index < playlist.count else { return }
        currentIndex = index
        currentTime = 0
        duration = playlist[index].duration ?? 0
        state = .stopped
        delegate?.audioEngineDidChangeTrack(currentTrack)
        delegate?.audioEngineDidUpdateTime(current: 0, duration: duration)
        delegate?.audioEngineDidChangeState(.stopped)
    }

    // MARK: - EQ

    public func setEQBand(_ band: Int, gain: Float) {
        guard band >= 0, band < eqBands.count else { return }
        eqBands[band] = max(-12, min(12, gain))
        pushEQSettings()
    }

    public func getEQBand(_ band: Int) -> Float {
        guard band >= 0, band < eqBands.count else { return 0 }
        return eqBands[band]
    }

    public func setPreamp(_ gain: Float) {
        eqPreamp = max(-12, min(12, gain))
        pushEQSettings()
    }

    public func getPreamp() -> Float {
        eqPreamp
    }

    public func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        pushEQSettings()
    }

    public func isEQEnabled() -> Bool {
        eqEnabled
    }

    // MARK: - Spectrum consumers

    public func addSpectrumConsumer(_ id: String) {
        spectrumConsumers.insert(id)
    }

    public func removeSpectrumConsumer(_ id: String) {
        spectrumConsumers.remove(id)
    }

    public func addWaveformConsumer(_ id: String) {
        waveformConsumers.insert(id)
    }

    public func removeWaveformConsumer(_ id: String) {
        waveformConsumers.remove(id)
    }

    // MARK: - Routing

    public func refreshOutputs() {
        backend.refreshOutputs()
    }

    @discardableResult
    public func selectOutputDevice(persistentID: String?) -> Bool {
        guard backend.capabilities.supportsOutputSelection else { return false }
        let success = backend.selectOutputDevice(persistentID: persistentID)
        if success {
            preferences?.selectedOutputDevicePersistentID = persistentID
        }
        return success
    }

    // MARK: - Backend event handling

    private func handleBackendEvent(_ event: AudioBackendEvent) {
        switch event {
        case let .stateChanged(newState, token):
            handleStateChanged(newState, token: token)

        case let .timeUpdated(current, duration, token):
            handleTimeUpdated(current: current, duration: duration, token: token)

        case let .endOfStream(token):
            handleEndOfStream(token: token)

        case let .loadFailed(track, failure, token):
            handleLoadFailed(track: track, failure: failure, token: token)

        case .formatChanged:
            break

        case let .analysisFrame(frame, token):
            handleAnalysisFrame(frame, token: token)

        case let .outputsChanged(devices, current):
            handleOutputsChanged(devices: devices, current: current)
        }
    }

    private func handleStateChanged(_ newState: PlaybackState, token: UInt64) {
        guard isCurrentToken(token) else { return }

        state = newState

        // Canonical load callback order:
        // audioEngineDidChangeTrack -> audioEngineDidUpdateTime -> audioEngineDidChangeState
        if pendingInitialLoadToken == token {
            if let pendingInitialTime {
                currentTime = pendingInitialTime.current
                duration = pendingInitialTime.duration
            }

            pendingInitialLoadToken = nil
            self.pendingInitialTime = nil

            delegate?.audioEngineDidChangeTrack(currentTrack)
            delegate?.audioEngineDidUpdateTime(current: currentTime, duration: duration)
            delegate?.audioEngineDidChangeState(newState)
            lastDeliveredTimeUpdate = Date()
            return
        }

        delegate?.audioEngineDidChangeState(newState)
    }

    private func handleTimeUpdated(current: TimeInterval, duration: TimeInterval, token: UInt64) {
        guard isCurrentToken(token) else { return }

        self.currentTime = max(0, current)
        self.duration = max(0, duration)

        if pendingInitialLoadToken == token {
            pendingInitialTime = (self.currentTime, self.duration)
            return
        }

        // Seek path: one immediate update, then resume steady cadence.
        if pendingSeekToken != nil {
            pendingSeekToken = nil
            pendingSeekTarget = nil
            delegate?.audioEngineDidUpdateTime(current: self.currentTime, duration: self.duration)
            lastDeliveredTimeUpdate = Date()
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastDeliveredTimeUpdate) >= delegateTimeCadence else { return }
        delegate?.audioEngineDidUpdateTime(current: self.currentTime, duration: self.duration)
        lastDeliveredTimeUpdate = now
    }

    private func handleEndOfStream(token: UInt64) {
        guard isCurrentToken(token) else { return }

        // Ignore EOS that races with an in-flight seek.
        if pendingSeekToken != nil {
            return
        }

        if let nextIndex = nextIndexForPlaybackAdvance() {
            currentIndex = nextIndex
            loadTrack(at: nextIndex, startPaused: false)
            return
        }

        setStoppedAndNotify(timeReset: false)
    }

    private func handleLoadFailed(track: NullPlayerCore.Track, failure: PlaybackFailure, token: UInt64) {
        guard isCurrentToken(token) else { return }

        delegate?.audioEngineDidFailToLoadTrack(track, error: PlaybackBackendFailure(code: failure.code, message: failure.message))

        if let nextIndex = nextIndexForPlaybackAdvance() {
            currentIndex = nextIndex
            loadTrack(at: nextIndex, startPaused: false)
            return
        }

        setStoppedAndNotify(timeReset: false)
    }

    private func handleAnalysisFrame(_ frame: AnalysisFrame, token: UInt64) {
        guard isCurrentToken(token) else { return }

        portableAnalysis.consume(frame)

        if !waveformConsumers.isEmpty {
            pcmData = portableAnalysis.pcmData
        }

        if !spectrumConsumers.isEmpty {
            spectrumData = portableAnalysis.spectrumData
            delegate?.audioEngineDidUpdateSpectrum(spectrumData)
        }
    }

    private func handleOutputsChanged(devices: [AudioOutputDevice], current: AudioOutputDevice?) {
        guard let selected = preferences?.selectedOutputDevicePersistentID else { return }
        let stillAvailable = devices.contains { $0.persistentID == selected }
        if !stillAvailable {
            preferences?.selectedOutputDevicePersistentID = current?.persistentID
        }
    }

    // MARK: - Load helpers

    private func loadTrack(at index: Int, startPaused: Bool) {
        guard index >= 0, index < playlist.count else { return }

        let previousToken = loadToken
        loadToken &+= 1
        seekToken &+= 1
        pendingSeekToken = nil
        pendingSeekTarget = nil

        let token = loadToken
        let track = playlist[index]

        currentTime = 0
        duration = track.duration ?? 0
        pendingInitialLoadToken = token
        pendingInitialTime = (current: currentTime, duration: duration)

        if previousToken != 0 {
            backend.stop(token: previousToken)
        }

        backend.load(track: track, token: token, startPaused: startPaused)
        backend.setVolume(volume, token: token)
        backend.setBalance(balance, token: token)
        backend.setEQ(enabled: eqEnabled, preamp: eqPreamp, bands: eqBands, token: token)
        refreshNextTrackHint(token: token)
    }

    private func refreshNextTrackHint(token: UInt64? = nil) {
        let selectedToken = token ?? loadToken
        guard selectedToken != 0 else { return }
        guard backend.capabilities.supportsGaplessPlayback else {
            backend.setNextTrackHint(nil, token: selectedToken)
            return
        }
        guard gaplessPlaybackEnabled else {
            backend.setNextTrackHint(nil, token: selectedToken)
            return
        }
        guard !repeatEnabled || shuffleEnabled else {
            backend.setNextTrackHint(nil, token: selectedToken)
            return
        }

        let nextTrack: NullPlayerCore.Track?
        if let nextIndex = peekNextTrackIndexForPlayback() {
            nextTrack = playlist[nextIndex]
        } else {
            nextTrack = nil
        }

        backend.setNextTrackHint(nextTrack, token: selectedToken)
    }

    private func pushEQSettings() {
        guard loadToken != 0 else { return }
        backend.setEQ(enabled: eqEnabled, preamp: eqPreamp, bands: eqBands, token: loadToken)
    }

    private func setStoppedAndNotify(timeReset: Bool) {
        if timeReset {
            currentTime = 0
        }
        state = .stopped
        delegate?.audioEngineDidUpdateTime(current: currentTime, duration: duration)
        delegate?.audioEngineDidChangeState(.stopped)
    }

    // MARK: - Playlist discovery

    private func discoverPlayableFiles(in folderURL: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                results.append(fileURL)
            }
        }
        return results
    }

    private func restoreCurrentIndex(afterReorderingTrackID trackID: UUID?) {
        guard let trackID else {
            if playlist.isEmpty {
                currentIndex = -1
            } else if currentIndex >= playlist.count {
                currentIndex = playlist.count - 1
            }
            return
        }

        currentIndex = playlist.firstIndex { $0.id == trackID } ?? -1
    }

    // MARK: - Shuffle traversal helpers

    private func clearShufflePlaybackState() {
        shufflePlaybackOrder.removeAll()
        shufflePlaybackPosition = -1
        pendingRepeatShuffleOrder = nil
    }

    private func invalidateShufflePlaybackStateAfterPlaylistMutation() {
        guard shuffleEnabled else {
            clearShufflePlaybackState()
            return
        }

        rebuildShufflePlaybackOrder(anchoredAt: currentIndex)
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

        let validPreferredIndices = (preferredIndices ?? Array(playlist.indices)).filter {
            $0 >= 0 && $0 < playlist.count
        }

        var deduplicatedPreferred: [Int] = []
        var seen = Set<Int>()
        for index in validPreferredIndices where seen.insert(index).inserted {
            deduplicatedPreferred.append(index)
        }

        let preferredPool = deduplicatedPreferred.isEmpty ? Array(playlist.indices) : deduplicatedPreferred
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

    private func nextIndexForPlaybackAdvance() -> Int? {
        guard !playlist.isEmpty else { return nil }

        if shuffleEnabled {
            return nextShuffleIndexForPlaybackAdvance()
        }

        if repeatEnabled {
            guard currentIndex >= 0, currentIndex < playlist.count else { return nil }
            return currentIndex
        }

        let next = currentIndex + 1
        return next < playlist.count ? next : nil
    }

    private func peekNextTrackIndexForPlayback() -> Int? {
        guard !playlist.isEmpty else { return nil }

        if shuffleEnabled {
            return peekNextShuffleIndexForPlayback()
        }

        let next = currentIndex + 1
        return next < playlist.count ? next : nil
    }

    private func nextIndexForManualNavigation() -> Int? {
        guard !playlist.isEmpty else { return nil }

        if shuffleEnabled {
            return nextShuffleIndexForManualNavigation()
        }

        if currentIndex < 0 || currentIndex >= playlist.count {
            return 0
        }

        return (currentIndex + 1) % playlist.count
    }

    private func previousIndexForManualNavigation() -> Int? {
        guard !playlist.isEmpty else { return nil }

        if shuffleEnabled {
            return previousShuffleIndexForManualNavigation()
        }

        if currentIndex < 0 || currentIndex >= playlist.count {
            return playlist.count - 1
        }

        return (currentIndex - 1 + playlist.count) % playlist.count
    }

    // MARK: - EQ config resolution

    private static func makeEQConfiguration(forBandCount bandCount: Int) -> EQConfiguration {
        if let persisted = EQConfiguration.persistedLayout(forBandCount: bandCount) {
            return persisted
        }

        if bandCount <= 1 {
            return EQConfiguration(
                name: "backend-1",
                frequencies: [1000],
                displayLabels: ["1K"],
                parametricBandwidth: 1.0
            )
        }

        let minFrequency: Double = 32
        let maxFrequency: Double = 20000
        let ratio = pow(maxFrequency / minFrequency, 1.0 / Double(bandCount - 1))
        let frequencies: [Float] = (0..<bandCount).map { index in
            Float(minFrequency * pow(ratio, Double(index)))
        }
        let labels = frequencies.map(Self.makeFrequencyLabel)

        return EQConfiguration(
            name: "backend-\(bandCount)",
            frequencies: frequencies,
            displayLabels: labels,
            parametricBandwidth: 1.0
        )
    }

    private static func makeFrequencyLabel(_ frequency: Float) -> String {
        if frequency >= 1000 {
            let value = frequency / 1000
            if value.rounded() == value {
                return "\(Int(value))K"
            }
            return String(format: "%.1fK", value)
        }
        return "\(Int(frequency.rounded()))"
    }
}

private struct PlaybackBackendFailure: LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? {
        if code.isEmpty {
            return message
        }
        return "[\(code)] \(message)"
    }
}

extension AudioEngineFacade: @unchecked Sendable {}
