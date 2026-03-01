# Move Yellow Text Colors to skin.json

## Findings
- Default yellow `#d9d900` is hardcoded in `ModernSkinConfig.swift:70` as `defaultTimeColor`
- Applies to: `timeColor`, `marqueeColor`, `dataColor`, `eqMid`
- NeonWave `skin.json` has no explicit entries for these — falls back to Swift hardcoded default
- Glow effects confirmed: time digits, marquee, EQ values all use `setShadow` blur glow (no code changes needed)

## Tasks

- [x] Add explicit `timeColor`, `marqueeColor`, `dataColor`, and `eqMid` to `NeonWave/skin.json`
- [x] Check EmeraldForge, IndustrialSignal, ArcticMinimal skin.json files and add missing color entries where needed
