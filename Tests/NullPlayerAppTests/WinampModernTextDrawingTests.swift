import AppKit
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// The two facts the `drawText` CoreText conversion rests on, each established here rather than
/// reasoned about at the call site.
///
/// Both are cases of the same rule: a measurement or a placement that the drawing path is about to
/// take on faith is pinned by a test *before* the code starts depending on it. The corpus render
/// sweep is the net underneath; these are the things it would only tell you about after the fact.
final class WinampModernTextDrawingTests: XCTestCase {

    /// A `.font`-only measurement is the same width as the full attribute dictionary `drawText`
    /// draws with — so `WasabiTextMetrics.measuredWidth(of:font:)`'s memo, which is keyed on the
    /// font alone, is safe to use for the draw path's own `measured`.
    ///
    /// `TASKS.md` § B106 took the memo for the two call sites that already measured with exactly
    /// `[.font:]` and left `drawText`'s own measure out, because it passes `.foregroundColor` and a
    /// `.paragraphStyle` as well and "the paragraph style cannot change a single-line width" was
    /// believed rather than established. It is true for the reason that it *cannot* be otherwise:
    /// `NSString.size(withAttributes:)` has no bounding width to break or align inside, so neither
    /// the alignment nor the line-break mode has anything to act on. Asserted over the whole cross
    /// product the renderer can produce, because if it ever stops being true the symptom is a box
    /// sized from one number and drawn from another — B87's shape, arriving silently.
    func testParagraphStyleDoesNotChangeSingleLineWidth() {
        let strings = ["", " ", "0:00", "1:23:45", "Winamp", "MMMMMMMMMM", "lll",
                       "Artist Name - A Fairly Long Track Title (Remastered)",
                       "AV Wa To ff fi", "ÂÖÄ éàü", "日本語のテキスト", "—:—"]
        let fonts: [NSFont] = [.systemFont(ofSize: 11), .systemFont(ofSize: 8.8),
                               .boldSystemFont(ofSize: 24), .monospacedSystemFont(ofSize: 30, weight: .regular)]
        let alignments: [NSTextAlignment] = [.left, .center, .right]
        let breaks: [NSLineBreakMode] = [.byClipping, .byTruncatingTail, .byWordWrapping]

        for font in fonts {
            for string in strings {
                let fontOnly = (string as NSString).size(withAttributes: [.font: font]).width
                for alignment in alignments {
                    for lineBreak in breaks {
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.alignment = alignment
                        paragraph.lineBreakMode = lineBreak
                        let full: [NSAttributedString.Key: Any] = [
                            .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph
                        ]
                        XCTAssertEqual((string as NSString).size(withAttributes: full).width, fontOnly,
                                       accuracy: 0.0001,
                                       "\(font.fontName) \(font.pointSize) \"\(string)\" "
                                       + "align=\(alignment.rawValue) break=\(lineBreak.rawValue)")
                    }
                }
            }
        }
    }

    // MARK: - The baseline formula

    /// A cached `CTLine` drawn at `rect.maxY - baselineOffset(of:)` reproduces
    /// `NSString.draw(in:)` **pixel for pixel**, inside the local flip `drawText` already sets up.
    ///
    /// This is the one genuinely uncertain step of the conversion, and it is settled here rather
    /// than derived at the call site. Two things it establishes that reading could not:
    ///
    /// * **The local flip stays.** The scene's own transform is top-origin, so `drawText`'s flip is
    ///   what makes the space y-up — the space CoreText draws upright in. Dropping it draws every
    ///   string mirrored, and a *mirrored* "Ayg|H" has almost the same ink bounding box as an
    ///   upright one, so only a pixel comparison sees it. (Measured: ~80% of the ink differs, and
    ///   the bounding boxes agree to a pixel.)
    /// * **The offset is TextKit's, not the font's.** It is not `ascender`: at 8pt all four faces
    ///   tested want 8 while their ascenders run 6.03…7.73, and Helvetica at 17.6pt wants 18
    ///   against an ascender of 13.55. Asking the layout manager AppKit's own drawing asks is what
    ///   makes them agree, and it agrees exactly.
    func testCachedLineMatchesStringDrawing() throws {
        let metrics = try makeMetrics()
        let canvas = CGSize(width: 220, height: 110)
        // A short string and one far too long for its box: the general branch clips rather than
        // truncates, so an overflowing string must place its glyphs identically too — that is what
        // a song ticker and every B87 tab label are.
        for text in ["Ayg|H", "Artist Name - A Fairly Long Track Title (Remastered) 0123456789"] {
        for pointSize in [8.0, 11.0, 17.6, 24.0] as [CGFloat] {
            for font in faces(at: pointSize) {
                for frameHeight in [16.0, 30.0, 60.0] as [CGFloat] {
                    for inset in [0.0, 5.5, 11.0] as [CGFloat] {
                        let frame = CGRect(x: 10, y: 30, width: 190, height: frameHeight)
                        let drawFrame = frame.offsetBy(dx: 0, dy: -inset)

                        let reference = render(canvas) { context in
                            let paragraph = NSMutableParagraphStyle()
                            paragraph.alignment = .left
                            paragraph.lineBreakMode = .byClipping
                            let attributes: [NSAttributedString.Key: Any] = [
                                .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph
                            ]
                            let measured = (text as NSString).size(withAttributes: attributes).width
                            var textFrame = drawFrame
                            textFrame.size.width = max(drawFrame.width, measured)
                            self.withLocalFlip(frame, context) {
                                (text as NSString).draw(in: textFrame, withAttributes: attributes)
                            }
                        }
                        let candidate = render(canvas) { context in
                            self.withLocalFlip(frame, context) {
                                // `drawText`'s bound at `drawFrame` — the scissor the rect
                                // `NSString.draw` was handed used to provide, read inside the mirror
                                // exactly as that rect was. Vertical only: horizontally the object's
                                // box is a layout anchor and not a scissor (B87), so the ambient
                                // clip — here the whole canvas — is what bounds the string.
                                context.clip(to: CGRect(x: 0, y: drawFrame.minY,
                                                        width: canvas.width,
                                                        height: drawFrame.height))
                                context.setFillColor(NSColor.white.cgColor)
                                context.textPosition = CGPoint(
                                    x: drawFrame.minX,
                                    y: drawFrame.maxY - metrics.baselineOffset(of: font))
                                CTLineDraw(metrics.line(for: text, font: font), context)
                            }
                        }
                        assertSamePixels(candidate, reference,
                                         "\(font.fontName) \(pointSize) h=\(frameHeight) "
                                         + "inset=\(inset) \"\(text.prefix(8))\"")
                    }
                }
            }
        }
        }
    }

