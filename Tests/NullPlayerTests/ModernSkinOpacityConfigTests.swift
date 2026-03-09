import XCTest
@testable import NullPlayer

final class ModernSkinOpacityConfigTests: XCTestCase {

    func testDecodeFailsWhenWindowOpacityMissing() {
        let json = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6 }
        }
        """

        XCTAssertThrowsError(try decodeConfig(from: json))
    }

    func testDecodeSucceedsWhenTextOpacityOmittedAndDefaultsToIdentity() throws {
        let omittedJSON = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62 }
        }
        """
        let explicitOneJSON = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62, "textOpacity": 1.0 }
        }
        """

        let omittedConfig = try decodeConfig(from: omittedJSON)
        XCTAssertNil(omittedConfig.window.textOpacity)
        let omittedSkin = ModernSkin(config: omittedConfig, bundlePath: nil)
        XCTAssertEqual(omittedSkin.textOpacityMultiplier, 1.0, accuracy: 0.0001)

        let explicitConfig = try decodeConfig(from: explicitOneJSON)
        let explicitSkin = ModernSkin(config: explicitConfig, bundlePath: nil)
        XCTAssertEqual(explicitSkin.textOpacityMultiplier, 1.0, accuracy: 0.0001)

        let baseColor = omittedSkin.textColor.withAlphaComponent(0.42)
        XCTAssertEqual(
            omittedSkin.applyTextOpacity(to: baseColor).alphaComponent,
            explicitSkin.applyTextOpacity(to: baseColor).alphaComponent,
            accuracy: 0.0001
        )
    }

    func testTextOpacityMultiplierClampsAtBounds() throws {
        let lowJSON = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62, "textOpacity": -0.3 }
        }
        """
        let highJSON = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62, "textOpacity": 1.7 }
        }
        """

        let lowSkin = ModernSkin(config: try decodeConfig(from: lowJSON), bundlePath: nil)
        let highSkin = ModernSkin(config: try decodeConfig(from: highJSON), bundlePath: nil)

        XCTAssertEqual(lowSkin.textOpacityMultiplier, 0.0, accuracy: 0.0001)
        XCTAssertEqual(highSkin.textOpacityMultiplier, 1.0, accuracy: 0.0001)
    }

    func testApplyTextOpacityMultipliesAlpha() throws {
        let json = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62, "textOpacity": 0.5 }
        }
        """

        let skin = ModernSkin(config: try decodeConfig(from: json), bundlePath: nil)
        let input = skin.textColor.withAlphaComponent(0.8)
        let output = skin.applyTextOpacity(to: input)

        XCTAssertEqual(output.alphaComponent, 0.4, accuracy: 0.0001)
    }

    func testDecodeSucceedsWhenMainSpectrumOpacityOmittedAndKeepsResolvedOpacity() throws {
        let omittedJSON = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62 }
        }
        """
        let omittedConfig = try decodeConfig(from: omittedJSON)
        XCTAssertNil(omittedConfig.window.mainSpectrumOpacity)
        let omittedSkin = ModernSkin(config: omittedConfig, bundlePath: nil)
        XCTAssertNil(omittedSkin.mainSpectrumOpacityOverride)

        let baseAlpha = omittedSkin.resolvedOpacity(for: .spectrumArea).content
        XCTAssertEqual(omittedSkin.applyMainSpectrumOpacity(to: baseAlpha), baseAlpha, accuracy: 0.0001)
    }

    func testMainSpectrumOpacityOverrideClampsAtBounds() throws {
        let lowJSON = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62, "mainSpectrumOpacity": -0.25 }
        }
        """
        let highJSON = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62, "mainSpectrumOpacity": 1.6 }
        }
        """

        let lowSkin = ModernSkin(config: try decodeConfig(from: lowJSON), bundlePath: nil)
        let highSkin = ModernSkin(config: try decodeConfig(from: highJSON), bundlePath: nil)

        XCTAssertNotNil(lowSkin.mainSpectrumOpacityOverride)
        XCTAssertNotNil(highSkin.mainSpectrumOpacityOverride)
        XCTAssertEqual(lowSkin.mainSpectrumOpacityOverride ?? -1, 0.0, accuracy: 0.0001)
        XCTAssertEqual(highSkin.mainSpectrumOpacityOverride ?? -1, 1.0, accuracy: 0.0001)
    }

    func testApplyMainSpectrumOpacityUsesOverrideAsAbsoluteAlpha() throws {
        let json = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": { "borderWidth": 1, "cornerRadius": 6, "opacity": 0.62, "mainSpectrumOpacity": 0.5 }
        }
        """

        let skin = ModernSkin(config: try decodeConfig(from: json), bundlePath: nil)
        XCTAssertEqual(skin.applyMainSpectrumOpacity(to: 0.8), 0.5, accuracy: 0.0001)
        XCTAssertEqual(skin.applyMainSpectrumOpacity(to: 0.2), 0.5, accuracy: 0.0001)
    }

    func testAreaOpacityFallbackUsesWindowOpacityAndMultiplierSemantics() throws {
        let json = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": {
                "borderWidth": 1,
                "cornerRadius": 6,
                "opacity": 0.62,
                "areaOpacity": {
                    "timeDisplay": { "background": 0.2 }
                }
            }
        }
        """

        let config = try decodeConfig(from: json)
        let skin = ModernSkin(config: config, bundlePath: nil)

        let timeStyle = skin.resolvedOpacity(for: .timeDisplay)
        XCTAssertEqual(timeStyle.background, 0.124, accuracy: 0.0001) // 0.62 * 0.2
        XCTAssertEqual(timeStyle.border, 0.62, accuracy: 0.0001)
        XCTAssertEqual(timeStyle.content, 0.62, accuracy: 0.0001)

        let volumeStyle = skin.resolvedOpacity(for: .volumeArea)
        XCTAssertEqual(volumeStyle.background, 0.62, accuracy: 0.0001)
        XCTAssertEqual(volumeStyle.border, 0.62, accuracy: 0.0001)
        XCTAssertEqual(volumeStyle.content, 0.62, accuracy: 0.0001)
    }

    func testAreaOpacityValuesAreClamped() throws {
        let json = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#080810", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": true },
            "window": {
                "borderWidth": 1,
                "cornerRadius": 6,
                "opacity": 1.3,
                "areaOpacity": {
                    "curveBackground": {
                        "background": -0.4,
                        "border": 1.7,
                        "content": 0.45
                    }
                }
            }
        }
        """

        let config = try decodeConfig(from: json)
        let skin = ModernSkin(config: config, bundlePath: nil)

        let curve = skin.resolvedOpacity(for: .curveBackground)
        XCTAssertEqual(curve.background, 0.0, accuracy: 0.0001)
        XCTAssertEqual(curve.border, 1.0, accuracy: 0.0001)
        XCTAssertEqual(curve.content, 0.45, accuracy: 0.0001)

        // Missing area falls back to clamped window.opacity.
        let main = skin.resolvedOpacity(for: .mainWindow)
        XCTAssertEqual(main.background, 1.0, accuracy: 0.0001)
        XCTAssertEqual(main.border, 1.0, accuracy: 0.0001)
        XCTAssertEqual(main.content, 1.0, accuracy: 0.0001)
    }

    func testBundledModernSkinJSONFilesDecodeWithAreaOpacity() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent() // NullPlayerTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let skinsDir = repoRoot.appendingPathComponent("Sources/NullPlayer/Resources/Skins")

        let fm = FileManager.default
        let dirs = try fm.contentsOfDirectory(at: skinsDir, includingPropertiesForKeys: [.isDirectoryKey])

        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let jsonURL = dir.appendingPathComponent("skin.json")
            let data = try Data(contentsOf: jsonURL)
            let config = try JSONDecoder().decode(ModernSkinConfig.self, from: data)

            XCTAssertNotNil(config.window.areaOpacity, "Expected areaOpacity in \(dir.lastPathComponent)")
        }
    }

    func testWindowBackgroundDrawIsStableAcrossRepeatedRedraws() throws {
        let json = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#123456", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": false },
            "window": { "borderWidth": 1, "cornerRadius": 0, "opacity": 0.52 }
        }
        """

        let config = try decodeConfig(from: json)
        let skin = ModernSkin(config: config, bundlePath: nil)
        let renderer = ModernSkinRenderer(skin: skin, scaleFactor: 1.0)

        let width = 32
        let height = 20
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)
        data.initialize(repeating: 0, count: totalBytes)
        defer { data.deallocate() }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            XCTFail("Failed to create bitmap context")
            return
        }

        let bounds = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        renderer.drawWindowBackground(in: bounds, context: context)
        let first = rgbaPixel(x: width / 2, y: height / 2, data: data, bytesPerRow: bytesPerRow)

        // Simulate timer-driven partial redraw of the same region.
        context.saveGState()
        context.clip(to: NSRect(x: 0, y: 0, width: 16, height: 20))
        renderer.drawWindowBackground(in: bounds, context: context)
        context.restoreGState()
        let second = rgbaPixel(x: width / 4, y: height / 2, data: data, bytesPerRow: bytesPerRow)

        assertChannelClose(first.r, second.r, tolerance: 1)
        assertChannelClose(first.g, second.g, tolerance: 1)
        assertChannelClose(first.b, second.b, tolerance: 1)
        assertChannelClose(first.a, second.a, tolerance: 1)

        // Guard against regressions where alpha keeps increasing after each redraw.
        XCTAssertEqual(Int(first.a), Int(round(0.52 * 255.0)), accuracy: 1)
    }

    func testSeamSuppressedBorderIsStableAcrossRepeatedRedraws() throws {
        let json = """
        {
            "meta": { "name": "Test", "author": "Tester", "version": "1.0", "description": "d" },
            "palette": {
                "primary": "#00ffcc", "secondary": "#00ccff", "accent": "#ff00aa",
                "background": "#1a2a3a", "surface": "#0c1018", "text": "#00ffcc", "textDim": "#009977"
            },
            "fonts": { "primaryName": "Menlo" },
            "background": { "grid": { "color": "#00ffcc", "spacing": 18, "angle": 75, "opacity": 0.06 } },
            "glow": { "enabled": false },
            "window": {
                "borderWidth": 1,
                "cornerRadius": 6,
                "opacity": 0.54,
                "seamlessDocking": 1.0
            }
        }
        """

        let config = try decodeConfig(from: json)
        let skin = ModernSkin(config: config, bundlePath: nil)
        let renderer = ModernSkinRenderer(skin: skin, scaleFactor: 1.0)

        let width = 96
        let height = 56
        let bytesPerRow = width * 4
        let totalBytes = bytesPerRow * height
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)
        data.initialize(repeating: 0, count: totalBytes)
        defer { data.deallocate() }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            XCTFail("Failed to create bitmap context")
            return
        }

        let bounds = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let nearFullRightJoin = EdgeOcclusionSegments(
            top: [],
            bottom: [],
            left: [],
            right: [0...(CGFloat(height) - 1.2)]
        )

        renderer.drawWindowBackground(in: bounds, context: context)
        renderer.drawWindowBorder(in: bounds, context: context, occlusionSegments: nearFullRightJoin)
        let first = rgbaPixel(x: width - 1, y: height / 2, data: data, bytesPerRow: bytesPerRow)

        context.saveGState()
        context.clip(to: NSRect(x: CGFloat(width - 4), y: 0, width: 4, height: CGFloat(height)))
        renderer.drawWindowBackground(in: bounds, context: context)
        renderer.drawWindowBorder(in: bounds, context: context, occlusionSegments: nearFullRightJoin)
        context.restoreGState()
        let second = rgbaPixel(x: width - 1, y: height / 2, data: data, bytesPerRow: bytesPerRow)

        assertChannelClose(first.r, second.r, tolerance: 1)
        assertChannelClose(first.g, second.g, tolerance: 1)
        assertChannelClose(first.b, second.b, tolerance: 1)
        assertChannelClose(first.a, second.a, tolerance: 1)
    }

    private func decodeConfig(from json: String) throws -> ModernSkinConfig {
        try JSONDecoder().decode(ModernSkinConfig.self, from: Data(json.utf8))
    }

    private func rgbaPixel(
        x: Int,
        y: Int,
        data: UnsafeMutablePointer<UInt8>,
        bytesPerRow: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let offset = y * bytesPerRow + x * 4
        return (
            r: data[offset],
            g: data[offset + 1],
            b: data[offset + 2],
            a: data[offset + 3]
        )
    }

    private func assertChannelClose(
        _ lhs: UInt8,
        _ rhs: UInt8,
        tolerance: UInt8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let delta = abs(Int(lhs) - Int(rhs))
        XCTAssertLessThanOrEqual(delta, Int(tolerance), file: file, line: line)
    }
}
