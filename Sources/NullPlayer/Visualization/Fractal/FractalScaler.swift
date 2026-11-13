/// NullPlayer-Fractal's render scale: the fraction of the viewport its scene and feedback passes
/// render at. Auto follows the GPU time those passes took against the host's frame interval,
/// with hysteresis; a fixed choice from the Render Scale menu overrides it.
struct FractalScaler {
    static let range = 0.35...1.0
    /// Auto's starting guess: about this many pixels across.
    static let startWidth = 1280.0
    /// Shrink above this share of the frame interval, grow below the lower one.
    static let shrinkAbove = 0.7
    static let growBelow = 0.45
    static let adjustInterval = 0.5

    /// 0 for auto, else the fixed scale.
    var setting: Double
    private(set) var scale: Double
    private var gpuMs: Double?
    private var frameMs: Double?
    private var lastAdjust = 0.0

    init(setting: Double, viewportWidth: Int) {
        self.setting = setting
        scale = setting > 0 ? setting : min(1, max(Self.range.lowerBound, Self.startWidth / Double(max(1, viewportWidth))))
    }

    /// One frame's measurements: the passes' GPU time when a timer query was ready, and the time
    /// since the previous frame. Returns the scale to render at, quantised to 5% so the targets
    /// are not reallocated every adjustment.
    mutating func update(gpuMs sample: Double?, frameMs frame: Double, now: Double) -> Double {
        guard setting == 0 else { return setting }
        if let sample { gpuMs = gpuMs.map { $0 + (sample - $0) * 0.2 } ?? sample }
        // The host runs at 30 or 60 fps; a hiccup longer than 100 ms is not a frame interval, but
        // seeds the budget at 100 ms so a scene too slow from the start still shrinks.
        if frame > 0, frame < 100 {
            frameMs = frameMs.map { $0 + (frame - $0) * 0.1 } ?? frame
        } else if frame > 0, frameMs == nil {
            frameMs = 100
        }
        guard let gpuMs, let frameMs, now - lastAdjust >= Self.adjustInterval else { return scale }
        lastAdjust = now
        if gpuMs > frameMs * Self.shrinkAbove {
            scale *= 0.85
        } else if gpuMs < frameMs * Self.growBelow {
            scale *= 1.08
        }
        scale = min(max((scale * 20).rounded() / 20, Self.range.lowerBound), Self.range.upperBound)
        return scale
    }
}
