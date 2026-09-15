import AppKit
import CoreGraphics
import Foundation

/// The window frame a `.wmz` skin already draws for its *own* panels, borrowed for NullPlayer's
/// windows.
///
/// **What the corpus authors.** A WMP skin has no frame system — no `<Wasabi:StandardFrame>` a
/// hosted surface can be mounted in — so for a long time the only thing a `.wmz` gave our own
/// windows was `WMPSurfacePalette`'s colours. But a skin with a styled playlist or equaliser panel
/// is not drawing a coloured rectangle: it is drawing an **eight-piece resizable ring** — four
/// corner bitmaps anchored to the corners, four edge bitmaps tiled or stretched along the sides —
/// with its real content in a stretched client subview inside. `xsn_sports` and `Halo 2` are the
/// reported pair and they are not unusual: measured over the 180-archive corpus on 2026-09-12,
/// **85 archives declare a view whose four corners are all present, and all 85 of those views also
/// declare a stretched client subview**, which is what makes the ring reusable rather than merely
/// recognisable.
///
/// **What is borrowed, and what is not.** Only the ring. The donor view's buttons, playlist, text
/// and video surface are the *skin's* window, not ours, and a NullPlayer spectrum analyser wearing
/// Halo 2's playlist buttons would be a lie about what those buttons do. So a template records the
/// ring pieces and the client panel, and the artwork it produces contains the ring alone; the
/// palette still paints the client area and NullPlayer still draws its own content and controls
/// over it.
///
/// **The insets come from the client subview, never from the artwork's thickness.** `Halo 2`'s
/// `f_left_tile.png` is 190px wide on a 406px window and is mostly transparent — the ring is a
/// decorative surround, not a border — while its `plFrame` states the content hole exactly
/// (`left="22" top="34" width="view.width-43" height="view.height-81"`). Sizing a window's content
/// from the corner bitmaps would leave 190px of dead margin on a 275px window.
///
/// The template is markup-only and cheap; the *artwork* is produced by re-building the donor view
/// through the ordinary `WMPSceneBuilder` at the hosted window's size, so every alignment, tile and
/// `JScript:` layout expression is resolved by the same code that draws the skin itself rather than
/// by a second, divergent reading of the same markup.
struct WMPHostedFrameTemplate: Equatable, Sendable {
    /// The view the ring was taken from.
    let viewID: String
    /// The ring pieces, by stable id — the only nodes whose paint commands reach our windows.
    let ringNodeIDs: Set<Int>
    /// The stretched client subview whose resolved frame is the content hole.
    let clientNodeID: Int
    /// The donor view's own declared floor. A window smaller than this cannot be built at its own
    /// size, because `WMPResizeLimits.clamp` is what every other consumer of this view obeys.
    let minimumSize: CGSize

    // MARK: - Derivation

    /// The eight places a ring piece can be anchored. A piece is classified by its *alignment*
    /// alone: that is the property the skin uses to keep the ring together while the window resizes,
    /// and it is readable without resolving a single expression.
    private enum Role: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        init?(horizontal: WMPAxisAlignment, vertical: WMPAxisAlignment) {
            switch (horizontal, vertical) {
            case (.leading, .leading): self = .topLeft
            case (.stretch, .leading): self = .top
            case (.trailing, .leading): self = .topRight
            case (.leading, .stretch): self = .left
            case (.trailing, .stretch): self = .right
            case (.leading, .trailing): self = .bottomLeft
            case (.stretch, .trailing): self = .bottom
            case (.trailing, .trailing): self = .bottomRight
            default: return nil
            }
        }

