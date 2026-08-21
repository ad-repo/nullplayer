---
name: projectm-milkdrop
description: ProjectM/MilkDrop preset engine inside the visualization window — preset loading, controls, modes, audio sensitivity, beat sensitivity, drag-suspend behavior. Use when editing the ProjectM wrapper, preset folder logic, or its menu.
---

# ProjectM/MilkDrop Visualizer

Renders classic MilkDrop presets using OpenGL. The visualization window has two implementations (classic/modern UI modes) both embedding `VisualizationGLView` for rendering. The same window hosts the ProjectM, Geiss, Tripex, and Met Museum engines, switchable from the right-click **Visualization Engine** submenu.

For sibling engines see [geiss-port](../geiss-port/SKILL.md), [tripex-port](../tripex-port/SKILL.md), [met-museum-visualizer](../met-museum-visualizer/SKILL.md).

## Access

Open the host window from **Windows > Visualizations** and its controls from
**Visuals > Visualizations**. The engine picker labels the projectM-backed engine **ProjectM**.
`VisualizationType.projectM` deliberately retains its legacy raw value (`ProjectM (ProjectM)`) for
existing persisted preferences; use `displayName` for user-facing text.

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

**Menu bar:** **Visuals → Visualizations → Restore Disabled ProjectM Presets** re-enables any presets that were auto-disabled after a suspected crash (see Crash Detection & Blacklist below). The item shows the disabled count and is disabled when there are none.

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
- **Rendering lifetime — the view must be in a *visible* window before it will start.** `startRendering()` requires `window.isVisible`, and the only thing that restarts a stopped link is an occlusion change resuming one that was stopped *because* of occlusion. A `VisualizationGLView` added to a window that has not been ordered in yet is refused once and never asks again: it renders black forever while everything around it draws. Any host that builds the view before showing its window must call `resumeRenderingAfterWindowTransition()` afterwards. The window views do this implicitly (their windows are on screen when the view is made); the `.wal` skin surface calls it from `setSceneVisible`/`setAuxiliaryWindow`, because a skin's AVS window is created hidden and opened later.
- **Drag suspend**: ProjectM rendering is suspended for the duration of any window drag (`.windowDragDidBegin` / `.windowDragDidEnd` from `WindowManager`). This prevents WindowServer stalls on Apple Silicon caused by simultaneous OpenGL compositing and window repositioning. If adding window-movement code that runs outside a drag, do NOT rely on ProjectM being suspended — the suspend is drag-scoped only.

## Crash Detection & Blacklist

libprojectM can SIGSEGV/SIGBUS on a buggy preset (bad shader compile, the null-texture deref in `FinalComposite::LoadVariables`). To keep one bad preset from crashing the app on every launch, `ProjectMWrapper` disables ("blacklists") a preset that crashes and skips it when building the preset list.

**How it works (`ProjectMWrapper.swift`, `// MARK: - Crash Detection`):**
- The **crash sentinel** file (`~/Library/Application Support/NullPlayer/projectm_crash_sentinel.txt`) is written **only from a fatal-signal handler** (`_pmCrashSignalHandler`), never eagerly. On first preset load, `installCrashHandlersIfNeeded()` installs process-wide **SIGSEGV/SIGBUS** handlers (only those two — SIGABRT/SIGILL are left alone so Swift runtime traps aren't misread as preset crashes).
- `armCrashSentinel(presetPath:)` copies the current preset path into a signal-handler-readable C buffer and stays armed for the preset's **entire** display lifetime. If libprojectM faults at any point — load, first frame, or minutes into steady state (the #328 null-texture deref referencing a freed texture) — the handler writes the armed path to the sentinel, restores the prior disposition, and re-raises so the crash still surfaces normally.
- On the next launch, `checkAndHandlePreviousCrash()` (once per process) reads any sentinel file → the named preset crashed → it's added to the persistent blacklist (`projectMCrashedPresets` in UserDefaults) and excluded by `addPresetPath`.
- `disarmCrashSentinel()` (called from `deinit` / `applicationWillTerminate`) clears the armed flag so a fault during/after teardown isn't blamed on the last preset.

**Why signal-driven, not time-based:** the sentinel is written *only* when a fatal signal actually fires. A clean quit, a force quit, or a dev build script's **SIGKILL** raises no catchable signal, so no sentinel is written and no healthy preset is blacklisted. An earlier fix eagerly wrote the sentinel on load and relied on a clean-teardown clear; any non-render termination left it behind and blacklisted the innocent on-screen preset (over many launches this disabled healthy presets — for some users, all of them). A settle-window variant would have fixed the false positives but missed exactly the late steady-state texture crashes the blacklist exists for; the signal handler catches those at any point in the preset's life. **Async-signal-safety:** the handler only reads file-scope globals and calls `open`/`write`/`close`/`sigaction`/`raise`; all state it touches is initialized in normal context before handlers are installed.

**Recovery:**
- **User-facing:** **Visuals → Visualizations → Restore Disabled ProjectM Presets** → `MenuActions.resetProjectMPresetBlacklist` → `ProjectMWrapper.clearCrashedPresetsBlacklist()` + reload.
- **Automatic one-time reset:** `clearErroneousBlacklistOnce()` (gated by `projectMBlacklistErroneousResetDone`) wipes the untrustworthy accumulated list once, to recover installs blacklisted by the earlier eager-sentinel behavior.

## Key Files

- `Windows/ProjectM/ProjectMWindowController.swift` — window controller (classic)
- `Windows/ProjectM/ProjectMView.swift` — container with classic chrome
- `Windows/ModernProjectM/ModernProjectMWindowController.swift` — window controller (modern)
- `Windows/ModernProjectM/ModernProjectMView.swift` — container with modern chrome
- `Visualization/VisualizationGLView.swift` — OpenGL rendering (shared)
- `Visualization/VisualizationContextMenu.swift` — the one context menu all three hosts build (`VisualizationMenuTarget` supplies the engine and the actions; `Options` the cycle state and whether Fullscreen/Close apply)
- `Windows/WinampModern/WinampModernVisualizationSurfaceView.swift` — the third host: the engine inside a `.wal` skin's own AVS window ([winamp-modern-skin-guide](../winamp-modern-skin-guide/reference/components.md))
- `Visualization/ProjectMWrapper.swift` — ProjectM library wrapper
- `App/ProjectMWindowProviding.swift` — protocol abstracting classic/modern

## Troubleshooting

**Black screen**: ProjectM requires OpenGL 4.1; check Console.app for projectM init errors; try reloading presets. If the view was added to a window that was still hidden, the display link was never started at all — see **Rendering lifetime** under Technical; in a `.wal` skin's window the DEBUG line `WINAMP-MODERN-VIS: resume … rendering=<0/1>` answers it directly.

**No presets loading**: verify preset files exist in bundle or custom folder; check folder permissions.

**Fewer presets than expected / presets missing**: a preset that crashed on load was auto-disabled (see Crash Detection & Blacklist). Restore them via **Visuals → Visualizations → Restore Disabled ProjectM Presets**. If they were disabled by mistake rather than a real crash, they'll stay restored; a genuinely crashing preset disables itself again on next load.

**Choppy animation**: close other GPU-intensive apps; try a different preset.

**Crashes during preset switching**: fixed by disabling soft cuts (blended transitions); check Console.app for `projectM` errors.

**Null texture pointer crash**: fixed by removing direct OpenGL calls from `reshape()` — the render thread now handles all viewport updates safely.
