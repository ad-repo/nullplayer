#if os(Linux)
import Foundation
import CGStreamer
import NullPlayerCore

public final class LinuxGStreamerAudioBackend: AudioBackend {
    public let capabilities = AudioBackendCapabilities(
        supportsOutputSelection: true,
        supportsGaplessPlayback: false,
        supportsSweetFade: false,
        supportsEQ: true,
        supportsWaveformFrames: false,
        eqBandCount: 10
    )

    public var eventHandler: (@Sendable (AudioBackendEvent) -> Void)?

    public var outputDevices: [AudioOutputDevice] {
        outputRouter.outputDevices
    }

    public var currentOutputDevice: AudioOutputDevice? {
        outputRouter.currentOutputDevice
    }

    private let backendQueue = DispatchQueue(label: "NullPlayer.LinuxGStreamerAudioBackend")
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private let outputRouter: GStreamerOutputRouter

    private var pipeline: GStreamerPipeline?
    private var busBridge: GStreamerBusBridge?
    private var prepared = false
    private var pipelineSetupFailure: PlaybackFailure?

    private var currentToken: UInt64 = 0
    private var currentTrack: NullPlayerCore.Track?

    private var eqEnabled = false
    private var eqPreamp: Float = 0
    private var eqBands: [Float] = Array(repeating: 0, count: 10)

    private var analysisTimer: DispatchSourceTimer?
    private var timeTimer: DispatchSourceTimer?
    private var bufferedAnalysisFrames: [AnalysisFrame] = []

    public init() {
        self.outputRouter = GStreamerOutputRouter()
        backendQueue.setSpecific(key: Self.queueKey, value: 1)
        self.outputRouter.onDevicesChanged = { [weak self] devices, current in
            self?.backendQueue.async {
                self?.emit(.outputsChanged(devices, current: current))
            }
        }
    }

    deinit {
        shutdown()
    }