        static let corners: Set<Role> = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    /// Pick the best ring in the skin, or answer nil when it has none.
    ///
    /// `playerViewID` is the view the app is presenting as the player. It is ranked last rather than
    /// excluded: the player's own body is what the user is already looking at, so wearing it on a
    /// spectrum window is the least interesting answer — but a skin whose *only* ring is there
    /// (`NVIDIA`, `WALL-E`) still has one, and one is better than none.
    static func derive(from skin: WMPLoadedSkin, playerViewID: String?) -> WMPHostedFrameTemplate? {
        var best: (template: WMPHostedFrameTemplate, score: Int)?
        for registration in skin.views {
            guard let candidate = template(for: registration) else { continue }
            // The ring's completeness is the score: an eight-piece ring resizes cleanly in both
            // axes, a four-corner one has gaps the skin filled some other way.
            var score = candidate.ringNodeIDs.count
            // A panel that holds something — a playlist, a visualiser, a video surface — is the
            // window this skin means by "one of my windows". Several skins wrap the *same* ring
            // around an `upgradeView`, the nag panel a 2002 skin shows a player too old to run it,
            // and picking that one is picking the copy nothing was ever meant to look at.
            if hostsContent(registration.node) { score += 4 }
            if let playerViewID, registration.id.caseInsensitiveCompare(playerViewID) == .orderedSame {
                score -= 100
            }
            if best == nil || score > best!.score { best = (candidate, score) }
        }
        return best?.template
    }

    private static func template(for registration: WMPViewRegistration) -> WMPHostedFrameTemplate? {
        let view = registration.node
        var ring: [Role: WMPNode] = [:]
        var client: WMPNode?

        // Direct children only. A ring is laid out against the *window*, so its pieces are the
        // window's own children; a nested panel that happens to stretch is part of the skin's
        // content, not of its frame.
        for child in view.children where child.kind == .subview {
            let horizontal = WMPAxisAlignment(horizontal: literal(child, "horizontalAlignment"))
            let vertical = WMPAxisAlignment(vertical: literal(child, "verticalAlignment"))
            if hasBackgroundImage(child) {
                guard let role = Role(horizontal: horizontal, vertical: vertical) else { continue }
                // First declaration wins, matching the duplicate-id rule elsewhere in the engine:
                // a skin that layers two bitmaps in one corner authored the lower one first.
                if ring[role] == nil { ring[role] = child }
            } else if horizontal == .stretch, vertical == .stretch, client == nil {
                client = child
            }
        }

        guard Role.corners.isSubset(of: Set(ring.keys)), let client else { return nil }
        return WMPHostedFrameTemplate(
            viewID: registration.id,
            ringNodeIDs: Set(ring.values.map(\.stableID)),
            clientNodeID: client.stableID,
            minimumSize: CGSize(width: number(view, "minWidth") ?? number(view, "width") ?? 0,
                                height: number(view, "minHeight") ?? number(view, "height") ?? 0)
        )
    }

    /// Whether a view carries one of the surfaces a WMP panel exists to hold.
    private static func hostsContent(_ node: WMPNode) -> Bool {
        for child in node.children {
            switch child.kind {
            case .playlist, .dropdownPlaylist, .video, .wmpVideo, .effects, .listBox,
                 .equalizerSettings:
                return true
            default:
                if hostsContent(child) { return true }
            }
        }
        return false
    }

    private static func hasBackgroundImage(_ node: WMPNode) -> Bool {
        for name in ["backgroundImage", "background"] {
            guard let attribute = node.attribute(named: name) else { continue }
            if case .resource = attribute.value { return true }
        }
        return false
    }

    private static func literal(_ node: WMPNode, _ name: String) -> String? {
        node.attribute(named: name)?.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ node: WMPNode, _ name: String) -> CGFloat? {
        WMPNumber.literal(node.attribute(named: name))
    }

    // MARK: - Producing artwork

