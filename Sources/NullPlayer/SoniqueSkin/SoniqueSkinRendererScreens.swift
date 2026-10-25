import CoreGraphics
import Foundation

/// The navigator's display: the menu and visual mode screens and the status line under them.
extension SoniqueSkinPainter {
    /// The visual mode screen (`SoniqueSkinScene.VisualScreen`); the window lays the effects surface
    /// over the vis panel's well.
    func visualModePanel() {
        typealias Screen = SoniqueSkinScene.VisualScreen
        guard let display = scene.visualScreenDisplay else { return }
        let x = display.bounds.left, top = display.bounds.top, bottom = display.bounds.bottom
        context.saveGState()
        clip(to: display.rects)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(Screen.visBlack.offset(x, top).cgRect)
        if skin.settings.colour(.systemBkColor2) != 0 {
            context.setFillColor(colour(.systemBkColor2))
            for frame in [Screen.visFrame.offset(x, top), Screen.fileFrame.offset(x, top), Screen.songFrame.offset(x, bottom)] {
                context.addPath(CGPath(roundedRect: frame.cgRect, cornerWidth: Screen.panelRadius, cornerHeight: Screen.panelRadius,
                                       transform: nil))
            }
            context.fillPath()
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(Screen.well.offset(x, top).cgRect)
        }
        text(SoniqueSkinText(string: scene.state.visualModeTitle, x: x + Screen.well.left, baseline: top + Screen.titleBaseline,
                             size: 8, colour: .systemColor1).centred(on: x + Screen.titleCentre))

        let s = host.elapsedSeconds
        let digits = { (string: String, left: Int) in
            SoniqueSkinText(string: string, x: x + left, baseline: bottom + Screen.digitsBaseline, size: Screen.digitSize,
                            colour: .systemColor1, font: Screen.digitFont)
        }
        text(digits(String(format: "%03d", host.trackNumber), Screen.trackX))
        text(digits(String(format: "%02d:%02d:%02d.%02d", s / 3600, s / 60 % 60, s % 60, host.elapsedHundredths), Screen.timeX))
        let label = { (string: String, left: Int, baseline: Int) in
            SoniqueSkinText(string: string, x: left, baseline: baseline, size: 9, colour: .systemColor2, spacing: Screen.labelSpacing)
        }
        for (string, centre) in Screen.labels {
            text(label(string, x, bottom + Screen.labelBaseline).centred(on: x + centre))
        }
        // The dots fill with progress as the mid rings do: the playlist's in `PlayListColor_1`, the
        // track's in `ProgressColor_1`, over `ProgressBkColor`.
        for (row, (progress, fill)) in zip(Screen.progressRows, [(host.listProgress, SoniqueColour.playListColor1), (host.songProgress, .progressColor1)]) {
            let lit = Int((progress * Double(Screen.dots)).rounded(.down))
            for dot in 0..<Screen.dots {
                context.setFillColor(colour(dot < lit ? fill : .progressBkColor))
                context.fillEllipse(in: CGRect(x: x + Screen.dotLeft + dot * Screen.dotSize, y: bottom + row.top,
                                               width: Screen.dotSize, height: Screen.dotSize))
            }
            text(label(row.label, x + Screen.dotLeft + 2, bottom + row.baseline))
        }

        text(label("file:", x + Screen.fileLeft, top + Screen.fileBaseline))
        var file = SoniqueSkinText(string: host.fileName, x: x + Screen.fileLeft, baseline: 0, size: 8, colour: .systemColor1)
        for (i, line) in wrapped(file, width: CGFloat(Screen.fileFrame.right - Screen.fileLeft - 3)).enumerated() {
            let baseline = Screen.fileBaseline + (i + 1) * Screen.fileLineHeight
            guard baseline <= Screen.fileFrame.bottom - 3 else { break }
            file.string = line
            file.baseline = top + baseline
            text(file)
        }
        context.restoreGState()
    }

    /// The navigator's status line, Sonique's own, along the display's bottom edge: a band in
    /// `StatusBarBgColor` dotted with `StatusBarFgColor`, and the title (`Sonique 1.96` idle; NullPlayer
    /// writes its own name and version) in `StatusBarTextColor`, centred on the display's span 7 px left of its
    /// middle (Trigun, Danzig and sonique all measure so).
    func statusLine() {
        guard let display = skin.display else { return }
        let bottom = display.bounds.bottom, band = CGRect(x: display.bounds.left, y: bottom - 13,
                                                         width: display.bounds.right - display.bounds.left, height: 13)
        context.saveGState()
        clip(to: display.rects)
        context.clip(to: band)
        context.setFillColor(colour(.statusBarBgColor))
        context.fill(band)
        context.setFillColor(colour(.statusBarFgColor))
        // A 2 px dot grid over the band (stopping 3 rows short, as sonique looks at 6x, made 301
        // captures worse).
        context.fill(stride(from: Int(band.minY), to: bottom, by: 2).flatMap { y in
            stride(from: Int(band.minX), to: Int(band.maxX), by: 2).map { CGRect(x: $0, y: y, width: 1, height: 1) }
        })
        let span = display.rects.filter { $0.top <= bottom - 5 && $0.bottom > bottom - 5 }
        let left = span.map(\.left).min() ?? display.bounds.left, right = span.map(\.right).max() ?? display.bounds.right
        titleLine(SoniqueSkinText(string: "NullPlayer \(host.version)", x: left + 2, baseline: bottom - 3, size: 9,
                                  colour: .statusBarTextColor),
                  centreX: (left + right) / 2 - 7, right: right - 2)
        context.restoreGState()
    }

    /// The menu screen in the display (`SoniqueSkinMenu`): each entry's lettering and boxed icon, the
    /// right column's headings and the version, in the skin's system colours.
    func menuScreen() {
        guard let display = skin.display else { return }
        let dx = display.bounds.left, dy = display.bounds.top
        context.saveGState()
        clip(to: display.rects)
        logo(at: dx, dy)
        for line in [SoniqueSkinMenu.Logo.label] + SoniqueSkinMenu.headings + [SoniqueSkinMenu.version(host.version)] {
            text(line.offset(dx, dy))
        }
        for entry in SoniqueSkinMenu.entries {
            entry.lines.forEach { text($0.offset(dx, dy)) }
            if let icon = entry.icon { menuIcon(entry.item, in: icon.offset(dx, dy).cgRect) }
        }
        context.restoreGState()
    }

    /// NullPlayer's wordmark in the logo's place (`SoniqueSkinMenu.Logo`): the swoosh, then the word
    /// filled black and edged in `LogoColor` over it, as Sonique's letters cross its swoosh.
    private func logo(at dx: Int, _ dy: Int) {
        context.addPath(SoniqueSkinMenu.Logo.swoosh.path(dx: dx, dy: dy))
        context.addPath(SoniqueSkinMenu.Logo.swooshHole.path(dx: dx, dy: dy))
        context.setFillColor(colour(.logoRingColor))
        context.fillPath(using: .evenOdd)
        let word = SoniqueSkinMenu.Logo.word.offset(dx, dy)
        draw(word.attributed(ink: SoniqueSkinRenderer.cgColor(0), outline: colour(word.colour)),
             x: word.x, baseline: word.baseline, lettering: false)
    }
}
