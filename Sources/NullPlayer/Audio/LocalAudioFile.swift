import AVFoundation

/// Opens local audio for the AVAudioEngine pipeline. Core Audio can recognize Opus in an
/// MPEG-4 container yet report zero frames (and fail on read); AVAssetReader can decode it.
/// Full preparation is async, cancellable, and must never run on the main queue.
enum LocalAudioFile {
    static func prepareForPlayback(_ sourceURL: URL) async throws -> AVAudioFile {
        try Task.checkCancellation()
        let staged = LocalAudioStaging.copyIfNeeded(for: sourceURL)
        return try await open(staged ?? sourceURL, sourceURL: sourceURL, stagedCopyURL: staged)
    }

    /// Reads `url`, natively or through the Opus fallback. A reader of anything but the source
    /// itself reports `sourceURL` as its identity and owns `stagedCopyURL`, deleted with it.
    static func open(_ url: URL, sourceURL: URL? = nil, stagedCopyURL: URL? = nil) async throws -> AVAudioFile {
        var transferred = false
        defer { if !transferred, let stagedCopyURL { removeTemporaryItem(stagedCopyURL) } }
        try Task.checkCancellation()
        let identity = sourceURL ?? url
        let file: AVAudioFile
        if let native = try openNatively(url) {
            file = identity == url && stagedCopyURL == nil ? native
                : try LocalPlaybackFile(backingURL: url, sourceURL: identity,
                                        storage: PlaybackFileStorage(paths: stagedCopyURL.map { [$0] } ?? []))
        } else {
            dispatchPrecondition(condition: .notOnQueue(.main))
            file = try await decodeOpusAsset(url, sourceURL: identity, stagedCopyURL: stagedCopyURL)
        }
        transferred = true
        return file
    }

