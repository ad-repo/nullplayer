#!/bin/bash
#
# Static feature index of the Winamp Modern (`.wal`) corpus (B168, corpus-runner-plan.md S2/§8).
# What each skin *declares* — read without running it — one row per (skin, feature):
#
#   scripts/wal_feature_index.sh <outdir> [--corpus <dir[:dir…]>] [--allow-dirty]
#
# Output: <outdir>/features.tsv — skin, sha256, kind, feature, implemented. Kinds:
#
#   maki-call   <classguid>.<method> an instruction invokes; implemented = yes/no against the
#               runtime's `signature(for:)` (WinampModernStaticDemandTests, parse-only)
#   maki-event  <classguid>.<event> a handler binds; implemented `-` (the host dispatches events)
#   xml-tag, xml-attr (`tag@attr`), xml-action, xml-display
#               every comment-stripped `.xml` in the archive, lowercased; implemented `-` until a
#               supported-surface manifest exists. It reads the archive *tree*, not the include
#               closure: an orphan file nobody includes still counts (see M30 in the archive).
#   family      one label per skin: cpro, standardframe, own-wasabi or plain
#   load        ok/failed — whether the loader took the skin; a failed one still gets its XML rows
#
# A run is a build, like wal_skin_census.sh: it refuses a dirty tree without --allow-dirty, and
# fails if any archive is missing its `load` row, so no skin is ever skipped silently.

set -u -o pipefail

source "$(dirname "$0")/lib/swiftpm.sh"
source "$(dirname "$0")/lib/wal_corpus.sh"

usage() {
    echo "usage: wal_feature_index.sh <outdir> [--corpus <dir[:dir…]>] [--allow-dirty]" >&2
    exit 2
}

out="" corpus="$WAL_CORPUS_DEFAULT" allow_dirty=0
while [ $# -gt 0 ]; do
    case "$1" in
        --allow-dirty) allow_dirty=1; shift ;;
        --corpus) corpus="${2:-}"; shift 2 ;;
        -*) echo "unknown option: $1" >&2; usage ;;
        *) [ -n "$out" ] && usage; out="$1"; shift ;;
    esac
done
[ -n "$out" ] || usage

archives=$(wal_corpus_archives "$corpus" | grep -c .) || { echo "wal_feature_index: no .wal archives in $corpus" >&2; exit 1; }

wal_require_clean_tree wal_feature_index "$allow_dirty" || exit 1

mkdir -p "$out"
out=$(cd "$out" && pwd)
echo "wal_feature_index: $archives archives in $corpus -> $out (rev $(git rev-parse --short HEAD 2>/dev/null || echo unknown))"

rm -f "$out/maki.tsv"
# Redirect, do not pipe.
WINAMP_MODERN_STATIC_DEMAND="$corpus" \
WINAMP_MODERN_STATIC_DEMAND_OUT="$out/maki.tsv" \
    swift test ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} --filter WinampModernStaticDemandTests \
    > "$out/maki.txt" 2> "$out/maki.stderr.txt"
if [ ! -s "$out/maki.tsv" ]; then
    echo "wal_feature_index: no maki.tsv — the build or the test failed; see $out/maki.txt" >&2
    tail -30 "$out/maki.stderr.txt" "$out/maki.txt" >&2
    exit 1
fi

python3 -I - "$corpus" "$out" <<'PYINDEX'
import hashlib, os, re, sys, zipfile

corpus, out = sys.argv[1:3]
paths = {name: os.path.join(root, name)
         for root in corpus.split(":") for name in os.listdir(root)
         if name.lower().endswith(".wal") and os.path.isfile(os.path.join(root, name))}

COMMENT = re.compile(r"<!--.*?-->", re.S)
TAG = re.compile(r"<([A-Za-z_][\w:.\-]*)((?:\s+[^<>]*?)?)/?>", re.S)
ATTR = re.compile(r"([A-Za-z_][\w:.\-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')")

def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()

def family(names):
    # ponytail: path heuristic, first match wins; replace with a loader-derived label if a ranking
    # ever needs Bento told apart from other standard-frame skins.
    lowered = [name.lower().replace("\\", "/") for name in names]
    if any(os.path.basename(name) == "classicpro.xml" for name in lowered):
        return "cpro"
    if any("standardframe" in name for name in lowered):
        return "standardframe"
    if any(name.startswith("wasabi/") or "/wasabi/" in name for name in lowered):
        return "own-wasabi"
    return "plain"

def read_entry(archive, info):
    """Some Windows-built archives spell an entry `xml\\player.xml` in the directory and
    `xml/player.xml` in its local header (PokemonDS, SingItKitty, Wiimote); zipfile refuses the
    mismatch, so retry with forward slashes. Only on failure: other entries carry the backslash in
    both places."""
    try:
        return archive.read(info)
    except zipfile.BadZipFile:
        info.orig_filename = info.orig_filename.replace("\\", "/")
        return archive.read(info)

def xml_features(path):
    features = set()
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        for info in archive.infolist():
            if not info.filename.lower().endswith(".xml"):
                continue
            text = COMMENT.sub("", read_entry(archive, info).decode("utf-8", errors="replace"))
            for tag, body in TAG.findall(text):
                tag = tag.lower()
                features.add(("xml-tag", tag))
                for attr, double, single in ATTR.findall(body):
                    attr, value = attr.lower(), (double or single).strip()
                    features.add(("xml-attr", f"{tag}@{attr}"))
                    if attr in ("action", "display") and value:
                        features.add((f"xml-{attr}", value.lower()))
    features.add(("family", family(names)))
    return features

rows = set()
for line in open(os.path.join(out, "maki.tsv"), errors="replace"):
    fields = line.rstrip("\n").split("\t")
    if len(fields) == 4 and fields[0] in paths:
        rows.add(tuple(fields))

loaded = {row[0] for row in rows if row[1] == "load"}
missing = sorted(set(paths) - loaded, key=str.lower)
if missing:
    sys.exit(f"wal_feature_index: {len(missing)} archives have no load row (the MAKI pass skipped them): "
             + ", ".join(missing[:10]))

for name in paths:
    try:
        rows.update((name, kind, feature, "-") for kind, feature in xml_features(paths[name]))
    except (zipfile.BadZipFile, OSError) as error:
        rows.add((name, "xml", f"unreadable: {error}".replace("\t", " "), "-"))

digests = {name: sha256(path) for name, path in paths.items()}
clean = lambda value: value.replace("\t", " ").replace("\n", " ")
with open(os.path.join(out, "features.tsv"), "w") as handle:
    handle.write("skin\tsha256\tkind\tfeature\timplemented\n")
    for name, kind, feature, implemented in sorted(rows, key=lambda row: (row[0].lower(), row[0], row[1], row[2])):
        handle.write("\t".join(clean(v) for v in (name, digests[name], kind, feature, implemented)) + "\n")

failed = sorted(name for name, kind, feature, _ in rows if kind == "load" and feature == "failed")
print(f"wal_feature_index: {len(rows)} rows over {len(paths)} archives -> {out}/features.tsv; "
      f"{len(failed)} did not load")
PYINDEX
