import XCTest
import AppKit
import ZIPFoundation
@testable import NullPlayer

/// B265, B266 — a film in the video component's own window beside a player that has no holder
/// for it (Winamp Single GUI's `Video` while the player shows its Library pane).
///
/// Windows → Video Player asked the *player* for the box the detached window held, got nil and hid
/// nothing (B265); closing the detached window reattached through the player, which fell back to
/// reopening the very window being closed (B266). The fixture's player holds the video in a pane
/// it keeps hidden, so the player never takes the film.
final class WinampModernVideoDetachTests: XCTestCase {

    @MainActor
    func testTheMenuTogglePutsAwayAndBringsBackADetachedFilm() throws {
        let (controller, video) = try makeDetachedSession()
        let detached = try XCTUnwrap(controller.auxiliaryContainer(id: "Video")).window

        XCTAssertTrue(controller.toggleVideo())
        XCTAssertFalse(detached.isVisible, "the toggle hides the window the film is in")
        XCTAssertFalse(video.isVideoOutputHosted)
        XCTAssertFalse(video.isVideoOutputVisible, "and the film with it, not into a window of ours")

        XCTAssertTrue(controller.toggleVideo())
        XCTAssertTrue(detached.isVisible, "toggled back, the film returns where the skin puts it")
        XCTAssertTrue(video.isVideoOutputHosted)
    }

    @MainActor
    func testClosingTheDetachedWindowWithNoPlayerHolderLeavesItClosed() throws {
        let (controller, video) = try makeDetachedSession()
        let detached = try XCTUnwrap(controller.auxiliaryContainer(id: "Video")).window

        controller.setAuxiliaryWindow(id: "Video", visible: false)
        XCTAssertFalse(detached.isVisible, "closing must not reopen the window being closed")
        XCTAssertFalse(video.isVideoOutputHosted)
        XCTAssertFalse(video.isVideoOutputVisible)
    }

    /// A skin switch with a film loaded re-hosts it only after `rehostVideoDelay`: parked one turn
    /// after the load, the Video window it opened could drop out of the screen composite.
    @MainActor
    func testASkinLoadReHostsTheFilmOnlyAfterTheDelay() throws {
        let (controller, video) = try makeLoadedSession()
        // Fixed, not derived from the delay, so a shorter delay fails here: a one-turn re-host, or
        // one 0.05 s late, drew the blank window, and both are long done after 0.1 s.
        spinRunLoop(for: 0.1)
        XCTAssertFalse(video.isVideoOutputHosted, "not parked during the load's aftermath")

        spinRunLoop(for: 2) { video.isVideoOutputHosted }
        XCTAssertTrue(video.isVideoOutputHosted, "parked once the delay has passed")
        XCTAssertEqual(controller.auxiliaryContainer(id: "Video")?.window.isVisible, true)
    }

    /// Windows → Video Player during the wait is the user's word on the film: the re-host is dropped.
    @MainActor
    func testTheMenuToggleDuringTheWaitDropsTheReHost() throws {
        let (controller, video) = try makeLoadedSession()
        // The outgoing skin's teardown left the film in NullPlayer's own window.
        video.window?.orderFront(nil)
        XCTAssertFalse(controller.toggleVideo(), "the skin hands the hide to NullPlayer's window")

        spinRunLoop(for: 1)
        XCTAssertFalse(video.isVideoOutputHosted)
        XCTAssertNotEqual(controller.auxiliaryContainer(id: "Video")?.window.isVisible, true)
    }

    // MARK: - Fixtures

    /// A loaded skin with a film in its detached `Video` window.
    @MainActor
    private func makeDetachedSession() throws
        -> (WinampModernMainWindowController, VideoPlayerWindowController) {
        let (controller, video) = try makeLoadedSession()
        XCTAssertTrue(controller.hostVideoOutput())
        XCTAssertEqual(controller.auxiliaryContainer(id: "Video")?.window.isVisible, true,
                       "a player with no holder sends the film to the component's own window")
        XCTAssertTrue(video.isVideoOutputHosted)
        return (controller, video)
    }

    /// The skin just loaded with a film playing, its re-host still pending.
    @MainActor
    private func makeLoadedSession() throws
        -> (WinampModernMainWindowController, VideoPlayerWindowController) {
        let video = VideoPlayerWindowController()
        video.debugSetCurrentTitleForTesting("Film")
        WindowManager.shared.debugSetVideoPlayerWindowControllerForTesting(video)
        addTeardownBlock { @MainActor in
            WindowManager.shared.debugSetVideoPlayerWindowControllerForTesting(nil)
            if let window = video.window {
                window.parent?.removeChildWindow(window)
                window.orderOut(nil)
            }
        }

        let window = WinampModernSkinWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 116),
                                            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = WinampModernMainWindowController(window: window)
        addTeardownBlock { @MainActor in
            controller.auxiliaryContainer(id: "Video")?.window.orderOut(nil)
            window.contentView = nil
        }
        controller.loadSkin(at: try makeArchive(xml: Self.skin))
        XCTAssertNil(controller.loadFailure, "fixture must load, or this test proves nothing")
        XCTAssertEqual(controller.videoDetachContainerID, "Video",
                       "the fixture must route video to the player, with `Video` as its own window")
        return (controller, video)
    }

    private static let skin = """
    <WasabiXML>
      <elements><bitmap id="bg" file="sheet.png" x="0" y="0" w="8" h="8"/></elements>
      <groupdef id="video.pane">
        <component id="playervideo" x="0" y="0" w="200" h="100" noshowcmdbar="1"
          param="{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}"/>
      </groupdef>
      <container id="main">
        <layout id="normal" w="200" h="116">
          <group id="video.pane" x="0" y="0" w="200" h="100" visible="0"/>
        </layout>
      </container>
      <container id="Video" name="Video" dynamic="1" default_visible="0"
        component="guid:{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}">
        <layout id="normal" w="200" h="150">
          <component id="video" x="0" y="0" w="200" h="150" noshowcmdbar="1"
            param="{F0816D7B-FFFC-4343-80F2-E8199AA15CC3}"/>
        </layout>
      </container>
    </WasabiXML>
    """

    /// Runs the main run loop for `seconds`, or until `done` holds.
    private func spinRunLoop(for seconds: TimeInterval, until done: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: min(deadline, Date().addingTimeInterval(0.02)))
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernVideoDetachTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeArchive(xml: String) throws -> URL {
        let url = try makeTemporaryDirectory().appendingPathComponent("Synthetic.wal")
        let archive = try Archive(url: url, accessMode: .create)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                   bitsPerPixel: 0)!
        let png = rep.representation(using: .png, properties: [:])!
        for (path, payload) in [("skin.xml", Data(xml.utf8)), ("sheet.png", png)] {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(payload.count),
                                 compressionMethod: .none) { position, size in
                let start = Int(position)
                guard start < payload.count else { return Data() }
                return payload.subdata(in: start..<min(payload.count, start + size))
            }
        }
        return url
    }
}
