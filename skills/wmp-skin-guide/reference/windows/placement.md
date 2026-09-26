# `.wmz` windows: placement, recovery and raising

Moved verbatim from `reference/windows.md` on 2026-09-25; that file is the router. Read it first.

### Window placement and recovery

**`App/WindowPlacement.swift` is the single definition of "on screen" — the window's top-left corner
is on some screen — and `.wmz` uses it. Do not re-derive it locally.** A `.wmz` window is borderless:
it has no title bar, and most skins make it unmovable by its background, so a window that lands past
an edge cannot be dragged back. Every other family can be recovered by hand; this one cannot, which
is why the rules below are contracts rather than preferences.

| Moment | Seam | `.wmz` |
|---|---|---|
| A skin's own view opens | `WMPViewWindowMaterializer.place` | authored `openViewRelative` offset or the stored top-left, else `WindowManager.tiledOrigin`, then `rescuedOrigin` as the never-`nil` backstop. Placed **once**, so a window the user moved is never yanked back |
| One of NullPlayer's own windows opens | `WindowManager.positionSubWindow` | the same `tiledOrigin` → `rescuedOrigin` pair, sharing the `.wal` branch. **First open in a session only** — `reopensWhereLeft` keeps a reopened window where the user left it, and closing one no longer slides the others up |
| Snap To Default | `WindowManager.snapWMPToDefaultPositions` | the player re-centred, then one `WinampModernTiler` walked over every window, then an unconditional reachability pass |
| A resize | per-family | top-left anchored, so growth cannot strand the reachable corner |
| A display change, a UI Size change, a skin load | `WindowManager.ensureAllWindowsOnScreen` | run, gated `appliesPlacementRecovery` (W217 G3) |
| A restore onto a smaller desktop | `AppStateManager.correctedRestoredFrames` | run, same gate — one offset for the whole session, and the corrected `main` is what the player is restored to (W217 G2) |
| The player's own restored frame | `WMPMainWindowController.restoreFrame` | no rule of its own: it keeps the top-left it is handed, which is the corrected one (W217 G1) |

**A drag reaches the screen top with the skin's first drawn row, not its frame (W303).** A `.wmz`
frame keeps transparent room for drawers — `Alpine7618_v09`'s 412-tall view draws only its bottom
~150 while they are shut — and both AppKit's `constrainFrameRect` (which clamps even a borderless
window) and `applySnapping`'s hard clamp measured the frame, parking the faceplate ~260 pt down.
`WMPMainView.transparentTopInset` is the empty rows read off the composite on a full or structural
present; `WMPSkinWindow.constrainFrameRect` and `WindowManager.transparentTopOverhang` (zero for
every window that is not a `WMPSkinWindow`, so no other family moves) let that much hang above the
visible top, and the top snap aligns the drawn top. When the inset shrinks — a drawer opening into
the hidden part — the view re-constrains the window down. **The recovery sweep below still judges the
frame's corner**, so a session restored or a display changed with the window parked up there brings
it back down to frame-top; that was left alone deliberately.

**The recovery gate is `WindowManager.appliesPlacementRecovery`, never `appliesWinampModernPlacement`.**
The second one stays what it says — the `.wal` *arrangement* — and the two are not interchangeable.
A seam about getting a window back on screen takes the first; a seam about how `.wal` lays its
windows out takes the second. `.wmz` is in the first and out of the second, and
`WMPPlacementRecoveryTests` pins exactly that, because widening the wrong one would hand `.wmz`
`.wal` layout behaviour it must not have.

**Classic and Original stay out of both, and that exclusion is the load-bearing part.** B56 is the
record of what happens when these corrections reach a family whose window positions people have laid
their desktops out around. Every site switched for W217 G2/G3 was switched to a gate that still
excludes them, and the one unconditional edit — the sweep's child-window skip — lives inside a
function they never enter.

**The hosted video output is a child window and the sweep skips it.** `WMPVideoSurface` glues it over
the skin's `<VIDEO>` box with `addChildWindow`, and it is in `managedWindowRecords`, so the sweep
walks it. AppKit carries a child with its parent: rescuing it alone displaces it off the box, and if
the parent is rescued afterwards it moves twice. `.wal` had the same latent defect and the skip fixes
both.

**`positionSubWindow` and Snap To Default both branched on `.winampModern` alone until W217, and
`.wmz` fell through to the Classic stack.** That stack opens each window flush under the lowest one
already open and clamps nothing, because in Classic a window parked past an edge is a placement the
user chose rather than damage to repair. Measured live on `Halo 2` over an 1800x1130 visible frame
with ten windows open: Cava straddled the bottom edge, the Audio Analyzer opened entirely below it
and Flow 200pt further down again — three windows gone, with no route home and Snap To Default
recentring the player and whichever unthemed fallback windows happened to exist. Both now take the
tiling branch, whose every slot `WinampModernTiler.nextSlot` clamps onto the visible frame on both
axes.

**Snap To Default walks one tiler, not `tiledOrigin` per window.** `tiledOrigin(for:avoiding:)`
builds a *fresh* tiler each call and returns the first slot clear of an occupancy set: that is how a
window opened **after** an arrangement joins one, and it is the wrong instrument for laying out a
whole session — it re-derives every column from the current window's own width, and late windows
pile onto each other (measured: four windows on one slot). A shared cursor is what makes the result
an arrangement. `WinampModernMainWindowController.arrangeWindows` is the recipe; the `.wmz` routine
is that recipe with the player re-centred first.

