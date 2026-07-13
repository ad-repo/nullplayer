import AppKit
import NullPlayerCore

// MARK: - Notifications

extension Notification.Name {
    static let timeDisplayModeDidChange = Notification.Name("timeDisplayModeDidChange")
    static let timeDisplaySettingsDidChange = Notification.Name("timeDisplaySettingsDidChange")
    static let doubleSizeDidChange = Notification.Name("doubleSizeDidChange")
    static let windowLayoutDidChange = Notification.Name("windowLayoutDidChange")
    static let connectedWindowHighlightDidChange = Notification.Name("connectedWindowHighlightDidChange")
    static let windowDragDidBegin = Notification.Name("windowDragDidBegin")
    static let windowDragDidEnd = Notification.Name("windowDragDidEnd")
}

#if DEBUG
extension WindowManager {
    var debugVideoPlayerWindowControllerForTesting: VideoPlayerWindowController? {
        videoPlayerWindowController
    }

    var debugTargetVideoCastDeviceForTesting: CastDevice? {
        targetVideoCastDevice
    }

    func debugSetVideoPlayerWindowControllerForTesting(_ controller: VideoPlayerWindowController?) {
        videoPlayerWindowController = controller
    }
}
#endif

// MARK: - Time Display Mode

enum TimeDisplayMode: String {
    case elapsed
    case remaining
}

enum TimeDisplayNumberSystem: String, CaseIterable {
    case decimal
    case arabicIndic
    case extendedArabicIndic
    case devanagari
    case bengali
    case thai
    case fullwidth
    case octal
    case hexadecimal

    static let modernDefault: TimeDisplayNumberSystem = .decimal

    var displayName: String {
        switch self {
        case .decimal:
            return "Decimal"
        case .arabicIndic:
            return "Arabic-Indic"
        case .extendedArabicIndic:
            return "Extended Arabic-Indic"
        case .devanagari:
            return "Devanagari"
        case .bengali:
            return "Bengali"
        case .thai:
            return "Thai"
        case .fullwidth:
            return "Fullwidth"
        case .octal:
            return "Octal"
        case .hexadecimal:
            return "Hexadecimal"
        }
    }
}

enum UIScaleLevel: String, Codable, CaseIterable {
    case p50 = "50"
    case p90 = "90"
    case p100 = "100"
    case p105 = "105"
    case p110 = "110"
    case p115 = "115"
    case p125 = "125"
    case p135 = "135"
    case p150 = "150"
    case p200 = "200"

    var percent: Int {
        Int(rawValue) ?? 100
    }

    var menuTitle: String {
        "\(percent)%"
    }

    /// Linear scale multiplier applied on top of Skin.scaleFactor.
    var scaleFactor: CGFloat {
        CGFloat(percent) / 100.0
    }

    init?(storedRawValue: String) {
        switch storedRawValue {
        case "normal":
            self = .p100
        case "medium":
            self = .p125
        case "large":
            self = .p150
        default:
            self.init(rawValue: storedRawValue)
        }
    }
}

/// Determines how a window drag affects its connected group.
enum DragMode {
    case pending   // mouseDown received, drag not yet started
    case separate  // drag started before holdThreshold — window moves alone
    case group     // holdThreshold elapsed before drag — connected windows move together
}

private enum CompactModeState {
    case regular
    case entering
    case compactHidden
    case compactVisible
    case exiting
}

private struct WindowSnapshot {
    var wasVisible: Bool
    var frame: NSRect
    /// Normal frame for position memory (Library only). Stores the full window frame.
    /// nil for windows with no special frame handling.
    var normalFrame: NSRect?
    /// Whether a side window (Library/ProjectM) was detached from the main-window edge (not docked)
    /// at capture time. Used to re-detach it after a UI Size re-apply force-docks it. Always false
    /// for non-side windows.
    var wasDetached: Bool = false
}

private struct CompactWindowSnapshot {
    var main: WindowSnapshot?
    var equalizer: WindowSnapshot?
    var playlist: WindowSnapshot?
    var spectrum: WindowSnapshot?
    var audioAnalysis: WindowSnapshot?
    var peppyMeter: WindowSnapshot?
    var networkMonitor: WindowSnapshot?
    var waveform: WindowSnapshot?
    var projectM: WindowSnapshot?
    var library: WindowSnapshot?
    var debug: WindowSnapshot?
    var additionalWindows: [NSWindow] = []
}

/// Joined edge intervals for seamless modern window border suppression.
/// Top/bottom ranges are in local X coordinates; left/right ranges are in local Y coordinates.
struct EdgeOcclusionSegments: Equatable {
    var top: [ClosedRange<CGFloat>] = []
    var bottom: [ClosedRange<CGFloat>] = []
    var left: [ClosedRange<CGFloat>] = []
    var right: [ClosedRange<CGFloat>] = []

    static let empty = EdgeOcclusionSegments()

    var isEmpty: Bool {
        top.isEmpty && bottom.isEmpty && left.isEmpty && right.isEmpty
    }
}

/// Manages all application windows and their interactions
/// Handles window docking, snapping, and coordinated movement
class WindowManager {
    
    // MARK: - Singleton
    
    static let shared = WindowManager()
    
    // MARK: - Properties
    
    /// The audio engine instance
    let audioEngine = AudioEngine()
    
    /// The currently loaded skin
    private(set) var currentSkin: Skin?
    
    /// Path to the currently loaded custom skin (nil if using a base skin)
    private(set) var currentSkinPath: String?
    
    
    // MARK: - User Preferences
    
    /// Time display mode (elapsed vs remaining)
    var timeDisplayMode: TimeDisplayMode = .elapsed {
        didSet {
            UserDefaults.standard.set(timeDisplayMode.rawValue, forKey: "timeDisplayMode")
            NotificationCenter.default.post(name: .timeDisplayModeDidChange, object: nil)
            NotificationCenter.default.post(name: .timeDisplaySettingsDidChange, object: nil)
        }
    }

    private var storedTimeDisplayNumberSystem: TimeDisplayNumberSystem = .modernDefault

