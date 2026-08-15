import Foundation

/// A source position inside the logical Winamp VFS. Physical host paths are never exposed.
struct WalSourceLocation: Hashable, Codable, CustomStringConvertible {
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

enum WalDiagnosticSeverity: String, Codable {
    case warning
    case error
}

/// Stable diagnostic codes make import failures actionable in both the UI and tests.
enum WalDiagnosticCode: String, Codable {
    case invalidArchive
    case unsupportedContainer
    case entryLimitExceeded
    case entryTooLarge
    case totalSizeExceeded
    case compressionRatioExceeded
    case unsafePath
    case symbolicLink
    case caseCollision
    case invalidRoot
    case resourceMissing
    case resourceEscapesVFS
    case unresolvedPathVariable
    case includeCycle
    case includeDepthExceeded
    case xmlDepthExceeded
    case expandedNodeLimitExceeded
    case invalidImageResource
    case imageDimensionsExceeded
    case fontSizeExceeded
    case malformedXML
    case duplicateIdentifier
    case groupInheritanceCycle
    case groupInheritanceDepthExceeded
    case missingGroupDefinition
    case invalidScript
    case unsupportedScriptCapability
    case scriptBudgetExceeded
}

struct WalDiagnostic: Hashable, Codable, CustomStringConvertible {
    let severity: WalDiagnosticSeverity
    let code: WalDiagnosticCode
    let message: String
    let location: WalSourceLocation?

    init(
        _ code: WalDiagnosticCode,
        _ message: String,
        severity: WalDiagnosticSeverity = .error,
        location: WalSourceLocation? = nil
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

struct WalFailure: LocalizedError {
    let diagnostics: [WalDiagnostic]

    init(_ diagnostic: WalDiagnostic) {
        self.diagnostics = [diagnostic]
    }

    init(_ diagnostics: [WalDiagnostic]) {
        self.diagnostics = diagnostics
    }

    var errorDescription: String? {
        diagnostics.map(\.description).joined(separator: "\n")
    }
}
