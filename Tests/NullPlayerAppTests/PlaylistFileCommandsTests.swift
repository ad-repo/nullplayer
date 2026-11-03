import AppKit
import XCTest
@testable import NullPlayer

/// The Classic and Original playlists lost their ADD / LIST bar, so their right-click carries its
/// commands as Add ▸ and Playlist ▸. A playlist that is not a `PlaylistFileCommands` (the `.wmz`
/// pane, `WMPPlaylistMenuTests`) keeps the menu without them.
final class PlaylistFileCommandsTests: XCTestCase {

    @MainActor
    private func assertFileCommands(on target: PlaylistFileCommands, file: StaticString = #filePath,
                                    line: UInt = #line) throws {
        let menu = PlaylistMenuBuilder.menu(target: target, state: .init(selectedRows: [], hasTracks: true))
        XCTAssertEqual(menu.items.map(\.title),
                       ["Play", "", "Add", "Remove Selected", "Clear Playlist", "Remove Dead Files", "",
                        "Selection", "Sort", "Playlist", "", "File Info...", "", "Show Artist", "Show Album"], file: file, line: line)
        let add = try XCTUnwrap(menu.items[2].submenu, file: file, line: line)
        let list = try XCTUnwrap(menu.items[9].submenu, file: file, line: line)
        XCTAssertEqual(add.items.map(\.title), ["Add URL...", "Add Directory...", "Add Files..."],
                       file: file, line: line)
        XCTAssertEqual(list.items.map(\.title), ["New Playlist", "Save Playlist...", "Load Playlist..."],
                       file: file, line: line)
        for item in add.items + list.items {
            XCTAssertTrue(item.target === target, item.title, file: file, line: line)
            XCTAssertTrue((item.target as AnyObject).responds(to: item.action), item.title, file: file, line: line)
        }
    }

    @MainActor
    func testTheClassicPlaylistMenuCarriesAddAndPlaylist() throws {
        try assertFileCommands(on: PlaylistView(frame: NSRect(x: 0, y: 0, width: 275, height: 116)))
    }

    @MainActor
    func testTheOriginalPlaylistMenuCarriesAddAndPlaylist() throws {
        try assertFileCommands(on: ModernPlaylistView(frame: NSRect(x: 0, y: 0, width: 275, height: 116)))
    }

    /// A stream keeps its whole URL, which `Playlist.load` reads back; its path alone would not play.
    func testTheSavedM3UKeepsAStreamsURLAndAFilesPath() {
        let file = Track(url: URL(fileURLWithPath: "/Music/a b.mp3"), title: "Song", duration: 61.7)
        let stream = Track(url: URL(string: "https://ice1.somafm.com/groovesalad-128-mp3")!,
                           title: "Groove Salad", duration: nil)
        XCTAssertEqual(Playlist.m3u(for: [file, stream]), """
            #EXTM3U
            #EXTINF:61,Song
            /Music/a b.mp3
            #EXTINF:0,Groove Salad
            https://ice1.somafm.com/groovesalad-128-mp3

            """)
    }

    /// Add ▸ appends behind a playing queue and leaves its track playing; it replaced the queue (M65).
    func testAddAppendsBehindThePlayingTrack() throws {
        let song = try TestAudioFile.temporaryWAV(seconds: 10, tone: true)
        let added = try TestAudioFile.temporaryWAV(seconds: 1, tone: true)
        defer { [song, added].forEach { try? FileManager.default.removeItem(at: $0) } }
        let missing = URL(fileURLWithPath: "/tmp/\(UUID()).mp3")

        let engine = AudioEngine()
        defer { engine.stop() }
        AudioEngine.isHeadless = true
        defer { AudioEngine.isHeadless = false }
        engine.appendFiles([song])
        XCTAssertEqual(engine.state, .playing, "an empty queue still loads and plays")
        let playing = engine.currentTrack?.id

        engine.appendFiles([added, missing])

        XCTAssertEqual(engine.playlist.map(\.url), [song, added], "a file that fails the check is left out")
        XCTAssertEqual(engine.currentIndex, 0)
        XCTAssertEqual(engine.currentTrack?.id, playing)
        XCTAssertEqual(engine.state, .playing)
    }
}