    public func prepare() {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            prepareOnQueue()
            return
        }
        backendQueue.sync { prepareOnQueue() }
    }

    public func shutdown() {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            shutdownOnQueue()
            return
        }
        backendQueue.sync { shutdownOnQueue() }
    }

    public func load(track: NullPlayerCore.Track, token: UInt64, startPaused: Bool) {
        backendQueue.async {
            self.currentToken = token
            self.currentTrack = track

            self.prepareIfNeededOnQueue()
            guard let pipeline = self.pipeline else {
                let failure = self.pipelineSetupFailure
                    ?? PlaybackFailure(code: "gstreamer_setup", message: "Failed to create playback pipeline")
                self.emit(.loadFailed(track: track, failure: failure, token: token))
                return
            }

            self.setStringProperty(pipeline.playbin, name: "uri", value: track.url.absoluteString)
            self.applyEQSettingsIfNeeded()

            let state: GstState = startPaused ? GST_STATE_PAUSED : GST_STATE_PLAYING
            let result = gst_element_set_state(pipeline.playbin, state)

            if result == GST_STATE_CHANGE_FAILURE {
                self.emit(.loadFailed(
                    track: track,
                    failure: PlaybackFailure(code: "state_change_failed", message: "Unable to start playback"),
                    token: token
                ))
                return
            }

            self.emitCurrentTimeUpdate()
            self.emit(.stateChanged(startPaused ? .paused : .playing, token: token))
        }
    }

    public func play(token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken,
                  let playbin = self.pipeline?.playbin else { return }
            _ = gst_element_set_state(playbin, GST_STATE_PLAYING)
        }
    }

    public func pause(token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken,
                  let playbin = self.pipeline?.playbin else { return }
            _ = gst_element_set_state(playbin, GST_STATE_PAUSED)
        }
    }

    public func stop(token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken,
                  let playbin = self.pipeline?.playbin else { return }
            _ = gst_element_set_state(playbin, GST_STATE_READY)
            self.emit(.stateChanged(.stopped, token: token))
            self.emit(.timeUpdated(current: 0, duration: self.queryDuration(), token: token))
        }
    }

    public func seek(to time: TimeInterval, token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken,
                  let playbin = self.pipeline?.playbin else { return }

            let clamped = max(0, time)
            let nanos = Int64(clamped * 1_000_000_000)
            let flags = GstSeekFlags(GST_SEEK_FLAG_FLUSH.rawValue | GST_SEEK_FLAG_KEY_UNIT.rawValue)
            let ok = gst_element_seek_simple(playbin, GST_FORMAT_TIME, flags, nanos)

            guard ok != 0 else { return }
            self.emitCurrentTimeUpdate()
        }
    }

    public func setVolume(_ value: Float, token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken,
                  let volume = self.pipeline?.volume else { return }
            self.setDoubleProperty(volume, name: "volume", value: Double(max(0, min(1, value))))
        }
    }

    public func setBalance(_ value: Float, token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken else { return }
            // Linux MVP keeps balance as a no-op for now.
            _ = value
        }
    }

    public func setEQ(enabled: Bool, preamp: Float, bands: [Float], token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken else { return }

            self.eqEnabled = enabled
            self.eqPreamp = preamp

            if bands.isEmpty {
                self.eqBands = Array(repeating: 0, count: self.capabilities.eqBandCount)
            } else {
                self.eqBands = (0..<self.capabilities.eqBandCount).map { index in
                    if index < bands.count {
                        return bands[index]
                    }
                    return 0
                }
            }

            self.applyEQSettingsIfNeeded()
        }
    }

    public func setNextTrackHint(_ track: NullPlayerCore.Track?, token: UInt64) {
        backendQueue.async {
            guard token == self.currentToken else { return }
            _ = track
        }
    }

    public func refreshOutputs() {
        outputRouter.refreshOutputs()
    }

    @discardableResult
    public func selectOutputDevice(persistentID: String?) -> Bool {
        guard outputRouter.selectOutputDevice(persistentID: persistentID) else {
            return false
        }

        backendQueue.async {
            guard var pipeline = self.pipeline else { return }
            let sinkFactory = self.outputRouter.preferredOutputSinkFactory()
            try? GStreamerPipelineBuilder.rebuildOutputSink(in: &pipeline, outputSinkFactory: sinkFactory)
            self.pipeline = pipeline
            self.emit(.outputsChanged(self.outputRouter.outputDevices, current: self.outputRouter.currentOutputDevice))
        }

        return true
    }

    private func handleBusSignal(_ signal: GStreamerBusSignal) {
        switch signal {
        case .endOfStream:
            emit(.endOfStream(token: currentToken))

        case let .loadError(code, message):
            guard let currentTrack else { return }
            emit(.loadFailed(
                track: currentTrack,
                failure: PlaybackFailure(code: code, message: message),
                token: currentToken
            ))

        case let .stateChanged(state):
            emit(.stateChanged(state, token: currentToken))
            if state == .playing || state == .paused {
                emitCurrentTimeUpdate()
            }

        case .streamStarted:
            emitCurrentTimeUpdate()

        case .durationChanged:
            emitCurrentTimeUpdate()
        }
    }

    private func startAnalysisTimer() {
        let timer = DispatchSource.makeTimerSource(queue: backendQueue)
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        timer.setEventHandler { [weak self] in
            self?.pullAnalysisFrames()
            self?.flushLatestAnalysisFrame()
        }
        timer.resume()
        analysisTimer = timer
    }

    private func startTimeTimer() {
        let timer = DispatchSource.makeTimerSource(queue: backendQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.emitCurrentTimeUpdate()
        }
        timer.resume()
        timeTimer = timer
    }

    private func pullAnalysisFrames() {
        guard let appSinkElement = pipeline?.appSink else { return }
        let appSink = asAppSink(appSinkElement)

        while let sample = gst_app_sink_try_pull_sample(appSink, 0) {
            if let frame = makeAnalysisFrame(sample: sample) {
                bufferedAnalysisFrames.append(frame)
                if bufferedAnalysisFrames.count > 3 {
                    bufferedAnalysisFrames.removeFirst(bufferedAnalysisFrames.count - 3)
                }
            }
            gst_sample_unref(sample)
        }
    }

    private func flushLatestAnalysisFrame() {
        guard currentToken != 0,
              let frame = bufferedAnalysisFrames.last else { return }

        bufferedAnalysisFrames.removeAll(keepingCapacity: true)
        emit(.analysisFrame(frame, token: currentToken))
    }

    private func makeAnalysisFrame(sample: UnsafeMutablePointer<GstSample>) -> AnalysisFrame? {
        guard let buffer = gst_sample_get_buffer(sample) else { return nil }

        var mapInfo = GstMapInfo()
        guard gst_buffer_map(buffer, &mapInfo, GST_MAP_READ) != 0,
              let rawData = mapInfo.data else {
            return nil
        }

        defer {
            gst_buffer_unmap(buffer, &mapInfo)
        }

        let floatCount = Int(mapInfo.size) / MemoryLayout<Float>.size
        guard floatCount > 0 else { return nil }

        let floatPointer = UnsafeRawPointer(rawData).assumingMemoryBound(to: Float.self)
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))

        var sampleRate = 44_100
        var channels = 2

        if let caps = gst_sample_get_caps(sample),
           let structure = gst_caps_get_structure(caps, 0) {
            _ = gst_structure_get_int(structure, "rate", &sampleRate)
            _ = gst_structure_get_int(structure, "channels", &channels)
        }

        return AnalysisFrame(
            samples: samples,
            channels: max(1, channels),
            sampleRate: Double(sampleRate),
            monotonicTime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func applyEQSettingsIfNeeded() {
        guard let equalizer = pipeline?.equalizer else { return }

        for band in 0..<capabilities.eqBandCount {
            let gain: Float
            if eqEnabled {
                let value = band < eqBands.count ? eqBands[band] : 0
                gain = max(-24, min(24, value + eqPreamp))
            } else {
                gain = 0
            }
            setDoubleProperty(equalizer, name: "band\(band)", value: Double(gain))
        }
    }

    private func emitCurrentTimeUpdate() {
        guard currentToken != 0 else { return }
        let current = queryPosition()
        let duration = queryDuration()
        emit(.timeUpdated(current: current, duration: duration, token: currentToken))
    }

    private func queryPosition() -> TimeInterval {
        guard let playbin = pipeline?.playbin else { return 0 }
        var position: Int64 = 0
        guard gst_element_query_position(playbin, GST_FORMAT_TIME, &position) != 0 else {
            return 0
        }
        return TimeInterval(Double(position) / 1_000_000_000.0)
    }

    private func queryDuration() -> TimeInterval {
        guard let playbin = pipeline?.playbin else { return 0 }
        var duration: Int64 = 0
        guard gst_element_query_duration(playbin, GST_FORMAT_TIME, &duration) != 0 else {
            return 0
        }
        return TimeInterval(Double(duration) / 1_000_000_000.0)
    }

    private func emit(_ event: AudioBackendEvent) {
        eventHandler?(event)
    }

    private func prepareIfNeededOnQueue() {
        if !prepared {
            prepareOnQueue()
        }
    }

    private func asAppSink(_ element: UnsafeMutablePointer<GstElement>) -> UnsafeMutablePointer<GstAppSink> {
        UnsafeMutableRawPointer(element).assumingMemoryBound(to: GstAppSink.self)
    }

    private func setStringProperty(_ element: UnsafeMutablePointer<GstElement>, name: String, value: String) {
        name.withCString { propName in
            value.withCString { valueCString in
                g_object_set(UnsafeMutableRawPointer(element), propName, valueCString, nil)
            }
        }
    }

    private func setDoubleProperty(_ element: UnsafeMutablePointer<GstElement>, name: String, value: Double) {
        name.withCString { propName in
            g_object_set(UnsafeMutableRawPointer(element), propName, value, nil)
        }
    }

    private static let gstInitOnce: Void = {
        gst_init(nil, nil)
    }()

    private static func initializeGStreamer() {
        _ = gstInitOnce
    }

    private func prepareOnQueue() {
        guard !prepared else { return }
        Self.initializeGStreamer()

        do {
            let sinkFactory = outputRouter.preferredOutputSinkFactory()
            pipeline = try GStreamerPipelineBuilder.build(outputSinkFactory: sinkFactory, eqBandCount: capabilities.eqBandCount)
            pipelineSetupFailure = nil
        } catch {
            pipelineSetupFailure = PlaybackFailure(
                code: "gstreamer_setup",
                message: "Failed to create playback pipeline: \(error)"
            )
            return
        }

        guard let pipeline else {
            pipelineSetupFailure = PlaybackFailure(
                code: "gstreamer_setup",
                message: "Failed to create playback pipeline"
            )
            return
        }

        busBridge = GStreamerBusBridge(
            playbin: pipeline.playbin,
            backendQueue: backendQueue,
            signalHandler: { [weak self] signal in
                self?.handleBusSignal(signal)
            }
        )
        busBridge?.start()

        startAnalysisTimer()
        startTimeTimer()
        outputRouter.refreshOutputs()

        prepared = true
    }

    private func shutdownOnQueue() {
        guard prepared else { return }

        analysisTimer?.cancel()
        analysisTimer = nil

        timeTimer?.cancel()
        timeTimer = nil

        busBridge?.stop()
        busBridge = nil

        if let playbin = pipeline?.playbin {
            _ = gst_element_set_state(playbin, GST_STATE_NULL)
        }

        pipeline = nil
        pipelineSetupFailure = nil
        prepared = false
        currentTrack = nil
        currentToken = 0
        bufferedAnalysisFrames.removeAll(keepingCapacity: false)
    }
}
#endif
