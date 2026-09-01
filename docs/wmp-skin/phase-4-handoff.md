# WMP skin Phase 4 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   a722df76ef301135a0a18037461d52cb60cbe0a9
status: clean except for the user-supplied, untracked skins/ corpus
```

## Delivered

- `WMPMappingImage`, with bounded top-left canonical RGB/alpha storage, exact un-premultiplied
  channel matching, transparent/unknown no-hit behavior, mapping-color lookup, per-node bounds, and
  byte-bounded reuse through `WMPImageStore`.
- `WMPHitTester`, using original control geometry plus a separate inherited clip, exact scaled map
  sampling, reverse z/document order, and fallthrough through transparent, unknown, clipped, and
  disabled pixels.
- `WMPInteractionState`, covering hover, pressed, captured, focused, sticky/down, and disabled state.
  The original press target owns capture through release/cancel; an action fires only on release
  inside that same target. Scan commands stop on release, cancellation, and teardown.
- Off-main normal/hover/down/disabled artwork selection and immutable scene rebuilding. AppKit keeps
  the full most recent render but invalidates only the union of changed control frames.
- A main-actor `WMPHost` protocol and `WMPAudioEngineHost` adapter for transport, scanning, seek,
  volume, balance, mute, shuffle, repeat, metadata, time strings, playlist position, and typed
  command-enabled state. Numeric inputs are finite-checked and clamped; skins never receive an
  `AudioEngine` reference.
- Semantic WMP transport elements and a deliberately small literal action recognizer. The latter
  accepts one exact transport statement, optionally preceded by the common `checkSoundPref(...)`
  statement. All general JScript remains disabled until Phase 5.
- Skinned mouse input, captured sliders, final-fallthrough window dragging, accessibility children,
  and host-driven disabled/sticky state. The dedicated unskinned WMP player now exposes native
  previous/play-pause/stop/next/mute controls and time state through the same host.

## Input behavior evidence

The implementation preserves the original, unclipped group frame for map scaling and applies the
ancestor clip independently. This was necessary for real skins whose mapping group is partially
clipped; scaling against the visible intersection selects the wrong map pixel.

The opt-in `9SeriesDefault.wmz` probe resolves a semantic mapped transport child, selects a real
pixel from its irregular region, converts that pixel through the authored group geometry, and
recovers the same child through the production hit tester.

Microsoft's WMP SDK documentation states that clicks on a registered mapping-color region belong to
that `BUTTONELEMENT` and describes `click`, `mousedown`, and `mouseup` as separate events. It does not
document the outside-release edge explicitly. A Windows WMP reference runtime was not available in
this macOS worktree, so Phase 4 locks the conventional click rule—capture remains with the original
node, but `click` activates only when release is still over that node—and covers it with focused
tests. Recheck this single edge during the Phase 7 Windows corpus/reference pass.

References: [BUTTONELEMENT.mappingColor](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/buttonelement-mappingcolor),
[External Events](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/wmp/external-events).

## Audio evidence

- A generated 0.5-second WAV exercises real `AudioEngine` local-file play, pause, resume, seek, and
  stop through `WMPAudioEngineHost` without replacing the engine or playlist.
- The opt-in streaming test used SomaFM's currently advertised Groove Salad MP3 endpoint. It reached
  AudioStreaming's `playing` state, decoded a 44.1 kHz stereo stream, received live metadata, and
  completed pause, resume, and stop through the same WMP host.
- Because WMP mode swaps only controllers and the host retains `WindowManager.shared.audioEngine`,
  mode switches do not replace playback state. The existing 20-cycle four-family test remains green.

## Shared-path audit

No shared/global application path changed. Product code changes are confined to
`Sources/NullPlayer/WMPSkin/` and `Sources/NullPlayer/Windows/WMPSkin/`; tests and documentation are
confined to the Phase 4 WMP paths and owning skill. No Classic, Original, Winamp Modern, or existing
audio-engine source file changed.

WMP-local alternatives therefore satisfied every integration requirement; no shared seam or new
mode gate was needed in this phase.

## Verification

```text
swift build: passed
focused WMPPhase4Tests: 12 executed, 2 expected opt-in skips, 0 failed
complete WMP suite: 57 executed, 4 expected opt-in skips, 0 failed
9SeriesDefault graph/render/pixel-hit corpus probes: 3 passed, 0 failed
real local playback host integration: passed
real streaming playback host integration: passed
full swift test: 490 executed, 4 expected opt-in skips, 0 failed
git diff --check: passed
```

The existing SQLite privacy-resource, deprecated OpenGL, aubio deployment-target, and other
pre-existing build warnings remain. The user-supplied `skins/` corpus and render dumps remain
untracked.

## Plan deviations and open risks

- The outside-release result is based on Microsoft click-region/event documentation plus standard
  click semantics, not a live Windows WMP reference run. It is isolated in `WMPInteractionState`
  and explicitly scheduled for reference confirmation in Phase 7.
- The real streaming test is opt-in because it requires an external endpoint. Default CI skips it
  cleanly; the local-file engine integration always runs.
- Phase 5 remains gated on the Phase 0 helper-process security decision. Phase 4 executes no skin
  script and recognizes no general handler program.

## Next work

Phase 5 adds the bounded helper-process JScript protocol, expression dependency engine, property
bindings, and event transactions without weakening the typed Phase 4 host boundary.
