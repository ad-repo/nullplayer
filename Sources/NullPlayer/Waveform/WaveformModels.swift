import AppKit
import Foundation

enum WaveformLoadState: String, Codable, Equatable {
    case loading
    case ready
    case unsupported
    case failed
}

struct WaveformSnapshot: Codable, Equatable {
    static let bucketCount = 4096

    var sourcePath: String?
    var duration: TimeInterval
    var samples: [UInt16]
    var state: WaveformLoadState
    var message: String?
    var cacheKey: String?
    var fileSize: Int64?
    var modificationDate: Date?
    var allowsSeeking: Bool
    var isStreaming: Bool

    var isInteractive: Bool {
        state == .ready && duration > 0 && !samples.isEmpty && allowsSeeking
    }

    static var loading: WaveformSnapshot {
        WaveformSnapshot(duration: 0, samples: [], state: .loading, message: "Generating waveform...", allowsSeeking: false, isStreaming: false)
    }

    static var loadingStream: WaveformSnapshot {
        WaveformSnapshot(duration: 0, samples: [], state: .loading, message: "Waiting for stream audio...", allowsSeeking: false, isStreaming: true)
    }

    static func unsupported(_ message: String) -> WaveformSnapshot {
        WaveformSnapshot(duration: 0, samples: [], state: .unsupported, message: message, allowsSeeking: false, isStreaming: false)
    }

    static func failed(_ message: String) -> WaveformSnapshot {
        WaveformSnapshot(duration: 0, samples: [], state: .failed, message: message, allowsSeeking: false, isStreaming: false)
    }
}

struct WaveformCuePoint: Equatable {
    let performer: String?
    let title: String
    let milliseconds: Int
}

struct WaveformRenderColors {
    let background: NSColor
    let waveform: NSColor
    let playedWaveform: NSColor
    let cuePoint: NSColor
    let playhead: NSColor
    let text: NSColor
    let selection: NSColor
}

struct WaveformBucketAccumulator {
    let totalFrames: Int64
    let bucketCount: Int
    private(set) var maxima: [Float]

    init(totalFrames: Int64, bucketCount: Int = WaveformSnapshot.bucketCount) {
        self.totalFrames = max(totalFrames, 1)
        self.bucketCount = bucketCount
        self.maxima = Array(repeating: 0, count: bucketCount)
    }

    mutating func add(frameAmplitude: Float, at frameIndex: Int64) {
        guard bucketCount > 0 else { return }
        let normalized = min(max(frameAmplitude, 0), 1)
        let bucket = min(bucketCount - 1, Int((frameIndex * Int64(bucketCount)) / totalFrames))
        maxima[bucket] = max(maxima[bucket], normalized)
    }

    func makeSamples() -> [UInt16] {
        maxima.map { maxValue in
            UInt16(min(32767, max(0, Int(round(Double(maxValue) * 32767.0)))))
        }
    }
}

final class StreamingWaveformAccumulator {
    private static let amplitudeLookup: [UInt16] = (0...128).map { distance in
        let normalized = min(1.0, Double(distance) / 127.0)
        return UInt16(min(32767, Int(round(normalized * 32767.0))))
    }

    private let bucketCount: Int
    private let rollingWindowDuration: TimeInterval
    private var trackDuration: TimeInterval?
    private var progressiveSamples: [UInt16]
    private var rollingSamples: [UInt16]
    private var rollingEpochs: [Int64]

    init(
        bucketCount: Int = WaveformSnapshot.bucketCount,
        duration: TimeInterval?,
        rollingWindowDuration: TimeInterval = 30
    ) {
        self.bucketCount = bucketCount
        self.rollingWindowDuration = rollingWindowDuration
        self.trackDuration = duration.flatMap { $0 > 0 ? $0 : nil }
        self.progressiveSamples = Array(repeating: 0, count: bucketCount)
        self.rollingSamples = Array(repeating: 0, count: bucketCount)
        self.rollingEpochs = Array(repeating: .min, count: bucketCount)
    }

    func reset(duration: TimeInterval?) {
        trackDuration = duration.flatMap { $0 > 0 ? $0 : nil }
        progressiveSamples = Array(repeating: 0, count: bucketCount)
        rollingSamples = Array(repeating: 0, count: bucketCount)
        rollingEpochs = Array(repeating: .min, count: bucketCount)
    }

    func updateDuration(_ duration: TimeInterval?) {
        let normalized = duration.flatMap { $0 > 0 ? $0 : nil }
        if trackDuration == normalized {
            return
        }
        trackDuration = normalized
        if normalized != nil {
            progressiveSamples = Array(repeating: 0, count: bucketCount)
        }
    }

    func append(left: [UInt8], right: [UInt8], sampleRate: Double, currentTime: TimeInterval) {
        let sampleCount = min(left.count, right.count)
        guard sampleCount > 0, sampleRate > 0 else { return }

        let chunkDuration = Double(sampleCount) / sampleRate
        let startTime = max(0, currentTime - chunkDuration)

        if let trackDuration, trackDuration > 0 {
            appendProgressive(
                left: left,
                right: right,
                sampleCount: sampleCount,
                startTime: startTime,
                chunkDuration: chunkDuration,
                duration: trackDuration
            )
        } else {
            appendRolling(
                left: left,
                right: right,
                sampleCount: sampleCount,
                startTime: startTime,
                chunkDuration: chunkDuration
            )
        }
    }

