import Foundation

/// One rip or YouTube download, as the Rip window, the Windows menu count and the history see it.
/// Main-actor state only; the background work reaches it through its `RipJobHandle`.
@MainActor
final class RipJob {
    enum Source: String, Codable, Sendable {
        case rip
        case youtube
    }

    enum Phase: String, Codable, Sendable {
        case downloading
        case queuedForEncode
        case converting
        case moving
        case done
        case failed
        case cancelled

        var isFinished: Bool { self == .done || self == .failed || self == .cancelled }

        var title: String {
            switch self {
            case .downloading: "Downloading"
            case .queuedForEncode: "Queued for encode"
            case .converting: "Converting"
            case .moving: "Saving"
            case .done: "Done"
            case .failed: "Failed"
            case .cancelled: "Cancelled"
            }
        }
    }

    let handle: RipJobHandle
    var id: String { handle.id }
    let source: Source
    let url: URL
    /// The rip's choices; nil for a YouTube download, which the window cannot retry.
    let mode: StreamRipper.Mode?
    /// The choices as the window and history show them (`video 4K original`, `youtube video`).
    let summary: String
    let folder: String?
    /// What to do with the file once an audio rip is done.
    let followUp: RipFollowUp
    let startedAt = Date()
    var finishedAt: Date?
    var title: String
    var phase: Phase = .downloading
    /// 0...1, or nil while the phase reports no progress.
    var fraction: Double?
    var remaining: TimeInterval?
    var outputPath: String?
    /// The finished file's size, read once off the main thread when the job ends.
    var sizeBytes: Int64?
    var error: String?
    /// When the job joined the encode queue, for its place in line.
    var queuedAt: Date?

    init(source: Source, url: URL, mode: StreamRipper.Mode?, summary: String, folder: String?,
         followUp: RipFollowUp = RipFollowUp()) {
        self.handle = RipJobHandle(id: String(UUID().uuidString.prefix(8)))
        self.source = source
        self.url = url
        self.mode = mode
        self.summary = summary
        self.folder = folder
        self.followUp = followUp
        self.title = url.absoluteString
    }

    /// Whether this job and a new request are the same rip still in progress.
    func duplicates(url: URL, mode: StreamRipper.Mode) -> Bool {
        !phase.isFinished && self.url == url && self.mode == mode
    }
}

/// What the background work reports about its job.
enum RipJobUpdate: Sendable {
    case phase(RipJob.Phase)
    case progress(fraction: Double?, remaining: TimeInterval?)
    case title(String)
}

/// The thread-safe side of a job: the background rip reports through it and checks it for
/// cancellation, and a cancel from the main actor terminates whichever process it is running.
final class RipJobHandle: @unchecked Sendable {
    let id: String
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    /// Set by `RipJobCenter`; delivers each update on the main actor.
    var onUpdate: (@Sendable (RipJobUpdate) -> Void)?

    init(id: String) { self.id = id }

    var isCancelled: Bool { lock.withLock { cancelled } }

    func report(_ update: RipJobUpdate) { onUpdate?(update) }

    /// Starts `task` as this job's running process, unless the job is already cancelled.
    func launch(_ task: Process) throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            try task.run()
            process = task
        }
    }

    /// Clears the running process once it has exited.
    func processExited() { lock.withLock { process = nil } }

    /// Marks the job cancelled and terminates its running process and everything it started:
    /// yt-dlp runs ffmpeg as a child, which outlives a terminated yt-dlp and keeps writing into
    /// the staging folder the cancel then deletes.
    func cancel() {
        let running: Process? = lock.withLock {
            cancelled = true
            return process
        }
        guard let running, running.isRunning else { return }
        for pid in Self.descendants(of: running.processIdentifier) { kill(pid, SIGTERM) }
        running.terminate()
    }

    /// Every process below `root`, children before their own children.
    static func descendants(of root: pid_t) -> [pid_t] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid="]
        let out = Pipe()
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        var children: [pid_t: [pid_t]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ")
            guard fields.count == 2, let pid = pid_t(fields[0]), let parent = pid_t(fields[1]) else { continue }
            children[parent, default: []].append(pid)
        }
        var result: [pid_t] = []
        var frontier = [root]
        while let next = frontier.popLast() {
            let found = children[next] ?? []
            result += found
            frontier += found
        }
        return result
    }
}
