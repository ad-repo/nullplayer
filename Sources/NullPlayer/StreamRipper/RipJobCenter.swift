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
        let job = register(RipJob(source: .rip, url: url, mode: mode, summary: mode.description, folder: folder,
                                  followUp: followUp))
        StreamRipper.log(job.id, "start host=\(url.host ?? "?") \(mode)")
        StreamRipper.run(job.handle, mode: mode, sourceURL: url, folder: folder)
        return job
    }

    /// Registers a download that runs outside `startRip` (the YouTube source); the caller ends it
    /// with `finish`.
    func beginExternal(source: RipJob.Source, url: URL, summary: String) -> RipJobHandle {
        let job = register(RipJob(source: source, url: url, mode: nil, summary: summary, folder: nil))
        StreamRipper.log(job.id, "start host=\(url.host ?? "?") \(summary)")
        return job.handle
    }

    private func register(_ job: RipJob) -> RipJob {
        // Weak: the job owns its handle, which owns this closure.
        job.handle.onUpdate = { [weak self, weak job] update in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let job else { return }
                    self?.apply(update, to: job)
                }
            }
        }
        jobs.insert(job, at: 0)
        syncActivityRow(job)
        postChange()
        return job
    }

    // MARK: - Updates

    private func apply(_ update: RipJobUpdate, to job: RipJob) {
        guard !job.phase.isFinished else { return }
        switch update {
        case .phase(let phase):
            job.phase = phase
            job.fraction = nil
            job.remaining = nil
            job.queuedAt = phase == .queuedForEncode ? Date() : nil
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
        job.phase = handle.isCancelled ? .cancelled : (error == nil ? .done : .failed)
        job.finishedAt = Date()
        job.outputPath = outputPath
        job.sizeBytes = sizeBytes
        job.error = job.phase == .failed ? error : nil
        job.fraction = job.phase == .done ? 1 : nil
        job.remaining = nil
        job.queuedAt = nil
        StreamRipper.log(job.id, "\(job.phase.rawValue) after \(StreamRipper.formatDuration(job.finishedAt!.timeIntervalSince(job.startedAt)))")
        history.append(RipHistoryEntry(
            id: job.id, source: job.source, url: job.url, mode: job.mode, summary: job.summary,
            folder: job.folder, title: job.title, outcome: job.phase, startedAt: job.startedAt,
            finishedAt: job.finishedAt!, outputPath: outputPath,
            sizeBytes: sizeBytes,
            error: job.error))
        syncActivityRow(job)
        postChange()
        if job.phase == .done, case .audio = job.mode, let outputPath {
            job.followUp.run(jobID: job.id, path: outputPath)
        }
        if job.phase == .failed, presentsFailures {
            DispatchQueue.main.async { MainActor.assumeIsolated { self.presentFailure(of: job) } }
        }
    }

    /// The job's place in the encode queue (1 = next), or nil when it is not waiting.
    func encodeQueuePosition(of job: RipJob) -> Int? {
        guard let queuedAt = job.queuedAt else { return nil }
        return jobs.filter { ($0.queuedAt ?? .distantFuture) <= queuedAt }.count
    }

    // MARK: - User actions

    func cancel(_ job: RipJob) {
        guard !job.phase.isFinished else { return }
        StreamRipper.log(job.id, "cancelled by user (\(job.phase.rawValue))")
        job.handle.cancel()
    }

    /// Starts the same rip again. A YouTube download has no rip choices and is not retried here.
    @discardableResult
    func retry(url: URL, mode: StreamRipper.Mode?, folder: String?, followUp: RipFollowUp = RipFollowUp()) -> RipJob? {
        guard let mode, let folder else { return nil }
        return startRip(url: url, mode: mode, folder: folder, followUp: followUp)
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

    /// Terminates every running job's process; called as the app quits, so no encode outlives it.
    func terminateAll() {
        for job in jobs where !job.phase.isFinished {
            StreamRipper.log(job.id, "terminated on app quit (\(job.phase.rawValue))")
            job.handle.cancel()
        }
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
        if job.mode != nil {
            alert.addButton(withTitle: "Retry")
            actions.append { self.retry(url: job.url, mode: job.mode, folder: job.folder, followUp: job.followUp) }
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
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        let out = Pipe()
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), parts[1] == "1" else { continue }
            let command = parts[2]
            guard command.contains("ffmpeg") || command.contains("yt-dlp"),
                  ["nullplayer-rip-", "nullplayer-ytdl-"].contains(where: { command.contains($0) })
            else { continue }
            kill(pid, SIGTERM)
            NSLog("StreamRipper: terminated orphaned rip process pid=%d", pid)
        }
    }
}
