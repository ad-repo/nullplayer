import AppKit

/// One of the Studio's two looks. Fixed colours and type — only the rim around it takes the skin's
/// colours. One layout and one drawing path read it; the looks differ only in these values.
struct StudioFaceplate {
    enum Kind: String { case console, boutique }

    let kind: Kind
    let panel: NSColor
    let well: NSColor
    let edge: NSColor
    let text: NSColor
    let dimText: NSColor
    let accent: NSColor
    let scale: NSColor
    let slot: NSColor
    /// Fader caps by range: low, mid, high.
    let caps: [NSColor]
    let meter: NSColor
    let meterHot: NSColor
    let peak: NSColor
    let legendFont: NSFont
    let buttonFont: NSFont
    let titleFont: NSFont

    static let defaultsKey = "equalizerStudioFaceplate"

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    private static func font(_ name: String, _ size: CGFloat, fallback weight: NSFont.Weight) -> NSFont {
        NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    func capColor(band: Int) -> NSColor { caps[band < 10 ? 0 : band < 21 ? 1 : 2] }

    /// Console: SSL / Neve / Manley mastering — matte grey-blue, engraved scales, colour-coded caps,
    /// condensed legends, bar metering on a dB graticule.
    static let console = StudioFaceplate(
        kind: .console, panel: rgb(0x4a5463), well: rgb(0x1b2027), edge: rgb(0x2b313a),
        text: rgb(0xe6e9ec), dimText: rgb(0x9ba5b0), accent: rgb(0xf2b33d), scale: rgb(0xc9ced4),
        slot: rgb(0x14181d), caps: [rgb(0xd9822b), rgb(0xe9e3d1), rgb(0x3f7fd9)],
        meter: rgb(0x4fc36b), meterHot: rgb(0xe6c341), peak: rgb(0xff5a4a),
        legendFont: font("AvenirNextCondensed-DemiBold", 8, fallback: .semibold),
        buttonFont: font("AvenirNextCondensed-Bold", 10, fallback: .bold),
        titleFont: font("AvenirNextCondensed-DemiBold", 14, fallback: .semibold))

    /// Boutique DSP: Weiss / Dangerous / Bricasti — flat black glass, thin type, one subtle accent,
    /// slim line faders, the analyser as a filled curve on a fine grid.
    static let boutique = StudioFaceplate(
        kind: .boutique, panel: rgb(0x0b0c0e), well: rgb(0x050607), edge: rgb(0x1c1e22),
        text: rgb(0xd9dbde), dimText: rgb(0x6d727a), accent: rgb(0x7cc4e4), scale: rgb(0x23262b),
        slot: rgb(0x2a2d33), caps: [rgb(0x7cc4e4), rgb(0x7cc4e4), rgb(0x7cc4e4)],
        meter: rgb(0x7cc4e4, 0.28), meterHot: rgb(0x7cc4e4), peak: rgb(0xffffff, 0.7),
        legendFont: font("HelveticaNeue-Light", 8, fallback: .light),
        buttonFont: font("HelveticaNeue-Light", 9.5, fallback: .light),
        titleFont: font("HelveticaNeue-Thin", 15, fallback: .thin))

    static var stored: StudioFaceplate {
        UserDefaults.standard.string(forKey: defaultsKey) == Kind.boutique.rawValue ? .boutique : .console
    }
}

/// The Studio's single view: header, buttons and two channel panels (L above R), each a per-channel
/// analyser over 31 band faders plus a preamp. Edits are heard live (the profile controller's
/// `audition`) and discarded unless saved.
final class EqualizerStudioView: NSView {
    private enum Button: CaseIterable {
        case link, flat, bypass, headroom, save, saveAs, rename, delete, revert, faceplate

        var title: String {
            switch self {
            case .link: return "LINK"
            case .flat: return "FLAT"
            case .bypass: return "BYPASS"
            case .headroom: return "HEADROOM"
            case .save: return "SAVE"
            case .saveAs: return "SAVE AS"
            case .rename: return "RENAME"
            case .delete: return "DELETE"
            case .revert: return "REVERT"
            case .faceplate: return "FACEPLATE"
            }
        }
    }

