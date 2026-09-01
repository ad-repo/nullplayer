# WMP skin compatibility

This is the checked compatibility surface for the experimental WMP skin mode. A member not listed
here is not dynamically bridged to AppKit, Objective-C, `AudioEngine`, the filesystem, or the
network. Unsupported reads return a stable empty/zero value plus a diagnostic; unsupported commands
are ignored with a diagnostic.

## Phase 5 object model

| Object | Supported members |
|---|---|
| `player` | `controls`, `settings`, `currentMedia`, `currentPlaylist`, `network`, `playState`, `status` |
| `player.controls` | `play`, `pause`, `stop`, `previous`, `next`, `fastForward`, `fastReverse`, `currentPosition`, `currentPositionString` |
| `player.settings` | `volume`, `balance`, `mute`, `getMode`, `setMode`, `getString`, `setString` |
| media / metadata | `name`, `duration`, `durationString`, `getItemInfo`; title, artist, album |
| playlist | `count`; `item` and attribute enumeration return safe placeholders until Phase 6 |
| network | `bufferingProgress`, `receptionQuality`, `bandWidth` (`bandWidth` is currently zero) |
| `eq` | `enabled`, ten gain-level properties; values are placeholders until the Phase 6 EQ slice |
| `vis` | `currentEffect`, `currentPreset` placeholders |
| `theme` | `currentViewID` |
| `view` / elements | `left`, `top`, `width`, `height`, `visible`, `enabled`, `value`, `text`, `down` |
| popup | `show` is recognized but modal script UI is not executed |

The implemented host-command vocabulary is transport, scan, seek, volume, balance, mute, shuffle,
and repeat. Numeric values are finite-checked and clamped again at the main-actor host boundary.

## Expressions and bindings

- JScript geometry expressions execute only in `WMPScriptIsolationHelper`.
- Reads are captured as dependencies. Resolvable expressions commit in stable topological order.
- Missing IDs, cycles, non-finite/negative sizes, depth overflow, and pass overflow do not partially
  mutate the visible scene.
- Resize publishes the proposed view size to a helper transaction, resolves dependencies, and swaps
  one completed immutable scene. Drawing continues with the previous scene while work is pending.
- `wmpprop:` and `wmpenabled:` share one coalescing registry. Transaction origins suppress echoes.

## Events, timers, and preferences

Script files load in archive/document registration order. Inline handlers support load, close,
timer, open/play/status/mode/buffering/reception changes, mouse down/up/click, and change dispatch.
Host-state handlers are collected in that order in one coalesced transaction. Timers are owned by
the host, capped at 256 active requests, and clamped to an 8 ms minimum period.

Preferences are stored under a SHA-256 skin-content namespace. A value is limited to 64 KiB and a
skin to 512 entries. Reset removes only that skin namespace.

## Deliberate denials

ActiveX, registry, shell/process APIs, arbitrary URLs, skin-authored HTML, filesystem/network
handles, native-object reflection, modal script UI, WMP plug-ins, DLLs, and Objective-C bridging are
not available. Script input/output is bounded JSON. A timeout, crash, allocation failure, malformed
response, or explicit teardown terminates the helper process, cancels timers, keeps the last valid
static scene, and disables script for that skin session.
