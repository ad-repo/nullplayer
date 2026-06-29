import Foundation
import AppKit

/// Handles splitting of .cue sheet albums into individual track files via ffmpeg.
/// This is a one-time operation per scan, with idempotency: if all expected split files
/// exist, no work is performed.
enum CueAlbumSplitter {

    // MARK: - Public Interface

    /// Determines the set of output paths that would be created for a given cue file.
    /// This function is testable and requires no ffmpeg.
    /// - Parameters:
    ///   - cueURL: URL of the .cue file
    /// - Returns: Array of expected output URLs in the same directory as the cue, or nil if cue cannot be parsed
    static func expectedOutputPaths(for cueURL: URL) -> [URL]? {
        do {
            let cue = try CueSheet.parse(from: cueURL)
            guard !cue.entries.isEmpty else { return nil }

            let outDir = outputDirectory(for: cue, cueURL: cueURL)

            // Output extension: always FLAC (re-encode for all sources per spec)
            let outExt = "flac"

            var paths: [URL] = []
            var pathsSet: Set<String> = []  // Track generated paths to de-dup within this cue

            for (index, entry) in cue.entries.enumerated() {
                let trackNum = index + 1
                let outURL = computeOutputPath(for: entry.title, trackIndex: trackNum, totalTracks: cue.entries.count, inDirectory: outDir, fileExtension: outExt, excludedPaths: pathsSet, checkFilesystem: false)
                paths.append(outURL)
                pathsSet.insert(outURL.path)
            }

            return paths
        } catch {
            NSLog("CueAlbumSplitter: Failed to parse cue for expected outputs: %@", error.localizedDescription)
            return nil
        }
    }

    /// Determines whether a cue album should be split.
    /// Returns true if any expected output files are missing (work needed).
    /// Returns false if all expected outputs exist (idempotent; no work).
    /// Returns nil if cue cannot be parsed.
    static func shouldPerformSplit(cueURL: URL) -> Bool? {
        guard let expectedPaths = expectedOutputPaths(for: cueURL) else { return nil }

        // If all expected files exist, no work needed
        for path in expectedPaths {
            if !FileManager.default.fileExists(atPath: path.path) {
                return true  // At least one missing, so we should split
            }
        }
        return false  // All exist, idempotent skip
    }

    /// Splits a .cue album into individual track files via ffmpeg (if available).
    /// Performs idempotency check: if all outputs exist, returns backing file path for exclusion
    /// and performs no ffmpeg work.
    /// On ffmpeg absence or write failure, logs a one-time warning notice and returns
    /// an empty outcome (original file remains importable).
    /// - Parameters:
    ///   - cueURL: URL of the .cue file
    /// - Returns: A `SplitOutcome` describing the backing file to exclude and the per-track
    ///   files that now exist on disk and should be imported.
    static func splitIfNeeded(cueURL: URL) -> SplitOutcome {
        // Parse once up front and resolve the backing path now, so the idempotent branch
        // never depends on a second parse that could fail and let the backing slip back in.
        guard let cue = try? CueSheet.parse(from: cueURL), !cue.entries.isEmpty else {
            return SplitOutcome(backingFileToExclude: nil, trackFiles: [])  // Cue unparseable
        }
        let backingURL = resolveBackingFileWithFallback(for: cueURL, fileName: cue.fileName)

        guard let shouldSplit = shouldPerformSplit(cueURL: cueURL) else {
            return SplitOutcome(backingFileToExclude: nil, trackFiles: [])
        }

        guard shouldSplit else {
            // Idempotent: all outputs already exist. Always exclude the backing while it's on
            // disk (so it can never be re-imported), and import the existing per-track files.
            let expectedPaths = expectedOutputPaths(for: cueURL) ?? []
            let backingExists = FileManager.default.fileExists(atPath: backingURL.path)
            return SplitOutcome(backingFileToExclude: backingExists ? backingURL : nil, trackFiles: expectedPaths)
        }

        // Work needed: attempt to split
        let result = performSplit(cueURL: cueURL)

        if let notice = result.skipWarnNotice {
            postSkipWarnNotice(notice)
        }

        return SplitOutcome(backingFileToExclude: result.backingFile, trackFiles: result.trackFiles)
    }

