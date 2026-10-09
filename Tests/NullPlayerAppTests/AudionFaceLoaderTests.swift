import XCTest
@testable import NullPlayer

/// A face folder synthesized in the test that uses it; no Panic artwork is ever committed.
struct AudionFaceFixture {
    let folder: URL

    init(name: String = "Fixture Face", json: [String: Any] = [:]) throws {
        folder = try WMPSkinTestSupport.temporaryDirectory().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write("index.json", JSONSerialization.data(withJSONObject: json))
        try png("base.png", width: 4, height: 4)
    }

    func write(_ name: String, _ data: Data) throws {
        try data.write(to: folder.appendingPathComponent(name))
    }

    func png(_ name: String, width: Int = 1, height: Int = 1) throws {
        let rgba = [UInt8](repeating: 255, count: width * height * 4)
        try write(name, WMPSkinTestSupport.encodedImage(width: width, height: height, rgba: rgba))
    }

    /// Frames `first..<first + count`, each a real 1×1 PNG.
    func picts(_ first: Int, count: Int) throws {
        for id in first..<(first + count) { try png("\(id).png") }
    }

    /// A PNG signature and IHDR claiming `width`×`height`, with no image data behind it: the
    /// limits are checked from headers, so this reaches them without building a huge image.
    func pngHeader(_ name: String, width: Int, height: Int) throws {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
        for value in [width, height] { bytes += (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) } }
        try write(name, Data(bytes + [8, 6, 0, 0, 0, 0, 0, 0, 0]))
    }

    func load() async throws -> AudionFace {
        try await AudionFaceLoader.load(folder: folder)
    }

    static func rect(top: Int, left: Int, bottom: Int, right: Int) -> [String: Int] {
        ["top": top, "left": left, "bottom": bottom, "right": right]
    }

    /// The fatal code `body` throws, or nil when it succeeds. Any other error is rethrown, so it can
    /// never read as success.
    static func failure(_ body: () async throws -> Any) async throws -> AudionFaceDiagnosticCode? {
        do { _ = try await body(); return nil } catch let finding as AudionFaceFinding { return finding.code }
    }
}

final class AudionFaceLoaderTests: XCTestCase {
    func testAnEmptyIndexLoadsABareFace() async throws {
        let face = try await AudionFaceFixture().load()
        XCTAssertEqual(face.base.width, 4)
        XCTAssertNil(face.mask)
        XCTAssertTrue(face.buttons.isEmpty && face.indicators.isEmpty && face.digits.isEmpty && face.animations.isEmpty)
        XCTAssertNil(face.artist)
        XCTAssertEqual(face.findings, [])
    }

    func testEveryElementResolvesAsFaceKitReadsIt() async throws {
        let fixture = try AudionFaceFixture(json: [
            "playButtonRect": rect(2, 3, 99, 99),
            "netIndicatorRect": rect(1, 1, 3, 4),
            "timeDigit1Rect": rect(0, 0, 2, 2), "timeDigit1FirstPICTID": 100,
            "trackDigit1Rect": rect(0, 2, 2, 4), "trackDigit1FirstPICTID": 200,
            "connectingAnimRect": rect(0, 0, 4, 4), "connectingFirstPICTID": 300,
            "connectingNumPICTs": 3, "connectingFrameDelay": 5,
            "faceInfo": ["by someone"],
        ])
        try fixture.png("play.png", width: 3, height: 2)
        for state in ["-active", "-disabled", "-hover"] { try fixture.png("play\(state).png", width: 3, height: 2) }
        try fixture.png("net.png")
        try fixture.png("net-on.png")
        try fixture.picts(100, count: 10)
        try fixture.picts(200, count: 11)
        try fixture.picts(300, count: 3)
        try fixture.png("base-alpha.png", width: 4, height: 4)

        let face = try await fixture.load()
        let play = try XCTUnwrap(face.buttons[.play])
        XCTAssertEqual(play.rect, AudionFaceRect(x: 3, y: 2, width: 3, height: 2), "origin from JSON, size from sprite")
        XCTAssertNotNil(play.pressedImage)
        XCTAssertNotNil(play.disabledImage)
        XCTAssertNotNil(play.hoverImage)
        XCTAssertEqual(face.indicators[.net]?.rect, AudionFaceRect(x: 1, y: 1, width: 3, height: 2))
        XCTAssertEqual(face.digits[.timeDigit1]?.images.count, 10)
        XCTAssertEqual(face.digits[.trackDigit1]?.images.count, 11)
        XCTAssertEqual(face.animations[.connecting]?.frames.count, 3)
        XCTAssertEqual(face.animations[.connecting]?.frameDelay, 5)
        XCTAssertNotNil(face.mask)
        XCTAssertEqual(face.faceInfo, ["by someone"])
        XCTAssertEqual(face.findings, [])
    }

