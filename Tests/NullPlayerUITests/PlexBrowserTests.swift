import XCTest

/// Tests for the Plex browser window
/// Consolidated to minimize app launches for faster CI execution
final class PlexBrowserTests: NullPlayerUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        if !plexBrowserWindow.exists {
            mainWindow.rightClick()
            let browserMenuItem = app.menuItems["Music Browser"]
            if browserMenuItem.waitForExistence(timeout: 1) {
                browserMenuItem.tap()
            }
            _ = waitForElement(plexBrowserWindow, timeout: 1)
        }
    }
    
    // MARK: - Window and Controls Test
    
    /// Tests browser window existence, tabs, and content interaction
    func testPlexBrowserWindowAndControls() {
        // Window existence
        XCTAssertTrue(plexBrowserWindow.exists, "Browser window should exist")
        XCTAssertTrue(plexBrowserWindow.isHittable, "Browser window should be hittable")
        
        // Tab clicks (Artists, Albums, Tracks, Search)
        let tabOffsets: [CGFloat] = [0.08, 0.22, 0.35, 0.92]
        for dx in tabOffsets {
            let tabArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.06))
            tabArea.tap()
        }
        XCTAssertTrue(plexBrowserWindow.exists)
        
        // Content interaction
        let contentArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        contentArea.tap()
        contentArea.doubleTap()
        
        // Scrolling
        plexBrowserWindow.scroll(byDeltaX: 0, deltaY: -100)
        plexBrowserWindow.scroll(byDeltaX: 0, deltaY: 100)
        
        XCTAssertTrue(plexBrowserWindow.exists)
    }
    
    // MARK: - Interaction Test
    
    /// Tests window drag, resize, context menu, and shade mode
    func testPlexBrowserInteractions() {
        // Window drag
        let startPoint = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        let endPoint = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(plexBrowserWindow.exists)
        
        // Window resize
        let resizeStart = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        let resizeEnd = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 1.1))
        resizeStart.click(forDuration: 0.1, thenDragTo: resizeEnd)
        XCTAssertTrue(plexBrowserWindow.exists)
        
        // Context menu
        plexBrowserWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
        
        // Shade mode
        let titleBar = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        titleBar.doubleTap()
        XCTAssertTrue(plexBrowserWindow.exists)
        titleBar.doubleTap()
    }
}
