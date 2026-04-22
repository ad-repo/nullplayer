import XCTest
@testable import NullPlayer

final class TimeDisplayFormatterTests: XCTestCase {
    func testDecimalFormattingMatchesCurrentBehavior() {
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .decimal),
            "4:32"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: true, numberSystem: .decimal),
            "-4:32"
        )
    }

    func testAlternateDecimalScriptsMapDigits() {
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .arabicIndic),
            "٤:٣٢"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .extendedArabicIndic),
            "۴:۳۲"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .devanagari),
            "४:३२"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .bengali),
            "৪:৩২"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .thai),
            "๔:๓๒"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .fullwidth),
            "４:３２"
        )
    }

    func testRadixFormattingSupportsDiscussedModes() {
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .octal),
            "4:40"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(minutes: 4, seconds: 32, isNegative: false, numberSystem: .hexadecimal),
            "4:20"
        )
    }

    func testRemainingModeOnlyShowsMinusWhenDurationExists() {
        XCTAssertEqual(
            TimeDisplayFormatter.string(currentTime: 32, duration: 0, mode: .remaining, numberSystem: .decimal),
            "0:32"
        )
        XCTAssertEqual(
            TimeDisplayFormatter.string(currentTime: 32, duration: 300, mode: .remaining, numberSystem: .decimal),
            "-4:28"
        )
    }
}