    /// Render the ring for a window of `size` points.
    ///
    /// The donor view is built at the window's own size wherever its declared floor allows it, so
    /// the pieces land where the skin's alignment rules put them. Below that floor the frame is
    /// built at the floor and **scaled to fit**: the ring is the skin's, and a skin that says its
    /// panel is never narrower than 406px has not been asked what 275px looks like. The alternative
    /// — forcing every hosted window up to the donor's minimum — moves windows the user placed.
    func artwork(builder: WMPSceneBuilder, renderer: WMPRenderer, size: CGSize,
                 backingScale: CGFloat) async throws -> SkinnedSurfaceFrameArtwork? {
        guard size.width > 0, size.height > 0 else { return nil }
        let scene = try await builder.build(viewID: viewID,
                                            requestedSize: WMPSize(width: size.width, height: size.height))
        guard let client = scene.geometries[clientNodeID]?.absoluteFrame, !client.isEmpty else {
            return nil
        }
        let ring = scene.commands.filter { ringNodeIDs.contains($0.stableID) }
        guard !ring.isEmpty else { return nil }

        let canvas = scene.canvasSize
        let ringOnly = WMPScene(viewID: scene.viewID, canvasSize: canvas,
                                resizeLimits: scene.resizeLimits, isResizable: scene.isResizable,
                                commands: ring, hits: [], widgets: [], geometries: [:],
                                unresolved: [], diagnostics: [], dirtyBounds: nil,
                                metrics: scene.metrics, wasBuiltOnMainThread: false)
        let rendered = try await renderer.render(scene: ringOnly, backingScale: backingScale)

        // The scene may have been clamped up to the donor's floor; map it back onto the window.
        let scaleX = canvas.width > 0 ? size.width / canvas.width : 1
        let scaleY = canvas.height > 0 ? size.height / canvas.height : 1
        let content = CGRect(x: client.x * scaleX, y: client.y * scaleY,
                             width: client.width * scaleX, height: client.height * scaleY)
        return SkinnedSurfaceFrameArtwork(
            image: rendered.image, size: size, contentRect: content,
            captionStrip: Self.titleStrip(in: rendered.image, captionHeight: content.minY, size: size),
            wasScaledToFit: abs(scaleX - 1) > 0.001 || abs(scaleY - 1) > 0.001)
    }

