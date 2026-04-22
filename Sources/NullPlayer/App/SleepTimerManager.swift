import Foundation
import AppKit

// =============================================================================
// SLEEP TIMER MANAGER
// =============================================================================
// Schedules an automatic pause/stop after a configurable duration.
//
// Three modes:
//   1. Timed:       Pause/stop after N minutes (with optional volume fade-out)
//   2. EndOfTrack:  Pause/stop when the current track finishes naturally
//   3. EndOfQueue:  Pause/stop when the last playlist track finishes
//
// All public methods must be called from the main thread.
// State is session-local (not persisted across launches).
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
    private var lastWrittenVolume: Float?
    private var isFading: Bool = false

    private init() {
        // Observe natural track completion (fires BEFORE currentTrack advances).
        // Used by both endOfTrack and endOfQueue modes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(trackDidFinishNaturally),
            name: .audioTrackDidFinishNaturally,
            object: nil
        )
        // Observe queue exhaustion for endOfQueue mode.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueDidExhaust),
            name: .audioQueueDidExhaust,
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
            fadeOutSeconds: Self.defaultFadeOutSeconds
        )
        fadeStartVolume = nil
        lastWrittenVolume = nil
        isFading = false
        let t = Timer(timeInterval: duration, repeats: false) { [weak self] _ in self?.fire() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let tt = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tt, forMode: .common)
        tickTimer = tt
        notifyChange()
    }

    func startEndOfTrack(action: Action = .pause) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancel()
        state = State(
            mode: .endOfTrack, action: action, fireDate: nil,
            originalDuration: nil, fadeOut: false, fadeOutSeconds: 0
        )
        notifyChange()
    }

    func startEndOfQueue(action: Action = .pause) {
        dispatchPrecondition(condition: .onQueue(.main))
        cancel()
        state = State(
            mode: .endOfQueue, action: action, fireDate: nil,
            originalDuration: nil, fadeOut: false, fadeOutSeconds: 0
        )
        notifyChange()
    }

    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        timer?.invalidate(); timer = nil
        tickTimer?.invalidate(); tickTimer = nil
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

    // MARK: - Tick / Fade

    private func tick() {
        guard let state, let fire = state.fireDate else { return }
        let remaining = max(0, fire.timeIntervalSinceNow)
        if state.fadeOut, state.fadeOutSeconds > 0, remaining <= state.fadeOutSeconds, !isFading {
            beginFade(over: remaining)
        } else if isFading {
            if let lastWritten = lastWrittenVolume {
                let currentVolume = WindowManager.shared.audioEngine.volume
                if abs(currentVolume - lastWritten) > 0.01 {
                    isFading = false
                    fadeStartVolume = nil
                    lastWrittenVolume = nil
                    notifyChange()
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

    // MARK: - Firing

    private func fire() {
        guard let state else { return }
        applyAction(state.action)
        if isFading, let startVolume = fadeStartVolume {
            if let lastWritten = lastWrittenVolume,
               abs(WindowManager.shared.audioEngine.volume - lastWritten) < 0.01 {
                WindowManager.shared.audioEngine.volume = startVolume
            }
        }
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

    // MARK: - Track Completion Handlers

    /// Fired when a track finishes playing naturally (BEFORE currentTrack advances).
    /// Handles endOfTrack mode; also fires before crossfade transitions.
    @objc private func trackDidFinishNaturally(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let state = self.state, state.mode == .endOfTrack else { return }
            self.fire()
        }
    }

    /// Fired when the queue exhausts naturally (last track finished, no next track).
    @objc private func queueDidExhaust(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let state = self.state, state.mode == .endOfQueue else { return }
            self.fire()
        }
    }

    // MARK: - Helpers

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
