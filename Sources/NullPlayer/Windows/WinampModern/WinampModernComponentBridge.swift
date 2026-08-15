import AppKit
import Foundation
import NullPlayerCore

/// Production `WinampModernComponentHost` that bridges embedded skin components to real NullPlayer
/// state. It exposes only the typed playlist/EQ/library operations the Wasabi runtime needs; the
/// skin never gains filesystem, network, or arbitrary app access through this seam. Playlist and EQ
/// bind to the shared `AudioEngine`; unavailable surfaces fall back to the classic WindowManager
/// windows (the Phase 1 auxiliary-window policy) rather than failing.
final class WinampModernComponentBridge: WinampModernComponentHost {
    private let engine: AudioEngine
    private let eqLayout = EQConfiguration.classic10
    private var selectedRow = -1

    init(engine: AudioEngine) {
        self.engine = engine
    }

    // MARK: - Playlist

    func playlistSnapshot() -> WinampModernPlaylistSnapshot {
        let rows = engine.playlist.enumerated().map { index, track in
            WinampModernPlaylistRow(
                title: track.title,
                secondary: [track.artist, track.album].compactMap { $0 }.joined(separator: " — "),
                duration: track.duration ?? 0,
                isCurrent: index == engine.currentIndex
            )
        }
        return WinampModernPlaylistSnapshot(rows: rows,
                                            currentIndex: engine.currentIndex,
                                            selectedIndex: selectedRow < rows.count ? selectedRow : -1)
    }

    func playlistSelect(row: Int) {
        guard row >= 0, row < engine.playlist.count else { return }
        selectedRow = row
    }

    func playlistPlay(row: Int) {
        guard row >= 0, row < engine.playlist.count else { return }
        selectedRow = row
        engine.playTrack(at: row)
    }

    func playlistRemove(row: Int) {
        guard row >= 0, row < engine.playlist.count else { return }
        engine.removeTrack(at: row)
        if selectedRow >= engine.playlist.count { selectedRow = engine.playlist.count - 1 }
    }

    // MARK: - Equalizer (classic10)

    func equalizerSnapshot() -> WinampModernEQSnapshot {
        WinampModernEQSnapshot(
            bandGainsDB: (0..<eqLayout.bandCount).map { engine.getEQBand($0) },
            preampDB: engine.getPreamp(),
            enabled: engine.isEQEnabled(),
            auto: UserDefaults.standard.bool(forKey: "EQAutoEnabled"),
            presetNames: EQPreset.allPresets.map(\.name)
        )
    }

    func equalizerSetBandGainDB(_ band: Int, gainDB: Float) {
        engine.setEQBand(band, gain: gainDB)
    }

    func equalizerSetPreampDB(_ gainDB: Float) {
        engine.setPreamp(gainDB)
    }

    func equalizerSetEnabled(_ enabled: Bool) {
        engine.setEQEnabled(enabled)
    }

    func equalizerSetAuto(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "EQAutoEnabled")
        guard enabled, let genre = engine.currentTrack?.genre,
              let preset = EQPreset.forGenre(genre) else { return }
        applyPreset(preset)
    }

    func equalizerApplyPreset(named name: String) {
        guard let preset = EQPreset.allPresets.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else { return }
        applyPreset(preset)
    }

    private func applyPreset(_ preset: EQPreset) {
        engine.setPreamp(preset.preamp)
        for (index, gain) in preset.bands.enumerated() where index < eqLayout.bandCount {
            engine.setEQBand(index, gain: gain)
        }
    }

    // MARK: - Library

    /// Embedding NullPlayer's full library browser inside the skin frame is a live, GUI-only
    /// integration; the bounded seam returns nil so the runtime falls back to the classic library
    /// window (see `toggleClassicWindow`). Wiring the live browser view is deferred to Phase 7.
    func makeLibraryContentView() -> NSView? { nil }

    // MARK: - Classic-window fallback

    func toggleClassicWindow(for kind: WinampModernComponentKind) {
        switch kind {
        case .playlist: WindowManager.shared.togglePlaylist()
        case .equalizer: WindowManager.shared.toggleEqualizer()
        case .library: WindowManager.shared.togglePlexBrowser()
        case .visualization, .video, .other: break
        }
    }
}
