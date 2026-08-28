# Loading a `.wal` skin

Reference for the `winamp-modern-skin-guide` skill: VFS mounts, the initialization passes, the retained object graph, and the coordinate conventions.

### VFS mounts

Fixed logical mounts only — the skin never sees a real path:

| Logical path | Backed by |
|--------------|-----------|
| `/Skins/<sanitized-name>/` | the `.wal` archive |
| `/Skins/<other skin>/` | another **installed** `.wal`, mounted lazily — see *Sibling skin mounts* |
| `/Plugins/classicPro/engine/` | the imported ClassicPro engine, when installed |
| `/System/` | code-supplied defaults via `WinampModernAdditionalMount` |

Path variables: `@WINAMPPATH@`, `@SKINPATH@`, `@COLORTHEMESPATH@`, `@DEFAULTSKINPATH@`,
`@SKINSPATH@` (= `/Skins`, the skins *collection* root — the whole Big Bento Modern family writes
`@SKINSPATH@\<Skin Name>\xml\player.xml`, 420 occurrences in the 36-skin corpus and all of them in
that family). Windows
separators, `.`, and `..` are normalized; a path escaping `/` is a hard error. A `*` wildcard is
allowed **only** in the final include component and returns sorted, deterministic results.

**`@HAVE_LIBRARY@` is a markup macro, not a path variable.** After the include graph is expanded,
every XML attribute value replaces it with `1`, because NullPlayer hosts a Media Library surface;
unknown `@…@` macros remain unchanged. The ordering matters: the resolved document is what surface
inventory, synthesis, type registration and object creation all read. Four measured skins put the
macro on a Media Library container's `default_visible`, while Defix also passes it to a script.

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

### What the XML parser tolerates, and what it still rejects

`WalLenientXMLParser` accepts multiple roots and raw ampersands. It also, since B33, accepts a file
that **runs out before it closes everything it opened**: the EOF check emits a `malformedXML`
**warning** at the open tag's location and returns the tree. Nothing is lost by doing so — a node is
attached to its parent (or to `roots`) when it *opens*, not when it closes, so by the time the check
runs the unclosed tag already holds all of its children and every sibling written after it.
`maximumDepth` still bounds how much can be left open, so nothing about the sandbox changes.

`Shield_Amp` is the measured case and was the only skin of the 30 installed that failed outright:
`opensource_notifier/notifier.xml` opens two `<container>`s, closes one, and ends on a
`<script file="…"/>`. Winamp loads it. The throw cost the skin all nine of its surfaces.

`parse` therefore returns `WalParsedXML { roots, diagnostics }` rather than `[WalXMLNode]`, and
`WalXMLDocumentLoader.loadFile` folds those diagnostics into the document's own list, so the warning
reaches the compatibility report like any other. Still hard errors, unchanged: an **unexpected
closing** tag (a `</foo>` matching nothing on the stack — no corpus skin does this, so it stays strict
until one demands otherwise), an unterminated comment, declaration, tag or attribute value, a tag
with no name, and every depth/node-count bound.

### Sibling skin mounts

An **overlay skin** is written against another skin: its own archive ships only what it changes and
it pulls the rest out of the base skin's directory by name through `@SKINSPATH@`. Both *Light*
editions of Big Bento Modern are overlays — 6 of the 8 includes in their `skin.xml` come from the
base archive, only `color-presets.xml` and `system-colors.xml` are their own — which is exactly how a
one-palette variant ships as a 300 KB archive.

So the VFS mounts a sibling **lazily**: when a path lands under `/Skins/<name>/…` that **no mount
already owns**, `WalVirtualFileSystem.mountSiblingIfNeeded` asks `siblingMountResolver` for it and
mounts what comes back at `/Skins/<name>`. `WinampModernSkinLoader` installs that closure; it looks
in the directory holding the archive being loaded first (so a `.wal` opened from `~/Downloads`, or by
the render-dump harness, finds the sibling next to it), then in
`WinampModernSkinImporter.defaultDestinationDirectory()`, matching `safeMountName(basename)`
case-insensitively — a *sanitized* name comparison, never a host path built from a skin-supplied
string.

- **The skin's own self-references never reach the resolver.** Big Bento writes
  `@SKINSPATH@\Big Bento Modern\…` 159 times for its *own* files; its own mount owns those paths, so
  the "no mount owns it" gate short-circuits every one. Do not add a self-mount special case.
- **Bounded** (security-model rule 2): at most **4** sibling archives per load (`entryLimitExceeded`
  past it), each opened with the same `archiveLimits` as the main skin, and a name the resolver
  answers `nil` for is memoized so a hostile skin cannot force one directory scan per reference.
  No cycle detection is needed — a name is mounted at most once and include cycles are caught by
  `WalXMLDocumentLoader`.
