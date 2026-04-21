import Foundation
import AppKit

// =============================================================================
// SLEEP TIMER MANAGER
// =============================================================================
// Schedules an automatic pause/stop after a configurable duration.
// =============================================================================

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
        cancel()
        let duration = TimeInterval(max(1, minutes) * 60)
        let fireDate = Date().addingTimeInterval(duration)
        state = State(mode: .timed, action: action, fireDate: fireDate, originalDuration: duration, fadeOut: fadeOut, fadeOutSeconds: Self.defaultFadeOutSeconds)
        fadeStartVolume = nil
        isFading = false
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.fire() }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        notifyChange()
    }

    func startEndOfTrack(action: Action = .pause) {
        cancel()
        state = State(mode: .endOfTrack, action: action, fireDate: nil, originalDuration: nil, fadeOut: false, fadeOutSeconds: 0)
        notifyChange()
    }

    func startEndOfQueue(action: Action = .pause) {
        cancel()
        state = State(mode: .endOfQueue, action: action, fireDate: nil, originalDuration: nil, fadeOut: false, fadeOutSeconds: 0)
        notifyChange()
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        tickTimer?.invalidate(); tickTimer = nil
        if isFading, let startVolume = fadeStartVolume {
            WindowManager.shared.audioEngine.volume = startVolume
        }
        fadeStartVolume = nil
        isFading = false
        let wasActive = state != nil
        state = nil
        if wasActive { notifyChange() }
    }

    // MARK: - Internal Logic
    private func tick() {
        guard let state, let fire = state.fireDate else { return }
        let remaining = fire.timeIntervalSinceNow
        if state.fadeOut, state.fadeOutSeconds > 0, remaining <= state.fadeOutSeconds, !isFading {
            beginFade(over: remaining)
        } else if isFading {
            updateFade(remaining: remaining)
        }
        notifyChange()
    }

    private func beginFade(over remaining: TimeInterval) {
        fadeStartVolume = WindowManager.shared.audioEngine.volume
        isFading = true
        updateFade(remaining: remaining)
    }

    private func updateFade(remaining: TimeInterval) {
        guard let state, let startVolume = fadeStartVolume else { return }
        let progress = max(0, min(1, 1.0 - (remaining / max(0.001, state.fadeOutSeconds))))
        WindowManager.shared.audioEngine.volume = max(0, startVolume * Float(1.0 - progress))
    }

    private func fire() {
        guard let state else { return }
        applyAction(state.action)
        if isFading, let startVolume = fadeStartVolume {
            WindowManager.shared.audioEngine.volume = startVolume
        }
        cancel()
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
            DispatchQueue.main.async { [weak self] in self?.fire() }
        case .endOfQueue:
            if WindowManager.shared.audioEngine.currentTrack == nil {
                DispatchQueue.main.async { [weak self] in self?.fire() }
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
