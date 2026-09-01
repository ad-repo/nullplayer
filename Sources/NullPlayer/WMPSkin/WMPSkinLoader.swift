import Foundation

struct WMPViewRegistration {
    let id: String
    let node: WMPNode
}

enum WMPResourceStatus: String, Codable {
    case available
    case missing
    case unsupported
}

struct WMPResourceRegistration: Hashable, Codable {
    let attributeName: String
    let authoredPath: String
    let resolvedPath: String?
    let declaringPath: String
    let status: WMPResourceStatus
}

struct WMPScriptRegistration: Hashable, Codable {
    let authoredPath: String
    let resolvedPath: String?
    let declaringPath: String
    let status: WMPResourceStatus
}

final class WMPLoadedSkin {
    let archive: WMPArchive
    let definitionPath: String
    let definitionSource: String
    let textEncoding: WMPTextEncoding
    let document: WMPXMLDocument
    let graph: WMPObjectGraph
    let views: [WMPViewRegistration]
    let resources: [WMPResourceRegistration]
    let scripts: [WMPScriptRegistration]
    let scriptSources: [String: String]
    let diagnostics: [WMPDiagnostic]
    let compatibilityReport: WMPCompatibilityReport
    let deterministicGraphDump: String
    let wasLoadedOnMainThread: Bool

    init(archive: WMPArchive, definitionPath: String, definitionSource: String,
         textEncoding: WMPTextEncoding,
         document: WMPXMLDocument, graph: WMPObjectGraph, views: [WMPViewRegistration],
         resources: [WMPResourceRegistration], scripts: [WMPScriptRegistration],
         diagnostics: [WMPDiagnostic], scriptSources: [String: String],
         wasLoadedOnMainThread: Bool) {
        self.archive = archive
        self.definitionPath = definitionPath
        self.definitionSource = definitionSource
        self.textEncoding = textEncoding
        self.document = document
        self.graph = graph
        self.views = views
        self.resources = resources
        self.scripts = scripts
        self.scriptSources = scriptSources
        self.diagnostics = diagnostics
        compatibilityReport = WMPCompatibilityReport(graph: graph, resources: resources,
            scripts: scripts, diagnostics: diagnostics, scriptSources: scriptSources)
        deterministicGraphDump = graph.dump()
        self.wasLoadedOnMainThread = wasLoadedOnMainThread
    }
}

struct WMPSkinLoader {
    let archiveLimits: WMPArchiveLimits
    let xmlLimits: WMPXMLLimits

    init(archiveLimits: WMPArchiveLimits = .production, xmlLimits: WMPXMLLimits = .production) {
        self.archiveLimits = archiveLimits
        self.xmlLimits = xmlLimits
    }

    /// The only production entry point. Even a MainActor caller immediately leaves the UI executor
    /// before touching archive metadata or bytes.
    func load(from url: URL) async throws -> WMPLoadedSkin {
        try await Task.detached(priority: .userInitiated) {
            try loadOffMain(from: url)
        }.value
    }

