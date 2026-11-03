import Foundation

/// The engine's output-stage fades: the pause/resume ramp (M71) and Fade Out Only's end-of-track
/// fade (M70). They stack, so the engine applies `gain`, their product, after the visualization
/// taps so the meters do not dip, and `onChange` fires whenever either moves.
final class OutputFades {
    let transport: TransportFade
    private(set) var endFade: Float = 1 {
        didSet { if endFade != oldValue { onChange() } }
    }
    private let onChange: () -> Void

    var gain: Float { transport.gain * endFade }

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        transport = TransportFade(onChange: onChange)
    }

    /// Fade Out Only's gain with `remaining` seconds of the track left, fading over `duration`;
    /// a nil `duration` (the mode is off) is no fade. Stateless, so a seek can refresh it as
    /// well as the clock tick.
    func updateEndFade(remaining: TimeInterval, over duration: TimeInterval?) {
        endFade = duration.map { Self.endFadeCurve(remaining: remaining, over: $0) } ?? 1
    }

    /// A different track starts at full level, and a pause still fading out on the old one is
    /// dropped rather than dipping the new one.
    func trackDidChange() {
        endFade = 1
        transport.set(1)
    }

    /// Unity until the last `duration` seconds, then the crossfade's equal-power cos curve down
    /// to silence at the end.
    static func endFadeCurve(remaining: TimeInterval, over duration: TimeInterval) -> Float {
        guard duration > 0, remaining < duration else { return 1 }
        let progress = 1 - max(0, remaining) / duration
        return Float(cos(progress * .pi / 2))
    }
}

/// A short gain ramp around pause and resume, so the audio doesn't stop or start mid-waveform
/// with a hard cut (M71).
final class TransportFade {
    /// Long enough to hear as a fade rather than a cut (80 ms only removed the click, and read the
    /// same as no fade), short enough that a pause still feels immediate.
    static let duration: TimeInterval = 0.3
    private static let step: TimeInterval = 0.005

    private(set) var gain: Float = 1 {
        didSet { onChange() }
    }
    private let onChange: () -> Void
    private var timer: Timer?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    /// Ramp from the current gain to `target`, then run `completion`. A new ramp or `set`
    /// replaces a running one, and its completion never runs.
    func ramp(to target: Float, completion: (() -> Void)? = nil) {
        timer?.invalidate()
        let start = gain
        let startDate = Date()
        let length = Self.duration * TimeInterval(abs(target - start))
        guard length > 0 else {
            timer = nil
            completion?()
            return
        }
        let timer = Timer(timeInterval: Self.step, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = Float(min(1, Date().timeIntervalSince(startDate) / length))
            self.gain = start + (target - start) * progress
            if progress >= 1 {
                timer.invalidate()
                self.timer = nil
                completion?()
            }
        }
        // .common so the ramp keeps running during menu tracking, as the crossfade timer does.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Jump to `gain` at once, cancelling any ramp and its completion.
    func set(_ gain: Float) {
        timer?.invalidate()
        timer = nil
        self.gain = gain
    }
}
