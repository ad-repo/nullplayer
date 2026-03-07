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

    func testAreaOpacityFallbackUsesWindowOpacity() throws {
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
        XCTAssertEqual(timeStyle.background, 0.2, accuracy: 0.0001)
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

    private func decodeConfig(from json: String) throws -> ModernSkinConfig {
        try JSONDecoder().decode(ModernSkinConfig.self, from: Data(json.utf8))
    }
}
