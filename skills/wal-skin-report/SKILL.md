---
name: wal-skin-report
description: Produce a structured compatibility report for one Winamp Modern (.wal) skin — capabilities, supported/unsupported features, per-surface implementation status, open questions, and a grade.
argument-hint: [skin file, e.g. "Defix Hi-END 200.WAL" or /abs/path/Skin.wal]
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# `.wal` Skin Report

Measure **one** skin end to end and emit the report in §4. This is the single-skin instrument; the
corpus-scale process it feeds is `skills/winamp-modern-skin-guide/triage-playbook.md`.

Read first if you have not this session — two targeted reads, not the whole guide:

- `skills/winamp-modern-skin-guide/reference/harness.md` — what every probe below is and does.
- `skills/winamp-modern-skin-guide/skins/<skin>.md`, if this skin already has one (the index is
  `skins.md` beside it). **If it does, start from it and update it at the end.**

`skills/winamp-modern-skin-guide/SKILL.md` is a router with a symptom → file table; read the one
reference file a finding points at, rather than the guide top to bottom.

## 0. Resolve the input

The argument may be a bare filename or a path. Resolve in this order, and **ask** rather than guess if
nothing matches:

```sh
[ -f "$ARG" ] || find ~/Downloads ~/Desktop ~/Library/Application\ Support/NullPlayer -iname "*${ARG}*" -maxdepth 4 2>/dev/null
```

Record `shasum -a 256` and byte size — a report is about a specific file, and skins circulate in
several revisions under one name.

**Never copy the skin into the repo.** Nothing third-party is committed (see
`docs/legal/winamp_modern_provenance.md`). The report itself is structural metadata — counts,
identifiers, `file:line` — which the Phase 0B inventory precedent established as retainable, so it may
be committed under `docs/winamp-modern/reports/`. Write it there only if the user asks; otherwise put
it in the scratchpad and hand over the path.

If the skin needs the ClassicPro engine (it references `@COLORTHEMESPATH@\..\..\Plugins\classicPro`,
or its report says the engine is missing), export `WINAMP_MODERN_ENGINE=/path/ClassicPro_*.exe` for
every command below.

## 1. Measure (in this order — each answers what the next assumes)

Every `WINAMP_MODERN_*` variable below is documented once, in
`skills/winamp-modern-skin-guide/reference/harness.md` — read it there if a step is unclear. What is
here is the **order**, which is the part that matters: each step answers what the next assumes.

Set once:

```sh
export WINAMP_MODERN_WAL="/abs/path/Skin.wal"
export OUT=/tmp/walreport && mkdir -p $OUT
```

| # | Command | Answers |
|---|---|---|
| 1 | `WINAMP_MODERN_RENDER_DUMP=$OUT/base swift test --filter WinampModernRenderDumpTests` | Loads? level + findings, containers/layouts, node counts, declared vs protective min/max, `HOLDERS` and `DIVIDERS` (both unconditional), PNG per layout. Add `WINAMP_MODERN_RENDER_MINIMUM=1` to see *which objects* set each floor |
| 2 | add `WINAMP_MODERN_RENDER_BITMAPS=1` | Resolved vs **missing** bitmaps per layout |
| 3 | add `WINAMP_MODERN_RENDER_SCRIPTS=bindings` | Per program: handlers declared, which **ran**, which failed and how |
| 4 | add `WINAMP_MODERN_RENDER_CLICKABLE=1` | Objects a script hooks the mouse on that the hit test rejects |
| 5 | `WINAMP_MODERN_RENDER_SETTLE=3 WINAMP_MODERN_RENDER_CLOCK=<t>` at t = 0, 0.25, 1, 4 into separate dirs | Motion: does anything actually move |
| 6 | `WINAMP_MODERN_RENDER_CLICK=<container>/<layout>@x,y[;x,y]` + `WINAMP_MODERN_RENDER_SETTLE=1` | Per control: hit, handler chain, attribute deltas, post-report. Right-click for menus |
| 7 | `WINAMP_MODERN_RENDER_PROBE=<container>/<layout>` | Full node list when something above is ambiguous |
| 8 | `WINAMP_MODERN_RENDER_DISASM=@<source>` | Only when semantics are in question — read the skin's own bytecode |

