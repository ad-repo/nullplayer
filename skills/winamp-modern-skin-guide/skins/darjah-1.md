## Darjah 1 (`Darjah 1.wal`)

*Per-skin status. Index: [skins.md](../skins.md) · engine-wide surface: [compatibility.md](../compatibility.md) · how a section gets written: `/wal-skin-report <skin.wal>`.*

- **File:** `Darjah 1.wal` · 792486 B · SHA-256 `973931ca4ebaba7d…`
- **Measured:** 2026-09-04 — **volume question only**, see *Not measured*
- **Grade: not graded (confidence: low)** — one reported symptom was chased to its cause; nothing else here was driven.

### The volume controls are the skin's, and there are almost none

Reported 2026-09-04: *"missing the volume controls on the main and only partially render volume
control in shade."* Both halves are the skin's own markup. **Nothing was changed** — this section
exists so the next report of it stops at reading rather than at a render sweep.

`grep -rli volume` over the extracted archive matches **one** file, `xml/player-shade.xml`. Not the
main layout, not a groupdef, not an include — one file.

The container is two layouts, and neither is named `normal`, so the first wins (`xml/player.xml`
includes `player-normal.xml` first):

```
main/sat   556x318   21 nodes   xml/player-normal.xml   <- the main window
main/du    687x106   23 nodes   xml/player-shade.xml    <- SWITCH target, the shade
```

- **`sat` declares no volume slider, no mute button and no fillbar.** All 21 nodes are accounted for
  in `RENDER_PROBE`, and `player/linux bg.png` paints no groove or track anywhere for one to sit in.
  Winamp shows the same thing. The wheel is the only volume affordance this layout ever had, and
  NullPlayer does not implement wheel-to-volume — see *If this is reopened*.
- **`du` draws its mute button, its speaker icon and the slider thumb correctly.** What is missing is
  the blue track behind the thumb, and the skin parks it off its own canvas:

  ```xml
  <layer id="volume.fillbar" x="457" y="402" image="play/Bar.png" />   <!-- layout is 106 tall -->
  ```

  `y="402"` verified in the raw bytes of the `.wal`, not just an extracted copy. `scripts/volume.maki`
  (disassembled, all six handlers) only ever calls `setRegionFromMap(fillmap, pos, reverse)` on that
  layer — `onScriptLoaded` resolves it, clears `dragable`, loads `play/volume-map.png` and seeds the
  region from `System.getVolume()`; nothing moves or resizes it. So it is ~300px below the window in
  Winamp too, and it appears only if the shade window is dragged past ~425px tall (the layout declares
  no `maximum_h`).

**Do not "fix" the fillbar with a quirk.** `WasabiSkinQuirks` requires the correct placement to be
derivable from the skin's own numbers. `x` is (`457` against the slider's `460`, with `Bar.png` 80
wide against the slider's 75 — symmetric); `y` is not — `402` is not a recoverable typo for anything,
and `64 − (23 − 13) / 2 = 59` is a plausible reconstruction, not a measurement.

The `player/` folder ships its own copies of `Bar.png` and `volume-map.png` that no XML references,
which is the trace of a main-layout volume the author started and did not finish.

### If this is reopened

The remedy that does not touch the skin is **Winamp's own default: the mouse wheel over the main
window is the volume**, 5/255 per notch. `WinampModernMainView.scrollWheel` currently falls through to
`super` when no `onmousewheel*` handler claims the notch. Adding the fallback there was written and
reverted 2026-09-04 (reporter's call: leave it). Classic mode has no wheel-volume either, so this
would be a Modern-only behaviour.

### Not measured

Everything else. No `/wal-skin-report` run, no click pass, no live pass, no coverage figure, no
comparison against an author screenshot. Its `Equaliser/*` art is missing (41 `resourceMissing`
warnings from `xml/player-elements.xml`) and its compatibility level reads `degraded`; neither was
investigated.
