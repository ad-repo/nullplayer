# Plex API for Music Radio & Playlists

This document describes the Plex API endpoints used for querying tracks and building radio/playlist features in AdAmp.

## Authentication

All requests require authentication headers:

```
X-Plex-Token: {token}
X-Plex-Client-Identifier: {unique-client-id}
X-Plex-Product: AdAmp
X-Plex-Version: 1.0
X-Plex-Platform: macOS
X-Plex-Device: Mac
Accept: application/json
```

## Core Endpoints

### Library Sections

```
GET /library/sections
```

Returns all libraries. Music libraries have `type: "artist"`.

### Query Items by Type

```
GET /library/sections/{libraryID}/all?type={typeID}
```

Type values:
| Type ID | Content |
|---------|---------|
| 8 | Artists |
| 9 | Albums |
| 10 | Tracks |

## Popular Tracks (Last.fm Integration)

Plex identifies "hit" tracks using the `ratingCount` field, which contains **global popularity data from Last.fm** - specifically, the number of unique listeners who have scrobbled the track worldwide.

| Field | Description |
|-------|-------------|
| `ratingCount` | Number of Last.fm listeners who have scrobbled the track |

**Example**: "Purple Haze" by Jimi Hendrix would have a high `ratingCount` (millions of scrobbles), while a deep cut like "Fire" from the same album might have a significantly lower count or none at all.

### Popular Tracks API

Fetch popular tracks for an artist:
```
GET /library/metadata/{artistID}/children?type=10&sort=ratingCount:desc&limit=10
```

Or use the dedicated endpoint via hubs:
```
GET /hubs/metadata/{artistID}
```

This returns various hubs including "Popular" tracks, which are sorted by `ratingCount`.

**Note**: Tracks without Last.fm match data may have no `ratingCount` value.

## Sonic Analysis (Radio Feature)

Tracks with sonic analysis have `musicAnalysisVersion: "1"` in their metadata.

### Sonically Similar Tracks (Primary Radio API)

```
GET /library/sections/{libraryID}/all?type=10&track.sonicallySimilar={trackID}&sort=random&limit=100
```

Returns tracks that are sonically similar to the seed track. Use `sort=random` for diverse results.

**Example:**
```bash
curl "http://192.168.0.102:32400/library/sections/15/all?type=10&track.sonicallySimilar=684925&sort=random&limit=20&X-Plex-Token=TOKEN" \
  -H "Accept: application/json"
```

### Sonically Similar Artists

```
GET /library/sections/{libraryID}/all?type=8&artist.sonicallySimilar={artistID}&limit=15
```

### Sonically Similar Albums

```
GET /library/sections/{libraryID}/all?type=9&album.sonicallySimilar={albumID}&limit=10
```

## Filter Parameters

### By Artist
```
?artist.id={artistID}
```

### By Genre
```
?genre={genreID}
```

### By Year/Decade
```
?year={year}
?year>=1980&year<=1989
```

### Sorting Options
```
?sort=random            # Random order (great for radio)
?sort=titleSort         # Alphabetical
?sort=lastViewedAt:desc # Recently played
?sort=addedAt:desc      # Recently added
?sort=year:desc         # By year (newest first)
?sort=year:asc          # By year (oldest first)
```

## PlayQueue API

### Create PlayQueue

```
POST /playQueues?type=audio&uri={uri}&continuous=1&includeRelated=1
```

URI formats:
- `server://{machineID}/com.plexapp.plugins.library/library/metadata/{id}`
- `library://{serverID}/item/%2Flibrary%2Fmetadata%2F{id}`

**Note:** The PlayQueue API with `continuous=1` does NOT generate radio tracks automatically. It only returns the seed track. Use the `sonicallySimilar` filter instead.

## Hubs API

### Related Content Hubs

```
GET /hubs/metadata/{itemID}
```

Returns related content hubs for an item (Most Played, Most Popular, etc.).

### Library Hubs

```
GET /hubs/sections/{libraryID}
```

Returns discovery hubs like "Recently Added", "Most Played", "By Genre".

## Complete Track API Schema

### Request

