import AVFoundation
import CryptoKit
import Foundation

actor WaveformCacheService {
    static let shared = WaveformCacheService()

    private struct CacheRecord: Codable {
        let sourcePath: String
        let duration: TimeInterval
        let samples: [UInt16]
        let cacheKey: String
        let fileSize: Int64
        let modificationDate: Date
    }

    private let fileManager = FileManager.default
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    private let cacheRootURL: URL?

    init(cacheDirectoryURL: URL? = nil) {
        self.cacheRootURL = cacheDirectoryURL
        encoder.outputFormat = .binary
    }

    func loadSnapshot(for track: Track?, forceRegeneration: Bool = false) async -> WaveformSnapshot {
        guard let track else {
            return .unsupported("No track loaded")
        }
        guard track.mediaType == .audio else {
            return .unsupported("Waveform unavailable for video")
        }
        guard track.url.isFileURL else {
            return .unsupported("Waveform available for local audio files only")
        }

        do {
            let metadata = try fileMetadata(for: track.url)
            let cacheKey = Self.cacheKey(
                canonicalPath: metadata.canonicalPath,
                fileSize: metadata.fileSize,
                modificationDate: metadata.modificationDate
            )
            let cacheURL = try cacheURL(for: cacheKey)

            if forceRegeneration {
                try? fileManager.removeItem(at: cacheURL)
            } else if let cached = try loadCachedRecord(from: cacheURL, expectedKey: cacheKey) {
                return WaveformSnapshot(
                    sourcePath: cached.sourcePath,
                    duration: cached.duration,
                    samples: cached.samples,
                    state: .ready,
                    message: nil,
                    cacheKey: cached.cacheKey,
                    fileSize: cached.fileSize,
                    modificationDate: cached.modificationDate,
                    allowsSeeking: true,
                    isStreaming: false
                )
            }

            let generated: WaveformSnapshot
            do {
                generated = try await generateSnapshot(
                    for: track.url,
                    durationHint: track.duration,
                    cacheKey: cacheKey,
                    metadata: metadata
                )
            } catch {
                throw waveformError("Waveform decode failed", underlying: error)
            }

            do {
                try persist(snapshot: generated, to: cacheURL)
            } catch {
                throw waveformError("Waveform cache write failed", underlying: error)
            }
            return generated
        } catch is CancellationError {
            return .failed("Waveform generation cancelled")
        } catch {
            return .failed("Waveform unavailable: \(error.localizedDescription)")
        }
    }

    func clearCache(for track: Track?) async {
        guard let track, track.url.isFileURL else { return }
        do {
            let metadata = try fileMetadata(for: track.url)
            let cacheKey = Self.cacheKey(
                canonicalPath: metadata.canonicalPath,
                fileSize: metadata.fileSize,
                modificationDate: metadata.modificationDate
            )
            let cacheURL = try cacheURL(for: cacheKey)
            if fileManager.fileExists(atPath: cacheURL.path) {
                try fileManager.removeItem(at: cacheURL)
            }
        } catch {
            NSLog("WaveformCacheService: Failed to clear cache for %@: %@", track.url.path, error.localizedDescription)
        }
    }

    func clearAllCache() async {
        do {
            let directory = try cacheDirectoryURL()
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for fileURL in contents where fileURL.pathExtension == "plist" {
                try? fileManager.removeItem(at: fileURL)
            }
        } catch {
            NSLog("WaveformCacheService: Failed to clear cache: %@", error.localizedDescription)
        }
    }

    static func cacheKey(canonicalPath: String, fileSize: Int64, modificationDate: Date) -> String {
        let source = "\(canonicalPath)|\(fileSize)|\(modificationDate.timeIntervalSinceReferenceDate)"
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func generateSnapshot(
        for fileURL: URL,
        durationHint: TimeInterval?,
        cacheKey: String,
        metadata: (canonicalPath: String, fileSize: Int64, modificationDate: Date)
    ) async throws -> WaveformSnapshot {
        try Task.checkCancellation()

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to open audio file: \((error as NSError).localizedDescription)",
                NSUnderlyingErrorKey: error
            ])
        }
        let totalFrames = max(audioFile.length, 1)
        let fileDuration = durationHint ?? (Double(totalFrames) / audioFile.processingFormat.sampleRate)
        let processingFormat = audioFile.processingFormat
        let channelCount = Int(processingFormat.channelCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: 16_384) else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate PCM buffer"
            ])
        }
        var accumulator = WaveformBucketAccumulator(totalFrames: totalFrames)
        var frameIndex: Int64 = 0

        while true {
            try Task.checkCancellation()
            if audioFile.framePosition >= audioFile.length {
                break
            }
            do {
                try audioFile.read(into: buffer)
            } catch {
                throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to read audio samples: \((error as NSError).localizedDescription)",
                    NSUnderlyingErrorKey: error
                ])
            }
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 {
                break
            }

            for frame in 0..<frameLength {
                let amplitude: Float
                do {
                    amplitude = try Self.maximumAmplitude(in: buffer, frame: frame, channelCount: channelCount)
                } catch {
                    throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to inspect audio samples: \((error as NSError).localizedDescription)",
                        NSUnderlyingErrorKey: error
                    ])
                }
                accumulator.add(frameAmplitude: amplitude, at: frameIndex)
                frameIndex += 1
            }
        }

        return WaveformSnapshot(
            sourcePath: metadata.canonicalPath,
            duration: fileDuration,
            samples: accumulator.makeSamples(),
            state: .ready,
            message: nil,
            cacheKey: cacheKey,
            fileSize: metadata.fileSize,
            modificationDate: metadata.modificationDate,
            allowsSeeking: true,
            isStreaming: false
        )
    }

    private func fileMetadata(for url: URL) throws -> (canonicalPath: String, fileSize: Int64, modificationDate: Date) {
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        let attributes = try fileManager.attributesOfItem(atPath: canonicalURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? .distantPast
        return (canonicalURL.path, fileSize, modificationDate)
    }

    private func cacheDirectoryURL() throws -> URL {
        let base = cacheRootURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NullPlayer", isDirectory: true)
            .appendingPathComponent("WaveformCache", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        return base
    }

    private func cacheURL(for key: String) throws -> URL {
        try cacheDirectoryURL().appendingPathComponent("\(key).plist")
    }

    private func loadCachedRecord(from cacheURL: URL, expectedKey: String) throws -> CacheRecord? {
        guard fileManager.fileExists(atPath: cacheURL.path) else { return nil }
        let data = try Data(contentsOf: cacheURL)
        let record = try decoder.decode(CacheRecord.self, from: data)
        guard record.cacheKey == expectedKey else { return nil }
        return record
    }

    private func persist(snapshot: WaveformSnapshot, to cacheURL: URL) throws {
        guard snapshot.state == .ready,
              let sourcePath = snapshot.sourcePath,
              let cacheKey = snapshot.cacheKey,
              let fileSize = snapshot.fileSize,
              let modificationDate = snapshot.modificationDate else {
            return
        }

        let record = CacheRecord(
            sourcePath: sourcePath,
            duration: snapshot.duration,
            samples: snapshot.samples,
            cacheKey: cacheKey,
            fileSize: fileSize,
            modificationDate: modificationDate
        )
        let data = try encoder.encode(record)
        try data.write(to: cacheURL, options: .atomic)
    }

    private func waveformError(_ description: String, underlying: Error) -> NSError {
        let nsError = underlying as NSError
        let detail = "\(description): \(nsError.domain) (\(nsError.code)) \(nsError.localizedDescription)"
        return NSError(domain: "WaveformCacheService", code: nsError.code, userInfo: [
            NSLocalizedDescriptionKey: detail,
            NSUnderlyingErrorKey: nsError
        ])
    }

    private static func maximumAmplitude(
        in buffer: AVAudioPCMBuffer,
        frame: Int,
        channelCount: Int
    ) throws -> Float {
        let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            return try maximumInterleavedOrPlanarSample(
                audioBuffers: audioBuffers,
                frame: frame,
                channelCount: channelCount,
                isInterleaved: buffer.format.isInterleaved,
                type: Float.self
            ) { abs($0) }
        case .pcmFormatFloat64:
            return try maximumInterleavedOrPlanarSample(
                audioBuffers: audioBuffers,
                frame: frame,
                channelCount: channelCount,
                isInterleaved: buffer.format.isInterleaved,
                type: Double.self
            ) { Float(abs($0)) }
        case .pcmFormatInt16:
            return try maximumInterleavedOrPlanarSample(
                audioBuffers: audioBuffers,
                frame: frame,
                channelCount: channelCount,
                isInterleaved: buffer.format.isInterleaved,
                type: Int16.self
            ) { min(1, Float(abs(Int32($0))) / Float(Int16.max)) }
        case .pcmFormatInt32:
            return try maximumInterleavedOrPlanarSample(
                audioBuffers: audioBuffers,
                frame: frame,
                channelCount: channelCount,
                isInterleaved: buffer.format.isInterleaved,
                type: Int32.self
            ) { min(1, Float(abs(Double($0))) / Float(Int32.max)) }
        default:
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported PCM buffer format"
            ])
        }
    }

    private static func maximumInterleavedOrPlanarSample<Sample>(
        audioBuffers: UnsafeMutableAudioBufferListPointer,
        frame: Int,
        channelCount: Int,
        isInterleaved: Bool,
        type: Sample.Type,
        normalize: (Sample) -> Float
    ) throws -> Float {
        if isInterleaved {
            guard let rawData = audioBuffers.first?.mData else {
                throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Missing audio buffer data"
                ])
            }
            let samples = rawData.bindMemory(to: Sample.self, capacity: (frame + 1) * channelCount)
            let startIndex = frame * channelCount
            var amplitude: Float = 0
            for channel in 0..<channelCount {
                amplitude = max(amplitude, normalize(samples[startIndex + channel]))
            }
            return amplitude
        }

        var amplitude: Float = 0
        for channel in 0..<min(channelCount, audioBuffers.count) {
            guard let rawData = audioBuffers[channel].mData else { continue }
            let samples = rawData.bindMemory(to: Sample.self, capacity: frame + 1)
            amplitude = max(amplitude, normalize(samples[frame]))
        }
        return amplitude
    }
}
