#if os(Linux)
import Foundation
import NullPlayerCore

typealias LinuxWindowHandle = UnsafeMutableRawPointer

protocol MainWindowProviding: AnyObject {
    var window: LinuxWindowHandle? { get }
    var isShadeMode: Bool { get }
    var isWindowVisible: Bool { get }

    func showWindow(_ sender: Any?)
    func updateTrackInfo(_ track: Track?)
    func updateVideoTrackInfo(title: String)
    func clearVideoTrackInfo()
    func updateTime(current: TimeInterval, duration: TimeInterval)
    func updatePlaybackState()
    func updateSpectrum(_ levels: [Float])
    func toggleShadeMode()
    func skinDidChange()
    func windowVisibilityDidChange()
    func setNeedsDisplay()
}

protocol PlaylistWindowProviding: AnyObject {
    var window: LinuxWindowHandle? { get }
    var isShadeMode: Bool { get }

    func showWindow(_ sender: Any?)
    func skinDidChange()
    func reloadPlaylist()
    func setShadeMode(_ enabled: Bool)
}

protocol LibraryBrowserWindowProviding: AnyObject {
    var window: LinuxWindowHandle? { get }
    var isShadeMode: Bool { get }
    var browseModeRawValue: Int { get set }

    func showWindow(_ sender: Any?)
    func skinDidChange()
    func setShadeMode(_ enabled: Bool)
    func reloadData()
    func showLinkSheet()
}

protocol EQWindowProviding: AnyObject {
    var window: LinuxWindowHandle? { get }
    var isShadeMode: Bool { get }

    func showWindow(_ sender: Any?)
    func skinDidChange()
    func setShadeMode(_ enabled: Bool)
}

protocol SpectrumWindowProviding: AnyObject {
    var window: LinuxWindowHandle? { get }
    var isShadeMode: Bool { get }

    func showWindow(_ sender: Any?)
    func skinDidChange()
    func stopRenderingForHide()
    func setShadeMode(_ enabled: Bool)
}

protocol WaveformWindowProviding: AnyObject {
    var window: LinuxWindowHandle? { get }
    var isShadeMode: Bool { get }

    func showWindow(_ sender: Any?)
    func skinDidChange()
    func setShadeMode(_ enabled: Bool)
    func updateTrack(_ track: Track?)
    func updateTime(current: TimeInterval, duration: TimeInterval)
    func reloadWaveform(force: Bool)
    func stopLoadingForHide()
}

protocol ProjectMWindowProviding: AnyObject {
    var window: LinuxWindowHandle? { get }
    var isShadeMode: Bool { get }
    var isFullscreen: Bool { get }
    var isPresetLocked: Bool { get set }
    var isProjectMAvailable: Bool { get }
    var currentPresetName: String { get }
    var currentPresetIndex: Int { get }
    var presetCount: Int { get }
    var presetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) { get }

    func showWindow(_ sender: Any?)
    func skinDidChange()
    func stopRenderingForHide()
    func setShadeMode(_ enabled: Bool)
    func toggleFullscreen()
    func nextPreset(hardCut: Bool)
    func previousPreset(hardCut: Bool)
    func selectPreset(at index: Int, hardCut: Bool)
    func randomPreset(hardCut: Bool)
    func reloadPresets()
}
#endif
