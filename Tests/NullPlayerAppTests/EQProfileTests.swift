import AVFoundation
import XCTest
@testable import NullPlayer

final class EQProfileTests: XCTestCase {
    private var directory: URL!
    private var storePath: String { directory.appendingPathComponent("eq_profiles.db").path }
    private var defaultsSuite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EQProfileTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaultsSuite = "EQProfileTests-\(UUID())"
        defaults = UserDefaults(suiteName: defaultsSuite)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    private func local(_ path: String, artist: String? = "Artist", album: String? = "Album") -> Track {
        Track(url: URL(fileURLWithPath: path), title: path, artist: artist, album: album)
    }

    private func curve(_ gain: Float) -> EQCurve {
        var curve = EQCurve.flat
        curve.left.bands[10] = gain
        curve.right.bands[10] = gain
        return curve
    }

    // MARK: - Keys

    func testKeysAreScopedBySourceAndCarryTheArtistOnTheAlbumKey() {
        let track = local("/music/a.flac", artist: " The Band ", album: "Greatest Hits")
        XCTAssertEqual(track.eqProfileScopes, [
            EQProfileScope(level: .track, source: "local", key: "/music/a.flac"),
            EQProfileScope(level: .album, source: "local", key: "the band|greatest hits"),
            EQProfileScope(level: .artist, source: "local", key: "the band"),
        ])

        let plex = Track(url: URL(string: "http://server/a")!, title: "a", artist: "X", album: "Y",
                         plexRatingKey: "42", plexServerId: "srv1")
        XCTAssertEqual(plex.eqProfileScopes.first, EQProfileScope(level: .track, source: "plex:srv1", key: "42"))
        XCTAssertEqual(plex.eqProfileScopes.last, EQProfileScope(level: .artist, source: "plex:srv1", key: "x"))

        let cue = Track(url: URL(fileURLWithPath: "/music/live.flac"), title: "t", artist: "A", album: "B",
                        cueStartOffset: 120.5, cueSourceURL: URL(fileURLWithPath: "/music/live.flac"))
        XCTAssertEqual(cue.eqProfileScopes.first?.key, "/music/live.flac@120.5")

        let radio = RadioStation(name: "Station", url: URL(string: "http://radio.example/stream")!, genre: "Jazz").toTrack()
        XCTAssertEqual(radio.eqProfileScopes, [EQProfileScope(level: .track, source: "radio", key: "http://radio.example/stream")])

        let youtube = Track(url: URL(fileURLWithPath: "/tmp/video.m4a"), title: "v", artist: "Channel",
                            isYouTubeOrigin: true)
        XCTAssertEqual(youtube.eqProfileScopes, [
            EQProfileScope(level: .track, source: "youtube", key: "/tmp/video.m4a"),
            EQProfileScope(level: .artist, source: "youtube", key: "channel"),
        ])
    }

    // MARK: - Resolution

    /// In memory; the reload and unreadable-file tests open a file themselves.
    private func makeResolver() -> EQProfileResolver {
        EQProfileResolver(store: EQProfileStore(path: nil, defaults: defaults))
    }

    func testTrackBeatsAlbumBeatsArtist() {
        let profiles = makeResolver(), store = profiles.store
        let a = store.add(name: "A", curve: curve(3))!, b = store.add(name: "B", curve: curve(6))!
        let c = store.add(name: "C", curve: curve(9))!
        let track = local("/music/1.flac"), sibling = local("/music/2.flac")
        profiles.assign(.profile(a.id), level: .artist, tracks: [track])
        XCTAssertEqual(profiles.resolve(track)?.profile?.name, "A")
        profiles.assign(.profile(b.id), level: .album, tracks: [track])
        XCTAssertEqual(profiles.resolve(track)?.level, .album)
        profiles.assign(.profile(c.id), level: .track, tracks: [track])
        XCTAssertEqual(profiles.resolve(track)?.profile?.name, "C")
        XCTAssertEqual(profiles.resolve(sibling)?.profile?.name, "B")
    }

