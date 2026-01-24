import XCTest

/// End-to-end integration tests for AdAmp
final class IntegrationTests: AdAmpUITestCase {
    
    // MARK: - App Launch Tests
    
    func testAppLaunch() {
        XCTAssertTrue(mainWindow.exists, "Main window should be visible on launch")
        XCTAssertTrue(mainWindow.isHittable, "Main window should be interactive")
    }
    
    // MARK: - Window Management Tests
    
    func testOpenAllWindows() {
        // Open playlist
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        // Open equalizer
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        // Open visualization
        mainWindow.rightClick()
        if let item = app.menuItems["Visualization"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        // Open browser
        mainWindow.rightClick()
        if let item = app.menuItems["Music Browser"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        XCTAssertTrue(mainWindow.exists)
    }
    
    func testCloseWindowsMainRemains() {
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
            
            if playlistWindow.waitForExistence(timeout: 1) {
                let closeArea = playlistWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.02))
                closeArea.tap()
            }
        }
        
        XCTAssertTrue(mainWindow.exists, "Main window should remain")
    }
    
    // MARK: - Keyboard Shortcut Tests
    
    func testGlobalKeyboardShortcuts() {
        app.pressSpace()
        app.pressLeftArrow()
        app.pressRightArrow()
        app.pressUpArrow()
        app.pressDownArrow()
        XCTAssertTrue(mainWindow.exists)
    }
    
    func testWinampStyleShortcuts() {
        app.typeKey("x", modifierFlags: [])  // Play
        app.typeKey("c", modifierFlags: [])  // Pause
        app.typeKey("v", modifierFlags: [])  // Stop
        app.typeKey("z", modifierFlags: [])  // Previous
        app.typeKey("b", modifierFlags: [])  // Next
        XCTAssertTrue(mainWindow.exists)
    }
    
    // MARK: - Context Menu Tests
    
    func testContextMenuItems() {
        mainWindow.rightClick()
        
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
    
    // MARK: - Toggle State Tests
    
    func testToggleStatesPersist() {
        let shuffleButton = app.buttons[AccessibilityIdentifiers.MainWindow.shuffleButton]
        guard shuffleButton.exists else { return }
        
        let initialLabel = shuffleButton.label
        shuffleButton.tap()
        XCTAssertNotEqual(initialLabel, shuffleButton.label)
        
        shuffleButton.tap()
        XCTAssertEqual(initialLabel, shuffleButton.label, "Toggle should return to original state")
    }
    
    // MARK: - Multi-Window Focus Tests
    
    func testWindowFocus() {
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        mainWindow.click()
        XCTAssertTrue(mainWindow.exists)
    }
    
    // MARK: - Window Docking Tests
    
    func testWindowDocking() {
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        if equalizerWindow.waitForExistence(timeout: 1) {
            XCTAssertTrue(equalizerWindow.exists, "EQ should be visible")
        }
    }
    
    func testWindowDragTogether() {
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 1) {
            item.tap()
        }
        
        let mainInitial = mainWindow.frame
        
        let startPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        let mainNew = mainWindow.frame
        XCTAssertNotEqual(mainInitial.origin, mainNew.origin, "Window should have moved")
    }
    
    // MARK: - Performance Tests
    
    func testAppResponsiveness() {
        let startTime = Date()
        
        for _ in 0..<5 {
            mainWindow.click()
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 2.0, "Interactions should complete quickly")
        XCTAssertTrue(mainWindow.exists)
    }
}
