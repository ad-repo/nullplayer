import AppKit

/// Controller for the debug console window
class DebugWindowController: NSWindowController, NSWindowDelegate {
    
    // MARK: - Properties
    
    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var stopToolbarItem: NSToolbarItem?
    private var upnpFilterToolbarItem: NSToolbarItem?
    
    /// Whether to hide UPnPManager messages (hidden by default to reduce noise)
    private var hideUPnPMessages = true
    
    // MARK: - Initialization
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.init(window: window)
        setupWindow()
        setupViews()
        setupToolbar()
        loadExistingMessages()
        subscribeToMessages()
    }
    
    // MARK: - Setup
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "NullPlayer Debug Console"
        window.minSize = NSSize(width: 400, height: 200)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        
        // Set accessibility
        window.setAccessibilityIdentifier("DebugConsoleWindow")
        window.setAccessibilityLabel("Debug Console Window")
    }
    
    private func setupViews() {
        guard let window = window else { return }
        
        // Create scroll view
        scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        
        // Create text view
        let contentSize = scrollView.contentSize
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        
        // Console-style appearance
        textView.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        textView.textColor = NSColor(white: 0.9, alpha: 1.0)
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        
        scrollView.documentView = textView
        window.contentView?.addSubview(scrollView)
    }
    
    private func setupToolbar() {
        guard let window = window else { return }
        
        let toolbar = NSToolbar(identifier: "DebugConsoleToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
    }
    
    private func loadExistingMessages() {
        let messages = getFilteredMessages()
        if !messages.isEmpty {
            let text = messages.joined(separator: "\n") + "\n"
            textView.string = text
            scrollToBottom()
        }
    }
    
    private func getFilteredMessages() -> [String] {
        var messages = DebugConsoleManager.shared.getMessages()
        if hideUPnPMessages {
            messages = messages.filter { !$0.contains("UPnPManager") }
        }
        return messages
    }
    
    private func subscribeToMessages() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewMessage),
            name: DebugConsoleManager.messageReceivedNotification,
            object: nil
        )
    }
    
    // MARK: - Message Handling
    
    @objc private func handleNewMessage() {
        // Reload all messages (simple approach)
        let messages = getFilteredMessages()
        let text = messages.joined(separator: "\n") + (messages.isEmpty ? "" : "\n")
        textView.string = text
        scrollToBottom()
    }
    
    private func scrollToBottom() {
        textView.scrollToEndOfDocument(nil)
    }
    
    // MARK: - Actions
    
    @objc func clearConsole(_ sender: Any?) {
        DebugConsoleManager.shared.clearMessages()
        textView.string = ""
    }
    
    @objc func copyAll(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
    }
    
    @objc func toggleCapture(_ sender: Any?) {
        if DebugConsoleManager.shared.isCapturing {
            DebugConsoleManager.shared.stopCapturing()
        } else {
            DebugConsoleManager.shared.startCapturing()
        }
        updateStopButtonState()
    }
    
    @objc func toggleUPnPFilter(_ sender: Any?) {
        hideUPnPMessages.toggle()
        updateUPnPFilterButtonState()
        // Refresh display with new filter state
        handleNewMessage()
    }
    
    private func updateStopButtonState() {
        guard let item = stopToolbarItem else { return }
        let isCapturing = DebugConsoleManager.shared.isCapturing
        
        // Use colored symbols to make state clear
        // Red stop = capturing (click to stop)
        // Green play = paused (click to start)
        let symbolName = isCapturing ? "stop.circle.fill" : "play.circle.fill"
        let color = isCapturing ? NSColor.systemRed : NSColor.systemGreen
        
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isCapturing ? "Stop" : "Start") {
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            item.image = image.withSymbolConfiguration(config)
        }
        
        item.label = isCapturing ? "Logging" : "Paused"
        item.toolTip = isCapturing ? "Click to pause logging" : "Click to resume logging"
    }
    
    private func updateUPnPFilterButtonState() {
        guard let item = upnpFilterToolbarItem else { return }
        
        // Use eye symbol - slashed when filtering (hiding)
        let symbolName = hideUPnPMessages ? "eye.slash" : "eye"
        let color = hideUPnPMessages ? NSColor.systemOrange : NSColor.secondaryLabelColor
        
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: hideUPnPMessages ? "Show UPnP" : "Hide UPnP") {
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            item.image = image.withSymbolConfiguration(config)
        }
        
        item.label = hideUPnPMessages ? "UPnP Hidden" : "UPnP Shown"
        item.toolTip = hideUPnPMessages ? "Click to show UPnP messages" : "Click to hide UPnP messages"
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Just hide, don't destroy
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - NSToolbarDelegate

extension DebugWindowController: NSToolbarDelegate {
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier.rawValue {
        case "Stop":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let isCapturing = DebugConsoleManager.shared.isCapturing
            
            // Use colored symbols to make state clear
            let symbolName = isCapturing ? "stop.circle.fill" : "play.circle.fill"
            let color = isCapturing ? NSColor.systemRed : NSColor.systemGreen
            
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isCapturing ? "Stop" : "Start") {
                let config = NSImage.SymbolConfiguration(paletteColors: [color])
                item.image = image.withSymbolConfiguration(config)
            }
            
            item.label = isCapturing ? "Logging" : "Paused"
            item.toolTip = isCapturing ? "Click to pause logging" : "Click to resume logging"
            item.target = self
            item.action = #selector(toggleCapture(_:))
            stopToolbarItem = item
            return item
            
        case "Clear":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Clear"
            item.toolTip = "Clear console"
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")
            item.target = self
            item.action = #selector(clearConsole(_:))
            return item
            
        case "Copy":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Copy All"
            item.toolTip = "Copy all text"
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
            item.target = self
            item.action = #selector(copyAll(_:))
            return item
            
        case "UPnPFilter":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            
            // Use eye symbol - normal when showing, slashed when hiding
            let symbolName = hideUPnPMessages ? "eye.slash" : "eye"
            let color = hideUPnPMessages ? NSColor.systemOrange : NSColor.secondaryLabelColor
            
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: hideUPnPMessages ? "Show UPnP" : "Hide UPnP") {
                let config = NSImage.SymbolConfiguration(paletteColors: [color])
                item.image = image.withSymbolConfiguration(config)
            }
            
            item.label = hideUPnPMessages ? "UPnP Hidden" : "UPnP Shown"
            item.toolTip = hideUPnPMessages ? "Click to show UPnP messages" : "Click to hide UPnP messages"
            item.target = self
            item.action = #selector(toggleUPnPFilter(_:))
            upnpFilterToolbarItem = item
            return item
            
        default:
            return nil
        }
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("Stop"),
            NSToolbarItem.Identifier("Clear"),
            NSToolbarItem.Identifier("Copy"),
            NSToolbarItem.Identifier("UPnPFilter"),
            .flexibleSpace
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }
}