- **A missing base names itself.** `missingRequiredMount` — *"This skin requires the skin 'X' to be
  installed."* — is deliberately **not** `resourceMissing`, so it bypasses both tolerance blocks that
  would otherwise swallow it into a half-loaded skin (the missing-include warning above, and
  `resolveSkinResource`'s `@SKINPATH@` fallback). Same rule as the ClassicPro engine: *the thing you
  need is not installed* stays a named, hard failure. There is deliberately **no** renamed-archive
  leniency: falling back to the current skin's mount would silently draw an overlay against the wrong
  artwork.

The contract this puts on the user: **the installed filename must match the skin name the overlay
asks for.** `Big Bento Modern.wal` renamed is `Big Bento Modern Light` failing to load.

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
  definition of its id takes the first rather than nothing. The redefinition still warns —
  **but only when it actually differs** (B29). A skin sharing an elements file between two containers
  re-includes every resource and `<groupdef>` in it, which is ordinary Winamp practice and was 198 of
  LOBE's 233 findings; a definition is compared on what it *is* (a resource: kind + logical file +
  attributes; a groupdef: XUI tag, `inherit_group`, `embed_xui`, defaults and the whole template
  subtree via `WalXMLNode.isStructurallyEqual(to:)`), with the source location ignored. Corpus:
  1343 → 851 diagnostic occurrences over 30 skins, and every differing redefinition still reported.
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

**An undecodable image degrades; an oversized one still fails.** A `<bitmap>`/`<cursor>`/
`<bitmapfont>` whose file *exists* but has no valid image metadata registers **without** its
`logicalFile` and records an `invalidImageResource` **warning** — the renderer already answers `nil`
for an image it cannot decode, on every path. The Big Bento Modern Windows 10 edition ships a
zero-byte `window/no_alb_art_shade.png`, and that one dud PNG failed the *whole* skin. The memo is
per resolved path, so a second `<bitmap>` naming the same dud file degrades too. `validateImage`
itself is unchanged and `imageDimensionsExceeded` stays a hard error: that one is the *bound*, not a
content problem, and so is every traversal/escape/variable failure.

### A skin's settings must start in a state its own scripts can express

`WinampModernConfigDefaults.apply` runs in `WinampModernSkinLoader.load`, **before** the runtime is
handed out, because a skin lays its windows out from these values inside `onScriptLoaded` — a seed
written afterwards arrives a whole layout late.

It exists for one shape, and the file is meant to stay nearly empty: a set of `cfgattrib`s the skin
treats as a **radio group** (its own `onDataChanged` forces exactly one member to `"1"` and zeroes the
siblings), where every member is registered with a `"0"` default. A profile that has never run the
skin then lands **all-zero — a state the skin has no branch for**, and Winamp only avoids it because
its config file already carries a choice. Big Bento Modern's tab strip is the measured case (BB29):
`tabswitch.maki`, `tabcontrol.maki` and `tabbutton.maki` are each a three-way `if` with no `else`, so
all-zero skipped every branch, the strip's divider kept its markup `x` of 0 and drew *over* the icons,
and its button was dead for ever — `onLeftClick` only cycles *between* the three states.

Two properties make it safe to keep: it is keyed on the skin's **own markup** (the group is only
considered when the document binds a control to a member, and the section GUID comes from that
binding, so a skin that declares none of them is untouched), and it is idempotent — once any member
reads `"1"`, whether from this seed or from the user's own pick, nothing is written again.

> **This is not the place for "the skin looks nicer this way."** The value seeded has to be the one
> the skin's *markup* is already laid out for, so it restores the author's arrangement rather than
> choosing a look. Bento's markup ships `sui.tabs w="40"` / `sui.components x="57"` — the exact
> numbers its icons branch writes — which is what makes `Tabs: Icons` the authored start.

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

**The `relat*` flags are `atoi(value) != 0`, not `== 1`.** Skins ship other numbers and mean nothing
by them beyond "relative": Big Bento Modern's dimmed album-art backdrop is `relatw="2" relath="2"`,
Ebonite_2_1 has six declarations at `relatw="2"`, and The_Nokia_5220 has two at `relatw="5"`. Read as
`== 1` every one of those silently fell back to **absolute** geometry — which is how Big Bento's
oversized backdrop came out as a *small crisp second copy of the album cover* beside the real one, a
defect that reads as "the album art is drawn twice" and sends you looking at the album-art code.

Two traps in the same attribute:

- **Do not read the number as a percentage.** It fits the values that first suggest it — Bento's
  `99`/`100`, Ebonite's `85`/`93` — and then breaks on Ebonite's own `group w="0" h="0" relatw="2"`,
  where 0% collapses the group but the plain relative reading gives the ordinary fill-the-parent
  idiom, and on `relatw="5"`, which is not a percentage at all. Enumerate the whole corpus before
  believing a mechanism derived from two skins.
- **A non-numeric value must stay absolute**, because that is also `atoi`'s answer and two skins
  depend on it: corneramp_redux and Shield_Amp ship a literal `relatw="%"`.

Use `atoi` semantics (leading integer), not `Int(_:)`, which refuses a trailing character and would
send `"1px"` down the opposite branch from the one Winamp takes.

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
