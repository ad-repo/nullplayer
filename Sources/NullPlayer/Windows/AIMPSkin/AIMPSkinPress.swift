import AppKit

/// A mouse press on one of the skin's targets, from the button going down to it coming up: the
/// target held, the knob or slider under a key that a drag hands the press to, where a knob's turn
/// started, and the timer that acts while a key is held.
@MainActor
final class AIMPSkinPress {
    /// The target held down; nil between presses.
    private(set) var target: AIMPSkinTarget?
    /// A knob or slider under a pressed key (Vega lays its mute switch over the volume knob): a drag
    /// hands the press to it, a click stays the key's.
    private var under: (target: AIMPSkinTarget, start: NSPoint)?
    /// Where a knob's drag started, in window points, and its value then.
    var knobStart: (point: NSPoint, value: Double)?
    private var holdTimer: Timer?
    /// Set once a hold has acted: letting go then does not click.
    private(set) var holdFired = false

    /// `under`: the knob or slider under the key, and where the press went down (window points).
    func begin(_ target: AIMPSkinTarget, under: (target: AIMPSkinTarget, start: NSPoint)?) {
        self.target = target
        self.under = under
        holdFired = false
    }

    /// The knob or slider under the key, once the pointer (window points) is more than 3 points
    /// from where it went down: the press is now that drag's. Nil while it stays the key's.
    func handOver(at point: NSPoint) -> (target: AIMPSkinTarget, start: NSPoint)? {
        guard let under, hypot(point.x - under.start.x, point.y - under.start.y) > 3 else { return nil }
        target = under.target
        self.under = nil
        return under
    }

    /// Held 0.4 s, `fire` runs once, or with `repeats` then every 0.1 s until let go.
    func hold(repeats: Bool, _ fire: @escaping @MainActor () -> Void) {
        guard let held = target?.control else { return }
        holdTimer = Self.whileHeld(0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.target?.control == held else { return }
                self.holdFired = true
                fire()
                guard repeats else { return }
                self.holdTimer = Self.whileHeld(0.1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.target?.control == held else { return }
                        fire()
                    }
                }
            }
        }
    }

    /// The button came up: the press is over. The target that was held, and whether a hold acted;
    /// nil when none was.
    func end() -> (target: AIMPSkinTarget, holdFired: Bool)? {
        knobStart = nil
        holdTimer?.invalidate()
        holdTimer = nil
        guard let target else { return nil }
        self.target = nil
        under = nil
        return (target, holdFired)
    }

    /// A timer that also fires while a mouse button is held, which AppKit tracks in its
    /// event-tracking run-loop mode: long presses and held keys run during the hold.
    private static func whileHeld(_ interval: TimeInterval, repeats: Bool,
                                  block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
