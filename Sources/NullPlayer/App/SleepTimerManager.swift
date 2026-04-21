import Foundation
import AppKit

// =============================================================================
// SLEEP TIMER MANAGER
// =============================================================================
// Schedules an automatic pause/stop after a configurable duration.
//
// All public methods must be called from the main thread (@MainActor enforced).
// Timer callbacks and volume writes happen on the main run loop.
// =============================================================================

/// All public methods must be called from the main thread.
/// Timer callbacks and volume writes happen on the main run loop.
final class SleepTimerManager {
    static let shared = SleepTimerManager()

    // MARK: - Notifications
    static let stateDidChangeNotification = Notification.Name("NullPlayer.SleepTimer.stateDidChange")

    // MARK: - Types
    enum Mode: String { case timed, endOfTrack, endOfQueue }
    enum Action: String { case pause, stop }

    struct State {
        let mode: Mode
        let action: Action
        let fireDate: Date?
        let originalDuration: TimeInterval?
        let fadeOut: Bool
        let fadeOutSeconds: TimeInterval
        /// Track ID captured at arm time — used by .endOfTrack to distinguish
        /// natural completion from manual skip.
        let armedTrackID: UUID?
    }

    // MARK: - Public State
    private(set) var state: State?
    var isActive: Bool { state != nil }
    var remainingSeconds: TimeInterval? {
        guard let state, let fire = state.fireDate else { return nil }
        return max(0, fire.timeIntervalSinceNow)
    }

    // MARK: - Config
    static let timedChoicesMinutes: [Int] = [5, 10, 15, 30, 45, 60, 90, 120]
    static let defaultFadeOutSeconds: TimeInterval = 10

