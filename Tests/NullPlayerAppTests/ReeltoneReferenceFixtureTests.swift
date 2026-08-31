import AppKit
import XCTest
@testable import NullPlayer

/// Opt-in acceptance coverage for the uncommitted official CC0 Aqua Glass reference package.
/// Run with REELTONE_AQUA_GLASS_ROOT pointing at its extracted root. Provenance and the official
/// archive digest are recorded in docs/reeltone-compatibility.md; third-party art stays local.
final class ReeltoneReferenceFixtureTests: XCTestCase {
    func testAquaGlassLoadsAndRendersAtOneAndTwoBackingScaleWhenProvided() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["REELTONE_AQUA_GLASS_ROOT"] else {
            throw XCTSkip("Set REELTONE_AQUA_GLASS_ROOT to run the local Aqua Glass acceptance fixture")
        }
        let fixtureURL = URL(fileURLWithPath: fixturePath, isDirectory: true)
        let skin = try ReeltoneSkinLoader().loadDirectory(at: fixtureURL)
        let inventory = try XCTUnwrap(ReeltoneSurfaceInventory(manifest: skin.manifest))

        XCTAssertEqual(skin.manifest.id, "com.example.reeltone.aqua-glass")
        XCTAssertEqual(skin.manifest.license, "CC0-1.0")
        XCTAssertEqual(inventory.main.authoredSize, .init(width: 960, height: 384))
        XCTAssertEqual(inventory.main.regions.count, 22)
        XCTAssertTrue(skin.diagnostics.isEmpty)
        XCTAssertTrue(inventory.diagnostics.isEmpty)

        let bridge = ReferenceFixtureBridge()
        bridge.currentTime = 73
        bridge.duration = 245
        bridge.volume = 0.62
        bridge.playbackState = .playing
        let view = ReeltoneSurfaceView(
            surface: inventory.main,
            skin: skin,
            bridge: bridge,
            hostFactory: .init(makeHost: { _, _ in nil })
        )
        view.updateTrack(Track(
            url: URL(fileURLWithPath: "/tmp/aqua-acceptance.flac"),
            title: "Aqua Glass Acceptance",
            artist: "NullPlayer"
        ))
        view.updateTime(current: bridge.currentTime, duration: bridge.duration)
        view.updateSpectrum((0..<64).map { Float($0 % 17) / 16 })
        view.updatePlaybackState()

        let outputRoot = ProcessInfo.processInfo.environment["REELTONE_ACCEPTANCE_OUTPUT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let outputRoot {
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        }
        for backingScale in [1, 2] {
            let representation = try XCTUnwrap(Self.render(view: view, backingScale: backingScale))
            XCTAssertEqual(representation.pixelsWide, 960 * backingScale)
            XCTAssertEqual(representation.pixelsHigh, 384 * backingScale)
            if let outputRoot {
                let output = outputRoot.appendingPathComponent("aqua-glass-\(backingScale)x.png")
                try XCTUnwrap(representation.representation(using: .png, properties: [:])).write(to: output)
            }
        }
        view.prepareForTeardown()
    }

    private static func render(view: ReeltoneSurfaceView, backingScale: Int) -> NSBitmapImageRep? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width) * backingScale,
            pixelsHigh: Int(view.bounds.height) * backingScale,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        representation.size = view.bounds.size
        guard let graphics = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        view.renderFlattened(in: graphics.cgContext)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }
}

private final class ReferenceFixtureBridge: ReeltoneComponentBridging {
    var playbackState: PlaybackState = .stopped
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 0
    var shuffleEnabled = false
    var repeatEnabled = false
    var currentTrack: Track?

    func play() { playbackState = .playing }
    func pause() { playbackState = .paused }
    func stop() { playbackState = .stopped }
    func previous() {}
    func next() {}
    func seek(to time: TimeInterval) { currentTime = time }
}
