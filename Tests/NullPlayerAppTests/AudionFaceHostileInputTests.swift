import XCTest
import ZIPFoundation
@testable import NullPlayer

/// One hostile input per `AUD####` code, at the production limits wherever a fixture can reach them
/// cheaply (sparse files and header-only PNGs do most of the work).
final class AudionFaceHostileInputTests: XCTestCase {
    private func failure(_ fixture: AudionFaceFixture) async throws -> AudionFaceDiagnosticCode? {
        try await AudionFaceFixture.failure { try await fixture.load() }
    }

    /// A file of `bytes` logical bytes that occupies almost no disk.
    private func sparse(_ fixture: AudionFaceFixture, _ name: String, bytes: Int, prefix: Data = Data()) throws {
        let url = fixture.folder.appendingPathComponent(name)
        try prefix.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(bytes))
        try handle.close()
    }

    func testAUD0001MissingIndex() async throws {
        let fixture = try AudionFaceFixture()
        try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent("index.json"))
        let code = try await failure(fixture)
        XCTAssertEqual(code, .missingIndex)
        let notAFolder = try await AudionFaceFixture.failure {
            try await AudionFaceLoader.load(folder: fixture.folder.appendingPathComponent("base.png"))
        }
        XCTAssertEqual(notAFolder, .missingIndex)
    }

    func testAUD0002MissingOrUndecodableBase() async throws {
        let missing = try AudionFaceFixture()
        try FileManager.default.removeItem(at: missing.folder.appendingPathComponent("base.png"))
        let notPNG = try AudionFaceFixture()
        try notPNG.write("base.png", Data("GIF89a".utf8))
        let headerOnly = try AudionFaceFixture()
        try headerOnly.pngHeader("base.png", width: 4, height: 4)
        for fixture in [missing, notPNG, headerOnly] {
            let code = try await failure(fixture)
            XCTAssertEqual(code, .missingBase)
        }
    }

    func testAUD0003IndexOverItsBound() async throws {
        let fixture = try AudionFaceFixture()
        let padding = String(repeating: " ", count: AudionFacePolicy.indexBytes - 1)
        try fixture.write("index.json", Data("{}\(padding)".utf8))
        let code = try await failure(fixture)
        XCTAssertEqual(code, .indexTooLarge)
    }

    func testAUD0004DecodedImageOverItsSideOrByteBound() async throws {
        let wide = try AudionFaceFixture(json: ["playButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1)])
        try wide.pngHeader("play.png", width: AudionFacePolicy.imageSide + 1, height: 1)
        let heavy = try AudionFaceFixture()
        let header = try Data(contentsOf: heavy.folder.appendingPathComponent("base.png"))
        try sparse(heavy, "base-alpha.png", bytes: AudionFacePolicy.imageBytes + 1, prefix: header)
        for fixture in [wide, heavy] {
            let code = try await failure(fixture)
            XCTAssertEqual(code, .imageTooLarge)
        }
    }

    func testAUD0004IgnoresFilesTheLoaderNeverDecodes() async throws {
        let fixture = try AudionFaceFixture()
        try fixture.pngHeader("drag.png", width: 100_000, height: 13)
        try fixture.pngHeader("play.png", width: 100_000, height: 13)   // no playButtonRect, so unread
        _ = try await fixture.load()
    }

    func testAUD0005TooManyFilesOrBytes() async throws {
        let many = try AudionFaceFixture()
        for index in 0..<AudionFacePolicy.faceFiles { try many.write("junk\(index)", Data()) }
        let heavy = try AudionFaceFixture()
        try sparse(heavy, "about.png", bytes: AudionFacePolicy.faceBytes)
        for fixture in [many, heavy] {
            let code = try await failure(fixture)
            XCTAssertEqual(code, .faceTooLarge)
        }
    }

    /// Only regular files are read: a FIFO named like a sprite would block the read forever.
    func testAFIFOIsAbsentNeverOpened() async throws {
        let sprite = try AudionFaceFixture(json: ["playButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1)])
        XCTAssertEqual(mkfifo(sprite.folder.appendingPathComponent("play.png").path, 0o600), 0)
        let face = try await sprite.load()
        XCTAssertEqual(face.findings.map(\.code), [.buttonWithoutSprite])
        for name in ["index.json", "base.png"] {
            let fixture = try AudionFaceFixture()
            try FileManager.default.removeItem(at: fixture.folder.appendingPathComponent(name))
            XCTAssertEqual(mkfifo(fixture.folder.appendingPathComponent(name).path, 0o600), 0)
            let code = try await failure(fixture)
            XCTAssertEqual(code, name == "base.png" ? .missingBase : .missingIndex)
        }
    }

    /// A sprite whose header passes and whose data does not decode is a missing file, in both passes.
    func testATruncatedSpriteIsMissing() async throws {
        let fixture = try AudionFaceFixture(json: ["playButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1)])
        try fixture.png("play.png", width: 8, height: 8)
        let png = try Data(contentsOf: fixture.folder.appendingPathComponent("play.png"))
        try fixture.write("play.png", png.prefix(33))   // signature + IHDR, no image data
        let face = try await fixture.load()
        XCTAssertNil(face.buttons[.play])
        XCTAssertEqual(face.findings.map(\.code), [.buttonWithoutSprite])
    }

    func testAUD0006Symlinks() async throws {
        let inside = try AudionFaceFixture()
        try FileManager.default.createSymbolicLink(at: inside.folder.appendingPathComponent("play.png"),
                                                   withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        let nested = try AudionFaceFixture()
        let sub = nested.folder.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sub.appendingPathComponent("x"),
                                                   withDestinationURL: URL(fileURLWithPath: "/"))
        for fixture in [inside, nested] {
            let code = try await failure(fixture)
            XCTAssertEqual(code, .pathEscape)
        }
        let target = try AudionFaceFixture()
        let link = target.folder.deletingLastPathComponent().appendingPathComponent("Linked Face")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.folder)
        let linked = try await AudionFaceFixture.failure { try await AudionFaceLoader.load(folder: link) }
        XCTAssertEqual(linked, .pathEscape)
    }

    func testAUD0007PICTRangesOutsideTheBoundDropTheElement() async throws {
        let rect = AudionFaceFixture.rect(top: 0, left: 0, bottom: 2, right: 2)
        let face = try await AudionFaceFixture(json: [
            "timeDigit1Rect": rect, "timeDigit1FirstPICTID": 99_995,
            "timeDigit2Rect": rect, "timeDigit2FirstPICTID": -1,
            "netLagAnimRect": rect, "netLagFirstPICTID": 0, "netLagNumPICTs": Int.max, "netLagFrameDelay": 1,
        ]).load()
        XCTAssertTrue(face.digits.isEmpty && face.animations.isEmpty)
        XCTAssertEqual(face.findings.map(\.code), [.pictOutOfRange, .pictOutOfRange, .pictOutOfRange])
    }

    /// Found by `AudionFaceFuzzTests`: an edge of `Int.max` trapped in the rect arithmetic, and a
    /// huge font size in the text rasterizer.
    func testAUD0013ExtremeCoordinatesAndFontSizesNeitherTrapNorDraw() async throws {
        let fixture = try AudionFaceFixture(json: [
            "playButtonRect": AudionFaceFixture.rect(top: 0, left: -1, bottom: 1, right: Int.max),
            "stopButtonRect": AudionFaceFixture.rect(top: 0, left: Int.max - 1, bottom: 1, right: Int.max),
            "artistDisplayRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 4, right: 40),
            "artistTextMode": 1, "artistDisplayFontName": "Helvetica", "artistFontSize": Int.max,
        ])
        try fixture.png("play.png")
        try fixture.png("stop.png")
        let face = try await fixture.load()
        XCTAssertTrue(face.buttons.isEmpty)
        // Play and pause share the malformed `playButtonRect`; stop is the third.
        XCTAssertEqual(face.findings.map(\.code), [.elementDropped, .elementDropped, .elementDropped])
        XCTAssertEqual(CTFontGetSize(try XCTUnwrap(face.artist).font), 12, "an out-of-range size reads as absent")
        var host = AudionFaceHostState()
        host.title = String(repeating: "W", count: 200)
        XCTAssertNotNil(AudionFaceRenderer.render(AudionFaceScene(face: face, host: host, scale: 6)))
    }

    func testAUD0011PixelBudgetIsCheckedFromHeadersBeforeAnyDecode() async throws {
        let side = AudionFacePolicy.imageSide
        let fixture = try AudionFaceFixture(json: [
            "playButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1),
            "stopButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1),
        ])
        for name in ["base.png", "base-alpha.png", "inactive-alpha.png", "play.png", "stop.png"] {
            try fixture.pngHeader(name, width: side, height: side)
        }
        let code = try await failure(fixture)
        XCTAssertEqual(code, .pixelBudgetExceeded)
    }

    func testAUD0012MalformedIndex() async throws {
        let deep = String(repeating: "[", count: 100_000)
        for json in ["[1, 2]", "{", "", deep] {
            let fixture = try AudionFaceFixture()
            try fixture.write("index.json", Data(json.utf8))
            let code = try await failure(fixture)
            XCTAssertEqual(code, .malformedIndex, json.prefix(8).description)
        }
    }

    // MARK: - Zip

    private func zip(_ entries: [WMPTestArchiveEntry], limits: AudionFaceZipLimits = .production) throws -> [URL] {
        let url = try WMPSkinTestSupport.makeArchive(entries, filename: "faces.zip")
        return try AudionFaceZipImport.unpack(url, into: try WMPSkinTestSupport.temporaryDirectory(), limits: limits)
    }

    /// As `AudionFaceFixture.failure`: an error that is not a finding is rethrown, never read as success.
    private func zipFailure(_ entries: [WMPTestArchiveEntry], limits: AudionFaceZipLimits = .production) throws -> AudionFaceDiagnosticCode? {
        do { _ = try zip(entries, limits: limits); return nil } catch let finding as AudionFaceFinding { return finding.code }
    }

    private func faceEntries(_ prefix: String) throws -> [WMPTestArchiveEntry] {
        let base = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: [UInt8](repeating: 255, count: 16))
        return [WMPTestArchiveEntry("\(prefix)index.json", data: Data("{}".utf8)),
                WMPTestArchiveEntry("\(prefix)base.png", data: base)]
    }

    func testAZipOfNestedFacesUnpacksEveryFaceAndSkipsAppleDouble() async throws {
        let url = try WMPSkinTestSupport.makeArchive(try faceEntries("Faces/One Face/") + faceEntries("Faces/Group/Two ™/")
            + [WMPTestArchiveEntry("__MACOSX/Faces/._One Face", data: Data("junk".utf8))], filename: "faces.zip")
        let destination = try WMPSkinTestSupport.temporaryDirectory()
        let faces = try AudionFaceZipImport.unpack(url, into: destination)
        XCTAssertEqual(faces.map(\.lastPathComponent), ["Two ™", "One Face"])
        for face in faces { _ = try await AudionFaceLoader.load(folder: face) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("__MACOSX").path))
    }

    func testAUD0010ZipBounds() throws {
        let entries = try faceEntries("Face/")
        var few = AudionFaceZipLimits.production
        few.entries = 1
        XCTAssertEqual(try zipFailure(entries, limits: few), .zipOverLimit)
        var small = AudionFaceZipLimits.production
        small.entryBytes = 10
        XCTAssertEqual(try zipFailure(entries, limits: small), .zipOverLimit)
        var tight = AudionFaceZipLimits.production
        tight.totalBytes = UInt64(entries[1].data.count)
        XCTAssertEqual(try zipFailure(entries, limits: tight), .zipOverLimit)
    }

    /// The `.wmz` Amendment 1 pair, at production values: a plain small file squashes past 200:1 and
    /// is admitted; past the 1 MiB floor the same ratio is a bomb.
    func testAUD0010RatioAppliesOnlyAboveItsFloor() throws {
        let plain = WMPTestArchiveEntry("Face/about.png", data: Data(count: 64 * 1_024), compression: .deflate)
        XCTAssertNil(try zipFailure(try faceEntries("Face/") + [plain]))
        let bomb = WMPTestArchiveEntry("Face/about.png", data: Data(count: 2 * 1_024 * 1_024), compression: .deflate)
        XCTAssertEqual(try zipFailure(try faceEntries("Face/") + [bomb]), .zipOverLimit)
    }

    func testAUD0006ZipPathsThatEscape() throws {
        for path in ["../evil.png", "/abs.png", "Face/../../x.png", "Face\\x.png"] {
            XCTAssertEqual(try zipFailure([WMPTestArchiveEntry(path, data: Data("x".utf8))]), .pathEscape, path)
        }
        XCTAssertEqual(try zipFailure([WMPTestArchiveEntry("Face/link", data: Data("/etc".utf8), type: .symlink)]), .pathEscape)
    }

    func testAUD0014UnreadableOrCorruptZip() throws {
        let garbage = try WMPSkinTestSupport.temporaryDirectory().appendingPathComponent("garbage.zip")
        try Data("not a zip".utf8).write(to: garbage)
        XCTAssertThrowsError(try AudionFaceZipImport.unpack(garbage, into: try WMPSkinTestSupport.temporaryDirectory())) {
            XCTAssertEqual(($0 as? AudionFaceFinding)?.code, .unreadableZip)
        }

        let marker = Data(String(repeating: "PAYLOAD-", count: 8).utf8)
        let url = try WMPSkinTestSupport.makeArchive([WMPTestArchiveEntry("Face/x.png", data: marker)], filename: "crc.zip")
        var bytes = try Data(contentsOf: url)
        let at = try XCTUnwrap(bytes.range(of: marker)).lowerBound
        bytes[at] ^= 0xFF
        try bytes.write(to: url)
        XCTAssertThrowsError(try AudionFaceZipImport.unpack(url, into: try WMPSkinTestSupport.temporaryDirectory())) {
            XCTAssertEqual(($0 as? AudionFaceFinding)?.code, .unreadableZip)
        }
    }
}
