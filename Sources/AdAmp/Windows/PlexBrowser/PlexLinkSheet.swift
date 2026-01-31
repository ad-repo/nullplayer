import AppKit

/// Sheet for PIN-based Plex account linking
class PlexLinkSheet: NSWindow {
    
    // MARK: - Properties
    
    private var contentBox: NSView!
    private var titleLabel: NSTextField!
    private var instructionLabel: NSTextField!
    private var pinCodeLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var openLinkButton: NSButton!
    private var cancelButton: NSButton!
    
    private var currentPIN: PlexPIN?
    private var linkingTask: Task<Void, Never>?
    
    /// Completion handler called when linking succeeds or is cancelled
    var completionHandler: ((Bool) -> Void)?
    
    // MARK: - Colors (Winamp-inspired)
    
    private struct Colors {
        static let background = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1.0)
        static let titleBar = NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
        static let textNormal = NSColor(calibratedRed: 0.0, green: 0.85, blue: 0.0, alpha: 1.0)
        static let textDim = NSColor(calibratedRed: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
        static let pinCodeColor = NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
        static let border = NSColor(calibratedRed: 0.3, green: 0.3, blue: 0.4, alpha: 1.0)
        static let buttonBackground = NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.25, alpha: 1.0)
    }
    
    // MARK: - Initialization
    
    convenience init() {
        let contentRect = NSRect(x: 0, y: 0, width: 400, height: 300)
        self.init(contentRect: contentRect,
                  styleMask: [.titled, .closable],
                  backing: .buffered,
                  defer: false)
        
        setupWindow()
        setupUI()
    }
    
    private func setupWindow() {
        title = "Link Plex Account"
        backgroundColor = Colors.background
        isReleasedWhenClosed = false
        center()
    }
    
    private func setupUI() {
        contentBox = NSView(frame: contentView!.bounds)
        contentBox.autoresizingMask = [.width, .height]
        contentBox.wantsLayer = true
        contentBox.layer?.backgroundColor = Colors.background.cgColor
        contentView?.addSubview(contentBox)
        
        // Title
        titleLabel = createLabel(text: "Link Plex Account", fontSize: 16, bold: true, color: .white)
        titleLabel.frame = NSRect(x: 20, y: 250, width: 360, height: 24)
        titleLabel.alignment = .center
        contentBox.addSubview(titleLabel)
        
        // Instructions
        let instructions = "To link your Plex account:\n\n1. Go to plex.tv/link\n2. Enter the code shown below"
        instructionLabel = createLabel(text: instructions, fontSize: 12, bold: false, color: Colors.textNormal)
        instructionLabel.frame = NSRect(x: 20, y: 170, width: 360, height: 70)
        instructionLabel.alignment = .center
        contentBox.addSubview(instructionLabel)
        
        // PIN Code display
        pinCodeLabel = createLabel(text: "----", fontSize: 48, bold: true, color: Colors.pinCodeColor)
        pinCodeLabel.frame = NSRect(x: 20, y: 110, width: 360, height: 60)
        pinCodeLabel.alignment = .center
        pinCodeLabel.font = NSFont.monospacedSystemFont(ofSize: 48, weight: .bold)
        contentBox.addSubview(pinCodeLabel)
        
        // Status label
        statusLabel = createLabel(text: "Generating PIN...", fontSize: 11, bold: false, color: Colors.textDim)
        statusLabel.frame = NSRect(x: 20, y: 85, width: 320, height: 20)
        statusLabel.alignment = .center
        contentBox.addSubview(statusLabel)
        
        // Progress indicator
        progressIndicator = NSProgressIndicator(frame: NSRect(x: 350, y: 87, width: 16, height: 16))
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        contentBox.addSubview(progressIndicator)
        
        // Open Link button
        openLinkButton = createButton(title: "Open plex.tv/link", action: #selector(openLinkClicked))
        openLinkButton.frame = NSRect(x: 80, y: 40, width: 140, height: 32)
        contentBox.addSubview(openLinkButton)
        
        // Cancel button
        cancelButton = createButton(title: "Cancel", action: #selector(cancelClicked))
        cancelButton.frame = NSRect(x: 230, y: 40, width: 90, height: 32)
        contentBox.addSubview(cancelButton)
    }
    
    private func createLabel(text: String, fontSize: CGFloat, bold: Bool, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        label.textColor = color
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.maximumNumberOfLines = 0
        return label
    }
    
    private func createButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = NSFont.systemFont(ofSize: 12)
        return button
    }
    
    // MARK: - Linking Flow
    
    /// Start the linking process
    func startLinking() {
        progressIndicator.startAnimation(nil)
        statusLabel.stringValue = "Generating PIN..."
        pinCodeLabel.stringValue = "----"
        openLinkButton.isEnabled = false
        
        linkingTask = Task { @MainActor in
            do {
                // Create PIN
                let pin = try await PlexManager.shared.startLinking()
                self.currentPIN = pin
                
                // Update UI with PIN code
                self.pinCodeLabel.stringValue = pin.code
                self.statusLabel.stringValue = "Waiting for authorization..."
                self.openLinkButton.isEnabled = true
                
                // Poll for authorization
                let success = try await PlexManager.shared.pollForAuthorization(pin: pin) { [weak self] updatedPIN in
                    // Progress callback - could show remaining time
                    DispatchQueue.main.async {
                        self?.statusLabel.stringValue = "Waiting for authorization..."
                    }
                }
                
                if success {
                    self.handleSuccess()
                }
            } catch is CancellationError {
                // User cancelled
            } catch {
                self.handleError(error)
            }
        }
    }
    
    private func handleSuccess() {
        progressIndicator.stopAnimation(nil)
        statusLabel.stringValue = "Account linked successfully!"
        statusLabel.textColor = Colors.textNormal
        
        // Close after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.close()
            self?.completionHandler?(true)
        }
    }
    
    private func handleError(_ error: Error) {
        progressIndicator.stopAnimation(nil)
        statusLabel.stringValue = "Error: \(error.localizedDescription)"
        statusLabel.textColor = NSColor.systemRed
        
        // Allow retry
        openLinkButton.isEnabled = true
        openLinkButton.title = "Try Again"
        openLinkButton.action = #selector(retryClicked)
    }
    
    // MARK: - Actions
    
    @objc private func openLinkClicked() {
        PlexManager.shared.openLinkPage()
    }
    
    @objc private func cancelClicked() {
        linkingTask?.cancel()
        PlexManager.shared.cancelLinking()
        close()
        completionHandler?(false)
    }
    
    @objc private func retryClicked() {
        openLinkButton.title = "Open plex.tv/link"
        openLinkButton.action = #selector(openLinkClicked)
        statusLabel.textColor = Colors.textDim
        startLinking()
    }
    
    // MARK: - Presentation
    
    /// Show the sheet attached to a parent window
    func showAsSheet(from parentWindow: NSWindow, completion: ((Bool) -> Void)? = nil) {
        self.completionHandler = completion
        parentWindow.beginSheet(self) { [weak self] _ in
            self?.linkingTask?.cancel()
        }
        startLinking()
    }
    
    /// Show as a standalone window
    func showAsWindow(completion: ((Bool) -> Void)? = nil) {
        self.completionHandler = completion
        self.level = .modalPanel  // Ensure dialog appears above floating windows
        center()
        makeKeyAndOrderFront(nil)
        startLinking()
    }
}
