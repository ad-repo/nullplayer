import Foundation

/// The stable `AUD####` codes. Their meaning is locked in
/// `docs/audion-face/phase-0-decision-record.md` § *Loading limits*, which also says which are fatal;
/// wording may improve, meaning may not.
enum AudionFaceDiagnosticCode: String {
    case missingIndex = "AUD0001"
    case missingBase = "AUD0002"
    case indexTooLarge = "AUD0003"
    case imageTooLarge = "AUD0004"
    case faceTooLarge = "AUD0005"
    case pathEscape = "AUD0006"
    case pictOutOfRange = "AUD0007"
    case maskSizeMismatch = "AUD0008"
    case buttonWithoutSprite = "AUD0009"
    case zipOverLimit = "AUD0010"
    case pixelBudgetExceeded = "AUD0011"
    case malformedIndex = "AUD0012"
    case elementDropped = "AUD0013"
    case unreadableZip = "AUD0014"
}

/// One finding. A fatal one is thrown; warnings ride on the loaded `AudionFace`.
struct AudionFaceFinding: Error, Hashable, CustomStringConvertible {
    let code: AudionFaceDiagnosticCode
    let message: String

    init(_ code: AudionFaceDiagnosticCode, _ message: String) {
        self.code = code
        self.message = message
    }

    var description: String { "[\(code.rawValue)] \(message)" }
}