    /// A band fader (`band` 0…30) or the preamp (`band` nil) of one channel.
    private struct Fader: Equatable {
        let channel: Int
        let band: Int?
    }

    private struct Panel {
        let frame: CGRect
        let label: CGRect
        let analyser: CGRect
        let faders: CGRect
        let legend: CGRect
        let preamp: CGRect
        let bandX0: CGFloat
        let bandWidth: CGFloat

        func centreX(_ band: Int) -> CGFloat { bandX0 + (CGFloat(band) + 0.5) * bandWidth }
        /// Continuous x for a frequency: the ISO centres sit ⅓ octave apart.
        func x(frequency: Double) -> CGFloat { bandX0 + (CGFloat(log2(frequency / 20) * 3) + 0.5) * bandWidth }
    }

    private static let linkedKey = "equalizerStudioLinked"
    /// Response and peaks are shown at this rate; the stream's own rate differs only above 20 kHz.
    private static let displayRate = 48000.0
    private static let gridFrequencies: [Double] = (0...180).map { 20 * pow(1000, Double($0) / 180) }
    private static let bandLabels = ["20", "25", "31", "40", "50", "63", "80", "100", "125", "160", "200",
                                     "250", "315", "400", "500", "630", "800", "1k", "1.2k", "1.6k", "2k",
                                     "2.5k", "3.1k", "4k", "5k", "6.3k", "8k", "10k", "12k", "16k", "20k"]
    private static let analyserRange: ClosedRange<Float> = -78...6

    private let store = EQProfileStore.shared
    private var controller: EQProfileController { WindowManager.shared.audioEngine.eqProfileController }
    private let rta = StudioRTA()

    private var edit = EQCurve.flat
    private var profileID: UUID?
    private var name = "New"
    private var bypass = false
    private var linked = true
    private var faceplate = StudioFaceplate.console
    private var focusChannel = 0
    private var dragging: Fader?
    /// Per channel: band-only response on `gridFrequencies` and its peak, dB.
    private var response: [[Double]] = [[], []]
    private var peakDB: [Double] = [0, 0]
    private var levels = [[Float]](repeating: [Float](repeating: StudioRTA.floorDB, count: 31), count: 2)
    private var peaks = [[Float]](repeating: [Float](repeating: StudioRTA.floorDB, count: 31), count: 2)

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Layout (fixed size)

    private var content: CGRect { bounds.insetBy(dx: SkinnedSurfaceChrome.glossBorder, dy: SkinnedSurfaceChrome.glossBorder) }
    private var nameRect: CGRect { CGRect(x: content.minX + 12, y: content.minY + 8, width: 330, height: 26) }
    private var closeRect: CGRect { CGRect(x: content.maxX - 28, y: content.minY + 10, width: 18, height: 18) }

    private var buttonRects: [(Button, CGRect)] {
        let count = CGFloat(Button.allCases.count), gap: CGFloat = 6
        let width = (content.width - 24 - gap * (count - 1)) / count
        return Button.allCases.enumerated().map { index, button in
            (button, CGRect(x: content.minX + 12 + CGFloat(index) * (width + gap), y: content.minY + 42,
                            width: width, height: 20))
        }
    }

    private var panels: [Panel] {
        let top = content.minY + 72
        let height = (content.maxY - 6 - top) / 2
        return (0..<2).map { channel in
            let frame = CGRect(x: content.minX + 8, y: top + CGFloat(channel) * height,
                               width: content.width - 16, height: height - 6)
            let inner = frame.insetBy(dx: 8, dy: 8)
            let column: CGFloat = 52
            let bandX0 = inner.minX + column + 8
            let analyser = CGRect(x: bandX0, y: inner.minY, width: inner.maxX - bandX0, height: 74)
            let faders = CGRect(x: bandX0, y: analyser.maxY + 8, width: analyser.width, height: 112)
            return Panel(frame: frame,
                         label: CGRect(x: inner.minX, y: inner.minY, width: column, height: analyser.height),
                         analyser: analyser, faders: faders,
                         legend: CGRect(x: bandX0, y: faders.maxY + 3, width: analyser.width, height: 11),
                         preamp: CGRect(x: inner.minX + 14, y: faders.minY, width: 24, height: faders.height),
                         // The analyser's dB labels sit in a gutter right of the 20 kHz band.
                         bandX0: bandX0, bandWidth: (analyser.width - 24) / CGFloat(EQProfileDesign.bandCount))
        }
    }

