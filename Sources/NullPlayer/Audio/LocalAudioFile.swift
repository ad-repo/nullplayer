import AVFoundation

/// Opens local audio for the AVAudioEngine pipeline. Core Audio can recognize Opus in an
/// MPEG-4 container yet report zero frames (and fail on read); AVAssetReader can decode it.
enum LocalAudioFile {
    static func open(_ url: URL) throws -> AVAudioFile {
        var nativeError: Error?
        do {
            let file = try AVAudioFile(forReading: url)
            guard isMPEG4(url), file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatOpus else {
                return file
            }
            // Keep the native path on systems where Apple's MPEG-4 Opus reader works.
            if file.length > 0,
               let probe = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1) {
                do {
                    try file.read(into: probe, frameCount: 1)
                    file.framePosition = 0
                    if probe.frameLength > 0 { return file }
                } catch { /* Try the asset reader below. */ }
            }
        } catch {
            guard isMPEG4(url) else { throw error }
            nativeError = error
        }
        do {
            return try decodeOpusAsset(url)
        } catch {
            throw nativeError ?? error
        }
    }

    /// The backing CAF is an implementation detail, never a playlist/library identity.
    static func sourceURL(of file: AVAudioFile) -> URL {
        (file as? DecodedAudioFile)?.sourceURL ?? file.url
    }

    private static func isMPEG4(_ url: URL) -> Bool {
        url.isFileURL && ["m4a", "mp4", "m4b"].contains(url.pathExtension.lowercased())
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LocalAudioFile", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func decodeOpusAsset(_ url: URL) throws -> AVAudioFile {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first,
              let description = track.formatDescriptions.first.map({ $0 as! CMAudioFormatDescription }),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              asbd.pointee.mFormatID == kAudioFormatOpus else {
            throw failure("No supported Opus audio track in MPEG-4 file")
        }

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
        defer { if !transferred { try? FileManager.default.removeItem(at: directory) } }
        let decodedURL = directory.appendingPathComponent("decoded.caf")
        try writePCM(from: output, reader: reader, duration: asset.duration, to: decodedURL)
        let file = try DecodedAudioFile(decodedURL: decodedURL, sourceURL: url, directory: directory)
        transferred = true
        return file
    }

    private static func writePCM(from output: AVAssetReaderTrackOutput, reader: AVAssetReader,
                                 duration: CMTime, to url: URL) throws {
        var writer: AVAudioFile?
        var written: AVAudioFramePosition = 0
        while let sample = output.copyNextSampleBuffer() {
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

/// Holding the file keeps its backing audio alive through queued player-node schedules too.
private final class DecodedAudioFile: AVAudioFile, @unchecked Sendable {
    let sourceURL: URL
    private let directory: URL

    init(decodedURL: URL, sourceURL: URL, directory: URL) throws {
        self.sourceURL = sourceURL
        self.directory = directory
        try super.init(forReading: decodedURL, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
