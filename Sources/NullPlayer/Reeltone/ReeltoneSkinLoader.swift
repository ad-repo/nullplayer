import Foundation

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
        for source in manifest.fonts?.allSources ?? [] {
            if let path = source.file, let postScriptName = source.postScriptName,
               let handle = resources[path] {
                try ReeltoneFontValidator.validate(handle, expectedPostScriptName: postScriptName)
            }
        }
        return ReeltoneLoadedSkin(
            manifest: manifest,
            rootURL: rootURL,
            resources: resources,
            imageInfo: imageInfo,
            diagnostics: compatibilityDiagnostics(for: manifest),
            cleanupURL: cleanupURL
        )
    }

    private func compatibilityDiagnostics(for manifest: ReeltoneManifest) -> [ReeltoneDiagnostic] {
        var diagnostics: [ReeltoneDiagnostic] = []
        if let sprites = manifest.sprites {
            let values: [(String, ReeltoneSprite?)] = [
                ("reelRim", sprites.reelRim), ("reelSpokes", sprites.reelSpokes),
                ("background", sprites.background), ("keyNormal", sprites.keyNormal),
                ("keyPressed", sprites.keyPressed)
            ]
            for (name, sprite) in values where sprite != nil {
                diagnostics.append(ReeltoneDiagnostic(
                    severity: .warning,
                    code: .unsupportedConstruct,
                    message: "Sprite '\(name)' is validated but is not rendered by NullPlayer's \(manifest.formatVersion == 1 ? "Original-content" : "shaped-surface") adapter",
                    codingPath: ["sprites", name],
                    resourcePath: sprite?.file,
                    skinID: manifest.id
                ))
            }
        }
        if manifest.fonts?.bodyBold != nil {
            diagnostics.append(ReeltoneDiagnostic(
                severity: .warning,
                code: .unsupportedConstruct,
                message: "bodyBold is validated but is not independently mapped; body is used for hosted content",
                codingPath: ["fonts", "bodyBold"],
                resourcePath: manifest.fonts?.bodyBold?.file,
                skinID: manifest.id
            ))
        }
        let surfaces: [(String, [ReeltoneRegion])] = [("main", manifest.regions)] + (manifest.window?.panels.map { ("panel:\($0.key)", $0.value.regions) } ?? [])
        for (surfaceID, regions) in surfaces {
            for (index, region) in regions.enumerated()
            where region.rowHeight != nil && region.component != .trackList && region.component != .library {
                diagnostics.append(ReeltoneDiagnostic(
                    severity: .warning,
                    code: .unsupportedConstruct,
                    message: "rowHeight applies only to trackList and library regions",
                    codingPath: [surfaceID == "main" ? "regions" : "window.panels", String(index), "rowHeight"],
                    skinID: manifest.id,
                    surfaceID: surfaceID,
                    regionIndex: index,
                    component: region.component.rawValue
                ))
            }
        }
        return diagnostics
    }
}
