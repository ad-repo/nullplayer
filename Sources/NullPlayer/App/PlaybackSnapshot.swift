import Foundation

#if DEBUG
/// Live-QA playback snapshot: `kill -INFO <pid>` (or Ctrl-T in the terminal running it) makes a
/// running debug build write the state of playback, casting, audio-graph recovery and output
/// routing to one file and to the log. SIGINFO, not SIGUSR1: its default action is ignore, so
/// signalling an older build without the handler cannot kill it.
/// Driven by `skills/app-control/scripts/playback-snapshot.sh`; see `app-control` for the fields.
///
/// It exists because the running app could not be read any other way: lldb does not attach to
/// the ad-hoc-signed debug build, and every question otherwise cost an instrumented rebuild.
enum PlaybackSnapshot {
    private static var signalSource: DispatchSourceSignal?

    /// `$DARWIN_USER_TEMP_DIR/nullplayer-snapshot-<pid>.txt`, read by the script.
    static var fileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nullplayer-snapshot-\(ProcessInfo.processInfo.processIdentifier).txt")
    }

    static func install() {
        guard signalSource == nil else { return }
        signal(SIGINFO, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINFO, queue: .main)
        source.setEventHandler { capture() }
        source.resume()
        signalSource = source
    }

    static func capture() {
        let engine = WindowManager.shared.audioEngine
        let cast = CastManager.shared
        let session = cast.activeSession
        let castLines = [
            "cast session=\(session.map { "'\($0.device.name)' (\($0.device.type.displayName))" } ?? "nil") state=\(session.map { "\($0.state)" } ?? "nil") currentCast=\(cast.currentCast) isCasting=\(cast.isCasting) routingActive=\(engine.isAudioCastRoutingActive) anyActive=\(engine.isAnyCastingActive)",
            "cast position=\(session.map { String(format: "%.1f", $0.position) } ?? "nil") sessionPlaying=\(session.map { "\($0.isPlaying)" } ?? "nil") sonosRooms=\(cast.selectedSonosRooms.count) localFileCastInProgress=\(cast.isLocalFileCastInProgress())",
        ]

        engine.playbackSnapshotLines { engineLines in
            let stamp = ISO8601DateFormatter().string(from: Date())
            let lines = ["snapshot at=\(stamp) pid=\(ProcessInfo.processInfo.processIdentifier)"] + engineLines + castLines
            for line in lines { NSLog("SNAPSHOT %@", line) }
            do {
                try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                NSLog("SNAPSHOT write failed: %@", error.localizedDescription)
            }
        }
    }
}
#endif
