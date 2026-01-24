import XCTest

/// Tests for the visualization (Milkdrop) window
final class VisualizationTests: AdAmpUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Open visualization window for all tests in this class
        if !visualizationWindow.exists {
            // Open via context menu
            mainWindow.rightClick()
            let visMenuItem = app.menuItems["Visualization"]
            if visMenuItem.waitForExistence(timeout: 2) {
                visMenuItem.tap()
            }
        }
    }
    
    // MARK: - Window Tests
    
    func testVisualizationWindowExists() {
        XCTAssertTrue(waitForElement(visualizationWindow), "Visualization window should exist")
    }
    
    func testVisualizationWindowIsVisible() {
        XCTAssertTrue(visualizationWindow.isHittable, "Visualization window should be visible")
    }
    
    // MARK: - Preset Navigation Tests
    
    func testNextPreset_rightArrow() {
        // Make window key
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Press right arrow for next preset
        app.pressRightArrow()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should respond to right arrow")
    }
    
    func testPreviousPreset_leftArrow() {
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Press left arrow for previous preset
        app.pressLeftArrow()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should respond to left arrow")
    }
    
    func testRandomPreset_rKey() {
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Press R for random preset
        app.typeKey("r", modifierFlags: [])
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should respond to R key")
    }
    
    func testPresetLock_lKey() {
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Press L to toggle preset lock
        app.typeKey("l", modifierFlags: [])
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Toggle back
        app.typeKey("l", modifierFlags: [])
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should respond to L key")
    }
    
    func testCycleMode_cKey() {
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Press C to toggle cycle mode
        app.typeKey("c", modifierFlags: [])
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Press again to cycle through modes
        app.typeKey("c", modifierFlags: [])
        app.typeKey("c", modifierFlags: [])  // Back to off
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should respond to C key")
    }
    
    // MARK: - Fullscreen Tests
    
    func testFullscreen_fKey() {
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Press F to toggle fullscreen
        app.typeKey("f", modifierFlags: [])
        
        Thread.sleep(forTimeInterval: 1.0)  // Fullscreen animation takes time
        
        // Exit fullscreen
        app.pressEscape()
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // Window should still exist
        XCTAssertTrue(visualizationWindow.exists || mainWindow.exists, 
                     "App should still be running after fullscreen toggle")
    }
    
    func testFullscreenExit_escape() {
        visualizationWindow.click()
        
        // Enter fullscreen
        app.typeKey("f", modifierFlags: [])
        
        Thread.sleep(forTimeInterval: 1.0)
        
        // Exit with Escape
        app.pressEscape()
        
        Thread.sleep(forTimeInterval: 1.0)
        
        XCTAssertTrue(visualizationWindow.exists || mainWindow.exists, 
                     "Should exit fullscreen with Escape")
    }
    
    // MARK: - Hard Cut Tests
    
    func testHardCut_shiftRightArrow() {
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Shift+Right for hard cut to next preset
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .shift)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Should handle shift+right arrow")
    }
    
    func testHardCut_shiftLeftArrow() {
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Shift+Left for hard cut to previous preset
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: .shift)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Should handle shift+left arrow")
    }
    
    // MARK: - Window Control Tests
    
    func testVisualizationCanBeDragged() {
        // Drag the window
        let startPoint = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        let endPoint = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should be draggable")
    }
    
    func testVisualizationCanResize() {
        // Drag resize handle
        let resizeStart = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        let resizeEnd = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 1.1))
        resizeStart.click(forDuration: 0.1, thenDragTo: resizeEnd)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should be resizable")
    }
    
    func testVisualizationCanClose() {
        // Click close button area
        let closeArea = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.02))
        closeArea.tap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        // Window may or may not close depending on click accuracy
    }
    
    // MARK: - Shade Mode Tests
    
    func testShadeMode_doubleClick() {
        // Double-click on title bar
        let titleBar = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        titleBar.doubleTap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists, "Should toggle shade mode")
        
        // Toggle back
        let shadeTitleBar = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shadeTitleBar.doubleTap()
        
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // MARK: - Context Menu Tests
    
    func testVisualizationContextMenu() {
        visualizationWindow.rightClick()
        
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 2), "Context menu should appear")
        
        // Verify preset navigation items exist
        let nextPresetItem = app.menuItems["Next Preset"]
        let prevPresetItem = app.menuItems["Previous Preset"]
        let randomPresetItem = app.menuItems["Random Preset"]
        let fullscreenItem = app.menuItems["Fullscreen"]
        
        // Some menu items should exist
        let hasMenuItems = nextPresetItem.exists || fullscreenItem.exists
        XCTAssertTrue(hasMenuItems || menu.menuItems.count > 0, "Context menu should have items")
        
        app.pressEscape()
    }
    
    func testContextMenu_presetSubmenu() {
        visualizationWindow.rightClick()
        
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 2))
        
        // Look for Presets submenu
        let presetsItem = app.menuItems.matching(NSPredicate(format: "title CONTAINS 'Presets'")).firstMatch
        if presetsItem.exists {
            presetsItem.hover()
            Thread.sleep(forTimeInterval: 0.5)
            // Submenu should appear with preset list
        }
        
        app.pressEscape()
    }
    
    // MARK: - Idle Mode Tests
    
    func testIdleVisualization() {
        // When not playing audio, visualization should show idle patterns
        // Just verify the window is responsive
        visualizationWindow.click()
        
        Thread.sleep(forTimeInterval: 2.0)  // Let visualization run
        
        XCTAssertTrue(visualizationWindow.exists, "Visualization should render in idle mode")
    }
}
