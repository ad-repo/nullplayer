# Winamp Modern (`.wal`) — Limits, engine policy, and verification status

Part of [compatibility.md](../compatibility.md). The enforced bounds a skin cannot exceed, the ClassicPro engine policy, and how much of this surface is test-protected.

## ClassicPro engine policy

- **User-supplied only.** Nothing is bundled and no permission is requested. The user provides the
  ClassicPro installer; NullPlayer never downloads it.
- **Internal extraction.** No external tools, no temp files, **no code execution** — the `.exe` is
  parsed by NullPlayer's own NSIS-2 reader and LZMA1 decoder.
- **Narrow format support.** NSIS-2 with a solid LZMA stream only (what ClassicPro ships). Non-solid,
  zlib/bzip2, NSIS-3, and non-NSIS `.exe` files fail with an actionable diagnostic. `.zip` (including
  a nested installer) and an already-extracted folder are also accepted.
- **Validated and hashed.** Structure validation requires the `one` engine family; content is
  SHA-256 hashed. One private copy is stored and mounted read-only.
- **Native surface is three shell methods**, none on the render path:
  - `exploreFile` — reveal an **existing** file in Finder
  - `openFile` — open an **existing** file with the default app
  - `findFiles` — bounded no-op returning −1, so callers early-return

  All gate on a real, existing, non-URL, non-`~` path. Skins cannot launch executables or reach
  arbitrary paths. Embedded `<browser>` navigation is a separate, WebKit-confined capability and
  never passes through these native methods.
- **Version gate.** `WinampVersionCheck` sees a build number past the `2405` gate, so `load.xml`
  *branches* past its update warning rather than being hard-blocked. Install/update/download prompts
  are inert.

## Limits

All enforced; exceeding one produces a typed `WalDiagnostic`, never a crash or a hang.

| Area | Limit |
|------|-------|
| Archive entries | 4,096 |
| Entry uncompressed size | 32 MB |
| Archive total uncompressed | 128 MB |
| Compression ratio | 200:1 |
| XML nesting depth | 256 |
| Include depth | 32 |
| Expanded XML nodes | 100,000 |
| Group inheritance depth | 64 |
| Image dimensions | 8,192 × 8,192, and 32 Mpx |
| Font point size | 512 |
| Script (`.maki`) size | 4 MB |
| MAKI table entries | 100,000 |
| Bitmap cache | 256 MB (LRU) |
| MAKI instructions per event | 5,000,000 |
| MAKI call depth | 256 |
| MAKI allocation per event | 64 MB |
| MAKI stack values | 1,000,000 |
| Active timers | 256 |
| Timer period | ≥ 8 ms, ≤ 120 Hz |
| Embedded browser VFS response | 16 MiB |
| `System.setClipboardText` text | 64 KB, truncated |

## Verification status

**Verified headlessly** (synthetic + opt-in fixtures): archive/VFS/XML contracts and every rejection
path; initialization pass order and graph snapshots; geometry/anchor rules; MAKI parse/execute and all
budget aborts; fuzzing of the archive, XML, group-expansion, MAKI-parser, and VM paths (bounded
outcome, no trap or hang); stress (timer caps, 50× rapid load/teardown, malformed images, 2,000
groupdefs); teardown completeness; live four-mode switching.

Embedded browser policy is also verified headlessly: exact scheme allowlisting, forged private-origin
rejection, VFS traversal/host-path rejection, download denial, nonpersistent WebKit storage, gated
media playback, safe search handling, and object-scoped MAKI routing. Camera and microphone requests
are denied unconditionally in the WebKit delegate and remain part of the manual security pass.

**Verified by rendering** (2026-08-15/16, `WinampModernRenderDumpTests` against user-supplied
archives, plus a manual GUI pass): Winamp Modern and cPro-Bento both render their frames and controls;
sprite crop origin, upright orientation, layer stretching, tiling, and `fitparent` are pinned per
pixel by `WinampModernRenderPixelTests`. Since Phase 11 cPro-Bento also renders its beat
visualization, spectrum and stream-info readouts, with all engine scripts completing. Since Phase 17
MMD3 draws its bitmap-font text (song title, time, KBPS, KHZ), resolves its drawer tabs and rotary
knobs to themselves under `WINAMP_MODERN_RENDER_CLICK`/`CLICKABLE`, and leaves its own animated
display unobstructed; a 2.5 s timer-driven run confirms the ticker settling on the track title and the
KBPS/KHZ fields filling from the skin's own `songinfo.maki`.

