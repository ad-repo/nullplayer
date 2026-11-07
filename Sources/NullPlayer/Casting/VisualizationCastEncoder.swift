import AVFoundation
import CoreMedia
import QuartzCore
import VideoToolbox

/// Turns the visualization's frames and the app's own audio into a live MPEG-TS stream: short HLS
/// segments for a Chromecast and one endless body for a DLNA TV (`VisualizationCast`).
///
/// A wall-clock tick at the chosen frame rate drives it. Each tick takes the newest frame (or repeats
/// the last) and exactly one tick's worth of audio from a ring (silence when the ring runs short), so
/// the stream never stalls, whatever playback is doing, and picture and sound share one timeline.
/// A keyframe every `keyframeSeconds` starts each segment.
final class VisualizationCastEncoder {
    let quality: VisualizationCastQuality
    private let inputSampleRate: Double
    private let queue = DispatchQueue(label: "com.nullplayer.viscast.encoder", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private let compression: VTCompressionSession
    private let audioConverter: AVAudioConverter
    private let aacFormat: AVAudioFormat
    private var muxer = MPEGTSMuxer()

    /// The tap writes here (`AudioTapRing`); the tick reads it. 200 ms, the most audio held back.
    let audio: AudioTapRing

    // Tick state: the encoder queue, and VT's output handler (`writeVideo`), which runs on VT's
    // thread inside `VTCompressionSessionCompleteFrames` while the queue waits on that call.
    private var startTime: CFTimeInterval = 0
    private var tickIndex: Int64 = 0
    private var audioFramesTaken: Int64 = 0
    private var aacPacketsWritten: Int64 = 0
    private var lastFrame: CVPixelBuffer?
    private var segmentBytes: [UInt8] = []
    private var segmentStartPTS: UInt64?

    // Shared state, under `lock`
    private let lock = NSLock()
    private var pendingFrame: CVPixelBuffer?
    private var lastFrameRequest: CFTimeInterval = 0
    private var stopped = false   // the session is invalidated: no more pool buffers
    private var durations: [Double] = []   // every segment's, by sequence: the EVENT playlist lists them all
    private var segments: [(sequence: Int, data: Data)] = []   // the newest few, to serve
    private var liveListeners: [UUID: AsyncStream<Data>.Continuation] = [:]

    private static let keptSegments = 8
    /// Seconds between keyframes, and so each segment's length. At 2 a Chromecast sat in BUFFERING,
    /// re-buffering every playlist refresh (measured), though a longer gap gives the frames between
    /// more bits.
    static let keyframeSeconds = 1
    private static let outputSampleRate = 48_000.0

    init(quality: VisualizationCastQuality, inputSampleRate: Double) throws {
        self.quality = quality
        self.inputSampleRate = inputSampleRate
        audio = AudioTapRing(frames: Int(inputSampleRate * 0.2))

        var session: VTCompressionSession?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: quality.width,
            kCVPixelBufferHeightKey: quality.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(quality.width), height: Int32(quality.height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard status == noErr, let session else { throw VisualizationCastError.encoder("video encoder (\(status))") }
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_RealTime: true,
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_H264_High_AutoLevel,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_AverageBitRate: quality.videoBitRate,
            // The average alone ran 18 Mbps against an 8 Mbps target (measured), and the TV buffered.
            kVTCompressionPropertyKey_DataRateLimits: [quality.videoBitRate * 5 / 4 / 8, 1] as CFArray,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: quality.frameRate * Self.keyframeSeconds,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: Self.keyframeSeconds,
            kVTCompressionPropertyKey_ExpectedFrameRate: quality.frameRate,
            // HD colour, tagged, so the BGRA→YUV conversion and the TV agree on the matrix.
            kVTCompressionPropertyKey_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kVTCompressionPropertyKey_TransferFunction: kCVImageBufferTransferFunction_ITU_R_709_2,
            kVTCompressionPropertyKey_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ]
        for (key, value) in properties { VTSessionSetProperty(session, key: key, value: value as CFTypeRef) }
        VTCompressionSessionPrepareToEncodeFrames(session)
        compression = session

        var aac = AudioStreamBasicDescription(
            mSampleRate: Self.outputSampleRate, mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        guard let pcmFormat = AVAudioFormat(standardFormatWithSampleRate: inputSampleRate, channels: 2),
              let aacFormat = AVAudioFormat(streamDescription: &aac),
              let converter = AVAudioConverter(from: pcmFormat, to: aacFormat) else {
            VTCompressionSessionInvalidate(session)
            throw VisualizationCastError.encoder("audio encoder")
        }
        converter.bitRate = 192_000
        self.aacFormat = aacFormat
        audioConverter = converter
    }

    // MARK: - Lifecycle

    func start() {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(quality.frameRate), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        startTime = CACurrentMediaTime()
        self.timer = timer
        timer.resume()
    }

    /// Stops the tick and ends every live body. The owner calls it once, off the main thread: it
    /// waits out a tick in flight.
    func stop() {
        timer?.cancel()
        timer = nil
        lock.withLock { stopped = true }   // the render thread may still hold this encoder
        queue.sync { VTCompressionSessionInvalidate(compression) }
        // Finished outside the lock: `finish()` runs the stream's termination handler, which takes it.
        let listeners = lock.withLock {
            defer { liveListeners.removeAll() }
            return Array(liveListeners.values)
        }
        listeners.forEach { $0.finish() }
    }

    // MARK: - Input (any thread)

    /// The render thread asks before reading back, so it reads back no more than once per tick.
    func wantsFrame() -> Bool {
        let now = CACurrentMediaTime()
        return lock.withLock {
            guard now - lastFrameRequest >= 0.9 / Double(quality.frameRate) else { return false }
            lastFrameRequest = now
            return true
        }
    }

    /// A buffer from the encoder's own pool, at the cast size; nil once stopped.
    func makePixelBuffer() -> CVPixelBuffer? {
        lock.withLock {
            guard !stopped, let pool = VTCompressionSessionGetPixelBufferPool(compression) else { return nil }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            return buffer
        }
    }

    func submit(_ frame: CVPixelBuffer) {
        lock.withLock { pendingFrame = frame }
    }

    // MARK: - Output (any thread)

    var segmentCount: Int { lock.withLock { durations.count } }

    /// The live HLS playlist, an EVENT one that starts 6 s back. A Chromecast starts a sliding live
    /// playlist at its newest segment whatever `EXT-X-START` says, and flapped BUFFERING/PLAYING for
    /// 15–50 s, jumping back to the edge after each stall; an EVENT playlist it starts where told,
    /// and plays after one buffering (measured, 1080p60, three runs each). Only the newest segments'
    /// bytes are kept: the TV never goes back for the rest. `TARGETDURATION` is the ceiling of the
    /// longest segment plus one: rounded down, a Chromecast stalls every few seconds (measured).
    // ponytail: the playlist grows a line a second (~90 KB an hour); cap it if long casts stutter.
    func playlist() -> String? {
        lock.withLock {
            guard let longest = durations.max() else { return nil }
            var text = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-PLAYLIST-TYPE:EVENT\n"
                + "#EXT-X-TARGETDURATION:\(Int(longest.rounded(.up)) + 1)\n#EXT-X-START:TIME-OFFSET=-6.0\n"
                + "#EXT-X-MEDIA-SEQUENCE:0\n"
            for (sequence, duration) in durations.enumerated() {
                text += String(format: "#EXTINF:%.3f,\nseg-%d.ts\n", duration, sequence)
            }
            return text
        }
    }

    func segment(_ sequence: Int) -> Data? {
        lock.withLock { segments.first { $0.sequence == sequence }?.data }
    }

    /// Every segment from the next one on, for as long as the client reads.
    func liveBody() -> AsyncStream<Data> {
        // ponytail: a client that disconnects stays registered (at most 4 segments buffered) until
        // the cast stops; prune on termination if many reconnects ever matter.
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(4))
        let id = UUID()
        lock.withLock { liveListeners[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.liveListeners.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: - Tick (encoder queue)

    private func tick() {
        // Catch up to the wall clock, so the stream runs in real time even if a tick fires late.
        let due = Int64((CACurrentMediaTime() - startTime) * Double(quality.frameRate)) + 1
        while tickIndex < due {
            guard encodeTick() else { return }
            tickIndex += 1
        }
    }

    /// One frame of video and its share of audio. False until the first frame has arrived.
    private func encodeTick() -> Bool {
        let fps = Int64(quality.frameRate)
        let framesDue = Int64(Double(tickIndex + 1) * inputSampleRate / Double(fps)) - audioFramesTaken
        let frame: CVPixelBuffer? = lock.withLock {
            defer { pendingFrame = nil }
            return pendingFrame ?? lastFrame
        }
        guard let frame else {
            // Nothing drawn yet: keep the timeline at zero, and only the newest audio.
            startTime = CACurrentMediaTime()
            _ = audio.read(frames: 0)
            return false
        }
        let audio = self.audio.read(frames: Int(framesDue))
        lastFrame = frame
        audioFramesTaken += framesDue

        let pts = CMTime(value: tickIndex, timescale: CMTimeScale(fps))
        let videoPTS = UInt64(tickIndex) * 90_000 / UInt64(fps)
        let properties = tickIndex % (fps * Int64(Self.keyframeSeconds)) == 0
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        VTCompressionSessionEncodeFrame(compression, imageBuffer: frame, presentationTimeStamp: pts,
                                        duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                                        frameProperties: properties, infoFlagsOut: nil) { [weak self] status, _, sample in
            guard status == noErr, let sample, let self else { return }
            self.writeVideo(sample, pts: videoPTS)
        }
        // Real time with no reordering: the frame comes out now, so its bytes land before this tick's audio.
        VTCompressionSessionCompleteFrames(compression, untilPresentationTimeStamp: pts)
        writeAudio(audio)
        segmentBytes += muxer.take()
        return true
    }

    private func writeVideo(_ sample: CMSampleBuffer, pts: UInt64) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyframe = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        if isKeyframe {
            closeSegment(at: pts)
            muxer.beginSegment()
        }
        guard segmentStartPTS != nil, let annexB = MPEGTSMuxer.annexB(sample, withParameterSets: isKeyframe) else { return }
        muxer.writeVideo(annexB: annexB, pts: pts, isKeyframe: isKeyframe)
    }

    private func closeSegment(at pts: UInt64) {
        defer { segmentStartPTS = pts }
        guard let start = segmentStartPTS else { segmentBytes = muxer.take(); return }
        let data = Data(segmentBytes + muxer.take())
        segmentBytes = []
        lock.withLock {
            segments.append((durations.count, data))
            durations.append(Double(pts - start) / 90_000)
            if segments.count > Self.keptSegments { segments.removeFirst() }
            liveListeners.values.forEach { $0.yield(data) }
        }
    }

    private func writeAudio(_ interleaved: [Float]) {
        let frames = AVAudioFrameCount(interleaved.count / 2)
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: audioConverter.inputFormat, frameCapacity: frames),
              let channels = pcm.floatChannelData else { return }
        pcm.frameLength = frames
        for f in 0..<Int(frames) {
            channels[0][f] = interleaved[f * 2]
            channels[1][f] = interleaved[f * 2 + 1]
        }

        var supplied = false
        var adts: [UInt8] = []
        let firstPacket = aacPacketsWritten
        let output = AVAudioCompressedBuffer(format: aacFormat, packetCapacity: 8,
                                             maximumPacketSize: max(audioConverter.maximumOutputPacketSize, 1536))
        while true {
            var error: NSError?
            let status = audioConverter.convert(to: output, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return pcm
            }
            for i in 0..<Int(output.packetCount) {
                guard let description = output.packetDescriptions?[i] else { continue }
                let bytes = UnsafeRawBufferPointer(start: output.data + Int(description.mStartOffset),
                                                   count: Int(description.mDataByteSize))
                adts += MPEGTSMuxer.adtsHeader(frameLength: bytes.count, sampleRate: Self.outputSampleRate,
                                               channels: UInt8(aacFormat.channelCount))
                adts += bytes
                aacPacketsWritten += 1
            }
            if status != .haveData { break }
        }
        // ponytail: the AAC encoder's priming (~2112 samples, 44 ms) is not subtracted; trim it if
        // the sound ever reads as late against the picture.
        guard !adts.isEmpty, segmentStartPTS != nil else { return }
        muxer.writeAudio(adts: adts, pts: UInt64(firstPacket) * 1024 * 90_000 / UInt64(Self.outputSampleRate))
    }
}
