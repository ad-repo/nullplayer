import XCTest

/// Tests for the playlist window
/// Consolidated to minimize app launches for faster CI execution
final class PlaylistTests: NullPlayerUITestCase {
    
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
    
    // MARK: - Window and Controls Test
    
    /// Tests playlist window existence, buttons, and keyboard shortcuts
    func testPlaylistWindowAndControls() {
        // Window existence
        XCTAssertTrue(playlistWindow.exists, "Playlist window should exist")
        XCTAssertTrue(playlistWindow.isHittable, "Playlist window should be hittable")
        
        // Test buttons
        let addButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.addButton]
        let removeButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.removeButton]
        let selectButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.selectButton]
        let miscButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.miscButton]
        let listButton = playlistWindow.buttons[AccessibilityIdentifiers.Playlist.listButton]
        
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
        
        // Keyboard shortcuts
        playlistWindow.click()
        app.typeShortcut("a", modifiers: .command)
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(playlistWindow.exists)
    }
    
    // MARK: - Interaction Test
    
    /// Tests scrolling, window drag, and context menu
    func testPlaylistInteractions() {
        // Scrolling
        playlistWindow.scroll(byDeltaX: 0, deltaY: -50)
        playlistWindow.scroll(byDeltaX: 0, deltaY: 50)
        XCTAssertTrue(playlistWindow.exists)
        
        // Window drag
        let startPoint = playlistWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = playlistWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(playlistWindow.exists)
        
        // Context menu
        playlistWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
}
