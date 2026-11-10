import CoreGraphics
import Foundation

/// The three modes: each one's picture, controls and what Sonique draws over them.
extension SoniqueSkinPainter {
    func navigator() {
        // The drawer first, its dials included, and only outside the console's frame: it sits behind
        // the console, so the console's pure black is black, not the drawer (padd's sliders, sonyque's icons).
        if let drawer = scene.drawer, let misc = skin.image("/jpeg/misc") {
            context.saveGState()
            clipOutsideConsole()
            let b = drawer.bounds, origin = scene.drawerOrigin
            let at = skin.settings.origin(.drawer)
            let x = at.x + b.left - origin.x, y = at.y + b.top - origin.y
            draw(misc, source: .init(left: x, top: y, right: x + b.right - b.left, bottom: y + b.bottom - b.top),
                 x: b.left, y: b.top, clip: drawer.rects)
            if scene.state.navDrawerOpen { drawerDials(misc, clip: drawer.rects) }
            context.restoreGState()
        }
        // The screen is Sonique's own surface, opaque: black in the picture there stays black (k2),
        // and nothing behind it, the drawer included, shows through (Trigun).
        if let display = skin.display {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(display.rects.map(\.cgRect))
        }
        picture()
        if scene.state.navScreen == .menu { menuScreen() }
        visualModePanel()
        statusLine()
        litStates(navigator: true)
        let strip: SoniqueKnobStrip = skin.image(SoniqueKnobStrip.navVolume.image) != nil ? .navVolume : .volume
        knob(control: .volume, strip: strip, value: host.volume)
    }

    /// Clips to the canvas minus the navigator's frame. Frame rects never overlap, so even-odd over
    /// the canvas leaves exactly the canvas without them.
    private func clipOutsideConsole() {
        guard let frame = skin.region(SoniqueSkin.Mode.navigator.frame) else { return }
        context.addRect(scene.canvas.cgRect)
        context.addRects(frame.rects.map(\.cgRect))
        context.clip(using: .evenOdd)
    }

    /// The open drawer's EQ slider handles (`SLIDEROFF`, `SLIDERON` while held), centred on their
    /// tracks and see-through by their darkness (`handle(_:)`), and its three knobs, `/jpeg/smallknob`'s
    /// grey frames tinted with each knob's colour (skinpack § *animations*).
    private func drawerDials(_ misc: CGImage, clip drawer: [SoniqueSkinRegion.Rect]) {
        let sliders = skin.settings.drawerSliders
        let w = sliders.handleWidth, h = sliders.handleHeight
        let handles = [SoniqueLitState.sliderOff, .sliderOn].map { state -> CGImage? in
            let at = skin.settings.origin(state)
            return misc.cropping(to: CGRect(x: at.x, y: at.y, width: w, height: h)).flatMap(Self.handle)
        }
        for (index, value) in host.eq.prefix(SoniqueSkinScene.eqSliders).enumerated() {
            guard let handle = handles[scene.state.pressed == .eqSlider(index) ? 1 : 0] else { continue }
            let track = scene.eqSliderTrack(index)
            let top = track.top + Int((1 - min(1, max(0, value))) * Double(track.bottom - track.top - h))
            context.saveGState()
            clip(to: drawer)
            draw(handle, x: track.left + (track.right - track.left - w) / 2, y: top)
            context.restoreGState()
        }
        for (control, value, colour) in [(SoniqueSkinControl.amp, host.amp, SoniqueColour.ampKnobColor),
                                         (.balance, host.balance, .balKnobColor), (.pitch, host.pitch, .pitchKnobColor)] {
            // A drawer knob's strip is a full turn, of which the knob sweeps 250° about its middle frame
            // (oracle: frames 5–30 of sonique's 36, 3–16 of metrobin's 20, 2–8 of bluehorizon's 11).
            knob(control: control, strip: .drawer, value: value, tint: colour, turn: 250.0 / 360)
        }
    }

    /// A slider handle as Sonique blends it: each pixel's opacity is its luminance over 128, so the
    /// near-black frame vanishes, mid-greys are half there and the light face is solid (sonique's
    /// grey handle within 1 level, BlueEyes' blue ball within 5, over screen 6's open drawer).
    private static func handle(_ sprite: CGImage) -> CGImage? {
        let w = sprite.width, h = sprite.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(sprite, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 0, to: w * h * 4, by: 4) where p[i + 3] == 255 {
            let luma = (299 * Int(p[i]) + 587 * Int(p[i + 1]) + 114 * Int(p[i + 2])) / 1000
            let alpha = min(255, luma * 2)
            for c in 0..<4 { p[i + c] = UInt8(Int(p[i + c]) * alpha / 255) }
        }
        return context.makeImage()
    }

