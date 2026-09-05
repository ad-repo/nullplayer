import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Text drawing: `<text>` layout and `forcefixed`, the attribute cache, ticker motion,
/// bitmap fonts, and the text NullPlayer draws on its own surfaces inside a skin. Split
/// out of `WasabiRenderer.swift`; see
/// `skills/winamp-modern-skin-guide/reference/rendering/text.md`.
extension WasabiSceneRenderer {
    func drawText(_ object: WasabiObject, frame: CGRect, context: CGContext) {
        // Content resolution (`display=`, a songticker's implicit track title, `setAlternateText`)
        // is shared with the measurement a script's `getAutoWidth()` gets — see `WasabiTextMetrics`.
        drawText(WasabiTextMetrics.content(of: object, host: host),
                 object: object, frame: frame, context: context)
    }

    /// `undeclaredColor` is what a text object that names no `color=` draws in. White for everything
    /// the skin lays out itself — Wasabi's own default, and what the corpus is drawn against — but an
    /// `<edit>` is different: Winamp fills it with a native child window whose text is
    /// `wasabi.list.text`, the same colour the lists take (Big Bento says so in its own markup:
    /// *"lists/trees item foreground (also edit text)"*). Left as white, a search box typed into a
    /// Light skin wrote white on white.
    func drawText(_ text: String, object: WasabiObject, frame rawFrame: CGRect,
                          context: CGContext, undeclaredColor: NSColor = .white) {
        // `leftpadding`/`rightpadding` inset the text inside its own rect. They are part of the width
        // a script measures with `getAutoWidth()`, so honouring them here is what makes a box sized
        // from that measurement fit the string it was sized for (ClassicPro's menu bar and SUI tabs).
        let left = CGFloat(Double(object.attributes["leftpadding"] ?? "0") ?? 0)
        let right = CGFloat(Double(object.attributes["rightpadding"] ?? "0") ?? 0)
        let frame = CGRect(x: rawFrame.minX + left, y: rawFrame.minY,
                           width: max(0, rawFrame.width - left - right), height: rawFrame.height)
        if let fontID = object.attributes["font"],
           let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: fontID),
           definition.kind == "bitmapfont" {
            drawBitmapText(text, definition: definition, object: object, frame: frame, context: context)
            return
        }
        // A skin (or one of its scripts) can name any point size at all, including 0, a negative, or
        // something that does not parse. CoreText builds its own attribute dictionary from whatever
        // it is handed, and an unusable size or font there aborts the process from inside a draw.
        let size = WasabiTextMetrics.pointSize(of: object)
        let font = resources.font(identifier: object.attributes["font"], size: size,
                                  traits: WasabiTextMetrics.traits(of: object))
            ?? NSFont.systemFont(ofSize: size)
        // Optional for the same reason as the font: nothing that ends up in a CoreText attribute
        // dictionary may be a null pointer, and only an `Optional` binding can see one.
        let resolved: NSColor? = object.attributes["color"].flatMap(resolvedColor)
        let color = resolved ?? undeclaredColor
        let alignment: NSTextAlignment
        switch object.attributes["align"]?.lowercased() {
        case "center": alignment = .center
        case "right": alignment = .right
        default: alignment = .left
        }
        // A wrapping object is laid out as a paragraph rather than as a line: broken at word
        // boundaries inside its own width, stacked downward, and never scrolled. See
        // `WasabiTextMetrics.wraps`.
        let wraps = WasabiTextMetrics.wraps(of: object)
        var attributes = textAttributes(font: font, color: color, alignment: alignment,
                                        lineBreakMode: wraps ? .byWordWrapping : .byClipping)
        // `forcefixed` is a different layout, not a different font: every glyph gets the same cell.
        // A fixed run is a clock or a counter and is sized to fit, so it never enters the ticker.
        let pitch = WasabiTextMetrics.fixedPitch(of: object, font: font)
        // A clock is laid out in fields with their own cells, which is a third layout again — and it
        // is sized to fit for the same reason a fixed run is, so it never scrolls either.
        let clock = WasabiTextMetrics.clockRun(of: object, text: text, font: font)
        // The same memo the layout path fills (B106), which is keyed on the *font alone*. Safe
        // here even though the draw dictionary also carries a colour and a paragraph style:
        // `NSString.size(withAttributes:)` has no bounding width to align or break inside, so
        // neither attribute has anything to act on — established over the whole cross product by
        // `WinampModernTextDrawingTests.testParagraphStyleDoesNotChangeSingleLineWidth` rather than
        // assumed, because a `measured` that stops agreeing with what the skin measured is B87's
        // defect arriving silently.
        let measured = clock?.width ?? pitch?.width(of: text)
            ?? resources.textWidth(of: text, font: font)
        // A paragraph absorbs its overflow into extra lines, so there is nothing left for a ticker
        // to carry — and a marquee running a wrapped block sideways is never what a skin asked for.
        let overflow = pitch == nil && clock == nil && !wraps ? measured - frame.width : 0
        let scroll = overflow > 0 ? tickerMotion(for: object, overflow: overflow, textWidth: measured) : nil
        if scroll != nil {
            // While scrolling, the string is drawn into an oversized rect, so any alignment other
            // than left would re-centre it inside that rect and cancel the motion out. A scrolling
            // object never wraps (the overflow a ticker carries is what a paragraph absorbs into
            // extra lines), so the line-break mode here is the non-wrapping one by construction.
            attributes = textAttributes(font: font, color: color, alignment: .left,
                                        lineBreakMode: .byClipping)
        }

