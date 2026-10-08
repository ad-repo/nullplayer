import AppKit

extension WindowManager {
    /// The windows that dock in the column below the main window.
    ///
    /// The equalizer and playlist belong to the main trio and keep paths of their own. Every other
    /// case is a **feature window**: each snapshot, restore, repair and saved-state path walks
    /// `featureWindows` and reads the window through `centerStackFeatureWindow(_:)`, so a new one
    /// joins all of them by adding a case here and its row there.
    enum CenterStackWindowKind: CaseIterable {
        case equalizer
        case playlist
        // Feature windows, in the order a restore opens them (and the z-order they are raised in).
        // A window opened without a frame goes to the bottom of the stack, so this order is also
        // where each lands when its frame is not carried across a family switch.
        case spectrum
        case audioAnalysis
        case peppyMeter
        case art
        case networkMonitor
        case cava
        case sonos
        case waveform

        static let featureWindows = allCases.filter { $0 != .equalizer && $0 != .playlist }

        /// The feature windows top to bottom in the column the UI Size reflow rebuilds: Spectrum
        /// and Waveform first, then the rest in open order. The launch repair walks the same order.
        static let stackOrder: [CenterStackWindowKind] =
            [.spectrum, .waveform] + featureWindows.filter { $0 != .spectrum && $0 != .waveform }

        /// The whole column below the main window, top to bottom.
        static let columnOrder: [CenterStackWindowKind] = [.equalizer, .playlist] + stackOrder

        /// The key `AppStateManager` files this window's restored frame under.
        var stateKey: String { "\(self)" }

        /// Where `AppState` keeps this window's visibility and frame. Both stay flat keys on disk
        /// (`isSpectrumVisible`, `spectrumWindowFrame`), so a saved state from any build decodes.
        var savedVisibility: WritableKeyPath<AppStateManager.AppState, Bool> {
            switch self {
            case .equalizer: return \.isEqualizerVisible
            case .playlist: return \.isPlaylistVisible
            case .spectrum: return \.isSpectrumVisible
            case .audioAnalysis: return \.isAudioAnalysisVisible
            case .peppyMeter: return \.isPeppyMeterVisible
            case .art: return \.isArtVisible
            case .networkMonitor: return \.isNetworkMonitorVisible
            case .cava: return \.isCavaVisible
            case .sonos: return \.isSonosVisible
            case .waveform: return \.isWaveformVisible
            }
        }

        var savedFrame: WritableKeyPath<AppStateManager.AppState, String?> {
            switch self {
            case .equalizer: return \.equalizerWindowFrame
            case .playlist: return \.playlistWindowFrame
            case .spectrum: return \.spectrumWindowFrame
            case .audioAnalysis: return \.audioAnalysisWindowFrame
            case .peppyMeter: return \.peppyMeterWindowFrame
            case .art: return \.artWindowFrame
            case .networkMonitor: return \.networkMonitorWindowFrame
            case .cava: return \.cavaWindowFrame
            case .sonos: return \.sonosWindowFrame
            case .waveform: return \.waveformWindowFrame
            }
        }
    }

    /// One feature window as every snapshot, restore and repair path sees it.
    struct CenterStackFeatureWindow {
        /// The per-feature controller; nil until first opened, and while a `.wal` skin hosts the
        /// window instead.
        let controller: ModeDependentWindow?
        /// The window on screen: the hosted one when a `.wal` skin hosts it, else the controller's.
        let window: NSWindow?
        /// Whether it is open, in either chrome.
        let isVisible: Bool
        /// Opens it, at a frame or (nil) at its default place.
        let show: (NSRect?) -> Void
    }
}