    private func loadOffMain(from url: URL) throws -> WMPLoadedSkin {
        let wasLoadedOnMainThread = Thread.isMainThread
        let archive = try WMPArchive(url: url, limits: archiveLimits)
        let path = archive.skinDefinitionPath
        let decoded = try WMPTextDecoder.decode(archive.data(for: path), path: path)
        let document = try WMPXMLParser(limits: xmlLimits).parse(decoded.string, path: path)
        let graph = WMPObjectGraph(document: document)
        var diagnostics = graph.diagnostics

        let views = graph.allNodes.compactMap { node -> WMPViewRegistration? in
            guard node.kind == .view else { return nil }
            return WMPViewRegistration(id: node.xmlID ?? "view-\(node.stableID)", node: node)
        }

        var resources: [WMPResourceRegistration] = []
        var scripts: [WMPScriptRegistration] = []
        var scriptSources: [String: String] = [:]
        var registeredScriptKeys = Set<String>()
        for node in graph.allNodes {
            for attribute in node.attributes {
                if attribute.name.caseInsensitiveCompare("scriptFile") == .orderedSame {
                    for item in attribute.rawValue.split(separator: ";", omittingEmptySubsequences: true) {
                        let authored = String(item).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !authored.isEmpty else { continue }
                        if isUnsupported(authored) {
                            if registeredScriptKeys.insert("unsupported:\(WMPPath.fold(authored))").inserted {
                                scripts.append(WMPScriptRegistration(authoredPath: authored, resolvedPath: nil,
                                    declaringPath: path, status: .unsupported))
                                diagnostics.append(WMPDiagnostic(.unsupportedResource,
                                    "Windows resource '\(authored)' cannot be loaded on macOS.",
                                    severity: .warning, location: node.location))
                            }
                        } else {
                            let resolved = try archive.resolve(authored, relativeTo: path)
                            guard let resolved else {
                                throw WMPFailure(WMPDiagnostic(.resourceMissing,
                                    "Script resource '\(authored)' does not exist.", location: node.location))
                            }
                            guard let entry = archive.entryInfo(for: resolved) else {
                                throw WMPFailure(WMPDiagnostic(.resourceMissing,
                                    "Script resource '\(authored)' disappeared from the provider.",
                                    location: node.location))
                            }
                            guard entry.uncompressedSize <= WMPPhase0Limits.scriptBytes else {
                                throw WMPFailure(WMPDiagnostic(.oversizedScript,
                                    "Script resource '\(authored)' exceeds the 4 MiB script limit.", location: node.location))
                            }
                            if registeredScriptKeys.insert("available:\(WMPPath.fold(resolved))").inserted {
                                scripts.append(WMPScriptRegistration(authoredPath: authored, resolvedPath: resolved,
                                    declaringPath: path, status: .available))
                                scriptSources[resolved] = try WMPTextDecoder.decode(
                                    archive.data(for: resolved), path: resolved).string
                            }
                        }
                    }
                }
                guard WMPAttributeParser.isResourceAttribute(attribute.name) else { continue }
                let authored = attribute.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if authored.isEmpty {
                    resources.append(WMPResourceRegistration(attributeName: attribute.name,
                        authoredPath: authored, resolvedPath: nil, declaringPath: path, status: .missing))
                    diagnostics.append(WMPDiagnostic(.resourceMissing,
                        "Optional image resource is empty.", severity: .warning, location: node.location))
                } else if isUnsupported(authored) {
                    resources.append(WMPResourceRegistration(attributeName: attribute.name,
                        authoredPath: authored, resolvedPath: nil, declaringPath: path, status: .unsupported))
                    diagnostics.append(WMPDiagnostic(.unsupportedResource,
                        "Resource '\(authored)' uses an unsupported external scheme.",
                        severity: .warning, location: node.location))
                } else if let resolved = try archive.resolve(authored, relativeTo: path) {
                    resources.append(WMPResourceRegistration(attributeName: attribute.name,
                        authoredPath: authored, resolvedPath: resolved, declaringPath: path, status: .available))
                } else {
                    resources.append(WMPResourceRegistration(attributeName: attribute.name,
                        authoredPath: authored, resolvedPath: nil, declaringPath: path, status: .missing))
                    diagnostics.append(WMPDiagnostic(.resourceMissing,
                        "Optional image resource '\(authored)' does not exist.",
                        severity: .warning, location: node.location))
                }
            }
        }

        return WMPLoadedSkin(archive: archive, definitionPath: path, definitionSource: decoded.string,
            textEncoding: decoded.encoding,
            document: document, graph: graph, views: views, resources: resources, scripts: scripts,
            diagnostics: diagnostics, scriptSources: scriptSources,
            wasLoadedOnMainThread: wasLoadedOnMainThread)
    }

    private func isUnsupported(_ path: String) -> Bool {
        if case .unsupported = WMPAttributeParser.parse(name: "image", value: path) { return true }
        return false
    }
}
