import XCTest
import ZIPFoundation
@testable import NullPlayer

/// wTunes' report (2026-10-21): VU needles that twitched, and a Windows menu reading `About%09Alt+A`.
final class WinampModernWTunesTests: XCTestCase {
    /// `%09` ends a container's name: what follows is the accelerator Winamp right-aligns in its menu.
    func testAcceleratorAfterAnEscapedTabIsNotPartOfTheName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernWTunesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wTunes.wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data("""
        <WasabiXML>
          <container id="main"><layout id="normal" w="100" h="100"/></container>
          <container id="about" name="About%09Alt+A"><layout id="a" w="100" h="100"/></container>
          <container id="plain" name="Album Art"><layout id="b" w="100" h="100"/></container>
          <container id="bare" name="%09Alt+B"><layout id="c" w="100" h="100"/></container>
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
        let names = Dictionary(uniqueKeysWithValues: WinampModernContainerTopology
            .analyze(graph: loaded.runtime.graph)
            .map { ($0.id, WinampModernContainerTopology.displayName(of: $0)) })

        XCTAssertEqual(names["about"], "About")
        XCTAssertEqual(names["plain"], "Album Art")
        XCTAssertEqual(names["bare"], "bare", "a name that is only an accelerator falls back to the id")
    }

    /// A VU rises at once and falls back over `releaseTime`, per channel.
    func testVUFalloffAttacksInstantlyAndReleasesSlowly() {
        let held = WinampModernLevelMeter.Level(left: 0.8, right: 0.2)
        let raw = WinampModernLevelMeter.Level(left: 0.1, right: 0.9)
        let step = WinampModernLevelMeter.releaseTime
        let next = WinampModernLevelMeter.falloff(from: held, toward: raw, elapsed: step)

        XCTAssertEqual(next.right, 0.9, "a louder block is shown at once")
        XCTAssertEqual(next.left, 0.8 * exp(-1), accuracy: 1e-9, "a quieter one decays, not drops")
        XCTAssertEqual(WinampModernLevelMeter.falloff(from: held, toward: .silence, elapsed: 10 * step).left,
                       0, accuracy: 1e-3, "silence still reaches zero")
    }
}
