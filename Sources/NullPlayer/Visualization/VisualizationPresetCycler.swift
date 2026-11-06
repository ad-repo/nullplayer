import Foundation

/// Auto-advances the running engine's presets: the one cycle timer for every engine in every host
/// (the Visualizations windows, the `.wal` surface, the `.wmz` / Sonique effects area). Each
/// engine's own switching is held when it is created (`VisualizationGLView.createEngine`), so a
/// preset changes only here or by hand. `stopRendering` stops it and `startRendering` or an engine
/// switch starts it again; the `.wmz` / Sonique surface's offscreen engine never starts a display
/// link, so that host starts it itself. Main thread only.
final class VisualizationPresetCycler {
    /// The view whose engine this cycles, set once by that view's `init`.
    weak var view: VisualizationGLView?
    private var timer: Timer?

    deinit { timer?.invalidate() }

    var mode: VisualizationCycleMode {
        get { view.map { VisualizationCycleSettings.mode(for: $0.currentEngineType) } ?? .off }
        set {
            guard let view else { return }
            VisualizationCycleSettings.save(mode: newValue, for: view.currentEngineType)
            restart()
        }
    }

    var interval: TimeInterval {
        get { view.map { VisualizationCycleSettings.interval(for: $0.currentEngineType) } ?? VisualizationCycleSettings.defaultInterval }
        set {
            guard let view else { return }
            VisualizationCycleSettings.save(interval: newValue, for: view.currentEngineType)
            restart()
        }
    }

    /// Re-reads the running engine's choice and waits a full interval from now.
    func restart() {
        stop()
        guard view != nil, mode != .off else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard let view else { return }
        // The editor's preset would be thrown away under it.
        if (view.currentEngine as? AvsEngine)?.isBeingEdited == true { return }
        mode == .random ? view.randomEnginePreset() : view.stepEnginePreset(by: 1)
    }
}