    func snapshot(sourcePath: String?, currentTime: TimeInterval) -> WaveformSnapshot {
        if let trackDuration, trackDuration > 0 {
            return WaveformSnapshot(
                sourcePath: sourcePath,
                duration: trackDuration,
                samples: progressiveSamples,
                state: .ready,
                message: nil,
                cacheKey: nil,
                fileSize: nil,
                modificationDate: nil,
                allowsSeeking: true,
                isStreaming: true
            )
        }

        let bucketSpan = rollingWindowDuration / Double(bucketCount)
        let currentEpoch = Int64(floor(max(0, currentTime) / bucketSpan))
        let oldestEpoch = currentEpoch - Int64(bucketCount) + 1
        var orderedSamples = Array(repeating: UInt16(0), count: bucketCount)

        for offset in 0..<bucketCount {
            let epoch = oldestEpoch + Int64(offset)
            let bucket = normalizedBucket(for: epoch)
            if rollingEpochs[bucket] == epoch {
                orderedSamples[offset] = rollingSamples[bucket]
            }
        }

        return WaveformSnapshot(
            sourcePath: sourcePath,
            duration: rollingWindowDuration,
            samples: orderedSamples,
            state: .ready,
            message: "Live stream waveform",
            cacheKey: nil,
            fileSize: nil,
            modificationDate: nil,
            allowsSeeking: false,
            isStreaming: true
        )
    }

    private func appendProgressive(
        left: [UInt8],
        right: [UInt8],
        sampleCount: Int,
        startTime: TimeInterval,
        chunkDuration: TimeInterval,
        duration: TimeInterval
    ) {
        let bucketScale = Double(bucketCount) / duration
        let timeStep = chunkDuration / Double(max(sampleCount, 1))
        var time = startTime
        for index in 0..<sampleCount {
            let bucket = min(bucketCount - 1, max(0, Int(time * bucketScale)))
            progressiveSamples[bucket] = max(progressiveSamples[bucket], amplitudeSample(left: left[index], right: right[index]))
            time += timeStep
        }
    }

    private func appendRolling(
        left: [UInt8],
        right: [UInt8],
        sampleCount: Int,
        startTime: TimeInterval,
        chunkDuration: TimeInterval
    ) {
        let inverseBucketSpan = Double(bucketCount) / rollingWindowDuration
        let timeStep = chunkDuration / Double(max(sampleCount, 1))
        var time = startTime

        for index in 0..<sampleCount {
            let epoch = Int64(max(0, time) * inverseBucketSpan)
            let bucket = normalizedBucket(for: epoch)
            let amplitude = amplitudeSample(left: left[index], right: right[index])
            if rollingEpochs[bucket] != epoch {
                rollingEpochs[bucket] = epoch
                rollingSamples[bucket] = amplitude
            } else {
                rollingSamples[bucket] = max(rollingSamples[bucket], amplitude)
            }
            time += timeStep
        }
    }

    private func normalizedBucket(for epoch: Int64) -> Int {
        Int(((epoch % Int64(bucketCount)) + Int64(bucketCount)) % Int64(bucketCount))
    }

    private func amplitudeSample(left: UInt8, right: UInt8) -> UInt16 {
        let leftAmplitude = abs(Int(left) - 128)
        let rightAmplitude = abs(Int(right) - 128)
        let peak = max(leftAmplitude, rightAmplitude)
        return Self.amplitudeLookup[min(peak, 128)]
    }
}

enum WaveformCueSheetParser {
    static func parse(for track: Track?) -> [WaveformCuePoint] {
        guard let track, track.url.isFileURL else { return [] }
        return parse(cueURL: track.url.deletingPathExtension().appendingPathExtension("cue"))
    }

    static func parse(cueURL: URL) -> [WaveformCuePoint] {
        guard let data = try? Data(contentsOf: cueURL),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            return []
        }

        var cuePoints: [WaveformCuePoint] = []
        var currentPerformer: String?
        var currentTitle: String?
        var currentTrackSeen = false

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("TRACK ") {
                currentPerformer = nil
                currentTitle = nil
                currentTrackSeen = true
                continue
            }

            guard currentTrackSeen else { continue }

            if line.hasPrefix("PERFORMER ") {
                currentPerformer = quotedValue(in: line)
            } else if line.hasPrefix("TITLE ") {
                currentTitle = quotedValue(in: line)
            } else if line.hasPrefix("INDEX ") {
                let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard components.count >= 3 else { continue }
                let timecode = components[2]
                let parts = timecode.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 3 else { continue }
                let milliseconds = (parts[0] * 60 * 1000) + (parts[1] * 1000) + ((parts[2] * 1000) / 75)
                cuePoints.append(
                    WaveformCuePoint(
                        performer: currentPerformer,
                        title: currentTitle ?? "Track \(cuePoints.count + 1)",
                        milliseconds: milliseconds
                    )
                )
            }
        }

        return cuePoints.sorted { $0.milliseconds < $1.milliseconds }
    }

    private static func quotedValue(in line: String) -> String? {
        guard let firstQuote = line.firstIndex(of: "\""),
              let lastQuote = line.lastIndex(of: "\""),
              firstQuote != lastQuote else {
            return nil
        }
        let start = line.index(after: firstQuote)
        return String(line[start..<lastQuote])
    }
}
