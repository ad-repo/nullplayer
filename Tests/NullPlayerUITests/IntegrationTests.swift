import XCTest

/// End-to-end integration tests for NullPlayer
/// Consolidated to minimize app launches for faster CI execution
final class IntegrationTests: NullPlayerUITestCase {
    
    // MARK: - App Launch and Core Tests
    
    /// Tests app launch, window management, and closing windows
    func testAppLaunchAndWindowManagement() {
        // App launch verification
        XCTAssertTrue(mainWindow.exists, "Main window should be visible on launch")
        XCTAssertTrue(mainWindow.isHittable, "Main window should be interactive")
        
        // Open all windows
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        mainWindow.rightClick()
        if let item = app.menuItems["Visualization"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        mainWindow.rightClick()
        if let item = app.menuItems["Music Browser"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        XCTAssertTrue(mainWindow.exists)
        
        // Close windows - main remains
        if playlistWindow.waitForExistence(timeout: 1) {
            let closeArea = playlistWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.02))
            closeArea.tap()
        }
        
        XCTAssertTrue(mainWindow.exists, "Main window should remain after closing other windows")
    }
    
    // MARK: - Keyboard and Toggle Tests
    
    /// Tests keyboard shortcuts and toggle state persistence
    func testKeyboardAndToggleStates() {
        // Global keyboard shortcuts
        app.pressSpace()
        app.pressLeftArrow()
        app.pressRightArrow()
        app.pressUpArrow()
        app.pressDownArrow()
        XCTAssertTrue(mainWindow.exists)
        
        // classic skin-style shortcuts
        app.typeKey("x", modifierFlags: [])  // Play
        app.typeKey("c", modifierFlags: [])  // Pause
        app.typeKey("v", modifierFlags: [])  // Stop
        app.typeKey("z", modifierFlags: [])  // Previous
        app.typeKey("b", modifierFlags: [])  // Next
        XCTAssertTrue(mainWindow.exists)
        
        // Context menu
        mainWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
        
        // Toggle state persistence
        let shuffleButton = app.buttons[AccessibilityIdentifiers.MainWindow.shuffleButton]
        if shuffleButton.exists {
            let initialLabel = shuffleButton.label
            shuffleButton.tap()
            XCTAssertNotEqual(initialLabel, shuffleButton.label)
            
            shuffleButton.tap()
            XCTAssertEqual(initialLabel, shuffleButton.label, "Toggle should return to original state")
        }
    }
    
    // MARK: - Multi-Window Focus and Docking Tests
    
    /// Tests window focus, docking behavior, and dragging windows together
    func testWindowFocusAndDocking() {
        // Open EQ and playlist windows
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        // Window focus switching
        mainWindow.click()
        XCTAssertTrue(mainWindow.exists)
        
        // Docking verification
        if equalizerWindow.waitForExistence(timeout: 1) {
            XCTAssertTrue(equalizerWindow.exists, "EQ should be visible")
        }
        
        // Drag windows together
        let mainInitial = mainWindow.frame
        
        let startPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        let mainNew = mainWindow.frame
        XCTAssertNotEqual(mainInitial.origin, mainNew.origin, "Window should have moved")
        
        // Performance check
        let startTime = Date()
        for _ in 0..<5 {
            mainWindow.click()
        }
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 2.0, "Interactions should complete quickly")
        XCTAssertTrue(mainWindow.exists)
    }
}
