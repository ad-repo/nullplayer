import XCTest
@testable import NullPlayer

/// **A `<PLAYLIST playlistItemsVisible="false">` picker keeps one row per queue row.** WMP 9 Redux's
/// top-right `plDropDown` drifted off its playlist by one row for every repeated track name,
/// because `NSPopUpButton.addItems(withTitles:)` drops duplicate titles — so the picker showed the
/// wrong current track, and choosing a row played a different one.
@MainActor
final class WMPDropdownPlaylistTests: XCTestCase {
    func testRepeatedTrackNamesKeepThePickerOnTheQueuesRows() {
        func item(_ title: String) -> WMPPlaylistItemSnapshot {
            WMPPlaylistItemSnapshot(title: title, artist: "Artist", duration: 60)
        }
        var snapshot = WMPHostSnapshot()
        snapshot.playlistItems = [item("A"), item("B"), item("A"), item("C")]
        snapshot.playlistIndex = 3

        let picker = WMPDropdownPlaylistSurfaceView(frame: .zero, pullsDown: false)
        var played: Int?
        picker.onAction = { action, _ in
            if case let .playPlaylistItem(index) = action { played = index }
        }
        picker.update(snapshot)

        XCTAssertEqual(picker.numberOfItems, 4, "one row per queue row, repeats included")
        XCTAssertEqual(picker.indexOfSelectedItem, 3, "the current track, not the one after it")

        picker.selectItem(at: 2)
        picker.sendAction(picker.action, to: picker.target)
        XCTAssertEqual(played, 2, "choosing the second \"A\" plays the second \"A\"")
    }
}
