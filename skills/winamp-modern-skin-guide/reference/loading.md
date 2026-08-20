# Loading a `.wal` skin

Reference for the `winamp-modern-skin-guide` skill: VFS mounts, the initialization passes, the retained object graph, and the coordinate conventions.

### VFS mounts

Fixed logical mounts only — the skin never sees a real path:

| Logical path | Backed by |
|--------------|-----------|
| `/Skins/<sanitized-name>/` | the `.wal` archive |
| `/Plugins/classicPro/engine/` | the imported ClassicPro engine, when installed |
| `/System/` | code-supplied defaults via `WinampModernAdditionalMount` |

Path variables: `@WINAMPPATH@`, `@SKINPATH@`, `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`. Windows
separators, `.`, and `..` are normalized; a path escaping `/` is a hard error. A `*` wildcard is
allowed **only** in the final include component and returns sorted, deterministic results.

Cross-mount climbs work, which is how cPro-Bento reaches its engine:
`@COLORTHEMESPATH@\..\..\Plugins\classicPro\engine\load.xml`.

**A missing `<include>` is a warning, not a failure** (Phase 35) — Winamp warns and carries on, and
two shipped skins (`Itemskin`: `xml/eq.xml`, `Overdrive_2`: `xml/pledit-elements.xml`) name a file
their archive does not contain. The expander skips it, records `resourceMissing` at `.warning`, and
expands the rest of the document; this is the same tolerance `WasabiSkinInitializer` applies to a
missing bitmap, cursor or TTF. **Scoped to the skin mount:** the tolerance only covers a path that
resolves inside `@SKINPATH@`. An include that climbs into another mount — the ClassicPro engine line
above — still fails the load, because that one means *the engine is not installed*, and a skin that
loads and draws almost nothing is worse than a named error. Cycles, depth, expansion limits, path
escapes and unresolved variables are all unchanged: still hard errors.

### Initialization passes

`WasabiSkinInitializer` runs six explicit, tested passes, in this order:

1. resource registration
2. groupdef/XUI registration + inheritance validation
3. object creation
4. script binding
5. initialization
6. first-paint preparation

Group semantics worth knowing:

- `inherit_group` **is** the inheritance edge (depth limit 64, cycle-detected).
- `embed_xui` is retained as metadata and is **not** an inheritance edge. It does two jobs: the
  instance's children are created under the object it names, **and** that object *is* the XUI, so the
  pointer events it receives are forwarded to the embedding group. Defix's `bento.tabbutton` embeds a
  `mousetrap` button while the core script hooks `onLeftClick` on the group (`switch.ml`) — without
  the forwarding every tab lit up under the pointer and switched nothing.
- `xuitag` registers a custom XML tag name for group instantiation.
- A duplicate definition does **not** replace the earlier one wholesale: every version is kept, and a
  `<group>` expands the version in force *where that group is written*. Winamp's parser is streaming,
  so an id redefined mid-document serves the groups after it and leaves the ones before it alone.
  T800 is the measured case — it gives `player.main.cms` one body for its full player and a
  completely different one for its shade layout; last-wins gave the full player the shade's controls,
  most of which then fell outside the canvas and were culled, leaving every button in the skin dead.
  `WasabiGroupDefinition.documentOrder` is the node's pre-order index in the expanded document
  (`documentOrder(of:)`); `definition(forInstance:documentOrder:)` picks the newest version at or
  before it. Template children inherit the position of the reference that expanded them, which is
  when Winamp would have read them. Two deliberate leniencies: a reference with no document position
  (`System.newGroup`, a synthesized node) takes the newest version, and one that precedes every
  definition of its id takes the first rather than nothing. The redefinition still warns.
