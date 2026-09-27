---
name: vis-classic-guide
description: Comprehensive implementation and profile reference for NullPlayer's vis_classic mode (CVisClassicCore, VisClassicBridge, SpectrumAnalyzerView integration, menu/keyboard controls, transparent-background behavior, persistence keys, and bundled INI profiles). Use when modifying vis_classic rendering behavior, profile import/export, assigning profiles to skins, or debugging profile-specific response differences.
---

# Vis Classic Guide

## Overview

Use this skill when working on `vis_classic` in NullPlayer.

This skill documents:
- Full implementation architecture (audio input to CPU frame generation to Metal presentation)
- Menu, keyboard, notification, and persistence behavior for profile operations
- Every bundled `vis_classic` profile with technical parameters and human description

## Workflow

1. Read [`references/implementation.md`](references/implementation.md) before changing `vis_classic` behavior.
2. Read [`references/profile-catalog.md`](references/profile-catalog.md) when selecting, comparing, or assigning profiles.
3. If profiles change, regenerate the catalog:
   - `python3 skills/vis-classic-guide/scripts/generate_profile_catalog.py`
4. Validate skill metadata after edits:
   - `python3 /Users/ad/.codex/skills/.system/skill-creator/scripts/quick_validate.py skills/vis-classic-guide`

## Skin Assignment Guidance

Each skin family has its own default profile — Classic "Purple Neon", Original per `skin.json`,
`.wal` / `.wmz` the bundled profile nearest the skin's colours, once per skin
(`VisClassicProfileMatcher`). The table, the matcher, its keys and its log line are in
[`references/implementation.md`](references/implementation.md) §7. Profile colours are `R G B` as
drawn (§5.3) — never trust the original source's variable names.
- Keep window scope separate (`mainWindow` vs `spectrumWindow`), matching existing vis_classic persistence behavior.
- Treat profile selection as runtime state (not compile-time skin metadata) unless you are explicitly extending skin config schema.

## Debugging a live defect

Read **`skills/live-ui-testing`** before diagnosing anything that only reproduces on screen, and
`winamp-modern-skin-guide/reference/harness.md` § *Debugging a live defect*, the reference
implementation of that workflow. Launch with `skills/app-control/scripts/launch.sh <skin>`, open the
window from the Windows menu by pid, and capture it with `winhelper capture`. For a wrong default
profile, grep the app log for `VisClassicProfileMatcher:` first (implementation.md §7.2).

## References

- [`references/implementation.md`](references/implementation.md): Architecture, codepaths, options, and behavior details.
- [`references/profile-catalog.md`](references/profile-catalog.md): Exhaustive per-profile technical settings and descriptions.

## Scripts

- `scripts/generate_profile_catalog.py`: Rebuilds the profile catalog directly from bundled `.ini` files.
