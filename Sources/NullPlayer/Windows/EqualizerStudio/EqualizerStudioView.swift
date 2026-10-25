import AppKit

/// The Studio's view of its session (`EqualizerStudioSession`): header, buttons and two channel
/// panels (L above R), each a per-channel analyser over 31 band faders — or, in parametric mode, a
/// response graph over a channel strip's dials — plus a preamp, with its own FLAT and BYPASS under
/// the channel name. Both stages are always heard and every curve drawn is their sum; the mode only
/// picks which controls are shown. Each host — the standalone window, a `.wal` skin's frame — has
/// one of its own.
final class EqualizerStudioView: NSView {
    private typealias Fader = EqualizerStudioSession.Fader

    /// The toolbar's buttons and each channel's BYPASS and FLAT: icon buttons all, so one model
    /// answers clicks, tooltips and drawing.
    private enum Button: Equatable {
        case link, mode, headroom, save, saveAs, rename, delete, revert, faceplate
        case bypass(channel: Int), flat(channel: Int)
    }

    /// The toolbar's groups, left to right.
    private static let toolbar: [[Button]] = [[.link, .mode, .headroom],
                                              [.save, .saveAs, .rename, .delete, .revert], [.faceplate]]

    /// What a click in a channel panel lands on.
    private enum Control {
        case fader(Fader)
        case knob(channel: Int, EQParametric.Knob)
        case toggle(channel: Int, EQParametric.Switch)
    }

    private struct Panel {
        let frame: CGRect
        /// The left column, top to bottom.
        let name: CGRect
        let peakReadout: CGRect
        let preampReadout: CGRect
        let flat: CGRect
        let bypass: CGRect
        let analyser: CGRect
        let faders: CGRect
        let legend: CGRect
        let preamp: CGRect
        let bandX0: CGFloat
        let bandWidth: CGFloat

        /// Parametric mode's use of the fader and legend rows, and of what the analyser gives up.
        var strip: StudioStrip {
            StudioStrip(in: CGRect(x: bandX0, y: analyser.maxY + 6, width: analyser.width, height: legend.maxY - analyser.maxY - 6))
        }

        func centreX(_ band: Int) -> CGFloat { bandX0 + (CGFloat(band) + 0.5) * bandWidth }
        /// Continuous x for a frequency: the ISO centres sit ⅓ octave apart.
        func x(frequency: Double) -> CGFloat { bandX0 + (CGFloat(log2(frequency / 20) * 3) + 0.5) * bandWidth }
    }

    private static let bandLabels = ["20", "25", "31", "40", "50", "63", "80", "100", "125", "160", "200",
                                     "250", "315", "400", "500", "630", "800", "1k", "1.2k", "1.6k", "2k",
                                     "2.5k", "3.1k", "4k", "5k", "6.3k", "8k", "10k", "12k", "16k", "20k"]
    private static let analyserRange: ClosedRange<Float> = -78...6

