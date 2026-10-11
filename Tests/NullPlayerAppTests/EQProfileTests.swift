import AVFoundation
import XCTest
@testable import NullPlayer

final class EQProfileTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("eq_profiles.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EQProfileTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func local(_ path: String, artist: String? = "Artist", album: String? = "Album") -> Track {
        Track(url: URL(fileURLWithPath: path), title: path, artist: artist, album: album)
    }

    private func curve(_ gain: Float) -> EQCurve {
        var curve = EQCurve.flat
        curve.left[10] = gain
        curve.right[10] = gain
        return curve
    }

    // MARK: - Keys

    func testKeysAreScopedBySourceAndCarryTheArtistOnTheAlbumKey() {
        let track = local("/music/a.flac", artist: " The Band ", album: "Greatest Hits")
        XCTAssertEqual(track.eqProfileKeys.map(\.key), [
            "track|local|/music/a.flac",
            "album|local|the band|greatest hits",
            "artist|local|the band",
        ])

        let plex = Track(url: URL(string: "http://server/a")!, title: "a", artist: "X", album: "Y",
                         plexRatingKey: "42", plexServerId: "srv1")
        XCTAssertEqual(plex.eqProfileKeys.first?.key, "track|plex:srv1|42")
        XCTAssertEqual(plex.eqProfileKeys.last?.key, "artist|plex:srv1|x")

        let cue = Track(url: URL(fileURLWithPath: "/music/live.flac"), title: "t", artist: "A", album: "B",
                        cueStartOffset: 120.5, cueSourceURL: URL(fileURLWithPath: "/music/live.flac"))
        XCTAssertEqual(cue.eqProfileKeys.first?.key, "track|local|/music/live.flac@120.5")

        let radio = RadioStation(name: "Station", url: URL(string: "http://radio.example/stream")!, genre: "Jazz").toTrack()
        XCTAssertEqual(radio.eqProfileKeys.map(\.key), ["track|radio|http://radio.example/stream"])

        let youtube = Track(url: URL(fileURLWithPath: "/tmp/video.m4a"), title: "v", artist: "Channel",
                            isYouTubeOrigin: true)
        XCTAssertEqual(youtube.eqProfileKeys.map(\.key), ["track|youtube|/tmp/video.m4a", "artist|youtube|channel"])
    }

    // MARK: - Resolution

    func testTrackBeatsAlbumBeatsArtist() {
        let store = EQProfileStore(url: storeURL)
        let a = store.add(name: "A", curve: curve(3)), b = store.add(name: "B", curve: curve(6))
        let c = store.add(name: "C", curve: curve(9))
        let track = local("/music/1.flac"), sibling = local("/music/2.flac")
        store.assign(.profile(a.id), level: .artist, tracks: [track])
        XCTAssertEqual(store.resolve(track)?.profile?.name, "A")
        store.assign(.profile(b.id), level: .album, tracks: [track])
        XCTAssertEqual(store.resolve(track)?.level, .album)
        store.assign(.profile(c.id), level: .track, tracks: [track])
        XCTAssertEqual(store.resolve(track)?.profile?.name, "C")
        XCTAssertEqual(store.resolve(sibling)?.profile?.name, "B")
    }

    func testOffStopsResolutionAndInheritFallsThrough() {
        let store = EQProfileStore(url: storeURL)
        let a = store.add(name: "A", curve: curve(3))
        let track = local("/music/1.flac")
        store.assign(.profile(a.id), level: .album, tracks: [track])
        store.assign(.off, level: .track, tracks: [track])
        XCTAssertNil(store.resolve(track)?.profile)
        XCTAssertEqual(store.resolve(track)?.level, .track)
        XCTAssertFalse(store.appliesProfile(to: track))
        store.assign(nil, level: .track, tracks: [track])
        XCTAssertEqual(store.resolve(track)?.profile?.name, "A")
        XCTAssertTrue(store.appliesProfile(to: track))
    }

    func testSameAlbumTitleUnderTwoArtistsStaysSeparate() {
        let store = EQProfileStore(url: storeURL)
        let a = store.add(name: "A", curve: curve(3))
        let one = local("/1.flac", artist: "One", album: "Greatest Hits")
        let two = local("/2.flac", artist: "Two", album: "Greatest Hits")
        store.assign(.profile(a.id), level: .album, tracks: [one])
        XCTAssertNotNil(store.resolve(one))
        XCTAssertNil(store.resolve(two))
    }

    func testCompilationAlbumAssignmentCoversEveryTrack() {
        let store = EQProfileStore(url: storeURL)
        let a = store.add(name: "A", curve: curve(3))
        let tracks = ["X", "Y", "Z"].map { (name: String) in local("/\(name).flac", artist: name, album: "Now 42") }
        store.assign(.profile(a.id), level: .album, tracks: tracks)
        XCTAssertTrue(tracks.allSatisfy { store.resolve($0)?.profile?.name == "A" })
    }

    func testDeletingAProfileDropsItsAssignments() {
        let store = EQProfileStore(url: storeURL)
        let a = store.add(name: "A", curve: curve(3)), b = store.add(name: "B", curve: curve(6))
        let track = local("/1.flac")
        store.assign(.profile(b.id), level: .artist, tracks: [track])
        store.assign(.profile(a.id), level: .track, tracks: [track])
        store.delete(a.id)
        XCTAssertNil(store.assignment(at: .track, of: track))
        XCTAssertEqual(store.resolve(track)?.profile?.name, "B")
    }

    func testProfilesAndAssignmentsSurviveAReload() {
        let store = EQProfileStore(url: storeURL)
        let a = store.add(name: "A", curve: curve(5))
        let track = local("/1.flac")
        store.assign(.profile(a.id), level: .track, tracks: [track])
        store.assign(.off, level: .artist, tracks: [track])

        let reloaded = EQProfileStore(url: storeURL)
        XCTAssertEqual(reloaded.profiles, [a])
        XCTAssertEqual(reloaded.assignment(at: .track, of: track), .profile(a.id))
        XCTAssertEqual(reloaded.assignment(at: .artist, of: track), .off)
    }

    func testControllerAppliesTheResolvedCurveAndNothingWhenProfilesAreOff() {
        let store = EQProfileStore(url: storeURL)
        let a = store.add(name: "A", curve: curve(6))
        let track = local("/1.flac")
        store.assign(.profile(a.id), level: .artist, tracks: [track])
        let wasEnabled = store.isEnabled
        defer { store.isEnabled = wasEnabled }
        store.isEnabled = true

        let controller = EQProfileController(store: store)
        let unit = { controller.localNode.auAudioUnit as? EQProfileAudioUnit }
        controller.trackDidChange(track)
        XCTAssertEqual(unit()?.curve, curve(6))
        store.isEnabled = false
        XCTAssertNil(unit()?.curve)
        XCTAssertFalse(store.appliesProfile(to: track))
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
        leftOnly.left[12] = 6
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
        let k = kernel(EQCurve(left: faders, right: faders, preampL: 0, preampR: 0), rate: rate, frames: n)
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
        let k = kernel(EQCurve(left: lone20, right: lone20, preampL: 0, preampR: 0), rate: 192000, frames: n)
        var impulse = [Float](repeating: 0, count: n)
        impulse[0] = 1
        impulse.withUnsafeMutableBufferPointer { k.process(left: $0.baseAddress!, right: nil, frames: n) }
        XCTAssertLessThan(impulse.suffix(4096).map(abs).max() ?? 1, 1e-9)
    }

    /// No click on change: across a crossfade no sample steps further than the signal's own slope.
    func testCoefficientChangeShowsNoStep() {
        let rate = 48000.0, block = 512
        var cut = EQCurve.flat, boost = EQCurve.flat
        cut.left[17] = -12
        boost.left[17] = 12
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
