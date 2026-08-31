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

    /// Resolves an installed skin *by mount name* into a provider, so an overlay skin can reach the
    /// base skin it is written against. Nil means "no such skin is installed".
    var siblingMountResolver: ((String) throws -> WalResourceProvider?)?
    /// Names the resolver has already answered `nil` for. Memoized so a hostile skin cannot force a
    /// directory scan per reference.
    private var failedSiblingNames: Set<String> = []
    private var lazySiblingMountCount = 0
    /// Security-model bound: a skin may pull in at most this many sibling archives per load.
    private static let maximumLazySiblingMounts = 4

    init() {
        variables["WINAMPPATH"] = "/"
        variables["DEFAULTSKINPATH"] = "/Skins/Default"
        // Winamp's skins *collection* root. Skins write `@SKINSPATH@\<Skin Name>\xml\player.xml`,
        // both to reach their own files and — for overlay skins such as the Big Bento Modern Light
        // editions — to reach the base skin they are written against. Every loaded skin is mounted
        // at `/Skins/<name>`, so `/Skins` is exactly that collection root.
        variables["SKINSPATH"] = "/Skins"
    }

    convenience init(skinName: String, skin: WalResourceProvider) throws {
        self.init()
        let safeName = try Self.safeMountComponent(skinName)
        let skinRoot = "/Skins/\(safeName)"
        try mount(skin, at: skinRoot)
        // Trailing separator: what Winamp's own `@SKINPATH@` carries, and what ClassicPro's
        // `getParam() + "ClassicPro.xml"` concatenations depend on. See `skinRoot`.
        setVariable("SKINPATH", to: skinRoot, trailingSeparator: true)
        setVariable("COLORTHEMESPATH", to: skinRoot, trailingSeparator: true)
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

    /// `trailingSeparator` survives the canonicalization, which otherwise drops it — `canonicalize`
    /// rebuilds the path by joining components, so a trailing `/` handed in here disappears silently.
    /// Only `@SKINPATH@`/`@COLORTHEMESPATH@` ask for one, and they need it because scripts
    /// concatenate a filename straight onto them (see `skinRoot`).
    func setVariable(_ name: String, to logicalPath: String, trailingSeparator: Bool = false) {
        let key = name.trimmingCharacters(in: CharacterSet(charactersIn: "@")).uppercased()
        guard let path = try? Self.canonicalize(logicalPath, relativeToDirectory: "/") else { return }
        variables[key] = trailingSeparator && !path.hasSuffix("/") ? path + "/" : path
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
        let canonical = try Self.canonicalize(substituted, relativeToDirectory: Self.directory(of: sourcePath),
                                              location: location)
        // A path written in skin markup that starts at the root — `<include
        // file="/standardframe/standardframe.xml"/>` — means the *skin's* root, because in Winamp the
        // skin is the filesystem it names. Here the skin is one mount inside a larger VFS, so `/`
        // alone lands beside the mount rather than inside it (B45: Shield_Amp's whole playlist layout
        // came in through one such include, so its `Pledit` container was built empty and the PL
        // button opened nothing). Tried second, and only when the literal reading finds nothing, so
        // every genuinely VFS-absolute path — this loader's own entry paths, and anything produced by
        // `@SKINPATH@`/`@SKINSPATH@` substitution — keeps resolving exactly as before.
        if Self.startsAtRoot(rawPath), substituted == rawPath, let skinRoot,
           resolvedExisting(canonical) == nil {
            // The leading separator comes off with it: `canonicalize` reads one as "already absolute"
            // and ignores the base entirely.
            let underSkin = try Self.canonicalize(String(substituted.drop(while: { $0 == "/" || $0 == "\\" })),
                                                  relativeToDirectory: skinRoot, location: location)
            if let existing = resolvedExisting(underSkin) {
                return WalResolvedResource(logicalPath: existing)
            }
        }
        guard mustExist else { return WalResolvedResource(logicalPath: canonical) }
        return WalResolvedResource(logicalPath: try canonicalExistingPath(canonical, location: location))
    }

    /// Where the skin archive is mounted, **without** a trailing separator — the form every internal
    /// consumer wants, and the form this was before B86.
    ///
    /// The stored variable keeps its trailing `/` because that is what a *script* has to see. Winamp
    /// hands `@SKINPATH@` out with one, and ClassicPro relies on it: five of its scripts build the
    /// path to the skin's own `ClassicPro.xml` by bare concatenation —
    /// `getParam() + "ClassicPro.xml"` in `player.m`, `shade.m`, `drawer.m`, `about.m` and
    /// `read-classicpro.m` — with no separator of their own. Without the trailing `/` that produced
    /// `/Skins/cPro_T2T-by-MACclassicpro.xml`, which resolves to nothing, so every one of those
    /// `myDoc.exists()` guards took its false branch and the whole feature behind it silently
    /// vanished: the custom beat-vis list, the songticker's antialias setting, the About box's skin
    /// info. No diagnostic fires for this — the scripts are *written* to branch on a missing file.
    ///
    /// Paths that already carry their own separator are unaffected: the doubled slash in
    /// `@COLORTHEMESPATH@\..\..\Plugins\…` is dropped by `canonicalize`, which splits on `/`
    /// omitting empty subsequences, so that include resolves to exactly what it did before.
    var skinRoot: String? {
        variables["SKINPATH"].map { root in
            root.count > 1 && root.hasSuffix("/") ? String(root.dropLast()) : root
        }
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
        // A wildcard include into another installed skin has to see that skin's entries, so the
        // sibling is mounted before `allLogicalPaths()` is filtered.
        if mountedResource(for: directory) == nil {
            try mountSiblingIfNeeded(for: directory, location: location)
        }
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

    /// Mounts an installed sibling skin the moment a path reaches into `/Skins/<Other Skin>/…` that
    /// no mount owns, and throws `.missingRequiredMount` naming the skin when none is installed.
    ///
    /// Called **only** when no mount already owns the path, so the loaded skin's own
    /// `@SKINSPATH@\<its own name>\…` self-references resolve through the mount it already has and
    /// never reach the resolver. Returns whether a new mount was added.
    @discardableResult
    private func mountSiblingIfNeeded(for canonical: String, location: WalSourceLocation?) throws -> Bool {
        guard let siblingMountResolver else { return false }
        let components = canonical.split(separator: "/").map(String.init)
        guard components.count >= 2, Self.fold(components[0]) == Self.fold("Skins"),
              let name = try? Self.safeMountComponent(components[1]) else { return false }
        let root = "/Skins/\(name)"
        let foldedRoot = Self.fold(root)
        // A mount can own the root itself without owning any path *under* it (a wildcard include
        // naming the mount directory), and re-mounting it would be a case collision.
        guard !mounts.contains(where: { $0.foldedRoot == foldedRoot }) else { return false }
        guard !failedSiblingNames.contains(foldedRoot) else { throw Self.missingMount(name, location) }
        guard lazySiblingMountCount < Self.maximumLazySiblingMounts else {
            throw WalFailure(WalDiagnostic(
                .entryLimitExceeded,
                "A skin may reference at most \(Self.maximumLazySiblingMounts) other installed skins.",
                location: location))
        }
        guard let provider = try siblingMountResolver(name) else {
            failedSiblingNames.insert(foldedRoot)
            throw Self.missingMount(name, location)
        }
        try mount(provider, at: root)
        lazySiblingMountCount += 1
        return true
    }

    private static func missingMount(_ name: String, _ location: WalSourceLocation?) -> WalFailure {
        WalFailure(WalDiagnostic(.missingRequiredMount,
                                 "This skin requires the skin '\(name)' to be installed.",
                                 location: location))
    }

    private func canonicalExistingPath(_ logicalPath: String, location: WalSourceLocation?) throws -> String {
        let canonical = try Self.canonicalize(logicalPath, relativeToDirectory: "/", location: location)
        if mountedResource(for: canonical) == nil {
            try mountSiblingIfNeeded(for: canonical, location: location)
        }
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

    /// The canonical spelling of `path` if some mount actually holds it, else nil.
    private func resolvedExisting(_ path: String) -> String? {
        try? canonicalExistingPath(path, location: nil)
    }

    /// Whether the path as written begins at the filesystem root, in either slash.
    private static func startsAtRoot(_ value: String) -> Bool {
        value.hasPrefix("/") || value.hasPrefix("\\")
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
