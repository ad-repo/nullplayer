import XCTest
import ZIPFoundation
@testable import NullPlayer

final class WinampModernPhase4Tests: XCTestCase {
    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 240
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = "Synthetic Song"
        var trackInfo = "Synthetic Artist"
        var spectrumLevels: [Float] = [0.1, 0.4, 0.8, 0.3]
        var beginCount = 0
        var endCount = 0

        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) { currentTime = seconds }
        func openFiles() {}
        func beginVisualizationConsumption() { beginCount += 1 }
        func endVisualizationConsumption() { endCount += 1 }
    }

    func testLocalWinampModernCompatibilityWhenFixtureIsSupplied() throws {
        guard let path = ProcessInfo.processInfo.environment["WINAMP_MODERN_WAL"] else {
            throw XCTSkip("Set WINAMP_MODERN_WAL to a user-supplied Winamp Modern .wal fixture.")
        }
        let loaded = try WinampModernSkinLoader().load(from: URL(fileURLWithPath: path))
        let host = Host()
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host)
        let scripts = try WinampModernScriptRuntime(loadedSkin: loaded, host: host)
        // Phase 13.3: the callback is addressed to a container; this harness hosts only the main one.
        scripts.layoutSwitchRequested = { container, id in
            guard container == renderer.container.stableID else { return false }
            return (try? renderer.activateLayout(id: id)) != nil
        }
        defer {
            scripts.teardown()
            renderer.teardown()
            loaded.teardown()
        }

        let shadeBindings = loaded.runtime.scriptBindings.filter { $0.logicalPath.lowercased().contains("shadelinks") }
        XCTAssertFalse(shadeBindings.isEmpty)
        for binding in shadeBindings {
            var owner = binding.ownerID.flatMap(loaded.runtime.graph.object(withID:))
            var foundLayout = false
            while let current = owner {
                if current.typeName.caseInsensitiveCompare("layout") == .orderedSame { foundLayout = true; break }
                owner = current.parent
            }
            XCTAssertTrue(foundLayout, "Shade script owner must remain attached beneath a layout")
        }
        try scripts.start()
        XCTAssertEqual(renderer.activeLayoutID.lowercased(), "normal")
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 354, height: 280))
        XCTAssertTrue(renderer.availableLayoutIDs.contains(where: { $0.caseInsensitiveCompare("shade") == .orderedSame }))
        XCTAssertGreaterThan(renderer.sceneNodes().count, 50)
        let program = try XCTUnwrap(scripts.programs.first)
        _ = try scripts.invoke(method: "switchtolayout",
                               on: MakiObjectReference(.gui(renderer.container.stableID)),
                               arguments: [.string("shade")], program: program)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 354, height: 25))
        XCTAssertEqual(renderer.resize(to: CGSize(width: 1, height: 1)), CGSize(width: 354, height: 25))
        _ = try scripts.invoke(method: "switchtolayout",
                               on: MakiObjectReference(.gui(renderer.container.stableID)),
                               arguments: [.string("normal")], program: program)
        XCTAssertEqual(renderer.canvasSize, CGSize(width: 354, height: 280))
        let originalTheme = renderer.themes.activeTheme
        if let alternate = renderer.themes.themeNames.first(where: {
            $0.caseInsensitiveCompare(originalTheme) != .orderedSame
        }) {
            XCTAssertTrue(renderer.activateTheme(alternate))
            XCTAssertEqual(renderer.themes.activeTheme, alternate)
            XCTAssertTrue(renderer.activateTheme(originalTheme))
        }
        XCTAssertEqual(host.beginCount, 1)
    }

    func testPhase4ResourcesWidgetsXUIThemesAndLayouts() throws {
        let xml = """
        <WasabiXML>
          <elements>
            <bitmap id="sheet" file="sheet.png" gammagroup="Tint"/>
            <bitmap id="state0" file="sheet.png" x="0" y="0" w="8" h="8"/>
            <bitmap id="state1" file="sheet.png" x="8" y="0" w="8" h="8"/>
            <elementalias id="sheet.alias" target="sheet"/>
            <bitmapfont id="pixel.font" file="sheet" charwidth="8" charheight="8"/>
            <color id="label.color" value="32,64,96" gammagroup="Tint"/>
            <gammaset id="Default"><gammagroup id="Tint" value="0,0,0"/></gammaset>
            <gammaset id="Red"><gammagroup id="Tint" value="2048,0,0" boost="1"/></gammaset>
          </elements>
          <groupdef id="synthetic.widget" xuitag="Synthetic:Widget" embed_xui="slot">
            <group id="slot"><layer id="aliased" image="sheet.alias" w="8" h="8"/></group>
          </groupdef>
          <container id="Main">
            <layout id="normal" minimum_w="100" minimum_h="40" maximum_w="200" maximum_h="100" w="120" h="60">
              <Synthetic:Widget id="widget"><text id="embedded" font="pixel.font" color="label.color" text="abc" w="40" h="10"/></Synthetic:Widget>
              <layer id="hidden" image="sheet" x="50" w="8" h="8"/>
              <NStatesButton id="states" image="state" state="1" x="60" w="8" h="8"/>
              <AnimatedLayer id="animation" image="sheet" x="70" w="8" h="8" autoplay="1" speed="20"/>
              <Songticker id="ticker" font="pixel.font" text="abcdefghijklmnopqrstuvwxyz" y="12" w="50" h="8"/>
              <AlbumArt id="cover" notfoundImage="state0" x="80" y="20" w="8" h="8"/>
              <Vis id="spectrum" x="0" y="30" w="80" h="10" colorBand1="255,255,255"/>
              <sendparams target="embedded" x="12"/>
              <hideobject target="hidden"/>
            </layout>
            <layout id="shade" minimum_w="90" minimum_h="20" w="90" h="20"><layer image="state0"/></layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader().load(from: try makeArchive(xml: xml))
        defer {
            UserDefaults.standard.removeObject(
                forKey: "winampModern.config.\(loaded.configuration.namespace).appearance.theme")
        }
        let host = Host()
        host.spectrumLevels = [0.2, 0.8, 0.4, 1]
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0.05 })
        defer { renderer.teardown(); loaded.teardown() }

        XCTAssertEqual(loaded.runtime.resources.resolvedDefinition(identifier: "sheet.alias")?.identifier, "sheet")
        let embedded = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "embedded").first)
        XCTAssertEqual(embedded.attributes["x"], "12")
        XCTAssertEqual(embedded.parent?.xmlID, "slot")
        XCTAssertEqual(loaded.runtime.graph.objects(xmlID: "hidden").first?.attributes["visible"], "0")
        XCTAssertEqual(renderer.themes.themeNames, ["Default", "Red"])
        XCTAssertTrue(renderer.activateTheme("Red"))
        XCTAssertEqual(renderer.themes.activeTheme, "Red")
        XCTAssertNotNil(renderer.resources.bitmap(identifier: "sheet.alias"))

        var pixels = [UInt8](repeating: 0, count: 120 * 60 * 4)
        let context = pixels.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: 120, height: 60, bitsPerComponent: 8,
                      bytesPerRow: 120 * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }
        renderer.draw(in: try XCTUnwrap(context))
        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 })
        XCTAssertEqual(try renderer.activateLayout(id: "shade"), CGSize(width: 90, height: 20))
        XCTAssertEqual(renderer.resize(to: CGSize(width: 1, height: 1)), CGSize(width: 90, height: 20))
        XCTAssertEqual(try renderer.activateLayout(id: "normal"), CGSize(width: 120, height: 60))
        XCTAssertEqual(renderer.resize(to: CGSize(width: 500, height: 500)), CGSize(width: 200, height: 100))
    }

    func testAliasCyclesFailClosedAndConfigurationIsNamespaced() throws {
        let registry = WalResourceRegistry()
        let source = WalSourceLocation(path: "/Synthetic/aliases.xml")
        registry.registerAlias(identifier: "a", target: "b", source: source)
        registry.registerAlias(identifier: "b", target: "a", source: source)
        XCTAssertNil(registry.resolvedDefinition(identifier: "a"))

        let suiteName = "WinampModernPhase4Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = WinampModernConfiguration(namespace: "first", defaults: defaults)
        let second = WinampModernConfiguration(namespace: "second", defaults: defaults)
        first.setInteger(7, section: "drawer", key: "state")
        XCTAssertEqual(first.integer(section: "drawer", key: "state"), 7)
        XCTAssertEqual(second.integer(section: "drawer", key: "state", default: 3), 3)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernPhase4Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Synthetic-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let png = try makePNG()
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", png)] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }

    private func makePNG() throws -> Data {
        let width = 256
        let height = 16
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = UInt8((offset / 4) % width)
            pixels[offset + 1] = 80
            pixels[offset + 2] = 160
        }
        let image = try pixels.withUnsafeMutableBytes { bytes -> CGImage in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height,
                                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let representation = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