    func mid() {
        picture()
        // With a track loaded the top window is the vis's, drawn on black (issue #729's captures of
        // Sonique); with none it is the picture, as the oracle draws it.
        if host.trackLoaded, let top = scene.region(for: .vis) {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(top.rects.map(\.cgRect))
        }
        litStates(navigator: false)
        knob(control: .volume, strip: .volume, value: host.volume)
        // The shuttle at rest is its first frame (258 mid captures closer than the middle one).
        knob(control: .shuttle, strip: .shuttle, value: 0, opaque: false)
        // The track's ring is a whole turn; the playlist's 270°, leaving the logo's quarter, unless
        // `mid_playlistmode` is 0 (the default skin's listposring stops at 9 o'clock).
        ring(.songRing, progress: host.songProgress, sweep: 1, gradient: .track)
        ring(.listRing, progress: host.listProgress, sweep: skin.settings.midListRingIsWholeTurn ? 1 : 0.75,
             gradient: .playList)
        songDisplay()
    }

    /// A progress ring, clockwise from 12:00 (issue #731; Sonique's own captures). The skin paints the
    /// dots in its picture under the ring's region, and Sonique tints them: the part come so far by
    /// the gradient at each dot's place, the rest by `ProgressBkColor`. With nothing loaded the ring
    /// is the picture, as the oracle draws it (a flat `ProgressBkColor` there made 239 mid captures worse).
    private func ring(_ control: SoniqueSkinControl, progress: Double, sweep: Double, gradient: SoniqueProgressGradient) {
        guard host.trackLoaded, let region = scene.region(for: control) else { return }
        context.saveGState()
        clip(to: region.rects)
        context.setBlendMode(.multiply)
        // Aliased, so neighbouring wedges meet without a seam of untinted picture between them.
        context.setShouldAntialias(false)
        let b = region.bounds.cgRect, centre = CGPoint(x: b.midX, y: b.midY), radius = max(b.width, b.height)
        // Skin pixels run top-down, so angles grow clockwise; -90° is 12:00. One wedge per 2° is
        // finer than any ring's dots.
        let slices = Int(180 * sweep), lit = Int((min(1, max(0, progress)) * Double(slices)).rounded(.down))
        let step = 2 * Double.pi * sweep / Double(slices)
        for slice in 0..<slices {
            let start = -Double.pi / 2 + Double(slice) * step
            context.move(to: centre)
            context.addArc(center: centre, radius: radius, startAngle: start, endAngle: start + step, clockwise: false)
            context.closePath()
            context.setFillColor(slice < lit ? colour(along: gradient, at: Double(slice) / Double(slices - 1))
                                             : colour(.progressBkColor))
            context.fillPath()
        }
        context.restoreGState()
    }

    /// Mid mode's song window, Sonique's own drawing at fixed offsets from `/rgn/mid/bottom`'s top-left
    /// whatever its size (measured on sonique, sTek2k, musicman, k2, carrot): a tab in
    /// `SystemBkColor_2` edged in `BorderColor` (pure black is not drawn), the track number, the time
    /// and the status line in `SystemColor_1`.
    /// ponytail: ~37 skins have a song window too small for this, and Sonique lays those out tighter
    /// (Trigun shows the time alone, CougarKW drops the hundredths); here they get it cut to the region.
    private func songDisplay() {
        guard let region = scene.region(for: .songInfo) else { return }
        let x = region.bounds.left, y = region.bounds.top
        context.saveGState()
        clip(to: region.rects)
        // The tab hangs from the window's top edge: open at the top, 3 px sides and bottom.
        let tab = { (inset: Int) in
            CGPath(roundedRect: CGRect(x: x + 13 + inset, y: y - 8, width: 68 - 2 * inset, height: 39 - inset),
                   cornerWidth: 5, cornerHeight: 5, transform: nil)
        }
        if skin.settings.colour(.systemBkColor2) != 0 {
            context.addPath(tab(3))
            context.setFillColor(colour(.systemBkColor2))
            context.fillPath()
        }
        if skin.settings.colour(.borderColor) != 0 {
            context.addPath(tab(0))
            context.addPath(tab(3))
            context.setFillColor(colour(.borderColor))
            context.fillPath(using: .evenOdd)
        }
        let seconds = host.elapsedSeconds
        let lines = [(String(format: "%03d", host.trackNumber), 15, CGFloat(14)),
                     (String(format: "%02d:%02d.00", seconds / 60 % 100, seconds % 60), 25, 10)]
        for (string, baseline, size) in lines {
            text(SoniqueSkinText(string: string, x: x + 13, baseline: y + baseline, size: size, colour: .systemColor1)
                .centred(on: x + 47))
        }
        songTitle(in: region, idle: SoniqueSkinText(string: "NullPlayer", x: x + 13, baseline: y + 41, size: 9,
                                                    colour: .systemColor1))
        context.restoreGState()
    }

