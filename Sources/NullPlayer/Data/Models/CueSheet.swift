import Foundation

/// Represents a parsed .cue sheet file
struct CueSheet {
    struct Entry {
        let number: Int
        let title: String
        let performer: String?
        let startTime: TimeInterval
    }

    let performer: String?   // top-level PERFORMER → artist fallback
    let title: String?       // top-level TITLE → album
    let fileName: String     // first FILE only (warn if more)
    let entries: [Entry]

    /// Parse a .cue sheet from file
    static func parse(from url: URL) throws -> CueSheet {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        var performer: String?
        var title: String?
        var fileName: String?
        var entries: [Entry] = []

        var currentTrackNumber: Int?
        var currentTrackTitle: String?
        var currentTrackPerformer: String?
        var currentTrackStartTime: TimeInterval?

        var fileCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("REM") {
                continue
            }

            // Split into tokens (preserve order for quoted values)
            let components = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
            guard let command = components.first?.uppercased() else { continue }

            switch command {
            case "PERFORMER":
                if fileName == nil {
                    // Top-level PERFORMER
                    performer = extractQuotedValue(from: trimmed, command: command)
                } else if currentTrackNumber != nil {
                    // Track-level PERFORMER
                    currentTrackPerformer = extractQuotedValue(from: trimmed, command: command)
                }

            case "TITLE":
                if fileName == nil {
                    // Top-level TITLE
                    title = extractQuotedValue(from: trimmed, command: command)
                } else if currentTrackNumber != nil {
                    // Track-level TITLE
                    currentTrackTitle = extractQuotedValue(from: trimmed, command: command)
                }

            case "FILE":
                fileCount += 1
                if fileCount == 1 {
                    // Use first FILE only; warn if more exist
                    fileName = extractQuotedValue(from: trimmed, command: command)
                } else {
                    NSLog("CueSheet: Warning — multiple FILE entries; using first only")
                }

            case "TRACK":
                // Save previous track if exists
                if let trackNum = currentTrackNumber, let startTime = currentTrackStartTime {
                    let entry = Entry(
                        number: trackNum,
                        title: currentTrackTitle ?? "Track \(trackNum)",
                        performer: currentTrackPerformer,
                        startTime: startTime
                    )
                    entries.append(entry)
                }

                // Parse new track
                if let trackNumStr = components.dropFirst().first,
                   let trackNum = Int(trackNumStr) {
                    currentTrackNumber = trackNum
                    currentTrackTitle = nil
                    currentTrackPerformer = nil
                    currentTrackStartTime = nil
                } else {
                    currentTrackNumber = nil
                }

            case "INDEX":
                if currentTrackNumber != nil {
                    // Try INDEX 01 first, fall back to INDEX 00
                    if let indexStr = components.dropFirst().first {
                        let indexNum = Int(indexStr) ?? -1

                        // Look for MM:SS:FF after "INDEX NN"
                        if let tsStr = components.dropFirst(2).first {
                            if let ts = parseCueTimestamp(tsStr) {
                                // Prefer INDEX 01, but accept INDEX 00 if no INDEX 01 exists
                                if indexNum == 1 || currentTrackStartTime == nil {
                                    currentTrackStartTime = ts
                                }
                            }
                        }
                    }
                }

            default:
                break
            }
        }

        // Save final track
        if let trackNum = currentTrackNumber, let startTime = currentTrackStartTime {
            let entry = Entry(
                number: trackNum,
                title: currentTrackTitle ?? "Track \(trackNum)",
                performer: currentTrackPerformer,
                startTime: startTime
            )
            entries.append(entry)
        }

        guard let fileName = fileName else {
            throw NSError(domain: "CueSheet", code: -1, userInfo: ["message": "No FILE entry found"])
        }

        return CueSheet(performer: performer, title: title, fileName: fileName, entries: entries)
    }

    /// Extract a quoted value from a line like: PERFORMER "Artist Name"
    private static func extractQuotedValue(from line: String, command: String) -> String? {
        // Find the command, then look for quoted string
        guard let commandRange = line.range(of: command, options: .caseInsensitive) else {
            return nil
        }

        let afterCommand = String(line[commandRange.upperBound...])

        // Find first quote
        guard let firstQuote = afterCommand.firstIndex(of: "\"") else {
            return nil
        }

        // Find closing quote
        let quoted = afterCommand[firstQuote...]
        guard let secondQuote = quoted.dropFirst().firstIndex(of: "\"") else {
            return nil
        }

        let value = String(quoted[quoted.index(after: quoted.startIndex)..<secondQuote])

        // Strip single quotes used as escapes for double quotes
        return value.replacingOccurrences(of: "'", with: "\"")
    }

    /// Parse MM:SS:FF (MM:SS:FF @ 75 fps) to seconds
    /// Inverse of StreamRipper's cueTimestamp
    static func parseCueTimestamp(_ s: String) -> TimeInterval? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }

        guard let mm = Int(parts[0]),
              let ss = Int(parts[1]),
              let ff = Int(parts[2]) else {
            return nil
        }

        let totalSeconds = mm * 60 + ss
        let totalFrames = totalSeconds * 75 + ff
        return Double(totalFrames) / 75.0
    }

    /// Resolve the backing file path, relative to the .cue's directory if relative
    static func resolveBackingFile(for cueURL: URL, fileName: String) -> URL {
        // If fileName starts with /, it's absolute
        if fileName.hasPrefix("/") {
            return URL(fileURLWithPath: fileName)
        }

        // Otherwise, resolve relative to the .cue's directory
        let cueDir = cueURL.deletingLastPathComponent()
        return cueDir.appendingPathComponent(fileName)
    }

    /// Check if a sibling .cue file exists next to an audio file
    static func siblingCue(for audioURL: URL) -> URL? {
        let cueURL = audioURL.deletingPathExtension().appendingPathExtension("cue")

        if FileManager.default.fileExists(atPath: cueURL.path) {
            return cueURL
        }
        return nil
    }

    /// Expand a .cue sheet into virtual Track objects for direct playback
    /// Returns empty array if cue is degenerate (no entries or unusable), which signals
    /// callers to fall back to normal Track-from-URL handling (for sibling-cue case) or
    /// log + no-op (for direct .cue open).
    static func expandToTracks(cue: CueSheet, cueFileURL: URL) -> [Track] {
        // Guard: if no entries, cue is unusable
        guard !cue.entries.isEmpty else {
            return []
        }

        // Resolve the backing file
        let backingURL = resolveBackingFile(for: cueFileURL, fileName: cue.fileName)

        var tracks: [Track] = []

        for i in 0..<cue.entries.count {
            let entry = cue.entries[i]

            // Determine cueEndOffset: next entry's startTime, or nil for last entry
            let cueEndOffset: TimeInterval? = {
                guard i + 1 < cue.entries.count else { return nil }
                return cue.entries[i + 1].startTime
            }()

            let track = Track(
                url: backingURL,
                title: entry.title,
                artist: entry.performer ?? cue.performer,
                album: cue.title,
                duration: cueEndOffset.map { $0 - entry.startTime } ?? nil,
                cueStartOffset: entry.startTime,
                cueEndOffset: cueEndOffset,
                cueSourceURL: cueFileURL
            )

            tracks.append(track)
        }

        return tracks
    }
}
