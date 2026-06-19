import Foundation

/// Keeps the audio engine work gated to the currently visible analysis pane.
final class AudioAnalysisConsumerCoordinator {
    private let scopeConsumerId = "audioAnalysis.scope"
    private let levelsConsumerId = "audioAnalysis.levels"
    private let spectrogramConsumerId = "audioAnalysis.spectrogram"
    private var activeConsumers: Set<String> = []

    func setVisiblePane(_ index: Int) {
        let engine = WindowManager.shared.audioEngine

        updateConsumer(
            scopeConsumerId,
            needed: index == 0,
            add: engine.addSpectrumConsumer,
            remove: engine.removeSpectrumConsumer
        )
        updateConsumer(
            levelsConsumerId,
            needed: index == 1,
            add: engine.addStereoConsumer,
            remove: engine.removeStereoConsumer
        )
        updateConsumer(
            spectrogramConsumerId,
            needed: index == 2,
            add: engine.addSpectrumConsumer,
            remove: engine.removeSpectrumConsumer
        )
    }

    func deregisterAll() {
        let engine = WindowManager.shared.audioEngine
        for consumerId in activeConsumers {
            if consumerId == levelsConsumerId {
                engine.removeStereoConsumer(consumerId)
            } else {
                engine.removeSpectrumConsumer(consumerId)
            }
        }
        activeConsumers.removeAll()
    }

    private func updateConsumer(
        _ consumerId: String,
        needed: Bool,
        add: (String) -> Void,
        remove: (String) -> Void
    ) {
        if needed {
            guard activeConsumers.insert(consumerId).inserted else { return }
            add(consumerId)
        } else if activeConsumers.remove(consumerId) != nil {
            remove(consumerId)
        }
    }
}
