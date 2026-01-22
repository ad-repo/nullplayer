# Testing Guide

This document defines the testing philosophy, standards, and practices for AdAmp.

## Quick Start

```bash
# Recommended: Run tests with swift test
# First ensure projectM library is available in the build directory:
cp .build/arm64-apple-macosx/Frameworks/libprojectM-4.4.dylib \
   .build/arm64-apple-macosx/debug/

# Run all unit tests (177 tests)
swift test

# Run a specific test
swift test --filter "testTrackCreation"

# List all available tests
swift test list
```

### Alternative: xcodebuild

```bash
# Copy library to DerivedData (required after clean builds)
cp .build/arm64-apple-macosx/Frameworks/libprojectM-4.4.dylib \
   ~/Library/Developer/Xcode/DerivedData/adamp-*/Build/Products/Debug/

# Run all tests
xcodebuild test -scheme AdAmp -destination 'platform=macOS'

# Run with coverage
xcodebuild test -scheme AdAmp -enableCodeCoverage YES
```

**Note:** The `libprojectM-4.4.dylib` library must be in the build directory for tests to run. The library is built by the bootstrap script and located at `.build/arm64-apple-macosx/Frameworks/`.

## Test Structure

```
Tests/
├── AdAmpTests/           # Unit tests (177 tests)
│   └── AdAmpTests.swift  # All unit tests in single file
└── AdAmpUITests.disabled/ # UI tests (disabled - require app running)
    ├── AdAmpUITestCase.swift      # Base test class
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

## Core Principles

### 1. Never Modify Code to Pass Tests

Tests exist to validate code correctness. If a test fails:

- **DO**: Fix the bug in the application code
- **DO**: Report to the user if the fix is beyond scope or requires architectural changes
- **DO NOT**: Modify application code solely to make a test pass
- **DO NOT**: Add workarounds, flags, or special cases just for testing

If a test reveals unexpected behavior, that behavior should be investigated and fixed properly, not accommodated.

### 2. Never Dumb Down Tests

Tests must remain rigorous and realistic:

- **DO**: Write tests that reflect real user behavior and edge cases
- **DO**: Maintain strict assertions that catch actual bugs
- **DO**: Report to the user when a test cannot pass due to a genuine application issue
- **DO NOT**: Weaken assertions to make tests pass
- **DO NOT**: Remove test cases because they're "too hard" to satisfy
- **DO NOT**: Use overly generous timeouts or retry logic to mask flaky behavior

If a test consistently fails, the options are:
1. Fix the underlying bug
2. Document the known issue and skip the test with explanation
3. Inform the user that the feature doesn't work as expected

### 3. Quality Over Quantity

A smaller suite of thorough, well-designed tests is more valuable than extensive shallow coverage:

- **DO**: Test meaningful behavior and business logic
- **DO**: Cover edge cases, error handling, and boundary conditions
- **DO**: Write tests that are readable and serve as documentation
- **DO NOT**: Write tests just to increase coverage numbers
- **DO NOT**: Test trivial getters/setters or obvious code paths
- **DO NOT**: Duplicate test logic across multiple test cases

### 4. Target 95% Code Coverage

Aim for 95% code coverage with these guidelines:

- Focus on critical paths: audio playback, playlist management, UI interactions
- Cover error handling and edge cases
- The remaining 5% should be genuinely untestable code (platform-specific callbacks, etc.)
- Coverage metrics are a guide, not a goal—meaningful coverage matters more than percentages

### 5. End-to-End Tests Must Be Realistic

E2E tests should simulate real user behavior as closely as possible:

- **DO**: Use real UI interactions (clicks, keyboard input, drag-drop)
- **DO**: Test complete user workflows from start to finish
- **DO**: Include realistic timing and wait conditions
- **DO**: Test with actual audio files and real playback
- **DO NOT**: Mock core functionality in E2E tests
- **DO NOT**: Use artificial shortcuts that bypass normal code paths
- **DO NOT**: Skip setup/teardown steps that users would experience

---

## Test Categories

### Unit Tests

Location: `Tests/AdAmpTests/`

Test individual components in isolation:
- Models (Track, Playlist, EQPreset)
- Parsers (BMP, skin files)
- Utility functions
- Business logic

```swift
func testTrackDisplayTitle() {
    let track = Track(url: url, title: "Test Song", artist: "Test Artist")
    XCTAssertEqual(track.displayTitle, "Test Artist - Test Song")
}
```

### UI Tests

Location: `Tests/AdAmpUITests/`

UI tests use Apple's XCUITest framework to test the application through its user interface.

**Test Classes:**

| Class | Coverage |
|-------|----------|
| `MainWindowTests` | Transport controls, sliders, toggles, keyboard shortcuts |
| `PlaylistTests` | Track list, buttons, drag-drop, scrolling |
| `EqualizerTests` | On/off toggle, presets, band sliders, graph |
| `PlexBrowserTests` | Tabs, content list, source selection, search |
| `VisualizationTests` | Preset navigation, fullscreen, keyboard controls |
| `IntegrationTests` | Multi-window workflows, docking, state persistence |

**Example Test:**

```swift
func testPlayPauseToggle() {
    let playButton = app.buttons["mainWindow.playButton"]
    playButton.tap()
    XCTAssertTrue(app.buttons["mainWindow.pauseButton"].waitForExistence(timeout: 2))
}
```

**Accessibility Identifiers:**

UI tests locate elements using accessibility identifiers. These are defined in:
- `Tests/AdAmpUITests/Helpers/AccessibilityIdentifiers.swift`

And set in the source views:
- `Sources/AdAmp/Windows/MainWindow/MainWindowView.swift`
- `Sources/AdAmp/Windows/Playlist/PlaylistView.swift`
- `Sources/AdAmp/Windows/Equalizer/EQView.swift`
- `Sources/AdAmp/Windows/PlexBrowser/PlexBrowserView.swift`
- `Sources/AdAmp/Windows/Milkdrop/MilkdropView.swift`

**Custom Drawn UI:**

Since AdAmp uses Winamp skins with custom drawing, accessibility elements are exposed via `accessibilityChildren()` override rather than standard AppKit controls. This allows XCUITest to find and interact with custom-drawn buttons and sliders.

### Integration Tests

Test component interactions:
- AudioEngine with StreamingAudioPlayer
- PlexManager with network layer
- WindowManager docking behavior

### End-to-End Tests

Test complete user workflows:
- Open app → Load files → Play → Seek → Stop
- Connect to Plex → Browse library → Play album
- Open EQ → Select preset → Verify audio changes

---

## Running Tests

### Local Development

```bash
# Ensure projectM library is in DerivedData (required once after clean)
cp .build/arm64-apple-macosx/Frameworks/libprojectM-4.4.dylib \
   ~/Library/Developer/Xcode/DerivedData/adamp-*/Build/Products/Debug/