```
GET /library/metadata/{trackID}?X-Plex-Token={token}
```

### Response

```json
{
  "MediaContainer": {
    "size": 1,
    "allowSync": true,
    "identifier": "com.plexapp.plugins.library",
    "librarySectionID": 15,
    "librarySectionTitle": "AD-FLAC",
    "librarySectionUUID": "b2804406-701f-46d3-a7f4-1e1fd3a3de66",
    "mediaTagPrefix": "/system/bundle/media/flags/",
    "mediaTagVersion": 1758205129,
    "Metadata": [
      {
        "ratingKey": "684925",
        "key": "/library/metadata/684925",
        "parentRatingKey": "684924",
        "grandparentRatingKey": "684899",
        "guid": "plex://track/5d07ce55403c640290040df6",
        "parentGuid": "plex://album/5d07c241403c6402908bae3e",
        "grandparentGuid": "plex://artist/5d07bc08403c6402904aed2b",
        "parentStudio": "Def Jam Recordings",
        "type": "track",
        "title": "Stymie's Theme",
        "grandparentKey": "/library/metadata/684899",
        "parentKey": "/library/metadata/684924",
        "librarySectionTitle": "AD-FLAC",
        "librarySectionID": 15,
        "librarySectionKey": "/library/sections/15",
        "grandparentTitle": "3rd Bass",
        "parentTitle": "The Cactus Album",
        "summary": "",
        "index": 1,
        "parentIndex": 1,
        "ratingCount": 316,
        "parentYear": 1989,
        "thumb": "/library/metadata/684924/thumb/1768251359",
        "parentThumb": "/library/metadata/684924/thumb/1768251359",
        "grandparentThumb": "/library/metadata/684899/thumb/1768251357",
        "duration": 13360,
        "addedAt": 1723508508,
        "updatedAt": 1768251359,
        "musicAnalysisVersion": "1",
        "Genre": [
          {
            "id": 12345,
            "filter": "genre=12345",
            "tag": "Hip-Hop"
          }
        ],
        "Guid": [
          {
            "id": "mbid://recording/abc123"
          }
        ],
        "Media": [
          {
            "id": 621630,
            "duration": 13360,
            "bitrate": 716,
            "audioChannels": 2,
            "audioCodec": "flac",
            "container": "flac",
            "hasVoiceActivity": false,
            "Part": [
              {
                "id": 653835,
                "key": "/library/parts/653835/1723508508/file.flac",
                "duration": 13360,
                "file": "/AD-FLAC/3rd Bass/The Cactus Album/01 - Stymie's Theme.flac",
                "size": 1204003,
                "container": "flac",
                "Stream": [
                  {
                    "id": 1050752,
                    "streamType": 2,
                    "selected": true,
                    "codec": "flac",
                    "index": 0,
                    "channels": 2,
                    "bitrate": 716,
                    "albumGain": "-3.23",
                    "albumPeak": "0.977234",
                    "albumRange": "4.090978",
                    "audioChannelLayout": "stereo",
                    "bitDepth": 16,
                    "gain": "-3.23",
                    "loudness": "-14.77",
                    "lra": "16.19",
                    "peak": "0.489227",
                    "samplingRate": 44100,
                    "displayTitle": "FLAC (Stereo)",
                    "extendedDisplayTitle": "FLAC (Stereo)"
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  }
}
```

### Key Track Fields

| Field | Description |
|-------|-------------|
| `ratingKey` | Unique track ID |
| `key` | API path to track metadata |
| `title` | Track title |
| `grandparentTitle` | Artist name |
| `parentTitle` | Album name |
| `grandparentKey` | API path to artist |
| `parentKey` | API path to album |
| `duration` | Duration in milliseconds |
| `index` | Track number on album |
| `parentIndex` | Disc number |
| `parentYear` | Album release year |
| `thumb` | Album art URL (relative) |
| `addedAt` | Unix timestamp when added |
| `musicAnalysisVersion` | Present if sonically analyzed |
| `ratingCount` | Global popularity from Last.fm (scrobble count) - used to identify "hit" tracks |
| `userRating` | User's personal star rating (0-10 scale, where 10 = 5 stars) - used for rating-based radio |
| `Media[].Part[].key` | Streaming URL path |
| `Media[].Part[].file` | Original file path on server |
| `Media[].audioCodec` | Audio format (flac, mp3, etc.) |
| `Media[].bitrate` | Bitrate in kbps |