    func testOffStopsResolutionAndInheritFallsThrough() {
        let profiles = makeResolver()
        let a = profiles.store.add(name: "A", curve: curve(3))!
        let track = local("/music/1.flac")
        profiles.assign(.profile(a.id), level: .album, tracks: [track])
        profiles.assign(.off, level: .track, tracks: [track])
        XCTAssertNil(profiles.resolve(track)?.profile)
        XCTAssertEqual(profiles.resolve(track)?.level, .track)
        XCTAssertFalse(profiles.appliesProfile(to: track))
        XCTAssertEqual(profiles.queueTitle(for: track), track.playlistTitle)
        profiles.assign(nil, level: .track, tracks: [track])
        XCTAssertEqual(profiles.resolve(track)?.profile?.name, "A")
        XCTAssertTrue(profiles.appliesProfile(to: track), "a change invalidates the cached marker")
        XCTAssertEqual(profiles.queueTitle(for: track), "∿ \(track.playlistTitle)")
    }

    func testSameAlbumTitleUnderTwoArtistsStaysSeparate() {
        let profiles = makeResolver()
        let a = profiles.store.add(name: "A", curve: curve(3))!
        let one = local("/1.flac", artist: "One", album: "Greatest Hits")
        let two = local("/2.flac", artist: "Two", album: "Greatest Hits")
        profiles.assign(.profile(a.id), level: .album, tracks: [one])
        XCTAssertNotNil(profiles.resolve(one))
        XCTAssertNil(profiles.resolve(two))
    }

    func testCompilationAlbumAssignmentCoversEveryTrack() {
        let profiles = makeResolver()
        let a = profiles.store.add(name: "A", curve: curve(3))!
        let tracks = ["X", "Y", "Z"].map { (name: String) in local("/\(name).flac", artist: name, album: "Now 42") }
        profiles.assign(.profile(a.id), level: .album, tracks: tracks)
        XCTAssertTrue(tracks.allSatisfy { profiles.resolve($0)?.profile?.name == "A" })
    }

    func testDeletingAProfileDropsItsAssignments() {
        let profiles = makeResolver(), store = profiles.store
        let a = store.add(name: "A", curve: curve(3))!, b = store.add(name: "B", curve: curve(6))!
        let track = local("/1.flac")
        profiles.assign(.profile(b.id), level: .artist, tracks: [track])
        profiles.assign(.profile(a.id), level: .track, tracks: [track])
        store.delete(a.id)
        XCTAssertNil(profiles.assignment(at: .track, of: track))
        XCTAssertEqual(profiles.resolve(track)?.profile?.name, "B")
    }

    func testProfilesAndAssignmentsSurviveAReload() {
        let profiles = EQProfileResolver(store: EQProfileStore(path: storePath, defaults: defaults))
        let a = profiles.store.add(name: "A", curve: curve(5))!
        let track = local("/1.flac")
        profiles.assign(.profile(a.id), level: .track, tracks: [track])
        profiles.assign(.off, level: .artist, tracks: [track])

        let reloaded = EQProfileResolver(store: EQProfileStore(path: storePath, defaults: defaults))
        XCTAssertEqual(reloaded.store.profiles, [a])
        XCTAssertEqual(reloaded.assignment(at: .track, of: track), .profile(a.id))
        XCTAssertEqual(reloaded.assignment(at: .artist, of: track), .off)
    }

