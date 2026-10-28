#!/bin/bash
# A `.wal` skin's own source, unpacked once and searched: find the archive by name, extract it into a
# directory keyed by its sha256 (reused on every later call), list its reference images, and grep its
# XML, MAKI source and text files with Windows line endings stripped.
#
#   scripts/wal_skin_src.sh <skin|path>              # the directory and the reference images
#   scripts/wal_skin_src.sh <skin|path> <ERE>        # plus at most 60 matching lines, file:line: text
#
# Why: intake #3 found, unzipped and grepped a skin about 140 times by hand, often unzipping the same
# archive again into a new scratch folder, and `grep` on CRLF XML misses patterns anchored at `$`.
set -uo pipefail
cd "$(dirname "$0")/.."
TMP="${TMPDIR:-/tmp}"; TMP="${TMP%/}"
source scripts/lib/wal_corpus.sh

[ $# -ge 1 ] || { echo "usage: wal_skin_src.sh <skin|path> [<ERE>]" >&2; exit 2; }
WAL=$(wal_resolve_skin "$1") || exit 2
SHA=$(shasum -a 256 "$WAL" | cut -c1-12)
DIR="$TMP/wal-src/$SHA"
# The marker alone is not trusted: macOS purges old files under $TMPDIR and leaves the newer marker.
if [ ! -f "$DIR/.complete" ] \
    || [ "$(find "$DIR" -type f ! -name .complete | wc -l)" -lt "$(unzip -Z1 "$WAL" | grep -vc '/$')" ]; then
    rm -rf "$DIR" && mkdir -p "$DIR" && unzip -o -q "$WAL" -d "$DIR" && touch "$DIR/.complete" \
        || { echo "wal_skin_src: could not unpack $WAL" >&2; exit 1; }
fi
echo "$WAL -> $DIR"
REFS=$(cd "$DIR" && find . -maxdepth 3 -type f \( -iname '*screenshot*' -o -iname '*skinshot*' -o -iname '*preview*' -o -iname '*readme*' \) | sed 's#^\./##')
echo "references: ${REFS:-none}" | paste -sd' ' -

[ $# -ge 2 ] || exit 0
# CR stripped before grep, so a pattern anchored at `$` matches a CRLF line.
MATCHES=$(cd "$DIR" && find . -type f \( -iname '*.xml' -o -iname '*.m' -o -iname '*.txt' -o -iname '*.ini' \) \
    | while IFS= read -r f; do LC_ALL=C tr -d '\r' <"$f" | grep -a -n -i -E "$2" 2>/dev/null | f="${f#./}" awk '{ print ENVIRON["f"] ":" $0 }'; done | cut -c1-240)
N=$(grep -c . <<<"$MATCHES")
[ "$N" -gt 0 ] || { echo "no match for $2"; exit 0; }
head -60 <<<"$MATCHES"
[ "$N" -le 60 ] || echo "… $((N - 60)) more; narrow the pattern"