### Stream Fields (Audio Analysis)

| Field | Description |
|-------|-------------|
| `gain` | ReplayGain value |
| `peak` | Peak amplitude |
| `loudness` | LUFS loudness measurement |
| `lra` | Loudness range |
| `albumGain` | Album-level ReplayGain |
| `albumPeak` | Album-level peak |

## Building Streaming URLs

```
{baseURL}{Media.Part.key}?X-Plex-Token={token}
```

Example:
```
http://192.168.0.102:32400/library/parts/653835/1723508508/file.flac?X-Plex-Token=TOKEN
```

## Radio Implementation Strategy

### Seed Selection

**Radio Selector UI** (menu-based radio selection):
- Uses the **currently playing track** as the seed
- If no track is playing, select a **random track** from the library and start playback

**Right-click Context Menu**:
- Track Radio uses the **clicked track** as the seed (unchanged)

### Track Radio
1. Use `track.sonicallySimilar={trackID}` with `sort=random`
2. Returns diverse tracks based on sonic fingerprint analysis

### Artist Radio
1. Get similar artists: `artist.sonicallySimilar={artistID}`
2. For each similar artist, fetch random tracks: `artist.id={id}&sort=random`
3. Shuffle combined results

### Album Radio
1. Get similar albums: `album.sonicallySimilar={albumID}`
2. Fetch tracks from each similar album
3. Shuffle combined results

### Only the Hits Radio
Plays only popular/hit tracks based on Last.fm scrobble data.

**Threshold**: 1,000,000+ scrobbles (configurable in `RadioConfig.hitsThreshold`)

**Sonic Version** - Sonically similar hits:
```
GET /library/sections/{libID}/all?type=10&track.sonicallySimilar={trackID}&ratingCount>=1000000&sort=random&limit=100
```

**Non-Sonic Version** - All hits from library:
```
GET /library/sections/{libID}/all?type=10&ratingCount>=1000000&sort=random&limit=100
```

### Deep Cuts Radio
Plays lesser-known tracks, excluding popular hits.

**Threshold**: Under 1,000 scrobbles (configurable in `RadioConfig.deepCutsThreshold`)

**Sonic Version** - Sonically similar deep cuts:
```
GET /library/sections/{libID}/all?type=10&track.sonicallySimilar={trackID}&ratingCount<=999&sort=random&limit=100
```

**Non-Sonic Version** - All deep cuts from library:
```
GET /library/sections/{libID}/all?type=10&ratingCount<=999&sort=random&limit=100
```

**Note**: Tracks without Last.fm data have no `ratingCount` field - these are considered "deep cuts" but should only be included if they have proper metadata (artist, album, title). Exclude tracks missing basic tags as they are likely poorly tagged files, not legitimate deep cuts.

### Genre Radio
Plays tracks from the same genre as the current track.

**Seed Selection**: Uses the genre(s) of the currently playing track. If no track is playing, select a random track from the library and use its genre.

**Sonic Version** - Sonically similar tracks in the same genre:
```
GET /library/sections/{libID}/all?type=10&track.sonicallySimilar={trackID}&genre={genreID}&sort=random&limit=100
```

**Non-Sonic Version** - All tracks from the genre:
```
GET /library/sections/{libID}/all?type=10&genre={genreID}&sort=random&limit=100
```

### Decade Radio
Plays tracks from a specific decade.

**Available Decades**: 1920s, 1930s, 1940s, 1950s, 1960s, 1970s, 1980s, 1990s, 2000s, 2010s, 2020s (configurable in `RadioConfig.decades`)

**Sonic Version** - Sonically similar tracks from the same decade:
```
GET /library/sections/{libID}/all?type=10&track.sonicallySimilar={trackID}&year>=1980&year<=1989&sort=random&limit=100
```

