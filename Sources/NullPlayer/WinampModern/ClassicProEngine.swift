import CryptoKit
import Foundation
import ZIPFoundation

/// Provenance/integrity summary of an imported ClassicPro engine.
struct ClassicProEngineInfo: Codable, Equatable {
    /// Engine families discovered at the root, e.g. `["one", "two"]`. cPro-Bento pins `one`.
    let families: [String]
    let fileCount: Int
    /// SHA-256 over the sorted (path, bytes) of the engine tree.
    let contentHash: String
}

/// Private, one-time store for the user-supplied ClassicPro engine. The engine is imported once and
/// reused for every cPro `.wal`; it is mounted read-only at the logical `/Plugins/classicPro/engine/`
/// path and never exposes the real filesystem to skins.
final class ClassicProEngineStore {
    static let shared = ClassicProEngineStore()

    /// Logical VFS mount every cPro skin's `load.xml` include resolves to.
    static let logicalMountRoot = "/Plugins/classicPro/engine"
    private static let infoFilename = ".engine-info.json"

    let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
    }

    static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        WinampModernSkinImporter.defaultDestinationDirectory(fileManager: fileManager)
            .appendingPathComponent("ClassicProEngine", isDirectory: true)
    }

    private var engineDirectory: URL { rootDirectory.appendingPathComponent("engine", isDirectory: true) }
    private var infoURL: URL { rootDirectory.appendingPathComponent(Self.infoFilename, isDirectory: false) }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: engineDirectory.appendingPathComponent("load.xml").path)
    }

    func info() -> ClassicProEngineInfo? {
        guard let data = try? Data(contentsOf: infoURL) else { return nil }
        return try? JSONDecoder().decode(ClassicProEngineInfo.self, from: data)
    }

    /// A read-only provider over the installed engine, for mounting at `logicalMountRoot`.
    func provider(limits: WalArchiveLimits = .production) throws -> WalResourceProvider {
        guard isInstalled else {
            throw WalFailure(WalDiagnostic(.resourceMissing,
                "No ClassicPro engine is installed. Import the engine to use cPro skins."))
        }
        return try WalDirectoryResourceProvider(rootURL: engineDirectory, limits: limits)
    }

    /// Persist a validated engine tree (paths relative to the engine root) atomically.
    func install(engineFiles: [String: Data]) throws -> ClassicProEngineInfo {
        let info = try Self.validate(engineFiles: engineFiles)
        let staging = rootDirectory.appendingPathComponent(".engine-importing-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        for (relative, data) in engineFiles {
            let destination = staging.appendingPathComponent(relative)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
        }

        // Swap the staged tree into place.
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: engineDirectory.path) {
            try fileManager.removeItem(at: engineDirectory)
        }
        try fileManager.moveItem(at: staging, to: engineDirectory)
        try JSONEncoder().encode(info).write(to: infoURL, options: .atomic)
        return info
    }

    /// Structure + provenance validation. cPro-Bento pins engine "one"; a tree lacking `load.xml` or
    /// the `one/` family is rejected as an engine-version mismatch.
    static func validate(engineFiles: [String: Data]) throws -> ClassicProEngineInfo {
        guard engineFiles["load.xml"] != nil else {
            throw WalFailure(WalDiagnostic(.invalidRoot,
                "This does not look like a ClassicPro engine (no load.xml at the engine root)."))
        }
        let families = Set(engineFiles.keys.compactMap { path -> String? in
            let parts = path.split(separator: "/")
            guard parts.count >= 2 else { return nil }
            let family = String(parts[0]).lowercased()
            return (family == "one" || family == "two") ? family : nil
        }).sorted()
        guard families.contains("one") else {
            throw WalFailure(WalDiagnostic(.invalidRoot,
                "This ClassicPro engine does not provide the \"one\" family required by cPro-Bento."))
        }
        var hasher = SHA256()
        for path in engineFiles.keys.sorted() {
            hasher.update(data: Data(path.utf8))
            hasher.update(data: engineFiles[path]!)
        }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return ClassicProEngineInfo(families: families, fileCount: engineFiles.count, contentHash: hash)
    }
}

/// Imports a user-supplied ClassicPro engine from an NSIS installer (`.exe`), a `.zip`, or an
/// already-extracted folder. All extraction happens internally — the user just points at a file.
final class ClassicProEngineImporter {
    static let shared = ClassicProEngineImporter()

    /// Case-insensitive prefix of the engine tree inside a full installer/zip extraction.
    private static let enginePrefix = "plugins/classicpro/engine/"

    let store: ClassicProEngineStore
    let limits: WalArchiveLimits
    private let fileManager: FileManager

