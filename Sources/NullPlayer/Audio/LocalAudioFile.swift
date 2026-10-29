import AVFoundation

/// Opens local audio for the AVAudioEngine pipeline. Core Audio can recognize Opus in an
/// MPEG-4 container yet report zero frames (and fail on read); AVAssetReader can decode it.
/// Full preparation is async, cancellable, and must never run on the main queue.
enum LocalAudioFile {
    static func open(_ url: URL, sourceURL: URL? = nil) async throws -> AVAudioFile {
        try Task.checkCancellation()
        if let file = try openNatively(url, sourceURL: sourceURL) { return file }
        dispatchPrecondition(condition: .notOnQueue(.main))
        return try await decodeOpusAsset(url, sourceURL: sourceURL ?? url)
    }

    /// nil means preparation is required. Synchronous transport paths must defer to `open`.
    static func openNatively(_ url: URL, sourceURL: URL? = nil) throws -> AVAudioFile? {
        do {
            let file: AVAudioFile
            if let sourceURL, sourceURL != url {
                file = try LocalPlaybackFile(backingURL: url, sourceURL: sourceURL)
            } else {
                file = try AVAudioFile(forReading: url)
            }
            guard isMPEG4(url), file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatOpus else {
                return file
            }
            if file.length > 0,
               let probe = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1) {
                do {
                    try file.read(into: probe, frameCount: 1)
                    file.framePosition = 0
                    if probe.frameLength > 0 { return file }
                } catch { /* Prepare a readable file off the main queue. */ }
            }
        } catch {
            guard isMPEG4(url) else { throw error }
        }
        return nil
    }

    /// The backing CAF is an implementation detail, never a playlist/library identity.
    static func sourceURL(of file: AVAudioFile) -> URL {
        (file as? LocalPlaybackFile)?.sourceURL ?? file.url
    }

    private static let cleanupQueue = DispatchQueue(label: "com.nullplayer.audio-file-cleanup", qos: .utility)

    fileprivate static func removeBackingDirectory(_ directory: URL) {
        cleanupQueue.async { try? FileManager.default.removeItem(at: directory) }
    }

    private static func isMPEG4(_ url: URL) -> Bool {
        url.isFileURL && ["m4a", "mp4", "m4b"].contains(url.pathExtension.lowercased())
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LocalAudioFile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func decodeOpusAsset(_ url: URL, sourceURL: URL) async throws -> AVAudioFile {
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
        defer { if !transferred { removeBackingDirectory(directory) } }
        let decodedURL = directory.appendingPathComponent("decoded.caf")
        try writePCM(from: output, reader: reader, duration: duration, to: decodedURL)
        try Task.checkCancellation()
        let file = try LocalPlaybackFile(backingURL: decodedURL, sourceURL: sourceURL, directory: directory)
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
/// Only immutable source/directory metadata is added; deletion is dispatched to a utility queue.
private final class LocalPlaybackFile: AVAudioFile, @unchecked Sendable {
    let sourceURL: URL
    private let directory: URL?

    init(backingURL: URL, sourceURL: URL, directory: URL? = nil) throws {
        self.sourceURL = sourceURL
        self.directory = directory
        try super.init(forReading: backingURL, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    deinit { if let directory { LocalAudioFile.removeBackingDirectory(directory) } }
}