Then a **live pass**, because the harness cannot draw hosted AppKit content and has no component host:

```sh
./scripts/kill_build_run.sh   # then switch to this skin, or:
./.build/debug/NullPlayer -uiMode winampModern -winampModernSkinPath "$WINAMP_MODERN_WAL"
```

### Reading the instruments honestly

- A blank area in a dump is **not** a missing feature. The embedded **library** is a live AppKit view
  the harness cannot draw; the embedded **playlist/EQ** are renderer-drawn but come out empty because
  the harness sets no `componentHost`. Check `HOLDERS` before concluding anything.
- The load-time report is clean for anything only a click reaches. Use the report `RENDER_CLICK`
  prints **after** the click.
- `RENDER_XUI`'s `onscriptloaded=false` does **not** mean the script never ran — use `RENDER_SCRIPTS`.
- Pin the clock for motion, and pump (`SETTLE`) for timer-driven state. Neither alone is enough, and a
  rung that reverts to an earlier hash is timer-reverted, not static.
- Unsupported methods are a **queue, not a set** — the list grows as scripts get further.

## 2. Enumerate what the skin *contains* (not just what ran)

Static, from the archive — this is what separates a report from a screenshot:

```sh
mkdir -p $OUT/x && (cd $OUT/x && unzip -o -q "$WINAMP_MODERN_WAL")
grep -rhoE '<[a-zA-Z:.]+' $OUT/x --include=*.xml | sort | uniq -c | sort -rn      # element census
grep -rhoE '(action|display|cfgattrib|ticker|xuitag|inherit_group)="[^"]*"' $OUT/x --include=*.xml | sort | uniq -c | sort -rn
grep -rhoE 'action="MENU"[^>]*param="[^"]*"' $OUT/x --include=*.xml | sort -u    # host menus expected
ls -R $OUT/x | head -50; find $OUT/x -name '*.maki' -exec ls -l {} +             # scripts + sizes
find $OUT/x -iname 'screenshot.png' -o -iname 'readme*' -o -iname '*.txt'        # author's own reference
```

Method-level demand (every API the skin *can* call, including paths nobody drove) lives in each
`.maki`'s method table — `MakiProgram.methods`. There is no CLI for it yet; until the corpus runner in
the playbook exists, approximate it with `RENDER_DISASM` on the programs that own the broken features,
and say so in §5 rather than implying the list is complete.

Count **declared objects vs objects ever visible** — the coverage number. A skin whose default scene
draws a small fraction of what it declares has been seen, not measured, and that must show up in §4.

## 3. Classify every finding

| Class | Meaning | Disposition |
|---|---|---|
| **A** Missing capability | Tag/attribute/method we never implemented | Implement, or record in the won't-do registry |
| **B** Wrong semantics | Implemented, behaves differently from Winamp | The expensive class — needs the author's `screenshot.png` or an external reference |
| **C** Missing content/host data | Unresolved resource, `nil` host property, unrouted surface | Usually small |
| **D** Out of scope by policy | Sandbox/product decision (`<Browser>`, arbitrary filesystem/network) | Record once; **not** the same as a narrowed-but-supported capability |

## 4. The report template

Fill every section. An empty section is a finding — write "not measured" and why, never leave it blank.