    private func y(gain: Float, in rect: CGRect) -> CGFloat {
        rect.minY + 6 + CGFloat((12 - gain) / 24) * (rect.height - 12)
    }

    private func gain(y: CGFloat, in rect: CGRect) -> Float {
        let g = 12 - Float((y - rect.minY - 6) / (rect.height - 12)) * 24
        return EQCurve.clamp((g * 10).rounded() / 10)
    }

    // MARK: - Open / close

    func studioDidOpen() {
        linked = UserDefaults.standard.object(forKey: Self.linkedKey) as? Bool ?? true
        faceplate = .stored
        bypass = false
        if let track = WindowManager.shared.audioEngine.currentTrack, let profile = store.resolve(track)?.profile {
            load(profile)
        } else {
            loadNew()
        }
        rta.onUpdate = { [weak self] levels, peaks in
            self?.levels = levels
            self?.peaks = peaks
            self?.needsDisplay = true
        }
        rta.start()
    }

    func studioDidClose() {
        rta.stop()
        rta.onUpdate = nil
        bypass = false
        controller.audition = nil
    }

    private func load(_ profile: EQProfile) {
        profileID = profile.id
        name = profile.name
        edit = profile.curve
        editDidChange()
    }

    private func loadNew() {
        profileID = nil
        name = "New"
        edit = .flat
        editDidChange()
    }

    private var savedCurve: EQCurve { profileID.flatMap { store.profile($0)?.curve } ?? .flat }
    private var isDirty: Bool { edit != savedCurve }

    private func editDidChange() {
        for channel in 0..<2 {
            let sections = EQProfileDesign.sections(for: edit.bands(channel), sampleRate: Self.displayRate)
            response[channel] = Self.gridFrequencies.map {
                EQProfileDesign.responseDB(sections, frequency: $0, sampleRate: Self.displayRate)
            }
            peakDB[channel] = response[channel].max() ?? 0
        }
        pushAudition()
    }

    private func pushAudition() {
        controller.audition = bypass ? .flat : edit
        needsDisplay = true
    }

    // MARK: - Editing

    private func value(_ fader: Fader) -> Float {
        guard let band = fader.band else { return edit.preamp(fader.channel) }
        return edit.bands(fader.channel)[band]
    }

    private func set(_ fader: Fader, _ value: Float) {
        let value = EQCurve.clamp(value)
        switch (fader.channel, fader.band) {
        case (0, nil): edit.preampL = value
        case (_, nil): edit.preampR = value
        case (0, let band?): edit.left[band] = value
        case (_, let band?): edit.right[band] = value
        }
    }

    /// LINK lit moves the other channel's fader by the same amount, so channels that differ keep
    /// their difference.
    private func move(_ fader: Fader, to newValue: Float) {
        let old = value(fader)
        let new = EQCurve.clamp(newValue)
        guard new != old else { return }
        set(fader, new)
        if linked {
            let other = Fader(channel: 1 - fader.channel, band: fader.band)
            set(other, value(other) + (new - old))
        }
        editDidChange()
    }

    private func reset(_ fader: Fader) {
        set(fader, 0)
        if linked { set(Fader(channel: 1 - fader.channel, band: fader.band), 0) }
        editDidChange()
    }

    private func flatten(channel: Int) {
        if channel == 0 {
            edit.left = EQCurve.flat.left; edit.preampL = 0
        } else {
            edit.right = EQCurve.flat.right; edit.preampR = 0
        }
    }