    private let session = EqualizerStudioSession.shared
    private let bloom = StudioBloom()
    /// Set while a `.wal` skin's frame hosts this view: an empty-area press then moves that window
    /// through the shared hosted drag, the skin's scene having no drag of its own for it.
    private var hostedContext: WinampModernHostedSurfaceContext?
    private var hostedDrag = WinampModernHostedWindowDrag()
    /// A fader or dial held, and the pointer's last y.
    private var drag: (control: Control, y: CGFloat)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionDidChange),
                                               name: EqualizerStudioSession.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func sessionDidChange() { needsDisplay = true }

    func configureForHostedSurface(context: WinampModernHostedSurfaceContext) {
        hostedContext = context
        needsDisplay = true
    }

    // MARK: - Layout

    /// The smallest the faceplate lays out at; the window's minimum adds its chrome to this.
    static let designSize = NSSize(width: 688, height: 518)
    /// A channel panel's inner height at `designSize`. Height beyond it goes to the analyser and the
    /// fader field (in parametric mode, the strip's graph).
    private static let designPanelHeight: CGFloat = 213

    private var nameRect: CGRect { CGRect(x: bounds.minX + 12, y: bounds.minY + 10, width: 220, height: 22) }

    /// Every icon button: the toolbar, right-aligned on the name's row — square, a wider gap between
    /// groups — then each channel's BYPASS and FLAT.
    private var buttons: [(Button, CGRect)] {
        let size = nameRect.height, gap: CGFloat = 4, groupGap: CGFloat = 14
        let count = CGFloat(Self.toolbar.joined().count), groups = CGFloat(Self.toolbar.count)
        var x = bounds.maxX - 12 - (count * size + (count - groups) * gap + (groups - 1) * groupGap)
        var buttons: [(Button, CGRect)] = []
        for group in Self.toolbar {
            for button in group {
                buttons.append((button, CGRect(x: x, y: nameRect.minY, width: size, height: size)))
                x += size + gap
            }
            x += groupGap - gap
        }
        for (channel, panel) in panels.enumerated() {
            buttons += [(.bypass(channel: channel), panel.bypass), (.flat(channel: channel), panel.flat)]
        }
        return buttons
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        removeAllToolTips()
        for (_, rect) in buttons { addToolTip(rect, owner: self, userData: nil) }
    }

    private var panels: [Panel] {
        let top = bounds.minY + 42
        let height = (bounds.maxY - 6 - top) / 2
        return (0..<2).map { channel in
            let frame = CGRect(x: bounds.minX + 8, y: top + CGFloat(channel) * height,
                               width: bounds.width - 16, height: height - 6)
            let inner = frame.insetBy(dx: 8, dy: 8)
            let column: CGFloat = 52
            let bandX0 = inner.minX + column + 8
            let spare = max(0, inner.height - Self.designPanelHeight)
            let grow = (spare * 0.4).rounded()
            // Parametric mode shortens the analyser to give the strip's dials room.
            let analyser = CGRect(x: bandX0, y: inner.minY, width: inner.maxX - bandX0,
                                  height: (session.mode == .graphic ? 74 : 56) + grow)
            let faders = CGRect(x: bandX0, y: inner.minY + 82 + grow, width: analyser.width, height: 112 + spare - grow)
            func row(_ y: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: inner.minX, y: inner.minY + y, width: column, height: height)
            }
            // BYPASS and FLAT: two icon buttons side by side, as the toolbar's.
            let (bypass, flat) = row(44, 22).divided(atDistance: column / 2, from: .minXEdge)
            return Panel(frame: frame,
                         name: row(0, 18), peakReadout: row(19, 11), preampReadout: row(30, 11),
                         flat: flat.insetBy(dx: 2, dy: 0), bypass: bypass.insetBy(dx: 2, dy: 0),
                         analyser: analyser, faders: faders,
                         legend: CGRect(x: bandX0, y: faders.maxY + 3, width: analyser.width, height: 11),
                         preamp: CGRect(x: inner.minX + 14, y: faders.minY, width: 24, height: faders.height),
                         // The analyser's dB labels sit in a gutter right of the 20 kHz band.
                         bandX0: bandX0, bandWidth: (analyser.width - 24) / CGFloat(EQProfileDesign.bandCount))
        }
    }

    // MARK: - Buttons

    private func perform(_ button: Button) {
        switch button {
        case .link: session.toggleLink()
        case .mode: session.toggleMode()
        case .headroom: session.applyHeadroom()
        case .save: session.save()
        case .saveAs:
            if let newName = promptName("Save Profile As", initial: session.profileID == nil ? "" : session.name) {
                session.saveAs(newName)
            }
        case .rename:
            if let newName = promptName("Rename Profile", initial: session.name) { session.rename(newName) }
        case .delete:
            let alert = NSAlert()
            alert.messageText = "Delete “\(session.name)”?"
            alert.informativeText = "Everything assigned to it falls back to the next level down."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { session.delete() }
        case .revert: session.revert()
        case .faceplate: session.toggleFaceplate()
        case .bypass(let channel): session.toggleBypass(channel)
        case .flat(let channel): session.flatten(channel)
        }
    }

    private func isEnabled(_ button: Button) -> Bool {
        switch button {
        // Lit only while a preamp is off its headroom setting, so a press always changes something.
        case .headroom: return session.isOffHeadroom
        // An unsaved profile has nothing stored to save over, rename or delete; Save As names it.
        case .save: return session.profileID != nil && session.isDirty
        case .rename, .delete: return session.profileID != nil
        case .revert: return session.isDirty
        default: return true
        }
    }

    /// LINK lights while on; BYPASS, a plug-in's power button, while its channel is heard.
    private func isLit(_ button: Button) -> Bool {
        switch button {
        case .link: return session.linked
        case .bypass(let channel): return !session.bypass[channel]
        default: return false
        }
    }

    /// A disabled button is faint, and so is a bypassed channel's power button.
    private func isFaint(_ button: Button) -> Bool {
        if case .bypass(let channel) = button { return session.bypass[channel] }
        return !isEnabled(button)
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
        for profile in EQProfileStore.shared.sortedProfiles {
            let item = NSMenuItem(title: profile.name, action: #selector(chooseProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id
            item.state = profile.id == session.profileID ? .on : .off
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let new = NSMenuItem(title: "New", action: #selector(chooseNew(_:)), keyEquivalent: "")
        new.target = self
        menu.addItem(new)
        menu.popUp(positioning: nil, at: NSPoint(x: nameRect.minX, y: nameRect.maxY + 2), in: self)
    }

    @objc private func chooseProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let profile = EQProfileStore.shared.profile(id) else { return }
        session.load(profile)
    }

    @objc private func chooseNew(_ sender: NSMenuItem) { session.loadNew() }

    // MARK: - Mouse

    /// The preamp in either mode; then the band faders or the strip, whichever the mode shows.
    private func control(at point: CGPoint) -> Control? {
        for (channel, panel) in panels.enumerated() {
            if panel.preamp.insetBy(dx: -8, dy: -4).contains(point) { return .fader(Fader(channel: channel, band: nil)) }
            switch session.mode {
            case .graphic:
                guard panel.faders.insetBy(dx: 0, dy: -4).contains(point) else { continue }
                let band = Int((point.x - panel.bandX0) / panel.bandWidth)
                if (0..<EQProfileDesign.bandCount).contains(band) { return .fader(Fader(channel: channel, band: band)) }
            case .parametric:
                let strip = panel.strip
                if let toggle = strip.toggle(at: point) { return .toggle(channel: channel, toggle) }
                if let knob = strip.knob(at: point) { return .knob(channel: channel, knob) }
            }
        }
        return nil
    }

    /// Where a fader's cap is drawn and dragged: a band fader adds the strip at its centre; the preamp is itself.
    private func offset(_ fader: Fader) -> Float {
        fader.band.map { session.responses[fader.channel].stripAtCentres[$0] } ?? 0
    }

    private func faderRect(_ fader: Fader) -> CGRect {
        let panel = panels[fader.channel]
        return fader.band == nil ? panel.preamp : panel.faders
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if nameRect.contains(point) {
            showProfileMenu()
        } else if let (button, _) = buttons.first(where: { $0.1.contains(point) }) {
            if isEnabled(button) { perform(button) }
        } else if let control = control(at: point) {
            press(control, at: point.y, clickCount: event.clickCount)
        } else if hostedContext != nil {
            // An empty area moves the window: a skin's frame through the shared hosted drag, the
            // standalone window through the window view behind, snapping as its title does.
            hostedDrag.prime(event, context: hostedContext)
        } else {
            super.mouseDown(with: event)
        }
    }

    /// A double-click resets a fader or dial; a single one starts dragging it. A switch flips.
    private func press(_ control: Control, at y: CGFloat, clickCount: Int) {
        switch control {
        case .fader(let fader):
            if clickCount == 2 {
                session.reset(fader)
            } else {
                drag = (control, y)
                session.move(fader, to: faderRect(fader).gain(y: y) - offset(fader))
            }
        case .knob(let channel, let knob):
            if clickCount == 2 {
                session.reset(knob, channel: channel)
            } else if session.edit[channel].parametric.isActive(knob) {
                drag = (control, y)
            }
        case .toggle(let channel, let toggle):
            session.flip(toggle, channel: channel)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let (control, lastY) = drag else {
            if hostedContext != nil { hostedDrag.drag(event) } else { super.mouseDragged(with: event) }
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        drag?.y = point.y
        switch control {
        case .fader(let fader):
            session.move(fader, to: faderRect(fader).gain(y: point.y) - offset(fader))
        case .knob(let channel, let knob):
            // Up turns clockwise; 200 points is the whole travel.
            session.turn(knob, channel: channel, by: Float(lastY - point.y) / 200)
        case .toggle:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if drag == nil {
            if hostedContext != nil { _ = hostedDrag.end() } else { super.mouseUp(with: event) }
        }
        drag = nil
    }

    // MARK: - Drawing

    private static let neutralStyle = SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
        background: NSColor(white: 0.22, alpha: 1), text: .white, currentText: .white,
        selectionBackground: .gray, selectionText: .white, treeText: .white, treeSelection: .gray))

    /// The faceplate's colours: the hosting skin's own surface style where it lends one, else the
    /// Classic skin's or the Original skin's surface roles. Not a Classic case in
    /// `hostedSurfaceStyle`, which would put Classic's Playlist and EQ windows in the gloss frame too.
    private var surfaceStyle: SkinnedSurfaceStyle {
        let wm = WindowManager.shared
        if let style = wm.hostedSurfaceStyle { return style }
        switch wm.uiMode.controllerFamily {
        case .classic:
            return SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(classic: wm.currentSkin?.playlistColors ?? .default))
        case .nullPlayerModern:
            return ModernSkinEngine.shared.currentSkin.map {
                SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(modern: $0.config.palette))
            } ?? Self.neutralStyle
        case .winampModern, .wmp, .audion, .sonique:
            // These lend a style once their skin is up; until then, the neutral one.
            return Self.neutralStyle
        }
    }

    /// Winamp's own EQ and spectrum colours: green, yellow, red.
    private static let winampMeter = [NSColor(srgbRed: 0, green: 0.85, blue: 0, alpha: 1),
                                      NSColor(srgbRed: 0.85, green: 0.85, blue: 0, alpha: 1),
                                      NSColor(srgbRed: 0.85, green: 0.15, blue: 0, alpha: 1)]

    /// The skin's own low, mid and high level colours where it declares them: an Original skin's EQ
    /// colours, or a Classic skin's spectrum (`viscolor.txt`'s bottom, middle and top bar rows).
    /// The families that lend only surface roles take Winamp's.
    private var meterColors: [NSColor] {
        let wm = WindowManager.shared
        switch wm.uiMode.controllerFamily {
        case .classic:
            if let colors = wm.currentSkin?.visColors, colors.count >= 18 { return [colors[17], colors[9], colors[2]] }
        case .nullPlayerModern:
            if let skin = ModernSkinEngine.shared.currentSkin { return [skin.eqLowColor, skin.eqMidColor, skin.eqHighColor] }
        case .winampModern, .wmp, .audion, .sonique:
            break
        }
        return Self.winampMeter
    }

    /// The classic Library's renderer, cached per skin as the Library caches it: the white text sheet
    /// is built once per renderer.
    private var tabRenderer: (path: String, renderer: SkinRenderer)?

    /// The Library's tab in this family, which the buttons are drawn as.
    private var tab: StudioTab {
        let wm = WindowManager.shared
        if wm.uiMode.controllerFamily == .nullPlayerModern {
            return .original(ModernSkinEngine.shared.currentSkin ?? ModernSkinLoader.shared.loadDefault())
        }
        let skin = wm.currentSkin ?? SkinLoader.shared.loadDefault()
        let path = wm.currentSkinPath ?? "default"
        if tabRenderer?.path != path { tabRenderer = (path, SkinRenderer(skin: skin)) }
        let style = wm.hostedSurfaceStyle
        return .classic(renderer: tabRenderer!.renderer, style: style, colors: style?.playlistColors ?? skin.playlistColors)
    }

    /// The running Original or Original-Metal skin; nil in every other family.
    private var originalSkin: ModernSkin? {
        guard WindowManager.shared.uiMode.controllerFamily == .nullPlayerModern else { return nil }
        return ModernSkinEngine.shared.currentSkin
    }

    override func draw(_ dirtyRect: NSRect) {
        let f = StudioFaceplate(session.faceplateKind, style: surfaceStyle, meter: meterColors, tab: tab, originalSkin: originalSkin)
        // Over, not copied: Original's clear panel must leave the chrome's surface behind it.
        f.panel.setFill()
        bounds.fill(using: .sourceOver)

        drawHeader(f)
        for (channel, panel) in panels.enumerated() { drawPanel(panel, channel: channel, f) }
        for (button, rect) in buttons {
            f.drawIcon(symbol(button), in: rect, lit: isLit(button), faint: isFaint(button))
        }
    }

    /// Draws `body` into `rect` through the bloom where the faceplate glows, else as it is.
    private func glow(_ f: StudioFaceplate, _ rect: CGRect, _ body: () -> Void) {
        guard f.glows else { body(); return }
        bloom.draw(rect, scale: window?.backingScaleFactor ?? 2, ground: f.panel, body)
    }

    private func drawHeader(_ f: StudioFaceplate) {
        // Name display: the profile, a dirty marker, and the menu it opens.
        f.well.setFill()
        NSBezierPath(roundedRect: nameRect, xRadius: 3, yRadius: 3).fill()
        f.edge.setStroke()
        NSBezierPath(roundedRect: nameRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
        // "*" marks unsaved changes: the classic sheet has no "●".
        f.drawDisplayText(session.name + (session.isDirty ? " *" : ""),
                          in: CGRect(x: nameRect.minX + 10, y: nameRect.minY, width: nameRect.width - 40, height: nameRect.height))
        f.drawText("▾", font: f.buttonFont, color: f.wellDimText, in: CGRect(x: nameRect.maxX - 22, y: nameRect.minY, width: 14, height: nameRect.height))
    }

    /// MODE shows its current setting's icon.
    private func symbol(_ button: Button) -> String {
        switch button {
        case .link: return "link"
        case .mode: return session.mode == .graphic ? "slider.vertical.3" : "dial.medium"
        case .headroom: return "gauge.with.dots.needle.33percent"
        case .save: return "square.and.arrow.down"
        case .saveAs: return "square.and.arrow.down.on.square"
        case .rename: return "pencil"
        case .delete: return "trash"
        case .revert: return "arrow.uturn.backward"
        case .faceplate: return "paintpalette"
        case .bypass: return "power"
        case .flat: return "arrow.counterclockwise"
        }
    }

    /// The tooltip: MODE names its current setting; FACEPLATE switches between the two looks.
    private func title(_ button: Button) -> String {
        switch button {
        case .link: return "Link Channels"
        case .mode: return "Mode: \(session.mode.rawValue.capitalized)"
        case .headroom: return "Headroom"
        case .save: return "Save"
        case .saveAs: return "Save As…"
        case .rename: return "Rename…"
        case .delete: return "Delete…"
        case .revert: return "Revert"
        case .faceplate: return "Switch View"
        case .bypass: return "Bypass"
        case .flat: return "Flat"
        }
    }

    private func drawPanel(_ panel: Panel, channel: Int, _ f: StudioFaceplate) {
        f.edge.withAlphaComponent(0.6).setStroke()
        NSBezierPath(roundedRect: panel.frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()

        // The name is a console's scribble strip; its colour bar lights with LINK, so the two
        // channels read as one linked pair. Then the peak response and preamp readouts; BYPASS and
        // FLAT are drawn with the toolbar.
        f.drawScribbleStrip(channel == 0 ? "LEFT" : "RIGHT", in: panel.name, lit: session.linked)
        let peak = session.responses[channel].peak + Double(session.edit[channel].preamp)
        f.drawText(String(format: "PK %+.1f", peak), font: f.legendFont, color: peak > 0.05 ? f.peak : f.dimText,
                   in: panel.peakReadout)
        f.drawText(String(format: "PRE %+.1f", session.edit[channel].preamp), font: f.legendFont, color: f.dimText,
                   in: panel.preampReadout)

        drawAnalyser(panel, channel: channel, f)
        switch session.mode {
        case .graphic:
            drawFaders(panel, channel: channel, f)
        case .parametric:
            let strip = panel.strip, parametric = session.edit[channel].parametric
            glow(f, strip.graph) {
                strip.drawGraph(parametric, x: panel.x(frequency:),
                                drawResponse: { drawResponse(panel, channel: channel, in: $0, f) }, f)
            }
            strip.drawControls(parametric, f)
        }
        drawPreamp(panel, channel: channel, f)
    }

    private func drawPreamp(_ panel: Panel, channel: Int, _ f: StudioFaceplate) {
        // A guide across the slot at each labelled step, in its label's colour; 0 dB the strongest.
        for tick in f.faderTickLabels {
            let y = panel.preamp.y(gain: tick).rounded()
            f.dimText.withAlphaComponent(tick == 0 ? 1 : 0.55).setFill()
            NSRect(x: panel.preamp.minX, y: y, width: panel.preamp.width, height: 1).fill()
            f.drawText(StudioFaceplate.dbLabel(tick), font: f.legendFont, color: f.dimText,
                       in: CGRect(x: panel.preamp.maxX + 2, y: panel.preamp.y(gain: tick) - 6, width: 18, height: 12))
        }
        f.drawFader(x: panel.preamp.midX, value: session.edit[channel].preamp, in: panel.preamp, cap: f.text, width: 18,
                    travel: f.preampTravel)
        f.drawText("PRE", font: f.legendFont, color: f.dimText,
                   in: CGRect(x: panel.preamp.minX - 8, y: panel.legend.minY, width: panel.preamp.width + 16,
                              height: panel.legend.height), alignment: .center)
    }

    /// 0…1 up the analyser's dB scale, clamped.
    private static func analyserPosition(_ db: Float) -> Float {
        let range = analyserRange
        return (min(range.upperBound, max(range.lowerBound, db)) - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    private func analyserY(_ db: Float, in rect: CGRect) -> CGFloat {
        rect.maxY - CGFloat(Self.analyserPosition(db)) * rect.height
    }

    /// What the ladder shows depends on where the feed sits: the local feed is pre-profile, so the
    /// auditioned curve is added (BYPASS shows the source); the streaming feed is already the output
    /// — post-profile, post-EQ, post-SRS — so it is shown as-is.
    private func drawAnalyser(_ panel: Panel, channel: Int, _ f: StudioFaceplate) {
        let rect = panel.analyser
        let graticule = stride(from: Self.analyserRange.upperBound - 6, to: Self.analyserRange.lowerBound, by: -f.graticuleStep)
        let streaming = WindowManager.shared.audioEngine.isStreamingPlayback
        let bypassed = session.bypass[channel]
        let added = session.responses[channel].centres.map { streaming || bypassed ? 0 : Float($0) + session.edit[channel].preamp }
        let levels = zip(session.levels[channel], added).map(+), peaks = zip(session.peaks[channel], added).map(+)

        glow(f, rect) {
            f.well.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            for db in graticule {
                (db == 0 ? f.graticuleZero : f.graticule).setFill()
                NSRect(x: rect.minX, y: analyserY(db, in: rect), width: rect.width, height: f.graticuleWeight).fill()
            }
            if f.octaveGrid {
                f.scale.setFill()
                for band in stride(from: 0, to: EQProfileDesign.bandCount, by: 3) {
                    NSRect(x: panel.centreX(band), y: rect.minY, width: 0.5, height: rect.height).fill()
                }
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            switch f.kind {
            case .console: drawBars(levels, peaks: peaks, panel, f)
            case .boutique: drawHeatCurve(levels, peaks: peaks, panel, f)
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // The labels sit on top, unbloomed.
        for db in graticule where db.truncatingRemainder(dividingBy: 12) == 0 {
            f.drawText(String(format: "%.0f", db), font: f.legendFont, color: f.wellDimText,
                       in: CGRect(x: rect.maxX - 22, y: analyserY(db, in: rect) - 6, width: 20, height: 12), alignment: .right)
        }
    }

    /// Console: a bar per band, coloured by the heat step its level reaches, with a peak line.
    private func drawBars(_ levels: [Float], peaks: [Float], _ panel: Panel, _ f: StudioFaceplate) {
        let rect = panel.analyser
        for band in 0..<EQProfileDesign.bandCount {
            let top = analyserY(levels[band], in: rect)
            let bar = CGRect(x: panel.centreX(band) - panel.bandWidth / 2 + 1.5, y: top,
                             width: panel.bandWidth - 3, height: rect.maxY - top)
            (f.heat.last { levels[band] > $0.db } ?? f.heat[0]).color.setFill()
            bar.fill()
            f.peak.setFill()
            NSRect(x: bar.minX, y: analyserY(peaks[band], in: rect), width: bar.width, height: 1.5).fill()
        }
    }

    /// Boutique: the levels as a curve filled with heat, and the peak holds as embers.
    private func drawHeatCurve(_ levels: [Float], peaks: [Float], _ panel: Panel, _ f: StudioFaceplate) {
        let rect = panel.analyser
        var locations = f.heat.map { CGFloat(Self.analyserPosition($0.db)) }
        guard let heat = NSGradient(colors: f.heat.map(\.color), atLocations: &locations, colorSpace: .sRGB) else { return }
        let points = levels.indices.map { CGPoint(x: panel.centreX($0), y: analyserY(levels[$0], in: rect)) }
        let line = NSBezierPath()
        for (band, point) in points.enumerated() { band == 0 ? line.move(to: point) : line.line(to: point) }
        let curve = NSBezierPath()
        curve.append(line)
        curve.line(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
        curve.line(to: CGPoint(x: points[0].x, y: rect.maxY))
        curve.close()
        // The fill is graded on the analyser's own dB scale, so a loud band burns white-hot.
        NSGraphicsContext.saveGraphicsState()
        curve.addClip()
        heat.draw(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.minX, y: rect.minY), options: [])
        NSGraphicsContext.restoreGraphicsState()
        line.lineWidth = 1
        f.accent.withAlphaComponent(0.8).setStroke()
        line.stroke()
        // Peak holds are embers in their level's heat; the bloom makes the hot ones glow.
        for (band, db) in peaks.enumerated() {
            heat.interpolatedColor(atLocation: CGFloat(Self.analyserPosition(db))).setFill()
            NSBezierPath(roundedRect: CGRect(x: panel.centreX(band) - 4, y: analyserY(db, in: rect) - 1, width: 8, height: 2),
                         xRadius: 1, yRadius: 1).fill()
        }
    }

    private func drawFaders(_ panel: Panel, channel: Int, _ f: StudioFaceplate) {
        let rect = panel.faders
        let bands = session.edit[channel].bands

        glow(f, rect) {
            // Scale: engraved on Console, a fine line on Boutique.
            for tick in f.faderTicks {
                let y = rect.y(gain: tick).rounded() + 0.5
                switch f.kind {
                case .console:
                    f.scale.withAlphaComponent(tick == 0 ? 0.55 : 0.28).setFill()
                    NSRect(x: rect.minX, y: y - 0.5, width: rect.width, height: 1).fill()
                    NSColor.black.withAlphaComponent(0.35).setFill()
                    NSRect(x: rect.minX, y: y + 0.5, width: rect.width, height: 1).fill()
                case .boutique:
                    f.scale.setFill()
                    NSRect(x: rect.minX, y: y - 0.25, width: rect.width, height: 0.5).fill()
                }
            }
            for band in 0..<EQProfileDesign.bandCount {
                let cap = f.capColor(band: band)
                f.drawFader(x: panel.centreX(band), value: EQCurve.clamp(bands[band] + session.responses[channel].stripAtCentres[band]),
                            in: rect, cap: cap, width: min(panel.bandWidth - 4, f.capWidth), travel: f.bandTravel(cap: cap))
            }
            drawResponse(panel, channel: channel, in: rect, f)
        }
        for band in 0..<EQProfileDesign.bandCount {
            f.drawText(Self.bandLabels[band], font: f.legendFont, color: f.dimText,
                       in: CGRect(x: panel.centreX(band) - panel.bandWidth / 2 - 2, y: panel.legend.minY,
                                  width: panel.bandWidth + 4, height: panel.legend.height), alignment: .center)
        }
    }

    /// The response actually applied — both stages, without the preamp, at 48 kHz — on a ±12 dB scale in `rect`.
    private func drawResponse(_ panel: Panel, channel: Int, in rect: CGRect, _ f: StudioFaceplate) {
        let path = NSBezierPath()
        for (index, (frequency, db)) in zip(EqualizerStudioSession.gridFrequencies, session.responses[channel].grid).enumerated() {
            let point = CGPoint(x: panel.x(frequency: frequency), y: rect.y(gain: Float(max(-12, min(12, db)))))
            index == 0 ? path.move(to: point) : path.line(to: point)
        }
        path.lineWidth = 1.2
        f.accent.withAlphaComponent(session.bypass[channel] ? 0.25 : 0.85).setStroke()
        path.stroke()
    }
}

/// The toolbar's icons carry no labels; each names itself on hover.
extension EqualizerStudioView: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        buttons.first { $0.1.contains(point) }.map { title($0.0) } ?? ""
    }
}

/// The Studio in a `.wal` skin's frame. Its session follows the hosted window's show and hide
/// (`WindowManager.hostedWindowVisibilityDidChange`), not `resume`/`suspend`, which also come with
/// occlusion — covering the window must not end it.
extension EqualizerStudioView: WinampModernHostedSurface {
    var view: NSView { self }
    func applyPalette(_ style: WinampModernSurfaceStyle) { needsDisplay = true }
    func applySkinScale(_ scale: CGFloat) { needsDisplay = true }
    func resume() {}
    func suspend() {}
    func unmountFromHolder() { removeFromSuperview() }
    func prepareForUITeardown() {
        hostedContext = nil
        removeFromSuperview()
    }
}
