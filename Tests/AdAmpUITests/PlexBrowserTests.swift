import XCTest

/// Tests for the Plex browser window
final class PlexBrowserTests: AdAmpUITestCase {
    
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
    
    // MARK: - Core Tests
    
    func testPlexBrowserWindow() {
        XCTAssertTrue(plexBrowserWindow.exists, "Browser window should exist")
        XCTAssertTrue(plexBrowserWindow.isHittable, "Browser window should be hittable")
    }
    
    func testTabClicks() {
        // Test clicking different tabs
        let tabOffsets: [CGFloat] = [0.08, 0.22, 0.35, 0.92]  // Artists, Albums, Tracks, Search
        for dx in tabOffsets {
            let tabArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.06))
            tabArea.tap()
        }
        XCTAssertTrue(plexBrowserWindow.exists)
    }
    
    func testContentInteraction() {
        let contentArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        contentArea.tap()
        contentArea.doubleTap()
        
        plexBrowserWindow.scroll(byDeltaX: 0, deltaY: -100)
        plexBrowserWindow.scroll(byDeltaX: 0, deltaY: 100)
        
        XCTAssertTrue(plexBrowserWindow.exists)
    }
    
    func testWindowDrag() {
        let startPoint = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        let endPoint = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        XCTAssertTrue(plexBrowserWindow.exists)
    }
    
    func testWindowResize() {
        let resizeStart = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        let resizeEnd = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 1.1))
        resizeStart.click(forDuration: 0.1, thenDragTo: resizeEnd)
        XCTAssertTrue(plexBrowserWindow.exists)
    }
    
    func testContextMenu() {
        plexBrowserWindow.rightClick()
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 1))
        app.pressEscape()
    }
    
    func testShadeMode() {
        let titleBar = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        titleBar.doubleTap()
        XCTAssertTrue(plexBrowserWindow.exists)
        titleBar.doubleTap()
    }
}
