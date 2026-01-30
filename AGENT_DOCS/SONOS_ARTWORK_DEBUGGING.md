# Sonos Artwork Debugging - Attempted Approaches

This document describes all approaches tried to fix Sonos artwork display when casting from AdAmp. None of these approaches worked.

## Problem Statement

When casting audio to Sonos from AdAmp, the artwork does not appear in the Sonos app, even though:
- The artwork URL is valid and accessible in a browser
- The DIDL-Lite metadata contains the `<upnp:albumArtURI>` element
- Plexamp (official Plex app) successfully displays artwork on the same Sonos speakers

## Background

The casting flow:
1. `CastManager.castTrack()` calls `getArtworkURL(for: track)` to get artwork URL
2. Creates `CastMetadata` with the artwork URL
3. `CastMetadata.toDIDLLite()` generates DIDL-Lite XML including `<upnp:albumArtURI>`
4. `UPnPManager.cast()` sends SOAP `SetAVTransportURI` with the DIDL-Lite as `CurrentURIMetaData`
5. Sonos receives the metadata but never requests the artwork URL

## Approaches Tried

### Approach 1: Fix the `findPlexTrack()` stub (Initial implementation)

**Problem**: `CastManager.findPlexTrack()` always returned `nil`, so artwork URL was never populated.

**Solution**: Added `artworkThumb` property to `Track` model and populated it from Plex/Subsonic track conversion.

**Files modified**:
- `Sources/AdAmpCore/Models/Track.swift` - Added `artworkThumb: String?` property
- `Sources/AdAmp/Data/Models/Track.swift` - Added `artworkThumb: String?` property  
- `Sources/AdAmp/Plex/PlexManager.swift` - Pass `plexTrack.thumb` to `artworkThumb` in `convertToTrack()`
- `Sources/AdAmp/Subsonic/SubsonicManager.swift` - Pass `song.coverArt` to `artworkThumb` in `convertToTrack()`
- `Sources/AdAmp/Casting/CastManager.swift` - Created `getArtworkURL(for:)` helper, removed dead `findPlexTrack()`
- `Sources/AdAmp/Audio/AudioEngine.swift` - Preserve `artworkThumb` when recreating Track

**Result**: Artwork URL now generated correctly, but still not displayed in Sonos app.

---

### Approach 2: Fix DIDL-Lite XML whitespace/formatting

**Problem**: The multiline Swift strings in `toDIDLLite()` included indentation whitespace that could confuse XML parsers.

**Solution**: Changed from multiline string literals to single-line concatenation:

```swift
// Before (with whitespace from indentation):
var didl = """
<DIDL-Lite xmlns="...">
<item id="1" parentID="0" restricted="1">
...
"""

// After (no extra whitespace):
var didl = "<DIDL-Lite xmlns=\"...\">"
didl += "<item id=\"1\" parentID=\"0\" restricted=\"1\">"
...
```

**Files modified**:
- `Sources/AdAmp/Casting/CastDevice.swift` - Rewrote `toDIDLLite()` to use string concatenation

**Result**: Fixed the spinning play button issue in Sonos app, but artwork still not displayed.

---

### Approach 3: Use simpler Plex artwork URL (direct thumb path)

**Problem**: The Plex transcode URL had multiple query parameters that get XML-escaped:
```
http://192.168.0.102:32400/photo/:/transcode?url=...&width=300&height=300&minSize=1&X-Plex-Token=...
```

When XML-escaped, all `&` become `&amp;`, potentially confusing Sonos.

**Solution**: Use direct thumb path with only the auth token:
```
http://192.168.0.102:32400/library/metadata/123/thumb/456?X-Plex-Token=...
```

**Files modified**:
- `Sources/AdAmp/Plex/PlexServerClient.swift` - Added `directArtworkURL(thumb:)` method
- `Sources/AdAmp/Plex/PlexManager.swift` - Added `directArtworkURL(thumb:)` wrapper
- `Sources/AdAmp/Casting/CastManager.swift` - Changed to use `directArtworkURL()`

**Result**: Simpler URL generated, but artwork still not displayed.

**Verification**: User confirmed the direct URL works when pasted in browser.

---

### Approach 4: Add DLNA namespace and profileID attribute

**Problem**: Some UPnP implementations require DLNA-specific attributes on albumArtURI.

**Solution**: Added DLNA namespace and profile attribute:
```xml
<DIDL-Lite xmlns="..." xmlns:dlna="urn:schemas-dlna-org:metadata-1-0/">
...
<upnp:albumArtURI dlna:profileID="JPEG_TN">http://...</upnp:albumArtURI>
```

**Files modified**:
- `Sources/AdAmp/Casting/CastDevice.swift` - Added DLNA namespace, added `dlna:profileID="JPEG_TN"` attribute

**Result**: No change, artwork still not displayed.

---

### Approach 5: Use Plex transcode endpoint with manually constructed URL

**Problem**: Maybe the direct thumb URL returns wrong image format/size.

