import AppKit

/// The About nullPlayer panel. Its contents are fixed for the session, so `AppDelegate` builds it
/// once and reopens it; OK and the title-bar close button both just close it.
final class AboutPanel: NSPanel {
    init() {
        // The layout below runs top-down from `y` = 0; the window is then sized to what it
        // consumed, so the panel keeps an even bottom margin whichever rows are shown.
        let windowWidth: CGFloat = 340
        let bottomPadding: CGFloat = 24

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 0),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = "About nullPlayer"
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)  // light text on the dark panel's buttons
        isMovableByWindowBackground = true
        level = .modalPanel  // Ensure dialog appears above floating windows

        // Dark background
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: 0))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1.0).cgColor
        self.contentView = contentView

        var y: CGFloat = -30

        // App icon
        let iconSize: CGFloat = 96
        let iconView = NSImageView(frame: NSRect(x: (windowWidth - iconSize) / 2, y: y - iconSize, width: iconSize, height: iconSize))
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)
        y -= iconSize + 16

        // App name
        let nameLabel = NSTextField(labelWithString: "nullPlayer")
        nameLabel.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        nameLabel.textColor = .white
        nameLabel.alignment = .center
        nameLabel.frame = NSRect(x: 20, y: y - 34, width: windowWidth - 40, height: 34)
        contentView.addSubview(nameLabel)
        y -= 40

        // Version
        let versionLabel = NSTextField(labelWithString: "Version \(BundleHelper.appVersion)")
        versionLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = NSColor(white: 0.6, alpha: 1.0)
        versionLabel.alignment = .center
        versionLabel.frame = NSRect(x: 20, y: y - 18, width: windowWidth - 40, height: 18)
        contentView.addSubview(versionLabel)
        y -= 28

        // Tagline
        let taglineLabel = NSTextField(wrappingLabelWithString: "Your media. Your backend. Your home devices. Your UI.")
        taglineLabel.font = NSFont.systemFont(ofSize: 14)
        taglineLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        taglineLabel.alignment = .center
        taglineLabel.frame = NSRect(x: 20, y: y - 40, width: windowWidth - 40, height: 40)
        contentView.addSubview(taglineLabel)
        y -= 50

        // Separator
        let separator = NSBox(frame: NSRect(x: 40, y: y, width: windowWidth - 80, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)
        y -= 20

        // Credits
        let thanksLabel = NSTextField(labelWithString: "Please add a ⭐ star ⭐ on github")
        thanksLabel.font = NSFont.systemFont(ofSize: 15)
        thanksLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        thanksLabel.alignment = .center
        thanksLabel.frame = NSRect(x: 20, y: y - 18, width: windowWidth - 40, height: 18)
        contentView.addSubview(thanksLabel)
        y -= 42   // 18 label + a blank line's worth of gap before the buttons

        // // sthanks
        // let sthanksLabel = NSTextField(labelWithString: "Thanks to u/SpaXter25 for QE and PD")
        // sthanksLabel.font = NSFont.systemFont(ofSize: 12)
        // sthanksLabel.textColor = NSColor(white: 0.5, alpha: 1.0)
        // sthanksLabel.alignment = .center
        // sthanksLabel.frame = NSRect(x: 20, y: y - 16, width: windowWidth - 40, height: 16)
        // contentView.addSubview(sthanksLabel)
        // y -= 36

        // Buttons (3 on one row)
        let buttonWidth: CGFloat = 90
        let buttonHeight: CGFloat = 28
        let buttonSpacing: CGFloat = 10
        let totalButtonWidth = buttonWidth * 3 + buttonSpacing * 2
        let buttonStartX = (windowWidth - totalButtonWidth) / 2

        // Link buttons: icon beside the title, URL carried in the tooltip. Brand marks are
        // simple-icons (CC0) PDFs, drawn as templates so the dark appearance tints them.
        func addLinkButton(_ title: String, icon: NSImage?, url: String, x: CGFloat, width: CGFloat) {
            let button = NSButton(frame: NSRect(x: x, y: y - buttonHeight, width: width, height: buttonHeight))
            button.title = title
            button.image = icon
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.bezelStyle = .rounded
            button.toolTip = url
            button.target = self
            button.action = #selector(openLink(_:))
            contentView.addSubview(button)
        }
        func brandIcon(_ name: String) -> NSImage? {
            guard let url = BundleHelper.url(forResource: name, withExtension: "pdf", subdirectory: "BrandIcons"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.size = NSSize(width: 14, height: 14)
            image.isTemplate = true
            return image
        }

        addLinkButton("nullplayer.fyi", icon: NSImage(systemSymbolName: "globe", accessibilityDescription: nil),
                      url: "https://nullplayer.fyi/", x: buttonStartX, width: totalButtonWidth)
        y -= buttonHeight + 12
        addLinkButton("GitHub", icon: brandIcon("github"), url: "https://github.com/ad-repo",
                      x: buttonStartX, width: buttonWidth)
        addLinkButton("LinkedIn", icon: brandIcon("linkedin"), url: "https://www.linkedin.com/in/andrew-d-9b83aa148/",
                      x: buttonStartX + buttonWidth + buttonSpacing, width: buttonWidth)
        addLinkButton("Reddit", icon: brandIcon("reddit"), url: "https://www.reddit.com/r/NullPlayer/",
                      x: buttonStartX + (buttonWidth + buttonSpacing) * 2, width: buttonWidth)
        y -= buttonHeight + 12
        if !BundleHelper.isAppStoreBuild {
            addLinkButton("Support on Ko-fi", icon: brandIcon("kofi"), url: "https://ko-fi.com/nullplayer",
                          x: buttonStartX, width: totalButtonWidth)
            y -= buttonHeight + 12
        }

        // Disclaimer
        let disclaimerLabel = NSTextField(wrappingLabelWithString: "This is a clean room project")
        disclaimerLabel.font = NSFont.systemFont(ofSize: 12)
        disclaimerLabel.textColor = NSColor(white: 0.4, alpha: 1.0)
        disclaimerLabel.alignment = .center
        disclaimerLabel.frame = NSRect(x: 20, y: y - 28, width: windowWidth - 40, height: 28)
        contentView.addSubview(disclaimerLabel)
        y -= 36

        // OK button (centered, prominent)
        let okButton = NSButton(frame: NSRect(x: (windowWidth - buttonWidth) / 2, y: y - buttonHeight, width: buttonWidth, height: buttonHeight))
        okButton.title = "OK"
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"  // Enter key closes
        okButton.target = self
        okButton.action = #selector(performClose(_:))
        contentView.addSubview(okButton)
        y -= buttonHeight

        // Size the window to the consumed height and lift the rows into it
        let windowHeight = bottomPadding - y
        setContentSize(NSSize(width: windowWidth, height: windowHeight))
        for subview in contentView.subviews { subview.frame.origin.y += windowHeight }
        center()
    }

    @objc private func openLink(_ sender: NSButton) {
        if let link = sender.toolTip, let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
