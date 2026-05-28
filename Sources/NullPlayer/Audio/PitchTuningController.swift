import AVFoundation
import Foundation

/// Owns the pitch-shift nodes used for the Reference Tuning feature and
/// drives the local AVAudioEngine graph plus each AudioStreaming graph from
/// a single cents offset.
///
/// `AVAudioUnitTimePitch.pitch` is in cents, ±2400 max.
final class PitchTuningController {

    enum Preset: Equatable {
        case off
        case hz432
        case hz440
        case custom(source: Double, target: Double)
    }

    static let userDefaultsEnabledKey = "referenceTuningEnabled"
    static let userDefaultsSourceKey = "referenceTuningSourceHz"
    static let userDefaultsTargetKey = "referenceTuningTargetHz"
    static let userDefaultsRateKey = "playbackSpeedRate"

    static let minCents: Double = -2400
    static let maxCents: Double = 2400
    static let minRate: Float = 0.25
    static let maxRate: Float = 4.0

    /// Attached to the main AVAudioEngine graph (local files).
    let localPitchNode = AVAudioUnitTimePitch()

    private final class WeakPitchNode {
        weak var node: AVAudioUnitTimePitch?

        init(_ node: AVAudioUnitTimePitch) {
            self.node = node
        }
    }

    /// AudioStreaming players each own a private AVAudioEngine, so every player
    /// needs its own pitch node. Weak storage avoids keeping retired crossfade
    /// players alive after their wrapper is released.
    private var streamingPitchNodes: [WeakPitchNode] = []

    private(set) var enabled: Bool = false
    private(set) var sourceReferenceHz: Double = 440
    private(set) var targetReferenceHz: Double = 432
    private(set) var rate: Float = 1.0

    init() {
        apply()
    }

    /// Cents offset = 1200 * log2(target / source). Returns 0 if inputs invalid.
    var offsetCents: Double {
        guard sourceReferenceHz > 0, targetReferenceHz > 0 else { return 0 }
        return 1200.0 * log2(targetReferenceHz / sourceReferenceHz)
    }

    /// Cents offset that will actually be applied to the audio graph (clamped to ±2400 and zeroed when disabled).
    var appliedCents: Double {
        guard enabled else { return 0 }
        return max(Self.minCents, min(Self.maxCents, offsetCents))
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        apply()
    }

    func setReferences(source: Double, target: Double) {
        sourceReferenceHz = source
        targetReferenceHz = target
        apply()
    }

    func setRate(_ value: Float) {
        rate = Self.clampedRate(value)
        apply()
    }

    func makeStreamingPitchNode() -> AVAudioUnitTimePitch {
        let node = AVAudioUnitTimePitch()
        streamingPitchNodes.append(WeakPitchNode(node))
        configureStreaming(node, cents: Float(appliedCents))
        pruneReleasedStreamingNodes()
        return node
    }

    func applyPreset(_ preset: Preset) {
        switch preset {
        case .off:
            enabled = false
        case .hz432:
            sourceReferenceHz = 440
            targetReferenceHz = 432
            enabled = true
        case .hz440:
            sourceReferenceHz = 440
            targetReferenceHz = 440
            enabled = true
        case .custom(let source, let target):
            sourceReferenceHz = source
            targetReferenceHz = target
            enabled = true
        }
        apply()
    }

    /// Active preset (used by menu state). `custom` matches anything that isn't an exact 432/440 match.
    var currentPreset: Preset {
        guard enabled else { return .off }
        if sourceReferenceHz == 440 && targetReferenceHz == 432 { return .hz432 }
        if sourceReferenceHz == 440 && targetReferenceHz == 440 { return .hz440 }
        return .custom(source: sourceReferenceHz, target: targetReferenceHz)
    }

    // MARK: - Persistence

    func loadFromDefaults() {
        let defaults = UserDefaults.standard
        enabled = defaults.bool(forKey: Self.userDefaultsEnabledKey)
        let savedSource = defaults.double(forKey: Self.userDefaultsSourceKey)
        sourceReferenceHz = savedSource > 0 ? savedSource : 440
        let savedTarget = defaults.double(forKey: Self.userDefaultsTargetKey)
        targetReferenceHz = savedTarget > 0 ? savedTarget : 432
        // UserDefaults.float(forKey:) returns 0 for missing keys, so 0 means "use default".
        let savedRate = defaults.float(forKey: Self.userDefaultsRateKey)
        rate = savedRate > 0 ? Self.clampedRate(savedRate) : 1.0
        apply()
    }

    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: Self.userDefaultsEnabledKey)
        defaults.set(sourceReferenceHz, forKey: Self.userDefaultsSourceKey)
        defaults.set(targetReferenceHz, forKey: Self.userDefaultsTargetKey)
        defaults.set(rate, forKey: Self.userDefaultsRateKey)
    }

    // MARK: - Apply

    private func apply() {
        let cents = Float(appliedCents)
        configureLocal(localPitchNode, cents: cents)
        pruneReleasedStreamingNodes()
        for entry in streamingPitchNodes {
            if let node = entry.node {
                configureStreaming(node, cents: cents)
            }
        }
    }

    private func configureLocal(_ node: AVAudioUnitTimePitch, cents: Float) {
        node.pitch = cents
        node.rate = rate
        node.bypass = (!enabled || cents.isZero) && rate == 1.0
    }

    private func configureStreaming(_ node: AVAudioUnitTimePitch, cents: Float) {
        node.pitch = cents
        node.rate = 1.0
        node.bypass = !enabled || cents.isZero
    }

    private func pruneReleasedStreamingNodes() {
        streamingPitchNodes.removeAll { $0.node == nil }
    }

    private static func clampedRate(_ value: Float) -> Float {
        max(minRate, min(maxRate, value))
    }
}
