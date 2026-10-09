import AppKit
import XCTest
@testable import NullPlayer

// The Audion face harness: one machine-readable line per measured fact, inside a `FACE <name>`
// block, parsed by `scripts/audion_face_census.sh` and `scripts/audion_render_sweep.sh`. It draws
// through `AudionFaceScene` and `AudionFaceRenderer`, the path the face window uses, so a capture is
// what the screen shows. Every `AUDION_*` flag is documented once, in
// `skills/audion-face-guide/reference/harness.md`; add a flag there in the change that adds it here.
//
// Lines go through `HarnessOutput.emit`, never `print`: see that type for the loss it prevents.

/// The flags of one run.
struct AudionFaceProbe {
    let env: [String: String]

    /// Each name in `AUDION_RENDER_STATE` (comma-separated, default `stopped`) as a host state.
    /// Every one pins Reduce Motion on, as the FaceKit oracle does, unless `AUDION_RENDER_CLOCK`
    /// asks for motion.
    var states: [(name: String, host: AudionFaceHostState)] {
        (env["AUDION_RENDER_STATE"] ?? "stopped").split(separator: ",").map(String.init).compactMap { name in
            var host = AudionFaceHostState()
            host.reduceMotion = env["AUDION_RENDER_CLOCK"] == nil
            switch name {
            case "stopped": break
            case "playing", "paused", "connecting", "streaming", "lag":
                // The oracle's playing state: 1:23 into 3:33, fixed text, no track index.
                host.playState = name == "paused" ? .paused : .playing
                host.elapsedSeconds = 83
                host.durationSeconds = 213
                host.title = "A Fairly Long Track Title For The Oracle"
                host.artist = "Harness Artist"
                host.album = "Harness Album"
                host.format = "MP3"
                host.streamPhase = AudionFaceHostState.StreamPhase(rawValue: name) ?? .none
            default: return nil
            }
            return (name, host)
        }
    }

    /// `AUDION_RENDER_CLOCK`: 60 Hz ticks, comma-separated; one image per value.
    var frames: [Int] {
        let frames = (env["AUDION_RENDER_CLOCK"] ?? "").split(separator: ",").compactMap { Int($0) }.filter { $0 >= 0 }
        return frames.isEmpty ? [0] : frames
    }

    var scale: Int { Int(env["AUDION_RENDER_SCALE"] ?? "").map { min(max($0, 1), 4) } ?? 1 }
    var wantsProbe: Bool { env["AUDION_RENDER_PROBE"] != nil }

    /// `AUDION_RENDER_HOVER` / `AUDION_RENDER_CLICK`: `x,y` in face pixels, top-left origin.
    func point(_ flag: String) -> (x: Int, y: Int)? {
        let parts = (env[flag] ?? "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// `AUDION_FACE` is a face folder, a corpus root walked for every folder holding `index.json`,
    /// or a text file listing face folders one per line (how the scripts apply their exclusions).
    static func faces(at path: String) -> [URL] {
        let root = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            let list = (try? String(contentsOf: root, encoding: .utf8)) ?? ""
            return list.split(separator: "\n").map { URL(fileURLWithPath: String($0), isDirectory: true) }
        }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path) { return [root] }
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return (walker?.compactMap { $0 as? URL } ?? [])
            .filter { $0.lastPathComponent == "index.json" }
            .map { $0.deletingLastPathComponent() }
            .sorted { $0.path < $1.path }
    }
}

