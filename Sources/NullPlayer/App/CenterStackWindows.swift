import AppKit

extension WindowManager {
    /// The windows that dock in the column below the main window: the main trio's equalizer and
    /// playlist, then the feature windows. Sizing and docking switch on this; every snapshot,
    /// restore and saved-state path walks `CenterStackFeature` instead.
    enum CenterStackWindowKind: CaseIterable {
        case equalizer
        case playlist
        case spectrum
        case audioAnalysis
        case peppyMeter
        case art
        case networkMonitor
        case cava
        case sonos
        case waveform

        /// The whole column below the main window, top to bottom.
        static let columnOrder: [CenterStackWindowKind] =
            [.equalizer, .playlist] + CenterStackFeature.stackOrder.map(\.kind)
    }

    /// The centre-stack windows other than the equalizer and playlist, which keep paths of their
    /// own. Each snapshot, restore, repair and saved-state path walks `allCases` and reads the
    /// window through `centerStackFeatureWindow(_:)`, so a new one joins all of them by adding a
    /// case here and its row there.
    enum CenterStackFeature: CaseIterable {
        // In the order a restore opens them (and the z-order they are raised in). A window opened
        // without a frame goes to the bottom of the stack, so this order is also where each lands
        // when its frame is not carried across a family switch.
        case spectrum
        case audioAnalysis
        case peppyMeter
        case art
        case networkMonitor
        case cava
        case sonos
        case waveform

        /// Every feature window but Spectrum and Waveform, which the UI Size reflow restacks by
        /// rules of their own.
        static let spectrumFamily = allCases.filter { $0 != .spectrum && $0 != .waveform }

        /// Top to bottom in the column the UI Size reflow rebuilds: Spectrum and Waveform first,
        /// then the rest in open order. The launch repair walks the same order.
        static let stackOrder: [CenterStackFeature] = [.spectrum, .waveform] + spectrumFamily

        var kind: CenterStackWindowKind {
            switch self {
            case .spectrum: .spectrum
            case .audioAnalysis: .audioAnalysis
            case .peppyMeter: .peppyMeter
            case .art: .art
            case .networkMonitor: .networkMonitor
            case .cava: .cava
            case .sonos: .sonos
            case .waveform: .waveform
            }
        }

        /// The window a `.wal` skin hosts in place of this one's controller.
        var hostedID: WinampModernHostedWindowID {
            switch self {
            case .spectrum: .spectrum
            case .audioAnalysis: .audioAnalysis
            case .peppyMeter: .peppyMeter
            case .art: .art
            case .networkMonitor: .flow
            case .cava: .cava
            case .sonos: .sonos
            case .waveform: .waveform
            }
        }

        /// The key `AppStateManager` files this window's restored frame under.
        var stateKey: String { "\(self)" }

        /// Where `AppState` keeps this window's visibility and frame. Both stay flat keys on disk
        /// (`isSpectrumVisible`, `spectrumWindowFrame`), so a saved state from any build decodes.
        var savedVisibility: WritableKeyPath<AppStateManager.AppState, Bool> {
            switch self {
            case .spectrum: \.isSpectrumVisible
            case .audioAnalysis: \.isAudioAnalysisVisible
            case .peppyMeter: \.isPeppyMeterVisible
            case .art: \.isArtVisible
            case .networkMonitor: \.isNetworkMonitorVisible
            case .cava: \.isCavaVisible
            case .sonos: \.isSonosVisible
            case .waveform: \.isWaveformVisible
            }
        }

        var savedFrame: WritableKeyPath<AppStateManager.AppState, String?> {
            switch self {
            case .spectrum: \.spectrumWindowFrame
            case .audioAnalysis: \.audioAnalysisWindowFrame
            case .peppyMeter: \.peppyMeterWindowFrame
            case .art: \.artWindowFrame
            case .networkMonitor: \.networkMonitorWindowFrame
            case .cava: \.cavaWindowFrame
            case .sonos: \.sonosWindowFrame
            case .waveform: \.waveformWindowFrame
            }
        }
    }

    /// One feature window's row: the per-feature controller (nil until first opened, and while a
    /// `.wal` skin hosts the window instead) and how it opens, at a frame or (nil) at its default
    /// place. The window on screen and its visibility follow from it: `centerStackWindow(_:)`.
    struct CenterStackFeatureWindow {
        let controller: ModeDependentWindow?
        let show: (NSRect?) -> Void
    }
}
