import XCTest

/// Tests for the main player window
final class MainWindowTests: AdAmpUITestCase {
    
    // MARK: - Window Tests
    
    func testMainWindow() {
        XCTAssertTrue(mainWindow.exists, "Main window should exist on launch")
        XCTAssertTrue(mainWindow.isHittable, "Main window should be hittable")
    }
    
    // MARK: - Transport Controls
    
    func testTransportButtons() {
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
    }
    
    // MARK: - Slider Tests
    
    func testSliders() {
        let volumeSlider = app.sliders[AccessibilityIdentifiers.MainWindow.volumeSlider]
        let seekSlider = app.sliders[AccessibilityIdentifiers.MainWindow.seekSlider]
        let balanceSlider = app.sliders[AccessibilityIdentifiers.MainWindow.balanceSlider]
        
        XCTAssertTrue(waitForElement(volumeSlider, timeout: 1), "Volume slider should exist")
        XCTAssertTrue(waitForElement(seekSlider, timeout: 1), "Seek slider should exist")
        XCTAssertTrue(waitForElement(balanceSlider, timeout: 1), "Balance slider should exist")
    }
    
    // MARK: - Toggle Button Tests
    
    func testToggleButtons() {
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
    
    // MARK: - Keyboard Tests
    
    func testKeyboardShortcuts() {
        app.pressSpace()
        app.pressLeftArrow()
        app.pressRightArrow()
        app.pressUpArrow()
        app.pressDownArrow()
        XCTAssertTrue(mainWindow.exists, "Window should handle keyboard shortcuts")
    }
    
    // MARK: - Window Interaction Tests
    
    func testWindowDrag() {
        let startPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let endPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(mainWindow.exists)
    }
    
    func testContextMenu() {
        mainWindow.rightClick()
        let contextMenu = app.menus.firstMatch
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
}
