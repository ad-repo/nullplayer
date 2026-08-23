# Winamp Modern (`.wal`) — Supported and Unsupported Behavior

What NullPlayer's Wasabi/MAKI runtime actually does, what it deliberately does not, and the limits it
enforces. Companion to [SKILL.md](SKILL.md).

The engine is **demand-driven**: coverage was added because a measured target skin needed it, not by
porting a reference implementation wholesale. So this document describes a real, narrow surface —
assume anything not listed is unimplemented, and confirm with the per-skin compatibility report rather
than guessing.

## What is in this document

Split by surface, because this is a lookup document — you want one table, not all of them.

| Read | For |
|---|---|
| Below | Archive and filesystem: what a `.wal` may contain and what is rejected |
| [compatibility/wasabi-surface.md](compatibility/wasabi-surface.md) | Wasabi XML / XUI — elements, attributes, geometry, and what the markup layer ignores |
| [compatibility/maki-surface.md](compatibility/maki-surface.md) | MAKI — implemented and unimplemented methods, the event surface, dispatch behavior |
| [compatibility/limits-and-policy.md](compatibility/limits-and-policy.md) | The enforced limits, the ClassicPro engine policy, and verification status |
| Below | Hosted components — playlist, EQ, library, and where each surface lives |

How the engine *works* (rather than what it supports) is
[SKILL.md](SKILL.md) and the `reference/` files it routes to. What each measured skin does is
[skins.md](skins.md).

## Reference targets

