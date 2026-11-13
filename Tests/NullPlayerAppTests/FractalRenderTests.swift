import XCTest
import OpenGL.GL3
@testable import NullPlayer

/// NullPlayer-Fractal in an offscreen GL 3.2 core context, the host's profile: every scene's
/// shader compiles and draws something. With `FRACTAL_RENDER_DIR` set, each scene also runs for
/// a few seconds of simulated 120 BPM music and writes PNG frames there; `FRACTAL_SCENES`, a
/// comma-separated list of scene names, limits the run to those, and `FRACTAL_SECONDS` sets each
/// scene's run (a camera shot is 64 beats, 32 s at 120 BPM) (the `fractal-vis` skill).
final class FractalRenderTests: XCTestCase {
    private let size = (width: 640, height: 360)

    func testEveryScenePresentsAPicture() throws {
        let context = try Self.makeContext()
        defer { CGLSetCurrentContext(nil); CGLDestroyContext(context) }

        var fbo: GLuint = 0, colour: GLuint = 0
        glGenFramebuffers(1, &fbo)
        glGenRenderbuffers(1, &colour)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colour)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_RGBA8), GLsizei(size.width), GLsizei(size.height))
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), colour)
        defer { glDeleteFramebuffers(1, &fbo); glDeleteRenderbuffers(1, &colour) }

        let outDir = ProcessInfo.processInfo.environment["FRACTAL_RENDER_DIR"].map(URL.init(fileURLWithPath:))
        let seconds = outDir == nil ? 0.3 : ProcessInfo.processInfo.environment["FRACTAL_SECONDS"].flatMap(Double.init) ?? 4

        let only = ProcessInfo.processInfo.environment["FRACTAL_SCENES"]?.split(separator: ",").map(String.init)
        for (index, scene) in FractalScenes.all.enumerated() where only?.contains(scene.name) ?? true {
            // A fresh engine per scene, so no earlier scene's trails count as this one's picture.
            let engine = FractalEngine(width: size.width, height: size.height)
            XCTAssertTrue(engine.isAvailable)
            defer { engine.cleanup() }
            engine.selectPreset(at: index, hardCut: true)
            let name = scene.name
            let start = CACurrentMediaTime()
            var lastPost = start, frame = 0, nextBeat = start
            while CACurrentMediaTime() - start < seconds {
                let now = CACurrentMediaTime()
                let isBeat = now >= nextBeat
                if isBeat { nextBeat += 0.5 }
                NotificationCenter.default.post(name: .audioBeatsUpdated, object: nil,
                                                userInfo: ["beats": [isBeat], "hopMs": (now - lastPost) * 1000])
                lastPost = now
                let kick = Float(max(0, 1 - (now - (nextBeat - 0.5)) * 4))
                engine.setSpectrum((0..<256).map { $0 < 4 ? 0.2 + 0.8 * kick : $0 < 24 ? 0.4 : 0.15 })
                glBindFramebuffer(GLenum(GL_FRAMEBUFFER), fbo)
                engine.renderFrame()
                glFinish()
                frame += 1
                if let outDir, frame % 20 == 0 {
                    try write(to: outDir.appendingPathComponent("\(name.replacingOccurrences(of: " ", with: "_"))-\(frame).png"))
                }
            }
            XCTAssertEqual(glGetError(), GLenum(GL_NO_ERROR), name)
            XCTAssertGreaterThan(brightPixels(), size.width * size.height / 50, "\(name) drew nothing")
        }
    }

    private func pixels() -> [UInt8] {
        var data = [UInt8](repeating: 0, count: size.width * size.height * 4)
        glReadPixels(0, 0, GLsizei(size.width), GLsizei(size.height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &data)
        return data
    }

    private func brightPixels() -> Int {
        let data = pixels()
        return stride(from: 0, to: data.count, by: 4).filter { Int(data[$0]) + Int(data[$0 + 1]) + Int(data[$0 + 2]) > 60 }.count
    }

    private func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = pixels()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size.width, pixelsHigh: size.height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: size.width * 4, bitsPerPixel: 32)!
        // GL rows run bottom-up.
        for y in 0..<size.height {
            let src = (size.height - 1 - y) * size.width * 4
            for i in 0..<size.width * 4 { rep.bitmapData![y * size.width * 4 + i] = i % 4 == 3 ? 255 : data[src + i] }
        }
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    private static func makeContext() throws -> CGLContextObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAllowOfflineRenderers, CGLPixelFormatAttribute(0),
        ]
        var format: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attributes, &format, &count)
        guard let format else { throw XCTSkip("no GL 3.2 core pixel format") }
        defer { CGLDestroyPixelFormat(format) }
        var context: CGLContextObj?
        CGLCreateContext(format, nil, &context)
        guard let context else { throw XCTSkip("no GL context") }
        CGLSetCurrentContext(context)
        return context
    }
}
