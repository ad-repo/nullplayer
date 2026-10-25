import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import NullPlayer

// The Sonique render probe: every mode of every skin through `SoniqueSkinRenderer`, the window's own
// draw path, written as `<out>/<skin>__<nav|mid|small>.png` at one skin pixel per pixel. Flags in
// `skills/sonique-skin-guide/reference/harness.md`.
final class SoniqueSkinRenderProbeTests: XCTestCase {
    func testRenderSkinOrCorpus() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["SONIQUE_SKIN"], !path.isEmpty, let out = env["SONIQUE_RENDER_OUT"], !out.isEmpty else {
            throw XCTSkip("Set SONIQUE_SKIN and SONIQUE_RENDER_OUT. See skills/sonique-skin-guide/reference/harness.md.")
        }
        let skins = SoniqueSkinCensusTests.skins(at: path)
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        // `SONIQUE_RENDER_STATE=playing` draws the lit play/stop, both drawers open with the
        // navigator's dials turned, and half-filled lines and rings at full volume; the default is the oracle's state:
        // stopped with an empty playlist, shuffle and repeat on (its registry's `ShufflePlay` and
        // `RepeatMode`; that is loop-one, which NullPlayer cannot show, and repeat-all's light is
        // nearer it in 310 mid captures than none), its knobs at their first frame (the prefix has
        // no sound device). `drawer` is that state with the navigator's drawer open, as the oracle's
        // audio controls screen (`-showwindow 3 6`) shows it. The navigator shows an empty screen with
        // the back ball, nearest the oracle's setup › skins, except in `menu`, its menu screen.
        let playing = env["SONIQUE_RENDER_STATE"] == "playing"
        let drawerOpen = playing || env["SONIQUE_RENDER_STATE"] == "drawer"
        let screen: SoniqueSkinNavScreen = env["SONIQUE_RENDER_STATE"] == "menu" ? .menu : .blank
        var host = SoniqueSkinHostState(shuffle: true, repeatAll: true, volume: 0)
        host.version = "1.96"
        if playing {
            host.volume = 1
            host.playState = .playing
            host.trackNumber = 1
            host.title = "05 - Bella Ciao.mp3"
            host.songProgress = 0.5
            host.listProgress = 0.5
            host.elapsedSeconds = 3_923
            host.blinkersLit = true
            host.amp = 0.75
            host.balance = 0.25
            host.pitch = 1
            host.eq = (0..<SoniqueSkinScene.eqSliders).map { Double($0) / Double(SoniqueSkinScene.eqSliders - 1) }
        }
        var rendered = 0
        for file in skins {
            let name = file.deletingPathExtension().lastPathComponent
            guard let skin = try? SoniqueSkinLoader.load(contentsOf: file) else {
                HarnessOutput.emit("RENDER \(name) FAILED")
                continue
            }
            for (mode, tag) in [(SoniqueSkin.Mode.navigator, "nav"), (.mid, "mid"), (.small, "small")] {
                let scene = SoniqueSkinScene(skin: skin, state: .init(mode: mode, host: host, smallDrawer: playing ? .top : nil,
                                                                       navDrawerOpen: drawerOpen, navScreen: screen))
                guard let image = SoniqueSkinRenderer.render(scene) else {
                    HarnessOutput.emit("RENDER \(name) \(tag) EMPTY")
                    continue
                }
                let url = URL(fileURLWithPath: out).appendingPathComponent("\(name)__\(tag).png")
                let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                CGImageDestinationAddImage(destination, image, nil)
                XCTAssertTrue(CGImageDestinationFinalize(destination))
                HarnessOutput.emit("RENDER \(name) \(tag) \(image.width)x\(image.height) origin=\(scene.canvas.left),\(scene.canvas.top)")
                rendered += 1
            }
        }
        HarnessOutput.emit("RENDERED \(rendered) of \(skins.count * 3)")
    }
}