    private func perform(_ button: Button) {
        switch button {
        case .link:
            linked.toggle()
            UserDefaults.standard.set(linked, forKey: Self.linkedKey)
            needsDisplay = true
        case .flat:
            if linked { flatten(channel: 0); flatten(channel: 1) } else { flatten(channel: focusChannel) }
            editDidChange()
        case .bypass:
            bypass.toggle()
            pushAudition()
        case .headroom:
            edit.preampL = EQCurve.clamp(Float(-peakDB[0]))
            edit.preampR = EQCurve.clamp(Float(-peakDB[1]))
            editDidChange()
        case .save:
            if let profileID { store.update(profileID, curve: edit); needsDisplay = true } else { saveAs() }
        case .saveAs:
            saveAs()
        case .rename:
            guard let newName = promptName("Rename Profile", initial: name) else { return }
            name = newName
            if let profileID { store.update(profileID, name: newName) }
            needsDisplay = true
        case .delete:
            guard let profileID else { return }
            let alert = NSAlert()
            alert.messageText = "Delete “\(name)”?"
            alert.informativeText = "Everything assigned to it falls back to the next level down."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            store.delete(profileID)
            loadNew()
        case .revert:
            edit = savedCurve
            editDidChange()
        case .faceplate:
            faceplate = faceplate.kind == .console ? .boutique : .console
            UserDefaults.standard.set(faceplate.kind.rawValue, forKey: StudioFaceplate.defaultsKey)
            needsDisplay = true
        }
    }

    private func isEnabled(_ button: Button) -> Bool {
        switch button {
        case .save: return isDirty || profileID == nil
        case .delete: return profileID != nil
        case .revert: return isDirty
        default: return true
        }
    }

    private func saveAs() {
        guard let newName = promptName("Save Profile As", initial: profileID == nil ? "" : name) else { return }
        load(store.add(name: newName, curve: edit))
    }

