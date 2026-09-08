import XCTest
import AppKit
@testable import NullPlayer

@MainActor
final class SonosRoomMixerTests: XCTestCase {
    func testSonosMenuAlwaysIncludesRoomWindowAndRefresh() throws {
        let output = ContextMenuBuilder.buildMenuBarOutputMenu()
        let sonos = try XCTUnwrap(output.items.first { $0.title == "Sonos" }?.submenu)
        XCTAssertEqual(sonos.items.first?.title, "Rooms & Volume…")
        let refresh = try XCTUnwrap(sonos.items.first { $0.title == "Refresh" })
        XCTAssertTrue(refresh.isEnabled)
        XCTAssertEqual(refresh.action, #selector(MenuActions.refreshSonosRooms))
    }

    func testRoomWritesCoalesceIndependently() async {
        let first = expectation(description: "First room send started")
        let second = expectation(description: "Other room remains responsive")
        let final = expectation(description: "Latest value delivered")
        var gate: CheckedContinuation<Void, Never>?
        var sent: [String: [Int]] = [:]
        let mixer = SonosRoomMixer(roomIDs: { ["a", "b"] }, readVolume: { _ in 10 },
            writeVolume: { value, id in
                sent[id, default: []].append(value)
                if id == "a", value == 20 {
                    await withCheckedContinuation { gate = $0; first.fulfill() }
                } else if id == "b" { second.fulfill() }
                else if value == 80 { final.fulfill() }
            })
        mixer.setVolume(20, room: "a")
        await fulfillment(of: [first], timeout: 2)
        mixer.setVolume(40, room: "a")
        mixer.setVolume(80, room: "a")
        mixer.setVolume(30, room: "b")
        await fulfillment(of: [second], timeout: 2)
        gate?.resume()
        await fulfillment(of: [final], timeout: 2)
        XCTAssertEqual(sent["a"], [20, 80])
        XCTAssertEqual(sent["b"], [30])
        XCTAssertEqual(mixer.volumes["a"], 80)
    }

    func testOldPollCannotOverwriteNewSliderValue() async {
        let reading = expectation(description: "Read began")
        let written = expectation(description: "Write finished")
        var gate: CheckedContinuation<Int, Never>?
        let mixer = SonosRoomMixer(roomIDs: { ["kitchen"] }, readVolume: { _ in
            await withCheckedContinuation { gate = $0; reading.fulfill() }
        }, writeVolume: { _, _ in written.fulfill() })
        let poll = Task { await mixer.refreshVolumes() }
        await fulfillment(of: [reading], timeout: 2)
        mixer.setVolume(67, room: "kitchen")
        await fulfillment(of: [written], timeout: 2)
        gate?.resume(returning: 12)
        await poll.value
        XCTAssertEqual(mixer.volumes["kitchen"], 67)
    }

    func testManyRoomsUseAtMostFourReadsAndKeepPerRoomErrors() async {
        let ids = (0..<32).map { "room-\($0)" }
        var active = 0
        var maximum = 0
        var read: Set<String> = []
        let mixer = SonosRoomMixer(roomIDs: { ids }, readVolume: { id in
            active += 1
            maximum = max(maximum, active)
            defer { active -= 1 }
            await Task.yield()
            read.insert(id)
            if id == "room-5" { throw CastError.deviceOffline }
            return 25
        }, writeVolume: { _, _ in XCTFail("Polling must never change speaker volume") })
        await mixer.refreshVolumes()
        XCTAssertEqual(read, Set(ids))
        XCTAssertLessThanOrEqual(maximum, 4)
        XCTAssertGreaterThan(maximum, 1)
        XCTAssertEqual(mixer.volumes.count, 31)
        XCTAssertNotNil(mixer.errors["room-5"])
        XCTAssertNil(mixer.volumes["room-5"])
    }

    func testManyRoomListScrollsAndKeepsFooterOutsideScrollView() async {
        _ = NSApplication.shared
        let rooms = (0..<32).map { index in
            UPnPManager.SonosRoomSummary(id: "room-\(index)", name: "Room \(index)",
                isGroupCoordinator: false, isInGroup: false, groupCoordinatorUDN: nil,
                groupCoordinatorName: nil)
        }
        let mixer = SonosRoomMixer(roomIDs: { rooms.map(\.id) }, readVolume: { _ in 25 },
                                    writeVolume: { _, _ in XCTFail("Rendering must never change volume") })
        await mixer.refreshVolumes()
        let view = SonosWindowView(frame: NSRect(x: 0, y: 0, width: 275, height: 270),
                                   mixer: mixer, rooms: { rooms })
        view.refresh()
        view.layoutSubtreeIfNeeded()
        guard let scroll = view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let document = scroll.documentView else { return XCTFail("Missing room list") }
        XCTAssertEqual(document.subviews.count, 32)
        XCTAssertGreaterThan(document.frame.height, scroll.contentSize.height)
        XCTAssertTrue(scroll.hasVerticalScroller)
        let footer = view.subviews.compactMap { $0 as? NSButton }
        XCTAssertEqual(footer.count, 2)
        for button in footer { XCTAssertFalse(button.frame.intersects(scroll.frame)) }
        document.scroll(NSPoint(x: 0, y: document.bounds.maxY))
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        XCTAssertTrue(document.subviews.last!.frame.intersects(scroll.documentVisibleRect))
    }

    func testRestoredSonosWindowPreservesTallRoomListAndTopEdge() {
        let frame = NSRect(x: 50, y: 100, width: 450, height: 700)
        let restored = WindowManager.normalizedModernCenterStackRestoredFrame(frame, kind: .sonos,
            mainWidth: 350, minimumWidth: 275, targetHeight: 116,
            peppyMeterFloor: 203, peppyMeterLegacyDoubleHeight: 232)
        XCTAssertEqual(restored, frame)
        let short = NSRect(x: 50, y: 100, width: 200, height: 50)
        let normalized = WindowManager.normalizedModernCenterStackRestoredFrame(short, kind: .sonos,
            mainWidth: 350, minimumWidth: 275, targetHeight: 116,
            peppyMeterFloor: 203, peppyMeterLegacyDoubleHeight: 232)
        XCTAssertEqual(normalized.height, 232)
        XCTAssertEqual(normalized.width, 275)
        XCTAssertEqual(normalized.maxY, short.maxY)
    }

    func testEmptyWindowLaysOutRefreshAndRendersRoomFixtures() async throws {
        _ = NSApplication.shared
        let wm = WindowManager.shared
        let oldMode = wm.uiMode
        defer { wm.uiMode = oldMode }
        for mode in [PlayerUIMode.classic, .modern, .metal] {
            wm.uiMode = mode
            if let family = mode.modernSkinFamily { ModernSkinEngine.shared.loadDefaultSkin(for: family) }
            for count in [0, 32] {
                let rooms = (0..<count).map { index in
                    UPnPManager.SonosRoomSummary(id: "fixture-\(index)",
                        name: ["Living Room", "Kitchen", "Dining Room", "Upstairs Bedroom", "Patio"][index % 5] + (index >= 5 ? " \(index)" : ""),
                        isGroupCoordinator: false, isInGroup: false,
                        groupCoordinatorUDN: nil, groupCoordinatorName: nil)
                }
                let mixer = SonosRoomMixer(roomIDs: { rooms.map(\.id) }, readVolume: { _ in 25 }, writeVolume: { _, _ in })
                await mixer.refreshVolumes()
                let view = SonosWindowView(frame: NSRect(x: 0, y: 0, width: 344, height: 360),
                                           mixer: mixer, rooms: { rooms })
                view.refresh()
                view.layoutSubtreeIfNeeded()
                let refresh = try XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Refresh" })
                XCTAssertGreaterThan(refresh.frame.width, 40)
                XCTAssertGreaterThan(refresh.frame.height, 15)
                XCTAssertTrue(view.bounds.contains(refresh.frame))
                XCTAssertTrue(refresh.isEnabled)
                if let directory = ProcessInfo.processInfo.environment["SONOS_RENDER_DUMP"] {
                    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("sonos-\(mode.rawValue)-\(count).png"))
                }
            }
        }
    }
}
