import Foundation
import os

// =============================================================================
// LOG
// =============================================================================
// Thin wrapper around Apple's unified logging (`os.Logger`) with convenience
// helpers and a shared set of subsystems/categories.
//
// Why: ~2,000 `NSLog(...)` calls litter the codebase. NSLog has drawbacks:
//   - Always writes to stderr + ASL regardless of log level
//   - No filtering by category or severity
//   - Performance cost even when nobody is reading the output
//   - Cannot be filtered in Console.app by subsystem
//
// `os.Logger` gives us:
//   - Free, async unified logging
//   - `.debug` output auto-suppressed in release builds
//   - Filterable in Console.app and `log stream --predicate`
//   - Argument-capture aware (privacy levels, format specifiers)
//
// Usage:
//   Log.audio.info("Playback started for \(track.title)")
//   Log.casting.error("Sonos group failed: \(error.localizedDescription)")
//   Log.radio.debug("Reconnect scheduled in \(delay)s")
//
// For one-shot compatibility, `Log.legacy(_:)` mirrors NSLog semantics
// (default-level general-category message).
// =============================================================================

enum Log {
    /// Unified logging subsystem. Filter in Console.app by entering this.
    private static let subsystem = Bundle.main.bundleIdentifier ?? "NullPlayer"

    // MARK: - Categories

    /// Audio playback (AudioEngine, streaming, crossfade, gapless).
    static let audio    = Logger(subsystem: subsystem, category: "audio")

    /// Casting (Sonos, Chromecast, DLNA, AirPlay).
    static let casting  = Logger(subsystem: subsystem, category: "casting")

    /// Internet radio + library radio.
    static let radio    = Logger(subsystem: subsystem, category: "radio")

    /// Local media library (scanning, metadata, SQLite).
    static let library  = Logger(subsystem: subsystem, category: "library")

    /// Plex / Jellyfin / Emby / Subsonic server integration.
    static let server   = Logger(subsystem: subsystem, category: "server")

    /// Window management + UI lifecycle.
    static let ui       = Logger(subsystem: subsystem, category: "ui")

    /// Skin loading (both classic .wsz and modern JSON).
    static let skin     = Logger(subsystem: subsystem, category: "skin")

    /// Visualizations (ProjectM, spectrum, vis_classic).
    static let viz      = Logger(subsystem: subsystem, category: "viz")

    /// App state persistence.
    static let state    = Logger(subsystem: subsystem, category: "state")

    /// Network reachability and generic networking.
    static let network  = Logger(subsystem: subsystem, category: "network")

    /// General / uncategorized.
    static let general  = Logger(subsystem: subsystem, category: "general")

    // MARK: - NSLog-compatibility shim

    /// Drop-in replacement for `NSLog(format, args)`. Emits at `.default` level
    /// on the `general` category.
    static func legacy(_ message: String) {
        general.log("\(message, privacy: .public)")
    }
}

// MARK: - String-taking convenience wrappers
//
// `os.Logger`'s native interpolation uses `OSLogMessage`, which internally
// captures arguments via `@autoclosure` + `@escaping`. That triggers Swift's
// strict closure-capture rules — bare instance members inside `\(...)` require
// explicit `self.` prefixes.
//
// These helpers take a pre-interpolated `String` so callers can write
// `Log.audio.infoString("Playback started for \(title)")` without worrying
// about `self.` everywhere. The trade-off is loss of deferred evaluation
// (the string is built even if the log level is filtered out). For hot-path
// logging, continue to use the native `Logger` API with `self.`-qualified args.

extension Logger {
    /// Log an info-level message from a pre-built String (no implicit capture).
    func infoString(_ message: String) {
        self.info("\(message, privacy: .public)")
    }

    /// Log a notice-level message from a pre-built String (no implicit capture).
    func noticeString(_ message: String) {
        self.notice("\(message, privacy: .public)")
    }

    /// Log an error-level message from a pre-built String (no implicit capture).
    func errorString(_ message: String) {
        self.error("\(message, privacy: .public)")
    }

    /// Log a warning-level message from a pre-built String (no implicit capture).
    func warningString(_ message: String) {
        self.warning("\(message, privacy: .public)")
    }

    /// Log a debug-level message from a pre-built String (no implicit capture).
    func debugString(_ message: String) {
        self.debug("\(message, privacy: .public)")
    }
}