**Solution**: Go back to transcode endpoint but build URL string manually to avoid URLComponents encoding:
```swift
let urlString = "\(baseURL)/photo/:/transcode?url=\(encodedThumb)&width=300&height=300&minSize=1&X-Plex-Token=\(authToken)"
```

**Files modified**:
- `Sources/AdAmp/Plex/PlexServerClient.swift` - Modified `directArtworkURL()` to use transcode endpoint with manual URL construction

**Result**: No change, artwork still not displayed.

---

### Approach 6: Proxy artwork through LocalMediaServer

**Problem**: Maybe Sonos has issues with complex Plex URLs or authentication.

**Solution**: Fetch artwork from Plex server, store locally, serve via LocalMediaServer with simple URL:
```
http://192.168.0.218:8765/artwork/abc123.jpg
```

No query parameters, no authentication needed for Sonos.

**Files modified**:
- `Sources/AdAmp/Casting/LocalMediaServer.swift` - Added `registerRemoteArtwork(from:)` method that:
  1. Fetches image from remote URL (Plex/Subsonic)
  2. Stores in memory with unique token
  3. Returns simple local HTTP URL
- `Sources/AdAmp/Casting/CastManager.swift` - Changed `getArtworkURL()` to proxy through LocalMediaServer

**Result**: Simple URL generated (e.g., `http://192.168.0.218:8765/artwork/6FF0DC334C3D4439.jpg`), confirmed in DIDL-Lite, but Sonos never requests it. No "Received artwork request" in logs.

---

### Approach 7: Remove DLNA profileID attribute

**Problem**: The `dlna:profileID` attribute might be causing Sonos to ignore the element.

**Solution**: Remove the attribute, use simple `<upnp:albumArtURI>url</upnp:albumArtURI>`

**Files modified**:
- `Sources/AdAmp/Casting/CastDevice.swift` - Removed `dlna:profileID` attribute

**Result**: No change, Sonos still doesn't request the artwork.

---

### Approach 8: Change element order and remove DLNA namespace

**Problem**: Maybe Sonos expects specific element ordering in DIDL-Lite.

**Solution**: 
1. Move `<upnp:albumArtURI>` BEFORE `<res>` element
2. Remove DLNA namespace entirely
3. Don't XML-escape the artwork URL (it's a simple URL)

**Files modified**:
- `Sources/AdAmp/Casting/CastDevice.swift` - Reordered elements, removed DLNA namespace

**Result**: No change, artwork still not displayed.

---

## Key Observations

1. **Artwork URL is valid**: User confirmed URLs work in browser
2. **DIDL-Lite contains albumArtURI**: Verified in logs, element is present with correct URL
3. **Sonos never requests artwork**: No HTTP request to LocalMediaServer for artwork
4. **Audio plays correctly**: Only artwork is missing
5. **Plexamp works**: Same Sonos speakers display artwork from Plexamp

## Remaining Investigation Ideas

1. **Capture Plexamp's SOAP request**: Use Wireshark/mitmproxy to see exactly what DIDL-Lite Plexamp sends
2. **Check Sonos firmware version**: Maybe artwork requires newer firmware
3. **Try different Sonos models**: User has multiple rooms, maybe some work
4. **Check if Sonos caches metadata**: Maybe old cached data without artwork
5. **Sonos-specific metadata format**: Research if Sonos uses proprietary extensions
6. **Check the SOAP request escaping**: The DIDL-Lite gets XML-escaped when embedded in SOAP - maybe double-escaping issue
7. **Try different UPnP class**: Maybe `object.item.audioItem` instead of `object.item.audioItem.musicTrack`
8. **Check res element attributes**: Maybe Sonos needs specific protocolInfo format

## Current State of Files

The following files have modifications that should be reverted:
- `Sources/AdAmp/Casting/CastDevice.swift` - DIDL-Lite generation changes
- `Sources/AdAmp/Casting/CastManager.swift` - getArtworkURL with LocalMediaServer proxy
- `Sources/AdAmp/Casting/LocalMediaServer.swift` - registerRemoteArtwork method
- `Sources/AdAmp/Plex/PlexServerClient.swift` - directArtworkURL method
- `Sources/AdAmp/Plex/PlexManager.swift` - directArtworkURL wrapper
- `Sources/AdAmp/Casting/UPnPManager.swift` - Debug logging (artworkURL, DIDL-Lite)

The following files have working changes that should be KEPT:
- `Sources/AdAmpCore/Models/Track.swift` - artworkThumb property
- `Sources/AdAmp/Data/Models/Track.swift` - artworkThumb property
- `Sources/AdAmp/Plex/PlexManager.swift` - artworkThumb in convertToTrack (KEEP this part)
- `Sources/AdAmp/Subsonic/SubsonicManager.swift` - artworkThumb in convertToTrack
- `Sources/AdAmp/Audio/AudioEngine.swift` - artworkThumb preservation
- `AGENT_DOCS/SONOS.md` - Documentation for artwork (can keep or remove)
