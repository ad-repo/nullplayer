import XCTest

/// Tests for the playlist window
final class PlaylistTests: AdAmpUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        if !playlistWindow.exists {
            mainWindow.rightClick()
            let playlistMenuItem = app.menuItems["Playlist Editor"]
            if playlistMenuItem.waitForExistence(timeout: 1) {
                playlistMenuItem.tap()
            }
            _ = waitForElement(playlistWindow, timeout: 1)
        }
    }
    
    // MARK: - Core Tests
    
    func testPlaylistWindow() {
        XCTAssertTrue(playlistWindow.exists, "Playlist window should exist")
        XCTAssertTrue(playlistWindow.isHittable, "Playlist window should be hittable")
    }
    
    func testPlaylistButtons() {
        let addButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.addButton]
        let removeButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.removeButton]
        let selectButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.selectButton]
        let miscButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.miscButton]
        let listButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.listButton]
        
        // Test each button that exists
        for button in [addButton, removeButton, selectButton, miscButton, listButton] {
            if button.exists {
                button.tap()
                let menu = app.menus.firstMatch
                if menu.waitForExistence(timeout: 0.5) {
                    app.pressEscape()
                }
            }
        }
        XCTAssertTrue(playlistWindow.exists)
    }
    
    func testKeyboardShortcuts() {
        playlistWindow.click()
        app.typeShortcut("a", modifiers: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(playlistWindow.exists)
    }
    
    func testScrolling() {
        playlistWindow.scroll(byDeltaX: 0, deltaY: -50)
        playlistWindow.scroll(byDeltaX: 0, deltaY: 50)
        XCTAssertTrue(playlistWindow.exists)
    }
    
    func testWindowDrag() {
        let startPoint = playlistWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = playlistWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(playlistWindow.exists)
    }
    
    func testContextMenu() {
        playlistWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
}
