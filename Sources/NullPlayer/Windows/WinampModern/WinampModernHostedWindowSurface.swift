import AppKit
import NullPlayerCore

/// The runtime context a synthesized `.wal` host-window adapter can act through.
///
/// The view layer mounts only typed hosted surfaces, not raw window views. That keeps controller and
/// window-manager actions behind narrow callbacks so a surface can ask to close or fullscreen itself
/// without reaching around the `.wal` window layer directly.
struct WinampModernHostedSurfaceContext {
    let audioEngine: AudioEngine
    let nativeWindow: () -> NSWindow?
    let requestClose: () -> Void
    let requestFullscreen: () -> Void
}

/// A NullPlayer-owned surface mounted inside a synthesized `.wal` holder.
///
/// Unlike the existing library/video/visualization protocols, this is for full host windows the skin
/// itself does not define. The bridge owns one adapter per hosted-window id per loaded skin and the
/// scene mounts or unmounts the adapter's view as holders come and go.
protocol WinampModernHostedSurface: AnyObject {
    var view: NSView { get }
    func applyPalette(_ style: WinampModernSurfaceStyle)
    func applySkinScale(_ scale: CGFloat)
    func resume()
    func suspend()
    func unmountFromHolder()
    func prepareForUITeardown()
}

/// Optional capabilities exposed only by the hosted surfaces that own them. WindowManager performs
/// the one typed-id routing switch; the registry/materializer remain feature-agnostic.
protocol WinampModernHostedFullscreenSurface: WinampModernHostedSurface {
    var isFullscreen: Bool { get }
    func toggleFullscreen()
}

protocol WinampModernHostedCavaSurface: WinampModernHostedSurface {
    func refreshAfterReset()
}

protocol WinampModernHostedWaveformSurface: WinampModernHostedSurface {
    func updateTrack(_ track: Track?)
    func updateTime(current: TimeInterval, duration: TimeInterval)
    func reloadWaveform(force: Bool)
}