**A row here names the seam an audit found; the seam the *user* hits may be a different one in the
same family.** W217's G4 was written against Snap To Default, and the defect reported from the
running app was `positionSubWindow` — four lines away, never audited, and no amount of reading found
it. The app was launched, ten windows were opened and their frames were read back. **Measure the
moment the user described, not only the seam the row names.**

**The `.wmp` case in `fallbackMainSize` is dead** — the branch above it returns first — and is kept
only for exhaustiveness. `ui-guide` § *Off-Screen Window Recovery* names all four families and says
which of them the sweep reaches.

**`restoreWindowPositions` (`WindowManager.swift`) has no callers, in any family.** It was named as
the one recovery seam still `.wal`-only and as the right place to look when G1 was taken up; taking
G1 up found that nothing in `Sources` or `Tests` invokes it. It is dead code that re-applies raw
`UserDefaults` frames, and its `.wal`-only gate is therefore not a recovery gap any user can reach.
It was left untouched rather than have its gate widened for a path that never runs — **check that
before reviving it**, because in `.wmz` re-applying a raw saved rect would run behind the session
correction and undo it.

**The contract is that one press is enough and a second press is a no-op.** Verify it that way:
`diff` the window list across two presses, do not judge it by eye.

**Verify a placement change live, and measure the frames** — `WMP_PLACE_TRACE=1`, `Halo 2` as the
load case (four panels from `onLoadSkin` plus `mainView`) and `Corona` as the control; read the
frames back through `app-control`'s `winhelper windows` rather than off a screenshot. A frame outside
every screen is `rescuedOrigin` failing. Two legs cannot be exercised by hand and need the unit
tests (`Tests/NullPlayerAppTests/WMPSnapToDefaultTests.swift`): a genuinely stranded window — a
`.wmz` window is not movable by its background and macOS clamps a drag at the screen edge, so one
cannot be produced with the mouse — and a window taller than the display.

**The recovery half's pure geometry is `Tests/NullPlayerAppTests/WMPPlacementRecoveryTests.swift`**:
the gate in all four families, the docked cluster that comes back touching rather than overlapping,
the AppKit contract the child-window skip rests on, and G1's pair — the controller keeping the frame
it is handed, and the seam above still rescuing that same frame, so a regression in either is
distinguishable from a regression in both. **G1's live leg is outstanding**: unlike G2, G3 and G4 it
was closed on the unit pair alone, so a restore onto a smaller desktop, an unplugged display and a
resolution change have not been driven against it. It is the first thing to run if a `.wmz` window
comes back unreachable. Its live half — an unplugged display, a
resolution change, a restore onto a smaller desktop — has no headless instrument and was verified by
driving the app.

### Raising the skin's windows together (W273, closed 2026-09-25)

**Clicking any NullPlayer window raises every one of them, a skin's `theme.openView` panels
included, with the clicked window on top.** `WindowManager.bringAllWindowsToFront` raises a fixed
list of NullPlayer's controllers. The panels are not controllers, so `WindowManager.raiseOrder`
appends `materializedAuxiliaryWindows` after that list, in the order the skin opened them. It does
this in `.wmz` only; every other family raises the list unchanged. Before this, clicking `WoW`'s
player left its EQ, vis and info panels behind whatever other app covered them.

Adding the panels to the list was not enough, and the live loop showed why. With a cover window from
another app over the player's edge and two panels, a click on the player ran the raise with the
right list and a nil key window, because the activation had not settled. The window server applied
only some of the reorders: the panels stayed under the cover. Two changes fix it, both limited to
WMP:

- **Both WMP `windowDidBecomeKey`s defer the raise one main-loop turn** (in `WMPMainWindowController`
  and `WMPViewWindowMaterializer`). The deferred call runs only if its window is still key.
- **In `.wmz`, the raise orders the other windows front with `orderFrontRegardless`**; the clicked
  window keeps `orderFront`. Deferral alone still left the panels behind the cover, while the key
  window, the list and the ordering were all correct in `NSApp.orderedWindows` immediately after
  the raise. `orderFrontRegardless` is what put them on top, confirmed by pixels.

What the live check showed, so it isn't re-investigated:

- **A docked panel sits above the player in the window list.** `updateDockedChildWindows` makes
  every docked window a child of the main window, and AppKit keeps a child above its parent. This
  is true in every mode, and docked windows don't overlap, so it can't be seen on screen.
- **Z-order between windows that don't overlap has no visible effect.** `NSApp.orderedWindows`
  settled 0.3 s after the raise with the panels above the player. That order is harmless, because
  the panels don't overlap the player. **Judge a raise by sampling pixels where a cover window
  overlaps each window, never by the window list alone.**
- **Covering the test area with your own windows is dangerous**: a click meant for the player
  landed on a Finder sidebar and navigated the reporter's window. Use a throwaway cover window
  (a 15-line `NSWindow` script) and hide other apps (`set visible of process … to false`), which
  leaves their state untouched.

The ordering itself needs a window server, so `WMPWindowRaiseTests` pins only the gate and the list.
