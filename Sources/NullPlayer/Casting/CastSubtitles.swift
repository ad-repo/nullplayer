import Foundation
import FlyingFox

/// Sidecar subtitles for a Chromecast video cast (M58). The Default Media Receiver takes WebVTT or
/// TTML text tracks, so an `.srt` is converted to WebVTT in a temp file before it is served.
enum CastSubtitles {
    /// In order of preference: a `.vtt` or `.ttml` goes out as is, an `.srt` needs converting.
    private static let sidecarExtensions = ["vtt", "ttml", "srt"]
    /// What `castableSidecar` hands the server, and so the only files a receiver fetches with CORS.
    private static let servedExtensions: Set<String> = ["vtt", "ttml"]

    /// The sidecar beside `video` as a file the receiver can read. Nil when there is none or it
    /// can't be read.
    static func castableSidecar(for video: URL) -> URL? {
        guard let sidecar = sidecar(for: video) else { return nil }
        guard sidecar.pathExtension.lowercased() == "srt" else { return sidecar }
        return convertedSRT(sidecar)
    }

    /// `<name>.<ext>` before a language-tagged `<name>.<tag>.<ext>` (`film.en.srt`), then by
    /// `sidecarExtensions`. A tag is one dot-free word, and not one that is another file's name:
    /// `film.2.srt` belongs to `film.2.mkv`, not `film.mkv`.
    static func sidecar(for video: URL) -> URL? {
        let directory = video.deletingLastPathComponent()
        let name = video.deletingPathExtension().lastPathComponent
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let otherStems = Set(siblings
            .filter { !sidecarExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { ($0 as NSString).deletingPathExtension })

        let ranked = siblings.compactMap { file -> (tagged: Int, ext: Int, file: String)? in
            guard let ext = sidecarExtensions.firstIndex(of: (file as NSString).pathExtension.lowercased()) else {
                return nil
            }
            let stem = (file as NSString).deletingPathExtension
            if stem == name { return (0, ext, file) }
            guard stem.hasPrefix(name + "."), !otherStems.contains(stem) else { return nil }
            let tag = stem.dropFirst(name.count + 1)
            guard !tag.isEmpty, !tag.contains(".") else { return nil }
            return (1, ext, file)
        }
        return ranked.min { $0 < $1 }.map { directory.appendingPathComponent($0.file) }
    }

    /// A Chromecast fetches a text track with CORS, sending `Origin`, and drops a response without
    /// `Access-Control-Allow-Origin`. Only served text tracks get it; every other file is unchanged.
    static func allowingCrossOrigin(_ response: HTTPResponse, for request: HTTPRequest) -> HTTPResponse {
        guard request.headers[HTTPHeader("Origin")] != nil,
              servedExtensions.contains((request.path as NSString).pathExtension.lowercased()) else {
            return response
        }
        NSLog("LocalMediaServer: allowing cross-origin GET %@", request.path)
        var response = response
        response.headers[HTTPHeader("Access-Control-Allow-Origin")] = "*"
        return response
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
