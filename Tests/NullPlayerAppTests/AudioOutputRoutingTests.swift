import XCTest
@testable import NullPlayer

final class AudioOutputRoutingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AudioOutputRoutingTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCanonicalPersistenceReadWrite() {
        defaults.set("coreaudio:uid-1", forKey: AudioOutputManager.savedDevicePersistentIDKey)

        let resolved = AudioOutputManager.resolvePersistedOutputDevicePersistentID(
            defaults: defaults,
            availablePersistentIDs: ["coreaudio:uid-1", "coreaudio:uid-2"]
        )

        XCTAssertEqual(resolved, "coreaudio:uid-1")
        XCTAssertEqual(defaults.string(forKey: AudioOutputManager.savedDevicePersistentIDKey), "coreaudio:uid-1")
    }

    func testMigratesLegacySelectedOutputDeviceUIDKey() {
        defaults.set("legacy:uid-a", forKey: "selectedOutputDeviceUID")

        let resolved = AudioOutputManager.resolvePersistedOutputDevicePersistentID(
            defaults: defaults,
            availablePersistentIDs: ["legacy:uid-a"]
        )

        XCTAssertEqual(resolved, "legacy:uid-a")
        XCTAssertEqual(defaults.string(forKey: AudioOutputManager.savedDevicePersistentIDKey), "legacy:uid-a")
        XCTAssertNil(defaults.object(forKey: "selectedOutputDeviceUID"))
    }

    func testMigratesLegacySelectedAudioOutputDeviceUIDKey() {
        defaults.set("legacy:uid-b", forKey: "selectedAudioOutputDeviceUID")

        let resolved = AudioOutputManager.resolvePersistedOutputDevicePersistentID(
            defaults: defaults,
            availablePersistentIDs: ["legacy:uid-b"]
        )

        XCTAssertEqual(resolved, "legacy:uid-b")
        XCTAssertEqual(defaults.string(forKey: AudioOutputManager.savedDevicePersistentIDKey), "legacy:uid-b")
        XCTAssertNil(defaults.object(forKey: "selectedAudioOutputDeviceUID"))
    }

    func testMissingDeviceFallsBackToNilAndClearsCanonicalKey() {
        defaults.set("missing:uid", forKey: AudioOutputManager.savedDevicePersistentIDKey)

        let resolved = AudioOutputManager.resolvePersistedOutputDevicePersistentID(
            defaults: defaults,
            availablePersistentIDs: ["available:uid"]
        )

        XCTAssertNil(resolved)
        XCTAssertNil(defaults.object(forKey: AudioOutputManager.savedDevicePersistentIDKey))
    }
}
