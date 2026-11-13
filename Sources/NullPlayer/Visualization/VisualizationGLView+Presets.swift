import AppKit

/// The running engine's presets, whatever the engine: every host's keys, buttons, menus and skin
/// bindings step "the next one" through here without asking which engine runs. Each engine
/// answers through `VisualizationEngine`'s preset requirements, so a new engine adds nothing here.
extension VisualizationGLView {
    // Reads hold `engineLock` (`readEngine`). Changes do not: AVS loads its preset on main, and
    // holding the lock through that would stall the render thread.

    var enginePresetCount: Int { readEngine { $0?.presetCount ?? 0 } }

    /// The running preset's index, nil when there is none yet.
    var currentEnginePresetIndex: Int? {
        readEngine { engine in
            guard let engine, let index = engine.presetIndex else { return nil }
            return (0..<engine.presetCount).contains(index) ? index : nil
        }
    }

    func enginePresetName(at index: Int) -> String { readEngine { $0?.presetName(at: index) ?? "" } }

    func selectEnginePreset(at index: Int) {
        currentEngine?.selectPreset(at: index, hardCut: false)
        enginePresetDidChange?()
    }

    /// One step forwards (`delta > 0`) or backwards. `hardCut` (switch without blending) reaches
    /// only ProjectM, the one engine that blends.
    func stepEnginePreset(by delta: Int, hardCut: Bool = false) {
        guard delta != 0 else { return }
        currentEngine?.stepPreset(forward: delta > 0, hardCut: hardCut)
        enginePresetDidChange?()
    }

    func randomEnginePreset(hardCut: Bool = false) {
        currentEngine?.randomPreset(hardCut: hardCut)
        enginePresetDidChange?()
    }

    // MARK: - The shared menu's actions (`VisualizationContextMenu`), so no host repeats them

    @objc func nextPresetMenuAction(_ sender: NSMenuItem) { stepEnginePreset(by: 1) }
    @objc func previousPresetMenuAction(_ sender: NSMenuItem) { stepEnginePreset(by: -1) }
    @objc func randomPresetMenuAction(_ sender: NSMenuItem) { randomEnginePreset() }
    @objc func selectPresetMenuAction(_ sender: NSMenuItem) { selectEnginePreset(at: sender.tag) }

    @objc func setCycleModeMenuAction(_ sender: NSMenuItem) {
        guard let mode = (sender.representedObject as? String).flatMap(VisualizationCycleMode.init) else { return }
        presetCycler.mode = mode
    }

    @objc func setCycleIntervalMenuAction(_ sender: NSMenuItem) {
        presetCycler.interval = TimeInterval(sender.tag)
    }
}
