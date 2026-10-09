import AppKit
import XCTest
@testable import NullPlayer

/// The palette NullPlayer's windows wear beside a face (A7): what it samples, and the goldens that
/// pin it for a handful of corpus faces.
final class AudionFacePhase5Tests: XCTestCase {
    // MARK: - Sampling

    /// 85 corpus faces author a 1×1 box at 0,0 for "no display": its colour is a default and the
    /// pixel under it a corner, so the ground is the face's body instead.
    func testAPlaceholderDisplayLendsNoColour() async throws {
        let fixture = try AudionFaceFixture(json: [
            "albumDisplayRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1), "albumTextMode": 1,
            "albumDisplayTextFaceColorFromFace": ["red": 0, "green": 0, "blue": 0],
        ])
        let white: [UInt8] = [255, 255, 255, 255], black: [UInt8] = [0, 0, 0, 255]
        let rgba = Array(([black] + [[UInt8]](repeating: white, count: 15)).joined())
        try fixture.write("base.png", WMPSkinTestSupport.encodedImage(width: 4, height: 4, rgba: rgba))

        let face = try await fixture.load()
        XCTAssertNil(AudionFacePalette.displayed(face.album))
        XCTAssertEqual(rgb(AudionFacePalette.surfaceStyle(for: face).background), [255, 255, 255])
    }

    /// The face as drawn: pixels `base-alpha.png` cuts away are not sampled.
    func testTheMaskCutsTheSampledFace() async throws {
        let fixture = try AudionFaceFixture()
        let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
        let clear: [UInt8] = [0, 0, 0, 0], opaque: [UInt8] = [0, 0, 0, 255]
        // Three red columns and one blue; the mask keeps only the blue one.
        let row = { (a: [UInt8], b: [UInt8]) in [a, a, a, b] }
        try fixture.write("base.png", WMPSkinTestSupport.encodedImage(
            width: 4, height: 4, rgba: Array([[[UInt8]]](repeating: row(red, blue), count: 4).joined().joined())))
        try fixture.write("base-alpha.png", WMPSkinTestSupport.encodedImage(
            width: 4, height: 4, rgba: Array([[[UInt8]]](repeating: row(clear, opaque), count: 4).joined().joined())))

        let face = try await fixture.load()
        XCTAssertEqual(rgb(AudionFacePalette.surfaceStyle(for: face).background), [0, 0, 255])
    }

    /// A face whose authored text is its ground's colour still gets a selection that stands off it:
    /// the blend goes toward a colour that can be read there, not toward the authored one.
    func testSelectionStandsOffAGroundItsAuthoredTextMatches() async throws {
        let fixture = try AudionFaceFixture(json: [
            "albumDisplayRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 4, right: 4), "albumTextMode": 1,
            "albumDisplayTextFaceColorFromFace": ["red": 0, "green": 0, "blue": 0],
        ])
        try fixture.png("base.png", width: 4, height: 4, fill: [0, 0, 0, 255])

        let style = AudionFacePalette.surfaceStyle(for: try await fixture.load())
        XCTAssertGreaterThanOrEqual(SkinnedSurfaceStyle.contrastRatio(style.selectionBackground, style.background), 1.3)
        XCTAssertGreaterThanOrEqual(SkinnedSurfaceStyle.contrastRatio(style.selectedText, style.selectionBackground),
                                    SkinnedSurfaceStyle.minimumContrast)
    }

    // MARK: - Goldens

    /// `Goldens/AudionFace/palettes.tsv`: the harness's `PALETTE` line for a handful of installed corpus
    /// faces, chosen for what they stress (see the file). Skips without the corpus, which this
    /// repository does not ship. After an intended palette change, re-record and read the diff:
    ///
    /// ```sh
    /// AUDION_PALETTE_GOLDEN_UPDATE=1 swift test --build-system native --filter AudionFacePhase5Tests/testPaletteGoldens
    /// ```
    func testPaletteGoldens() async throws {
        let root = try AudionFaceCorpusLoadTests.installedFaces()[0].deletingLastPathComponent()
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Goldens/AudionFace/palettes.tsv")
        let text = try String(contentsOf: url, encoding: .utf8)
        let header = text.split(separator: "\n").filter { $0.hasPrefix("#") }
        let golden = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
            .map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }

        var actual: [[String]] = []
        for row in golden {
            let folder = root.appendingPathComponent(row[0], isDirectory: true)
            guard FileManager.default.fileExists(atPath: folder.path) else { throw XCTSkip("\(row[0]) is not installed") }
            actual.append([row[0], AudionFaceHarness.paletteLine(try await AudionFaceLoader.load(folder: folder))])
        }
        if ProcessInfo.processInfo.environment["AUDION_PALETTE_GOLDEN_UPDATE"] != nil {
            let lines = header.map(String.init) + actual.map { $0.joined(separator: "\t") }
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            return
        }
        for (expected, got) in zip(golden, actual) {
            XCTAssertEqual(got[1], expected[1], expected[0])
        }
    }

    private func rgb(_ color: NSColor) -> [Int] {
        let c = color.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
    }
}
