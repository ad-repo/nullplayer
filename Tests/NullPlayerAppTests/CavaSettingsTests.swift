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

    func testCompactWindowDefaultsToStereoWithSmoothTuning() {
        XCTAssertEqual(CavaSettings.mode(for: .compactWindow), .stereo)
        XCTAssertEqual(CavaSettings.barCount(for: .compactWindow), CavaSettings.defaultBrowserBarCount)
        XCTAssertEqual(
            CavaSettings.noiseReduction(for: .compactWindow),
            CavaSettings.defaultCompactNoiseReduction,
            accuracy: 0.001
        )
    }

    func testCompactWindowCanStillUseExplicitMono() {
        CavaSettings.setMode(.mono, for: .compactWindow)

        XCTAssertEqual(CavaSettings.mode(for: .compactWindow), .mono)
    }

    func testLibraryWindowDefaultsToMonoButPreservesExplicitStereo() {
        XCTAssertEqual(CavaSettings.mode(for: .libraryWindow), .mono)
        XCTAssertEqual(CavaSettings.barCount(for: .libraryWindow), CavaSettings.defaultBrowserBarCount)

        CavaSettings.setMode(.stereo, for: .libraryWindow)

        XCTAssertEqual(CavaSettings.mode(for: .libraryWindow), .stereo)
    }

    func testCompactWindowVisualsMenuIsAvailableInDefaultBuild() {
        XCTAssertTrue(AppCapabilities.supports(.compactWindowVisualsMenu))

        let menu = ContextMenuBuilder.buildCompactBackdropMenu()
        XCTAssertEqual(
            Array(menu.items.prefix(4)).map(\.title),
            ["Off", "Cava", "Art", "Cava + Art"]
        )

        let libraryMenu = ContextMenuBuilder.buildLibraryBackdropMenu()
        XCTAssertEqual(
            Array(libraryMenu.items.prefix(4)).map(\.title),
            ["Off", "Cava", "Art", "Cava + Art"]
        )
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

    func testCompactWindowTuningHasAnIndependentNamespace() {
        CavaSettings.setBarCount(19, for: .mainWindow)
        CavaSettings.setBarCount(48, for: .cavaWindow)
        CavaSettings.setBarCount(64, for: .compactWindow)
        CavaSettings.setNoiseReduction(0.8, for: .compactWindow)

        XCTAssertEqual(CavaSettings.barCount(for: .compactWindow), 64)
        XCTAssertEqual(CavaSettings.noiseReduction(for: .compactWindow), 0.8, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.barCount(for: .mainWindow), 19)
        XCTAssertEqual(CavaSettings.barCount(for: .cavaWindow), 48)
        XCTAssertEqual(CavaSettings.mode(for: .compactWindow), .stereo)
        XCTAssertEqual(CavaSettings.barCountPresets(for: .compactWindow), [16, 24, 32, 48, 64])
    }

    func testLibraryWindowTuningHasAnIndependentNamespace() {
        CavaSettings.setBarCount(48, for: .libraryWindow)
        CavaSettings.setNoiseReduction(0.9, for: .libraryWindow)

        XCTAssertEqual(CavaSettings.barCount(for: .libraryWindow), 48)
        XCTAssertEqual(CavaSettings.noiseReduction(for: .libraryWindow), 0.9, accuracy: 0.001)
        XCTAssertEqual(CavaSettings.barCount(for: .compactWindow), CavaSettings.defaultBrowserBarCount)
        XCTAssertEqual(
            CavaSettings.noiseReduction(for: .compactWindow),
            CavaSettings.defaultCompactNoiseReduction,
            accuracy: 0.001
        )
    }

    func testBrowserWindowTuningResetRestoresSixtyFourBars() {
        CavaSettings.setBarCount(16, for: .libraryWindow)
        CavaSettings.setBarCount(24, for: .compactWindow)

        CavaSettings.resetTuning(scope: .libraryWindow)
        CavaSettings.resetTuning(scope: .compactWindow)

        XCTAssertEqual(CavaSettings.barCount(for: .libraryWindow), 64)
        XCTAssertEqual(CavaSettings.barCount(for: .compactWindow), 64)
    }

    func testMirroredMonoBackdropCoversBothHorizontalEdges() {
        let entries = CavaDrawing.monoBarRects(
            in: CGRect(x: 0, y: 0, width: 200, height: 100),
            bars: [0.25, 0.75],
            layout: .mirrored
        ).sorted { $0.rect.minX < $1.rect.minX }

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.first?.rect.minX, 0)
        XCTAssertEqual(entries.last?.rect.maxX, 200)
        XCTAssertEqual(entries.map(\.rect.height), [75, 25, 25, 75])
    }

    func testCompactWindowPreferenceKeysExcludeStandaloneTransparency() {
        let keys = CavaSettings.preferenceKeys(for: .compactWindow)

        XCTAssertTrue(keys.contains("cava.compactWindow.barCount"))
        XCTAssertTrue(keys.contains("cava.compactWindow.colorsCustomized"))
        XCTAssertFalse(keys.contains("cava.compactWindow.transparentBackground"))
        XCTAssertFalse(keys.contains("cava.compactWindow.transparencyCustomized"))
    }

    func testLibraryWindowPreferenceKeysExcludeStandaloneTransparency() {
        let keys = CavaSettings.preferenceKeys(for: .libraryWindow)

        XCTAssertTrue(keys.contains("cava.libraryWindow.barCount"))
        XCTAssertTrue(keys.contains("cava.libraryWindow.colorsCustomized"))
        XCTAssertFalse(keys.contains("cava.libraryWindow.transparentBackground"))
        XCTAssertFalse(keys.contains("cava.libraryWindow.transparencyCustomized"))
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
        CavaSettings.setHasCustomColors(true, for: .compactWindow)
        CavaSettings.setHasCustomColors(true, for: .libraryWindow)
        CavaSettings.transparentBackground = true

        CavaSettings.resetAppearanceForSkinChange()

        XCTAssertFalse(CavaSettings.hasCustomColors(for: .cavaWindow))
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .mainWindow))
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .compactWindow))
        XCTAssertFalse(CavaSettings.hasCustomColors(for: .libraryWindow))
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

    func testBundledModernSkinsDefaultEmbeddedVisualizerToCava() throws {
        let bundledSkinNames = [
            "ArcticMinimal",
            "BananaParty",
            "BloodGlass",
            "Bubblegum Retro",
            "EmeraldForge",
            "ForgedTitanium",
            "HyperPopPrism",
            "IndustrialSignal",
            "NeonWave",
            "Sakura Minimal",
            "SeaGlass",
            "Skulls",
            "SmoothGlass",
        ]

        for name in bundledSkinNames {
            let configURL = try XCTUnwrap(
                BundleHelper.url(
                    forResource: "skin",
                    withExtension: "json",
                    subdirectory: "Resources/Skins/\(name)"
                ),
                "Missing bundled skin config for \(name)"
            )
            let skin = try ModernSkinLoader.shared.load(from: configURL.deletingLastPathComponent())
            XCTAssertEqual(
                skin.config.visualization?.mainWindowMode,
                MainWindowVisMode.cava.rawValue,
                "\(name) should default its embedded visualizer to Cava"
            )
        }
    }

    func testBuiltInMetalSkinsDefaultEmbeddedVisualizerToCava() {
        for name in ModernSkinLoader.builtInMetalSkinNames {
            let skin = ModernSkinLoader.shared.createBuiltInMetalSkin(named: name)
            XCTAssertEqual(
                skin.config.visualization?.mainWindowMode,
                MainWindowVisMode.cava.rawValue,
                "\(name) should default its embedded visualizer to Cava"
            )
            XCTAssertEqual(
                skin.config.visualization?.spectrumWindowMode,
                SpectrumQualityMode.visClassicExact.rawValue,
                "\(name) should retain vis_classic for the dedicated Spectrum window"
            )
        }
    }

    func testClassicVisualizationDefaultRemainsVisClassic() throws {
        let suiteName = "CavaSettingsTests.classicVisualizationDefault.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        WindowManager.shared.writeClassicVisualizationDefaultKeys(for: .all, defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: "mainWindowVisMode"),
            MainWindowVisMode.visClassicExact.rawValue
        )
        XCTAssertEqual(
            defaults.string(forKey: "spectrumQualityMode"),
            SpectrumQualityMode.visClassicExact.rawValue
        )
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
