# Loading Audion faces

**Stub (Phase 0).** Read `../SKILL.md` first; its isolation rule binds every section here.

This file will own the loader, zip import, policy, diagnostics and, from Phase 3, the importer: what
is tolerated, what stays fatal, and the order checks run in.

The limits, their `AUD####` codes, what each one covers, and the threat model are locked in
`docs/audion-face/phase-0-decision-record.md` § *Threat model* and § *Loading limits*. **A limit is
never relaxed to make one face load**; an amendment goes in the decision record, argued about the
threat.

## Sections to come

- *Check order*
- *Tolerance* — what is dropped with a finding while the face still loads
- *Zip import*
- *Install, select, remove*
- *Codes* — one row per `AUD####` with the test that proves it
