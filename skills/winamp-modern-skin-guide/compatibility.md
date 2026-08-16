# Winamp Modern (`.wal`) — Supported and Unsupported Behavior

What NullPlayer's Wasabi/MAKI runtime actually does, what it deliberately does not, and the limits it
enforces. Companion to [SKILL.md](SKILL.md).

The engine is **demand-driven**: coverage was added because a measured target skin needed it, not by
porting a reference implementation wholesale. So this document describes a real, narrow surface —
assume anything not listed is unimplemented, and confirm with the per-skin compatibility report rather
than guessing.

## Reference targets

Three skins drove the implementation, in increasing order of demand:

| Target | Role | State |
|--------|------|-------|
| **CornerAmp_Redux** | first vertical slice | loads, scripts, renders its 246×228 alpha-shaped layout, button input routed |
| **Winamp Modern** | compatibility expansion | loads and runs `onscriptloaded` headlessly; normal (354×280) and shade (354×25) switch through script dispatch; resize clamps; theme switching restores |
| **cPro-Bento** + ClassicPro engine | north-star | full 40-file include graph expands, graph builds, scripts bind and run, topology yields exactly one SUI window |

None of these ship with NullPlayer. All fixture-based tests are opt-in behind `WINAMP_MODERN_WAL` /
`WINAMP_MODERN_ENGINE`; everything committed is synthetic and self-authored.

## Archive and filesystem

**Supported**

- `.wal` (ZIP) with `skin.xml` at the archive root, or under exactly one wrapper directory
- Case-insensitive lookup with original spelling retained for diagnostics
- Windows path separators; `.` and `..` normalization; `@WINAMPPATH@`, `@SKINPATH@`,
  `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`
- `<include>` / `<elementinclude>` expansion, including a `*` glob in the **final** path component
  (sorted, deterministic)
- Cross-mount climbs into the ClassicPro engine mount

**Rejected** (typed diagnostic, never a crash)

- Path traversal, absolute paths, drive letters, symlinks, split/deep roots
- Case-colliding resources, corrupt ZIPs, archives exceeding any limit below
- Include cycles, missing include targets, a path escaping `/`
- A glob anywhere but the final component

## Wasabi XML / XUI

**Supported**

- Multiple document roots and raw ampersands (real skins contain both) — but tags must balance
- `groupdef` with `inherit_group` inheritance; `xuitag` custom tag registration
- Group template expansion during object creation
- Containers, layouts, layers, sprite regions, buttons/toggles with state images, sliders (horizontal
  and vertical), text, `clipchildren` parent clipping
- Bitmap fonts and TTF fonts (Core Text, not installed globally), colors, gamma groups
- Animated, N-state, ticker, album-art, and visualization elements
- Layout/shade switching, resize constraints, alpha-shaped window regions
- Namespaced per-skin configuration persistence
- Aliases and meta-commands
- `windowholder hold="guid:…"` component embedding and `componentbucket` discovery
- The curated predefined `wasabi.*` standard-library base groups (`registerWasabiStandardLibrary`)

**Not supported / degraded**

- **`wasabi.*` widgets render empty.** The predefined bases are identifier-only shells with no
  artwork, frames, or scrollbars — the real assets live inside Winamp, which NullPlayer does not
  bundle. A widget whose visuals come entirely from such a base draws nothing. This is the single
  largest visual gap on cPro-Bento.
- A base group outside the curated set warns and is dropped.
- A missing **optional** bitmap or cursor is a warning, not an error (Winamp-compatible).
- `file="$solid"` / `file="$gradient"` predefined bitmaps are recognized but not resolved as files.
- `embed_xui` is retained as metadata only — it is **not** an inheritance edge.
- Auxiliary container windows render and take input but do **not** drive per-container MAKI layout
  switching; the main window owns the scripted scene. (cPro-Bento is single-window, so this is
  invisible there.)
- Pixel-exact fidelity against real Winamp has never been verified for any target.

Duplicate resource/group/XUI definitions **replace** earlier ones and warn — this is intentional
override behavior, not an error.

## MAKI

**Supported opcodes** — stack push/pop/assignment; equality and ordered comparison; conditional and
unconditional branches; host/global method calls; local call/return; move; pre/post
increment/decrement; arithmetic and modulo; bitwise and logical operations; allocation; delete.

**Supported API** — the authoritative list is `signature(for:)` in `WinampModernScriptRuntime.swift`.
By area:

- **Playback host**: playback state, current time, duration, volume, shuffle/repeat, title/info,
  spectrum levels, transport (play/pause/stop/prev/next), seek, file-open
- **GUI mutation**: `setxmlparam`, `resize`, `show`, `hide` (each invalidates the view)
- **Lookups**: containers, layouts, object descendants, script group, script parameter/token access
- **System**: viewport/application coordinates, runtime/skin identity, integer/string conversion,
  date helpers, per-skin `getPublicInt`/`setPublicInt`
- **Timers**: bounded scheduling (see limits)
- **ClassicPro shell**: `exploreFile`, `openFile`, `findFiles` (policy below)

**Not supported**

- Any method not in `signature(for:)` — fails closed with `.unsupportedScriptCapability` and is
  recorded in the compatibility report's `unsupportedMethods` bucket
- Unsupported opcodes fail closed; they never become silent no-ops

