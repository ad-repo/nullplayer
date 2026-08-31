import AppKit

protocol ReeltoneComponentHosting: AnyObject {
    var component: ReeltoneComponent { get }
    var view: NSView { get }
    func layout(in frame: NSRect)
    func updateTheme()
    func updateSpectrum(_ levels: [Float])
    func focus()
    func visibilityDidChange(_ visible: Bool)
    func prepareForTeardown()
}

extension ReeltoneComponentHosting {
    func layout(in frame: NSRect) { view.frame = frame }
    func updateTheme() { view.needsDisplay = true }
    func updateSpectrum(_ levels: [Float]) {}
    func focus() { view.window?.makeFirstResponder(view) }
    func visibilityDidChange(_ visible: Bool) {}
    func prepareForTeardown() { view.removeFromSuperview() }
}

struct ReeltoneComponentHostFactory {
    let makeHost: (ReeltoneSurfaceRegion, NSRect) -> ReeltoneComponentHosting?

    static let live = ReeltoneComponentHostFactory { region, frame in
        switch region.component {
        case .trackList: return ReeltonePlaylistHost(frame: frame, region: region)
        case .equaliser: return ReeltoneEqualizerHost(frame: frame)
        case .library: return ReeltoneLibraryHost(frame: frame, region: region)
        case .visualiser: return ReeltoneVisualizerHost(frame: frame)
        default: return nil
        }
    }
}

final class ReeltonePlaylistHost: ReeltoneComponentHosting {
    let component = ReeltoneComponent.trackList
    let playlistView: ModernPlaylistView
    var view: NSView { playlistView }

    private let authoredRowHeight: CGFloat?
    private let authoredWidth: CGFloat

    init(frame: NSRect, region: ReeltoneSurfaceRegion) {
        authoredRowHeight = region.manifestRegion.rowHeight.map { CGFloat($0) }
        authoredWidth = CGFloat(region.authoredRect.width)
        playlistView = ModernPlaylistView(frame: frame)
        playlistView.isEmbedded = true
        playlistView.autoresizingMask = [.width, .height]
        applyRowHeight(in: frame)
    }

    func layout(in frame: NSRect) {
        playlistView.frame = frame
        applyRowHeight(in: frame)
    }

    private func applyRowHeight(in frame: NSRect) {
        guard let authoredRowHeight, authoredWidth > 0 else { return }
        playlistView.embeddedRowHeightOverride = authoredRowHeight * frame.width / authoredWidth
    }

    func updateTheme() { playlistView.skinDidChange() }
    func visibilityDidChange(_ visible: Bool) { playlistView.setEmbeddedHostVisible(visible) }
    func prepareForTeardown() {
        playlistView.removeFromSuperview()
    }
}

final class ReeltoneEqualizerHost: ReeltoneComponentHosting {
    let component = ReeltoneComponent.equaliser
    let equalizerView: ModernEQView
    var view: NSView { equalizerView }

    init(frame: NSRect) {
        equalizerView = ModernEQView(frame: frame, preferences: ReeltoneDefaults.shared)
        equalizerView.isEmbedded = true
        equalizerView.autoresizingMask = [.width, .height]
    }

    func updateTheme() { equalizerView.skinDidChange() }
}

final class ReeltoneLibraryHost: ReeltoneComponentHosting {
    let component = ReeltoneComponent.library
    let libraryView: ModernLibraryBrowserView
    var view: NSView { libraryView }

    private let authoredRowHeight: CGFloat?
    private let authoredWidth: CGFloat

    init(frame: NSRect, region: ReeltoneSurfaceRegion) {
        authoredRowHeight = region.manifestRegion.rowHeight.map { CGFloat($0) }
        authoredWidth = CGFloat(region.authoredRect.width)
        libraryView = ModernLibraryBrowserView(frame: frame, preferences: ReeltoneDefaults.shared)
        libraryView.isEmbedded = true
        libraryView.autoresizingMask = [.width, .height]
        applyRowHeight(in: frame)
    }

    func layout(in frame: NSRect) {
        libraryView.frame = frame
        applyRowHeight(in: frame)
    }

    private func applyRowHeight(in frame: NSRect) {
        guard let authoredRowHeight, authoredWidth > 0 else { return }
        libraryView.embeddedRowHeightOverride = authoredRowHeight * frame.width / authoredWidth
    }

    func updateTheme() { libraryView.skinDidChange() }
    func visibilityDidChange(_ visible: Bool) { libraryView.setEmbeddedHostVisible(visible) }
    func prepareForTeardown() {
        libraryView.prepareForUITeardown()
        libraryView.removeFromSuperview()
    }
}

final class ReeltoneVisualizerHost: ReeltoneComponentHosting {
    let component = ReeltoneComponent.visualiser
    let visualizerView: SpectrumAnalyzerView
    var view: NSView { visualizerView }

    init(frame: NSRect) {
        visualizerView = SpectrumAnalyzerView(
            frame: frame,
            preferences: ReeltoneDefaults.shared,
            embedded: true,
            normalizationUserDefaultsKey: "visualizer.normalizationMode"
        )
        visualizerView.qualityMode = .classic
        visualizerView.decayMode = .snappy
        visualizerView.barCount = max(8, min(84, Int(frame.width / 4)))
        visualizerView.autoresizingMask = [.width, .height]
        updateTheme()
    }

    func updateTheme() {
        visualizerView.spectrumColors = ReeltoneSkinEngine.shared.currentTheme.presentationSkin.spectrumColors()
    }

    func updateSpectrum(_ levels: [Float]) { visualizerView.updateSpectrum(levels) }

    func visibilityDidChange(_ visible: Bool) {
        if visible { visualizerView.startDisplayLink() } else { visualizerView.stopDisplayLink() }
    }

    func prepareForTeardown() {
        visualizerView.stopDisplayLink()
        visualizerView.removeFromSuperview()
    }
}