    // MARK: - Internal
    private var timer: Timer?
    private var tickTimer: Timer?
    private var fadeStartVolume: Float?
    /// Last volume we wrote during fade — used to detect external volume changes.
    private var lastWrittenVolume: Float?
    private var isFading: Bool = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trackDidChange),
            name: .audioTrackDidChange,
            object: nil
        )
    }

    // MARK: - Public API

    func startTimed(minutes: Int, action: Action = .pause, fadeOut: Bool = true) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancel()
        let duration = TimeInterval(max(1, minutes) * 60)
        let fireDate = Date().addingTimeInterval(duration)
        state = State(
            mode: .timed, action: action, fireDate: fireDate,
            originalDuration: duration, fadeOut: fadeOut,
            fadeOutSeconds: Self.defaultFadeOutSeconds,
            armedTrackID: WindowManager.shared.audioEngine.currentTrack?.id
        )
        fadeStartVolume = nil
        lastWrittenVolume = nil
        isFading = false
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.fire()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        notifyChange()
    }

    func startEndOfTrack(action: Action = .pause) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancel()
        state = State(
            mode: .endOfTrack, action: action, fireDate: nil,
            originalDuration: nil, fadeOut: false, fadeOutSeconds: 0,
            armedTrackID: WindowManager.shared.audioEngine.currentTrack?.id
        )
        notifyChange()
    }

    func startEndOfQueue(action: Action = .pause) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancel()
        state = State(
            mode: .endOfQueue, action: action, fireDate: nil,
            originalDuration: nil, fadeOut: false, fadeOutSeconds: 0,
            armedTrackID: nil
        )
        notifyChange()
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        timer?.invalidate(); timer = nil
        tickTimer?.invalidate(); tickTimer = nil
        // Only restore volume if we were mid-fade AND the user hasn't changed
        // the volume externally since our last write.
        if isFading, let startVolume = fadeStartVolume {
            let currentVolume = WindowManager.shared.audioEngine.volume
            if let lastWritten = lastWrittenVolume,
               abs(currentVolume - lastWritten) < 0.01 {
                WindowManager.shared.audioEngine.volume = startVolume
            }
        }
        fadeStartVolume = nil
        lastWrittenVolume = nil
        isFading = false
        let wasActive = state != nil
        state = nil
        if wasActive { notifyChange() }
    }

    // MARK: - Internal Logic

    private func tick() {
        guard let state, let fire = state.fireDate else { return }
        let remaining = max(0, fire.timeIntervalSinceNow)
        if state.fadeOut, state.fadeOutSeconds > 0, remaining <= state.fadeOutSeconds, !isFading {
            beginFade(over: remaining)
        } else if isFading {
            // Detect external volume change — abort fade if user adjusted volume
            if let lastWritten = lastWrittenVolume {
                let currentVolume = WindowManager.shared.audioEngine.volume
                if abs(currentVolume - lastWritten) > 0.01 {
                    // User changed volume externally — abort fade
                    isFading = false
                    fadeStartVolume = nil
                    lastWrittenVolume = nil
                    return
                }
            }
            updateFade(remaining: remaining)
        }
        notifyChange()
    }

    private func beginFade(over remaining: TimeInterval) {
        fadeStartVolume = WindowManager.shared.audioEngine.volume
        lastWrittenVolume = nil
        isFading = true
        updateFade(remaining: remaining)
    }

    private func updateFade(remaining: TimeInterval) {
        guard let state, let startVolume = fadeStartVolume else { return }
        let progress = max(0, min(1, 1.0 - (max(0, remaining) / max(0.001, state.fadeOutSeconds))))
        let newVolume = max(0, startVolume * Float(1.0 - progress))
        WindowManager.shared.audioEngine.volume = newVolume
        lastWrittenVolume = newVolume
    }

    private func fire() {
        guard let state else { return }
        applyAction(state.action)
        // Restore volume only if no external change was detected
        if isFading, let startVolume = fadeStartVolume {
            if let lastWritten = lastWrittenVolume,
               abs(WindowManager.shared.audioEngine.volume - lastWritten) < 0.01 {
                WindowManager.shared.audioEngine.volume = startVolume
            }
        }
        // Clear state (don't call cancel() to avoid double-restore)
        timer?.invalidate(); timer = nil
        tickTimer?.invalidate(); tickTimer = nil
        self.state = nil
        fadeStartVolume = nil
        lastWrittenVolume = nil
        isFading = false
        notifyChange()
    }

    private func applyAction(_ action: Action) {
        switch action {
        case .pause: WindowManager.shared.audioEngine.pause()
        case .stop:  WindowManager.shared.audioEngine.stop()
        }
    }

    @objc private func trackDidChange(_ note: Notification) {
        guard let state else { return }
        switch state.mode {
        case .timed: break
        case .endOfTrack:
            // Only fire if the track that just ended is the one we armed for.
            // This prevents firing on manual skip/previous — only natural
            // completion triggers the sleep action.
            let newTrack = note.userInfo?["track"] as? Track
            if let armedID = state.armedTrackID {
                if newTrack?.id != armedID {
                    // Track changed — this is the completion of the armed track.
                    // But also check it wasn't a skip to a *different* track:
                    // if the new track is non-nil (user skipped to another track),
                    // re-arm for the new track instead of firing.
                    if newTrack != nil {
                        // User skipped — re-arm for the new track
                        self.state = State(
                            mode: .endOfTrack, action: state.action,
                            fireDate: nil, originalDuration: nil,
                            fadeOut: false, fadeOutSeconds: 0,
                            armedTrackID: newTrack?.id
                        )
                        notifyChange()
                    } else {
                        // Track ended naturally (no next track) — fire
                        fire()
                    }
                }
                // Same track ID — ignore (metadata update, not a real change)
            } else {
                // No armed track (shouldn't happen) — fire as fallback
                fire()
            }
        case .endOfQueue:
            if WindowManager.shared.audioEngine.currentTrack == nil {
                fire()
            }
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: nil)
    }

    var menuDescription: String? {
        guard let state else { return nil }
            switch state.mode {
            case .timed:
                guard let remaining = remainingSeconds else { return "Sleep Timer" }
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60
                return String(format: "Sleep Timer: %d:%02d", minutes, seconds)
            case .endOfTrack: return "Sleep Timer: End of track"
            case .endOfQueue: return "Sleep Timer: End of queue"
            }
    }
}
