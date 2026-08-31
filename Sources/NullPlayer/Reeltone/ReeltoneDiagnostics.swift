import Foundation

enum ReeltoneDiagnosticSeverity: String, Codable, Sendable {
    case warning
    case error
}

enum ReeltoneDiagnosticCode: String, Codable, Sendable {
    case unreadableArchive
    case invalidArchivePath
    case symbolicLink
    case duplicatePath
    case unexpectedRootLayout
    case entryCountLimit
    case uncompressedSizeLimit
    case compressionRatioLimit
    case malformedManifest
    case unsupportedFormatVersion
    case invalidManifest
    case missingResource
    case invalidResourcePath
    case invalidImage
    case imageDimensionLimit
    case decodedImageMemoryLimit
    case invalidFont
    case duplicateSingletonComponent
    case unsupportedConstruct
    case duplicateManifestID
    case installationNotFound
    case storeFailure
}

struct ReeltoneDiagnostic: Error, Codable, Equatable, Sendable, LocalizedError {
    let severity: ReeltoneDiagnosticSeverity
    let code: ReeltoneDiagnosticCode
    let message: String
    let codingPath: [String]
    let resourcePath: String?
    let skinID: String?
    let surfaceID: String?
    let regionIndex: Int?
    let component: String?

    init(
        severity: ReeltoneDiagnosticSeverity = .error,
        code: ReeltoneDiagnosticCode,
        message: String,
        codingPath: [String] = [],
        resourcePath: String? = nil,
        skinID: String? = nil,
        surfaceID: String? = nil,
        regionIndex: Int? = nil,
        component: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.codingPath = codingPath
        self.resourcePath = resourcePath
        self.skinID = skinID
        self.surfaceID = surfaceID
        self.regionIndex = regionIndex
        self.component = component
    }

    var errorDescription: String? {
        let location = codingPath.isEmpty ? "" : " at \(codingPath.joined(separator: "."))"
        return "\(message)\(location)"
    }
}

extension ReeltoneDiagnostic {
    static func decoding(_ error: Error) -> ReeltoneDiagnostic {
        let context: DecodingError.Context
        let message: String
        switch error {
        case let DecodingError.keyNotFound(key, value):
            context = value
            message = "Missing required field '\(key.stringValue)'"
        case let DecodingError.typeMismatch(type, value):
            context = value
            message = "Expected \(type): \(value.debugDescription)"
        case let DecodingError.valueNotFound(type, value):
            context = value
            message = "Missing \(type): \(value.debugDescription)"
        case let DecodingError.dataCorrupted(value):
            context = value
            message = value.debugDescription
        default:
            return ReeltoneDiagnostic(code: .malformedManifest, message: error.localizedDescription)
        }
        return ReeltoneDiagnostic(
            code: .malformedManifest,
            message: message,
            codingPath: context.codingPath.map(\.stringValue)
        )
    }
}
