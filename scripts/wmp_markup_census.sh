#!/bin/bash
#
# Static markup census for the Windows Media Player (`.wmz`) engine.
#
#   scripts/wmp_markup_census.sh <outdir> [--corpus <dir>] [tag-or-attribute ...]
#
# *How many skins would an element or attribute reach?* `wmp_skin_census.sh` answers what the
# engine did with a corpus it already parses; this answers what the corpus **asks for**, including
# the attributes the engine parses into the graph and then never implements. Those are invisible to
# every other instrument: an unimplemented attribute is not an unknown tag, not an unknown member,
# and not a diagnostic — it is markup that loads cleanly and changes nothing on screen. Ranking
# Phase 5's drawing work needed exactly this number.
#
# It reads the `.wms` files directly rather than through the engine, so it measures authored demand
# and nothing about the result. A count here says a skin asks; only a dumped PNG says it is drawn.
#
# Two traps this script exists to enforce:
#
#   * **grep goes silent on these files.** A `.wms` is usually UTF-16 and carries bytes grep calls
#     binary, and a binary file matches with `-o` prints *nothing at all* — a whole census of zeros
#     that reads as "the corpus never uses this". Every file is stripped to ASCII before it is
#     counted, and `-a` is passed anyway.
#   * **A tag is spread over many lines.** Corpus markup routinely opens `<SLIDER` and closes `>`
#     six lines later, so a per-line scan finds neither the tag's attributes nor the tag. Newlines
#     are folded to spaces before anything is counted.
#
# Reach is skins, not uses: one fix that unblocks 90 skins beats ten that unblock one. Both columns
# are printed because a high use count in few skins is a different (smaller) job.
#
# See skills/wmp-skin-guide/reference/harness.md; this script documents no probe flags.

set -u -o pipefail

outdir=${1:-}
if [ -z "$outdir" ]; then
    echo "usage: $0 <outdir> [--corpus <dir>] [tag-or-attribute ...]" >&2
    exit 2
fi
shift

corpus="$HOME/Library/Application Support/NullPlayer/WMPSkins"
names=()
while [ $# -gt 0 ]; do
    case "$1" in
        --corpus) corpus=$2; shift 2 ;;
        *) names+=("$1"); shift ;;
    esac
done

root=$(cd "$(dirname "$0")/.." && pwd)
exclusions="$root/scripts/wmp_corpus_exclusions.txt"

mkdir -p "$outdir/flat" || exit 1
rm -f "$outdir"/flat/*.txt

total=0
measured=0
unreadable=()
while IFS= read -r archive; do
    total=$((total + 1))
    base=$(basename "$archive")
    if [ -f "$exclusions" ] && grep -qxF "$base" <(grep -v '^#' "$exclusions" | grep -v '^[[:space:]]*$'); then
        echo "wmp_markup_census: excluded $base (scripts/wmp_corpus_exclusions.txt)"
        continue
    fi
    name=${base%.*}
    staging="$outdir/staging"
    rm -rf "$staging"; mkdir -p "$staging"
    # -C: match the entry name case-insensitively. A corpus `.wms` is as often `Corona.WMS`.
    unzip -o -qq -C -j "$archive" '*.wms' -d "$staging" >/dev/null 2>&1
    if [ -z "$(ls -A "$staging" 2>/dev/null)" ]; then
        unreadable+=("$base")
        continue
    fi
    for file in "$staging"/*; do
        LC_ALL=C tr -d '\000' < "$file" \
            | LC_ALL=C tr '\r\n\t' '   ' \
            | LC_ALL=C tr -c '\11\12\40-\176' '?' >> "$outdir/flat/$name.txt"
    done
    measured=$((measured + 1))
done < <(find "$corpus" -type f -name '*.[wW][mM][zZ]' | sort)
rm -rf "$outdir/staging"

echo "wmp_markup_census: $total archive(s) in $corpus"
if [ ${#unreadable[@]} -gt 0 ]; then
    echo "wmp_markup_census: ${#unreadable[@]} unreadable by unzip (repaired-header archives): ${unreadable[*]}"
fi
echo "wmp_markup_census: measuring $measured"

if [ ${#names[@]} -eq 0 ]; then
    names=(SLIDER CUSTOMSLIDER PROGRESSBAR BUTTON BUTTONGROUP BUTTONELEMENT TEXT EDITBOX LISTBOX
           POPUP VIDEO WMPVIDEO EFFECTS PLAYLIST EQUALIZERSETTINGS
           thumbImage thumbDownImage thumbHoverImage thumbDisabledImage direction borderSize
           positionImage foregroundImage useForegroundProgress alphaBlend passthrough cursor sticky
           tabstop clippingImage clippingColor fontFace fontType fontStyle fontSmoothing
           justification disabledForegroundColor)
fi

report="$outdir/markup.tsv"
printf 'name\tkind\tuses\tskins\tof\n' > "$report"
for name in "${names[@]}"; do
    tag_uses=$(grep -aoiE "<${name}[[:space:]/>]" "$outdir"/flat/*.txt 2>/dev/null | wc -l | tr -d ' ')
    if [ "$tag_uses" != "0" ]; then
        skins=$(grep -aliE "<${name}[[:space:]/>]" "$outdir"/flat/*.txt 2>/dev/null | wc -l | tr -d ' ')
        printf '%s\telement\t%s\t%s\t%s\n' "$name" "$tag_uses" "$skins" "$measured" >> "$report"
        printf '%-24s element   uses=%-6s skins=%s of %s\n' "$name" "$tag_uses" "$skins" "$measured"
        continue
    fi
    uses=$(grep -aoiE "[^a-z]${name}[[:space:]]*=" "$outdir"/flat/*.txt 2>/dev/null | wc -l | tr -d ' ')
    skins=$(grep -aliE "[^a-z]${name}[[:space:]]*=" "$outdir"/flat/*.txt 2>/dev/null | wc -l | tr -d ' ')
    printf '%s\tattribute\t%s\t%s\t%s\n' "$name" "$uses" "$skins" "$measured" >> "$report"
    printf '%-24s attribute uses=%-6s skins=%s of %s\n' "$name" "$uses" "$skins" "$measured"
done

echo "wmp_markup_census: wrote $report"