# Run all tests
xcodebuild test -scheme AdAmp -destination 'platform=macOS'

# Run unit tests only
xcodebuild test -scheme AdAmp -destination 'platform=macOS' -only-testing:AdAmpTests

# Run UI tests only
xcodebuild test -scheme AdAmp -destination 'platform=macOS' -only-testing:AdAmpUITests

# Run specific test class
xcodebuild test -scheme AdAmp -destination 'platform=macOS' -only-testing:AdAmpTests/AdAmpTests

# Run specific test method
xcodebuild test -scheme AdAmp -destination 'platform=macOS' -only-testing:AdAmpTests/AdAmpTests/testTrackCreation

# Run with coverage
xcodebuild test -scheme AdAmp -enableCodeCoverage YES

# View coverage report
xcrun xccov view --report ~/Library/Developer/Xcode/DerivedData/adamp-*/Logs/Test/*.xcresult
```

**Note:** `swift test` is not recommended for this project because it doesn't properly handle the AppKit dependencies and external frameworks. Use `xcodebuild test` instead.

### UI Testing Mode

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

### CI (GitHub Actions)

Tests run automatically on:
- Push to `main` or `test-dev` branches
- Pull requests targeting `main`

See `.github/workflows/ui-tests.yml` for configuration.

**CI Features:**
- Parallel unit and UI test jobs
- Test result artifacts (`.xcresult` bundles)
- Failure screenshot capture
- Build log preservation on failure

---

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

---

## Test Data and Fixtures

### Audio Files

Test audio files are located in `Tests/Fixtures/`:
- `test-short.mp3` - 5 second silence for quick tests
- `test-3min.mp3` - 3 minute track for seek tests
- `test-metadata.mp3` - File with full ID3 tags

### Mock Mode

When running UI tests, the app launches with `--ui-testing` flag which:
- Skips Plex auto-connection
- Disables network requests (uses mock responses)
- Loads test fixtures automatically

---

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

---

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

Generate coverage reports:

```bash
xcodebuild test -scheme AdAmp -enableCodeCoverage YES
xcrun xccov view --report ~/Library/Developer/Xcode/DerivedData/adamp-*/Logs/Test/*.xcresult
```
