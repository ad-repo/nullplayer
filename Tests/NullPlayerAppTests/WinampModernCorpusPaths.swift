import Foundation

/// The `.wal` archives a corpus harness variable names: one archive, one directory, or a
/// `:`-separated list of either. The corpus is tier directories (`gold:silver`, B167), so one
/// sweep walks several in a single invocation. Unsorted; each harness keeps its own order.
enum WinampModernCorpusPaths {
    static func archives(in list: String) -> [URL] {
        list.split(separator: ":").flatMap { part -> [URL] in
            let url = URL(fileURLWithPath: String(part))
            guard isDirectory(url.path) else { return [url] }
            return ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "wal" }
        }
    }

    /// A list or a directory is a sweep; a single archive is not.
    static func isSweep(_ list: String) -> Bool {
        list.contains(":") || isDirectory(list)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