    /// The `drawFlippedText` half, both sides of its branch.
    ///
    /// **A row that fits** is drawn from the cached line and matches `NSString.draw` exactly.
    ///
    /// **A row that does not** keeps `NSString.draw`, and this pins the reason so it does not get
    /// "simplified" back later: `.byTruncatingTail` tightens inter-character spacing by up to
    /// `tighteningFactorForTruncation` before it cuts, and a `CTLine` — truncated or not —
    /// reproduces the cut and not the tightening. The assertion below is that the two genuinely
    /// disagree, by a lot.
    ///
    /// The corpus render sweep does **not** cover any of this: the harness has no component host,
    /// so no playlist row is ever drawn into a dump. It is proven here or it is not proven.
    func testFlippedTextCachedLineMatchesStringDrawing() throws {
        let metrics = try makeMetrics()
        let canvas = CGSize(width: 220, height: 60)
        let frame = CGRect(x: 6, y: 10, width: 120, height: 20)
        let overlong = "Artist Name - A Fairly Long Track Title (Remastered)"

        for pointSize in [8.0, 11.0, 17.6] as [CGFloat] {
            for font in faces(at: pointSize) {
                for text in ["short", "a whole row", overlong] {
                    for alignment in [NSTextAlignment.left, .center, .right] {
                        let reference = render(canvas) { context in
                            let paragraph = NSMutableParagraphStyle()
                            paragraph.alignment = alignment
                            paragraph.lineBreakMode = .byTruncatingTail
                            let attributes: [NSAttributedString.Key: Any] = [
                                .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph
                            ]
                            self.withLocalFlip(frame, context) {
                                (text as NSString).draw(in: frame, withAttributes: attributes)
                            }
                        }
                        let width = metrics.measuredWidth(of: text, font: font)
                        let candidate = render(canvas) { context in
                            self.withLocalFlip(frame, context) {
                                context.clip(to: frame)
                                let x: CGFloat
                                switch alignment {
                                case .right: x = frame.maxX - width
                                case .center: x = frame.midX - width / 2
                                default: x = frame.minX
                                }
                                context.setFillColor(NSColor.white.cgColor)
                                context.textPosition = CGPoint(
                                    x: x, y: frame.maxY - metrics.baselineOffset(of: font))
                                CTLineDraw(metrics.line(for: text, font: font), context)
                            }
                        }
                        let what = "\(font.fontName) \(pointSize) align=\(alignment.rawValue) "
                            + "\"\(text.prefix(12))\""
                        if width <= frame.width {
                            assertSamePixels(candidate, reference, what)
                        } else {
                            XCTAssertGreaterThan(inkDifference(candidate, reference), 10,
                                                 "\(what): the cached line reproduced a *truncated* "
                                                 + "draw, so the fallback in `drawFlippedText` may "
                                                 + "no longer be needed — re-measure before removing it")
                        }
                    }
                }
            }
        }
    }

