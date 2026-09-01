# WMP skin compatibility

This is the checked compatibility surface for the public WMP skin mode. A member not listed
here is not dynamically bridged to AppKit, Objective-C, `AudioEngine`, the filesystem, or the
network. Unsupported reads return a stable empty/zero value plus a diagnostic; unsupported commands
are ignored with a diagnostic.

NullPlayer supports ZIP-based `.wmz` archives containing the XML/JScript `.wms` format used by
Windows Media Player 7 through 12 when a skin stays within the capabilities below. The version label
is not a blanket compatibility promise: malformed XML, unsafe archives, legacy code-page text, and
Windows-only object-model features are rejected or diagnosed even when Windows Media Player accepted
them. UTF-8, UTF-16LE, UTF-16BE, and deterministic legacy Windows-1252 definitions are supported.

## Phase 6 object model

| Object | Supported members |
|---|---|
| `player` | `controls`, `settings`, `currentMedia`, `currentPlaylist`, `network`, `playState`, `status` |
| `player.controls` | `play`, `pause`, `stop`, `previous`, `next`, `fastForward`, `fastReverse`, `currentPosition`, `currentPositionString` |
| `player.settings` | `volume`, `balance`, `mute`, `getMode`, `setMode`, `getString`, `setString` |
| media / metadata | `name`, `duration`, `durationString`, `getItemInfo`; title, artist, album |
| playlist | `count`, bounded `item(index)` snapshots (`name`, `duration`, artist metadata), `attributeCount`, `getAttributeName` |
| network | `bufferingProgress`, `receptionQuality`, `bandWidth` (`bandWidth` is currently zero) |
| `eq` | live `enabled` and ten gain-level properties, remapped to/from NullPlayer's active 10/21-band layout |
| `vis` | bounded `currentEffect` / `currentPreset` state; WMP effects render the safe NullPlayer bars surface |
| `theme` | live `currentViewID`; assignment requests a controlled switch to an authored view |
| `view` / elements | `left`, `top`, `width`, `height`, `visible`, `enabled`, `value`, `text`, `down` |
| popup | `show` is recognized but modal script UI is not executed |

The implemented host-command vocabulary is transport, scan, seek, volume, balance, mute, shuffle,
repeat, playlist play/remove/move, EQ enable/gain/preamp, and view switching. Numeric values are
finite-checked and clamped again at the main-actor host boundary.

## Phase 6 tags and native surfaces

| Tag/capability | Status |
|---|---|
| `TEXT`, `IMAGE`, `SUBVIEW` | Rendered; text publishes static-text accessibility, authored labels and tooltips |
| `SLIDER` | Pointer capture, keyboard adjustment, bounded value mutation, and change events |
| `VOLUMESLIDER`, `SEEKSLIDER`, `BALANCESLIDER` | Live typed host controls with keyboard/pointer accessibility |
| `PLAYLIST` | Live bounded list, selection, scrolling, double-click/Return play, and Delete mutation |
| `DROPDOWNPLAYLIST` | Live bounded selection and play |
| `EQUALIZERSETTINGS` | AppKit 10-band/preamp surface backed by live EQ with 10↔21-band remapping |
| `POPUP` | Safe host-owned preset menu only; arbitrary script modal UI remains denied |
| `WMPEFFECTS` | Safe NullPlayer bar visualizer; its audio consumer exists only while the active view contains the surface |
| `VIDEO`, `WMPVIDEO` | Documented app-authored placeholder; plug-ins and ActiveX remain denied |
| Multiple `VIEW`s | Controlled `theme.currentViewID` transaction, per-skin/view size, safe top-left, accessibility replacement |

NullPlayer auxiliary windows remain hidden in WMP mode because WMP-owned chrome hosts have not been
defined for them. They never fall back to Classic, Original, Original-Metal, or Winamp Modern chrome.

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

## Phase 7 corpus findings

The opt-in local corpus contained 14 user-supplied skins spanning several WMP styles. The Phase 7
report harness accepted and measured 4 archives and rejected 10 with typed diagnostics. Reports
contain only archive hashes/facts, compatibility demand, diagnostics, and numeric render metrics;
they never contain source archives, artwork, screenshots, render buffers, or local corpus paths.

- Unmarked legacy text falls back only to Windows-1252, the system-ANSI encoding commonly used by
  WMP 7-10 skin tools. NullPlayer does not guess among ANSI code pages.
- Three archives contain duplicate XML attributes, which are not well-formed XML, and fail with
  `WMP0027`. NullPlayer does not silently choose one authored value.
- Empty optional image attributes are compatibility-defaulted as a `WMP0023` warning. They no
  longer reject the surrounding skin; direct provider escapes remain hard failures.
- The accepted corpus exercises full/tiny views, transport elements, multiple auxiliary-style
  views, 1×/2× render surfaces, resize layout, mapping/hit testing, and bounded cache reuse.
- Remaining demand includes custom controls such as `CUSTOMSLIDER`, `EDITBOX`, `LISTBOX`, legacy
  `EFFECTS`/video settings, additional playlist variants, appearance-only attributes, and denied
  object-model members. These appear explicitly as unknowns and reduce report confidence instead of
  being guessed or bridged dynamically.

Run `WMPPhase7Tests.testOptInLocalCorpusProducesTypedReport` with `WMP_CORPUS_PATH` to use an external
directory and `WMP_CORPUS_REPORT_DIR` to retain the JSON report outside the repository.
