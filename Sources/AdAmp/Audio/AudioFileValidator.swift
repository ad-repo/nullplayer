import Foundation
import AVFoundation

/// Validates audio files before adding to playlist or library
enum AudioFileValidator {
    
    /// Supported audio extensions
    static let supportedExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg", "alac"]
    
    /// Result of validating a batch of URLs
    struct ValidationResult {
        let validURLs: [URL]
        let invalidFiles: [(url: URL, reason: String)]
        
        var hasInvalidFiles: Bool { !invalidFiles.isEmpty }
    }
    
    /// Quick validation - checks existence and extension only (fast, for batch operations)
    /// Returns nil if valid, or an error message if invalid
    static func quickValidate(url: URL) -> String? {
        // Remote URLs (streaming) don't need validation
        if url.scheme == "http" || url.scheme == "https" {
            return nil
        }
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "File does not exist"
        }
        
        // Check extension is supported
        let ext = url.pathExtension.lowercased()
        if !supportedExtensions.contains(ext) {
            return "Unsupported format: .\(ext)"
        }
        
        return nil  // Valid
    }
    
    /// Full validation - opens file with AVAudioFile (slower, for playback time)
    /// Returns nil if valid, or an error message if invalid
    static func fullValidate(url: URL) -> String? {
        // Remote URLs (streaming) don't need validation
        if url.scheme == "http" || url.scheme == "https" {
            return nil
        }
        
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "File does not exist"
        }
        
        // Try to open with AVAudioFile to validate format
        do {
            _ = try AVAudioFile(forReading: url)
            return nil  // Valid
        } catch {
            let ext = url.pathExtension.lowercased()
            var reason = error.localizedDescription
            
            // Add helpful hints for common issues
            if ext == "wav" {
                reason += " (WAV may use unsupported compression)"
            } else if ext == "wma" {
                reason = "WMA format is not supported"
            }
            
            return reason
        }
    }
    
    /// Quick validate multiple URLs (fast - just checks existence and extension)
    static func quickValidate(urls: [URL]) -> ValidationResult {
        var validURLs: [URL] = []
        var invalidFiles: [(url: URL, reason: String)] = []
        
        for url in urls {
            if let errorReason = quickValidate(url: url) {
                invalidFiles.append((url: url, reason: errorReason))
                NSLog("AudioFileValidator: Invalid file '%@': %@", url.lastPathComponent, errorReason)
            } else {
                validURLs.append(url)
            }
        }
        
        return ValidationResult(validURLs: validURLs, invalidFiles: invalidFiles)
    }
    
    /// Post notification about invalid files for UI feedback
    static func notifyInvalidFiles(_ invalidFiles: [(url: URL, reason: String)]) {
        guard !invalidFiles.isEmpty else { return }
        
        // Build a summary message
        let fileNames = invalidFiles.map { $0.url.lastPathComponent }
        let message: String
        if invalidFiles.count == 1 {
            message = "Could not load '\(fileNames[0])': \(invalidFiles[0].reason)"
        } else {
            message = "Could not load \(invalidFiles.count) files: \(fileNames.joined(separator: ", "))"
        }
        
        NSLog("AudioFileValidator: %@", message)
        
        // Post notification for UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .audioTrackDidFailToLoad,
                object: nil,
                userInfo: [
                    "message": message,
                    "invalidFiles": invalidFiles
                ]
            )
        }
    }
}
