# WMP skin Phase 0 decision record

**Date:** 2026-08-31
**Implementation branch:** `feat/wmp-skin-support`
**Implementation base:** `a746d8c7e5a8d72f548bb8761b9ecd3c9cea1534`
**Product exposure:** none

## Decisions

- **Phase 1: GO.** The bounded-container contract has stable typed diagnostics, original fixtures,
  metadata-first rejection, CRC verification, and no extraction or installed-state mutation.
- **Phase 5: GO with the helper-process architecture.** Untrusted JScript must run only in the
  bundled `WMPScriptIsolationHelper`, one fresh process and JavaScriptCore realm per evaluation
  batch, with a parent-owned deadline. A missed deadline terminates and reaps the helper before a
  replacement is launched. A main-process `JSContext` and an in-app `WKWebView` are prohibited.
- The Phase 0 helper is a security/feasibility proof and is not connected to a player mode. Phase 5
  must retain the framed protocol and process boundary while adding the typed WMP command/event
  vocabulary; it may amortize startup only if teardown and hard-stop properties remain equivalent.

## Threat model

A user-supplied `.wmz` is a hostile ZIP containing attacker-controlled names, sizes, compression,
XML, images, and JScript. The attacker may attempt path escape, normalized-name aliasing, decompression
bombs, parser exhaustion, oversized allocations, CPU loops, callback/timer floods, malformed framing,
state retention across restarts, or access to native objects, files, network, UI, and player internals.

The trust boundary is:

1. Central-directory metadata is checked before any entry payload is decompressed.
2. Entries are read through ZIPFoundation into bounded memory only; Phase 0 never extracts to disk.
3. Script input crosses a length-prefixed JSON protocol capped at 1 MiB per frame.
4. The helper creates a bare JavaScriptCore global realm. It exports only JSON globals, `callback`,
   and bounded timer shims—no Swift/Objective-C objects, selectors, filesystem URLs, network APIs,
   `AudioEngine`, UI objects, `require`, or `fetch`.
5. The parent owns the wall-clock deadline. It sends `SIGTERM`, waits 100 ms, escalates to `SIGKILL`,
   and synchronously reaps the child. The next request starts a new process and realm.
6. The helper has a 256 MiB address-space limit and 16-file-descriptor limit. The packaged helper is
   signed with App Sandbox enabled and no file or network entitlements.

Phase 0 does not claim that JavaScriptCore is memory-safe against engine vulnerabilities. The process
and sandbox boundaries limit consequences; OS and WebKit/JavaScriptCore security updates remain part
of the trusted computing base.

## Locked limits

| Area | Limit |
|---|---:|
| Archive entries | 4,096 |
| Entry / archive uncompressed bytes | 32 MiB / 128 MiB |
| Per-entry compression ratio | 200:1 |
| Wrapper directories above `.wms` | zero or one |
| XML depth / expanded nodes | 256 / 100,000 |
| Image bounds | 8,192×8,192 and 32 Mpx |
| Script file | 4 MiB |
| Expression dependency depth / passes | 128 / 256 |
| Active timers / minimum period | 256 / 8 ms (120 Hz effective maximum) |
| Preference value | 64 KiB, namespaced per skin hash |
| Script message / in-flight bytes | 1 MiB / 16 MiB |
| Helper address space / open descriptors | 256 MiB / 16 |
| Evaluation deadline / termination grace | caller-selected; proof uses 50 ms / 50 ms |

`WMPPhase0Limits` is the executable source of truth. Phase 1 may move it into production WMP types
without changing values unless corpus evidence and a new decision-record entry justify the change.

Paths normalize `\` to `/` and compare case-insensitively after Unicode canonical composition.
Absolute paths, Windows drive prefixes, `..` components, symbolic links, and normalized case
collisions are hard failures. Bounds, corruption, CRC mismatch, and invalid root shape are also hard
failures. Missing optional images and `res://` localization become warnings in Phase 1.

## Candidate comparison

### Studio-derived WebKit realm — rejected for WMP script execution

Useful Studio mechanisms remain valid patterns: an app-authored document, nonpersistent data store,
CSP, blocked navigation/windows/downloads, narrow typed messages, rate limits, and explicit handler
removal. They reduce ambient capability but do not terminate JavaScript execution.

The macOS 26.2 SDK exposes no public API that kills or deadlines one `WKWebView` evaluation.
`stopLoading()` stops navigation; dropping a view/process pool does not synchronously prove content
process death; `webViewWebContentProcessDidTerminate` is an observation callback. The SDK also does
not expose `JSContextGroupSetExecutionTimeLimit`. Running the infinite-loop fixture in the app process
would therefore create the exact unkillable state Phase 0 is meant to prevent. The WebKit candidate
is NO-GO without a future public hard-termination API and was not allowed to execute hostile loops in
the app/test-runner process.

### Bundled JavaScriptCore helper — selected

The helper has no UI and reads one bounded frame from stdin, evaluates in a new `JSContext`, writes
one bounded response, and exits. A script can read/write JSON peer/host-shaped objects and emit plain
callback values, but cannot receive native objects. The timer shim retains at most 256 callbacks and
drains at most the caller's bounded count. Allocation pressure is contained by the helper's address
space and the parent deadline. Syntax/recursion failures return errors; crashes and protocol failures
become stable diagnostics.

