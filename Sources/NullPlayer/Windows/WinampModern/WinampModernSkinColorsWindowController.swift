import AppKit

/// The user's own colours for a `.wal` skin — the panel that outranks what the skin resolved (B146).
///
/// **This exists for a class of problem the engine cannot fix.** `WasabiPalette` resolves each role
/// from its own id chain and applies the skin's `<gammaset>`; winampmodern566 ships 88 of those, and
/// several re-tint the list roles into pairings that are simply hard to read. That is not a defect —
/// the engine is reporting what the author wrote. B48 and B122 rescue only *selected* and *current*
/// rows, and B113 records why a plain row on its own plate is deliberately left alone. So there is a
/// whole family of bad-but-authored colour that nothing automatic will ever touch, and the honest
/// answer is to let the user say what they want instead.
///
/// Three things follow from that, and each is visible in the window:
///
/// - **A colour the user picks is taken verbatim.** The legibility guards step aside for an
///   overridden role (`WasabiPalette.isOverridden`), because a panel that previewed one colour and
///   drew another would be lying about the only thing it does.
/// - **Overrides are per theme.** A fix for one `<gammaset>` is the wrong colour under the next, so
///   the header names the theme the pickers are writing into, and the footer's **Reset This Skin**
///   is the only control that can reach the ones set under a theme the user is not looking at.
/// - **The contrast column is measured against the plate the role's own draw fills**, not against a
///   single background — B113's rule, applied to the readout. Row text is weighed on the list plate,
///   selected-row text on the selection bar, tree text on the tree selection.
///
/// Styled from `WindowManager.shared.winampModernSurfaceStyle` like every other surface NullPlayer
/// draws inside a `.wal` skin, and it re-reads on `.hostedSurfaceStyleDidChange` — the theme can move
/// under this window from the skin's own picker, and then it is editing a different theme's slots.
final class WinampModernSkinColorsWindowController: NSWindowController {

    /// One role's row: everything that has to be restyled or re-read when the palette moves.
    private struct Row {
        let role: WasabiPalette.Role
        let label: NSTextField
        let well: NSColorWell
        let contrast: NSTextField
        let reset: NSButton
    }

    private weak var controller: WinampModernMainWindowController?
    private let stack = NSStackView()
    private let header = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private var rows: [Row] = []
    /// Set while `refreshValues` is writing the wells, so the change notifications it provokes are not
    /// read back as the user having picked those colours — which would override all eight roles the
    /// first time the window opened.
    private var isRefreshing = false

    init(controller: WinampModernMainWindowController) {
        self.controller = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Skin Colors"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 420, height: 260)
        super.init(window: window)
        buildContent()
        refreshValues()
        applyStyle()
        NotificationCenter.default.addObserver(self, selector: #selector(paletteDidChange),
                                               name: .hostedSurfaceStyleDidChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Content

    private func buildContent() {
        guard let window else { return }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        header.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(12, after: header)

        for role in WasabiPalette.Role.presentationOrder {
            let row = makeRow(for: role)
            rows.append(row)
            let container = NSStackView(views: [row.label, row.well, row.contrast, row.reset])
            container.orientation = .horizontal
            container.spacing = 8
            container.alignment = .centerY
            stack.addArrangedSubview(container)
            container.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                             constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        }

        let resetAll = NSButton(title: "Reset This Skin", target: self,
                                action: #selector(resetAllTapped))
        resetAll.bezelStyle = .rounded
        footer.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let footerRow = NSStackView(views: [resetAll, footer])
        footerRow.orientation = .horizontal
        footerRow.spacing = 10
        footerRow.alignment = .centerY
        if let last = stack.views.last { stack.setCustomSpacing(16, after: last) }
        stack.addArrangedSubview(footerRow)

        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor)
        ])
    }

