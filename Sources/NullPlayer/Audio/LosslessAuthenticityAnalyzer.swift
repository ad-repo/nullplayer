import AVFoundation
import Accelerate
import CryptoKit
import Foundation

enum LosslessAuthenticityStatus: Equatable {
    case disabled
    case notApplicable(reason: String)
    case pending
    case available(LosslessAuthenticityResult)
    case inconclusive(LosslessAuthenticityResult)
    case failed(reason: String)
}

struct LosslessAuthenticityResult: Equatable {
    let confidencePercent: Int
    let classification: Classification
    let evidence: [Evidence]
    let coverage: Coverage
    let analyzedDuration: TimeInterval
    let analyzedFrames: Int64
    let sampleRate: Double
    let channelCount: Int

    enum Classification: String {
        case highConfidenceGenuine
        case moderateConfidence
        case lowConfidencePossibleLossySource
        case veryLowConfidenceLikelyLossyOrUpsampled
        case inconclusive
    }

    struct Evidence: Equatable {
        let label: String
        let value: String
        let severity: Severity
    }

    enum Severity: String {
        case info
        case warning
        case strongWarning
    }

    enum Coverage: String {
        case sampledFile
        case boundedRemoteSample
        case liveStreamSample
    }
}

struct LosslessAnalysisRequest {
    let track: Track
    let playbackURL: URL
    let generation: Int
    let sourceKind: LosslessAnalysisSourceKind
    let maxAnalysisSeconds: TimeInterval
    /// Safety cap on the volume of *decoded* Float32 PCM pulled from a remote asset.
    /// The `maxAnalysisSeconds` frame cap is the primary bound; this is a secondary
    /// guard so a malformed/over-long stream can't accumulate unbounded memory. It does
    /// not bound raw network transfer.
    let maxRemoteBytes: Int64
}

enum LosslessAnalysisSourceKind {
    case localFile
    case serviceStream
    case internetRadioOrUnknownStream
}

final class LosslessAuthenticityCache {
    private var statuses: [String: LosslessAuthenticityStatus] = [:]
    private let queue = DispatchQueue(label: "com.nullplayer.lossless-authenticity-cache")

    func status(forKey key: String) -> LosslessAuthenticityStatus? {
        queue.sync { statuses[key] }
    }

    func store(_ status: LosslessAuthenticityStatus, forKey key: String) {
        guard !status.isPending else { return }
        queue.sync {
            statuses[key] = status
        }
    }
}

extension LosslessAuthenticityStatus {
    fileprivate var isPending: Bool {
        if case .pending = self { return true }
        return false
    }
}

enum LosslessAuthenticityAnalyzer {
    fileprivate static let frameLength = 16_384
    fileprivate static let hopLength = 8_192
    fileprivate static let usefulFrameFloor = 20
    fileprivate static let silenceRMSDb: Float = -60
    /// Wall-clock bound on loading an `AVURLAsset`'s `tracks` property. Remote/icy
    /// streams can otherwise block the calling queue indefinitely.
    fileprivate static let assetLoadTimeoutSeconds: TimeInterval = 15
    /// Overall wall-clock bound on the remote read loop, so a slow stream cannot
    /// keep the decode running far past the analysis window.
    fileprivate static let assetReadDeadlineSeconds: TimeInterval = 30

