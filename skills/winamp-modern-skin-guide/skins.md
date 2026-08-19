# Per-skin status

What each measured `.wal` fixture actually does in NullPlayer today, and what is still missing **for
that skin**. The engine-wide surface is [compatibility.md](compatibility.md); this file is the
skin-by-skin view, because a `.wal` skin exercises an arbitrary slice of Wasabi and two skins can fail
in completely different ways while the compatibility report says the same thing about both.

Nothing third-party is committed — every skin here is user-supplied. See
[manual-qa-checklist.md](manual-qa-checklist.md) for how to run one.

**How a skin's file gets written.** Run `/wal-skin-report <skin.wal>` (`skills/wal-skin-report`) — it
measures the skin in a fixed order and emits the full structured report; `skins/<skin>.md` is the
durable summary distilled from it, not a second measurement. The report is a snapshot and lives
outside the repo; the trap list and the "knowingly missing" list belong in the skin's file.

**Keep this current.** When a phase closes on a skin, update its row below *and* its file: the phase
it was fixed in, what came alive, and what is knowingly left. A skin's own `screenshot.png`, when the archive ships one,
is the reference to compare against.

| Skin | Last worked | State | Biggest gap |
|---|---|---|---|
| Love is War Miku | Phase 23 | renders and drives correctly | `fliph`; oscilloscope is a mirrored spectrum |
| mmd3 | Phase 17 | text, knobs, drawers, own display all live | `wasabi.*`-backed widgets draw empty |
| cPro-Bento (+ ClassicPro engine) | Phase 24 | SUI body drawn and framed, live tabs, beat vis, playlist, embedded library, **script-built menus** | Guilist widgets |
| Winamp Modern (stock) | Phase 24 | frame, script-built body, playlist + library, **EQ drawer**, **centred title + streaks** | the 1px title overlay keeps its declared slot |
| CornerAmp Redux | Phase 13 | frame, titles, playlist + EQ | synthesized library window |
| T800 | Phase 20–22 | per-layout groups, region-clipped volume, drag | — |
| ZDL Reel-To-Reel | Phase 18 | sized from its background art | — |
| Rika | Phase 22 | loads without its missing TTF; vis colours honoured | — |
| Defix Hi-End 200 | Phase 26–29 (**confirmed live** 2026-08-19) | wood panel + framed windows, cassette display, **live SUI tabs + embedded library**; display styles and songticker modes selectable through **Skin Settings**; **all eight display styles animate smoothly** — needles and cassette reels through Layer FX, level strips through frame strips; frame cost 18.3 → 3.5 ms at Retina scale; VU fed block-played peak amplitude that falls to rest on silence | speaker-cone animation unverified live; `fx_setBgFx(1)` / `fx_onGetPixelA` accepted and inert — `phase-29-handoff.md` |

---

## Where each skin's detail lives

One file per measured skin. A pointer that says "read `skins.md` for skin X" resolves here in one hop.

| Skin | File |
|---|---|
| cPro-Bento (+ ClassicPro engine) | [skins/cpro-bento.md](skins/cpro-bento.md) |
| Winamp Modern (stock 5.x) | [skins/winamp-modern-stock.md](skins/winamp-modern-stock.md) |
| Love is War Miku | [skins/love-is-war-miku.md](skins/love-is-war-miku.md) |
| Defix Hi-End 200 | [skins/defix-hi-end-200.md](skins/defix-hi-end-200.md) |

The other five skins in the table above are rows only, and stay rows until one is measured with
`/wal-skin-report`. When that happens, add `skins/<skin>.md` and a row here.

### Trap index

Every measured skin sets traps that have already cost phases. Each file's **Traps this skin sets**
section is the list; read it *before* changing engine code on that skin's behalf.

- [cPro-Bento](skins/cpro-bento.md#traps-this-skin-sets) — relative geometry, `newGroup`/`init`
  two-step, `RENDER_XUI` misreading, frame-pane clipping
- [Love is War Miku](skins/love-is-war-miku.md#traps-this-skin-sets)
- [Defix Hi-End 200](skins/defix-hi-end-200.md#traps-this-skin-sets) — unseeded background preference,
  alpha-multiplexed readouts, `rectrgn` hit testing, `findObject`'s wide lookup, timer-gated tabs

## Reference targets

Three skins drove the implementation, in increasing order of demand:

| Target | Role | Detail |
|--------|------|--------|
| **CornerAmp_Redux** | first vertical slice | loads, scripts, renders its 246×228 alpha-shaped layout, button input routed |
| **Winamp Modern** | compatibility expansion | [skins/winamp-modern-stock.md](skins/winamp-modern-stock.md) |
| **cPro-Bento** + ClassicPro engine | north-star | [skins/cpro-bento.md](skins/cpro-bento.md) |

None of these ship with NullPlayer. All fixture-based tests are opt-in behind `WINAMP_MODERN_WAL` /
`WINAMP_MODERN_ENGINE`; everything committed is synthetic and self-authored.