        // Wasabi centres a string in its box unless `valign=` says otherwise; `NSString.draw(in:)`
        // starts at the box's top edge, which is `valign="top"` and nothing else. The difference is a
        // whole line's leading on a tall box (Love is War Miku's 30px time readout) and enough on a
        // tight one to push the song ticker's descenders onto the seek bar below it. Under the local
        // mirror below, a rect's *top* edge is its `maxY`, so lowering the text by `inset` means
        // moving the rect down the same amount. Clamped at zero: a string taller than its own box
        // starts at the top rather than above it, whatever it asked for.
        //
        // A paragraph's "cell" is the height of the whole broken block, not of one line: aligning a
        // nine-line block by a single line's leading would centre its *first* line in the box and
        // run the other eight out of the bottom.
        let lineCell = font.ascender - font.descender
        let cell: CGFloat
        if wraps {
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: frame.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            cell = max(lineCell, ceil(bounds.height))
        } else {
            cell = lineCell
        }
        let inset = max(0, WasabiTextMetrics.verticalAlignment(of: object)
            .offset(cell: cell, in: frame.height))
        // `offsetx`/`offsety` shift the *string* inside its own box without moving the box — so the
        // object still measures and hit-tests where it was declared, and its parent still clips it
        // where it was. Big Bento Modern's SUI tab labels are the measured case: `offsetx="35"` puts
        // the label clear of the 40px icon, which in the icons-only tab mode (a 40px-wide strip) is
        // also what pushes it entirely outside the clip. Ignoring the attribute drew every tab's
        // caption straight over its own icon.
        let offsetX = CGFloat(Double(object.attributes["offsetx"] ?? "0") ?? 0)
        let offsetY = CGFloat(Double(object.attributes["offsety"] ?? "0") ?? 0)
        let drawFrame = frame.offsetBy(dx: offsetX, dy: -inset - offsetY)
        // …and when the shift lands the string's own origin in the **last pixel column** of what is
        // still visible, the skin means it to be gone, not to leave a sliver. Big Bento Modern's SUI
        // tab captions land exactly there in the icons-only mode: `offsetx="35"` on a box at x=4
        // starts the string on column 39 of a 40px strip, so a glyph with no left side bearing (`V`,
        // `W`) paints one bright column beside its icon and one of antialiasing beside that, and each
        // caption's first letter decides how much — which is what made the strip look notched. A
        // single column of a 24px letter is never information; it is the fringe of a string the
        // clip was meant to swallow.
        if scroll == nil, alignment == .left {
            let visible = context.boundingBoxOfClipPath.intersection(frame)
            if !visible.isNull, drawFrame.minX >= visible.maxX - 1 { return }
        }