    func testZeroRectsAreAbsentButAButtonTakesItsSizeFromTheSprite() async throws {
        let fixture = try AudionFaceFixture(json: [
            "netIndicatorRect": rect(0, 0, 0, 0),
            "stopButtonRect": rect(1, 2, 1, 2),
        ])
        try fixture.png("net.png")
        try fixture.png("net-on.png")
        try fixture.png("stop.png", width: 2, height: 2)
        let face = try await fixture.load()
        XCTAssertNil(face.indicators[.net])
        // FaceKit reads only top and left for a button, so a zero rect with a sprite still draws.
        XCTAssertEqual(face.buttons[.stop]?.rect, AudionFaceRect(x: 2, y: 1, width: 2, height: 2))
        XCTAssertEqual(face.findings, [])
    }

    func testMissingPauseAndStateSpritesAreNotFindings() async throws {
        let fixture = try AudionFaceFixture(json: ["playButtonRect": rect(0, 0, 2, 2)])
        try fixture.png("play.png")
        let face = try await fixture.load()
        XCTAssertNotNil(face.buttons[.play])
        XCTAssertNil(face.buttons[.pause])
        XCTAssertNil(face.buttons[.play]?.hoverImage)
        XCTAssertEqual(face.findings, [])
    }

    func testAButtonRectWithoutASpriteIsDroppedWithAUD0009() async throws {
        let face = try await AudionFaceFixture(json: ["closeButtonRect": rect(0, 0, 2, 2)]).load()
        XCTAssertNil(face.buttons[.close])
        XCTAssertEqual(face.findings.map(\.code), [.buttonWithoutSprite])
    }

    func testTrackDigitsNeedElevenFramesAndTimeDigitsTen() async throws {
        let fixture = try AudionFaceFixture(json: [
            "timeDigit1Rect": rect(0, 0, 2, 2), "timeDigit1FirstPICTID": 100,
            "trackDigit1Rect": rect(0, 2, 2, 4), "trackDigit1FirstPICTID": 100,
        ])
        try fixture.picts(100, count: 10)
        let face = try await fixture.load()
        XCTAssertEqual(face.digits[.timeDigit1]?.images.count, 10)
        XCTAssertNil(face.digits[.trackDigit1], "the blank eleventh frame, 110.png, is missing")
        XCTAssertEqual(face.findings.map(\.code), [.elementDropped])
    }

    func testAnAnimationMissingAFrameIsDroppedWhole() async throws {
        let fixture = try AudionFaceFixture(json: [
            "streamingAnimRect": rect(0, 0, 4, 4), "streamingFirstPICTID": 300,
            "streamingNumPICTs": 4, "streamingFrameDelay": 1,
        ])
        try fixture.picts(300, count: 3)
        let face = try await fixture.load()
        XCTAssertNil(face.animations[.streaming])
        XCTAssertEqual(face.findings.map(\.code), [.elementDropped])
    }

    func testAMaskOfAnotherSizeIsKeptWithAUD0008() async throws {
        let fixture = try AudionFaceFixture()
        try fixture.png("base-alpha.png", width: 3, height: 5)
        let face = try await fixture.load()
        XCTAssertEqual(face.mask?.width, 3)
        XCTAssertEqual(face.findings.map(\.code), [.maskSizeMismatch])
    }

    func testWhitespaceAndSymbolsInTheFolderName() async throws {
        let face = try await AudionFaceFixture(name: " Escher∆ Face™ ").load()
        XCTAssertEqual(face.base.height, 4)
    }

    func testSpriteNamesMatchCaseInsensitively() async throws {
        let fixture = try AudionFaceFixture(json: ["playButtonRect": rect(0, 0, 1, 1)])
        try fixture.png("Play.PNG")
        let face = try await fixture.load()
        XCTAssertNotNil(face.buttons[.play])
    }

