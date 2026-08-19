# `docs/winamp-modern/` — index

**Durable rules do not live here.** How the `.wal` engine works, what it supports, how to debug it,
and what each measured skin does are all in `skills/winamp-modern-skin-guide/`, which is kept current.
The files in this directory are an **immutable historical record**: what each phase decided, changed,
and left open, written at the time.

Read a handoff to understand *why* something is the way it is, or to pick up an open thread. Do not
read one for current behaviour — where the two disagree, the skill is right.

## Following a pointer out of a handoff

Handoffs cite the skill by file **and section title** (*"the `rectrgn` bullet under Hit testing: who
owns a point"*, *"read `skins.md` for Defix"*). Those titles are all still verbatim, but the skill was
split into a router plus topic files, so they live in different files now. Two maps resolve any such
pointer in one hop, and they are kept where the reader lands:

- **Section title → reference file**: the *Section-title map* in
  [`skills/winamp-modern-skin-guide/SKILL.md`](../../skills/winamp-modern-skin-guide/SKILL.md).
- **Skin → file**: the *Where each skin's detail lives* index in
  [`skills/winamp-modern-skin-guide/skins.md`](../../skills/winamp-modern-skin-guide/skins.md).

The maps are not duplicated here — one home per fact applies to the migration map too.

## Phases

Numbering has gaps: phases 1, 9, 14–15, 18–22, 24–25 shipped without their own handoff document (their
outcome is recorded in the skill and in the git history).

| Phase | Date | What it changed | Key files |
|---|---|---|---|
| [0A](phase-0a-decision-record.md) | 2026-08-15 | The legal, provenance, and security gate that had to clear before any loader existed. Decisions locked by the product owner | `docs/legal/winamp_modern_provenance.md` |
| [0B](phase-0b-decision-record.md) | 2026-08-15 | Feasibility harness and compatibility inventory against cPro-Bento. Verdict: GO | — (throwaway harness) |
| [2](phase-2-handoff.md) | 2026-08-15 | Production archive, XML/XUI core, retained object graph | `WalArchive`, `WalXML`, `WinampModernSkinLoader`, `WinampModernSkinImporter` |
| [3](phase-3-handoff.md) | 2026-08-15 | CornerAmp_Redux vertical slice — first skin on screen | `WinampModernMainWindowController`, `WinampModernMainView` |
| [4](phase-4-handoff.md) | 2026-08-15 | Winamp Modern (stock) compatibility expansion | `WasabiSkinInitializer`, `WasabiRenderer`, `WinampModernConfiguration` |
| [5](phase-5-handoff.md) | 2026-08-15 | Playlist, EQ, library, and component hosting | `WinampModernComponents`, `WinampModernContainerTopology` |
| [6](phase-6-handoff.md) | 2026-08-15 | ClassicPro user-supplied engine import; cPro-Bento loads | `NSISArchive`, `LZMA1Decoder`, `WalDirectoryResourceProvider` |
| [7](phase-7-handoff.md) | 2026-08-15 | Compatibility hardening — fuzz, stress, limits, typed diagnostics | `WinampModernCompatibilityReport`, `WalDiagnostic`, `WinampModernPhase7Tests` |
| [8](phase-8-handoff.md) | 2026-08-15 | Documentation and release readiness; produced the subsystem guide | `MakiInterpreter`, `WalXML` |
| [10](phase-10-handoff.md) | 2026-08-16 | MMD3 fidelity — colour themes, script-built UI, UI Size | `WasabiRenderer`, `WasabiSkinInitializer`, `WinampModernScriptRuntime` |
| [11](phase-11-handoff.md) | 2026-08-16 | cPro-Bento's blocking MAKI surface (the SUI body still empty) | `WasabiSkinInitializer`, `WasabiSceneRenderer`, `WinampModernCrashRepro` |
| [12](phase-12-handoff.md) | 2026-08-16 | `Wasabi:Frame` — the SUI body builds; window sizing left open | `WasabiFrame`, `WasabiGeometry`, `WasabiTextMetrics` |
| [13](phase-13-handoff.md) | 2026-08-16 | Playlist, EQ and library become skin-owned surfaces | `WinampModernSurfaceCoordinator`, `WinampModernLibrarySurfaceView`, `WasabiPalette` |
| [16](phase-16-handoff.md) | 2026-08-16 | Surfaces NullPlayer draws itself are themed from the skin, not classic-skinned | `WinampModernSurfaceStyle`, `WasabiPalette` |
| [17](phase-17-handoff.md) | 2026-08-16 | The MMD3 defect sweep — text metrics, resource cache | `WasabiTextMetrics`, `WasabiRenderer` |
| [23](phase-23-handoff.md) | 2026-08-17 | The Love is War Miku defect sweep; first per-skin status file | `MakiBytecode`, `WasabiTextMetrics`, `WasabiSceneRenderer` |
| [26](phase-26-handoff.md) | 2026-08-18 | The Defix Hi-End 200 live-GUI sweep | `WinampModernMainWindowController`, `WinampModernComponentBridge` |
| [27](phase-27-handoff.md) | 2026-08-18 | Skin Settings sheet, `getVisBand`, `isLoading`, VU level scale | `WinampModernScriptRuntime`, `MakiBytecode`, `WasabiRenderer` |
| [28](phase-28-handoff.md) | 2026-08-19 | Layer FX, MAKI math library, unary-minus fix, targeted repaints. **Superseded by 29** | `WasabiLayerFX`, `MakiBytecode`, `WinampModernScriptRuntime` |
| [29](phase-29-handoff.md) | 2026-08-19 | Frame budget, repaint discipline, the VU scale — all confirmed live | `WasabiRenderer`, `WinampModernScriptRuntime`, `WinampModernMainView` |

## Not a phase handoff

- [state-of-the-engine.md](state-of-the-engine.md) — orientation for someone arriving cold: what was
  built, component-by-component status, **what is not verified**, and the reverse-engineering /
  provenance analysis.
- [corpus-runner-plan.md](corpus-runner-plan.md) — **a build plan for tooling that does not exist.**
  The unattended corpus-triage pipeline (S0–S4) and its build order. Corpus triage is manual today;
  the method that is runnable now is `skills/winamp-modern-skin-guide/triage-playbook.md`.
