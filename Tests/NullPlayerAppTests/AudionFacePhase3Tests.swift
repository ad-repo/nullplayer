import XCTest
@testable import NullPlayer

/// Audion mode's app integration: the factory route, the capability, the menu, persistence,
/// the importer and the face-derived palette. Faces are synthesized; nothing here launches the app.
final class AudionFacePhase3Tests: XCTestCase {

    func testFactoryRoutesAudionToItsOwnControllerAndTeardownCyclesStayExplicit() {
        let cycle: [PlayerUIMode] = [.classic, .audion, .wmp, .audion, .modern]
        for _ in 0..<10 {
            for mode in cycle {
                autoreleasepool {
                    let controller = WindowManager.makeMainWindowController(for: mode)
                    XCTAssertEqual(controller is AudionFaceMainWindowController, mode == .audion)
                    controller.prepareForUITeardown()
                    controller.window?.close()
                }
            }
        }
    }

    func testTheModeIsAvailableAndHasItsOwnMenu() {
        XCTAssertEqual(PlayerUIMode.audion.controllerFamily, .audion)
        XCTAssertFalse(PlayerUIMode.audion.usesModernEQLayout)
        XCTAssertNil(PlayerUIMode.audion.modernSkinFamily)
        XCTAssertTrue(AppCapabilities.supports(.audionFaceMode))
        XCTAssertEqual(PlayerUIMode.argumentOverride(from: ["uiMode": "audion"]), .audion)
        let item = ContextMenuBuilder.buildMenuBarUIMenu().items.first { $0.title == "Audion Faces" }
        let titles = item?.submenu?.items.map(\.title) ?? []
        for option in ["Load Face...", "Get More Faces...", "Open Faces Folder..."] {
            XCTAssertTrue(titles.contains(option), option)
        }
    }

    func testALongFaceListIsGroupedByInitialAndTheCheckedLetterIsMarked() {
        let names = ["agitator", " Apple", "Black Bar", "Étoile", "#9", "zed"]
        let items = names.map { NSMenuItem(title: $0, action: nil, keyEquivalent: "") }
        items[2].state = .on
        XCTAssertEqual(ContextMenuBuilder.groupedAlphabetically(items, over: names.count), items, "at the limit, flat")
        let groups = ContextMenuBuilder.groupedAlphabetically(items, over: 3)
        XCTAssertEqual(groups.map(\.title), ["A", "B", "E", "Z", "#"])
        XCTAssertEqual(groups[0].submenu?.items.map(\.title), ["agitator", " Apple"])
        XCTAssertEqual(groups.filter { $0.state == .on }.map(\.title), ["B"])
    }

    func testTheFaceNameRoundTripsAndOlderStateDecodesWithoutIt() throws {
        var state = AppStateManager.AppState.fixture()
        state.uiMode = PlayerUIMode.audion.rawValue
        state.audionFaceName = " Escher∆ "
        let encoded = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(AppStateManager.AppState.self, from: encoded).audionFaceName, " Escher∆ ")

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "audionFaceName")
        let decoded = try JSONDecoder().decode(AppStateManager.AppState.self,
                                               from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.audionFaceName)
    }

    // MARK: - Importer

    private func importer() throws -> AudionFaceImporter {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AudionFacePhase3Tests-\(UUID().uuidString)"))
        return AudionFaceImporter(directoryURL: try WMPSkinTestSupport.temporaryDirectory(), defaults: defaults)
    }

    func testAFolderInstallsSelectsAndRemoves() async throws {
        let importer = try importer()
        XCTAssertNil(try importer.selectedFaceURL())
        let fixture = try AudionFaceFixture(name: " Spaced Face ")
        let installed = try await importer.importFaces(from: fixture.folder)
        XCTAssertEqual(installed.map(\.name), [" Spaced Face "])
        XCTAssertEqual(importer.installedFaces().map(\.name), [" Spaced Face "])
        XCTAssertEqual(try importer.selectedFaceURL()?.lastPathComponent, " Spaced Face ")
        // Installing again replaces the face in place.
        _ = try await importer.importFaces(from: fixture.folder)
        XCTAssertEqual(importer.installedFaces().count, 1)

        try await importer.removeFace(named: " Spaced Face ")
        XCTAssertTrue(importer.installedFaces().isEmpty)
        XCTAssertNil(importer.selectedFaceName)
    }

    func testAMissingSelectionThrowsAndAnInvalidFaceInstallsNothing() async throws {
        let importer = try importer()
        importer.select("Gone")
        XCTAssertThrowsError(try importer.selectedFaceURL())

        let broken = try AudionFaceFixture(name: "Broken")
        try FileManager.default.removeItem(at: broken.folder.appendingPathComponent("base.png"))
        let code = try await AudionFaceFixture.failure { try await importer.importFaces(from: broken.folder) }
        XCTAssertEqual(code, .missingBase)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: importer.directoryURL.path)
        XCTAssertEqual(leftovers, [], "no face and no .incoming copy left behind")
    }

    func testAZipInstallsEveryFaceItHolds() async throws {
        let base = try WMPSkinTestSupport.encodedImage(width: 2, height: 2, rgba: [UInt8](repeating: 255, count: 16))
        let entries = ["Faces/One/", "Faces/Two/"].flatMap {
            [WMPTestArchiveEntry("\($0)index.json", data: Data("{}".utf8)), WMPTestArchiveEntry("\($0)base.png", data: base)]
        }
        let zip = try WMPSkinTestSupport.makeArchive(entries, filename: "faces.zip")
        let importer = try importer()
        let installed = try await importer.importFaces(from: zip)
        XCTAssertEqual(Set(installed.map(\.name)), ["One", "Two"])
        XCTAssertEqual(importer.installedFaces().map(\.name), ["One", "Two"])
    }

    // MARK: - Palette

    func testThePaletteIsTheDisplayGroundTheFacesTextColoursAndItsBody() async throws {
        let fixture = try AudionFaceFixture(json: [
            "albumDisplayRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 2, right: 4), "albumTextMode": 1,
            "albumDisplayTextFaceColorFromFace": ["red": 255, "green": 255, "blue": 255],
            "artistDisplayRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 2, right: 4), "artistTextMode": 1,
            "artistDisplayTextFaceColorFromFace": ["red": 255, "green": 255, "blue": 0],
        ])
        // A 4×8 base: a black display over the top two rows, grey below.
        let black: [UInt8] = [0, 0, 0, 255], grey: [UInt8] = [128, 128, 128, 255]
        let rgba = Array(([[UInt8]](repeating: black, count: 8) + [[UInt8]](repeating: grey, count: 24)).joined())
        try fixture.write("base.png", WMPSkinTestSupport.encodedImage(width: 4, height: 8, rgba: rgba))

        let style = AudionFacePalette.surfaceStyle(for: try await fixture.load())
        func rgb(_ color: NSColor) -> [Int] {
            let c = color.usingColorSpace(.sRGB)!
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        // The face's colours are device RGB; read back in sRGB they move a few levels.
        func assertNear(_ color: NSColor, _ expected: [Int], _ role: String) {
            XCTAssertTrue(zip(rgb(color), expected).allSatisfy { abs($0 - $1) <= 6 }, "\(role): \(rgb(color))")
        }
        assertNear(style.background, [0, 0, 0], "ground")
        assertNear(style.text, [255, 255, 255], "text")
        assertNear(style.currentText, [255, 255, 0], "current text")
        assertNear(style.selectionBackground, [128, 128, 128], "selection")
    }
}