```markdown
# Skin Report — <name>

- **File:** `<filename>` · <bytes> B · SHA-256 `<hash>`
- **Measured:** <date> · harness `<git rev>` · engine: <none | ClassicPro x.y>
- **Prior status:** <`skins/<skin>.md`, or "first measurement">
- **Grade: <A–F> (confidence: high | medium | low)**

## 1. Identity
Author / version / origin from the archive's own metadata; does it ship `screenshot.png` or a readme;
external reference captured (video, gallery page) — and if none, say so, because Class B is unfalsifiable without one.

## 2. Shape
Arrangement (singleWindowSUI | separate windows). Table: container · layouts · declared size · min (declared → protective) · max · node count.
Surface catalog: playlist / equalizer / library → embedded | declared | synthesized | classic fallback.

## 3. Declared capabilities
Element census (counts by tag). Notable attributes in use. `action=` values. `display=` bindings.
`cfgattrib` list (GUID + name + shipped default). `MENU` params expected from the host. Colour themes (gammaset count).
Fonts (bitmap / TrueType, shipped vs named). Frames, holders, XUI tags, custom groupdefs.
Scripts: file · size · handlers declared.

## 4. Implementation status
One row per user-visible surface or feature. Status: **Works · Partial · Dead · Not implemented · Out of scope · Not measured**.
Every row cites the probe that proved it — a status with no evidence column is an opinion.

| Feature | Status | Class | Evidence | Note |
|---|---|---|---|---|

Cover at minimum: window chrome/frames · transport · seek · volume · display/readouts · song ticker ·
visualization · playlist · equalizer · library · tabs/drawers · configurator · colour themes ·
album art · each menu · each animation · each auxiliary window · **NullPlayer-owned windows**.

That last row is required and is easy to forget, because it is not a surface the skin declares. Since
B110/B140 the windows NullPlayer owns — Cava, Flow, PeppyMeter, the spectrum analyzer, the waveform,
Audio Analysis, projectM, and the fallback equalizer — open wearing *this skin's* standard frame, so a
skin can be flawless in its own containers and still put a broken border, an unreachable title strip
or a mispositioned client area around eight of ours. It is a large visible surface and it wants one
row per window, not one row for all of them. `WINAMP_MODERN_DRAG_HOSTED` says which windows got a
skin frame and which fell back to the standalone classic window, and
`WINAMP_MODERN_DRAG_HOSTED_PNG` renders each one with its chrome composited — reach for the PNG, not
the counts: `surfaces=1` says a client area exists and is reachable and says **nothing** about where
it is drawn.

## 5. Unsupported / unimplemented
Split by class (A/B/C/D). For A, name the exact method or attribute. Note explicitly that the method
list is measured demand from the paths driven — **not** the complete static set — until the corpus
runner exists.

## 6. Motion
Per animated declaration: declared (`animatedlayer` / `autoplay` / script `Timer`) vs observed across
the ladder → Animating · Static · Timer-reverted · Not driven. Static-where-declared is a defect.

## 7. Interaction
Controls with mouse handlers: total / reachable / dead. Dead-control list with the chain's stopping
point. `CLICKABLE` misses that a user can see. Drag and knob controls: gesture used, result.

## 8. Menus
Per menu: family (script-built `PopupMenu` | host `action="MENU"`), trigger, opens?, item list,
per-item outcome (works | silent no-op | blocked on <method> | host menu not provided).

## 9. States and coverage
Layouts, `cfgattrib` value spaces, tabs/drawers — explored vs unexplored.
**Coverage: <visible>/<declared> objects ever rendered (<%>).** Name the states never entered.

## 10. Unknowns and questions
Each as: the question · why it is open · **what evidence would settle it** (a probe, a reference video,
the author's screenshot, a user answer). This section is the point of the report — do not compress it.

## 11. Follow-ups
Proposed `skins/<skin>.md` content plus its `skins.md` row. Capability requests for the demand index, each with this skin as a
test case. Anything that belongs in `TASKS.md`.
```

## 5. Grading

Grade the **user's experience of this skin**, not the engine's effort. Confidence is separate: low
coverage or an undriven configurator caps confidence, never inflates the grade.