    /// Where the skin's own title strip sits inside the band above the client hole.
    ///
    /// **The band is not the strip.** `Half-Life_2` leaves 46px there and paints an orange bar
    /// across part of it; the rest is the frame's dark inner shadow, and our title and close control
    /// centred in the 46 land below the bar a user reads as the title bar (reported 2026-09-15).
    /// **Nothing in the markup says where the bar ends** — the ring pieces are decorative and
    /// overlap the client area (Half-Life's top edge node is 77px tall on a 46px band,
    /// `Combat_Flight_Simulator_3`'s is 120 on 37) — so the answer is in the pixels the ring just
    /// drew.
    ///
    /// **The bar is the lit run, not a step in the tone.** Row-to-row continuity was the first rule
    /// and it answers "the whole band" for every skin that bevels or gradients its frame, which is
    /// most of them: Half-Life's own rows walk from 0.19 to 0.64 and back with no step wider than
    /// the threshold. So the run is taken around the *brightest* row instead, out to where the tone
    /// falls halfway to the band's darkest — which is the bar, and nothing else in this corpus.
    /// A band with little contrast in it is one flat caption and answers nil, which is what every
    /// ring did before this existed.
    private static func titleStrip(in image: CGImage, captionHeight: CGFloat,
                                   size: CGSize) -> SkinnedSurfaceFrameArtwork.CaptionStrip? {
        guard captionHeight >= 12, size.height > 0 else { return nil }
        let scale = CGFloat(image.height) / size.height
        let rows = min(Int((captionHeight * scale).rounded()), 160)
        guard rows >= 12, image.width > 8 else { return nil }
        let crop = CGRect(x: CGFloat(image.width) * 0.2, y: 0,
                          width: CGFloat(image.width) * 0.6, height: CGFloat(rows)).integral
        guard let band = image.cropping(to: crop) else { return nil }

        let columns = 8
        var pixels = [UInt8](repeating: 0, count: columns * rows * 4)
        let profile: [CGFloat?] = pixels.withUnsafeMutableBytes { buffer -> [CGFloat?] in
            guard let context = CGContext(data: buffer.baseAddress, width: columns, height: rows,
                                          bitsPerComponent: 8, bytesPerRow: columns * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return [] }
            context.interpolationQuality = .medium
            context.draw(band, in: CGRect(x: 0, y: 0, width: columns, height: rows))
            // A bitmap context's backing store is top-down: row 0 of the data is the top row of the
            // image drawn into it, which is the top of the caption band.
            return (0..<rows).map { row -> CGFloat? in
                var total: CGFloat = 0
                var covered = 0
                for column in 0..<columns {
                    let offset = (row * columns + column) * 4
                    let alpha = CGFloat(buffer[offset + 3]) / 255
                    guard alpha >= 0.5 else { continue }
                    let color = NSColor(deviceRed: min(1, CGFloat(buffer[offset]) / 255 / alpha),
                                        green: min(1, CGFloat(buffer[offset + 1]) / 255 / alpha),
                                        blue: min(1, CGFloat(buffer[offset + 2]) / 255 / alpha),
                                        alpha: 1)
                    total += SkinnedSurfaceStyle.relativeLuminance(color)
                    covered += 1
                }
                guard covered * 2 >= columns else { return nil }
                return total / CGFloat(covered)
            }
        }

        if ProcessInfo.processInfo.environment["WMP_STRIP_TRACE"] != nil {
            print("STRIP-TRACE profile=" + profile.map { $0.map { String(format: "%.2f", $0) } ?? "-" }
                .joined(separator: ","))
        }

        // **Smoothed first, and the widest run rather than the brightest.** A specular highlight is
        // one pixel tall and outshines the bar it sits under: on `Half-Life_2` at 2x the peak row is
        // a rivet below the caption, and a run grown from it is 2px wide and answers nothing. At 1x
        // the same highlight averages away, which is how a rule measured only in the harness passed
        // and the app drew the old layout (2026-09-15).
        let window = max(1, Int((scale * 3).rounded()))
        let smoothed: [CGFloat?] = (0..<rows).map { row in
            let span = max(0, row - window)...min(rows - 1, row + window)
            let values = span.compactMap { profile[$0] }
            guard values.count * 2 >= span.count else { return nil }
            return values.reduce(0, +) / CGFloat(values.count)
        }
        let lit = smoothed.compactMap { $0 }
        guard lit.count >= 12, let brightest = lit.max(), let darkest = lit.min(),
              brightest - darkest >= 0.2 else { return nil }
        // A third of the way up from the band's darkest, not halfway: a bar is lit at its centre
        // and falls off towards its edges, so a midpoint threshold keeps the core and drops the
        // shoulders — `Half-Life_2`'s orange runs 0-29px and a midpoint cut calls it 3.5-19, which
        // centres our controls in the top half of what a user sees. Compared at 0.5/0.35/0.25
        // against the rendered captions of five skins on 2026-09-15.
        let threshold = darkest + (brightest - darkest) * 0.35

        var best: ClosedRange<Int>?
        var start: Int?
        for row in 0...rows {
            let above = row < rows && (smoothed[row] ?? 0) >= threshold
            if above, start == nil { start = row }
            if !above, let first = start {
                let run = first...(row - 1)
                if best == nil || run.count > best!.count { best = run }
                start = nil
            }
        }
        guard let best else { return nil }

        let top = CGFloat(best.lowerBound) / scale
        let height = CGFloat(best.count) / scale
        guard height >= SkinnedSurfaceStyle.classicCharHeight + 2, height < captionHeight else {
            return nil
        }
        return SkinnedSurfaceFrameArtwork.CaptionStrip(top: top, height: height)
    }
}
