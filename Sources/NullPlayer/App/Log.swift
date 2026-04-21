//
//  Log.swift
//  NullPlayer
//
//  Structured logging infrastructure using os.Logger.
//
//  Usage:
//      Log.audio.info("Playback started for \(url.lastPathComponent)")
//      Log.audio.error("Failed to create reader: \(error)")
//
//  Each subsystem logger appears as a separate category in Console.app,
//  making it easy to filter by area.  The subsystem is always
//  "com.nullplayer.app" (matching CFBundleIdentifier).
//
//  Privacy:
//      os.Logger redacts interpolated values in release builds by
//      default.  Use `\(value, privacy: .public)` only for data that
//      is safe to log in user-submitted diagnostics (e.g., enum names,
//      file extensions, error descriptions).  NEVER mark usernames,
//      file paths, device UIDs, or auth tokens as public.
//

import os

/// Centralized loggers, one per subsystem area.
///
/// Add new categories here as the codebase grows.  Prefer a small
/// number of coarse categories over per-file loggers — Console.app
/// filtering by category works best with ~10–20 categories.
enum Log {

    private static let subsystem = "com.nullplayer.app"

    // MARK: - Audio pipeline

    /// Audio engine, playback, decoding, gapless, crossfade.
    static let audio = Logger(subsystem: subsystem, category: "audio")

    /// Audio output device selection, routing, AirPlay.
    static let audioOutput = Logger(subsystem: subsystem, category: "audioOutput")

    /// Equalizer, DSP, normalization.
    static let eq = Logger(subsystem: subsystem, category: "eq")

    // MARK: - Media library

    /// Local media library scanning, indexing, metadata.
    static let library = Logger(subsystem: subsystem, category: "library")

    /// Waveform generation and caching.
    static let waveform = Logger(subsystem: subsystem, category: "waveform")

    // MARK: - Network / media servers

    /// Plex server communication.
    static let plex = Logger(subsystem: subsystem, category: "plex")

    /// Jellyfin server communication.
    static let jellyfin = Logger(subsystem: subsystem, category: "jellyfin")

    /// Emby server communication.
    static let emby = Logger(subsystem: subsystem, category: "emby")

    /// Subsonic / OpenSubsonic server communication.
    static let subsonic = Logger(subsystem: subsystem, category: "subsonic")

    /// Internet radio streaming.
    static let radio = Logger(subsystem: subsystem, category: "radio")

    // MARK: - Casting

    /// UPnP / DLNA / Chromecast / AirPlay casting.
    static let casting = Logger(subsystem: subsystem, category: "casting")

    // MARK: - UI

    /// Window management, layout, skin loading.
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Visualization (spectrum, waveform display, ProjectM, shaders).
    static let vis = Logger(subsystem: subsystem, category: "vis")

    /// Modern and classic skin rendering.
    static let skin = Logger(subsystem: subsystem, category: "skin")

    // MARK: - General

    /// App lifecycle, updates, general diagnostics.
    static let general = Logger(subsystem: subsystem, category: "general")
}