    /// The native reader, or nil when the file needs the fallback decode in `open`.
    /// Synchronous transport paths call this and defer a nil to asynchronous preparation.
    static func openNatively(_ url: URL) throws -> AVAudioFile? {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            guard mayNeedFallbackDecode(url) else { throw error }
            return nil
        }
        guard mayNeedFallbackDecode(url),
              file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatOpus else { return file }
        // Core Audio can accept MPEG-4 Opus yet report no frames or fail the first read.
        guard file.length > 0,
              let probe = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1),
              (try? file.read(into: probe, frameCount: 1)) != nil,
              probe.frameLength > 0 else { return nil }
        file.framePosition = 0
        return file
    }

    /// MPEG-4 is the only container whose Opus Core Audio cannot always read.
    static func mayNeedFallbackDecode(_ url: URL) -> Bool {
        url.isFileURL && ["m4a", "mp4", "m4b"].contains(url.pathExtension.lowercased())
    }

    /// The backing CAF is an implementation detail, never a playlist/library identity.
    static func sourceURL(of file: AVAudioFile) -> URL {
        (file as? LocalPlaybackFile)?.sourceURL ?? file.url
    }

    /// An explicit read URL plus ownership token: analysis can outlive the scheduled player
    /// without retaining/sharing that player's mutable AVAudioFile reader.
    static func analysisSource(of file: AVAudioFile) -> LocalAudioAnalysisSource {
        LocalAudioAnalysisSource(backingURL: file.url, sourceURL: sourceURL(of: file),
                                 storage: (file as? LocalPlaybackFile)?.storage)
    }

    private static let cleanupQueue = DispatchQueue(label: "com.nullplayer.audio-file-cleanup", qos: .utility)

    fileprivate static func removeTemporaryItem(_ directory: URL) {
        cleanupQueue.async { try? FileManager.default.removeItem(at: directory) }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LocalAudioFile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func decodeOpusAsset(_ url: URL, sourceURL: URL, stagedCopyURL: URL?) async throws -> AVAudioFile {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let description = try await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              asbd.pointee.mFormatID == kAudioFormatOpus else {
            throw failure("No supported Opus audio track in MPEG-4 file")
        }

        let duration = try await asset.load(.duration)
        try Task.checkCancellation()
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw failure("Cannot attach Opus audio reader") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? failure("Cannot start Opus audio reader") }
        defer { reader.cancelReading() }

        // The player schedules AVAudioFile segments for seek, cue, gapless and crossfade.
        // Give those existing paths a lossless Float32 backing file, owned by the open file
        // rather than the track. Originals and playlist URLs are never changed. The OS also
        // reclaims this replacement directory if the app crashes before normal teardown.
        let directory = try FileManager.default.url(for: .itemReplacementDirectory,
            in: .userDomainMask, appropriateFor: FileManager.default.temporaryDirectory, create: true)
        var transferred = false
        defer { if !transferred { removeTemporaryItem(directory) } }
        let decodedURL = directory.appendingPathComponent("decoded.caf")
        try writePCM(from: output, reader: reader, duration: duration, to: decodedURL)
        try Task.checkCancellation()
        let storage = PlaybackFileStorage(paths: [directory] + (stagedCopyURL.map { [$0] } ?? []))
        let file = try LocalPlaybackFile(backingURL: decodedURL, sourceURL: sourceURL, storage: storage)
        transferred = true
        return file
    }

    private static func writePCM(from output: AVAssetReaderTrackOutput, reader: AVAssetReader,
                                 duration: CMTime, to url: URL) throws {
        var writer: AVAudioFile?
        var written: AVAudioFramePosition = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let description = CMSampleBufferGetFormatDescription(sample) else {
                throw failure("Missing decoded Opus audio format")
            }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            guard format.commonFormat == .pcmFormatFloat32, format.isInterleaved,
                  let data = CMSampleBufferGetDataBuffer(sample) else {
                throw failure("Invalid decoded Opus audio buffer")
            }
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0, count <= Int(UInt32.max),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                  let samples = buffer.floatChannelData else {
                throw failure("Cannot allocate decoded Opus audio buffer")
            }
            buffer.frameLength = AVAudioFrameCount(count)
            let bytes = count * Int(format.streamDescription.pointee.mBytesPerFrame)
            guard CMBlockBufferGetDataLength(data) >= bytes,
                  CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: bytes,
                                            destination: samples[0]) == noErr else {
                throw failure("Cannot read decoded Opus audio samples")
            }
            if writer == nil {
                writer = try AVAudioFile(forWriting: url, settings: format.settings,
                                        commonFormat: .pcmFormatFloat32, interleaved: true)
            }
            // AVAssetReader removes Opus pre-skip but can include the last packet's padding.
            // Respect the presentation duration, especially across gapless boundaries.
            if duration.isNumeric, duration.seconds > 0 {
                let limit = CMTimeConvertScale(duration, timescale: Int32(format.sampleRate),
                                               method: .roundHalfAwayFromZero).value
                buffer.frameLength = AVAudioFrameCount(min(Int64(count), max(0, limit - written)))
            }
            if buffer.frameLength > 0 {
                try writer?.write(from: buffer)
                written += AVAudioFramePosition(buffer.frameLength)
            }
        }
        guard reader.status == .completed else {
            throw reader.error ?? failure("Opus audio reader did not finish")
        }
        guard written > 0 else { throw failure("No audio samples decoded from Opus file") }
        // Release the writer (and finalize the CAF header) before opening it for playback.
        writer = nil
    }
}

/// Like AVAudioFile, the mutable reader is handed off to one consumer, not used concurrently.
/// Only immutable source/storage metadata is added; deletion is dispatched to a utility queue.
private final class LocalPlaybackFile: AVAudioFile, @unchecked Sendable {
    let sourceURL: URL
    let storage: PlaybackFileStorage

    init(backingURL: URL, sourceURL: URL, storage: PlaybackFileStorage) throws {
        self.sourceURL = sourceURL
        self.storage = storage
        try super.init(forReading: backingURL, commonFormat: .pcmFormatFloat32, interleaved: false)
    }
}

/// One immutable lifetime for every temporary path behind a prepared reader.
fileprivate final class PlaybackFileStorage: @unchecked Sendable {
    private let paths: [URL]
    init(paths: [URL]) { self.paths = paths }
    deinit { for path in paths { LocalAudioFile.removeTemporaryItem(path) } }
}

struct LocalAudioAnalysisSource: Sendable {
    let backingURL: URL
    let sourceURL: URL
    fileprivate let storage: PlaybackFileStorage?

    func withFile<T>(_ read: (AVAudioFile) throws -> T) throws -> T {
        try withExtendedLifetime(storage) {
            try read(AVAudioFile(forReading: backingURL))
        }
    }
}
