import AVFoundation
import CoreAudio
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
    /// What `AudioEngine.readPlaybackSnapshot` reports: every field read at one moment on the main
    /// thread, then the main-mixer level measured over the following 0.3 s.
    struct EngineReading {
        enum Level {
            case measured(Float)
            case noBuffers
            case unavailable(String)
        }

        var state: PlaybackState
        var trackTitle: String?
        var index: Int
        var playlistCount: Int
        var time: TimeInterval
        var isStreaming: Bool
        var hasAudioFile: Bool
        var isRunning: Bool
        var playerIsPlaying: Bool
        var playerSampleTime: AVAudioFramePosition?
        var crossfadeActive: Bool
        var volume: Float
        var mainMixerOutputVolume: Float
        var playerVolume: Float
        var eqBypass: Bool
        var pitchRate: Float
        var recoveryState: AudioGraphRecoveryCoordinator.State
        var pendingIntent: AudioGraphRecoveryIntent?
        var needsReplacement: Bool
        var retryScheduled: Bool
        var engineDeviceID: AudioDeviceID?
        var systemDefaultDeviceID: AudioDeviceID?
        var selectedDeviceID: AudioDeviceID?
        var sampleRate: Double
        var channelCount: AVAudioChannelCount
        var level: Level
    }

    private static var signalSource: DispatchSourceSignal?
    /// The engine's level tap is exclusive to its bus, so a second request while one is measuring
    /// is dropped rather than installing a second tap (which raises and kills the app).
    private static var isCapturing = false

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
        guard !isCapturing else {
            NSLog("SNAPSHOT skipped: a capture is already measuring")
            return
        }
        isCapturing = true
        let header = "snapshot at=\(ISO8601DateFormatter().string(from: Date())) pid=\(ProcessInfo.processInfo.processIdentifier)"
        let castLines = self.castLines()
        WindowManager.shared.audioEngine.readPlaybackSnapshot { reading in
            isCapturing = false
            let lines = [header] + engineLines(reading) + castLines
            for line in lines { NSLog("SNAPSHOT %@", line) }
            do {
                try (lines.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                NSLog("SNAPSHOT write failed: %@", error.localizedDescription)
            }
        }
    }

    static func engineLines(_ r: EngineReading) -> [String] {
        let level: String
        switch r.level {
        case .measured(let peak): level = String(format: "%.4f", peak)
        case .noBuffers: level = "no buffers in 0.3s"
        case .unavailable(let reason): level = "n/a (\(reason))"
        }
        return [
            "engine state=\(r.state) track='\(r.trackTitle ?? "nil")' index=\(r.index)/\(r.playlistCount) time=\(String(format: "%.1f", r.time))",
            "engine pipeline=\(r.isStreaming ? "streaming" : "local") audioFile=\(r.hasAudioFile) running=\(r.isRunning) player.playing=\(r.playerIsPlaying) player.sampleTime=\(r.playerSampleTime.map { String($0) } ?? "nil") crossfadeActive=\(r.crossfadeActive)",
            "engine volume=\(String(format: "%.2f", r.volume)) mainMixerOut=\(String(format: "%.2f", r.mainMixerOutputVolume)) player.volume=\(String(format: "%.2f", r.playerVolume)) eqBypass=\(r.eqBypass) pitchRate=\(String(format: "%.2f", r.pitchRate))",
            "graph recovery=\(r.recoveryState) pendingIntent=\(r.pendingIntent.map { "\($0)" } ?? "nil") needsReplacement=\(r.needsReplacement) retryScheduled=\(r.retryScheduled)",
            "output engineDevice='\(deviceName(r.engineDeviceID))' systemDefault='\(deviceName(r.systemDefaultDeviceID))' selected=\(r.selectedDeviceID.map { String($0) } ?? "default") format=\(Int(r.sampleRate))Hz/\(r.channelCount)ch",
            "level mainMixerPeak=\(level)",
        ]
    }

    private static func castLines() -> [String] {
        let engine = WindowManager.shared.audioEngine
        let cast = CastManager.shared
        let session = cast.activeSession
        return [
            "cast session=\(session.map { "'\($0.device.name)' (\($0.device.type.displayName))" } ?? "nil") state=\(session.map { "\($0.state)" } ?? "nil") currentCast=\(cast.currentCast) isCasting=\(cast.isCasting) routingActive=\(engine.isAudioCastRoutingActive) anyActive=\(engine.isAnyCastingActive)",
            "cast position=\(session.map { String(format: "%.1f", $0.position) } ?? "nil") sessionPlaying=\(session.map { "\($0.isPlaying)" } ?? "nil") sonosRooms=\(cast.selectedSonosRooms.count) localFileCastInProgress=\(cast.isLocalFileCastInProgress())",
        ]
    }

    private static func deviceName(_ deviceID: AudioDeviceID?) -> String {
        guard let deviceID else { return "nil" }
        return AudioOutputManager.shared.getDeviceName(deviceID: deviceID) ?? "#\(deviceID)"
    }
}
#endif
