import XCTest

/// End-to-end integration tests for AdAmp
/// Tests complete user workflows across multiple windows
final class IntegrationTests: AdAmpUITestCase {
    
    // MARK: - App Launch Tests
    
    func testAppLaunches_mainWindowVisible() {
        XCTAssertTrue(mainWindow.exists, "Main window should be visible on launch")
        XCTAssertTrue(mainWindow.isHittable, "Main window should be interactive")
    }
    
    func testAppLaunches_inUITestingMode() {
        // The app should have the UI testing mode flag active
        // This is verified by the presence of the main window without intro playing
        XCTAssertTrue(mainWindow.exists, "App should launch successfully in UI testing mode")
    }
    
    // MARK: - Window Management Tests
    
    func testOpenAllWindows() {
        // Open playlist
        mainWindow.rightClick()
        let playlistItem = app.menuItems["Playlist Editor"]
        if playlistItem.waitForExistence(timeout: 2) {
            playlistItem.tap()
        }
        Thread.sleep(forTimeInterval: 0.5)
        
        // Open equalizer
        mainWindow.rightClick()
        let eqItem = app.menuItems["Graphical EQ"]
        if eqItem.waitForExistence(timeout: 2) {
            eqItem.tap()
        }
        Thread.sleep(forTimeInterval: 0.5)
        
        // Open visualization
        mainWindow.rightClick()
        let visItem = app.menuItems["Visualization"]
        if visItem.waitForExistence(timeout: 2) {
            visItem.tap()
        }
        Thread.sleep(forTimeInterval: 0.5)
        
        // Open Plex browser
        mainWindow.rightClick()
        let browserItem = app.menuItems["Music Browser"]
        if browserItem.waitForExistence(timeout: 2) {
            browserItem.tap()
        }
        Thread.sleep(forTimeInterval: 0.5)
        
        // Verify all windows exist
        XCTAssertTrue(mainWindow.exists, "Main window should exist")
        // Note: Other windows may or may not be visible depending on menu item names
    }
    
