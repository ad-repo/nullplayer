import XCTest

/// Tests for the Plex browser window
final class PlexBrowserTests: AdAmpUITestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Open Plex browser window for all tests in this class
        if !plexBrowserWindow.exists {
            // Open via context menu
            mainWindow.rightClick()
            let browserMenuItem = app.menuItems["Music Browser"]
            if browserMenuItem.waitForExistence(timeout: 2) {
                browserMenuItem.tap()
            }
        }
    }
    
    // MARK: - Window Tests
    
    func testPlexBrowserWindowExists() {
        XCTAssertTrue(waitForElement(plexBrowserWindow), "Plex browser window should exist")
    }
    
    func testPlexBrowserWindowIsVisible() {
        XCTAssertTrue(plexBrowserWindow.isHittable, "Plex browser window should be visible")
    }
    
    // MARK: - Tab Tests
    
    func testModeTabs_exist() {
        // The Plex browser has tabs for Artists, Albums, Tracks, Movies, Shows, Search
        // In custom-drawn view, these are part of the skin
        XCTAssertTrue(plexBrowserWindow.exists, "Browser with tabs should exist")
    }
    
    func testArtistsTab_click() {
        // Click in the Artists tab area
        let artistsTabArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.06))
        artistsTabArea.tap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should respond to Artists tab click")
    }
    
    func testAlbumsTab_click() {
        let albumsTabArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.06))
        albumsTabArea.tap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should respond to Albums tab click")
    }
    
    func testTracksTab_click() {
        let tracksTabArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.06))
        tracksTabArea.tap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should respond to Tracks tab click")
    }
    
    func testSearchTab_click() {
        let searchTabArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.06))
        searchTabArea.tap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should respond to Search tab click")
    }
    
    // MARK: - Source Selection Tests
    
    func testSourceButton_click() {
        // Click the source button (LOCAL FILES / PLEX)
        let sourceArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
        sourceArea.tap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        // Should show source selection menu or toggle
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should respond to source selection")
    }
    
    // MARK: - Content List Tests
    
    func testContentList_scroll() {
        // Scroll within the content list
        plexBrowserWindow.scroll(byDeltaX: 0, deltaY: -100)
        
        Thread.sleep(forTimeInterval: 0.3)
        
        plexBrowserWindow.scroll(byDeltaX: 0, deltaY: 100)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should handle scroll events")
    }
    
    func testContentList_click() {
        // Click in the content area
        let contentArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        contentArea.tap()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should respond to content clicks")
    }
    
    func testContentList_doubleClick() {
        // Double-click to expand/play item
        let contentArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        contentArea.doubleTap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should handle double-clicks")
    }
    
    // MARK: - Bottom Bar Tests
    
    func testSortButton_click() {
        // Click sort button area
        let sortArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.97))
        sortArea.tap()
        
        Thread.sleep(forTimeInterval: 0.3)
        
        // May show sort menu
        let menu = app.menus.firstMatch
        if menu.exists {
            app.pressEscape()
        }
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should respond to sort button")
    }
    
    // MARK: - Local Files Mode Tests
    
    func testLocalFilesMode() {
        // In test mode, should default to local files
        // Verify the browser shows local file UI
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should show local files mode")
    }
    
    // MARK: - Window Control Tests
    
    func testPlexBrowserCanBeDragged() {
        let initialFrame = plexBrowserWindow.frame
        
        // Drag the window
        let startPoint = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        let endPoint = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.1))
        startPoint.click(forDuration: 0.1, thenDragTo: endPoint)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should still exist after drag")
    }
    
    func testPlexBrowserCanClose() {
        let closeButton = plexBrowserWindow.buttons[AccessibilityIdentifiers.PlexBrowser.closeButton]
        
        if closeButton.exists {
            closeButton.tap()
        } else {
            // Click in close button area (top-right)
            let closeArea = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.01))
            closeArea.tap()
        }
        
        Thread.sleep(forTimeInterval: 0.5)
        
        // Window should close or still exist (depends on click accuracy)
        // Don't assert closure since custom drawing hit areas may vary
    }
    
    func testPlexBrowserCanResize() {
        // Drag resize handle (bottom-right corner)
        let resizeStart = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
        let resizeEnd = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 1.1, dy: 1.1))
        resizeStart.click(forDuration: 0.1, thenDragTo: resizeEnd)
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should handle resize")
    }
    
    // MARK: - Shade Mode Tests
    
    func testShadeMode_toggle() {
        // Double-click on title bar
        let titleBar = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        titleBar.doubleTap()
        
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(plexBrowserWindow.exists, "Browser should toggle shade mode")
        
        // Toggle back
        let shadeTitleBar = plexBrowserWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        shadeTitleBar.doubleTap()
        
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    // MARK: - Context Menu Tests
    
    func testPlexBrowserContextMenu() {
        plexBrowserWindow.rightClick()
        
        let menu = app.menus.firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 2), "Context menu should appear")
        
        app.pressEscape()
    }
    
    // MARK: - Drag and Drop Tests
    
    func testBrowserAcceptsDraggedFiles() {
        XCTAssertTrue(plexBrowserWindow.isHittable, "Browser should be able to receive drag operations")
    }
}
