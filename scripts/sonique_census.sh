#!/bin/bash
#
# Structural census of the Sonique skin corpus, through the app's own loader.
#
#   scripts/sonique_census.sh <outdir> [--corpus <dir>]
#
# Runs SoniqueSkinCensusTests over the corpus (raw.txt), then prints one summary: load counts,
# spec versions, ini sections, how many skins carry each entry, findings by code, modes on the
# default skin, and every fatal. It never asserts a fixed count, because the corpus moves.
# The numbers and what they settled are in skills/sonique-skin-guide/reference/harness.md.

set -u -o pipefail
source "$(dirname "$0")/lib/swiftpm.sh"

out="" corpus="$HOME/Library/Application Support/NullPlayer/SoniqueSkins"
while [ $# -gt 0 ]; do
    case "$1" in
        --corpus) corpus="${2:-}"; shift 2 ;;
        -*) echo "usage: sonique_census.sh <outdir> [--corpus <dir>]" >&2; exit 2 ;;
        *) out="$1"; shift ;;
    esac
done
[ -n "$out" ] || { echo "usage: sonique_census.sh <outdir> [--corpus <dir>]" >&2; exit 2; }
[ -e "$corpus" ] || { echo "sonique_census: no corpus at $corpus" >&2; exit 1; }

mkdir -p "$out"
SONIQUE_SKIN="$corpus" swift test ${SWIFTPM_ARGS[@]+"${SWIFTPM_ARGS[@]}"} \
    --filter SoniqueSkinCensusTests/testCensusSkinOrCorpus > "$out/raw.txt" 2> "$out/stderr.txt"

python3 -I - "$out/raw.txt" <<'PY'
import collections, re, sys

skins, skin = {}, None
expected = 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.rstrip("\n")
    if line.startswith("HARNESS "):
        expected = int(line.split()[1])
    elif line.startswith("SKIN "):
        failed = re.match(r"SKIN (.*) FAILED (.*)", line)
        skin = None if failed else line[5:]
        if failed:
            skins[failed.group(1)] = {"fatal": failed.group(2)}
        else:
            skins[skin] = {"fatal": None, "entries": [], "sections": [], "findings": [], "digest": "-"}
    elif skin and line.startswith("SIZE "):
        skins[skin]["size"] = {k: int(v) for k, v in (kv.split("=") for kv in line[5:].split())}
    elif skin and line.startswith("DIGEST "):
        skins[skin]["digest"] = line[7:]
    elif skin and line.startswith("ENTRY "):
        skins[skin]["entries"].append(line[6:])
    elif skin and line.startswith("SECTION "):
        skins[skin]["sections"].append(line[8:])
    elif skin and line.startswith("VERSION "):
        skins[skin]["version"] = line[8:]
    elif skin and line.startswith("MODES default="):
        skins[skin]["defaults"] = [m for m in line[14:].split(",") if m]
    elif skin and line.startswith("FINDING "):
        skins[skin]["findings"].append(line[8:])

loaded = [s for s in skins.values() if not s["fatal"]]
failed = [(name, s["fatal"]) for name, s in skins.items() if s["fatal"]]
unique = len({s["digest"] for s in loaded}) + len(failed)
code = lambda finding: finding[1:7]
regions = sum(1 for s in loaded for f in s["findings"] if code(f) == "SQ0008" and "region" in f)
print(f"files={len(skins)} unique={unique} parsed={len(loaded)} failed={len(failed)} malformed_regions={regions}")
print("version", dict(collections.Counter(s["version"] for s in loaded).most_common()))
print("sections", dict(collections.Counter(x for s in loaded for x in s["sections"]).most_common()))
for name, n in collections.Counter(x for s in loaded for x in s["entries"]).most_common():
    print(f"entry {n:4} {name}")
print("findings", dict(sorted(collections.Counter(code(f) for s in loaded for f in s["findings"]).items())))
print("default_modes", dict(collections.Counter(m for s in loaded for m in s["defaults"]).most_common()))
named = {id(s): name for name, s in skins.items()}
for key, limit in (("bytes", "SQ0002 16 MiB"), ("entries", "SQ0003 256"), ("side", "SQ0005 16,384 px"),
                   ("pixels", "SQ0006 64 Mpx"), ("ini", "SQ0007 256 KiB")):
    top = max(loaded, key=lambda s: s["size"][key])
    print(f"headroom {key} max {top['size'][key]} ({named[id(top)]}) against {limit}")
for name, why in failed:
    print("FAIL", name, why)
if len(skins) < expected:
    print(f"sonique_census: {expected - len(skins)} skin(s) have no block; the run died, see stderr.txt")
    sys.exit(1)
PY
