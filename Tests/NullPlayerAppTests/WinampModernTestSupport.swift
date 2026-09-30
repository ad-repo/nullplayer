import Foundation
import XCTest
import ZIPFoundation
@testable import NullPlayer

/// A host with nothing playing, for a test that needs a scene or a runtime and no audio.
final class WinampModernStubHost: WinampModernHost {
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

extension XCTestCase {
    /// A synthetic `.wal` holding `xml` as its `skin.xml`, loaded through the same loader the app
    /// uses. The archive and the loaded skin are torn down with the test.
    func makeWinampModernSkin(xml: String) throws -> WinampModernLoadedSkin {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(type(of: self))-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // A name of its own: what the host remembers about a skin is keyed on it.
        let url = directory.appendingPathComponent("\(type(of: self))-\(UUID().uuidString).wal")
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
