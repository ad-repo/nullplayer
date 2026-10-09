# Loading Audion faces

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

This file will own `AudionFaceLoader`, `AudionFaceZipImport`, `AudionFacePolicy`,
`AudionFaceDiagnostics` and, from Phase 3, `AudionFaceImporter`: what is tolerated, what stays
fatal, and the order checks run in.

The limits and their `AUD####` codes are locked in `docs/audion-face/phase-0-decision-record.md`
§ *Loading limits*, with the corpus headroom measured against each. **A limit is never relaxed to
make one face load**; an amendment goes in the decision record, argued about the threat.

## Sections to come

- *Check order* — symlinks and file count before any open; `index.json` size before parse; PNG
  header dimensions and the `AUD0011` pixel budget before any decode.
- *Tolerance* — an element with a malformed or missing key is dropped with a finding; the face loads.
- *Zip import* — central-directory checks, temporary folder, the same loader. No code shared with
  `WMPArchive`.
- *Install, select, remove* — `.incoming-<UUID>` then an atomic move; the `audionFaceName` key.
- *Codes* — one row per `AUD####` with the test that proves it.
