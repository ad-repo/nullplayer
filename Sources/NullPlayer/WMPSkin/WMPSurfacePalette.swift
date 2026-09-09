import AppKit

/// The colours NullPlayer's *own* windows are painted in while a `.wmz` skin is on screen.
///
/// A `.wmz` has no frame system to borrow — no `<Wasabi:StandardFrame>` a playlist can be mounted
/// in — so a NullPlayer window beside a WMP skin is app-authored chrome that has to be *coloured*
/// like the skin instead. This is the derivation, and it is declaration-first because a skin that
/// states a colour has told us what it wants:
///
/// 1. **The skin's own `PLAYLIST` element.** It declares exactly the roles a list needs —
///    `backgroundColor`, `foregroundColor`, `itemPlayingColor`, `itemPlayingBackgroundColor` — so a
///    skin with one hands us a complete palette for our playlist and library. Measured over the
///    180-archive corpus on 2026-09-09: 73 skins declare the background, 74 the foreground, 47 the
///    playing colour and 40 the playing background.
/// 2. **`VIEW` / `SUBVIEW` `backgroundColor` and `TEXT` `foregroundColor`.** The window's ground and
///    its lettering: 93 skins declare a `VIEW` background, 72 a `SUBVIEW` one, and `TEXT`
///    `foregroundColor` is the single most authored colour in the corpus outside the transparency
///    keys (760 uses).
/// 3. **The artwork itself** (`sampledBackground`). Coverage is why this step exists rather than
///    being a nicety: **only 96 of the 180 archives declare any background colour at all and 95 any
///    foreground**, so declarations alone leave nearly half the corpus with no palette. What the
///    skin *draws* is the next most honest source, so the presented view's rendered bitmap is
///    sampled for its dominant opaque colour.
/// 4. **An app-authored WMP-neutral fallback.** Never another skin family's colours, per
///    `wmp-skin-guide` § *Phase 3 app integration contracts*: the same near-black and white
///    `WMPUnskinnedMainView` draws itself in.
///
/// Values are `WMPColor`, not `NSColor`, so the whole derivation runs off the main thread with the
/// rest of the loader; `surfaceStyle` is the only part that touches AppKit.
struct WMPSurfacePalette: Equatable, Sendable {
    /// The view this palette was derived for. A skin's playlist view and its player usually declare
    /// different colours, and the palette follows whichever view is presented.
    let viewID: String

    var background: WMPColor?
    var text: WMPColor?
    var playingText: WMPColor?
    var playingBackground: WMPColor?
    var disabledText: WMPColor?

    /// The dominant opaque colour of what the skin actually drew, filled in by the controller once
    /// the view has been rendered. Only ever consulted when `background` is nil.
    var sampledBackground: WMPColor?

    /// The app-authored WMP-neutral ground and lettering — `WMPUnskinnedMainView`'s own near-black
    /// and white. Nothing here is taken from a `.wsz`, a `.wal`, or `skin.json`.
    static let neutralBackground = WMPColor(red: 23, green: 23, blue: 23)
    static let neutralText = WMPColor(red: 255, green: 255, blue: 255)

    // MARK: - Derivation from markup

    /// Walks the presented view for declared colours, then the rest of the document for the roles it
    /// left unset.
    ///
    /// The second pass is what makes a skin like a stock WMP template usable: its `mainView` declares
    /// nothing while its playlist view declares a full list palette, and a palette taken from the
    /// presented view alone would throw that away.
    init(skin: WMPLoadedSkin, viewID: String) {
        self.viewID = viewID
        if let view = skin.views.first(where: { $0.id.caseInsensitiveCompare(viewID) == .orderedSame }) {
            absorb(node: view.node)
        }
        guard !isComplete else { return }
        for view in skin.views where view.id.caseInsensitiveCompare(viewID) != .orderedSame {
            absorb(node: view.node)
            if isComplete { return }
        }
    }

    init(viewID: String) { self.viewID = viewID }

    private var isComplete: Bool {
        background != nil && text != nil && playingText != nil && playingBackground != nil
    }

    /// Document order is the priority: a `VIEW`'s own background outranks a `SUBVIEW`'s, and an outer
    /// subview outranks the panel nested inside it, which is the same order the skin paints in.
    private mutating func absorb(node: WMPNode) {
        let isPlaylist = node.kind == .playlist || node.authoredTagName.caseInsensitiveCompare("PLAYLIST") == .orderedSame

        if let color = color(of: node, named: "backgroundColor") {
            // A `PLAYLIST`'s own background is the one role a `.wmz` states about a *list*, so it
            // outranks a view or subview ground that was chosen for artwork to sit on.
            if isPlaylist { background = color } else if background == nil { background = color }
        }
        if let color = color(of: node, named: "foregroundColor") {
            if isPlaylist { text = color } else if text == nil { text = color }
        }
        if playingText == nil { playingText = color(of: node, named: "itemPlayingColor") }
        if playingBackground == nil { playingBackground = color(of: node, named: "itemPlayingBackgroundColor") }
        if disabledText == nil { disabledText = color(of: node, named: "disabledItemColor") }

        for child in node.children { absorb(node: child) }
    }

