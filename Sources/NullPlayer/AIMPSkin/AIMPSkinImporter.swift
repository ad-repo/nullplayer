import Foundation
import ZIPFoundation

struct AIMPInstalledSkin: Hashable {
    /// The file name without its extension.
    let name: String
    let url: URL
}

enum AIMPSkinImportError: LocalizedError {
    case selectionMissing(String)
    case notInstalled(String)
    case noSkinInZip(String)

    var errorDescription: String? {
        switch self {
        case let .selectionMissing(name):
            return "The selected AIMP skin “\(name)” is no longer installed. Load it again or choose another skin."
        case let .notInstalled(name):
            return "No AIMP skin named “\(name)” is installed."
        case let .noSkinInZip(name):
            return "“\(name)” holds no .acs5, .acs4, .acs3 or .acs skin."
        }
    }
}

/// The installed-skins folder and the selection preference. A skin is one `.acs5`, `.acs4`, `.acs3`
/// or `.acs` file, validated through `AIMPSkinLoader` off the main thread as it is committed
/// (`SkinInstallFolder`). A name is one skin, whatever its extension: of two files with one name,
/// the first of `fileExtensions` is the skin, removing the skin removes both, and installing one
/// under another extension replaces the skin of that name. The AIMP catalog ships each skin in a
/// `.zip`; importing one installs every skin inside it.
struct AIMPSkinImporter {
    /// A skin file's extensions, lowercased, the one a name prefers first.
    static let fileExtensions = ["acs5", "acs4", "acs3", "acs"]

    let folder: SkinInstallFolder
    let selection: SkinSelection
    var directoryURL: URL { folder.url }
    private var fileManager: FileManager { folder.fileManager }

    init(directoryURL: URL? = nil, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        selection = SkinSelection(key: "aimpSkinName", defaults: defaults)
        folder = SkinInstallFolder("AIMPSkins", at: directoryURL, fileManager: fileManager)
    }

