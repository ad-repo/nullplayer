import AppKit

/// What a library browser view does that is not drawing, shared by the classic and modern views.
/// It takes the model's changes and passes each to the list and the view; follows the window
/// (minimized, covered, highlighted in a docked group) and the library scan; handles clicks on the
/// server bar's buttons, the tabs, the Sort button and the search bar, and files dropped on the
/// browser; runs the server and library names' scroll and steps the spinners; and
/// tears the model, actions and list down. Each view draws the controls in its own coordinates and
/// records where in `rects`; clicks reach here in the same coordinates, as they reach
/// `LibraryBrowserList`.
@MainActor
final class LibraryBrowserCoordinator: NSObject {
    enum Region {
        case all
        /// The list area: a row's or the loading spinner turned.
        case list
        /// The server bar: its names scrolled or the scan spinner turned.
        case serverBar
    }

    struct Host {
        let redraw: (Region) -> Void
        /// The Data tab may have shown or hidden.
        let updateHistory: () -> Void
        /// The window was minimized, restored, covered or uncovered: the Cava backdrop pauses or resumes.
        let visibilityChanged: () -> Void
    }

    /// Where the view last drew each control. Each band resets its own rects as it is drawn, never
    /// the whole set at once: the names' scroll redraws the server bar alone, which must leave the
    /// tabs' and Sort's rects in place.
    struct Rects {
        /// The server bar's full band, and its buttons.
        var serverBar = NSRect.zero
        var refresh = NSRect.zero
        var source = NSRect.zero
        var library = NSRect.zero
        var add = NSRect.zero
        var viewModes: [(mode: LibraryViewMode, rect: NSRect)] = []
        /// One per `LibraryBrowseMode.tabs` slot.
        var tabs: [NSRect] = []
        var sort = NSRect.zero
        /// The search bar's band; it takes clicks only while the Search tab shows.
        var searchBar = NSRect.zero
    }

    /// A name that scrolls through its field when it overflows.
    struct Marquee {
        private(set) var offset: CGFloat = 0
        private var text = ""
        /// How far the text travels before the scroll wraps; 0 while it fits.
        fileprivate(set) var cycleWidth: CGFloat = 0

        fileprivate mutating func show(_ text: String) {
            guard text != self.text else { return }
            self.text = text
            offset = 0
        }

        fileprivate mutating func advance() {
            offset = offset + 1 < cycleWidth ? offset + 1 : 0
        }

        fileprivate mutating func reset() {
            offset = 0
        }
    }

    private unowned let view: NSView
    private let model: LibraryBrowserModel
    private let actions: LibraryBrowserActions
    private let list: LibraryBrowserList
    private let host: Host

    var rects = Rects()
    private(set) var serverName = Marquee()
    private(set) var libraryName = Marquee()
    private var marqueeTimer: Timer?

    /// The loading, row and scan spinners' step, advanced while one turns.
    private(set) var spinnerStep = 0
    private(set) var isLibraryScanning = false
    private var spinnerTimer: Timer?

    /// Drag-mode feedback: the window is part of a highlighted docked group.
    private(set) var isHighlighted = false

    init(view: NSView, model: LibraryBrowserModel, actions: LibraryBrowserActions, list: LibraryBrowserList, host: Host) {
        self.view = view
        self.model = model
        self.actions = actions
        self.list = list
        self.host = host
    }