| Grade | Bar |
|---|---|
| **A** | Loads (warnings only). Every declared surface routes and draws. Controls live, animation matches declarations, menus work. Coverage ≥ 80%. Nothing a user would report |
| **B** | Fully usable. Gaps are cosmetic or confined to one non-essential subsystem (one dead menu, one undistorted FX style) |
| **C** | Usable with visible defects — some dead controls, missing animations, or a surface on classic fallback that the skin meant to own |
| **D** | Loads, but a whole window/tab/pane is blank or unreachable, or the majority of controls are dead |
| **F** | Fails to load, renders nothing, crashes, or is so wrong it is unrecognisable against its own screenshot |

Rules: **never grade a state you did not enter** — put it in §9 and lower confidence. A skin that
looks perfect at rest and is dead under the mouse is **not** an A. If the archive ships a
`screenshot.png` and you did not compare against it, confidence is at most medium.

### A grade goes stale, and it must say so

A letter is a measurement of one skin against one engine, and the engine moves. The template's
`Measured: <date> · harness <git rev>` line already records which one — but nothing compared that rev
to HEAD, so a grade written before forty backlog items landed still read as current. Several of those
items change what a user sees on *every* skin (window frames, gamma, title rendering, window sizing),
which is exactly the kind of change that invalidates a letter without touching the skin.

So the rev is not decoration. **A grade is stale once the engine has moved underneath it:**

```sh
git log <measured-rev>..HEAD --oneline -- \
    Sources/NullPlayer/WinampModern Sources/NullPlayer/Windows/WinampModern
```

Non-empty output means stale. A stale grade is still evidence and is never silently deleted — it
publishes as **"B (as of 2026-08-31)"**, never as a current grade, and anything reading it should say
what has landed since. Re-measuring is the only thing that clears it; there is no partial refresh.

Check this before quoting an existing grade anywhere, and record the rev in
`skins/<skin>.md` beside the letter so the check is possible without opening the report.

### The provisional (headless) letter

A driven report is the only way to a real letter, and there are 75 installed skins. So every skin also
carries a **provisional** letter derived from a headless pass — load the archive, render every
container and layout it declares to an image, start its scripts, and record artwork lookups,
unimplemented-method calls and surface routing. `docs/winamp-modern/skin-compatibility.md` publishes
it, clearly marked, wherever no live letter exists. A live letter always supersedes it.

The ladder, and the *only* four signals allowed to move it:

| | Awarded when |
|---|---|
| **F** | the archive does not load, **or** the main player container's best layout paints < 5% of its canvas |
| **D** | a container the skin declares paints < 2% of its canvas, and it is not one a host fills (search results, tooltips, notifiers, about/preferences dialogs, which are legitimately empty at rest) |
| **C** | a managed surface has no window in the skin, **or** the skin calls a MAKI method we do not implement — dispatch is fail-closed, so each such call abandons its whole handler |
| **B** | none of the above |
| **A** | never. The A bar is "nothing a user would report", and only a user establishes that |

**Its measured error is about ±1 letter, in both directions.** On the six skins that had both, the
headless letter disagreed with the driven one four times: three times harsher (cPro Insomnis, Insomnis
v2, das-skin-prev, all B by hand and C headless) and **once kinder** — LOBE, headless B against a
driven C. Do not describe the method as conservative; it is not.

**Three signals were tried as discriminators and rejected on measurement.** Record them so nobody
re-adds one:

- **Unresolved artwork.** cPro Insomnis is a driven **B** with 13 unresolved ids of its own; cPro T2T
  is a driven **C** with 15. It does not separate them. Worse, much of it is not missing at all: a
  skin points an element at `none`, `null`, `image.null`, `window.background.hidden` or
  `rating.remove.invisible` *precisely so that nothing draws*, and Winamp treats an unresolved id as
  "draw nothing". Filter those, and separate hover/pressed-state art (cosmetic) from base art, before
  quoting a number — then put it in the skin's outstanding list, not in its grade.
