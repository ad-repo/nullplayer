import AppKit
import XCTest
@testable import NullPlayer

final class CavaSettingsTests: XCTestCase {
    private var originalValues: [String: Any] = [:]

    private var protectedPreferenceKeys: [String] {
        CavaSettings.Scope.allCases.flatMap { CavaSettings.preferenceKeys(for: $0) } + [
            "mainWindowVisMode",
            "modernMainWindowVisMode",
            "spectrumQualityMode",
            "visClassicLastProfileName.mainWindow",
            "visClassicLastProfileName.spectrumWindow",
            "visClassicFitToWidth.mainWindow",
            "visClassicFitToWidth.spectrumWindow",
            "visClassicLastProfileName",
            "visClassicFitToWidth",
        ]
    }

    override func setUp() {
        super.setUp()
        originalValues = [:]
        for key in protectedPreferenceKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                originalValues[key] = value
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in protectedPreferenceKeys {
            if let value = originalValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testModeDefaultsToStereoWhenPreferenceIsAbsent() {
        XCTAssertEqual(CavaSettings.mode, .stereo)
    }

    func testExplicitMonoPreferenceIsPreserved() {
        CavaSettings.mode = .mono
        XCTAssertEqual(CavaSettings.mode, .mono)
    }

    func testMainWindowModeIsForcedMonoWithoutChangingWindowMode() {
        CavaSettings.mode = .stereo
        CavaSettings.setMode(.stereo, for: .mainWindow)

        XCTAssertEqual(CavaSettings.mode(for: .mainWindow), .mono)
        XCTAssertEqual(CavaSettings.mode, .stereo)
    }

    func testMainWindowTuningIsIndependentFromStandaloneWindow() {
        CavaSettings.barCount = 64
        CavaSettings.noiseReduction = 0.9
        CavaSettings.bassTilt = 0.7

        CavaSettings.setBarCount(19, for: .mainWindow)
        CavaSettings.setNoiseReduction(0.5, for: .mainWindow)
        CavaSettings.setBassTilt(0.15, for: .mainWindow)

        XCTAssertEqual(CavaSettings.barCount(for: .mainWindow), 19)
        XCTAssertEqual(CavaSettings.noiseReduction(for: .mainWindow), 0.5, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.bassTilt(for: .mainWindow), 0.15, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.barCount, 64)
        XCTAssertEqual(CavaSettings.noiseReduction, 0.9, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.bassTilt, 0.7, accuracy: 0.001)
    }

    func testMainWindowResetTuningLeavesStandaloneWindowUntouched() {
        CavaSettings.barCount = 48
        CavaSettings.setBarCount(12, for: .mainWindow)

        CavaSettings.resetTuning(scope: .mainWindow)

        XCTAssertEqual(CavaSettings.barCount(for: .mainWindow), CavaSettings.defaultBarCount)
        XCTAssertEqual(CavaSettings.barCount, 48)
    }

    func testSkinChangeResetsSkinOwnedAppearanceWithoutDeletingColors() throws {
        let fireIndex = try XCTUnwrap(CavaSettings.colorSchemes.firstIndex { $0.name == "Fire" })
        let iceIndex = try XCTUnwrap(CavaSettings.colorSchemes.firstIndex { $0.name == "Ice" })
        let fire = CavaSettings.colorSchemes[fireIndex]
        let ice = CavaSettings.colorSchemes[iceIndex]

        CavaSettings.setLowGradientColor(fire.low, for: .cavaWindow)
        CavaSettings.setHighGradientColor(fire.high, for: .cavaWindow)
        CavaSettings.setHasCustomColors(true, for: .cavaWindow)
        CavaSettings.setLowGradientColor(ice.low, for: .mainWindow)
        CavaSettings.setHighGradientColor(ice.high, for: .mainWindow)
        CavaSettings.setHasCustomColors(true, for: .mainWindow)
        CavaSettings.transparentBackground = true

        CavaSettings.resetAppearanceForSkinChange()

        XCTAssertFalse(CavaSettings.hasCustomColors(for: .cavaWindow))
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .mainWindow))
        XCTAssertFalse(CavaSettings.transparentBackground)
        XCTAssertEqual(CavaSettings.currentColorSchemeIndex(for: .cavaWindow), fireIndex)
        XCTAssertEqual(CavaSettings.currentColorSchemeIndex(for: .mainWindow), iceIndex)
    }

    func testSkinChangeAppliesIncomingCavaTransparencyDefault() {
        CavaSettings.transparentBackground = false

        CavaSettings.resetAppearanceForSkinChange(transparentBackground: true)
        XCTAssertTrue(CavaSettings.transparentBackground)
        XCTAssertFalse(CavaSettings.isTransparencyCustomized)

        CavaSettings.resetAppearanceForSkinChange(transparentBackground: false)
        XCTAssertFalse(CavaSettings.transparentBackground)
        XCTAssertFalse(CavaSettings.isTransparencyCustomized)
    }

    func testLaunchRepairsUncustomizedTransparencyWithoutReplacingUserChoice() {
        CavaSettings.resetAppearanceForSkinChange(transparentBackground: false)

        CavaSettings.applyTransparencyDefaultIfUncustomized(true)
        XCTAssertTrue(CavaSettings.transparentBackground)

        CavaSettings.setTransparentBackground(false, customized: true)
        CavaSettings.applyTransparencyDefaultIfUncustomized(true)
        XCTAssertFalse(CavaSettings.transparentBackground)
        XCTAssertTrue(CavaSettings.isTransparencyCustomized)
    }

