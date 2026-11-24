import Foundation

/// The Scope's audio history and the trace drawn from it: no view and no clock, so the window and
/// blend math is testable.
///
/// Two things keep the trace readable: a **trigger** that phase-locks each window to a rising
/// zero-crossing (so periodic content stays stationary instead of swimming horizontally), and a
/// gentle **temporal blend** of the aligned windows (so the line stops flickering frame to frame
/// without smearing transients).
struct ScopeTrace {
    /// Chunks of history kept: the drawn window is three chunks less the trigger search region.
    static let historyChunks = 3
    /// Samples per drawn point.
    static let drawStride = 3
    static let historyLength = WaveformPlayout.sampleCount * historyChunks
    /// The trigger is searched for in the first quarter of the history.
    static let triggerSearchLength = historyLength / 4
    static let pointCount = (historyLength - triggerSearchLength) / drawStride
    /// The blend weights were tuned at the old ~20 updates per second; scaled to it by elapsed time.
    static let blendReferenceRate = 20.0
    /// Below half an 8-bit step the trace draws flat.
    static let flatThreshold: Float = 0.002
    /// Temporal-blend weights (1 = no smoothing, lower = smoother). Asymmetric: a window louder than
    /// the trace (a beat) snaps in quickly so it is never averaged away, a quieter one eases in.
    static let attackWeight: Float = 0.85
    static let releaseWeight: Float = 0.45

    /// The last `historyChunks` chunks, mono, -1…1, oldest first.
    private(set) var history = [Float](repeating: 0, count: historyLength)
    /// The drawn trace, `pointCount` points once anything has been rendered.
    private(set) var points: [Float] = []
    private var lastRender: TimeInterval?

    /// The drawn trace is flat: silence has nothing more to blend in.
    var isFlat: Bool { !points.contains { abs($0) > Self.flatThreshold } }

    /// Shift one 576-sample chunk (`UInt8`, centred on 128) into the history as mono.
    mutating func append(left: [UInt8], right: [UInt8]) {
        history.removeFirst(WaveformPlayout.sampleCount)
        for i in 0..<WaveformPlayout.sampleCount {
            history.append((Float(left[i]) + Float(right[i]) - 256) / 254)
        }
    }

    /// Trigger-align the newest window of the history and blend it into `points`, weighted by the
    /// time since the last render.
    mutating func render(at now: TimeInterval) {
        defer { lastRender = now }
        // Trigger: first rising zero-crossing in the search region; 0 (no lock) when there is none.
        var trigger = 0
        for i in 1...Self.triggerSearchLength where history[i - 1] <= 0 && history[i] > 0 {
            trigger = i
            break
        }
        let window = (0..<Self.pointCount).map { history[trigger + $0 * Self.drawStride] }

        guard let lastRender, points.count == Self.pointCount else {
            points = window
            return
        }
        let windowPeak = window.map(abs).max() ?? 0
        let tracePeak = points.map(abs).max() ?? 0
        let windowWeight = windowPeak > tracePeak ? Self.attackWeight : Self.releaseWeight
        let elapsed = Float(min(1, (now - lastRender) * Self.blendReferenceRate))
        let weight = 1 - pow(1 - windowWeight, elapsed)
        for i in 0..<Self.pointCount {
            points[i] += (window[i] - points[i]) * weight
        }
    }
}