- **`WINAMP_MODERN_RENDER_CLICKABLE` counts.** This probe lists objects the **markup hit test rejects
  but a script hooks the mouse on** — so a **zero is the good result**, and 23 corpus skins report
  zero. Reading it as "no working controls" downgrades most of the corpus on an inverted premise.
  There is no headless inventory of *working* controls; that is what a driven pass is for.
- **The compatibility level.** Diagnostics, not correctness. See the section above.

### The census rating is not a grade, and must never be printed as one

`scripts/wal_skin_census.sh` gives every installed archive a coarse **release rating** —
`fully-skinned` / `player-skinned` / `partly-skinned` / `does-not-load` — and
`docs/winamp-modern/skin-compatibility.md` publishes it
for the skins nobody has graded. It exists because there are 75 distinct skins and six letters, and a
release document has to say *something* about the other sixty-nine. It answers exactly one question:

> **Did every piece the skin declares end up somewhere, with its artwork resolved?**

- **fully-skinned** — the archive loaded, every layout the skin declares has a renderer, every
  managed surface (playlist, equalizer, library, video, visualization) is embedded or has its own
  window, and the NullPlayer-owned windows wear the skin's own frame.
- **player-skinned** — all of that, except our own windows fall back to the standalone classic window
  because the skin ships no usable standard frame.
- **partly-skinned** — a managed surface has no window in the skin at all, or a declared container has
  no selectable layout, so a standard NullPlayer window stands in for it. Mostly this is a skin that
  predates Winamp's media library, not a defect.
- **does-not-load** — the archive failed to load. No skin in the corpus is in this tier today.

The names matter. An earlier pass called these `complete` / `partial` / `needs-work`, which told a
user that Nullsoft's own Winamp3 base skin "needs work" because it declares no library window — a
surface that did not exist when it was made. Name the measurement, not a verdict.

Three things it is deliberately **not**, each of them measured rather than merely cautious:

1. **It is not the compatibility level.** `full` / `degraded` / `unsupported`
   (`WinampModernCompatibilityReport.swift`) counts *diagnostics*, not correctness — an unsupported
   MAKI call is a warning, a thrown load or any error-severity finding forces `unsupported`. Itemskin
   reads `unsupported` and draws correctly; a skin can read `full` and be visibly wrong. Publishing
   that column to users would tell them a working skin is unsupported. Keep it as an internal
   diagnostic column and nothing more.
2. **It is not built from finding or missing-bitmap counts.** Across the corpus on 2026-09-06, 57 of
   79 archives referenced at least one bitmap that did not resolve and 23 carried an error-severity
   finding. Neither tracks what a user sees: cPro Insomnis carries a hand-graded **B** with 15
   unresolved ids and Big Bento Modern is among the best-drawing skins in the corpus with 20, and
   most of the shortfall is Wasabi base ids (`wasabi.frame.basetexture`, `component.basetexture`)
   that nothing visible draws. A rating built on those columns called 58 of 79 skins broken. They
   stay in the TSV; they do not decide the rating.
3. **It is not a letter.** It says the pieces are present and placed. It says nothing about whether
   they are drawn right, whether the controls respond, whether the animations run, or whether the
   skin resembles its author's screenshot. Only a live pass says that. Wherever the rating is
   published, that sentence is published beside it.

A skin that has both a rating and a letter publishes the **letter**; the rating adds nothing once a
human has looked.

## 6. Close the loop

1. Update `skills/winamp-modern-skin-guide/skins/<skin>.md` (state, what came alive, what is knowingly
   left, and any trap it sets) — that file is the durable memory, the report is the snapshot. If the
   skin has no file yet, create it and add its row to the index and trap index in `skins.md`.
2. Anything that generalises beyond this skin belongs in the `reference/` file that owns the concept
   (probes → `reference/harness.md`, drawing → `reference/rendering.md`, …) or in `compatibility.md`,
   not in the report. `SKILL.md` gains a row only if a whole new *category* appeared.
3. Hand the user the report path and the grade line, and list the §10 questions that only they can
   answer.
