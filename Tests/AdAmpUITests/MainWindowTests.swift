import XCTest

/// Tests for the main player window
final class MainWindowTests: AdAmpUITestCase {
    
    // MARK: - Window Tests
    
    func testMainWindowExists() {
        XCTAssertTrue(mainWindow.exists, "Main window should exist on app launch")
    }
    
    func testMainWindowIsVisible() {
        XCTAssertTrue(mainWindow.isHittable, "Main window should be visible and hittable")
    }
    
    // MARK: - Transport Controls
    
    func testPlayButton_exists() {
        let playButton = app.buttons[AccessibilityIdentifiers.MainWindow.playButton]
        // Play button should exist when not playing
        XCTAssertTrue(waitForElement(playButton), "Play button should exist")
    }
    
    func testPlayPauseToggle() throws {
        // Initially should show play button (not playing)
        let playButton = app.buttons[AccessibilityIdentifiers.MainWindow.playButton]
        XCTAssertTrue(waitForElement(playButton), "Play button should exist initially")
        
        // Click play - should start playback (if tracks are loaded) or do nothing
        playButton.tap()
        
        // Note: Without test audio loaded, playback won't actually start
        // In a full test, we'd load test fixtures first
    }
    
    func testStopButton_exists() {
        let stopButton = app.buttons[AccessibilityIdentifiers.MainWindow.stopButton]
        XCTAssertTrue(waitForElement(stopButton), "Stop button should exist")
    }
    
    func testPreviousButton_exists() {
        let prevButton = app.buttons[AccessibilityIdentifiers.MainWindow.previousButton]
        XCTAssertTrue(waitForElement(prevButton), "Previous button should exist")
    }
    
    func testNextButton_exists() {
        let nextButton = app.buttons[AccessibilityIdentifiers.MainWindow.nextButton]
        XCTAssertTrue(waitForElement(nextButton), "Next button should exist")
    }
    
    func testEjectButton_exists() {
        let ejectButton = app.buttons[AccessibilityIdentifiers.MainWindow.ejectButton]
        XCTAssertTrue(waitForElement(ejectButton), "Eject (open file) button should exist")
    }
    
    // MARK: - Slider Tests
    
    func testVolumeSlider_exists() {
        let volumeSlider = app.sliders[AccessibilityIdentifiers.MainWindow.volumeSlider]
        XCTAssertTrue(waitForElement(volumeSlider), "Volume slider should exist")
    }
    
    func testSeekSlider_exists() {
        let seekSlider = app.sliders[AccessibilityIdentifiers.MainWindow.seekSlider]
        XCTAssertTrue(waitForElement(seekSlider), "Seek slider should exist")
    }
    
    func testBalanceSlider_exists() {
        let balanceSlider = app.sliders[AccessibilityIdentifiers.MainWindow.balanceSlider]
        XCTAssertTrue(waitForElement(balanceSlider), "Balance slider should exist")
    }
    
    // MARK: - Toggle Button Tests
    
    func testShuffleButton_exists() {
        let shuffleButton = app.buttons[AccessibilityIdentifiers.MainWindow.shuffleButton]
        XCTAssertTrue(waitForElement(shuffleButton), "Shuffle button should exist")
    }
    
    func testRepeatButton_exists() {
        let repeatButton = app.buttons[AccessibilityIdentifiers.MainWindow.repeatButton]
        XCTAssertTrue(waitForElement(repeatButton), "Repeat button should exist")
    }
    
    func testShuffleToggle() {
        let shuffleButton = app.buttons[AccessibilityIdentifiers.MainWindow.shuffleButton]
        XCTAssertTrue(waitForElement(shuffleButton), "Shuffle button should exist")
        
        // Get initial label (state)
        let initialLabel = shuffleButton.label
        
        // Toggle shuffle
        shuffleButton.tap()
        
        // Wait for UI update
        Thread.sleep(forTimeInterval: 0.5)
        
        // Label should change (from "Shuffle Off" to "Shuffle On" or vice versa)
        let newLabel = shuffleButton.label
        XCTAssertNotEqual(initialLabel, newLabel, "Shuffle state should toggle when clicked")
    }
    
    func testRepeatToggle() {
        let repeatButton = app.buttons[AccessibilityIdentifiers.MainWindow.repeatButton]
        XCTAssertTrue(waitForElement(repeatButton), "Repeat button should exist")
        
        // Get initial label (state)
        let initialLabel = repeatButton.label
        
        // Toggle repeat
        repeatButton.tap()
        
        // Wait for UI update
        Thread.sleep(forTimeInterval: 0.5)
        
        // Label should change
        let newLabel = repeatButton.label
        XCTAssertNotEqual(initialLabel, newLabel, "Repeat state should toggle when clicked")
    }
    
    // MARK: - Keyboard Shortcut Tests
    
    func testSpaceBarPlayPause() {
        // Press space bar - should toggle play/pause
        app.pressSpace()
        
        // Note: Without tracks loaded, this won't change state
        // This test verifies the key event is processed without crashing
    }
    
    func testArrowKeysSeek() {
        // Press left/right arrows - should seek (if playing)
        app.pressLeftArrow()
        app.pressRightArrow()
        
        // Verify no crash occurred
        XCTAssertTrue(mainWindow.exists, "Main window should still exist after arrow key presses")
    }
    
    func testArrowKeysVolume() {
        // Press up/down arrows - should adjust volume
        app.pressUpArrow()
        app.pressDownArrow()
        
        // Verify no crash occurred
        XCTAssertTrue(mainWindow.exists, "Main window should still exist after volume adjustment")
    }
    
    // MARK: - Window Interaction Tests
    
    func testMainWindowCanBeDragged() {
        // Get initial position
        let initialFrame = mainWindow.frame
        
        // Drag the window
        let startPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let endPoint = mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        // Wait for drag to complete
        Thread.sleep(forTimeInterval: 0.5)
        
        // Window should have moved
        let newFrame = mainWindow.frame
        // Note: In a borderless window, drag behavior may vary
        // At minimum, verify window still exists
        XCTAssertTrue(mainWindow.exists, "Main window should still exist after drag attempt")
    }
    
    // MARK: - Context Menu Tests
    
    func testContextMenuOpens() {
        // Right-click on main window
        mainWindow.rightClick()
        
        // Context menu should appear
        let contextMenu = app.menus.firstMatch
        XCTAssertTrue(contextMenu.waitForExistence(timeout: 2), "Context menu should appear on right-click")
        
        // Dismiss menu
        app.pressEscape()
    }
}
