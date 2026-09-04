# Loading a `.wal` skin

Reference for the `winamp-modern-skin-guide` skill: VFS mounts, the initialization passes, the retained object graph, and the coordinate conventions.

### VFS mounts

Fixed logical mounts only — the skin never sees a real path:

| Logical path | Backed by |
|--------------|-----------|
| `/Skins/<sanitized-name>/` | the `.wal` archive |
| `/Skins/<other skin>/` | another **installed** `.wal`, mounted lazily — see *Sibling skin mounts* |
| `/Skins/Default/` | Winamp's stock Modern skin — **usually nothing**, see *`@DEFAULTSKINPATH@` is an optional mount* |
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

**A path a skin writes starting at the root means the *skin's* root** (B45). In Winamp the skin is
the filesystem it names, so `<include file="/standardframe/standardframe.xml"/>` reads from the skin
directory; here the skin is one mount inside a larger VFS, and taking that `/` literally lands
beside the mount rather than inside it. `WalVirtualFileSystem.resolve` therefore tries the literal
reading **first** and re-bases on `@SKINPATH@` only when nothing exists there — so this loader's own
entry paths, another mount, and every `@SKINPATH@`/`@SKINSPATH@` expansion (already absolute, and
which would nest the skin root inside itself if re-based) all keep resolving exactly as before. Only
paths written *raw* with a leading separator are re-based, and the fallback is what a failure still
names when neither reading exists. **1 site in the 36-skin corpus**
(`rg -o 'file="[/\\][^"]*"' "$corpus"`) — Shield_Amp's `xml/pledit-normal.xml:3`.

**A missing `<include>` is a warning, not a failure** (Phase 35) — Winamp warns and carries on, and
two shipped skins (`Itemskin`: `xml/eq.xml`, `Overdrive_2`: `xml/pledit-elements.xml`) name a file
their archive does not contain. The expander skips it, records `resourceMissing` at `.warning`, and
expands the rest of the document; this is the same tolerance `WasabiSkinInitializer` applies to a
missing bitmap, cursor or TTF. **Scoped to the skin mount:** the tolerance only covers a path that
resolves inside `@SKINPATH@` — or inside `/Skins/Default`, the one root a skin may name with nothing
behind it (see *`@DEFAULTSKINPATH@` is an optional mount*). An include that climbs into another mount — the ClassicPro engine line
above — still fails the load, because that one means *the engine is not installed*, and a skin that
loads and draws almost nothing is worse than a named error. Cycles, depth, expansion limits, path
escapes and unresolved variables are all unchanged: still hard errors.

**The tolerance covers the include that names the missing file, and nothing deeper** (B45). It used
to wrap the recursion as well, which attributed every depth to the outermost node: one unfound
include discarded everything its *parent* file contained, silently, and under the parent's name.
Shield_Amp's `xml/pledit.xml` is a `<container id="Pledit">` whose only child is
`<include file="pledit-normal.xml"/>`; that file's own root-relative include failed, the whole of
`pledit-normal.xml` was dropped, and the container was built **empty** — a playlist window the PL
button could never open, reported by the render sweep only as `dropped container: Pledit (no
layout)`. It also laundered the one failure the skin-mount scope exists to keep fatal, since a
ClassicPro engine include nested under an ordinary in-skin one was judged by the *outer* path.

### A container root's id has to be unique, and the source location says how to make it so

Every consumer downstream of expansion addresses a window by its **id string** — `WasabiSceneRenderer`'s
`containerID`, the Skin Windows menu, `TOGGLE`'s container fallback, and the per-container layout and
frame persistence in `WinampModernSkinState`. A second container root claiming an id another already
holds is therefore unreachable: it is never the answer to a lookup for that id. Two causes produce
that shape, and they want opposite answers, so `WasabiSkinInitializer` keys the first declaration's
**source location** and compares (B96):

- **Same location — one declaration reached twice.** A skin that includes the same file from two
  places gets two container roots out of one `<container>`; `jvc.tape.v0.5` reads `xml/pledit.xml`
  from both `skin.xml` and `xml/amp.xml`, and its `Pledit` came out twice. The repeat is **dropped**,
  with a `duplicateIdentifier` warning. This is the container-root half only — re-including an
  elements file to share its resources and `<groupdef>`s is ordinary Winamp practice and is untouched
  (see the duplicate-definition rule below). B75, a skin that runs every handler twice because it
  includes the same *script* twice, is the script-side sibling and is still open.
