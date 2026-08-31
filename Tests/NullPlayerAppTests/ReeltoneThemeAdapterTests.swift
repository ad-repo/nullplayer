import AppKit
import Foundation
import XCTest
@testable import NullPlayer

final class ReeltoneThemeAdapterTests: XCTestCase {
    func testMapsVersionOneColorsIntoOriginalPresentationPalette() throws {
        let manifest = try ReeltoneManifestDecoder.decode(Data(#"""
        {
            "formatVersion": 1,
            "id": "com.example.theme",
            "name": "Theme Fixture",
            "colors": {
                "screen": "#102030",
                "ink": "#AABBCCDD",
                "inkDim": "#405060",
                "panel": "#203040",
                "panelText": "#F0E0D0"
            }
        }
        """#.utf8))

        let adapter = ReeltoneThemeAdapter(manifest: manifest)

        XCTAssertEqual(adapter.palette.screen, "#102030")
        XCTAssertEqual(adapter.palette.ink, "#AABBCC")
        XCTAssertEqual(adapter.palette.inkDim, "#405060")
        XCTAssertEqual(adapter.palette.panel, "#203040")
        XCTAssertEqual(adapter.palette.panelText, "#F0E0D0")
        XCTAssertEqual(adapter.presentationSkin.backgroundColor, NSColor.from(hex: "#102030"))
        XCTAssertEqual(adapter.presentationSkin.surfaceColor, NSColor.from(hex: "#203040"))
        XCTAssertEqual(adapter.presentationSkin.textColor, NSColor.from(hex: "#F0E0D0"))
        XCTAssertEqual(adapter.presentationSkin.timeColor, NSColor.from(hex: "#AABBCC"))
    }

    func testMissingColorsUseReadableDefaultPalette() throws {
        let manifest = try ReeltoneManifestDecoder.decode(Data(#"""
        {
            "formatVersion": 1,
            "id": "com.example.partial",
            "name": "Partial",
            "colors": { "ink": "#123456" }
        }
        """#.utf8))

        let adapter = ReeltoneThemeAdapter(manifest: manifest)

        XCTAssertEqual(adapter.palette.screen, ReeltoneThemeAdapter.defaultPalette.screen)
        XCTAssertEqual(adapter.palette.ink, "#123456")
        XCTAssertEqual(adapter.palette.panel, ReeltoneThemeAdapter.defaultPalette.panel)
        XCTAssertEqual(adapter.palette.panelText, ReeltoneThemeAdapter.defaultPalette.panelText)
    }

    func testMapsVersionOneBuiltinFontsIntoTransientPresentation() throws {
        let manifest = try ReeltoneManifestDecoder.decode(Data(#"""
        {"formatVersion":1,"id":"fonts","name":"Fonts","fonts":{
          "body":{"builtin":"Silkscreen-Regular"},
          "digits":{"builtin":"DSEG7Classic-Regular"}
        }}
        """#.utf8))
        let adapter = ReeltoneThemeAdapter(manifest: manifest)
        XCTAssertNotNil(adapter.presentationSkin.primaryFont)
        XCTAssertNotNil(adapter.presentationSkin.timeFont)
        XCTAssertNotNil(adapter.presentationSkin.smallFont)
    }
}
