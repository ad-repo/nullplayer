import AppKit
import CoreGraphics
import Foundation

/// How loud one spectrum analyzer draws in a `.wal` skin's `<vis>` box (B53).
///
/// **Why this exists at all.** The three engines that can paint that box measure the same audio on
/// three scales that were never meant to agree: Winamp's own analyzer maps its bands through a
/// decibel curve, so ordinary music fills the box to the top; Cava normalises linearly under its own
/// slow auto-gain; and vis_classic scales against a canvas cut for a 128px-tall window. Dropped into
/// a 30px skin box side by side, the first reads hot and the other two read cold.
///
/// `WasabiVisStyle.Gain` is the calibration that brings them to a common loudness — measured by eye
/// against each other, which is the only instrument that settles "too hot". This is the **user's
/// adjustment on top of it**, as a percentage of that calibrated default, so `Normal` is always the
/// tuned value and the menu means the same thing for every engine.
///
/// Per engine and **not** per skin: it calibrates an engine's own scale, not an author's artwork, so
/// a Cava turned up once stays turned up in every skin. That is the opposite of the choice of engine
/// (`WinampModernSkinState`), which is per skin because it is about how a skin should look.
enum WinampModernVisSensitivity: Int, CaseIterable {
    case lowest = 60
    case lower = 80
    case normal = 100
    case higher = 130
    case highest = 160

    /// A multiplier on the engine's calibrated gain. `Normal` is exactly the calibration.
    var multiplier: CGFloat { CGFloat(rawValue) / 100 }

    var displayName: String {
        switch self {
        case .lowest: return "Lowest"
        case .lower: return "Lower"
        case .normal: return "Normal"
        case .higher: return "Higher"
        case .highest: return "Highest"
        }
    }

    static func from(storedValue: Int) -> WinampModernVisSensitivity {
        WinampModernVisSensitivity(rawValue: storedValue) ?? .normal
    }

    // MARK: - Persistence

    static func key(for analyzer: WinampModernSpectrumAnalyzer) -> String {
        "winampModern.visSensitivity.\(analyzer.rawValue)"
    }

    static func stored(for analyzer: WinampModernSpectrumAnalyzer,
                       defaults: UserDefaults = .standard) -> WinampModernVisSensitivity {
        if let cached = cache[analyzer] { return cached }
        let key = key(for: analyzer)
        let value = defaults.object(forKey: key) == nil
            ? .normal : from(storedValue: defaults.integer(forKey: key))
        cache[analyzer] = value
        return value
    }

    static func set(_ sensitivity: WinampModernVisSensitivity,
                    for analyzer: WinampModernSpectrumAnalyzer,
                    defaults: UserDefaults = .standard) {
        defaults.set(sensitivity.rawValue, forKey: key(for: analyzer))
        cache[analyzer] = sensitivity
    }

    /// The setting is read **once per band per frame** by the analyzer that is drawing, so it is held
    /// in memory rather than asked of `UserDefaults` at that rate. Every write goes through `set`,
    /// which is the only thing that can move it.
    private nonisolated(unsafe) static var cache: [WinampModernSpectrumAnalyzer: WinampModernVisSensitivity] = [:]

    /// Drop the memoized values — for tests, which write straight to their own `UserDefaults`.
    static func invalidateCache() { cache.removeAll() }

    /// The gain an engine actually draws at: its calibration times the user's adjustment.
    static func gain(for analyzer: WinampModernSpectrumAnalyzer,
                     defaults: UserDefaults = .standard) -> CGFloat {
        let calibration: CGFloat
        switch analyzer {
        case .skin: calibration = WasabiVisStyle.Gain.builtInAnalyzer
        case .cava: calibration = CGFloat(WasabiVisStyle.Gain.cava)
        case .visClassic: calibration = CGFloat(WasabiVisStyle.Gain.visClassicInput)
        }
        return calibration * stored(for: analyzer, defaults: defaults).multiplier
    }

    /// The same setting, applied to Winamp's **oscilloscope**. One Sensitivity for the skin's own
    /// engine covers both of its modes — it is one engine and one row in the menu — but the two
    /// surfaces are calibrated apart, because the analyzer needed turning down off its decibel curve
    /// and the scope, which draws the wave itself, never did.
    static func oscilloscopeGain(defaults: UserDefaults = .standard) -> CGFloat {
        WasabiVisStyle.Gain.builtInOscilloscope * stored(for: .skin, defaults: defaults).multiplier
    }
}

/// The **Sensitivity** submenu, and the thing that answers it.
///
/// One builder rather than one per engine, and it lives beside the setting instead of in the view:
/// the same submenu is offered from the box's own right-click menu and from the menu bar, and those
/// two routes describing one control differently is the defect this file exists to avoid. It owns
/// the repaint too — a gain change moves nothing on screen until something asks for one, and a
/// paused player has no clock running to notice.
final class WinampModernVisSensitivityMenu: NSObject {
    static let shared = WinampModernVisSensitivityMenu()

    func menuItem(for analyzer: WinampModernSpectrumAnalyzer, enabled: Bool = true) -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = WinampModernVisSensitivity.stored(for: analyzer)
        for level in WinampModernVisSensitivity.allCases {
            let item = NSMenuItem(title: level.displayName, action: #selector(apply(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = "\(analyzer.rawValue)|\(level.rawValue)"
            item.state = level == current ? .on : .off
            item.isEnabled = enabled
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: "Sensitivity", action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = enabled
        return item
    }

    @objc private func apply(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? String else { return }
        let parts = spec.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let raw = Int(parts[1]) else { return }
        WinampModernVisSensitivity.set(WinampModernVisSensitivity.from(storedValue: raw),
                                       for: WinampModernSpectrumAnalyzer.from(storedValue: String(parts[0])))
        WindowManager.shared.repaintWinampModernVisualization()
    }
}