        context.saveGState()
        // A `<text>`'s box is a **layout anchor, not a scissor**, horizontally (B87). A skin sizes its
        // own boxes from the very measurement this renderer draws with and then routinely declares one
        // a pixel or two narrower than the string it just measured: ClassicPro's SUI tab is
        // `label.getAutoWidth() + 14` around a `<text w="-15" relatw="1">`, so the label's box is
        // always `measurement - 1`, and its v2 engine is `getTextWidth() + 23` around `w="-26"`, three
        // short. Scissored at its own rect the last glyph is cut through its middle and the strip
        // reads `LIE PLE VII` for `LIB PLE VID` — the shape of B87. The group is what actually bounds
        // the string (the tab is 32 wide and hands its label only 17 of them), so clip horizontally to
        // the ambient clip and keep the object's own rect for the vertical bound — BB27's auto-height
        // still decides whether a line is drawn at all, and a string still cannot bleed onto the row
        // above or below it.
        //
        // A **scrolling** ticker keeps its own box on both axes: the motion is defined by that box, and
        // a marquee let loose in its parent would smear across the whole panel.
        //
        // A **wrapping** object keeps its box on both axes too, and for the same reason as a ticker:
        // the width is not an approximation the skin measured a string against, it is the width the
        // paragraph was broken to. Anything still overrunning it is one unbreakable word, and Winamp
        // cuts it there.
        let clip: CGRect
        if scroll == nil, !wraps {
            let ambient = context.boundingBoxOfClipPath
            let minX = min(frame.minX, ambient.minX)
            let maxX = max(frame.maxX, ambient.maxX)
            clip = CGRect(x: minX, y: frame.minY, width: maxX - minX, height: frame.height)
        } else {
            clip = frame
        }
        context.clip(to: clip)
        context.translateBy(x: 0, y: frame.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.midY)
        // The rect a string was drawn in was a **vertical** scissor as well as a layout box, and a
        // `CTLine` has no rect at all, so that bound is restored here. It is load-bearing wherever a
        // skin declares a font taller than the box it draws into, which is the whole point of a box
        // that clips: measured pixel-for-pixel against `NSString.draw` over four faces, a 24pt line
        // in a 16px box differs by ~350 pixels without it and by none with it
        // (`WinampModernTextDrawingTests`). The wrapping branch draws into its own rect and needs no
        // help.
        //
        // Applied *inside* the mirror, which is the space the rect it replaces was read in. `clip`
        // above works unflipped only because mirroring `frame` about its own midpoint gives `frame`
        // back; `drawFrame` is that box after `valign` and `offsety` have moved the string inside
        // it, so it is not symmetric and the same trick does not work on it.
        if !wraps {
            context.clip(to: CGRect(x: clip.minX, y: drawFrame.minY,
                                    width: clip.width, height: drawFrame.height))
        }
        // Where a line's baseline sits inside `drawFrame`, and the one piece of vertical arithmetic
        // the conversion needs. All three branches share it: a clock cell and a ticker use the same
        // rect vertically, and only the horizontal origin differs between them.
        let baseline = drawFrame.maxY - resources.baselineOffset(of: font)
        if let scroll {
            // The rect the string used to be drawn in was exactly `measured` wide, so it never
            // scissored; `clip = frame` above is what bounds a marquee, and it is unchanged.
            var x = drawFrame.minX - scroll.offset
            drawCachedLine(text, font: font, color: color, x: x, baseline: baseline, context: context)
            if scroll.wraps {
                // Continuous mode runs the tail off the left edge, so draw a second copy a gap
                // behind it; otherwise the ticker would blank out between cycles.
                x += measured + Self.tickerGap
                drawCachedLine(text, font: font, color: color, x: x, baseline: baseline, context: context)
            }
        } else if let clock {
            // The run keeps a pixel or two of clearance from the edge it is aligned against — a skin
            // that puts a separator beside a readout counts on it, and centring needs none because
            // both edges are already free.
            // Aligned by the room the clock holds, then drawn from that room's left edge — so the
            // digits stay in their columns rather than shuffling when the value gains one.
            let room = clock.layoutWidth
            var origin: CGFloat
            switch alignment {
            case .right: origin = drawFrame.maxX - WasabiTextMetrics.ClockRun.edgeInset - room
            case .center: origin = drawFrame.minX + (drawFrame.width - room) / 2
            default: origin = drawFrame.minX + WasabiTextMetrics.ClockRun.edgeInset
            }
            // Each cell places its own field, so the object's alignment must not apply a second time
            // inside one: a centred glyph sits in the middle of its fixed-pitch cell, and every other
            // field starts at its own cell's left edge.
            //
            // The cell rect used to be a scissor as well as a box — `.byClipping` was set for that
            // reason — and a `CTLine` has none. The per-cell clip below restores it. It is not
            // hypothetical: a `timecolonwidth` narrower than the colon glyph is exactly the case, and
            // Big Bento Modern declares one.
            for cell in clock.cells {
                let cellFrame = CGRect(x: origin, y: drawFrame.minY,
                                       width: cell.width, height: drawFrame.height)
                let glyphWidth = resources.textWidth(of: cell.text, font: font)
                let x = cell.centred ? cellFrame.minX + (cellFrame.width - glyphWidth) / 2
                                     : cellFrame.minX
                context.saveGState()
                context.clip(to: cellFrame)
                drawCachedLine(cell.text, font: font, color: color, x: x, baseline: baseline,
                               context: context)
                context.restoreGState()
                origin += cell.width
            }
        } else {
            // `forcefixed` outside a clock run reserves a **width**; it does not monospace the glyphs.
            // `measured` above is already the fixed-pitch width, so the box a skin sizes from
            // `getTextWidth()` stays put as the digits change — which is the jitter `forcefixed`
            // exists to stop — while the string itself is drawn with the font's own advances, from
            // that reserved room's aligned edge.
            //
            // Drawing each glyph centred in a widest-digit cell was the earlier reading, and cPro2
            // Dark Aluminum rules it out. `info-text.m` places the total time at
            // `trackTime.getTextWidth() - 4 + 21` — a deliberate 4px tuck into the elapsed time's
            // reserved box — and the author's own `screenshot.png` shows a clear gap between `2:16`
            // and the `/`. Under cell drawing the final digit fills its cell, so the ink runs to the
            // box edge and the separator lands on top of it *for every value and every cell width*:
            // clearing a 4px tuck by centring would need a cell 8px wider than the glyph on each
            // side. Only a proportionally drawn string inside a fixed reservation produces the gap.
            //
            // A clock run (`display="time"`) is unaffected: it is handled above and keeps its cells,
            // which is what holds Big Bento Modern's digits in their columns across 9:59 → 10:00.
            //
            // The **widened clip** above is now the only scissor, which is what B87 wanted all
            // along. `NSString.draw(in:)` also cut the string at its own rect, so the rect had to be
            // widened to `max(drawFrame.width, measured)` purely to defeat that second scissor; a
            // `CTLine` draws from an origin and is bounded by the context clip alone, so the
            // widening has nothing left to do and is gone.
            if wraps {
                // The one branch that stays on `NSString.draw`. Here the rect *is* the line-breaking
                // width — the paragraph style breaks and aligns each line inside it, and
                // `boundingRect` on the same attributes decided the block's height above. Replacing
                // it means re-implementing line breaking to keep the draw and the measure agreeing,
                // for a case that is rare and never in a per-row loop.
                (text as NSString).draw(in: drawFrame, withAttributes: attributes)
            } else {
                // The object's own alignment, applied to the origin rather than inside a rect —
                // which is what it already was, so cPro2's 4px tuck and Big Bento's clock columns
                // keep the arithmetic they had.
                let x: CGFloat
                switch alignment {
                case .right: x = drawFrame.maxX - measured
                case .center: x = drawFrame.midX - measured / 2
                default: x = drawFrame.minX
                }
                drawCachedLine(text, font: font, color: color, x: x, baseline: baseline,
                               context: context)
            }
        }
        context.restoreGState()
    }

    /// Draw one cached line with its **left edge at `x` and its baseline at `y`**, in `color`.
    ///
    /// The context is expected to be inside `drawText`'s local flip, which is the y-up space
    /// CoreText draws upright in — the scene's own transform is top-origin, so the flip is what
    /// makes it y-up rather than something to undo. The colour goes on the context because the line
    /// is cached colourless; see `WasabiTextMetrics.line(for:font:)`.
    private func drawCachedLine(_ text: String, font: NSFont, color: NSColor, x: CGFloat,
                                baseline: CGFloat, context: CGContext) {
        guard !text.isEmpty, let line = resources.line(for: text, font: font) else { return }
        context.setFillColor(color.cgColor)
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
    }

    /// The attribute dictionary a string draws with — memoized, because it is a pure function of
    /// exactly these four values and it is the **same** dictionary for every row of a list.
    ///
    /// `drawText` and `drawFlippedText` each built one per string, per frame, allocating a fresh
    /// `NSMutableParagraphStyle` inside it; the two clock-cell styles were computed *properties*, so
    /// a skin with a seconds field allocated one per cell per frame. Nothing here depends on the
    /// call, and a dictionary handed to `NSString.draw` is not mutated by it.
    private func textAttributes(font: NSFont, color: NSColor, alignment: NSTextAlignment,
                                lineBreakMode: NSLineBreakMode) -> [NSAttributedString.Key: Any] {
        let key = TextAttributeKey(font: font, color: color, alignment: alignment,
                                   lineBreakMode: lineBreakMode)
        if let cached = cachedTextAttributes[key] { return cached }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ]
        if cachedTextAttributes.count >= Self.maximumTextAttributes {
            cachedTextAttributes.removeAll(keepingCapacity: true)
        }
        cachedTextAttributes[key] = attributes
        return attributes
    }

    struct TextAttributeKey: Hashable {
        let font: NSFont
        let color: NSColor
        let alignment: NSTextAlignment
        let lineBreakMode: NSLineBreakMode
    }

    /// How far to shift an over-long string this frame, and whether the motion wraps.
    ///
    /// `ticker="bounce"` slides to the end and back; any other enabled value scrolls continuously.
    /// A `songticker` scrolls by default — that is the whole point of the object — while a plain
    /// `text` only scrolls when it opts in, so static labels stay put.
    private func tickerMotion(for object: WasabiObject, overflow: CGFloat,
                              textWidth: CGFloat) -> (offset: CGFloat, wraps: Bool)? {
        let isSongticker = object.typeName.caseInsensitiveCompare("songticker") == .orderedSame
        let mode = (object.attributes["ticker"] ?? (isSongticker ? "1" : "0")).lowercased()
        guard !["0", "off", "false", "no"].contains(mode) else { return nil }
        if mode == "bounce" {
            let span = Double(overflow)
            let cycle = span * 2
            guard cycle > 0 else { return nil }
            let phase = (clock() * Self.tickerSpeed).truncatingRemainder(dividingBy: cycle)
            return (CGFloat(phase <= span ? phase : cycle - phase), false)
        }
        // One cycle carries the string its own width plus the gap, at which point the trailing copy
        // has taken its place exactly.
        let cycle = Double(textWidth + Self.tickerGap)
        guard cycle > 0 else { return nil }
        return (CGFloat((clock() * Self.tickerSpeed).truncatingRemainder(dividingBy: cycle)), true)
    }

    private func drawBitmapText(_ text: String, definition: WalResourceDefinition,
                                object: WasabiObject, frame: CGRect, context: CGContext) {
        let alignment: NSTextAlignment
        switch object.attributes["align"]?.lowercased() {
        case "center": alignment = .center
        case "right": alignment = .right
        default: alignment = .left
        }
        drawBitmapText(text, definition: definition, frame: frame, alignment: alignment,
                       verticalAlignment: WasabiTextMetrics.verticalAlignment(of: object),
                       colonWidth: WasabiTextMetrics.bitmapColonWidth(of: object),
                       ticker: object, context: context)
    }

    /// Draw a run of bitmap-font glyphs. `ticker` is the object whose scroll state applies, or nil for
    /// content NullPlayer draws itself (a playlist row never scrolls).
    private func drawBitmapText(_ text: String, definition: WalResourceDefinition, frame: CGRect,
                                alignment: NSTextAlignment,
                                verticalAlignment: WasabiTextMetrics.VerticalAlignment = .center,
                                colonWidth: CGFloat? = nil,
                                ticker: WasabiObject?, context: CGContext) {
        guard let sheet = resources.fontSheet(for: definition) else { return }
        let charWidth = max(1, Int(Double(definition.attributes["charwidth"] ?? "1") ?? 1))
        let charHeight = max(1, Int(Double(definition.attributes["charheight"] ?? "1") ?? 1))
        let spacing = Int(Double(definition.attributes["hspacing"] ?? "0") ?? 0)
        let advance = max(1, charWidth + spacing)
        let positions = Self.bitmapGlyphPositions
        // `timecolonwidth` is the colon's own **cell**, and on a fixed-pitch atlas the colon is the
        // only glyph that gets one. A sheet inks its colon into the left few columns of a
        // full-width cell, so advancing the whole cell leaves the rest of it as a gap before the
        // seconds: ClassicPro's `numfont.png` is 15px per glyph with a 6px colon and its engine
        // declares `timecolonwidth="6"` for exactly that reason — without it every cPro clock reads
        // `1:03: 16` (B-cPro colon gap). Enkera, TRON Legacy and impulse are the corpus's other
        // bitmap-font clocks and all of them declare a cell *narrower* than the atlas advance, so
        // the glyph is cropped to its cell rather than centred in it — which is also what the Core
        // Text path's per-cell clip does with a `timecolonwidth` narrower than the glyph.
        let colonAdvance = colonWidth.map { max(1, $0.rounded()) }
        let colonCrop = colonAdvance.map { min(CGFloat(charWidth), $0) }
        func cellWidth(of character: Character) -> CGFloat {
            character == ":" ? (colonCrop ?? CGFloat(charWidth)) : CGFloat(charWidth)
        }
        func advanceWidth(of character: Character) -> CGFloat {
            character == ":" ? (colonAdvance ?? CGFloat(advance)) : CGFloat(advance)
        }
        let width = text.reduce(CGFloat(0)) { $0 + advanceWidth(of: $1) }
        var startX: CGFloat
        switch alignment {
        case .center: startX = frame.midX - width / 2
        case .right: startX = frame.maxX - width
        default: startX = frame.minX
        }
        // Bitmap-font tickers share the TrueType path's motion model. The previous formula anchored
        // the run at `frame.maxX`, so at rest the text sat entirely off the right edge and a long
        // title simply vanished instead of scrolling.
        var repeats: [CGFloat] = []
        if width > frame.width, let ticker,
           let scroll = tickerMotion(for: ticker, overflow: width - frame.width, textWidth: width) {
            startX = frame.minX - scroll.offset
            repeats = scroll.wraps ? [width + Self.tickerGap] : []
        }

        // A sheet's glyphs are a fixed `charheight` tall, so the run's vertical placement is one
        // offset for the whole line. The scene is drawn top-origin (see `draw(in:)`), so this is a
        // distance down from `minY` — it was pinned there, which is `valign="top"` and only correct
        // for the 54 declarations that ask for it. Rounded: a glyph is a blit, and a half-pixel
        // origin resamples an LED readout into a blur. Clamped at zero for the same reason as the
        // Core Text path: a sheet whose glyphs are taller than the box keeps their tops.
        let top = frame.minY + max(0, verticalAlignment
            .offset(cell: CGFloat(charHeight), in: frame.height).rounded())

        context.saveGState()
        context.clip(to: frame)
        for origin in [CGFloat.zero] + repeats {
            var x = startX + origin
            for character in text.lowercased() {
                let (column, row) = positions[character] ?? positions[" "] ?? (0, 0)
                let cell = cellWidth(of: character)
                // Top-left origin: `cropping(to:)` indexes pixel rows directly (see `bitmap(identifier:)`).
                let cropRect = CGRect(x: CGFloat(column * charWidth), y: CGFloat(row * charHeight),
                                      width: cell, height: CGFloat(charHeight))
                if x + advanceWidth(of: character) >= frame.minX, x <= frame.maxX,
                   cropRect.maxY <= CGFloat(sheet.height), cropRect.maxX <= CGFloat(sheet.width),
                   let glyph = cropped(sheet.image, to: cropRect) {
                    drawImage(glyph, in: CGRect(x: x, y: top,
                                                width: cell, height: CGFloat(charHeight)),
                              context: context)
                }
                x += advanceWidth(of: character)
            }
        }
        context.restoreGState()
    }

    /// Draw one line of NullPlayer-owned content (a playlist row, a status line) with the skin's own
    /// font when it has one, and a system font when it does not.
    func drawSurfaceText(_ text: String, in rect: CGRect, color: NSColor,
                                 alignment: NSTextAlignment, pointSize: CGFloat,
                                 context: CGContext) {
        if let definition = surfaceFont, definition.kind == "bitmapfont" {
            drawBitmapText(text, definition: definition, frame: rect, alignment: alignment,
                           ticker: nil, context: context)
            return
        }
        let font = surfaceTextFont(pointSize: pointSize)
        drawFlippedText(text, in: rect, font: font, color: color, alignment: alignment, context: context)
    }

    /// How wide `drawSurfaceText` will draw a string. Resolves the font by the same two branches, so
    /// a caller that sizes a box from this gets the box the text actually needs — a tab measured in
    /// one font and drawn in another is a tab whose label runs past its own edge.
    func surfaceTextWidth(_ text: String, pointSize: CGFloat) -> CGFloat {
        if let definition = surfaceFont, definition.kind == "bitmapfont" {
            let charWidth = max(1, Int(Double(definition.attributes["charwidth"] ?? "1") ?? 1))
            let spacing = Int(Double(definition.attributes["hspacing"] ?? "0") ?? 0)
            return CGFloat(text.count * max(1, charWidth + spacing))
        }
        let font = surfaceTextFont(pointSize: pointSize)
        return resources.textWidth(of: text, font: font)
    }

    /// The face a NullPlayer-owned surface draws in, for a skin whose list font is not a bitmap
    /// sheet.
    ///
    /// **A skin that declares no list font at all is not the same case as one naming a face that
    /// cannot be resolved**, and it is the common case: cPro Bento, cPro2 Dark Aluminum and Anaheim
    /// Player all declare the `wasabi.list.*`/`studio.list.*` *colours* and no list font whatsoever.
    /// Passing that nil id down lands on `WasabiTextMetrics`' monospaced fallback, which is the right
    /// *diagnostic* for a name that resolved to nothing and the wrong *default* for silence — every
    /// playlist row in those skins drew in a console face.
    ///
    /// Winamp does not leave the list unfonted there: the Modern framework supplies the default, a
    /// proportional UI face, which is also what these skins ask for themselves everywhere they do
    /// name one (Anaheim's playlist window says `font="Arial"` on all four of its own `<text>`
    /// objects). So an undeclared list font resolves as `Arial` — through the same installed-family
    /// branch a skin naming it gets — and only a system without it falls back to the proportional
    /// system font. A *declared* font keeps whatever it resolves to, monospaced fallback included.
    private func surfaceTextFont(pointSize: CGFloat) -> NSFont {
        if let identifier = surfaceFont?.identifier,
           let declared = resources.font(identifier: identifier, size: pointSize) {
            return declared
        }
        let installed = resources.font(identifier: Self.defaultSurfaceFontFamily, size: pointSize)
        if let installed, !installed.isFixedPitch { return installed }
        let system: NSFont? = .systemFont(ofSize: pointSize)
        return system ?? installed ?? NSFont.systemFont(ofSize: pointSize)
    }

    /// The face an undeclared list font resolves to, matching Winamp's own default.
    private static let defaultSurfaceFontFamily = "Arial"

    private func drawFlippedText(_ text: String, in frame: CGRect, font: NSFont, color: NSColor,
                                 alignment: NSTextAlignment, context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: frame.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.midY)
        let width = resources.textWidth(of: text, font: font)
        if width > frame.width {
            // **The row does not fit, so it keeps `NSString.draw`.** `.byTruncatingTail` is not just
            // a cut: AppKit first tightens inter-character spacing by up to
            // `tighteningFactorForTruncation` (0.05 by default) to save a character, and that drift
            // accumulates across the whole line. A `CTLine` reproduces the cut and not the
            // tightening — measured, the first dozen columns match to the byte and the rest diverge,
            // ~85% of the ink — so an over-long row would visibly re-space itself. Rare enough to be
            // worth the exactness: this is the branch a *widened* playlist column leaves behind.
            let attributes = textAttributes(font: font, color: color, alignment: alignment,
                                            lineBreakMode: .byTruncatingTail)
            (text as NSString).draw(in: frame, withAttributes: attributes)
        } else {
            // The common case, and the per-row playlist path: one cached line, drawn from the
            // alignment's own origin. `NSString.draw` scissored at the rect, so the rect becomes the
            // clip.
            context.clip(to: frame)
            let x: CGFloat
            switch alignment {
            case .right: x = frame.maxX - width
            case .center: x = frame.midX - width / 2
            default: x = frame.minX
            }
            drawCachedLine(text, font: font, color: color, x: x,
                           baseline: frame.maxY - resources.baselineOffset(of: font),
                           context: context)
        }
        context.restoreGState()
    }

    /// A skin declares a handful of faces and a handful of colours. The cap is a guard against a
    /// script driving one of them continuously, not a working limit.
    private static let maximumTextAttributes = 256

    /// Gap between the repeats of a continuously scrolling ticker, in skin pixels.
    private static let tickerGap: CGFloat = 40
    /// Ticker scroll speed, in skin pixels per second.
    private static let tickerSpeed: Double = 30

    /// Where each character sits in a bitmap-font sheet, as `(column, row)`.
    ///
    /// Winamp's sheet is three rows of glyphs. The accented row used to be appended to the second
    /// one, which put it past column 32 — outside every real sheet, so those glyphs cropped out of
    /// bounds and drew nothing.
    ///
    /// The two trailing spaces on the first row are load-bearing: they map the space character onto
    /// a blank cell of that row rather than onto the fallback, glyph (0, 0).
    ///
    /// Built once. It was built per call — a three-row `[Character]` array and the derived
    /// dictionary, per string per frame — in the path a bitmap-font skin takes for every playlist
    /// row.
    private static let bitmapGlyphPositions: [Character: (Int, Int)] = {
        let rows = [Array("abcdefghijklmnopqrstuvwxyz\"@  "),
                    Array("0123456789….:()-'!_+\\/[]^&%,=$#"),
                    Array("âöä?*")]
        var positions: [Character: (Int, Int)] = [:]
        for (row, characters) in rows.enumerated() {
            for (column, character) in characters.enumerated() { positions[character] = (column, row) }
        }
        return positions
    }()

    /// The font NullPlayer's own surfaces draw with inside this skin.
    ///
    /// A skin's list font may be a bitmap-font *sheet*, which has no `NSFont` at all — passing its id
    /// into a CoreText attribute dictionary is how the Phase 11 `drawText` crash happened. This
    /// returns the resolved resource so the caller can take the right path, never a bare id.
    private var surfaceFont: WalResourceDefinition? {
        for identifier in ["pledit.font", "wasabi.list.font", "studio.list.font"] {
            if let definition = loadedSkin.runtime.resources.resolvedDefinition(identifier: identifier),
               definition.kind == "bitmapfont" || definition.kind == "truetypefont" {
                return definition
            }
        }
        return nil
    }
}
