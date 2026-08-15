import Foundation

final class WalMemoryResourceProvider: WalResourceProvider {
    private let resources: [String: Data]
    private let canonical: [String: String]

    init(resources: [String: Data]) throws {
        var stored: [String: Data] = [:]
        var names: [String: String] = [:]
        for (path, data) in resources {
            let normalized = path.replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !normalized.isEmpty, !normalized.split(separator: "/").contains("..") else {
                throw WalFailure(WalDiagnostic(.unsafePath, "Unsafe in-memory resource path '\(path)'."))
            }
            let folded = Self.fold(normalized)
            guard names[folded] == nil else {
                throw WalFailure(WalDiagnostic(.caseCollision, "In-memory resources '\(names[folded]!)' and '\(normalized)' collide."))
            }
            names[folded] = normalized
            stored[folded] = data
        }
        self.resources = stored
        self.canonical = names
    }

    var resourcePaths: [String] { canonical.values.sorted() }

    func canonicalPath(for path: String) -> String? {
        canonical[Self.fold(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))]
    }

    func data(for path: String) throws -> Data {
        guard let data = resources[Self.fold(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))] else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Resource '\(path)' does not exist."))
        }
        return data
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

struct WalResolvedResource: Hashable {
    let logicalPath: String
}

/// A fixed-mount, read-only filesystem. It canonicalizes paths without ever consulting the host FS.
final class WalVirtualFileSystem {
    private struct Mount {
        let root: String
        let foldedRoot: String
        let provider: WalResourceProvider
    }

    private var mounts: [Mount] = []
    private var variables: [String: String] = [:]

    init() {
        variables["WINAMPPATH"] = "/"
        variables["DEFAULTSKINPATH"] = "/Skins/Default"
    }

    convenience init(skinName: String, skin: WalResourceProvider) throws {
        self.init()
        let safeName = try Self.safeMountComponent(skinName)
        let skinRoot = "/Skins/\(safeName)"
        try mount(skin, at: skinRoot)
        setVariable("SKINPATH", to: skinRoot)
        setVariable("COLORTHEMESPATH", to: skinRoot)
    }

    func mount(_ provider: WalResourceProvider, at logicalRoot: String) throws {
        let root = try Self.canonicalize(logicalRoot, relativeToDirectory: "/")
        guard root != "/" else {
            throw WalFailure(WalDiagnostic(.unsafePath, "The VFS root cannot be replaced by an external provider."))
        }
        let folded = Self.fold(root)
        guard !mounts.contains(where: { $0.foldedRoot == folded }) else {
            throw WalFailure(WalDiagnostic(.caseCollision, "A VFS provider is already mounted at '\(root)'."))
        }
        mounts.append(Mount(root: root, foldedRoot: folded, provider: provider))
        mounts.sort { $0.root.count > $1.root.count }
    }

    func setVariable(_ name: String, to logicalPath: String) {
        let key = name.trimmingCharacters(in: CharacterSet(charactersIn: "@")).uppercased()
        guard let path = try? Self.canonicalize(logicalPath, relativeToDirectory: "/") else { return }
        variables[key] = path
    }

    func resolve(
        _ rawPath: String,
        relativeTo sourcePath: String,
        location: WalSourceLocation? = nil,
        mustExist: Bool = true
    ) throws -> WalResolvedResource {
        let substituted = try substituteVariables(in: rawPath, location: location)
        guard !Self.looksLikeHostPath(substituted) else {
            throw WalFailure(WalDiagnostic(.resourceEscapesVFS, "Host path '\(rawPath)' is not allowed.", location: location))
        }
        let base = Self.directory(of: sourcePath)
        let canonical = try Self.canonicalize(substituted, relativeToDirectory: base, location: location)
        guard mustExist else { return WalResolvedResource(logicalPath: canonical) }
        return WalResolvedResource(logicalPath: try canonicalExistingPath(canonical, location: location))
    }

    func expand(
        _ rawPath: String,
        relativeTo sourcePath: String,
        location: WalSourceLocation? = nil
    ) throws -> [WalResolvedResource] {
        let normalizedRaw = rawPath.replacingOccurrences(of: "\\", with: "/")
        let last = normalizedRaw.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? normalizedRaw
        guard last.contains("*") else {
            return [try resolve(rawPath, relativeTo: sourcePath, location: location)]
        }
        guard !normalizedRaw.dropLast(last.count).contains("*") else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Only the final include path component may contain a wildcard: '\(rawPath)'.", location: location))
        }

