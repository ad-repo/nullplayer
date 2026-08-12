import Foundation

/// Tracks an app-initiated Sonos Stop across asynchronous transport polls.
///
/// Sonos Stop SOAP can take several seconds, so a poll that started before the command may still
/// report PLAYING. That stale result must not clear the stop intent. Once STOPPED has actually been
/// observed, a later PLAYING report represents a genuine restart and may clear the intent.
struct SonosLocalStopState: Equatable {
    private enum Phase: Equatable {
        case none
        case requested
        case observedStopped
    }

    private var phase: Phase = .none

    var suppressesNaturalFinish: Bool {
        phase != .none
    }

    mutating func requestStop() {
        phase = .requested
    }

    mutating func observeStopped() {
        guard phase != .none else { return }
        phase = .observedStopped
    }

    mutating func observePlaying() {
        guard phase == .observedStopped else { return }
        phase = .none
    }

    mutating func clear() {
        phase = .none
    }
}
