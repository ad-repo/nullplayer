import XCTest

/// Tests for the visualization (Milkdrop) window
final class VisualizationTests: AdAmpUITestCase {
    
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
    
    // MARK: - Core Tests
    
    func testVisualizationWindow() {
        XCTAssertTrue(visualizationWindow.exists, "Visualization window should exist")
        XCTAssertTrue(visualizationWindow.isHittable, "Visualization window should be hittable")
    }
    
    func testPresetNavigation() {
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
    }
    
    func testHardCuts() {
        visualizationWindow.click()
        
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .shift)
        app.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: .shift)
        
        XCTAssertTrue(visualizationWindow.exists)
    }
    
    func testFullscreen() {
        visualizationWindow.click()
        
        app.typeKey("f", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)  // Minimal wait for fullscreen transition
        app.pressEscape()
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(visualizationWindow.exists || mainWindow.exists)
    }
    
    func testWindowDrag() {
        let startPoint = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        let endPoint = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(visualizationWindow.exists)
    }
    
    func testWindowResize() {
        let resizeStart = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        let resizeEnd = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 1.1))
        resizeStart.click(forDuration: 0.1, thenDragTo: resizeEnd)
        XCTAssertTrue(visualizationWindow.exists)
    }
    
    func testContextMenu() {
        visualizationWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
    
    func testShadeMode() {
        let titleBar = visualizationWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        titleBar.doubleTap()
        XCTAssertTrue(visualizationWindow.exists)
        titleBar.doubleTap()
    }
}