**Non-Sonic Version** - All tracks from the decade:
```
GET /library/sections/{libID}/all?type=10&year>=1980&year<=1989&sort=random&limit=100
```

### Library Radio
Plays random tracks from the entire library.

**Sonic Version** - Sonically similar to seed track:
```
GET /library/sections/{libID}/all?type=10&track.sonicallySimilar={trackID}&sort=random&limit=100
```

**Non-Sonic Version** - Random tracks from library:
```
GET /library/sections/{libID}/all?type=10&sort=random&limit=100
```

### Rating Radio (My Ratings)
Plays tracks based on the user's personal star ratings. Users can select from multiple rating thresholds:

| Station | Min Rating | Description |
|---------|------------|-------------|
| 5 Stars Radio | 10 (5★) | Only tracks rated exactly 5 stars |
| 4+ Stars Radio | 8 (4★+) | Highly rated tracks (4-5 stars) |
| 3+ Stars Radio | 6 (3★+) | Good tracks (3-5 stars) |
| 2+ Stars Radio | 4 (2★+) | Any track rated 2 stars or higher |
| All Rated Radio | 0.1 | Any track with a rating |

**Note**: Plex stores ratings on a 0-10 scale internally (10 = 5 stars, 8 = 4 stars, etc.)

**Sonic Version** - Sonically similar rated tracks:
```http
GET /library/sections/{libID}/all?type=10&track.sonicallySimilar={trackID}&userRating>=8&sort=random&limit=100
```

**Non-Sonic Version** - All rated tracks at threshold:
```http
GET /library/sections/{libID}/all?type=10&userRating>=8&sort=random&limit=100
```

### URL Encoding Warning

**IMPORTANT**: Plex filter operators (`>=`, `<=`, `=`, `!=`) must NOT be URL-encoded in query parameters.

- **WRONG**: `userRating%3E%3D=8` (URLQueryItem encodes `>=` as `%3E%3D`)
- **CORRECT**: `userRating>=8` (literal `>=` in the URL)

**Note**: Plex only supports these comparison operators: `>=`, `<=`, `=`, `!=`. The `<` and `>` operators (without equals) are NOT supported and will return HTTP 400 errors. Use `<=` with value-1 instead of `<` (e.g., `ratingCount<=999` instead of `ratingCount<1000`).

When using Swift's `URLQueryItem`, it will incorrectly encode the operator. Build URLs manually for filter parameters:
```swift
// WRONG - URLQueryItem encodes >=
URLQueryItem(name: "userRating>=", value: "8")  // produces userRating%3E%3D=8

// CORRECT - manual URL construction
let urlString = "\(baseURL)/library/sections/\(id)/all?type=10&userRating>=8&..."
```

This applies to all filter operators: `>=`, `<=`, `=`, `!=`

## Configuration

Radio station thresholds are defined in `RadioConfig` enum (`PlexServerClient.swift`):

| Setting | Value | Description |
|---------|-------|-------------|
| `hitsThreshold` | 1,000,000 | Minimum Last.fm scrobbles for "hits" |
| `deepCutsThreshold` | 1,000 | Maximum Last.fm scrobbles for "deep cuts" |
| `defaultLimit` | 100 | Default number of tracks per radio station |
| `maxTracksPerArtist` | 2 | Maximum tracks per artist for variety (1 for Sonic) |
| `overFetchMultiplier` | 3 | Multiplier for over-fetching to allow deduplication |
| `fallbackGenres` | Pop/Rock, Jazz, Classical, Electronic, R&B, Rap, Country, Blues | Fallback if genre fetch fails |
| `decades` | 1920s-2020s | Available decade stations |
| `ratingStations` | 5★, 4+★, 3+★, 2+★, All Rated | Available user rating thresholds |

### Dynamic Genre Fetching

Genres are fetched dynamically from the Plex library via:
```
GET /library/sections/{libID}/genre
```

This ensures genre names match the actual tags in your library (e.g., "Pop/Rock" instead of "Rock").

### Artist Variety Filter

