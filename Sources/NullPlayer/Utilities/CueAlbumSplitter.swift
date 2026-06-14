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

            let cueDir = cueURL.deletingLastPathComponent()

            // Output extension: always FLAC (re-encode for all sources per spec)
            let outExt = "flac"

            var paths: [URL] = []
            var pathsSet: Set<String> = []  // Track generated paths to de-dup within this cue

            for (index, entry) in cue.entries.enumerated() {
                let trackNum = index + 1
                let outURL = computeOutputPath(for: entry.title, trackIndex: trackNum, totalTracks: cue.entries.count, inDirectory: cueDir, fileExtension: outExt, excludedPaths: pathsSet, checkFilesystem: false)
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
    /// On ffmpeg absence or write failure, logs a one-time warning notice and returns nil
    /// (original file remains importable).
    /// - Parameters:
    ///   - cueURL: URL of the .cue file
    /// - Returns: Backing file URL if successfully split (or already split), nil otherwise
    static func splitIfNeeded(cueURL: URL) -> URL? {
        guard let shouldSplit = shouldPerformSplit(cueURL: cueURL) else {
            return nil  // Cue unparseable
        }

        guard shouldSplit else {
            // Idempotent: all outputs exist, return backing file for exclusion
            if let expectedPaths = expectedOutputPaths(for: cueURL), !expectedPaths.isEmpty {
                do {
                    let cue = try CueSheet.parse(from: cueURL)
                    let backingURL = CueSheet.resolveBackingFile(for: cueURL, fileName: cue.fileName)
                    if FileManager.default.fileExists(atPath: backingURL.path) {
                        return backingURL
                    }
                } catch {
                    return nil
                }
            }
            return nil
        }

        // Work needed: attempt to split
        let result = performSplit(cueURL: cueURL)

        if let backingURL = result.backingFile {
            return backingURL
        }

        if let notice = result.skipWarnNotice {
            postSkipWarnNotice(notice)
        }

        return nil
    }

    // MARK: - Private Implementation

    private struct SplitResult {
        let backingFile: URL?  // Backing file to exclude (only if split succeeded)
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
            let backingURL = CueSheet.resolveBackingFile(for: cueURL, fileName: cue.fileName)

            // Check backing file exists
            guard FileManager.default.fileExists(atPath: backingURL.path) else {
                NSLog("CueAlbumSplitter: Backing file missing: %@", backingURL.path)
                return SplitResult(backingFile: nil, skipWarnNotice: nil)
            }

            // Resolve ffmpeg
            guard let ffmpegPath = resolveToolPath("ffmpeg") else {
                let msg = "Install ffmpeg to split cue albums. Enable in Preferences and rescan."
                NSLog("CueAlbumSplitter: ffmpeg not found")
                if !skipWarnNoticeShown {
                    skipWarnNoticeShown = true
                    return SplitResult(backingFile: nil, skipWarnNotice: msg)
                }
                return SplitResult(backingFile: nil, skipWarnNotice: nil)
            }

            // Resolve ffprobe for cover-art detection
            let ffprobePath = resolveToolPath("ffprobe")

            // Check if source has video/attached-pic stream for cover art
            let hasAttachedPic = ffprobePath != nil ? checkHasAttachedPic(backingURL, ffprobePath: ffprobePath!) : false

            let cueDir = cueURL.deletingLastPathComponent()
            let outExt = "flac"

            var anyWriteFailed = false
            var successCount = 0
            var thisCueOutputPaths: Set<String> = []  // Track this cue's expected outputs for de-dup logic

            for (index, entry) in cue.entries.enumerated() {
                let trackNum = index + 1
                let outURL = computeOutputPath(for: entry.title, trackIndex: trackNum, totalTracks: cue.entries.count, inDirectory: cueDir, fileExtension: outExt, excludedPaths: thisCueOutputPaths, checkFilesystem: true)
                thisCueOutputPaths.insert(outURL.path)

                // Skip if already exists
                if FileManager.default.fileExists(atPath: outURL.path) {
                    successCount += 1
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

                args.append(contentsOf: [
                    "-map", "0:a:0",
                    "-c:a", "flac",
                    "-map_metadata", "-1",
                    "-metadata", "title=\(entry.title)",
                    "-metadata", "artist=\(entry.performer ?? cue.performer ?? "")",
                    "-metadata", "album=\(cue.title ?? "")",
                    "-metadata", "album_artist=\(cue.performer ?? "")",
                    "-metadata", "track=\(trackNum)/\(cue.entries.count)"
                ])

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
                return SplitResult(backingFile: backingURL, skipWarnNotice: nil)
            } else if anyWriteFailed {
                let msg = "Failed to split some .cue albums (permission or disk space). Check logs."
                if !skipWarnNoticeShown {
                    skipWarnNoticeShown = true
                    return SplitResult(backingFile: nil, skipWarnNotice: msg)
                }
                return SplitResult(backingFile: nil, skipWarnNotice: nil)
            }

            return SplitResult(backingFile: nil, skipWarnNotice: nil)
        } catch {
            NSLog("CueAlbumSplitter: Error during split: %@", error.localizedDescription)
            return SplitResult(backingFile: nil, skipWarnNotice: nil)
        }
    }

    // MARK: - Filename Sanitization

    /// Sanitizes a track title for use in a filename.
    /// - Replaces illegal characters (/ \ : * ? " < > | + control chars) with `_`
    /// - Collapses runs of whitespace to single space
    /// - Trims leading/trailing spaces and dots
    /// - Applies Unicode NFC normalization to avoid HFS+/APFS collisions
    /// - Truncates to ~200 UTF-8 bytes for the title portion
    private static func sanitizeTrackTitle(_ title: String, trackIndex: Int, totalTracks: Int) -> String {
        var result = title

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

        // Truncate title to ~200 UTF-8 bytes
        if let data = result.data(using: .utf8), data.count > 200 {
            // Find safe truncation point (don't split UTF-8 sequences)
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
        let sanitized = sanitizeTrackTitle(title, trackIndex: trackIndex, totalTracks: totalTracks)
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
