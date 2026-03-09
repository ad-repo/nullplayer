---
name: vis-classic-guide
description: Comprehensive implementation and profile reference for NullPlayer's vis_classic mode (CVisClassicCore, VisClassicBridge, SpectrumAnalyzerView integration, menu/keyboard controls, persistence keys, and bundled INI profiles). Use when modifying vis_classic rendering behavior, profile import/export, assigning profiles to skins, or debugging profile-specific response differences.
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

When planning skin-specific profile defaults:
- Keep window scope separate (`mainWindow` vs `spectrumWindow`), matching existing vis_classic persistence behavior.
- Treat profile selection as runtime state (not compile-time skin metadata) unless you are explicitly extending skin config schema.
- Prefer deterministic identifiers for skins (bundle skin name/path hash) if adding a profile-per-skin map.

## References

- [`references/implementation.md`](references/implementation.md): Architecture, codepaths, options, and behavior details.
- [`references/profile-catalog.md`](references/profile-catalog.md): Exhaustive per-profile technical settings and descriptions.

## Scripts

- `scripts/generate_profile_catalog.py`: Rebuilds the profile catalog directly from bundled `.ini` files.