    /// Numeral system for the modern time display. Falls back to decimal outside modern UI mode.
    var timeDisplayNumberSystem: TimeDisplayNumberSystem {
        get { isRunningModernUI ? storedTimeDisplayNumberSystem : .modernDefault }
        set {
            guard isRunningModernUI else { return }
            guard storedTimeDisplayNumberSystem != newValue else { return }
            storedTimeDisplayNumberSystem = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "timeDisplayNumberSystem")
            NotificationCenter.default.post(name: .timeDisplaySettingsDidChange, object: nil)
        }
    }
    
    /// UI scale mode - not persisted here, restored by AppStateManager when Remember State is enabled.
    var uiScaleLevel: UIScaleLevel = .p100 {
        didSet {
            guard oldValue != uiScaleLevel else { return }
            applyUIScaleLevelChangeIfNeeded()
        }
    }

    private var appliedUIScaleLevel: UIScaleLevel = .p100
    private var isApplyingUIScaleLevel = false
    private var pendingUIScaleLevel: UIScaleLevel?

    /// Back-compat shim for callers that only need to know whether the UI is at a non-default size.
    var isDoubleSize: Bool {
        uiScaleLevel != .p100
    }

    /// Classic UI size multiplier driven by the UI Size menu.
    /// Stays discrete so free window stretching does not alter skin scale.
    var classicScaleMultiplier: CGFloat {
        uiScaleLevel.scaleFactor
    }

    /// Scale factor for playlist-style title-bar controls on classic secondary windows,
    /// derived from the live main-window width so chrome stays in sync when the user resizes.
    var playlistChromeScale: CGFloat {
        if let mainWindow = mainWindowController?.window, mainWindow.frame.width > 0 {
            return mainWindow.frame.width / Skin.baseMainSize.width
        }
        return Skin.scaleFactor * classicScaleMultiplier
    }
    
    /// Always on top mode (floating window level)
    var isAlwaysOnTop: Bool = false {
        didSet {
            UserDefaults.standard.set(isAlwaysOnTop, forKey: "isAlwaysOnTop")
            NSLog("WindowManager: isAlwaysOnTop changed to %d, applying to windows", isAlwaysOnTop ? 1 : 0)
            applyAlwaysOnTop()
        }
    }

    /// Lock connected windows so dragging keeps connected groups together.
    var isWindowLayoutLocked: Bool = false {
        didSet {
            UserDefaults.standard.set(isWindowLayoutLocked, forKey: "isWindowLayoutLocked")
            NSLog("WindowManager: isWindowLayoutLocked changed to %d", isWindowLayoutLocked ? 1 : 0)
        }
    }
    
    /// Main player window controller (classic or modern, accessed via protocol)
    private(set) var mainWindowController: MainWindowProviding?
    
    var uiMode: PlayerUIMode {
        get { PlayerUIMode.stored() }
        set { newValue.persist() }
    }

    /// Whether the modern-family UI is enabled. Kept as a compatibility mirror for
    /// call sites that only need to choose classic vs. modern-family controllers.
    var isModernUIEnabled: Bool {
        get { uiMode.usesModernControllers }
        set { uiMode = newValue ? .modern : .classic }
    }

    /// Runtime UI mode inferred from the active main window controller.
    /// Falls back to the persisted preference before controllers exist.
    var isRunningModernUI: Bool {
        if let controller = mainWindowController {
            if controller is ModernMainWindowController { return true }
            if controller is MainWindowController { return false }
        }
        return isModernUIEnabled
    }

    var isRunningModernFamilyUI: Bool {
        isRunningModernUI
    }

    var isRunningMetalUI: Bool {
        isRunningModernFamilyUI && uiMode == .metal
    }
    
    /// Whether title bars are hidden on all windows (only applies in modern UI mode)
    var hideTitleBars: Bool {
        get { isRunningModernUI && UserDefaults.standard.bool(forKey: "hideTitleBars") }
        set { UserDefaults.standard.set(newValue, forKey: "hideTitleBars") }
    }

    /// Whether Compact Mode (menu-bar mini-player) is currently active. Works in both
    /// classic and modern UI; toggled live at runtime. The persisted preference key
    /// `compactModeEnabled` mirrors this so the mode can be restored on the next launch.
    private(set) var compactModeEnabled = false

    /// Whether Compact Window (free-floating mini-player) is currently active. Unlike
    /// Compact Mode, this keeps the app regular and hides only the main window.
    private(set) var compactWindowEnabled = false

    private var compactModeState: CompactModeState = .regular

    private var regularWindowSnapshot: CompactWindowSnapshot?
    private var mainWasVisibleBeforeCompactWindow = false

    /// Status-bar item shown while Compact Mode is active.
    private var compactStatusItem: NSStatusItem?

    private var compactWindowController: CompactModeWindowController?

    /// Marks mode-dependent player windows so stale instances can be distinguished from
    /// legitimate standalone dialogs when sweeping NSApp.windows.
    private static let modeDependentWindowIdentifier =
        NSUserInterfaceItemIdentifier("nullPlayer.modeDependentWindow")

    /// Ensure modern main window keeps full-height geometry in HT mode at startup/restore.
    /// Keeps the top edge fixed so legacy compact HT frames are expanded.
    @discardableResult
    func normalizeModernMainWindowForHTIfNeeded(_ explicitWindow: NSWindow? = nil) -> CGFloat {
        guard isRunningModernUI, hideTitleBars else { return 0 }
        guard let mainWindow = explicitWindow ?? mainWindowController?.window else { return 0 }

        let targetHeight = fullMainHeightForCurrentScale()
        mainWindow.minSize = NSSize(width: mainWindow.minSize.width, height: targetHeight)

        var frame = mainWindow.frame
        let oldOriginY = frame.origin.y
        guard abs(frame.height - targetHeight) > 0.5 else { return 0 }

        let topY = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = topY - targetHeight
        mainWindow.setFrame(frame, display: true)

        return frame.origin.y - oldOriginY
    }
    
    /// Toggle hide title bars mode (modern UI only). Sub-windows only hide their title bar when docked.
    func toggleHideTitleBars() {
        guard isRunningModernUI else { return }
        hideTitleBars = !hideTitleBars

        // Keep main window size unchanged across HT toggles (internal reflow is view-level).
        if let mainWindow = mainWindowController?.window {
            let newSize = NSSize(width: mainWindow.frame.width, height: fullMainHeightForCurrentScale())
            mainWindow.minSize = newSize
            var frame = mainWindow.frame
            let topY = frame.maxY
            let oldOriginY = frame.origin.y
            frame.size = newSize
            frame.origin.y = topY - newSize.height
            let dy = frame.origin.y - oldOriginY

            // Find sub-windows stacked below the main window (below-only BFS, same pattern as
            // slideUpWindowsBelow). Library browser and ProjectM are side-docked and must NOT
            // be moved — only the main window's bottom changes, its top is anchored.
            let subWindows = [equalizerWindowController?.window,
                              playlistWindowController?.window,
                              spectrumWindowController?.window,
                              audioAnalysisWindowController?.window,
                              peppyMeterWindowController?.window,
                              networkMonitorWindowController?.window,
                              waveformWindowController?.window].compactMap { $0 }
            var windowsBelow: [NSWindow] = []
            var frontier: [NSRect] = [mainWindow.frame]
            while !frontier.isEmpty {
                let ref = frontier.removeFirst()
                for win in subWindows {
                    guard win.isVisible, !windowsBelow.contains(win) else { continue }
                    let vGap = abs(win.frame.maxY - ref.minY)
                    let hOverlap = win.frame.minX < ref.maxX && win.frame.maxX > ref.minX
                    if vGap <= dockThreshold && hOverlap {
                        windowsBelow.append(win)
                        frontier.append(win.frame)
                    }
                }
            }

            // Suppress windowDidMove → windowWillMove side-effects during programmatic resize.
            // Without this, windowWillMove either uses stale offsets (leaving draggingWindow set
            // from a prior HT toggle) or computes fresh offsets relative to the post-resize origin
            // (which leaves every docked window at its pre-move position, creating a gap).
            isSnappingWindow = true
            mainWindow.setFrame(frame, display: true, animate: false)
            // Move below-stacked windows by the same Y delta so they stay flush against the main.
            for win in windowsBelow {
                win.setFrameOrigin(NSPoint(x: win.frame.origin.x, y: win.frame.origin.y + dy))
            }
            // Keep connected center-stack window sizes unchanged across HT toggles.
            // These windows already hide titlebars while docked, so changing HT should
            // not change their frame heights; only their stacked position should move.
            let orderedBelow = windowsBelow.sorted { $0.frame.maxY > $1.frame.maxY }
            var nextTop = frame.minY
            for win in orderedBelow {
                guard let kind = centerStackWindowKind(for: win) else { continue }
                var winFrame = win.frame
                if kind == .equalizer { winFrame.size.width = frame.width }
                let targetHeight = winFrame.height
                winFrame.origin.x = frame.minX
                winFrame.origin.y = nextTop - targetHeight
                win.setFrame(winFrame, display: true, animate: false)
                nextTop = winFrame.minY
            }
            // Resize side windows (library browser, projectM) so their bottom follows the main
            // window's bottom. Their top (maxY) is anchored to the main window's top and must
            // not change — only height and origin.y are adjusted.
            for win in [plexBrowserWindowController?.window, projectMWindowController?.window].compactMap({ $0 }) {
                guard win.isVisible else { continue }
                let newOriginY = win.frame.origin.y + dy
                let newHeight = win.frame.height - dy
                win.setFrame(NSRect(x: win.frame.origin.x, y: newOriginY,
                                    width: win.frame.width, height: newHeight),
                             display: true, animate: false)
            }
            isSnappingWindow = false
        }

        // Refresh all managed window views
        for controller in [mainWindowController as? NSWindowController,
                           equalizerWindowController as? NSWindowController,
                           playlistWindowController as? NSWindowController,
                          spectrumWindowController as? NSWindowController,
                          audioAnalysisWindowController as? NSWindowController,
                          peppyMeterWindowController as? NSWindowController,
                          networkMonitorWindowController as? NSWindowController,
                          waveformWindowController as? NSWindowController,
                           projectMWindowController as? NSWindowController,
                           plexBrowserWindowController as? NSWindowController] {
            if let view = controller?.window?.contentView {
                view.needsDisplay = true
                view.needsLayout = true
            }
        }
    }
    
    /// Returns true if any other window is currently docked to the given window.
    func isWindowDocked(_ window: NSWindow) -> Bool {
        !findDockedWindows(to: window).isEmpty
    }
    
    /// Returns true if the title bar should be hidden for the given window.
    /// - Base behavior: EQ, Playlist, Spectrum, and Waveform always hide when docked.
    /// - HT on: ALL windows hide titlebars regardless of docking.
    func effectiveHideTitleBars(for window: NSWindow?) -> Bool {
        guard let window else { return false }
        guard isRunningModernUI else { return false }

        // Sub-windows always hide when docked (base behavior)
        let isSubWindow = window === equalizerWindowController?.window ||
                          window === playlistWindowController?.window ||
                          window === spectrumWindowController?.window ||
                          window === waveformWindowController?.window ||
                          window === audioAnalysisWindowController?.window ||
                          window === peppyMeterWindowController?.window ||
                          window === networkMonitorWindowController?.window
        if isSubWindow && isWindowDocked(window) {
            return true
        }

        // When HT is on, ALL app windows hide titlebars
        guard hideTitleBars else { return false }
        let isAppWindow = window === mainWindowController?.window ||
                          isSubWindow ||
                          window === projectMWindowController?.window ||
                          window === plexBrowserWindowController?.window
        return isAppWindow
    }
    
    /// Playlist window controller (classic or modern, accessed via protocol)
    private(set) var playlistWindowController: PlaylistWindowProviding?
    
    /// Equalizer window controller (classic or modern, accessed via protocol)
    private(set) var equalizerWindowController: EQWindowProviding?
    
    /// Library browser window controller (classic or modern, accessed via protocol)
    private var plexBrowserWindowController: LibraryBrowserWindowProviding?

    /// Last known Library window frame, remembered across hide/close so the
    /// window reopens where the user left it instead of the default right-of-stack layout.
    private var lastPlexBrowserFrame: NSRect?
    private var lastPlexBrowserFrameWasDocked = false

    /// Video player window controller
    private var videoPlayerWindowController: VideoPlayerWindowController?
    
    /// ProjectM visualization window controller (classic or modern, accessed via protocol)
    private var projectMWindowController: ProjectMWindowProviding?

    /// Last known Visualizations window frame, remembered across hide/close so a docked
    /// window can refit to the current center stack while a floating one reopens exactly.
    private var lastProjectMFrame: NSRect?
    private var lastProjectMFrameWasDocked = false
    
    /// Spectrum analyzer window controller (classic or modern, accessed via protocol)
    private var spectrumWindowController: SpectrumWindowProviding?

    /// Audio analysis window controller for the active UI mode, accessed via protocol.
    private var audioAnalysisWindowController: AudioAnalysisWindowProviding?

    /// PeppyMeter (analog VU meter) window controller for the active UI mode, accessed via protocol.
    private var peppyMeterWindowController: PeppyMeterWindowProviding?

    /// Network monitor window controller for the active UI mode, accessed via protocol.
    private var networkMonitorWindowController: NetworkMonitorWindowProviding?

    /// Shared vis_classic bridge — created on first use, driven by audioWaveform576DataUpdated notifications.
    private(set) var sharedVisClassicBridge: VisClassicBridge?
    private(set) var mainWindowVisClassicBridge: VisClassicBridge?

    /// Waveform window controller (classic or modern, accessed via protocol)
    private var waveformWindowController: WaveformWindowProviding?
    
    /// Debug console window controller
    private var debugWindowController: DebugWindowController?
    
    /// Video playback time tracking
    private(set) var videoCurrentTime: TimeInterval = 0
    private var _videoDuration: TimeInterval = 0
    private(set) var videoTitle: String?
    
    /// Video duration - returns cast duration when video casting is active
    var videoDuration: TimeInterval {
        get {
            if case .video = CastManager.shared.currentCast {
                return CastManager.shared.videoCastDuration
            }
            return _videoDuration
        }
        set {
            _videoDuration = newValue
        }
    }
    
    /// Snap threshold in pixels - how close windows need to be to snap
    private let snapThreshold: CGFloat = 15
    
    /// Docking threshold - windows closer than this are considered docked
    /// Should be small so only truly touching windows are grouped
    private let dockThreshold: CGFloat = 3
    
    /// Hold threshold - how long (seconds) before a drag moves the connected group
    private let holdThreshold: TimeInterval = 0.4

    /// Time when current drag's mouseDown was received
    private var holdStartTime: CFTimeInterval?

    /// Window that primed hold timing on mouseDown before drag motion started.
    private weak var primedDragWindow: NSWindow?

    /// Current drag mode, determined on first windowWillMove call
    private var dragMode: DragMode = .pending

    /// Whether a connectedWindowHighlightDidChange notification was posted for this drag
    private var highlightWasPosted = false
    
    /// Track which window is currently being dragged
    private var draggingWindow: NSWindow?

    /// Local monitor used to guarantee drag teardown even when a view misses mouseUp.
    private var dragMouseUpMonitor: Any?

    /// Track the last drag delta for grouped movement
    private var lastDragDelta: NSPoint = .zero
    
    /// Windows that should move together with the dragging window
    private var dockedWindowsToMove: [NSWindow] = []
    
    /// Store relative offsets of docked windows from the dragging window's origin
    /// This prevents drift during fast movement by maintaining exact relative positions
    private var dockedWindowOffsets: [ObjectIdentifier: NSPoint] = [:]

    /// Store absolute origins of docked windows at drag start, for position restoration on separation
    private var dockedWindowOriginalOrigins: [ObjectIdentifier: NSPoint] = [:]
    
    /// Flag to prevent feedback loop when moving docked windows programmatically
    private var isMovingDockedWindows = false
    
    /// Flag to prevent feedback loop when snapping windows
    private var isSnappingWindow = false
    private var programmaticFrameChangeToken = 0

    /// Guard against re-entrant classic stack tightening while applying repaired frames.
    private var isTighteningClassicCenterStack = false

    /// Time gate for drag layout notifications (throttle to ~30Hz)
    private var lastDragLayoutNotificationTime: TimeInterval = 0

    /// Per-notification-cycle caches for adjacency/sharp-corners computation
    private var adjacencyCache: [ObjectIdentifier: AdjacentEdges] = [:]
    private var edgeOcclusionSegmentsCache: [ObjectIdentifier: EdgeOcclusionSegments] = [:]
    private var sharpCornersCache: [ObjectIdentifier: CACornerMask] = [:]

    /// Windows that were attached as children for coordinated minimize (for restore)
    private var coordinatedMiniaturizedWindows: [NSWindow] = []

    /// Windows currently in miniaturize animation; suppress drag/group movement for these.
    private var miniaturizingWindowIds = Set<ObjectIdentifier>()
    
    // MARK: - Initialization
    
    private init() {
        // Register and load preferences
        registerPreferenceDefaults()
        loadPreferences()

        // Load default skin
        loadDefaultSkin()

        // Clean up drag state if a window closes mid-drag
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillMiniaturize(_:)),
            name: NSWindow.willMiniaturizeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidMiniaturize(_:)),
            name: NSWindow.didMiniaturizeNotification,
            object: nil
        )
    }
    
    /// Register default preference values
    private func registerPreferenceDefaults() {
        UserDefaults.standard.register(defaults: [
            "timeDisplayMode": TimeDisplayMode.elapsed.rawValue,
            "timeDisplayNumberSystem": TimeDisplayNumberSystem.modernDefault.rawValue,
            "isAlwaysOnTop": false,
            "isWindowLayoutLocked": false,
            "hideTitleBars": true,
            "waveformShowCuePoints": false,
            "waveformHideTooltip": false,
            "compactModeEnabled": false,
            "compactWindowEnabled": false
        ])
    }
    
    /// Load preferences from UserDefaults
    private func loadPreferences() {
        if let mode = UserDefaults.standard.string(forKey: "timeDisplayMode"),
           let displayMode = TimeDisplayMode(rawValue: mode) {
            timeDisplayMode = displayMode
        }
        if let rawValue = UserDefaults.standard.string(forKey: "timeDisplayNumberSystem"),
           let numberSystem = TimeDisplayNumberSystem(rawValue: rawValue) {
            storedTimeDisplayNumberSystem = numberSystem
        }
        // Note: uiScaleLevel always starts normal - windows are created at 1x size
        // and AppStateManager applies the saved UI Size after they're created if needed.
        let savedAlwaysOnTop = UserDefaults.standard.bool(forKey: "isAlwaysOnTop")
        isAlwaysOnTop = savedAlwaysOnTop
        NSLog("WindowManager: Loaded isAlwaysOnTop = %d from UserDefaults", savedAlwaysOnTop ? 1 : 0)
        let savedWindowLayoutLocked = UserDefaults.standard.bool(forKey: "isWindowLayoutLocked")
        isWindowLayoutLocked = savedWindowLayoutLocked
        NSLog("WindowManager: Loaded isWindowLayoutLocked = %d from UserDefaults", savedWindowLayoutLocked ? 1 : 0)
    }

    func toggleWindowLayoutLock() {
        isWindowLayoutLocked.toggle()
    }
    
    // MARK: - Window Management
    
    /// - Parameter reveal: When `false`, the controller (and its window) are created and
    ///   configured but the window is never ordered onscreen. Used at launch when starting
    ///   straight into Compact Mode, so the regular window doesn't flash before it is hidden.
    func showMainWindow(reveal: Bool = true) {
        let isNew = mainWindowController == nil
        if isNew {
            if isModernUIEnabled {
                let modern = ModernMainWindowController()
                mainWindowController = modern
            } else {
                mainWindowController = MainWindowController()
            }
        }
        markModeDependentWindow(mainWindowController?.window)
        // Enforce HT compact height on both first show and subsequent re-shows.
        if isRunningModernUI {
            normalizeModernMainWindowForHTIfNeeded()
        }
        if reveal && !compactWindowEnabled {
            mainWindowController?.showWindow(nil)
        }
        applyAlwaysOnTopToWindow(mainWindowController?.window)
    }
    
    func toggleMainWindow() {
        if compactWindowEnabled {
            exitCompactWindow()
            return
        }
        if let controller = mainWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showMainWindow()
        }
    }
    
    func showPlaylist(at restoredFrame: NSRect? = nil) {
        let isNewWindow = playlistWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                playlistWindowController = ModernPlaylistWindowController()
            } else {
                playlistWindowController = PlaylistWindowController()
            }
        }
        markModeDependentWindow(playlistWindowController?.window)

        // Position BEFORE showing (unless restoring from saved state)
        if let playlistWindow = playlistWindowController?.window {
            applyCenterStackSizingConstraints(playlistWindow, kind: .playlist)
            if let frame = restoredFrame, frame != .zero {
                applyRestoredCenterStackFrame(frame, to: playlistWindow, kind: .playlist)
            } else {
                // By design: always reset to default when showing without a saved frame.
                // This keeps the window snapped below main whenever the user opens it fresh,
                // even if it was previously resized. Stretch state is intentionally not persisted
                // across hide/show toggles.
                if isModernUIEnabled {
                    applyDefaultCenterStackFrameForCurrentHT(playlistWindow, kind: .playlist)
                } else {
                    (playlistWindowController as? PlaylistWindowController)?.resetToDefaultFrame()
                }
                positionSubWindow(playlistWindow)
            }
            NSLog("showPlaylist: window frame = \(playlistWindow.frame)")
        }
        
        playlistWindowController?.showWindow(nil)
        playlistWindowController?.window?.makeKeyAndOrderFront(nil)
        applyAlwaysOnTopToWindow(playlistWindowController?.window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
    }

    var isPlaylistVisible: Bool {
        playlistWindowController?.window?.isVisible == true
    }
    
    func togglePlaylist() {
        if let controller = playlistWindowController,
           let window = controller.window,
           window.isVisible {
            let closingFrame = window.frame
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: closingFrame)
        } else {
            showPlaylist()
        }
        notifyMainWindowVisibilityChanged()
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }
    
    func showEqualizer(at restoredFrame: NSRect? = nil) {
        let isNewWindow = equalizerWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                equalizerWindowController = ModernEQWindowController()
            } else {
                equalizerWindowController = EQWindowController()
            }
        }
        markModeDependentWindow(equalizerWindowController?.window)
        
        // Position BEFORE showing (unless restoring from saved state)
        if let eqWindow = equalizerWindowController?.window {
            applyCenterStackSizingConstraints(eqWindow, kind: .equalizer)
            if let frame = restoredFrame, frame != .zero {
                applyRestoredCenterStackFrame(frame, to: eqWindow, kind: .equalizer)
            } else {
                if isNewWindow {
                    applyDefaultCenterStackFrameForCurrentHT(eqWindow, kind: .equalizer)
                }
                positionSubWindow(eqWindow)
            }
        }
        
        equalizerWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(equalizerWindowController?.window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
    }

    var isEqualizerVisible: Bool {
        equalizerWindowController?.window?.isVisible == true
    }
    
    func toggleEqualizer() {
        if let controller = equalizerWindowController,
           let window = controller.window,
           window.isVisible {
            let closingFrame = window.frame
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: closingFrame)
        } else {
            showEqualizer()
        }
        notifyMainWindowVisibilityChanged()
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }
    
    /// Position a sub-window (EQ, Playlist, Spectrum, or Waveform) in the vertical stack.
    /// Fills the first gap between visible stack windows if one exists,
    /// otherwise positions below the lowest visible window in the stack.
    private func positionSubWindow(_ window: NSWindow, preferBelowEQ: Bool = false) {
        guard let mainWindow = mainWindowController?.window else { return }
        
        if let kind = centerStackWindowKind(for: window) {
            applyCenterStackSizingConstraints(window, kind: kind)
        }

        let mainFrame = mainWindow.frame
        let newHeight = window.frame.size.height
        let newWidth = window.frame.size.width
        
        // Detached windows moved aside should not affect where new stack windows open.
        var visibleWindows: [NSWindow] = [mainWindow]
        for win in dockedCenterStackWindowsBelowMain(mainFrame: mainFrame) where win !== window {
            visibleWindows.append(win)
        }
        
        // Sort top-to-bottom (highest minY first, since macOS Y increases upward)
        visibleWindows.sort { $0.frame.minY > $1.frame.minY }
        
        // Scan for gaps between adjacent windows (first gap from top wins)
        var targetY: CGFloat? = nil
        for i in 0..<(visibleWindows.count - 1) {
            let upper = visibleWindows[i]
            let lower = visibleWindows[i + 1]
            let gap = upper.frame.minY - lower.frame.maxY
            if gap >= newHeight {
                targetY = upper.frame.minY - newHeight
                NSLog("positionSubWindow: Found gap (%.0f px) between windows at minY=%.0f and maxY=%.0f, placing at y=%.0f",
                      gap, upper.frame.minY, lower.frame.maxY, targetY!)
                break
            }
        }
        
        // No gap found: position below the lowest visible window
        if targetY == nil {
            let lowest = visibleWindows.last!
            targetY = lowest.frame.minY - newHeight
            NSLog("positionSubWindow: No gap found, positioning below lowest window (minY=%.0f), placing at y=%.0f",
                  lowest.frame.minY, targetY!)
        }
        
        let newFrame = NSRect(
            x: mainFrame.minX,  // Always align with main window
            y: targetY!,
            width: newWidth,
            height: newHeight
        )
        
        // Disable snapping during programmatic frame changes to prevent docking logic
        // from moving the entire window stack
        isSnappingWindow = true
        window.setFrame(newFrame, display: true)
        isSnappingWindow = false
        postLayoutChangeNotification()
    }
    
    /// After a center-stack window is hidden, slide up any visible sub-windows that
    /// were docked below it (directly or transitively). Only windows within
    /// `dockThreshold` of the closing window's bottom edge are moved.
    private func slideUpWindowsBelow(closingFrame: NSRect) {
        let subWindows = [equalizerWindowController?.window,
                          playlistWindowController?.window,
                          spectrumWindowController?.window,
                          audioAnalysisWindowController?.window,
                          peppyMeterWindowController?.window,
                          networkMonitorWindowController?.window,
                          waveformWindowController?.window].compactMap { $0 }

        // BFS: find windows directly docked below closingFrame, then those below them
        var toMove: [NSWindow] = []
        var frontier: [NSRect] = [closingFrame]

        while !frontier.isEmpty {
            let referenceFrame = frontier.removeFirst()
            for win in subWindows {
                guard win.isVisible, !toMove.contains(win) else { continue }
                // win's top (maxY) should be near referenceFrame's bottom (minY)
                let vertGap = abs(win.frame.maxY - referenceFrame.minY)
                let horizOverlap = win.frame.minX < referenceFrame.maxX && win.frame.maxX > referenceFrame.minX
                if vertGap <= dockThreshold && horizOverlap {
                    toMove.append(win)
                    frontier.append(win.frame)
                }
            }
        }

        guard !toMove.isEmpty else { return }

        isSnappingWindow = true
        defer { isSnappingWindow = false }

        for win in toMove {
            var frame = win.frame
            frame.origin.y += closingFrame.height
            win.setFrame(frame, display: true, animate: false)
        }

        postLayoutChangeNotification()
    }

    /// Call from windowWillClose on classic center-stack windows (EQ, Playlist, Spectrum, Waveform)
    /// when closed via the X button. Slides up windows below and tightens the stack.
    func handleCenterStackWindowWillClose(_ window: NSWindow) {
        guard !isRunningModernUI else { return }
        let closingFrame = window.frame
        slideUpWindowsBelow(closingFrame: closingFrame)
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    /// Show local media library (redirects to unified browser in local mode)
    func showMediaLibrary() {
        // Redirect to unified browser - it handles both Plex and local files
        showPlexBrowser()
    }
    
    var isMediaLibraryVisible: Bool {
        // Redirects to unified browser visibility
        isPlexBrowserVisible
    }
    
    func toggleMediaLibrary() {
        // Redirect to unified browser toggle
        togglePlexBrowser()
    }
    
    // MARK: - Plex Browser Window
    
    func showPlexBrowser(at restoredFrame: NSRect? = nil) {
        let isNewWindow = plexBrowserWindowController == nil
        if isNewWindow {
            createPlexBrowserWindowController()
        }
        markModeDependentWindow(plexBrowserWindowController?.window)
        plexBrowserWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(plexBrowserWindowController?.window)
        // Position window to match the vertical stack
        if let window = plexBrowserWindowController?.window {
            // Priority: explicit restored frame (launch / mode-rebuild) → remembered session
            // frame (reopen after hide/close) → default right-of-stack layout (first-ever open).
            if let frame = restoredFrame, frame != .zero {
                window.setFrame(frame, display: true)
            } else if let frame = lastPlexBrowserFrame, frame != .zero {
                if lastPlexBrowserFrameWasDocked,
                   let dockedFrame = rightDockedSideFrame(for: window, width: frame.width) {
                    window.setFrame(dockedFrame, display: true)
                } else {
                    window.setFrame(frame, display: true)
                }
            } else {
                // Scale width for double-size mode
                let sideWidth = window.frame.width * (isModernUIEnabled ? ModernSkinElements.sizeMultiplier : 1.0)
                if let newFrame = rightDockedSideFrame(for: window, width: sideWidth) {
                    window.setFrame(newFrame, display: true)
                }
            }
        }
        postLayoutChangeNotification()
    }

    private func createPlexBrowserWindowController() {
        if isModernUIEnabled {
            plexBrowserWindowController = ModernLibraryBrowserWindowController()
        } else {
            plexBrowserWindowController = PlexBrowserWindowController()
        }
        markModeDependentWindow(plexBrowserWindowController?.window)
    }

    var isPlexBrowserVisible: Bool {
        plexBrowserWindowController?.window?.isVisible == true
    }
    
    /// Get the Plex Browser window frame if visible (for positioning other windows)
    var plexBrowserWindowFrame: NSRect? {
        guard let window = plexBrowserWindowController?.window, window.isVisible else { return nil }
        return window.frame
    }
    
    /// Get/set the library browser browse mode raw value (for state save/restore)
    var plexBrowserBrowseMode: Int? {
        get { plexBrowserWindowController?.browseModeRawValue }
        set {
            if let value = newValue {
                plexBrowserWindowController?.browseModeRawValue = value
            }
        }
    }

    var isLibraryHistoryVisible: Bool {
        guard isRunningModernUI, isPlexBrowserVisible else { return false }
        return plexBrowserBrowseMode == ModernBrowseMode.history.rawValue
    }
    
    /// Get the ProjectM window frame (for state saving)
    var projectMWindowFrame: NSRect? {
        return projectMWindowController?.window?.frame
    }

    /// Cache the current Visualizations frame before it is hidden/closed.
    private func rememberProjectMFrame() {
        if let window = projectMWindowController?.window,
           window.isVisible,
           window.frame != .zero {
            lastProjectMFrame = window.frame
            lastProjectMFrameWasDocked = sideFrameIsLeftDockedToCurrentStack(window.frame)
        }
    }

    /// Public entry point so the Visualizations controllers can cache their frame from
    /// `windowWillClose` (the red-button close path bypasses `toggleProjectM`).
    func rememberProjectMFrameBeforeClose() {
        rememberProjectMFrame()
    }

    /// Cache the current library frame before it is hidden/closed.
    private func rememberPlexBrowserFrame() {
        if let window = plexBrowserWindowController?.window,
           let f = plexBrowserWindowController?.frameForPositionMemory,
           f != .zero {
            lastPlexBrowserFrame = f
            lastPlexBrowserFrameWasDocked = window.isVisible && sideFrameIsRightDockedToCurrentStack(f)
        }
    }

    /// Public entry point so the library controllers can cache their frame from
    /// `windowWillClose` (the red-button close path bypasses `togglePlexBrowser`).
    func rememberPlexBrowserFrameBeforeClose() {
        rememberPlexBrowserFrame()
    }

    /// Frame to persist at quit: live controller frame (valid even when orderOut-hidden, e.g.
    /// Compact Mode) when the controller exists, else the last remembered frame (seeded/closed).
    var plexBrowserFrameForPersistence: NSRect? {
        plexBrowserWindowController?.frameForPositionMemory ?? lastPlexBrowserFrame
    }

    /// Seed the remembered frame at launch when the library is not reopened.
    func seedPlexBrowserFrame(_ frame: NSRect?) {
        if let f = frame, f != .zero {
            lastPlexBrowserFrame = f
            lastPlexBrowserFrameWasDocked = sideFrameIsRightDockedToCurrentStack(f)
        }
    }

    func togglePlexBrowser() {
        if let controller = plexBrowserWindowController, controller.window?.isVisible == true {
            rememberPlexBrowserFrame()
            controller.window?.orderOut(nil)
        } else {
            showPlexBrowser()
        }
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    // MARK: - Compact Mode

    /// Toggle the menu-bar Compact Mode (works in both classic and modern UI). Live — no restart.
    func toggleCompactMode() {
        if compactModeEnabled {
            exitCompactMode()
        } else {
            enterCompactMode()
        }
    }

    /// Toggle the free-floating Compact Window. This reuses the compact mini-player surface
    /// without changing activation policy or hiding any secondary windows.
    func toggleCompactWindow() {
        if compactWindowEnabled {
            exitCompactWindow()
        } else {
            enterCompactWindow()
        }
    }

    /// Enter the free-floating Compact Window variant.
    ///
    /// - Parameter treatMainAsVisible: Used at launch restore when the main window was created
    ///   hidden only to avoid flash. Exiting Compact Window should still bring it back.
    func enterCompactWindow(treatMainAsVisible: Bool = false) {
        if compactModeState != .regular {
            exitCompactMode { [weak self] in
                self?.enterCompactWindow(treatMainAsVisible: treatMainAsVisible)
            }
            return
        }
        guard !compactWindowEnabled else { return }

        compactWindowEnabled = true
        UserDefaults.standard.set(true, forKey: "compactWindowEnabled")
        UserDefaults.standard.set(false, forKey: "compactModeEnabled")

        mainWasVisibleBeforeCompactWindow = treatMainAsVisible
            || (mainWindowController?.window?.isVisible ?? false)
        mainWindowController?.window?.orderOut(nil)

        createCompactWindowControllerIfNeeded()
        compactWindowController?.showFloating(level: isAlwaysOnTop ? .floating : .normal)
        postLayoutChangeNotification()
    }

    func exitCompactWindow(restoreMainWindow: Bool = true) {
        guard compactWindowEnabled else { return }
        compactWindowEnabled = false
        UserDefaults.standard.set(false, forKey: "compactWindowEnabled")

        compactWindowController?.hide()
        compactWindowController = nil

        if restoreMainWindow, mainWasVisibleBeforeCompactWindow,
           let mainWindow = mainWindowController?.window {
            mainWindow.makeKeyAndOrderFront(nil)
            applyAlwaysOnTopToWindow(mainWindow)
        }
        mainWasVisibleBeforeCompactWindow = false
        postLayoutChangeNotification()
    }

    func handleAppReopen() {
        if compactWindowEnabled {
            mainWindowController?.window?.orderOut(nil)
            createCompactWindowControllerIfNeeded()
            compactWindowController?.showFloating(level: isAlwaysOnTop ? .floating : .normal)
            postLayoutChangeNotification()
            return
        }

        showMainWindow()
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    /// - Parameter revealWindow: When `true` (live toggle from the menu) the compact window is
    ///   shown and positioned under the status item. When `false` (restore on launch) the window
    ///   is left hidden behind the status item so the *first* click reveals it — otherwise the
    ///   status item starts in a "visible" state and the first click would just hide it.
    /// - Parameter treatMainAsVisible: When `true` (launch-into-compact path), the captured
    ///   snapshot records the main window as visible even though it was never revealed, so
    ///   exiting Compact Mode later restores it onscreen. The main window is always part of the
    ///   regular layout, so this matches the live-toggle behavior. Defaults to `false` so the
    ///   live menu toggle keeps recording the main window's actual visibility.
    func enterCompactMode(revealWindow: Bool = true, treatMainAsVisible: Bool = false) {
        let compactWindowMainWasVisible = compactWindowEnabled && mainWasVisibleBeforeCompactWindow
        if compactWindowEnabled {
            exitCompactWindow(restoreMainWindow: false)
        }
        guard compactModeState == .regular else { return }
        compactModeState = .entering
        compactModeEnabled = true
        UserDefaults.standard.set(true, forKey: "compactModeEnabled")

        regularWindowSnapshot = captureRegularWindowSnapshot()
        if treatMainAsVisible || compactWindowMainWasVisible {
            regularWindowSnapshot?.main?.wasVisible = true
        }

        // Put an (invisible) compact window on the current Space *before* hiding the regular
        // windows and dropping to .accessory, so NullPlayer always has a window here for the
        // re-activation below to focus. See CompactModeWindowController.establishPresenceOnActiveSpace().
        createCompactWindowControllerIfNeeded()
        compactWindowController?.establishPresenceOnActiveSpace()

        detachManagedChildWindowsForCompactMode()
        orderOutRegularWindows()

        NSApp.setActivationPolicy(.accessory)
        // Going .accessory makes macOS resign NullPlayer and activate the next app in the stack.
        // If that app is fullscreen on another Space (e.g. Console), the user gets switched to that
        // Space (and the .moveToActiveSpace compact window follows). Immediately re-activate so
        // NullPlayer stays frontmost on the *current* Space — the compact window is already ordered
        // front here. Mirrors the NSApp.activate the exit path uses to reclaim focus.
        NSApp.activate(ignoringOtherApps: true)
        createCompactStatusItem()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.compactModeState == .entering else { return }
            if revealWindow {
                // showCompactWindow() self-defers its reveal until the status-item anchor is
                // ready, so a single call is enough — no second show needed.
                self.showCompactWindow()
                self.compactModeState = .compactVisible
            } else {
                self.hideCompactWindow()
                self.compactModeState = .compactHidden
            }
        }
        postLayoutChangeNotification()
    }

    /// Exit Compact Mode and restore the regular window layout.
    ///
    /// The restore is deferred to the next runloop tick (after the compact window/status item
    /// are torn down) so AppKit settles before the regular windows are re-shown — this is what
    /// keeps the transition artifact-free. Callers that must run work only *after* the layout is
    /// fully restored and `compactModeState` is back to `.regular` (e.g. live UI-mode switching,
    /// which re-enters Compact Mode afterward) MUST pass `completion`; it runs at the very end of
    /// that deferred restore. It also fires if the guard rejects the call, so a completion is
    /// never silently dropped.
    ///
    /// Pass `restoreRegularWindows: false` when the caller is about to tear down and rebuild the
    /// regular windows anyway (the live UI switch). The pre-compact windows are `.managed` and
    /// assigned to whatever Space they were created on; re-showing them here would activate the
    /// app on *that* Space and yank the user away from the Space they're currently viewing. Skip
    /// the restore and the dock/activation-policy churn so the rebuilt-fresh windows (and the
    /// re-entered compact window) land on the current Space instead.
    func exitCompactMode(restoreRegularWindows: Bool = true, completion: (() -> Void)? = nil) {
        guard compactModeState == .compactVisible ||
              compactModeState == .compactHidden ||
              compactModeState == .entering else {
            completion?()
            return
        }
        compactModeState = .exiting
        compactModeEnabled = false
        UserDefaults.standard.set(false, forKey: "compactModeEnabled")

        hideCompactWindow()
        compactWindowController = nil
        removeCompactStatusItem()

        if restoreRegularWindows {
            NSApp.setActivationPolicy(.regular)
            restoreDockIconImage()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            (NSApp.delegate as? AppDelegate)?.rebuildMainMenu()
            if restoreRegularWindows {
                self.restoreRegularWindowSnapshot()
                self.updateDockedChildWindows()
                self.reassertRegularActivation()

                // The `.accessory → .regular` transition settles over a runloop turn or two on
                // modern macOS: right after the activation above the menu bar can still show the
                // stale (empty) menu — the menu options stay missing until the user manually
                // minimizes and restores a window — and the Dock tile can show the generic
                // executable icon. Re-assert activation, the rebuilt menu, and the icon once the
                // transition has fully landed so none of them depends on winning that race.
                DispatchQueue.main.async {
                    guard self.compactModeState == .regular else { return }
                    (NSApp.delegate as? AppDelegate)?.rebuildMainMenu()
                    self.reassertRegularActivation()
                }
            }
            self.compactModeState = .regular
            self.postLayoutChangeNotification()
            completion?()
        }
    }

    /// Reclaim foreground activation after leaving Compact Mode's `.accessory` policy: activate the
    /// app, make the restored main window key, and re-apply the Dock icon. Establishing a key window
    /// is what gives the app menu-bar ownership and first responder — without it the rebuilt menu can
    /// stay missing until the user manually minimizes/restores a window. Re-applying the icon here
    /// (after macOS has built the `.regular` Dock tile) keeps the NullPlayer logo from being replaced
    /// by the generic executable icon.
    private func reassertRegularActivation() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindowController?.window, window.isVisible, !isInNativeFullScreen(window) {
            window.makeKey()
        }
        restoreDockIconImage()
    }

    private func captureRegularWindowSnapshot() -> CompactWindowSnapshot {
        func snap(_ controller: ModeDependentWindow?, normalFrame: NSRect? = nil,
                  sideWindow: Bool = false) -> WindowSnapshot? {
            guard let window = controller?.window else { return nil }
            return WindowSnapshot(
                wasVisible: window.isVisible,
                frame: window.frame,
                normalFrame: normalFrame,
                // Record detached-ness while the window is live (it's determinable here; after
                // Compact Mode hides it, docking can no longer be measured).
                wasDetached: sideWindow && window.isVisible && !isWindowDocked(window)
            )
        }

        func snapWindow(_ window: NSWindow?) -> WindowSnapshot? {
            guard let window else { return nil }
            return WindowSnapshot(wasVisible: window.isVisible, frame: window.frame)
        }

        return CompactWindowSnapshot(
            main: snap(mainWindowController),
            equalizer: snap(equalizerWindowController),
            playlist: snap(playlistWindowController),
            spectrum: snap(spectrumWindowController),
            audioAnalysis: snap(audioAnalysisWindowController),
            peppyMeter: snap(peppyMeterWindowController),
            networkMonitor: snap(networkMonitorWindowController),
            waveform: snap(waveformWindowController),
            projectM: snap(projectMWindowController, sideWindow: true),
            // Library stores its position frame for restoration after Compact-mode rebuild.
            library: snap(plexBrowserWindowController,
                          normalFrame: plexBrowserWindowController?.frameForPositionMemory, sideWindow: true),
            debug: snapWindow(debugWindowController?.window)
        )
    }

    /// A window in native fullscreen occupies its own Space. Calling `orderOut` (or `orderFront`)
    /// on it forces macOS to switch to that Space to run the transition animation — which, when
    /// the user is viewing a different Space, yanks them away from the desktop they're on. Compact
    /// Mode must leave such windows untouched: they simply stay on their own Space, out of view.
    private func isInNativeFullScreen(_ window: NSWindow?) -> Bool {
        window?.styleMask.contains(.fullScreen) ?? false
    }

    private func orderOutRegularWindows() {
        // The video player and debug console are allowed to stay in Compact Mode. They are
        // deliberately excluded here and skipped by the orphan sweep below, so Compact Mode
        // never hides or restores them.
        for window in [mainWindowController?.window,
                       equalizerWindowController?.window,
                       playlistWindowController?.window,
                       spectrumWindowController?.window,
                       audioAnalysisWindowController?.window,
                       peppyMeterWindowController?.window,
                       networkMonitorWindowController?.window,
                       waveformWindowController?.window,
                       projectMWindowController?.window,
                       plexBrowserWindowController?.window].compactMap({ $0 })
        where !isInNativeFullScreen(window) {
            window.orderOut(nil)
        }

        orderOutOrphanedAppWindows()
    }

    /// Break persistent AppKit parent/child relationships before hiding the normal window set.
    /// Docking is recomputed on Compact Mode exit after all prior windows are visible again.
    private func detachManagedChildWindowsForCompactMode() {
        guard let mainWindow = mainWindowController?.window else { return }
        let managedWindows = [
            equalizerWindowController?.window,
            playlistWindowController?.window,
            spectrumWindowController?.window,
            audioAnalysisWindowController?.window,
            peppyMeterWindowController?.window,
            networkMonitorWindowController?.window,
            waveformWindowController?.window,
            projectMWindowController?.window,
            plexBrowserWindowController?.window
        ].compactMap { $0 }

        for child in mainWindow.childWindows ?? []
        where managedWindows.contains(where: { $0 === child }) {
            mainWindow.removeChildWindow(child)
        }
    }

    private func orderOutOrphanedAppWindows() {
        let compactWindow = compactWindowController?.window
        for window in NSApp.windows where window.isVisible {
            if window === compactWindow { continue }
            // These windows are allowed to remain visible in Compact Mode (see orderOutRegularWindows).
            if window === videoPlayerWindowController?.window { continue }
            if window === debugWindowController?.window { continue }
            if isSystemOrTransientWindow(window) { continue }
            // Leave fullscreen windows on their own Space — hiding them would switch Spaces.
            if isInNativeFullScreen(window) { continue }
            let isOrphanedPlayerWindow =
                window.identifier == Self.modeDependentWindowIdentifier
            if !isOrphanedPlayerWindow {
                regularWindowSnapshot?.additionalWindows.append(window)
            }
            NSLog("WindowManager: compact mode hiding %@ window class=%@",
                  isOrphanedPlayerWindow ? "orphaned" : "additional",
                  NSStringFromClass(type(of: window)))
            window.orderOut(nil)
        }
    }

    /// Windows the compact-mode sweep must never touch: the status-bar item window,
    /// system popovers/tooltips/palettes, and attached modal sheets. App-owned NSPanel
    /// instances (such as About) are not exempt.
    private func isSystemOrTransientWindow(_ window: NSWindow) -> Bool {
        if window is NSColorPanel || window is NSFontPanel { return true }
        if window.sheetParent != nil { return true }    // attached modal sheet
        let className = NSStringFromClass(type(of: window))
        let systemClasses = ["NSStatusBarWindow", "_NSPopoverWindow",
                             "NSToolTipPanel", "NSCarbonMenuWindow", "NSMenuWindowManagerWindow"]
        return systemClasses.contains(className)
    }

    private func restoreRegularWindowSnapshot() {
        guard let snapshot = regularWindowSnapshot else { return }

        func restore(_ snapshot: WindowSnapshot?, controller: ModeDependentWindow?) {
            guard let snapshot, let window = controller?.window else { return }
            // Never touched on entry (see isInNativeFullScreen); leave it on its own Space so
            // exiting Compact Mode doesn't switch away from the user's current desktop.
            if isInNativeFullScreen(window) { return }
            if snapshot.frame != .zero {
                window.setFrame(snapshot.frame, display: true)
            }
            if snapshot.wasVisible {
                window.orderFront(nil)
            } else {
                window.orderOut(nil)
            }
        }

        restore(snapshot.main, controller: mainWindowController)
        restore(snapshot.equalizer, controller: equalizerWindowController)
        restore(snapshot.playlist, controller: playlistWindowController)
        restore(snapshot.spectrum, controller: spectrumWindowController)
        restore(snapshot.audioAnalysis, controller: audioAnalysisWindowController)
        restore(snapshot.peppyMeter, controller: peppyMeterWindowController)
        restore(snapshot.networkMonitor, controller: networkMonitorWindowController)
        restore(snapshot.waveform, controller: waveformWindowController)
        restore(snapshot.projectM, controller: projectMWindowController)
        restore(snapshot.library, controller: plexBrowserWindowController)
        // The video player and debug console are never hidden by Compact Mode, so they are not restored here either.

        for window in snapshot.additionalWindows where !isInNativeFullScreen(window) {
            window.orderFront(nil)
        }
        regularWindowSnapshot = nil
    }

    private func markModeDependentWindow(_ window: NSWindow?) {
        window?.identifier = Self.modeDependentWindowIdentifier
    }

    /// While Compact Mode is active, state persistence must record the windows that were
    /// visible before entry rather than the intentionally hidden compact-mode window set.
    func visibilityForStateSaving(_ key: String, current: Bool) -> Bool {
        if compactWindowEnabled, key == "main" {
            return mainWasVisibleBeforeCompactWindow
        }
        guard compactModeState != .regular, let snapshot = regularWindowSnapshot else { return current }
        switch key {
        case "main": return snapshot.main?.wasVisible ?? current
        case "equalizer": return snapshot.equalizer?.wasVisible ?? current
        case "playlist": return snapshot.playlist?.wasVisible ?? current
        case "spectrum": return snapshot.spectrum?.wasVisible ?? current
        case "audioAnalysis": return snapshot.audioAnalysis?.wasVisible ?? current
        case "peppyMeter": return snapshot.peppyMeter?.wasVisible ?? current
        case "networkMonitor": return snapshot.networkMonitor?.wasVisible ?? current
        case "waveform": return snapshot.waveform?.wasVisible ?? current
        case "projectM": return snapshot.projectM?.wasVisible ?? current
        case "plexBrowser": return snapshot.library?.wasVisible ?? current
        // "video" and "debug" are intentionally omitted: Compact Mode no longer hides them,
        // so their live visibility is already the value worth saving (falls through to `current`).
        default: return current
        }
    }

    /// Switching activation policy `.accessory` → `.regular` makes macOS forget the bundle's
    /// CFBundleIconFile and show the generic executable icon in the Dock. Re-apply the app icon
    /// explicitly so the NullPlayer logo returns when leaving Compact Mode.
    private func restoreDockIconImage() {
        let image: NSImage?
        if let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") {
            image = NSImage(contentsOf: icnsURL)
        } else if let pngURL = BundleHelper.url(forResource: "AppIcon", withExtension: "png"),
                  let png = NSImage(contentsOf: pngURL) {
            png.size = NSSize(width: 128, height: 128)
            image = png
        } else {
            image = nil
        }
        if let image { NSApp.applicationIconImage = image }
    }

    /// Draws the NullPlayer brand mark (a circle with a slash through it) as a monochrome
    /// template image sized for the menu bar. As a template, macOS tints it automatically to
    /// match light/dark menu bars and selection state.
    private static func makeCompactStatusItemImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 1.6
            let inset = lineWidth + 1.5
            let circleRect = rect.insetBy(dx: inset, dy: inset)
            NSColor.black.setStroke()

            let circle = NSBezierPath(ovalIn: circleRect)
            circle.lineWidth = lineWidth
            circle.stroke()

            // Diagonal slash from lower-left to upper-right, extending slightly past the circle.
            let slash = NSBezierPath()
            let pad: CGFloat = 1.0
            slash.move(to: NSPoint(x: circleRect.minX - pad, y: circleRect.minY - pad))
            slash.line(to: NSPoint(x: circleRect.maxX + pad, y: circleRect.maxY + pad))
            slash.lineWidth = lineWidth
            slash.lineCapStyle = .round
            slash.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func createCompactStatusItem() {
        guard compactStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = WindowManager.makeCompactStatusItemImage()
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(compactStatusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        compactStatusItem = item
    }

    private func removeCompactStatusItem() {
        if let item = compactStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            compactStatusItem = nil
        }
    }

    @objc private func compactStatusItemClicked() {
        let event = NSApp.currentEvent
        let isContextClick = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)
        if isContextClick {
            presentCompactStatusMenu()
        } else {
            toggleCompactWindowVisibility()
        }
    }

    private func presentCompactStatusMenu() {
        guard let item = compactStatusItem else { return }
        let menu = NSMenu()
        let title = compactModeState == .compactVisible ? "Hide Compact Window" : "Show Compact Window"
        let toggle = NSMenuItem(title: title, action: #selector(toggleCompactWindowVisibility), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())
        let exit = NSMenuItem(title: "Exit Compact Mode", action: #selector(exitCompactModeMenuAction), keyEquivalent: "")
        exit.target = self
        menu.addItem(exit)
        // Temporarily attach the menu so the button presents it, then detach so plain
        // left-clicks keep toggling the window.
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggleCompactWindowVisibility() {
        switch compactModeState {
        case .compactVisible:
            hideCompactWindow()
            compactModeState = .compactHidden
        case .compactHidden:
            showCompactWindow()
            compactModeState = .compactVisible
        default:
            break
        }
    }

    private func createCompactWindowControllerIfNeeded() {
        if compactWindowController == nil {
            compactWindowController = CompactModeWindowController(modernUI: isRunningModernUI)
        }
        compactWindowController?.seedFromAudioEngine()
    }

    private func hideCompactWindow() {
        compactWindowController?.hide()
    }

    private func showCompactWindow() {
        guard compactModeEnabled else { return }
        createCompactWindowControllerIfNeeded()
        compactWindowController?.show(anchoredTo: compactStatusItem?.button)
    }

    func compactSurfaceDidHide() {
        if compactWindowEnabled {
            exitCompactWindow()
            return
        }
        guard compactModeState == .compactVisible || compactModeState == .entering else { return }
        compactModeState = .compactHidden
    }

    @objc private func exitCompactModeMenuAction() {
        exitCompactMode()
    }

    // Forwarders from the AudioEngine broadcast hub to the embedded compact player bar.
    func compactBarUpdateTime(current: TimeInterval, duration: TimeInterval) {
        guard compactModeEnabled || compactWindowEnabled else { return }
        compactWindowController?.updateTime(current: current, duration: duration)
    }

    func compactBarUpdateTrack(_ track: Track?) {
        guard compactModeEnabled || compactWindowEnabled else { return }
        compactWindowController?.updateTrack(track)
    }

    func compactBarUpdatePlaybackState() {
        guard compactModeEnabled || compactWindowEnabled else { return }
        compactWindowController?.updatePlaybackState()
    }

    // MARK: - Library History

    func showLibraryHistory() {
        guard isRunningModernUI else { return }
        showPlexBrowser()
        plexBrowserBrowseMode = ModernBrowseMode.history.rawValue
        plexBrowserWindowController?.window?.makeKeyAndOrderFront(nil)
        applyAlwaysOnTopToWindow(plexBrowserWindowController?.window)
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    func toggleLibraryHistory() {
        guard isRunningModernUI else { return }
        if isLibraryHistoryVisible {
            plexBrowserWindowController?.window?.orderOut(nil)
            postLayoutChangeNotification()
            updateDockedChildWindows()
            return
        }

        showLibraryHistory()
    }

    /// Show the Plex account linking sheet
    func showPlexLinkSheet() {
        // Show from main window if available, otherwise standalone
        if let mainWindow = mainWindowController?.window {
            let linkSheet = PlexLinkSheet()
            linkSheet.showAsSheet(from: mainWindow) { [weak self] success in
                if success {
                    self?.plexBrowserWindowController?.reloadData()
                }
            }
        } else {
            let linkSheet = PlexLinkSheet()
            linkSheet.showAsWindow { [weak self] success in
                if success {
                    self?.plexBrowserWindowController?.reloadData()
                }
            }
        }
    }
    
    /// Unlink the Plex account
    func unlinkPlexAccount() {
        PlexManager.shared.unlinkAccount()
        plexBrowserWindowController?.reloadData()
    }
    
    // MARK: - Subsonic Sheets
    
    /// Subsonic dialogs
    private var subsonicLinkSheet: SubsonicLinkSheet?
    private var subsonicServerListSheet: SubsonicServerListSheet?
    
    /// Show the Subsonic server add dialog
    func showSubsonicLinkSheet() {
        subsonicLinkSheet = SubsonicLinkSheet()
        subsonicLinkSheet?.showDialog { [weak self] server in
            self?.subsonicLinkSheet = nil
            if server != nil {
                self?.plexBrowserWindowController?.reloadData()
            }
        }
    }
    
    /// Show the Subsonic server list management dialog
    func showSubsonicServerList() {
        subsonicServerListSheet = SubsonicServerListSheet()
        subsonicServerListSheet?.showDialog { [weak self] _ in
            self?.subsonicServerListSheet = nil
            self?.plexBrowserWindowController?.reloadData()
        }
    }
    
    // MARK: - Jellyfin Sheets
    
    private var jellyfinLinkSheet: JellyfinLinkSheet?
    private var jellyfinServerListSheet: JellyfinServerListSheet?

    private var embyLinkSheet: EmbyLinkSheet?
    private var embyServerListSheet: EmbyServerListSheet?
    
    /// Show the Jellyfin server add dialog
    func showJellyfinLinkSheet() {
        jellyfinLinkSheet = JellyfinLinkSheet()
        jellyfinLinkSheet?.showDialog { [weak self] server in
            self?.jellyfinLinkSheet = nil
            if server != nil {
                self?.plexBrowserWindowController?.reloadData()
            }
        }
    }
    
    /// Show the Jellyfin server list management dialog
    func showJellyfinServerList() {
        jellyfinServerListSheet = JellyfinServerListSheet()
        jellyfinServerListSheet?.showDialog { [weak self] _ in
            self?.jellyfinServerListSheet = nil
            self?.plexBrowserWindowController?.reloadData()
        }
    }

    // MARK: - Emby Sheets

    /// Show the Emby server add dialog
    func showEmbyLinkSheet() {
        embyLinkSheet = EmbyLinkSheet()
        embyLinkSheet?.showDialog { [weak self] server in
            self?.embyLinkSheet = nil
            if server != nil {
                self?.plexBrowserWindowController?.reloadData()
            }
        }
    }

    /// Show the Emby server list management dialog
    func showEmbyServerList() {
        embyServerListSheet = EmbyServerListSheet()
        embyServerListSheet?.showDialog { [weak self] _ in
            self?.embyServerListSheet = nil
            self?.plexBrowserWindowController?.reloadData()
        }
    }

    // MARK: - Video Player Window

    private var targetVideoCastDevice: CastDevice? {
        let castManager = CastManager.shared
        if castManager.currentCast == .video,
           let activeDevice = castManager.activeSession?.device,
           activeDevice.supportsVideo {
            return activeDevice
        }
        // Auto-route only to the exact device the user explicitly selected. The general
        // preferredVideoCastDevice getter intentionally falls back to the first available
        // video device when the preference is missing/offline for cast-button convenience;
        // that fallback must not silently redirect normal video playback.
        guard let preferredID = castManager.preferredVideoCastDeviceID else { return nil }
        return castManager.discoveredDevices.first {
            $0.id == preferredID && $0.supportsVideo
        }
    }

    private func routeToVideoCastIfNeeded(title: String, artworkTrack: Track?, operation: @escaping (CastDevice) async throws -> Void) -> Bool {
        guard let device = targetVideoCastDevice else { return false }

        // If a video cast is already active, close it now — two simultaneous casts aren't possible.
        // Local video teardown is deferred until the cast succeeds so playback isn't lost on failure.
        let hasLocalVideoRunning: Bool
        if let vpc = videoPlayerWindowController, vpc.currentTitle != nil {
            if vpc.isCastingVideo {
                vpc.closeForCastTransition()
                hasLocalVideoRunning = false
            } else {
                hasLocalVideoRunning = true
            }
        } else {
            hasLocalVideoRunning = false
        }

        videoTitle = title
        mainWindowController?.updateVideoTrackInfo(title: title, artworkTrack: artworkTrack)
        mainWindowController?.updatePlaybackState()

        Task {
            do {
                try await operation(device)
                // Cast succeeded — safe to stop any local video that was running
                if hasLocalVideoRunning {
                    await MainActor.run {
                        self.videoPlayerWindowController?.stop()
                        self.videoTitle = title
                        self.mainWindowController?.updateVideoTrackInfo(title: title, artworkTrack: artworkTrack)
                        self.mainWindowController?.updatePlaybackState()
                    }
                }
            } catch {
                NSLog("WindowManager: Failed to route video '%@' to active cast device %@: %@", title, device.name, error.localizedDescription)
                await MainActor.run {
                    if hasLocalVideoRunning,
                       let localController = self.videoPlayerWindowController,
                       let localTitle = localController.currentTitle {
                        self.videoTitle = localTitle
                        self.mainWindowController?.updateVideoTrackInfo(
                            title: localTitle,
                            artworkTrack: localController.currentArtworkTrack
                        )
                    } else {
                        self.videoTitle = nil
                        self.mainWindowController?.clearVideoTrackInfo()
                    }
                    self.mainWindowController?.updatePlaybackState()
                }
                CastManager.shared.postError(.playbackFailed("Could not play '\(title)' on \(device.name): \(error.localizedDescription)"))
            }
        }

        return true
    }
    
    /// Show the video player with a URL and title
    func showVideoPlayer(url: URL, title: String, allowCasting: Bool = true) {
        let artworkTrack = Track(url: url, title: title, mediaType: .video)
        if allowCasting, routeToVideoCastIfNeeded(title: title, artworkTrack: artworkTrack, operation: { device in
            try await CastManager.shared.castVideoURL(url, title: title, to: device)
        }) {
            return
        }

        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(url: url, title: title)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Plex movie in the video player
    func playMovie(_ movie: PlexMovie) {
        if routeToVideoCastIfNeeded(title: movie.title, artworkTrack: PlexManager.shared.convertToTrack(movie), operation: { device in
            try await CastManager.shared.castPlexMovie(movie, to: device)
        }) {
            return
        }

        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(movie: movie)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Plex episode in the video player
    func playEpisode(_ episode: PlexEpisode) {
        let title = episode.grandparentTitle.map { "\($0) - \(episode.episodeIdentifier) - \(episode.title)" } ?? episode.title
        if routeToVideoCastIfNeeded(title: title, artworkTrack: PlexManager.shared.convertToTrack(episode), operation: { device in
            try await CastManager.shared.castPlexEpisode(episode, to: device)
        }) {
            return
        }

        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(episode: episode)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Jellyfin movie in the video player
    func playJellyfinMovie(_ movie: JellyfinMovie) {
        if routeToVideoCastIfNeeded(title: movie.title, artworkTrack: JellyfinManager.shared.convertToTrack(movie), operation: { device in
            try await CastManager.shared.castJellyfinMovie(movie, to: device)
        }) {
            return
        }

        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(jellyfinMovie: movie)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }
    
    /// Play a Jellyfin episode in the video player
    func playJellyfinEpisode(_ episode: JellyfinEpisode) {
        let title = episode.seriesName.map { "\($0) - \(episode.episodeIdentifier) - \(episode.title)" } ?? episode.title
        if routeToVideoCastIfNeeded(title: title, artworkTrack: JellyfinManager.shared.convertToTrack(episode), operation: { device in
            try await CastManager.shared.castJellyfinEpisode(episode, to: device)
        }) {
            return
        }

        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(jellyfinEpisode: episode)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }

    /// Play an Emby movie in the video player
    func playEmbyMovie(_ movie: EmbyMovie) {
        if routeToVideoCastIfNeeded(title: movie.title, artworkTrack: EmbyManager.shared.convertToTrack(movie), operation: { device in
            try await CastManager.shared.castEmbyMovie(movie, to: device)
        }) {
            return
        }

        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(embyMovie: movie)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }

    /// Play an Emby episode in the video player
    func playEmbyEpisode(_ episode: EmbyEpisode) {
        let title = episode.seriesName.map { "\($0) - \(episode.episodeIdentifier) - \(episode.title)" } ?? episode.title
        if routeToVideoCastIfNeeded(title: title, artworkTrack: EmbyManager.shared.convertToTrack(episode), operation: { device in
            try await CastManager.shared.castEmbyEpisode(episode, to: device)
        }) {
            return
        }

        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        videoPlayerWindowController?.volume = audioEngine.volume
        videoPlayerWindowController?.play(embyEpisode: episode)
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
    }

    /// Play a video Track from the playlist
    /// Called by AudioEngine when it encounters a video track
    func playVideoTrack(_ track: Track) {
        guard track.mediaType == .video else {
            NSLog("WindowManager: playVideoTrack called with non-video track")
            return
        }

        if routeToVideoCastIfNeeded(title: track.displayTitle, artworkTrack: track, operation: { device in
            try await CastManager.shared.castVideoURL(
                track.url,
                title: track.displayTitle,
                to: device,
                duration: track.duration,
                contentType: track.contentType
            )
        }) {
            return
        }
        
        if videoPlayerWindowController == nil {
            videoPlayerWindowController = VideoPlayerWindowController()
        }
        
        // Set up callback for when video finishes (to advance playlist)
        videoPlayerWindowController?.onVideoFinishedForPlaylist = { [weak self] in
            self?.videoTrackDidFinish()
        }
        
        videoPlayerWindowController?.volume = audioEngine.volume
        
        // Use server-aware playback for scrobbling/progress
        if track.plexRatingKey != nil {
            videoPlayerWindowController?.play(plexTrack: track)
        } else if track.jellyfinId != nil {
            videoPlayerWindowController?.play(jellyfinTrack: track)
        } else if track.embyId != nil {
            videoPlayerWindowController?.play(embyTrack: track)
        } else {
            videoPlayerWindowController?.play(url: track.url, title: track.displayTitle)
        }
        
        applyAlwaysOnTopToWindow(videoPlayerWindowController?.window)
        NSLog("WindowManager: Playing video track from playlist: %@", track.title)
    }
    
    /// Called when a video track from the playlist finishes playing
    private func videoTrackDidFinish() {
        NSLog("WindowManager: Video track finished, advancing playlist")
        audioEngine.next()
    }
    
    var isVideoPlayerVisible: Bool {
        videoPlayerWindowController?.window?.isVisible == true
    }
    
    /// Whether video is currently playing
    var isVideoPlaying: Bool {
        if case .video = CastManager.shared.currentCast {
            return CastManager.shared.isVideoCastPlaying
        }
        return videoPlayerWindowController?.isPlaying ?? false
    }
    
    /// Current video title (if playing)
    var currentVideoTitle: String? {
        if case .video = CastManager.shared.currentCast {
            return CastManager.shared.videoCastTitle
        }
        return videoPlayerWindowController?.currentTitle
    }
    
    /// Public access to video player controller (for About Playing feature)
    var currentVideoPlayerController: VideoPlayerWindowController? {
        videoPlayerWindowController
    }
    
    func toggleVideoPlayer() {
        if let controller = videoPlayerWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else if videoPlayerWindowController != nil {
            videoPlayerWindowController?.showWindow(nil)
        }
    }
    
    /// Toggle video play/pause
    func toggleVideoPlayPause() {
        switch CastManager.shared.currentCast {
        case .video:
            Task {
                if CastManager.shared.isVideoCastPlaying {
                    try? await CastManager.shared.pause()
                } else {
                    try? await CastManager.shared.resume()
                }
            }
        default:
            videoPlayerWindowController?.togglePlayPause()
        }
    }

    /// Stop video playback
    func stopVideo() {
        switch CastManager.shared.currentCast {
        case .video:
            Task {
                await CastManager.shared.stopCasting()
                await MainActor.run {
                    WindowManager.shared.videoPlaybackDidStop()
                }
            }
        default:
            videoPlayerWindowController?.stop()
        }
    }
    
    /// Set video player volume
    func setVideoVolume(_ volume: Float) {
        videoPlayerWindowController?.volume = volume
    }
    
    /// Whether video casting is currently active
    var isVideoCastingActive: Bool {
        if case .video = CastManager.shared.currentCast { return true }
        return false
    }

    /// Set volume on video cast device
    func setVideoCastVolume(_ volume: Float) {
        guard isVideoCastingActive else { return }
        Task {
            try? await CastManager.shared.setVolume(volume)
        }
    }

    /// Toggle play/pause on video cast
    func toggleVideoCastPlayPause() {
        switch CastManager.shared.currentCast {
        case .video:
            Task {
                if CastManager.shared.isVideoCastPlaying {
                    try? await CastManager.shared.pause()
                } else {
                    try? await CastManager.shared.resume()
                }
            }
        default:
            videoPlayerWindowController?.togglePlayPause()
        }
    }

    /// Seek video cast (normalized 0-1 position)
    func seekVideoCast(position: Double) {
        switch CastManager.shared.currentCast {
        case .video:
            let duration = CastManager.shared.videoCastDuration
            guard duration > 0 else { return }
            let time = position * duration
            Task {
                try? await CastManager.shared.seek(to: time)
            }
        default:
            if let controller = videoPlayerWindowController {
                let time = position * controller.duration
                controller.seek(to: time)
            }
        }
    }

    /// Skip video forward
    func skipVideoForward(_ seconds: TimeInterval = 10) {
        switch CastManager.shared.currentCast {
        case .video:
            let duration = CastManager.shared.videoCastDuration
            let requestedTime = CastManager.shared.videoCastCurrentTime + seconds
            let newTime = duration > 0 ? min(requestedTime, duration) : requestedTime
            Task {
                try? await CastManager.shared.seek(to: newTime)
            }
        default:
            videoPlayerWindowController?.skipForward(seconds)
        }
    }

    /// Skip video backward
    func skipVideoBackward(_ seconds: TimeInterval = 10) {
        switch CastManager.shared.currentCast {
        case .video:
            let newTime = max(CastManager.shared.videoCastCurrentTime - seconds, 0)
            Task {
                try? await CastManager.shared.seek(to: newTime)
            }
        default:
            videoPlayerWindowController?.skipBackward(seconds)
        }
    }

    /// Seek video to specific time
    func seekVideo(to time: TimeInterval) {
        switch CastManager.shared.currentCast {
        case .video:
            Task {
                try? await CastManager.shared.seek(to: time)
            }
        default:
            videoPlayerWindowController?.seek(to: time)
        }
    }
    
    /// Called when video playback starts - pause audio
    func videoPlaybackDidStart() {
        if audioEngine.state == .playing {
            audioEngine.pause()
        }
        // In Compact Mode the mini-player floats at `.statusBar`, above the video player window.
        // Drop it below normal level and bring the video forward so the player launches in front
        // instead of behind the floating compact window. (Clicking the mini-player still raises it
        // again via CompactModeWindowController's key-window handling.)
        if compactModeEnabled, let videoWindow = videoPlayerWindowController?.window {
            compactWindowController?.yieldFrontForVideoPlayer()
            videoWindow.makeKeyAndOrderFront(nil)
        }
        // Update main window with video title
        if let title = videoPlayerWindowController?.currentTitle {
            videoTitle = title
            mainWindowController?.updateVideoTrackInfo(title: title, artworkTrack: videoPlayerWindowController?.currentArtworkTrack)
        }
        mainWindowController?.updatePlaybackState()
    }
    
    /// Called when video playback stops
    /// Close the video player window when an audio cast supersedes an active video cast.
    /// Called from CastManager when castNewTrack or cast() transitions video→audio.
    func closeVideoPlayerForCastTransition(wasVideoCast: Bool = false) {
        if let vpc = videoPlayerWindowController, vpc.isCastingVideo {
            // castNewTrack path: isCastingVideo still true
            vpc.closeForCastTransition()
        } else if let vpc = videoPlayerWindowController,
                  wasVideoCast || CastManager.shared.isVideoCasting || CastManager.shared.currentCast == .video {
            // cast() path: isCastingVideo already cleared by stopCastingAndAwaitTeardown,
            // so use CastManager's explicit video-cast state instead of window visibility.
            vpc.closeForCastTransition()
        }
    }

    func videoPlaybackDidStop() {
        videoCurrentTime = 0
        videoDuration = 0
        videoTitle = nil
        // If audio was paused (by video starting), stop it so main window shows stopped state
        if audioEngine.state == .paused {
            audioEngine.stop()
        }
        mainWindowController?.clearVideoTrackInfo()
        mainWindowController?.updateTime(current: 0, duration: 0)
        mainWindowController?.updatePlaybackState()
        // Restore the compact window's floating level dropped in videoPlaybackDidStart(), so the
        // mini-player returns to always-on-top even if the user never re-focuses it.
        if compactModeEnabled {
            compactWindowController?.restoreFloatingLevelAfterVideoPlayer()
        }
    }

    /// Called by video player to update time (for main window display)
    func videoDidUpdateTime(current: TimeInterval, duration: TimeInterval) {
        videoCurrentTime = current
        videoDuration = duration
        mainWindowController?.updateTime(current: current, duration: duration)
    }
    
    /// Whether video is the active playback source (video session is active)
    /// Returns true when a video is loaded in the video player (even if paused) OR when video casting is active
    /// This is used by playlist mini controls to route commands correctly
    var isVideoActivePlayback: Bool {
        // Video casting is active - controls should route to video cast
        if isVideoCastingActive {
            return true
        }
        
        // A video session is active if the video player is visible AND has a video loaded
        // (indicated by currentTitle being set). This is different from isVideoPlaying
        // which only returns true when actively playing (not paused).
        guard let controller = videoPlayerWindowController,
              let window = controller.window,
              window.isVisible else {
            return false
        }
        return controller.currentTitle != nil
    }

    /// True if a video is actively loaded in the player window or CastManager is video casting.
    /// Unlike isVideoActivePlayback, does NOT rely on VideoPlayerWindowController.isCastingVideo.
    var isVideoContentActive: Bool {
        if case .video = CastManager.shared.currentCast { return true }
        guard let controller = videoPlayerWindowController,
              let window = controller.window,
              window.isVisible else {
            return false
        }
        return controller.currentTitle != nil
    }

    /// Get current video playback state for main window display
    var videoPlaybackState: PlaybackState {
        if case .video = CastManager.shared.currentCast {
            return CastManager.shared.isVideoCastPlaying ? .playing : .paused
        }
        guard let controller = videoPlayerWindowController else { return .stopped }
        return controller.isPlaying ? .playing : .paused
    }
    
    // MARK: - ProjectM Visualization Window
    
    func showProjectM(at restoredFrame: NSRect? = nil, restoringPresetIndex presetIndex: Int? = nil) {
        let isNewWindow = projectMWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                projectMWindowController = ModernProjectMWindowController()
            } else {
                projectMWindowController = ProjectMWindowController()
            }
        }
        markModeDependentWindow(projectMWindowController?.window)
        // When rebuilding the visualization window, stash the live preset before showWindow()
        // starts the display link. Otherwise the first render can queue the saved startup preset
        // and the immediate restore can be rejected by ProjectMWrapper's rapid-change guard.
        if let presetIndex, presetIndex >= 0 {
            projectMWindowController?.restorePresetSelection(index: presetIndex)
        }
        projectMWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(projectMWindowController?.window)
        // Position window to match the vertical stack
        if let window = projectMWindowController?.window {
            if isNewWindow, let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration (first creation only)
                window.setFrame(frame, display: true)
            } else if let frame = lastProjectMFrame, frame != .zero {
                if lastProjectMFrameWasDocked,
                   let dockedFrame = leftDockedSideFrame(for: window, width: frame.width) {
                    window.setFrame(dockedFrame, display: true)
                } else {
                    window.setFrame(frame, display: true)
                }
            } else {
                if let newFrame = leftDockedSideFrame(for: window, width: window.frame.width) {
                    window.setFrame(newFrame, display: true)
                }
            }
        }
        postLayoutChangeNotification()
    }
    
    var isProjectMVisible: Bool {
        projectMWindowController?.window?.isVisible == true
    }
    
    /// Whether ProjectM is in fullscreen mode
    var isProjectMFullscreen: Bool {
        projectMWindowController?.isFullscreen ?? false
    }
    
    /// Toggle ProjectM fullscreen
    func toggleProjectMFullscreen() {
        projectMWindowController?.toggleFullscreen()
    }
    
    /// Whether the debug console window is visible
    var isDebugWindowVisible: Bool {
        debugWindowController?.window?.isVisible == true
    }
    
    func toggleProjectM() {
        if let controller = projectMWindowController, controller.window?.isVisible == true {
            rememberProjectMFrame()
            // Stop rendering before hiding to save CPU (orderOut doesn't trigger windowWillClose)
            controller.stopRenderingForHide()
            controller.window?.orderOut(nil)
        } else {
            showProjectM()
        }
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }
    
    // MARK: - Spectrum Analyzer Window
    
    func showSpectrum(at restoredFrame: NSRect? = nil) {
        let isNewWindow = spectrumWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                spectrumWindowController = ModernSpectrumWindowController()
            } else {
                spectrumWindowController = SpectrumWindowController()
            }
        }
        markModeDependentWindow(spectrumWindowController?.window)
        
        // Position BEFORE showing (unless restoring from saved state)
        if let window = spectrumWindowController?.window {
            applyCenterStackSizingConstraints(window, kind: .spectrum)
            if let frame = restoredFrame, frame != .zero {
                applyRestoredCenterStackFrame(frame, to: window, kind: .spectrum)
            } else {
                // By design: always reset to default when showing without a saved frame.
                // Same rationale as showPlaylist — stretch state is not persisted across toggles.
                if isModernUIEnabled {
                    applyDefaultCenterStackFrameForCurrentHT(window, kind: .spectrum)
                } else {
                    (spectrumWindowController as? SpectrumWindowController)?.resetToDefaultFrame()
                }
                positionSubWindow(window)
            }
        }
        
        spectrumWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(spectrumWindowController?.window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
    }
    
    var isSpectrumVisible: Bool {
        spectrumWindowController?.window?.isVisible == true
    }
    
    /// Get the Spectrum window frame (for state saving)
    var spectrumWindowFrame: NSRect? {
        return spectrumWindowController?.window?.frame
    }

    /// Access the spectrum window when visible/internal geometry repairs need direct frame updates.
    var spectrumWindow: NSWindow? {
        spectrumWindowController?.window
    }
    
    func toggleSpectrum() {
        if let controller = spectrumWindowController,
           let window = controller.window,
           window.isVisible {
            let closingFrame = window.frame
            // Stop rendering before hiding to save CPU (orderOut doesn't trigger windowWillClose)
            controller.stopRenderingForHide()
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: closingFrame)
        } else {
            showSpectrum()
        }
        notifyMainWindowVisibilityChanged()
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    // MARK: - Audio Analysis Window

    func showAudioAnalysis(at restoredFrame: NSRect? = nil) {
        let runningModernMode = isRunningModernUI
        if audioAnalysisWindowController == nil {
            if runningModernMode {
                audioAnalysisWindowController = ModernAudioAnalysisWindowController()
            } else {
                audioAnalysisWindowController = AudioAnalysisWindowController()
            }
        }
        markModeDependentWindow(audioAnalysisWindowController?.window)

        if let window = audioAnalysisWindowController?.window {
            applyCenterStackSizingConstraints(window, kind: .audioAnalysis)
            if let frame = restoredFrame, frame != .zero {
                applyRestoredCenterStackFrame(frame, to: window, kind: .audioAnalysis)
            } else {
                if runningModernMode {
                    applyDefaultCenterStackFrameForCurrentHT(window, kind: .audioAnalysis)
                } else {
                    (audioAnalysisWindowController as? AudioAnalysisWindowController)?.resetToDefaultFrame()
                }
                positionSubWindow(window)
            }
        }

        audioAnalysisWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(audioAnalysisWindowController?.window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
    }

    var isAudioAnalysisVisible: Bool {
        audioAnalysisWindowController?.window?.isVisible == true
    }

    /// Get the Audio Analysis window frame (for state saving)
    var audioAnalysisWindowFrame: NSRect? {
        return audioAnalysisWindowController?.window?.frame
    }

    var audioAnalysisWindow: NSWindow? {
        audioAnalysisWindowController?.window
    }

    func toggleAudioAnalysis() {
        if let controller = audioAnalysisWindowController,
           let window = controller.window,
           window.isVisible {
            let closingFrame = window.frame
            controller.stopRenderingForHide()
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: closingFrame)
        } else {
            showAudioAnalysis()
        }
        notifyMainWindowVisibilityChanged()
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    // MARK: - PeppyMeter Window

    func showPeppyMeter(at restoredFrame: NSRect? = nil) {
        let runningModernMode = isRunningModernUI
        if peppyMeterWindowController == nil {
            if runningModernMode {
                peppyMeterWindowController = ModernPeppyMeterWindowController()
            } else {
                peppyMeterWindowController = PeppyMeterWindowController()
            }
        }
        markModeDependentWindow(peppyMeterWindowController?.window)

        if let window = peppyMeterWindowController?.window {
            applyCenterStackSizingConstraints(window, kind: .peppyMeter)
            if let frame = restoredFrame, frame != .zero {
                applyRestoredCenterStackFrame(frame, to: window, kind: .peppyMeter)
            } else {
                if runningModernMode {
                    applyDefaultCenterStackFrameForCurrentHT(window, kind: .peppyMeter)
                } else {
                    (peppyMeterWindowController as? PeppyMeterWindowController)?.resetToDefaultFrame()
                }
                positionSubWindow(window)
            }
        }

        peppyMeterWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(peppyMeterWindowController?.window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
    }

    var isPeppyMeterVisible: Bool {
        peppyMeterWindowController?.window?.isVisible == true
    }

    var isPeppyMeterFullscreen: Bool {
        peppyMeterWindowController?.isFullscreen ?? false
    }

    var peppyMeterWindowFrame: NSRect? {
        peppyMeterWindowController?.window?.frame
    }

    var peppyMeterWindow: NSWindow? {
        peppyMeterWindowController?.window
    }

    func togglePeppyMeterFullscreen() {
        if peppyMeterWindowController?.window?.isVisible == true {
            peppyMeterWindowController?.toggleFullscreen()
        } else {
            showPeppyMeter()
            peppyMeterWindowController?.toggleFullscreen()
        }
    }

    func togglePeppyMeter() {
        if let controller = peppyMeterWindowController,
           let window = controller.window,
           window.isVisible {
            if controller.isFullscreen {
                controller.toggleFullscreen()
            }
            let closingFrame = window.frame
            controller.stopRenderingForHide()
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: closingFrame)
        } else {
            showPeppyMeter()
        }
        notifyMainWindowVisibilityChanged()
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    // MARK: - Network Monitor Window

    func showNetworkMonitor(at restoredFrame: NSRect? = nil) {
        let runningModernMode = isRunningModernUI
        if networkMonitorWindowController == nil {
            if runningModernMode {
                networkMonitorWindowController = ModernNetworkMonitorWindowController()
            } else {
                networkMonitorWindowController = NetworkMonitorWindowController()
            }
        }
        markModeDependentWindow(networkMonitorWindowController?.window)

        if let window = networkMonitorWindowController?.window {
            applyCenterStackSizingConstraints(window, kind: .networkMonitor)
            if let frame = restoredFrame, frame != .zero {
                applyRestoredCenterStackFrame(frame, to: window, kind: .networkMonitor)
            } else {
                if runningModernMode {
                    applyDefaultCenterStackFrameForCurrentHT(window, kind: .networkMonitor)
                } else {
                    (networkMonitorWindowController as? NetworkMonitorWindowController)?.resetToDefaultFrame()
                }
                positionSubWindow(window)
            }
        }

        networkMonitorWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(networkMonitorWindowController?.window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
    }

    var isNetworkMonitorVisible: Bool {
        networkMonitorWindowController?.window?.isVisible == true
    }

    var networkMonitorWindowFrame: NSRect? {
        networkMonitorWindowController?.window?.frame
    }

    var networkMonitorWindow: NSWindow? {
        networkMonitorWindowController?.window
    }

    func toggleNetworkMonitor() {
        if let controller = networkMonitorWindowController,
           let window = controller.window,
           window.isVisible {
            let closingFrame = window.frame
            controller.stopMonitoringForHide()
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: closingFrame)
        } else {
            showNetworkMonitor()
        }
        notifyMainWindowVisibilityChanged()
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    // MARK: - Waveform Window

    func showWaveform(at restoredFrame: NSRect? = nil) {
        let isNewWindow = waveformWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                waveformWindowController = ModernWaveformWindowController()
            } else {
                waveformWindowController = WaveformWindowController()
            }
        }
        markModeDependentWindow(waveformWindowController?.window)

        if let window = waveformWindowController?.window {
            let classicController = waveformWindowController as? WaveformWindowController
            applyCenterStackSizingConstraints(window, kind: .waveform)
            if let frame = restoredFrame, frame != .zero {
                classicController?.clearPendingFrameReset()
                applyRestoredCenterStackFrame(frame, to: window, kind: .waveform)
            } else {
                if isModernUIEnabled {
                    applyDefaultCenterStackFrameForCurrentHT(window, kind: .waveform)
                } else {
                    // Classic waveform should only reset after explicit close + reopen.
                    // orderOut/show cycles and unrelated layout changes must preserve user size.
                    let shouldResetClassicFrame = classicController?.consumeShouldResetFrameOnNextShow() ?? isNewWindow
                    if shouldResetClassicFrame {
                        classicController?.resetToDefaultFrame()
                    }
                }
                positionSubWindow(window)
            }
        }

        waveformWindowController?.showWindow(nil)
        waveformWindowController?.updateTrack(audioEngine.currentTrack)
        waveformWindowController?.updateTime(current: audioEngine.currentTime, duration: audioEngine.duration)
        applyAlwaysOnTopToWindow(waveformWindowController?.window)
        notifyMainWindowVisibilityChanged()
        postLayoutChangeNotification()
    }

    var isWaveformVisible: Bool {
        waveformWindowController?.window?.isVisible == true
    }

    var waveformWindowFrame: NSRect? {
        waveformWindowController?.window?.frame
    }

    /// Access the waveform window when visible/internal geometry repairs need direct frame updates.
    var waveformWindow: NSWindow? {
        waveformWindowController?.window
    }

    func toggleWaveform() {
        if let controller = waveformWindowController,
           let window = controller.window,
           window.isVisible {
            let closingFrame = window.frame
            controller.stopLoadingForHide()
            window.orderOut(nil)
            slideUpWindowsBelow(closingFrame: closingFrame)
        } else {
            showWaveform()
        }
        notifyMainWindowVisibilityChanged()
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    func updateWaveformTrack(_ track: Track?) {
        waveformWindowController?.updateTrack(track)
    }

    func updateWaveformTime(current: TimeInterval, duration: TimeInterval) {
        waveformWindowController?.updateTime(current: current, duration: duration)
    }

    func reloadWaveform(force: Bool) {
        waveformWindowController?.reloadWaveform(force: force)
    }

    func clearCurrentWaveformCache() {
        waveformWindowController?.stopLoadingForHide()
        let track = audioEngine.currentTrack
        Task {
            await WaveformCacheService.shared.clearCache(for: track)
            await MainActor.run {
                WindowManager.shared.waveformWindowController?.reloadWaveform(force: false)
            }
        }
    }

    func toggleWaveformCuePoints() {
        let current = UserDefaults.standard.bool(forKey: "waveformShowCuePoints")
        UserDefaults.standard.set(!current, forKey: "waveformShowCuePoints")
        waveformWindowController?.updateTrack(audioEngine.currentTrack)
    }

    func isWaveformTransparentBackgroundEnabled() -> Bool {
        WaveformAppearancePreferences.transparentBackgroundEnabled(
            isRunningModernUI: isRunningModernUI,
            modernSkinName: ModernSkinEngine.shared.currentSkinName
        )
    }

    func toggleWaveformTransparentBackground() {
        WaveformAppearancePreferences.setTransparentBackgroundEnabled(!isWaveformTransparentBackgroundEnabled())
    }

    func toggleWaveformTooltip() {
        let current = UserDefaults.standard.bool(forKey: "waveformHideTooltip")
        UserDefaults.standard.set(!current, forKey: "waveformHideTooltip")
        waveformWindowController?.updateTrack(audioEngine.currentTrack)
    }
    
    // MARK: - Debug Window
    
    /// Show the debug console window
    func showDebugWindow() {
        if debugWindowController == nil {
            // Start capturing BEFORE creating the window so toolbar shows correct state
            DebugConsoleManager.shared.startCapturing()
            debugWindowController = DebugWindowController()
        }
        debugWindowController?.showWindow(nil)
        debugWindowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    /// Toggle debug console window visibility
    func toggleDebugWindow() {
        if isDebugWindowVisible {
            debugWindowController?.window?.orderOut(nil)
        } else {
            showDebugWindow()
        }
    }
    
    // MARK: - Visualization Settings
    
    /// Whether projectM visualization is available
    var isProjectMAvailable: Bool {
        projectMWindowController?.isProjectMAvailable ?? false
    }
    
    /// Total number of visualization presets
    var visualizationPresetCount: Int {
        projectMWindowController?.presetCount ?? 0
    }
    
    /// Current visualization preset index
    var visualizationPresetIndex: Int? {
        projectMWindowController?.currentPresetIndex
    }

    /// Current visualization engine type
    var visualizationEngineType: VisualizationType {
        projectMWindowController?.currentEngineType ?? {
            if let raw = UserDefaults.standard.string(forKey: "visualizationEngineType"),
               let type = VisualizationType(rawValue: raw) {
                return type
            }
            return .projectM
        }()
    }

    /// Switch visualization engine if the window exists; otherwise persist for next creation.
    func switchVisualizationEngine(to type: VisualizationType) {
        UserDefaults.standard.set(type.rawValue, forKey: "visualizationEngineType")
        projectMWindowController?.switchEngine(to: type)
    }
    
    /// Get information about loaded presets (bundled count, custom count, custom path)
    var visualizationPresetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        projectMWindowController?.presetsInfo ?? (0, 0, nil)
    }
    
    /// Reload all visualization presets from bundled and custom folders
    func reloadVisualizationPresets() {
        projectMWindowController?.reloadPresets()
    }

    /// Build the visualization window's full controls menu when the window has been created.
    func buildVisualizationMenu() -> NSMenu? {
        projectMWindowController?.buildVisualizationMenu()
    }
    
    /// Select a visualization preset by index
    func selectVisualizationPreset(at index: Int) {
        projectMWindowController?.selectPreset(at: index, hardCut: false)
    }

    func notifyMainWindowVisibilityChanged() {
        mainWindowController?.windowVisibilityDidChange()
    }
    
    // MARK: - Skin Management

    enum ClassicSkinImportError: LocalizedError {
        case unsupportedExtension(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedExtension(let ext):
                return "Expected a .wsz skin file, got .\(ext)"
            }
        }
    }
    
    /// When true, shows album art as transparent background in browser window (default: true)
    var showBrowserArtworkBackground: Bool {
        get {
            // Default to true (enabled) if not set
            if UserDefaults.standard.object(forKey: "showBrowserArtworkBackground") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "showBrowserArtworkBackground")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showBrowserArtworkBackground")
            // Trigger browser redraw
            plexBrowserWindowController?.window?.contentView?.needsDisplay = true
        }
    }
    
    @discardableResult
    func loadSkin(from url: URL, userDefaults: UserDefaults = .standard) -> Bool {
        do {
            let skin = try SkinLoader.shared.load(from: url)
            currentSkin = skin
            currentSkinPath = url.path
            // Persist last used classic skin for easy reload when switching UI modes
            userDefaults.set(url.path, forKey: "lastClassicSkinPath")
            applyClassicVisualizationDefaults(notify: true)
            notifySkinChanged()
            return true
        } catch {
            print("Failed to load skin: \(error)")
            return false
        }
    }

    /// Import a classic `.wsz` skin into the persistent user skins directory.
    /// Returns the canonical imported URL used for future selection.
    @discardableResult
    func importClassicSkin(from sourceURL: URL) throws -> URL {
        try Self.importClassicSkin(from: sourceURL, to: skinsDirectoryURL)
    }
    
    private func loadDefaultSkin() {
        // 1. Try last used skin from UserDefaults
        if let lastPath = UserDefaults.standard.string(forKey: "lastClassicSkinPath"),
           FileManager.default.fileExists(atPath: lastPath) {
            do {
                currentSkin = try SkinLoader.shared.load(from: URL(fileURLWithPath: lastPath))
                currentSkinPath = lastPath
                applyClassicVisualizationDefaults(notify: false)
                return
            } catch {
                NSLog("Failed to restore last skin: \(error)")
            }
        }
        
        // 2. Try bundled default skin from app resources
        if let bundledURL = findBundledClassicSkin("NullPlayer-Silver") {
            do {
                currentSkin = try SkinLoader.shared.load(from: bundledURL)
                applyClassicVisualizationDefaults(notify: false)
                return
            } catch {
                NSLog("Failed to load bundled skin: \(error)")
            }
        }
        
        // 3. Fallback: unskinned native macOS rendering
        currentSkin = SkinLoader.shared.loadDefault()
        applyClassicVisualizationDefaults(notify: false)
    }
    
    private func findBundledClassicSkin(_ name: String) -> URL? {
        let bundle = Bundle.main
        guard let resourceURL = bundle.resourceURL else { return nil }
        // Mirror search paths from ModernSkinLoader.findBundledSkinDirectory()
        let searchPaths = [
            resourceURL.appendingPathComponent("Resources/Skins/\(name).wsz"),
            resourceURL.appendingPathComponent("NullPlayer_NullPlayer.bundle/Resources/Skins/\(name).wsz"),
            resourceURL.appendingPathComponent("Skins/\(name).wsz"),
        ]
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path.path) {
                return path
            }
        }
        return nil
    }
    
    /// Load the bundled default classic skin (NullPlayer-Silver) at runtime
    func loadBundledDefaultSkin() {
        if let bundledURL = findBundledClassicSkin("NullPlayer-Silver") {
            do {
                currentSkin = try SkinLoader.shared.load(from: bundledURL)
                currentSkinPath = nil
                UserDefaults.standard.removeObject(forKey: "lastClassicSkinPath")
                applyClassicVisualizationDefaults(notify: true)
                notifySkinChanged()
                return
            } catch {
                NSLog("Failed to load bundled default skin: \(error)")
            }
        }
        // Fallback: unskinned
        currentSkin = SkinLoader.shared.loadDefault()
        currentSkinPath = nil
        UserDefaults.standard.removeObject(forKey: "lastClassicSkinPath")
        applyClassicVisualizationDefaults(notify: true)
        notifySkinChanged()
    }

    func acquireSharedVisClassicBridge() -> VisClassicBridge {
        if let b = sharedVisClassicBridge { return b }
        let bridge = VisClassicBridge(width: 576, height: 128, scope: .spectrumWindow)!
        bridge.setReferenceWidth(576)
        sharedVisClassicBridge = bridge
        return bridge
    }

    /// Dedicated bridge for the main window's embedded analyzer, scoped to `.mainWindow`
    /// so it loads and persists its own profile independently of the dedicated spectrum
    /// window (which uses `acquireSharedVisClassicBridge`). This realizes the window-scoped
    /// vis_classic profile independence and lets metal skins default the main-window
    /// analyzer to a per-finish profile without clobbering the spectrum window's choice.
    func acquireMainWindowVisClassicBridge() -> VisClassicBridge {
        if let b = mainWindowVisClassicBridge { return b }
        let bridge = VisClassicBridge(width: 576, height: 128, scope: .mainWindow)!
        bridge.setReferenceWidth(576)
        mainWindowVisClassicBridge = bridge
        return bridge
    }

    private func applyClassicVisualizationDefaults(notify: Bool) {
        // Classic and modern skins are independent. WindowManager still loads the
        // remembered classic skin at startup so it is ready if the user switches UI
        // modes, but its visualization defaults must not overwrite modern scoped
        // profile preferences while the modern UI is active.
        guard !isRunningModernUI else { return }

        let defaults = UserDefaults.standard
        let visClassicMode = MainWindowVisMode.visClassicExact.rawValue
        let classicProfile = "Purple Neon"

        defaults.set(visClassicMode, forKey: "mainWindowVisMode")
        defaults.set(visClassicMode, forKey: "modernMainWindowVisMode")
        defaults.set(SpectrumQualityMode.visClassicExact.rawValue, forKey: "spectrumQualityMode")

        defaults.set(classicProfile, forKey: "visClassicLastProfileName.mainWindow")
        defaults.set(classicProfile, forKey: "visClassicLastProfileName.spectrumWindow")
        defaults.set(true, forKey: "visClassicFitToWidth.mainWindow")
        defaults.set(true, forKey: "visClassicFitToWidth.spectrumWindow")

        // Legacy fallback keys are still read by VisClassicBridge.
        defaults.set(classicProfile, forKey: "visClassicLastProfileName")
        defaults.set(true, forKey: "visClassicFitToWidth")

        guard notify else { return }

        NotificationCenter.default.post(name: NSNotification.Name("MainWindowVisChanged"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("SpectrumSettingsChanged"), object: nil)
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "load", "profileName": classicProfile, "target": "mainWindow"]
        )
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "load", "profileName": classicProfile, "target": "spectrumWindow"]
        )
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "fitToWidth", "enabled": true, "target": "mainWindow"]
        )
        NotificationCenter.default.post(
            name: .visClassicProfileCommand,
            object: nil,
            userInfo: ["command": "fitToWidth", "enabled": true, "target": "spectrumWindow"]
        )
    }
    
    private func notifySkinChanged() {
        // Notify all windows to redraw with new skin
        mainWindowController?.skinDidChange()
        playlistWindowController?.skinDidChange()
        equalizerWindowController?.skinDidChange()
        plexBrowserWindowController?.skinDidChange()
        projectMWindowController?.skinDidChange()
        spectrumWindowController?.skinDidChange()
        audioAnalysisWindowController?.skinDidChange()
        peppyMeterWindowController?.skinDidChange()
        networkMonitorWindowController?.skinDidChange()
        waveformWindowController?.skinDidChange()
        compactWindowController?.skinDidChange()
    }

    // MARK: - Skin Discovery
    
    /// Application Support directory for NullPlayer
    var applicationSupportURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("NullPlayer")
    }
    
    /// Skins directory
    var skinsDirectoryURL: URL {
        applicationSupportURL.appendingPathComponent("Skins")
    }
    
    /// Get list of available skins (name, URL)
    func availableSkins() -> [(name: String, url: URL)] {
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: skinsDirectoryURL, withIntermediateDirectories: true)

        return Self.availableClassicSkins(in: skinsDirectoryURL)
    }

    /// Import a classic `.wsz` file into a skins directory.
    /// Existing files with the same name are replaced.
    static func importClassicSkin(from sourceURL: URL, to skinsDirectoryURL: URL, fileManager: FileManager = .default) throws -> URL {
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "wsz" else {
            throw ClassicSkinImportError.unsupportedExtension(ext.isEmpty ? "(none)" : ext)
        }

        try fileManager.createDirectory(at: skinsDirectoryURL, withIntermediateDirectories: true)

        let destinationURL = skinsDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }

        return destinationURL
    }

    /// Discover available classic `.wsz` skins in a directory.
    static func availableClassicSkins(in directoryURL: URL, fileManager: FileManager = .default) -> [(name: String, url: URL)] {
        guard let contents = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        return contents
            .filter { $0.pathExtension.lowercased() == "wsz" }
            .map { (name: $0.deletingPathExtension().lastPathComponent, url: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - UI Size

    private func applyUIScaleLevelChangeIfNeeded() {
        guard !isApplyingUIScaleLevel else {
            pendingUIScaleLevel = uiScaleLevel
            return
        }

        isApplyingUIScaleLevel = true
        defer {
            isApplyingUIScaleLevel = false
            pendingUIScaleLevel = nil
        }

        repeat {
            pendingUIScaleLevel = nil
            let targetLevel = uiScaleLevel
            guard targetLevel != appliedUIScaleLevel else { continue }

            applyDoubleSize(previousScale: appliedUIScaleLevel.scaleFactor, targetLevel: targetLevel)
            appliedUIScaleLevel = targetLevel
            NotificationCenter.default.post(name: .doubleSizeDidChange, object: nil)
        } while pendingUIScaleLevel != nil && uiScaleLevel != appliedUIScaleLevel
    }

    /// Apply UI scaling to all windows.
    private func applyDoubleSize(previousScale: CGFloat = 1.0, targetLevel: UIScaleLevel? = nil) {
        let runningModernMode = isRunningModernUI
        let targetScale = (targetLevel ?? uiScaleLevel).scaleFactor
        let ratio = targetScale / previousScale

        // For modern UI, set the sizeMultiplier so all ModernSkinElements computed
        // sizes (window sizes, title bar heights, border widths, etc.) reflect the UI size.
        // This must happen BEFORE reading any ModernSkinElements sizes.
        if runningModernMode {
            ModernSkinElements.sizeMultiplier = targetScale
        }
        
        let scale = targetScale
        
        // Get main window position as anchor point
        guard let mainWindow = mainWindowController?.window else { return }
        
        // For modern UI, sizes already include the multiplier via scaleFactor.
        // For classic UI, sizes are base sizes that need explicit * scale.
        let mainTargetSize: NSSize
        if runningModernMode {
            mainTargetSize = NSSize(width: ModernSkinElements.mainWindowSize.width,
                                    height: fullMainHeightForCurrentScale())
        } else {
            mainTargetSize = NSSize(width: Skin.mainWindowSize.width * scale,
                                    height: Skin.mainWindowSize.height * scale)
        }
        
        let mainAdjustedSize = mainTargetSize
        
        // Update minSize
        mainWindow.minSize = mainAdjustedSize
        
        // Suppress windowDidMove → windowWillMove feedback during programmatic layout.
        // Animated setFrame fires windowDidMove on every display-link tick, which triggers
        // the docked-window movement loop and causes infinite recursion (stack overflow).
        isSnappingWindow = true

        // Resize main window (anchor top-left)
        var mainFrame = mainWindow.frame
        let mainTopY = mainFrame.maxY  // Keep top edge fixed
        mainFrame.size = mainAdjustedSize
        mainFrame.origin.y = mainTopY - mainAdjustedSize.height
        mainWindow.setFrame(mainFrame, display: true, animate: false)
        
        // Track the bottom edge for stacking windows below main
        var nextY = mainFrame.minY
        
        // EQ window - position below main window
        if let eqWindow = equalizerWindowController?.window {
            let eqTargetSize: NSSize
            if runningModernMode {
                eqTargetSize = NSSize(width: mainFrame.width, height: expectedMainHeightForCurrentHT(mainWindowController?.window))
            } else {
                eqTargetSize = NSSize(width: Skin.eqWindowSize.width * scale,
                                      height: Skin.eqWindowSize.height * scale)
            }
            let eqAdjustedSize = eqTargetSize
            eqWindow.minSize = eqAdjustedSize
            eqWindow.maxSize = eqAdjustedSize
            if eqWindow.isVisible {
                let eqFrame = NSRect(
                    x: mainFrame.minX,
                    y: nextY - eqAdjustedSize.height,
                    width: eqAdjustedSize.width,
                    height: eqAdjustedSize.height
                )
                eqWindow.setFrame(eqFrame, display: true, animate: false)
                nextY = eqFrame.minY
            } else {
                eqWindow.setContentSize(eqAdjustedSize)
            }
        }
        
        // Playlist - position below EQ (or main if no EQ)
        if let playlistWindow = playlistWindowController?.window {
            let baseMinSize: NSSize = runningModernMode ? ModernSkinElements.playlistMinSize : Skin.playlistMinSize
            let minHeight = runningModernMode
                ? expectedMainHeightForCurrentHT(mainWindowController?.window)
                : baseMinSize.height * scale
            let minWidth = runningModernMode
                ? ModernSkinElements.playlistMinSize.width
                : baseMinSize.width * scale
            playlistWindow.minSize = NSSize(width: minWidth, height: minHeight)
            playlistWindow.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            // Scale height proportionally
            let currentFrame = playlistWindow.frame
            let newHeight = max(minHeight, currentFrame.height * ratio)
            let newWidth = max(minWidth, currentFrame.width * ratio)

            if playlistWindow.isVisible {
                let playlistFrame = NSRect(
                    x: mainFrame.minX,
                    y: nextY - newHeight,
                    width: newWidth,
                    height: newHeight
                )
                playlistWindow.setFrame(playlistFrame, display: true, animate: false)
                nextY = playlistFrame.minY
            } else {
                playlistWindow.setContentSize(NSSize(width: newWidth, height: newHeight))
            }
        }
        
        // Spectrum window - position below playlist (or previous window)
        if let spectrumWindow = spectrumWindowController?.window {
            let baseMinSize: NSSize = runningModernMode ? ModernSkinElements.spectrumMinSize : SkinElements.SpectrumWindow.minSize
            let minHeight = runningModernMode
                ? expectedMainHeightForCurrentHT(mainWindowController?.window)
                : baseMinSize.height * scale
            let minWidth = runningModernMode
                ? ModernSkinElements.spectrumMinSize.width
                : baseMinSize.width * scale
            spectrumWindow.minSize = NSSize(width: minWidth, height: minHeight)
            spectrumWindow.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let currentFrame = spectrumWindow.frame
            let newHeight = max(minHeight, currentFrame.height * ratio)
            let newWidth = max(minWidth, currentFrame.width * ratio)
            if spectrumWindow.isVisible {
                let spectrumFrame = NSRect(
                    x: mainFrame.minX,
                    y: nextY - newHeight,
                    width: newWidth,
                    height: newHeight
                )
                spectrumWindow.setFrame(spectrumFrame, display: true, animate: false)
                nextY = spectrumFrame.minY
            } else {
                spectrumWindow.setContentSize(NSSize(width: newWidth, height: newHeight))
            }
        }

        // Waveform window - position below spectrum (or previous window)
        if let waveformWindow = waveformWindowController?.window {
            let baseMinSize: NSSize = runningModernMode ? ModernSkinElements.waveformMinSize : SkinElements.WaveformWindow.minSize
            let minHeight = runningModernMode
                ? expectedMainHeightForCurrentHT(mainWindowController?.window)
                : baseMinSize.height * scale

            let skinMinWidth: CGFloat = runningModernMode
                ? ModernSkinElements.waveformMinSize.width
                : baseMinSize.width * scale
            waveformWindow.minSize = NSSize(width: skinMinWidth, height: minHeight)
            waveformWindow.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let currentFrame = waveformWindow.frame
            let newHeight = max(minHeight, currentFrame.height * ratio)
            // Waveform width should transition with UI Size in both modes so toggling off
            // reliably returns to the prior 1x geometry.
            let newWidth = max(skinMinWidth, currentFrame.width * ratio)

            if waveformWindow.isVisible {
                let waveformFrame = NSRect(
                    x: mainFrame.minX,
                    y: nextY - newHeight,
                    width: newWidth,
                    height: newHeight
                )
                waveformWindow.setFrame(waveformFrame, display: true, animate: false)
                nextY = waveformFrame.minY
            } else {
                waveformWindow.setContentSize(NSSize(width: newWidth, height: newHeight))
            }
        }
        
        // Audio Analysis window - position below previous stack window.
        if let audioAnalysisWindow = audioAnalysisWindowController?.window {
            let baseMinSize: NSSize = runningModernMode
                ? ModernSkinElements.spectrumMinSize
                : SkinElements.SpectrumWindow.minSize
            let minHeight = runningModernMode
                ? expectedMainHeightForCurrentHT(mainWindowController?.window)
                : baseMinSize.height * scale
            let minWidth = runningModernMode
                ? ModernSkinElements.spectrumMinSize.width
                : baseMinSize.width * scale
            audioAnalysisWindow.minSize = NSSize(width: minWidth, height: minHeight)
            audioAnalysisWindow.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let currentFrame = audioAnalysisWindow.frame
            let newHeight = max(minHeight, currentFrame.height * ratio)
            let newWidth = max(minWidth, currentFrame.width * ratio)
            if audioAnalysisWindow.isVisible {
                let analysisFrame = NSRect(
                    x: mainFrame.minX,
                    y: nextY - newHeight,
                    width: newWidth,
                    height: newHeight
                )
                audioAnalysisWindow.setFrame(analysisFrame, display: true, animate: false)
                nextY = analysisFrame.minY
            } else {
                audioAnalysisWindow.setContentSize(NSSize(width: newWidth, height: newHeight))
            }
        }

        // PeppyMeter window - position below previous stack window.
        if let peppyMeterWindow = peppyMeterWindowController?.window {
            let baseMinSize: NSSize = runningModernMode
                ? ModernSkinElements.spectrumMinSize
                : SkinElements.SpectrumWindow.minSize
            let heightMultiplier = centerStackHeightMultiplier(for: .peppyMeter)
            let minHeight = runningModernMode
                ? expectedMainHeightForCurrentHT(mainWindowController?.window)
                : baseMinSize.height * scale
            let adjustedMinHeight = (minHeight * heightMultiplier).rounded()
            let minWidth = runningModernMode
                ? ModernSkinElements.spectrumMinSize.width
                : baseMinSize.width * scale
            peppyMeterWindow.minSize = NSSize(width: minWidth, height: adjustedMinHeight)
            peppyMeterWindow.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let currentFrame = peppyMeterWindow.frame
            let newHeight = max(adjustedMinHeight, currentFrame.height * ratio)
            let newWidth = max(minWidth, currentFrame.width * ratio)
            if peppyMeterWindow.isVisible {
                let meterFrame = NSRect(
                    x: mainFrame.minX,
                    y: nextY - newHeight,
                    width: newWidth,
                    height: newHeight
                )
                peppyMeterWindow.setFrame(meterFrame, display: true, animate: false)
                nextY = meterFrame.minY
            } else {
                peppyMeterWindow.setContentSize(NSSize(width: newWidth, height: newHeight))
            }
        }

        // Network Monitor window - position below previous stack window.
        if let networkMonitorWindow = networkMonitorWindowController?.window {
            let baseMinSize: NSSize = runningModernMode
                ? ModernSkinElements.spectrumMinSize
                : SkinElements.SpectrumWindow.minSize
            let heightMultiplier = centerStackHeightMultiplier(for: .networkMonitor)
            let minHeight = runningModernMode
                ? expectedMainHeightForCurrentHT(mainWindowController?.window)
                : baseMinSize.height * scale
            let adjustedMinHeight = minHeight * heightMultiplier
            let minWidth = runningModernMode
                ? ModernSkinElements.spectrumMinSize.width
                : baseMinSize.width * scale
            networkMonitorWindow.minSize = NSSize(width: minWidth, height: adjustedMinHeight)
            networkMonitorWindow.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            let currentFrame = networkMonitorWindow.frame
            let newHeight = max(adjustedMinHeight, currentFrame.height * ratio)
            let newWidth = max(minWidth, currentFrame.width * ratio)
            if networkMonitorWindow.isVisible {
                let monitorFrame = NSRect(
                    x: mainFrame.minX,
                    y: nextY - newHeight,
                    width: newWidth,
                    height: newHeight
                )
                networkMonitorWindow.setFrame(monitorFrame, display: true, animate: false)
                nextY = monitorFrame.minY
            } else {
                networkMonitorWindow.setContentSize(NSSize(width: newWidth, height: newHeight))
            }
        }

        // Side windows - match the vertical stack height and reposition
        let stackTopY = mainFrame.maxY
        let stackHeight = stackTopY - nextY
        
        if let plexWindow = plexBrowserWindowController?.window, plexWindow.isVisible {
            let newWidth = plexWindow.frame.width * ratio
            let plexFrame = NSRect(
                x: mainFrame.maxX,
                y: nextY,
                width: newWidth,
                height: stackHeight
            )
            plexWindow.setFrame(plexFrame, display: true, animate: false)
        }

        if let projectMWindow = projectMWindowController?.window, projectMWindow.isVisible {
            let newWidth = projectMWindow.frame.width * ratio
            let projectMFrame = NSRect(
                x: mainFrame.minX - (projectMWindow.frame.width * ratio),
                y: nextY,
                width: newWidth,
                height: stackHeight
            )
            projectMWindow.setFrame(projectMFrame, display: true, animate: false)
        }

        isSnappingWindow = false

        // Force every affected window to redraw its skin at the new scale. Classic views are
        // layer-backed with `.onSetNeedsDisplay`, so resizing alone just stretches/leaves the
        // cached bitmap (a stale "ghost" of the old size) until something marks them dirty —
        // switching Spaces and back used to be the only thing that cleared it. Redraw explicitly.
        for controller in [mainWindowController, equalizerWindowController, playlistWindowController,
                           spectrumWindowController, waveformWindowController, audioAnalysisWindowController,
                           peppyMeterWindowController,
                           networkMonitorWindowController,
                           plexBrowserWindowController, projectMWindowController] {
            guard let window = controller?.window, window.isVisible,
                  let contentView = window.contentView else { continue }
            contentView.markSubtreeForDisplayAndLayout()
            window.displayIfNeeded()
        }
    }

    private func applyAlwaysOnTop() {
        let level: NSWindow.Level = isAlwaysOnTop ? .floating : .normal
        
        // Apply to all app windows
        mainWindowController?.window?.level = level
        equalizerWindowController?.window?.level = level
        playlistWindowController?.window?.level = level
        plexBrowserWindowController?.window?.level = level
        videoPlayerWindowController?.window?.level = level
        projectMWindowController?.window?.level = level
        spectrumWindowController?.window?.level = level
        audioAnalysisWindowController?.window?.level = level
        peppyMeterWindowController?.window?.level = level
        networkMonitorWindowController?.window?.level = level
        waveformWindowController?.window?.level = level
        if compactWindowEnabled {
            compactWindowController?.window?.level = level
        }
    }
    
    /// Apply always on top level to a single window (used when showing windows)
    private func applyAlwaysOnTopToWindow(_ window: NSWindow?) {
        guard let window = window else { return }
        window.level = isAlwaysOnTop ? .floating : .normal
    }
    
    /// Bring all visible app windows to front (called when any app window gets focus).
    /// If possible, keep the active window on top so detached-window overlap feels consistent.
    func bringAllWindowsToFront(keepingWindowOnTop preferredTopWindow: NSWindow? = nil) {
        // Order all visible windows to front without making them key.
        // Keep a predictable base order, then re-raise the active window at the end.
        let windows: [NSWindow?] = [
            mainWindowController?.window,
            equalizerWindowController?.window,
            playlistWindowController?.window,
            spectrumWindowController?.window,
            audioAnalysisWindowController?.window,
            peppyMeterWindowController?.window,
            networkMonitorWindowController?.window,
            waveformWindowController?.window,
            videoPlayerWindowController?.window,
            projectMWindowController?.window,
            plexBrowserWindowController?.window
        ]

        let topWindow = preferredTopWindow ?? NSApp.keyWindow

        for window in windows {
            if let window = window, window.isVisible, window !== topWindow {
                window.orderFront(nil)
            }
        }

        if let topWindow = topWindow, topWindow.isVisible {
            topWindow.orderFront(nil)
        }
    }
    
    /// Find visible center-stack windows that are docked below the main window
    /// (directly or transitively), using the current dock threshold.
    private func dockedCenterStackWindowsBelowMain(mainFrame: NSRect) -> [NSWindow] {
        let subWindows = [equalizerWindowController?.window,
                          playlistWindowController?.window,
                          spectrumWindowController?.window,
                          audioAnalysisWindowController?.window,
                          peppyMeterWindowController?.window,
                          networkMonitorWindowController?.window,
                          waveformWindowController?.window].compactMap { $0 }
        var docked: [NSWindow] = []
        var frontier: [NSRect] = [mainFrame]

        while !frontier.isEmpty {
            let referenceFrame = frontier.removeFirst()
            for win in subWindows {
                guard win.isVisible, !docked.contains(win) else { continue }
                let vertGap = abs(win.frame.maxY - referenceFrame.minY)
                let horizOverlap = win.frame.minX < referenceFrame.maxX && win.frame.maxX > referenceFrame.minX
                if vertGap <= dockThreshold && horizOverlap {
                    docked.append(win)
                    frontier.append(win.frame)
                }
            }
        }

        return docked
    }

    /// Calculate the bounding box of the docked vertical center stack
    /// (main + only windows docked below main).
    private func verticalStackBounds() -> NSRect {
        guard let mainFrame = mainWindowController?.window?.frame else { return .zero }

        let topY = mainFrame.maxY
        var bottomY = mainFrame.minY
        let x = mainFrame.minX
        let width = mainFrame.width

        // Only include center windows that are currently docked below main.
        for dockedWindow in dockedCenterStackWindowsBelowMain(mainFrame: mainFrame) {
            bottomY = min(bottomY, dockedWindow.frame.minY)
        }

        return NSRect(x: x, y: round(bottomY), width: width, height: round(topY) - round(bottomY))
    }

    /// Calculate the bounding box of the full cluster of windows docked to main
    /// (all directions), optionally excluding the window being positioned.
    private func windowClusterBounds(excluding excludedWindow: NSWindow? = nil) -> NSRect {
        guard let mainWindow = mainWindowController?.window else { return .zero }
        var bounds = mainWindow.frame
        for win in findDockedWindows(to: mainWindow) {
            guard win !== excludedWindow else { continue }
            bounds = bounds.union(win.frame)
        }
        return bounds
    }

    enum CenterStackWindowKind {
        case equalizer
        case playlist
        case spectrum
        case waveform
        case audioAnalysis
        case peppyMeter
        case networkMonitor
    }

    private func centerStackWindowKind(for window: NSWindow) -> CenterStackWindowKind? {
        if window === equalizerWindowController?.window { return .equalizer }
        if window === playlistWindowController?.window { return .playlist }
        if window === spectrumWindowController?.window { return .spectrum }
        if window === waveformWindowController?.window { return .waveform }
        if window === audioAnalysisWindowController?.window { return .audioAnalysis }
        if window === peppyMeterWindowController?.window { return .peppyMeter }
        if window === networkMonitorWindowController?.window { return .networkMonitor }
        return nil
    }

    private func fullMainHeightForCurrentScale() -> CGFloat {
        ModernSkinElements.baseMainSize.height * ModernSkinElements.scaleFactor
    }

    private func rightDockedSideFrame(for window: NSWindow, width: CGFloat) -> NSRect? {
        guard let mainWindow = mainWindowController?.window else { return nil }
        let stackBounds = verticalStackBounds()
        guard stackBounds != .zero else { return nil }

        let clusterBounds = windowClusterBounds(excluding: window)
        let rightEdgeX = clusterBounds != .zero ? clusterBounds.maxX : mainWindow.frame.maxX
        let mainActualHeight = mainWindow.frame.height
        let stackHasMultipleWindows = stackBounds.height > mainActualHeight + 1

        if stackHasMultipleWindows {
            return NSRect(x: rightEdgeX, y: stackBounds.minY, width: width, height: stackBounds.height)
        }

        let defaultHeight = defaultSideWindowHeight(mainFrame: mainWindow.frame)
        return NSRect(
            x: rightEdgeX,
            y: mainWindow.frame.maxY - defaultHeight,
            width: width,
            height: defaultHeight
        )
    }

    private func leftDockedSideFrame(for window: NSWindow, width: CGFloat) -> NSRect? {
        guard let mainWindow = mainWindowController?.window else { return nil }
        let stackBounds = verticalStackBounds()
        guard stackBounds != .zero else { return nil }

        let clusterBounds = windowClusterBounds(excluding: window)
        let leftEdgeX = clusterBounds != .zero ? clusterBounds.minX : mainWindow.frame.minX
        let mainActualHeight = mainWindow.frame.height
        let stackHasMultipleWindows = stackBounds.height > mainActualHeight + 1

        if stackHasMultipleWindows {
            return NSRect(x: leftEdgeX - width, y: stackBounds.minY, width: width, height: stackBounds.height)
        }

        let defaultHeight = defaultSideWindowHeight(mainFrame: mainWindow.frame)
        return NSRect(
            x: leftEdgeX - width,
            y: mainWindow.frame.maxY - defaultHeight,
            width: width,
            height: defaultHeight
        )
    }

    private func sideFrameIsRightDockedToCurrentStack(_ frame: NSRect) -> Bool {
        let stackBounds = verticalStackBounds()
        guard stackBounds != .zero else { return false }
        let touchesRightEdge = abs(frame.minX - stackBounds.maxX) <= dockThreshold
        let overlapsStackVertically = frame.minY < stackBounds.maxY && frame.maxY > stackBounds.minY
        return touchesRightEdge && overlapsStackVertically
    }

    private func sideFrameIsLeftDockedToCurrentStack(_ frame: NSRect) -> Bool {
        let stackBounds = verticalStackBounds()
        guard stackBounds != .zero else { return false }
        let touchesLeftEdge = abs(frame.maxX - stackBounds.minX) <= dockThreshold
        let overlapsStackVertically = frame.minY < stackBounds.maxY && frame.maxY > stackBounds.minY
        return touchesLeftEdge && overlapsStackVertically
    }

    private func refitDockedPlexBrowserToVerticalStack() {
        guard let window = plexBrowserWindowController?.window, window.isVisible else { return }
        guard sideFrameIsRightDockedToCurrentStack(window.frame) else { return }
        guard let frame = rightDockedSideFrame(for: window, width: window.frame.width),
              frame != window.frame else { return }

        let previousSnappingState = isSnappingWindow
        isSnappingWindow = true
        window.setFrame(frame, display: true, animate: false)
        isSnappingWindow = previousSnappingState
    }

    private func refitDockedProjectMToVerticalStack() {
        guard let window = projectMWindowController?.window, window.isVisible else { return }
        guard sideFrameIsLeftDockedToCurrentStack(window.frame) else { return }
        guard let frame = leftDockedSideFrame(for: window, width: window.frame.width),
              frame != window.frame else { return }

        let previousSnappingState = isSnappingWindow
        isSnappingWindow = true
        window.setFrame(frame, display: true, animate: false)
        isSnappingWindow = previousSnappingState
    }

    /// Height multiplier for a center-stack window's default/minimum height.
    /// PeppyMeter is taller than single-height windows, but not double-height: its bundled assets are landscape.
    private func centerStackHeightMultiplier(for kind: CenterStackWindowKind) -> CGFloat {
        kind == .peppyMeter ? 1.75 : 1
    }

    private func peppyMeterHeight(for baseHeight: CGFloat) -> CGFloat {
        (baseHeight * centerStackHeightMultiplier(for: .peppyMeter)).rounded()
    }

    /// Height for a restored PeppyMeter frame. Collapses the previous double-height default
    /// down to the current 1.75x landscape floor, but otherwise honors a user-stretched height
    /// so the window remembers its size like the other stack windows.
    private func restoredPeppyMeterHeight(saved: CGFloat, floor: CGFloat, legacyDoubleHeight: CGFloat) -> CGFloat {
        if abs(saved - legacyDoubleHeight) <= 2 { return floor }
        return max(floor, saved)
    }

    private func targetCenterStackHeight(for kind: CenterStackWindowKind,
                                         currentHeight: CGFloat,
                                         titleBarDelta: CGFloat,
                                         preservePlaylistContentHeight: Bool) -> CGFloat {
        let baseTarget = expectedMainHeightForCurrentHT(mainWindowController?.window)
        let target = kind == .peppyMeter
            ? peppyMeterHeight(for: baseTarget)
            : baseTarget * centerStackHeightMultiplier(for: kind)
        guard kind == .playlist || kind == .waveform else { return target }
        guard preservePlaylistContentHeight else { return target }
        let adjusted = hideTitleBars ? (currentHeight - titleBarDelta) : (currentHeight + titleBarDelta)
        return max(target, adjusted)
    }

    private func applyCenterStackSizingConstraints(_ window: NSWindow, kind: CenterStackWindowKind) {
        guard isRunningModernUI, let mainWindow = mainWindowController?.window else { return }
        let targetWidth = mainWindow.frame.width
        let targetHeight = expectedMainHeightForCurrentHT(mainWindow)
        switch kind {
        case .equalizer:
            window.minSize = NSSize(width: targetWidth, height: targetHeight)
            window.maxSize = NSSize(width: targetWidth, height: targetHeight)
        case .spectrum:
            window.minSize = NSSize(width: ModernSkinElements.spectrumMinSize.width, height: targetHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        case .playlist:
            window.minSize = NSSize(width: ModernSkinElements.playlistMinSize.width, height: targetHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        case .waveform:
            window.minSize = NSSize(width: ModernSkinElements.waveformMinSize.width, height: targetHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        case .audioAnalysis:
            // Matches the center-stack width; stretchable in height like spectrum/playlist.
            window.minSize = NSSize(width: ModernSkinElements.spectrumMinSize.width, height: targetHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        case .peppyMeter:
            // Matches the center-stack width; stretchable above its landscape meter floor.
            window.minSize = NSSize(
                width: ModernSkinElements.spectrumMinSize.width,
                height: peppyMeterHeight(for: targetHeight)
            )
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        case .networkMonitor:
            // Matches the center-stack width; stretchable above its single-height floor.
            window.minSize = NSSize(width: ModernSkinElements.spectrumMinSize.width, height: targetHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    private func applyDefaultCenterStackFrameForCurrentHT(_ window: NSWindow, kind: CenterStackWindowKind) {
        guard isRunningModernUI, let mainWindow = mainWindowController?.window else { return }
        var frame = window.frame
        let topY = frame.maxY
        frame.size.width = mainWindow.frame.width
        frame.size.height = targetCenterStackHeight(for: kind,
                                                    currentHeight: frame.height,
                                                    titleBarDelta: 0,
                                                    preservePlaylistContentHeight: false)
        frame.origin.y = topY - frame.size.height
        frame.origin.x = mainWindow.frame.minX
        window.setFrame(frame, display: true)
    }

    private func applyRestoredCenterStackFrame(_ frame: NSRect, to window: NSWindow, kind: CenterStackWindowKind) {
        let normalizedFrame = normalizedCenterStackRestoredFrame(frame, kind: kind)
        withProgrammaticWindowFrameChange {
            window.setFrame(normalizedFrame, display: true)
        }
    }

    private func modernMinimumRestoredWidth(for kind: CenterStackWindowKind) -> CGFloat {
        switch kind {
        case .equalizer:
            return mainWindowController?.window?.frame.width ?? ModernSkinElements.mainWindowSize.width
        case .playlist:
            return ModernSkinElements.playlistMinSize.width
        case .spectrum, .audioAnalysis, .peppyMeter, .networkMonitor:
            return ModernSkinElements.spectrumMinSize.width
        case .waveform:
            return ModernSkinElements.waveformMinSize.width
        }
    }

    static func normalizedModernCenterStackRestoredFrame(
        _ frame: NSRect,
        kind: CenterStackWindowKind,
        mainWidth: CGFloat,
        minimumWidth: CGFloat,
        targetHeight: CGFloat,
        peppyMeterFloor: CGFloat,
        peppyMeterLegacyDoubleHeight: CGFloat
    ) -> NSRect {
        var normalized = frame
        if kind == .equalizer {
            normalized.size.width = mainWidth
        } else {
            normalized.size.width = max(minimumWidth, normalized.width)
        }

        let topY = normalized.maxY
        switch kind {
        case .equalizer:
            normalized.size.height = targetHeight
        case .playlist, .spectrum, .waveform, .audioAnalysis, .networkMonitor:
            normalized.size.height = max(targetHeight, normalized.height)
        case .peppyMeter:
            normalized.size.height = abs(normalized.height - peppyMeterLegacyDoubleHeight) <= 2
                ? peppyMeterFloor
                : max(peppyMeterFloor, normalized.height)
        }
        normalized.origin.y = topY - normalized.size.height
        return normalized
    }

    static func normalizedClassicNetworkMonitorRestoredFrame(
        _ frame: NSRect,
        minimumHeight: CGFloat
    ) -> NSRect {
        var normalized = frame
        let topY = normalized.maxY
        normalized.size.height = max(minimumHeight, normalized.height)
        normalized.origin.y = topY - normalized.size.height
        return normalized
    }

    private func normalizedCenterStackRestoredFrame(_ frame: NSRect, kind: CenterStackWindowKind) -> NSRect {
        guard isRunningModernUI else {
            guard kind == .peppyMeter || kind == .networkMonitor else { return frame }
            var normalized = frame
            let topY = normalized.maxY
            if kind == .peppyMeter {
                normalized.size.height = restoredPeppyMeterHeight(
                    saved: normalized.height,
                    floor: (SkinElements.PeppyMeterWindow.windowSize.height * classicScaleMultiplier).rounded(),
                    legacyDoubleHeight: (SkinElements.SpectrumWindow.windowSize.height * 2 * classicScaleMultiplier).rounded()
                )
            } else {
                return Self.normalizedClassicNetworkMonitorRestoredFrame(
                    frame,
                    minimumHeight: SkinElements.SpectrumWindow.minSize.height * classicScaleMultiplier
                )
            }
            normalized.origin.y = topY - normalized.size.height
            return normalized
        }
        let target = expectedMainHeightForCurrentHT(mainWindowController?.window)
        return Self.normalizedModernCenterStackRestoredFrame(
            frame,
            kind: kind,
            mainWidth: mainWindowController?.window?.frame.width ?? ModernSkinElements.mainWindowSize.width,
            minimumWidth: modernMinimumRestoredWidth(for: kind),
            targetHeight: target,
            peppyMeterFloor: peppyMeterHeight(for: target),
            peppyMeterLegacyDoubleHeight: (target * 2).rounded()
        )
    }

    /// Baseline center-stack height in modern UI.
    private func expectedMainHeightForCurrentHT(_ mainWindow: NSWindow?) -> CGFloat {
        guard isRunningModernUI else { return mainWindow?.frame.height ?? 0 }
        return fullMainHeightForCurrentScale()
    }

    /// Default side-window height when only the main window is visible.
    /// Uses the center-stack baseline height in modern UI.
    private func defaultSideWindowHeight(mainFrame: NSRect) -> CGFloat {
        guard isRunningModernUI else { return mainFrame.height * 4 }
        return expectedMainHeightForCurrentHT(mainWindowController?.window) * 4
    }

    /// Classic-only runtime self-heal for near-docked center-stack gaps/width drift.
    /// Keeps modern mode untouched and only adjusts windows that match classic near-dock rules.
    @discardableResult
    private func tightenClassicCenterStackIfNeeded() -> Bool {
        guard !isRunningModernUI else { return false }
        guard !isTighteningClassicCenterStack else { return false }
        guard let mainWindow = mainWindowController?.window else { return false }

        let scale = uiScaleLevel.scaleFactor
        let equalizerWindow = equalizerWindowController?.window
        let playlistWindow = playlistWindowController?.window
        let spectrumWindow = spectrumWindowController?.window
        let waveformWindow = waveformWindowController?.window
        let audioAnalysisWindow = audioAnalysisWindowController?.window
        let peppyMeterWindow = peppyMeterWindowController?.window
        let networkMonitorWindow = networkMonitorWindowController?.window

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: mainWindow.frame,
            equalizerFrame: (equalizerWindow?.isVisible == true) ? equalizerWindow?.frame : nil,
            playlistFrame: (playlistWindow?.isVisible == true) ? playlistWindow?.frame : nil,
            spectrumFrame: (spectrumWindow?.isVisible == true) ? spectrumWindow?.frame : nil,
            waveformFrame: (waveformWindow?.isVisible == true) ? waveformWindow?.frame : nil,
            audioAnalysisFrame: (audioAnalysisWindow?.isVisible == true) ? audioAnalysisWindow?.frame : nil,
            peppyMeterFrame: (peppyMeterWindow?.isVisible == true) ? peppyMeterWindow?.frame : nil,
            networkMonitorFrame: (networkMonitorWindow?.isVisible == true) ? networkMonitorWindow?.frame : nil,
            scale: scale
        )

        guard repaired.repaired else { return false }

        isTighteningClassicCenterStack = true
        let previousSnappingState = isSnappingWindow
        isSnappingWindow = true
        defer {
            isSnappingWindow = previousSnappingState
            isTighteningClassicCenterStack = false
        }

        if repaired.mainFrame != mainWindow.frame {
            mainWindow.setFrame(repaired.mainFrame, display: true, animate: false)
        }
        if let equalizerWindow,
           equalizerWindow.isVisible,
           let repairedFrame = repaired.equalizerFrame,
           repairedFrame != equalizerWindow.frame {
            equalizerWindow.setFrame(repairedFrame, display: true, animate: false)
        }
        if let playlistWindow,
           playlistWindow.isVisible,
           let repairedFrame = repaired.playlistFrame,
           repairedFrame != playlistWindow.frame {
            playlistWindow.setFrame(repairedFrame, display: true, animate: false)
        }
        if let spectrumWindow,
           spectrumWindow.isVisible,
           let repairedFrame = repaired.spectrumFrame,
           repairedFrame != spectrumWindow.frame {
            spectrumWindow.setFrame(repairedFrame, display: true, animate: false)
        }
        if let waveformWindow,
           waveformWindow.isVisible,
           let repairedFrame = repaired.waveformFrame,
           repairedFrame != waveformWindow.frame {
            waveformWindow.setFrame(repairedFrame, display: true, animate: false)
        }
        if let audioAnalysisWindow,
           audioAnalysisWindow.isVisible,
           let repairedFrame = repaired.audioAnalysisFrame,
           repairedFrame != audioAnalysisWindow.frame {
            audioAnalysisWindow.setFrame(repairedFrame, display: true, animate: false)
        }
        if let peppyMeterWindow,
           peppyMeterWindow.isVisible,
           let repairedFrame = repaired.peppyMeterFrame,
           repairedFrame != peppyMeterWindow.frame {
            peppyMeterWindow.setFrame(repairedFrame, display: true, animate: false)
        }
        if let networkMonitorWindow,
           networkMonitorWindow.isVisible,
           let repairedFrame = repaired.networkMonitorFrame,
           repairedFrame != networkMonitorWindow.frame {
            networkMonitorWindow.setFrame(repairedFrame, display: true, animate: false)
        }

        return true
    }
    
    /// Reset all windows to their default positions
    /// Only stacks currently visible windows with no gaps, preserving their current sizes
    func snapToDefaultPositions() {
        let defaults = UserDefaults.standard
        
        // Get screen for positioning - use the screen the main window is on, or fall back to main screen
        // Use full screen frame (not visibleFrame) so windows aren't constrained by menu bar/dock
        guard let screen = mainWindowController?.window?.screen ?? NSScreen.main else { return }
        let screenFrame = screen.frame
        
        // Use current main window size (preserves user scaling)
        let mainSize = mainWindowController?.window?.frame.size ??
            (isModernUIEnabled ? ModernSkinElements.mainWindowSize : Skin.mainWindowSize)
        let mainFrame = NSRect(
            x: screenFrame.midX - mainSize.width / 2,
            y: screenFrame.midY - mainSize.height / 2,
            width: mainSize.width,
            height: mainSize.height
        )
        
        // Build a tight vertical stack of only visible windows below main
        // Each window preserves its current size and aligns left with main
        var nextY = mainFrame.minY  // Bottom of previous window in stack
        
        // Collect frames for visible stack windows
        // (order: EQ, Playlist, Spectrum, Waveform, Audio Analysis).
        var eqFrame: NSRect?
        var playlistFrame: NSRect?
        var spectrumFrame: NSRect?
        
        if let eqWindow = equalizerWindowController?.window, eqWindow.isVisible {
            let h = eqWindow.frame.height
            let w = eqWindow.frame.width
            nextY -= h
            eqFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }
        
        if let playlistWindow = playlistWindowController?.window, playlistWindow.isVisible {
            let h = playlistWindow.frame.height
            let w = playlistWindow.frame.width
            nextY -= h
            playlistFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }
        
        if let spectrumWindow = spectrumWindowController?.window, spectrumWindow.isVisible {
            let h = spectrumWindow.frame.height
            let w = spectrumWindow.frame.width
            nextY -= h
            spectrumFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }

        var waveformFrame: NSRect?
        if let waveformWindow = waveformWindowController?.window, waveformWindow.isVisible {
            let h = waveformWindow.frame.height
            let w = waveformWindow.frame.width
            nextY -= h
            waveformFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }

        var audioAnalysisFrame: NSRect?
        if let audioAnalysisWindow = audioAnalysisWindowController?.window, audioAnalysisWindow.isVisible {
            let h = audioAnalysisWindow.frame.height
            let w = audioAnalysisWindow.frame.width
            nextY -= h
            audioAnalysisFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }

        var peppyMeterFrame: NSRect?
        if let peppyMeterWindow = peppyMeterWindowController?.window, peppyMeterWindow.isVisible {
            let h = peppyMeterWindow.frame.height
            let w = peppyMeterWindow.frame.width
            nextY -= h
            peppyMeterFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }

        var networkMonitorFrame: NSRect?
        if let networkMonitorWindow = networkMonitorWindowController?.window, networkMonitorWindow.isVisible {
            let h = networkMonitorWindow.frame.height
            let w = networkMonitorWindow.frame.width
            nextY -= h
            networkMonitorFrame = NSRect(x: mainFrame.minX, y: nextY, width: w, height: h)
        }

        // Side windows span the full stack height
        let stackTopY = mainFrame.maxY
        let stackBottomY = nextY
        let stackHeight = stackTopY - stackBottomY
        
        var browserFrame: NSRect?
        var projectMFrame: NSRect?
        
        if let plexWindow = plexBrowserWindowController?.window, plexWindow.isVisible {
            let w = plexWindow.frame.width
            browserFrame = NSRect(x: mainFrame.maxX, y: stackBottomY, width: w, height: stackHeight)
        }
        
        if let projectMWindow = projectMWindowController?.window, projectMWindow.isVisible {
            let w = projectMWindow.frame.width
            projectMFrame = NSRect(x: mainFrame.minX - w, y: stackBottomY, width: w, height: stackHeight)
        }
        
        // Clear any saved positions (windows will be positioned relative to main on open)
        defaults.removeObject(forKey: "MainWindowFrame")
        defaults.removeObject(forKey: "EqualizerWindowFrame")
        defaults.removeObject(forKey: "PlaylistWindowFrame")
        defaults.removeObject(forKey: "PlexBrowserWindowFrame")
        defaults.removeObject(forKey: "ProjectMWindowFrame")
        defaults.removeObject(forKey: "VideoPlayerWindowFrame")
        defaults.removeObject(forKey: "ArtVisualizerWindowFrame")
        defaults.removeObject(forKey: "SpectrumWindowFrame")
        defaults.removeObject(forKey: "WaveformWindowFrame")
        defaults.removeObject(forKey: "PeppyMeterWindowFrame")
        defaults.removeObject(forKey: "NetworkMonitorWindowFrame")
        
        // Disable snapping during programmatic frame changes to prevent interference
        isSnappingWindow = true
        defer { isSnappingWindow = false }
        
        // Apply positions to visible windows
        if let mainWindow = mainWindowController?.window {
            mainWindow.setFrame(mainFrame, display: true, animate: false)
        }
        if let frame = eqFrame, let window = equalizerWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = playlistFrame, let window = playlistWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = spectrumFrame, let window = spectrumWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = waveformFrame, let window = waveformWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = audioAnalysisFrame, let window = audioAnalysisWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = peppyMeterFrame, let window = peppyMeterWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = networkMonitorFrame, let window = networkMonitorWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = browserFrame, let window = plexBrowserWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let frame = projectMFrame, let window = projectMWindowController?.window {
            window.setFrame(frame, display: true, animate: false)
        }
        if let videoWindow = videoPlayerWindowController?.window, videoWindow.isVisible {
            videoWindow.center()
        }
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
    }
    
    // MARK: - Window Snapping & Docking

    /// Pure timing function: determines drag mode from hold duration.
    /// - Parameters:
    ///   - holdStart: The CACurrentMediaTime() value captured at mouseDown, or nil if unavailable.
    ///   - currentTime: The current CACurrentMediaTime() value.
    ///   - threshold: The hold duration threshold in seconds.
    /// - Returns: `.separate` if elapsed time is below threshold; `.group` otherwise.
    static func determineDragMode(
        holdStart: CFTimeInterval?,
        currentTime: CFTimeInterval,
        threshold: TimeInterval,
        isWindowLayoutLocked: Bool = false
    ) -> DragMode {
        if isWindowLayoutLocked { return .group }
        guard let start = holdStart else { return .group }
        return (currentTime - start) < threshold ? .separate : .group
    }

    /// Decide whether a move callback should be treated as an active user drag.
    /// Programmatic moves (startup restore, snapping, frame repair) must not arm drag state.
    static func shouldTreatMoveAsDrag(
        holdPrimed: Bool,
        pressedMouseButtons: Int
    ) -> Bool {
        // A move counts as an interactive drag only if a drag was primed by the window's own
        // mouse-down handler, or the left mouse button is physically held right now.
        //
        // We deliberately do NOT key off `currentEventType` alone: `NSApp.currentEvent` can be a
        // stale `.leftMouseDown` from the click that opened a window via a menu/toolbar item, long
        // after the button was released. Programmatic positioning `setFrame`s during window open or
        // docking then emit `windowDidMove`, and treating those as drags starts a phantom drag that
        // never ends — leaving the cluster tinted in drag-highlight and the visualization window
        // render-suspended until a real click finishes the imaginary drag.
        if holdPrimed { return true }
        if (pressedMouseButtons & 0x1) != 0 { return true } // Left mouse button physically held.
        return false
    }

    /// Whether a window drag is actually in progress right now. Consumers of the
    /// `windowDragDidBegin` / `windowDragDidEnd` notifications (e.g. `VisualizationGLView`,
    /// which suspends rendering during drags) use this to resync their suspended state and
    /// recover if those notifications ever arrive unbalanced.
    ///
    /// A real interactive drag always has the left mouse button held down. Programmatic frame
    /// changes (window open/dock/restore) can leave `draggingWindow` set without a matching
    /// drag-end — a phantom "stuck drag". Requiring the button to be pressed rejects that stale
    /// state so a just-opened visualization window doesn't strand itself drag-suspended.
    var isWindowDragInProgress: Bool {
        draggingWindow != nil && (NSEvent.pressedMouseButtons & 0x1) != 0
    }

    /// Called when a window drag begins
    /// - Parameters:
    ///   - window: The window being dragged
    ///   - fromTitleBar: Whether the drag originated from the title bar. Currently unused by the drag
    ///     logic; retained so call sites can document drag origin and for future title-bar-specific behavior.
    func windowWillStartDragging(_ window: NSWindow, fromTitleBar: Bool = false) {
        let usingPrimedHold = (primedDragWindow === window && holdStartTime != nil)
        draggingWindow = window
        installDragMouseUpMonitorIfNeeded()
        if !usingPrimedHold {
            holdStartTime = CACurrentMediaTime()
        }
        primedDragWindow = nil
        dragMode = .pending

        // Find all windows that are docked to this window
        dockedWindowsToMove = findDockedWindows(to: window)

        // Store relative offsets from dragging window's origin (prevents drift during fast movement)
        dockedWindowOffsets.removeAll()
        dockedWindowOriginalOrigins.removeAll()
        let dragOrigin = window.frame.origin
        for dockedWindow in dockedWindowsToMove {
            let offset = NSPoint(
                x: dockedWindow.frame.origin.x - dragOrigin.x,
                y: dockedWindow.frame.origin.y - dragOrigin.y
            )
            dockedWindowOffsets[ObjectIdentifier(dockedWindow)] = offset
            dockedWindowOriginalOrigins[ObjectIdentifier(dockedWindow)] = dockedWindow.frame.origin
        }

        // Highlight connected peers and dragged window so user can see full moving set
        if !dockedWindowsToMove.isEmpty {
            var highlightSet = Set(dockedWindowsToMove)
            highlightSet.insert(window)
            postConnectedWindowHighlight(highlightSet)
            highlightWasPosted = true
        }
        NotificationCenter.default.post(name: .windowDragDidBegin, object: nil)
    }

    /// Prime hold timing at mouseDown without starting drag movement yet.
    /// Used by views that begin movement on first mouseDragged (e.g. HT on in library view).
    func windowWillPrimeDragging(_ window: NSWindow) {
        guard draggingWindow == nil else { return }
        installDragMouseUpMonitorIfNeeded()
        primedDragWindow = window
        holdStartTime = CACurrentMediaTime()
        dragMode = .pending
    }

    /// Cancel a primed hold when mouseUp occurs without an actual window drag.
    func windowDidCancelDragPrime(_ window: NSWindow) {
        guard draggingWindow == nil, primedDragWindow === window else { return }
        primedDragWindow = nil
        holdStartTime = nil
        dragMode = .pending
        removeDragMouseUpMonitor()
    }
    
    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === draggingWindow else { return }
        windowDidFinishDragging(closingWindow)
    }

    @objc private func handleWindowWillMiniaturize(_ notification: Notification) {
        guard let miniaturizingWindow = notification.object as? NSWindow else { return }
        miniaturizingWindowIds.insert(ObjectIdentifier(miniaturizingWindow))

        // Minimize should never leave drag/group state armed.
        if draggingWindow === miniaturizingWindow {
            windowDidFinishDragging(miniaturizingWindow)
        } else if primedDragWindow === miniaturizingWindow {
            primedDragWindow = nil
            holdStartTime = nil
            dragMode = .pending
            if highlightWasPosted {
                postConnectedWindowHighlight([])
                highlightWasPosted = false
            }
        }
    }

    @objc private func handleWindowDidMiniaturize(_ notification: Notification) {
        guard let miniaturizedWindow = notification.object as? NSWindow else { return }
        miniaturizingWindowIds.remove(ObjectIdentifier(miniaturizedWindow))
    }

    /// Called when a window drag ends
    func windowDidFinishDragging(_ window: NSWindow) {
        guard draggingWindow === window else { return }
        draggingWindow = nil
        removeDragMouseUpMonitor()
        primedDragWindow = nil
        dockedWindowsToMove.removeAll()
        dockedWindowOffsets.removeAll()
        dockedWindowOriginalOrigins.removeAll()
        holdStartTime = nil
        dragMode = .pending
        if highlightWasPosted {
            postConnectedWindowHighlight([])
            highlightWasPosted = false
        }
        NotificationCenter.default.post(name: .windowDragDidEnd, object: nil)
        _ = tightenClassicCenterStackIfNeeded()
        postLayoutChangeNotification()
        updateDockedChildWindows()
    }

    private func installDragMouseUpMonitorIfNeeded() {
        guard dragMouseUpMonitor == nil else { return }
        dragMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            if let dragging = self.draggingWindow {
                self.windowDidFinishDragging(dragging)
            } else if let primed = self.primedDragWindow {
                self.windowDidCancelDragPrime(primed)
            }
            return event
        }
    }

    private func removeDragMouseUpMonitor() {
        guard let monitor = dragMouseUpMonitor else { return }
        NSEvent.removeMonitor(monitor)
        dragMouseUpMonitor = nil
    }
    
    /// Safely apply snapped position to a window without triggering feedback loop
    func applySnappedPosition(_ window: NSWindow, to position: NSPoint) {
        // Re-entrant move callbacks can arrive synchronously while setFrameOrigin is in flight.
        // Ignore them so we don't recursively set the same frame until the stack overflows.
        guard !isSnappingWindow else { return }
        guard position != window.frame.origin else { return }
        let previousSnappingState = isSnappingWindow
        isSnappingWindow = true
        defer { isSnappingWindow = previousSnappingState }
        window.setFrameOrigin(position)
    }

    /// Run a programmatic frame mutation without letting windowDidMove feed back into
    /// docking/drag state. Animated fullscreen transitions emit move callbacks during
    /// the animation; those are not user drags.
    func withProgrammaticWindowFrameChange(animationDuration: TimeInterval = 0, _ work: () -> Void) {
        let previousSnappingState = isSnappingWindow
        programmaticFrameChangeToken += 1
        let token = programmaticFrameChangeToken
        isSnappingWindow = true
        work()
        guard animationDuration > 0 else {
            isSnappingWindow = previousSnappingState
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) { [weak self] in
            guard let self, self.programmaticFrameChangeToken == token else { return }
            self.isSnappingWindow = previousSnappingState
        }
    }
    
    /// Called when a window is being dragged - handle snapping and move docked windows
    func windowWillMove(_ window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        // The Compact Mode window is a floating, status-item-anchored window positioned
        // explicitly by CompactModeWindowController. It must never participate in snapping or
        // docking against the regular window set — when extra regular windows are open, snapping
        // pulls it off its menu-bar anchor. Always accept its programmatic origin verbatim.
        if window === compactWindowController?.window {
            return newOrigin
        }

        // Programmatic frame changes should never re-enter snap logic.
        if isSnappingWindow {
            return newOrigin
        }

        // Intercept minimize button/animation movement from drag-group logic.
        if miniaturizingWindowIds.contains(ObjectIdentifier(window)) {
            return newOrigin
        }

        let holdPrimedForWindow = (primedDragWindow === window && holdStartTime != nil)
        let treatAsDrag = WindowManager.shouldTreatMoveAsDrag(
            holdPrimed: holdPrimedForWindow,
            pressedMouseButtons: Int(NSEvent.pressedMouseButtons)
        )

        // Ignore non-drag moves for drag-state purposes (e.g. startup/applyFrame).
        // Also clear stale primed/highlight state if a no-button move arrives.
        if !treatAsDrag {
            if draggingWindow === window {
                windowDidFinishDragging(window)
            } else {
                if holdPrimedForWindow {
                    primedDragWindow = nil
                    holdStartTime = nil
                    dragMode = .pending
                }
                if highlightWasPosted {
                    postConnectedWindowHighlight([])
                    highlightWasPosted = false
                }
            }
            return applySnapping(for: window, to: newOrigin)
        }
        
        // Ignore all window movement while we're programmatically repositioning docked windows.
        // This covers both the docked windows themselves and windows AppKit moves automatically
        // as child windows of a docked window (e.g. the dragging window is a child of main).
        if isMovingDockedWindows {
            return newOrigin
        }

        // If this window is a child of the currently-dragging window, AppKit moved it
        // automatically as part of the parent's setFrameOrigin — don't treat it as an
        // independent drag or we'll corrupt the drag state (draggingWindow, offsets).
        if let dragging = draggingWindow, dragging !== window,
           dragging.childWindows?.contains(window) == true {
            return newOrigin
        }

        // If this move callback is for a peer in the active drag group, ignore it.
        // Peers can report late/asynchronous move notifications during fast group drags.
        if let dragging = draggingWindow, dragging !== window,
           dockedWindowsToMove.contains(where: { $0 === window }) {
            return newOrigin
        }

        // If this is a new drag, find docked windows
        if draggingWindow !== window {
            let hadPrimedHold = (primedDragWindow === window && holdStartTime != nil)
            windowWillStartDragging(window)
            // windowWillStartDragging sets holdStartTime to now, so determineDragMode would see
            // elapsed ≈ 0 → .separate. Override to .group: mid-flight drag is always group move.
            if !hadPrimedHold {
                dragMode = .group
            }
        }

        // NEW — determine mode on first drag movement
        if dragMode == .pending {
            let mode = WindowManager.determineDragMode(
                holdStart: holdStartTime,
                currentTime: CACurrentMediaTime(),
                threshold: holdThreshold,
                isWindowLayoutLocked: isWindowLayoutLocked
            )
            dragMode = mode
            if mode == .separate {
                // Restore peers to their pre-drag positions before breaking the dock
                isMovingDockedWindows = true
                for dockedWindow in dockedWindowsToMove {
                    if let origin = dockedWindowOriginalOrigins[ObjectIdentifier(dockedWindow)] {
                        dockedWindow.setFrameOrigin(origin)
                    }
                }
                isMovingDockedWindows = false
                dockedWindowsToMove.removeAll()
                dockedWindowOffsets.removeAll()
                dockedWindowOriginalOrigins.removeAll()
                if highlightWasPosted {
                    postConnectedWindowHighlight([])
                    highlightWasPosted = false
                }
            }
        }
        
        // Apply snap to screen edges and other windows
        let snappedOrigin = applySnapping(for: window, to: newOrigin)
        
        // Move all docked windows using stored offsets (prevents drift during fast movement).
        // Child windows of the dragging window are skipped here — AppKit will move them
        // synchronously when the parent's setFrameOrigin is called, which keeps them
        // in the same display frame as the parent and prevents visual tearing.
        if !dockedWindowsToMove.isEmpty {
            var autoMovedChildWindowIds = Set(window.childWindows?.map { ObjectIdentifier($0) } ?? [])
            // Any parent window moved in this tick will bring its child windows along automatically.
            // Skip explicit repositioning for those children to avoid duplicate moves and transient gaps.
            for parent in dockedWindowsToMove {
                for child in parent.childWindows ?? [] {
                    autoMovedChildWindowIds.insert(ObjectIdentifier(child))
                }
            }

            isMovingDockedWindows = true
            for dockedWindow in dockedWindowsToMove {
                guard !autoMovedChildWindowIds.contains(ObjectIdentifier(dockedWindow)) else { continue }
                if let offset = dockedWindowOffsets[ObjectIdentifier(dockedWindow)] {
                    // Use stored offset from drag start to maintain exact relative position
                    let newDockedOrigin = NSPoint(
                        x: snappedOrigin.x + offset.x,
                        y: snappedOrigin.y + offset.y
                    )
                    dockedWindow.setFrameOrigin(newDockedOrigin)
                }
            }
            isMovingDockedWindows = false
        }

        let now = CACurrentMediaTime()
        if now - lastDragLayoutNotificationTime >= 1.0 / 30.0 {
            lastDragLayoutNotificationTime = now
            postLayoutChangeNotification()
        }

        return snappedOrigin
    }
    
    /// Calculate the bounding box of the dragging window and all its docked windows
    /// - Parameters:
    ///   - window: The window being dragged
    ///   - newOrigin: The proposed new origin for the dragging window
    /// - Returns: The bounding rectangle of the entire window group
    private func calculateGroupBounds(for window: NSWindow, at newOrigin: NSPoint) -> NSRect {
        var bounds = NSRect(origin: newOrigin, size: window.frame.size)
        
        // Include all docked windows in the bounds calculation
        for dockedWindow in dockedWindowsToMove {
            if let offset = dockedWindowOffsets[ObjectIdentifier(dockedWindow)] {
                let dockedOrigin = NSPoint(
                    x: newOrigin.x + offset.x,
                    y: newOrigin.y + offset.y
                )
                let dockedFrame = NSRect(origin: dockedOrigin, size: dockedWindow.frame.size)
                bounds = bounds.union(dockedFrame)
            }
        }
        
        return bounds
    }
    
    /// Check if the window group spans multiple screens
    /// - Parameter groupBounds: The bounding rectangle of the entire group
    /// - Returns: true if the group is currently crossing monitor boundaries
    private func groupSpansMultipleScreens(_ groupBounds: NSRect) -> Bool {
        var containingScreen: NSScreen? = nil
        
        for screen in NSScreen.screens {
            let intersection = groupBounds.intersection(screen.frame)
            if !intersection.isEmpty {
                if containingScreen != nil {
                    // Group intersects multiple screens
                    return true
                }
                containingScreen = screen
            }
        }
        
        return false
    }
    
    /// Check if snapping would cause any docked window to end up on a different screen
    /// - Parameters:
    ///   - mainOrigin: The proposed origin for the main/dragging window after snapping
    ///   - mainSize: The size of the main/dragging window
    /// - Returns: true if any docked window would end up on a different screen than main
    private func wouldSnapCauseScreenSeparation(mainOrigin: NSPoint, mainSize: NSSize) -> Bool {
        guard !dockedWindowsToMove.isEmpty else { return false }
        
        let mainFrame = NSRect(origin: mainOrigin, size: mainSize)
        
        // Find which screen the main window would be on after snapping
        var mainScreen: NSScreen? = nil
        var maxIntersection: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = mainFrame.intersection(screen.frame)
            let area = intersection.width * intersection.height
            if area > maxIntersection {
                maxIntersection = area
                mainScreen = screen
            }
        }
        
        guard let targetScreen = mainScreen else { return false }
        
        // Check if any docked window would end up primarily on a different screen
        for dockedWindow in dockedWindowsToMove {
            guard let offset = dockedWindowOffsets[ObjectIdentifier(dockedWindow)] else { continue }
            
            let dockedOrigin = NSPoint(
                x: mainOrigin.x + offset.x,
                y: mainOrigin.y + offset.y
            )
            let dockedFrame = NSRect(origin: dockedOrigin, size: dockedWindow.frame.size)
            
            // Find which screen this docked window would be on
            var dockedScreen: NSScreen? = nil
            var dockedMaxIntersection: CGFloat = 0
            for screen in NSScreen.screens {
                let intersection = dockedFrame.intersection(screen.frame)
                let area = intersection.width * intersection.height
                if area > dockedMaxIntersection {
                    dockedMaxIntersection = area
                    dockedScreen = screen
                }
            }
            
            // If docked window would be on a different screen, snapping would cause separation
            if dockedScreen !== targetScreen {
                return true
            }
        }
        
        return false
    }
    
    /// Apply snapping to other windows and screen edges
    private func applySnapping(for window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
        var snappedX = newOrigin.x
        var snappedY = newOrigin.y
        let frame = NSRect(origin: newOrigin, size: window.frame.size)
        
        // Track best snaps (closest distance)
        var bestHorizontalSnap: (distance: CGFloat, value: CGFloat)? = nil
        var bestVerticalSnap: (distance: CGFloat, value: CGFloat)? = nil
        
        // Helper to check if ranges overlap (with tolerance for snapping)
        func rangesOverlap(_ min1: CGFloat, _ max1: CGFloat, _ min2: CGFloat, _ max2: CGFloat) -> Bool {
            return max1 > min2 - snapThreshold && min1 < max2 + snapThreshold
        }
        
        // Track if we're dragging a group (for screen separation checks)
        let isDraggingGroup = !dockedWindowsToMove.isEmpty
        let windowSize = window.frame.size
        
        // Snap to screen edges (with special handling for groups to prevent separation)
        if let screen = window.screen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            
            // Left edge to screen left
            let leftDist = abs(frame.minX - screenFrame.minX)
            if leftDist < snapThreshold {
                let candidateOrigin = NSPoint(x: screenFrame.minX, y: newOrigin.y)
                // Only snap if it won't cause docked windows to end up on different screen
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestHorizontalSnap == nil || leftDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (leftDist, screenFrame.minX)
                    }
                }
            }
            
            // Right edge to screen right
            let rightDist = abs(frame.maxX - screenFrame.maxX)
            if rightDist < snapThreshold {
                let candidateX = screenFrame.maxX - frame.width
                let candidateOrigin = NSPoint(x: candidateX, y: newOrigin.y)
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestHorizontalSnap == nil || rightDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (rightDist, candidateX)
                    }
                }
            }
            
            // Bottom edge to screen bottom
            let bottomDist = abs(frame.minY - screenFrame.minY)
            if bottomDist < snapThreshold {
                let candidateOrigin = NSPoint(x: newOrigin.x, y: screenFrame.minY)
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestVerticalSnap == nil || bottomDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (bottomDist, screenFrame.minY)
                    }
                }
            }
            
            // Top edge to screen top
            let topDist = abs(frame.maxY - screenFrame.maxY)
            if topDist < snapThreshold {
                let candidateY = screenFrame.maxY - frame.height
                let candidateOrigin = NSPoint(x: newOrigin.x, y: candidateY)
                if !isDraggingGroup || !wouldSnapCauseScreenSeparation(mainOrigin: candidateOrigin, mainSize: windowSize) {
                    if bestVerticalSnap == nil || topDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (topDist, candidateY)
                    }
                }
            }
        }
        
        // All windows can snap to dockable windows plus the Library browser.
        let windowsToSnapTo = snapTargetWindows()
        for otherWindow in windowsToSnapTo {
            guard otherWindow != window else { continue }
            // Skip docked windows as they're moving with us
            guard !dockedWindowsToMove.contains(otherWindow) else { continue }
            
            let otherFrame = otherWindow.frame
            
            // Check if windows overlap or are close vertically (for horizontal snapping)
            let verticallyClose = rangesOverlap(frame.minY, frame.maxY, otherFrame.minY, otherFrame.maxY)
            
            // Check if windows overlap or are close horizontally (for vertical snapping)
            let horizontallyClose = rangesOverlap(frame.minX, frame.maxX, otherFrame.minX, otherFrame.maxX)
            
            // HORIZONTAL SNAPPING (only if vertically aligned)
            if verticallyClose {
                // Priority 1: Edge-to-edge docking (most intuitive)
                // Snap right edge to left edge (dock side by side)
                let rightToLeftDist = abs(frame.maxX - otherFrame.minX)
                if rightToLeftDist < snapThreshold {
                    if bestHorizontalSnap == nil || rightToLeftDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (rightToLeftDist, otherFrame.minX - frame.width)
                    }
                }
                
                // Snap left edge to right edge (dock side by side)
                let leftToRightDist = abs(frame.minX - otherFrame.maxX)
                if leftToRightDist < snapThreshold {
                    if bestHorizontalSnap == nil || leftToRightDist < bestHorizontalSnap!.distance {
                        bestHorizontalSnap = (leftToRightDist, otherFrame.maxX)
                    }
                }
                
                // Priority 2: Edge alignment (only if not already snapping to edge-to-edge)
                // Snap left edges together
                let leftToLeftDist = abs(frame.minX - otherFrame.minX)
                if leftToLeftDist < snapThreshold && leftToLeftDist > 0 {
                    if bestHorizontalSnap == nil || leftToLeftDist < bestHorizontalSnap!.distance * 0.8 {
                        // Only use alignment snap if significantly closer (0.8 factor)
                        bestHorizontalSnap = (leftToLeftDist, otherFrame.minX)
                    }
                }
                
                // Snap right edges together
                let rightToRightDist = abs(frame.maxX - otherFrame.maxX)
                if rightToRightDist < snapThreshold && rightToRightDist > 0 {
                    if bestHorizontalSnap == nil || rightToRightDist < bestHorizontalSnap!.distance * 0.8 {
                        bestHorizontalSnap = (rightToRightDist, otherFrame.maxX - frame.width)
                    }
                }
            }
            
            // VERTICAL SNAPPING (only if horizontally aligned)
            if horizontallyClose {
                // Priority 1: Edge-to-edge docking
                // Snap bottom edge to top edge (stack below)
                let bottomToTopDist = abs(frame.minY - otherFrame.maxY)
                if bottomToTopDist < snapThreshold {
                    if bestVerticalSnap == nil || bottomToTopDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (bottomToTopDist, otherFrame.maxY)
                    }
                }
                
                // Snap top edge to bottom edge (stack above)
                let topToBottomDist = abs(frame.maxY - otherFrame.minY)
                if topToBottomDist < snapThreshold {
                    if bestVerticalSnap == nil || topToBottomDist < bestVerticalSnap!.distance {
                        bestVerticalSnap = (topToBottomDist, otherFrame.minY - frame.height)
                    }
                }
                
                // Priority 2: Edge alignment
                // Snap top edges together
                let topToTopDist = abs(frame.maxY - otherFrame.maxY)
                if topToTopDist < snapThreshold && topToTopDist > 0 {
                    if bestVerticalSnap == nil || topToTopDist < bestVerticalSnap!.distance * 0.8 {
                        bestVerticalSnap = (topToTopDist, otherFrame.maxY - frame.height)
                    }
                }
                
                // Snap bottom edges together
                let bottomToBottomDist = abs(frame.minY - otherFrame.minY)
                if bottomToBottomDist < snapThreshold && bottomToBottomDist > 0 {
                    if bestVerticalSnap == nil || bottomToBottomDist < bestVerticalSnap!.distance * 0.8 {
                        bestVerticalSnap = (bottomToBottomDist, otherFrame.minY)
                    }
                }
            }
        }
        
        // Apply best snaps.
        //
        // Classic windows are opaque and square-cornered, so their docked edge must land
        // exactly on the neighbor's edge. `bestVerticalSnap.value` / `bestHorizontalSnap.value`
        // are edge-derived (e.g. `otherFrame.minY - frame.height`), so using them directly makes
        // the shared edges coincide. Rounding the snapped *origin* to an integer while the
        // neighbor's edge sits on a fractional pixel — main's origin becomes fractional after any
        // free drag on a 1x display — leaves a gap of `frac(neighborEdge)` that shows the desktop
        // as a ~1px seam between the two opaque frames (issue #364). Only the drag-snap path has
        // this bug: default-open (`positionSubWindow`) and restore
        // (`normalizedCenterStackRestoredFrame`) already place the docked edge edge-exact.
        //
        // Modern/metal keep the integer round: their windows are translucent with rounded corners,
        // and a fractional origin would rasterize those corners across pixel boundaries and soften
        // them on 1x displays. Modern's seam is a separate mechanism (translucent background exposed
        // by seamless docking) handled by the joined-edge content bleed in each view's
        // `contentAreaRect()`, not by this snap.
        let pixelSnapOrigin = isRunningModernUI
        if let hSnap = bestHorizontalSnap {
            snappedX = pixelSnapOrigin ? round(hSnap.value) : hSnap.value
        }
        if let vSnap = bestVerticalSnap {
            snappedY = pixelSnapOrigin ? round(vSnap.value) : vSnap.value
        }

        // Hard-clamp to screen top: macOS enforces this on setFrameOrigin to keep the
        // title bar visible. If we don't clamp first, the main window ends up at a
        // different Y than the docked windows we already repositioned → they detach.
        // Also clamp so that docked windows above the dragging window don't go off-screen:
        // when a lower window is dragged upward, its docked peers above (positive Y offset)
        // get placed at snappedY + offset.y and can exceed the screen top.
        if let screen = window.screen ?? NSScreen.main {
            var maxAllowedY = screen.visibleFrame.maxY - frame.height
            for dockedWindow in dockedWindowsToMove {
                if let offset = dockedWindowOffsets[ObjectIdentifier(dockedWindow)], offset.y > 0 {
                    let clampForDocked = screen.visibleFrame.maxY - offset.y - dockedWindow.frame.height
                    maxAllowedY = min(maxAllowedY, clampForDocked)
                }
            }
            snappedY = min(snappedY, maxAllowedY)
        }

        return NSPoint(x: snappedX, y: snappedY)
    }
    
    /// Find all windows that are docked (touching) the given window
    /// Any connected group of 2+ eligible windows moves together, regardless of main-window membership.
    func findDockedWindows(to window: NSWindow) -> [NSWindow] {
        let candidateWindows = groupMovableWindows()
        guard candidateWindows.contains(where: { $0 === window }) else { return [] }
        
        var dockedWindows: [NSWindow] = []
        var windowsToCheck: [NSWindow] = [window]
        var checkedWindows: Set<ObjectIdentifier> = [ObjectIdentifier(window)]
        
        // Use BFS to find all transitively docked windows among group-movable candidates.
        while !windowsToCheck.isEmpty {
            let currentWindow = windowsToCheck.removeFirst()
            
            for otherWindow in candidateWindows {
                let otherId = ObjectIdentifier(otherWindow)
                if checkedWindows.contains(otherId) { continue }
                
                if areWindowsDocked(currentWindow, otherWindow) {
                    dockedWindows.append(otherWindow)
                    windowsToCheck.append(otherWindow)
                    checkedWindows.insert(otherId)
                }
            }
        }
        
        return dockedWindows
    }
    
    /// Check if two windows are docked (touching edges)
    private func areWindowsDocked(_ window1: NSWindow, _ window2: NSWindow) -> Bool {
        let frame1 = window1.frame
        let frame2 = window2.frame
        
        // Check if windows are touching horizontally (side by side)
        let horizontallyAligned = (frame1.minY < frame2.maxY && frame1.maxY > frame2.minY)
        let hGap1 = abs(frame1.maxX - frame2.minX)
        let hGap2 = abs(frame1.minX - frame2.maxX)
        let touchingHorizontally = horizontallyAligned && (hGap1 <= dockThreshold || hGap2 <= dockThreshold)
        
        // Check if windows are touching vertically (stacked)
        let verticallyAligned = (frame1.minX < frame2.maxX && frame1.maxX > frame2.minX)
        let vGap1 = abs(frame1.maxY - frame2.minY)
        let vGap2 = abs(frame1.minY - frame2.maxY)
        let touchingVertically = verticallyAligned && (vGap1 <= dockThreshold || vGap2 <= dockThreshold)
        
        return touchingHorizontally || touchingVertically
    }
    
    /// Public entry point for window controllers to post a layout change notification.
    /// Always clears per-cycle caches first so all observers receive fresh occlusion data.
    /// Use this instead of posting windowLayoutDidChange directly.
    func postWindowLayoutDidChange() {
        postLayoutChangeNotification()
    }

    /// Post a windowLayoutDidChange notification, clearing per-cycle caches first.
    private func postLayoutChangeNotification() {
        adjacencyCache.removeAll(keepingCapacity: true)
        edgeOcclusionSegmentsCache.removeAll(keepingCapacity: true)
        sharpCornersCache.removeAll(keepingCapacity: true)
        NotificationCenter.default.post(name: .windowLayoutDidChange, object: nil)
    }

    /// Post a connectedWindowHighlightDidChange notification.
    /// - Parameter windows: The windows to highlight. Pass an empty set to clear all highlights.
    private func postConnectedWindowHighlight(_ windows: Set<NSWindow>) {
        NotificationCenter.default.post(
            name: .connectedWindowHighlightDidChange,
            object: nil,
            userInfo: ["highlightedWindows": windows]
        )
    }

    /// Compute joined edge intervals in window-local coordinates for modern seamless border rendering.
    /// Uses a per-notification-cycle cache so multiple observers share one computation.
    func computeEdgeOcclusionSegments(for window: NSWindow) -> EdgeOcclusionSegments {
        guard isModernUIEnabled else { return .empty }
        let key = ObjectIdentifier(window)
        if let cached = edgeOcclusionSegmentsCache[key] { return cached }
        let result = _computeEdgeOcclusionSegmentsImpl(for: window)
        edgeOcclusionSegmentsCache[key] = result
        return result
    }

    /// Compute which edges of a window are adjacent to another visible managed window.
    /// Uses a per-notification-cycle cache so multiple observers share one computation.
    func computeAdjacentEdges(for window: NSWindow) -> AdjacentEdges {
        guard isModernUIEnabled else { return [] }
        let key = ObjectIdentifier(window)
        if let cached = adjacencyCache[key] { return cached }
        let segments = computeEdgeOcclusionSegments(for: window)
        let result = adjacentEdges(from: segments)
        adjacencyCache[key] = result
        return result
    }

    private func adjacentEdges(from segments: EdgeOcclusionSegments) -> AdjacentEdges {
        var edges: AdjacentEdges = []
        if !segments.top.isEmpty { edges.insert(.top) }
        if !segments.bottom.isEmpty { edges.insert(.bottom) }
        if !segments.left.isEmpty { edges.insert(.left) }
        if !segments.right.isEmpty { edges.insert(.right) }
        return edges
    }

    /// Returns a frame suitable for edge-occlusion calculations.
    ///
    /// During active drag-group moves, windows can briefly report mixed frame
    /// timing. Derive group members from the dragging window + stored offset.
    private func edgeOcclusionFrame(for window: NSWindow) -> NSRect {
        guard let dragging = draggingWindow else { return window.frame }
        if window === dragging { return dragging.frame }
        if let offset = dockedWindowOffsets[ObjectIdentifier(window)] {
            return Self.dragAdjustedFrame(
                windowFrame: window.frame,
                draggingFrame: dragging.frame,
                offsetFromDragging: offset
            )
        }
        return window.frame
    }

    /// Pure helper for deriving a drag-group member frame from the dragging
    /// window's frame plus stored relative offset. Used by runtime logic and tests.
    static func dragAdjustedFrame(windowFrame: NSRect, draggingFrame: NSRect, offsetFromDragging: NSPoint) -> NSRect {
        NSRect(
            origin: NSPoint(
                x: draggingFrame.origin.x + offsetFromDragging.x,
                y: draggingFrame.origin.y + offsetFromDragging.y
            ),
            size: windowFrame.size
        )
    }

    private func _computeEdgeOcclusionSegmentsImpl(for window: NSWindow) -> EdgeOcclusionSegments {
        let frame = edgeOcclusionFrame(for: window)
        let otherFrames = allWindows().compactMap { other in
            other === window ? nil : edgeOcclusionFrame(for: other)
        }
        return Self.computeEdgeOcclusionSegments(frame: frame, otherFrames: otherFrames, dockThreshold: dockThreshold)
    }

    /// Pure geometry helper for interval-based edge occlusion. Used by runtime logic and unit tests.
    static func computeEdgeOcclusionSegments(frame: NSRect, otherFrames: [NSRect], dockThreshold: CGFloat) -> EdgeOcclusionSegments {
        var top: [ClosedRange<CGFloat>] = []
        var bottom: [ClosedRange<CGFloat>] = []
        var left: [ClosedRange<CGFloat>] = []
        var right: [ClosedRange<CGFloat>] = []

        let width = frame.width
        let height = frame.height

        for other in otherFrames {
            let hOverlapMin = max(frame.minX, other.minX)
            let hOverlapMax = min(frame.maxX, other.maxX)
            let hOverlap = hOverlapMax > hOverlapMin

            let vOverlapMin = max(frame.minY, other.minY)
            let vOverlapMax = min(frame.maxY, other.maxY)
            let vOverlap = vOverlapMax > vOverlapMin

            if hOverlap {
                if abs(frame.maxY - other.minY) <= dockThreshold {
                    let start = max(0, hOverlapMin - frame.minX)
                    let end = min(width, hOverlapMax - frame.minX)
                    if end > start { top.append(start...end) }
                }
                if abs(frame.minY - other.maxY) <= dockThreshold {
                    let start = max(0, hOverlapMin - frame.minX)
                    let end = min(width, hOverlapMax - frame.minX)
                    if end > start { bottom.append(start...end) }
                }
            }

            if vOverlap {
                if abs(frame.maxX - other.minX) <= dockThreshold {
                    let start = max(0, vOverlapMin - frame.minY)
                    let end = min(height, vOverlapMax - frame.minY)
                    if end > start { right.append(start...end) }
                }
                if abs(frame.minX - other.maxX) <= dockThreshold {
                    let start = max(0, vOverlapMin - frame.minY)
                    let end = min(height, vOverlapMax - frame.minY)
                    if end > start { left.append(start...end) }
                }
            }
        }

        return EdgeOcclusionSegments(
            top: mergeOcclusionIntervals(top),
            bottom: mergeOcclusionIntervals(bottom),
            left: mergeOcclusionIntervals(left),
            right: mergeOcclusionIntervals(right)
        )
    }

    private static func mergeOcclusionIntervals(_ intervals: [ClosedRange<CGFloat>], epsilon: CGFloat = 0.5) -> [ClosedRange<CGFloat>] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { lhs, rhs in
            if lhs.lowerBound == rhs.lowerBound { return lhs.upperBound < rhs.upperBound }
            return lhs.lowerBound < rhs.lowerBound
        }

        var merged: [ClosedRange<CGFloat>] = [sorted[0]]
        for interval in sorted.dropFirst() {
            guard let last = merged.last else { continue }
            if interval.lowerBound <= last.upperBound + epsilon {
                let combined = last.lowerBound...max(last.upperBound, interval.upperBound)
                merged[merged.count - 1] = combined
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// Returns a CACornerMask indicating which corners should be sharp
    /// because an adjacent window actually reaches/covers that corner.
    /// Uses a per-notification-cycle cache so multiple observers share one computation.
    func computeSharpCorners(for window: NSWindow) -> CACornerMask {
        guard isModernUIEnabled else { return [] }
        let key = ObjectIdentifier(window)
        if let cached = sharpCornersCache[key] { return cached }
        let result = _computeSharpCornersImpl(for: window)
        sharpCornersCache[key] = result
        return result
    }

    private func _computeSharpCornersImpl(for window: NSWindow) -> CACornerMask {
        // Sharp corners apply only inside the center stack
        // (main/EQ/playlist/spectrum/waveform).
        // Side windows (library/projectM) keep rounded corners and do not force
        // sharp corners on center-stack windows where they meet.
        guard isDockableWindow(window) else { return [] }

        var sharp: CACornerMask = []
        let f = window.frame
        let t = dockThreshold
        for other in allWindows() where other !== window {
            guard isDockableWindow(other) else { continue }
            let o = other.frame
            let vOverlap = f.minY < o.maxY && f.maxY > o.minY
            let hOverlap = f.minX < o.maxX && f.maxX > o.minX
            // Window to the right
            if abs(f.maxX - o.minX) <= t && vOverlap {
                if o.minY <= f.minY + t { sharp.insert(.layerMaxXMinYCorner) }
                if o.maxY >= f.maxY - t { sharp.insert(.layerMaxXMaxYCorner) }
            }
            // Window to the left
            if abs(f.minX - o.maxX) <= t && vOverlap {
                if o.minY <= f.minY + t { sharp.insert(.layerMinXMinYCorner) }
                if o.maxY >= f.maxY - t { sharp.insert(.layerMinXMaxYCorner) }
            }
            // Window above (macOS Y-up: o.minY ≈ f.maxY)
            if abs(f.maxY - o.minY) <= t && hOverlap {
                if o.minX <= f.minX + t { sharp.insert(.layerMinXMaxYCorner) }
                if o.maxX >= f.maxX - t { sharp.insert(.layerMaxXMaxYCorner) }
            }
            // Window below
            if abs(f.minY - o.maxY) <= t && hOverlap {
                if o.minX <= f.minX + t { sharp.insert(.layerMinXMinYCorner) }
                if o.maxX >= f.maxX - t { sharp.insert(.layerMaxXMinYCorner) }
            }
        }
        return sharp
    }

    /// Get all managed windows
    private func allWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let w = mainWindowController?.window, w.isVisible { windows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible { windows.append(w) }
        if let w = equalizerWindowController?.window, w.isVisible { windows.append(w) }
        if let w = plexBrowserWindowController?.window, w.isVisible { windows.append(w) }
        if let w = videoPlayerWindowController?.window, w.isVisible { windows.append(w) }
        if let w = projectMWindowController?.window, w.isVisible { windows.append(w) }
        if let w = spectrumWindowController?.window, w.isVisible { windows.append(w) }
        if let w = audioAnalysisWindowController?.window, w.isVisible { windows.append(w) }
        if let w = peppyMeterWindowController?.window, w.isVisible { windows.append(w) }
        if let w = networkMonitorWindowController?.window, w.isVisible { windows.append(w) }
        if let w = waveformWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }

    /// Get windows that participate in docking/snapping together (classic skin windows)
    private func dockableWindows() -> [NSWindow] {
        var windows: [NSWindow] = []
        if let w = mainWindowController?.window, w.isVisible { windows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible { windows.append(w) }
        if let w = equalizerWindowController?.window, w.isVisible { windows.append(w) }
        if let w = spectrumWindowController?.window, w.isVisible { windows.append(w) }
        if let w = audioAnalysisWindowController?.window, w.isVisible { windows.append(w) }
        if let w = peppyMeterWindowController?.window, w.isVisible { windows.append(w) }
        if let w = networkMonitorWindowController?.window, w.isVisible { windows.append(w) }
        if let w = waveformWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }

    /// Get windows that can be used as snapping targets.
    /// Includes Library browser and ProjectM for side-docking.
    private func snapTargetWindows() -> [NSWindow] {
        var windows = dockableWindows()
        if let w = plexBrowserWindowController?.window, w.isVisible { windows.append(w) }
        if let w = projectMWindowController?.window, w.isVisible { windows.append(w) }
        return windows
    }

    /// Get windows that can participate in connected group dragging.
    /// Grouping is connection-based and does not depend on the main window being part of the group.
    private func groupMovableWindows() -> [NSWindow] {
        snapTargetWindows()
    }
    
    /// Check if a window participates in docking
    private func isDockableWindow(_ window: NSWindow) -> Bool {
        return window === mainWindowController?.window ||
               window === playlistWindowController?.window ||
               window === equalizerWindowController?.window ||
               window === spectrumWindowController?.window ||
               window === audioAnalysisWindowController?.window ||
               window === peppyMeterWindowController?.window ||
               window === networkMonitorWindowController?.window ||
               window === waveformWindowController?.window
    }
    
    /// Get all visible windows
    func visibleWindows() -> [NSWindow] {
        return allWindows()
    }

    // MARK: - Mode-Dependent Window Teardown / Rebuild

    /// Controllers whose window layer depends on the active UI mode (classic vs. modern).
    /// This is the single source of truth for `teardownModeDependentWindows()`.
    ///
    /// It is intentionally **separate** from `allWindows()` / `dockableWindows()` /
    /// `snapTargetWindows()` — those encode docking/snap *capabilities* and are not
    /// interchangeable with "things to rebuild on a UI switch". The mode-independent
    /// `videoPlayerWindowController` and the DEBUG console are deliberately excluded:
    /// the video player must survive a switch (closing it stops playback / casts).
    private var modeDependentWindowControllers: [ModeDependentWindow] {
        [mainWindowController,
         playlistWindowController,
         equalizerWindowController,
         plexBrowserWindowController,
         projectMWindowController,
         spectrumWindowController,
         audioAnalysisWindowController,
         peppyMeterWindowController,
         networkMonitorWindowController,
         waveformWindowController].compactMap { $0 }
    }

    /// Tear down only the mode-dependent window layer, leaving audio, casting, the video
    /// player, and all application-level services untouched. After this returns, every
    /// mode-dependent controller is `nil` and its window is closed; callers rebuild via
    /// `recreateModeDependentLayout(_:)` (or the individual `show*()` paths).
    ///
    /// This is the central primitive proven by the DEBUG "Recreate Windows" action and
    /// reused by the live UI switch (PR4). It does **not** touch Compact Mode or the
    /// `modernUIEnabled` flag — that orchestration belongs to the caller.
    func teardownModeDependentWindows() {
        NSLog("WindowManager: teardownModeDependentWindows — begin")

        // End any in-flight drag so monitors and drag state never reference dead windows.
        if let dragging = draggingWindow {
            windowDidFinishDragging(dragging)
        }
        removeDragMouseUpMonitor()

        // 1 + 2: order out, then let each controller/root view release its own resources
        // (cancel tasks/timers, stop render loops, unregister observers + audio consumers).
        for controller in modeDependentWindowControllers {
            controller.window?.orderOut(nil)
            controller.prepareForUITeardown()
        }

        // Detach docked child-window relationships before closing so AppKit does not retain
        // soon-to-be-dead windows through the parent.
        if let mainWindow = mainWindowController?.window {
            for child in mainWindow.childWindows ?? [] {
                mainWindow.removeChildWindow(child)
            }
        }

        // 3: close() then nil the mode-dependent controllers. Preserve the video player.
        mainWindowController?.window?.close()
        mainWindowController = nil
        playlistWindowController?.window?.close()
        playlistWindowController = nil
        equalizerWindowController?.window?.close()
        equalizerWindowController = nil
        plexBrowserWindowController?.window?.close()
        plexBrowserWindowController = nil
        // The close() above fires windowWillClose, which caches the old-mode library frame.
        // Discard it so a classic frame can't leak onto the modern controller (or vice-versa);
        // classic/modern differ in coordinates/size. An open library that must survive the
        // switch is repositioned explicitly via recreateModeDependentLayout's snapshot frame.
        lastPlexBrowserFrame = nil
        lastPlexBrowserFrameWasDocked = false
        projectMWindowController?.window?.close()
        projectMWindowController = nil
        lastProjectMFrame = nil
        lastProjectMFrameWasDocked = false
        spectrumWindowController?.window?.close()
        spectrumWindowController = nil
        audioAnalysisWindowController?.window?.close()
        audioAnalysisWindowController = nil
        peppyMeterWindowController?.window?.close()
        peppyMeterWindowController = nil
        networkMonitorWindowController?.window?.close()
        networkMonitorWindowController = nil
        waveformWindowController?.window?.close()
        waveformWindowController = nil

        // 4: clear drag/snap/dock state so stale ObjectIdentifier keys can't survive.
        draggingWindow = nil
        primedDragWindow = nil
        dockedWindowsToMove.removeAll()
        dockedWindowOffsets.removeAll()
        dockedWindowOriginalOrigins.removeAll()
        holdStartTime = nil
        dragMode = .pending
        highlightWasPosted = false

        // 5: synchronously flush the ObjectIdentifier-keyed geometry caches (otherwise new
        // controllers can collide with dead entries — these are normally only cleared on
        // layout-change notifications).
        adjacencyCache.removeAll(keepingCapacity: true)
        edgeOcclusionSegmentsCache.removeAll(keepingCapacity: true)
        sharpCornersCache.removeAll(keepingCapacity: true)

        NSLog("WindowManager: teardownModeDependentWindows — complete")
    }

    /// Visibility + frame of a single mode-dependent window, captured before teardown.
    private struct UIWindowSnapshot {
        let visible: Bool
        let frame: NSRect
        /// Normal frame for position memory. Stores the full window frame for Library window
        /// restoration; nil for other window types.
        var normalFrame: NSRect?
    }

    /// Snapshot of the mode-dependent window layer, used to restore which windows were open
    /// (and where) after a teardown/rebuild.
    private struct ModeDependentLayoutSnapshot {
        var main: UIWindowSnapshot?
        var playlist: UIWindowSnapshot?
        var equalizer: UIWindowSnapshot?
        var library: UIWindowSnapshot?
        var projectM: UIWindowSnapshot?
        var spectrum: UIWindowSnapshot?
        var audioAnalysis: UIWindowSnapshot?
        var peppyMeter: UIWindowSnapshot?
        var networkMonitor: UIWindowSnapshot?
        var waveform: UIWindowSnapshot?
        /// Live ProjectM preset index, carried across the rebuild so the visualization stays on the
        /// exact preset the user was viewing rather than reverting to the saved startup default.
        var projectMPresetIndex: Int?
    }

    private func captureModeDependentLayout() -> ModeDependentLayoutSnapshot {
        func snap(_ controller: ModeDependentWindow?, normalFrame: NSRect? = nil) -> UIWindowSnapshot? {
            guard let window = controller?.window else { return nil }
            return UIWindowSnapshot(
                visible: window.isVisible,
                frame: window.frame,
                normalFrame: normalFrame
            )
        }
        return ModeDependentLayoutSnapshot(
            main: snap(mainWindowController),
            playlist: snap(playlistWindowController),
            equalizer: snap(equalizerWindowController),
            // Library stores its position frame for restoration after the rebuild.
            library: snap(plexBrowserWindowController, normalFrame: plexBrowserWindowController?.frameForPositionMemory),
            projectM: snap(projectMWindowController),
            spectrum: snap(spectrumWindowController),
            audioAnalysis: snap(audioAnalysisWindowController),
            peppyMeter: snap(peppyMeterWindowController),
            networkMonitor: snap(networkMonitorWindowController),
            waveform: snap(waveformWindowController),
            projectMPresetIndex: restorableProjectMPresetIndex()
        )
    }

    private func restorableProjectMPresetIndex() -> Int? {
        guard let controller = projectMWindowController,
              controller.isProjectMAvailable else { return nil }
        let count = controller.presetCount
        let index = controller.currentPresetIndex
        guard count > 0, index >= 0, index < count else { return nil }
        return index
    }

    /// Rebuild the mode-dependent windows from a snapshot: the main window always returns,
    /// but callers may keep it ordered out for transitions where another surface replaces it
    /// temporarily (Compact Window). Each sub-window returns only if it was visible, restored
    /// to its captured frame.
    private func recreateModeDependentLayout(_ snapshot: ModeDependentLayoutSnapshot,
                                             revealMainWindow: Bool = true) {
        showMainWindow(reveal: revealMainWindow)
        if let main = snapshot.main {
            if main.frame != .zero {
                mainWindowController?.window?.setFrame(main.frame, display: true)
            }
        }

        if let playlist = snapshot.playlist, playlist.visible {
            showPlaylist(at: playlist.frame)
        }
        if let equalizer = snapshot.equalizer, equalizer.visible {
            showEqualizer(at: equalizer.frame)
        }
        if let library = snapshot.library, library.visible {
            let normalFrame = library.normalFrame ?? library.frame
            showPlexBrowser(at: normalFrame)
        }
        if let spectrum = snapshot.spectrum, spectrum.visible {
            showSpectrum(at: spectrum.frame)
        }
        if snapshot.audioAnalysis?.visible == true { showAudioAnalysis(at: snapshot.audioAnalysis?.frame) }
        if snapshot.peppyMeter?.visible == true { showPeppyMeter(at: snapshot.peppyMeter?.frame) }
        if snapshot.networkMonitor?.visible == true { showNetworkMonitor(at: snapshot.networkMonitor?.frame) }
        if let waveform = snapshot.waveform, waveform.visible {
            showWaveform(at: waveform.frame)
        }
        if let projectM = snapshot.projectM, projectM.visible {
            showProjectM(
                at: projectM.frame,
                restoringPresetIndex: snapshot.projectMPresetIndex
            )
        }

        pushCurrentPresentationStateToRecreatedWindows()

        if revealMainWindow {
            mainWindowController?.window?.makeKeyAndOrderFront(nil)
        } else {
            mainWindowController?.window?.orderOut(nil)
        }
        postWindowLayoutDidChange()
        updateDockedChildWindows()

        // The freshly rebuilt visualization window starts its CVDisplayLink, but the rapid
        // window reordering during recreate (main window made key last) fires an occlusion-state
        // change that pauses it (stoppedDueToOcclusion). Without an explicit kick the loop only
        // resumes once the user clicks the window. Re-pin the GL drawable and restart on the next
        // runloop, after AppKit's occlusion state has settled. Mirrors the fullscreen-transition path.
        if isProjectMVisible {
            DispatchQueue.main.async { [weak self] in
                self?.projectMWindowController?.resumeRenderingAfterWindowTransition()
            }
        }

        #if DEBUG
        // Log any visible orphaned windows that survived the rebuild
        var trackedWindows = Set<ObjectIdentifier>()
        for window in [mainWindowController?.window,
                       playlistWindowController?.window,
                       equalizerWindowController?.window,
                       plexBrowserWindowController?.window,
                       projectMWindowController?.window,
                       spectrumWindowController?.window,
                       audioAnalysisWindowController?.window,
                       peppyMeterWindowController?.window,
                       networkMonitorWindowController?.window,
                       waveformWindowController?.window,
                       videoPlayerWindowController?.window,
                       debugWindowController?.window].compactMap({ $0 }) {
            trackedWindows.insert(ObjectIdentifier(window))
        }

        for window in NSApp.windows where window.isVisible {
            guard !trackedWindows.contains(ObjectIdentifier(window)) else { continue }
            guard window.identifier == Self.modeDependentWindowIdentifier else { continue }
            NSLog("WindowManager: DEBUG orphan survived rebuild class=%@",
                  NSStringFromClass(type(of: window)))
        }
        #endif
    }

    /// Re-seed freshly created windows with the current audio/video presentation state.
    /// `AudioEngine` is alive across the rebuild, so this is purely a display refresh —
    /// it does not start, stop, or seek playback.
    private func pushCurrentPresentationStateToRecreatedWindows() {
        let track = audioEngine.currentTrack
        mainWindowController?.updateTrackInfo(track)
        mainWindowController?.updatePlaybackState()
        mainWindowController?.updateTime(current: audioEngine.currentTime, duration: audioEngine.duration)
        updateWaveformTrack(track)
        updateWaveformTime(current: audioEngine.currentTime, duration: audioEngine.duration)
        playlistWindowController?.reloadPlaylist()

        // If a video session is active, the video player survived teardown — restore its
        // title/state on the new main window instead of the audio track display.
        if isVideoActivePlayback, let title = videoPlayerWindowController?.currentTitle {
            mainWindowController?.updateVideoTrackInfo(
                title: title,
                artworkTrack: videoPlayerWindowController?.currentArtworkTrack
            )
            mainWindowController?.updatePlaybackState()
        }
    }

    #if DEBUG
    /// DEBUG-only proof-of-concept: tear down and rebuild the mode-dependent windows in the
    /// **same** UI mode (no `modernUIEnabled` flip, no runtime swap). This exercises the full
    /// AppKit teardown/rebuild cycle so leaks and lifecycle bugs surface before the live mode
    /// switch (PR4) layers mode-change semantics on top. Logs teardown/recreate timing.
    func debugRecreateModeDependentWindows() {
        NSLog("WindowManager: debugRecreateModeDependentWindows — start")
        // Compact Mode restores the underlying layout asynchronously on exit; defer the rebuild
        // until that completes so the snapshot captures the real windows and the re-enter is not
        // swallowed by the `.exiting` guard. Mirrors the production reloadUI path.
        if compactModeEnabled {
            // Same-mode rebuild: UI Size is not collapsed/re-applied here, so restore the snapshot
            // frames as-is (no 1x collapse — they'd never be re-scaled).
            let snapshot = modeDependentLayout(from: regularWindowSnapshot, collapsingScaleLevel: .p100)
            let preSwitchSnapshot = regularWindowSnapshot
            exitCompactMode(restoreRegularWindows: false) { [weak self] in
                guard let self else { return }
                self.performDebugRecreateModeDependentWindows(snapshot: snapshot, reenterCompact: true)
                self.reapplyModeIndependentWindows(from: preSwitchSnapshot)
            }
        } else if compactWindowEnabled {
            let compactWindowMainWasVisible = mainWasVisibleBeforeCompactWindow
            exitCompactWindow(restoreMainWindow: false)
            performDebugRecreateModeDependentWindows(snapshot: captureModeDependentLayout(), reenterCompact: false,
                                                     reenterCompactWindow: true,
                                                     compactWindowTreatMainAsVisible: compactWindowMainWasVisible)
        } else {
            performDebugRecreateModeDependentWindows(snapshot: captureModeDependentLayout(), reenterCompact: false,
                                                     reenterCompactWindow: false)
        }
    }

    private func performDebugRecreateModeDependentWindows(snapshot: ModeDependentLayoutSnapshot, reenterCompact: Bool,
                                                         reenterCompactWindow: Bool = false,
                                                         compactWindowTreatMainAsVisible: Bool = false) {
        let t0 = CACurrentMediaTime()
        teardownModeDependentWindows()
        let tTorn = CACurrentMediaTime()
        recreateModeDependentLayout(snapshot, revealMainWindow: !reenterCompactWindow)
        if reenterCompact { enterCompactMode() }
        if reenterCompactWindow {
            enterCompactWindow(treatMainAsVisible: compactWindowTreatMainAsVisible)
        }
        let tDone = CACurrentMediaTime()

        NSLog("WindowManager: debugRecreateModeDependentWindows — teardown %.1fms, recreate %.1fms",
              (tTorn - t0) * 1000.0, (tDone - tTorn) * 1000.0)
    }
    #endif

    /// Switch between Classic, Modern, and Metal UI in-process, with **no app restart**.
    ///
    /// This is the production live-switch built on the same teardown/rebuild primitive proven
    /// by the DEBUG recreate action, with mode-change semantics layered on:
    ///   1. snapshot which mode-dependent windows are open (+ frames) and the Compact-Mode state;
    ///   2. `teardownModeDependentWindows()` — synchronous; its completion gates recreation;
    ///   3. flip `isModernUIEnabled` — the `show*()` paths read it to pick classic vs. modern
    ///      controllers, so it must change *between* teardown and recreate;
    ///   4. `prepareUIRuntime(forModernUI:)` — target-mode runtime prep before any controller exists;
    ///   5. reprogram both EQ nodes to the target layout via canonical per-layout gains;
    ///   6. rebuild the menu bar (mode-dependent items);
    ///   7+8. recreate windows, restore visibility/frames, re-push presentation state, make the
    ///      new main window key (all inside `recreateModeDependentLayout`), then restore Compact Mode.
    ///
    /// Audio, casting, the video player, and all playback state survive untouched: `AudioEngine`
    /// is owned here (not by any window), so playlist / current track / seek / play-pause continue
    /// across the switch — audio state is deliberately *not* snapshotted or restored. No-op if the
    /// requested mode is already running.
    func reloadUI(toModernUI targetModern: Bool) {
        reloadUI(to: targetModern ? .modern : .classic)
    }

    /// Switch the live UI to `targetMode`. When Compact Mode is active the actual swap is
    /// deferred until compact teardown finishes, so callers that need to read the post-swap
    /// state (`uiMode`, `isRunningModernFamilyUI`) or rebuild window/skin state must pass
    /// `completion` — it runs after `performReloadUI`, on the main thread, in both the
    /// synchronous and deferred paths. It also fires when no switch is needed.
    func reloadUI(to targetMode: PlayerUIMode, completion: (() -> Void)? = nil) {
        guard targetMode != uiMode else {
            completion?()
            return
        }
        NSLog("WindowManager: reloadUI — switching to %@ UI", targetMode.displayName)

        let restoreCompactWindow = compactWindowEnabled
        let compactWindowMainWasVisible = restoreCompactWindow && mainWasVisibleBeforeCompactWindow
        if restoreCompactWindow {
            exitCompactWindow(restoreMainWindow: false)
        }

        // If an enlarged UI size is active, collapse it to 1x in the *current* mode before the switch and
        // re-apply it in the target mode afterward (inside performReloadUI). The two UI systems
        // have different window geometry (and modern layout is driven by the global
        // ModernSkinElements.sizeMultiplier), so forcing the old mode's enlarged frames onto
        // freshly-created target-mode windows renders them distorted. Collapsing first lets each
        // mode drive its own tested 1x-to-target scaling. The 1x windows are torn down immediately, so
        // no flash is visible.
        //
        // Collapsing runs applyDoubleSize(), which force-docks the side windows (Library/ProjectM)
        // to the main-window edge — capture their detached frames first so a user's detached position
        // survives the switch (restored after UI Size is re-applied). In Compact Mode the regular
        // windows are hidden, so captureSideWindowFrames() would see nothing; derive the detached
        // frames from `regularWindowSnapshot` (which recorded each side window's detached state at
        // Compact entry) instead.
        let restoreScaleLevel = uiScaleLevel
        let preservedSideFrames: SideWindowFrames
        if restoreScaleLevel != .p100 {
            preservedSideFrames = compactModeEnabled
                ? sideWindowFrames(from: regularWindowSnapshot)
                : captureSideWindowFrames()
        } else {
            preservedSideFrames = SideWindowFrames()
        }
        if restoreScaleLevel != .p100 { uiScaleLevel = .p100 }

        // Compact Mode hides the underlying regular window layout and restores it *asynchronously*
        // on exit. When in Compact Mode, derive the layout to rebuild from the pre-compact capture
        // (`regularWindowSnapshot`) rather than the live windows — they're still hidden, and
        // re-showing them would pull the user to whatever Space those `.managed` windows live on.
        // Defer the swap until the compact teardown completes so the re-enter sees
        // `compactModeState == .regular` instead of a no-op `.exiting` guard.
        if compactModeEnabled {
            let snapshot = modeDependentLayout(from: regularWindowSnapshot, collapsingScaleLevel: restoreScaleLevel)
            // The hidden mode-independent windows (app panels) survive teardown but were
            // hidden on compact entry and are not re-shown here. enterCompactMode() will re-capture
            // the snapshot from the live (still-hidden) windows, losing their visibility — so carry
            // their pre-switch state forward afterward. (The video player and debug console are
            // exempt from Compact Mode hiding and stay visible throughout.) See reapplyModeIndependentWindows(from:).
            let preSwitchSnapshot = regularWindowSnapshot
            exitCompactMode(restoreRegularWindows: false) { [weak self] in
                guard let self else { return }
                self.performReloadUI(to: targetMode, snapshot: snapshot, reenterCompact: true,
                                     reenterCompactWindow: false,
                                     restoreScaleLevel: restoreScaleLevel, preservedSideFrames: preservedSideFrames)
                self.reapplyModeIndependentWindows(from: preSwitchSnapshot)
                completion?()
            }
        } else {
            performReloadUI(to: targetMode, snapshot: captureModeDependentLayout(), reenterCompact: false,
                            reenterCompactWindow: restoreCompactWindow,
                            compactWindowTreatMainAsVisible: compactWindowMainWasVisible,
                            restoreScaleLevel: restoreScaleLevel, preservedSideFrames: preservedSideFrames)
            completion?()
        }
    }

    /// Frames of the side windows that `applyDoubleSize()` force-docks to the main-window edge.
    /// Captured before a UI Size collapse so a user's detached Library/ProjectM position can be
    /// restored after a mode switch.
    private struct SideWindowFrames {
        var library: NSRect?
        var projectM: NSRect?
    }

    /// Capture only *detached* side windows. A docked side window is re-docked to the
    /// target-mode main edge by `applyDoubleSize()` during the UI Size re-apply; restoring its
    /// old-mode frame on top of that would fight the target mode's docking and misalign it (the
    /// old frame was measured against the old main width). A detached window has no docking to
    /// recompute, so its exact floating position must be carried across the switch.
    private func captureSideWindowFrames() -> SideWindowFrames {
        func detachedFrame(_ window: NSWindow?) -> NSRect? {
            guard let window, window.isVisible, !isWindowDocked(window) else { return nil }
            return window.frame
        }
        return SideWindowFrames(
            library: detachedFrame(plexBrowserWindowController?.window),
            projectM: detachedFrame(projectMWindowController?.window)
        )
    }

    /// Detached side-window frames drawn from a Compact-Mode capture. The live windows are hidden in
    /// Compact Mode, so `captureSideWindowFrames()` would see nothing; instead read each side
    /// window's Compact-entry frame, carrying only those that were detached then (docked ones are
    /// left to `applyDoubleSize()`'s target-mode docking). Frames were captured at the UI Size
    /// scale, matching the scale `restoreSideWindowFrames` re-applies them at.
    private func sideWindowFrames(from snapshot: CompactWindowSnapshot?) -> SideWindowFrames {
        guard let snapshot else { return SideWindowFrames() }
        func detachedFrame(_ w: WindowSnapshot?) -> NSRect? {
            guard let w, w.wasVisible, w.wasDetached else { return nil }
            return w.frame
        }
        return SideWindowFrames(
            library: detachedFrame(snapshot.library),
            projectM: detachedFrame(snapshot.projectM)
        )
    }

    private func restoreSideWindowFrames(_ frames: SideWindowFrames) {
        if let frame = frames.library, let window = plexBrowserWindowController?.window, window.isVisible {
            window.setFrame(frame, display: true)
        }
        if let frame = frames.projectM, let window = projectMWindowController?.window, window.isVisible {
            window.setFrame(frame, display: true)
        }
    }

    /// A Compact-Mode-preserving UI switch leaves hidden mode-independent app-owned panels
    /// hidden without re-showing them, then `enterCompactMode()`
    /// re-captures `regularWindowSnapshot` from those still-hidden windows — recording them as not
    /// visible and dropping `additionalWindows`. Carry those fields forward from the pre-switch
    /// capture so a later Compact-Mode exit restores them. The mode-dependent fields in the fresh
    /// capture are correct (rebuilt then captured) and are left untouched. (The video player and
    /// debug console are exempt from Compact Mode hiding, so they need no carry-forward.)
    private func reapplyModeIndependentWindows(from previous: CompactWindowSnapshot?) {
        guard let previous, regularWindowSnapshot != nil else { return }
        // The video player and debug console are exempt from Compact Mode hiding, so they need
        // no carry-forward; only additional app windows are hidden and must be preserved.
        regularWindowSnapshot?.additionalWindows = previous.additionalWindows
    }

    /// Build a mode-dependent layout snapshot from a Compact-Mode capture, so the live UI switch
    /// can rebuild the regular windows without first re-showing them. Falls back to a live capture
    /// if no Compact snapshot exists.
    private func modeDependentLayout(from snapshot: CompactWindowSnapshot?,
                                     collapsingScaleLevel: UIScaleLevel) -> ModeDependentLayoutSnapshot {
        guard let snapshot else { return captureModeDependentLayout() }

        // The regular windows were snapshotted at Compact-Mode *entry*, so their frames still carry
        // the enlarged UI scale if it was active. performReloadUI re-applies that scale after the
        // rebuild, and applyDoubleSize scales the relative-sized stack/side windows off their
        // *current* frame. Collapse those frames back to 1x here so the re-apply lands once, matching the non-Compact path
        // (which captures its frames *after* the 1x collapse). Main and EQ use absolute target sizes
        // in applyDoubleSize, so they are left untouched.
        let inverse: CGFloat = 1.0 / collapsingScaleLevel.scaleFactor
        func collapsed(_ rect: NSRect?) -> NSRect? {
            guard var rect else { return nil }
            rect.size.width *= inverse
            rect.size.height *= inverse
            return rect
        }
        func conv(_ w: WindowSnapshot?) -> UIWindowSnapshot? {
            guard let w else { return nil }
            return UIWindowSnapshot(visible: w.wasVisible, frame: w.frame,
                                    normalFrame: w.normalFrame)
        }
        func convScaled(_ w: WindowSnapshot?) -> UIWindowSnapshot? {
            guard let w else { return nil }
            return UIWindowSnapshot(visible: w.wasVisible, frame: collapsed(w.frame) ?? w.frame,
                                    normalFrame: collapsed(w.normalFrame))
        }
        return ModeDependentLayoutSnapshot(
            main: conv(snapshot.main),
            playlist: convScaled(snapshot.playlist),
            equalizer: conv(snapshot.equalizer),
            library: convScaled(snapshot.library),
            projectM: convScaled(snapshot.projectM),
            spectrum: convScaled(snapshot.spectrum),
            audioAnalysis: convScaled(snapshot.audioAnalysis),
            peppyMeter: convScaled(snapshot.peppyMeter),
            networkMonitor: convScaled(snapshot.networkMonitor),
            waveform: convScaled(snapshot.waveform),
            projectMPresetIndex: restorableProjectMPresetIndex()
        )
    }

    /// The actual mode-dependent window swap. Runs synchronously when not in Compact Mode, or as
    /// the `exitCompactMode` completion when it was — see `reloadUI(toModernUI:)`.
    private func performReloadUI(to targetMode: PlayerUIMode, snapshot: ModeDependentLayoutSnapshot, reenterCompact: Bool,
                                 reenterCompactWindow: Bool = false,
                                 compactWindowTreatMainAsVisible: Bool = false,
                                 restoreScaleLevel: UIScaleLevel, preservedSideFrames: SideWindowFrames) {
        let t0 = CACurrentMediaTime()
        teardownModeDependentWindows()
        let tTorn = CACurrentMediaTime()

        // Persist the mode before recreate — show*() reads it to choose controllers.
        uiMode = targetMode

        prepareUIRuntime(for: targetMode)
        audioEngine.applyEQLayout(forModernUI: targetMode.usesModernControllers)
        (NSApp.delegate as? AppDelegate)?.rebuildMainMenu()

        recreateModeDependentLayout(snapshot, revealMainWindow: !reenterCompactWindow)

        // Re-apply UI size (collapsed to 1x in reloadUI before the switch) now that the target-mode
        // windows exist. This must happen *before* enterCompactMode() so the compact capture records
        // the enlarged regular layout, not a 1x one. applyDoubleSize (via the scale setter)
        // also re-docks the side windows, so restore any preserved detached frames afterward.
        if restoreScaleLevel != .p100 {
            uiScaleLevel = restoreScaleLevel
            restoreSideWindowFrames(preservedSideFrames)
        }

        // Restore Compact Mode last so it captures the freshly rebuilt window set, not stale state.
        if reenterCompact { enterCompactMode() }
        if reenterCompactWindow {
            enterCompactWindow(treatMainAsVisible: compactWindowTreatMainAsVisible)
        }
        let tDone = CACurrentMediaTime()

        NSLog("WindowManager: reloadUI — teardown %.1fms, recreate %.1fms (now %@ UI)",
              (tTorn - t0) * 1000.0, (tDone - tTorn) * 1000.0, targetMode.displayName)
    }

    /// Prepare mode-specific runtime state *before* target-mode controllers are created.
    /// Mirrors the startup branches in `AppDelegate.applicationDidFinishLaunching`: load the
    /// preferred modern skin when entering modern; reset classic spectrum transparent-background
    /// defaults when entering classic. The classic `currentSkin` is loaded once at init and
    /// survives across switches, so no classic skin reload is needed here.
    private func prepareUIRuntime(for targetMode: PlayerUIMode) {
        if let family = targetMode.modernSkinFamily {
            // Modern window sizes are derived from this global multiplier, so pin it to the
            // current UI Size state before any modern controller is created — otherwise a
            // stale value left over from a previous modern session would create the windows
            // at the wrong scale. reloadUI collapses uiScaleLevel to 1x before switching, so
            // this is normally 1.0 here; UI Size is re-applied via applyDoubleSize afterward.
            ModernSkinElements.sizeMultiplier = uiScaleLevel.scaleFactor
            ModernSkinEngine.shared.loadPreferredSkin(for: family)
        } else {
            UserDefaults.standard.set(false, forKey: VisClassicBridge.PreferenceScope.spectrumWindow.transparentBgKey)
            UserDefaults.standard.set(false, forKey: VisClassicBridge.PreferenceScope.mainWindow.transparentBgKey)
        }
    }

    /// Miniaturize all visible, managed player windows.
    /// Main window is miniaturized first so existing docked-window miniaturize
    /// coordination remains intact, then any remaining visible windows follow.
    func miniaturizeAllManagedWindows() {
        let windowsToMiniaturize = visibleWindows().filter { !$0.isMiniaturized }
        guard !windowsToMiniaturize.isEmpty else { return }

        let mainWindow = mainWindowController?.window
        if let mainWindow, windowsToMiniaturize.contains(where: { $0 === mainWindow }) {
            mainWindow.miniaturize(nil)
        }

        for window in windowsToMiniaturize where window !== mainWindow {
            window.miniaturize(nil)
        }
    }
    
    // MARK: - Coordinated Miniaturize
    
    /// Update persistent child window relationships so docked windows follow the
    /// main window when it moves across macOS Spaces.
    func updateDockedChildWindows() {
        guard let mainWindow = mainWindowController?.window else { return }
        refitDockedPlexBrowserToVerticalStack()
        refitDockedProjectMToVerticalStack()
        let docked = findDockedWindows(to: mainWindow)

        // Remove children that are no longer docked
        for child in mainWindow.childWindows ?? [] {
            if !docked.contains(child) {
                mainWindow.removeChildWindow(child)
            }
        }

        // Add newly docked children
        let existingChildren = Set(mainWindow.childWindows?.map { ObjectIdentifier($0) } ?? [])
        for window in docked {
            if !existingChildren.contains(ObjectIdentifier(window)) {
                mainWindow.addChildWindow(window, ordered: .above)
            }
        }
    }

    /// Temporarily attach all docked windows as child windows of the main window
    /// so they animate together into the dock as a group.
    /// Called from windowWillMiniaturize (before the animation starts).
    func attachDockedWindowsForMiniaturize(mainWindow: NSWindow) {
        let docked = findDockedWindows(to: mainWindow)
        coordinatedMiniaturizedWindows = docked
        for window in docked {
            // Only add if not already a child window
            if !(mainWindow.childWindows?.contains(window) ?? false) {
                mainWindow.addChildWindow(window, ordered: .above)
            }
        }
    }
    
    /// Remove child window relationships after the main window is restored from dock,
    /// so windows become independent again for normal docking/dragging behavior.
    /// Called from windowDidDeminiaturize.
    func detachDockedWindowsAfterDeminiaturize(mainWindow: NSWindow) {
        for window in coordinatedMiniaturizedWindows {
            mainWindow.removeChildWindow(window)
        }
        coordinatedMiniaturizedWindows.removeAll()
        // Reinstate persistent docked-child relationships for Spaces following
        updateDockedChildWindows()
    }
    
    // MARK: - State Persistence
    
    func saveWindowPositions() {
        let defaults = UserDefaults.standard
        compactWindowController?.persistFloatingFrameForStateSaving()
        
        if let frame = mainWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "MainWindowFrame")
        }
        if let frame = playlistWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "PlaylistWindowFrame")
        }
        if let frame = equalizerWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "EqualizerWindowFrame")
        }
        if let frame = plexBrowserWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "PlexBrowserWindowFrame")
        }
        if let frame = videoPlayerWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "VideoPlayerWindowFrame")
        }
        if let frame = projectMWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "ProjectMWindowFrame")
        }
        if let frame = spectrumWindowController?.window?.frame {
            defaults.set(NSStringFromRect(frame), forKey: "SpectrumWindowFrame")
        }
    }
    
    func restoreWindowPositions() {
        let defaults = UserDefaults.standard
        
        if let frameString = defaults.string(forKey: "MainWindowFrame"),
           let window = mainWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "PlaylistWindowFrame"),
           let window = playlistWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "EqualizerWindowFrame"),
           let window = equalizerWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "PlexBrowserWindowFrame"),
           let window = plexBrowserWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "VideoPlayerWindowFrame"),
           let window = videoPlayerWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "ProjectMWindowFrame"),
           let window = projectMWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
        if let frameString = defaults.string(forKey: "SpectrumWindowFrame"),
           let window = spectrumWindowController?.window {
            let frame = NSRectFromString(frameString)
            window.setFrame(frame, display: true)
        }
    }
}
