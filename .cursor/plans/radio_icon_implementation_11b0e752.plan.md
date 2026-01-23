---
name: Radio Icon Implementation
overview: Add the radio icon resource and implement all documented radio station types with both Sonic and Non-Sonic versions.
todos:
  - id: add-icon
    content: Copy tmp/radio.png to Sources/AdAmp/Resources/radio-icon.png
    status: pending
  - id: add-config
    content: Add RadioConfig enum with thresholds, genres, and decades constants
    status: pending
  - id: update-model
    content: Add genre, parentYear, ratingCount fields to PlexTrack model
    status: pending
  - id: add-api-methods
    content: Add radio API methods to PlexServerClient (genre, decade, hits, deep cuts - sonic and non-sonic)
    status: pending
  - id: add-manager-methods
    content: Add radio wrapper methods to PlexManager
    status: pending
  - id: update-browser-menu
    content: Update radio menu with all station types and implement handlers
    status: pending
  - id: remove-mood-stations
    content: Remove unsupported Mood stations from radio menu
    status: pending
  - id: update-docs
    content: Update PLEX_API.md with correct thresholds (250k hits, 1k deep cuts)
    status: pending
isProject: false
---

# Implement Radio Icon and All Radio Stations

## Overview

Implement all radio station types documented in [PLEX_API.md](docs/PLEX_API.md) with both **Sonic** and **Non-Sonic** versions (no fallback between them).

## Radio Menu Structure

```
Library Radio
Library Radio (Sonic)
──────────────────────────
Only the Hits
Only the Hits (Sonic)
Deep Cuts  
Deep Cuts (Sonic)
──────────────────────────
Genre Stations ►
    Rock Radio
    Rock Radio (Sonic)
    Pop Radio
    Pop Radio (Sonic)
    Hip-Hop Radio
    Hip-Hop Radio (Sonic)
    Metal Radio
    Metal Radio (Sonic)
    Jazz Radio
    Jazz Radio (Sonic)
    Classical Radio
    Classical Radio (Sonic)
    Electronic Radio
    Electronic Radio (Sonic)
    R&B Radio
    R&B Radio (Sonic)
──────────────────────────
Decade Stations ►
    1920s Radio / 1920s Radio (Sonic)
    1930s Radio / 1930s Radio (Sonic)
    1940s Radio / 1940s Radio (Sonic)
    1950s Radio / 1950s Radio (Sonic)
    1960s Radio / 1960s Radio (Sonic)
    1970s Radio / 1970s Radio (Sonic)
    1980s Radio / 1980s Radio (Sonic)
    1990s Radio / 1990s Radio (Sonic)
    2000s Radio / 2000s Radio (Sonic)
    2010s Radio / 2010s Radio (Sonic)
    2020s Radio / 2020s Radio (Sonic)
```

**Remove**: Mood stations (no Plex API support)

## Hardcoded Values

**Genres**: Rock, Pop, Hip-Hop, Metal, Jazz, Classical, Electronic, R&B

**Decades**: 1920s (1920-1929), 1930s, 1940s, 1950s, 1960s, 1970s, 1980s, 1990s, 2000s, 2010s, 2020s (2020-2029)

**Thresholds** (defined as constants for easy modification):
- Hits: 250,000+ scrobbles
- Deep Cuts: Under 1,000 scrobbles

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/AdAmp/Resources/radio-icon.png` | Add icon file |
| `Sources/AdAmp/Data/Models/PlexModels.swift` | Add genre, parentYear, ratingCount to PlexTrack |
| `Sources/AdAmp/Plex/PlexServerClient.swift` | Add radio API methods + RadioConfig |
| `Sources/AdAmp/Plex/PlexManager.swift` | Add radio wrapper methods |
| `Sources/AdAmp/Windows/PlexBrowser/PlexBrowserView.swift` | Update menu, implement handlers |

## Implementation Details

### 1. Add Radio Icon

Copy `tmp/radio.png` to `Sources/AdAmp/Resources/radio-icon.png`

### 2. Radio Configuration Constants

Add to `PlexServerClient.swift` (or a dedicated file):

```swift
/// Radio station configuration - easy to modify thresholds
enum RadioConfig {
    /// Minimum Last.fm scrobbles to qualify as a "hit"
    static let hitsThreshold = 250_000
    
    /// Maximum Last.fm scrobbles to qualify as a "deep cut"
    static let deepCutsThreshold = 1_000
    
    /// Default number of tracks to fetch for radio
    static let defaultLimit = 100
    
    /// Hardcoded genres for Genre Radio
    static let genres = ["Rock", "Pop", "Hip-Hop", "Metal", "Jazz", "Classical", "Electronic", "R&B"]
    
