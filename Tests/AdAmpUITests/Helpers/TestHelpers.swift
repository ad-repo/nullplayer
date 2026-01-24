import XCTest

/// Test utility helpers
extension XCUIElement {
    
    /// Wait for element to exist and return it, failing if not found
    /// - Parameter timeout: Maximum time to wait
    /// - Returns: Self for chaining
    @discardableResult
    func waitAndReturn(timeout: TimeInterval = 5) -> XCUIElement {
        XCTAssertTrue(self.waitForExistence(timeout: timeout), 
                     "Element '\(self.identifier)' did not appear within \(timeout) seconds")
        return self
    }
    
    /// Safely tap an element, waiting for it first
    func safeTap(timeout: TimeInterval = 5) {
        waitAndReturn(timeout: timeout).tap()
    }
    
    /// Check if element has expected accessibility value
    func hasValue(_ expected: String) -> Bool {
        guard let value = self.value as? String else { return false }
        return value == expected
    }
    
    /// Get the element's label text
    var labelText: String {
        return label
    }
}

/// Test data helpers
enum TestFixtures {
    /// Short test audio file path (5 seconds)
    static let shortAudioFile = "test-short.mp3"
    
    /// Medium test audio file path (3 minutes)
    static let mediumAudioFile = "test-3min.mp3"
    
    /// Test file with full metadata
    static let metadataAudioFile = "test-metadata.mp3"
    
    /// Test playlist file
    static let playlistFile = "test-playlist.m3u"
    
    /// Get the full path to a test fixture
    static func path(for fixture: String) -> String? {
        return Bundle(for: AdAmpUITestCase.self).path(forResource: fixture, ofType: nil)
    }
    
    /// Get the URL to a test fixture
    static func url(for fixture: String) -> URL? {
        return Bundle(for: AdAmpUITestCase.self).url(forResource: fixture, withExtension: nil)
    }
}

/// Keyboard shortcut helpers
extension XCUIApplication {
    
    /// Send a keyboard shortcut
    /// - Parameters:
    ///   - key: The key to press
    ///   - modifiers: Modifier flags (command, shift, option, control)
    func typeShortcut(_ key: String, modifiers: XCUIElement.KeyModifierFlags = []) {
        let element = windows.firstMatch
        element.typeKey(key, modifierFlags: modifiers)
    }
    
    /// Press space bar (play/pause)
    func pressSpace() {
        typeShortcut(" ")
    }
    
    /// Press escape
    func pressEscape() {
        typeShortcut(XCUIKeyboardKey.escape.rawValue)
    }
    
    /// Press left arrow
    func pressLeftArrow() {
        typeShortcut(XCUIKeyboardKey.leftArrow.rawValue)
    }
    
    /// Press right arrow
    func pressRightArrow() {
        typeShortcut(XCUIKeyboardKey.rightArrow.rawValue)
    }
    
    /// Press up arrow
    func pressUpArrow() {
        typeShortcut(XCUIKeyboardKey.upArrow.rawValue)
    }
    
    /// Press down arrow
    func pressDownArrow() {
        typeShortcut(XCUIKeyboardKey.downArrow.rawValue)
    }
}

/// Timing helpers for playback tests
extension AdAmpUITestCase {
    
    /// Wait for playback to start (play button should be replaced by pause button)
    func waitForPlaybackToStart(timeout: TimeInterval = 5) -> Bool {
        let pauseButton = app.buttons[AccessibilityIdentifiers.MainWindow.pauseButton]
        return waitForElement(pauseButton, timeout: timeout)
    }
    
    /// Wait for playback to stop (pause button should be replaced by play button)
    func waitForPlaybackToStop(timeout: TimeInterval = 5) -> Bool {
        let playButton = app.buttons[AccessibilityIdentifiers.MainWindow.playButton]
        return waitForElement(playButton, timeout: timeout)
    }
    
    /// Wait a specific amount of time (for playback timing tests)
    func waitForDuration(_ seconds: TimeInterval) {
        let expectation = XCTestExpectation(description: "Wait for \(seconds) seconds")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: seconds + 1)
    }
}

/// Window position helpers
extension XCUIElement {
    
    /// Get the frame origin
    var frameOrigin: CGPoint {
        return frame.origin
    }
    
    /// Get the frame size
    var frameSize: CGSize {
        return frame.size
    }
    
    /// Check if this window is docked below another
    func isDockedBelow(_ other: XCUIElement) -> Bool {
        let thisFrame = self.frame
        let otherFrame = other.frame
        
        // Check if aligned horizontally (same X position)
        let horizontallyAligned = abs(thisFrame.minX - otherFrame.minX) < 5
        
        // Check if directly below (this window's top matches other's bottom)
        let verticallyDocked = abs(thisFrame.maxY - otherFrame.minY) < 5
        
        return horizontallyAligned && verticallyDocked
    }
    
    /// Check if this window is docked to the right of another
    func isDockedRightOf(_ other: XCUIElement) -> Bool {
        let thisFrame = self.frame
        let otherFrame = other.frame
        
        // Check if aligned vertically (same Y position)
        let verticallyAligned = abs(thisFrame.minY - otherFrame.minY) < 5
        
        // Check if directly to the right (this window's left matches other's right)
        let horizontallyDocked = abs(thisFrame.minX - otherFrame.maxX) < 5
        
        return verticallyAligned && horizontallyDocked
    }
}
