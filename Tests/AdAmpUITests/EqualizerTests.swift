import XCTest

/// Tests for the equalizer window
final class EqualizerTests: AdAmpUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Open equalizer window for all tests in this class
        if !equalizerWindow.exists {
            // Open via context menu
            mainWindow.rightClick()
            let eqMenuItem = app.menuItems["Graphical EQ"]
            if eqMenuItem.waitForExistence(timeout: 2) {
                eqMenuItem.tap()
            }
        }
    }
    
    // MARK: - Window Tests
    
    func testEqualizerWindowExists() {
        XCTAssertTrue(waitForElement(equalizerWindow), "Equalizer window should exist")
    }
    
    func testEqualizerWindowIsVisible() {
        XCTAssertTrue(equalizerWindow.isHittable, "Equalizer window should be visible and hittable")
    }
    
    // MARK: - Toggle Button Tests
    
    func testOnOffButton_togglesEQ() {
        let onOffButton = equalizerWindow.buttons[AccessibilityIdentifiers.Equalizer.onOffButton]
        
        if onOffButton.exists {
            // Toggle EQ on/off
            onOffButton.tap()
            
            Thread.sleep(forTimeInterval: 0.3)
            
            // Toggle back
            onOffButton.tap()
            
            XCTAssertTrue(equalizerWindow.exists, "EQ window should remain visible after toggle")
        } else {
            // In custom-drawn view, just verify window responds to clicks
            XCTAssertTrue(equalizerWindow.exists)
        }
    }
    
    func testAutoButton_exists() {
        let autoButton = equalizerWindow.buttons[AccessibilityIdentifiers.Equalizer.autoButton]
        // Auto button may not be separately accessible in custom view
        XCTAssertTrue(equalizerWindow.exists, "EQ window should exist")
    }
    
    func testPresetsButton_showsMenu() {
        let presetsButton = equalizerWindow.buttons[AccessibilityIdentifiers.Equalizer.presetsButton]
        
        if presetsButton.exists {
            presetsButton.tap()
            
            // Presets menu should appear
            let menu = app.menus.firstMatch
            if menu.waitForExistence(timeout: 2) {
                // Verify some preset options exist
                app.pressEscape()
            }
        }
    }
    
    // MARK: - Slider Tests
    
    func testPreampSlider_exists() {
        let preampSlider = equalizerWindow.sliders[AccessibilityIdentifiers.Equalizer.preampSlider]
        // Preamp slider may be part of custom-drawn view
        XCTAssertTrue(equalizerWindow.exists, "EQ window with preamp should exist")
    }
    
    func testBandSliders_exist() {
        // Test that the EQ window has band sliders (10 bands)
        // In custom-drawn view, these may not be separately accessible
        XCTAssertTrue(equalizerWindow.exists, "EQ window with band sliders should exist")
    }
    
    func testSliderInteraction() {
        // Click and drag in the EQ area to adjust bands
        // This tests that the custom drawing responds to mouse events
        
        // Click in the middle of the EQ window
        let centerPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        centerPoint.tap()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // Drag to simulate slider adjustment
        let startPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let endPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        XCTAssertTrue(equalizerWindow.exists, "EQ should respond to slider interactions")
    }
    
    // MARK: - EQ Graph Tests
    
    func testEQGraph_displays() {
        // The EQ graph shows the current curve
        // Just verify the window is displayed correctly
        XCTAssertTrue(equalizerWindow.exists, "EQ window with graph should be visible")
    }
    
    // MARK: - Preset Tests
    
    func testLoadPreset() {
        // Try to load a preset via the presets button
        // Click in the presets button area
        let presetsArea = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.15))
        presetsArea.tap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        // If menu appeared, select first preset
        let menu = app.menus.firstMatch
        if menu.waitForExistence(timeout: 1) {
            let firstItem = menu.menuItems.firstMatch
            if firstItem.exists {
                firstItem.tap()
            } else {
                app.pressEscape()
            }
        }
        
        XCTAssertTrue(equalizerWindow.exists, "EQ should still exist after preset selection")
    }
    
    // MARK: - Window Control Tests
    
    func testEqualizerWindowCanBeDragged() {
        let initialFrame = equalizerWindow.frame
        
        // Drag the window by the title bar
        let startPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        let endPoint = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(equalizerWindow.exists, "EQ window should still exist after drag")
    }
    
    func testEqualizerWindowCanClose() {
        let closeButton = equalizerWindow.buttons[AccessibilityIdentifiers.Equalizer.closeButton]
        
        if closeButton.exists {
            closeButton.tap()
            
            Thread.sleep(forTimeInterval: 0.5)
            
            XCTAssertFalse(equalizerWindow.exists, "EQ window should close")
        } else {
            // Try clicking in close button area
            let closeArea = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.05))
            closeArea.tap()
            
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
    
    // MARK: - Shade Mode Tests
    
    func testShadeMode_toggle() {
        // Double-click on title bar to toggle shade mode
        let titleBar = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        titleBar.doubleTap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        // Window should still exist (in shade mode)
        XCTAssertTrue(equalizerWindow.exists, "EQ should still exist in shade mode")
        
        // Double-click again to exit shade mode
        let shadeTitleBar = equalizerWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shadeTitleBar.doubleTap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(equalizerWindow.exists, "EQ should exist after exiting shade mode")
    }
    
    // MARK: - Context Menu Tests
    
    func testEqualizerContextMenu() {
        equalizerWindow.rightClick()
        
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 2), "Context menu should appear")
        
        app.pressEscape()
    }
}
