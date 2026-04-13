---
name: cli
description: Headless CLI mode for NullPlayer on macOS and Linux. Use when working on CLI flags, source resolution, query/interactive playback behavior, terminal controls, and output routing.
---

# NullPlayer CLI

NullPlayer now has two CLI implementations:

- `Sources/NullPlayer/CLI/*`: macOS AppKit-backed CLI mode (`NullPlayer --cli`)
- `Sources/NullPlayerCLI/*`: Linux Foundation-only executable target (`swift run NullPlayerCLI --cli ...`)

Use this guide whenever a task touches CLI argument parsing, playback controls, output selection, or query behavior.

## Target Layout

| Target | Platform | Entry point | Notes |
|---|---|---|---|
| `NullPlayer` | macOS | `Sources/NullPlayer/App/main.swift` | App + CLI mode (`CLIMode`) |
| `NullPlayerCLI` | Linux-first | `Sources/NullPlayerCLI/main.swift` | No AppKit in Linux path |

## Shared Rule: Output Routing

CLI code should talk to `AudioOutputRouting` only:

- `outputDevices`
- `currentOutputDevice`
- `refreshOutputs()`
- `selectOutputDevice(persistentID:)`

Do not introduce direct CLI dependencies on `AudioOutputManager` in portable code paths.

`AudioOutputDevice` is keyed by `persistentID` (not CoreAudio numeric IDs).

## Linux CLI (Phase 2)

### Files

| File | Purpose |
|---|---|
| `Sources/NullPlayerCLI/main.swift` | Linux bootstrap, signal handling, wiring backend/facade/player |
| `Sources/NullPlayerCLI/LinuxCLIOptions.swift` | Linux flag parsing + unsupported-flag rejection |
| `Sources/NullPlayerCLI/LinuxSourceResolver.swift` | Resolves local paths and http/https URLs into tracks |
| `Sources/NullPlayerCLI/LinuxCLIPlayer.swift` | Playback controller using `AudioEngineFacade` |
| `Sources/NullPlayerCLI/LinuxCLIDisplay.swift` | Terminal rendering + raw keyboard capture |

### Supported Linux flags

- `--cli`
- `--help`
- `--list-outputs`
- `--shuffle`
- `--repeat-all`
- `--repeat-one`
- `--volume <0-100>`
- `--eq <off|flat|10 comma-separated gains>`
- `--output <name-or-persistent-id>`
- `--no-art`
- Positional inputs: local file paths or `http://` / `https://` URLs

### Unsupported Linux flags (fail fast)

Linux intentionally rejects macOS/library/casting query flags such as:

- `--source`, `--artist`, `--album`, `--track`, `--genre`, `--playlist`, `--search`
- `--station`, `--radio`, `--folder`, `--channel`, `--region`
- `--cast`, `--cast-type`, `--sonos-rooms`
- `--list-devices`, `--list-sources`, `--list-libraries`, `--list-artists`, `--list-albums`, `--list-tracks`, `--list-genres`, `--list-playlists`, `--list-stations`

### Linux keyboard controls

- `space`: play/pause
- `n`: next
- `p`: previous
- `f` / `b`: seek +10s / -10s
- `+` / `-`: volume +/-5%
- `q`: quit

### Linux playback semantics

- `repeatOne`: maps to `AudioEngineFacade.repeatEnabled = true`
- `repeatAll`: in delegate `state == .stopped`, restarts with `playTrack(at: 0)`
- `--output` matches exact `persistentID` first, then exact case-insensitive device name
- `--eq`:
  - `off` disables EQ
  - `flat` enables EQ and zeroes all bands + preamp
  - CSV requires exactly `engine.eqConfiguration.bandCount` gains

## macOS CLI (`NullPlayer --cli`)

### Files

| File | Purpose |
|---|---|
| `Sources/NullPlayer/CLI/CLIMode.swift` | AppKit CLI bootstrap, query-mode dispatch |
| `Sources/NullPlayer/CLI/CLIOptions.swift` | Full macOS flag parser |
| `Sources/NullPlayer/CLI/CLIPlayer.swift` | Interactive playback + cast/radio integration |
| `Sources/NullPlayer/CLI/CLIQueryHandler.swift` | Query commands (`--list-*`, `--search`) |
| `Sources/NullPlayer/CLI/CLISourceResolver.swift` | Resolves local + remote service sources |

macOS CLI supports full source/query/casting flows and should remain the only path touching Plex/Subsonic/Jellyfin/Emby/radio/casting managers.

## Source Resolution Rules

Linux (`LinuxSourceResolver`):
- Empty input is an error.
- `http`/`https` URLs pass through unchanged.
- Other inputs are treated as paths (tilde expanded, relative paths resolved against CWD).
- Non-existent files fail with `fileNotFound`.

## Signals and Exit Codes

Linux `main.swift` behavior:
- Installs dispatch signal handlers (`SIGINT`, `SIGTERM`)
- `SIGINT` exits `130`
- `SIGTERM` exits `0`
- On quit, backend is shut down before exit

## Testing

- Linux smoke: `swift test --filter LinuxSmokeTests`
- Playback facade behavior: `swift test --filter AudioEngineFacadeTests`
- DSP helper: `swift test --filter PortableAudioAnalysisTests`

Linux smoke tests set `GST_AUDIO_SINK=fakesink` so tests run headlessly.

## Gotchas

- Keep Linux compile path AppKit-free (`Sources/NullPlayerCLI/*`).
- Do not expand Linux flag support by silently accepting unsupported flags; reject with a clear error.
- Keep query/list output routing through the protocol abstraction, not concrete audio manager singletons.
- Preserve `--repeat-all` vs `--repeat-one` mutual exclusion.
