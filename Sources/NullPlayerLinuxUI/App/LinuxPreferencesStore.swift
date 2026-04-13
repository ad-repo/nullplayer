#if os(Linux)
import Foundation
import Dispatch
import NullPlayerCore

final class LinuxPreferencesStore: BrowserPreferenceStoring {
    static let shared = LinuxPreferencesStore()

    private let queue = DispatchQueue(label: "NullPlayer.LinuxPreferencesStore")
    private let fileURL: URL
    private var values: [String: String] = [:]

    private init() {
        self.fileURL = LinuxPathResolver.configDirectory()
            .appendingPathComponent("preferences.json")
        self.values = Self.loadValues(from: fileURL)
    }

    func data(forKey key: String) -> Data? {
        queue.sync {
            guard let base64 = values[key] else { return nil }
            return Data(base64Encoded: base64)
        }
    }

    func string(forKey key: String) -> String? {
        queue.sync { values[key] }
    }

    func set(_ value: Data?, forKey key: String) {
        queue.sync {
            values[key] = value?.base64EncodedString()
            persist()
        }
    }

    func set(_ value: String?, forKey key: String) {
        queue.sync {
            values[key] = value
            persist()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: LinuxPathResolver.configDirectory(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(values)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            fputs("LinuxPreferencesStore: failed to persist: \(error)\n", stderr)
        }
    }

    private static func loadValues(from fileURL: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

enum LinuxPathResolver {
    static func configDirectory() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let xdg = env["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("nullplayer", isDirectory: true)
        }
        let home = env["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("nullplayer", isDirectory: true)
    }
}
#endif
