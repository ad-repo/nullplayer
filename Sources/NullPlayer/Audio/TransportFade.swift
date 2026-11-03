import Foundation

/// A short gain ramp around pause and resume, so the audio doesn't stop or start mid-waveform
/// with a click (M71). The engine applies `gain` to its output stage, after the visualization
/// taps, so the meters are not faded with it.
final class TransportFade {
    /// Long enough to hear as a fade rather than a cut (80 ms only removed the click, and read the
    /// same as no fade), short enough that a pause still feels immediate.
    static let duration: TimeInterval = 0.3
    private static let step: TimeInterval = 0.005

    private(set) var gain: Float = 1 {
        didSet { apply(gain) }
    }
    private let apply: (Float) -> Void
    private var timer: Timer?

    init(apply: @escaping (Float) -> Void) {
        self.apply = apply
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
