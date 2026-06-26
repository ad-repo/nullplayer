---
name: metal-gotchas
description: Cross-cutting Metal pitfalls in NullPlayer's visualization code — command encoder ordering, render-to-texture y-flip, shader availability checks, and the AudioEngine spectrum coalescing pattern that fixes Classic/Spectrum bar stuttering. Use when writing Metal pipelines or chasing visualizer jitter/crash bugs.
---

# Metal Gotchas

Cross-cutting Metal pitfalls that have bitten the visualization stack. Mode-specific shader details live in [gpu-vis-modes](../gpu-vis-modes/SKILL.md).

## Metal Command Encoders — guard the pipeline BEFORE the encoder

Never use `if let enc = cb.makeRenderCommandEncoder(...), let pl = pipeline { ... }` — if `pipeline` is nil the encoder is created but never ended, leaving the command buffer in an invalid state and causing a Metal API violation crash on `commit()`. Always guard the pipeline **before** creating the encoder:

```swift
// WRONG — encoder created but never ended if pipeline is nil:
if let enc = cb.makeRenderCommandEncoder(descriptor: rpd), let pl = pipeline {
    enc.setRenderPipelineState(pl)
    enc.endEncoding()
}
cb.commit()  // Crashes!

// CORRECT — guard pipeline first, then create encoder:
guard let pl = pipeline else { inFlightSemaphore.signal(); return }
if let enc = cb.makeRenderCommandEncoder(descriptor: rpd) {
    enc.setRenderPipelineState(pl)
    enc.endEncoding()
}
cb.commit()
```

## Metal Render-to-Texture UV Y-Flip

When doing multi-pass rendering (pass A writes to an intermediate texture, pass B samples that texture), the intermediate texture is stored with `y=0` at the **top** (Metal render-target convention). But the fullscreen-quad vertex shader maps `in.uv.y=0` to the **bottom** of the screen (NDC `y=-1`). So pass B must flip y when sampling:

```metal
float2(in.uv.x, 1.0 - in.uv.y)
```

Failing to flip produces an upside-down result. Example: `FlameShaders.metal` `flame_blur_v` uses `baseUV = float2(in.uv.x, 1.0 - in.uv.y)` to read the horizontal-blur intermediate texture correctly.

## Spectrum Shader Availability

Use `SpectrumAnalyzerView.isShaderAvailable(for:)` to check if a mode's shader file exists before switching to it. This static method works without a view instance and should be used when restoring modes from UserDefaults and when building menus. The instance method `isPipelineAvailable(for:)` checks the actual compiled pipeline and is used after `setupMetal()`.

## Spectrum Jitter / Bar Stuttering

**Symptom**: Classic and CPU Spectrum modes show jerky bar movement at startup or after cycling modes between windows.

**Root cause**: `AudioEngine` dispatched a new `DispatchQueue.main.async` block every audio tap (~60 Hz). During busy main-thread periods (mode switching, window ordering, UserDefaults writes), these backed up in the queue. When the backlog cleared, multiple blocks fired in rapid succession, causing bars to jump.

**Fix**: `AudioEngine` now uses the same coalescing pattern as `StreamingAudioPlayer` — a `pendingSpectrumUpdate` flag ensures at most one dispatch is ever queued, while `latestRawSpectrum` always holds the freshest frame so data is never lost. On the main thread the pending block reads `latestRawSpectrum` and posts the notification once, then clears the flag.

**Why Classic/Spectrum are more sensitive**: The LED attack rate in Enhanced mode (`cellAttackRate = 0.5`) absorbs rapid-fire updates visually. Classic and CPU-Spectrum have no equivalent damping, so burst updates are directly visible as bar jumps.

## Metal Default Colors

When adding a metal-family fallback skin or metal-only drawing path, do not leave palette fields nil if the modern default is bright or saturated. Missing `timeColor`, `dataColor`, `warning`, or EQ colors will fall back to the modern neon defaults, which can make metal text or traces disappear against the brushed background.

Recommended pattern:

- Set metal-family fallback text to dark neutral values
- Use muted graphite or steel fills for control wells and transport buttons
- Choose a waveform/trace color with enough contrast to remain visible on black or near-black background fills