**Open crash report (2026-08-16, not reproduced).** A live cPro-Bento run aborted in `drawText` with
`-[__NSPlaceholderDictionary initWithObjects:forKeys:count:]: attempt to insert nil object` from
`NSString.size(withAttributes:)`. The text boundary is now hardened (optional-typed font, clamped
point size, PostScript-name check, optional-typed colour), but neither the dump harness nor
`WinampModernCrashRepro` — which fires every standard event at all 290 objects with a redraw after
each — triggers it, with or without the hardening reverted. **Treat the fix as plausible, not
proven**, and see `docs/winamp-modern/phase-11-handoff.md` §5 for what is still untried.

**Not verified**: casting continuity in this mode, Compact Mode, UI Size, window docking, and
pixel-exact fidelity against real Winamp. Playback and casting are `AudioEngine`-owned and
mode-independent, and are proven for the other three families, but have not been driven from a `.wal`
skin's own controls. See [manual-qa-checklist.md](../manual-qa-checklist.md).

**Known rendering gaps**: the lower third of Winamp Modern's main window (`player.main` and
`player.normal.drawer` both resolve to y≈17 and overlap, leaving the config/EQ drawer area blank), and
any widget whose visuals come entirely from a body-less `wasabi.*` standard-library shell — measured,
that is `wasabi.panel` and `wasabi.objectframe.group` only, and none of it on cPro-Bento or Winamp
Modern.

> **cPro-Bento's centre is no longer empty.** Phase 12 implemented the `Wasabi:Frame` splitter that
> builds the SUI body, and Phase 13 filled the surfaces inside it: the playlist pane draws the live
> queue, and the Media Library tab hosts the real browser (verified live against a Plex server).

**Window sizing** (Phase 13.0). A `.wal` window is sized by its own layout, and a frame restored from
saved state is now honoured for its *position* but clamped to that layout's `minimum_*`/`maximum_*`
with the saved top-left preserved — restoring verbatim is what brought a 500×500 cPro-Bento window
back as 376×182. Separately, an object whose parent is smaller than the object's own margins resolves
to a **negative** box; those are dropped with their subtree rather than flipped across their origin,
which is what made an undersized window scramble instead of cramp. Zero-sized objects are still
walked — skins park real content in 0×0 groups that size themselves from their children.

**A missing optional resource never fails the load** (Phase 22). Bitmaps, cursors and bitmap fonts
were already tolerated; `truetypefont` was not, and one skin naming a font it does not ship (Rika's
`SUPERGLU.ttf`) failed the **whole skin** — nothing on screen at all. Winamp falls back to a default
face, and `WasabiTextMetrics.font` already answers `nil` for a face it cannot produce, so the cost of
the miss is a substitute font. Security failures (traversal, escape, oversize, corrupt image) still
throw.

**A `<vis>` box is painted as the skin declares it** (Phase 22). Band colour resolves
`colorband1`…`colorband16` → `colorallbands` → white, the oscilloscope reads `colorosc1`…`colorosc5`,
and the object's own `alpha` applies to both. Reading only the per-band form and defaulting to white
put bright bars over the artwork of every skin that colours its analyzer in one stroke — Rika
(`colorallbands="0,0,0"` at `alpha="50"`, a shading over its display), T800, micro and Anexa.
`mode="3"` still means "the skin draws its own here" (Phase 17).

