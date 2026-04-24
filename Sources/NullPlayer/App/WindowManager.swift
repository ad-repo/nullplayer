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

/// Determines how a window drag affects its connected group.
enum DragMode {
    case pending   // mouseDown received, drag not yet started
    case separate  // drag started before holdThreshold — window moves alone
    case group     // holdThreshold elapsed before drag — connected windows move together
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
    
    /// Enlarged UI mode - not persisted, always starts at 1x (both modern and classic UI)
    var isDoubleSize: Bool = false {
        didSet {
            applyDoubleSize()
            NotificationCenter.default.post(name: .doubleSizeDidChange, object: nil)
        }
    }

    /// Classic UI size multiplier driven by the Large UI mode toggle.
    /// Stays discrete (1x / 1.5x) so free window stretching does not alter skin scale.
    var classicScaleMultiplier: CGFloat {
        isDoubleSize ? 1.5 : 1.0
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
    
    /// Whether the modern UI is enabled (requires restart to take effect)
    var isModernUIEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "modernUIEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "modernUIEnabled") }
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
    
    /// Whether title bars are hidden on all windows (only applies in modern UI mode)
    var hideTitleBars: Bool {
        get { isRunningModernUI && UserDefaults.standard.bool(forKey: "hideTitleBars") }
        set { UserDefaults.standard.set(newValue, forKey: "hideTitleBars") }
    }

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
                          window === waveformWindowController?.window
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

    /// Video player window controller
    private var videoPlayerWindowController: VideoPlayerWindowController?
    
    /// ProjectM visualization window controller (classic or modern, accessed via protocol)
    private var projectMWindowController: ProjectMWindowProviding?
    
    /// Spectrum analyzer window controller (classic or modern, accessed via protocol)
    private var spectrumWindowController: SpectrumWindowProviding?

    /// Shared vis_classic bridge — created on first use, driven by audioWaveform576DataUpdated notifications.
    private(set) var sharedVisClassicBridge: VisClassicBridge?

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
            if isVideoCastingActive {
                if CastManager.shared.isVideoCasting {
                    return CastManager.shared.videoCastDuration
                }
                if let controller = videoPlayerWindowController, controller.isCastingVideo {
                    return controller.castDuration
                }
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
    
    /// Track if current drag is from title bar (retained for context; does not gate separation logic)
    private var isTitleBarDrag = false
    
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
            "waveformHideTooltip": false
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
        // Note: isDoubleSize always starts false - windows are created at 1x size
        // and we apply double size after they're created if needed
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
    
    func showMainWindow() {
        let isNew = mainWindowController == nil
        if isNew {
            if isModernUIEnabled {
                let modern = ModernMainWindowController()
                mainWindowController = modern
            } else {
                mainWindowController = MainWindowController()
            }
        }
        // Enforce HT compact height on both first show and subsequent re-shows.
        if isRunningModernUI {
            normalizeModernMainWindowForHTIfNeeded()
        }
        mainWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(mainWindowController?.window)
    }
    
    func toggleMainWindow() {
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
        
        // Position BEFORE showing (unless restoring from saved state)
        if let playlistWindow = playlistWindowController?.window {
            applyCenterStackSizingConstraints(playlistWindow, kind: .playlist)
            if let frame = restoredFrame, frame != .zero {
                playlistWindow.setFrame(normalizedCenterStackRestoredFrame(frame, kind: .playlist), display: true)
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
        
        // Position BEFORE showing (unless restoring from saved state)
        if let eqWindow = equalizerWindowController?.window {
            applyCenterStackSizingConstraints(eqWindow, kind: .equalizer)
            if let frame = restoredFrame, frame != .zero {
                eqWindow.setFrame(normalizedCenterStackRestoredFrame(frame, kind: .equalizer), display: true)
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
        
        // Collect all visible stack windows except the one being positioned
        var visibleWindows: [NSWindow] = [mainWindow]
        if let w = equalizerWindowController?.window, w.isVisible, w !== window { visibleWindows.append(w) }
        if let w = playlistWindowController?.window, w.isVisible, w !== window { visibleWindows.append(w) }
        if let w = spectrumWindowController?.window, w.isVisible, w !== window { visibleWindows.append(w) }
        if let w = waveformWindowController?.window, w.isVisible, w !== window { visibleWindows.append(w) }
        
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
            if isModernUIEnabled {
                plexBrowserWindowController = ModernLibraryBrowserWindowController()
            } else {
                plexBrowserWindowController = PlexBrowserWindowController()
            }
        }
        plexBrowserWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(plexBrowserWindowController?.window)
        // Position window to match the vertical stack
        if let window = plexBrowserWindowController?.window {
            if isNewWindow, let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration (first creation only)
                window.setFrame(frame, display: true)
            } else {
                // Position to the right of the vertical stack
                // Only match stack height if there's more than just the main window
                let stackBounds = verticalStackBounds()
                let mainWindow = mainWindowController?.window
                let mainActualHeight = mainWindow?.frame.height ?? 0
                let stackHasMultipleWindows = stackBounds.height > mainActualHeight + 1
                // Scale width for double-size mode
                let sideWidth = window.frame.width * (isModernUIEnabled ? ModernSkinElements.sizeMultiplier : 1.0)
                // Use full cluster bounds for X so we don't open on top of side-docked windows
                let clusterBounds = windowClusterBounds(excluding: window)
                let rightEdgeX = clusterBounds != .zero ? clusterBounds.maxX : (mainWindow?.frame.maxX ?? 0)

                if stackBounds != .zero && stackHasMultipleWindows {
                    // Match stack height when multiple windows are stacked
                    // No adjustWindowForHiddenTitleBars needed - stack height already accounts for it
                    let newFrame = NSRect(
                        x: rightEdgeX,
                        y: stackBounds.minY,
                        width: sideWidth,
                        height: stackBounds.height
                    )
                    window.setFrame(newFrame, display: true)
                } else if let mainWindow = mainWindow {
                    // Use default height (4× main) when only main window is visible
                    let mainFrame = mainWindow.frame
                    let defaultHeight = defaultSideWindowHeight(mainFrame: mainFrame)
                    let newFrame = NSRect(
                        x: rightEdgeX,
                        y: mainFrame.maxY - defaultHeight,
                        width: sideWidth,
                        height: defaultHeight
                    )
                    window.setFrame(newFrame, display: true)
                }
            }
        }
        postLayoutChangeNotification()
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
    
    func togglePlexBrowser() {
        if let controller = plexBrowserWindowController, controller.window?.isVisible == true {
            controller.window?.orderOut(nil)
        } else {
            showPlexBrowser()
        }
        postLayoutChangeNotification()
        updateDockedChildWindows()
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
        if CastManager.shared.isVideoCasting,
           let device = CastManager.shared.activeSession?.device,
           device.supportsVideo {
            return device
        }

        guard CastManager.shared.preferredVideoCastDeviceID != nil else { return nil }
        return CastManager.shared.preferredVideoCastDevice
    }

    private func routeToVideoCastIfNeeded(title: String, operation: @escaping (CastDevice) async throws -> Void) -> Bool {
        guard let device = targetVideoCastDevice else { return false }

        // Once a library selection replaces the cast media, CastManager owns the cast state.
        videoPlayerWindowController?.releaseCastOwnershipToCastManager()
        videoTitle = title
        mainWindowController?.updateVideoTrackInfo(title: title)
        mainWindowController?.updatePlaybackState()

        Task {
            do {
                try await operation(device)
            } catch {
                NSLog("WindowManager: Failed to route video '%@' to active cast device %@: %@", title, device.name, error.localizedDescription)
                CastManager.shared.postError(.playbackFailed("Could not play '\(title)' on \(device.name): \(error.localizedDescription)"))
            }
        }

        return true
    }
    
    /// Show the video player with a URL and title
    func showVideoPlayer(url: URL, title: String) {
        if routeToVideoCastIfNeeded(title: title, operation: { device in
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
        if routeToVideoCastIfNeeded(title: movie.title, operation: { device in
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
        if routeToVideoCastIfNeeded(title: title, operation: { device in
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
        if routeToVideoCastIfNeeded(title: movie.title, operation: { device in
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
        if routeToVideoCastIfNeeded(title: title, operation: { device in
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
        if routeToVideoCastIfNeeded(title: movie.title, operation: { device in
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
        if routeToVideoCastIfNeeded(title: title, operation: { device in
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

        if routeToVideoCastIfNeeded(title: track.displayTitle, operation: { device in
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
        if CastManager.shared.isVideoCasting {
            return CastManager.shared.isVideoCastPlaying
        }
        return videoPlayerWindowController?.isPlaying ?? false
    }
    
    /// Current video title (if playing)
    var currentVideoTitle: String? {
        if CastManager.shared.isVideoCasting {
            return CastManager.shared.videoCastTitle
        }
        if let title = videoPlayerWindowController?.currentTitle {
            return title
        }
        return nil
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
        if CastManager.shared.isVideoCasting {
            Task {
                if CastManager.shared.isVideoCastPlaying {
                    try? await CastManager.shared.pause()
                } else {
                    try? await CastManager.shared.resume()
                }
            }
            return
        }

        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.togglePlayPause()
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.togglePlayPause()
    }
    
    /// Stop video playback
    func stopVideo() {
        if CastManager.shared.isVideoCasting {
            Task {
                await CastManager.shared.stopCasting()
                await MainActor.run {
                    WindowManager.shared.videoPlaybackDidStop()
                }
            }
            return
        }

        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.stop()
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.stop()
    }
    
    /// Set video player volume
    func setVideoVolume(_ volume: Float) {
        videoPlayerWindowController?.volume = volume
    }
    
    /// Whether video casting is currently active
    var isVideoCastingActive: Bool {
        // Check both VideoPlayerWindowController (for casts initiated from video player)
        // and CastManager (for casts initiated from context menu)
        (videoPlayerWindowController?.isCastingVideo ?? false) || CastManager.shared.isVideoCasting
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
        if CastManager.shared.isVideoCasting {
            Task {
                if CastManager.shared.isVideoCastPlaying {
                    try? await CastManager.shared.pause()
                } else {
                    try? await CastManager.shared.resume()
                }
            }
            return
        }

        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.togglePlayPause()
        }
    }
    
    /// Seek video cast (normalized 0-1 position)
    func seekVideoCast(position: Double) {
        if CastManager.shared.isVideoCasting {
            let time = position * CastManager.shared.videoCastDuration
            Task {
                try? await CastManager.shared.seek(to: time)
            }
            return
        }

        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            let time = position * controller.duration
            controller.seek(to: time)
        }
    }
    
    /// Skip video forward
    func skipVideoForward(_ seconds: TimeInterval = 10) {
        if CastManager.shared.isVideoCasting {
            let newTime = min(CastManager.shared.videoCastCurrentTime + seconds, CastManager.shared.videoCastDuration)
            Task {
                try? await CastManager.shared.seek(to: newTime)
            }
            return
        }

        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.skipForward(seconds)
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.skipForward(seconds)
    }
    
    /// Skip video backward
    func skipVideoBackward(_ seconds: TimeInterval = 10) {
        if CastManager.shared.isVideoCasting {
            let newTime = max(CastManager.shared.videoCastCurrentTime - seconds, 0)
            Task {
                try? await CastManager.shared.seek(to: newTime)
            }
            return
        }

        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.skipBackward(seconds)
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.skipBackward(seconds)
    }
    
    /// Seek video to specific time
    func seekVideo(to time: TimeInterval) {
        if CastManager.shared.isVideoCasting {
            Task {
                try? await CastManager.shared.seek(to: time)
            }
            return
        }

        if let controller = videoPlayerWindowController, controller.isCastingVideo {
            controller.seek(to: time)
            return
        }
        
        // Local video player (not casting)
        videoPlayerWindowController?.seek(to: time)
    }
    
    /// Called when video playback starts - pause audio
    func videoPlaybackDidStart() {
        if audioEngine.state == .playing {
            audioEngine.pause()
        }
        // Update main window with video title
        if let title = videoPlayerWindowController?.currentTitle {
            videoTitle = title
            mainWindowController?.updateVideoTrackInfo(title: title)
        }
        mainWindowController?.updatePlaybackState()
        // Auto-cast to preferred device if one is set
        videoPlayerWindowController?.performAutoCastIfNeeded()
    }
    
    /// Called when video playback stops
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
        if CastManager.shared.isVideoCasting { return true }
        guard let controller = videoPlayerWindowController,
              let window = controller.window,
              window.isVisible else {
            return false
        }
        return controller.currentTitle != nil
    }
    
    /// Get current video playback state for main window display
    var videoPlaybackState: PlaybackState {
        if CastManager.shared.isVideoCasting {
            return CastManager.shared.isVideoCastPlaying ? .playing : .paused
        }
        guard let controller = videoPlayerWindowController else { return .stopped }
        return controller.isPlaying ? .playing : .paused
    }
    
    // MARK: - ProjectM Visualization Window
    
    func showProjectM(at restoredFrame: NSRect? = nil) {
        let isNewWindow = projectMWindowController == nil
        if isNewWindow {
            if isModernUIEnabled {
                projectMWindowController = ModernProjectMWindowController()
            } else {
                projectMWindowController = ProjectMWindowController()
            }
        }
        projectMWindowController?.showWindow(nil)
        applyAlwaysOnTopToWindow(projectMWindowController?.window)
        // Position window to match the vertical stack
        if let window = projectMWindowController?.window {
            if isNewWindow, let frame = restoredFrame, frame != .zero {
                // Use restored frame from state restoration (first creation only)
                window.setFrame(frame, display: true)
            } else {
                // Position to the left of the vertical stack
                // Only match stack height if there's more than just the main window
                let stackBounds = verticalStackBounds()
                let mainWindow = mainWindowController?.window
                let mainActualHeight = mainWindow?.frame.height ?? 0
                let stackHasMultipleWindows = stackBounds.height > mainActualHeight + 1
                // Use full cluster bounds for X so we don't open on top of side-docked windows
                let clusterBounds = windowClusterBounds(excluding: window)
                let leftEdgeX = clusterBounds != .zero ? clusterBounds.minX : (mainWindow?.frame.minX ?? 0)

                if stackBounds != .zero && stackHasMultipleWindows {
                    // Match stack height when multiple windows are stacked
                    // No adjustWindowForHiddenTitleBars needed - stack height already accounts for it
                    let newFrame = NSRect(
                        x: leftEdgeX - window.frame.width,
                        y: stackBounds.minY,
                        width: window.frame.width,
                        height: stackBounds.height
                    )
                    window.setFrame(newFrame, display: true)
                } else if let mainWindow = mainWindow {
                    // Use default height (4× main) when only main window is visible
                    let mainFrame = mainWindow.frame
                    let defaultHeight = defaultSideWindowHeight(mainFrame: mainFrame)
                    let newFrame = NSRect(
                        x: leftEdgeX - window.frame.width,
                        y: mainFrame.maxY - defaultHeight,
                        width: window.frame.width,
                        height: defaultHeight
                    )
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
        
        // Position BEFORE showing (unless restoring from saved state)
        if let window = spectrumWindowController?.window {
            applyCenterStackSizingConstraints(window, kind: .spectrum)
            if let frame = restoredFrame, frame != .zero {
                window.setFrame(normalizedCenterStackRestoredFrame(frame, kind: .spectrum), display: true)
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

        if let window = waveformWindowController?.window {
            let classicController = waveformWindowController as? WaveformWindowController
            applyCenterStackSizingConstraints(window, kind: .waveform)
            if let frame = restoredFrame, frame != .zero {
                classicController?.clearPendingFrameReset()
                window.setFrame(normalizedCenterStackRestoredFrame(frame, kind: .waveform), display: true)
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
    
    /// Get information about loaded presets (bundled count, custom count, custom path)
    var visualizationPresetsInfo: (bundledCount: Int, customCount: Int, customPath: String?) {
        projectMWindowController?.presetsInfo ?? (0, 0, nil)
    }
    
    /// Reload all visualization presets from bundled and custom folders
    func reloadVisualizationPresets() {
        projectMWindowController?.reloadPresets()
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

    private func applyClassicVisualizationDefaults(notify: Bool) {
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
        waveformWindowController?.skinDidChange()
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
    
    // MARK: - Double Size
    
    /// Apply enlarged UI scaling to all windows
    private func applyDoubleSize() {
        let runningModernMode = isRunningModernUI
        let classicScaleMultiplier: CGFloat = 1.5
        let classicInverseScaleMultiplier: CGFloat = 1.0 / classicScaleMultiplier

        // For modern UI, set the sizeMultiplier so all ModernSkinElements computed
        // sizes (window sizes, title bar heights, border widths, etc.) reflect the large mode.
        // This must happen BEFORE reading any ModernSkinElements sizes.
        if runningModernMode {
            ModernSkinElements.sizeMultiplier = isDoubleSize ? 1.5 : 1.0
        }
        
        let scale: CGFloat = isDoubleSize ? classicScaleMultiplier : 1.0
        
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
            let heightScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let newHeight = max(minHeight, currentFrame.height * heightScaleMultiplier)
            let widthScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let newWidth = max(minWidth, currentFrame.width * widthScaleMultiplier)

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
            let heightScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let widthScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let newHeight = max(minHeight, currentFrame.height * heightScaleMultiplier)
            let newWidth = max(minWidth, currentFrame.width * widthScaleMultiplier)
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
            let heightScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let newHeight = max(minHeight, currentFrame.height * heightScaleMultiplier)
            // Waveform width should transition with Large UI in both modes so toggling off
            // reliably returns to the prior 1x geometry.
            let widthScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let newWidth = max(skinMinWidth, currentFrame.width * widthScaleMultiplier)

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
        
        // Side windows - match the vertical stack height and reposition
        let stackTopY = mainFrame.maxY
        let stackHeight = stackTopY - nextY
        
        if let plexWindow = plexBrowserWindowController?.window, plexWindow.isVisible {
            let widthScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let newWidth = plexWindow.frame.width * widthScaleMultiplier
            let plexFrame = NSRect(
                x: mainFrame.maxX,
                y: nextY,
                width: newWidth,
                height: stackHeight
            )
            plexWindow.setFrame(plexFrame, display: true, animate: false)
        }

        if let projectMWindow = projectMWindowController?.window, projectMWindow.isVisible {
            let widthScaleMultiplier: CGFloat = isDoubleSize ? classicScaleMultiplier : classicInverseScaleMultiplier
            let newWidth = projectMWindow.frame.width * widthScaleMultiplier
            let projectMFrame = NSRect(
                x: mainFrame.minX - (projectMWindow.frame.width * widthScaleMultiplier),
                y: nextY,
                width: newWidth,
                height: stackHeight
            )
            projectMWindow.setFrame(projectMFrame, display: true, animate: false)
        }

        isSnappingWindow = false
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
        waveformWindowController?.window?.level = level
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

    private enum CenterStackWindowKind {
        case equalizer
        case playlist
        case spectrum
        case waveform
    }

    private func centerStackWindowKind(for window: NSWindow) -> CenterStackWindowKind? {
        if window === equalizerWindowController?.window { return .equalizer }
        if window === playlistWindowController?.window { return .playlist }
        if window === spectrumWindowController?.window { return .spectrum }
        if window === waveformWindowController?.window { return .waveform }
        return nil
    }

    private func fullMainHeightForCurrentScale() -> CGFloat {
        ModernSkinElements.baseMainSize.height * ModernSkinElements.scaleFactor
    }

    private func targetCenterStackHeight(for kind: CenterStackWindowKind,
                                         currentHeight: CGFloat,
                                         titleBarDelta: CGFloat,
                                         preservePlaylistContentHeight: Bool) -> CGFloat {
        let target = expectedMainHeightForCurrentHT(mainWindowController?.window)
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

    private func normalizedCenterStackRestoredFrame(_ frame: NSRect, kind: CenterStackWindowKind) -> NSRect {
        guard isRunningModernUI else { return frame }
        var normalized = frame
        if let mainWindow = mainWindowController?.window, kind != .waveform {
            normalized.origin.x = mainWindow.frame.minX
            normalized.size.width = mainWindow.frame.width
        }

        let topY = normalized.maxY
        let target = expectedMainHeightForCurrentHT(mainWindowController?.window)
        switch kind {
        case .equalizer, .spectrum:
            normalized.size.height = target
        case .playlist, .waveform:
            // Accept legacy compact saved frames but normalize to current full-height minimum.
            normalized.size.height = max(target, normalized.height)
        }
        normalized.origin.y = topY - normalized.size.height
        return normalized
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

        let scale: CGFloat = isDoubleSize ? 1.5 : 1.0
        let equalizerWindow = equalizerWindowController?.window
        let playlistWindow = playlistWindowController?.window
        let spectrumWindow = spectrumWindowController?.window
        let waveformWindow = waveformWindowController?.window

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: mainWindow.frame,
            equalizerFrame: (equalizerWindow?.isVisible == true) ? equalizerWindow?.frame : nil,
            playlistFrame: (playlistWindow?.isVisible == true) ? playlistWindow?.frame : nil,
            spectrumFrame: (spectrumWindow?.isVisible == true) ? spectrumWindow?.frame : nil,
            waveformFrame: (waveformWindow?.isVisible == true) ? waveformWindow?.frame : nil,
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
        
        // Collect frames for visible stack windows (order: EQ, Playlist, Spectrum, Waveform)
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
        pressedMouseButtons: Int,
        currentEventType: NSEvent.EventType?
    ) -> Bool {
        if holdPrimed { return true }
        if (pressedMouseButtons & 0x1) != 0 { return true } // Left mouse button.
        switch currentEventType {
        case .leftMouseDown, .leftMouseDragged:
            return true
        default:
            return false
        }
    }

    /// Called when a window drag begins
    /// - Parameters:
    ///   - window: The window being dragged
    ///   - fromTitleBar: Whether the drag originated from the title bar (recorded for reference)
    func windowWillStartDragging(_ window: NSWindow, fromTitleBar: Bool = false) {
        let usingPrimedHold = (primedDragWindow === window && holdStartTime != nil)
        draggingWindow = window
        isTitleBarDrag = fromTitleBar
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
    
    /// Called when a window is being dragged - handle snapping and move docked windows
    func windowWillMove(_ window: NSWindow, to newOrigin: NSPoint) -> NSPoint {
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
            pressedMouseButtons: Int(NSEvent.pressedMouseButtons),
            currentEventType: NSApp.currentEvent?.type
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
        
        // Apply best snaps
        if let hSnap = bestHorizontalSnap {
            snappedX = round(hSnap.value)
        }
        if let vSnap = bestVerticalSnap {
            snappedY = round(vSnap.value)
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
               window === waveformWindowController?.window
    }
    
    /// Get all visible windows
    func visibleWindows() -> [NSWindow] {
        return allWindows()
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
