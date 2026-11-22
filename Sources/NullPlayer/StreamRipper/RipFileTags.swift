import Foundation
import ImageIO

/// Reads and writes a media file's own tags with ffprobe / ffmpeg (stream copy, no re-encode).
enum RipFileTags {
    /// The editable tags, as ffmpeg names them, in form order.
    static let keys: [(key: String, label: String)] = [
        ("title", "Title"), ("artist", "Artist"), ("album", "Album"), ("album_artist", "Album Artist"),
        ("genre", "Genre"), ("date", "Year"), ("track", "Track #"), ("comment", "Comment"),
    ]

    /// Ogg keeps its tags on the audio stream, not the container.
    private static func isOgg(_ file: URL) -> Bool { ["ogg", "oga", "opus"].contains(file.pathExtension.lowercased()) }

    static func read(_ file: URL) -> [String: String] {
        guard let ffprobe = StreamRipper.resolveTool("ffprobe") else { return [:] }
        let names = keys.map(\.key).joined(separator: ",")
        guard let output = try? RipProcess.run(ffprobe, ["-v", "error", "-select_streams", "a:0",
                                                         "-show_entries", "stream_tags=\(names):format_tags=\(names)",
                                                         "-of", "default=noprint_wrappers=1", file.path])
        else { return [:] }
        let out = String(decoding: output.stdout, as: UTF8.self)
        var tags: [String: String] = [:]
        for line in out.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            // "TAG:album=…"; a key can repeat (stream, then format): the last non-empty wins.
            let key = line[..<eq].lowercased().replacingOccurrences(of: "tag:", with: "")
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if keys.contains(where: { $0.key == key }), !value.isEmpty { tags[key] = value }
        }
        return tags
    }

    /// Rewrites the file with `tags` (an empty value clears that tag). With a sibling .cue, its
    /// PERFORMER lines follow the artist, since the splitter prefers them to the file's own.
    static func write(_ tags: [String: String], to file: URL) throws {
        guard let ffmpeg = StreamRipper.resolveTool("ffmpeg") else {
            throw NSError(domain: "RipFileTags", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg is not installed."])
        }
        let temp = file.deletingLastPathComponent()
            .appendingPathComponent(".nullplayer-tags-\(UUID().uuidString).\(file.pathExtension)")
        defer { try? FileManager.default.removeItem(at: temp) }
        let ogg = isOgg(file)
        let flag = ogg ? "-metadata:s:a:0" : "-metadata"
        var args = ["-nostdin", "-y", "-v", "error", "-i", file.path, "-c", "copy", "-map_metadata", "0", "-map", "0:a"]
        // ffmpeg reads an Ogg cover as a picture stream it cannot write back, so the cover is
        // re-embedded as the tag it came from. Elsewhere the cover stream copies across.
        if ogg {
            if let picture = oggPictureTag(from: file, ffmpeg: ffmpeg) { args += [flag, "METADATA_BLOCK_PICTURE=\(picture)"] }
        } else {
            args += ["-map", "0:v?"]
        }
        for (key, _) in keys { args += [flag, "\(key)=\(tags[key] ?? "")"] }
        // `.m4a` picks the ipod muxer, which refuses a cover stream; mp4 writes it.
        if ["m4a", "mp4", "m4b"].contains(file.pathExtension.lowercased()) { args += ["-f", "mp4"] }
        let result = try RipProcess.run(ffmpeg, args + [temp.path])
        guard result.status == 0 else {
            throw NSError(domain: "RipFileTags", code: 2, userInfo: [NSLocalizedDescriptionKey: result.stderr])
        }
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)

        let cue = file.deletingPathExtension().appendingPathExtension("cue")
        if let artist = tags["artist"], !artist.isEmpty, let text = try? String(contentsOf: cue, encoding: .utf8) {
            let quoted = artist.replacingOccurrences(of: "\"", with: "'")
            let lines = text.components(separatedBy: "\n").map { line -> String in
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                return line.dropFirst(indent.count).hasPrefix("PERFORMER ") ? "\(indent)PERFORMER \"\(quoted)\"" : line
            }
            try lines.joined(separator: "\n").write(to: cue, atomically: true, encoding: .utf8)
        }
    }

    /// The file's cover as a base64 FLAC picture block (front cover), Ogg's cover tag; nil without one.
    private static func oggPictureTag(from file: URL, ffmpeg: String) -> String? {
        let jpeg = FileManager.default.temporaryDirectory.appendingPathComponent("nullplayer-cover-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: jpeg) }
        guard (try? RipProcess.run(ffmpeg, ["-nostdin", "-y", "-v", "error", "-i", file.path, "-map", "0:v:0",
                                            "-frames:v", "1", jpeg.path]))?.status == 0,
              let image = try? Data(contentsOf: jpeg),
              let source = CGImageSourceCreateWithData(image as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        var block = Data()
        func u32(_ value: Int) { withUnsafeBytes(of: UInt32(value).bigEndian) { block.append(contentsOf: $0) } }
        let mime = Data("image/jpeg".utf8)
        u32(3)  // front cover
        u32(mime.count); block.append(mime)
        u32(0)  // no description
        u32(properties[kCGImagePropertyPixelWidth] as? Int ?? 0)
        u32(properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
        u32(24); u32(0)  // colour depth, palette size
        u32(image.count); block.append(image)
        return block.base64EncodedString()
    }
}