- **Different locations — two declarations sharing an id.** `WMP11-BlueVU/xml/VU-Meters.xml` writes
  `<container id="Meter" name="VU Meters Large">` and then `<container id="Meter" name="VU Meters
  Small">`. Both are windows the skin means to ship, so both are **kept**, and the second is renamed
  to `Meter#2` (`#3` for a third, and so on) so it can be addressed. The **first** keeps the declared
  id, which is what Winamp's own container table answers with, so `getContainer("Meter")` and every
  persisted key resolve exactly where they did. The skin's `name=` is untouched — that is what the
  Skin Windows menu shows, and it is the only thing telling the pair apart to a user.

Corpus: one rename (`WMP11-BlueVU`) and one drop (`jvc.tape.v0.5`) across all 70 archives; every other
skin takes the identical path, because the branch only fires on a repeated container-root id.

**Do not read `resolved=0` on a repeated container id as an engine defect.** The render dump keys its
renderers by container id and tears each one down at the end of its turn, so before this a duplicate
id took two turns on one renderer and the second ran against a **torn-down** cache — reporting
`resolved=0` and listing the *first* container's bitmap ids as missing. That is the harness, not the
skin's resource scope. `jvc.tape`'s `Pledit` missing `pl.button.bg` and `pl.button.small` is a real
and separate two-bitmap miss.

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

### A byte order mark decides the encoding, and it has to be read before the fallback chain

`WalXMLDocumentLoader.decodeText` sniffs the mark — UTF-32LE/BE, UTF-8, UTF-16LE/BE — strips it, and
only then falls through to the old chain of UTF-8 then ISO-8859-1. **The order is the whole point.**
ISO-8859-1 maps all 256 byte values, so it accepts any input whatsoever and can never report a wrong
guess; a decoder chain ending in it has no failing branch to hang a third encoding off. Before B93 a
UTF-16 file failed UTF-8 (on `ff fe`, which is not valid UTF-8), landed on ISO-8859-1, and came back
as one character per byte with the nulls intact — so the parser read `ÿþ<\0g\0a\0m…`, scanned every
`<` as an opening tag, matched no `</` against any of them, and climbed until the depth guard threw:

```
colorthemes.xml:260:6: [xmlDepthExceeded] XML nesting exceeds 256 levels.
```

The guard was right and the skin still did not load. `cpro2_dark_aluminum` is the measured case, and
it was refused outright. Note the two orderings that matter inside the sniff: `ff fe` opens **both**
UTF-16LE and UTF-32LE, so the 4-byte marks are tested first, and a UTF-8 mark is *stripped* rather
than decoded, or a leading U+FEFF sits in front of the first tag.

Reach was measured at 3 files across the corpus and only the one on an include path was fatal
(`languages/Wasabi.xml` in both Big Bento Modern editions is never included). **Treat that as a
floor, not the reach** — Windows XML tooling emits UTF-16 by default, so an author on Windows
produces one without deciding to.

### `loadMap("file.png")` resolves against the **skin**, not the calling script

`Map.loadMap` takes either a declared `<bitmap>` id or a path, and the path form is relative to the
skin — an engine's scripts live in their own mount and read the *skin's* artwork by bare filename.
ClassicPro's `player.maki` sizes the Winamp corner bolt with `loadMap("buttons.png")` and gives the
button its `image`/`downImage` only when `getWidth()` answers 332; resolved beside the script (in
`/Plugins/classicPro/engine/one/scripts/`) the file was never found, the width came back 0, and the
logo was invisible at rest — its `hoverImage` is the only artwork the markup declares, so it appeared
only under the pointer. Try the script's own directory first, then `vfs.skinRoot`, and require the
file to **exist** at each step rather than returning the first path that merely canonicalizes.

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

### `@DEFAULTSKINPATH@` is an optional mount, and the only one

`@DEFAULTSKINPATH@` means Winamp's **stock Modern skin**, which sits beside the user's own skins in a
real installation. NullPlayer ships none, so `/Skins/Default` is normally empty. A skin names it to
borrow windows it does not style itself: canum's `skin.xml` pulls `xml/eq.xml`, `xml/thinger.xml` and
`xml/pledit.xml` out of it, and there is no reason to expect the corpus to stop at one.

Two rules, both of which cost canum its whole load before B92:

