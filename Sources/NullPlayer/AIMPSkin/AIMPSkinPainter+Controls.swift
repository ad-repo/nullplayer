import CoreGraphics
import Foundation

/// Keys, captions, sliders, digit strips and tabs, as the layout decided they look.
extension AIMPSkinPainter {
    /// A key, or a control drawn as one: its picture at `frame`, a panel's fill, its caption.
    func drawKey(_ control: AIMPSkinControl, _ key: AIMPControlClass.Key, image: AIMPSkinImage?, frame: Int, caption: String,
                 glyphFirst: Bool, in rect: CGRect) {
        // A panel's `Color` fills it under its picture (Unsquareable's light theme: a #DDDDDD panel
        // over the whole customize window).
        if key.fill != nil { canvas.fill(rect, argb: argb(key.fill)) }
        // `glyphFirst`: its centred glyph at its left (`AIMPSkinLayout.Look.key`).
        if glyphFirst, let image {
            let size = image.frameSize
            paint(image, in: CGRect(x: rect.minX, y: rect.midY - (size.height / 2).rounded(), width: size.width, height: size.height), frame: frame)
        } else {
            paint(image, in: rect, frame: frame)
        }
        guard key.showsText, !caption.isEmpty else { return }
        let text = control.text, font = self.font(text.font)
        // A display that wraps runs down from its top (FLAT DARK's tips; 200 corpus displays).
        if key.role == .textDisplay, text.wraps {
            canvas.draw(AIMPSkinText.lines(caption, font: font, width: rect.width), font: font, in: rect, alignment: text.alignment)
            return
        }
        // A key's caption sits in its picture's content margins, centred unless its `Alignment` says
        // otherwise (FLAT DARK's text keys); a display's `Alignment` (`taCenter`, `taRightJustify`)
        // places its text in its box; a running line scrolls what does not fit.
        let isButton = key.role == .button, running = key.role == .runningLine
        let box = isButton ? image.map { $0.contentMargins.inset(rect) } ?? rect : rect
        let alignment = running ? nil : text.alignment ?? (isButton ? .center : nil)
        canvas.draw(caption, font: font, at: CGPoint(x: isButton ? box.minX : rect.minX + 4, y: box.midY),
                    centeredIn: alignment == .center ? box : nil,
                    clippedTo: isButton ? nil : rect, scrolls: running, rightAligned: alignment == .right)
    }

    /// `places` frames of a digit strip (0–9 first), zero-padded, left to right, each overlapping
    /// the last by `-indent`. A one-digit display of a one-frame image is a picture the value picks.
    func drawDigits(_ image: AIMPSkinImage?, value: Double, digits: AIMPControlClass.Digits, in rect: CGRect) {
        guard let image else { return }
        let number = max(0, Int(value.rounded(.towardZero)))
        let size = image.frameSize, indent = CGFloat(digits.indent), declared = digits.places ?? 0
        // No `Digits`: as many as the box holds, the number to the right, the places before it
        // blank when the strip has a blank (TEAC CD-RW890's VOLUME and minutes: three in 57 px,
        // 13 frames, the last blank); a counter's higher places roll off. A box one digit wide is a
        // number label instead: it grows to the left of the box to hold the number (RealPlayer 11's
        // "44 kHz" and "320 kbps", set against their labels).
        let fits = Int((rect.width + indent) / max(1, size.width + indent))
        let places = declared > 0 ? declared : fits <= 1 ? String(number).count : fits
        let blank = declared > 0 ? nil : image.frameCount >= 13 ? 12 : image.frameCount == 11 ? 10 : nil
        let text = String(String(number).suffix(places))
        let padded = String(repeating: blank == nil ? "0" : " ", count: max(0, places - text.count)) + text
        let overflow = declared > 0 ? 0 : CGFloat(max(0, places - max(1, fits))) * (size.width + indent)
        for (i, character) in padded.enumerated() {
            let x = rect.minX - overflow + CGFloat(i) * (size.width + indent)
            paint(image, in: CGRect(x: x, y: rect.minY, width: size.width, height: size.height), frame: character.wholeNumberValue ?? blank ?? 0)
        }
    }

    /// A 13-frame strip: digits 0–9, then the separator, the minus and a blank. `Digits` places show
    /// the seconds as [-]MM:SS, right-aligned, `IndentBetweenDigits` apart (Denon's -4 packs six 20-px
    /// glyphs into its 100-px box).
    func drawTime(_ image: AIMPSkinImage?, seconds: Int, digits: AIMPControlClass.Digits, in rect: CGRect) {
        guard let image else { return }
        let text = String(format: "%02d:%02d", (seconds / 60) % 100, seconds % 60)
        let glyphs = String(repeating: " ", count: max(0, (digits.places ?? text.count) - text.count)) + text
        let size = image.frameSize, step = size.width + CGFloat(digits.indent)
        for (i, character) in glyphs.enumerated() {
            let frame = character.wholeNumberValue ?? (character == ":" ? 10 : character == "-" ? 11 : 12)
            paint(image, in: CGRect(x: rect.minX + CGFloat(i) * step, y: rect.minY, width: size.width, height: size.height), frame: frame)
        }
    }

