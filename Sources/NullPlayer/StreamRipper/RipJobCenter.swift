import AppKit

extension Notification.Name {
    /// A rip job started, changed or finished, or the history changed. Posted on the main actor.
    static let ripJobsDidChange = Notification.Name("NullPlayer.ripJobsDidChange")
}

/// The one list of rip and YouTube download jobs. Jobs belong to it, not to the Rip window: the
/// window and the Windows menu count are views of it, so closing or rebuilding the window never
/// touches a job. It also owns the notification-panel rows, the failure alert and the history.
@MainActor
final class RipJobCenter {
    static let shared = RipJobCenter()

    static let showsActivityNotificationsKey = "ripShowsActivityNotifications"

    /// Running jobs and those finished this session, newest first.
    private(set) var jobs: [RipJob] = []
    let history: RipHistoryStore
    private let presentsFailures: Bool

    init(history: RipHistoryStore? = nil, presentsFailures: Bool = true) {
        self.history = history ?? .shared
        self.presentsFailures = presentsFailures
    }

    var runningCount: Int { jobs.filter { !$0.phase.isFinished }.count }

    /// Whether running jobs show rows in the top-right notification panel. Off by default.
    var showsActivityNotifications: Bool {
        get { UserDefaults.standard.bool(forKey: Self.showsActivityNotificationsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.showsActivityNotificationsKey)
            jobs.forEach(syncActivityRow)
        }
    }

    // MARK: - Starting jobs

    /// Starts a rip, or returns the same rip already in progress (same URL and choices).
    @discardableResult
    func startRip(url: URL, mode: StreamRipper.Mode, folder: String, followUp: RipFollowUp = RipFollowUp()) -> RipJob {
        if let running = jobs.first(where: { $0.duplicates(url: url, mode: mode) }) { return running }
        let job = register(RipRequest(url: url, kind: .rip(mode, folder: folder)), followUp: followUp)
        StreamRipper.run(job.handle, mode: mode, sourceURL: url, folder: folder)
        return job
    }

    /// Registers a download that runs outside `startRip` (the YouTube source); the caller ends it
    /// with `finish`.
    func beginExternal(url: URL, summary: String) -> RipJobHandle {
        register(RipRequest(url: url, kind: .youtube(summary: summary))).handle
    }

    private func register(_ request: RipRequest, followUp: RipFollowUp = RipFollowUp()) -> RipJob {
        let id = String(UUID().uuidString.prefix(8))
        let handle = RipJobHandle(id: id) { [weak self] update in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply(update, toJob: id) } }
        }
        let job = RipJob(handle: handle, request: request, followUp: followUp)
        StreamRipper.log(id, "start host=\(request.url.host ?? "?") \(request.summary)")
        jobs.insert(job, at: 0)
        syncActivityRow(job)
        postChange()
        return job
    }

    // MARK: - Updates

    private func apply(_ update: RipJobUpdate, toJob id: String) {
        guard let job = jobs.first(where: { $0.id == id }), !job.phase.isFinished else { return }
        switch update {
        case .phase(let phase):
            job.phase = phase
            job.fraction = nil
            job.remaining = nil
        case .progress(let fraction, let remaining):
            job.fraction = fraction
            job.remaining = remaining
        case .title(let title):
            job.title = title
        }
        syncActivityRow(job)
        postChange()
    }

    /// Ends a job: `error` nil and not cancelled is success. `sizeBytes` is read by the caller,
    /// off the main thread: the destination can be a network volume.
    func finish(_ handle: RipJobHandle, outputPath: String?, sizeBytes: Int64?, error: String?) {
        guard let job = jobs.first(where: { $0.handle === handle }), !job.phase.isFinished else { return }
        let entry = job.finish(outputPath: outputPath, sizeBytes: sizeBytes, error: error)
        StreamRipper.log(job.id, "\(entry.outcome.rawValue) after \(StreamRipper.formatDuration(entry.finishedAt.timeIntervalSince(entry.startedAt)))")
        history.append(entry)
        syncActivityRow(job)
        postChange()
        if entry.outcome == .done, let outputPath { job.followUp.run(jobID: job.id, path: outputPath) }
        if entry.outcome == .failed, presentsFailures {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.presentFailure(of: job) } }
        }
    }

    // MARK: - User actions

    func cancel(_ job: RipJob) {
        guard !job.phase.isFinished else { return }
        StreamRipper.log(job.id, "cancelled by user (\(job.phase.rawValue))")
        job.handle.cancel()
    }

    func clearFinished() {
        jobs.removeAll { $0.phase.isFinished }
        postChange()
    }

    func removeHistoryEntry(id: String) {
        history.remove(id: id)
        postChange()
    }

    func clearHistory() {
        history.clear()
        postChange()
    }

    /// Terminates every running job's process tree before returning; called as the app quits,
    /// so no encode outlives it.
    func terminateAll() {
        let running = jobs.filter { !$0.phase.isFinished }
        for job in running { StreamRipper.log(job.id, "terminated on app quit (\(job.phase.rawValue))") }
        RipJobHandle.cancelAndWait(running.map(\.handle))
    }

    // MARK: - Presentation

    private func postChange() {
        NotificationCenter.default.post(name: .ripJobsDidChange, object: self)
    }

    private func syncActivityRow(_ job: RipJob) {
        let rowID = "rip-\(job.id)"
        guard showsActivityNotifications, !job.phase.isFinished else {
            ActivityCenter.shared.hide(id: rowID)
            return
        }
        let percent = job.fraction.map { " \(Int($0 * 100))%" } ?? ""
        ActivityCenter.shared.show(id: rowID, message: "\(job.phase.title)\(percent) — \(job.title)")
    }

    private func presentFailure(of job: RipJob) {
        let alert = NSAlert()
        alert.messageText = "Rip Failed"
        // yt-dlp errors can be long; keep the tail which usually has the cause.
        alert.informativeText = job.title + "\n\n" + String((job.error ?? "").suffix(600))
        alert.alertStyle = .warning
        var actions: [() -> Void] = []
        // A YouTube download has no rip choices and is not retried here.
        if case .rip(let mode, let folder) = job.request.kind {
            alert.addButton(withTitle: "Retry")
            actions.append { self.startRip(url: job.request.url, mode: mode, folder: folder, followUp: job.followUp) }
        }
        alert.addButton(withTitle: "Show in Stream Ripper")
        actions.append { WindowManager.shared.showRip() }
        alert.addButton(withTitle: "OK")
        actions.append {}
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if actions.indices.contains(index) { actions[index]() }
    }

    // MARK: - Orphans

    /// Terminates yt-dlp and ffmpeg processes a previous NullPlayer left running when it was
    /// killed (a relaunch's `kill -9` skips `applicationWillTerminate`). They are recognised by a
    /// rip staging path in their arguments and by having no parent left (`ppid` 1). Called at
    /// launch, before the temp-item reaper, off the main thread.
    nonisolated static func terminateOrphanedRipProcesses() {
        for entry in ProcessTable.snapshot().entries where entry.parent == 1 {
            guard entry.command.contains("ffmpeg") || entry.command.contains("yt-dlp"),
                  ["nullplayer-rip-", "nullplayer-ytdl-"].contains(where: { entry.command.contains($0) })
            else { continue }
            kill(entry.pid, SIGTERM)
            NSLog("StreamRipper: terminated orphaned rip process pid=%d", entry.pid)
        }
    }
}
