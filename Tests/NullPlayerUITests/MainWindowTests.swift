import XCTest

/// Tests for the main player window
/// Consolidated to minimize app launches for faster CI execution
final class MainWindowTests: NullPlayerUITestCase {
    
    // MARK: - Window and Controls Test
    
    /// Tests main window existence, transport buttons, sliders, and toggle buttons
    func testMainWindowAndControls() {
        // Window existence
        XCTAssertTrue(mainWindow.exists, "Main window should exist on launch")
        XCTAssertTrue(mainWindow.isHittable, "Main window should be hittable")
        
        // Transport buttons
        let playButton = app.buttons[AccessibilityIdentifiers.MainWindow.playButton]
        let stopButton = app.buttons[AccessibilityIdentifiers.MainWindow.stopButton]
        let prevButton = app.buttons[AccessibilityIdentifiers.MainWindow.previousButton]
        let nextButton = app.buttons[AccessibilityIdentifiers.MainWindow.nextButton]
        let ejectButton = app.buttons[AccessibilityIdentifiers.MainWindow.ejectButton]
        
        XCTAssertTrue(waitForElement(playButton, timeout: 1), "Play button should exist")
        XCTAssertTrue(waitForElement(stopButton, timeout: 1), "Stop button should exist")
        XCTAssertTrue(waitForElement(prevButton, timeout: 1), "Previous button should exist")
        XCTAssertTrue(waitForElement(nextButton, timeout: 1), "Next button should exist")
        XCTAssertTrue(waitForElement(ejectButton, timeout: 1), "Eject button should exist")
        
        // Sliders
        let volumeSlider = app.sliders[AccessibilityIdentifiers.MainWindow.volumeSlider]
        let seekSlider = app.sliders[AccessibilityIdentifiers.MainWindow.seekSlider]
        let balanceSlider = app.sliders[AccessibilityIdentifiers.MainWindow.balanceSlider]
        
        XCTAssertTrue(waitForElement(volumeSlider, timeout: 1), "Volume slider should exist")
        XCTAssertTrue(waitForElement(seekSlider, timeout: 1), "Seek slider should exist")
        XCTAssertTrue(waitForElement(balanceSlider, timeout: 1), "Balance slider should exist")
        
        // Toggle buttons
        let shuffleButton = app.buttons[AccessibilityIdentifiers.MainWindow.shuffleButton]
        let repeatButton = app.buttons[AccessibilityIdentifiers.MainWindow.repeatButton]
        
        XCTAssertTrue(waitForElement(shuffleButton, timeout: 1))
        XCTAssertTrue(waitForElement(repeatButton, timeout: 1))
        
        // Test shuffle toggle
        let initialShuffleLabel = shuffleButton.label
        shuffleButton.tap()
        XCTAssertNotEqual(initialShuffleLabel, shuffleButton.label)
        
        // Test repeat toggle
        let initialRepeatLabel = repeatButton.label
        repeatButton.tap()
        XCTAssertNotEqual(initialRepeatLabel, repeatButton.label)
    }
    
    // MARK: - Interaction Test
    
    /// Tests keyboard shortcuts, window drag, and context menu
    func testMainWindowInteractions() {
        // Keyboard shortcuts
        app.pressSpace()
        app.pressLeftArrow()
        app.pressRightArrow()
        app.pressUpArrow()
        app.pressDownArrow()
        XCTAssertTrue(mainWindow.exists, "Window should handle keyboard shortcuts")
        
        // Window drag
        let startPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let endPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(mainWindow.exists)
        
        // Context menu
        mainWindow.rightClick()
        let contextMenu = app.menus.firstMatch
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
}
