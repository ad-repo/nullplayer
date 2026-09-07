# Winamp Modern (`.wal`) — Phase 16 Handoff

**For:** the agent picking up Winamp Modern work after Phase 16

**From:** Phase 16 (the surfaces NullPlayer draws itself are themed from the skin, not classic-skinned)

**Date:** 2026-08-16

Read first:

- `skills/winamp-modern-skin-guide/SKILL.md` — "Colours and hosted AppKit content" now carries the
  durable version of this; the file table has `WinampModernSurfaceStyle.swift`
- `skills/winamp-modern-skin-guide/compatibility.md` — the "Classic fallback" bullet in *Where a
  surface lives* says what "classic" does and does not mean now
- `skills/winamp-modern-skin-guide/manual-qa-checklist.md` §4 — **the open gate** (see §5 below)
- `TASKS.md` §16 — every step, including two corrections to the plan's own inventory
- `~/.claude/plans/winamp-modern-fallback-surface-style.md` — the plan, with outcomes

## 1. What Phase 16 was

Everything NullPlayer draws *for* a `.wal` skin — the library embedded in a skin's holder, and the
playlist / equalizer / library windows opened when a skin declares none — was painted by the
**classic** renderer: `SkinRenderer` sprite sheets, the 5×6 bitmap font, and `skin.playlistColors`
from whatever `.wsz` happened to be selected. Inside a Winamp 5.x skin that is a foreign UI coloured
by a skin the user is not looking at.

The engine already resolved the right colours — `WasabiPalette`, through the renderer's own resolver
and colour-theme gamma. `WinampModernLibrarySurfaceView.applyPalette` had received it since Phase 13
and dropped it on the floor ("kept as a named seam so a future recolour has a home"). Phase 16 is
that recolour.

619 tests (was 611).

| Step | What landed |
|---|---|
| 16.1 | `WinampModernSurfaceStyle` — palette → chrome roles, and the replacement text primitive |
| 16.2 | Plumbing: the embedded seam, `WindowManager.winampModernSurfaceStyle`, `.winampModernThemeDidChange` |
| 16.3 | `PlexBrowserView` (embedded *and* fallback window) |
| 16.4 | `PlaylistView` fallback window |
| 16.5 | `EQView` fallback window |
| 16.6 | `WinampModernPhase16Tests` (8), docs, CHANGELOG |

## 2. Why the change was small enough to be safe

The line counts are misleading. Almost all of this drawing code already went through
`PlaylistColors` fills; the *classic-specific* surface is tiny:

| View | `SkinRenderer` entry points |
|---|---|
| `PlexBrowserView` (19.9k lines) | `drawSkinText` ×1, `drawSkinTextWhite` ×2, `skinTextColor` ×6, `drawPlexBrowserWindow` ×1 |
| `PlaylistView` (2.1k) | `drawPlaylistWindow` ×1 (its four `drawSkinText` calls are dead — see §3) |
| `EQView` (0.6k) | `drawEqualizerBackground`, `drawEQGraph`, `drawEQSlider` ×2, `drawButton` ×3 |

Three text helpers in the browser funnel 77 call sites into one place. Measure before assuming a
20k-line file needs a 20k-line change.

## 3. Five things that will bite you if you don't know them

**1. The font advance is load-bearing, and it is not a style choice.** These views lay themselves out
as `text.count * SkinElements.TextFont.charWidth * scale` — 77 times in the browser alone, plus tab
widths, button widths, and truncation points. `WinampModernSurfaceStyle.font(scale:)` therefore
*solves for* a monospaced point size whose advance equals that cell exactly (measure a probe at size
100, scale by the ratio), and `attributes` adds a `.kern` correction for the remainder. Pick a font
by eye instead and every box in these files is silently wrong. `WinampModernPhase16Tests`
asserts the two agree at five scales; keep that test if you change the face.

**2. Chrome roles must be blends, never fixed greys.** Real skins declare three of the seven palette
roles. A hardcoded `#333` chrome is correct on a dark skin and invisible on a light one, so
`barBackground`/`border`/`divider`/`dimText`/`pressedFill` are all `blend(background, toward: text)`.
`testDerivationFollowsTheSkinsOwnDirection` pins the light-skin direction specifically.

**3. `PlaylistView`'s bottom bar does not exist.** `Layout.bottomBarHeight` is
`SkinElements.Playlist.bottomHeight` = **7px**, and the classic renderer draws a border strip there.
`drawBottomBarInfo` and `drawPlaybackTime` are dead code ("Bottom bar removed"), and
`hitTestBottomButton` still carries boxes written for a 38px bar with ADD/REM/SEL and a mini
transport. Drawing those buttons from the hit-test rects — which is exactly what this phase did
first — paints a 38px button row over a 7px frame. The hit boxes are stale; the drawing is correct.

**4. `drawScaledSkinText` runs ~77 times a frame, so nothing in it may be expensive.** Deriving a
style converts seven colours through a colour space, and solving the font measures a glyph. Both are
cached: the style per view (invalidated by `.winampModernThemeDidChange`), the font memoized by
scale. If you add a role or a text variant, keep it out of the per-string path.

**5. The gating is three-valued, not two.** `WindowManager.winampModernSurfaceStyle` is nil outside
`winampModern` **and** nil inside it until a skin actually loads — the placeholder window and any
load failure keep the untouched classic drawing. Classic mode's pixels are unchanged by construction:
every new path is behind `if let style`.

## 4. Where the seams are

```
WasabiPalette  (engine, unchanged — skin colour resources + gamma)
  └─ WinampModernSurfaceStyle          roles + blended chrome + the text primitive
      ├─ embedded:  WinampModernMainView.themeDidChange / reconcileHostedSurfaces
      │               → WinampModernLibrarySurface.applyPalette
      │               → PlexBrowserView.applyWinampModernStyle
      └─ windows:   WindowManager.winampModernSurfaceStyle  (nil in every other mode)
                      → PlexBrowserView / PlaylistView / EQView, per draw
                      ← repainted by .winampModernThemeDidChange
```

`WinampModernSurfaceStyle` deliberately reads `SkinElements.TextFont` and produces `PlaylistColors`:
it is the *bridge* between the two systems, which is why it can depend on both. Do not give the same
licence to anything else in `WinampModern/`.

## 5. What is open

- **The live GUI pass — the only Phase 16 item not done.** Nothing here has been verified against
  real pixels: the render-dump harness renders the skin's own scene, not these AppKit surfaces, so
  the chrome drawing has no automated coverage at all. `manual-qa-checklist.md` §4 has the gate;
  the light-skin case and the "switch back to Classic and confirm nothing leaked" case are the two
  most likely to find something.
- **15.6 is still open and unrelated** — cPro-Bento's SUI tab row is inert because `CproTabs.maki`
  never initializes (`onscriptloaded=false`). Phase 16 did not touch it.
- **15.4 is still open** — the live splitter/protective-minimum run.

## 6. If you extend this

- Add a role to `WinampModernSurfaceStyle` rather than reaching for a literal colour in a view. A
  literal is the bug this phase existed to remove.
- Keep chrome at classic metrics. Every button box in these three views is also a hit-test box
  somewhere else in the same file, and the two are not derived from a shared constant.
- If a fourth surface needs theming, it goes through the same optional-style gate — never a mode
  check inside a drawing routine.