    func testCavaTransparencyDefaultFollowsSkinWindowOpacity() throws {
        let glassConfigURL = try XCTUnwrap(
            BundleHelper.url(
                forResource: "skin",
                withExtension: "json",
                subdirectory: "Resources/Skins/SmoothGlass"
            )
        )
        let opaqueConfigURL = try XCTUnwrap(
            BundleHelper.url(
                forResource: "skin",
                withExtension: "json",
                subdirectory: "Resources/Skins/NeonWave"
            )
        )
        let glassSkin = try ModernSkinLoader.shared.load(
            from: glassConfigURL.deletingLastPathComponent()
        )
        let opaqueSkin = try ModernSkinLoader.shared.load(
            from: opaqueConfigURL.deletingLastPathComponent()
        )
        let metalSkin = ModernSkinLoader.shared.createBuiltInMetalSkin(named: "Brushed Steel")

        XCTAssertTrue(glassSkin.cavaTransparentBackgroundDefault)
        XCTAssertFalse(opaqueSkin.cavaTransparentBackgroundDefault)
        XCTAssertFalse(metalSkin.cavaTransparentBackgroundDefault)
    }

    func testClassicSkinRestorePreservesCavaAppearanceWhileExplicitLoadResetsIt() throws {
        let skinURL = try XCTUnwrap(
            BundleHelper.url(
                forResource: "NullPlayer-Silver",
                withExtension: "wsz",
                subdirectory: "Resources/Skins"
            )
        )
        let suiteName = "CavaSettingsTests.classicSkinLoad.\(UUID().uuidString)"
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        CavaSettings.setHasCustomColors(true, for: .cavaWindow)
        CavaSettings.setHasCustomColors(true, for: .mainWindow)
        CavaSettings.transparentBackground = true

        XCTAssertTrue(WindowManager.shared.restoreClassicSkin(from: skinURL, userDefaults: testDefaults))
        XCTAssertTrue(CavaSettings.hasCustomColors(for: .cavaWindow))
        XCTAssertTrue(CavaSettings.hasCustomColors(for: .mainWindow))
        XCTAssertTrue(CavaSettings.transparentBackground)

        XCTAssertTrue(WindowManager.shared.loadSkin(from: skinURL, userDefaults: testDefaults))
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .cavaWindow))
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .mainWindow))
        XCTAssertFalse(CavaSettings.transparentBackground)
    }

    func testMetalCavaTransparentContentRetainsWindowServerInputMask() throws {
        let skin = ModernSkinLoader.shared.createBuiltInMetalSkin(named: "Brushed Steel")
        skin.renderStyle = .metal
        let transparentGap = try renderedTransparentCavaBackingColor(for: skin)

        XCTAssertEqual(
            transparentGap.alphaComponent,
            ModernCavaView.transparentInteractionAlpha,
            accuracy: 1.0 / 255.0
        )
        XCTAssertLessThan(transparentGap.alphaComponent, 0.01)

        CavaSettings.transparentBackground = true
        let view = ModernCavaView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        XCTAssertTrue(view.hitTest(NSPoint(x: 160, y: 40)) === view)
        XCTAssertTrue(view.acceptsFirstMouse(for: nil))
    }

    func testGlassCavaTransparentContentPreservesConfiguredWindowOpacity() throws {
        let configURL = try XCTUnwrap(
            BundleHelper.url(
                forResource: "skin",
                withExtension: "json",
                subdirectory: "Resources/Skins/SmoothGlass"
            )
        )
        let skin = try ModernSkinLoader.shared.load(from: configURL.deletingLastPathComponent())
        skin.renderStyle = .standard
        let transparentGap = try renderedTransparentCavaBackingColor(for: skin)

        XCTAssertEqual(
            transparentGap.alphaComponent,
            skin.spectrumWindowBackgroundOpacity,
            accuracy: 1.0 / 255.0
        )
        XCTAssertGreaterThan(transparentGap.alphaComponent, 0.5)
    }

    private func renderedTransparentCavaBackingColor(for skin: ModernSkin) throws -> NSColor {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 20,
                pixelsHigh: 20,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        ModernCavaView.drawTransparentContentBacking(
            in: NSRect(x: 0, y: 0, width: 20, height: 20),
            clippedTo: NSRect(x: 0, y: 0, width: 20, height: 20),
            renderer: ModernSkinRenderer(skin: skin, scaleFactor: 1),
            context: graphics.cgContext
        )
        return try XCTUnwrap(bitmap.colorAt(x: 10, y: 10))
    }

    func testClassicStackRepairIncludesCavaAfterFlow() throws {
        let main = NSRect(x: 100, y: 500, width: 275, height: Skin.mainWindowSize.height)
        let rowHeight = SkinElements.SpectrumWindow.windowSize.height
        let flow = NSRect(
            x: 103,
            y: main.minY - rowHeight + 5,
            width: 300,
            height: rowHeight
        )
        let cava = NSRect(
            x: 104,
            y: flow.minY - rowHeight + 7,
            width: 310,
            height: rowHeight
        )

        let repaired = AppStateManager.repairClassicCenterStackFrames(
            mainFrame: main,
            equalizerFrame: nil,
            playlistFrame: nil,
            spectrumFrame: nil,
            waveformFrame: nil,
            audioAnalysisFrame: nil,
            peppyMeterFrame: nil,
            networkMonitorFrame: flow,
            cavaFrame: cava,
            scale: 1
        )

        let repairedFlow = try XCTUnwrap(repaired.networkMonitorFrame)
        let repairedCava = try XCTUnwrap(repaired.cavaFrame)
        XCTAssertEqual(repairedFlow.maxY, repaired.mainFrame.minY, accuracy: 0.001)
        XCTAssertEqual(repairedCava.maxY, repairedFlow.minY, accuracy: 0.001)
        XCTAssertEqual(repairedCava.minX, repaired.mainFrame.minX, accuracy: 0.001)
        XCTAssertTrue(repaired.repaired)
    }
}
