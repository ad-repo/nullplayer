# Dead Code Analysis

This document lists potentially unused code identified for review and possible removal.

---

## 1. Unused Debug Function

**File:** `Sources/AdAmp/Audio/AudioOutputManager.swift`  
**Lines:** 387-446

```swift
func printDeviceDebugInfo() {
    // ... prints debug info to console
    print("=== Audio Device Debug Info ===")
    // ...
    print("=== End Debug Info ===")
}
```

**Status:** Never called anywhere in the codebase.  
**Recommendation:** Remove if not needed for manual debugging.

---

## 2. Debug Print Statements

**File:** `Sources/AdAmp/Windows/Playlist/PlaylistView.swift`  
**Lines:** 948-953

```swift
print(">>> STOP BUTTON PRESSED <<<")
// ...
print(">>> Calling engine.stop() <<<")
```

**Status:** Leftover debugging code.  
**Recommendation:** Remove these debug prints.

---

## 3. Unused `SliderDragTracker` Class

**File:** `Sources/AdAmp/Skin/SkinRegion.swift`  
**Lines:** 508-553

```swift
class SliderDragTracker {
    var isDragging = false
    var sliderType: SliderType?
    var startValue: CGFloat = 0
    var startPoint: NSPoint = .zero
    
    func beginDrag(slider: SliderType, at point: NSPoint, currentValue: CGFloat) { ... }
    func updateDrag(to point: NSPoint, in rect: NSRect) -> CGFloat { ... }
    func endDrag() { ... }
}
```

**Status:** Class is defined but never instantiated.  
**Recommendation:** Remove entirely.

---

## 4. Unused `VideoTitleBarView` Class

**File:** `Sources/AdAmp/Windows/VideoPlayer/VideoPlayerView.swift`  
**Lines:** 1020-1183

```swift
class VideoTitleBarView: NSView {
    var title: String = ""
    var isWindowActive: Bool = true
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    // ... ~164 lines of implementation
}
```

**Status:** Class is defined but never instantiated or used.  
**Recommendation:** Remove entirely.

---

## 5. Unused `LibraryFilter` Struct and `filteredTracks` Function

**File:** `Sources/AdAmp/Data/Models/MediaLibrary.swift`

### LibraryFilter (Lines 169-179)
```swift
struct LibraryFilter: Codable {
    var searchText: String = ""
    var artists: Set<String> = []
    var albums: Set<String> = []
    var genres: Set<String> = []
    var yearRange: ClosedRange<Int>?
    
    var isEmpty: Bool { ... }
}
```

### filteredTracks Function (Lines 476-549)
```swift
func filteredTracks(filter: LibraryFilter, sortBy: LibrarySortOption, ascending: Bool = true) -> [LibraryTrack] {
    // ... ~70 lines of filtering logic
}
```

**Status:** Both are defined but never used. The library uses simpler search methods (`searchTracks(query:)`) instead.  
**Recommendation:** Remove both.

---

## 6. Unused `hexString` Property

**File:** `Sources/AdAmp/Skin/Skin.swift`  
**Lines:** 176-182

```swift
extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

**Status:** Only used in unit tests (`AdAmpTests.swift`), not in production code.  
**Recommendation:** Keep if useful for debugging/testing, otherwise remove.

---

## 7. Unused `FlexibleDouble` Struct

**File:** `Sources/AdAmp/Data/Models/PlexModels.swift`  
**Lines:** 29-48

```swift
/// A type that can decode either a String or a numeric value into a Double
/// Used for Plex fields that inconsistently return strings vs numbers (like frameRate)
struct FlexibleDouble: Codable, Equatable {
    let value: Double?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let intValue = try? container.decode(Int.self) {
            value = Double(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            value = Double(stringValue)
        } else {
            value = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
```

**Status:** Struct defined but never used as a type anywhere. Similar `FlexibleString` IS used for `frameRate` decoding.  
**Recommendation:** Remove entirely.

---

## Summary

| Item | File | Lines | Severity |
|------|------|-------|----------|
| `printDeviceDebugInfo()` | AudioOutputManager.swift | 387-446 | Low |
| Debug prints | PlaylistView.swift | 948-953 | Low |
| `SliderDragTracker` | SkinRegion.swift | 508-553 | Medium |
| `VideoTitleBarView` | VideoPlayerView.swift | 1020-1183 | Medium |
| `LibraryFilter` + `filteredTracks` | MediaLibrary.swift | 169-179, 476-549 | Medium |
| `hexString` | Skin.swift | 176-182 | Low |
| `FlexibleDouble` | PlexModels.swift | 29-48 | Low |

**Estimated removable lines:** ~380 lines

---

## Unimplemented TODO Comments

These TODO comments indicate incomplete functionality that may warrant attention:

| File | Line | Description |
|------|------|-------------|
| PlexBrowserView.swift | 7584 | `// TODO: Build local playlist items` |
| PlexBrowserView.swift | 7680 | `// TODO: Implement Subsonic search` |
| PlexBrowserView.swift | 8169 | `// TODO: Build local playlist items` |
| PlexBrowserView.swift | 8183 | `displayItems = [] // TODO: Implement Subsonic search` |
| SkinLoader.swift | 464 | `// TODO: Implement .cur/.ani file parsing` |

---

*Last updated: 2026-01-24*
