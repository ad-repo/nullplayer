---
name: testing
description: Testing workflows for NullPlayer across macOS UI/unit tests and new Linux playback/CLI smoke tests. Use when adding tests, debugging failures, or validating playback behavior changes.
---

# Testing Guide

This guide covers practical test execution and expectations for current targets.

## Quick Start

```bash
# All SwiftPM tests
swift test

# Focused suites
swift test --filter AudioEngineFacadeTests
swift test --filter PortableAudioAnalysisTests
swift test --filter LinuxSmokeTests

# List tests
swift test list
```

## Current Test Targets

```text
Tests/
├── NullPlayerCoreTests/       # Core models/utilities
├── NullPlayerAppTests/        # App target unit tests (Darwin logic)
├── NullPlayerPlaybackTests/   # Cross-platform playback seam (facade + DSP)
├── NullPlayerCLITests/        # Linux CLI smoke tests
└── NullPlayerUITests/         # XCUITest (xcodebuild)
```

## Critical Suites For Linux Port Work

### `Tests/NullPlayerPlaybackTests/AudioEngineFacadeTests.swift`

Validates facade state machine behavior:
- stale token events are dropped
- canonical load callback ordering (`track -> time -> state`)
- seek emits immediate time update
- EOS advances playlist
- load-failed path notifies and advances

### `Tests/NullPlayerPlaybackTests/PortableAudioAnalysisTests.swift`

Validates portable analysis helper:
- 75-bin spectrum output
- 512-sample PCM snapshot
- silence decay and zero threshold behavior
- nil/empty-frame handling

### `Tests/NullPlayerCLITests/LinuxSmokeTests.swift`

Linux integration smoke:
- local playback pause/resume/seek
- next/previous, EQ writes, output listing/selection
- HTTP stream playback
- uses generated WAV fixtures and temporary HTTP server
- sets `GST_AUDIO_SINK=fakesink` for headless runtime

## Running macOS UI Tests

```bash
# All macOS tests (including UI)
xcodebuild test -scheme NullPlayer -destination 'platform=macOS'

# UI tests only
xcodebuild test -scheme NullPlayer -destination 'platform=macOS' -only-testing:NullPlayerUITests
```

UI tests rely on `--ui-testing` launch behavior in `AppDelegate`.

## Linux Test Notes

- If running Linux smoke on macOS, the suite compiles but only executes a placeholder `testLinuxOnly`.
- On Linux hosts, ensure GStreamer runtime/plugins are installed.
- Keep smoke tests deterministic: use synthetic fixtures and local loopback endpoints.

## Test Design Rules

- Fix production code for real defects; do not weaken tests to make failures disappear.
- Keep assertions specific and behavior-focused.
- Cover token/order/race-sensitive playback flows when touching facade/backend glue.
- For async behavior, prefer expectations and bounded waits over arbitrary long sleeps.

## Useful Filters

```bash
swift test --filter AudioOutputRoutingTests
swift test --filter AudioEngineFacadeTests
swift test --filter LinuxSmokeTests
swift test --filter NullPlayerCoreTests
```

## Common Failure Patterns

- Flaky order assertions: backend events emitted without token checks or incorrect load sequencing.
- Linux playback no-op: pipeline setup failed but no `.loadFailed` surfaced.
- Bus thread stops early: timeout treated as fatal in GStreamer bus loop.
- Output-selection regressions: code still using old UID/device-ID assumptions instead of `persistentID`.