- `registerWasabiStandardLibrary` seeds the curated `wasabi.*` base groups that ship inside Winamp
  rather than in the archive. Skin/engine definitions register first and always win. A base outside
  the curated set warns and is dropped rather than failing the load.
  - The shells are **identifier-only on purpose** — a body would push structure we invented into every
    skin that inherits it. `wasabi.titlebar` is the one measured exception: a clean-room
    `<text default=":componentname">` filling the box, because CornerAmp instantiates
    `<Wasabi:TitleBar>` inside its own standard frame and never defines the tag, so every CornerAmp
    window came up with a nameless title bar. It invents no artwork (CornerAmp ships no
    `wasabi.titlebar.*` bitmaps) and adds exactly one node per framed window.
  - Two alias passes, and the order matters: `WasabiStandardFrames.conventionalXUITags` runs *before*
    seeding (its destinations are the skin's own groupdefs), `wasabiStandardLibraryXUITags` *after*
    (its destinations are the shells). Both only fill an *unclaimed* tag, so a skin's own `xuitag=`
    always wins.

### Retained graph and coordinates

**`findObject` is the wide lookup, `getObject` the narrow one.** `getObject(id)` searches the
receiver's own subtree; `findObject(id)` searches that subtree **first and then the rest of the
container**, which is the whole reason a skin reaches for one name over the other. Defix's core
script holds `sui.content` and asks it for `switch.ml`, a tab button in a *sibling* subtree: resolved
from descendants alone, all five tab lookups came back null and the script bound its handlers to
nothing, so the SUI never changed tabs. The nearest match still wins, so a skin with the same id in
both places keeps getting its own.

`WasabiObjectGraph` owns every node (including detached ones). IDs are monotonic and deterministic
for a deterministic expanded document, which makes `snapshot()` the golden-test surface. XML `id`
values are attributes and are **not** unique, so `objects(xmlID:)` returns an array.

Geometry stays in **Wasabi top-left coordinates** throughout the graph. The signed-anchor rule is
encoded in `WasabiGeometry`:

- `x=-60 relatx=1` → `parent.width - 60`
- `w=-120 relatw=1` → `parent.width - 120`
- same for Y/height; missing dimensions use the intrinsic size

> **Gotcha:** the Y flip to AppKit's bottom-left happens exactly **once**, at the Core Graphics
> drawing boundary in `WasabiSceneRenderer` (and once at the event boundary in `WinampModernMainView`).
> Never store flipped coordinates back into the graph, and never insert AppKit types into graph objects.

A `<layout>`'s `w`/`h` are **optional**, exactly like any other object's: one that declares neither
is sized by its `background` bitmap (`WasabiSceneRenderer.defaultSize(for:resources:)`), and only a
layout with no background at all falls through to the classic 275×116. ZDL's Reel-To-Reel writes
every one of its layouts that way — with the old unconditional fallback its 275×348 player got a
275×116 canvas, everything below the reels landed outside it where `append` culls it, and what was
left stacked on top of the reels. Same rule in the two collapsed-window checks
(`WinampModernContainerTopology`, `WasabiSurfaceInventory.isVisibleWindow`): a window is collapsed
only when it *declares* a ≤2px box, or a skin that sizes its equalizer from art looks like it has
none and gets a synthesized one built over the top of it.

`fitparent="1"` fills the parent regardless of `x/y/w/h`. Winamp Modern and ClassicPro use it
constantly for their SUI/content groups; without it those groups resolve to a 0×0 rect at the origin
and every descendant collapses into the top-left corner.

#### The protective window minimum

A `<group>` whose box the skin **declared** (its own `w`/`h`, or `fitparent`) clips its children,
because a group is a window in Wasabi — Defix's cassette display is a 263×79 group holding a 117×117
reel bitmap, and unclipped both reels spilled 53px below the cassette and painted over the song
ticker beneath it. A group with **no** declared box does *not* clip: its rect is one the renderer
inferred, and clipping children to a guess erases content that is really there. Across the 15
measured skins the rule changes four rendered images and leaves 13 skins byte-identical.

`layoutMinimumSize` is **not** just the layout's `minimum_w`/`minimum_h`. Those numbers are written
for Winamp, where every group clips its children; we clip a declared group and inherit otherwise, so
past a certain size a child that no longer fits can still paint over its siblings. The
renderer therefore probes for the smallest size at which the scene still lays out the way its author
drew it, and raises the declared floor to it (`computeProtectiveMinimumSize`). Every window's
`contentMinSize`, `resize()`, and `clampRestoredFrame` go through the same number.

A layout that declares **no** range at all (none of `minimum_w`/`minimum_h`/`maximum_w`/`maximum_h`)
is a different case: it is fixed at its own size, and `userResizeLimits` reports that size as both
limits so the window cannot be dragged or restored to anything else. Only the user-facing range is
pinned — a script's `resize()` still goes through `resize(to:)`'s own clamp.

The reference is the layout's own **default size** — at the size a skin ships at, its scene is
correct by definition, so overhang present there is deliberate and only failures introduced by
shrinking count. There are two failure kinds and they are tracked **separately**: an object escaping
the box it resolved against, and an object vanishing from the scene (`append` culls a node that
lands wholly outside its parent). Counting only the first loses the search's monotonicity — a wildly
overflowing object stops being counted once it leaves its parent completely — and merging them lets
an object that is allowed to overhang also silently disappear. The result is capped at the default
size, so this can never make a window bigger than the skin describes. It costs ~20 scene builds per
layout, cached per layout id.

#### The two y-origin conventions (source of a whole class of bugs)

Three different APIs are involved and only one of them is bottom-left:

| Operation | Origin | Rule |
|---|---|---|
| Wasabi `y=` in XML, graph frames | top-left | native, never converted |
| `CGImage.cropping(to:)` | **top-left** | indexes raw pixel rows — pass the Wasabi `y` **unchanged** |
| `CGContext.draw(image:in:)` | bottom-left | places the image's *bottom* row at `rect.minY` |

Because `draw(in:)` runs under the renderer's flipped CTM, `rect.minY` is the visual *top*, so every
bitmap must be re-flipped about its own rect or it renders vertically mirrored in place. That is what
`drawImage(_:in:context:)` exists for — **use it for every image draw**, never `context.draw` directly.
`drawFlippedText` does the same job for text.

Converting a Wasabi `y` to a bottom-left origin before `cropping(to:)` mirrors the source rect about
the sheet's centreline, so every sprite is cut from the wrong row of the atlas. Sprite-sheet crops in
`drawBitmapText` and `drawAnimated` index rows directly for the same reason.

A **clip mask** goes through the same rule as a drawn image, and cannot be re-flipped afterwards the
way `drawImage` re-flips its rect — restoring the graphics state would discard the clip. So the mask
is built pre-flipped instead (`WasabiResourceCache.regionMask`, which reads its source buffer bottom
row first). A mask built the wrong way up looks plausible on a symmetric control and is wrong on
every other one.

