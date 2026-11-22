import Foundation

/// A short tool run whose output is read whole: ffprobe, a yt-dlp query, an ffmpeg tag rewrite.
/// With a `handle`, the run is that job's process, so a cancel terminates it.
enum RipProcess {
    struct Output {
        let status: Int32
        let stdout: Data
        let stderr: String
    }

    /// Runs `tool` to completion; nil when it cannot start (or the job is already cancelled).
    static func run(_ tool: String, _ args: [String], handle: RipJobHandle? = nil) -> Output? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            if let handle { try handle.launch(task) } else { try task.run() }
        } catch { return nil }
        // ponytail: stdout is drained before stderr, so a tool writing over 64 KB of stderr while
        // stdout is still open would stall; every caller runs its tool at `-v error` or quieter.
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        handle?.processExited()
        return Output(status: task.terminationStatus, stdout: stdout,
                      stderr: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
