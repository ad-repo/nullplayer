import XCTest
import AppKit
import ZIPFoundation
@testable import NullPlayer

/// B98 — switching `.wal` skins left NullPlayer's own open windows wearing the outgoing skin.
///
/// The Media Library, the playlist, the equalizer and the visualization windows are painted from
/// `WinampModernSurfaceStyle`, derived from the loaded skin's palette. None of them has a handle on
/// the skin controller, so they learn that the palette moved from `.hostedSurfaceStyleDidChange` —
/// and `PlexBrowserView`, the Media Library in this mode, caches its resolved style and drops that
/// cache only on that notification. Until B98 the notification was posted by a colour-theme switch
/// and by nothing else, so loading a *different skin* changed every surface the renderer draws and
/// none of the surfaces we draw ourselves. Closing and reopening the window was the only cure,
/// because that rebuilt the view.
///
/// So what these tests pin is not the palette — that is Phase 16's — but the announcement: a skin
/// load tells the fallback windows, whether or not the load succeeded.
final class WinampModernB98Tests: XCTestCase {

    @MainActor
    func testLoadingASkinTellsTheFallbackWindowsThePaletteMoved() throws {
        let controller = makeController()
        let posts = countPosts()
        controller.loadSkin(at: try makeArchive(xml: Self.skin))
        XCTAssertNil(controller.loadFailure, "fixture must load, or this test proves nothing")
        XCTAssertGreaterThanOrEqual(posts.count, 1,
                                    "a new skin is a new palette: the windows we draw ourselves are "
                                    + "still open in front of it and have no other way to hear about it")
    }

    /// The failure path posts too. A placeholder has no palette, so `winampModernSurfaceStyle` is nil
    /// from here on and those windows must fall back to their classic drawing rather than keep
    /// painting a skin that is gone.
    @MainActor
    func testAFailedLoadTellsThemAsWell() throws {
        let controller = makeController()
        let directory = try makeTemporaryDirectory()
        let notAnArchive = directory.appendingPathComponent("broken.wal")
        try Data("this is not a zip".utf8).write(to: notAnArchive)

        let posts = countPosts()
        controller.loadSkin(at: notAnArchive)
        XCTAssertNotNil(controller.loadFailure, "fixture must fail, or this test proves nothing")
        XCTAssertGreaterThanOrEqual(posts.count, 1)
    }

    // MARK: - Fixtures

    /// Built through the designated initializer rather than `init()`, which would load whichever skin
    /// the machine running the tests happens to have selected.
    @MainActor
    private func makeController() -> WinampModernMainWindowController {
        let window = WinampModernSkinWindow(contentRect: NSRect(x: 0, y: 0, width: 275, height: 116),
                                            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let controller = WinampModernMainWindowController(window: window)
        addTeardownBlock { @MainActor in
            window.contentView = nil
            _ = controller
        }
        return controller
    }

    /// A live count of `.hostedSurfaceStyleDidChange` posts, removed when the test ends.
    private func countPosts() -> PostCounter {
        let counter = PostCounter()
        let token = NotificationCenter.default.addObserver(
            forName: .hostedSurfaceStyleDidChange, object: nil, queue: nil) { _ in
                counter.count += 1
            }
        addTeardownBlock { NotificationCenter.default.removeObserver(token) }
        return counter
    }

    final class PostCounter {
        var count = 0
    }

    private static let skin = """
    <WasabiXML>
      <elements><bitmap id="bg" file="sheet.png" x="0" y="0" w="8" h="8"/></elements>
      <container id="main">
        <layout id="normal" w="200" h="116"/>
      </container>
    </WasabiXML>
    """

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinampModernB98Tests-\(UUID().uuidString)", isDirectory: true)
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
