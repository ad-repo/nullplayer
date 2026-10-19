import AVFoundation
import XCTest
@testable import NullPlayer

final class EQCastCacheTests: XCTestCase {
    private var directory: URL!
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("EQCastCacheTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaultsSuite = "EQCastCacheTests-\(UUID())"
        UserDefaults.standard.set(true, forKey: EQCastCache.enabledKey)
        UserDefaults.standard.set(directory.appendingPathComponent("cache").path, forKey: EQCastCache.folderKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: EQCastCache.enabledKey)
        UserDefaults.standard.removeObject(forKey: EQCastCache.folderKey)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: directory)
    }

    /// A +12 dB band renders to a 16-bit FLAC the second lookup reuses; a curve edit invalidates it,
    /// and Delete Cache keeps the file being cast.
    func testRenderReuseAndInvalidate() async throws {
        let wav = directory.appendingPathComponent("tone.wav")
        try TestAudioFile.writeWAV(to: wav, seconds: 1, tone: true)
        let store = EQProfileStore(path: nil, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        var curve = EQCurve.flat
        curve.left.bands[10] = 12
        curve.right.bands[10] = 12
        let profile = try XCTUnwrap(store.add(name: "Boost", curve: curve))
        let track = Track(url: wav)
        store.assign(.profile(profile.id), scopes: [try XCTUnwrap(track.eqProfileScopes.first)])
        let cache = EQCastCache(store: store)

        let before = await cache.cached(track, device: .chromecast)
        XCTAssertEqual(before, .needsRender)
        let rendered = await cache.render(track)
        let file = try XCTUnwrap(rendered)
        XCTAssertEqual(file.pathExtension, "flac")

        let output = try AVAudioFile(forReading: file)
        XCTAssertEqual(output.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatFLAC)
        XCTAssertEqual(output.fileFormat.streamDescription.pointee.mFormatFlags, kAppleLosslessFormatFlag_16BitSourceData)
        XCTAssertEqual(output.fileFormat.sampleRate, 48_000)
        XCTAssertEqual(output.length, 48_000)
        let after = await cache.cached(track, device: .chromecast)
        XCTAssertEqual(after, .hit(file))

        curve.left.bands[10] = 6
        store.update(profile.id, curve: curve)
        let edited = await cache.cached(track, device: .chromecast)
        XCTAssertEqual(edited, .needsRender)

        await cache.deleteCache(keeping: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    /// No profile, no render: the original is cast.
    func testTrackWithoutProfileIsSkipped() async throws {
        let wav = directory.appendingPathComponent("plain.wav")
        try TestAudioFile.writeWAV(to: wav)
        let store = EQProfileStore(path: nil, defaults: try XCTUnwrap(UserDefaults(suiteName: defaultsSuite)))
        let lookup = await EQCastCache(store: store).cached(Track(url: wav), device: .chromecast)
        XCTAssertEqual(lookup, .skip)
    }
}
