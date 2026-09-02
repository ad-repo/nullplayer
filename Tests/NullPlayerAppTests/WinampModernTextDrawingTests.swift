import AppKit
import XCTest
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
}