The parent can always terminate an OS process using public APIs. This is the decisive capability the
WebKit and in-process JavaScriptCore designs lack.

## Measured evidence

Hardware/OS: arm64 Mac, macOS 26.5.1 (25F80), Xcode macOS 26.2 SDK. Debug SwiftPM build.

| Probe | Result |
|---|---|
| Normal expression | `21 * 2` returned `42` |
| Peer/host read-write | nested JSON value changed from `0.25` to `0.75` and was returned |
| Callback | one plain `"ready"` callback returned |
| Syntax error | contained and returned as an error |
| Recursion | stack overflow contained and returned as an error |
| Timer storm | 10,000 requests admitted only 256 callbacks |
| Allocation pressure | test runner remained responsive; helper ended within 0.611 s |
| Infinite loop | 100/100 realms hit the 50 ms deadline, were terminated/reaped, and restarted |
| State reset | after every kill, `typeof priorState` returned `undefined` in the replacement realm |
| 100 kill/restart cycles | 19.768 s total; fixed outer test deadline 60 s |
| Archive corpus | all three valid archives accepted; all 15 hostile archives returned expected typed codes |

The test waits for each child to exit before returning, so a passing cycle has no unreaped helper.
The parent/test runner performed normal evaluations after every forced termination, demonstrating
responsiveness and clean replacement rather than merely issuing an asynchronous stop request.

## Fixture provenance and inventory

Everything under `Tests/NullPlayerAppTests/Fixtures/WMPSkin/` is original synthetic material authored
for NullPlayer and generated by `scripts/generate_wmp_phase0_fixtures.py`. No Microsoft or community
skin, script, or artwork is tracked. `MANIFEST.txt` records byte sizes and SHA-256 digests.

- Encoding: UTF-8, UTF-16LE BOM, UTF-16BE BOM `.wms` files.
- Structure: root, one-wrapper, two-view, nested `SUBVIEW`, `TEXT`, `IMAGE`, ordinary `BUTTON`,
  mapping-image `BUTTONGROUP`, and `SLIDER` fixtures with original 24-bit BMP pixels.
- Scripts: normal return, host read/write, callback, syntax error, recursion, timer storm, allocation
  pressure, and infinite loop.
- Hostile archives: traversal, absolute path, drive path, case collision, symbolic link, excessive
  wrapper depth, entry count, compression ratio, entry bytes, archive bytes, XML depth, XML nodes,
  image dimensions, script bytes, and CRC corruption.

The size-limit archives use compact ZIP headers with deliberately declared sizes where committing the
full hostile byte count would add more than 160 MiB of meaningless data. Those headers are themselves
the hostile input the metadata gate must reject; payload extraction is never attempted.

## Diagnostics locked by Phase 0

`WMP0001`–`WMP0020` cover unreadable archive, entry/byte/ratio limits, path forms, links/collisions,
wrapper depth, CRC, XML limits, image/script bounds, script message size, timeout, crash, and protocol
violation. Codes are stable compatibility-report identifiers; wording may improve without changing
the code's meaning.

## Packaging implications and proof

`WMPScriptIsolationHelper` is a separate SwiftPM executable product linked only to Foundation,
Darwin, and the system JavaScriptCore framework. App assembly installs it at
`Contents/Helpers/WMPScriptIsolationHelper`.

- DMG assembly signs the helper first with its restricted entitlements, then signs the app.
- MAS assembly signs the helper first with the distribution identity and restricted entitlements,
  then signs the enclosing app. The helper asks for App Sandbox only; it has no network, file, UI,
  automation, or inheritance entitlement.
- `scripts/verify_wmp_phase0_packaging.sh` verifies the nested signature, sandbox entitlement, and
  absence of client/server network entitlements.
- No third-party runtime, new dylib, JavaScript source package, XPC interface, or license payload is
  added. JavaScriptCore is supplied by macOS.

An actual MAS `.pkg` still requires the existing `MAS_*` signing credentials and provisioning profile;
the Phase 0 gate verifies the complete assembly/signing path structurally and with ad-hoc packaging,
while App Store distribution signing remains the release operator's credentialed step.

## Studio mechanism disposition

| Studio mechanism | WMP decision |
|---|---|
| Narrow capability/action vocabulary | Reuse in Phase 5 |
| Typed/clamped arguments and outbound JSON | Reuse; Phase 0 protocol is JSON-only |
| Request IDs, timeouts, inbound byte/rate limits | Reuse; process deadline is additionally mandatory |
| Nonpersistent WebKit store and CSP | Not applicable to selected non-WebKit realm |
| Navigation/read-access confinement | Replaced by no document/navigation/filesystem surface |
| Handler removal and `stopLoading()` | Rejected as a script termination guarantee |
| Fresh realm after teardown | Strengthened to a fresh OS process and JSC realm |

## Follow-up requirements

- Phase 1 replaces the proof auditor with `WMPArchive`/`WMPResourceProviding` and retains every code,
  bound, metadata-first check, CRC rule, and no-partial-install property.
- Phase 5 defines a closed request/command/event schema, capability allowlist, clamps, request IDs,
  rate limiting, preference namespace, and aggregate 16 MiB in-flight accounting.
- Phase 5 reruns this entire corpus and the 100-cycle proof against the production bridge before any
  scripted WMP mode can be enabled.
