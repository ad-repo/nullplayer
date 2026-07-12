---
name: projectm-milkdrop
description: ProjectM/MilkDrop preset engine inside the visualization window — preset loading, controls, modes, audio sensitivity, beat sensitivity, drag-suspend behavior. Use when editing the ProjectM wrapper, preset folder logic, or its menu.
---

# ProjectM/MilkDrop Visualizer

Renders classic MilkDrop presets using OpenGL. The visualization window has two implementations (classic/modern UI modes) both embedding `VisualizationGLView` for rendering. The same window hosts the ProjectM, Geiss, Tripex, and Met Museum engines, switchable from the right-click **Visualization Engine** submenu.

For sibling engines see [geiss-port](../geiss-port/SKILL.md), [tripex-port](../tripex-port/SKILL.md), [met-museum-visualizer](../met-museum-visualizer/SKILL.md).

## What is ProjectM/MilkDrop?

- **MilkDrop** — iconic Winamp visualization plugin
- **ProjectM** — open-source reimplementation
- Presets are shader-based programs creating infinite visual variety

## Presets

NullPlayer ships bundled presets. Custom presets go in:
```
~/Library/Application Support/NullPlayer/Presets/
```
Place `.milk` files there and use "Reload Presets" from the context menu.

## Controls

**Keyboard:**
- **→ / ←** — Next/Previous preset
- **Shift+→ / Shift+←** — Hard cut (no blend)
- **R** — Random preset
- **Shift+R** — Random preset (hard cut)
- **L** — Lock/unlock preset
- **C** — Cycle modes (Off → Auto-Cycle → Auto-Random)
- **F** — Toggle fullscreen
- **Escape** — Exit fullscreen

**Context Menu:**
- Current Preset (name + index)
- Next/Previous/Random Preset, Lock Preset
- Manual Only / Auto-Cycle / Auto-Random
- Cycle Interval (5s/10s/20s/30s/60s/2min)
- Presets submenu, Audio Sensitivity, Beat Sensitivity, Fullscreen

## Modes

| Mode | Behavior |
|------|----------|
| **Manual Only** | Presets only change via user input (default) |
| **Auto-Cycle** | Advances to next preset sequentially at interval |
| **Auto-Random** | Jumps to random preset at interval |

Auto-switching modes are disabled by default for stability — some presets may glitch during transitions.

Cycle mode and interval are persistent user preferences:
- Mode: `projectM.cycleMode` (`off`, `cycle`, `random`)
- Interval: `projectM.cycleInterval` (seconds, default 30)

## Audio Sensitivity (PCM Gain)

Amplitude of audio samples fed to the visualization engine:

| Preset | Gain |
|--------|------|
| Low | 0.5× |
| Normal | 1.0× (default) |
| High | 1.5× |
| Intense | 2.0× |
| Max | 3.0× |

Persisted: `projectMPCMGain` (UserDefaults)

## Beat Sensitivity

- **Idle**: 0.2 when audio is quiet/stopped
- **Active**: user-configurable (default 1.0)

Persisted: `projectMBeatSensitivity` (UserDefaults)

## Technical

- **Rendering**: OpenGL 4.1 Core Profile via NSOpenGLView
- **Frame Rate**: 60 FPS via CVDisplayLink
- **Audio Input**: PCM waveform data from AudioEngine
- **Beat Detection**: built-in projectM beat sensitivity
- **Drag suspend**: ProjectM rendering is suspended for the duration of any window drag (`.windowDragDidBegin` / `.windowDragDidEnd` from `WindowManager`). This prevents WindowServer stalls on Apple Silicon caused by simultaneous OpenGL compositing and window repositioning. If adding window-movement code that runs outside a drag, do NOT rely on ProjectM being suspended — the suspend is drag-scoped only.

## Key Files

- `Windows/ProjectM/ProjectMWindowController.swift` — window controller (classic)
- `Windows/ProjectM/ProjectMView.swift` — container with classic chrome
- `Windows/ModernProjectM/ModernProjectMWindowController.swift` — window controller (modern)
- `Windows/ModernProjectM/ModernProjectMView.swift` — container with modern chrome
- `Visualization/VisualizationGLView.swift` — OpenGL rendering (shared)
- `Visualization/ProjectMWrapper.swift` — ProjectM library wrapper
- `App/ProjectMWindowProviding.swift` — protocol abstracting classic/modern

## Troubleshooting

**Black screen**: ProjectM requires OpenGL 4.1; check Console.app for projectM init errors; try reloading presets.

**No presets loading**: verify preset files exist in bundle or custom folder; check folder permissions.

**Choppy animation**: close other GPU-intensive apps; try a different preset.

**Crashes during preset switching**: fixed by disabling soft cuts (blended transitions); check Console.app for `projectM` errors.

**Null texture pointer crash**: fixed by removing direct OpenGL calls from `reshape()` — the render thread now handles all viewport updates safely.