    /// `itemPlayingColor` and its peers are not in `WMPAttributeParser`'s colour set — they parse as
    /// literals — so the raw value is read here rather than only the classified one. Both paths use
    /// the same strict `#RRGGBB` parse the rest of the engine does; a value the engine would reject
    /// (`FF00FF` with no `#`) is rejected here too rather than being special-cased into a palette.
    private func color(of node: WMPNode, named name: String) -> WMPColor? {
        guard let attribute = node.attribute(named: name) else { return nil }
        if case .color(let color) = attribute.value { return color }
        return WMPAttributeParser.color(from: attribute.rawValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Sampling what the skin drew

    /// The dominant opaque colour of a rendered view.
    ///
    /// Scaled into a small box first, so this costs the same on a 1024px skin as on a 200px one, and
    /// bucketed rather than averaged: averaging a player made of dark chrome and one bright display
    /// returns a grey that appears nowhere in the skin. Fully transparent pixels are skipped — a
    /// `.wmz` window is genuinely shaped, and counting the cut-out would return the shape, not the
    /// artwork.
    static func dominantColor(of image: CGImage) -> WMPColor? {
        let side = 32
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * side)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = pixels.withUnsafeMutableBytes({ bytes in
            CGContext(data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: bitmapInfo)
        }) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        // 4 bits per channel: coarse enough that a gradient counts as one colour, fine enough that
        // two different panels do not.
        var counts = [Int](repeating: 0, count: 4096)
        var sums = [(r: Int, g: Int, b: Int)](repeating: (0, 0, 0), count: 4096)
        for index in 0..<(side * side) {
            let offset = index * 4
            let alpha = Int(bytes[offset + 3])
            guard alpha > 127 else { continue }
            // Un-premultiply so a half-transparent black edge is not counted as black.
            let red = Int(bytes[offset]) * 255 / alpha
            let green = Int(bytes[offset + 1]) * 255 / alpha
            let blue = Int(bytes[offset + 2]) * 255 / alpha
            let bucket = (min(red, 255) >> 4) << 8 | (min(green, 255) >> 4) << 4 | (min(blue, 255) >> 4)
            counts[bucket] += 1
            sums[bucket] = (sums[bucket].r + min(red, 255),
                            sums[bucket].g + min(green, 255),
                            sums[bucket].b + min(blue, 255))
        }
        guard let bucket = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[bucket] > 0 else {
            return nil
        }
        let count = counts[bucket]
        return WMPColor(red: UInt8(sums[bucket].r / count),
                        green: UInt8(sums[bucket].g / count),
                        blue: UInt8(sums[bucket].b / count))
    }

    // MARK: - The style NullPlayer's windows are drawn from

    /// Widens whatever the skin gave us into the seven roles every hosted NullPlayer surface needs.
    ///
    /// Each missing role is *derived from the ones that are present* rather than invented, the same
    /// rule `SkinnedSurfaceStyle` applies to its blends: a skin that declared only a background gets
    /// lettering that can be read on it, and a skin that declared only lettering gets a ground that
    /// can carry it.
    ///
    /// **And every foreground is put through the same legibility guard `.wal` uses**
    /// (`SkinnedSurfaceStyle.legible`, WCAG's large-text 3.0:1 bar). It is needed here for a reason
    /// `.wal` does not have: a `.wms` declares its colours per *element*, so the ground can come from
    /// a `VIEW` and the lettering from a `PLAYLIST` three levels down that was never drawn on it —
    /// and where nothing is declared at all the ground is *sampled from artwork*, which no author ever
    /// chose a text colour against. Both cases produce pairings the skin never actually shows. The
    /// guard tries the skin's own colours first, in intent order, so a legible declaration is always
    /// kept; only a pairing that cannot be read falls through to black or white.
    var surfaceStyle: SkinnedSurfaceStyle {
        let ground = (background ?? sampledBackground ?? Self.neutralBackground).nsColor
        // The skin's own foregrounds, best-intent first, are the candidates for every text role — so
        // a `PLAYLIST` that names an unreadable colour is answered with another colour *the same skin
        // named* wherever one can be read, and with black or white only when none can.
        let declaredForegrounds = [text, playingText, disabledText].compactMap { $0?.nsColor }
        let lettering = SkinnedSurfaceStyle.legible(preferring: declaredForegrounds, on: ground)
        // A skin that names no playing highlight gets one a step off its own ground, in the
        // direction of its own lettering — never a fixed blue.
        let highlight = playingBackground?.nsColor
            ?? SkinnedSurfaceStyle.blend(ground, toward: lettering, by: 0.35)
        // Each foreground is guarded against the ground it is *actually drawn on*, which is not the
        // same ground for all of them: the playing row's text sits on the window background until the
        // row is also selected, while the selection's text sits on the highlight. Guarding both
        // against one background is what leaves a playlist with an unreadable current track.
        let playingCandidates = [playingText, text].compactMap { $0?.nsColor } + [lettering]
        let playing = SkinnedSurfaceStyle.legible(preferring: playingCandidates, on: ground)
        let highlightText = SkinnedSurfaceStyle.legible(preferring: playingCandidates, on: highlight)
        return SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
            background: ground,
            text: lettering,
            currentText: playing,
            selectionBackground: highlight,
            selectionText: highlightText,
            treeText: lettering,
            treeSelection: highlight
        ))
    }
}

extension WMPColor {
    var nsColor: NSColor {
        NSColor(deviceRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: 1)
    }
}
