import Foundation

enum WinampModernContainerKind: String {
    case walArchive
    case classicProInstaller
}

struct WinampModernValidatedContainer {
    let kind: WinampModernContainerKind
    let sourceURL: URL
    let displayName: String
    let preferredFilename: String
}

protocol WinampModernContainerIngesting {
    func supports(_ sourceURL: URL) -> Bool
    func validate(_ sourceURL: URL) throws -> WinampModernValidatedContainer
}

struct WalContainerIngestor: WinampModernContainerIngesting {
    let limits: WalArchiveLimits

    init(limits: WalArchiveLimits = .production) { self.limits = limits }

    func supports(_ sourceURL: URL) -> Bool { sourceURL.pathExtension.lowercased() == "wal" }

    func validate(_ sourceURL: URL) throws -> WinampModernValidatedContainer {
        guard supports(sourceURL) else {
            throw WalFailure(WalDiagnostic(.unsupportedContainer, "Expected a .wal skin archive, not '.\(sourceURL.pathExtension)'."))
        }
        _ = try WalArchive(url: sourceURL, limits: limits)
        let filename = sourceURL.lastPathComponent
        return WinampModernValidatedContainer(
            kind: .walArchive,
            sourceURL: sourceURL,
            displayName: sourceURL.deletingPathExtension().lastPathComponent,
            preferredFilename: filename
        )
    }
}

struct WinampModernImportedSkin: Equatable {
    let name: String
    let archiveURL: URL
}

/// Single ingestion seam for all user-supplied Winamp Modern containers. Phase 2 ships the `.wal`
/// strategy; Phase 6 adds the internal NSIS strategy without changing picker or storage code.
final class WinampModernSkinImporter {
    static let shared = WinampModernSkinImporter()

    let destinationDirectory: URL
    private let fileManager: FileManager
    private let ingestors: [WinampModernContainerIngesting]

    init(
        destinationDirectory: URL? = nil,
        fileManager: FileManager = .default,
        ingestors: [WinampModernContainerIngesting] = [WalContainerIngestor()]
    ) {
        self.fileManager = fileManager
        self.destinationDirectory = destinationDirectory ?? Self.defaultDestinationDirectory(fileManager: fileManager)
        self.ingestors = ingestors
    }

    static func defaultDestinationDirectory(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NullPlayer", isDirectory: true)
            .appendingPathComponent("WinampModernSkins", isDirectory: true)
    }

    @discardableResult
    func importContainer(at sourceURL: URL) throws -> WinampModernImportedSkin {
        guard let ingestor = ingestors.first(where: { $0.supports(sourceURL) }) else {
            let ext = sourceURL.pathExtension.isEmpty ? "(none)" : sourceURL.pathExtension
            throw WalFailure(WalDiagnostic(.unsupportedContainer, "Unsupported Winamp Modern container extension '\(ext)'."))
        }

        // Validation is deliberately complete before the installed archive can be replaced.
        let validated = try ingestor.validate(sourceURL)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destination = destinationDirectory.appendingPathComponent(validated.preferredFilename, isDirectory: false)
        if sourceURL.standardizedFileURL != destination.standardizedFileURL {
            let staging = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).wal-importing")
            defer { try? fileManager.removeItem(at: staging) }
            try fileManager.copyItem(at: sourceURL, to: staging)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        }
        return WinampModernImportedSkin(name: validated.displayName, archiveURL: destination)
    }

    func installedSkins() -> [WinampModernImportedSkin] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: destinationDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.pathExtension.lowercased() == "wal" }
            .map { WinampModernImportedSkin(name: $0.deletingPathExtension().lastPathComponent, archiveURL: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
