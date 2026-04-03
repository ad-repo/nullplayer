---
name: testing
description: UI testing mode, accessibility identifiers, and testing workflows. Use when writing tests, adding testable UI elements, or understanding test structure and philosophy.
---

# Testing Guide

This document defines the testing philosophy, standards, and practices for NullPlayer.

## Quick Start

```bash
# Run all unit tests
swift test

# Run a specific test
swift test --filter "testTrackCreation"

# List all available tests
swift test list
```

## Core Principles

### 1. Never Modify Code to Pass Tests

Tests exist to validate code correctness. If a test fails:

- **DO**: Fix the bug in the application code
- **DO**: Report to the user if the fix is beyond scope
- **DO NOT**: Modify application code solely to make a test pass
- **DO NOT**: Add workarounds or special cases just for testing

### 2. Never Dumb Down Tests

Tests must remain rigorous and realistic:

- **DO**: Write tests that reflect real user behavior and edge cases
- **DO**: Maintain strict assertions that catch actual bugs
- **DO NOT**: Weaken assertions to make tests pass
- **DO NOT**: Remove test cases because they're "too hard" to satisfy
- **DO NOT**: Use overly generous timeouts to mask flaky behavior

### 3. Quality Over Quantity

A smaller suite of thorough tests is more valuable than extensive shallow coverage:

- **DO**: Test meaningful behavior and business logic
- **DO**: Cover edge cases, error handling, and boundary conditions
- **DO NOT**: Write tests just to increase coverage numbers
- **DO NOT**: Test trivial getters/setters
- **DO NOT**: Duplicate test logic

### 4. Target 95% Code Coverage

- Focus on critical paths: audio playback, playlist management, UI interactions
- Cover error handling and edge cases
- The remaining 5% should be genuinely untestable code

### 5. End-to-End Tests Must Be Realistic

- **DO**: Use real UI interactions (clicks, keyboard input, drag-drop)
- **DO**: Test complete user workflows from start to finish
- **DO**: Test with actual audio files and real playback
- **DO NOT**: Mock core functionality in E2E tests
- **DO NOT**: Use artificial shortcuts that bypass normal code paths

## Test Structure

```
Tests/
├── NullPlayerCoreTests/       # Unit tests for NullPlayerCore target - run with swift test
│   └── EQConfigurationTests.swift
├── NullPlayerAppTests/        # Unit tests for NullPlayer app target - run with swift test
│   ├── AudioEngineShuffleTests.swift
│   └── RadioRequestConstructionTests.swift
└── NullPlayerUITests/         # UI tests - run with xcodebuild
    ├── NullPlayerUITestCase.swift      # Base test class
    ├── Helpers/
    │   ├── AccessibilityIdentifiers.swift
    │   └── TestHelpers.swift
    └── ... (UI test files)
```

### Unit Test Coverage

| Module | Tests | Coverage |
|--------|-------|----------|
| Track model | 12 | Display title, duration, equality |
| Playlist model | 9 | CRUD, M3U export |
| EQPreset model | 7 | Presets, Codable |
| LibraryTrack model | 6 | Properties, conversion |
| Album/Artist models | 7 | Properties, duration |
| PlexModels | 22 | All Plex data types |
| Casting models | 13 | CastDevice, CastMetadata, errors |
| Skin/SkinElements | 45 | Sprites, dimensions, fonts |
| PlayerAction/Region | 20 | Actions, clickable regions |
| BMPParser | 4 | Parsing, validation |
| NSColor extension | 9 | Hex conversion |
| Audio models | 6 | AudioOutputDevice |
| Other | 17 | Various utility tests |

## UI Tests

Location: `Tests/NullPlayerUITests/`

UI tests use Apple's XCUITest framework. Tests are consolidated to minimize app launches (the main bottleneck) - each test class has only 2-3 test methods covering multiple related features.

**Test Classes:**

| Class | Tests | Coverage |
|-------|-------|----------|
| `MainWindowTests` | 2 | Transport controls, sliders, toggles, keyboard shortcuts, drag, context menu |
| `PlaylistTests` | 2 | Window, buttons, keyboard shortcuts, scrolling, drag, context menu |
| `EqualizerTests` | 2 | On/off toggle, presets, sliders, drag, context menu, shade mode |
| `PlexBrowserTests` | 2 | Tabs, content, scrolling, drag, resize, context menu, shade mode |
| `VisualizationTests` | 2 | Preset navigation, fullscreen, hard cuts, drag, resize, context menu, shade mode |
| `IntegrationTests` | 3 | Multi-window workflows, docking, keyboard shortcuts, toggle persistence |

**Example Test:**

```swift
func testPlayPauseToggle() {
    let playButton = app.buttons["mainWindow.playButton"]
    playButton.tap()
    XCTAssertTrue(app.buttons["mainWindow.pauseButton"].waitForExistence(timeout: 2))
}
```

**Accessibility Identifiers:**

UI tests locate elements using accessibility identifiers defined in:
- `Tests/NullPlayerUITests/Helpers/AccessibilityIdentifiers.swift`

