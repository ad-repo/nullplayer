import AppKit

/// The settings a `.wal` skin registered but gave the user no way to reach (Phase 27.3).
///
/// A Winamp 5.x skin registers its own options with `Config.newItem` / `ConfigItem.newAttribute`
/// and expects **Winamp's preferences dialog** to list them; many skins bind no control of their
/// own to any of them. Defix Hi-End 200 registers eight display styles (`Audio cassette`,
/// `Left Right VU`, seven analog VU meters) and three songticker modes that way, ships all the
/// artwork, and offers no switch anywhere in the skin — so seven of its eight displays could not be
/// selected at all.
///
/// This window is that missing dialog, and nothing else: it lists exactly what the loaded skin
/// registered, in registration order, grouped by the item that owns it. It knows nothing about any
/// particular skin. Writes go through `WinampModernScriptRuntime.setConfigAttribute`, the same route
/// a `cfgattrib` control the skin drew itself uses, so the skin applies the change from its own
/// `onDataChanged` handler exactly as it would in Winamp.
final class WinampModernSkinSettingsWindowController: NSWindowController {
    private struct Section {
        let name: String
        var settings: [WinampModernScriptRuntime.RegisteredSetting]
    }

    private weak var runtime: WinampModernScriptRuntime?
    private var controlsBySetting: [String: NSControl] = [:]
    private let stack = NSStackView()

    /// A boolean-valued setting — the overwhelming majority — draws as a checkbox; anything else
    /// gets a text field, because the skin's own meaning for it is unknowable from here.
    private static func isToggle(_ value: String) -> Bool {
        ["0", "1"].contains(value.trimmingCharacters(in: .whitespaces))
    }

    init(runtime: WinampModernScriptRuntime) {
        self.runtime = runtime
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Skin Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 320, height: 200)
        super.init(window: window)
        buildContent()
        applyStyle()
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange),
                                               name: .winampModernThemeDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Content

    private var sections: [Section] {
        guard let runtime else { return [] }
        var ordered: [Section] = []
        for setting in runtime.presentableSettings {
            if let index = ordered.firstIndex(where: { $0.name == setting.sectionName }) {
                ordered[index].settings.append(setting)
            } else {
                ordered.append(Section(name: setting.sectionName, settings: [setting]))
            }
        }
        return ordered
    }

    private func buildContent() {
        guard let window, let runtime else { return }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for section in sections {
            let header = NSTextField(labelWithString: section.name)
            header.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            if !stack.views.isEmpty { stack.setCustomSpacing(16, after: stack.views[stack.views.count - 1]) }
            stack.addArrangedSubview(header)
            for setting in section.settings {
                stack.addArrangedSubview(control(for: setting, value: runtime.configAttributeValue(setting)))
            }
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)
        scroll.documentView = documentView

        let content = NSView()
        content.addSubview(scroll)
        window.contentView = content
        scroll.frame = content.bounds
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
    }

    private func control(for setting: WinampModernScriptRuntime.RegisteredSetting,
                         value: String) -> NSView {
        let key = Self.key(for: setting)
        if Self.isToggle(value) {
            let button = NSButton(checkboxWithTitle: setting.name, target: self,
                                  action: #selector(toggleChanged(_:)))
            button.state = value.trimmingCharacters(in: .whitespaces) == "1" ? .on : .off
            button.identifier = NSUserInterfaceItemIdentifier(key)
            controlsBySetting[key] = button
            return button
        }
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let label = NSTextField(labelWithString: setting.name)
        let field = NSTextField(string: value)
        field.identifier = NSUserInterfaceItemIdentifier(key)
        field.target = self
        field.action = #selector(fieldChanged(_:))
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        controlsBySetting[key] = field
        row.addArrangedSubview(label)
        row.addArrangedSubview(field)
        return row
    }

    private static func key(for setting: WinampModernScriptRuntime.RegisteredSetting) -> String {
        "\(setting.section)\u{1}\(setting.name)"
    }

    // MARK: - Write-back

    @objc private func toggleChanged(_ sender: NSButton) {
        write(identifier: sender.identifier?.rawValue, value: sender.state == .on ? "1" : "0")
    }

    @objc private func fieldChanged(_ sender: NSTextField) {
        write(identifier: sender.identifier?.rawValue, value: sender.stringValue)
    }

    private func write(identifier: String?, value: String) {
        guard let identifier, let runtime,
              let setting = runtime.registeredSettings.first(where: { Self.key(for: $0) == identifier })
        else { return }
        runtime.setConfigAttribute(section: setting.section, key: setting.name, value: value)
        // A skin's `onDataChanged` may write further attributes of its own (choosing one display
        // style switches the others off), so the whole list is re-read rather than just this row.
        refreshValues()
        WindowManager.shared.refreshWinampModernSurfaces()
    }

    /// Re-read every control from the configuration, without rebuilding the window.
    func refreshValues() {
        guard let runtime else { return }
        for setting in runtime.presentableSettings {
            let value = runtime.configAttributeValue(setting)
            switch controlsBySetting[Self.key(for: setting)] {
            case let button as NSButton:
                button.state = value.trimmingCharacters(in: .whitespaces) == "1" ? .on : .off
            case let field as NSTextField:
                if field.currentEditor() == nil { field.stringValue = value }
            default: break
            }
        }
    }

    // MARK: - Style

    @objc private func themeDidChange() { applyStyle() }

    /// Palette-themed like every other surface NullPlayer draws inside a `.wal` skin — never
    /// classic-skinned, which would colour it from a `.wsz` the user is not looking at.
    private func applyStyle() {
        let style = WindowManager.shared.winampModernSurfaceStyle ?? .fallback
        window?.backgroundColor = style.background
        for view in stack.views { apply(style, to: view) }
    }

    private func apply(_ style: WinampModernSurfaceStyle, to view: NSView) {
        switch view {
        case let button as NSButton:
            button.attributedTitle = NSAttributedString(
                string: button.title, attributes: [.foregroundColor: style.text,
                                                   .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        case let field as NSTextField:
            field.textColor = style.text
            if field.isEditable {
                // `backgroundColor` alone does nothing on an NSTextField (CLAUDE.md).
                field.backgroundColor = style.barBackground
                field.drawsBackground = true
            }
        case let row as NSStackView:
            for child in row.views { apply(style, to: child) }
        default: break
        }
    }
}
