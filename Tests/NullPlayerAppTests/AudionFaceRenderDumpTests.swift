import AppKit
import CryptoKit
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
            host.reduceMotion = !clocked
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

    /// `AUDION_RENDER_CLOCK` is set: the run asks for motion, and labels carry the tick.
    var clocked: Bool { env["AUDION_RENDER_CLOCK"] != nil }

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
        do {
            HarnessOutput.emit("DIGEST \(try digest(of: folder))")
        } catch {
            HarnessOutput.emit("DIGEST FAILED \(error)")
        }
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
        HarnessOutput.emit("PALETTE \(paletteLine(face))")

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
                let label = state + (probe.clocked ? "-f\(frame)" : "") + suffix
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
                        var line = "PROBE \(label) \(op.element) \(rect.x),\(rect.y) \(rect.width)x\(rect.height)"
                        if case .label(_, let offset) = op.element {
                            line += " offset=\(offset) text=\(op.image.width)x\(op.image.height)"
                        }
                        HarnessOutput.emit(line)
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

    /// `AudionFacePalette.surfaceStyle(for:)` as hex roles, the contrasts the windows depend on, and
    /// which of the face's own text colours (`roles(for:)`) the style's `legible` guard overruled.
    static func paletteLine(_ face: AudionFace) -> String {
        let roles = AudionFacePalette.roles(for: face)
        let style = SkinnedSurfaceStyle(roles: roles)
        func hex(_ color: NSColor) -> String {
            let c = color.usingColorSpace(.deviceRGB) ?? .black
            return String(format: "%02x%02x%02x", Int((c.redComponent * 255).rounded()),
                          Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
        }
        func ratio(_ a: NSColor, _ b: NSColor) -> String {
            String(format: "%.2f", SkinnedSurfaceStyle.contrastRatio(a, b))
        }
        let overruled = [("text", roles.text != style.text), ("current", roles.currentText != style.currentText)]
            .filter(\.1).map(\.0)
        return "authored=\(hex(roles.text))/\(hex(roles.currentText)) "
            + "ground=\(hex(style.background)) text=\(hex(style.text)) current=\(hex(style.currentText)) "
            + "selection=\(hex(style.selectionBackground)) selected=\(hex(style.selectedText)) "
            + "text/ground=\(ratio(style.text, style.background)) current/ground=\(ratio(style.currentText, style.background)) "
            + "selected/selection=\(ratio(style.selectedText, style.selectionBackground)) "
            + "selection/ground=\(ratio(style.selectionBackground, style.background)) "
            + "overruled=\(overruled.isEmpty ? "-" : overruled.joined(separator: ","))"
    }

    /// The census digest, the key of `Fixtures/AudionFace/corpus-baseline.tsv`: every regular file
    /// in the face, in UTF-8 byte order of its relative path, as the path, a NUL, then its contents.
    /// The harness prints it and `AudionFaceCorpusLoadTests` computes it, so there is one definition.
    static func digest(of folder: URL) throws -> String {
        let root = folder.standardizedFileURL.path + "/"
        let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .map { String($0.standardizedFileURL.path.dropFirst(root.count)) }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        var hash = SHA256()
        for path in files {
            hash.update(data: Data(path.utf8) + [0])
            hash.update(data: try Data(contentsOf: folder.appendingPathComponent(path), options: .mappedIfSafe))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
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
}
