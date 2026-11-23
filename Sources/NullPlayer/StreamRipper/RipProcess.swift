import Foundation

/// One tool run for a rip: ffprobe, a yt-dlp query, yt-dlp's download, ffmpeg's encode, an ffmpeg
/// tag rewrite. With a `handle`, the run is that job's process, so a cancel terminates it.
enum RipProcess {
    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: String
        let terminationReason: Process.TerminationReason
    }

    /// Runs `tool` to completion. With `onStdout`, stdout is handed over as it arrives (a
    /// progress stream; `Output.stdout` is then empty) and must be: an unread pipe fills its
    /// ~64 KB buffer mid-run and blocks the tool forever. Throws when the tool cannot start, or
    /// `CancellationError` when the job was cancelled first.
    static func run(_ tool: String, _ args: [String], environment: [String: String]? = nil,
                    handle: RipJobHandle? = nil, onStdout: (@Sendable (Data) -> Void)? = nil) throws -> Output {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        if let environment { task.environment = environment }
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        if let onStdout {
            out.fileHandleForReading.readabilityHandler = { onStdout($0.availableData) }
        }
        defer { out.fileHandleForReading.readabilityHandler = nil }
        if let handle {
            try handle.launch(task)
            StreamRipper.log(handle.id, "\(task.executableURL?.lastPathComponent ?? tool) started pid=\(task.processIdentifier)")
        } else {
            try task.run()
        }
        // ponytail: without `onStdout`, stdout is drained before stderr, so a tool writing over
        // 64 KB of stderr while stdout is still open would stall; those callers run at `-v error`
        // or quieter.
        let stdout = onStdout == nil ? out.fileHandleForReading.readDataToEndOfFile() : Data()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        handle?.processExited()
        return Output(status: task.terminationStatus, stdout: stdout,
                      stderr: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
                      terminationReason: task.terminationReason)
    }
}

/// Every process's parent and command line, as `ps` lists them at one moment.
struct ProcessTable {
    struct Entry {
        let pid: pid_t
        let parent: pid_t
        let command: Substring
    }

    let entries: [Entry]

    static func snapshot() -> ProcessTable {
        guard let output = try? RipProcess.run("/bin/ps", ["-axo", "pid=,ppid=,command="]) else {
            return ProcessTable(entries: [])
        }
        let entries = String(decoding: output.stdout, as: UTF8.self).split(separator: "\n").compactMap { line -> Entry? in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = pid_t(fields[0]), let parent = pid_t(fields[1]) else { return nil }
            return Entry(pid: pid, parent: parent, command: fields.count == 3 ? fields[2] : "")
        }
        return ProcessTable(entries: entries)
    }

    /// Every process below `root`, children before their own children.
    func descendants(of root: pid_t) -> [pid_t] {
        let children = Dictionary(grouping: entries, by: \.parent)
        var result: [pid_t] = []
        var frontier = [root]
        while let next = frontier.popLast() {
            let found = children[next]?.map(\.pid) ?? []
            result += found
            frontier += found
        }
        return result
    }

    /// Terminates each running process and everything it started, from one snapshot: yt-dlp runs
    /// ffmpeg as a child, which outlives a terminated yt-dlp and keeps writing into the staging
    /// folder a cancel then deletes. Blocks on `ps`, so it never runs on the main thread except
    /// as the app quits.
    static func terminateTrees(of processes: [Process]) {
        let running = processes.filter(\.isRunning)
        guard !running.isEmpty else { return }
        let table = snapshot()
        for process in running {
            for pid in table.descendants(of: process.processIdentifier) { kill(pid, SIGTERM) }
            process.terminate()
        }
    }
}
