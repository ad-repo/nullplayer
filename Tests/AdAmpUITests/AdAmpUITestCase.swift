import XCTest

/// Base test case for AdAmp UI tests
/// Provides common setup, teardown, and helper methods
class AdAmpUITestCase: XCTestCase {
    
    /// The application under test
    var app: XCUIApplication!
    
    /// Timeout for UI element waits
    let defaultTimeout: TimeInterval = 5
    
    // MARK: - Setup and Teardown
    
    override func setUpWithError() throws {
        // Stop immediately on failure
        continueAfterFailure = false
        
        // Initialize the application
        app = XCUIApplication()
        
        // Set UI testing launch argument
        app.launchArguments = ["--ui-testing"]
        
        // Launch the app
        app.launch()
    }
    
    override func tearDownWithError() throws {
        // Capture screenshot on failure for CI debugging
        if let failureCount = testRun?.failureCount, failureCount > 0 {
            captureFailureScreenshot()
        }
        
        // Terminate the app
        app.terminate()
        app = nil
    }
    
    // MARK: - Screenshot Helpers
    
    /// Capture a screenshot and attach it to the test results
    func captureFailureScreenshot() {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Failure-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    /// Capture a screenshot with a custom name
    func captureScreenshot(named name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    // MARK: - Wait Helpers
    
    /// Wait for an element to exist with the default timeout
    /// - Parameter element: The element to wait for
    /// - Returns: True if the element exists within the timeout
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        return element.waitForExistence(timeout: timeout ?? defaultTimeout)
    }
    
    /// Wait for an element to become hittable (exists and can be interacted with)
    /// - Parameters:
    ///   - element: The element to wait for
    ///   - timeout: Maximum time to wait
    /// - Returns: True if the element is hittable within the timeout
    @discardableResult
    func waitForHittable(_ element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        let effectiveTimeout = timeout ?? defaultTimeout
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: effectiveTimeout)
        return result == .completed
    }
    
    /// Wait for an element to have a specific value
    /// - Parameters:
    ///   - element: The element to check
    ///   - value: The expected value
    ///   - timeout: Maximum time to wait
    /// - Returns: True if the element has the expected value
    @discardableResult
    func waitForValue(_ element: XCUIElement, value: String, timeout: TimeInterval? = nil) -> Bool {
        let effectiveTimeout = timeout ?? defaultTimeout
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: effectiveTimeout)
        return result == .completed
    }
    
    // MARK: - Window Helpers
    
    /// Get the main player window
    var mainWindow: XCUIElement {
        return app.windows["MainWindow"]
    }
    
    /// Get the playlist window
    var playlistWindow: XCUIElement {
        return app.windows["PlaylistWindow"]
    }
    
    /// Get the equalizer window
    var equalizerWindow: XCUIElement {
        return app.windows["EqualizerWindow"]
    }
    
    /// Get the Plex browser window
    var plexBrowserWindow: XCUIElement {
        return app.windows["PlexBrowserWindow"]
    }
    
    /// Get the visualization window
    var visualizationWindow: XCUIElement {
        return app.windows["MilkdropWindow"]
    }
    
    // MARK: - Navigation Helpers
    
    /// Open the playlist window via menu
    func openPlaylist() {
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Playlist"].click()
        XCTAssertTrue(waitForElement(playlistWindow))
    }
    
    /// Open the equalizer window via menu
    func openEqualizer() {
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Equalizer"].click()
        XCTAssertTrue(waitForElement(equalizerWindow))
    }
    
    /// Open the Plex browser window via menu
    func openPlexBrowser() {
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Plex Browser"].click()
        XCTAssertTrue(waitForElement(plexBrowserWindow))
    }
    
    /// Open the visualization window via menu
    func openVisualization() {
        app.menuBars.menuBarItems["View"].click()
        app.menuItems["Visualization"].click()
        XCTAssertTrue(waitForElement(visualizationWindow))
    }
    
    // MARK: - Playback Helpers
    
    /// Get the current playback state from the play/pause button state
    var isPlaying: Bool {
        return app.buttons[AccessibilityIdentifiers.MainWindow.pauseButton].exists
    }
    
    /// Start playback
    func play() {
        let playButton = app.buttons[AccessibilityIdentifiers.MainWindow.playButton]
        if playButton.exists {
            playButton.click()
        }
    }
    
    /// Pause playback
    func pause() {
        let pauseButton = app.buttons[AccessibilityIdentifiers.MainWindow.pauseButton]
        if pauseButton.exists {
            pauseButton.click()
        }
    }
    
    /// Stop playback
    func stop() {
        let stopButton = app.buttons[AccessibilityIdentifiers.MainWindow.stopButton]
        stopButton.click()
    }
    
    // MARK: - Assertion Helpers
    
    /// Assert that a window is visible
    func assertWindowVisible(_ window: XCUIElement, message: String = "") {
        XCTAssertTrue(window.exists && window.isHittable, 
                     message.isEmpty ? "Window should be visible" : message)
    }
    
    /// Assert that a window is not visible
    func assertWindowNotVisible(_ window: XCUIElement, message: String = "") {
        XCTAssertFalse(window.exists, 
                      message.isEmpty ? "Window should not be visible" : message)
    }
}