And set in source views:
- `Sources/NullPlayer/Windows/MainWindow/MainWindowView.swift`
- `Sources/NullPlayer/Windows/Playlist/PlaylistView.swift`
- `Sources/NullPlayer/Windows/Equalizer/EQView.swift`
- `Sources/NullPlayer/Windows/PlexBrowser/PlexBrowserView.swift`
- `Sources/NullPlayer/Windows/ProjectM/ProjectMView.swift`

**Custom Drawn UI:**

Since NullPlayer uses Winamp skins with custom drawing, accessibility elements are exposed via `accessibilityChildren()` override rather than standard AppKit controls.

## UI Testing Mode

When running UI tests, the app launches with `--ui-testing` argument which:
- Skips Plex server auto-connection
- Skips intro sound playback
- Uses default skin for consistent test results
- Disables network-dependent features

This is handled in `AppDelegate.swift`:

```swift
if CommandLine.arguments.contains("--ui-testing") {
    setupUITestingMode()
    return
}
```

## Running Tests

### Local Development

```bash
# Run all tests
xcodebuild test -scheme NullPlayer -destination 'platform=macOS'

# Run unit tests only
xcodebuild test -scheme NullPlayer -destination 'platform=macOS' -only-testing:NullPlayerTests

# Run UI tests only
xcodebuild test -scheme NullPlayer -destination 'platform=macOS' -only-testing:NullPlayerUITests

# Run with coverage
xcodebuild test -scheme NullPlayer -enableCodeCoverage YES

# View coverage report
xcrun xccov view --report ~/Library/Developer/Xcode/DerivedData/nullplayer-*/Logs/Test/*.xcresult
```

## Local Library Regression Checklist

See `skills/local-library/SKILL.md` — Testing section.

## Writing Good Tests

### Test Structure

Follow the Arrange-Act-Assert pattern:

```swift
func testSeekUpdatesPosition() {
    // Arrange
    loadTestTrack()
    app.buttons["mainWindow.playButton"].tap()
    
    // Act
    let seekSlider = app.sliders["mainWindow.seekSlider"]
    seekSlider.adjust(toNormalizedSliderPosition: 0.5)
    
    // Assert
    let timeLabel = app.staticTexts["mainWindow.currentTime"]
    XCTAssertTrue(timeLabel.label.contains("1:30"))  // Half of 3:00 track
}
```

### Naming Conventions

Test names should describe the scenario and expected outcome:

```swift
// Good
func testPlaylistRemoveTrack_updatesCount()
func testSeekBeyondDuration_clampsToEnd()
func testPlexConnection_withInvalidToken_showsError()

// Bad
func testRemove()
func testSeek()
func test1()
```

### Assertions

Use specific assertions with clear failure messages:

```swift
// Good
XCTAssertEqual(playlist.tracks.count, 5, "Playlist should have 5 tracks after adding")
XCTAssertTrue(playButton.isEnabled, "Play button should be enabled when tracks are loaded")

// Bad
XCTAssert(playlist.tracks.count == 5)
XCTAssertTrue(playButton.isEnabled)
```

### Handling Async Operations

Use explicit waits, not arbitrary delays:

```swift
// Good
let playingIndicator = app.images["mainWindow.playingIndicator"]
XCTAssertTrue(playingIndicator.waitForExistence(timeout: 5))

// Bad
sleep(5)
XCTAssertTrue(playingIndicator.exists)
```

## Test Data and Fixtures

Test audio files are located in `Tests/Fixtures/`:
- `test-short.mp3` - 5 second silence for quick tests
- `test-3min.mp3` - 3 minute track for seek tests
- `test-metadata.mp3` - File with full ID3 tags

## Reporting Test Issues

When a test fails and cannot be fixed:

1. **Document the issue**: Add a comment explaining what's broken
2. **Skip with reason**: Use `XCTSkip("Reason")` with clear explanation
3. **Create an issue**: Link to a GitHub issue tracking the bug
4. **Inform the user**: If discovered during development, report the limitation

```swift
func testFeatureThatIsBroken() throws {
    throw XCTSkip("Skipped: Issue #123 - Audio seeking fails near track end")
}
```

## Coverage Requirements

| Category | Target | Current | Notes |
|----------|--------|---------|-------|
| Models | 95%+ | ~80% | Core data structures |
| Utilities | 90%+ | ~60% | Parsers, helpers |
| Skin elements | 80%+ | ~70% | Sprite coordinates, layouts |
| Audio Engine | 90%+ | N/A | Requires hardware/runtime |
| UI Views | 85%+ | N/A | Requires running app |
| Plex Integration | 80%+ | N/A | Network-dependent code |

### Coverage Notes

**Testable with unit tests:**
- Models (Track, Playlist, EQPreset, PlexModels, etc.)
- Pure utility functions (BMPParser, color conversion)
- Static data structures (SkinElements, regions)
- Data transformations

**Requires integration/UI tests:**
- Audio playback (AudioEngine, StreamingAudioPlayer)
- UI rendering (NSView subclasses, window controllers)
- Network operations (PlexServerClient, PlexAuthClient)
- System integration (AudioOutputManager, CoreAudio)
