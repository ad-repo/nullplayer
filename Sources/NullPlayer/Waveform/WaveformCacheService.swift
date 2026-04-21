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
        let fileSize: Int64?
        let modificationDate: Date?
    }

    private struct CacheDescriptor {
        let sourcePath: String
        let cacheKey: String
        let durationHint: TimeInterval?
        let fileSize: Int64?
        let modificationDate: Date?
        let isStreaming: Bool
        let sourceURL: URL
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

        do {
            let descriptor = try cacheDescriptor(for: track)
            let cacheURL = try cacheURL(for: descriptor.cacheKey)

            if forceRegeneration {
                try? fileManager.removeItem(at: cacheURL)
            } else if let cached = try loadCachedRecord(from: cacheURL, expectedKey: descriptor.cacheKey) {
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
                    isStreaming: descriptor.isStreaming
                )
            }

            let generated: WaveformSnapshot
            do {
                generated = try await generateSnapshot(with: descriptor)
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
        guard let track else { return }
        do {
            guard let cacheKey = try cacheKey(for: track) else { return }
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

    static func serviceCacheKey(
        serviceIdentity: String,
        duration: TimeInterval,
        bitrate: Int?,
        sampleRate: Int?
    ) -> String {
        let source = "service|\(serviceIdentity)|\(Int(round(duration * 1000)))|\(bitrate ?? 0)|\(sampleRate ?? 0)"
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheDescriptor(for track: Track) throws -> CacheDescriptor {
        if track.url.isFileURL {
            let metadata = try fileMetadata(for: track.url)
            return CacheDescriptor(
                sourcePath: metadata.canonicalPath,
                cacheKey: Self.cacheKey(
                    canonicalPath: metadata.canonicalPath,
                    fileSize: metadata.fileSize,
                    modificationDate: metadata.modificationDate
                ),
                durationHint: track.duration,
                fileSize: metadata.fileSize,
                modificationDate: metadata.modificationDate,
                isStreaming: false,
                sourceURL: track.url
            )
        }

        guard !track.isStreamingPlaceholder,
              let serviceIdentity = track.streamingServiceIdentity else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Waveform prerender unavailable for live streams"
            ])
        }
        let duration = track.duration ?? 0
        guard duration > 0 else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Waveform prerender unavailable until stream duration is known"
            ])
        }

        return CacheDescriptor(
            sourcePath: "service:\(serviceIdentity)",
            cacheKey: Self.serviceCacheKey(
                serviceIdentity: serviceIdentity,
                duration: duration,
                bitrate: track.bitrate,
                sampleRate: track.sampleRate
            ),
            durationHint: duration,
            fileSize: nil,
            modificationDate: nil,
            isStreaming: true,
            sourceURL: track.url
        )
    }

    private func cacheKey(for track: Track) throws -> String? {
        if track.url.isFileURL {
            let metadata = try fileMetadata(for: track.url)
            return Self.cacheKey(
                canonicalPath: metadata.canonicalPath,
                fileSize: metadata.fileSize,
                modificationDate: metadata.modificationDate
            )
        }
        guard !track.isStreamingPlaceholder,
              let serviceIdentity = track.streamingServiceIdentity else {
            return nil
        }
        let duration = track.duration ?? 0
        guard duration > 0 else { return nil }
        return Self.serviceCacheKey(
            serviceIdentity: serviceIdentity,
            duration: duration,
            bitrate: track.bitrate,
            sampleRate: track.sampleRate
        )
    }

    private func generateSnapshot(with descriptor: CacheDescriptor) async throws -> WaveformSnapshot {
        if descriptor.sourceURL.isFileURL {
            return try await generateLocalSnapshot(with: descriptor)
        }
        return try await generateServiceSnapshot(with: descriptor)
    }

    private func generateLocalSnapshot(with descriptor: CacheDescriptor) async throws -> WaveformSnapshot {
        try Task.checkCancellation()

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: descriptor.sourceURL)
        } catch {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to open audio file: \((error as NSError).localizedDescription)",
                NSUnderlyingErrorKey: error
            ])
        }
        let totalFrames = max(audioFile.length, 1)
        let fileDuration = descriptor.durationHint ?? (Double(totalFrames) / audioFile.processingFormat.sampleRate)
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
            sourcePath: descriptor.sourcePath,
            duration: fileDuration,
            samples: accumulator.makeSamples(),
            state: .ready,
            message: nil,
            cacheKey: descriptor.cacheKey,
            fileSize: descriptor.fileSize,
            modificationDate: descriptor.modificationDate,
            allowsSeeking: true,
            isStreaming: false
        )
    }

    private func generateServiceSnapshot(with descriptor: CacheDescriptor) async throws -> WaveformSnapshot {
        do {
            return try await generateServiceSnapshotViaAssetReader(with: descriptor)
        } catch {
            NSLog(
                "WaveformCacheService: Remote asset-reader prerender failed for %@: %@",
                descriptor.sourcePath,
                error.localizedDescription
            )
        }
        try Task.checkCancellation()
        return try await generateServiceSnapshotViaDownload(with: descriptor)
    }

    private func generateServiceSnapshotViaAssetReader(with descriptor: CacheDescriptor) async throws -> WaveformSnapshot {
        try Task.checkCancellation()

        let duration = descriptor.durationHint ?? 0
        guard duration > 0 else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Service stream duration unavailable"
            ])
        }

        let asset = AVURLAsset(url: descriptor.sourceURL)

        // Modern async API (macOS 13+): replaces synchronous tracks(withMediaType:) + statusOfValue.
        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to load audio tracks: \(error.localizedDescription)",
                NSUnderlyingErrorKey: error
            ])
        }

        guard let audioTrack = audioTracks.first else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No audio track available for waveform prerender"
            ])
        }

        let sampleRate = (await Self.sampleRate(for: audioTrack)) ?? 44_100
        let totalFrames = max(Int64(round(duration * sampleRate)), 1)
        var accumulator = WaveformBucketAccumulator(totalFrames: totalFrames)
        var frameIndex: Int64 = 0

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create asset reader: \((error as NSError).localizedDescription)",
                NSUnderlyingErrorKey: error
            ])
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Cannot attach audio output for waveform prerender"
            ])
        }
        reader.add(output)

        guard reader.startReading() else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Waveform reader failed to start: \((reader.error as NSError?)?.localizedDescription ?? "Unknown error")"
            ])
        }

        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            let amplitudes = try Self.sampleAmplitudes(from: sampleBuffer)
            for amplitude in amplitudes {
                accumulator.add(frameAmplitude: amplitude, at: frameIndex)
                frameIndex += 1
            }
            CMSampleBufferInvalidate(sampleBuffer)
        }

        switch reader.status {
        case .completed:
            break
        case .cancelled:
            throw CancellationError()
        case .failed:
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Waveform reader failed: \((reader.error as NSError?)?.localizedDescription ?? "Unknown error")",
                NSUnderlyingErrorKey: reader.error as Any
            ])
        default:
            break
        }
        guard frameIndex > 0 else {
            throw NSError(domain: "WaveformCacheService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No audio samples decoded from remote stream"
            ])
        }

        return WaveformSnapshot(
            sourcePath: descriptor.sourcePath,
            duration: duration,
            samples: accumulator.makeSamples(),
            state: .ready,
            message: nil,
            cacheKey: descriptor.cacheKey,
            fileSize: nil,
            modificationDate: nil,
            allowsSeeking: true,
            isStreaming: true
        )
    }

    private func generateServiceSnapshotViaDownload(with descriptor: CacheDescriptor) async throws -> WaveformSnapshot {
        try Task.checkCancellation()

        let (tempDownloadURL, response) = try await URLSession.shared.download(from: descriptor.sourceURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw NSError(domain: "WaveformCacheService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Waveform download failed with HTTP \(httpResponse.statusCode)"
            ])
        }

        // Use the source URL's path extension (strips query string) rather than
        // the temp download path, which has no extension and would resolve to ".bin"
        let sourceExt = descriptor.sourceURL.pathExtension
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("waveform-prerender-\(UUID().uuidString)")
            .appendingPathExtension(sourceExt.isEmpty ? "bin" : sourceExt)

        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: tempDownloadURL, to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let localDescriptor = CacheDescriptor(
            sourcePath: descriptor.sourcePath,
            cacheKey: descriptor.cacheKey,
            durationHint: descriptor.durationHint,
            fileSize: nil,
            modificationDate: nil,
            isStreaming: true,
            sourceURL: localURL
        )
        let localSnapshot = try await generateLocalSnapshot(with: localDescriptor)
        return WaveformSnapshot(
            sourcePath: descriptor.sourcePath,
            duration: descriptor.durationHint ?? localSnapshot.duration,
            samples: localSnapshot.samples,
            state: .ready,
            message: nil,
            cacheKey: descriptor.cacheKey,
            fileSize: nil,
            modificationDate: nil,
            allowsSeeking: true,
            isStreaming: true
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
              let cacheKey = snapshot.cacheKey else {
            return
        }

        let record = CacheRecord(
            sourcePath: sourcePath,
            duration: snapshot.duration,
            samples: snapshot.samples,
            cacheKey: cacheKey,
            fileSize: snapshot.fileSize,
            modificationDate: snapshot.modificationDate
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

    private static func sampleRate(for track: AVAssetTrack) async -> Double? {
        // Modern async API (macOS 13+): replaces synchronous formatDescriptions accessor.
        let descriptions: [CMFormatDescription]
        do {
            descriptions = try await track.load(.formatDescriptions)
        } catch {
            Log.general.warningPublic("WaveformCacheService: failed to load formatDescriptions: \(error.localizedDescription)")
            return nil
        }
        for description in descriptions {
            guard let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
                continue
            }
            let rate = asbdPointer.pointee.mSampleRate
            if rate > 0 {
                return rate
            }
        }
        return nil
    }

    private static func sampleAmplitudes(from sampleBuffer: CMSampleBuffer) throws -> [Float] {
        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else { return [] }

        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            throw NSError(domain: "WaveformCacheService", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to read PCM samples from audio buffer list"
            ])
        }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        guard !audioBuffers.isEmpty else { return [] }

        var amplitudes = Array(repeating: Float(0), count: sampleCount)
        if audioBuffers.count == 1 {
            let channels = max(Int(audioBuffers[0].mNumberChannels), 1)
            guard let mData = audioBuffers[0].mData else { return amplitudes }
            let samples = mData.bindMemory(to: Float.self, capacity: sampleCount * channels)
            for frame in 0..<sampleCount {
                let base = frame * channels
                var peak: Float = 0
                for channel in 0..<channels {
                    peak = max(peak, abs(samples[base + channel]))
                }
                amplitudes[frame] = min(1, max(0, peak))
            }
            return amplitudes
        }

        for frame in 0..<sampleCount {
            var peak: Float = 0
            for buffer in audioBuffers {
                guard let mData = buffer.mData else { continue }
                let samples = mData.bindMemory(to: Float.self, capacity: sampleCount)
                peak = max(peak, abs(samples[frame]))
            }
            amplitudes[frame] = min(1, max(0, peak))
        }
        return amplitudes
    }
}