- **It carries a trailing separator**, set through `setVariable(…, trailingSeparator: true)` exactly
  like `@SKINPATH@` and `@COLORTHEMESPATH@`, because skins concatenate a filename straight onto it.
  Assigned bare, `@DEFAULTSKINPATH@xml/eq.xml` canonicalises to `/Skins/Defaultxml/eq.xml` — and the
  fused name comes back out of the sibling mount verbatim, as *"requires the skin 'Defaultxml'"*.
  **A mount name in an error that is two words run together is this bug**, not a corrupt skin.
- **An unanswered path under it is `resourceMissing`, not `missingRequiredMount`.**
  `mountSiblingIfNeeded` returns `false` for this root rather than throwing, so the include expander's
  skipped-include warning applies (`WalXML.isInsideSkin` accepts `/Skins/Default/` alongside
  `vfs.skinRoot`) and `WasabiSurfaceSynthesizer` then builds the surface out of **the skin's own
  frame**. That is nearer to what the author asked for than refusing the skin.

**Do not alias `Default` onto `winampmodern566.wal`.** It is the *Winamp5 Base Skin*, a reference
subset: it has `xml/pledit.xml` and neither `xml/eq.xml` nor `xml/thinger.xml`, so two of canum's
three includes would still fail — and the shipped stock skin they were written against is not in the
corpus at all. A skin genuinely installed as `Default.wal` is still mounted and still resolves; that
path is unchanged.

**This is the only optional root.** Every other absent sibling mount stays the hard, named
`missingRequiredMount` above, and so does the ClassicPro engine — an overlay drawn against missing
artwork, or a cPro skin with no engine, must say so rather than half-load.

### Initialization passes

`WasabiSkinInitializer` runs six explicit, tested passes, in this order:

1. resource registration
2. groupdef/XUI registration + inheritance validation
3. object creation
4. script binding
5. initialization
6. first-paint preparation

Group semantics worth knowing:

- `inherit_group` **is** the inheritance edge (depth limit 64, cycle-detected). The derived group
  wins on **children** as well as attributes: a derived child that redeclares an inherited `id`
  replaces that child **in the base's slot**, so the base's draw order survives, and any other
  derived child appends. An inherited child the derived group is silent about still draws.
  Appending both lists instead built the whole subtree twice (B116): WMP11-BlueVU redeclares
  `wasabi.frame.layout` at `h="-69"` where `wasabi.standardframe.nostatusbar` has `h="-12"`, and
  `RENDER_PROBE main/normal` showed both — 354x135 *and* 354x78 — each dragging a duplicate
  `frame.top.middle` (edge strips, titlebar, caption buttons) drawn every frame. The duplicates
  landed mostly on top of each other, which is why it read as cost rather than as a visible
  defect. Keeping the un-redeclared children is load-bearing in the other direction: that skin
  never redeclares `frame.bottom`, and dropping the base's children would take its bottom border
  with them. `WasabiSkinInitializer.merging(inherited:with:)`.
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
    always wins. The standard-frame pairs are in **both** lists on purpose — a skin that declares
    the groupdef is aliased to its own in the first pass, and one that declares none falls through
    to the shell in the second. Before B95 they were only in the first, so a skin with no frame of
    its own left `<Wasabi:StandardFrame:*>` resolving to *nothing at all*.

#### A standard frame the skin never defined instantiates its own client area (B95, 2026-09-01)

A `<Wasabi:StandardFrame:*>` **names its body by group id** — `content="player.content.group"` —
and in real Winamp the frame's own `standardframe.maki` does the `newGroup(getParam("content"))`.
A skin that ships that groupdef ships the script with it; a skin that expects Winamp's ships
neither, so the named group never entered the graph at all. Not undrawn — **absent**, the same shape
as [`WasabiTitleBox`](rendering.md) and `<Wasabi:Frame>`'s two panes.

`Winamp 3.0 Default` — Nullsoft's own *"Winamp3 Base Skin"* — is every full-size layout of one such
frame, and it measured **9 nodes, `resolved=0`**: a blank white 275x116, the only skin in the corpus
that loaded and rendered nothing. Its windowshade layouts are plain groups and always drew fine,
which is what isolates the cause to the frame rather than to the skin. B95 was filed against the
missing `wasabi.*` chrome bitmaps; that is real but it is the *survivable* half — Formamp and
corneramp_redux are missing part of the same set and render acceptably. The frame is the fatal half.

