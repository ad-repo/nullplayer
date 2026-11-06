import Foundation

/// The running engine's presets, whatever the engine: ProjectM's preset list, Geiss's, Tripex's
/// and Goom's effect lists, AVS's preset files. The one place that knows each engine's calls, so
/// a host's keys, buttons and skin bindings step "the next one" without asking which engine runs.
/// `hardCut` (switch without blending) reaches only ProjectM, the one engine that blends.
extension VisualizationGLView {
    var enginePresetCount: Int {
        switch currentEngineType {
        case .projectM: return presetCount
        case .geiss: return geissEffectCount
        case .tripex: return tripexEffectCount
        case .avs: return (currentEngine as? AvsEngine)?.presets.count ?? 0
        case .goom: return GoomEngine.effectCount
        }
    }

    /// The running preset's index, nil when there is none yet.
    var currentEnginePresetIndex: Int? {
        let index: Int?
        switch currentEngineType {
        case .projectM: index = currentPresetIndex
        case .geiss:
            let name = currentGeissEffectName
            index = (0..<geissEffectCount).first { geissEffectName(at: $0) == name }
        case .tripex: index = currentTripexEffectIndex
        case .avs: index = (currentEngine as? AvsEngine)?.currentIndex
        case .goom: index = (currentEngine as? GoomEngine)?.currentEffect
        }
        return index.flatMap { (0..<enginePresetCount).contains($0) ? $0 : nil }
    }

    func enginePresetName(at index: Int) -> String {
        switch currentEngineType {
        case .projectM: return presetName(at: index)
        case .geiss: return geissEffectName(at: index)
        case .tripex: return tripexEffectName(at: index)
        case .avs:
            guard let presets = (currentEngine as? AvsEngine)?.presets, presets.indices.contains(index) else { return "" }
            return presets[index].deletingPathExtension().lastPathComponent
        case .goom: return GoomEngine.effectName(at: index)
        }
    }

    func selectEnginePreset(at index: Int) {
        switch currentEngineType {
        case .projectM: selectPreset(at: index)
        case .geiss: selectGeissEffect(at: index)
        case .tripex: selectTripexEffect(at: index)
        case .avs: (currentEngine as? AvsEngine)?.selectPreset(at: index)
        case .goom: (currentEngine as? GoomEngine)?.selectEffect(at: index)
        }
    }

    /// One step forwards (`delta > 0`) or backwards.
    func stepEnginePreset(by delta: Int, hardCut: Bool = false) {
        guard delta != 0 else { return }
        switch currentEngineType {
        case .projectM: delta > 0 ? nextPreset(hardCut: hardCut) : previousPreset(hardCut: hardCut)
        case .geiss: delta > 0 ? nextGeissEffect() : previousGeissEffect()
        case .tripex: delta > 0 ? nextTripexEffect() : previousTripexEffect()
        case .avs: (currentEngine as? AvsEngine)?.step(by: delta > 0 ? 1 : -1)
        case .goom: (currentEngine as? GoomEngine)?.step(by: delta > 0 ? 1 : -1)
        }
    }

    func randomEnginePreset(hardCut: Bool = false) {
        switch currentEngineType {
        case .projectM: randomPreset(hardCut: hardCut)
        case .geiss: randomGeissEffect()
        case .tripex: randomTripexEffect()
        case .avs: (currentEngine as? AvsEngine)?.selectRandomPreset()
        case .goom: (currentEngine as? GoomEngine)?.selectRandomEffect()
        }
    }
}
