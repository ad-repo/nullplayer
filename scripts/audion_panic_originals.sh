#!/bin/bash
#
# Mirror Panic's original Audion faces and extract their resource forks.
#
#   scripts/audion_panic_originals.sh [<cache>] [--corpus <dir>]
#
# download.panic.com/audion/faces/ lists each face twice: <code>.jpg, a screenshot of the face
# in Audion, and <code>.sit.bin, the original Mac face as a StuffIt 5 archive. The archive's
# resource fork holds what the 2021 index.json conversion lost (`Txtr`: justification, style,
# fonts the converter dropped). This mirrors both into <cache> (default
# ~/Library/Caches/NullPlayer/audion-panic), extracts each archive into its own new directory
# with the forks as AppleDouble (`unar -k visible`, Homebrew), then writes <cache>/map.tsv
# through `audion_txtr.py map`. Already-fetched files are kept. Nothing in the cache is ever
# committed. Documented in skills/audion-face-guide/reference/harness.md.

set -u -o pipefail
source "$(dirname "$0")/lib/audion_corpus.sh"

readonly BASE_URL="https://download.panic.com/audion/faces"
cache="$HOME/Library/Caches/NullPlayer/audion-panic" corpus="$AUDION_CORPUS_DEFAULT"
while [ $# -gt 0 ]; do
    case "$1" in
        --corpus) corpus="${2:-}"; shift 2 ;;
        -*) echo "usage: audion_panic_originals.sh [<cache>] [--corpus <dir>]" >&2; exit 2 ;;
        *) cache="$1"; shift ;;
    esac
done
command -v unar > /dev/null || { echo "audion_panic_originals: needs unar (brew install unar)" >&2; exit 1; }
[ -d "$corpus" ] || { echo "audion_panic_originals: no corpus at $corpus" >&2; exit 1; }
mkdir -p "$cache/download" "$cache/extract"

curl -fsS "$BASE_URL/" | grep -oE 'href="/audion/faces/[^"/]+\.(jpg|sit\.bin)"' \
    | sed -E 's|^href="/audion/faces/||; s|"$||' | sort -u > "$cache/listing.txt" \
    || { echo "audion_panic_originals: could not read $BASE_URL/" >&2; exit 1; }
echo "audion_panic_originals: $(grep -c '\.jpg$' "$cache/listing.txt") JPGs, $(grep -c '\.sit\.bin$' "$cache/listing.txt") archives listed"

# curl writes to .part and renames, so an interrupted run never leaves a short file looking fetched.
( cd "$cache/download" && while IFS= read -r file; do
    [ -s "$file" ] || printf '%s\n' "$file"
done < ../listing.txt ) | tr '\n' '\0' | xargs -0 -P 8 -n 1 sh -c \
    'curl -fsS -o "$0/$2.part" "$1/$2" && mv "$0/$2.part" "$0/$2" || echo "audion_panic_originals: fetch failed: $2" >&2' \
    "$cache/download" "$BASE_URL"

failed=0
for archive in "$cache/download/"*.sit.bin; do
    dir="$cache/extract/$(basename "$archive" .sit.bin)"
    [ -d "$dir" ] && continue
    mkdir "$dir.part"
    if unar -q -k visible -o "$dir.part" "$archive" > /dev/null 2>&1; then
        mv "$dir.part" "$dir"
    else
        rm -rf "$dir.part"; failed=$((failed + 1))
        echo "audion_panic_originals: unar failed: $(basename "$archive")" >&2
    fi
done
echo "audion_panic_originals: $(ls "$cache/extract" | grep -vc '\.part$') extracted, $failed failed this run"

python3 -I "$(dirname "$0")/audion_txtr.py" map "$cache" "$corpus"
