# AIMP skins that taught the engine something

The index of AIMP skin evidence. Each row is a skin a code comment cites; the comment is where the
rule lives. A skin that produces two or more unrelated defects, or one no probe could see, gets a
dossier here in the shape `skin-subsystem-blueprint` § *What a family's documentation looks like*
asks for (what it exercises, what it found, **what was ruled out**, the coordinates that reach its
controls). None is written yet; write one the next time a row's skin is worked on.

| Skin | What it exercises | Where the rule lives |
|---|---|---|
| Sony TC-RX80 | press-and-hold timers (REW/FF seek every 100 ms); keys drawn as displays; LED ladders | `AIMPSkinRuntime.send`, `AIMPSkinScript.swift`, `AIMPSkinLayout+Controls.swift`, `AIMPSkinPainter.swift` |
| Technics SL-1200 | the size limits (539 MB body, ~135 Mpx); one animator following another; scripted tonearm | `AIMPSkinPolicy.swift`, `AIMPSkinDataflow+Controls.swift`, `AIMPSkinScript.swift` |
| Vega MP-120 | 58,580-px filmstrips; resource aliases a script repoints; tape-type keys stepping a page; a script-object tape counter | `AIMPSkinPolicy.swift`, `AIMPSkin.image`, `AIMPSkinDataflow.swift`, `AIMPSkinHostState.swift` |
| Cassette-3D | items hidden at start (`InitialVisible`); `IsActive` hover; a container minimum larger than its picture | `AIMPSkinIndex.swift`, `AIMPSkinHostState.swift`, `AIMPSkinRenderer.swift` |
| Akai CS-F33 | selectors over skin counters, lamps lit at a position, click-stepped ends; `.acs4` pre-zlib bytes | `AIMPSkinLayout+Controls.swift`, `AIMPSkinControl+Input.swift`, `AIMPSkinMainView+Mouse.swift`, `AIMPSkinArchive.swift` |
| Sony TC-MR2 | `.myimg`; scripts reading volume as 0–1; `AlignmentMargins`; a slider bound to a counter | `AIMPSkin.swift`, `AIMPSkinHostState.swift`, `AIMPSkinLayout.swift`, `AIMPSkinPainter+Controls.swift`, `AIMPSkinMainView+Mouse.swift` |
| Kenwood KX-800 | `Accessibility` disabling a key; a companion sized by its docked bars | `AIMPSkinLayout+Controls.swift`, `AIMPSkinRenderer.swift` |
| Akai GX-77 | a playlist window named `Win_1` (role from its lists, not its name) | `AIMPSkin.Companion.role` |
| Mayak-232 | balance −1…1 from two volume knobs; an event handler run from another | `AIMPSkinScript+HostBridge.swift` |
| Soot | 2,958 entries (five DPI variants of every image); script-driven modern layout | `AIMPSkinPolicy.swift`, `tasks/AIMP_TASKS.md` |

## Counter-evidence

The skins that disagree with a change that looked right, one rule each. Add a row whenever a sweep
shows one; nothing else records it.

| Skin | Rule it enforces |
|---|---|
| Vega MP-120 | `AM0006` limits a filmstrip's *frame*, never its width |
| Akai GX-77 | a window's role comes from its lists; never from its name alone |
