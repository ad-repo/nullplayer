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
album art · each menu · each animation · each auxiliary window.

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

## 6. Close the loop

1. Update `skills/winamp-modern-skin-guide/skins/<skin>.md` (state, what came alive, what is knowingly
   left, and any trap it sets) — that file is the durable memory, the report is the snapshot. If the
   skin has no file yet, create it and add its row to the index and trap index in `skins.md`.
2. Anything that generalises beyond this skin belongs in the `reference/` file that owns the concept
   (probes → `reference/harness.md`, drawing → `reference/rendering.md`, …) or in `compatibility.md`,
   not in the report. `SKILL.md` gains a row only if a whole new *category* appeared.
3. Hand the user the report path and the grade line, and list the §10 questions that only they can
   answer.
