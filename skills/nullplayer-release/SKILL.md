---
name: nullplayer-release
description: Ship a NullPlayer release — cut a GitHub release from a built DMG and update the Homebrew tap so `brew upgrade` picks it up.
argument-hint: [version, e.g. 0.26.1]
disable-model-invocation: true
allowed-tools: Bash, Read, Edit
---

# Release Process

`./scripts/create_release.sh` is the entry point. It builds the DMG (unless `--skip-build`), extracts the release notes from `CHANGELOG.md`, creates/updates the GitHub release with both the versioned and stable DMGs, **and** updates the Homebrew cask so `brew upgrade` picks up the new version. Prefer it over running the `gh` steps by hand — the manual flow below is only a fallback for when the script fails.

Two repos are involved:

- **App repo** — `ad-repo/nullplayer` (this working copy). Holds `CHANGELOG.md`, `Info.plist`, and is where the GitHub release + DMG assets live.
- **Homebrew tap** — `ad-repo/homebrew-nullplayer` (not cloned locally; the script edits it via the GitHub API with `gh`). Holds `Casks/nullplayer.rb`.

Tags and releases are **bare** (`0.26.1`, no `v` prefix). The script tags with `CFBundleShortVersionString` verbatim.

Invoke with `/nullplayer-release <version>` (e.g. `/nullplayer-release 0.26.1`). If no version argument is given, ask the user for it — don't guess.

## Steps

### 1. Stamp the version and the changelog

The version argument is the explicit instruction to bump (it overrides [[no-version-bumps]] for this run). Set it as the marketing version and turn the `## Unreleased` changelog section into the release section:

```bash
V=0.26.1   # the version being released
git switch main && git pull --ff-only origin main
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $V" Sources/NullPlayer/Resources/Info.plist
sed -i '' "s/^## Unreleased\$/## $V/" CHANGELOG.md
grep -n "^## $V\$" CHANGELOG.md   # exactly one hit; if none, there was no Unreleased section — stop and ask
git diff --stat                    # only Info.plist and CHANGELOG.md
git commit -am "Release $V" && git push origin main
```

If `## $V` already exists (a re-run), skip the `sed` — don't create a duplicate heading. Leave `CFBundleVersion` alone. Pushing to `main` is outward-facing: confirm with the user before the push.

### 2. Verify preconditions

The script derives the version from `CFBundleShortVersionString` in `Sources/NullPlayer/Resources/Info.plist` — confirm it matches the version being released.

**The helper only runs from a clean, up-to-date `main`.** Before doing anything else, `require_release_source()` hard-fails unless the checkout is on the `main` branch, has no uncommitted changes, and has `HEAD == origin/main` (it fetches `origin main` to compare); if a remote tag for the version already exists, it must already point at that same `HEAD`. The release always targets `main@HEAD` — you cannot point it at an arbitrary commit, so land the changelog/version commit on `main` and pull first.

```bash
V=0.26.1   # the version being released
git switch main && git pull --ff-only origin main  # the script requires this exact state
git status --porcelain                              # must be empty (clean tree)
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Sources/NullPlayer/Resources/Info.plist  # must equal $V
grep -n "^## $V\$" CHANGELOG.md                    # the changelog section the notes come from must exist
gh release list -R ad-repo/nullplayer --limit 3    # confirm tag scheme + that $V isn't already released
git log --oneline -1                                # HEAD (== origin/main) is what the release tags
```

The release is cut from `main@HEAD`, which must be the commit that contains the changelog entry. If HEAD isn't that commit, get it onto `main` and pull — the script won't let you target anything else.

### 3. Run the release helper

```bash
./scripts/create_release.sh              # build DMG, publish release, update the Homebrew cask
./scripts/create_release.sh --skip-build # reuse an existing dist/NullPlayer-$V.dmg instead of rebuilding
```

The helper prints the versioned/stable asset paths, the SHA256, and — after publishing — the Homebrew cask commit URL. It:

- extracts the `## $V` section from `CHANGELOG.md` (falling back to a placeholder with a warning if missing) and merges it into `.github/release_template.md`,
- uploads `NullPlayer-$V.dmg` (versioned, what Homebrew pins to) and `NullPlayer.dmg` (stable, `releases/latest/download`),
- hashes the versioned DMG and rewrites `version` + `sha256` in `Casks/nullplayer.rb` via the GitHub API.