**A layout with no declared range is fixed** (Phase 21). "Undeclared" is not "unbounded": a layout
that declares none of `minimum_w`/`minimum_h`/`maximum_w`/`maximum_h` takes its own size as both
limits, and its window gets no resize affordance — Winamp gives one none either. Reading undeclared
as unbounded let a restored frame stretch the scene: T800 is a 177×400 window whose entire face is
one background layer, and it came back from another skin's saved frame several hundred pixels wide
with the head smeared across it. The rule keys on whether the skin *described* a range, so cPro-Bento
(317×168…1920×1080) and Winamp Modern 5.66 (a declared minimum, meant to widen) are untouched, while
T800, ZDL Reel-To-Reel and mmd3's shade layouts become fixed. A *script* may still resize a fixed
layout — `WasabiSceneRenderer.resize(to:)` keeps its own clamp; only `userResizeLimits`, which the
window's `contentMinSize`/`contentMaxSize` and the restore clamp read, is pinned.

**The protective minimum** (Phase 15, narrowed by B89). A skin's declared `minimum_w`/`minimum_h` is
written for Winamp, where *every* group clips its children; we clip a group only when it says
`clipchildren="1"` or declares its own box, so below a certain size a child that no longer fits can
paint over its siblings instead of being cut off. Rather than change clipping globally (which would
change what every skin draws), `WasabiSceneRenderer.layoutMinimumSize` raises the floor to the
smallest size at which nothing does that, and every window, script `resize`, and restored frame is
clamped to it.

The probe calibrates against the layout's **own default size**: at the size its author ships, the
scene is by definition correct, so overhang already present there is deliberate (a slider centres its
thumb on its track) and only failures that appear *after* shrinking count.

**Painting over something is the whole of the test, and that is narrower than it sounds.** Three
things are *not* failures, and each of them used to be:

| Not a failure | Why |
|---|---|
| A child its parent **clips** | The clip cuts it exactly where Winamp cuts it; it cannot reach a sibling however far past the box it resolves |
| An object that has **left the window** | It is behind the window's own clip and paints nothing |
| An object that has **left the scene** | `append` culls a node landing wholly outside its parent, and a node that is not drawn paints over nothing either |

Counting them made the floor **cPro's own default size** — "not resizable at all" — for a family of
skins declaring `minimum_w="317"` and shipping promo sheets of that compact player (B89). The
ClassicPro engine's `<group id="beatvis" x="200" w="300"/>` sits flush against the right edge of a
500-wide `cpro.screen`, so it overflowed the instant the canvas narrowed by a single pixel; and
below that, every rejected size was rejected by objects *disappearing*, with zero overflow, at sizes
that render correctly.

Dropping the "disappeared" kind costs the search its monotonicity, so **the search runs downwards**:
from the size the author drew, where the scene is by definition well formed, doubling the step until
a size fails and then bisecting the last interval. A search that probed the *bottom* of the range
first would accept it — a layout's declared minimum is usually degenerate in exactly the way that
stops the offending object being counted — and answered "the declared minimum is fine" for almost
every skin in the corpus. ~2·log₂(range) scene builds per axis, cached per layout; the result never
exceeds the layout's default size.

**A runtime-written floor beats the probe** (B127). The probe never tells the scripts about the
canvas it is measuring, so it sees a scene the skin would never draw; a skin that *writes*
`minimum_w`/`minimum_h` from a script has said what the probe is inferring, and the probe stands down
on that axis. Only two layouts in the installed corpus write one, and only one is changed by it —
cPro2 Dark Aluminum's player, 240x352 back down to the 240x106 its own `layout.m` computes. Full
account in [reference/loading.md](../reference/loading.md) → *The protective window minimum*.

Measured across the installed corpus (2026-08-31, 36 skins / 306 layouts): **169 layouts lowered,
none raised**, every one of them to its own declared minimum. All five cPro skins go 495×324
(das-skin-prev 483×324) → **317×174** against a declared 317×168; Big Bento Modern `main/normal`
1186×667 → its declared 814×530. The corpus render sweep is byte-identical apart from the known
`Anexa/main-shade.png` run-to-run flake — the floor is a *limit*, so nothing draws differently at
the sizes skins already open at.

**Not fuzzed**: `NSISArchive` and `LZMA1Decoder`. They are validated byte-for-byte against the real
installer (309/309 engine files match a reference oracle), but a bounded fuzz over them remains
reasonable future hardening.