    private func promptName(_ message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func showProfileMenu() {
        let menu = NSMenu()
        for profile in store.profiles.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let item = NSMenuItem(title: profile.name, action: #selector(chooseProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == profileID ? .on : .off
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let new = NSMenuItem(title: "New", action: #selector(chooseNew(_:)), keyEquivalent: "")
        new.target = self
        menu.addItem(new)
        menu.popUp(positioning: nil, at: NSPoint(x: nameRect.minX, y: nameRect.maxY + 2), in: self)
    }

    @objc private func chooseProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let profile = store.profile(id) else { return }
        load(profile)
    }

    @objc private func chooseNew(_ sender: NSMenuItem) { loadNew() }

    // MARK: - Mouse

    private func fader(at point: CGPoint) -> Fader? {
        for (channel, panel) in panels.enumerated() {
            if panel.preamp.insetBy(dx: -8, dy: -4).contains(point) { return Fader(channel: channel, band: nil) }
            guard panel.faders.insetBy(dx: 0, dy: -4).contains(point) else { continue }
            let band = Int((point.x - panel.bandX0) / panel.bandWidth)
            if (0..<EQProfileDesign.bandCount).contains(band) { return Fader(channel: channel, band: band) }
        }
        return nil
    }

    private func faderRect(_ fader: Fader) -> CGRect {
        let panel = panels[fader.channel]
        return fader.band == nil ? panel.preamp : panel.faders
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if linked, linkBadge.contains(point) {
            perform(.link)
        } else if closeRect.insetBy(dx: -4, dy: -4).contains(point) {
            window?.close()
        } else if nameRect.contains(point) {
            showProfileMenu()
        } else if let (button, _) = buttonRects.first(where: { $0.1.contains(point) }) {
            if isEnabled(button) { perform(button) }
        } else if let channel = panels.firstIndex(where: { $0.label.contains(point) }) {
            focusChannel = channel
            needsDisplay = true
        } else if let fader = fader(at: point) {
            focusChannel = fader.channel
            if event.clickCount == 2 {
                reset(fader)
            } else {
                dragging = fader
                move(fader, to: gain(y: point.y, in: faderRect(fader)))
            }
        } else {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        move(dragging, to: gain(y: point.y, in: faderRect(dragging)))
    }

    override func mouseUp(with event: NSEvent) { dragging = nil }

    // MARK: - Drawing

    /// The rim's colours: the hosting skin's own surface style where it lends one, else one built
    /// here from the Classic skin's playlist colours or the Original skin's palette. Built here rather
    /// than as a Classic case in `hostedSurfaceStyle`, which would put Classic's Playlist and EQ
    /// windows in the gloss frame too.
    private var rimStyle: SkinnedSurfaceStyle {
        let wm = WindowManager.shared
        if let style = wm.hostedSurfaceStyle { return style }
        let neutral = SkinnedSurfaceRoles(background: NSColor(white: 0.22, alpha: 1), text: .white, currentText: .white,
                                          selectionBackground: .gray, selectionText: .white,
                                          treeText: .white, treeSelection: .gray)
        let roles: SkinnedSurfaceRoles
        switch wm.uiMode.controllerFamily {
        case .classic:
            let c = wm.currentSkin?.playlistColors ?? .default
            roles = SkinnedSurfaceRoles(background: c.normalBackground, text: c.normalText, currentText: c.currentText,
                                        selectionBackground: c.selectedBackground, selectionText: c.selectedText,
                                        treeText: c.normalText, treeSelection: c.selectedBackground)
        case .nullPlayerModern:
            roles = ModernSkinEngine.shared.currentSkin.map { skin in
                let p = skin.config.palette
                return SkinnedSurfaceRoles(background: p.resolvedSurface(), text: p.resolvedText(),
                                           currentText: p.resolvedPrimary(), selectionBackground: p.resolvedAccent(),
                                           selectionText: p.resolvedText(), treeText: p.resolvedTextDim(),
                                           treeSelection: p.resolvedAccent())
            } ?? neutral
        case .winampModern, .wmp, .audion:
            // These lend a style once their skin is up; until then, the neutral rim.
            roles = neutral
        }
        return SkinnedSurfaceStyle(roles: roles)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let f = faceplate
        SkinnedSurfaceChrome.drawGlossFrame(in: context, bounds: bounds, style: rimStyle,
                                            isActive: window?.isKeyWindow ?? true, fillGround: false)
        f.panel.setFill()
        NSBezierPath(roundedRect: content, xRadius: 2, yRadius: 2).fill()

        drawHeader(f)
        for (channel, panel) in panels.enumerated() { drawPanel(panel, channel: channel, f) }
        drawLink(f)
    }

    private func drawText(_ string: String, font: NSFont, color: NSColor, in rect: CGRect,
                          alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let height = (string as NSString).size(withAttributes: attributes).height
        (string as NSString).draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                                  withAttributes: attributes)
    }

    private func drawHeader(_ f: StudioFaceplate) {
        // Name display: the profile, a dirty marker, and the menu it opens.
        f.well.setFill()
        NSBezierPath(roundedRect: nameRect, xRadius: 3, yRadius: 3).fill()
        f.edge.setStroke()
        NSBezierPath(roundedRect: nameRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
        drawText(name + (isDirty ? "  ●" : ""), font: f.titleFont, color: f.text,
                 in: CGRect(x: nameRect.minX + 10, y: nameRect.minY, width: nameRect.width - 40, height: nameRect.height))
        drawText("▾", font: f.buttonFont, color: f.dimText, in: CGRect(x: nameRect.maxX - 22, y: nameRect.minY, width: 14, height: nameRect.height))

        let title = CGRect(x: nameRect.maxX + 16, y: nameRect.minY, width: closeRect.minX - nameRect.maxX - 28, height: nameRect.height)
        drawText(bypass ? "EQUALIZER STUDIO — BYPASS" : "EQUALIZER STUDIO", font: f.buttonFont,
                 color: bypass ? f.accent : f.dimText, in: title, alignment: .right)

        // Close: a drawn ×.
        let x = closeRect.insetBy(dx: 5, dy: 5)
        let cross = NSBezierPath()
        cross.move(to: x.origin); cross.line(to: CGPoint(x: x.maxX, y: x.maxY))
        cross.move(to: CGPoint(x: x.maxX, y: x.minY)); cross.line(to: CGPoint(x: x.minX, y: x.maxY))
        cross.lineWidth = 1.5
        f.dimText.setStroke()
        cross.stroke()

        for (button, rect) in buttonRects {
            let lit = (button == .link && linked) || (button == .bypass && bypass)
            let enabled = isEnabled(button)
            (lit ? f.accent : f.well).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            f.edge.setStroke()
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
            let color = lit ? f.panel : enabled ? f.text : f.dimText.withAlphaComponent(0.5)
            drawText(button == .faceplate ? f.kind.rawValue.uppercased() : button.title,
                     font: f.buttonFont, color: color, in: rect, alignment: .center)
        }
    }

    private func drawPanel(_ panel: Panel, channel: Int, _ f: StudioFaceplate) {
        f.edge.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: panel.frame, xRadius: 3, yRadius: 3).fill()
        f.panel.setFill()
        NSBezierPath(roundedRect: panel.frame.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3).fill()

        // Channel label, focus, and the peak response readout beside the preamp.
        // Linked, both labels take the rail's colour; separate, only the channel being edited.
        let labelColor = linked || channel == focusChannel ? f.accent : f.text
        drawText(channel == 0 ? "LEFT" : "RIGHT", font: f.titleFont, color: labelColor,
                 in: CGRect(x: panel.label.minX, y: panel.label.minY + 4, width: panel.label.width, height: 20))
        let peak = peakDB[channel] + Double(edit.preamp(channel))
        drawText(String(format: "PK %+.1f", peak), font: f.legendFont, color: peak > 0.05 ? f.peak : f.dimText,
                 in: CGRect(x: panel.label.minX, y: panel.label.minY + 30, width: panel.label.width, height: 12))
        drawText(String(format: "PRE %+.1f", edit.preamp(channel)), font: f.legendFont, color: f.dimText,
                 in: CGRect(x: panel.label.minX, y: panel.label.minY + 44, width: panel.label.width, height: 12))
        // Separate channels: say which one FLAT acts on, rather than leave a lone lit label to decode.
        if !linked && channel == focusChannel {
            drawText("FLAT ACTS HERE", font: f.legendFont, color: f.accent,
                     in: CGRect(x: panel.label.minX, y: panel.label.minY + 58, width: panel.label.width + 8, height: 12))
        }

        drawAnalyser(panel, channel: channel, f)
        drawFaders(panel, channel: channel, f)

        for band in 0..<EQProfileDesign.bandCount {
            drawText(Self.bandLabels[band], font: f.legendFont, color: f.dimText,
                     in: CGRect(x: panel.centreX(band) - panel.bandWidth / 2 - 2, y: panel.legend.minY,
                                width: panel.bandWidth + 4, height: panel.legend.height), alignment: .center)
        }
        drawText("PRE", font: f.legendFont, color: f.dimText,
                 in: CGRect(x: panel.preamp.minX - 8, y: panel.legend.minY, width: panel.preamp.width + 16,
                            height: panel.legend.height), alignment: .center)
    }

    /// The chain on the rail, at the seam between the panels; clicking it unlinks.
    private var linkBadge: CGRect {
        let panels = panels
        let seam = (panels[0].frame.maxY + panels[1].frame.minY) / 2
        return CGRect(x: panels[0].frame.minX + 4 - 9, y: seam - 9, width: 18, height: 18)
    }

    /// LINK lit: a rail brackets the LEFT and RIGHT labels, with a chain where it crosses the seam.
    /// Separate: nothing.
    private func drawLink(_ f: StudioFaceplate) {
        guard linked else { return }
        let panels = panels, badge = linkBadge
        let x = badge.midX
        let top = panels[0].label.minY + 14, bottom = panels[1].label.minY + 14
        let rail = NSBezierPath()
        rail.move(to: CGPoint(x: panels[0].label.minX - 1, y: top))
        rail.line(to: CGPoint(x: x, y: top))
        rail.line(to: CGPoint(x: x, y: bottom))
        rail.line(to: CGPoint(x: panels[1].label.minX - 1, y: bottom))
        rail.lineWidth = 2
        rail.lineJoinStyle = .round
        rail.lineCapStyle = .round
        f.accent.setStroke()
        rail.stroke()
        f.accent.setFill()
        NSBezierPath(ovalIn: badge).fill()
        if let link = NSImage(systemSymbolName: "link", accessibilityDescription: "Linked")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold).applying(.init(paletteColors: [f.panel]))) {
            let size = link.size
            link.draw(in: CGRect(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2,
                                 width: size.width, height: size.height))
        }
    }