`WasabiStandardFrames.contentGroupNode` supplies the client area and the initializer expands it onto
the frame **instance**, beside the `<Wasabi:TitleBox>` and `<Wasabi:Frame>` expansions, gated on
`!claimedBySkin`. Three things worth keeping:

- **`contentInset` is measured, not chosen.** `Winamp 3.0 Default`'s `placeholder` sits at `6,5` in
  its content group and lands at `11,20` in the skin's own `screenshot.png`, which puts the client
  origin at `5,15`; its resize grip is a 16px sprite at `254,85`, so the client must be at least
  270x101 inside a 275x116 window. That is the whole derivation of `(5, 15, -5, -15)`.
- **The title strip goes on the instance, never in the shell's body.** The shell is also reachable
  as an ordinary base — EPS's notifier writes
  `<group id="wasabi.standardframe.nostatusbar" x="0" y="0" w="0" h="0" relatw="1" relath="1"/>`
  and wants the empty base it asked for. Putting the strip in `shellTemplateChildren` pushed a stray
  object into it, and `testEveryOtherShellStaysIdentifierOnly` is the guard that caught it.
- **`window.titlebar.title` is the one object such a skin addresses by name.**
  `<sendparams target="window.titlebar.title" default="WINAMP"/>` is how `Winamp 3.0 Default` names
  its own player, so the strip carries that id or the send lands nowhere.

Reach when this landed: **5 skins, 18 layouts** — `Winamp 3.0 Default` (8 layouts, blank → fully
drawn), TomK (`gallery` and `colorwnd`, empty windows → the image gallery and a working theme list),
corneramp_redux (5), Overdrive_2 and jvc.tape (playlist titles). The other 31 skins and 531 layouts
in the sweep are pixel-identical.

**An undecodable image degrades; an oversized one still fails.** A `<bitmap>`/`<cursor>`/
`<bitmapfont>` whose file *exists* but has no valid image metadata registers **without** its
`logicalFile` and records an `invalidImageResource` **warning** — the renderer already answers `nil`
for an image it cannot decode, on every path. The Big Bento Modern Windows 10 edition ships a
zero-byte `window/no_alb_art_shade.png`, and that one dud PNG failed the *whole* skin. The memo is
per resolved path, so a second `<bitmap>` naming the same dud file degrades too. `validateImage`
itself is unchanged and `imageDimensionsExceeded` stays a hard error: that one is the *bound*, not a
content problem, and so is every traversal/escape/variable failure.

#### An attribute that names an image file gets an implicit bitmap (B94, 2026-09-01)

Wasabi creates a bitmap on the skin's behalf when an attribute names an image **file** where a
declared `<bitmap>` id was expected, so `image="play/Bar.png"` is as good as `image="volume.bar"`.
Resolving only the declared form left a skin authored entirely that way drawing none of its own
artwork: Darjah 1 declares no `<bitmap>` for its player at all, both of its layouts reported
`resolved=0`, and it fell back to NullPlayer's generic transport over a plain background. **606 such
declarations across 9 corpus skins** — Pure Inspired 184, K-jr 133, MoonLight 78, Darjah 1 75,
the three DewyTears editions 40 each, WMP11-BlueVU 10, Itemskin 6.

A second registration pass over the expanded document walks every node's attributes and, for a value
ending in `.png`/`.jpg`/`.jpeg`/`.gif`/`.bmp` that resolves to a real image in the skin, registers a
bitmap under the path string itself. Doing it here rather than at the ~24 sites that read a bitmap id
is what makes one change reach all of them — layers, buttons, sliders, an `animatedlayer`'s frame
count, `Map.loadMap`, and a script's `setXmlParam("image", …)`. The path resolves through
`resolveSkinResource`, so the declaring file's own directory is tried first and the skin root second:
Darjah writes `image="Player/Normal.png"` from `xml/player-normal.xml`.

Four bounds, all pinned in `WinampModernB94Tests`:

- **It runs after every declaration and never displaces one.** A `<bitmap>` keeps its id, its crop
  and its gamma group; an implicit bitmap is only ever created for an id nothing else claims,
  `<elementalias>` included.
- **It is the whole file.** A path form declares no `x`/`y`/`w`/`h` and no `gammagroup`, so there is
  no crop and no colour-theme tint — the same reading `background=` already takes (B90).
