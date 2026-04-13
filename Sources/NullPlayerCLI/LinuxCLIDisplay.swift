import Foundation
import Dispatch
import NullPlayerCore

enum LinuxCLIInputAction {
    case togglePlayPause
    case next
    case previous
    case seekForward
    case seekBackward
    case volumeUp
    case volumeDown
    case quit
}

#if os(Linux)
import Glibc

final class LinuxCLIDisplay {
    private var inputSource: DispatchSourceRead?
    private var originalTermios: termios?
    private var rawModeEnabled = false

    deinit {
        stopKeyboardCapture()
        restoreTerminal()
    }

    func printBanner() {
        print("NullPlayer Linux CLI")
        print("Keys: [space]=play/pause  n=next  p=previous  f/b=seek +/-10s  +/-=volume  q=quit")
    }

    func printMessage(_ message: String) {
        print(message)
    }

    func printNowPlaying(
        track: Track?,
        state: PlaybackState,
        current: TimeInterval,
        duration: TimeInterval,
        volume: Float,
        eqEnabled: Bool
    ) {
        let title: String
        if let track {
            title = track.displayTitle.isEmpty ? track.url.lastPathComponent : track.displayTitle
        } else {
            title = "(no track)"
        }

        let line = "\r\(title) | \(stateText(state)) | \(formatTime(current))/\(formatTime(duration)) | vol \(Int(volume * 100))% | EQ \(eqEnabled ? "on" : "off")"
        FileHandle.standardOutput.write(Data(line.utf8))
        FileHandle.standardOutput.write(Data("\u{001B}[K".utf8))
    }

    func printOutputs(_ devices: [AudioOutputDevice], current: AudioOutputDevice?) {
        for device in devices {
            let marker = (device.persistentID == current?.persistentID) ? "*" : " "
            print("\(marker) \(device.name) [\(device.persistentID)]")
        }
    }

    func startKeyboardCapture(_ handler: @escaping (LinuxCLIInputAction) -> Void) {
        guard inputSource == nil else { return }
        guard enableRawMode() else { return }

        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 32)
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            guard count > 0 else { return }

            for index in 0..<count {
                switch buffer[index] {
                case 32:
                    handler(.togglePlayPause)
                case UInt8(ascii: "n"), UInt8(ascii: "N"):
                    handler(.next)
                case UInt8(ascii: "p"), UInt8(ascii: "P"):
                    handler(.previous)
                case UInt8(ascii: "f"), UInt8(ascii: "F"):
                    handler(.seekForward)
                case UInt8(ascii: "b"), UInt8(ascii: "B"):
                    handler(.seekBackward)
                case UInt8(ascii: "+"), UInt8(ascii: "="):
                    handler(.volumeUp)
                case UInt8(ascii: "-"):
                    handler(.volumeDown)
                case UInt8(ascii: "q"), UInt8(ascii: "Q"):
                    handler(.quit)
                default:
                    break
                }
            }
        }
        source.setCancelHandler { [weak self] in
            self?.restoreTerminal()
        }
        source.resume()
        inputSource = source
    }

    func stopKeyboardCapture() {
        inputSource?.cancel()
        inputSource = nil
    }

    func restoreTerminal() {
        guard rawModeEnabled, var saved = originalTermios else { return }
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
        rawModeEnabled = false
        print("")
    }

    private func enableRawMode() -> Bool {
        guard !rawModeEnabled else { return true }

        var settings = termios()
        guard tcgetattr(STDIN_FILENO, &settings) == 0 else {
            return false
        }

        originalTermios = settings
        cfmakeraw(&settings)

        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &settings) == 0 else {
            return false
        }

        rawModeEnabled = true
        return true
    }

    private func stateText(_ state: PlaybackState) -> String {
        switch state {
        case .playing: return "playing"
        case .paused: return "paused"
        case .stopped: return "stopped"
        }
    }

    private func formatTime(_ value: TimeInterval) -> String {
        guard value.isFinite && value >= 0 else { return "--:--" }
        let total = Int(value.rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#else

final class LinuxCLIDisplay {
    func printBanner() {
        print("NullPlayerCLI Linux mode is unavailable on this platform.")
    }

    func printMessage(_ message: String) {
        print(message)
    }

    func printNowPlaying(
        track: Track?,
        state: PlaybackState,
        current: TimeInterval,
        duration: TimeInterval,
        volume: Float,
        eqEnabled: Bool
    ) {
        _ = track
        _ = state
        _ = current
        _ = duration
        _ = volume
        _ = eqEnabled
    }

    func printOutputs(_ devices: [AudioOutputDevice], current: AudioOutputDevice?) {
        _ = current
        for device in devices {
            print(device.name)
        }
    }

    func startKeyboardCapture(_ handler: @escaping (LinuxCLIInputAction) -> Void) {
        _ = handler
    }

    func stopKeyboardCapture() {}

    func restoreTerminal() {}
}
#endif