enum AudionFaceHarness {
    static func measure(folder: URL, dump: URL?, probe: AudionFaceProbe) async {
        let name = folder.lastPathComponent
        HarnessOutput.emit("FACE \(name)")
        let face: AudionFace
        do {
            face = try await AudionFaceLoader.load(folder: folder)
        } catch {
            HarnessOutput.emit("FACE \(name) FAILED \("\(error)".replacingOccurrences(of: "\n", with: " · "))")
            return
        }
        let size = { (image: CGImage?) in image.map { "\($0.width)x\($0.height)" } ?? "none" }
        HarnessOutput.emit("LOAD size=\(size(face.base)) mask=\(size(face.mask)) "
            + "inactiveMask=\(size(face.inactiveMask)) findings=\(face.findings.count)")
        for finding in face.findings { HarnessOutput.emit("FINDING \(finding)") }
        func names<Role>(_ roles: [Role], _ present: (Role) -> Bool) -> String {
            let found = roles.filter(present).map { "\($0)" }
            return found.isEmpty ? "-" : found.joined(separator: ",")
        }
        HarnessOutput.emit("ELEMENTS buttons=\(names(AudionFace.ButtonRole.allCases) { face.buttons[$0] != nil })"
            + " indicators=\(names(AudionFace.IndicatorRole.allCases) { face.indicators[$0] != nil })"
            + " digits=\(names(AudionFace.DigitRole.allCases) { face.digits[$0] != nil })"
            + " animations=\(names(AudionFace.AnimationRole.allCases) { face.animations[$0] != nil })"
            + " text=\(names(AudionFace.TextRole.allCases) { ($0 == .artist ? face.artist : face.album) != nil })")

        for (state, host) in probe.states {
            var interaction = AudionFaceInteractionState()
            var suffix = ""
            if let point = probe.point("AUDION_RENDER_HOVER") {
                interaction.hovered = AudionFaceScene.button(atX: point.x, y: point.y, face: face, host: host)
                suffix += "-hover"
            }
            if let point = probe.point("AUDION_RENDER_CLICK") {
                interaction.pressed = AudionFaceScene.button(atX: point.x, y: point.y, face: face, host: host)
                suffix += "-click"
            }
            for frame in probe.frames {
                let label = state + (probe.env["AUDION_RENDER_CLOCK"] == nil ? "" : "-f\(frame)") + suffix
                    + (probe.scale == 1 ? "" : "@\(probe.scale)x")
                let scene = AudionFaceScene(face: face, host: host, interaction: interaction, frame: frame,
                                            scale: probe.scale)
                let hit = [interaction.hovered.map { "hovered=\($0)" }, interaction.pressed.map { "pressed=\($0)" }]
                    .compactMap { $0 }.joined(separator: " ")
                HarnessOutput.emit("RENDER-DUMP \(label): \(scene.width * scene.scale)x\(scene.height * scene.scale) "
                    + "ops=\(scene.ops.count)" + (hit.isEmpty ? "" : " " + hit))
                if probe.wantsProbe {
                    for op in scene.ops {
                        let rect = op.rect
                        HarnessOutput.emit("PROBE \(label) \(op.element) \(rect.x),\(rect.y) \(rect.width)x\(rect.height)"
                            + (op.layer == .labels ? " offset=\(op.textOffset) text=\(op.image.width)x\(op.image.height)" : ""))
                    }
                }
                guard let dump else { continue }
                let file = dump.appendingPathComponent(name, isDirectory: true).appendingPathComponent("\(label).png")
                do {
                    guard let image = AudionFaceRenderer.render(scene),
                          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                    else { throw CocoaError(.fileWriteUnknown) }
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try data.write(to: file)
                    HarnessOutput.emit("PNG \(label): \(name)/\(file.lastPathComponent)")
                } catch {
                    HarnessOutput.emit("PNG \(label) FAILED \(error)")
                }
            }
        }
    }
}

final class AudionFaceRenderDumpTests: XCTestCase {
    // MARK: - The corpus sweep

    func testSweepsFaceOrCorpus() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["AUDION_FACE"], !path.isEmpty else {
            throw XCTSkip("Set AUDION_FACE to a face folder, a corpus root or a list file. "
                + "See skills/audion-face-guide/reference/harness.md.")
        }
        let faces = AudionFaceProbe.faces(at: path)
        guard !faces.isEmpty else { throw XCTSkip("No faces under \(path).") }
        let dump = env["AUDION_RENDER_DUMP"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let probe = AudionFaceProbe(env: env)
        HarnessOutput.emit("HARNESS \(faces.count) face(s) from \(path)")
        for folder in faces {
            await AudionFaceHarness.measure(folder: folder, dump: dump, probe: probe)
        }
    }

    // MARK: - Scene and renderer

    private let red: [UInt8] = [255, 0, 0, 255], green: [UInt8] = [0, 255, 0, 255]
    private let blue: [UInt8] = [0, 0, 255, 255], clear: [UInt8] = [0, 0, 0, 0]

    /// FaceKit's layers: digits and indicators sit above the buttons (zPosition 2 over 1), an
    /// animation clears the base under it, and the mask, anchored bottom-left, cuts everything.
    func testLayersCompositeInFaceKitsOrder() async throws {
        let fixture = try AudionFaceFixture(json: [
            "stopButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 2, right: 2),
            "timeDigit1Rect": AudionFaceFixture.rect(top: 1, left: 1, bottom: 2, right: 2),
            "timeDigit1FirstPICTID": 100,
            "connectingAnimRect": AudionFaceFixture.rect(top: 3, left: 3, bottom: 4, right: 4),
            "connectingFirstPICTID": 200, "connectingNumPICTs": 1, "connectingFrameDelay": 1,
        ])
        try fixture.png("base.png", width: 4, height: 4, fill: green)
        try fixture.png("stop.png", width: 2, height: 2, fill: red)
        for id in 100..<110 { try fixture.png("\(id).png", fill: blue) }
        try fixture.png("200.png", fill: clear)
        // A 4×3 mask: the base's top row is outside it and must come out transparent.
        try fixture.png("base-alpha.png", width: 4, height: 3, fill: [0, 0, 0, 255])
        let face = try await fixture.load()

        var host = AudionFaceHostState()
        host.streamPhase = .connecting
        let image = try XCTUnwrap(AudionFaceRenderer.render(AudionFaceScene(face: face, host: host)))
        XCTAssertEqual(Self.pixel(image, 0, 0), clear, "the mask's missing top row")
        XCTAssertEqual(Self.pixel(image, 0, 1), red, "the button over the base")
        XCTAssertEqual(Self.pixel(image, 1, 1), blue, "the digit over the button")
        XCTAssertEqual(Self.pixel(image, 2, 2), green, "the base")
        XCTAssertEqual(Self.pixel(image, 3, 3), clear, "the transparent animation frame cleared the base")
    }

