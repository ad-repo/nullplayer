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
    /// What the skin declared, measured before the graph existed (Phase 13.2).
    let surfaceInventory: WinampModernSurfaceInventory
    /// Which missing surfaces got a synthetic window, and why the others did not.
    let surfaceSynthesis: WasabiSurfaceSynthesizer.Result

    init(archive: WalArchive, vfs: WalVirtualFileSystem,
         document: WalExpandedXMLDocument, runtime: WasabiSkinRuntime,
         configuration: WinampModernConfiguration,
         surfaceInventory: WinampModernSurfaceInventory,
         surfaceSynthesis: WasabiSurfaceSynthesizer.Result) {
        self.archive = archive
        self.vfs = vfs
        self.document = document
        self.runtime = runtime
        self.configuration = configuration
        self.surfaceInventory = surfaceInventory
        self.surfaceSynthesis = surfaceSynthesis
    }

    /// The skin's one active colour theme, shared by every renderer and hosted surface it owns
    /// (Phase 13.5). Lazily built so a headless load that never renders pays nothing.
    lazy var themeCoordinator = WinampModernThemeCoordinator(loadedSkin: self)

    func teardown() { runtime.teardown() }

    /// Per-skin compatibility report from load-time diagnostics (missing resources/groups, unresolved
    /// predefined bases, etc.). A successful load with warnings is `.degraded`. To include runtime
    /// unsupported-MAKI-method demand, fold in `scriptRuntime.unsupportedMethodCalls` via
    /// `compatibilityReport(withRuntime:)`.
    var compatibilityReport: WinampModernCompatibilityReport {
        WinampModernCompatibilityReport(diagnostics: runtime.diagnostics)
    }

    func compatibilityReport(withRuntime scriptRuntime: WinampModernScriptRuntime)
        -> WinampModernCompatibilityReport {
        WinampModernCompatibilityReport(diagnostics: runtime.diagnostics + scriptRuntime.scriptFailures,
                                        unsupportedMethodCalls: scriptRuntime.unsupportedMethodCalls)
    }
}

final class WinampModernSkinLoader {
    let archiveLimits: WalArchiveLimits
    let xmlLimits: WalXMLLimits
    let engineStore: ClassicProEngineStore?

    init(archiveLimits: WalArchiveLimits = .production, xmlLimits: WalXMLLimits = .production,
         engineStore: ClassicProEngineStore? = .shared) {
        self.archiveLimits = archiveLimits
        self.xmlLimits = xmlLimits
        self.engineStore = engineStore
    }

    func load(from archiveURL: URL, additionalMounts: [WinampModernAdditionalMount] = []) throws -> WinampModernLoadedSkin {
        guard archiveURL.pathExtension.lowercased() == "wal" else {
            throw WalFailure(WalDiagnostic(.unsupportedContainer, "Winamp Modern skins must use the .wal extension."))
        }
        let archive = try WalArchive(url: archiveURL, limits: archiveLimits)
        let mountName = Self.safeMountName(archiveURL.deletingPathExtension().lastPathComponent)
        let vfs = try WalVirtualFileSystem(skinName: mountName, skin: archive)
        // Attach the user-supplied ClassicPro engine (once, reused across all cPro skins) at the
        // logical path cPro-Bento's include resolves to. Non-cPro skins simply never reference it.
        var mounts = additionalMounts
        if let engineStore, engineStore.isInstalled {
            mounts.append(WinampModernAdditionalMount(
                logicalRoot: ClassicProEngineStore.logicalMountRoot,
                provider: try engineStore.provider(limits: archiveLimits)))
        }
        for mount in mounts { try vfs.mount(mount.provider, at: mount.logicalRoot) }
        let entryPath = "/Skins/\(mountName)/\(archive.skinXMLPath)"
        let loaded = try WalXMLDocumentLoader(vfs: vfs, limits: xmlLimits).load(entryPath: entryPath)
        // Take stock of the skin's declared surfaces and append windows for the ones it leaves out,
        // *before* initialization, so synthetic XML is registered, validated, instantiated, and
        // script-bound by exactly the same passes as everything the skin wrote (Phase 13.2).
        let inventory = WinampModernSurfaceInventory.build(document: loaded)
        let synthesis = WasabiSurfaceSynthesizer.synthesize(document: loaded, inventory: inventory,
                                                            limits: xmlLimits)
        let document = synthesis.document
        let runtime = try WasabiSkinInitializer(vfs: vfs,
                                                maximumObjectCount: xmlLimits.maximumExpandedNodeCount)
            .initialize(document: document)
        for diagnostic in inventory.diagnostics { runtime.record(diagnostic) }
        return WinampModernLoadedSkin(archive: archive, vfs: vfs, document: document, runtime: runtime,
                                      configuration: WinampModernConfiguration(namespace: mountName),
                                      surfaceInventory: inventory, surfaceSynthesis: synthesis)
    }

    private static func safeMountName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let result = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "ImportedSkin" : result
    }
}
