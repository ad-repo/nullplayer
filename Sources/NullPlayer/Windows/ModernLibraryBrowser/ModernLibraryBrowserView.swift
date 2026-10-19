import AppKit
import AVFoundation
import SwiftUI
import NullPlayerCore

/// The library browser in an Original or Metal skin: the window chrome, server bar, tabs and search
/// bar drawn with the modern skin engine, in AppKit's bottom-up coordinates, and never touching the
/// classic skin system. What it browses and how its list behaves and draws are shared with the
/// classic view in `Windows/LibraryBrowser/`.
class ModernLibraryBrowserView: NSView {

    // MARK: - Properties

    weak var controller: ModernLibraryBrowserWindowController?

    /// Compact Mode: when true, a stripped-down player bar is embedded across the top
    /// (just below the title bar) and all content below shifts down to make room.
    /// The window itself is never resized -- only the list/content region shrinks.
    var compactMode: Bool = false {
        didSet {
            guard compactMode != oldValue else { return }
            refreshBackdrop()
            needsLayout = true
            needsDisplay = true
        }
    }
    private var compactPlayerBar: CompactPlayerBarView?
    private lazy var backdrop = BrowserBackdrop(mode: { [weak self] in self?.effectiveBackdropMode ?? .off },
                                                look: Self.backdropLook)

    var backdropPresenter: CavaPresenter? {
        backdrop.presenter
    }

    /// Height of the embedded compact player bar (0 when not in compact mode).
    private var compactPlayerBarHeight: CGFloat {
        compactMode ? CompactPlayerBarView.preferredHeight(for: ModernSkinElements.sizeMultiplier) : 0
    }

    /// Y coordinate of the bottom of the top chrome (title bar + optional compact player bar).
    /// All content below the title bar measures down from here, so inserting the player bar
    /// shifts the server bar / tabs / search / list down without resizing the window.
    private var topChromeBottomY: CGFloat {
        bounds.height - Layout.titleBarHeight - compactPlayerBarHeight
    }

    /// Y coordinate of the bottom of the scrollable content region. Content measures up from
    /// here, so reserving the compact footer band shifts the list / alphabet / server bar up
    /// without any other layout math changing (mirrors `topChromeBottomY` for the bottom).
    private var contentRegionBottomY: CGFloat {
        Layout.statusBarHeight + compactFooterHeight
    }
    
    /// The browser's source, tab, rows and caches; this view draws them.
    let model = LibraryBrowserModel(keyPrefix: "")

    private var historyHostingView: NSHostingView<StatsContentView>?

