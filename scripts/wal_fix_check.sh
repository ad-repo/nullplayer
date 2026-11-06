#!/bin/bash
#
# The corpus sweeps one `.wal` fix pass needs, chosen from what the pass changed, each run once
# against the stored baseline:
#
#   scripts/wal_fix_check.sh <base-rev> <outdir> [--dry-run]
#
# The change is <base-rev> against the working tree, uncommitted and untracked files included.
#   render                  any change under Sources/ outside Windows/WinampModern/ (~25 s sharded)
#   + interaction, motion   only when it touches hit testing, script runtime, MAKI, the object graph, loading,
#                           click/host/EQ actions, key accelerators, or code outside the .wal engine
#                           (~17 and ~10 min over gold+silver)
#   none                    a change only in Sources/NullPlayer/Windows/WinampModern/ (the live window
#                           layer) or in docs/scripts: no headless sweep can see it. Check it live
#                           with window-census.sh --shots and wal_live_smoke.sh on the skins instead.
# The baseline is served from the run store (--rev). One never captured stops the script: capture it
# once per batch in a worktree (scripts/baseline_worktree.sh, harness.md § "The run store") and every
# later fix pass in that batch reuses it.
#
# Output: <outdir>/plan.txt, render/compare.txt, interaction/diff.txt, motion/diff.txt, and one line
# per sweep on stdout. Classify every diff (skin-triage Phase 8); the noise list is in
# skills/skin-intake/SKILL.md § "Running it".
#
# Why: intake #6's two fix passes took 61 and ~45 minutes, most of it interaction and motion sweeps
# a render-only or window-layer change could not reach, paid twice because the fixes were split into
# two passes.
set -euo pipefail
cd "$(dirname "$0")/.."

base=${1:?usage: wal_fix_check.sh <base-rev> <outdir> [--dry-run]}
out=${2:?usage: wal_fix_check.sh <base-rev> <outdir> [--dry-run]}
dry=${3:-}
git rev-parse --verify -q "$base^{commit}" >/dev/null || { echo "wal_fix_check: no commit $base" >&2; exit 2; }
mkdir -p "$out"

changed=$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u | grep '^Sources/' || true)
engine='^Sources/NullPlayer/WinampModern/'
window='^Sources/NullPlayer/Windows/WinampModern/'
behaviour='WinampModern/(WasabiRendererHitTesting|WinampModernScriptRuntime|WinampModernScriptHooks|MakiBytecode|WasabiObjectGraph|WasabiSkinInitializer|WinampModernSkinLoader|WinampModernClickActions|WinampModernHostActions|WinampModernEQActions|WinampModernKeyAccelerator|WinampModernConfig)'

render=0; behave=0
while IFS= read -r f; do
  [[ -z $f ]] && continue
  if [[ $f =~ $window ]]; then continue
  elif [[ $f =~ $engine ]]; then render=1; [[ $f =~ $behaviour ]] && behave=1
  else render=1; behave=1          # shared code: every sweep, and the change must be gated on .wal
  fi
done <<< "$changed"

{
  echo "base $base"
  echo "changed sources:"; sed 's/^/  /' <<< "${changed:-  (none)}"
  echo "render $render  interaction+motion $behave"
  [[ $render$behave == 00 ]] && echo "no headless sweep reaches this change: check it live (window-census.sh --shots, wal_live_smoke.sh)"
} > "$out/plan.txt"
cat "$out/plan.txt"
[[ $dry == --dry-run || $render$behave == 00 ]] && exit 0

if [[ $render == 1 ]]; then
  r="$out/render"; mkdir -p "$r"
  scripts/wal_render_sweep.sh capture "$r/base" --rev "$base" --shards 10 > "$r/base.log" 2>&1 \
    || { echo "render: no stored baseline for $base (see $r/base.log); capture it once in a worktree" >&2; exit 3; }
  scripts/wal_render_sweep.sh capture "$r/after" --allow-dirty --shards 10 > "$r/after.log" 2>&1
  scripts/wal_render_sweep.sh compare "$r/base" "$r/after" > "$r/compare.txt" 2>&1 || true
  echo "render: $(grep -c '^DIFF' "$r/compare.txt" || true) DIFF lines -> $r/compare.txt"
fi

if [[ $behave == 1 ]]; then
  for kind in interaction:30 motion:10; do
    name=${kind%%:*}; shards=${kind##*:}; d="$out/$name"; mkdir -p "$d"
    scripts/wal_${name}_sweep.sh "$d/base" --rev "$base" --shards "$shards" > "$d/base.log" 2>&1 \
      || { echo "$name: no stored baseline for $base (see $d/base.log); capture it once in a worktree" >&2; exit 3; }
    scripts/wal_${name}_sweep.sh "$d/after" --allow-dirty --shards "$shards" > "$d/after.log" 2>&1
    diff <(sort "$d/base/$name.tsv") <(sort "$d/after/$name.tsv") > "$d/diff.txt" || true
    echo "$name: $(grep -c '^[<>]' "$d/diff.txt" || true) changed rows -> $d/diff.txt"
  done
fi