    private func makeRow(for role: WasabiPalette.Role) -> Row {
        let label = NSTextField(labelWithString: role.displayName)
        label.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let well = NSColorWell()
        well.target = self
        well.action = #selector(colorChanged(_:))
        well.widthAnchor.constraint(equalToConstant: 54).isActive = true
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let contrast = NSTextField(labelWithString: "")
        contrast.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize,
                                                         weight: .regular)
        contrast.alignment = .right
        contrast.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let reset = NSButton(title: "Reset", target: self, action: #selector(resetRoleTapped(_:)))
        reset.bezelStyle = .rounded
        reset.controlSize = .small

        // The role travels on the controls rather than in a lookup keyed by position, so inserting a
        // row can never re-point an existing one at a different colour.
        let identifier = NSUserInterfaceItemIdentifier(role.rawValue)
        well.identifier = identifier
        reset.identifier = identifier
        return Row(role: role, label: label, well: well, contrast: contrast, reset: reset)
    }

    // MARK: - Reading the current state

    /// Re-read every row from the live palette: the swatch shows the **effective** colour, whether the
    /// user set it or the skin resolved it, and the Reset button is enabled only where they set it.
    func refreshValues() {
        guard let controller, let palette = controller.currentPalette else { return }
        let overrides = controller.paletteOverrides
        isRefreshing = true
        defer { isRefreshing = false }

        header.stringValue = "Overrides for theme: \(controller.activeThemeName)"
        for row in rows {
            let color = palette.color(for: row.role)
            row.well.color = color
            row.reset.isEnabled = overrides[row.role] != nil
            row.contrast.stringValue = contrastText(for: row.role, in: palette)
        }
        let count = overrides.count
        footer.stringValue = count == 0
            ? "No colours overridden in any theme of this skin yet."
            : "\(count) overridden in this theme. Reset clears every theme."
        applyStyle()
    }

    /// The role's colour against the plate its own draw fills (B113), or blank for a role that *is* a
    /// plate and so has no single foreground to be measured against.
    private func contrastText(for role: WasabiPalette.Role, in palette: WasabiPalette) -> String {
        guard let plate = role.contrastPlate else { return "" }
        let ratio = WinampModernSurfaceStyle.contrastRatio(palette.color(for: role),
                                                           palette.color(for: plate))
        let formatted = String(format: "%.1f:1", ratio)
        // Flagged, never blocked: below the threshold the guards use, this pairing is one the user
        // will struggle to read — but it is theirs to choose, so this says so and does nothing.
        return ratio < WinampModernSurfaceStyle.minimumContrast ? "⚠ \(formatted)" : formatted
    }

    // MARK: - Write-back

    @objc private func colorChanged(_ sender: NSColorWell) {
        guard !isRefreshing,
              let raw = sender.identifier?.rawValue,
              let role = WasabiPalette.Role(rawValue: raw) else { return }
        controller?.setPaletteOverride(sender.color, for: role)
    }

    @objc private func resetRoleTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              let role = WasabiPalette.Role(rawValue: raw) else { return }
        controller?.setPaletteOverride(nil, for: role)
    }

    /// Confirmed, because it reaches colours set under themes that are not on screen — the user
    /// cannot see what this is about to discard.
    @objc private func resetAllTapped() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset every colour for this skin?"
        alert.informativeText = "This clears the colours you set by hand under every colour theme of "
            + "this skin, not just \"\(controller?.activeThemeName ?? "")\". The skin's own colours come back."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.controller?.resetAllPaletteOverrides()
        }
    }

    // MARK: - Style

    /// The theme moved under this window — from the skin's own picker, or from the Color Themes menu.
    /// It is now editing a different theme's slots, so the header, the swatches and the enablement all
    /// have to be re-read, not just recoloured.
    @objc private func paletteDidChange() { refreshValues() }

    private func applyStyle() {
        let style = WindowManager.shared.winampModernSurfaceStyle ?? .fallback
        window?.backgroundColor = style.background
        window?.appearance = NSAppearance(named: style.prefersDarkAppearance ? .darkAqua : .aqua)
        header.textColor = style.text
        footer.textColor = style.dimText
        for row in rows {
            row.label.textColor = style.text
            row.contrast.textColor = style.dimText
        }
    }
}
