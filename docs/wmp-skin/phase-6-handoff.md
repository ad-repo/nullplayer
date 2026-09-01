# WMP skin Phase 6 handoff

## Repository state at phase start

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   0497dee5a68478e90f23875250533c1d22f593dd
status: clean except for the user-supplied, untracked skins/ corpus
```

## Delivered

- Immutable `WMPWidget` scene metadata for text, sliders, playlist/dropdown playlist, equalizer,
  popup, effects, and video surfaces. Metadata carries resolved top-left frames, clips, labels,
  tooltips, and slider ranges without placing AppKit objects in the scene.
- Tab/Shift-Tab focus, Space/Return activation, arrow-key slider adjustment, pointer capture, authored
  tooltips, and stable accessibility elements for custom-drawn text and controls.
- Live bounded playlist surfaces. The list supports selection, scrolling, double-click/Return play,
  Delete removal, and Option-arrow movement; the dropdown supports selection/play. Host snapshots
  cap copied rows at 4,096 and never expose `Track` objects to scripts or scene state.
- A live `EQUALIZERSETTINGS` surface with enable, preamp, and ten gains. The typed host remaps through
  `EQBandRemapper` when NullPlayer runs its 21-band layout and clamps all writes to ±12 dB.
- A host-owned safe popup preset menu. Script-authored arbitrary modal UI remains denied.
- A safe `WMPEFFECTS` bars surface driven by the existing spectrum callback. One ref-counted WMP
  consumer is registered only while the active scene contains the surface and is removed on switch
  or teardown. Scan release does not disturb visualization demand.
- An app-authored `VIDEO`/`WMPVIDEO` placeholder. WMP plug-ins, ActiveX, DLLs, and arbitrary media
  embedding remain unavailable.
- Controlled multiple-view switching through `theme.currentViewID`: capture and outgoing timers are
  canceled, continuous commands stop, view-local overrides reset, the new view resolves/renders
  off-main, top-left is preserved, per-skin/view size is applied, native/accessibility surfaces swap,
  and the view event is delivered afterward.
- Phase 6 compatibility documentation and owning-skill lifecycle contracts.

## Corpus evidence

The opt-in, user-supplied `skins/9SeriesDefault.wmz` archive passed the complete WMP suite, including
graph/load, mapping-image transport, three-size script geometry, render dump, hostile helper
replacement, and the Phase 6 widget/view tests. No archive, screenshot, artwork, or render dump is
tracked.

## Deliberate limitations

- WMP native auxiliary-window actions remain hidden because WMP-derived chrome hosts have not been
  defined for those windows. This satisfies the isolation rule: no Classic, Original,
  Original-Metal, or Winamp Modern controller/artwork is exposed as a fallback.
- `VIDEO`/`WMPVIDEO` is a documented placeholder rather than a video plug-in host.
- `WMPEFFECTS` intentionally uses the safe NullPlayer bars surface; arbitrary WMP effect plug-ins and
  script-selected native visualization engines remain denied.
- Popup support is a bounded host preset menu only. `popup.show` cannot create script modal UI.

## Shared-path audit

No shared/global source path changed. Every production edit is under `Sources/NullPlayer/WMPSkin/`
or `Sources/NullPlayer/Windows/WMPSkin/`; tests, compatibility docs, the handoff, and the owning skill
are in WMP-owned paths. The existing typed `WMPHost` seam was sufficient for playlist, EQ, and
spectrum behavior, so no `AudioEngine`, `WindowManager`, menu, Classic, Original, or Winamp Modern
source change was needed.

The planning worktree remains unchanged. The `/Users/ad/Projects/nullplayer` checkout retains its
pre-existing unrelated state. The untracked implementation `skins/` directory remains untouched.

## Verification

```text
swift build: passed
focused WMPPhase6Tests: 6 passed, 0 failed
complete WMP suite with 9SeriesDefault.wmz: 75 executed, 1 expected stream skip, 0 failed
full swift test: 508 executed, 5 expected opt-in skips, 0 failed (40.139 s)
git diff --check: passed
```

Pre-existing SQLite privacy-resource, deprecated OpenGL, aubio deployment-target, and local shader
warnings remain. No DMG was built, per the owning skill.

## Repository state before phase commit

```text
pwd:    /Users/ad/Projects/nullplayer-wmp-skin-support
branch: feat/wmp-skin-support
HEAD:   0497dee5a68478e90f23875250533c1d22f593dd
status: Phase 6 WMP-owned changes plus the user-supplied, untracked skins/ corpus
```

The planning worktree is clean at `4af0b7e4`. The original `/Users/ad/Projects/nullplayer` checkout
contains only its pre-existing Winamp Modern edits and untracked `.opencode/`; it contains no WMP
Phase 6 implementation path.