    /// Result of attempting to split a cue album.
    struct SplitOutcome {
        /// Backing file to exclude from the library — non-nil only when the per-track
        /// split files exist on disk (freshly written or from a prior scan).
        let backingFileToExclude: URL?
        /// Per-track files that now exist on disk and should be imported as library tracks.
        let trackFiles: [URL]
    }

    // MARK: - Private Implementation

    private struct SplitResult {
        let backingFile: URL?  // Backing file to exclude (only if split succeeded)
        let trackFiles: [URL]  // Per-track files written/confirmed on disk
        let skipWarnNotice: String?  // One-time warning message if split skipped
    }

    private static var skipWarnNoticeShown = false

    /// Helper to resolve tool path without MainActor isolation.
    /// Replicates StreamRipper.resolveTool but callable from background threads.
    private static func resolveToolPath(_ name: String) -> String? {
        let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
        for dir in searchPaths {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.fileExists(atPath: candidate) && FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func performSplit(cueURL: URL) -> SplitResult {
        do {
            let cue = try CueSheet.parse(from: cueURL)
            let backingURL = resolveBackingFileWithFallback(for: cueURL, fileName: cue.fileName)

            // Check backing file exists
            guard FileManager.default.fileExists(atPath: backingURL.path) else {
                NSLog("CueAlbumSplitter: Backing file missing: %@", backingURL.path)
                return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: nil)
            }

            // Resolve ffmpeg
            guard let ffmpegPath = resolveToolPath("ffmpeg") else {
                let msg = "Install ffmpeg to split cue albums. Enable in Preferences and rescan."
                NSLog("CueAlbumSplitter: ffmpeg not found")
                if !skipWarnNoticeShown {
                    skipWarnNoticeShown = true
                    return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: msg)
                }
                return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: nil)
            }

            // Resolve ffprobe for cover-art detection
            let ffprobePath = resolveToolPath("ffprobe")

            // Check if source has video/attached-pic stream for cover art
            let hasAttachedPic = ffprobePath != nil ? checkHasAttachedPic(backingURL, ffprobePath: ffprobePath!) : false

            // Read the source file's own album/artist tags. The cue's TITLE is usually the
            // video/show title (the "track" name); the real album lives in the file metadata.
            let src = sourceTags(for: cue, cueURL: cueURL)

            // Write each album into its own subdirectory (named from metadata) so tracks
            // don't land loose alongside the source. Create it before writing.
            let outDir = outputDirectory(for: cue, cueURL: cueURL)
            do {
                try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            } catch {
                NSLog("CueAlbumSplitter: Failed to create output directory %@: %@", outDir.path, error.localizedDescription)
                if !skipWarnNoticeShown {
                    skipWarnNoticeShown = true
                    return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: "Failed to create folder for split .cue album (check permissions).")
                }
                return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: nil)
            }
            let outExt = "flac"

            var anyWriteFailed = false
            var successCount = 0
            var producedFiles: [URL] = []

            // Seed with this cue's FULL set of deterministic canonical output paths up front.
            // A track whose canonical file already exists (idempotent partial re-run) is then
            // recognized as our own output and reused, never re-encoded into a "(N)" duplicate.
            // Collision de-dup only fires against genuinely unrelated pre-existing files.
            let thisCueOutputPaths: Set<String> = Set(cue.entries.enumerated().map { index, entry in
                computeOutputPath(for: entry.title, trackIndex: index + 1, totalTracks: cue.entries.count, inDirectory: outDir, fileExtension: outExt, excludedPaths: [], checkFilesystem: false).path
            })

            for (index, entry) in cue.entries.enumerated() {
                let trackNum = index + 1
                let outURL = computeOutputPath(for: entry.title, trackIndex: trackNum, totalTracks: cue.entries.count, inDirectory: outDir, fileExtension: outExt, excludedPaths: thisCueOutputPaths, checkFilesystem: true)

                // Skip if already exists
                if FileManager.default.fileExists(atPath: outURL.path) {
                    successCount += 1
                    producedFiles.append(outURL)
                    continue
                }

                let startTime = entry.startTime
                let endTime: TimeInterval? = {
                    guard index + 1 < cue.entries.count else { return nil }
                    return cue.entries[index + 1].startTime
                }()

                // Build ffmpeg args per spec
                var args: [String] = [
                    "-hide_banner", "-loglevel", "error", "-y",
                    "-i", backingURL.path,
                    "-ss", String(format: "%.6f", startTime)
                ]

                // Conditionally add -to for non-last tracks
                if let endTime = endTime {
                    args.append("-to")
                    args.append(String(format: "%.6f", endTime))
                }

                // Inherit the source file's metadata (date, genre, album-art tags, and any
                // album/artist the source carries), then layer the cue's values on top.
                // `-map_metadata 0` copies the source global metadata; per-track title and
                // track number always override; album/artist/album_artist override ONLY when
                // the cue provides a non-empty value, so we never blank an inherited field.
                args.append(contentsOf: [
                    "-map", "0:a:0",
                    "-c:a", "flac",
                    "-map_metadata", "0",
                    "-metadata", "title=\(entry.title)",
                    "-metadata", "track=\(trackNum)/\(cue.entries.count)"
                ])
                if let artist = (entry.performer ?? src.artist ?? cue.performer)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !artist.isEmpty {
                    args.append(contentsOf: ["-metadata", "artist=\(artist)"])
                }
                // Album comes from the source file's tag (the real release), not the cue TITLE.
                if let album = (src.album ?? cue.title)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !album.isEmpty {
                    args.append(contentsOf: ["-metadata", "album=\(album)"])
                }
                if let albumArtist = (src.albumArtist ?? src.artist ?? cue.performer)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !albumArtist.isEmpty {
                    args.append(contentsOf: ["-metadata", "album_artist=\(albumArtist)"])
                }

                // Conditionally add cover art (only if source has video/attached-pic)
                if hasAttachedPic {
                    args.append(contentsOf: [
                        "-map", "0:v:0",
                        "-c:v", "copy",
                        "-disposition:v", "attached_pic"
                    ])
                }

                args.append(outURL.path)

                // Execute ffmpeg
                let task = Process()
                task.executableURL = URL(fileURLWithPath: ffmpegPath)
                task.arguments = args

                // Discard stderr (ffmpeg's -loglevel error suppresses normal output)
                task.standardError = FileHandle.nullDevice
                task.standardOutput = FileHandle.nullDevice

                do {
                    try task.run()
                    task.waitUntilExit()

                    if task.terminationStatus == 0 && FileManager.default.fileExists(atPath: outURL.path) {
                        successCount += 1
                        producedFiles.append(outURL)
                    } else {
                        anyWriteFailed = true
                        NSLog("CueAlbumSplitter: ffmpeg failed for track %d: %@", trackNum, outURL.lastPathComponent)
                        // Try to clean up partial file
                        try? FileManager.default.removeItem(at: outURL)
                    }
                } catch {
                    anyWriteFailed = true
                    NSLog("CueAlbumSplitter: Failed to run ffmpeg: %@", error.localizedDescription)
                    try? FileManager.default.removeItem(at: outURL)
                }
            }

            // Only exclude backing if ALL tracks succeeded (no partial writes)
            if successCount == cue.entries.count && !anyWriteFailed {
                return SplitResult(backingFile: backingURL, trackFiles: producedFiles, skipWarnNotice: nil)
            } else if anyWriteFailed {
                let msg = "Failed to split some .cue albums (permission or disk space). Check logs."
                if !skipWarnNoticeShown {
                    skipWarnNoticeShown = true
                    return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: msg)
                }
                return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: nil)
            }

            return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: nil)
        } catch {
            NSLog("CueAlbumSplitter: Error during split: %@", error.localizedDescription)
            return SplitResult(backingFile: nil, trackFiles: [], skipWarnNotice: nil)
        }
    }

    // MARK: - Output Location

    /// The directory split tracks are written to: a per-cue subdirectory of the cue's
    /// own folder, named from album metadata (falling back to the .cue's filename), so
    /// each album lands in its own folder instead of loose alongside the source.
    private static func outputDirectory(for cue: CueSheet, cueURL: URL) -> URL {
        cueURL.deletingLastPathComponent()
            .appendingPathComponent(albumFolderName(for: cue, cueURL: cueURL), isDirectory: true)
    }

    /// Builds the album subdirectory name: "Artist - Album" from cue metadata, falling
    /// back to the album or artist alone, then to the .cue's own basename (always unique
    /// within the folder) when no usable metadata is present.
    private static func albumFolderName(for cue: CueSheet, cueURL: URL) -> String {
        // Prefer the source file's own ALBUM/ARTIST tags (the real release). The cue's TITLE
        // is usually the video/show title (the "track" name), not the album.
        let src = sourceTags(for: cue, cueURL: cueURL)
        let artist = (src.artist ?? cue.performer ?? "").trimmingCharacters(in: .whitespaces)
        let album = (src.album ?? cue.title ?? "").trimmingCharacters(in: .whitespaces)
        let base: String
        if !artist.isEmpty && !album.isEmpty {
            base = "\(artist) - \(album)"
        } else if !album.isEmpty {
            base = album
        } else if !artist.isEmpty {
            base = artist
        } else {
            base = ""
        }
        let sanitized = sanitizeFilenameComponent(base)
        if !sanitized.isEmpty { return sanitized }
        // Unique fallback: the cue's own filename.
        let fromCue = sanitizeFilenameComponent(cueURL.deletingPathExtension().lastPathComponent)
        return fromCue.isEmpty ? "Cue Album" : fromCue
    }

    // MARK: - Filename Sanitization

    /// Sanitizes a string for use as a single filename/directory component.
    /// - Replaces illegal characters (/ \ : * ? " < > | + control chars) with `_`
    /// - Collapses runs of whitespace to single space
    /// - Trims leading/trailing spaces and dots
    /// - Applies Unicode NFC normalization to avoid HFS+/APFS collisions
    /// - Truncates to ~200 UTF-8 bytes
    private static func sanitizeFilenameComponent(_ input: String) -> String {
        var result = input

        // Replace illegal filesystem characters with underscore
        let illegalChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let controlChars = CharacterSet.controlCharacters
        let replacementChars = illegalChars.union(controlChars)

        result = result.components(separatedBy: replacementChars)
            .joined(separator: "_")

        // Collapse whitespace runs to single space
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Trim leading/trailing spaces and dots
        result = result.trimmingCharacters(in: .whitespaces)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Apply Unicode NFC normalization (avoids HFS+/APFS case- and form-folding collisions)
        result = (result as NSString).precomposedStringWithCanonicalMapping

        // Truncate to ~200 UTF-8 bytes (don't split UTF-8 sequences)
        if let data = result.data(using: .utf8), data.count > 200 {
            if let truncated = String(data: data.prefix(200), encoding: .utf8) {
                result = truncated.trimmingCharacters(in: .whitespaces)
            }
        }

        return result
    }

    /// Computes the output path for a single track, with collision de-duplication.
    /// Ensures idempotency: only de-duplicates against unrelated pre-existing files,
    /// not against other paths from THIS cue's own expected outputs.
    /// - Parameters:
    ///   - title: Track title to sanitize
    ///   - trackIndex: 1-based track number
    ///   - totalTracks: Total number of tracks in the album
    ///   - inDirectory: Directory where the file will be written
    ///   - fileExtension: File extension (e.g., "flac")
    ///   - excludedPaths: Set of paths already generated for THIS cue (to avoid de-dup against them)
    ///   - checkFilesystem: If true, check filesystem and de-dup against unrelated files; if false, return deterministic path only
    /// - Returns: URL of the output file, with collision suffix if needed (only when checkFilesystem is true)
    private static func computeOutputPath(
        for title: String,
        trackIndex: Int,
        totalTracks: Int,
        inDirectory: URL,
        fileExtension: String,
        excludedPaths: Set<String>,
        checkFilesystem: Bool
    ) -> URL {
        let sanitized = sanitizeFilenameComponent(title)
        let baseFilename = "\(trackIndex) - \(sanitized)"
        let ext = fileExtension
        var filename = "\(baseFilename).\(ext)"
        var outURL = inDirectory.appendingPathComponent(filename)

        // De-duplicate only when writing: if target path exists and is NOT part of this cue's own outputs,
        // append (2), (3), etc. until unique
        if checkFilesystem {
            var counter = 2
            while FileManager.default.fileExists(atPath: outURL.path) && !excludedPaths.contains(outURL.path) {
                filename = "\(baseFilename) (\(counter)).\(ext)"
                outURL = inDirectory.appendingPathComponent(filename)
                counter += 1
            }
        }

        return outURL
    }

    // MARK: - Backing File Resolution

    /// Resolves the cue's backing file, honoring the `FILE` line first and falling back to a
    /// same-basename audio sibling when that file is absent on disk.
    ///
    /// The common case: a cue+audio pair is renamed together (`track01.{cue,flac}` →
    /// `My Album.{cue,flac}`) but the `FILE "track01.flac"` line inside the cue is left stale.
    /// `CueSheet.resolveBackingFile` then points at a file that no longer exists, so the split
    /// silently no-ops. When that happens, look for an audio file next to the cue whose basename
    /// matches the cue's own basename (`My Album.cue` → `My Album.flac`) and use it instead.
    ///
    /// The fallback only ever inspects the cue's own directory, so — like `resolveBackingFile`'s
    /// path-escape guard — it can never read an arbitrary file elsewhere on disk. It is
    /// deterministic (sorted), so `expectedOutputPaths`, `performSplit`, and `sourceTags` all
    /// resolve the same backing and idempotency holds. When the `FILE` line resolves to an
    /// existing file, or no matching sibling exists, the original resolved path is returned
    /// unchanged so callers' existence checks behave exactly as before.
    ///
    /// Internal (not private) so the resolution logic can be unit-tested without ffmpeg.
    static func resolveBackingFileWithFallback(for cueURL: URL, fileName: String) -> URL {
        let primary = CueSheet.resolveBackingFile(for: cueURL, fileName: fileName)
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        return siblingAudioByName(for: cueURL) ?? primary
    }

    /// Finds an audio file next to the cue that shares the cue's basename (`My Album.cue` →
    /// `My Album.flac`). Returns nil when none exists. Deterministic: candidates are sorted by
    /// path so repeated calls within a scan agree.
    private static func siblingAudioByName(for cueURL: URL) -> URL? {
        let dir = cueURL.deletingLastPathComponent()
        let base = cueURL.deletingPathExtension().lastPathComponent
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        return entries
            .filter { $0.deletingPathExtension().lastPathComponent == base
                && LocalFileDiscovery.isSupportedAudioFile($0) }
            .sorted { $0.path < $1.path }
            .first
    }

    // MARK: - Source Tags

    /// Reads the backing file's own album/artist/album_artist tags via ffprobe.
    /// Deterministic (same file → same result), so it is safe to call from both the
    /// idempotency path and the split path. Returns nils when ffprobe or the file is absent.
    private static func sourceTags(for cue: CueSheet, cueURL: URL) -> (artist: String?, album: String?, albumArtist: String?) {
        let backingURL = resolveBackingFileWithFallback(for: cueURL, fileName: cue.fileName)
        guard FileManager.default.fileExists(atPath: backingURL.path),
              let ffprobe = resolveToolPath("ffprobe") else { return (nil, nil, nil) }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffprobe)
        task.arguments = [
            "-v", "error",
            "-show_entries", "format_tags=artist,album,album_artist",
            "-of", "default=noprint_wrappers=1",
            backingURL.path
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        var artist: String?, album: String?, albumArtist: String?
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            for raw in out.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = String(raw)
                guard let eq = line.firstIndex(of: "=") else { continue }
                // Key form is "TAG:album" or "album" depending on ffprobe version.
                let key = String(line[..<eq]).lowercased()
                let val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !val.isEmpty else { continue }
                if key.hasSuffix("album_artist") { albumArtist = val }
                else if key.hasSuffix("album") { album = val }
                else if key.hasSuffix("artist") { artist = val }
            }
        } catch {
            return (nil, nil, nil)
        }
        return (artist, album, albumArtist)
    }

    // MARK: - Cover Art Detection

    /// Checks if the backing file has a video or attached-picture stream using ffprobe.
    private static func checkHasAttachedPic(_ audioURL: URL, ffprobePath: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: ffprobePath)
        task.arguments = [
            "-v", "error",
            "-show_entries", "stream=codec_type",
            "-of", "compact=p=0:nk=1",
            audioURL.path
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains("video") || output.contains("attached_pic")
            }
        } catch {
            NSLog("CueAlbumSplitter: ffprobe check failed: %@", error.localizedDescription)
        }

        return false
    }

    // MARK: - Notifications

    private static func postSkipWarnNotice(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Cue Album Splitting"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
