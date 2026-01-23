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

### Genre Radio (Future)
```
GET /library/sections/{libID}/all?type=10&genre={genreID}&sort=random&limit=100
```

### Decade Radio (Future)
```
GET /library/sections/{libID}/all?type=10&year>=1980&year<=1989&sort=random&limit=100
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
