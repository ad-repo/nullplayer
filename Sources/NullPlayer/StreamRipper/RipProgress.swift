import Foundation

/// Splits a pipe's output into lines, keeping a partial last line for the next chunk. Splits on
/// the newline byte before decoding, so a UTF-8 character cut between two reads survives.
/// Fed from one readability handler, which runs serially.
struct LineBuffer {
    private var pending = Data()

    mutating func lines(from data: Data) -> [Substring] {
        pending.append(data)
        guard let last = pending.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let complete = String(decoding: pending[..<last], as: UTF8.self)
        pending = Data(pending[pending.index(after: last)...])
        return complete.split(separator: "\n", omittingEmptySubsequences: true)
    }
}

/// Reads yt-dlp's `--progress-template` lines (`YtDlpProgressReader.template`) into a job's
/// fraction, time remaining and title. A video rip downloads its video stream, then its audio;
/// each runs 0–100 % and opens with a `[download] Destination:` line, which advances the stream.
final class YtDlpProgressReader: @unchecked Sendable {
    static let marker = "NPPROG|"
    static let args = ["--newline", "--progress-template",
                       "download:\(marker)%(progress._percent_str)s|%(progress.eta)s|%(info.title)s"]

    private let handle: RipJobHandle
    /// The share of the whole download each stream carries, in download order.
    private let streamWeights: [Double]
    private var buffer = LineBuffer()
    private var stream = -1
    private var streamStarted = false
    private var title: String?

    /// ponytail: a video's audio stream counted as 5 % of the download; weigh by stream sizes if
    /// the bar visibly jumps.
    init(handle: RipJobHandle, isVideo: Bool) {
        self.handle = handle
        self.streamWeights = isVideo ? [0.95, 0.05] : [1]
    }

    func consume(_ data: Data) {
        for line in buffer.lines(from: data) {
            if line.hasPrefix("[download] Destination:") {
                stream = min(stream + 1, streamWeights.count - 1)
                streamStarted = false
                continue
            }
            guard let start = line.range(of: Self.marker) else { continue }
            let fields = line[start.upperBound...].split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let percentText = fields[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
            guard let percent = Double(percentText) else { continue }
            // The HLS downloader reports one 100 % before a stream's first fragment.
            if !streamStarted, percent >= 100 { continue }
            streamStarted = true
            let current = max(stream, 0)
            let done = streamWeights.prefix(current).reduce(0, +)
            let fraction = min(1, done + streamWeights[current] * percent / 100)
            handle.report(.progress(fraction: fraction, remaining: Double(fields[1])))
            let name = String(fields[2]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name != "NA", name != title {
                title = name
                handle.report(.title(name))
            }
        }
    }
}

/// Reads an ffmpeg `-progress pipe:1` stream into a job's fraction and time remaining, and logs
/// one line every five minutes.
final class FFmpegProgressReader: @unchecked Sendable {
    private static let logInterval: TimeInterval = 300

    private let handle: RipJobHandle
    private let duration: Double?
    private var buffer = LineBuffer()
    private var fields: [String: String] = [:]
    private var lastLog = Date()

    init(handle: RipJobHandle, duration: Double?) {
        self.handle = handle
        self.duration = duration
    }

    func consume(_ data: Data) {
        for line in buffer.lines(from: data) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            // `progress=` closes each report block.
            if key == "progress" { report(final: value == "end") } else { fields[key] = value }
        }
    }

    private func report(final: Bool) {
        let position = fields["out_time_us"].flatMap(Double.init).map { $0 / 1_000_000 }
        let speed = fields["speed"].flatMap { Double($0.replacingOccurrences(of: "x", with: "")) }
        if let duration, duration > 0, let position {
            let remaining = speed.flatMap { $0 > 0 ? max(0, duration - position) / $0 : nil }
            handle.report(.progress(fraction: min(1, position / duration), remaining: remaining))
        }
        guard final || Date().timeIntervalSince(lastLog) >= Self.logInterval else { return }
        lastLog = Date()
        let at = fields["out_time"].map { String($0.prefix(8)) } ?? "?"
        let bytes = fields["total_size"].flatMap(Int64.init)
            .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?"
        StreamRipper.log(handle.id, "encode at \(at) speed=\(fields["speed"] ?? "?") written=\(bytes)")
    }
}
