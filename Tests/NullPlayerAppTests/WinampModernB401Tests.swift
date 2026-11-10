import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B401 — a Winamp3 skin's window takes the bitmap definition in effect where it is declared.
///
/// Lapis_Lazuli (`version="0.8"`) defines `glass` as its dome sheen before the player and again as a
/// rounded bar in a file included after it; its Winamp3 screenshot shows the sheen. Winamp 5 skins
/// (cPro-Bento, SpongeBob) rely on the later definition winning, so that stays for version 1 and up.
final class WinampModernB401Tests: XCTestCase {

    func testAWinamp3ContainerKeepsTheDefinitionReadBeforeIt() throws {
        let image = try playerImage(version: "0.8")
        XCTAssertNotEqual(image.lowercased(), "glass")
        let loaded = try makeSkin(xml: skinXML(version: "0.8"))
        XCTAssertEqual(loaded.runtime.resources.definition(identifier: image)?.attributes["file"], "sheen.png")
    }

    func testAWinamp5SkinKeepsTheLaterDefinition() throws {
        XCTAssertEqual(try playerImage(version: "1.2"), "glass")
    }

    private func playerImage(version: String) throws -> String {
        let loaded = try makeSkin(xml: skinXML(version: version))
        var pending = loaded.runtime.graph.roots
        while let object = pending.popLast() {
            if object.xmlID == "player.glass" { return try XCTUnwrap(object.attributes["image"]) }
            pending.append(contentsOf: object.children)
        }
        throw XCTSkip("player.glass not built")
    }

    private func skinXML(version: String) -> String {
        """
        <WinampAbstractionLayer version="\(version)">
          <elements><bitmap id="glass" file="sheen.png"/></elements>
          <container id="main" name="Main" default_visible="1">
            <layout id="normal" w="100" h="50">
              <layer id="player.glass" x="0" y="0" image="glass"/>
            </layout>
          </container>
          <elements><bitmap id="glass" file="bar.png"/></elements>
        </WinampAbstractionLayer>
        """
    }

    private func makeSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB401Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B401-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: url)
        addTeardownBlock { loaded.teardown() }
        return loaded
    }
}
