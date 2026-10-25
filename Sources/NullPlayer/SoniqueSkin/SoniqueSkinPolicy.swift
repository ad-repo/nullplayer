import Foundation

/// The loading limits, the executable source of truth for `docs/sonique/phase-0-decision-record.md`
/// § *Loading limits*. Never relax one to make a skin load; amend the record, arguing the threat.
/// The corpus maxima each bound was checked against are in the record's § *Measured headroom*.
enum SoniqueSkinPolicy {
    /// SQ0002.
    static let fileBytes = 16 * 1_024 * 1_024
    /// SQ0003.
    static let entries = 256
    /// SQ0005. The corpus's longest side is a 9,241 px knob strip.
    static let imageSide = 16_384
    /// SQ0006, summed from JPEG headers before any decode. 64 Mpx is 256 MB of RGBA.
    static let decodedPixels = 64 * 1_024 * 1_024
    /// SQ0007.
    static let iniBytes = 256 * 1_024
}

/// The stable `SQ####` codes. Their meaning and which are fatal are locked in the decision record;
/// wording may improve, meaning may not.
enum SoniqueSkinDiagnosticCode: String {
    case notAnArchive = "SQ0001"
    case fileTooLarge = "SQ0002"
    case tooManyEntries = "SQ0003"
    case entryOutOfBounds = "SQ0004"
    case imageTooLarge = "SQ0005"
    case pixelBudgetExceeded = "SQ0006"
    case iniTooLarge = "SQ0007"
    case entryUnreadable = "SQ0008"
    case modeUsesDefault = "SQ0009"
    case regionClipped = "SQ0010"
    /// Emitted from S4, when `skin.ini` values are interpreted.
    case iniValueMalformed = "SQ0011"
}

/// One finding. A fatal one is thrown; warnings ride on the loaded `SoniqueSkin`.
struct SoniqueSkinFinding: Error, Hashable, CustomStringConvertible {
    let code: SoniqueSkinDiagnosticCode
    let message: String

    init(_ code: SoniqueSkinDiagnosticCode, _ message: String) {
        self.code = code
        self.message = message
    }

    var description: String { "[\(code.rawValue)] \(message)" }
}
