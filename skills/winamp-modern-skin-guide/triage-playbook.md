# Winamp Modern (`.wal`) — Corpus Triage Playbook

- **Date:** 2026-08-18
- **Problem:** the long tail. Nine skins were fixed one at a time over 26 phases. There are tens of
  thousands of `.wal` skins in the wild, each one a bespoke program, and every one of them can fail
  differently. Per-skin heroics do not scale to that.
- **Companion:** [SKILL.md](SKILL.md) and [compatibility.md](compatibility.md) (how the engine works),
  [skins.md](skins.md) (per-skin status), `docs/winamp-modern/state-of-the-engine.md` (where the engine
  stands overall)

---

## 0. Why this is a different beast from classic skins

A `.wsz` is a **fixed contract**: a known set of BMPs at known coordinates. The surface is bounded, so
"support classic skins" is a finite, once-and-done job, and a broken skin is almost always a sprite
we cropped wrong.

A `.wal` is a **program**. The skin ships its own layout engine input, its own bytecode, its own
widgets, and its own idea of where the playlist lives. The supported surface is unbounded in
principle, and our coverage is demand-driven — so the question is never "is the engine done?" but
**"what does the corpus actually ask for, and what fraction of it do we answer?"**

That flips the working unit. Phases 2–26 worked **skin-first** (pick a skin, make it work). Beyond a
handful of skins the only tractable unit is **capability-first**: measure the whole corpus, rank
missing capabilities by how many skins they kill, implement the top cluster, re-measure. One fix that
unblocks 200 skins beats ten fixes that unblock one each — and you cannot see that ranking without a
corpus harness.

---

## 1. The four defect classes

Triage starts by naming the class, because each one has a different detector, a different cost, and a
different owner. Misclassification is what cost Phase 25/26 two passes ("the SUI body is empty" was
read as a missing widget; it was three routing bugs behind a surface the harness structurally cannot
draw).

| Class | What it is | Detected by | Typical cost |
|---|---|---|---|
| **A — Missing capability** | The skin declares a tag/attribute or calls a method we never implemented | Static scan (§3) + `unsupportedMethods` | Small each, high volume |
| **B — Wrong semantics** | Implemented, but behaves differently from Winamp | Nothing automatic. Pixels, the skin's own `screenshot.png`, or a user report | **The expensive class** |
| **C — Missing content/host data** | Resource unresolved, host property `nil`, surface not routed | `BITMAPS … missing=`, report `resources`, holder census | Small |
| **D — Out of scope by policy** | Sandbox or product decision (`<Browser>`, layer FX, arbitrary filesystem/network access) | Won't-do registry lookup (§5) | Zero — but must be recorded once |

> Class D is only what policy **rejects**, not what it **narrows**. ClassicPro's three filesystem-shell
> methods are *adapted under restriction* (`exploreFile`/`openFile` on existing non-URL paths, `findFiles`
> a bounded no-op) — that is an implemented capability with a tight contract, and filing it as a policy
> reject would hide a real, working surface from triage.

**Class B is why the compatibility report can be clean while the skin looks wrong.** Every corpus-scale
instrument below detects A, C and D. B is only ever caught by looking, so the corpus tooling's real job
is to *drain A/C/D automatically* so human attention is spent exclusively on B.

---

## 2. What our current instruments can and cannot see

Know the blind spots before trusting any batch output. **What each probe is and every environment
variable it takes is documented once, in
[reference/harness.md](reference/harness.md)** — this section is only about what they cannot see:

| Instrument | Sees | Blind to |
|---|---|---|
| Load-time compatibility report | Archive/resource/group/script problems at load | Anything a script only reaches on an event. A handler that dies on a missing method records **nothing** until something drives it |
| `unsupportedMethods` tally | Methods actually *called* | Methods on paths nobody drove. A method with a `signature(for:)` entry but a stubbed dispatch is **invisible** — it looks implemented |
| `RENDER_DUMP` PNGs | Initial static scene, **including** renderer-drawn embedded surfaces (the playlist and EQ are drawn by `WasabiSceneRenderer`, coloured by the skin's palette) | Everything time-driven; everything a click changes; the embedded **library**, which is a live AppKit view whose holder paints only a flat fill. And in the dump harness specifically, the playlist/EQ come out as empty panels because no `componentHost` is set — a harness artifact, not a missing feature |
| `RENDER_CLICK` | One point, its handler chain, attribute deltas | Whatever you didn't think to click |
| `RENDER_SCRIPTS` | Which handlers actually ran and how they failed | Only for events that were driven |

Two corollaries that shape the whole pipeline: **runtime demand must be provoked**, and **animation is
invisible to a single frame**. Both are addressed by §3's pipeline — which is not built (see below),
so provoke them by hand.

---

## 3. The pipeline

**Not built. Corpus triage is a manual process today.** Everything else in this playbook is runnable
by hand right now; the five-stage unattended pipeline (S0 ingest/tier, S1 load census, S2 static MAKI
demand, S3 motion + interaction sweep, S3.5 state-space enumeration, S4 aggregate and rank) is
**specified but not written**. Do not go looking for a corpus runner to invoke.

The specification, and the build order that would deliver it, are in
`docs/winamp-modern/corpus-runner-plan.md` — a project plan, kept where the phase handoffs live. As
each stage is built, its commands land in [reference/harness.md](reference/harness.md) and that part of
the plan becomes history.

---

## 4. Isolating one issue, once it is ranked

The corpus tells you *what* to fix; this is how you find *why*, and the order matters because each
probe is cheap only if the previous one has narrowed the space. Never change renderer code before
step 3 answers.

1. **[skins.md](skins.md) → `skins/<skin>.md`** — is this a known trap for this skin? Two phases have already been lost to
   re-deriving one.
2. **Report after driving** (`RENDER_CLICK`'s post-report, not the load-time one) — is it a missing
   method? If yes, it is Class A, stop, add it to the demand cluster, do **not** hand-fix it here.
3. **`RENDER_PROBE` + `RENDER_BITMAPS`** — missing art (C), bad geometry (B), or a script that never
   ran (A/B)? `missing=` separates an unresolved resource from one drawing wrongly.
4. **`RENDER_SCRIPTS`** (not `RENDER_XUI`) — did the handler *run*? Per-object binding state does not
   answer that question, and reading it as if it did cost two phases.
5. **`RENDER_CLICK` chain** — a chain that ends one hop early is a missing script-to-script route; a
   chain that completes and changes the right attributes with no pixel change is a renderer gap.
6. **`RENDER_DISASM=@<source>`** — read the skin's own bytecode. (For **ClassicPro** specifically, the
   engine ships its MAKI `.m` sources next to the bytecode, so read those instead of disassembling;
   ordinary skins ship bytecode only.) Read the script that owns the feature rather than inferring
   semantics. Three
   semantics (`getARGBValue` channel order, `getDateYear`'s epoch, the `isInvalid` probe idiom) were
   pinned this way rather than guessed.
7. **The skin's own `screenshot.png`**, when it ships one — the author's reference render is ground
   truth for Class B, and it is the only ground truth we have that isn't real Winamp.

---

## 4b. What is open right now, ranked (2026-08-20)

The live list is **`TASKS.md`** plus **`BENTO_TASKS.md`** (both tracked in git since 2026-08-23) —
together they are the **whole** backlog, and where new items go. Bento's family had grown to four sections of
`TASKS.md` and was split out on 2026-08-23; its items are numbered `BB*` so the two series never
collide. Anything that affects skins beyond Bento belongs in `TASKS.md`. There was once a tracked copy at `docs/winamp-modern/open-items.md` holding the ranked
reasoning behind B1–B23a; it was **deleted on 2026-08-23** after an audit confirmed nothing in it was
unique (B19 shipped as `ea4d9472`, B22 as `df9d1028`, and B23a moved to `TASKS.md`). Do not recreate
it. The table below is the head of that ranking, kept here as history so a reader does not have to go
looking — it is ordered by **bang for buck**, corpus impact ÷ effort:

| # | Open item | Reach |
|---|---|---|
| ~~B1~~ | ~~A missing `<include>` fails the **whole skin** instead of warning~~ — **closed in Phase 35**; the corpus is 17 skins wide | ~~2 of 17 skins do not load at all~~ (Itemskin, Overdrive_2 both render) |
| ~~B2~~ | ~~`dblclickaction=` / `rightclickaction=` read nowhere~~ — **closed in Phase 36**: decoded (including `ACTION;PARAM`), hit-tested, and `TRACKINFO`/`TRACKMENU` implemented | ~~`TRACKINFO` 6 skins, `TRACKMENU` 5~~ — the scan found **62 uses in 9 skins**, most of them the winshade switch |
| ~~B3~~ | ~~`PAN` (balance) has no case beside `SEEK`/`VOLUME`~~ — **closed in Phase 37**: the drag writes the engine's balance, the thumb is drawn from it, and a drag now moves the object's own position and dispatches `onSetPosition` | ~~6 skins~~ — the scan found **8 uses in 7 skins** |
| ~~B4~~ | ~~`valign` ignored — text is always vertically centred~~ — **closed in Phase 38**: decoded for both draw paths, and the bitmap-font path (which was pinned to the box's top edge) centres by default | ~~every skin's text~~ — the scan found **63 uses in 9 skins**, 54 of them `top` |
| ~~B5~~ | ~~`VIS_*` / `PE_*` / `VID_*` / `CB_*` host actions inert~~ — **closed in Phase 39**: the five visualization, five playlist and two video commands implemented; `VID_1X`/`2X`, `VID_TV` and `CB_*` accepted and inert with a recorded reason | ~~75 button uses~~ — the scan found **108 uses in 11 skins** |
| ~~B6~~ | ~~`default_visible="1"` not honoured on auxiliary containers~~ — **closed in Phase 40**: honoured as a *default* the user's own choice overrides, placed by `default_x`/`default_y`; the notifier remains suppressed, while browser windows now open with real WebKit content | ~~Defix's `Config`~~ — the scan found **10 containers in 8 of the 17 skins** |
| ~~B7~~ | ~~`onEqBandChanged` / `onEqPreampChanged` never dispatched~~ — **closed in Phase 41**: one funnel that dispatches only what moved, on every route including a 1 Hz poll for the ones nothing calls back on, with the skins' own EQ sliders synced first | ~~5 skins' EQ readouts~~ — all five answer under `RENDER_EQ` |
| ~~B8~~ | ~~The playlist-editor script API (`getCurrentIndex`, `getNumTracks`, `playTrack`, …)~~ — **closed in Phase 42**: the cause was the parser reading *every* `system`-flagged global as the System object, so `PlEdit.x()` arrived as a call on System; the twelve methods are keyed on `PlEdit`'s class GUID, not by name | ~~Defix's known gap~~ — and every skin that drives its own list |
| ~~B9~~ | ~~`onKeyDown` never dispatched~~ — **closed in Phase 43**: it carries Winamp's accelerator *string*, not a keycode, and the missing seam was a borderless window's `canBecomeKey` rather than first responder. `complete;` is the consumption signal; `isActive()` implemented alongside, because the corpus gates on it | ~~5 skins~~ — the measurement found **3** that bind it (Rika's and T800's are the edit control's `onKeyDown(Int)`, in a program neither skin loads) |
| ~~B10~~ | ~~No CI cover for the render sweep~~ — **closed in Phase 44**: five committed golden images over synthetic fixtures (`WinampModernGoldenImageTests`) cover group clipping, frame slicing, animated-layer framing, text placement and `alpha`, each verified to fail under a reintroduced regression. §6 still stands for the corpus half — CI now catches the *mechanism*, not a change against real artwork | all |

The pattern worth noticing across B1–B9: each is a **single attribute or policy** that nothing reads,
and each makes a *visible* control dead in several skins at once. That is what the demand index is
for — one of these outranks any amount of work on a widget only one skin declares.

## 5. Dispositions

Every triaged issue ends in exactly one of four states, recorded once:

- **Implement** — goes into a capability cluster with the skins that need it as its test set.
- **Degrade gracefully** — we cannot do the real thing, but the skin must not look broken (a missing
  optional resource warns; a `truetypefont` a skin never shipped falls back to a substitute face).
- **Accept and inert** — the call succeeds and does nothing, because the skin only needs to get past
  it (`switchSkin`, install/update prompts, `fx_*`). **Never** silently, and never with a
  `signature(for:)` entry that hides it from the demand tally.
- **Won't do** — sandbox or product policy (`<Browser>`, arbitrary filesystem, network). Gets a row in
  a **won't-do registry** with the reason, so the next person triages it in ten seconds instead of
  ten minutes.

The registry matters more than it sounds: at corpus scale the same fifty exotic features will surface
in every batch forever, and an un-recorded "no" is re-litigated every time.

---

## 6. Regression safety at corpus scale

**Half of this is now done.** Phase 44 committed golden images for the *mechanisms* the sweep protects
— group clipping, `<Wasabi:Frame>` slicing, animated-layer framing, bitmap-font text placement and
per-object `alpha` — as synthetic fixtures no third-party artwork is needed for
(`WinampModernGoldenImageTests`, goldens in `Tests/NullPlayerAppTests/Goldens/WinampModern/`,
regenerated with `WINAMP_MODERN_GOLDEN_UPDATE=1`). A whole canvas is the assertion, so a defect
anywhere in the frame fails; each golden was checked to fail under a deliberately reintroduced
regression before being trusted, which is the only thing that tells a golden apart from a
[blind instrument](reference/harness.md).

What is still manual is the other half: the evidence that a renderer change disturbs no other *real*
skin is a **17-skin before/after sweep**, and no synthetic fixture can stand in for a skin's own
artwork and scripts.

Replace that half with the corpus:

- **Render hashes** for every Gold + Silver layout, clock pinned (unpinned, animation noise makes every
  skin look changed — it did on the first manual run). A diff surfaces the exact skin/layout/frame.
- **Motion signatures** from S3's ladder, so a change that freezes an animation fails a check instead of
  waiting for a user to notice.
- **Interaction signatures** — the dead-control count per skin. A routing or hit-test change that kills
  controls in an unrelated skin shows up as a number moving.
- **Re-measure after every change, never work down a static list.** Each fix lets scripts run further
  and reach the next thing they need.

Hashes are of *our own renders of user-supplied skins*, so they stay local like the corpus — which
makes **provisioning** part of the contract, not an afterthought. A hash is comparable only between
runs with the same three things pinned: the corpus tier (by the manifest's SHA-256 list, so a machine
either has the exact Gold set or is not running that gate), the harness version, and the clock/settle
ladder. Therefore:

- CI (no corpus) runs the **synthetic** tests only, plus a check that the manifest is well-formed.
- The corpus sweep is a **documented pre-merge gate run on a provisioned machine** for any
  renderer/dispatch/routing change, and its output (the hash set) is what gets attached to the PR.
- A machine missing a manifest entry **skips loudly** and reports partial coverage; it never silently
  compares a smaller set and calls it green.

---

## Appendix A — How do we even know what functionality a skin contains?

The corpus pipeline stands or falls on this question, so it is worth being precise: **a `.wal` is
almost entirely self-describing, and nearly all of it can be read without executing a single
instruction.** There are three different sets in play, and every triage question is a difference
between two of them:

- **Declared** — what the archive says it contains (static, complete, cheap)
- **Reachable** — what actually gets exercised in a session (runtime, partial, expensive to provoke)
- **Implemented** — what our engine answers (a manifest we control)

`Declared − Implemented` is the work queue. `Reachable − Implemented` is what the user is complaining
about *today*. `Declared − Reachable` is how much of the skin we have never even tested.

### What the archive tells you, statically

**1. The expanded XML document — the UI inventory.**
After include/glob expansion and group expansion, the document is a complete list of what the skin
draws and what it wires up. Every one of these is a countable declaration:

- containers and layouts → how many windows, and their declared sizes
- every element tag (`layer`, `animatedlayer`, `button`, `togglebutton`, `slider`, `text`,
  `songticker`, `vis`, `grid`, `component`, `windowholder`, `Wasabi:Frame`, custom `xuitag`s…)
- every attribute per tag → the exact feature surface asked for (`tile`, `rectrgn`, `fitparent`,
  `ticker`, `forcefixed`, `regionmap`, `fliph`, `fx_*`…)
- `action=` values → the built-in commands wired to controls, **including every `MENU` action and its
  param** — a skin button asking the *host* for one of Winamp's own menus (`MENU presets`, the
  playlist ADD/REM/SEL/MISC menus) is inert unless we provide that menu, and the param census is the
  complete list of which ones a skin expects
- `display=` bindings → which host data the skin expects (`time`, `songname`, `songinfo`)
- `cfgattrib=` → every preference the skin exposes, with its GUID
- component GUIDs and holder types → where the playlist / EQ / library are expected to live
- `gammaset` count → how many colour themes ship
- `groupdef`/`inherit_group`/`embed_xui`/`xuitag` → the skin's own widget vocabulary

We already walk exactly this document for surface synthesis (`WasabiSurfaceInventory`), so the census
is a second visitor over a structure that is already built. The only thing that has to be **authored**
is the other side of the diff: a curated manifest of which tags and attributes we actually honour.
Without it, "unimplemented" stays folklore.

**2. The MAKI symbol tables — the behaviour inventory, without running anything.**
Every compiled `.maki` carries, in the file:

- `classes` — the class GUIDs it touches
- `methods` — every method name it can call (class + lowercased name)
- `variables` — its typed storage, including which objects it holds
- `bindings` — **(object variable, handler method, entry-point instruction)** triples
- `instructions` — the full instruction stream

Two things fall straight out of that, and both are the answer to "what does this skin *do*":

- **`methods` minus our `signature(for:)` set = a complete per-skin list of API the skin can call
  that we do not implement** — including every branch nobody ever clicked. This is the single
  highest-value measurement available, and it needs a parse, not a run.
- **`bindings` is the event map.** It says which object handles which events. Composed with the
  instruction stream — walk from a binding's entry point to the next one — you get *per handler* the
  methods it calls. That is a **static per-control requirement list**: "this button's `onLeftButtonUp`
  needs `isMouseOverRect`, `getScriptGroup`, `sendAction`", and if one of those is unimplemented, that
  control is statically predictable-dead before anyone clicks it.

Note this also cures a structural weakness of the current process: runtime demand is a **queue** (each
fix lets a script run further and reveal the next need), so discovering capability by execution
converges slowly and only along paths you happen to drive. Static extraction gives the whole set at
once.

**3. The resources — the content inventory.**
Declared `<bitmap>`/`<bitmapfont>`/`<truetypefont>`/`<cursor>`/`<color>` versus what the archive
actually contains; sprite-sheet dimensions versus declared frame counts (an `animatedlayer`'s frame
count is arithmetic on its sheet); which bitmaps opt into which `gammagroup`. This is where Class C
lives, and `RENDER_BITMAPS`' `missing=` already reports it per layout.

For a colour complaint specifically, two greps settle in seconds what running the skin cannot tell you
apart — whether an asset carries its own colour or is a template the theme paints:

```bash
unzip -p skin.wal '*.xml' | grep -o 'boost="[^"]*"' | sort | uniq -c   # which gamma model it wants
python3 -c "from PIL import Image; im=Image.open('skin/player/x.png').convert('RGBA'); \
  px=[q for q in im.getdata() if q[3]>16]; print(max(max(q[:3]) for q in px))"   # 0 = black template
```

A skin whose themed PNGs come back max-RGB **0** gets *all* of its colour from gamma offsets, and its
`<color>` resources will be `value="0,0,0"` to match. Anaheim Player 01 is the type specimen.

**4. What some skins hand you outright.**
The ClassicPro engine ships its MAKI **`.m` sources** beside the bytecode — read the script that owns
the feature rather than inferring its semantics. Many archives ship a `screenshot.png` (the author's
own reference render — the ground truth for "wrong, not missing") and a readme naming features. Free
signal; use it before reverse-engineering anything.

### What is only knowable by running

Three things resist static analysis and always will:

- **Dynamic construction.** `System.newGroup(id)` builds UI at runtime, and the id can be computed;
  `setXmlParam("image", prefix + suffix)` swaps artwork from a preference. Static census sees the call,
  not the result.
- **Whether a branch is taken.** A skin can declare a feature and gate it behind a config value or a
  `isInvalid()` probe. Static demand is an **upper bound** on what matters.
- **Timing and ordering.** Animation, tickers, and timer-gated transitions have no static signature
  beyond "a timer exists" — hence the motion ladder in S3.

Which is exactly why the pipeline pairs them: **rank on static, confirm on runtime.** The gap between
the two sets is itself a finding — a method the tables declare but the runtime never records is either
an untested path or, worse, a stub of ours that is quietly answering for it.
