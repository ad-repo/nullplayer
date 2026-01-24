import XCTest

/// Tests for the equalizer window
final class EqualizerTests: AdAmpUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Open equalizer window for all tests
        if !equalizerWindow.exists {
            mainWindow.rightClick()
            let eqMenuItem = app.menuItems["Graphical EQ"]
            if eqMenuItem.waitForExistence(timeout: 1) {
                eqMenuItem.tap()
            }
            _ = waitForElement(equalizerWindow, timeout: 1)
        }
    }
    
    // MARK: - Core Tests
    
    func testEqualizerWindow() {
        XCTAssertTrue(equalizerWindow.exists, "Equalizer window should exist")
        XCTAssertTrue(equalizerWindow.isHittable, "Equalizer window should be hittable")
    }
    
    func testOnOffToggle() {
        let onOffButton = equalizerWindow.buttons[AccessibilityIdentifiers.Equalizer.onOffButton]
        guard onOffButton.exists else { return }
        
        onOffButton.tap()
        onOffButton.tap()
        XCTAssertTrue(equalizerWindow.exists)
    }
    
    func testSliderInteraction() {
        let startPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let endPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(equalizerWindow.exists)
    }
    
    func testPresetMenu() {
        let presetsArea = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15))
        presetsArea.tap()
        
        let menu = app.menus.firstMatch
        if menu.waitForExistence(timeout: 1) {
            app.pressEscape()
        }
        XCTAssertTrue(equalizerWindow.exists)
    }
    
    func testWindowDrag() {
        let startPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(equalizerWindow.exists)
    }
    
    func testContextMenu() {
        equalizerWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
    
    func testShadeMode() {
        let titleBar = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        titleBar.doubleTap()
        XCTAssertTrue(equalizerWindow.exists)
        titleBar.doubleTap()
        XCTAssertTrue(equalizerWindow.exists)
    }
}
