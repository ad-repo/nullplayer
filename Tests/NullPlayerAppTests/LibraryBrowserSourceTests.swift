import XCTest
@testable import NullPlayer

/// The browser's source is persisted under `"BrowserSource"` (also read by the `.wmz` library
/// catalog), so the key and the JSON the pre-merge enums wrote must keep loading.
final class LibraryBrowserSourceTests: XCTestCase {
    private let key = "BrowserSource"
    private var saved: Data?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.data(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.set(saved, forKey: key)
        super.tearDown()
    }

    func testLoadsEveryCaseSavedByThePreMergeEnums() {
        let written: [(String, LibraryBrowserSource)] = [
            (#"{"local":{}}"#, .local),
            (#"{"plex":{"serverId":"p1"}}"#, .plex(serverId: "p1")),
            (#"{"subsonic":{"serverId":"s1"}}"#, .subsonic(serverId: "s1")),
            (#"{"jellyfin":{"serverId":"j1"}}"#, .jellyfin(serverId: "j1")),
            (#"{"emby":{"serverId":"e1"}}"#, .emby(serverId: "e1")),
            (#"{"radio":{}}"#, .radio),
            (#"{"youtube":{}}"#, .youtube),
        ]
        for (json, source) in written {
            UserDefaults.standard.set(Data(json.utf8), forKey: key)
            XCTAssertEqual(LibraryBrowserSource.load(), source, json)
        }
    }

    func testSavesUnderTheBrowserSourceKey() throws {
        LibraryBrowserSource.jellyfin(serverId: "j1").save()
        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: key))
        XCTAssertEqual(try JSONDecoder().decode(LibraryBrowserSource.self, from: data), .jellyfin(serverId: "j1"))
    }
}
