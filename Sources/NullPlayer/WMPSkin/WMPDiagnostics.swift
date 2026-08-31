import Foundation

struct WMPSourceLocation: Hashable, Codable, CustomStringConvertible {
    let path: String
    let line: Int
    let column: Int

    init(path: String, line: Int = 1, column: Int = 1) {
        self.path = path
        self.line = max(1, line)
        self.column = max(1, column)
    }

    var description: String { "\(path):\(line):\(column)" }
}

enum WMPDiagnosticSeverity: String, Codable {
    case warning
    case error
}

enum WMPDiagnosticCode: String, Codable {
    // WMP0001...WMP0020 are locked by the Phase 0 decision record.
    case invalidArchive = "WMP0001"
    case entryLimitExceeded = "WMP0002"
    case entryTooLarge = "WMP0003"
    case totalSizeExceeded = "WMP0004"
    case compressionRatioExceeded = "WMP0005"
    case absolutePath = "WMP0006"
    case drivePath = "WMP0007"
    case pathTraversal = "WMP0008"
    case symbolicLink = "WMP0009"
    case caseCollision = "WMP0010"
    case wrapperDepthExceeded = "WMP0011"
    case crcMismatch = "WMP0012"
    case xmlDepthExceeded = "WMP0013"
    case expandedNodeLimitExceeded = "WMP0014"
    case oversizedImage = "WMP0015"
    case oversizedScript = "WMP0016"
    case scriptMessageTooLarge = "WMP0017"
    case scriptTimedOut = "WMP0018"
    case scriptCrashed = "WMP0019"
    case scriptProtocolViolation = "WMP0020"

    case invalidRoot = "WMP0021"
    case ambiguousSkinDefinition = "WMP0022"
    case resourceMissing = "WMP0023"
    case resourceEscapesProvider = "WMP0024"
    case invalidTextEncoding = "WMP0025"
    case embeddedNUL = "WMP0026"
    case malformedXML = "WMP0027"
    case duplicateIdentifier = "WMP0028"
    case unsupportedResource = "WMP0029"
    case unsupportedAttributeValue = "WMP0030"
    case unresolvedGeometry = "WMP0031"
    case invalidGeometry = "WMP0032"
    case imageDecodeFailed = "WMP0033"
    case renderFailed = "WMP0035"
}

struct WMPDiagnostic: Hashable, Codable, CustomStringConvertible {
    let severity: WMPDiagnosticSeverity
    let code: WMPDiagnosticCode
    let message: String
    let location: WMPSourceLocation?

    init(
        _ code: WMPDiagnosticCode,
        _ message: String,
        severity: WMPDiagnosticSeverity = .error,
        location: WMPSourceLocation? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.location = location
    }

    var description: String {
        let prefix = location.map { "\($0): " } ?? ""
        return "\(prefix)[\(code.rawValue)] \(message)"
    }
}

struct WMPFailure: LocalizedError {
    let diagnostics: [WMPDiagnostic]

    init(_ diagnostic: WMPDiagnostic) {
        diagnostics = [diagnostic]
    }

    init(_ diagnostics: [WMPDiagnostic]) {
        self.diagnostics = diagnostics
    }

    var errorDescription: String? {
        diagnostics.map(\.description).joined(separator: "\n")
    }
}
