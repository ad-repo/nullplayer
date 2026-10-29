import XCTest
@testable import NullPlayer

/// The classic EQ slider bar sprites: a 2 × 14 grid of 14-px states on a 15-px stride, so the
/// 1-px gap column after each state (which some skins paint) is never copied.
final class ClassicEQSliderBarTests: XCTestCase {
    func testSourceRectsSkipTheGapColumn() {
        let eq = SkinElements.Equalizer.self
        XCTAssertEqual(eq.sliderBarSource(state: 0), NSRect(x: 13, y: 164, width: 14, height: 63))
        XCTAssertEqual(eq.sliderBarSource(state: 13), NSRect(x: 208, y: 164, width: 14, height: 63))
        XCTAssertEqual(eq.sliderBarSource(state: 14), NSRect(x: 13, y: 229, width: 14, height: 63))
        XCTAssertEqual(eq.sliderBarSource(state: 99), eq.sliderBarSource(state: 27))
    }
}