**Failure granularity.** A method miss aborts *that script event only*; the remaining scripts still
run and the skin loads degraded, with every failure collected into the compatibility report. It
cannot degrade any finer than the event: the bytecode does not encode a call's argument count, so
without a signature the interpreter cannot unwind the stack and must abandon the event rather than
guess. This is why each needed method has to be implemented rather than stubbed.

**Measured demand — cPro-Bento startup.** As of 2026-08-15, exactly five methods block the
north-star target's `onscriptloaded` (from the report; 193 methods are *referenced* across the engine
but never reached at startup):

| Method | Calls |
|--------|-------|
| `loadmap` | 5 |
| `getitembyguid` | 2 |
| `getposition` | 1 |
| `getscale` | 1 |
| `isinvalid` | 1 |

Two follow-on `findobject`-on-null errors are downstream of these. Implement these five (each with a
signature and a regression test) before looking any further down the list.
- `messagebox` — denied (no arbitrary modal host UI)
- `navigateurl` — sandboxed no-op
- `newgroup` — returns a safe null result; broad runtime group instantiation is not implemented
- Popup menus use an inert command model with an injected presenter
- `getPublicInt`/`setPublicInt` are per-skin namespaced, not truly app-global

## Hosted components

| Component | State |
|-----------|-------|
| Playlist | Embedded and bound to `AudioEngine` — rows, now-playing marker, selection, bounded scroll, click/double-click/scroll input |
| EQ | Embedded classic 10-band + preamp, enabled/auto, presets, bound to `AudioEngine`; gains persist across mode switches |
| Library | Bounded live-subview seam; the production bridge returns `nil`, so a library toggle **falls back to the classic library window** |
| Visualization / video | Holder discovered and framed; content per the component host |

Playlist and EQ are **engine-drawn inside the skin-provided frame** — correct geometry and behavior,
but not painted with the skin's own list bitmaps, scrollbars, or EQ thumbs.

`TOGGLE`/`sendaction` for eq/pl/ml/video resolves in order: embedded component → separate skin window
→ classic `WindowManager` window.

## ClassicPro engine policy

- **User-supplied only.** Nothing is bundled and no permission is requested. The user provides the
  ClassicPro installer; NullPlayer never downloads it.
- **Internal extraction.** No external tools, no temp files, **no code execution** — the `.exe` is
  parsed by NullPlayer's own NSIS-2 reader and LZMA1 decoder.
- **Narrow format support.** NSIS-2 with a solid LZMA stream only (what ClassicPro ships). Non-solid,
  zlib/bzip2, NSIS-3, and non-NSIS `.exe` files fail with an actionable diagnostic. `.zip` (including
  a nested installer) and an already-extracted folder are also accepted.
- **Validated and hashed.** Structure validation requires the `one` engine family; content is
  SHA-256 hashed. One private copy is stored and mounted read-only.
- **Native surface is three shell methods**, none on the render path:
  - `exploreFile` — reveal an **existing** file in Finder
  - `openFile` — open an **existing** file with the default app
  - `findFiles` — bounded no-op returning −1, so callers early-return

  All gate on a real, existing, non-URL, non-`~` path. Skins cannot navigate URLs, launch
  executables, or reach arbitrary paths.
- **Version gate.** `WinampVersionCheck` sees a build number past the `2405` gate, so `load.xml`
  *branches* past its update warning rather than being hard-blocked. Install/update/download prompts
  are inert.

## Limits

All enforced; exceeding one produces a typed `WalDiagnostic`, never a crash or a hang.

| Area | Limit |
|------|-------|
| Archive entries | 4,096 |
| Entry uncompressed size | 32 MB |
| Archive total uncompressed | 128 MB |
| Compression ratio | 200:1 |
| XML nesting depth | 256 |
| Include depth | 32 |
| Expanded XML nodes | 100,000 |
| Group inheritance depth | 64 |
| Image dimensions | 8,192 × 8,192, and 32 Mpx |
| Font point size | 512 |
| Script (`.maki`) size | 4 MB |
| MAKI table entries | 100,000 |
| Bitmap cache | 256 MB (LRU) |
| MAKI instructions per event | 5,000,000 |
| MAKI call depth | 256 |
| MAKI allocation per event | 64 MB |
| MAKI stack values | 1,000,000 |
| Active timers | 256 |
| Timer period | ≥ 8 ms, ≤ 120 Hz |

## Verification status

**Verified headlessly** (synthetic + opt-in fixtures): archive/VFS/XML contracts and every rejection
path; initialization pass order and graph snapshots; geometry/anchor rules; MAKI parse/execute and all
budget aborts; fuzzing of the archive, XML, group-expansion, MAKI-parser, and VM paths (bounded
outcome, no trap or hang); stress (timer caps, 50× rapid load/teardown, malformed images, 2,000
groupdefs); teardown completeness; live four-mode switching.

**Not verified**: live GUI rendering and interaction for any target skin, casting continuity in this
mode, Compact Mode, UI Size, window docking, and pixel-level fidelity. Playback and casting are
`AudioEngine`-owned and mode-independent, and are proven for the other three families, but have not
been driven from a `.wal` skin's own controls. See [manual-qa-checklist.md](manual-qa-checklist.md).

**Not fuzzed**: `NSISArchive` and `LZMA1Decoder`. They are validated byte-for-byte against the real
installer (309/309 engine files match a reference oracle), but a bounded fuzz over them remains
reasonable future hardening.