    private var itemHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }
    private var columnHeaderHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }

    /// Content shown below the compact player bar: the library browser or the play queue.
    /// Only consulted when `compactMode == true`; the full library window is unaffected.
    enum CompactContentMode: Int { case library = 0, queue = 1 }

    private var compactContentMode: CompactContentMode {
        get { CompactContentMode(rawValue: UserDefaults.standard.integer(forKey: "compactContentMode")) ?? .library }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "compactContentMode")
            updateCompactPlaylistFrame()   // show/hide + size the embedded queue
            // Hand keyboard focus to whichever view is now visible.
            window?.makeFirstResponder(newValue == .queue ? (compactPlaylistView ?? self) : self)
            needsLayout = true
            needsDisplay = true
        }
    }

    /// Height of the Library|Playlist toggle footer at the bottom of the compact window
    /// (0 outside compact mode).
    private var compactFooterHeight: CGFloat {
        compactMode ? 24 * ModernSkinElements.sizeMultiplier : 0
    }

    /// Embedded compact-sized play queue, shown in place of the library chrome in queue mode.
    private var compactPlaylistView: ModernPlaylistView?

    /// What the rows do and the menus that offer it.
    private lazy var actions: LibraryBrowserActions = LibraryBrowserActions(model: model, host: .init(
        view: { [unowned self] in self },
        presentLinkSheet: { [unowned self] in controller?.showLinkSheet() },
        ratingStarColor: {
            ModernSkinEngine.shared.currentRenderStyle == .metal
                ? NSColor(calibratedRed: 0.34, green: 0.28, blue: 0.13, alpha: 1.0)
                : NSColor(srgbRed: 0.98, green: 0.78, blue: 0.20, alpha: 1.0)
        },
        busyChanged: { [unowned self] in coordinator.busyChanged() }
    ))

    /// Routes the model's changes, the window's events and the clicks above the list, and runs the
    /// names' scroll and the spinners. The controls are drawn here, which `coordinator.rects` records.
    private lazy var coordinator = LibraryBrowserCoordinator(view: self, model: model, actions: actions, list: list, host: .init(
        redraw: { [unowned self] region in
            switch region {
            case .all, .list: needsDisplay = true
            case .serverBar: setNeedsDisplay(serverBarRect())
            }
        },
        updateHistory: { [unowned self] in updateHistoryHostingVisibility() },
        visibilityChanged: { [unowned self] in backdrop.reload() }
    ))

    /// Cached server bar font and attribute dictionaries — invalidated when skin changes
    private var cachedServerBarFont: NSFont?
    private var cachedServerBarFontSkinName: String?
    private var cachedServerBarFontScale: CGFloat?
    private var cachedServerBarIsMetal: Bool?
    private var cachedServerBarCompact: Bool?
    private var cachedServerBarChromeScale: CGFloat?
    private var cachedPrefixAttrs: [NSAttributedString.Key: Any]?
    private var cachedDataAttrs: [NSAttributedString.Key: Any]?
    private var cachedActiveAttrs: [NSAttributedString.Key: Any]?

    /// Scrolling, clicks, keys and menus on the rows, and Flow / Tiles standing in for them.
    private lazy var list = LibraryBrowserList(view: self, model: model, actions: actions, art: art, host: .init(
        layout: { [unowned self] in listLayout() },
        artStyle: { [unowned self] in
            let skin = currentSkin()
            return LibraryArtStyle(titleColor: skin.textColor, subtitleColor: skin.textDimColor,
                                   placeholderFill: skin.surfaceColor, placeholderTextColor: skin.textDimColor)
        },
        backdropMenu: { [unowned self] in
            ContextMenuBuilder.browserBackdropMenuItem(compact: compactMode, presenter: backdropPresenter)
        }
    ))

    /// Row art and the art drawn behind the list.
    private lazy var art = LibraryBrowserArt(model: model, isBackgroundEnabled: { [unowned self] in effectiveBackdropMode.showsArt })
    private var isPreparingForUITeardown = false
    private let rowThumbnails = LibraryRowThumbnailTracker()
    
    /// Which edges are adjacent to another docked window (for seamless border rendering)
    private var adjacentEdges: AdjacentEdges = [] { didSet { updateCornerMask() } }
    private var sharpCorners: CACornerMask = [] { didSet { updateCornerMask() } }
    private var edgeOcclusionSegments: EdgeOcclusionSegments = .empty
    
    // Button/drag state
    private var isClosePressed = false
    private var isDraggingWindow = false
    /// True when hide-title-bars mode primed drag hold timing on mouseDown.
    private var didPrimeWindowDragHold = false
    private var windowDragStartPoint: NSPoint = .zero
    
    // MARK: - Layout Constants (independent of classic skin)
    
    private struct Layout {
        static var titleBarHeight: CGFloat {
            WindowManager.shared.hideTitleBars ? Layout.borderWidth : ModernSkinElements.libraryTitleBarHeight
        }
        static var tabBarHeight: CGFloat { 24 * ModernSkinElements.sizeMultiplier }
        static var serverBarHeight: CGFloat { 24 * ModernSkinElements.sizeMultiplier }
        static var searchBarHeight: CGFloat { 26 * ModernSkinElements.sizeMultiplier }
        static var statusBarHeight: CGFloat { 6 * ModernSkinElements.sizeMultiplier }
        static var offlineBannerHeight: CGFloat { 18 * ModernSkinElements.sizeMultiplier }
        static let scrollbarWidth: CGFloat = 0
        static var alphabetWidth: CGFloat { 16 * ModernSkinElements.sizeMultiplier }
        static var borderWidth: CGFloat { ModernSkinElements.libraryBorderWidth }
        static var padding: CGFloat { 3 * ModernSkinElements.sizeMultiplier }
    }
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.isOpaque = false
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // Register notifications
        NotificationCenter.default.addObserver(self, selector: #selector(modernSkinDidChange),
                                               name: ModernSkinEngine.skinDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(doubleSizeChanged),
                                               name: .doubleSizeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowLayoutDidChange),
                                               name: .windowLayoutDidChange, object: nil)

        // Register for drag and drop
        registerForDraggedTypes([.fileURL])

        coordinator.start()

        // Load artwork for current track
        art.onBackgroundChange = { [weak self] in self?.needsDisplay = true }
        art.showPlayingTrack(WindowManager.shared.audioEngine.currentTrack)
        
        // Set accessibility
        setAccessibilityIdentifier("modernLibraryBrowserView")
        setAccessibilityRole(.group)
        setAccessibilityLabel("Library Browser")
        updateCornerMask()
        updateHistoryHostingVisibility()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        backdrop.stop()
    }

    /// Synchronously cancel every in-flight task, work item, and timer this view and its model
    /// own so they can be deallocated immediately when the controller is torn down for a UI
    /// reload — rather than being pinned alive (and mutating dead UI state) by a detached
    /// `@MainActor` expand/load task or a self-retaining repeating timer. `deinit` is deferred by
    /// AppKit's autorelease pool, so `WindowManager.teardownModeDependentWindows()` calls this
    /// *before* closing the window.
    func prepareForUITeardown() {
        isPreparingForUITeardown = true
        coordinator.teardown()
        art.cancel()
        backdrop.remove()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        updateCornerMask()
        updateEmbeddedSubviewFrames()
        refreshBackdrop()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        coordinator.startMarquee()
        updateEmbeddedSubviewFrames()
        list.clampHorizontalScrollOffset()
    }

    override func layout() {
        super.layout()
        updateEmbeddedSubviewFrames()
    }

    // MARK: - Current Skin Helper
    
    private func currentSkin() -> ModernSkin {
        return ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
    }

    private let backdropScrimAlpha: CGFloat = 0.72

    private var backdropActive: Bool {
        effectiveBackdropMode.showsCava
    }

    private var effectiveBackdropMode: BrowserBackdropMode {
        compactMode
            ? WindowManager.shared.compactBackdropMode
            : WindowManager.shared.libraryBackdropMode
    }

    private var backdropScope: CavaSettings.Scope {
        compactMode ? .compactWindow : .libraryWindow
    }

    private func contentFill(_ base: NSColor) -> NSColor {
        guard backdropActive else { return base }
        return base.withAlphaComponent(base.alphaComponent * backdropScrimAlpha)
    }

    private func updateHistoryHostingBackground() {
        guard let historyHostingView else { return }
        let background = contentFill(currentSkin().backgroundColor)
        historyHostingView.layer?.backgroundColor = background.cgColor
        historyHostingView.layer?.isOpaque = !backdropActive && background.alphaComponent >= 1
    }

    private func updateCornerMask() {
        guard let layer = self.layer else { return }
        let cornerRadius = currentSkin().config.window.cornerRadius ?? 0
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = cornerRadius > 0
        backdrop.view?.setSharpCorners(sharpCorners)
        guard cornerRadius > 0 else { return }
        let allCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner,
                                         .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = allCorners.subtracting(sharpCorners)
    }

    private func makeHistoryHostingView() -> NSHostingView<StatsContentView> {
        let skin = currentSkin()
        let rootView = StatsContentView(agent: model.history,
                                        skinTextColor: Color(skin.textColor),
                                        headerTitle: "Library Data",
                                        heatmapTheme: ContributionHeatmapTheme(modernSkin: skin))
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        let background = contentFill(skin.backgroundColor)
        hostingView.layer?.backgroundColor = background.cgColor
        hostingView.layer?.isOpaque = !backdropActive && background.alphaComponent >= 1
        hostingView.appearance = NSAppearance.matching(background: skin.backgroundColor)
        hostingView.setAccessibilityIdentifier("modernLibraryBrowser.data")
        hostingView.setAccessibilityLabel("Library Data")
        return hostingView
    }

    private func ensureHistoryHostingView() {
        guard historyHostingView == nil else { return }
        let hostingView = makeHistoryHostingView()
        addSubview(hostingView)
        historyHostingView = hostingView
        updateEmbeddedSubviewFrames()
    }

    private func updateHistoryHostingVisibility() {
        if model.browseMode.isHistoryMode {
            ensureHistoryHostingView()
        }
        // The embedded queue covers the content region in Playlist mode, so the SwiftUI
        // history subview must stay hidden there regardless of browseMode.
        let inQueueMode = compactMode && compactContentMode == .queue
        let isVisible = model.browseMode.isHistoryMode && !inQueueMode
        historyHostingView?.isHidden = !isVisible
        updateEmbeddedSubviewFrames()
    }

    private func embeddedHistoryContentRect() -> NSRect {
        NSRect(
            x: Layout.borderWidth,
            y: contentRegionBottomY,
            width: bounds.width - Layout.borderWidth * 2,
            height: max(0, listTopY - contentRegionBottomY)
        )
    }

    private func updateEmbeddedSubviewFrames() {
        historyHostingView?.frame = embeddedHistoryContentRect()
        // Flow / Tiles leave the alphabet index beside them.
        list.lens.frame = listLayout().area.divided(atDistance: Layout.alphabetWidth, from: .maxXEdge).remainder
        updateCompactPlayerBarFrame()
        updateCompactPlaylistFrame()
        backdrop.updateFrame()
    }

    func refreshBackdrop() {
        updateHistoryHostingBackground()
        art.showPlayingTrack(WindowManager.shared.audioEngine.currentTrack)
        backdrop.refresh(beneath: self, showsCava: !isPreparingForUITeardown && backdropActive,
                         scope: backdropScope, sharpCorners: sharpCorners)
    }

    /// The Original or Metal skin's colours and corners for the Cava backdrop.
    private static func backdropLook() -> BrowserBackdropLook {
        let skin = ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault()
        return BrowserBackdropLook(background: skin.backgroundColor, low: skin.primaryColor, high: skin.accentColor,
                                   cornerRadius: skin.config.window.cornerRadius ?? 0)
    }

    func stopBackdrop() {
        backdrop.stop()
    }

    /// Create/position/remove the embedded compact player bar to match the current mode.
    private func updateCompactPlayerBarFrame() {
        guard compactMode else {
            compactPlayerBar?.removeFromSuperview()
            compactPlayerBar = nil
            return
        }
        let bar: CompactPlayerBarView
        if let existing = compactPlayerBar {
            bar = existing
        } else {
            bar = CompactPlayerBarView(frame: .zero)
            addSubview(bar)
            compactPlayerBar = bar
            seedCompactPlayerBar(bar)
        }
        bar.frame = NSRect(x: Layout.borderWidth, y: topChromeBottomY,
                           width: bounds.width - Layout.borderWidth * 2,
                           height: compactPlayerBarHeight)
    }

    /// Create/position/remove the embedded compact play queue to match the current mode.
    /// It fills the content region below the toggle strip and covers the library chrome
    /// (server bar / tabs / alphabet index) when shown, so queue mode hides library chrome.
    private func updateCompactPlaylistFrame() {
        guard compactMode else {
            compactPlaylistView?.removeFromSuperview()
            compactPlaylistView = nil
            return
        }
        let queue: ModernPlaylistView
        let didCreateQueue: Bool
        if let existing = compactPlaylistView {
            queue = existing
            didCreateQueue = false
        } else {
            queue = ModernPlaylistView(frame: .zero)
            queue.isEmbedded = true
            // Render above the library chrome and the Cava/art backdrop.
            addSubview(queue)
            compactPlaylistView = queue
            didCreateQueue = true
        }
        let border = Layout.borderWidth
        queue.frame = NSRect(x: border, y: contentRegionBottomY,
                             width: bounds.width - border * 2,
                             height: max(0, topChromeBottomY - contentRegionBottomY))
        queue.isHidden = (compactContentMode != .queue)
        if didCreateQueue {
            // `reloadData()` needs the final frame so it can scroll the current track into view.
            queue.reloadData()
            if compactContentMode == .queue {
                window?.makeFirstResponder(queue)
            }
        }
    }

    /// Refresh the private playlist presentation after the shared audio-engine queue mutates.
    func reloadCompactPlaylist() {
        compactPlaylistView?.reloadData()
    }

    /// Seed the bar with the engine's current state so it isn't blank until the next update tick.
    private func seedCompactPlayerBar(_ bar: CompactPlayerBarView) {
        let engine = WindowManager.shared.audioEngine
        bar.updateTrackInfo(engine.currentTrack)
        bar.updateTime(current: engine.currentTime, duration: engine.duration)
        bar.updatePlaybackState()
    }

    // MARK: - Compact Player Bar Forwarding

    func compactBarUpdateTime(current: TimeInterval, duration: TimeInterval) {
        compactPlayerBar?.updateTime(current: current, duration: duration)
    }

    func compactBarUpdateTrack(_ track: Track?) {
        compactPlayerBar?.updateTrackInfo(track)
    }

    func compactBarUpdatePlaybackState() {
        compactPlayerBar?.updatePlaybackState()
    }

    private var isMetalRenderStyle: Bool {
        // Read from the skin we actually draw with (currentSkin()), not the engine's global
        // currentRenderStyle. The two can momentarily disagree across a skin swap, which let
        // the modern darkened top-chrome band paint over the metal brushed surface.
        currentSkin().renderStyle == .metal
    }

    /// Active metal finish (falls back to Brushed Steel). The control colors below are
    /// derived from its per-finish EQ control palette so they adapt to dark finishes:
    /// on Anodized Black / Gunmetal the band fills go dark and the strokes go light, so
    /// the tab/control boxes stay visible instead of washing out against the chrome.
    private var metalMaterial: MetalMaterial {
        ModernSkinEngine.shared.currentSkin?.metalMaterial ?? .brushedSteel
    }

    // Header/alphabet band — the strip wrapping the top and the right-side alphabet index.
    // In metal mode the top chrome and alphabet index blend into the brushed-metal panel
    // (no darker overlay) so the whole window reads as a single continuous surface.
    private var metalControlBandFill: NSColor {
        .clear
    }

    private var metalControlFill: NSColor {
        metalMaterial.eqControlFill
    }

    private var metalControlActiveFill: NSColor {
        metalMaterial.eqActiveFill
    }

    private var metalControlStroke: NSColor {
        metalMaterial.eqStroke
    }

    private var metalRatingColor: NSColor {
        NSColor(calibratedRed: 0.34, green: 0.28, blue: 0.13, alpha: 1.0)
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let skin = currentSkin()
        let mainOpacity = skin.resolvedOpacity(for: .mainWindow)
        let backgroundOpacity = backdropActive
            ? mainOpacity.background * backdropScrimAlpha
            : mainOpacity.background
        let isShowingCompactPlaylist = compactMode && compactContentMode == .queue

        // Fast path: scroll timer marks only server bar dirty — skip full window redraw.
        // Always fill the full background first (copy blend mode) so the layer is never
        // left partially transparent from accumulated alpha on repeated scroll-tick draws.
        let serverBarY = topChromeBottomY - Layout.serverBarHeight
        let sbRect = NSRect(x: 0, y: serverBarY, width: bounds.width, height: Layout.serverBarHeight)
        if !isShowingCompactPlaylist, sbRect.contains(dirtyRect) {
            // Build the renderer from the current skin (not the cached instance) so the
            // background can't lag a skin swap and render the wrong surface under the bands.
            let renderer = ModernSkinRenderer(skin: skin)
            renderer.drawWindowBackground(
                in: bounds,
                context: context,
                adjacentEdges: adjacentEdges,
                sharpCorners: sharpCorners,
                backgroundOpacity: backgroundOpacity,
                drawMetalAccentStrip: false
            )
            context.saveGState()
            context.setAlpha(mainOpacity.content)
            drawServerBar(in: context, serverBarY: serverBarY, skin: skin)
            context.restoreGState()
            return
        }

        // Normal mode - bottom-left origin (no coordinate flipping)
        let renderer = ModernSkinRenderer(skin: skin)
        renderer.drawWindowBackground(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            backgroundOpacity: backgroundOpacity,
            drawMetalAccentStrip: false
        )
        renderer.drawWindowBorder(
            in: bounds,
            context: context,
            adjacentEdges: adjacentEdges,
            sharpCorners: sharpCorners,
            occlusionSegments: edgeOcclusionSegments,
            borderOpacity: mainOpacity.border
        )

        context.saveGState()
        context.setAlpha(mainOpacity.content)
        
        // Title bar, close button use base (unscaled) coordinates
        // because the renderer's scaledRect() multiplies by scaleFactor
        let scale = ModernSkinElements.scaleFactor
        let baseWidth = bounds.width / scale
        let baseHeight = bounds.height / scale
        
        // Draw title bar
        if !WindowManager.shared.hideTitleBars {
            // Title bar at TOP in base space
            let tbh = ModernSkinElements.titleBarBaseHeight
            let titleBarRect = NSRect(x: 0, y: baseHeight - tbh, width: baseWidth, height: tbh)
            renderer.drawTitleBar(in: titleBarRect, title: "NULLPLAYER LIBRARY", prefix: "library_", context: context)

            // Close button in title bar (base space)
            let closeBtnRect = NSRect(x: baseWidth - 14, y: baseHeight - tbh / 2 - 5, width: 10, height: 10)
            let closeState = isClosePressed ? "pressed" : "normal"
            renderer.drawWindowControlButton("library_btn_close", state: closeState, in: closeBtnRect, context: context)
        }
        
        updateHistoryHostingVisibility()

        // In the compact window's Playlist mode the embedded queue subview fills the content
        // region, so skip drawing the library chrome (server bar / tabs / search / list /
        // alphabet) behind it — the shared Cava/art backdrop then shows through the queue,
        // matching how it shows behind the library list.
        let showLibraryContent = !isShowingCompactPlaylist

        if showLibraryContent {
            // Server bar (below title bar in screen coords)
            drawServerBar(in: context, serverBarY: serverBarY, skin: skin)

            // Tab bar (below server bar)
            let tabBarY = serverBarY - Layout.tabBarHeight
            drawTabBar(in: context, tabBarY: tabBarY, skin: skin)

            // Search bar (below tab bar, only in search mode)
            if model.browseMode == .search {
                drawSearchBar(in: context, searchBarY: listTopY, skin: skin)
            }

            let layout = listLayout()
            let listRect = layout.area

            // Offline volume banner (local source only, under the list)
            if let bannerRect = layout.banner, let label = model.offlineBannerText {
                drawOfflineBanner(label, in: context, rect: bannerRect, skin: skin)
            }

            if model.browseMode.isHistoryMode {
                art.drawBackground(in: context, rect: listRect, flipped: false)
                // SwiftUI-hosted history content is rendered via an embedded subview.
            } else {
                switch model.listState {
                case .notLinked:
                    drawNotLinkedState(in: context, listRect: listRect, skin: skin)
                case .loading:
                    drawLoadingState(in: context, listRect: listRect, skin: skin)
                case .error(let error):
                    drawErrorState(in: context, message: error, listRect: listRect, skin: skin)
                case .rows where list.lens.isPresenting:
                    // The Flow / Tiles view renders the art. Draw nothing here: the window
                    // background (already filled above — translucent when a Cava backdrop is
                    // active, opaque otherwise) is exactly what should sit behind the covers, so
                    // the Cava backdrop shows through at full strength instead of behind a second scrim.
                    listPainter(context, layout, skin: skin).drawAlphabet()
                case .rows where model.displayItems.isEmpty:
                    // An empty list has no columns, so `rows` is the whole list here.
                    drawEmptyState(in: context, listRect: layout.rows, skin: skin)
                case .rows:
                    listPainter(context, layout, skin: skin).drawList()
                }
            }
        }

        // Library | Playlist toggle footer at the bottom (compact window only).
        if compactMode {
            drawCompactFooter(in: context, skin: skin)
        }

        context.restoreGState()

        if coordinator.isHighlighted {
            NSColor.white.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
    }

    // MARK: - Tab Bar Drawing (Modern Boxed Toggle Style)
    
    /// Server-bar field widths at full size, in points before scaling.
    private static let serverFieldWidth: CGFloat = 100
    /// The library field's narrowest width; it grows into the free space before the right-side buttons.
    private static let minLibraryFieldWidth: CGFloat = 80

    /// The side of the square refresh and List / Flow / Tiles buttons.
    private func serverBarButtonSide(m: CGFloat) -> CGFloat {
        Layout.serverBarHeight - 6 * m
    }

    /// Full-size content width needed by the current server-bar state.
    private func serverBarNaturalWidth(font: NSFont) -> CGFloat {
        let m = ModernSkinElements.sizeMultiplier
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth: (String) -> CGFloat = { $0.size(withAttributes: attrs).width }
        let prefixWidth = textWidth("Source: ")
        let leadingInset = 4 * m
        let minimumGap = 12 * m

        var rightWidth = 8 * m + serverBarButtonSide(m: m)
        if list.lens.hasItems {
            rightWidth += 12 * m + viewModeButtonsWidth(m: m)
        }

        let leftWidth: CGFloat
        switch model.sourceBarContent {
        case .builtIn(let name):
            leftWidth = leadingInset + prefixWidth + textWidth(model.withItemCount(name)) + 28 * m + textWidth("+ADD")
        case .server:
            leftWidth = leadingInset + prefixWidth + Self.serverFieldWidth * m + 16 * m +
                textWidth("Lib:") + 4 * m + Self.minLibraryFieldWidth * m
        case .unconfigured(let prompt):
            leftWidth = leadingInset + prefixWidth
            return max(leftWidth + minimumGap + rightWidth,
                       textWidth(prompt) + 2 * max(leftWidth, rightWidth) + 2 * minimumGap)
        }
        return leftWidth + minimumGap + rightWidth
    }

    private func tabRowNaturalWidth(font: NSFont) -> CGFloat {
        let m = ModernSkinElements.sizeMultiplier
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxLabelWidth = LibraryBrowseMode.slotLabels.map { $0.size(withAttributes: attrs).width }.max() ?? 0

        let sortWidth = "Sort".size(withAttributes: attrs).width + 16 * m
        let perTab = maxLabelWidth + 12 * m
        return perTab * CGFloat(LibraryBrowseMode.tabs.count) + sortWidth
    }

    private func topChromeScale(for skin: ModernSkin) -> CGFloat {
        let font = skin.libraryFont(size: compactMode ? 11 : 12)
        let referenceWidth = max(tabRowNaturalWidth(font: font),
                                 serverBarNaturalWidth(font: font))
        let availableWidth = max(0, bounds.width - Layout.borderWidth * 2)
        guard referenceWidth > 0 else { return 1 }
        return min(1, max(0.66, availableWidth / referenceWidth))
    }

    /// Smallest window width at which every full-size compact tab label fits its outline.
    var minimumCompactContentWidth: CGFloat {
        let font = currentSkin().libraryFont(size: 11)
        return ceil(tabRowNaturalWidth(font: font) + Layout.borderWidth * 2)
    }

    private func drawTabBar(in context: CGContext, tabBarY: CGFloat, skin: ModernSkin) {
        let tabBarRect = NSRect(x: Layout.borderWidth, y: tabBarY,
                                width: bounds.width - Layout.borderWidth * 2, height: Layout.tabBarHeight)
        
        // Background
        contentFill(isMetalRenderStyle ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)).setFill()
        context.fill(tabBarRect)

        let chromeScale = topChromeScale(for: skin)
        let font = ModernLibraryTab.font(skin: skin, compact: compactMode, scale: chromeScale)
        
        // Sort indicator width on right
        let sortText = "Sort"
        let sortAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor)
        ]
        let sortSize = sortText.size(withAttributes: sortAttrs)
        let sortWidth = sortSize.width + 16 * ModernSkinElements.sizeMultiplier * chromeScale
        
        let tabsWidth = tabBarRect.width - sortWidth

        // Each tab its label's width plus padding, the leftover shared; hit-testing reads the rects.
        let labels = model.tabLabels
        let padding = 18 * ModernSkinElements.sizeMultiplier * chromeScale
        let widths = LibraryBrowseMode.fitTabWidths(
            labels.map { $0.size(withAttributes: [.font: font]).width + padding }, into: tabsWidth)
        var tabX = tabBarRect.minX
        coordinator.rects.tabs.removeAll(keepingCapacity: true)

        for (index, mode) in LibraryBrowseMode.tabs.enumerated() {
            let tabWidth = widths[index]
            let tabRect = NSRect(x: tabX, y: tabBarY,
                                 width: tabWidth, height: Layout.tabBarHeight)
            tabX += tabWidth

            let label = labels[index]
            let tabInset = 2 * ModernSkinElements.sizeMultiplier * chromeScale
            ModernLibraryTab.draw(label, isActive: mode == model.activeTabSlot,
                          rect: tabRect.insetBy(dx: tabInset,
                                               dy: 2 * ModernSkinElements.sizeMultiplier),
                          font: font, skin: skin, context: context)
            coordinator.rects.tabs.append(tabRect)
        }
        
        // Sort indicator
        let sortRect = NSRect(x: tabBarRect.maxX - sortWidth, y: tabBarY,
                              width: sortWidth, height: Layout.tabBarHeight)
        coordinator.rects.sort = sortRect
        drawInlineTabBarLabel(label: sortText, rect: sortRect,
                              font: font, skin: skin, context: context)
    }
    
    /// Full band of the Library|Playlist toggle footer at the bottom (compact window only),
    /// sitting just above the thin status-bar margin.
    private var compactFooterRect: NSRect {
        NSRect(x: Layout.borderWidth, y: Layout.statusBarHeight,
               width: bounds.width - Layout.borderWidth * 2,
               height: compactFooterHeight)
    }

    /// The two full-width halves of the footer band — (.library, .queue) — used for both
    /// hit-testing and (after insetting to the tab-box size) drawing, mirroring the tab bar.
    private func compactToggleSegmentRects() -> (library: NSRect, queue: NSRect) {
        let strip = compactFooterRect
        let halfWidth = (strip.width / 2).rounded()
        let library = NSRect(x: strip.minX, y: strip.minY, width: halfWidth, height: strip.height)
        let queue = NSRect(x: strip.minX + halfWidth, y: strip.minY,
                           width: strip.width - halfWidth, height: strip.height)
        return (library, queue)
    }

    private func drawCompactFooter(in context: CGContext, skin: ModernSkin) {
        guard compactFooterHeight > 0 else { return }

        // Fill the band to match the tab-bar row so the footer reads as part of the chrome.
        contentFill(isMetalRenderStyle ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)).setFill()
        context.fill(compactFooterRect)

        let chromeScale = topChromeScale(for: skin)
        let font = ModernLibraryTab.font(skin: skin, compact: compactMode, scale: chromeScale)
        let m = ModernSkinElements.sizeMultiplier
        // Same box insets the tab bar uses (drawTabBar), so the toggle boxes match the tabs.
        let insetX = 2 * m * chromeScale
        let insetY = 2 * m
        let segments = compactToggleSegmentRects()
        ModernLibraryTab.draw("Library", isActive: compactContentMode == .library,
                      rect: segments.library.insetBy(dx: insetX, dy: insetY),
                      font: font, skin: skin, context: context)
        ModernLibraryTab.draw("Playlist", isActive: compactContentMode == .queue,
                      rect: segments.queue.insetBy(dx: insetX, dy: insetY),
                      font: font, skin: skin, context: context)
    }

    /// The List / Flow / Tiles buttons: three squares the server bar's height, 2 pt apart.
    private func viewModeButtonsWidth(m: CGFloat) -> CGFloat {
        let count = CGFloat(LibraryViewMode.allCases.count)
        return count * serverBarButtonSide(m: m) + (count - 1) * 2 * m
    }

    private func drawInlineTabBarLabel(label: String, rect: NSRect,
                                       font: NSFont, skin: ModernSkin, context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor)
        ]
        let textSize = label.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: rect.midX - textSize.width / 2,
                                 y: rect.midY - textSize.height / 2)
        drawText(label, at: textOrigin, withAttributes: attrs, context: context)
    }
    
    // MARK: - Server Bar Drawing
    
    private func drawServerBar(in context: CGContext, serverBarY: CGFloat, skin: ModernSkin) {
        let barRect = NSRect(x: Layout.borderWidth, y: serverBarY,
                            width: bounds.width - Layout.borderWidth * 2,
                            height: Layout.serverBarHeight)
        
        contentFill(isMetalRenderStyle ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)).setFill()
        context.fill(barRect)

        let dimColor = skin.textDimColor
        let dataColor = skin.dataColor
        let accentColor = skin.accentColor

        let skinName = ModernSkinEngine.shared.currentSkinName ?? "default"
        let currentScale = ModernSkinElements.sizeMultiplier
        let chromeScale = topChromeScale(for: skin)
        let isMetal = isMetalRenderStyle
        if cachedServerBarFont == nil ||
            cachedServerBarFontSkinName != skinName ||
            cachedServerBarFontScale != currentScale ||
            cachedServerBarIsMetal != isMetal ||
            cachedServerBarCompact != compactMode ||
            cachedServerBarChromeScale != chromeScale {
            let font = skin.libraryFont(size: (compactMode ? 11 : 12) * chromeScale)
            cachedServerBarFont = font
            cachedServerBarFontSkinName = skinName
            cachedServerBarFontScale = currentScale
            cachedServerBarIsMetal = isMetal
            cachedServerBarCompact = compactMode
            cachedServerBarChromeScale = chromeScale
            cachedPrefixAttrs = [.font: font, .foregroundColor: skin.applyTextOpacity(to: dimColor)]
            cachedDataAttrs   = [.font: font, .foregroundColor: skin.applyTextOpacity(to: dataColor)]
            cachedActiveAttrs = [.font: font, .foregroundColor: skin.applyTextOpacity(to: isMetal ? skin.textColor : accentColor)]
        }
        let font = cachedServerBarFont!
        let prefixAttrs = cachedPrefixAttrs!
        let dataAttrs   = cachedDataAttrs!
        let activeAttrs = cachedActiveAttrs!

        let m = ModernSkinElements.sizeMultiplier
        let hm = m * chromeScale
        let textY = barRect.minY + (barRect.height - font.pointSize - 2 * m) / 2

        coordinator.beginServerBar(in: NSRect(x: 0, y: serverBarY, width: bounds.width, height: Layout.serverBarHeight))

        // Common prefix
        let prefix = "Source: "
        drawText(prefix, at: NSPoint(x: barRect.minX + 4 * hm, y: textY), withAttributes: prefixAttrs, context: context)
        let prefixWidth = prefix.size(withAttributes: prefixAttrs).width
        let sourceNameStartX = barRect.minX + 4 * hm + prefixWidth
        
        // Right side: refresh button (F5), boxed like the view-mode buttons
        let buttonSide = serverBarButtonSide(m: m)
        let refreshX = barRect.maxX - buttonSide - 8 * hm
        let refreshBox = NSRect(x: refreshX, y: barRect.minY + 3 * m, width: buttonSide, height: buttonSide)
        let refreshColor = ModernLibraryTab.drawBox(isActive: false, rect: refreshBox, skin: skin, context: context)
        LibraryBarIcon.fill(LibraryBarIcon.refresh,
                            in: refreshBox.insetBy(dx: buttonSide * 0.28, dy: buttonSide * 0.28),
                            color: skin.applyTextOpacity(to: refreshColor), context: context)
        coordinator.rects.refresh = NSRect(x: refreshX, y: barRect.minY,
                                   width: barRect.maxX - refreshX, height: barRect.height)
        
        var visEndX = refreshX

        // List / Flow / Tiles — shown when the current list has art to show.
        if list.lens.hasItems {
            let leadingX = refreshX - 12 * hm - viewModeButtonsWidth(m: m)
            var x = leadingX
            for mode in LibraryViewMode.allCases {
                let rect = NSRect(x: x, y: barRect.minY + 3 * m, width: buttonSide, height: buttonSide)
                let color = ModernLibraryTab.drawBox(isActive: list.lens.mode == mode, rect: rect, skin: skin, context: context)
                mode.drawIcon(in: rect.insetBy(dx: buttonSide * 0.28, dy: buttonSide * 0.28),
                              color: skin.applyTextOpacity(to: color), context: context)
                coordinator.rects.viewModes.append((mode, rect))
                x += buttonSide + 2 * m
            }
            visEndX = leadingX
        }

        // Source-specific content
        switch model.sourceBarContent {
        case .builtIn(let name):
            let sourceText = model.withItemCount(name)
            drawText(sourceText, at: NSPoint(x: sourceNameStartX, y: textY), withAttributes: dataAttrs, context: context)
            let sourceTextWidth = sourceText.size(withAttributes: dataAttrs).width
            coordinator.rects.source = NSRect(x: barRect.minX, y: barRect.minY,
                                      width: sourceNameStartX + sourceTextWidth - barRect.minX,
                                      height: barRect.height)

            let addText = "+ADD"
            let addX = sourceNameStartX + sourceTextWidth + 28 * hm
            drawText(addText, at: NSPoint(x: addX, y: textY), withAttributes: activeAttrs, context: context)
            coordinator.rects.add = NSRect(x: addX, y: barRect.minY,
                                   width: max(addText.size(withAttributes: activeAttrs).width, 50 * hm),
                                   height: barRect.height)

            // Scan animation: small spinner at center of bar while library is scanning
            if model.currentSource.isLocal, coordinator.isLibraryScanning {
                let outerR: CGFloat = 8 * m
                LibraryBrowserListPainter.drawSpinner(
                    in: context, center: CGPoint(x: barRect.midX, y: barRect.midY), innerRadius: 3 * m, outerRadius: outerR,
                    lineWidth: 1.5 * m, color: isMetalRenderStyle ? skin.textColor : skin.accentColor, maxAlpha: 0.9,
                    step: coordinator.spinnerStep)
                let scanText = "SCANNING"
                let scanTextX = barRect.midX + outerR + 6 * m
                drawText(scanText, at: NSPoint(x: scanTextX, y: textY), withAttributes: prefixAttrs, context: context)
            }

        case .server(let serverName, let library):
            coordinator.showNames(server: serverName, library: library)
            let textH = font.pointSize + 4 * m

            let serverNameMaxWidth = Self.serverFieldWidth * hm
            let server = drawScrollingText(serverName, startX: sourceNameStartX, textY: textY,
                                                availableWidth: serverNameMaxWidth, scrollOffset: coordinator.serverName.offset,
                                                textHeight: textH, attributes: dataAttrs, in: context)

            let libLabel = "Lib:"
            let libraryLabelX = sourceNameStartX + serverNameMaxWidth + 16 * hm
            drawText(libLabel, at: NSPoint(x: libraryLabelX, y: textY), withAttributes: prefixAttrs, context: context)

            let libraryX = libraryLabelX + libLabel.size(withAttributes: prefixAttrs).width + 4 * hm
            let libraryText = model.withItemCount(library)
            // The field grows into the free space before the right cluster; it scrolls when even that is short.
            let libraryNameMaxWidth = max(Self.minLibraryFieldWidth * hm, visEndX - 24 * hm - libraryX)
            let libraryName = drawScrollingText(libraryText, startX: libraryX, textY: textY,
                                                 availableWidth: libraryNameMaxWidth, scrollOffset: coordinator.libraryName.offset,
                                                 textHeight: textH, attributes: dataAttrs, in: context)

            coordinator.rects.source = NSRect(x: barRect.minX, y: barRect.minY,
                                      width: sourceNameStartX + serverNameMaxWidth - barRect.minX,
                                      height: barRect.height)
            coordinator.rects.library = NSRect(x: libraryLabelX, y: barRect.minY,
                                       width: libraryX + libraryName.width - libraryLabelX,
                                       height: barRect.height)
            coordinator.namesDrawn(serverCycle: server.cycle, libraryCycle: libraryName.cycle)

        case .unconfigured(let prompt):
            let promptWidth = prompt.size(withAttributes: prefixAttrs).width
            drawText(prompt, at: NSPoint(x: barRect.midX - promptWidth / 2, y: textY), withAttributes: prefixAttrs, context: context)
            coordinator.rects.source = barRect
        }
    }
    
    /// Draw text with circular scrolling when it overflows the available width.
    /// Uses NSAttributedString drawing (system font) rather than bitmap sprites. Returns how far
    /// the text travels before the scroll wraps, or 0 when it fits and does not scroll, and the
    /// width it drew.
    private func drawScrollingText(_ text: String,
                                   startX: CGFloat, textY: CGFloat,
                                   availableWidth: CGFloat,
                                   scrollOffset: CGFloat,
                                   textHeight: CGFloat,
                                   attributes: [NSAttributedString.Key: Any],
                                   in context: CGContext) -> (cycle: CGFloat, width: CGFloat) {
        let textWidth = (text as NSString).size(withAttributes: attributes).width

        // Text fits — draw once with a simple clip, no scrolling artifacts.
        guard textWidth > availableWidth else {
            context.saveGState()
            context.clip(to: NSRect(x: startX, y: textY, width: availableWidth, height: textHeight))
            drawText(text, at: NSPoint(x: startX, y: textY), withAttributes: attributes, context: context)
            context.restoreGState()
            return (0, textWidth)
        }

        let separatorWidth = textWidth * 0.3  // 30% gap before repeat
        let totalCycleWidth = textWidth + separatorWidth

        context.saveGState()
        context.clip(to: NSRect(x: startX, y: textY, width: availableWidth, height: textHeight))

        // Two passes for seamless circular wrap
        for pass in 0..<2 {
            let baseX = startX - scrollOffset + CGFloat(pass) * totalCycleWidth
            if baseX + totalCycleWidth < startX || baseX > startX + availableWidth { continue }
            drawText(text, at: NSPoint(x: baseX, y: textY), withAttributes: attributes, context: context)
        }

        context.restoreGState()
        return (totalCycleWidth, availableWidth)
    }

    /// Draw string text without inheriting parent content alpha attenuation.
    private func drawText(_ text: String, at point: NSPoint,
                          withAttributes attributes: [NSAttributedString.Key: Any],
                          context: CGContext) {
        context.saveGState()
        context.setAlpha(1.0)
        text.draw(at: point, withAttributes: attributes)
        context.restoreGState()
    }

    /// Draw wrapped/truncated string text without inheriting parent content alpha attenuation.
    private func drawText(_ text: String, in rect: NSRect,
                          withAttributes attributes: [NSAttributedString.Key: Any],
                          context: CGContext) {
        context.saveGState()
        context.setAlpha(1.0)
        text.draw(in: rect, withAttributes: attributes)
        context.restoreGState()
    }

    /// Draw wrapped/truncated text without inheriting parent content alpha attenuation.
    private func drawText(_ text: String, in rect: NSRect,
                          options: NSString.DrawingOptions,
                          withAttributes attributes: [NSAttributedString.Key: Any],
                          context: CGContext) {
        context.saveGState()
        context.setAlpha(1.0)
        text.draw(with: rect, options: options, attributes: attributes)
        context.restoreGState()
    }

    // MARK: - Search Bar Drawing
    
    private func drawSearchBar(in context: CGContext, searchBarY: CGFloat, skin: ModernSkin) {
        coordinator.rects.searchBar = NSRect(x: 0, y: searchBarY, width: bounds.width, height: Layout.searchBarHeight)
        let searchRect = NSRect(x: Layout.borderWidth + Layout.padding, y: searchBarY + 3,
                               width: bounds.width - Layout.borderWidth * 2 - Layout.padding * 2,
                               height: Layout.searchBarHeight - 6)
        
        let isFocused = window?.firstResponder === self
        let bgColor: NSColor
        if isMetalRenderStyle {
            bgColor = isFocused ? metalControlActiveFill : metalControlFill
        } else {
            bgColor = isFocused
                ? skin.accentColor.withAlphaComponent(0.15)
                : skin.surfaceColor.withAlphaComponent(0.3)
        }
        contentFill(bgColor).setFill()
        let path = NSBezierPath(roundedRect: searchRect, xRadius: 3, yRadius: 3)
        path.fill()
        
        if isFocused {
            (isMetalRenderStyle ? metalControlStroke : skin.accentColor.withAlphaComponent(0.5)).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
        
        // The same size as the server bar's and tab labels' text.
        let font = skin.libraryFont(size: compactMode ? 11 : 12)
        let placeholder = model.currentSource.isYouTube ? "Search YouTube channels — press ↵" : "Type and press ↵ to search..."
        let displayText = model.searchQuery.isEmpty ? placeholder : model.searchQuery
        let textColor = model.searchQuery.isEmpty ? skin.textDimColor : skin.textColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: textColor)
        ]
        let textSize = displayText.size(withAttributes: attrs)
        let textY = searchRect.minY + (searchRect.height - textSize.height) / 2
        drawText(displayText, at: NSPoint(x: searchRect.minX + 6, y: textY), withAttributes: attrs, context: context)
    }
    
    // MARK: - Offline Volume Banner

    private func drawOfflineBanner(_ label: String, in context: CGContext, rect: NSRect, skin: ModernSkin) {
        // Background — amber tint
        NSColor.systemOrange.withAlphaComponent(0.18).setFill()
        context.fill(rect)

        let font = skin.scaledSystemFont(size: 7.5)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textColor)
        ]
        let textSize = label.size(withAttributes: attrs)
        let textOrigin = NSPoint(x: rect.minX + 6, y: rect.midY - textSize.height / 2)
        drawText(label, at: textOrigin, withAttributes: attrs, context: context)
    }

    // MARK: - List

    /// The shared list painter, in this skin's fonts and colours.
    private func listPainter(_ context: CGContext, _ layout: LibraryBrowserListLayout, skin: ModernSkin) -> LibraryBrowserListPainter {
        let metal = isMetalRenderStyle
        let selected = skin.applyTextOpacity(to: metal ? skin.textColor : skin.accentColor)
        let dim = skin.applyTextOpacity(to: skin.textDimColor)
        let style = LibraryBrowserListPainter.Style(
            titleFont: skin.scaledSystemFont(size: 8),
            detailFont: skin.scaledSystemFont(size: 7.2),
            disclosureFont: skin.scaledSystemFont(size: 6.4),
            title: skin.applyTextOpacity(to: skin.textColor), selectedTitle: selected,
            cell: dim, selectedCell: selected,
            info: dim, selectedInfo: selected,
            disclosure: dim,
            filledStar: metal ? metalRatingColor : NSColor(srgbRed: 0.98, green: 0.78, blue: 0.20, alpha: 1.0),
            emptyStar: dim.withAlphaComponent(0.4),
            // Metal highlights with the green LCD colour of the playlist's now-playing row.
            selectedRowFill: metal ? metalMaterial.displayFill.withAlphaComponent(0.30) : skin.primaryColor.withAlphaComponent(0.06),
            rowFill: nil,
            listFill: nil,
            thumbnailPlaceholder: skin.textDimColor.withAlphaComponent(0.15),
            spinner: skin.applyTextOpacity(to: skin.textColor),
            snapsRowsToPoints: false,
            textIgnoresContentAlpha: true,
            headerFill: contentFill(metal ? metalControlBandFill : skin.surfaceColor.withAlphaComponent(0.4)),
            headerFont: skin.scaledSystemFont(size: 7.2, weight: .medium),
            sortIndicatorFont: skin.scaledSystemFont(size: 5.6),
            headerTitle: skin.applyTextOpacity(to: skin.textDimColor.withAlphaComponent(0.7)),
            sortedHeaderTitle: skin.applyTextOpacity(to: skin.textColor.withAlphaComponent(0.9)),
            headerSeparator: skin.textDimColor.withAlphaComponent(0.2),
            headerBottomLine: skin.textDimColor.withAlphaComponent(0.3),
            // Metal lets the brushed panel show through, so the index reads as part of one surface.
            alphabetFill: contentFill(metal ? .clear : skin.surfaceColor.withAlphaComponent(0.3)),
            letterWithRows: selected,
            letterWithoutRows: skin.applyTextOpacity(to: skin.textDimColor.withAlphaComponent(0.3)))
        return LibraryBrowserListPainter(context: context, layout: layout, style: style, model: model, list: list,
                                         art: art, youtubeVideos: actions.youtubeVideos, isEQMarked: actions.isEQMarked,
                                         thumbnails: rowThumbnails,
                                         spinnerStep: coordinator.spinnerStep)
    }
    // MARK: - State Drawing Methods
    
    private func drawNotLinkedState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        let message = "Link your Plex account to browse your music library"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor),
            .font: NSFont.systemFont(ofSize: 12)
        ]
        let size = message.size(withAttributes: attrs)
        drawText(message, at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2), withAttributes: attrs, context: context)
        
        let hint = "Click the server bar above to link"
        let hintColor = isMetalRenderStyle ? metalRatingColor : skin.warningColor
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.applyTextOpacity(to: hintColor),
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        drawText(hint, at: NSPoint(x: listRect.midX - hintSize.width / 2, y: listRect.midY - size.height / 2 - 20), withAttributes: hintAttrs, context: context)
    }
    
    private func drawLoadingState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        LibraryBrowserListPainter.drawSpinner(in: context, center: CGPoint(x: listRect.midX, y: listRect.midY),
                                              innerRadius: 5, outerRadius: 12, lineWidth: 2.5, color: skin.textColor,
                                              step: coordinator.spinnerStep)
    }

    private func drawErrorState(in context: CGContext, message: String, listRect: NSRect, skin: ModernSkin) {
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor),
            .font: NSFont.systemFont(ofSize: 11)
        ]
        let size = message.size(withAttributes: attrs)
        drawText(message, at: NSPoint(x: listRect.midX - size.width / 2, y: listRect.midY - size.height / 2), withAttributes: attrs, context: context)
    }
    
    private func drawEmptyState(in context: CGContext, listRect: NSRect, skin: ModernSkin) {
        let message = model.emptyMessage(enterKey: "↵")
        let font = skin.libraryFont(size: 10)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: skin.applyTextOpacity(to: skin.textDimColor)
        ]
        let textSize = message.size(withAttributes: attrs)
        let textX = listRect.midX - textSize.width / 2
        let textY = listRect.midY - textSize.height / 2
        drawText(message, at: NSPoint(x: textX, y: textY), withAttributes: attrs, context: context)
    }
    
    // MARK: - List Layout

    /// The bottom of the tab bar, or of the search bar in search mode.
    private var listTopY: CGFloat {
        topChromeBottomY - Layout.serverBarHeight - Layout.tabBarHeight
            - (model.browseMode == .search ? Layout.searchBarHeight : 0)
    }

    private func listLayout() -> LibraryBrowserListLayout {
        // Flow / Tiles draw no column header, so the alphabet index beside them runs full height.
        let (columns, group) = list.headerColumns()
        return LibraryBrowserListLayout(
            content: NSRect(x: Layout.borderWidth, y: contentRegionBottomY,
                            width: bounds.width - Layout.borderWidth * 2, height: listTopY - contentRegionBottomY),
            bannerHeight: model.offlineBannerText == nil ? 0 : Layout.offlineBannerHeight,
            columns: columns, group: group, headerHeight: columnHeaderHeight,
            scrollbarWidth: Layout.scrollbarWidth, alphabetWidth: Layout.alphabetWidth, alphabetBesideHeader: false,
            rowHeight: itemHeight, scale: ModernSkinElements.sizeMultiplier, isFlipped: false
        )
    }


    // MARK: - Hit Testing (Bottom-Left Origin)
    
    private func hitTestTitleBar(at point: NSPoint) -> Bool {
        let m = ModernSkinElements.sizeMultiplier
        return point.y > bounds.height - Layout.titleBarHeight &&
               point.x < bounds.width - 30 * m
    }
    
    private func hitTestCloseButton(at point: NSPoint) -> Bool {
        let m = ModernSkinElements.sizeMultiplier
        let closeRect = NSRect(x: bounds.width - 20 * m, y: bounds.height - Layout.titleBarHeight, width: 20 * m, height: Layout.titleBarHeight)
        return closeRect.contains(point)
    }
    
    // MARK: - Mouse Events
    
    override var acceptsFirstResponder: Bool { true }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        ))
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // When HT is on, record drag start point early so mouseDragged can move the window
        // from anywhere (title bar is hidden so there's no dedicated drag handle)
        if WindowManager.shared.hideTitleBars {
            windowDragStartPoint = event.locationInWindow
            if let window = window {
                WindowManager.shared.windowWillPrimeDragging(window)
                didPrimeWindowDragHold = true
            }
        }

        // Window buttons (only when titlebar is visible)
        if !WindowManager.shared.hideTitleBars {
            if hitTestCloseButton(at: point) { isClosePressed = true; needsDisplay = true; return }
        }

        // Library | Playlist toggle footer (compact window only). The footer band sits below
        // the content region, outside the embedded queue subview's frame, so its clicks
        // always reach the parent regardless of z-order.
        if compactMode, compactFooterHeight > 0 {
            let segments = compactToggleSegmentRects()
            if segments.library.contains(point) {
                if compactContentMode != .library { compactContentMode = .library }
                return
            }
            if segments.queue.contains(point) {
                if compactContentMode != .queue { compactContentMode = .queue }
                return
            }
        }

        // The server bar, tabs, Sort and search; then the column header, alphabet index and rows
        if coordinator.mouseDown(at: point, event: event) || list.mouseDown(at: point, event: event) { return }

        // Title bar drag

        if hitTestTitleBar(at: point) {
            isDraggingWindow = true; windowDragStartPoint = event.locationInWindow
            if let window = window { WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true) }
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if list.mouseDragged(at: convert(event.locationInWindow, from: nil)) { return }

        // When HT is on, lazily start window drag on first mouseDragged (handles content-area drags)
        if !isDraggingWindow && WindowManager.shared.hideTitleBars {
            isDraggingWindow = true
            if let window = window { WindowManager.shared.windowWillStartDragging(window, fromTitleBar: true) }
        }

        if isDraggingWindow, let window = window {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - windowDragStartPoint.x
            let deltaY = currentPoint.y - windowDragStartPoint.y
            var newOrigin = window.frame.origin
            newOrigin.x += deltaX; newOrigin.y += deltaY
            newOrigin = WindowManager.shared.windowWillMove(window, to: newOrigin)
            window.setFrameOrigin(newOrigin)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        list.mouseUp()
        if isDraggingWindow {
            isDraggingWindow = false
            if let window = window { WindowManager.shared.windowDidFinishDragging(window) }
            didPrimeWindowDragHold = false
        } else if didPrimeWindowDragHold {
            if let window = window { WindowManager.shared.windowDidCancelDragPrime(window) }
            didPrimeWindowDragHold = false
        }

        if isClosePressed {
            if hitTestCloseButton(at: point) { window?.close() }
            isClosePressed = false; needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        list.cursor(at: point).set()
        rowThumbnails.hover(at: list.rowIndex(at: point) != nil ? point : nil) { window?.convertToScreen(convert($0, to: nil)) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        RowThumbnailPreview.shared.hide()
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if !list.rightMouseDown(at: convert(event.locationInWindow, from: nil), event: event) {
            super.rightMouseDown(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard list.scrollWheel(event) else {
            if model.browseMode.isHistoryMode { super.scrollWheel(with: event) }
            return
        }
        // The list with its header and the offline banner: a horizontal scroll moves the header too.
        let layout = listLayout()
        setNeedsDisplay(layout.banner.map { layout.area.union($0) } ?? layout.area)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        if !list.keyDown(event) { super.keyDown(with: event) }
    }

    // MARK: - Drag and Drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        coordinator.dragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        coordinator.performDrop(sender)
    }
    
    // MARK: - Notification Handlers
    
    private func invalidateServerBarFontCache() {
        cachedServerBarFont = nil
        cachedServerBarFontSkinName = nil
        cachedServerBarFontScale = nil
        cachedServerBarIsMetal = nil
        cachedServerBarCompact = nil
        cachedPrefixAttrs = nil
        cachedDataAttrs = nil
        cachedActiveAttrs = nil
    }

    @objc private func modernSkinDidChange() {
        let skin = currentSkin()
        historyHostingView?.rootView = StatsContentView(agent: model.history,
                                                        skinTextColor: Color(skin.textColor),
                                                        headerTitle: "Library Data",
                                                        heatmapTheme: ContributionHeatmapTheme(modernSkin: skin))
        historyHostingView?.appearance = NSAppearance.matching(background: skin.backgroundColor)
        updateHistoryHostingBackground()
        list.lens.restyle()
        backdrop.reload()
        invalidateServerBarFontCache()
        updateCornerMask()
        updateEmbeddedSubviewFrames()
        compactPlayerBar?.skinDidChange()
        needsDisplay = true
    }
    
    @objc private func doubleSizeChanged() {
        modernSkinDidChange()
    }

    @objc private func windowLayoutDidChange() {
        guard let window = window else { return }
        let newEdges = WindowManager.shared.computeAdjacentEdges(for: window)
        let newSharp = WindowManager.shared.computeSharpCorners(for: window)
        let newSegments = WindowManager.shared.computeEdgeOcclusionSegments(for: window)
        let cornersChanged = newSharp != sharpCorners
        if newEdges != adjacentEdges || cornersChanged || newSegments != edgeOcclusionSegments {
            adjacentEdges = newEdges
            sharpCorners = newSharp
            edgeOcclusionSegments = newSegments
            needsDisplay = true
        }
        if cornersChanged { window.invalidateSkinShadowShape("corners") }
        updateEmbeddedSubviewFrames()
    }

    func skinDidChange() { modernSkinDidChange() }

    /// Returns the rect of the server bar for targeted redraws.
    private func serverBarRect() -> NSRect {
        let barY = topChromeBottomY - Layout.serverBarHeight
        return NSRect(x: 0, y: barY, width: bounds.width, height: Layout.serverBarHeight)
    }

}
