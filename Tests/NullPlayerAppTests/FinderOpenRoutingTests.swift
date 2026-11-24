import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

/// What `AppDelegate.application(_:openFiles:)`, the Finder open path, does with the files it is
/// handed before launch finishes. That is a cold open: the delegate parks the tracks in
/// `pendingFilesToOpen` for `applicationDidFinishLaunching`.
///
/// The live counterpart, with real Apple Events across every skin family, is
/// `skills/app-control/scripts/finder-open-matrix.sh`.
final class FinderOpenRoutingTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        _ = NSApplication.shared    // openFiles replies through NSApp
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderOpenRoutingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Creates each named file (empty unless `contents` says otherwise) and returns what a delegate
    /// that has not finished launching parks for launch after a Finder open of them, in order.
    private func pending(after names: [String], contents: [String: String] = [:]) throws -> [Track] {
        for name in names {
            try (contents[name] ?? "").write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let delegate = AppDelegate()
        delegate.application(NSApplication.shared, openFiles: names.map { dir.appendingPathComponent($0).path })
        // The queue is private; reflection reads it without widening the delegate for a test.
        return Mirror(reflecting: delegate).children
            .first { $0.label == "pendingFilesToOpen" }?.value as? [Track] ?? []
    }

    private let cue = """
        FILE "album.m4a" WAVE
          TRACK 01 AUDIO
            TITLE "One"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Two"
            INDEX 01 01:00:00
        """

    func testAudioFilesQueueInTheOrderGiven() throws {
        let names = ["a.mp3", "b.flac", "c.m4a", "d.ogg", "e.opus", "f.wav", "g.aiff"]
        XCTAssertEqual(try pending(after: names).map(\.url.lastPathComponent), names)
    }

    func testACueAndItsBackingAudioQueueTheAlbumOnce() throws {
        let tracks = try pending(after: ["album.cue", "album.m4a"], contents: ["album.cue": cue])
        XCTAssertEqual(tracks.map(\.title), ["One", "Two"])
        XCTAssertEqual(Set(tracks.map { $0.url.lastPathComponent }), ["album.m4a"])
    }

    func testVideoQueuesAsVideo() throws {
        for name in ["v.mp4", "v.mov", "v.mkv"] {
            XCTAssertEqual(try pending(after: [name]).map(\.mediaType), [.video], name)
        }
    }

    func testMixedAudioAndVideoKeepsBoth() throws {
        XCTAssertEqual(try pending(after: ["a.mp3", "v.mp4"]).map(\.url.lastPathComponent), ["a.mp3", "v.mp4"])
    }

    func testPlaylistsQueueTheirEntries() throws {
        let a = dir.appendingPathComponent("a.mp3").path
        let files = ["list.m3u": "#EXTM3U\n\(a)\n", "list.pls": "[playlist]\nFile1=\(a)\nNumberOfEntries=1\n"]
        for (name, body) in files.sorted(by: { $0.key < $1.key }) {
            try "".write(toFile: a, atomically: true, encoding: .utf8)
            XCTAssertEqual(try pending(after: [name], contents: [name: body]).map(\.url.lastPathComponent), ["a.mp3"], name)
        }
    }

    /// Finder offers NullPlayer for a file only when Info.plist declares its type, so every extension
    /// openFiles accepts must be declared. Acceptance is measured through openFiles itself, so this
    /// follows the accepted set as it grows.
    func testDeclaredDocumentTypesCoverEveryAcceptedExtension() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NullPlayer/Resources/Info.plist")
        let info = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        let docTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let declared = docTypes.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }.compactMap(UTType.init)
        let declaredExtensions = Set(docTypes.flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] }.map { $0.lowercased() })

        let candidates = AudioFileValidator.supportedExtensions
            .union(AudioFileValidator.supportedVideoExtensions)
            .union(["cue", "m3u", "m3u8", "pls"])
        for ext in candidates.sorted() {
            let name = "probe.\(ext)"
            guard !(try pending(after: [name], contents: ext == "cue" ? [name: cue] : [:])).isEmpty else { continue }
            let type = UTType(filenameExtension: ext)
            let covered = declaredExtensions.contains(ext) || declared.contains { type?.conforms(to: $0) == true }
            XCTAssertTrue(covered, ".\(ext) is accepted by openFiles but no CFBundleDocumentTypes entry declares it")
        }
    }
}
