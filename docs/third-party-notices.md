# Third-Party License Notices

NullPlayer ships notices for every third-party component bundled into the app:
Swift packages compiled into the binary, bundled frameworks/dylibs, native
source ports, fonts, and bundled assets. This doc explains how the system works
and how to keep it correct when dependencies change.

## Pieces

| File | Role |
|------|------|
| `scripts/third_party_components.tsv` | **Source of truth.** One tab-separated row per component: `key`, `name`, `spdx`, `copyright`, `source_url`, `version`, `license_text`, `bundle_glob`. |
| `Sources/NullPlayer/Resources/ThirdPartyLicenses/` | The shipped license texts. Shared bodies (GPL-3.0, LGPL-2.1, Apache-2.0) live in `licenses/`; per-component permissive texts sit at the top level. |
| `Sources/NullPlayer/Resources/ThirdPartyLicenses/ThirdPartyNotices.txt` | **Generated** aggregate of every notice (attribution header + full license text). Committed to the repo and bundled into the app. |
| `scripts/generate_third_party_notices.sh` | Regenerates `ThirdPartyNotices.txt` from the manifest. |
| `scripts/validate_notices.sh` | Fails if any manifest notice is missing from the app bundle, or any bundled framework/dylib has no manifest entry. |

The whole `Resources/` tree is copied into the app bundle by SPM, so every file
under `ThirdPartyLicenses/` ends up at `Contents/Resources/ThirdPartyLicenses/`.

## Manifest field reference

- **license_text** — path to the required license text, **relative to
  `Sources/NullPlayer/Resources/`** (equivalently `Contents/Resources/` in the
  built app). Multiple components may point at the same shared file (e.g. all
  LGPL-2.1 components share `ThirdPartyLicenses/licenses/LGPL-2.1.txt`); the
  per-component attribution still comes from the manifest row.
- **bundle_glob** — basename glob matched against the real files in
  `Contents/Frameworks` (e.g. `libaubio*.dylib`, `VLCKit.framework`). Use `-`
  for components compiled into the `NullPlayer` binary with no standalone
  bundled artifact. `validate_notices.sh` requires **every** non-symlink
  framework/dylib in `Contents/Frameworks` to match at least one glob.

## Build-time enforcement

`scripts/build_dmg.sh` calls `validate_notices.sh "$RESOURCES_DIR"
"$FRAMEWORKS_DIR"` after assembling the bundle. The release build **fails** if:

- a component in the manifest is missing its `license_text` in the bundle, or
- `ThirdPartyNotices.txt` is missing/empty, or
- a bundled framework/dylib is not covered by any manifest `bundle_glob`.

The same script is what a future Mac App Store build should invoke for notice
validation.

## When dependencies change

1. **A new bundled dylib/framework appears** (e.g. `bundle_homebrew_deps` pulls
   in a new transitive library, or a new SPM binary target is added):
   - `validate_notices.sh` will fail the build with
     *"Bundled binary has NO notice in manifest"*.
   - Find the library's upstream license + copyright, add the license text under
     `Resources/ThirdPartyLicenses/` (reuse a shared body in `licenses/` for
     GPL/LGPL/Apache), and add a manifest row with a matching `bundle_glob`.

2. **A new SPM source dependency is added** (compiled into the binary):
   - Read its `LICENSE` from `.build/checkouts/<dep>/`, add the text under
     `Resources/ThirdPartyLicenses/`, and add a manifest row with `bundle_glob`
     set to `-`.

3. **A dependency version bumps:** update the `version` (and `copyright`/SPDX if
   the upstream license changed) in the manifest.

4. **Regenerate and commit:**
   ```bash
   ./scripts/generate_third_party_notices.sh
   git add scripts/third_party_components.tsv \
           Sources/NullPlayer/Resources/ThirdPartyLicenses/
   ```

5. **Verify locally** without a full DMG build:
   ```bash
   ./scripts/validate_notices.sh \
       Sources/NullPlayer/Resources \
       dist/NullPlayer.app/Contents/Frameworks
   ```
   (Point the second argument at a built `Contents/Frameworks` to exercise the
   reverse coverage check.)

## Notes

- `Frameworks/libkeyfinder/` exists in the tree but is **not** linked or
  bundled (no `CKeyFinder` target, no references in `Sources/`). If it is ever
  wired into the build, add a manifest entry for it.
- The bundled Homebrew dylib versions are whatever `scripts/build_dmg.sh` copies
  from `/opt/homebrew` on the build host; keep the manifest `version` column in
  sync with the build machine's Homebrew versions when they move.
