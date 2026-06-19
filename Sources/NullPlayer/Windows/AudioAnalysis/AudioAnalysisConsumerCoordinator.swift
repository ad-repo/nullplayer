import Foundation

/// Keeps the audio engine work gated to the currently visible analysis pane.
final class AudioAnalysisConsumerCoordinator {
    // Consumer IDs for each pane
    private let scopeConsumerId = "audioAnalysis.scope"
    private let levelsConsumerId = "audioAnalysis.levels"
    private let spectrogramConsumerId = "audioAnalysis.spectrogram"
    private let pitchConsumerId = "audioAnalysis.pitch"
    private let octaveSpectrumConsumerId = "audioAnalysis.octave.spectrum"
    private let octaveMagnitudesConsumerId = "audioAnalysis.octave.magnitudes"
    private let delayConsumerId = "audioAnalysis.delay"

    /// Maps consumer ID to its removal function for proper cleanup
    private var consumerRemovers: [String: (String) -> Void] = [:]
    private var activeConsumers: Set<String> = []

    func setVisiblePane(_ index: Int) {
        let engine = WindowManager.shared.audioEngine

        // Pane 0: Scope — spectrum consumer
        updateConsumer(
            scopeConsumerId,
            needed: index == 0,
            add: engine.addSpectrumConsumer,
            remove: engine.removeSpectrumConsumer
        )

        // Pane 1: Levels — stereo consumer
        updateConsumer(
            levelsConsumerId,
            needed: index == 1,
            add: engine.addStereoConsumer,
            remove: engine.removeStereoConsumer
        )

        // Pane 2: Spectrogram — spectrum consumer
        updateConsumer(
            spectrogramConsumerId,
            needed: index == 2,
            add: engine.addSpectrumConsumer,
            remove: engine.removeSpectrumConsumer
        )

        // Pane 3: Octave — spectrum + magnitudes consumers
        updateConsumer(
            octaveSpectrumConsumerId,
            needed: index == 3,
            add: engine.addSpectrumConsumer,
            remove: engine.removeSpectrumConsumer
        )
        updateConsumer(
            octaveMagnitudesConsumerId,
            needed: index == 3,
            add: engine.addMagnitudesConsumer,
            remove: engine.removeMagnitudesConsumer
        )

        // Pane 4: Pitch — spectrum consumer
        updateConsumer(
            pitchConsumerId,
            needed: index == 4,
            add: engine.addSpectrumConsumer,
            remove: engine.removeSpectrumConsumer
        )

        // Pane 5: Delay — stereo consumer
        updateConsumer(
            delayConsumerId,
            needed: index == 5,
            add: engine.addStereoConsumer,
            remove: engine.removeStereoConsumer
        )
    }

    func deregisterAll() {
        for consumerId in activeConsumers {
            if let remover = consumerRemovers[consumerId] {
                remover(consumerId)
            }
        }
        activeConsumers.removeAll()
        consumerRemovers.removeAll()
    }

    private func updateConsumer(
        _ consumerId: String,
        needed: Bool,
        add: (String) -> Void,
        remove: @escaping (String) -> Void
    ) {
        if needed {
            guard activeConsumers.insert(consumerId).inserted else { return }
            consumerRemovers[consumerId] = remove
            add(consumerId)
        } else if activeConsumers.remove(consumerId) != nil {
            consumerRemovers.removeValue(forKey: consumerId)
            remove(consumerId)
        }
    }
}
