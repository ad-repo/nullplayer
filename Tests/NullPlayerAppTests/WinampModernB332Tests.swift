import XCTest
import AppKit
import ZIPFoundation
@testable import NullPlayer

/// B331-B334 (intake #5, group 5): one seam each.
final class WinampModernB332Tests: XCTestCase {
    /// B332: a group that declares no size is not a coordinate space; a sized one is.
    func testMouseSpaceSkipsASizelessGroup() throws {
        let (loaded, renderer) = try makeRenderer(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="400" h="200">
            <group id="loose" x="100"><layer id="a" x="0" y="0" w="10" h="10"/></group>
            <group id="boxed" x="30" y="20" w="50" h="50"><layer id="b" x="0" y="0" w="10" h="10"/></group>
          </layout></container>
        </WasabiXML>
        """)
        let a = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "a").first)
        let b = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "b").first)
        XCTAssertEqual(renderer.coordinateSpace(of: a), CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertEqual(renderer.coordinateSpace(of: b)?.origin, CGPoint(x: 30, y: 20))
    }

    /// B333: a host component ignores the group's focus fade, not its static alpha.
    func testHostComponentIgnoresInactiveAlpha() throws {
        let (loaded, _) = try makeRenderer(xml: """
        <WasabiXML>
          <container id="main"><layout id="normal" w="400" h="200">
            <group id="g" inactivealpha="175" alpha="200"><layer id="c"/></group>
          </layout></container>
        </WasabiXML>
        """)
        let c = try XCTUnwrap(loaded.runtime.graph.objects(xmlID: "c").first)
        XCTAssertEqual(WasabiSceneRenderer.hostComponentAlpha(of: c), 200.0 / 255, accuracy: 1e-9)
    }

    /// B334: on an `alphabackground` layout, a text wholly below the artwork is not drawn or hit.
    func testTextBelowTheArtIsDropped() throws {
        let (_, renderer) = try makeRenderer(xml: """
        <WasabiXML>
          <bitmap id="bg" file="bg.png"/>
          <container id="main"><layout id="normal" w="100" h="100" alphabackground="bg">
            <layer id="body" image="bg" x="0" y="0"/>
            <text id="on" x="0" y="5" w="20" h="10" default="x"/>
            <text id="below" x="0" y="60" w="20" h="10" default="x"/>
          </layout></container>
        </WasabiXML>
        """, png: true)
        func clip(_ id: String) -> CGRect? {
            renderer.sceneNodes().first { $0.object.xmlID == id }?.clipping.rect
        }
        XCTAssertEqual(clip("on")?.isEmpty, false)
        XCTAssertEqual(clip("below")?.isEmpty, true)
    }

    /// B334: a bitmap that is present and fully transparent is not a missing one (HALOAMP's): the
    /// button is the only art, and the text below it is still dropped.
    func testTextBelowIsStillDroppedWhenTheBitmapIsTransparent() throws {
        let (_, renderer) = try makeRenderer(xml: """
        <WasabiXML>
          <bitmap id="bg" file="bg.png"/>
          <container id="main"><layout id="normal" w="100" h="100" alphabackground="bg">
            <button id="b" x="0" y="5" w="10" h="10"/>
            <text id="below" x="0" y="60" w="20" h="10" default="x"/>
          </layout></container>
        </WasabiXML>
        """, png: true, transparent: true)
        let below = renderer.sceneNodes().first { $0.object.xmlID == "below" }
        XCTAssertEqual(below?.clipping.rect.isEmpty, true)
    }

    /// B334 audit: a layout whose named bitmap is not in the archive (Auburn's thinger) has art the
    /// renderer cannot see, so its text below the buttons is the skin's own and stays.
    func testTextIsKeptWhenTheLayoutsBitmapIsMissing() throws {
        let (_, renderer) = try makeRenderer(xml: """
        <WasabiXML>
          <bitmap id="bg" file="bg.png"/>
          <container id="main"><layout id="normal" w="100" h="100" alphabackground="bg">
            <button id="b" x="0" y="5" w="10" h="10"/>
            <text id="below" x="0" y="60" w="20" h="10" default="x"/>
          </layout></container>
        </WasabiXML>
        """)
        let below = renderer.sceneNodes().first { $0.object.xmlID == "below" }
        XCTAssertEqual(below?.clipping.rect.isEmpty, false)
    }

    private func makeRenderer(xml: String, png: Bool = false, transparent: Bool = false) throws -> (WinampModernLoadedSkin, WasabiSceneRenderer) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB332Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B332.wal")
        let archive = try Archive(url: url, accessMode: .create)
        func add(_ name: String, _ payload: Data) throws {
            try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        try add("skin.xml", Data(xml.utf8))
        if png { try add("bg.png", Self.artPNG(opaqueSide: transparent ? 0 : 20)) }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: Host())
        addTeardownBlock { renderer.teardown() }
        return (loaded, renderer)
    }

    /// 40x40, opaque in the top-left 20x20 only.
    private static func artPNG(opaqueSide: Int = 20) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(rep.bitmapData)
        for y in 0..<40 { for x in 0..<40 {
            let o = y * rep.bytesPerRow + x * 4
            let opaque = x < opaqueSide && y < opaqueSide
            (pixels[o], pixels[o + 1], pixels[o + 2], pixels[o + 3]) = (opaque ? 255 : 0, 0, 0, opaque ? 255 : 0)
        } }
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let back = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(back.colorAt(x: 5, y: 5)?.alphaComponent ?? 0, opaqueSide > 0 ? 1 : 0, accuracy: 0.01)
        return png
    }

    private final class Host: WinampModernHost {
        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval = 0
        var duration: TimeInterval = 0
        var volume: Double = 0.5
        var shuffleEnabled = false
        var repeatEnabled = false
        var trackTitle = ""
        var trackInfo = ""
        var spectrumLevels: [Float] = []
        func play() {}
        func pause() {}
        func stop() {}
        func previous() {}
        func next() {}
        func seek(to seconds: TimeInterval) {}
        func openFiles() {}
        func beginVisualizationConsumption() {}
        func endVisualizationConsumption() {}
    }
}