- **It never answers a colour request.** `registerImplicit` does not touch `colorsByIdentifier`.
- **It is not a declaration**, and `WalResourceDefinition.isImplicit` says so, because one caller has
  to tell them apart. `fontSheet` reads `<bitmapfont file=>` as an id first and a path second, and
  the id branch must take a **declared** bitmap only: MMD3 writes
  `<bitmapfont file="player/tickerfont2.png">`, and once that path had an implicit bitmap the id
  branch returned the untinted whole file, so the ticker, time, KBPS and KHZ went grey inside a
  themed player. The font's sheet carries the *font's* gamma group.

The file gets the same `validateImage` check a declared `<bitmap>` gets, sharing its memo; a failure
just declines to create the implicit bitmap, with no warning — nothing asked for the file yet, so
there is no skin to fail. A path-shaped value the archive does not contain still registers nothing
and still draws nothing, which is Darjah's remaining `play/on.png` (the file it ships is
`player/On.png`, a different directory — Winamp misses it too).

Corpus sweep, 549 renders: **62 changed across 13 skins**, every one an improvement, and MMD3 and
mmd3 byte-identical once the `fontSheet` bound was in. Two structural changes, both correct: the five
DewyTears `main` layouts resize 275x116 -> **299x113**, which is the exact size of the
`player/background.png` that now resolves, and Darjah's `main/du` drops the fallback transport node
it no longer needs.

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

### A layout with no size of its own is sized by its content

`w`/`h` are optional on a `<layout>`, and the fallback chain runs:

1. `default_w`/`default_h`, then `w`/`h` — what the author declared;
2. the `background` bitmap's size (ZDL's Reel-To-Reel declares every layout that way);
3. **the laid-out content's extent** — this rule;
4. the 275×116 classic default.

Before this, a layout with neither a box nor a background fell through to its **`minimum_w`** — the
floor it is *allowed to shrink to*, which is not a size anybody drew. ClassicPro's Widgets Manager is
the case: `<layout id="normal" minimum_h="400" minimum_w="100" noparent="1" ontop="1" nodock="1">`
and nothing else, so it opened **100×400** — a tall empty sliver — on all five cPro skins, including
cPro-Bento. Its content group opens with a 305×57 header bitmap, clipped to 92 wide.

Measured, never inferred: the layout is resolved at a candidate size, and any node escaping **its own
parent's box** is content the canvas is too small to hold, so the canvas grows by the largest escape
and the layout is resolved again. Relative children track the canvas and never overflow, so only
intrinsic artwork moves the number and the loop reaches its fixed point in one or two passes. It is
bounded to four regardless, and clamped by any `maximum_w`/`maximum_h`.

**Overflow that does not shrink when the canvas grows is not content the window is too small for** —
it is artwork drawn deliberately past its box, and no size will ever satisfy it. A stalled axis stops
and steps **back one**, to the last size not chosen to chase the residual. Two measured cases, and
the step-back serves both:

- BLAKK's video window stretches `component.bottom.middle-video`, a 407px sheet, across a 204px frame
  and reports the same 51px overhang at *every* canvas. It stalls on the first comparison, so the
  step back is to its declared 204 — which is right, and is the window its author drew.
- The Widgets Manager overflows by 213 (the header), then by a standing 3 from a list item's
  artwork. It stalls on the second comparison, so the step back is to the 313 the header asked for
  rather than all the way to the useless 100.

**The fit runs once, on the first scene resolved after `runtime.start()`** — that is when the content
exists, because a `Wasabi:StandardFrame`'s client group is instantiated by the skin's own
`standardframe.maki`, not by the markup. Measured: the Widgets Manager is 19 nodes at `init` and 30
after. A first attempt that fitted in `init` read an empty frame, left the window at 100×400 — its
whole defect — and grew four *other* skins that happened to be complete by then. Reading `canvasSize`
settles the fit, because the first thing anybody does with a renderer is ask how big its window
should be, and that read comes before the first scene is resolved.

**The result is a minimum as well as a default.** The fit only acts while the canvas is still the one
it chose, so it cannot help a window whose size arrives from somewhere else first — restored state
above all, which is how the Widgets Manager kept coming back at 100×400 every launch. Below 313 the
header is genuinely clipped, so it is not a size anyone can have meant, and the existing
`contentMinSize` plumbing carries it to the window. AppKit applies `contentMinSize` to the *next*
resize and never retroactively, so `applyLayoutConstraints` also grows an already-too-small window —
upward only, bounded by the same limits a drag obeys — and is called a second time after
`scriptsDidStart()`, because the first call runs before any content exists.
