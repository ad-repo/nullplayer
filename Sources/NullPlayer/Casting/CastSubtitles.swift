import Foundation

/// Sidecar subtitles for a Chromecast video cast (M58). The Default Media Receiver takes WebVTT or
/// TTML text tracks, so an `.srt` is converted to WebVTT in a temp file before it is served.
enum CastSubtitles {
    /// In order of preference: a `.vtt` or `.ttml` goes out as is, an `.srt` needs converting.
    private static let sidecarExtensions = ["vtt", "ttml", "srt"]

    /// The sidecar beside `video` as a file the receiver can read: `<name>.<ext>` first, then a
    /// language-tagged `<name>.<tag>.<ext>` (`film.en.srt`). Nil when there is none or it can't be read.
    static func castableSidecar(for video: URL) -> URL? {
        guard let sidecar = sidecar(for: video) else { return nil }
        guard sidecar.pathExtension.lowercased() == "srt" else { return sidecar }
        return convertedSRT(sidecar)
    }

    static func sidecar(for video: URL) -> URL? {
        let directory = video.deletingLastPathComponent()
        let name = video.deletingPathExtension().lastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for ext in sidecarExtensions {
            let matches = siblings.filter {
                ($0 as NSString).pathExtension.lowercased() == ext && $0.hasPrefix(name + ".")
            }
            // The exact `<name>.<ext>` sorts first: it is the shortest match
            if let match = matches.min(by: { ($0.count, $0) < ($1.count, $1) }) {
                return directory.appendingPathComponent(match)
            }
        }
        return nil
    }

    /// The MIME type a receiver expects for a served text track, by extension.
    static func contentType(for track: URL) -> String {
        track.pathExtension.lowercased() == "ttml" ? "application/ttml+xml" : "text/vtt"
    }

    // ponytail: a converted file is left in the temp directory for the OS to clear; one per cast
    private static func convertedSRT(_ srt: URL) -> URL? {
        guard let data = try? Data(contentsOf: srt),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            NSLog("CastSubtitles: could not read %@", srt.lastPathComponent)
            return nil
        }
        let vtt = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NullPlayerCastSubtitles-\(UUID().uuidString).vtt")
        do {
            try webVTT(fromSRT: text).write(to: vtt, atomically: true, encoding: .utf8)
        } catch {
            NSLog("CastSubtitles: could not write %@: %@", vtt.lastPathComponent, error.localizedDescription)
            return nil
        }
        return vtt
    }

    /// SRT and WebVTT cues differ only in the header and the timestamp's decimal comma.
    static func webVTT(fromSRT srt: String) -> String {
        let lines = srt
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.contains("-->") ? $0.replacingOccurrences(of: ",", with: ".") : $0 }
        return "WEBVTT\n\n" + lines.joined(separator: "\n")
    }
}
