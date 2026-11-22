import Foundation

/// What a job was asked to do: enough to list it, match a duplicate and retry it.
struct RipRequest: Codable, Equatable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        /// A rip from the Stream Ripper window into `folder`; it can be retried.
        case rip(StreamRipper.Mode, folder: String)
        /// A download the YouTube source runs (`youtube audio`, `youtube video`); listed, never
        /// retried here.
        case youtube(summary: String)
    }

    let url: URL
    let kind: Kind

    /// The choices as the window and history show them (`video 4K original`, `youtube video`).
    var summary: String {
        switch kind {
        case .rip(let mode, _): mode.description
        case .youtube(let summary): summary
        }
    }

    var isYouTube: Bool { if case .youtube = kind { true } else { false } }
}

/// One rip or YouTube download, as the Rip window, the Windows menu count and the history see it.
/// Main-actor state only; the background work reaches it through its `RipJobHandle`.
@MainActor
final class RipJob {
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
    let request: RipRequest
    /// What to do with the file once an audio rip is done.
    let followUp: RipFollowUp
    let startedAt = Date()
    private(set) var finishedAt: Date?
    var title: String
    var phase: Phase = .downloading
    /// 0...1, or nil while the phase reports no progress.
    var fraction: Double?
    var remaining: TimeInterval?
    private(set) var outputPath: String?
    /// The finished file's size, read once off the main thread when the job ends.
    private(set) var sizeBytes: Int64?
    private(set) var error: String?

    init(handle: RipJobHandle, request: RipRequest, followUp: RipFollowUp = RipFollowUp()) {
        self.handle = handle
        self.request = request
        self.followUp = followUp
        self.title = request.url.absoluteString
    }

    /// Whether this job and a new rip request are the same rip still in progress.
    func duplicates(url: URL, mode: StreamRipper.Mode) -> Bool {
        guard !phase.isFinished, case .rip(let running, _) = request.kind else { return false }
        return request.url == url && running == mode
    }

    /// Ends the job: `error` nil and not cancelled is success. Returns it as History keeps it.
    func finish(outputPath: String?, sizeBytes: Int64?, error: String?) -> RipHistoryEntry {
        let finishedAt = Date()
        phase = handle.isCancelled ? .cancelled : (error == nil ? .done : .failed)
        self.finishedAt = finishedAt
        self.outputPath = outputPath
        self.sizeBytes = sizeBytes
        self.error = phase == .failed ? error : nil
        fraction = phase == .done ? 1 : nil
        remaining = nil
        return RipHistoryEntry(id: id, request: request, title: title, outcome: phase, startedAt: startedAt,
                               finishedAt: finishedAt, outputPath: outputPath, sizeBytes: sizeBytes, error: self.error)
    }
}

/// What the background work reports about its job.
enum RipJobUpdate: Sendable {
    case phase(RipJob.Phase)
    case progress(fraction: Double?, remaining: TimeInterval?)
    case title(String)
}

/// The thread-safe side of a job: the background rip reports through it and checks it for
/// cancellation, and a cancel terminates whichever process it is running.
final class RipJobHandle: @unchecked Sendable {
    let id: String
    /// Delivers each update; `RipJobCenter` hops it to the main actor.
    private let onUpdate: (@Sendable (RipJobUpdate) -> Void)?
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    init(id: String, onUpdate: (@Sendable (RipJobUpdate) -> Void)? = nil) {
        self.id = id
        self.onUpdate = onUpdate
    }

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

    /// Marks the job cancelled and returns at once: its process tree is terminated on a
    /// background queue, and a wait for the encoder ends.
    func cancel() {
        guard let running = markCancelled() else { return }
        DispatchQueue.global(qos: .userInitiated).async { ProcessTable.terminateTrees(of: [running]) }
    }

    /// Cancels every handle and terminates their process trees before returning, from one `ps`
    /// snapshot; for the app's quit, which cannot wait on a background queue.
    static func cancelAndWait(_ handles: [RipJobHandle]) {
        ProcessTable.terminateTrees(of: handles.compactMap { $0.markCancelled() })
    }

    private func markCancelled() -> Process? {
        let running = lock.withLock {
            cancelled = true
            return process
        }
        RipEncodeQueue.wakeWaiters()
        return running
    }
}