    enum AnalysisError: LocalizedError {
        case noAudioSamples
        case unsupportedPCMFormat
        case assetReaderFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioSamples:
                return "No audio samples could be decoded for authenticity analysis"
            case .unsupportedPCMFormat:
                return "Decoded audio was not available as Float32 PCM"
            case .assetReaderFailed(let reason):
                return reason
            }
        }
    }

    static func status(for request: LosslessAnalysisRequest) -> LosslessAuthenticityStatus {
        if let notApplicable = notApplicableStatus(for: request.track, playbackURL: request.playbackURL) {
            return notApplicable
        }

        do {
            let coverage: LosslessAuthenticityResult.Coverage
            let decoded: DecodedPCM
            switch request.sourceKind {
            case .localFile:
                coverage = .sampledFile
                decoded = try decodeLocalFile(url: request.playbackURL, maxAnalysisSeconds: request.maxAnalysisSeconds)
            case .serviceStream:
                coverage = .boundedRemoteSample
                decoded = try decodeAsset(url: request.playbackURL, maxAnalysisSeconds: request.maxAnalysisSeconds, maxRemoteBytes: request.maxRemoteBytes)
            case .internetRadioOrUnknownStream:
                coverage = .liveStreamSample
                decoded = try decodeAsset(url: request.playbackURL, maxAnalysisSeconds: request.maxAnalysisSeconds, maxRemoteBytes: request.maxRemoteBytes)
            }

            let result = analyze(
                channels: decoded.channels,
                sampleRate: decoded.sampleRate,
                coverage: coverage
            )
            return result.classification == .inconclusive ? .inconclusive(result) : .available(result)
        } catch {
            // A remote sample we couldn't fetch/decode is an expected best-effort
            // outcome, not a user-facing failure. AVAssetReader cannot read many
            // streamed/HLS or header-authenticated endpoints (it reports a generic
            // "Operation Stopped"), so degrade those to a friendly "not applicable"
            // rather than surfacing the raw decode error. Only a genuine local-file
            // decode failure is reported as `.failed`.
            switch request.sourceKind {
            case .internetRadioOrUnknownStream:
                return .notApplicable(reason: "live stream sample unavailable")
            case .serviceStream:
                return .notApplicable(reason: "remote sample unavailable")
            case .localFile:
                return .failed(reason: error.localizedDescription)
            }
        }
    }

    static func notApplicableStatus(for track: Track, playbackURL: URL? = nil) -> LosslessAuthenticityStatus? {
        guard track.mediaType == .audio else {
            return .notApplicable(reason: "video track")
        }

        let url = playbackURL ?? track.url
        let classification = formatClassification(url: url, contentType: track.contentType)
        switch classification {
        case .losslessLooking:
            return nil
        case .lossy:
            return .notApplicable(reason: "lossy format")
        case .unknown:
            return .notApplicable(reason: "format is not lossless-looking")
        }
    }

    static func cacheKey(for track: Track, playbackURL: URL) -> String? {
        if playbackURL.isFileURL {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: playbackURL.path),
                  let fileSize = attributes[.size] as? NSNumber,
                  let modificationDate = attributes[.modificationDate] as? Date else {
                return nil
            }
            let canonicalPath = (try? URL(fileURLWithPath: playbackURL.path).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? playbackURL.path
            return digest("local|\(canonicalPath)|\(fileSize.int64Value)|\(modificationDate.timeIntervalSinceReferenceDate)")
        }

        guard let identity = track.streamingServiceIdentity else { return nil }
        return digest("service|\(identity)|\(track.bitrate ?? 0)|\(track.sampleRate ?? 0)|\(track.contentType ?? "")")
    }

    static func formatClassification(url: URL, contentType: String?) -> FormatClassification {
        let normalizedType = contentType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let ext = url.pathExtension.lowercased()

        if let normalizedType {
            if normalizedType.contains("flac") ||
                normalizedType.contains("alac") ||
                normalizedType.contains("x-wav") ||
                normalizedType.contains("wav") ||
                normalizedType.contains("aiff") ||
                normalizedType.contains("aifc") ||
                normalizedType.contains("lpcm") ||
                normalizedType.contains("linear-pcm") {
                return .losslessLooking
            }
            if normalizedType.contains("mpeg") ||
                normalizedType.contains("mp3") ||
                normalizedType.contains("aac") ||
                normalizedType.contains("ogg") ||
                normalizedType.contains("opus") {
                return .lossy
            }
            if normalizedType == "audio/mp4" || normalizedType == "audio/m4a" {
                return .lossy
            }
        }

        switch ext {
        case "flac", "alac", "wav", "wave", "aiff", "aif", "aifc", "pcm":
            return .losslessLooking
        case "mp3", "aac", "ogg", "oga", "opus", "m4a":
            return .lossy
        default:
            return .unknown
        }
    }

    static func analyze(
        channels: [[Float]],
        sampleRate: Double,
        coverage: LosslessAuthenticityResult.Coverage
    ) -> LosslessAuthenticityResult {
        guard sampleRate > 0, let shortest = channels.map(\.count).min(), shortest >= frameLength else {
            return inconclusiveResult(
                coverage: coverage,
                sampleRate: sampleRate,
                channelCount: channels.count,
                reason: "Insufficient decoded audio"
            )
        }

        var analyzer = SpectrumAccumulator(sampleRate: sampleRate)
        analyzer.consume(channels: channels, frameCount: shortest)
        return score(features: analyzer.features(), sampleRate: sampleRate, channelCount: channels.count, coverage: coverage)
    }

    static func score(
        features: LosslessSpectralFeatures,
        sampleRate: Double,
        channelCount: Int,
        coverage: LosslessAuthenticityResult.Coverage
    ) -> LosslessAuthenticityResult {
        var evidence = [LosslessAuthenticityResult.Evidence]()

        guard features.usefulFrameCount >= usefulFrameFloor,
              features.activeGroupCount >= 8 else {
            evidence.append(.init(label: "Scan coverage", value: "insufficient active high-frequency content", severity: .info))
            return LosslessAuthenticityResult(
                confidencePercent: 50,
                classification: .inconclusive,
                evidence: evidence,
                coverage: coverage,
                analyzedDuration: features.analyzedDuration,
                analyzedFrames: Int64(features.usefulFrameCount),
                sampleRate: sampleRate,
                channelCount: channelCount
            )
        }

        let brickwallEvidence = brickwallEvidence(for: features)
        let upsamplePenalty = upsamplePenalty(features: features, sampleRate: sampleRate)
        let confidence = max(0, min(100, 100 - brickwallEvidence.penalty - upsamplePenalty))

        // Severity reflects the detected cutoff frequency itself, not the combined
        // brickwall penalty, so the label can't read "~20 kHz (strongWarning)".
        let cutoffSeverity: LosslessAuthenticityResult.Severity
        if features.effectiveCutoffHz < 17_000 {
            cutoffSeverity = .strongWarning
        } else if features.effectiveCutoffHz < 19_500 {
            cutoffSeverity = .warning
        } else {
            cutoffSeverity = .info
        }
        evidence.append(.init(
            label: "Spectral cutoff",
            value: formatFrequency(features.effectiveCutoffHz),
            severity: cutoffSeverity
        ))
        evidence.append(.init(
            label: "High-band energy",
            value: formatRatio(features.highBandEnergyRatio),
            severity: features.highBandEnergyRatio < 0.015 ? .warning : .info
        ))
        if sampleRate >= 88_200 {
            evidence.append(.init(
                label: "Upsample check",
                value: features.ultrasonicEnergyRatio < 0.004 ? "no significant content above 22.05 kHz" : "ultrasonic content present",
                severity: upsamplePenalty >= 15 ? .warning : .info
            ))
        }
        if brickwallEvidence.isWeakHighBandOnly && upsamplePenalty == 0 {
            evidence.append(.init(
                label: "Scan coverage",
                value: "high-band energy alone is not decisive",
                severity: .info
            ))
            return LosslessAuthenticityResult(
                confidencePercent: 50,
                classification: .inconclusive,
                evidence: evidence,
                coverage: coverage,
                analyzedDuration: features.analyzedDuration,
                analyzedFrames: Int64(features.usefulFrameCount),
                sampleRate: sampleRate,
                channelCount: channelCount
            )
        }
        return LosslessAuthenticityResult(
            confidencePercent: confidence,
            classification: classification(for: confidence),
            evidence: evidence,
            coverage: coverage,
            analyzedDuration: features.analyzedDuration,
            analyzedFrames: Int64(features.usefulFrameCount),
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    static func normalizedToneDB(amplitude: Float, sampleRate: Double = 44_100, frequency: Double = 1_000) -> Float {
        let frameLength = Self.frameLength
        let binFrequency = sampleRate / Double(frameLength)
        let alignedFrequency = round(frequency / binFrequency) * binFrequency
        let samples = (0..<frameLength).map { index in
            amplitude * sinf(2 * .pi * Float(alignedFrequency) * Float(index) / Float(sampleRate))
        }
        var analyzer = SpectrumAccumulator(sampleRate: sampleRate)
        analyzer.consume(channels: [samples], frameCount: samples.count)
        return analyzer.features().peakDb
    }

    private static func decodeLocalFile(url: URL, maxAnalysisSeconds: TimeInterval) throws -> DecodedPCM {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let targetFrames = min(file.length, AVAudioFramePosition(maxAnalysisSeconds * sampleRate))
        guard targetFrames > 0 else { throw AnalysisError.noAudioSamples }

        var channels = Array(repeating: [Float](), count: channelCount)
        let chunkFrames: AVAudioFrameCount = 16_384
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)!

        let segmentCount = file.length > targetFrames && targetFrames >= AVAudioFramePosition(frameLength * 3) ? 3 : 1
        let segmentFrames = targetFrames / AVAudioFramePosition(segmentCount)
        let starts: [AVAudioFramePosition]
        if segmentCount == 3 {
            starts = [
                0,
                max(0, (file.length / 2) - (segmentFrames / 2)),
                max(0, file.length - segmentFrames)
            ]
        } else {
            starts = [0]
        }

        for start in starts {
            file.framePosition = start
            var framesRead: AVAudioFramePosition = 0
            while framesRead < segmentFrames {
                let requested = AVAudioFrameCount(min(Int64(chunkFrames), segmentFrames - framesRead))
                try file.read(into: buffer, frameCount: requested)
                guard buffer.frameLength > 0 else { break }
                guard let floatData = buffer.floatChannelData else { throw AnalysisError.unsupportedPCMFormat }

                for channel in 0..<channelCount {
                    let pointer = floatData[channel]
                    channels[channel].append(contentsOf: UnsafeBufferPointer(start: pointer, count: Int(buffer.frameLength)))
                }
                framesRead += AVAudioFramePosition(buffer.frameLength)
            }
        }

        guard channels.first?.isEmpty == false else { throw AnalysisError.noAudioSamples }
        return DecodedPCM(channels: channels, sampleRate: sampleRate)
    }

    private static func decodeAsset(url: URL, maxAnalysisSeconds: TimeInterval, maxRemoteBytes: Int64) throws -> DecodedPCM {
        let asset = AVURLAsset(url: url)
        // Bound the (otherwise unbounded) remote property load before touching `tracks`.
        try loadAssetTracks(asset, timeout: assetLoadTimeoutSeconds)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw AnalysisError.assetReaderFailed("No audio track available")
        }

        let sampleRate = sampleRate(for: audioTrack) ?? 44_100
        let channelCount = max(channelCount(for: audioTrack) ?? 2, 1)
        let maxFrames = Int(maxAnalysisSeconds * sampleRate)
        var channels = Array(repeating: [Float](), count: channelCount)
        var bytesRead: Int64 = 0

        let reader = try AVAssetReader(asset: asset)
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
            throw AnalysisError.assetReaderFailed("Cannot attach audio output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw AnalysisError.assetReaderFailed(reader.error?.localizedDescription ?? "Asset reader failed to start")
        }

        let readDeadline = Date().addingTimeInterval(assetReadDeadlineSeconds)
        while reader.status == .reading,
              channels.first?.count ?? 0 < maxFrames,
              bytesRead < maxRemoteBytes {
            if Date() >= readDeadline {
                reader.cancelReading()
                break
            }
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sampleBuffer) }
            let decoded = try sampleBufferChannels(sampleBuffer, expectedChannels: channelCount)
            for channel in 0..<min(channels.count, decoded.count) {
                let remaining = max(0, maxFrames - channels[channel].count)
                channels[channel].append(contentsOf: decoded[channel].prefix(remaining))
            }
            bytesRead += Int64(decoded.reduce(0) { $0 + $1.count * MemoryLayout<Float>.size })
        }

        if reader.status == .failed {
            throw AnalysisError.assetReaderFailed(reader.error?.localizedDescription ?? "Asset reader failed")
        }
        if channels.first?.isEmpty != false {
            throw AnalysisError.noAudioSamples
        }
        return DecodedPCM(channels: channels, sampleRate: sampleRate)
    }

    private static func sampleBufferChannels(_ sampleBuffer: CMSampleBuffer, expectedChannels: Int) throws -> [[Float]] {
        var blockBuffer: CMBlockBuffer?
        var sizeNeeded = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, sizeNeeded > 0 else { throw AnalysisError.unsupportedPCMFormat }

        var storage = [UInt8](repeating: 0, count: sizeNeeded)
        return try storage.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { throw AnalysisError.unsupportedPCMFormat }
            let audioBufferList = baseAddress.assumingMemoryBound(to: AudioBufferList.self)
            status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: audioBufferList,
                bufferListSize: sizeNeeded,
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &blockBuffer
            )
            guard status == noErr else { throw AnalysisError.unsupportedPCMFormat }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
            if buffers.count > 1 {
                return buffers.map { buffer in
                    guard let data = buffer.mData else { return [] }
                    let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
                }
            }

            guard let data = buffers.first?.mData else {
                return Array(repeating: [], count: expectedChannels)
            }
            let values = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: frameCount * max(expectedChannels, 1)
            )
            var channels = Array(repeating: [Float](), count: max(expectedChannels, 1))
            for frame in 0..<frameCount {
                for channel in channels.indices {
                    channels[channel].append(values[frame * channels.count + channel])
                }
            }
            return channels
        }
    }

    /// Loads the asset's `tracks` property with a wall-clock timeout. Runs on the
    /// caller's (background) queue and blocks it for at most `timeout` seconds so a
    /// stalled remote/icy stream cannot hang the analysis indefinitely.
    private static func loadAssetTracks(_ asset: AVURLAsset, timeout: TimeInterval) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var error: NSError?
            let status = asset.statusOfValue(forKey: "tracks", error: &error)
            if status != .loaded {
                loadError = error ?? AnalysisError.assetReaderFailed("Tracks unavailable (status \(status.rawValue))")
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            asset.cancelLoading()
            throw AnalysisError.assetReaderFailed("Asset load timed out")
        }
        if let loadError {
            throw AnalysisError.assetReaderFailed(loadError.localizedDescription)
        }
    }

    private static func sampleRate(for track: AVAssetTrack) -> Double? {
        guard let description = track.formatDescriptions.first else { return nil }
        let formatDescription = description as! CMFormatDescription
        return CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee.mSampleRate
    }

    private static func channelCount(for track: AVAssetTrack) -> Int? {
        guard let description = track.formatDescriptions.first else { return nil }
        let formatDescription = description as! CMFormatDescription
        return CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription).map { Int($0.pointee.mChannelsPerFrame) }
    }

    private static func brickwallPenalty(features: LosslessSpectralFeatures) -> Int {
        brickwallEvidence(for: features).penalty
    }

    private static func brickwallEvidence(for features: LosslessSpectralFeatures) -> BrickwallEvidence {
        let cutoffPenalty: Int
        if features.effectiveCutoffHz < 17_000 {
            cutoffPenalty = 45
        } else if features.effectiveCutoffHz < 19_500 {
            let ratio = (19_500 - features.effectiveCutoffHz) / 2_500
            cutoffPenalty = Int((20 + 20 * ratio).rounded())
        } else {
            cutoffPenalty = 0
        }

        let sharpnessPenalty: Int
        if features.cutoffSharpnessDbPerKhz > 18 {
            sharpnessPenalty = 30
        } else if features.cutoffSharpnessDbPerKhz > 10 {
            sharpnessPenalty = 15
        } else {
            sharpnessPenalty = 0
        }

        let holePenalty: Int
        if features.spectralHoleScore > 0.7 {
            holePenalty = 32
        } else if features.spectralHoleScore > 0.45 {
            holePenalty = 18
        } else {
            holePenalty = 0
        }

        let hasCorroboratingBrickwallEvidence = cutoffPenalty > 0 || sharpnessPenalty > 0 || holePenalty > 0
        let highBandPenalty: Int
        if features.highBandEnergyRatio < 0.006 {
            highBandPenalty = hasCorroboratingBrickwallEvidence ? 42 : 18
        } else if features.highBandEnergyRatio < 0.02 {
            highBandPenalty = hasCorroboratingBrickwallEvidence ? 18 : 8
        } else {
            highBandPenalty = 0
        }

        let evidence = max(cutoffPenalty, highBandPenalty, sharpnessPenalty, holePenalty)
        return BrickwallEvidence(
            penalty: min(evidence, 45),
            isWeakHighBandOnly: highBandPenalty > 0 && cutoffPenalty == 0 && sharpnessPenalty == 0 && holePenalty == 0
        )
    }

    private static func upsamplePenalty(features: LosslessSpectralFeatures, sampleRate: Double) -> Int {
        guard sampleRate >= 88_200 else { return 0 }
        if features.ultrasonicEnergyRatio < 0.0015 { return 20 }
        if features.ultrasonicEnergyRatio < 0.004 { return 12 }
        return 0
    }

    private static func classification(for confidence: Int) -> LosslessAuthenticityResult.Classification {
        switch confidence {
        case 85...100: return .highConfidenceGenuine
        case 60...84: return .moderateConfidence
        case 35...59: return .lowConfidencePossibleLossySource
        default: return .veryLowConfidenceLikelyLossyOrUpsampled
        }
    }

    private static func inconclusiveResult(
        coverage: LosslessAuthenticityResult.Coverage,
        sampleRate: Double,
        channelCount: Int,
        reason: String
    ) -> LosslessAuthenticityResult {
        LosslessAuthenticityResult(
            confidencePercent: 50,
            classification: .inconclusive,
            evidence: [.init(label: "Scan coverage", value: reason, severity: .info)],
            coverage: coverage,
            analyzedDuration: 0,
            analyzedFrames: 0,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
    }

    private static func formatFrequency(_ hz: Double) -> String {
        guard hz.isFinite, hz > 0 else { return "unavailable" }
        return String(format: "~%.1f kHz", hz / 1_000)
    }

    private static func formatRatio(_ ratio: Double) -> String {
        if ratio < 0.006 { return "very low above 16 kHz" }
        if ratio < 0.02 { return "low above 16 kHz" }
        return "present above 16 kHz"
    }

    private static func digest(_ source: String) -> String {
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum FormatClassification {
    case losslessLooking
    case lossy
    case unknown
}

struct LosslessSpectralFeatures: Equatable {
    let usefulFrameCount: Int
    let analyzedDuration: TimeInterval
    let effectiveCutoffHz: Double
    let highBandEnergyRatio: Double
    let ultrasonicEnergyRatio: Double
    let cutoffSharpnessDbPerKhz: Double
    let spectralHoleScore: Double
    let activeBandwidthHz: Double
    let activeGroupCount: Int
    let peakDb: Float
}

private struct DecodedPCM {
    let channels: [[Float]]
    let sampleRate: Double
}

private struct BrickwallEvidence {
    let penalty: Int
    let isWeakHighBandOnly: Bool
}

private struct SpectrumAccumulator {
    private let sampleRate: Double
    private let frameLength = 16_384
    private let hopLength = 8_192
    private let halfLength = 8_192
    private var window = [Float](repeating: 0, count: 16_384)
    private var log2n: vDSP_Length = 14
    private var setup: FFTSetup?

    private var usefulFrames = 0
    private var sumDb = [Float](repeating: 0, count: 8_193)
    private var peakDb: Float = -120
    private var lowMidPowers = [Double]()
    private var highPower = 0.0
    private var referencePower = 0.0
    private var ultrasonicPower = 0.0
    private var audibleReferencePower = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        vDSP_hann_window(&window, vDSP_Length(frameLength), Int32(vDSP_HANN_NORM))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    mutating func consume(channels: [[Float]], frameCount: Int) {
        guard let setup else { return }
        var offset = 0
        while offset + frameLength <= frameCount {
            let rms = broadbandRMS(channels: channels, offset: offset)
            let rmsDb = 20 * log10(max(rms, 1e-12))
            if rmsDb > LosslessAuthenticityAnalyzer.silenceRMSDb {
                accumulateFrame(channels: channels, offset: offset, setup: setup)
            }
            offset += hopLength
        }
    }

    func features() -> LosslessSpectralFeatures {
        guard usefulFrames > 0 else {
            return LosslessSpectralFeatures(
                usefulFrameCount: 0,
                analyzedDuration: 0,
                effectiveCutoffHz: 0,
                highBandEnergyRatio: 0,
                ultrasonicEnergyRatio: 0,
                cutoffSharpnessDbPerKhz: 0,
                spectralHoleScore: 1,
                activeBandwidthHz: 0,
                activeGroupCount: 0,
                peakDb: peakDb
            )
        }

        let averageDb = sumDb.map { $0 / Float(usefulFrames) }
        let medianLowMid = median(values: averageDb.enumerated().compactMap { index, value in
            let frequency = frequency(forBin: index)
            return (frequency >= 20 && frequency <= 8_000) ? value : nil
        })
        let peakAbove8k = averageDb.enumerated().compactMap { index, value -> Float? in
            frequency(forBin: index) >= 8_000 ? value : nil
        }.max() ?? -120
        let floor = max(medianLowMid - 55, peakAbove8k - 65)
        let smoothed = smoothedDb(averageDb)

        var effectiveCutoff = 0.0
        for (index, value) in smoothed.enumerated() {
            let frequency = frequency(forBin: index)
            if frequency <= min(sampleRate / 2, 48_000), value > floor {
                effectiveCutoff = frequency
            }
        }

        let db12 = averageDbForRange(12_000...14_000, values: averageDb)
        let db20 = averageDbForRange(18_000...20_000, values: averageDb)
        let sharpness = max(0, Double(db12 - db20) / 8.0)
        let highGroups = octaveGroups(from: 14_000, through: min(20_000, sampleRate / 2), values: averageDb)
        let spectralHoleScore = highGroups.isEmpty ? 1.0 : Double(highGroups.filter { $0 < floor }.count) / Double(highGroups.count)
        let activeThreshold = max(peakDb - 80, -100)
        let activeGroupCount = octaveGroups(from: 2_000, through: min(20_000, sampleRate / 2), values: smoothed).filter { $0 > activeThreshold }.count
        let highRatio = highPower / max(referencePower, 1e-18)
        let ultrasonicRatio = ultrasonicPower / max(audibleReferencePower, 1e-18)

        return LosslessSpectralFeatures(
            usefulFrameCount: usefulFrames,
            analyzedDuration: Double(usefulFrames * hopLength) / sampleRate,
            effectiveCutoffHz: effectiveCutoff,
            highBandEnergyRatio: highRatio,
            ultrasonicEnergyRatio: ultrasonicRatio,
            cutoffSharpnessDbPerKhz: sharpness,
            spectralHoleScore: spectralHoleScore,
            activeBandwidthHz: effectiveCutoff,
            activeGroupCount: activeGroupCount,
            peakDb: peakDb
        )
    }

    private mutating func accumulateFrame(channels: [[Float]], offset: Int, setup: FFTSetup) {
        var frameMax = [Float](repeating: -120, count: halfLength + 1)
        for channel in channels {
            guard offset + frameLength <= channel.count else { continue }
            let spectrum = spectrumDb(samples: channel, offset: offset, setup: setup)
            for index in frameMax.indices {
                frameMax[index] = max(frameMax[index], spectrum[index])
            }
        }

        usefulFrames += 1
        for index in frameMax.indices {
            sumDb[index] += frameMax[index]
            peakDb = max(peakDb, frameMax[index])
            let frequency = frequency(forBin: index)
            let power = pow(10, Double(frameMax[index]) / 10)
            if frequency >= 20 && frequency < 8_000 {
                lowMidPowers.append(power)
            }
            if frequency >= 16_000 && frequency <= min(20_000, sampleRate / 2) {
                highPower += power
            }
            if frequency >= 2_000 && frequency < 16_000 {
                referencePower += power
            }
            if sampleRate >= 88_200, frequency > 22_050 && frequency <= min(sampleRate / 2, 48_000) {
                ultrasonicPower += power
            }
            if frequency >= 2_000 && frequency <= 16_000 {
                audibleReferencePower += power
            }
        }
    }

    private func spectrumDb(samples: [Float], offset: Int, setup: FFTSetup) -> [Float] {
        var frame = Array(samples[offset..<(offset + frameLength)])
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(frameLength))

        var real = [Float](repeating: 0, count: halfLength)
        var imaginary = [Float](repeating: 0, count: halfLength)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                frame.withUnsafeBufferPointer { framePointer in
                    framePointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfLength) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &split, 1, vDSP_Length(halfLength))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
            }
        }

        let coherentGain = max(window.reduce(0, +) / Float(frameLength), 1e-12)
        let scale = Float(1.0 / Double(frameLength)) / coherentGain
        var output = [Float](repeating: -120, count: halfLength + 1)
        output[0] = db(abs(real[0]) * scale)
        output[halfLength] = db(abs(imaginary[0]) * scale)
        if halfLength > 1 {
            for index in 1..<halfLength {
                output[index] = db(hypot(real[index], imaginary[index]) * scale)
            }
        }
        return output
    }

    private func broadbandRMS(channels: [[Float]], offset: Int) -> Float {
        var total: Float = 0
        var count = 0
        for channel in channels where offset + frameLength <= channel.count {
            var rms: Float = 0
            vDSP_rmsqv(Array(channel[offset..<(offset + frameLength)]), 1, &rms, vDSP_Length(frameLength))
            total += rms
            count += 1
        }
        return count == 0 ? 0 : total / Float(count)
    }

    private func db(_ magnitude: Float) -> Float {
        20 * log10(max(magnitude, 1e-12))
    }

    private func frequency(forBin index: Int) -> Double {
        Double(index) * sampleRate / Double(frameLength)
    }

    private func averageDbForRange(_ range: ClosedRange<Double>, values: [Float]) -> Float {
        let selected = values.enumerated().compactMap { index, value -> Float? in
            range.contains(frequency(forBin: index)) ? value : nil
        }
        guard !selected.isEmpty else { return -120 }
        return selected.reduce(0, +) / Float(selected.count)
    }

    private func smoothedDb(_ values: [Float]) -> [Float] {
        values.indices.map { index in
            let frequency = max(frequency(forBin: index), 20)
            let width = max(2, Int(round((frequency * (pow(2.0, 1.0 / 12.0) - 1.0)) / (sampleRate / Double(frameLength)))))
            let lower = max(0, index - width)
            let upper = min(values.count - 1, index + width)
            return values[lower...upper].max() ?? -120
        }
    }

    private func octaveGroups(from start: Double, through end: Double, values: [Float]) -> [Float] {
        guard start < end else { return [] }
        var groups = [Float]()
        var lower = start
        while lower < end {
            let upper = min(end, lower * pow(2.0, 1.0 / 12.0))
            groups.append(averageDbForRange(lower...upper, values: values))
            lower = upper
        }
        return groups
    }

    private func median(values: [Float]) -> Float {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