    /// Total absolute difference between two alpha planes, as a percentage of the reference's ink.
    private func inkDifference(_ candidate: [UInt8], _ reference: [UInt8]) -> Double {
        var total = 0
        for index in candidate.indices {
            total += abs(Int(candidate[index]) - Int(reference[index]))
        }
        return 100 * Double(total) / Double(max(reference.reduce(0) { $0 + Int($1) }, 1))
    }

    // MARK: - Harness

    /// Compare two alpha planes and report *how* they differ, not their contents: an
    /// `XCTAssertEqual` on the arrays themselves prints two 24,000-element buffers per failure.
    private func assertSamePixels(_ candidate: [UInt8], _ reference: [UInt8], _ what: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        guard candidate.count == reference.count else {
            return XCTFail("\(what): \(candidate.count) vs \(reference.count) pixels",
                           file: file, line: line)
        }
        var differing = 0
        var worst = 0
        var total = 0
        for index in candidate.indices {
            let delta = abs(Int(candidate[index]) - Int(reference[index]))
            if delta > 0 { differing += 1 }
            worst = max(worst, delta)
            total += delta
        }
        let ink = reference.reduce(0) { $0 + Int($1) }
        let share = 100 * Double(total) / Double(max(ink, 1))
        // Not exact equality, and the gap is worth stating precisely rather than papering over.
        //
        // AppKit's string drawing and a bare `CTLineDraw` rasterize a glyph edge slightly
        // differently. Across four faces, four sizes, three box heights and three insets the
        // difference is confined to **Courier** and to **one or two pixels** per string, at a
        // partial coverage delta (≤55 of 255) and ≤0.14% of the ink. Every other face is exact.
        //
        // The tolerance is set so that anything *geometric* still fails loudly: a line one pixel out
        // of place moves the whole glyph run, which is hundreds of pixels and many percent of the
        // ink — the failures this test was written from ran 62 to 406 pixels and 10% to 117%.
        //
        // (`CGContext.setShouldSubpixelQuantizePositions` would close the remaining gap, and it is
        // not in the public CoreGraphics headers. Not worth a private symbol for one pixel of one
        // font, and the corpus render sweep is the authority on what actually changed on screen.)
        XCTAssertLessThanOrEqual(differing, 4,
                                 "\(what): \(differing) px differ, max delta \(worst), "
                                 + "\(String(format: "%.2f", share))% of ink",
                                 file: file, line: line)
        XCTAssertLessThan(share, 1.0,
                          "\(what): \(differing) px differ, max delta \(worst), "
                          + "\(String(format: "%.2f", share))% of ink",
                          file: file, line: line)
    }

    /// The faces the corpus actually reaches: the system font a skin gets with no `font=`, the
    /// monospaced fallback `WasabiTextMetrics` answers with when a named font resolves to nothing,
    /// and two installed families skins name outright.
    private func faces(at pointSize: CGFloat) -> [NSFont] {
        [.systemFont(ofSize: pointSize),
         .monospacedSystemFont(ofSize: pointSize, weight: .regular),
         NSFont(name: "Helvetica", size: pointSize) ?? .systemFont(ofSize: pointSize),
         NSFont(name: "Courier", size: pointSize) ?? .systemFont(ofSize: pointSize)]
    }

    /// `WasabiSceneRenderer.drawText`'s own local mirror, about the object's box.
    private func withLocalFlip(_ frame: CGRect, _ context: CGContext, _ body: () -> Void) {
        context.saveGState()
        context.translateBy(x: 0, y: frame.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.midY)
        body()
        context.restoreGState()
    }

    /// Render into a bitmap under the scene's top-origin transform and return its alpha plane.
    ///
    /// The global flip is not optional decoration: without it the local mirror above leaves the
    /// reference upside down, and the whole comparison silently measures the wrong thing.
    private func render(_ size: CGSize, _ body: (CGContext) -> Void) -> [UInt8] {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let previous = NSGraphicsContext.current
        // `NSString.draw` renders into the *current* `NSGraphicsContext`, not the `CGContext` it is
        // handed — without this every reference comes back blank and every assertion passes.
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        body(context)
        NSGraphicsContext.current = previous

        let pointer = context.data!.bindMemory(to: UInt8.self,
                                               capacity: context.bytesPerRow * context.height)
        var plane = [UInt8](repeating: 0, count: context.width * context.height)
        for row in 0..<context.height {
            for column in 0..<context.width {
                plane[row * context.width + column] = pointer[row * context.bytesPerRow + column * 4 + 3]
            }
        }
        return plane
    }

    private func makeMetrics() throws -> WasabiTextMetrics {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernTextDrawingTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("text.wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data("""
        <WasabiXML>
          <container id="main"><layout id="normal" w="200" h="200"/></container>
        </WasabiXML>
        """.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        let metrics = WasabiTextMetrics(loadedSkin: loaded)
        addTeardownBlock { metrics.teardown() }
        return metrics
    }
}
