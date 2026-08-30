import Foundation

struct ReeltoneInstallationRecord: Codable, Equatable, Sendable {
    let identity: String
    let manifestID: String
    let name: String
    let manifestVersion: String?
    let installedAt: Date
}

struct ReeltoneInstalledSkin: Equatable, Sendable {
    let record: ReeltoneInstallationRecord
    let rootURL: URL
}

struct ReeltoneDiscoveryResult: Sendable {
    let installations: [ReeltoneInstalledSkin]
    let diagnostics: [ReeltoneDiagnostic]
}

final class ReeltoneSkinStore {
    static let metadataFilename = ".reeltone-installation.json"

    let rootURL: URL
    private let fileManager: FileManager
    private let loader: ReeltoneSkinLoader

    init(
        rootURL: URL? = nil,
        fileManager: FileManager = .default,
        limits: ReeltoneArchiveLimits = .published
    ) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootURL = applicationSupport
                .appendingPathComponent("NullPlayer", isDirectory: true)
                .appendingPathComponent("ReeltoneSkins", isDirectory: true)
        }
        loader = ReeltoneSkinLoader(fileManager: fileManager, limits: limits)
    }

    @discardableResult
    func install(archiveAt archiveURL: URL) throws -> ReeltoneInstalledSkin {
        try ensureRoot()
        let stage = rootURL.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        do {
            try loader.inspector.extractArchive(at: archiveURL, to: stage)
            let loaded = try loader.loadDirectory(at: stage)
            let identity = UUID().uuidString.lowercased()
            let record = ReeltoneInstallationRecord(
                identity: identity,
                manifestID: loaded.manifest.id,
                name: loaded.manifest.name,
                manifestVersion: loaded.manifest.version,
                installedAt: Date()
            )
            try write(record, under: stage)
            let destination = rootURL.appendingPathComponent(identity, isDirectory: true)
            try fileManager.moveItem(at: stage, to: destination)
            return ReeltoneInstalledSkin(record: record, rootURL: destination)
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
    }

    @discardableResult
    func replace(identity: String, withArchiveAt archiveURL: URL) throws -> ReeltoneInstalledSkin {
        try ensureRoot()
        let destination = try installationURL(for: identity)
        guard fileManager.fileExists(atPath: destination.path) else {
            throw ReeltoneDiagnostic(code: .installationNotFound, message: "Reeltone installation was not found")
        }
        let oldRecord = try readRecord(under: destination)
        let stage = rootURL.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        do {
            try loader.inspector.extractArchive(at: archiveURL, to: stage)
            let loaded = try loader.loadDirectory(at: stage)
            let record = ReeltoneInstallationRecord(
                identity: oldRecord.identity,
                manifestID: loaded.manifest.id,
                name: loaded.manifest.name,
                manifestVersion: loaded.manifest.version,
                installedAt: Date()
            )
            try write(record, under: stage)
            _ = try fileManager.replaceItemAt(destination, withItemAt: stage)
            return ReeltoneInstalledSkin(record: record, rootURL: destination)
        } catch {
            try? fileManager.removeItem(at: stage)
            throw error
        }
    }

    func remove(identity: String, defaults: UserDefaults = .standard) throws {
        let destination = try installationURL(for: identity)
        guard fileManager.fileExists(atPath: destination.path) else {
            throw ReeltoneDiagnostic(code: .installationNotFound, message: "Reeltone installation was not found")
        }
        try fileManager.removeItem(at: destination)
        if ReeltoneSkinState.selectedSkinIdentity(in: defaults) == identity {
            ReeltoneSkinState.selectSkin(identity: nil, in: defaults)
        }
    }

    func discover() -> ReeltoneDiscoveryResult {
        do { try ensureRoot() } catch {
            return ReeltoneDiscoveryResult(
                installations: [],
                diagnostics: [ReeltoneDiagnostic(code: .storeFailure, message: "Reeltone skin store is unavailable: \(error.localizedDescription)")]
            )
        }
        var installations: [ReeltoneInstalledSkin] = []
        var diagnostics: [ReeltoneDiagnostic] = []
        let children = (try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children {
            do {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }
                let record = try readRecord(under: child)
                guard record.identity == child.lastPathComponent else {
                    throw ReeltoneDiagnostic(code: .invalidManifest, message: "Installation metadata identity does not match its directory")
                }
                let loaded = try loader.loadDirectory(at: child)
                guard loaded.manifest.id == record.manifestID else {
                    throw ReeltoneDiagnostic(code: .invalidManifest, message: "Installed manifest ID does not match installation metadata")
                }
                installations.append(ReeltoneInstalledSkin(record: record, rootURL: child))
            } catch let diagnostic as ReeltoneDiagnostic {
                diagnostics.append(diagnostic)
            } catch {
                diagnostics.append(ReeltoneDiagnostic(code: .storeFailure, message: "Could not inspect installation '\(child.lastPathComponent)': \(error.localizedDescription)"))
            }
        }
        installations.sort {
            let comparison = $0.record.name.localizedCaseInsensitiveCompare($1.record.name)
            return comparison == .orderedSame ? $0.record.identity < $1.record.identity : comparison == .orderedAscending
        }
        return ReeltoneDiscoveryResult(installations: installations, diagnostics: diagnostics)
    }

    func preferredSkin(in defaults: UserDefaults = .standard) -> ReeltoneInstalledSkin? {
        guard let identity = ReeltoneSkinState.selectedSkinIdentity(in: defaults) else { return nil }
        return discover().installations.first { $0.record.identity == identity }
    }

    func selectPreferred(_ installation: ReeltoneInstalledSkin?, in defaults: UserDefaults = .standard) {
        ReeltoneSkinState.selectSkin(identity: installation?.record.identity, in: defaults)
    }

    func load(_ installation: ReeltoneInstalledSkin) throws -> ReeltoneLoadedSkin {
        try loader.loadDirectory(at: installation.rootURL)
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func installationURL(for identity: String) throws -> URL {
        guard UUID(uuidString: identity) != nil, identity.lowercased() == identity else {
            throw ReeltoneDiagnostic(code: .installationNotFound, message: "Invalid Reeltone installation identity")
        }
        return rootURL.appendingPathComponent(identity, isDirectory: true)
    }

    private func write(_ record: ReeltoneInstallationRecord, under root: URL) throws {
        let data = try JSONEncoder().encode(record)
        try data.write(to: root.appendingPathComponent(Self.metadataFilename), options: .atomic)
    }

    private func readRecord(under root: URL) throws -> ReeltoneInstallationRecord {
        let url = root.appendingPathComponent(Self.metadataFilename)
        do {
            return try JSONDecoder().decode(ReeltoneInstallationRecord.self, from: Data(contentsOf: url))
        } catch {
            throw ReeltoneDiagnostic(code: .storeFailure, message: "Installation metadata is missing or invalid")
        }
    }
}