    init(store: ClassicProEngineStore = .shared, limits: WalArchiveLimits = .production,
         fileManager: FileManager = .default) {
        self.store = store
        self.limits = limits
        self.fileManager = fileManager
    }

    @discardableResult
    func importEngine(from url: URL) throws -> ClassicProEngineInfo {
        let engineFiles = try engineFileMap(from: url)
        return try store.install(engineFiles: engineFiles)
    }

    /// Resolve any supported source to an engine-root-relative file map (`load.xml`, `one/...`, …).
    func engineFileMap(from url: URL) throws -> [String: Data] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Engine source '\(url.lastPathComponent)' does not exist."))
        }
        if isDirectory.boolValue {
            return try engineFilesFromDirectory(url)
        }
        switch url.pathExtension.lowercased() {
        case "exe":
            return Self.slice(engine: try NSISArchive.extract(data: try readBounded(url), limits: limits), sourceName: url.lastPathComponent)
        case "zip", "wal":
            return try engineFilesFromZip(url)
        default:
            throw WalFailure(WalDiagnostic(.unsupportedContainer,
                "Unsupported engine source '.\(url.pathExtension)'. Provide the ClassicPro installer (.exe), a .zip, or the extracted engine folder."))
        }
    }

    // MARK: - Source resolution

    private func engineFilesFromDirectory(_ directory: URL) throws -> [String: Data] {
        // If the directory *is* the engine root, use it directly.
        if fileManager.fileExists(atPath: directory.appendingPathComponent("load.xml").path) {
            let provider = try WalDirectoryResourceProvider(rootURL: directory, limits: limits)
            var map: [String: Data] = [:]
            for path in provider.resourcePaths { map[path] = try provider.data(for: path) }
            return map
        }
        // Otherwise look for a nested Plugins/ClassicPro/engine/ tree.
        let provider = try WalDirectoryResourceProvider(rootURL: directory, limits: limits)
        var full: [String: Data] = [:]
        for path in provider.resourcePaths { full[path] = try provider.data(for: path) }
        return Self.slice(engine: full, sourceName: directory.lastPathComponent)
    }

    private func engineFilesFromZip(_ url: URL) throws -> [String: Data] {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw WalFailure(WalDiagnostic(.invalidArchive, "Unable to open '\(url.lastPathComponent)' as a ZIP archive."))
        }
        var files: [String: Data] = [:]
        var total: UInt64 = 0
        var nestedInstaller: (name: String, data: Data)?
        for entry in archive where entry.type == .file {
            guard entry.uncompressedSize <= limits.maximumEntrySize else {
                throw WalFailure(WalDiagnostic(.entryTooLarge, "ZIP entry '\(entry.path)' is too large."))
            }
            let (newTotal, overflow) = total.addingReportingOverflow(entry.uncompressedSize)
            guard !overflow, newTotal <= limits.maximumTotalSize else {
                throw WalFailure(WalDiagnostic(.totalSizeExceeded, "ZIP expands beyond the total limit."))
            }
            total = newTotal
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            let normalized = entry.path.replacingOccurrences(of: "\\", with: "/")
            if normalized.lowercased().hasSuffix(".exe"), nestedInstaller == nil {
                nestedInstaller = (entry.path, data)
            }
            files[normalized] = data
        }
        // Prefer an embedded engine tree; otherwise fall back to a nested NSIS installer.
        let sliced = Self.slice(engine: files, sourceName: url.lastPathComponent)
        if !sliced.isEmpty { return sliced }
        if let installer = nestedInstaller {
            return Self.slice(engine: try NSISArchive.extract(data: installer.data, limits: limits),
                              sourceName: installer.name)
        }
        throw WalFailure(WalDiagnostic(.invalidRoot,
            "'\(url.lastPathComponent)' contains neither a ClassicPro engine tree nor an installer."))
    }

    private func readBounded(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard UInt64(data.count) <= limits.maximumTotalSize * 2 else {
            throw WalFailure(WalDiagnostic(.totalSizeExceeded, "Engine source is too large to import."))
        }
        return data
    }

    /// Keep only files under `Plugins/ClassicPro/engine/`, rekeyed relative to the engine root.
    private static func slice(engine files: [String: Data], sourceName: String) -> [String: Data] {
        var result: [String: Data] = [:]
        for (path, data) in files {
            let normalized = path.replacingOccurrences(of: "\\", with: "/")
            let folded = normalized.lowercased()
            guard let range = folded.range(of: enginePrefix) else { continue }
            let relative = String(normalized[normalized.index(normalized.startIndex, offsetBy: folded.distance(from: folded.startIndex, to: range.upperBound))...])
            guard !relative.isEmpty else { continue }
            result[relative] = data
        }
        return result
    }
}
