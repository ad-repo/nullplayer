import Foundation

enum WMPScanDirection: String, Hashable, Codable { case reverse, forward }

enum WMPTransportAction: Hashable, Codable {
    case play, pause, stop, previous, next
    case beginScan(WMPScanDirection), endScan
    case seek, volume, balance
    case toggleMute, toggleShuffle, toggleRepeat
    case playPlaylistItem(Int), removePlaylistItem(Int), movePlaylistItem(Int, Int)
    case setEQEnabled, setEQBand(Int), setPreamp
}

enum WMPHostValue: Hashable, Codable {
    case number(Double), bool(Bool), string(String)

    var finiteNumber: Double? {
        switch self {
        case let .number(value): return value.isFinite ? value : nil
        case let .bool(value): return value ? 1 : 0
        case let .string(value):
            guard let number = Double(value), number.isFinite else { return nil }
            return number
        }
    }
}

struct WMPMediaMetadata: Hashable, Codable {
    var title = ""
    var artist = ""
    var album = ""
}

struct WMPPlaylistItemSnapshot: Hashable, Codable {
    let title: String
    let artist: String
    let duration: TimeInterval
}

struct WMPEqualizerSnapshot: Hashable, Codable {
    var enabled = false
    var preamp: Double = 0
    var gains: [Double] = Array(repeating: 0, count: 10)
}

struct WMPHostSnapshot: Hashable, Codable {
    enum State: String, Hashable, Codable { case stopped, playing, paused }
    var state: State = .stopped
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Double = 0
    var balance: Double = 0
    var muted = false
    var shuffle = false
    var repeatMode = false
    var bufferingProgress: Double = 0
    var receptionQuality: Double = 0
    var metadata = WMPMediaMetadata()
    var playlistIndex = -1
    var playlistCount = 0
    var playlistItems: [WMPPlaylistItemSnapshot] = []
    var equalizer = WMPEqualizerSnapshot()

    var elapsedText: String { Self.timeString(currentTime) }
    var durationText: String { Self.timeString(duration) }

    func isEnabled(_ action: WMPTransportAction) -> Bool {
        switch action {
        case .play: return playlistCount > 0 && state != .playing
        case .pause: return state == .playing
        case .stop: return state != .stopped
        case .previous, .next: return playlistCount > 1
        case .seek, .beginScan: return duration > 0
        case let .playPlaylistItem(index), let .removePlaylistItem(index):
            return playlistItems.indices.contains(index)
        case let .movePlaylistItem(source, destination):
            return playlistItems.indices.contains(source) && playlistItems.indices.contains(destination)
        case .endScan, .volume, .balance, .toggleMute, .toggleShuffle, .toggleRepeat,
             .setEQEnabled, .setEQBand, .setPreamp: return true
        }
    }

    private static func timeString(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value.isFinite ? value : 0))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

@MainActor
protocol WMPHost: AnyObject {
    var snapshot: WMPHostSnapshot { get }
    func perform(_ action: WMPTransportAction, value: WMPHostValue?)
    func stopContinuousCommands()
    func setSpectrumConsumerActive(_ active: Bool)
}

extension WMPTransportAction {
    static func authoredAction(for node: WMPNode) -> WMPTransportAction? {
        switch node.kind {
        case .playElement: return .play
        case .pauseButton: return .pause
        case .stopElement: return .stop
        case .prevElement: return .previous
        case .nextElement: return .next
        case .rewButton, .rewElement: return .beginScan(.reverse)
        case .ffwdButton, .ffwdElement: return .beginScan(.forward)
        case .volumeSlider: return .volume
        case .seekSlider: return .seek
        case .balanceSlider: return .balance
        case .shuffleButton: return .toggleShuffle
        default: break
        }
        guard let attribute = node.attribute(named: "onClick"),
              case let .handler(_, source) = attribute.value else { return nil }
        let statements = source.lowercased().split(separator: ";").map {
            String($0).filter { !$0.isWhitespace }
        }.filter { !$0.isEmpty && !$0.hasPrefix("checksoundpref(") }
        guard statements.count == 1, let normalized = statements.first else { return nil }
        // Phase 4 accepts only exact, non-script transport literals. General handlers remain off.
        if normalized == "player.controls.play()" { return .play }
        if normalized == "player.controls.pause()" { return .pause }
        if normalized == "player.controls.stop()" { return .stop }
        if normalized == "player.controls.previous()" { return .previous }
        if normalized == "player.controls.next()" { return .next }
        if normalized == "player.settings.mute=!player.settings.mute" { return .toggleMute }
        if normalized == "player.settings.setmode('shuffle',down)" || normalized == "player.settings.setmode(\"shuffle\",down)" {
            return .toggleShuffle
        }
        if normalized == "player.settings.setmode('loop',down)" || normalized == "player.settings.setmode(\"loop\",down)" {
            return .toggleRepeat
        }
        return nil
    }
}
