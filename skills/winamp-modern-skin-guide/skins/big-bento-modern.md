# Big Bento Modern (all four variants)

**Archives:** `Big Bento Modern.wal`, `Big Bento Modern Light.wal`,
`Big Bento Modern Windows 10 edition.wal`, `Big Bento Modern Windows 10 edition Light.wal`
**Author:** Victhor, over Taber Buhl's work and the original Wasabi development
**Arrangement:** `singleWindowSUI` — playlist, library and video are all embedded tabs
**Layouts:** `main/normal` 814×530 declared, 1186×597 minimum, capped at the 1920×1080 screen box;
`main/shade` 565×42. Plus `searchresults`, `Hsearchresults`, `browserpro`, `main.aerosnap`,
`query.pathurl`, `welcomessage` and `notifier` containers.

## Status

| Feature | Status | Notes |
|---------|--------|-------|
| Loading | **Fixed (B35)** | All four failed outright before B35 — see the three root causes below |
| Rendering | **Works** | 80–82 bitmaps resolve in `main/normal`, 19–20 in `main/shade`; 38 scenes across the four |
| Overlay (`Light`) palette | **Works** | The Light editions render in their own light palette against the base skin's artwork |
| Album-art panel (W10 edition) | **Degrades** | Its `window/no_alb_art_shade.png` is zero bytes; that one placeholder draws nothing |
| Scripts | **Partial** | `getsettingspath` and `scrolltopercent` are unimplemented, which is why all four still report `unsupported` although they draw |

## The family is two skins and two overlays

`Big Bento Modern` and `Big Bento Modern Windows 10 edition` are complete skins (273 files each).
The two `Light` editions are **overlays**: 138 files, and 6 of the 8 includes in their `skin.xml`
come out of the base archive by name —

```xml
<script  file="@SKINSPATH@\Big Bento Modern\scripts\loadattribs.maki" param="bbmlight"/>
<include file="@SKINSPATH@\Big Bento Modern Light\xml\color-presets.xml"/>   <!-- its own -->
<include file="@SKINSPATH@\Big Bento Modern Light\xml\system-colors.xml"/>   <!-- its own -->
<include file="@SKINSPATH@\Big Bento Modern\xml\system-elements.xml"/>       <!-- the base's -->
… standardframe.xml, window-overrides.xml, player.xml, notifier.xml, about.xml
```

so **the base must be installed, under its own name**, or the Light edition cannot load. That is
what `missingRequiredMount` says, by name. `@SKINSPATH@` usage: base 159, W10 165, each Light 48.

## Why all four failed before B35

1. **`@SKINSPATH@` was undefined** — a hard `unresolvedPathVariable` on the first include
   (`xml/player-normal.xml` / `xml/player.xml`, or `skin.xml:32-33` for the overlays). It is the
   skins *collection* root; every loaded skin is mounted at `/Skins/<name>`, so it is `/Skins`.
2. **The overlays reach into a sibling archive**, which the VFS had no way to mount. It now does,
   lazily and bounded — `reference/loading.md` → *Sibling skin mounts*.
3. **The Windows 10 edition ships a zero-byte `window/no_alb_art_shade.png`**, and one undecodable
   PNG failed the whole skin. An undecodable image now degrades to a warning.

Three independent causes with one symptom: *this skin does not load at all*. Fixing any one of them
alone would have left two of the four still dead.

## Traps

- **`@SKINPATH@` and `@SKINSPATH@` mean different things here, and the skin uses both on purpose.**
  Base XML that an overlay is meant to *override* is pulled with `@SKINPATH@` — the **loaded** skin's
  mount — so `player-normal-sui.xml`'s `<include file="@SKINPATH@\xml\config.xml">` picks up the
  Light edition's `config.xml`, not the base's. Shared XML is pulled with
  `@SKINSPATH@\Big Bento Modern\…`, an absolute name. Reading either as the other inverts which
  edition's markup wins.
- **The base's 159 `@SKINSPATH@\Big Bento Modern\…` references are *self*-references.** They resolve
  through the mount the skin already has and must never reach the sibling resolver.
- **Bitmap overrides do not currently win** (measured 2026-08-23, follow-up filed). The Light
  editions ship light versions of the *same* `window/*.png` the base declares (`frames.png`,
  `equalizer.png`, `no_alb_art_*.png`, 30-odd files), but a `<bitmap file="window/frames.png">`
  declared in base XML resolves relative to that XML first, so it loads the **base's** artwork; only
  the `@SKINPATH@` fallback would reach the overlay's copy. The Light editions still read as light
  because their palette comes from `color-presets.xml` / `system-colors.xml` and the gamma model.
  Do not "fix" this by flipping `resolveSkinResource`'s order without a full corpus sweep — the
  relative-first order exists for authored subfolders.
- **The `unsupported` compatibility level is about MAKI, not loading.** `getsettingspath` and
  `scrolltopercent` are recorded as errors; the skin loads and draws regardless.
- `main/normal`'s missing-bitmap list is mostly deliberate placeholder ids (`none`, `null`,
  `player.button.pause.normal.null`, `window.background.hidden`, `show.sui.tabs.invisible`) — the
  skin's own way of drawing nothing. They are not a defect.