    /// Decade ranges for Decade Radio (start year, end year, display name)
    static let decades: [(start: Int, end: Int, name: String)] = [
        (1920, 1929, "1920s"), (1930, 1939, "1930s"), (1940, 1949, "1940s"),
        (1950, 1959, "1950s"), (1960, 1969, "1960s"), (1970, 1979, "1970s"),
        (1980, 1989, "1980s"), (1990, 1999, "1990s"), (2000, 2009, "2000s"),
        (2010, 2019, "2010s"), (2020, 2029, "2020s")
    ]
}
```

### 3. PlexServerClient API Methods

```swift
// Library Radio - Non-Sonic (random tracks, no filter)
func createLibraryRadio(libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&sort=random&limit=100

// Library Radio - Sonic (sonically similar to seed track)
func createLibraryRadioSonic(trackID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&track.sonicallySimilar={trackID}&sort=random&limit=100

// Genre Radio - Non-Sonic
func createGenreRadio(genre: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&genre={genre}&sort=random&limit=100

// Genre Radio - Sonic (requires seed track)
func createGenreRadioSonic(genre: String, trackID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&genre={genre}&track.sonicallySimilar={trackID}&sort=random&limit=100

// Decade Radio - Non-Sonic
func createDecadeRadio(startYear: Int, endYear: Int, libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&year>={start}&year<={end}&sort=random&limit=100

// Decade Radio - Sonic
func createDecadeRadioSonic(startYear: Int, endYear: Int, trackID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&year>={start}&year<={end}&track.sonicallySimilar={trackID}&sort=random&limit=100

// Only the Hits - Non-Sonic
func createHitsRadio(libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&ratingCount>=250000&sort=random&limit=100

// Only the Hits - Sonic
func createHitsRadioSonic(trackID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&ratingCount>=250000&track.sonicallySimilar={trackID}&sort=random&limit=100

// Deep Cuts - Non-Sonic
func createDeepCutsRadio(libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&ratingCount<1000&sort=random&limit=100

// Deep Cuts - Sonic
func createDeepCutsRadioSonic(trackID: String, libraryID: String, limit: Int = 100) async throws -> [PlexTrack]
// API: /library/sections/{libID}/all?type=10&ratingCount<1000&track.sonicallySimilar={trackID}&sort=random&limit=100
```

### 4. PlexManager Wrapper Methods

```swift
// Non-sonic versions (no seed needed)
func createLibraryRadio(limit: Int = 100) async -> [Track]
func createGenreRadio(genre: String, limit: Int = 100) async -> [Track]
func createDecadeRadio(startYear: Int, endYear: Int, limit: Int = 100) async -> [Track]
func createHitsRadio(limit: Int = 100) async -> [Track]
func createDeepCutsRadio(limit: Int = 100) async -> [Track]

// Sonic versions (use current playing track as seed)
func createLibraryRadioSonic(limit: Int = 100) async -> [Track]
func createGenreRadioSonic(genre: String, limit: Int = 100) async -> [Track]
func createDecadeRadioSonic(startYear: Int, endYear: Int, limit: Int = 100) async -> [Track]
func createHitsRadioSonic(limit: Int = 100) async -> [Track]
func createDeepCutsRadioSonic(limit: Int = 100) async -> [Track]
```

**Sonic Seed Selection:**
1. Get currently playing track from AudioEngine
2. If it's a Plex track with `plexRatingKey`, use that as seed
3. If no Plex track playing, pick random track from library as seed

### 5. PlexBrowserView Menu Handlers

```swift
// Example handler for non-sonic genre radio
@objc private func radioMenuGenreRadio(_ sender: NSMenuItem) {
    guard let genre = sender.representedObject as? String else { return }
    Task { @MainActor in
        let tracks = await PlexManager.shared.createGenreRadio(genre: genre)
        if !tracks.isEmpty {
            let audioEngine = WindowManager.shared.audioEngine
            audioEngine.clearPlaylist()
            audioEngine.loadTracks(tracks)
            audioEngine.play()
        }
    }
}

// Example handler for sonic genre radio
@objc private func radioMenuGenreRadioSonic(_ sender: NSMenuItem) {
    guard let genre = sender.representedObject as? String else { return }
    Task { @MainActor in
        let tracks = await PlexManager.shared.createGenreRadioSonic(genre: genre)
        if !tracks.isEmpty {
            let audioEngine = WindowManager.shared.audioEngine
            audioEngine.clearPlaylist()
            audioEngine.loadTracks(tracks)
            audioEngine.play()
        }
    }
}
```

## API Reference

| Radio Type | Non-Sonic Filter | Sonic Filter (adds) |
|------------|------------------|---------------------|
| Library | (none) | `track.sonicallySimilar={id}` |
| Hits | `ratingCount>=250000` | `&track.sonicallySimilar={id}` |
| Deep Cuts | `ratingCount<1000` | `&track.sonicallySimilar={id}` |
| Genre | `genre={name}` | `&track.sonicallySimilar={id}` |
| Decade | `year>={start}&year<={end}` | `&track.sonicallySimilar={id}` |

All queries use `type=10&sort=random&limit=100`