Useful flags: `--dry-run` (build notes/assets, don't call GitHub), `--draft` / `--prerelease` (the cask is left alone for these), `--replace-versioned` (re-upload the versioned DMG on an existing release, refreshing the cask sha), `--skip-tap` (publish without touching the cask).

The cask update runs automatically only when the versioned asset actually changed (a fresh release, a first upload, or `--replace-versioned`) and never for drafts/prereleases whose download URL isn't live yet.

### 4. Verify the release is live and downloadable (deterministic)

Run this **after** the helper reports success. It is deterministic: every check is an exact assertion (published state, asset names, HTTP 200, byte-for-byte sha256, cask contents, `brew fetch` checksum), it prints `PASS`/`FAIL` per line, and it exits non-zero if anything fails — so it is safe to gate a release on. The canonical checksum is the local DMG that was uploaded; everything downloadable must match it.

```bash
V=0.26.1                       # the released version
REPO=ad-repo/nullplayer        # app repo AND the cask tap shorthand
TAP=ad-repo/homebrew-nullplayer
LOCAL_DMG="dist/NullPlayer-$V.dmg"

fail=0
note() { [[ $1 == 0 ]] && printf 'PASS %s\n' "$2" || { printf 'FAIL %s\n' "$2"; fail=1; }; }

[[ -f "$LOCAL_DMG" ]] || { echo "FAIL missing $LOCAL_DMG (build or --skip-build first)"; exit 1; }
EXPECTED=$(shasum -a 256 "$LOCAL_DMG" | awk '{print $1}')

# --- GitHub release ---
[[ "$(gh release view "$V" -R "$REPO" --json isDraft -q .isDraft)" == false ]]
note $? "release $V is published (not a draft)"

assets=$(gh release view "$V" -R "$REPO" --json assets -q '.assets[].name')
grep -qx "NullPlayer-$V.dmg" <<<"$assets"; note $? "versioned asset NullPlayer-$V.dmg attached"
grep -qx "NullPlayer.dmg"    <<<"$assets"; note $? "stable asset NullPlayer.dmg attached"

for url in \
  "https://github.com/$REPO/releases/download/$V/NullPlayer-$V.dmg" \
  "https://github.com/$REPO/releases/latest/download/NullPlayer.dmg"; do
    tmp=$(mktemp)
    code=$(curl -sL -w '%{http_code}' -o "$tmp" "$url")
    got=$(shasum -a 256 "$tmp" | awk '{print $1}')
    rm -f "$tmp"
    [[ "$code" == 200 && "$got" == "$EXPECTED" ]]
    note $? "HTTP 200 + sha256 matches: $url"
done

# --- Homebrew cask ---
gh api "repos/$TAP/contents/Casks/nullplayer.rb" -q .content | base64 -d > /tmp/cask-verify.rb
grep -q "version \"$V\""       /tmp/cask-verify.rb; note $? "cask pins version $V"
grep -q "sha256 \"$EXPECTED\"" /tmp/cask-verify.rb; note $? "cask pins the matching sha256"
rm -f /tmp/cask-verify.rb

brew tap "$REPO" >/dev/null 2>&1
brew update >/dev/null 2>&1
brew fetch --cask "$REPO/nullplayer" --force >/dev/null 2>&1
note $? "brew fetch downloads and checksum-verifies the cask artifact"

if [[ $fail == 0 ]]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; exit 1; fi
```

`brew fetch` (rather than `brew install`) verifies the cask URL is live and its `sha256` matches the actual download **without** mutating the machine's installed apps — a non-zero exit means either the URL is wrong or the checksum drifted. If any line reports `FAIL`, do not announce the release; fix the failing asset/cask first (usually a stale `--replace-versioned` sha or a draft that was never published).

### 5. Report

Give the user the release URL (`gh release view "$V" -R ad-repo/nullplayer --json url -q .url`) and the cask commit URL the script printed, confirm the verification block above printed `ALL CHECKS PASSED`, and note that `brew upgrade --cask ad-repo/nullplayer/nullplayer` now pulls the new version.

## Fallback: update the Homebrew cask by hand

Only if `create_release.sh` published the release but the cask step failed (or you ran `--skip-tap`). The cask pins both `version` and the DMG's `sha256`. Hash the **exact DMG that was uploaded**, then edit `Casks/nullplayer.rb` via the API — the tap isn't cloned locally:

```bash
shasum -a 256 dist/NullPlayer-$V.dmg            # the new sha256

# Fetch the cask + its blob sha (needed to commit an update)
gh api repos/ad-repo/homebrew-nullplayer/contents/Casks/nullplayer.rb -q .content | base64 -d > /tmp/cask.rb
BLOBSHA=$(gh api repos/ad-repo/homebrew-nullplayer/contents/Casks/nullplayer.rb -q .sha)

# Replace the OLD version and OLD sha256 (read them out of /tmp/cask.rb first; sed needs exact old strings)
sed -i '' 's/version "0.26.0"/version "0.26.1"/' /tmp/cask.rb
sed -i '' 's/sha256 "<OLD_SHA>"/sha256 "<NEW_SHA>"/' /tmp/cask.rb
grep -E 'version |sha256 ' /tmp/cask.rb          # sanity check both changed

# Commit the update
gh api -X PUT repos/ad-repo/homebrew-nullplayer/contents/Casks/nullplayer.rb \
  -f message="Update NullPlayer to $V" \
  -f content="$(base64 -i /tmp/cask.rb)" \
  -f sha="$BLOBSHA" -q '.commit.html_url'
```

Only `version` and `sha256` change. The `url` line is templated on `#{version}` and needs no edit. Leave the `postflight` xattr block, `zap`, and keychain note alone.

## Gotchas

- **sha256 must match the uploaded DMG byte-for-byte.** The script hashes the same file it uploads; if you update the cask by hand, hash the same file too — a stale or rebuilt DMG produces a different hash and `brew install` fails with a checksum mismatch.
- **Tag scheme is bare** (no `v`). The script tags with `CFBundleShortVersionString`; `gh release list` is the source of truth. Older tags used `v` prefixes, don't copy those.
- **The tap is a separate repo** with its own commit history — the cask change does NOT go in the app repo, and the script edits it via `gh api`, not by committing to this working copy.
- **GitHub blob `sha`** in the PUT call is the existing file's blob sha (from the GET), not the DMG hash — they're unrelated. Omitting it on an update fails.