    private func analyserY(_ db: Float, in rect: CGRect) -> CGFloat {
        let range = Self.analyserRange
        let t = (min(range.upperBound, max(range.lowerBound, db)) - range.lowerBound) / (range.upperBound - range.lowerBound)
        return rect.maxY - CGFloat(t) * rect.height
    }

    /// What the ladder shows depends on where the feed sits: the local feed is pre-profile, so the
    /// auditioned curve is added (BYPASS shows the source); the streaming feed is already the output
    /// — post-profile, post-EQ, post-SRS — so it is shown as-is and labelled so.
    private func drawAnalyser(_ panel: Panel, channel: Int, _ f: StudioFaceplate) {
        let rect = panel.analyser
        f.well.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()

        // Graticule: every 12 dB on Console, every 6 dB plus octaves on Boutique.
        let step: Float = f.kind == .console ? 12 : 6
        var db = Self.analyserRange.upperBound - 6
        while db > Self.analyserRange.lowerBound {
            let y = analyserY(db, in: rect)
            (f.kind == .console ? f.scale.withAlphaComponent(db == 0 ? 0.35 : 0.15) : f.scale).setFill()
            NSRect(x: rect.minX, y: y, width: rect.width, height: f.kind == .console ? 1 : 0.5).fill()
            if f.kind == .console || db.truncatingRemainder(dividingBy: 12) == 0 {
                drawText(String(format: "%.0f", db), font: f.legendFont, color: f.dimText.withAlphaComponent(0.7),
                         in: CGRect(x: rect.maxX - 22, y: y - 6, width: 20, height: 12), alignment: .right)
            }
            db -= step
        }
        if f.kind == .boutique {
            f.scale.setFill()
            for band in stride(from: 0, to: EQProfileDesign.bandCount, by: 3) {
                NSRect(x: panel.centreX(band), y: rect.minY, width: 0.5, height: rect.height).fill()
            }
        }

        let streaming = WindowManager.shared.audioEngine.isStreamingPlayback
        let added: (Int) -> Float = { [edit, bypass] band in
            streaming || bypass ? 0 : edit.bands(channel)[band] + edit.preamp(channel)
        }
        drawText(streaming ? "OUTPUT" : bypass ? "SOURCE" : "SOURCE + PROFILE", font: f.legendFont,
                 color: f.dimText, in: CGRect(x: rect.minX + 4, y: rect.minY + 2, width: 120, height: 11))

        let levels = self.levels[channel], peaks = self.peaks[channel]
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        switch f.kind {
        case .console:
            for band in 0..<EQProfileDesign.bandCount {
                let level = levels[band] + added(band)
                let top = analyserY(level, in: rect)
                let bar = CGRect(x: panel.centreX(band) - panel.bandWidth / 2 + 1.5, y: top,
                                 width: panel.bandWidth - 3, height: rect.maxY - top)
                (level > -3 ? f.peak : level > -12 ? f.meterHot : f.meter).setFill()
                bar.fill()
                f.peak.setFill()
                NSRect(x: bar.minX, y: analyserY(peaks[band] + added(band), in: rect), width: bar.width, height: 1.5).fill()
            }
        case .boutique:
            let curve = NSBezierPath()
            curve.move(to: CGPoint(x: panel.centreX(0), y: rect.maxY))
            for band in 0..<EQProfileDesign.bandCount {
                curve.line(to: CGPoint(x: panel.centreX(band), y: analyserY(levels[band] + added(band), in: rect)))
            }
            curve.line(to: CGPoint(x: panel.centreX(EQProfileDesign.bandCount - 1), y: rect.maxY))
            curve.close()
            f.meter.setFill()
            curve.fill()
            let line = NSBezierPath()
            for band in 0..<EQProfileDesign.bandCount {
                let point = CGPoint(x: panel.centreX(band), y: analyserY(levels[band] + added(band), in: rect))
                band == 0 ? line.move(to: point) : line.line(to: point)
            }
            line.lineWidth = 1
            f.meterHot.setStroke()
            line.stroke()
            f.peak.setFill()
            for band in 0..<EQProfileDesign.bandCount {
                NSRect(x: panel.centreX(band) - 2, y: analyserY(peaks[band] + added(band), in: rect), width: 4, height: 1).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFaders(_ panel: Panel, channel: Int, _ f: StudioFaceplate) {
        let rect = panel.faders
        let bands = edit.bands(channel)

        // Scale: engraved ±12 / ±6 / ±3 / 0 ticks on Console, a fine 0 dB line on Boutique.
        let ticks: [Float] = f.kind == .console ? [12, 6, 3, 0, -3, -6, -12] : [0]
        for tick in ticks {
            let y = self.y(gain: tick, in: rect).rounded() + 0.5
            if f.kind == .console {
                f.scale.withAlphaComponent(tick == 0 ? 0.55 : 0.28).setFill()
                NSRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1).fill()
                NSColor.black.withAlphaComponent(0.35).setFill()
                NSRect(x: rect.minX, y: y + 0.5, width: rect.width, height: 1).fill()
            } else {
                f.scale.setFill()
                NSRect(x: rect.minX, y: y - 0.25, width: rect.width, height: 0.5).fill()
            }
        }
        if f.kind == .console {
            for tick: Float in [12, 6, 0, -6, -12] {
                drawText(String(format: "%+.0f", tick).replacingOccurrences(of: "+0", with: "0"), font: f.legendFont,
                         color: f.dimText, in: CGRect(x: panel.preamp.maxX + 2, y: y(gain: tick, in: rect) - 6, width: 18, height: 12))
            }
        }

        func drawFader(x: CGFloat, value: Float, in rect: CGRect, cap: NSColor, width: CGFloat) {
            let slotWidth: CGFloat = f.kind == .console ? 3 : 1
            f.slot.setFill()
            NSRect(x: x - slotWidth / 2, y: rect.minY + 4, width: slotWidth, height: rect.height - 8).fill()
            let y = self.y(gain: value, in: rect)
            if f.kind == .console {
                let capRect = CGRect(x: x - width / 2, y: y - 4.5, width: width, height: 9)
                NSColor.black.withAlphaComponent(0.4).setFill()
                capRect.offsetBy(dx: 0, dy: 1).fill()
                cap.setFill()
                NSBezierPath(roundedRect: capRect, xRadius: 1.5, yRadius: 1.5).fill()
                NSColor.white.withAlphaComponent(0.45).setFill()
                NSRect(x: capRect.minX + 1, y: capRect.minY + 1, width: capRect.width - 2, height: 1).fill()
                NSColor.black.withAlphaComponent(0.55).setFill()
                NSRect(x: capRect.minX + 1, y: capRect.midY - 0.5, width: capRect.width - 2, height: 1).fill()
            } else {
                let zero = self.y(gain: 0, in: rect)
                cap.withAlphaComponent(0.35).setFill()
                NSRect(x: x - 0.5, y: min(y, zero), width: 1, height: abs(y - zero)).fill()
                cap.setFill()
                NSRect(x: x - width / 2, y: y - 1, width: width, height: 2).fill()
            }
        }

        for band in 0..<EQProfileDesign.bandCount {
            drawFader(x: panel.centreX(band), value: bands[band], in: rect, cap: f.capColor(band: band),
                      width: min(panel.bandWidth - 4, f.kind == .console ? 14 : 10))
        }
        drawFader(x: panel.preamp.midX, value: edit.preamp(channel), in: panel.preamp, cap: f.text, width: 18)

        // The response actually applied (band sections, 48 kHz): what the faders produce between centres.
        guard response[channel].count == Self.gridFrequencies.count else { return }
        let path = NSBezierPath()
        for (index, frequency) in Self.gridFrequencies.enumerated() {
            let point = CGPoint(x: panel.x(frequency: frequency),
                                y: y(gain: Float(max(-12, min(12, response[channel][index]))), in: rect))
            index == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.lineWidth = 1.2
        f.accent.withAlphaComponent(bypass ? 0.25 : 0.85).setStroke()
        path.stroke()
    }
}
