import CoreGraphics
import Foundation

/// A `SoniqueSkinScene` to pixels, one skin pixel per pixel. Pure CoreGraphics, so the harness and
/// the window draw through the same path. The loader has already keyed pure black out of every
/// picture; the outline clips everything, and is black under it all.
enum SoniqueSkinRenderer {
    static func render(_ scene: SoniqueSkinScene) -> CGImage? {
        let w = scene.width, h = scene.height
        guard w > 0, h > 0,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Skin pixels, top-left origin: flip once and move skin (0,0) to its place in the canvas.
        context.translateBy(x: 0, y: CGFloat(h))
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: CGFloat(-scene.canvas.left), y: CGFloat(-scene.canvas.top))
        context.interpolationQuality = .none
        let painter = SoniqueSkinPainter(context: context, scene: scene)
        painter.clip(to: scene.outline)
        // Inside the window Sonique paints black where a picture is pure black; only the outline
        // is transparent.
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: scene.canvas.left, y: scene.canvas.top, width: w, height: h))
        switch scene.state.mode {
        case .navigator: painter.navigator()
        case .mid: painter.mid()
        case .small: painter.small()
        }
        painter.balls()
        return context.makeImage()
    }

    /// A `[sonique colors]` value, `0xRRGGBB`.
    static func cgColor(_ rgb: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// What draws a scene: the canvas and the shared drawing steps. The modes, the navigator's screens,
/// Sonique's own glyphs and its lettering are extensions in their own `SoniqueSkinRenderer*` files.
struct SoniqueSkinPainter {
    let context: CGContext
    let scene: SoniqueSkinScene
    var skin: SoniqueSkin { scene.skin }
    var host: SoniqueSkinHostState { scene.state.host }

    func clip(to rects: [SoniqueSkinRegion.Rect]) {
        context.clip(to: rects.map(\.cgRect))
    }

    /// `image` drawn with its top-left at (x, y), skin pixels.
    func draw(_ image: CGImage, x: Int, y: Int) {
        // The context is flipped, so the image is drawn flipped back about its own middle.
        context.saveGState()
        context.translateBy(x: CGFloat(x), y: CGFloat(y + image.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.restoreGState()
    }

    /// The part of `image` at `source` (top-left, skin pixels), drawn at (x, y) inside `clip`.
    func draw(_ image: CGImage, source: SoniqueSkinRegion.Rect, x: Int, y: Int, clip rects: [SoniqueSkinRegion.Rect]) {
        let bounded = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let part = image.cropping(to: source.cgRect.intersection(bounded)), !rects.isEmpty else { return }
        context.saveGState()
        clip(to: rects)
        draw(part, x: x + max(0, -source.left), y: y + max(0, -source.top))
        context.restoreGState()
    }

    func picture() {
        guard let picture = skin.image(scene.state.mode.picture) else { return }
        context.saveGState()
        if let frame = skin.region(scene.state.mode.frame) { clip(to: frame.rects) }
        draw(picture, x: 0, y: 0)
        context.restoreGState()
    }

    // MARK: - Lit states

    /// Each control's lit state from `/jpeg/misc`: the key names the top-left of a rectangle the
    /// size of the control's bounds (skinpack `how-to-make-skins` § *misc locations*), drawn over
    /// the control and cut to its shape. The play button is a play/stop toggle: while playing it
    /// shows the stop picture, `…STOPOFF`, lit to `…STOPON` while pressed.
    /// The navigator reads each state's `NAV_` position and adds the rocker's.
    func litStates(navigator: Bool) {
        guard let misc = skin.image("/jpeg/misc") else { return }
        let pressed = scene.state.pressed
        var lit: [(SoniqueSkinControl, SoniqueLitState)] = []
        if host.playState == .playing {
            lit.append((.play, pressed == .play ? .stopOn : .stopOff))
        } else if pressed == .play {
            lit.append((.play, .playOn))
        }
        if host.playState == .paused || pressed == .pause { lit.append((.pause, .pauseOn)) }
        if pressed == .prev { lit.append((.prev, .prev)) }
        if pressed == .next { lit.append((.next, .next)) }
        if pressed == .eject { lit.append((.eject, .orangeOn)) }
        if host.shuffle { lit.append((.shuffle, .greenOn)) }
        if host.repeatAll { lit.append((.repeatButton, .cyanOn)) }
        if pressed == .navButton { lit.append((.navButton, .redOn)) }
        if navigator {
            if pressed == .up { lit.append((.up, .bigUp)) }
            if pressed == .down { lit.append((.down, .bigOnDown)) }
        }
        for (control, state) in lit {
            draw(misc, lit: state, navigator: navigator, control: control)
        }
    }

    private func draw(_ misc: CGImage, lit state: SoniqueLitState, navigator: Bool, control: SoniqueSkinControl) {
        guard let region = scene.region(for: control) else { return }
        let (x, y) = skin.settings.origin(state, navigator: navigator)
        let b = region.bounds
        draw(misc, source: .init(left: x, top: y, right: x + b.right - b.left, bottom: y + b.bottom - b.top),
             x: b.left, y: b.top, clip: region.rects)
    }

    /// A knob's frame from its horizontal strip (`<key>_width` px a frame, `<key>_images` frames),
    /// at the control's top-left and cut to its shape: a frame can be wider than the knob (BlueEyes:
    /// 29 px frames on a 15 px knob), and the oracle shows only the part inside it.
    /// `tint` multiplies the frame by a `[sonique colors]` key: the drawer's knobs are grey strips.
    /// A knob's frame is opaque, its pure black drawn black over the picture (257 captures closer); the
    /// shuttle's is not (26 mid captures worse opaque), so it passes `opaque: false`. `turn` is the
    /// share of the strip, centred on its middle, that the value spans.
    func knob(control: SoniqueSkinControl, strip key: SoniqueKnobStrip, value: Double,
              tint: SoniqueColour? = nil, opaque: Bool = true, turn: Double = 1) {
        guard let strip = skin.image(key.image), let region = scene.region(for: control) else { return }
        let declared = skin.settings.frames(key)
        let width = max(1, declared.width)
        let frames = max(1, min(declared.count, strip.width / width))
        let frame = Int(((0.5 + (min(1, max(0, value)) - 0.5) * turn) * Double(frames - 1)).rounded())
        let b = region.bounds
        if opaque {
            let face = CGRect(x: b.left, y: b.top, width: width, height: strip.height)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(region.rects.map { $0.cgRect.intersection(face) })
        }
        draw(strip, source: .init(left: frame * width, top: 0, right: frame * width + width, bottom: strip.height),
             x: b.left, y: b.top, clip: region.rects)
        guard let tint else { return }
        context.saveGState()
        clip(to: region.rects)
        context.setBlendMode(.multiply)
        context.setFillColor(colour(tint))
        context.fill(CGRect(x: b.left, y: b.top, width: width, height: strip.height))
        context.restoreGState()
    }

    func colour(_ key: SoniqueColour) -> CGColor { SoniqueSkinRenderer.cgColor(skin.settings.colour(key)) }
}

extension SoniqueSkinRegion.Rect {
    var cgRect: CGRect { CGRect(x: left, y: top, width: right - left, height: bottom - top) }
}