        let directoryRaw = String(normalizedRaw.dropLast(last.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let directory = try resolve(directoryRaw.isEmpty ? "." : directoryRaw,
                                    relativeTo: sourcePath, location: location, mustExist: false).logicalPath
        let foldedDirectory = Self.fold(directory == "/" ? "/" : directory + "/")
        let matches = allLogicalPaths().filter { path in
            let foldedPath = Self.fold(path)
            guard foldedPath.hasPrefix(foldedDirectory) else { return false }
            let directoryComponentCount = directory.split(separator: "/").count
            let tail = path.split(separator: "/").dropFirst(directoryComponentCount).joined(separator: "/")
            return !tail.contains("/") && Self.wildcard(last, matches: tail)
        }
        guard !matches.isEmpty else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Include pattern '\(rawPath)' matched no resources.", location: location))
        }
        return matches.sorted().map(WalResolvedResource.init(logicalPath:))
    }

    func data(at logicalPath: String, location: WalSourceLocation? = nil) throws -> Data {
        let canonical = try canonicalExistingPath(logicalPath, location: location)
        guard let (mount, relative) = mountedResource(for: canonical) else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "No provider owns logical resource '\(canonical)'.", location: location))
        }
        do {
            return try mount.provider.data(for: relative)
        } catch let failure as WalFailure {
            throw failure
        } catch {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Failed to read logical resource '\(canonical)': \(error.localizedDescription)", location: location))
        }
    }

    func contains(_ logicalPath: String) -> Bool {
        (try? canonicalExistingPath(logicalPath, location: nil)) != nil
    }

    func allLogicalPaths() -> [String] {
        mounts.flatMap { mount in
            mount.provider.resourcePaths.map { mount.root + "/" + $0 }
        }.sorted()
    }

    private func canonicalExistingPath(_ logicalPath: String, location: WalSourceLocation?) throws -> String {
        let canonical = try Self.canonicalize(logicalPath, relativeToDirectory: "/", location: location)
        guard let (mount, relative) = mountedResource(for: canonical),
              let providerPath = mount.provider.canonicalPath(for: relative) else {
            throw WalFailure(WalDiagnostic(.resourceMissing, "Logical resource '\(canonical)' was not found in any mounted provider.", location: location))
        }
        return mount.root + "/" + providerPath
    }

    private func mountedResource(for canonical: String) -> (Mount, String)? {
        let folded = Self.fold(canonical)
        for mount in mounts {
            let prefix = mount.foldedRoot + "/"
            guard folded.hasPrefix(prefix) else { continue }
            let mountComponentCount = mount.root.split(separator: "/").count
            let relative = canonical.split(separator: "/").dropFirst(mountComponentCount).joined(separator: "/")
            return (mount, relative)
        }
        return nil
    }

    private func substituteVariables(in raw: String, location: WalSourceLocation?) throws -> String {
        var output = raw
        while let start = output.firstIndex(of: "@"),
              let end = output[output.index(after: start)...].firstIndex(of: "@") {
            let token = String(output[output.index(after: start)..<end])
            guard !token.isEmpty, token.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
                break
            }
            guard let replacement = variables[token.uppercased()] else {
                throw WalFailure(WalDiagnostic(.unresolvedPathVariable, "Unknown path variable '@\(token)@' in '\(raw)'.", location: location))
            }
            output.replaceSubrange(start...end, with: replacement)
        }
        return output
    }

    private static func safeMountComponent(_ value: String) throws -> String {
        guard !value.isEmpty, value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"), !value.contains(":") else {
            throw WalFailure(WalDiagnostic(.unsafePath, "Unsafe VFS mount name '\(value)'."))
        }
        return value
    }

    private static func looksLikeHostPath(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil || value.hasPrefix("~")
    }

    private static func directory(of path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard let slash = normalized.lastIndex(of: "/") else { return "/" }
        return slash == normalized.startIndex ? "/" : String(normalized[..<slash])
    }

    private static func canonicalize(
        _ raw: String,
        relativeToDirectory base: String,
        location: WalSourceLocation? = nil
    ) throws -> String {
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        let combined = normalized.hasPrefix("/") ? normalized : (base == "/" ? "/" + normalized : base + "/" + normalized)
        var components: [Substring] = []
        for component in combined.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else {
                    throw WalFailure(WalDiagnostic(.resourceEscapesVFS, "Path '\(raw)' escapes the logical VFS root.", location: location))
                }
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    private static func wildcard(_ pattern: String, matches value: String) -> Bool {
        let p = Array(fold(pattern))
        let v = Array(fold(value))
        var pi = 0, vi = 0, star: Int?, retry = 0
        while vi < v.count {
            if pi < p.count, p[pi] == v[vi] {
                pi += 1; vi += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; retry = vi; pi += 1
            } else if let star {
                retry += 1; vi = retry; pi = star + 1
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