    /// The track's rating: a star picture (empty, lit, …) five across, lit up to the rating.
    func drawRating(_ image: AIMPSkinImage?, rating: Int, in rect: CGRect) {
        guard let image else { return }
        let size = image.frameSize
        for i in 0..<max(1, Int(rect.width / max(1, size.width))) {
            paint(image, in: CGRect(x: rect.minX + CGFloat(i) * size.width, y: rect.minY, width: size.width, height: size.height),
                  frame: i < rating ? 1 : 0)
        }
    }

    /// A slider's track, its progress frame up to `fraction`, and its thumb there.
    func drawSlider(_ slider: AIMPControlClass.Slider, image: AIMPSkinImage?, fraction: Double, thumb: AIMPSkinImage?, in rect: CGRect) {
        // `SliderVertical`, or any slider turned upright (Kenwood KX-4520's EQ: `Orientation` oVertical).
        let vertical = slider.isVertical
        // A track drawn centred runs the slider's length at its own thickness (Unsquareable's
        // customize sliders: a 10×5 line under a 350-px slider).
        if let image, image.fill == .center, let line = image.frame(0) {
            let thickness = vertical ? image.frameSize.width : image.frameSize.height
            canvas.drawUpright(line, in: vertical
                ? CGRect(x: rect.midX - (thickness / 2).rounded(), y: rect.minY, width: thickness, height: rect.height)
                : CGRect(x: rect.minX, y: rect.midY - (thickness / 2).rounded(), width: rect.width, height: thickness))
        } else {
            paint(image, in: rect)
        }
        // A vertical slider fills from the bottom and its thumb rides up and down inside the track
        // (Technics SL-1200's volume).
        let filled = vertical
            ? CGRect(x: rect.minX, y: rect.maxY - (rect.height * fraction).rounded(), width: rect.width, height: (rect.height * fraction).rounded())
            : CGRect(x: rect.minX, y: rect.minY, width: (rect.width * fraction).rounded(), height: rect.height)
        // The progress frame is the track's lit twin: revealed up to the value, never squeezed.
        if let image, image.frameCount > 1, filled.width > 0, filled.height > 0 {
            context.saveGState()
            context.clip(to: filled)
            paint(image, in: rect, frame: 1)
            context.restoreGState()
        }
        if let thumb {
            let s = thumb.frameSize
            let thumbRect = vertical
                ? CGRect(x: rect.minX + ((rect.width - s.width) / 2).rounded(),
                         y: rect.minY + ((rect.height - s.height) * (1 - fraction)).rounded(), width: s.width, height: s.height)
                : CGRect(x: filled.maxX - (s.width / 2).rounded(), y: rect.minY + ((rect.height - s.height) / 2).rounded(),
                         width: s.width, height: s.height)
            paint(thumb, in: thumbRect)
        }
    }

    /// AIMP 4's playlist tabs (`TabControl` over `prvPlaylistManager`): NullPlayer's one playlist (or
    /// its library), its tab lit.
    func drawTabControl(_ tabs: AIMPSkinControl.Tabs, caption: String, image: AIMPSkinImage?, in rect: CGRect) {
        paint(image, in: rect)
        let tabImage = self.image(tabs.picture) ?? self.image(tabs.optionsPicture)
        let size = tabImage?.frameSize ?? CGSize(width: rect.width, height: 20)
        let vertical = rect.height > rect.width
        // A row of tabs: as wide as its caption needs, at least its picture.
        let font = self.font(tabs.font)
        let width = vertical ? rect.width : min(rect.width, max(size.width, AIMPSkinText.width(caption, font: font) + 24))
        let box = CGRect(x: rect.minX, y: rect.minY, width: width, height: min(rect.height, size.height))
        paint(tabImage, in: box, frame: (tabImage?.frameCount ?? 1) > 1 ? 1 : 0)
        canvas.draw(caption, font: font, at: CGPoint(x: box.minX + 6, y: box.midY), centeredIn: box, clippedTo: box)
    }

    /// The playlist tabs: NullPlayer has the one playlist, its tab lit (the active frame, the
    /// second), at the start of the row or the top of the column.
    func drawPlaylistTabs(_ tabs: AIMPSkinControl.Tabs, playing: Bool, image: AIMPSkinImage?, in rect: CGRect) {
        paint(image, in: rect)
        let tab = self.image(tabs.optionsPicture)
        let size = tab?.frameSize ?? CGSize(width: min(rect.width, 100), height: min(rect.height, 20))
        let box = CGRect(origin: rect.origin, size: CGSize(width: tabs.isVertical ? rect.width : size.width, height: size.height))
        paint(tab, in: box, frame: (tab?.frameCount ?? 1) > 1 ? 1 : 0)
        let inner = tabs.offsets?.inset(box) ?? box
        canvas.draw("Playlist", font: self.font(playing ? tabs.playingFont : tabs.activeFont), at: CGPoint(x: inner.minX + 4, y: inner.midY),
                    centeredIn: tabs.isCentred ? inner : nil, clippedTo: inner)
    }
}
