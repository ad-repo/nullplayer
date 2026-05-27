---
name: met-museum-visualizer
description: The Met Museum Open Access slideshow engine — controls, persistence keys, throttled API client, disk image cache, empty-department handling, audio reactivity hooks. Use when modifying the Met Museum engine, its menu, the API client, or the image cache.
---

# Met Museum Art Visualization

A ProjectM-peer engine that displays a slideshow of public-domain artwork from the Metropolitan Museum of Art's Open Access collection (api.collection.metmuseum.org). Selected from the same right-click **Visualization Engine** submenu as ProjectM/Geiss/Tripex, and reuses the same fullscreen, frame-rate, window docking, and engine-switch lifecycle. See [projectm-milkdrop](../projectm-milkdrop/SKILL.md) for the host window.

## Controls

**Keyboard** (wired in both `ProjectMView` and `ModernProjectMView`):
- **→ / ←** — Advance to another artwork
- **R** — Advance to another random artwork
- **F** — Toggle fullscreen
- **Escape** — Exit fullscreen

**Context Menu** (built by `MetMuseumMenuBuilder`, shared classic/modern):
- **Department** submenu — filters by Met department (departments with no public-domain images are auto-excluded after exhaustion)
- **Slideshow Interval** submenu
- **Transition** submenu — Crossfade / Ken Burns / Beat Cut / Slide
- **Transition Duration** submenu
- **Aspect Ratio** submenu — Fit / Fill / Stretch
- **Audio-Modulated Effects** toggle (subtle zoom/pan reacting to PCM levels)
- **Beat-Triggered Changes** toggle (advance on detected beats instead of fixed interval)
- **Show Artist & Title** toggle
- **Clear Image Cache** action
- Visualization Engine, Audio Sensitivity, Fullscreen

## Persistence

All preferences live in UserDefaults under the `metMuseum*` namespace via `MetMuseumEngine.DefaultsKey`:
`metMuseumDepartmentID`, `metMuseumIntervalSeconds`, `metMuseumTransitionMode`, `metMuseumTransitionDuration`, `metMuseumAspectMode`, `metMuseumAudioReactive`, `metMuseumBeatTriggered`, `metMuseumShowAttribution`.

When restoring config from UserDefaults in `VisualizationGLView`, **Bool keys must be guarded with `object(forKey:) != nil`** before calling `bool(forKey:)` — an unconditional `bool(forKey:)` returns `false` for missing keys and would clobber the engine's defaults on fresh installs.

## Technical

- **Files**:
  - `Visualization/MetMuseum/MetMuseumEngine.swift` — slideshow + OpenGL rendering
  - `Visualization/MetMuseum/MetMuseumClient.swift` — Met API client
  - `Visualization/MetMuseum/MetMuseumImageCache.swift` — on-disk image cache
- **API Client**: `MetMuseumClient` uses a semaphore + minimum request spacing (`withPermit`) to stay under the API's throttle and avoid 429s under load. `withPermit` is `throws` (not `rethrows`) so `CancellationError` from `Task.sleep` propagates and the network request is skipped when the slideshow task is cancelled mid-throttle.
- **Image URL validation**: `URL(string: objectInfo.primaryImage)` must be optional-bound; throw `MetMuseumError.noImageURL` on nil rather than force-unwrapping — the Met occasionally returns malformed URL strings.
- **Caching**: downloaded images are persisted to a disk cache keyed by object ID, so re-visits and history walks are free.
- **Empty-department handling**: when a department exhausts its public-domain pool without a match, it's added to an exclusion set, the menu hides it, and the slideshow auto-picks a different department.
- **Audio hook**: engine is `setAudioActive`-driven; the slideshow pauses when playback stops. Beat-triggered mode listens to `bpmUpdated` notifications; audio-reactive mode samples PCM levels each frame for zoom/pan modulation.
- **Per-engine scoped prefs**: visualization preferences are scoped per engine — Met Museum's prefs do not collide with ProjectM/Geiss/Tripex (see commit 40c8a5c).
- **Licensing**: Met Museum Open Access content is CC0; attribution shown via the in-engine overlay when **Show Artist & Title** is on.
