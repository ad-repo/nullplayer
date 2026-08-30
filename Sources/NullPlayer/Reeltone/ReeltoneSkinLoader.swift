import Foundation

final class ReeltoneLoadedSkin {
    let manifest: ReeltoneManifest
    let rootURL: URL
    let resources: [String: ReeltoneResourceHandle]
    let imageInfo: [String: ReeltoneImageInfo]
    let diagnostics: [ReeltoneDiagnostic]

    private var cleanupURL: URL?

    init(
        manifest: ReeltoneManifest,
        rootURL: URL,
        resources: [String: ReeltoneResourceHandle],
        imageInfo: [String: ReeltoneImageInfo],
        diagnostics: [ReeltoneDiagnostic] = [],
        cleanupURL: URL? = nil
    ) {
        self.manifest = manifest
        self.rootURL = rootURL
        self.resources = resources
        self.imageInfo = imageInfo
        self.diagnostics = diagnostics
        self.cleanupURL = cleanupURL
    }

    deinit {
        close()
    }

    func close() {
        guard let cleanupURL else { return }
        self.cleanupURL = nil
        try? FileManager.default.removeItem(at: cleanupURL)
    }
}

struct ReeltoneSkinLoader {
    static let temporaryDirectoryPrefix = "ReeltoneSkin_"

    let fileManager: FileManager
    let inspector: ReeltoneArchiveInspector
    let temporaryDirectory: URL

    init(
        fileManager: FileManager = .default,
        limits: ReeltoneArchiveLimits = .published,
        temporaryDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.inspector = ReeltoneArchiveInspector(limits: limits)
        self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
    }

    func loadArchive(at archiveURL: URL) throws -> ReeltoneLoadedSkin {
        let temporaryRoot = temporaryDirectory.appendingPathComponent(Self.temporaryDirectoryPrefix + UUID().uuidString, isDirectory: true)
        do {
            try inspector.extractArchive(at: archiveURL, to: temporaryRoot)
            return try loadDirectory(at: temporaryRoot, cleanupURL: temporaryRoot)
        } catch {
            try? fileManager.removeItem(at: temporaryRoot)
            throw error
        }
    }

    func loadDirectory(at rootURL: URL) throws -> ReeltoneLoadedSkin {
        try loadDirectory(at: rootURL, cleanupURL: nil)
    }

    private func loadDirectory(at rootURL: URL, cleanupURL: URL?) throws -> ReeltoneLoadedSkin {
        let manifestURL = rootURL.appendingPathComponent("skin.json", isDirectory: false)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: manifestURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ReeltoneDiagnostic(code: .unexpectedRootLayout, message: "skin.json must be a file at the skin root")
        }

        let manifest: ReeltoneManifest
        do {
            manifest = try ReeltoneManifestDecoder.decode(Data(contentsOf: manifestURL))
        } catch let diagnostic as ReeltoneDiagnostic {
            throw diagnostic
        } catch {
            throw ReeltoneDiagnostic(code: .malformedManifest, message: "skin.json could not be read: \(error.localizedDescription)")
        }

        var resources: [String: ReeltoneResourceHandle] = [:]
        for path in manifest.referencedResources {
            let handle = try ReeltoneResourceHandle(relativePath: path, root: rootURL)
            var isResourceDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: handle.fileURL.path, isDirectory: &isResourceDirectory), !isResourceDirectory.boolValue else {
                throw ReeltoneDiagnostic(code: .missingResource, message: "Referenced resource is missing", resourcePath: path)
            }
            let resolved = handle.fileURL.resolvingSymlinksInPath()
            let canonicalRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(canonicalRoot.path + "/") else {
                throw ReeltoneDiagnostic(code: .invalidResourcePath, message: "Referenced resource escapes the skin root", resourcePath: path)
            }
            resources[path] = handle
        }

        let imageHandles = try manifest.referencedImages.sorted().map { path -> ReeltoneResourceHandle in
            guard let handle = resources[path] else {
                throw ReeltoneDiagnostic(code: .missingResource, message: "Referenced image is missing", resourcePath: path)
            }
            return handle
        }
        let imageInfo = try ReeltoneImageValidator.validate(imageHandles)
        return ReeltoneLoadedSkin(
            manifest: manifest,
            rootURL: rootURL,
            resources: resources,
            imageInfo: imageInfo,
            cleanupURL: cleanupURL
        )
    }
}