Radio playlists automatically limit duplicate artists for better variety. The system:
1. Fetches 3x the requested tracks (`overFetchMultiplier`)
2. Filters to allow max 2 tracks per artist (1 for Sonic stations)
3. Spreads same-artist tracks apart to avoid back-to-back plays
4. Returns the requested number of tracks with diverse artists

This prevents radio stations from being dominated by a few prolific artists.

## Video Content (Movies & TV Shows)

### Fetching Movies

```
GET /library/sections/{libraryID}/all?type=1
```

Type 1 = movies. Returns all movies in the library.

### Fetching TV Shows

```
GET /library/sections/{libraryID}/all?type=2
```

Type 2 = shows. Returns all TV shows in the library.

### Multi-Version Movies

Movies may contain multiple media versions (different qualities, bonus content, etc.):

```json
{
  "title": "Movie Name",
  "duration": 273472,  // WARNING: May be from first media, not primary!
  "Media": [
    {"id": 1, "duration": 273472, "Part": [{"file": "/video/Bonus.mkv"}]},
    {"id": 2, "duration": 5820000, "Part": [{"file": "/video/Movie.mkv"}]}
  ]
}
```

**Important**: The top-level `duration` field may point to bonus content, not the main movie. AdAmp uses the **longest duration** from the `Media` array to identify the primary content.

### Bonus Content Filtering

Plex may misclassify bonus content (trailers, extras) as separate entries:
- Bonus files in movie folders may appear as short movies
- Numbered bonus files may appear as TV show episodes

AdAmp filters these by:
- Using the longest media entry for movie duration/playback
- Filtering TV shows with ≤1 season AND ≤2 episodes (likely bonus content)

### External IDs (IMDB, TMDB, TVDB)

Movies, TV shows, and episodes include external service IDs in the `Guid` array:

```json
{
  "title": "The Matrix",
  "Guid": [
    {"id": "imdb://tt0133093"},
    {"id": "tmdb://603"},
    {"id": "tvdb://12345"}
  ]
}
```

| Service | URL Pattern | Used For |
|---------|-------------|----------|
| IMDB | `https://www.imdb.com/title/{id}/` | Movies, Shows, Episodes |
| TMDB | `https://www.themoviedb.org/movie/{id}` | Movies |
| TMDB | `https://www.themoviedb.org/tv/{id}` | TV Shows |
| TVDB | `https://www.thetvdb.com/series/{id}` | TV Shows |

AdAmp uses these IDs to provide "View Online" context menu links for IMDB, TMDB, and Rotten Tomatoes (search).

## Setting User Ratings

### Rate an Item

```
PUT /:/rate?key={ratingKey}&identifier=com.plexapp.plugins.library&rating={rating}
```

| Parameter | Description |
|-----------|-------------|
| key | The item's ratingKey |
| identifier | Always `com.plexapp.plugins.library` |
| rating | 0-10 scale (2 per star), or -1 to clear |

**HTTP Method**: PUT

**Response**: HTTP 200 with empty body on success

**Rating Scale**:
- 2 = 1 star (★☆☆☆☆)
- 4 = 2 stars (★★☆☆☆)
- 6 = 3 stars (★★★☆☆)
- 8 = 4 stars (★★★★☆)
- 10 = 5 stars (★★★★★)
- -1 = Clear rating

**Side Effects**: Updates `userRating` and `lastRatedAt` fields in track metadata.

### Test Script

Run `scripts/test_plex_rate.swift` to validate the API:

```bash
PLEX_URL=http://192.168.1.x:32400 PLEX_TOKEN=xxx swift scripts/test_plex_rate.swift
```

## Requirements

- **Plex Pass** subscription (for sonic analysis)
- **Plex Media Server v1.24.0+** (64-bit)
- **Sonic analysis enabled** on the music library
- Tracks must be analyzed (check for `musicAnalysisVersion` attribute)

## References

- [Python PlexAPI](https://github.com/pkkid/python-plexapi)
- [Plex API Documentation](https://plexapi.dev/)
- [Plex Support - Sonic Analysis](https://support.plex.tv/articles/sonic-analysis-music/)