    func testButtonStatesFollowFaceKitsPrecedence() async throws {
        let fixture = try AudionFaceFixture(json: [
            "playButtonRect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1),
            "stopButtonRect": AudionFaceFixture.rect(top: 0, left: 2, bottom: 1, right: 3),
        ])
        for name in ["play", "play-active", "play-hover", "pause", "stop", "stop-disabled"] { try fixture.png("\(name).png") }
        let face = try await fixture.load()
        func image(_ element: String, _ scene: AudionFaceScene) -> CGImage? {
            scene.ops.first { $0.element == element }?.image
        }

        var host = AudionFaceHostState()
        XCTAssertTrue(image("button:stop", AudionFaceScene(face: face, host: host)) === face.buttons[.stop]?.disabledImage,
                      "stop is disabled with no duration")
        var interaction = AudionFaceInteractionState(hovered: .play, pressed: .play)
        XCTAssertTrue(image("button:play", AudionFaceScene(face: face, host: host, interaction: interaction))
                      === face.buttons[.play]?.pressedImage, "pressed beats hover")
        interaction.pressed = nil
        XCTAssertTrue(image("button:play", AudionFaceScene(face: face, host: host, interaction: interaction))
                      === face.buttons[.play]?.hoverImage)
        XCTAssertEqual(AudionFaceScene.button(atX: 0, y: 0, face: face, host: host), .play)

        host.playState = .playing
        host.durationSeconds = 10
        let playing = AudionFaceScene(face: face, host: host)
        XCTAssertNil(image("button:play", playing), "play hides while playing")
        XCTAssertNotNil(image("button:pause", playing))
        XCTAssertTrue(image("button:stop", playing) === face.buttons[.stop]?.image)
        XCTAssertEqual(AudionFaceScene.button(atX: 0, y: 0, face: face, host: host), .pause)
    }

    func testIndicatorsAndDigitsFollowTheHostState() async throws {
        var json: [String: Any] = [
            "timeDigit4Rect": AudionFaceFixture.rect(top: 0, left: 0, bottom: 1, right: 1), "timeDigit4FirstPICTID": 100,
            "trackDigit2Rect": AudionFaceFixture.rect(top: 0, left: 1, bottom: 1, right: 2), "trackDigit2FirstPICTID": 200,
        ]
        for (index, key) in ["MP3IndicatorRect", "netIndicatorRect", "pauseIndicatorRect"].enumerated() {
            json[key] = AudionFaceFixture.rect(top: 1, left: index, bottom: 2, right: index + 1)
        }
        let fixture = try AudionFaceFixture(json: json)
        try fixture.picts(100, count: 10)
        try fixture.picts(200, count: 11)
        for name in ["mp3", "net", "pause-indicator"] {
            try fixture.png("\(name).png")
            try fixture.png("\(name)-on.png")
        }
        let face = try await fixture.load()
        func image(_ element: String, _ host: AudionFaceHostState) -> CGImage? {
            AudionFaceScene(face: face, host: host).ops.first { $0.element == element }?.image
        }

        var host = AudionFaceHostState()
        host.elapsedSeconds = 83
        XCTAssertTrue(image("digit:timeDigit4", host) === face.digits[.timeDigit4]?.images[3])
        XCTAssertTrue(image("digit:trackDigit2", host) === face.digits[.trackDigit2]?.images[10], "blank without a track")
        host.trackIndex = 7
        XCTAssertTrue(image("digit:trackDigit2", host) === face.digits[.trackDigit2]?.images[7])
        XCTAssertTrue(image("indicator:mp3", host) === face.indicators[.mp3]?.image, "off with no duration")

        host.durationSeconds = 100
        host.playState = .paused
        XCTAssertTrue(image("indicator:mp3", host) === face.indicators[.mp3]?.onImage)
        XCTAssertTrue(image("indicator:pause", host) === face.indicators[.pause]?.onImage)
        host.streamPhase = .streaming
        XCTAssertTrue(image("indicator:net", host) === face.indicators[.net]?.onImage)
        XCTAssertTrue(image("indicator:mp3", host) === face.indicators[.mp3]?.image)
    }

    /// FaceKit `LabelView.frameNum`, worked by hand for a 40 px string in a 100 px box.
    func testMarqueeHoldsThenScrollsAndReentersFromTheRight() {
        let offset = { AudionFaceScene.marqueeOffset(frame: $0, textWidth: 40, boxWidth: 100) }
        XCTAssertEqual(offset(79), 0)
        XCTAssertEqual(offset(84), -2)
        XCTAssertEqual(offset(80 + 2 * 100), -100, "the last step before the gap is spent")
        XCTAssertEqual(offset(80 + 2 * 101), 99, "re-entering at the box's right edge")
        XCTAssertEqual(offset(80 + 2 * 200), 0, "one full cycle of 200 steps")
    }

    /// The pixel at `x`, `y`, top-left origin, as RGBA.
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return bytes
    }
}
