import XCTest
@testable import NullPlayer

/// `ModernSkinElements`' two scale globals — the process-wide state every Original window's geometry
/// is derived from.
///
/// They were plain `static var`s, writable from anywhere: an assignment from any file in the module
/// would have resized the whole UI with nothing to point at afterwards. They are `private(set)` now,
/// with one named setter each, and this pins both the composition rule and who owns each write.
final class ModernSkinScaleTests: XCTestCase {
    private var savedBase: CGFloat = 1.25
    private var savedMultiplier: CGFloat = 1.0

    override func setUp() {
        super.setUp()
        savedBase = ModernSkinElements.baseScaleFactor
        savedMultiplier = ModernSkinElements.sizeMultiplier
    }

    override func tearDown() {
        ModernSkinElements.applyBaseScaleFactor(savedBase)
        ModernSkinElements.applySizeMultiplier(savedMultiplier)
        super.tearDown()
    }

    /// The skin's `window.scale` and the user's UI Size are independent, and the effective scale is
    /// their product — which is why loading a skin must not disturb a chosen UI Size, and vice
    /// versa.
    func testTheEffectiveScaleIsTheProductOfTheTwoAndEachSurvivesTheOther() {
        ModernSkinElements.applyBaseScaleFactor(1.5)
        ModernSkinElements.applySizeMultiplier(2.0)

        XCTAssertEqual(ModernSkinElements.baseScaleFactor, 1.5)
        XCTAssertEqual(ModernSkinElements.sizeMultiplier, 2.0)
        XCTAssertEqual(ModernSkinElements.scaleFactor, 3.0, accuracy: 0.0001)

        // A skin load moves the base alone.
        ModernSkinElements.applyBaseScaleFactor(1.0)
        XCTAssertEqual(ModernSkinElements.sizeMultiplier, 2.0, "a skin load leaves the UI Size alone")
        XCTAssertEqual(ModernSkinElements.scaleFactor, 2.0, accuracy: 0.0001)

        // A UI Size change moves the multiplier alone.
        ModernSkinElements.applySizeMultiplier(0.5)
        XCTAssertEqual(ModernSkinElements.baseScaleFactor, 1.0,
                       "a UI Size change leaves the skin's own scale alone")
        XCTAssertEqual(ModernSkinElements.scaleFactor, 0.5, accuracy: 0.0001)
    }

    /// The window size the whole Original layout hangs off follows the effective scale.
    func testTheMainWindowSizeFollowsTheEffectiveScale() {
        ModernSkinElements.applyBaseScaleFactor(1.0)
        ModernSkinElements.applySizeMultiplier(1.0)
        XCTAssertEqual(ModernSkinElements.mainWindowSize.width,
                       ModernSkinElements.baseMainSize.width, accuracy: 0.0001)

        ModernSkinElements.applySizeMultiplier(2.0)
        XCTAssertEqual(ModernSkinElements.mainWindowSize.width,
                       ModernSkinElements.baseMainSize.width * 2, accuracy: 0.0001)
        XCTAssertEqual(ModernSkinElements.mainWindowSize.height,
                       ModernSkinElements.baseMainSize.height * 2, accuracy: 0.0001)
    }
}
