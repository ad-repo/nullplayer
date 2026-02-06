import XCTest

/// Tests for the visualization (ProjectM) window
/// Consolidated to minimize app launches for faster CI execution
final class VisualizationTests: NullPlayerUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        if !visualizationWindow.exists {
            mainWindow.rightClick()
            let visMenuItem = app.menuItems["Visualization"]
            if visMenuItem.waitForExistence(timeout: 1) {
                visMenuItem.tap()
            }
            _ = waitForElement(visualizationWindow, timeout: 1)
        }
    }
    
    // MARK: - Window and Controls Test
    
    /// Tests visualization window existence, preset navigation, and keyboard shortcuts
    func testVisualizationWindowAndControls() {
        // Window existence
        XCTAssertTrue(visualizationWindow.exists, "Visualization window should exist")
        XCTAssertTrue(visualizationWindow.isHittable, "Visualization window should be hittable")
        
        // Preset navigation
        visualizationWindow.click()
        
        app.pressRightArrow()  // Next preset
        app.pressLeftArrow()   // Previous preset
        app.typeKey("r", modifierFlags: [])  // Random preset
        app.typeKey("l", modifierFlags: [])  // Toggle lock
        app.typeKey("l", modifierFlags: [])  // Toggle back
        app.typeKey("c", modifierFlags: [])  // Cycle mode
        app.typeKey("c", modifierFlags: [])
        app.typeKey("c", modifierFlags: [])
        
        XCTAssertTrue(visualizationWindow.exists)
        
        // Hard cuts
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .shift)
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: .shift)
        
        XCTAssertTrue(visualizationWindow.exists)
        
        // Fullscreen toggle
        app.typeKey("f", modifierFlags: [])
        // Brief wait for fullscreen transition
        _ = XCTWaiter.wait(for: [XCTestExpectation()], timeout: 0.3)
        app.pressEscape()
        _ = XCTWaiter.wait(for: [XCTestExpectation()], timeout: 0.3)
        
        XCTAssertTrue(visualizationWindow.exists || mainWindow.exists)
    }
    
    // MARK: - Interaction Test
    
    /// Tests window drag, resize, context menu, and shade mode
    func testVisualizationInteractions() {
        // Window drag
        let startPoint = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        let endPoint = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(visualizationWindow.exists)
        
        // Window resize
        let resizeStart = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        let resizeEnd = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 1.1))
        resizeStart.click(forDuration: 0.1, thenDragTo: resizeEnd)
        XCTAssertTrue(visualizationWindow.exists)
        
        // Context menu
        visualizationWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
        
        // Shade mode
        let titleBar = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        titleBar.doubleTap()
        XCTAssertTrue(visualizationWindow.exists)
        titleBar.doubleTap()
    }
}
