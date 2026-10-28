import AppKit

/// Turns scroll-wheel events into whole up/down steps. A wheel click is one step; a trackpad's
/// precise deltas are summed into steps, and momentum is ignored so a swipe doesn't fling the value.
/// Direction is physical: up is positive whether or not natural scrolling is on.
struct ScrollWheelStepper {
    static let preciseScrollPointsPerStep: CGFloat = 12

    private var remainder: CGFloat = 0

    mutating func steps(for event: NSEvent) -> Int {
        guard event.momentumPhase.isEmpty else { return 0 }
        let deltaY = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        guard event.hasPreciseScrollingDeltas else { return deltaY > 0 ? 1 : (deltaY < 0 ? -1 : 0) }
        if event.phase == .began { remainder = 0 }
        remainder += deltaY
        let steps = Int(remainder / Self.preciseScrollPointsPerStep)
        remainder -= CGFloat(steps) * Self.preciseScrollPointsPerStep
        return steps
    }
}