    func testAMalformedKeyDropsOnlyItsElement() async throws {
        let fixture = try AudionFaceFixture(json: [
            "playButtonRect": "not a rect",
            "stopButtonRect": rect(0, 0, 1, 1),
            "netIndicatorRect": rect(4, 4, 2, 2),                    // negative: a listed departure
            "timeDigit1Rect": rect(0, 0, 2, 2),                      // no FirstPICTID: FaceKit throws
            "artistDisplayRect": rect(0, 0, 2, 4),                   // no TextMode: FaceKit throws
        ])
        try fixture.png("play.png")
        try fixture.png("stop.png")
        try fixture.png("net.png")
        try fixture.png("net-on.png")
        let face = try await fixture.load()
        XCTAssertNil(face.buttons[.play])
        XCTAssertNotNil(face.buttons[.stop])
        XCTAssertNil(face.indicators[.net])
        XCTAssertNil(face.digits[.timeDigit1])
        XCTAssertNil(face.artist)
        // Five: pause shares playButtonRect, so that one key drops two buttons.
        XCTAssertEqual(face.findings.map(\.code), Array(repeating: .elementDropped, count: 5))
    }

    func testTextFollowsFaceKitsColourFontAndStyleRules() async throws {
        var json: [String: Any] = [
            "artistDisplayRect": rect(0, 0, 2, 4), "artistTextMode": 3,
            "artistDisplayFontName": "No Such Font Anywhere", "artistFontSize": 9,
            "artistDisplayTextFaceColorFromTxtr": ["red": 255, "green": 0, "blue": 0],
            "artistDisplayTextFaceColorFromFace": ["red": 0, "green": 255, "blue": 0],
            "albumDisplayRect": rect(2, 0, 4, 4), "albumTextMode": 1,
            "albumDisplayTextFaceColorFromFace": ["red": 0, "green": 0, "blue": 255],
        ]
        for suffix in ["Bold", "Italic", "Underline", "Outline", "Shadow", "Condense", "Extend", "Justify"] {
            json["artist\(suffix)"] = suffix == "Bold" || suffix == "Justify"
            json["album\(suffix)"] = true
        }
        json["albumExtend"] = "yes"   // one undecodable key empties the whole style
        let face = try await AudionFaceFixture(json: json).load()
        let artist = try XCTUnwrap(face.artist), album = try XCTUnwrap(face.album)
        XCTAssertEqual(artist.style, [.bold, .justify])
        XCTAssertTrue(artist.xor)
        XCTAssertEqual(artist.color.components, [1, 0, 0, 1], "Txtr wins over Face")
        XCTAssertEqual(CTFontGetSize(artist.font), 9)
        XCTAssertEqual(CTFontCopyFamilyName(artist.font) as String, "Helvetica")
        XCTAssertEqual(album.style, [])
        XCTAssertFalse(album.xor)
        XCTAssertEqual(album.color.components, [0, 0, 1, 1])
        XCTAssertEqual(CTFontGetSize(album.font), 12, "no font name: Helvetica 12")
    }

    func testRoleKeysMatchFaceKit() {
        XCTAssertEqual(AudionFace.ButtonRole.rewind.rectKey, "rewindButtonRect")
        XCTAssertEqual(AudionFace.ButtonRole.pause.rectKey, "playButtonRect")
        XCTAssertEqual(AudionFace.ButtonRole.playlist.sprite, "menu")
        XCTAssertEqual(AudionFace.IndicatorRole.mp3.rectKey, "MP3IndicatorRect")
        XCTAssertEqual(AudionFace.IndicatorRole.play.sprite, "play-indicator")
        XCTAssertEqual(AudionFace.DigitRole.trackDigit2.firstPICTKey, "trackDigit2FirstPICTID")
        XCTAssertEqual(AudionFace.AnimationRole.netLag.frameCountKey, "netLagNumPICTs")
        XCTAssertEqual(AudionFace.TextRole.album.styleKeys.last, "albumJustify")
    }

    func testTheFlipIsAgainstTheContainerHeight() {
        XCTAssertEqual(AudionFaceRect(x: 1, y: 2, width: 3, height: 4).flipped(inHeight: 10),
                       CGRect(x: 1, y: 4, width: 3, height: 4))
    }

    // Positional shorthand for the fixture's `{top, left, bottom, right}`.
    private func rect(_ top: Int, _ left: Int, _ bottom: Int, _ right: Int) -> [String: Int] {
        AudionFaceFixture.rect(top: top, left: left, bottom: bottom, right: right)
    }
}