    func installedSkins() -> [AIMPInstalledSkin] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        let files = names.filter { !$0.hasPrefix(".") && Self.rank($0) != nil }
        var skins: [AIMPInstalledSkin] = []
        var taken: [String: Int] = [:]
        for file in files {
            let skin = AIMPInstalledSkin(name: (file as NSString).deletingPathExtension, url: directoryURL.appendingPathComponent(file))
            guard let index = taken[skin.name] else {
                taken[skin.name] = skins.count
                skins.append(skin)
                continue
            }
            if Self.rank(file) ?? 0 < Self.rank(skins[index].url.lastPathComponent) ?? 0 { skins[index] = skin }
        }
        return skins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The installed skin of that name; a name that is not a plain visible file name never resolves
    /// outside the directory.
    func skin(named name: String) -> AIMPInstalledSkin? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return installedSkins().first { $0.name == name }
    }

    /// The selected skin's file, nil when nothing is selected; throws when the selection is gone.
    func selectedSkinURL() throws -> URL? {
        guard let name = selection.name, !name.isEmpty else { return nil }
        guard let skin = skin(named: name) else { throw AIMPSkinImportError.selectionMissing(name) }
        return skin.url
    }

    /// Deletes an installed skin, every file of its name, off the main thread; removing the selected
    /// one clears the selection.
    func removeSkin(named name: String) async throws {
        guard let skin = skin(named: name) else { throw AIMPSkinImportError.notInstalled(name) }
        for file in Self.files(named: skin.name, in: folder) { try await folder.remove(file) }
        selection.forget(name)
    }

    /// Installs an `.acs5`/`.acs4`, or every one inside a `.zip`, replacing any of the same name, and
    /// selects the first.
    @discardableResult
    func importSkins(from source: URL) async throws -> [AIMPInstalledSkin] {
        let installed = try await Task.detached(priority: .userInitiated) { [folder] in
            guard source.pathExtension.lowercased() == "zip" else { return [try await Self.install(source, into: folder)] }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("aimp-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            var skins: [AIMPInstalledSkin] = []
            for file in try Self.unzipSkins(source, into: staging) {
                skins.append(try await Self.install(file, into: folder))
            }
            guard !skins.isEmpty else { throw AIMPSkinImportError.noSkinInZip(source.lastPathComponent) }
            return skins
        }.value
        if let first = installed.first { selection.select(first.name) }
        return installed
    }

    private static func install(_ file: URL, into folder: SkinInstallFolder) async throws -> AIMPInstalledSkin {
        let name = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension.lowercased()
        let destination = folder.url.appendingPathComponent("\(name).\(ext)")
        try await folder.commit(file, to: destination, suffix: ".\(ext)") { _ = try AIMPSkinLoader.load(contentsOf: $0) }
        let installed = AIMPInstalledSkin(name: name, url: destination)
        try removeOtherFiles(of: installed, in: folder)
        return installed
    }

    /// After `installed` is committed: the other files of its name go, so the name stays one skin.
    private static func removeOtherFiles(of installed: AIMPInstalledSkin, in folder: SkinInstallFolder) throws {
        for file in files(named: installed.name, in: folder) where file.lastPathComponent != installed.url.lastPathComponent {
            try folder.fileManager.removeItem(at: file)
        }
    }

    /// The files in `folder` that are the skin `name`, under any of the extensions.
    private static func files(named name: String, in folder: SkinInstallFolder) -> [URL] {
        let names = (try? folder.fileManager.contentsOfDirectory(atPath: folder.url.path)) ?? []
        return names.filter { rank($0) != nil && ($0 as NSString).deletingPathExtension == name }
            .map { folder.url.appendingPathComponent($0) }
    }

    /// Where a file's extension stands in `fileExtensions`; nil for a file that is no skin.
    private static func rank(_ file: String) -> Int? {
        fileExtensions.firstIndex(of: (file as NSString).pathExtension.lowercased())
    }

    /// The skins of a zip, flattened into `directory` by file name. Every bound is checked from the
    /// central directory before a byte is inflated (`AIMPSkinZipLimits`), and each skin is held to
    /// its declared size and CRC as it is written. A name is one skin, whatever its extension or
    /// folder in the zip: the first entry of a name is taken, so no skin is written, or installed,
    /// twice. Off the main thread; a zip that fails a check part-way can leave files in `directory`,
    /// which the caller discards.
    static func unzipSkins(_ zip: URL, into directory: URL, limits: AIMPSkinZipLimits = .production) throws -> [URL] {
        let archive = try Archive(url: zip, accessMode: .read)
        var admitted: [(entry: Entry, target: URL)] = []
        var names = Set<String>()
        var count = 0
        var total: UInt64 = 0
        for entry in archive {
            count += 1
            guard count <= limits.entries else {
                throw AIMPSkinFinding(.zipRejected, "More than \(limits.entries) entries.")
            }
            let name = (entry.path as NSString).lastPathComponent
            let stem = (name as NSString).deletingPathExtension.lowercased()
            guard entry.type == .file, !name.hasPrefix("."), fileExtensions.contains((name as NSString).pathExtension.lowercased()),
                  names.insert(stem).inserted else { continue }
            let size = entry.uncompressedSize
            guard size <= limits.entryBytes else {
                throw AIMPSkinFinding(.fileTooLarge, "'\(entry.path)' expands to \(size) bytes, more than \(limits.entryBytes).")
            }
            guard size <= limits.totalBytes - total else {
                throw AIMPSkinFinding(.zipRejected, "The zip's skins expand past \(limits.totalBytes) bytes.")
            }
            total += size
            // Skins are compressed already: one that squashes far is a bomb, not a skin.
            let ratio = Double(size) / Double(max(entry.compressedSize, 1))
            if size > limits.ratioFloorBytes, ratio > Double(limits.ratio) {
                throw AIMPSkinFinding(.zipRejected, "'\(entry.path)' expands \(Int(ratio)):1, past \(limits.ratio):1.")
            }
            admitted.append((entry, directory.appendingPathComponent(name)))
        }

        for (entry, target) in admitted {
            FileManager.default.createFile(atPath: target.path, contents: nil)
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            var written: UInt64 = 0
            let checksum = try archive.extract(entry) { chunk in
                written += UInt64(chunk.count)
                guard written <= entry.uncompressedSize else {
                    throw AIMPSkinFinding(.fileTooLarge, "'\(entry.path)' inflates past its declared size.")
                }
                try handle.write(contentsOf: chunk)
            }
            guard checksum == entry.checksum, written == entry.uncompressedSize else {
                throw AIMPSkinFinding(.zipRejected, "'\(entry.path)' fails its CRC or size check.")
            }
        }
        return admitted.map(\.target)
    }
}
