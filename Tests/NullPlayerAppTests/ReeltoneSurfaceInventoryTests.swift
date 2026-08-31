import AppKit
import XCTest
@testable import NullPlayer

final class ReeltoneSurfaceInventoryTests: XCTestCase {
    func testBuildsStableSurfaceInventoryAndSingletonPolicy() throws {
        let manifest = try decode(#"""
        {
          "formatVersion":2,"id":"fixture","name":"Fixture",
          "window":{"size":[960,384],"art":{"normal":"main.png"},"panels":{
            "zeta":{"size":[100,80],"attach":"bottom","art":{"normal":"z.png"},"visible":true,
                    "regions":[{"component":"trackList","rect":[0,0,100,80]}]},
            "alpha":{"size":[120,90],"attach":"right","art":{"normal":"a.png"},
                     "regions":[{"component":"equaliser","rect":[0,0,120,90]}]}
          }},
          "regions":[
            {"component":"trackList","rect":[10,10,300,200]},
            {"component":"library","rect":[320,10,300,200]}
          ]
        }
        """#)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))

        XCTAssertEqual(inventory.main.authoredSize, .init(width: 960, height: 384))
        XCTAssertEqual(inventory.panels.map(\.id), [.panel("alpha"), .panel("zeta")])
        XCTAssertEqual(inventory.owner(of: .trackList), .main)
        XCTAssertEqual(inventory.owner(of: .equaliser), .panel("alpha"))
        XCTAssertEqual(inventory.owner(of: .library), .main)
        XCTAssertNil(inventory.owner(of: .visualiser))
        XCTAssertFalse(inventory.panels[1].regions[0].ownsSingletonHost)
        XCTAssertEqual(inventory.diagnostics.map(\.code), [.duplicateSingletonComponent])
        XCTAssertEqual(inventory.diagnostics[0].skinID, "fixture")
        XCTAssertEqual(inventory.diagnostics[0].surfaceID, "panel:zeta")
        XCTAssertEqual(inventory.diagnostics[0].regionIndex, 0)
        XCTAssertEqual(inventory.diagnostics[0].component, "trackList")
        XCTAssertTrue(inventory.panels[1].initiallyVisible)
    }

    func testTopLeftConversionAtOneAndTwoTimes() {
        let rect = ReeltoneAuthoredRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(rect.appKitRect(surfaceHeight: 100, scale: 1), CGRect(x: 10, y: 40, width: 30, height: 40))
        XCTAssertEqual(rect.appKitRect(surfaceHeight: 100, scale: 2), CGRect(x: 20, y: 80, width: 60, height: 80))
        XCTAssertEqual(
            ReeltoneAuthoredRect.topLeftPoint(fromAppKitPoint: CGPoint(x: 20, y: 80), surfaceHeight: 100, scale: 2),
            CGPoint(x: 10, y: 60)
        )
        for level in UIScaleLevel.allCases {
            let converted = rect.appKitRect(surfaceHeight: 100, scale: Double(level.scaleFactor))
            XCTAssertEqual(converted.origin.x, 10 * level.scaleFactor, accuracy: 0.0001)
            XCTAssertEqual(converted.origin.y, 40 * level.scaleFactor, accuracy: 0.0001)
            XCTAssertEqual(converted.width, 30 * level.scaleFactor, accuracy: 0.0001)
            XCTAssertEqual(converted.height, 40 * level.scaleFactor, accuracy: 0.0001)
        }
    }

    func testHitTestingUsesEllipseAndLastEligibleRegion() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"hit","name":"Hit","window":{"size":[100,100],"art":{"normal":"m.png"}},"regions":[
          {"component":"play","rect":[10,10,50,50]},
          {"component":"decoration","rect":[10,10,50,50]},
          {"component":"pause","rect":[10,10,50,50],"clipShape":"ellipse"}
        ]}
        """#)
        let surface = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest)?.main)
        XCTAssertEqual(surface.hitRegion(atTopLeftX: 35, y: 35)?.component, .pause)
        XCTAssertEqual(surface.hitRegion(atTopLeftX: 11, y: 11)?.component, .play)
        XCTAssertNil(surface.hitRegion(atTopLeftX: 90, y: 90))
    }

    func testControlArtAndAnimationSelection() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"art","name":"Art","window":{"size":[10,10],"art":{"normal":"m.png"}},"regions":[
          {"component":"playPause","rect":[0,0,10,10],"art":{"normal":"n.png","hover":"h.png","playing":"p.png","playingPressed":"pp.png"}}
        ]}
        """#)
        let art = try XCTUnwrap(manifest.regions[0].art)
        XCTAssertEqual(ReeltoneControlArtSelector.resourcePath(in: art, isPlaying: false, isHovered: true, isPressed: false), "h.png")
        XCTAssertEqual(ReeltoneControlArtSelector.resourcePath(in: art, isPlaying: true, isHovered: false, isPressed: true), "pp.png")
        XCTAssertEqual(ReeltoneControlArtSelector.resourcePath(in: art, isPlaying: true, isHovered: true, isPressed: false), "p.png")
        XCTAssertEqual(ReeltoneControlArtSelector.state(isPlaying: false, isHovered: false, isPressed: false), .normal)
        XCTAssertEqual(ReeltoneControlArtSelector.state(isPlaying: false, isHovered: true, isPressed: false), .hover)
        XCTAssertEqual(ReeltoneControlArtSelector.state(isPlaying: false, isHovered: false, isPressed: true), .pressed)
        XCTAssertEqual(ReeltoneControlArtSelector.state(isPlaying: true, isHovered: false, isPressed: false), .playing)
        XCTAssertEqual(ReeltoneControlArtSelector.state(isPlaying: true, isHovered: true, isPressed: false), .playingHover)
        XCTAssertEqual(ReeltoneControlArtSelector.state(isPlaying: true, isHovered: false, isPressed: true), .playingPressed)
        XCTAssertTrue(ReeltoneControlArtSelector.changesWithPlayback(art))
        XCTAssertEqual(ReeltoneAnimationClock.frameIndex(frameCount: 4, fps: 2, elapsed: 1.6, driver: .always, isPlaying: false), 3)
        XCTAssertEqual(ReeltoneAnimationClock.frameIndex(frameCount: 4, fps: 2, elapsed: 1.6, driver: .playback, isPlaying: false), 0)
        XCTAssertEqual(ReeltoneAnimationClock.frameIndex(frameCount: 4, fps: 2, elapsed: 1.6, driver: .never, isPlaying: true), 0)
    }

    func testPanelAttachmentGeometry() {
        let main = CGRect(x: 100, y: 200, width: 300, height: 100)
        let panel = CGSize(width: 50, height: 40)
        XCTAssertEqual(ReeltonePanelGeometry.attachedFrame(mainFrame: main, panelSize: panel, attachment: .left), CGRect(x: 50, y: 260, width: 50, height: 40))
        XCTAssertEqual(ReeltonePanelGeometry.attachedFrame(mainFrame: main, panelSize: panel, attachment: .right), CGRect(x: 400, y: 260, width: 50, height: 40))
        XCTAssertEqual(ReeltonePanelGeometry.attachedFrame(mainFrame: main, panelSize: panel, attachment: .top), CGRect(x: 100, y: 300, width: 50, height: 40))
        XCTAssertEqual(ReeltonePanelGeometry.attachedFrame(mainFrame: main, panelSize: panel, attachment: .bottom), CGRect(x: 100, y: 160, width: 50, height: 40))
    }

    func testRestoredFramesClampOnlyWhenPresented() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let offscreen = CGRect(x: 1800, y: -200, width: 300, height: 200)

        XCTAssertEqual(
            ReeltonePanelGeometry.frameForPresentation(offscreen, visibleFrames: [screen]),
            CGRect(x: 1140, y: 0, width: 300, height: 200)
        )
        XCTAssertEqual(
            ReeltonePanelGeometry.frameForPresentation(
                CGRect(x: 100, y: 200, width: 300, height: 200),
                visibleFrames: [screen]
            ),
            CGRect(x: 100, y: 200, width: 300, height: 200)
        )
    }

    func testContinuousControlMappingClampsAndSupportsKnobs() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 100)
        XCTAssertEqual(ReeltoneControlMapping.fraction(point: CGPoint(x: -20, y: 40), in: rect, style: nil), 0)
        XCTAssertEqual(ReeltoneControlMapping.fraction(point: CGPoint(x: 140, y: 40), in: rect, style: nil), 1)
        XCTAssertEqual(ReeltoneControlMapping.fraction(point: CGPoint(x: 60, y: 40), in: rect, style: nil), 0.5)
        XCTAssertEqual(
            ReeltoneControlMapping.fraction(point: CGPoint(x: rect.maxX, y: rect.midY), in: rect, style: .knob),
            0.5,
            accuracy: 0.0001
        )
    }

    func testAuthoredSliderThumbKeepsNaturalSizeAndTracksValue() {
        let track = CGRect(x: 0, y: 0, width: 370, height: 27)
        let authored = CGSize(width: 16, height: 16)
        XCTAssertEqual(
            ReeltoneControlGeometry.sliderThumbRect(in: track, authoredThumbSize: authored, scale: 1, fraction: 0),
            CGRect(x: 0, y: 5.5, width: 16, height: 16)
        )
        XCTAssertEqual(
            ReeltoneControlGeometry.sliderThumbRect(in: track, authoredThumbSize: authored, scale: 1, fraction: 0.5),
            CGRect(x: 177, y: 5.5, width: 16, height: 16)
        )
        XCTAssertEqual(
            ReeltoneControlGeometry.sliderThumbRect(in: track, authoredThumbSize: authored, scale: 1, fraction: 1),
            CGRect(x: 354, y: 5.5, width: 16, height: 16)
        )
        XCTAssertEqual(
            ReeltoneControlGeometry.sliderThumbRect(
                in: CGRect(x: 0, y: 0, width: 740, height: 54),
                authoredThumbSize: authored,
                scale: 2,
                fraction: 0.5
            ),
            CGRect(x: 354, y: 11, width: 32, height: 32)
        )
    }

    func testPanelDisplayNamesAreSafeAndBounded() {
        XCTAssertEqual(ReeltoneSurfaceInventory.safePanelDisplayName("  Queue\nPanel\u{0000} "), "Queue Panel")
        XCTAssertEqual(ReeltoneSurfaceInventory.safePanelDisplayName("\n\t"), "Panel")
        XCTAssertEqual(ReeltoneSurfaceInventory.safePanelDisplayName(String(repeating: "x", count: 100)).count, 80)
    }

    func testOrderedHostsKeepDistinctVisualizerRegionsAndLiveScale() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"hosts","name":"Hosts","window":{"size":[100,80],"art":{"normal":"m.png"}},"regions":[
          {"component":"decoration","rect":[0,0,10,10],"art":{"normal":"d.png"}},
          {"component":"visualiser","rect":[10,10,30,20]},
          {"component":"decoration","rect":[45,10,5,5],"art":{"normal":"d.png"}},
          {"component":"visualiser","rect":[50,20,40,30]}
        ]}
        """#)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))
        let bridge = FakeBridge()
        var hosts: [FakeHost] = []
        let factory = ReeltoneComponentHostFactory { region, frame in
            guard region.component == .visualiser else { return nil }
            let host = FakeHost(component: .visualiser, frame: frame)
            hosts.append(host)
            return host
        }
        let view = makeView(inventory: inventory, manifest: manifest, bridge: bridge, factory: factory)

        XCTAssertEqual(view.hostedRegionComponents, [.visualiser, .visualiser])
        XCTAssertEqual(view.subviews.count, 4)
        XCTAssertTrue(view.subviews[1] === hosts[0].view)
        XCTAssertTrue(view.subviews[3] === hosts[1].view)
        XCTAssertEqual(view.hostedFrame(forRegionIndex: 1), NSRect(x: 10, y: 50, width: 30, height: 20))
        XCTAssertEqual(view.hostedFrame(forRegionIndex: 3), NSRect(x: 50, y: 30, width: 40, height: 30))

        view.setFrameSize(NSSize(width: 200, height: 160))
        view.layout()
        XCTAssertEqual(view.hostedFrame(forRegionIndex: 1), NSRect(x: 20, y: 100, width: 60, height: 40))
        XCTAssertEqual(view.hostedFrame(forRegionIndex: 3), NSRect(x: 100, y: 60, width: 80, height: 60))

        view.updateSpectrum([0.1, 0.5, 1])
        XCTAssertEqual(hosts.map(\.spectrumUpdateCount), [1, 1])
        view.updateTheme()
        XCTAssertEqual(hosts.map(\.themeUpdateCount), [1, 1])
        view.visibilityDidChange(true)
        view.visibilityDidChange(false)
        XCTAssertEqual(hosts.map(\.visibilityEvents), [[true, false], [true, false]])
        view.prepareForTeardown()
        XCTAssertEqual(hosts.map(\.teardownCount), [1, 1])
    }

    func testLiveEmbeddedHostsApplyAuthoredRowHeightAtSurfaceScale() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"rows","name":"Rows","window":{"size":[400,200],"art":{"normal":"m.png"}},"regions":[
          {"component":"trackList","rect":[0,0,200,100],"rowHeight":14},
          {"component":"library","rect":[200,0,200,100],"rowHeight":20}
        ]}
        """#)
        let regions = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest)?.main.regions)
        let playlist = try XCTUnwrap(ReeltoneComponentHostFactory.live.makeHost(regions[0], CGRect(x: 0, y: 0, width: 200, height: 100)) as? ReeltonePlaylistHost)
        let library = try XCTUnwrap(ReeltoneComponentHostFactory.live.makeHost(regions[1], CGRect(x: 0, y: 0, width: 200, height: 100)) as? ReeltoneLibraryHost)
        XCTAssertEqual(playlist.playlistView.embeddedRowHeightOverride, 14)
        XCTAssertEqual(library.libraryView.embeddedRowHeightOverride, 20)
        playlist.layout(in: CGRect(x: 0, y: 0, width: 400, height: 200))
        library.layout(in: CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertEqual(playlist.playlistView.embeddedRowHeightOverride, 28)
        XCTAssertEqual(library.libraryView.embeddedRowHeightOverride, 40)
        playlist.prepareForTeardown()
        library.prepareForTeardown()
    }

    func testPlaybackArtInvalidationAndAnimationVisibilityLifecycle() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"dynamic","name":"Dynamic","window":{"size":[100,80],"art":{"normal":"m.png","playing":"mp.png"}},"regions":[
          {"component":"decoration","rect":[0,0,20,20],"art":{"normal":"d.png","playing":"dp.png"}},
          {"component":"decoration","rect":[20,0,20,20],"frames":["a.png","b.png"],"fps":8,"drivenBy":"always"}
        ]}
        """#)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))
        let bridge = FakeBridge()
        let view = makeView(inventory: inventory, manifest: manifest, bridge: bridge)
        var invalidations: [Int?] = []
        view.invalidationObserver = { invalidations.append($0) }
        bridge.playbackState = .playing
        view.updatePlaybackState()
        XCTAssertTrue(invalidations.contains { $0 == nil })
        XCTAssertTrue(invalidations.contains { $0 == 0 })

        XCTAssertFalse(view.isAnimationTimerRunning)
        view.visibilityDidChange(true)
        XCTAssertTrue(view.isAnimationTimerRunning)
        view.visibilityDidChange(false)
        XCTAssertFalse(view.isAnimationTimerRunning)
        view.visibilityDidChange(true)
        view.prepareForTeardown()
        XCTAssertFalse(view.isAnimationTimerRunning)
    }

    func testUnicodeMetadataRendersWithPackagedFontFallback() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"unicode","name":"Unicode","fonts":{"display":{"builtin":"Silkscreen-Regular"}},"window":{"size":[320,40],"art":{"normal":"m.png"}},"regions":[
          {"component":"title","rect":[0,0,320,40],"size":18}
        ]}
        """#)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))
        let view = makeView(inventory: inventory, manifest: manifest, bridge: FakeBridge())
        view.updateTrack(Track(
            url: URL(fileURLWithPath: "/tmp/unicode.flac"),
            title: "曲名 🎵 موسيقى",
            artist: "Björk — アーティスト"
        ))

        let representation = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        XCTAssertGreaterThanOrEqual(representation.pixelsWide, 320)
        XCTAssertGreaterThanOrEqual(representation.pixelsHigh, 40)
    }

    func testAccessibilityActionsValuesAndKeyboardOperateControls() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"controls","name":"Controls","window":{"size":[240,40],"art":{"normal":"m.png"}},"regions":[
          {"component":"play","rect":[0,0,20,20]},
          {"component":"playPause","rect":[20,0,20,20]},
          {"component":"stop","rect":[40,0,20,20]},
          {"component":"prev","rect":[60,0,20,20]},
          {"component":"next","rect":[80,0,20,20]},
          {"component":"shuffle","rect":[100,0,20,20]},
          {"component":"repeatMode","rect":[120,0,20,20]},
          {"component":"seek","rect":[140,0,40,20],"controlStyle":"slider"},
          {"component":"volume","rect":[180,0,40,20],"controlStyle":"knob"},
          {"component":"close","rect":[220,0,10,20]},
          {"component":"minimise","rect":[230,0,10,20]}
        ]}
        """#)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))
        let bridge = FakeBridge()
        bridge.duration = 200
        bridge.currentTime = 50
        bridge.volume = 0.5
        let delegate = FakeSurfaceDelegate()
        let view = makeView(inventory: inventory, manifest: manifest, bridge: bridge)
        view.delegate = delegate
        view.updateTime(current: 50, duration: 200)
        let elements = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])

        XCTAssertTrue(elements[0].accessibilityPerformPress())
        XCTAssertEqual(bridge.playCount, 1)
        bridge.playbackState = .playing
        XCTAssertTrue(elements[1].accessibilityPerformPress())
        XCTAssertEqual(bridge.pauseCount, 1)
        XCTAssertTrue(elements[2].accessibilityPerformPress())
        XCTAssertTrue(elements[3].accessibilityPerformPress())
        XCTAssertTrue(elements[4].accessibilityPerformPress())
        XCTAssertEqual(bridge.stopCount, 1)
        XCTAssertEqual(bridge.previousCount, 1)
        XCTAssertEqual(bridge.nextCount, 1)
        XCTAssertTrue(elements[5].accessibilityPerformPress())
        XCTAssertTrue(elements[6].accessibilityPerformPress())
        XCTAssertTrue(bridge.shuffleEnabled)
        XCTAssertTrue(bridge.repeatEnabled)
        XCTAssertTrue(elements[7].accessibilityPerformIncrement())
        XCTAssertGreaterThan(bridge.lastSeekTime, 50)
        XCTAssertTrue(elements[8].accessibilityPerformDecrement())
        XCTAssertEqual(bridge.volume, 0.45, accuracy: 0.001)
        XCTAssertTrue(elements[9].accessibilityPerformPress())
        XCTAssertTrue(elements[10].accessibilityPerformPress())
        XCTAssertEqual(delegate.closeCount, 1)
        XCTAssertEqual(delegate.minimizeCount, 1)
        XCTAssertEqual(elements[7].accessibilityRole(), .slider)
        XCTAssertEqual(elements[7].accessibilityValue() as? NSNumber, NSNumber(value: 0.25))
        XCTAssertEqual((elements[8].accessibilityValue() as? NSNumber)?.doubleValue ?? -1, 0.45, accuracy: 0.001)

        view.keyDown(with: keyEvent(keyCode: 48, characters: "\t"))
        view.keyDown(with: keyEvent(keyCode: 36, characters: "\r"))
        XCTAssertEqual(bridge.playCount, 2)
    }

    func testTextRegionsAreExposedToAccessibility() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"text","name":"Text","window":{"size":[240,40],"art":{"normal":"m.png"}},"regions":[
          {"component":"title","rect":[0,0,120,20],"marquee":true},
          {"component":"elapsed","rect":[120,0,60,20]},
          {"component":"duration","rect":[180,0,60,20]}
        ]}
        """#)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))
        let view = makeView(inventory: inventory, manifest: manifest, bridge: FakeBridge())
        view.updateTrack(Track(url: URL(fileURLWithPath: "/tmp/a.flac"), title: "A Very Long Track Title", artist: "Artist"))
        view.updateTime(current: 65, duration: 245)
        let elements = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(elements.map { $0.accessibilityRole() }, [.staticText, .staticText, .staticText])
        XCTAssertEqual(elements.map { $0.accessibilityLabel() ?? "" }, ["Track Title", "Elapsed Time", "Duration"])
        XCTAssertEqual(elements[0].accessibilityValue() as? String, "Artist — A Very Long Track Title")
        XCTAssertEqual(elements[1].accessibilityValue() as? String, "1:05")
        XCTAssertEqual(elements[2].accessibilityValue() as? String, "4:05")
        view.visibilityDidChange(true)
        XCTAssertTrue(view.isAnimationTimerRunning)
        view.visibilityDidChange(false)
        XCTAssertFalse(view.isAnimationTimerRunning)
    }

    func testCoordinatorCreatesAndMovesDeclaredPanelTopologyWithIsolatedPersistence() throws {
        let manifest = try decode(#"""
        {"formatVersion":2,"id":"topology","name":"Topology","window":{"size":[300,100],"art":{"normal":"m.png"},"panels":{
          "left":{"size":[40,30],"attach":"left","visible":true,"art":{"normal":"l.png"},"regions":[]},
          "right":{"size":[50,30],"attach":"right","visible":true,"art":{"normal":"r.png"},"regions":[{"component":"equaliser","rect":[0,0,50,30]}]},
          "top":{"size":[60,20],"attach":"top","visible":false,"art":{"normal":"t.png"},"regions":[]},
          "bottom":{"size":[70,25],"attach":"bottom","visible":true,"art":{"normal":"b.png"},"regions":[]}
        }},"regions":[{"component":"trackList","rect":[0,0,100,80]}]}
        """#)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))
        let skin = ReeltoneLoadedSkin(
            manifest: manifest,
            rootURL: URL(fileURLWithPath: "/private/tmp"),
            resources: [:],
            imageInfo: [:]
        )
        let suite = "ReeltoneSurfaceCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let main = NSWindow(
            contentRect: NSRect(x: 100, y: 200, width: 300, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        var hosts: [FakeHost] = []
        let hostFactory = ReeltoneComponentHostFactory { region, frame in
            guard region.component == .trackList || region.component == .equaliser else { return nil }
            let host = FakeHost(component: region.component, frame: frame)
            hosts.append(host)
            return host
        }
        let coordinator = ReeltoneSurfaceCoordinator(
            mainWindow: main,
            skin: skin,
            inventory: inventory,
            scale: 1,
            identity: "topology-install",
            defaults: defaults,
            bridge: FakeBridge(),
            hostFactory: hostFactory
        )

        coordinator.showInitialPanels()
        XCTAssertEqual(coordinator.panelCount, 4)
        XCTAssertEqual(coordinator.panelFrame(named: "left"), NSRect(x: 60, y: 270, width: 40, height: 30))
        XCTAssertEqual(coordinator.panelFrame(named: "right"), NSRect(x: 400, y: 270, width: 50, height: 30))
        XCTAssertEqual(coordinator.panelFrame(named: "top"), NSRect(x: 100, y: 300, width: 60, height: 20))
        XCTAssertEqual(coordinator.panelFrame(named: "bottom"), NSRect(x: 100, y: 175, width: 70, height: 25))
        XCTAssertTrue(coordinator.panelIsAttached(named: "left"))
        XCTAssertTrue(coordinator.panelIsVisible(named: "left"))
        XCTAssertFalse(coordinator.panelIsVisible(named: "top"))
        XCTAssertEqual(hosts.map(\.component), [.trackList, .equaliser])
        XCTAssertTrue(coordinator.route(component: .trackList))
        XCTAssertTrue(coordinator.route(component: .equaliser))
        XCTAssertFalse(coordinator.route(component: .library))

        coordinator.mainVisibilityDidChange(false)
        XCTAssertFalse(coordinator.panelIsVisible(named: "left"))
        XCTAssertFalse(coordinator.panelIsVisible(named: "right"))
        XCTAssertFalse(coordinator.panelIsVisible(named: "bottom"))
        coordinator.mainVisibilityDidChange(true)
        XCTAssertTrue(coordinator.panelIsVisible(named: "left"))
        XCTAssertTrue(coordinator.panelIsVisible(named: "right"))
        XCTAssertTrue(coordinator.panelIsVisible(named: "bottom"))
        XCTAssertFalse(coordinator.panelIsVisible(named: "top"))

        main.setFrameOrigin(NSPoint(x: 125, y: 240))
        coordinator.mainWindowDidMove()
        XCTAssertEqual(coordinator.panelFrame(named: "right"), NSRect(x: 425, y: 310, width: 50, height: 30))

        coordinator.applyScale(2)
        XCTAssertEqual(main.frame.size, NSSize(width: 600, height: 200))
        XCTAssertEqual(coordinator.panelFrame(named: "right"), NSRect(x: 725, y: 280, width: 100, height: 60))

        coordinator.setAlwaysOnTop(true)
        XCTAssertTrue(coordinator.allWindows.allSatisfy { $0.level == .floating })
        coordinator.togglePanel("left")
        XCTAssertFalse(coordinator.panelIsVisible(named: "left"))
        XCTAssertEqual(
            ReeltoneSkinState.panelVisibility(identity: "topology-install", surfaceID: .panel("left"), in: defaults),
            false
        )
        XCTAssertNil(
            ReeltoneSkinState.panelVisibility(identity: "other-install", surfaceID: .panel("left"), in: defaults)
        )

        let lifecycleSnapshot = coordinator.captureLayout()
        XCTAssertEqual(lifecycleSnapshot.skinIdentity, "topology-install")
        XCTAssertEqual(lifecycleSnapshot.panels.count, 4)
        coordinator.togglePanel("left")
        XCTAssertTrue(coordinator.panelIsVisible(named: "left"))
        coordinator.restoreLayout(lifecycleSnapshot)
        XCTAssertFalse(coordinator.panelIsVisible(named: "left"))

        let foreignSnapshot = ReeltoneSurfaceLayoutSnapshot(
            skinIdentity: "other-install",
            panels: lifecycleSnapshot.panels.map {
                .init(surfaceID: $0.surfaceID, frame: $0.frame, wasVisible: true, wasAttached: $0.wasAttached)
            }
        )
        coordinator.restoreLayout(foreignSnapshot)
        XCTAssertFalse(coordinator.panelIsVisible(named: "left"), "A different skin identity must not restore panel state")

        coordinator.prepareForTeardown()
        XCTAssertEqual(coordinator.panelCount, 0)
        XCTAssertEqual(coordinator.allWindows, [main])
        XCTAssertEqual(hosts.map(\.teardownCount), [1, 1])
        main.contentView = nil
    }

    func testRepeatedSkinTopologyRebuildsLeaveNoPanelsHostsOrAnimationTimers() throws {
        let manifestA = try decode(#"""
        {"formatVersion":2,"id":"topology-a","name":"Topology A","window":{"size":[300,100],"art":{"normal":"a.png"},"panels":{
          "queue":{"size":[140,80],"attach":"bottom","visible":true,"art":{"normal":"queue.png"},"regions":[
            {"component":"trackList","rect":[0,0,140,80]}
          ]},
          "meter":{"size":[80,100],"attach":"right","visible":true,"art":{"normal":"meter.png"},"regions":[
            {"component":"visualiser","rect":[0,0,80,100],"frames":["m0.png","m1.png"],"fps":12,"drivenBy":"always"}
          ]}
        }},"regions":[{"component":"equaliser","rect":[0,0,100,100]}]}
        """#)
        let manifestB = try decode(#"""
        {"formatVersion":2,"id":"topology-b","name":"Topology B","window":{"size":[520,180],"art":{"normal":"b.png"},"panels":{
          "library":{"size":[240,160],"attach":"left","visible":true,"art":{"normal":"library.png"},"regions":[
            {"component":"library","rect":[0,0,240,160]}
          ]}
        }},"regions":[
          {"component":"trackList","rect":[0,0,260,180]},
          {"component":"visualiser","rect":[260,0,260,180],"frames":["v0.png","v1.png"],"fps":10,"drivenBy":"always"}
        ]}
        """#)
        let suite = "ReeltoneSurfaceCoordinatorRebuildTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let main = NSWindow(
            contentRect: NSRect(x: 100, y: 200, width: 300, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        for cycle in 0..<6 {
            let manifest = cycle.isMultiple(of: 2) ? manifestA : manifestB
            let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: manifest))
            let skin = ReeltoneLoadedSkin(
                manifest: manifest,
                rootURL: URL(fileURLWithPath: "/private/tmp"),
                resources: [:],
                imageInfo: [:]
            )
            var hosts: [FakeHost] = []
            let hostFactory = ReeltoneComponentHostFactory { region, frame in
                guard region.ownsSingletonHost else { return nil }
                let host = FakeHost(component: region.component, frame: frame)
                hosts.append(host)
                return host
            }
            let coordinator = ReeltoneSurfaceCoordinator(
                mainWindow: main,
                skin: skin,
                inventory: inventory,
                scale: 1,
                identity: "\(manifest.id)-install",
                defaults: defaults,
                bridge: FakeBridge(),
                hostFactory: hostFactory
            )

            coordinator.showInitialPanels()
            coordinator.mainVisibilityDidChange(true)
            XCTAssertEqual(coordinator.panelCount, cycle.isMultiple(of: 2) ? 2 : 1)
            XCTAssertEqual(hosts.count, 3)
            XCTAssertEqual(coordinator.allWindows.count, coordinator.panelCount + 1)
            XCTAssertEqual(main.contentView?.frame.size, main.frame.size)

            coordinator.prepareForTeardown()
            XCTAssertEqual(coordinator.panelCount, 0)
            XCTAssertEqual(coordinator.allWindows, [main])
            XCTAssertEqual(coordinator.runningAnimationTimerCount, 0)
            XCTAssertTrue(hosts.allSatisfy { $0.teardownCount == 1 })
            XCTAssertTrue(hosts.allSatisfy { $0.view.superview == nil })
        }
        main.contentView = nil
    }

    private func decode(_ json: String) throws -> ReeltoneManifest {
        try ReeltoneManifestDecoder.decode(Data(json.utf8))
    }

    private func makeView(
        inventory: ReeltoneSurfaceInventory,
        manifest: ReeltoneManifest,
        bridge: FakeBridge,
        factory: ReeltoneComponentHostFactory = ReeltoneComponentHostFactory { _, _ in nil }
    ) -> ReeltoneSurfaceView {
        let skin = ReeltoneLoadedSkin(manifest: manifest, rootURL: URL(fileURLWithPath: "/private/tmp"), resources: [:], imageInfo: [:])
        return ReeltoneSurfaceView(surface: inventory.main, skin: skin, bridge: bridge, hostFactory: factory)
    }

    private func keyEvent(keyCode: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}

private final class FakeBridge: ReeltoneComponentBridging {
    var playbackState: PlaybackState = .stopped
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0
    var shuffleEnabled = false
    var repeatEnabled = false
    var currentTrack: Track?
    var playCount = 0
    var pauseCount = 0
    var stopCount = 0
    var previousCount = 0
    var nextCount = 0
    var lastSeekTime: TimeInterval = 0

    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() { stopCount += 1 }
    func previous() { previousCount += 1 }
    func next() { nextCount += 1 }
    func seek(to time: TimeInterval) { lastSeekTime = time }
}

private final class FakeHost: ReeltoneComponentHosting {
    let component: ReeltoneComponent
    let view: NSView
    var spectrumUpdateCount = 0
    var themeUpdateCount = 0
    var visibilityEvents: [Bool] = []
    var teardownCount = 0

    init(component: ReeltoneComponent, frame: NSRect) {
        self.component = component
        view = NSView(frame: frame)
    }

    func updateSpectrum(_ levels: [Float]) { spectrumUpdateCount += 1 }
    func updateTheme() { themeUpdateCount += 1 }
    func visibilityDidChange(_ visible: Bool) { visibilityEvents.append(visible) }
    func prepareForTeardown() {
        teardownCount += 1
        view.removeFromSuperview()
    }
}

private final class FakeSurfaceDelegate: ReeltoneSurfaceViewDelegate {
    var closeCount = 0
    var minimizeCount = 0
    func reeltoneSurfaceViewDidRequestClose(_ view: ReeltoneSurfaceView) { closeCount += 1 }
    func reeltoneSurfaceViewDidRequestMinimise(_ view: ReeltoneSurfaceView) { minimizeCount += 1 }
    func reeltoneSurfaceView(_ view: ReeltoneSurfaceView, togglePanel name: String) {}
    func reeltoneSurfaceViewDidRequestLibraryBack(_ view: ReeltoneSurfaceView) {}
}
