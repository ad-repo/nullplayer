import Foundation

struct WinampModernAdditionalMount {
    let logicalRoot: String
    let provider: WalResourceProvider
}

/// Headless Phase 2 result: validated resources, expanded XML, registries, and a retained graph.
/// It intentionally owns no renderer, host playback adapter, or MAKI interpreter.
final class WinampModernLoadedSkin {
    let archive: WalArchive
    let vfs: WalVirtualFileSystem
    let document: WalExpandedXMLDocument
    let runtime: WasabiSkinRuntime
    let configuration: WinampModernConfiguration

    init(archive: WalArchive, vfs: WalVirtualFileSystem,
         document: WalExpandedXMLDocument, runtime: WasabiSkinRuntime,
         configuration: WinampModernConfiguration) {
        self.archive = archive
        self.vfs = vfs
        self.document = document
        self.runtime = runtime
        self.configuration = configuration
    }

    func teardown() { runtime.teardown() }
}

final class WinampModernSkinLoader {
    let archiveLimits: WalArchiveLimits
    let xmlLimits: WalXMLLimits

    init(archiveLimits: WalArchiveLimits = .production, xmlLimits: WalXMLLimits = .production) {
        self.archiveLimits = archiveLimits
        self.xmlLimits = xmlLimits
    }

    func load(from archiveURL: URL, additionalMounts: [WinampModernAdditionalMount] = []) throws -> WinampModernLoadedSkin {
        guard archiveURL.pathExtension.lowercased() == "wal" else {
            throw WalFailure(WalDiagnostic(.unsupportedContainer, "Winamp Modern skins must use the .wal extension."))
        }
        let archive = try WalArchive(url: archiveURL, limits: archiveLimits)
        let mountName = Self.safeMountName(archiveURL.deletingPathExtension().lastPathComponent)
        let vfs = try WalVirtualFileSystem(skinName: mountName, skin: archive)
        for mount in additionalMounts { try vfs.mount(mount.provider, at: mount.logicalRoot) }
        let entryPath = "/Skins/\(mountName)/\(archive.skinXMLPath)"
        let document = try WalXMLDocumentLoader(vfs: vfs, limits: xmlLimits).load(entryPath: entryPath)
        let runtime = try WasabiSkinInitializer(vfs: vfs,
                                                maximumObjectCount: xmlLimits.maximumExpandedNodeCount)
            .initialize(document: document)
        return WinampModernLoadedSkin(archive: archive, vfs: vfs, document: document, runtime: runtime,
                                     configuration: WinampModernConfiguration(namespace: mountName))
    }

    private static func safeMountName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "ImportedSkin" : result
    }
}
