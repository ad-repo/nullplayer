import XCTest

/// Tests for the equalizer window
/// Consolidated to minimize app launches for faster CI execution
final class EqualizerTests: NullPlayerUITestCase {
    
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
    
    // MARK: - Window and Controls Test
    
    /// Tests equalizer window existence, on/off toggle, slider interaction, and presets
    func testEqualizerWindowAndControls() {
        // Window existence
        XCTAssertTrue(equalizerWindow.exists, "Equalizer window should exist")
        XCTAssertTrue(equalizerWindow.isHittable, "Equalizer window should be hittable")
        
        // On/Off toggle
        let onOffButton = equalizerWindow.buttons[AccessibilityIdentifiers.Equalizer.onOffButton]
        if onOffButton.exists {
            onOffButton.tap()
            onOffButton.tap()
        }
        XCTAssertTrue(equalizerWindow.exists)
        
        // Slider interaction
        let startPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let endPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(equalizerWindow.exists)
        
        // Preset menu
        let presetsArea = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15))
        presetsArea.tap()
        
        let menu = app.menus.firstMatch
        if menu.waitForExistence(timeout: 1) {
            app.pressEscape()
        }
        XCTAssertTrue(equalizerWindow.exists)
    }
    
    // MARK: - Interaction Test
    
    /// Tests window drag, context menu, and shade mode
    func testEqualizerInteractions() {
        // Window drag
        let startPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(equalizerWindow.exists)
        
        // Context menu
        equalizerWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
        
        // Shade mode
        let titleBar = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        titleBar.doubleTap()
        XCTAssertTrue(equalizerWindow.exists)
        titleBar.doubleTap()
        XCTAssertTrue(equalizerWindow.exists)
    }
}