    func testAnUnreadableDatabaseIsNeverOverwritten() throws {
        let junk = Data("not a database".utf8)
        try junk.write(to: URL(fileURLWithPath: storePath))
        let profiles = EQProfileResolver(store: EQProfileStore(path: storePath, defaults: defaults))
        XCTAssertNil(profiles.store.add(name: "A", curve: curve(3)), "an unsaved profile is not handed back")
        profiles.assign(.off, level: .track, tracks: [local("/1.flac")])
        XCTAssertTrue(profiles.store.profiles.isEmpty)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: storePath)), junk)
    }

    func testPruneDropsOnlyLocalTrackAssignmentsWhoseFileIsGone() throws {
        let profiles = makeResolver()
        let a = profiles.store.add(name: "A", curve: curve(3))!
        let kept = directory.appendingPathComponent("kept.flac").path
        let gone = directory.appendingPathComponent("gone.flac").path
        try Data().write(to: URL(fileURLWithPath: kept))
        let tracks = [
            local(kept), local(gone),
            Track(url: URL(fileURLWithPath: kept), title: "cue", artist: "A", album: "B",
                  cueStartOffset: 60, cueSourceURL: URL(fileURLWithPath: kept)),
            local("/Volumes/NotMounted-\(UUID())/a.flac"),
            Track(url: URL(string: "http://server/a")!, title: "a", plexRatingKey: "42", plexServerId: "srv1"),
            Track(url: URL(fileURLWithPath: gone), title: "v", isYouTubeOrigin: true),
            RadioStation(name: "Station", url: URL(string: "http://radio.example/stream")!, genre: "Jazz").toTrack(),
        ]
        profiles.assign(.profile(a.id), level: .track, tracks: tracks)
        profiles.assign(.profile(a.id), level: .artist, tracks: [local(gone)])

        let pruned = expectation(description: "pruned")
        profiles.pruneMissingLocalTracks { pruned.fulfill() }
        wait(for: [pruned], timeout: 5)
        XCTAssertEqual(tracks.map { profiles.assignment(at: .track, of: $0) != nil },
                       [true, false, true, true, true, true, true])
        XCTAssertNotNil(profiles.assignment(at: .artist, of: local(gone)), "only track level is pruned")
    }

    func testAWMPRowsMarkerIsNotAQueueChange() {
        let plain = WMPPlaylistItemSnapshot(title: "t", artist: "a", duration: 1)
        var marked = plain
        marked.hasEQProfile = true
        XCTAssertNotEqual(plain, marked, "the surface redraws for a marker change")
        XCTAssertTrue([plain].isSameQueue(as: [marked]), "a marker change must not bump WMPObjectModel.queueGeneration")
        XCTAssertFalse([plain].isSameQueue(as: [plain, plain]))
    }

    func testControllerAppliesTheResolvedCurveAndNothingWhenProfilesAreOff() {
        let profiles = makeResolver(), store = profiles.store
        let a = store.add(name: "A", curve: curve(6))!
        let track = local("/1.flac")
        profiles.assign(.profile(a.id), level: .artist, tracks: [track])
        XCTAssertTrue(store.isEnabled, "on by default")

        let controller = EQProfileController(resolver: profiles)
        let unit = { controller.localNode.auAudioUnit as? EQProfileAudioUnit }
        controller.trackDidChange(track)
        XCTAssertEqual(unit()?.curve, curve(6))
        store.isEnabled = false
        XCTAssertNil(unit()?.curve)
        XCTAssertFalse(profiles.appliesProfile(to: track))
        controller.audition = curve(9)
        XCTAssertEqual(unit()?.curve, curve(9), "the Studio's edit is heard whatever the toggle")
        controller.audition = nil
        XCTAssertNil(unit()?.curve)
    }

    // MARK: - Kernel

    private func kernel(_ curve: EQCurve?, rate: Double, frames: Int) -> EQProfileKernel {
        let kernel = EQProfileKernel(maximumFrames: frames, sampleRate: rate)
        EQProfileCoefficients.design(curve, sampleRate: rate).withUnsafeBufferPointer { kernel.reset(with: $0.baseAddress!) }
        return kernel
    }

    func testFlatCurveIsBypassedAndLeftOnlyBoostLeavesRightUntouched() {
        XCTAssertTrue(kernel(nil, rate: 48000, frames: 16).isBypassed)
        XCTAssertTrue(kernel(.flat, rate: 48000, frames: 16).isBypassed)

        var leftOnly = EQCurve.flat
        leftOnly.left.bands[12] = 6
        let k = kernel(leftOnly, rate: 48000, frames: 1024)
        var left = (0..<1024).map { Float(sin(Double($0) * 0.05)) }, right = left
        let original = right
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in k.process(left: l.baseAddress!, right: r.baseAddress!, frames: 1024) }
        }
        XCTAssertEqual(right, original)
        XCTAssertNotEqual(left, original)
    }

    /// Faders mean what they say: the cascade lands within ±0.5 dB of every fader at every centre.
    func testResponseMeetsEveryFaderAtEveryCentre() {
        var generator = SystemRandomNumberGenerator()
        let alternating = (0..<31).map { Float($0 % 2 == 0 ? 12 : -12) }
        var lone20k = [Float](repeating: 0, count: 31)
        lone20k[30] = 12
        for rate in [44100.0, 48000, 96000, 192000] {
            var curves = [alternating, lone20k]
            for _ in 0..<10 { curves.append((0..<31).map { _ in Float.random(in: -12...12, using: &generator) }) }
            for faders in curves {
                let sections = EQProfileDesign.sections(for: faders, sampleRate: rate)
                for band in 0..<EQProfileDesign.usableBandCount(sampleRate: rate) {
                    let response = EQProfileDesign.responseDB(sections, frequency: EQProfileDesign.frequencies[band], sampleRate: rate)
                    XCTAssertEqual(response, Double(faders[band]), accuracy: 0.5, "band \(band) at \(rate) Hz")
                }
            }
        }
    }

    /// The same, measured: an impulse through the render kernel, its spectrum at each centre.
    func testImpulseThroughTheKernelMatchesTheFaders() {
        let rate = 48000.0, n = 1 << 16
        let faders = (0..<31).map { Float(($0 * 7) % 25) - 12 }
        let k = kernel(EQCurve(left: .init(bands: faders, preamp: 0), right: .init(bands: faders, preamp: 0)), rate: rate, frames: n)
        var impulse = [Float](repeating: 0, count: n)
        impulse[0] = 1
        impulse.withUnsafeMutableBufferPointer { k.process(left: $0.baseAddress!, right: nil, frames: n) }
        for band in 0..<31 {
            let w = 2 * Double.pi * EQProfileDesign.frequencies[band] / rate
            var re = 0.0, im = 0.0
            for i in 0..<n {
                re += Double(impulse[i]) * cos(w * Double(i))
                im -= Double(impulse[i]) * sin(w * Double(i))
            }
            XCTAssertEqual(10 * log10(re * re + im * im), Double(faders[band]), accuracy: 0.5, "band \(band)")
        }
    }

    func testTwentyHertzBoostAt192kHzStaysStable() {
        var lone20 = [Float](repeating: 0, count: 31)
        lone20[0] = 12
        let n = 1 << 20
        let k = kernel(EQCurve(left: .init(bands: lone20, preamp: 0), right: .init(bands: lone20, preamp: 0)), rate: 192000, frames: n)
        var impulse = [Float](repeating: 0, count: n)
        impulse[0] = 1
        impulse.withUnsafeMutableBufferPointer { k.process(left: $0.baseAddress!, right: nil, frames: n) }
        XCTAssertLessThan(impulse.suffix(4096).map(abs).max() ?? 1, 1e-9)
    }

    /// No click on change: across a crossfade no sample steps further than the signal's own slope.
    func testCoefficientChangeShowsNoStep() {
        let rate = 48000.0, block = 512
        var cut = EQCurve.flat, boost = EQCurve.flat
        cut.left.bands[17] = -12
        boost.left.bands[17] = 12
        let k = kernel(cut, rate: rate, frames: block)
        let next = EQProfileCoefficients.design(boost, sampleRate: rate)
        var output: [Float] = []
        for index in 0..<80 {
            if index == 40 { next.withUnsafeBufferPointer { k.stage($0.baseAddress!) } }
            var buffer = (0..<block).map { Float(0.05 * sin(2 * Double.pi * 1000 * Double(index * block + $0) / rate)) }
            buffer.withUnsafeMutableBufferPointer { k.process(left: $0.baseAddress!, right: nil, frames: block) }
            output += buffer
        }
        let steps = zip(output.dropFirst(), output).map { abs($0 - $1) }
        let duringChange = steps[(40 * block - 200)..<(40 * block + 1000)].max()!
        let settled = steps[(60 * block)...].max()!
        XCTAssertLessThanOrEqual(duringChange, settled * 1.001)
    }
}
