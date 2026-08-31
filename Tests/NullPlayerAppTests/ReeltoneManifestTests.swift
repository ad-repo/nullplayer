import XCTest
@testable import NullPlayer

final class ReeltoneManifestTests: XCTestCase {
    func testDecodesVersionOneTheme() throws {
        let manifest = try ReeltoneManifestDecoder.decode(Data(#"""
        {
            "formatVersion": 1,
            "id": "com.example.deck",
            "name": "Deck",
            "colors": { "screen": "#001122", "ink": "#AABBCCDD" },
            "fonts": { "display": { "builtin": "DSEG14Classic-Regular" } },
            "sprites": { "background": { "file": "art/background.png", "mode": "fill" } }
        }
        """#.utf8))

        XCTAssertEqual(manifest.formatVersion, 1)
        XCTAssertEqual(manifest.id, "com.example.deck")
        XCTAssertNil(manifest.window)
        XCTAssertEqual(manifest.sprites?.background?.mode, .fill)
        XCTAssertEqual(manifest.referencedImages, ["art/background.png"])
    }

    func testDecodesVersionTwoSurfaceAndPanel() throws {
        let manifest = try ReeltoneManifestDecoder.decode(Data(#"""
        {
            "formatVersion": 2,
            "id": "com.example.shaped",
            "name": "Shaped",
            "window": {
                "size": [640, 240],
                "art": { "normal": "chassis.png" },
                "panels": {
                    "playlist": {
                        "size": [320, 240], "attach": "right",
                        "art": { "normal": "panel.png" },
                        "regions": [{ "component": "trackList", "rect": [10, 10, 300, 220] }]
                    }
                }
            },
            "regions": [
                { "component": "playPause", "rect": [10, 20, 30, 40], "art": { "normal": "play.png" } },
                { "component": "togglePanel", "rect": [50, 20, 30, 40], "panel": "playlist" }
            ],
            "futureField": true
        }
        """#.utf8))

        XCTAssertEqual(manifest.window?.size, [640, 240])
        XCTAssertEqual(manifest.window?.panels["playlist"]?.attach, .right)
        XCTAssertEqual(manifest.regions.map(\.component), [.playPause, .togglePanel])
        XCTAssertEqual(manifest.referencedImages, ["chassis.png", "panel.png", "play.png"])
    }

    func testDecodesPublishedVersionTwoVocabularyFixture() throws {
        let components = [
            "play", "pause", "playPause", "stop", "prev", "next", "seek", "volume",
            "shuffle", "repeatMode", "title", "elapsed", "duration", "artwork", "trackList",
            "visualiser", "equaliser", "close", "minimise", "togglePanel", "decoration",
            "library", "libraryBack"
        ]
        let regions = components.enumerated().map { index, component -> String in
            if component == "togglePanel" {
                return #"{"component":"togglePanel","rect":[\#(index),0,1,1],"panel":"right"}"#
            }
            if component == "seek" {
                return ##"{"component":"seek","rect":[\##(index),0,1,1],"controlStyle":"slider","color":"#11223344","highlightColor":"#AABBCC","art":{"normal":"n.png","hover":"h.png","pressed":"p.png","playing":"on.png","playingHover":"oh.png","playingPressed":"op.png"}}"##
            }
            if component == "volume" {
                return #"{"component":"volume","rect":[\#(index),0,1,1],"controlStyle":"knob","clipShape":"ellipse"}"#
            }
            if component == "title" {
                return #"{"component":"title","rect":[\#(index),0,1,1],"size":10,"align":"center","marquee":true}"#
            }
            if component == "trackList" || component == "library" {
                return #"{"component":"\#(component)","rect":[\#(index),0,1,1],"rowHeight":14}"#
            }
            if component == "decoration" {
                return #"{"component":"decoration","rect":[\#(index),0,1,1],"frames":["a.png","b.png"],"fps":24,"drivenBy":"playback"}"#
            }
            return #"{"component":"\#(component)","rect":[\#(index),0,1,1]}"#
        }.joined(separator: ",")
        let json = """
        {"formatVersion":2,"id":"vocabulary","name":"Vocabulary","window":{"size":[64,32],"art":{"normal":"main.png"},"panels":{
          "left":{"size":[1,1],"attach":"left","art":{"normal":"l.png"}},
          "right":{"size":[1,1],"attach":"right","art":{"normal":"r.png"}},
          "top":{"size":[1,1],"attach":"top","art":{"normal":"t.png"}},
          "bottom":{"size":[1,1],"attach":"bottom","art":{"normal":"b.png"}}
        }},"regions":[\(regions)]}
        """
        let manifest = try ReeltoneManifestDecoder.decode(Data(json.utf8))
        XCTAssertEqual(Set(manifest.regions.map { $0.component.rawValue }), Set(components))
        XCTAssertEqual(Set(manifest.window?.panels.values.map { $0.attach } ?? []), Set(ReeltonePanel.Attachment.allCases))
        let seek = try XCTUnwrap(manifest.regions.first { $0.component == ReeltoneComponent.seek })
        XCTAssertEqual(seek.art.map { Array($0.values).count }, 6)
        XCTAssertEqual(manifest.regions.first { $0.component == ReeltoneComponent.decoration }?.drivenBy, .playback)
    }

    func testReportsUsefulCodingPathForMalformedManifest() {
        assertDiagnostic(#"{"formatVersion":1,"id":"x""#, code: .malformedManifest)
        assertDiagnostic(#"{"formatVersion":2,"id":"x","name":"X","window":{"size":"large","art":{"normal":"a.png"}},"regions":[]}"#, code: .malformedManifest) {
            XCTAssertEqual($0.codingPath, ["window", "size"])
        }
    }

    func testRejectsUnsupportedVersionAndInvalidReferences() {
        assertDiagnostic(#"{"formatVersion":3,"id":"x","name":"X"}"#, code: .unsupportedFormatVersion)
        assertDiagnostic(#"{"formatVersion":1,"id":"../x","name":"X"}"#, code: .invalidManifest)
        assertDiagnostic(#"{"formatVersion":1,"id":"x","name":"X","sprites":{"background":{"file":"../outside.png"}}}"#, code: .invalidResourcePath)
        assertDiagnostic(#"{"formatVersion":1,"id":"x","name":"X","fonts":{"display":{"builtin":"Unknown"}}}"#, code: .invalidManifest)
        assertDiagnostic(#"{"formatVersion":2,"id":"x","name":"X","window":{"size":[10,10],"art":{"normal":"a.png"}}}"#, code: .invalidManifest)
        assertDiagnostic(#"{"formatVersion":2,"id":"x","name":"X","sprites":{"background":{"file":"a.png","mode":"fill"}}}"#, code: .invalidManifest)
        assertDiagnostic(#"{"formatVersion":2,"id":"x","name":"X","window":{"size":[10,10],"art":{"normal":"a.png"},"panels":{}},"regions":[{"component":"togglePanel","rect":[0,0,1,1],"panel":"missing"}]}"#, code: .invalidManifest)
    }

    func testIgnoresSafeAdditiveFontFields() throws {
        let manifest = try ReeltoneManifestDecoder.decode(Data(
            #"{"formatVersion":1,"id":"x","name":"X","fonts":{"display":{"builtin":"DSEG14Classic-Regular","futureHint":true}}}"#.utf8
        ))
        XCTAssertEqual(manifest.fonts?.display?.builtin, "DSEG14Classic-Regular")
    }

    private func assertDiagnostic(
        _ json: String,
        code: ReeltoneDiagnosticCode,
        verify: (ReeltoneDiagnostic) -> Void = { _ in }
    ) {
        XCTAssertThrowsError(try ReeltoneManifestDecoder.decode(Data(json.utf8))) { error in
            guard let diagnostic = error as? ReeltoneDiagnostic else {
                return XCTFail("Expected ReeltoneDiagnostic, got \(error)")
            }
            XCTAssertEqual(diagnostic.code, code)
            verify(diagnostic)
        }
    }
}
