import Foundation

/// A requested playback action held until the local AVAudioEngine graph is usable.
enum AudioGraphRecoveryIntent {
    case play
    case playTrack(index: Int)
    case loadTrack(index: Int)
    case loadLocalImmediate(index: Int)
}

/// Owns the recovery lifecycle for the local AVAudioEngine graph.
///
/// Graph mutation remains in `AudioEngine`; this coordinator deliberately owns the
/// asynchronous state so casting deferrals, retries, and pending user intent do not
/// become independent flags in the playback controller.
final class AudioGraphRecoveryCoordinator {
    enum State: Equatable {
        case ready
        case awaitingRebuild
        case retrying(attempt: Int)
    }

    private(set) var state: State = .ready
    private var workItem: DispatchWorkItem?
    private(set) var pendingIntent: AudioGraphRecoveryIntent?

    var isDeferred: Bool {
        state != .ready
    }

    var retryCount: Int {
        guard case .retrying(let attempt) = state else { return 0 }
        return attempt
    }

    var hasScheduledWork: Bool {
        workItem != nil
    }

    func startNewRecoveryCycle() {
        cancelScheduledWork()
        state = .ready
    }

    func deferRebuild() {
        if state == .ready {
            state = .awaitingRebuild
        }
    }

    func finishRebuild() {
        state = .ready
    }

    func beginRebuild() {
        cancelScheduledWork()
    }

    func replacePendingIntent(with intent: AudioGraphRecoveryIntent) {
        pendingIntent = intent
    }

    func addPendingIntentIfAbsent(_ intent: AudioGraphRecoveryIntent) {
        if pendingIntent == nil {
            pendingIntent = intent
        }
    }

    func takePendingIntent() -> AudioGraphRecoveryIntent? {
        defer { pendingIntent = nil }
        return pendingIntent
    }

    func clearPendingIntent() {
        pendingIntent = nil
    }

    func cancelScheduledWork() {
        workItem?.cancel()
        workItem = nil
    }

    func scheduleConfigurationChange(_ action: @escaping () -> Void) {
        schedule(after: 0.25, action)
    }

    /// Schedules a bounded exponential-backoff recovery attempt.
    /// Returns false once the recovery cycle has been exhausted.
    @discardableResult
    func scheduleRetry(_ action: @escaping () -> Void) -> Bool {
        // One failed attempt reaches this from two places: the failure path inside the
        // rebuild, and the caller that observed the rebuild fail. The retry armed first is
        // the one that counts — re-arming here would burn a second attempt from the budget
        // and cancel the backoff that was just scheduled.
        guard !hasScheduledWork else { return true }
        let attempt = retryCount + 1
        guard attempt <= 6 else {
            clearPendingIntent()
            NSLog("AudioEngine: Audio graph recovery exhausted; waiting for Play or a device change")
            return false
        }
        state = .retrying(attempt: attempt)
        schedule(after: min(4.0, 0.25 * pow(2.0, Double(attempt - 1))), action)
        return true
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        cancelScheduledWork()
        let item = DispatchWorkItem { [weak self] in
            self?.workItem = nil
            action()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    #if DEBUG
    private var faultInjector: ((String) -> Void)?

    func setFaultInjectorForTesting(_ faultInjector: ((String) -> Void)?) {
        self.faultInjector = faultInjector
    }

    func injectFaultForTesting(at stage: String) {
        faultInjector?(stage)
    }
    #endif
}