    /// The title under the tab, wrapped to the window's width row by row and centred, 11 px apart down
    /// to the window's bottom, as Sonique fills its round window (issue #732's captures). A title that
    /// still does not fit scrolls on the first line instead.
    private func songTitle(in region: SoniqueSkinRegion, idle: SoniqueSkinText) {
        // Lines 11 px apart, down to 3 px above the window's bottom; each row's span is read 4 px above
        // its baseline (mid-letter) and keeps 2 px clear either side.
        let lineHeight = 11, midLetter = 4, margin = 2, bottomClear = 3
        let x = region.bounds.left
        // One span per row the window covers, stopping at the first it does not.
        var spans: [(left: Int, right: Int, baseline: Int)] = []
        for baseline in stride(from: idle.baseline, through: region.bounds.bottom - bottomClear, by: lineHeight) {
            let row = region.rects.filter { $0.top <= baseline - midLetter && $0.bottom > baseline - midLetter }
            guard let left = row.map(\.left).min(), let right = row.map(\.right).max() else { break }
            spans.append((left, right, baseline))
        }
        var line = idle
        line.string = host.title
        // Past the last row everything left goes on one more line, which says it does not fit.
        let lines = host.title.isEmpty ? [] : wrapped(line) { n in
            n < spans.count ? CGFloat(spans[n].right - spans[n].left - 2 * margin) : .greatestFiniteMagnitude
        }
        guard !lines.isEmpty, lines.count <= spans.count else {
            return titleLine(idle, centreX: x + 47, right: x + 81)
        }
        for (n, string) in lines.enumerated() {
            line.string = string
            line.x = spans[n].left + margin
            line.baseline = spans[n].baseline
            text(line.centred(on: (spans[n].left + spans[n].right) / 2))
        }
    }

    func small() {
        guard let picture = skin.image(SoniqueSkin.Mode.small.picture), let bar = skin.region(SoniqueSkin.Mode.small.frame) else { return }
        if let side = scene.state.smallDrawer { smallDrawer(side) }
        // `/jpeg/smallstate` is the bar twice: unlit above, lit below. The lit half shows through
        // the progress lines as far as they have come, and the blinker caps by loudness.
        let barHeight = bar.bounds.bottom
        let unlit = SoniqueSkinRegion.Rect(left: 0, top: 0, right: picture.width, bottom: barHeight)
        draw(picture, source: unlit, x: 0, y: 0, clip: bar.rects)
        let lit: (SoniqueSkinRegion.Rect) -> Void = { rect in
            draw(picture, source: rect.offset(0, barHeight), x: rect.left, y: rect.top, clip: [rect])
        }
        // ponytail: fixed spots measured on the oracle's default small frame (every corpus small
        // frame is that shape, `format.md`); read them from a skin if one ever moves its lines.
        let line = (left: 93, right: 184)
        let filled = { (fraction: Double) in line.left + Int(Double(line.right - line.left) * min(1, max(0, fraction))) }
        lit(.init(left: line.left, top: 3, right: filled(host.listProgress), bottom: 6))
        lit(.init(left: line.left, top: 18, right: filled(host.songProgress), bottom: 21))
        if host.blinkersLit {
            lit(.init(left: 9, top: 0, right: 15, bottom: barHeight))
            lit(.init(left: 186, top: 0, right: 192, bottom: barHeight))
        }
        let time = String(format: "%02d:%02d:%02d", host.elapsedSeconds / 3600, host.elapsedSeconds / 60 % 60, host.elapsedSeconds % 60)
        text(SoniqueSkinText(string: String(format: "%03d", host.trackNumber), x: 93, baseline: 16, size: 11, colour: .systemColor1))
        text(SoniqueSkinText(string: time, x: 125, baseline: 16, size: 11, colour: .systemColor1))
    }

    /// The open drawer: `/jpeg/extra`'s half for that side, then Sonique's icons and marquee on it.
    private func smallDrawer(_ side: SoniqueSmallDrawer) {
        guard let placement = skin.smallDrawerPlacement(side) else { return }
        if let extra = skin.image("/jpeg/extra") {
            let b = placement.region.bounds
            draw(extra, source: b, x: b.left + placement.dx, y: b.top + placement.dy,
                 clip: placement.region.rects.map { $0.offset(placement.dx, placement.dy) })
        }
        for (control, rect) in scene.drawerButtons {
            icon(control, in: rect, lit: scene.state.pressed == control)
        }
        if let marquee = scene.marqueeRect, !host.title.isEmpty {
            context.saveGState()
            clip(to: [marquee])
            self.marquee(SoniqueSkinText(string: host.title, x: marquee.left, baseline: marquee.bottom - 2, size: 9,
                                         colour: .systemColor1), right: marquee.right)
            context.restoreGState()
        }
    }
}