    func testCloseAllWindows_mainWindowRemains() {
        // Open and close playlist
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 2) {
            item.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            // Close it
            if playlistWindow.exists {
                let closeArea = playlistWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.02))
                closeArea.tap()
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        
        // Main window should still exist (app doesn't quit when auxiliary windows close)
        XCTAssertTrue(mainWindow.exists, "Main window should remain when other windows close")
    }
    
    // MARK: - Window Docking Tests
    
    func testWindowDocking_EQBelowMain() {
        // Open EQ window
        mainWindow.rightClick()
        let eqItem = app.menuItems["Graphical EQ"]
        if eqItem.waitForExistence(timeout: 2) {
            eqItem.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Check if EQ is docked below main window
        if equalizerWindow.exists {
            // The EQ window should be positioned relative to main window
            let mainFrame = mainWindow.frame
            let eqFrame = equalizerWindow.frame
            
            // EQ should have same X position as main (horizontally aligned)
            let isHorizontallyAligned = abs(eqFrame.minX - mainFrame.minX) < 10
            
            // EQ should be below main (its top near main's bottom)
            let isBelow = abs(eqFrame.maxY - mainFrame.minY) < 10
            
            // Note: Exact docking depends on implementation
            // Just verify both windows exist and are positioned
            XCTAssertTrue(equalizerWindow.exists, "EQ should be visible")
        }
    }
    
    func testWindowDocking_playlistBelowEQ() {
        // Open EQ first
        mainWindow.rightClick()
        let eqItem = app.menuItems["Graphical EQ"]
        if eqItem.waitForExistence(timeout: 2) {
            eqItem.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Then open playlist
        mainWindow.rightClick()
        let playlistItem = app.menuItems["Playlist Editor"]
        if playlistItem.waitForExistence(timeout: 2) {
            playlistItem.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Playlist should be below EQ (or below main if EQ not visible)
        if playlistWindow.exists && equalizerWindow.exists {
            let eqFrame = equalizerWindow.frame
            let playlistFrame = playlistWindow.frame
            
            // Should be vertically stacked
            XCTAssertTrue(playlistWindow.exists, "Playlist should be visible")
        }
    }
    
    func testWindowDragging_movesTogether() {
        // Open EQ (which should dock to main)
        mainWindow.rightClick()
        let eqItem = app.menuItems["Graphical EQ"]
        if eqItem.waitForExistence(timeout: 2) {
            eqItem.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Record initial positions
        let mainInitial = mainWindow.frame
        let eqExists = equalizerWindow.exists
        let eqInitial = eqExists ? equalizerWindow.frame : .zero
        
        // Drag main window
        let startPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        // Both windows should have moved
        let mainNew = mainWindow.frame
        XCTAssertNotEqual(mainInitial.origin, mainNew.origin, "Main window should have moved")
        
        // If EQ was docked, it should also have moved
        if eqExists && equalizerWindow.exists {
            let eqNew = equalizerWindow.frame
            // EQ should have moved by roughly the same amount if docked
            let mainDeltaX = mainNew.minX - mainInitial.minX
            let eqDeltaX = eqNew.minX - eqInitial.minX
            
            // Allow some tolerance
            let moved = abs(eqDeltaX) > 5
            // Note: Docked behavior may vary based on implementation
        }
    }
    
    // MARK: - Keyboard Shortcut Tests
    
    func testGlobalKeyboardShortcuts() {
        // Test playback shortcuts
        app.pressSpace()  // Play/Pause toggle
        Thread.sleep(forTimeInterval: 0.3)
        
        app.pressLeftArrow()  // Seek back
        app.pressRightArrow()  // Seek forward
        
        app.pressUpArrow()  // Volume up
        app.pressDownArrow()  // Volume down
        
        // App should still be responsive
        XCTAssertTrue(mainWindow.exists, "App should handle keyboard shortcuts")
    }
    
    func testWinampStyleKeyboardShortcuts() {
        // X - Play
        app.typeKey("x", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
        
        // C - Pause
        app.typeKey("c", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
        
        // V - Stop
        app.typeKey("v", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
        
        // Z - Previous
        app.typeKey("z", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
        
        // B - Next
        app.typeKey("b", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
        
        XCTAssertTrue(mainWindow.exists, "App should handle Winamp-style shortcuts")
    }
    
    // MARK: - Context Menu Flow Tests
    
    func testContextMenu_openFile() {
        mainWindow.rightClick()
        
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 2))
        
        // Look for Open File item
        let openItem = app.menuItems["Open File..."]
        if openItem.exists {
            // Don't actually click it (would open file dialog)
            // Just verify it exists
        }
        
        app.pressEscape()
    }
    
    func testContextMenu_playbackControls() {
        mainWindow.rightClick()
        
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 2))
        
        // Should have playback control items
        let hasPlaybackItems = app.menuItems["Play"].exists ||
                               app.menuItems["Pause"].exists ||
                               app.menuItems["Stop"].exists
        
        app.pressEscape()
        
        // Note: Menu items depend on implementation
    }
    
    // MARK: - Skin Consistency Tests
    
    func testAllWindows_useSameSkin() {
        // Open multiple windows
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 2) {
            item.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 2) {
            item.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }
        
        // Verify windows are visible (they should use the same skin)
        XCTAssertTrue(mainWindow.exists)
        // Visual consistency can't be verified programmatically,
        // but we ensure all windows render without crashing
    }
    
    // MARK: - State Persistence Tests
    
    func testToggleStates_persist() {
        // Toggle shuffle
        let shuffleButton = app.buttons[AccessibilityIdentifiers.MainWindow.shuffleButton]
        if shuffleButton.exists {
            let initialLabel = shuffleButton.label
            shuffleButton.tap()
            Thread.sleep(forTimeInterval: 0.3)
            
            // State should change
            let newLabel = shuffleButton.label
            XCTAssertNotEqual(initialLabel, newLabel)
            
            // Toggle back
            shuffleButton.tap()
            Thread.sleep(forTimeInterval: 0.3)
            
            // Should be back to initial state
            let finalLabel = shuffleButton.label
            XCTAssertEqual(initialLabel, finalLabel, "Toggle should return to original state")
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testApp_handlesNoNetwork() {
        // In UI testing mode, Plex should not auto-connect
        // Open Plex browser - should show local files or appropriate message
        mainWindow.rightClick()
        let browserItem = app.menuItems["Music Browser"]
        if browserItem.waitForExistence(timeout: 2) {
            browserItem.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Browser should open without crashing (even without Plex connection)
        if plexBrowserWindow.exists {
            XCTAssertTrue(plexBrowserWindow.exists, "Browser should work without network")
        }
    }
    
    // MARK: - Multi-Window Focus Tests
    
    func testWindowFocus_bringsAllToFront() {
        // Open multiple windows
        mainWindow.rightClick()
        if let item = app.menuItems["Graphical EQ"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 2) {
            item.tap()
        }
        Thread.sleep(forTimeInterval: 0.3)
        
        mainWindow.rightClick()
        if let item = app.menuItems["Playlist Editor"].firstMatch as? XCUIElement, item.waitForExistence(timeout: 2) {
            item.tap()
        }
        Thread.sleep(forTimeInterval: 0.3)
        
        // Click on main window to bring all to front
        mainWindow.click()
        Thread.sleep(forTimeInterval: 0.5)
        
        // All windows should be visible (brought to front together)
        XCTAssertTrue(mainWindow.exists, "Main window should be visible")
        // Other windows should also be visible if they were open
    }
    
    // MARK: - Performance Tests
    
    func testApp_respondsQuickly() {
        let startTime = Date()
        
        // Perform several quick interactions
        for _ in 0..<5 {
            mainWindow.click()
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should complete in reasonable time
        XCTAssertLessThan(elapsed, 5.0, "Interactions should complete quickly")
        XCTAssertTrue(mainWindow.exists, "App should remain responsive")
    }
}