    deinit {
        spinnerTimer?.invalidate()
        marqueeTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    /// Listen to the model and the window, and load the first rows.
    func start() {
        let observers: [(Selector, Notification.Name)] = [
            (#selector(windowVisibilityDidChange(_:)), NSWindow.didMiniaturizeNotification),
            (#selector(windowVisibilityDidChange(_:)), NSWindow.didDeminiaturizeNotification),
            (#selector(windowVisibilityDidChange(_:)), NSWindow.didChangeOcclusionStateNotification),
            (#selector(libraryScanProgressChanged), MediaLibrary.scanProgressNotification),
            (#selector(connectedWindowHighlightDidChange(_:)), .connectedWindowHighlightDidChange),
            // A row thumbnail or YouTube avatar finished loading.
            (#selector(rowThumbnailDidLoad), LibraryRowThumbnails.didLoadNotification),
        ]
        for (selector, name) in observers {
            NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
        }
        model.onChange = { [weak self] in self?.modelDidChange($0) }
        model.reloadData()
        startMarquee()
    }

    /// Cancel every in-flight load, action and timer before the view is torn down, so nothing
    /// pins it alive or touches dead UI.
    func teardown() {
        model.cancelAll()
        actions.cancelAll()
        stopSpinner()
        stopMarquee()
        list.teardown()
    }

    private func modelDidChange(_ change: LibraryBrowserModel.Change) {
        list.modelDidChange(change)
        switch change {
        case .rows, .reveal, .columns:
            host.redraw(.all)
        case .listState:
            updateSpinner()
            host.redraw(.all)
        case .rowsReplaced:
            if model.browseMode.isHistoryMode { host.updateHistory() }
        case .rebuilt:
            break
        case .loaded:
            // The offline banner (local source, a folder offline) takes list height from Flow / Tiles.
            view.needsLayout = true
        case .source:
            view.needsLayout = true
            startMarquee()
        case .browseMode:
            host.updateHistory()
            host.redraw(.all)
        }
    }

    // MARK: - Clicks

    /// A click on the server bar, a tab, the Sort button or the search bar. Returns false when
    /// `point` is on none of them.
    func mouseDown(at point: NSPoint, event: NSEvent) -> Bool {
        if rects.serverBar.contains(point) {
            clickServerBar(at: point, event: event)
        } else if rects.sort.contains(point) {
            popDown(actions.sortMenu(), from: event)
        } else if let index = rects.tabs.firstIndex(where: { $0.contains(point) }),
                  LibraryBrowseMode.tabs.indices.contains(index) {
            model.selectTab(LibraryBrowseMode.tabs[index], doubleClick: event.clickCount == 2)
            view.window?.makeFirstResponder(view)
        } else if model.browseMode == .search, rects.searchBar.contains(point) {
            view.window?.makeFirstResponder(view)
        } else {
            return false
        }
        return true
    }

    private func clickServerBar(at point: NSPoint, event: NSEvent) {
        if let hit = rects.viewModes.first(where: { $0.rect.contains(point) }) {
            list.lens.mode = hit.mode
            host.redraw(.all)
        } else if model.needsPlexLink {
            actions.host.presentLinkSheet()
        } else if rects.refresh.contains(point) {
            model.refreshCurrentSource()
        } else if rects.add.contains(point), let menu = actions.addMenu() {
            popDown(menu, from: event)
        } else if rects.library.contains(point), let menu = actions.libraryMenu() {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if rects.source.contains(point) {
            popDown(actions.sourceMenu(), from: event)
        }
    }

    /// A server-bar menu, dropped down from the click.
    private func popDown(_ menu: NSMenu, from event: NSEvent) {
        menu.popUp(positioning: nil, at: NSPoint(x: event.locationInWindow.x, y: event.locationInWindow.y - 5),
                   in: view.window?.contentView)
    }

    // MARK: - Drops

    /// Local files, folders and playlists dropped on the browser are added to the library.
    func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return [] }
        return LocalFileDiscovery.hasSupportedDropContent(items, includeVideo: true, includePlaylists: true) ? .copy : []
    }

    func performDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return false }
        return actions.addDroppedItems(items)
    }

    // MARK: - Server bar names

    /// A server bar is being drawn into `band`: its buttons and names are recorded afresh.
    func beginServerBar(in band: NSRect) {
        rects.serverBar = band
        rects.refresh = .zero
        rects.source = .zero
        rects.library = .zero
        rects.add = .zero
        rects.viewModes = []
        serverName.cycleWidth = 0
        libraryName.cycleWidth = 0
    }

    /// The server and library names the bar shows; a changed name scrolls from its start.
    func showNames(server: String, library: String) {
        serverName.show(server)
        libraryName.show(library)
    }

    /// The names as just drawn: how far each travels before it wraps, 0 when it fits. Either one
    /// overflowing starts the scroll.
    func namesDrawn(serverCycle: CGFloat, libraryCycle: CGFloat) {
        serverName.cycleWidth = serverCycle
        libraryName.cycleWidth = libraryCycle
        if serverCycle > 0 || libraryCycle > 0 { startMarquee() }
    }

    func startMarquee() {
        guard marqueeTimer == nil else { return }
        marqueeTimer = Timer.scheduledTimer(withTimeInterval: 0.067, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.marqueeTick() }
        }
    }

    private func stopMarquee() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        serverName.reset()
        libraryName.reset()
    }

    private func marqueeTick() {
        guard let window = view.window, window.isVisible, window.occlusionState.contains(.visible) else { return }
        guard serverName.cycleWidth > 0 || libraryName.cycleWidth > 0 else {
            let hadOffset = serverName.offset != 0 || libraryName.offset != 0
            stopMarquee()
            if hadOffset { host.redraw(.serverBar) }
            return
        }
        serverName.advance()
        libraryName.advance()
        host.redraw(.serverBar)
    }

    // MARK: - Spinners

    /// A YouTube download or a channel's uploads started or finished loading.
    func busyChanged() {
        updateSpinner()
        host.redraw(.all)
    }

    /// Turn the spinners while the rows or the library scan have something in flight.
    private func updateSpinner() {
        if actions.rowsAreBusy || isLibraryScanning { startSpinner() } else { stopSpinner() }
    }

    private func startSpinner() {
        guard spinnerTimer == nil else { return }
        // In .common mode, so the spinner keeps turning while a context menu is open.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.spinnerTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        spinnerTimer = timer
    }

    private func spinnerTick() {
        let rowsAreBusy = actions.rowsAreBusy
        guard rowsAreBusy || isLibraryScanning else { stopSpinner(); return }
        spinnerStep += 1
        if rowsAreBusy { host.redraw(.list) }
        if isLibraryScanning { host.redraw(.serverBar) }
    }

    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        spinnerStep = 0
    }

    // MARK: - Notifications

    @objc private func windowVisibilityDidChange(_ notification: Notification) {
        guard let window = view.window, notification.object as? NSWindow === window else { return }
        switch notification.name {
        case NSWindow.didMiniaturizeNotification: stopMarquee()
        case NSWindow.didDeminiaturizeNotification: startMarquee()
        default:
            if window.occlusionState.contains(.visible) { startMarquee() } else { stopMarquee() }
        }
        host.visibilityChanged()
    }

    @objc private func libraryScanProgressChanged() {
        let scanning = MediaLibrary.shared.isScanning
        guard scanning != isLibraryScanning else { return }
        isLibraryScanning = scanning
        updateSpinner()
        if !scanning { host.redraw(.all) }
    }

    @objc private func connectedWindowHighlightDidChange(_ notification: Notification) {
        let highlighted = notification.userInfo?["highlightedWindows"] as? Set<NSWindow> ?? []
        let newValue = highlighted.contains { $0 === view.window }
        guard newValue != isHighlighted else { return }
        isHighlighted = newValue
        host.redraw(.all)
    }

    @objc private func rowThumbnailDidLoad() {
        host.redraw(.all)
    }
}