Three skins drove the implementation, in increasing order of demand: **CornerAmp_Redux** (first
vertical slice), **Winamp Modern** (compatibility expansion), and **cPro-Bento** + the ClassicPro
engine (north-star). What each one does today lives in [skins.md](skins.md#reference-targets) and the
per-skin files it indexes — one home for measured state, because that is the part that drifts.

None of these ship with NullPlayer. All fixture-based tests are opt-in behind `WINAMP_MODERN_WAL` /
`WINAMP_MODERN_ENGINE`; everything committed is synthetic and self-authored.

## Archive and filesystem

**Supported**

- `.wal` (ZIP) with `skin.xml` at the archive root, or under exactly one wrapper directory
- Case-insensitive lookup with original spelling retained for diagnostics
- Windows path separators; `.` and `..` normalization; `@WINAMPPATH@`, `@SKINPATH@`,
  `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`, `@SKINSPATH@` (= `/Skins`)
- `<include>` / `<elementinclude>` expansion, including a `*` glob in the **final** path component
  (sorted, deterministic)
- Cross-mount climbs into the ClassicPro engine mount
- **Overlay skins**: `@SKINSPATH@\<Other Skin>\…` lazily mounts that installed `.wal` (≤ 4 per load).
  A base skin that is not installed fails with `missingRequiredMount`, which *names the skin to
  install*. The installed filename must match the name the overlay asks for. See
  `reference/loading.md` → *Sibling skin mounts*
- A `<bitmap>`/`<cursor>`/`<bitmapfont>` file that is present but undecodable (a zero-byte PNG)
  degrades to a warning and draws nothing; oversized images still fail

**Rejected** (typed diagnostic, never a crash)

- Path traversal, absolute paths, drive letters, symlinks, split/deep roots
- Case-colliding resources, corrupt ZIPs, archives exceeding any limit below
- Include cycles, missing include targets, a path escaping `/`
- A glob anywhere but the final component

## Hosted components

| Component | State |
|-----------|-------|
**The playlist status line is claimed by `display="PE_Info"`, not by `id="PE_Info"`.** Both work, but
the attribute form is what real skins use — the stock Winamp Modern skin
(`<text id="PLTime" display="PE_Info"/>`) and Defix (a hidden `<text id="info.input" display="PE_Info"
w="0" h="0" visible="0"/>` its script parses) both do. Matching on the id alone left both blank.
Its content is `N items/h:mm:ss`; the `/` is load-bearing — Defix reads the duration as
`getToken(text, "/", 1)`.

| Playlist | Embedded and bound to `AudioEngine` — rows, now-playing marker, selection, bounded scroll, click/double-click/wheel, Delete/Forward-Delete removal while focused, `PE_Info` status line. Drawn in the skin's palette and list font. Scriptable through **`PlEdit`** (Phase 42): length/current entry, per-entry title, length, filename and metadata, and play/remove/move/clear/scroll-to. `System.getPlaylistIndex()`/`getPlaylistLength()` answer from the same queue |
| EQ | Embedded classic 10-band + preamp, enabled/auto, presets, `<eqvis>`, bound to `AudioEngine`; gains persist across mode switches |
| Library | **The real browser, embedded** in the skin's holder — servers, tabs, search, CoverFlow, history, linking. Falls back to a window of its own only when the skin offers no home for it; either way it is drawn in the skin's palette, not with classic `.wsz` artwork |
| Visualization / video | Holder discovered and framed; content per the component host |

A holder is any of `<windowholder hold=…>`, `<componentbucket>`, or `<component param=…>` — the last
is the form separate-window skins use for their real content.

Playlist and EQ are **engine-drawn inside the skin-provided frame**: correct geometry, behavior, and
colours (via `WasabiPalette`, resolved through the skin's own colour resources and active colour
theme), but not painted with the skin's own list bitmaps, scrollbars, or EQ thumbs.

### Where a surface lives

Every request for the playlist, equalizer, or library — a menu item, a skin button's `TOGGLE guid:…`,
a restored session — resolves through one catalog, in one order: **embedded → declared container →
synthesized container → classic fallback**. The full resolution order, the Wasabi reveal contract, and
the synthesis prerequisites live in
[reference/components.md](reference/components.md#where-a-surface-lives). What is measured per skin is
the table below.

Measured, for the four reference skins:

| Skin | Playlist | Equalizer | Library |
|---|---|---|---|
| cPro-Bento | embedded | embedded (drawer) | embedded (tab) |
| mmd3 | declared `Pledit` | embedded (main-window drawer) | synthesized |
| CornerAmp_Redux | declared `Pledit` | declared `eq` | synthesized |
| Winamp Modern | declared `Pledit` | embedded | declared `MLibrary` |

Winamp defines **no equalizer component GUID** — no measured skin contains one — so an equalizer is
recognized by its controls (`EQ_BAND`, `EQ_PREAMP`, `<eqvis>`), and a synthesized one uses `guid:eq`.
`EQ_TOGGLE`/`EQ_AUTO` deliberately do not count as evidence: a button that opens the equalizer is not
an equalizer.

### Not implemented in the playlist

`PlEdit.enqueueFile(path)` and `System.playFile(path)` are **not implemented**: both take a filesystem
path from the skin, which is a sandbox policy decision rather than a missing method, so they stay out
of `signature(for:)` and keep being counted as measured demand (cPro-Bento and T800 respectively).

The skin-specific ADD / REM / SEL / MISC button menus are **inert**. They open Winamp's own nested
popup menus over playlist-manager operations NullPlayer has no equivalent for; the buttons draw and
respond to hover, and clicking one does nothing.

### Skin Windows — the windows a skin declares but binds no button to

The same shape of gap as Skin Settings, and reported the same way (*"there is no way to open the
speaker windows"*). A `.wal` skin can declare a container, name it, and bind nothing to it, because in
Winamp it appears in **Winamp's Windows menu**. Defix declares `SPEAKER 1`, `SPEAKER 2` and its
configurator that way; all three were built, rendered and ordered out, with no route to show them.

**Winamp Modern → Skin Windows** is that menu. What it lists is decided by the skin's own markup:

- a container is offered when it carries `name=` and does **not** carry `nomenu="1"` — the attribute
  Winamp itself uses. Defix marks its `browserpro`, `notifier` and two `searchresults` popups
  `nomenu="1"`; its `SUI` and `VISCON` carry no name because its own buttons reach them
- the main player is never listed, and neither is a container the **surface catalog** already routes
  (`WinampModernSurfaceCatalog.routedContainerIDs`) — the playlist/EQ/library have their own menu
  items, and a second entry would be a second route to one window. Container *kind* is not enough to
  spot those: Defix's `pledit` declares no `component=` GUID and is recognized from the declarative
  inventory
- it is deliberately **not** routed through `WinampModernSurfaceCoordinator`: that resolves a playback
  surface across embedded / declared / classic homes, and these are skin windows with no NullPlayer
  surface behind them

Measured: Defix → `SPEAKER 1`, `SPEAKER 2`, `Skin Settings`; mmd3 → `ColorThemes`; cPro-Bento →
`Widgets Manager`; CornerAmp Redux → `Color Themes`; T800 → `Quadhelix Home`; stock Winamp Modern →
none. The harness prints the list as `RENDER-DUMP skin windows:` — gated, since B26, by whether a
renderer can actually open the container, with the excluded ones printed as `RENDER-DUMP dropped
container:`. A container whose `name` is an unresolved string-table reference (`:componenttitle`,
the wasabi standard `Component` shell in three skins) is not listed. Phase 27, B26.

`default_visible="1"` **is honoured** as of Phase 40 — a skin that expects one of these open at load
(Defix's configurator and playlist editor; 10 containers in 8 of the 17 skins) starts with it on
screen, placed by the skin's own `default_x`/`default_y` relative to the player. It is a *default*: a
window the user closes stays closed for that skin. A `notifier`/`tooltip` container and one holding a
`<browser>` are the two suppressed cases, each recorded in the skin's diagnostics. See
[reference/components.md](reference/components.md) §*`default_visible="1"`*.

### Skin Settings — the options a skin registers but binds nothing to

A Winamp 5.x skin registers its own options with `Config.newItem(name, guid)` +
`ConfigItem.newAttribute(value, default)` and expects **Winamp's preferences dialog** to list them.
A skin that binds no control of its own to an attribute therefore leaves it unreachable in a host
that has no such dialog. Defix Hi-End 200 registers 38 attributes that way, including its eight
display styles (`Audio cassette` and seven analog VU meters, all of whose artwork ships) and its
three songticker modes.

**Winamp Modern → Skin Settings...** is that missing dialog:

- **Generic.** It lists exactly what the loaded skin registered, in registration order, grouped by
  the item that owns it. No skin is named anywhere in it.
- **Value shape decides the control.** A `0`/`1` value draws as a checkbox; anything else as a text
  field, because the skin's meaning for it is unknowable from here. Winamp's config is a tree, and a
  root item registers one attribute per **child item** whose value is that child's GUID (6 of Defix's
  38); those are navigation, not options, and stay out of the list.
- **One write route.** Changes go through `WinampModernScriptRuntime.setConfigAttribute`, the same
  path a `cfgattrib` control the skin drew itself uses **and the path a script's own
  `ConfigAttribute.setData` takes since Phase 45**, so the skin applies the change from its own
  `onDataChanged` exactly as it would in Winamp — and a switch in this window and the control that
  mirrors it in the skin cannot disagree. The broadcast half is what matters: a skin registers the
  same attribute once per script, so a write that only tells the caller reaches one window.
- **A radio group is the skin's logic, not the list's.** Defix's eight display styles and three
  songticker modes are each a group of `0`/`1` attributes whose exclusivity lives in the skin's
  `onDataChanged` (picking one writes `0` to the others, and the list re-reads every row after a
  write). Where a skin does *not* enforce it, the checkboxes behave exactly as Winamp's do: Defix's
  songticker handler tests `Disable` first, so *Modern* only takes effect once `Disable` is unticked.
- **Empty state.** A skin that registers nothing shows **no menu entry**, rather than an empty window.
- Palette-themed through `WinampModernSurfaceStyle` like every other NullPlayer-drawn surface, and
  torn down with the skin it belongs to.

The headless probe is `WINAMP_MODERN_RENDER_SETTINGS=1` on the render-dump harness, which prints
every registered attribute with its current and default value. Phase 27.
