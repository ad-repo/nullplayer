import XCTest
import ZIPFoundation
@testable import NullPlayer

/// B107/B108 — what a seek bar reads, and what counts as the end of a film.
///
/// Both halves are the same shape of defect: a value that quietly changes its **source** when the
/// playback clock goes away, and is therefore correct for as long as anyone looks at it during
/// playback.
final class WinampModernB107Tests: XCTestCase {

    // MARK: - The seek bar reads the clock and nothing else

    /// **The two-thumb defect.** cPro_MMD stacks two `action="SEEK"` sliders on one frame (`seeker`
    /// and `seeker2`, both `{{10,434},{480,20}}`) and a script writes `setValue` on one of them as
    /// it plays. While the clock existed both read it and agreed, so the skin drew one thumb; the
    /// moment a duration went to zero the old code fell through to the generic `value` branch and
    /// the written slider read back its own stored 255 while its twin read 0 — a thumb at each end
    /// of the bar. Nothing here is specific to the end of a film: any moment without a duration did
    /// it.
    func testTwoSeekSlidersAgreeWhenTheClockGoesAway() throws {
        let scene = try makeScene(host: Host(currentTime: 0, duration: 0), markup: """
              <slider id="seeker"  action="SEEK" x="0" y="0" w="200" h="20"/>
              <slider id="seeker2" action="SEEK" x="0" y="0" w="200" h="20" value="255"/>
        """)
        XCTAssertEqual(try scene.normalizedValue(of: "seeker"), 0, accuracy: 0.0001)
        XCTAssertEqual(try scene.normalizedValue(of: "seeker2"), 0, accuracy: 0.0001,
                       "a seek slider stands at zero without a clock — it must not read back a value a script wrote")
    }

    /// The same pair with a clock: both read it, and the written `value` is still ignored. This is
    /// what makes the fix a rule rather than a special case for zero.
    func testASeekSliderIgnoresItsValueAttributeWhileThereIsAClock() throws {
        let scene = try makeScene(host: Host(currentTime: 50, duration: 200), markup: """
              <slider id="seeker"  action="SEEK" x="0" y="0" w="200" h="20"/>
              <slider id="seeker2" action="SEEK" x="0" y="0" w="200" h="20" value="255"/>
        """)
        XCTAssertEqual(try scene.normalizedValue(of: "seeker"), 0.25, accuracy: 0.0001)
        XCTAssertEqual(try scene.normalizedValue(of: "seeker2"), 0.25, accuracy: 0.0001)
    }

    /// A slider that is *not* a seek slider still reads its own value — the fix is scoped to the
    /// one action that owns the playback clock, and must not flatten every other slider to zero.
    func testANonSeekSliderStillReadsItsOwnValue() throws {
        let scene = try makeScene(host: Host(currentTime: 0, duration: 0), markup: """
              <slider id="plain" x="0" y="0" w="200" h="20" low="0" high="255" value="255"/>
        """)
        XCTAssertEqual(try scene.normalizedValue(of: "plain"), 1, accuracy: 0.0001)
    }

    // MARK: - What counts as the end of a film

    /// The measured case: a Plex `.mkv` whose end-of-film pause arrives at `t=5054.42` against a
    /// `5056.06` duration. VLCKit's clock stops updating over a second before the last frame, so a
    /// tight window misses the end of a real stream entirely.
    func testAPlexStreamsMeasuredEndCountsAsTheEnd() {
        XCTAssertFalse(VideoPlayerView.isFarFromEndOfMedia(currentTime: 5054.42,
                                                           totalDuration: 5056.06,
                                                           position: 0.9997))
    }

    func testTheMiddleOfAFilmIsNotItsEnd() {
        XCTAssertTrue(VideoPlayerView.isFarFromEndOfMedia(currentTime: 2500,
                                                          totalDuration: 5056.06,
                                                          position: 0.494))
    }

    /// **A seek in flight.** VLCKit blanks `time` while it seeks, so a seek to 30 s from the end
    /// briefly reports `t=0` against a known duration. Reading that as "no clock" and falling to
    /// the position term latched the session as finished in the middle of a film.
    func testAZeroClockAgainstAKnownDurationIsNotTheEnd() {
        XCTAssertTrue(VideoPlayerView.isFarFromEndOfMedia(currentTime: 0,
                                                          totalDuration: 5056.06,
                                                          position: 0.994))
    }

    /// B108's server-stream half: a stream whose duration VLCKit reports late or not at all. The
    /// normalized position is the only witness left, and it has to be believed — a duration-only
    /// test never fires for exactly this content, which is what left it never marked watched.
    func testAStreamWithNoDurationIsJudgedByItsPosition() {
        XCTAssertFalse(VideoPlayerView.isFarFromEndOfMedia(currentTime: 0, totalDuration: 0,
                                                           position: 0.999))
        XCTAssertTrue(VideoPlayerView.isFarFromEndOfMedia(currentTime: 0, totalDuration: 0,
                                                          position: 0.5))
    }

    /// Neither clock nor position: nothing is known. Unknown must not read as "not finished", or
    /// content whose duration never arrives never finishes at all — but this is only ever asked of
    /// a film that was playing, and the requested-pause test carries the real weight.
    func testNoClockAndNoPositionIsNotTreatedAsMidFilm() {
        XCTAssertFalse(VideoPlayerView.isFarFromEndOfMedia(currentTime: 0, totalDuration: 0,
                                                           position: 0))
    }

    // MARK: - Fixture

    private struct Scene {
        let renderer: WasabiSceneRenderer

        func normalizedValue(of id: String) throws -> CGFloat {
            let object = try XCTUnwrap(renderer.loadedSkin.runtime.graph.objects(xmlID: id).first,
                                       "no object with id \(id)")
            return renderer.normalizedValue(of: object)
        }
    }

    private func makeScene(host: Host, markup: String) throws -> Scene {
        let xml = """
        <WasabiXML>
          <container id="Main">
            <layout id="normal" w="200" h="20">
        \(markup)
            </layout>
          </container>
        </WasabiXML>
        """
        let loaded = try WinampModernSkinLoader(engineStore: nil).load(from: try makeArchive(xml: xml))
        addTeardownBlock { loaded.teardown() }
        let renderer = try WasabiSceneRenderer(loadedSkin: loaded, host: host, clock: { 0 })
        addTeardownBlock { renderer.teardown() }
        return Scene(renderer: renderer)
    }

    private func makeArchive(xml: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB107Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("B107-\(UUID().uuidString).wal")
        let archive = try Archive(url: url, accessMode: .create)
        let payload = Data(xml.utf8)
        try archive.addEntry(with: "skin.xml", type: .file, uncompressedSize: Int64(payload.count),
                             compressionMethod: .none) { position, size in
            let start = Int(position)
            guard start < payload.count else { return Data() }
            return payload.subdata(in: start..<min(payload.count, start + size))
        }
        return url
    }

    private final class Host: WinampModernHost {
        init(currentTime: TimeInterval, duration: TimeInterval) {
            self.currentTime = currentTime
            self.duration = duration
        }

        var playbackState: PlaybackState = .stopped
        var currentTime: TimeInterval
        var duration: TimeInterval
        var volume: Double = 0.5
        var balance: Double = 0
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
