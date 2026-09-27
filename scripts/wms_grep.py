#!/usr/bin/env python3
"""grep for the `.wmz` corpus that reads what the engine reads.

  scripts/wms_grep.py [-i] [-l | -c] [--ext wms,js] [--corpus <dir>] <regex>

Every `.wms` / `.js` entry of every in-scope archive is decoded the way `WMPTextDecoder` does
(`scripts/wmp_corpus.py` says why a bare `grep` or `unzip -p | grep` silently under-counts), and the
regex runs over the decoded text, one line at a time.

  default   archive/entry:line: text          (text trimmed to 200 characters)
  -l        one archive name per line that matches
  -c        per-archive match counts, highest first

Always ends with a summary line on stderr — matches, entries, archives matched **of archives
scanned**, the encoding breakdown, and every archive or entry it could not read — because a count
without its denominator and its skips is exactly the number this script exists to replace.
For a tag or attribute tally with authored-demand semantics, `wmp_markup_census.sh` is still the
instrument; this is for everything else (a handler body, a member name, a literal).
"""
import argparse, os, re, sys
from collections import Counter

sys.dont_write_bytecode = True   # no scripts/__pycache__ from importing wmp_corpus
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmp_corpus import CORPUS, archives, decode, open_archive


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('pattern')
    ap.add_argument('-i', action='store_true', help='case-insensitive')
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument('-l', action='store_true', help='list matching archives')
    mode.add_argument('-c', action='store_true', help='per-archive counts')
    ap.add_argument('--ext', default='wms,js', help='entry extensions (default wms,js)')
    ap.add_argument('--corpus', default=CORPUS)
    a = ap.parse_args()

    rx = re.compile(a.pattern, re.I if a.i else 0)
    exts = tuple('.' + e.strip().lower().lstrip('.') for e in a.ext.split(','))
    per_archive, entries_hit, encodings = Counter(), set(), Counter()
    unreadable, scanned = [], 0
    for arch in archives(a.corpus):
        try:
            zf = open_archive(os.path.join(a.corpus, arch))
        except Exception as exc:
            unreadable.append('%s (%s)' % (arch, exc)); continue
        scanned += 1
        for info in zf.infolist():
            if not info.filename.lower().endswith(exts): continue
            try:
                text, enc = decode(zf.read(info))
            except Exception as exc:
                unreadable.append('%s/%s (%s)' % (arch, info.filename, exc)); continue
            if text is None:
                unreadable.append('%s/%s (undecodable)' % (arch, info.filename)); continue
            encodings[enc] += 1
            for n, line in enumerate(text.splitlines(), 1):
                hits = len(rx.findall(line))
                if not hits: continue
                per_archive[arch] += hits
                entries_hit.add((arch, info.filename))
                if not (a.l or a.c):
                    print('%s/%s:%d: %s' % (arch, info.filename, n, line.strip()[:200]))
    if a.l:
        for arch in sorted(per_archive): print(arch)
    if a.c:
        for arch, count in sorted(per_archive.items(), key=lambda kv: (-kv[1], kv[0])):
            print('%6d  %s' % (count, arch))
    enc = ' / '.join('%d %s' % (c, e) for e, c in sorted(encodings.items(), key=lambda kv: (-kv[1], kv[0])))
    print('wms_grep: %d matches in %d entries, %d of %d archives; decoded %s; %d unreadable'
          % (sum(per_archive.values()), len(entries_hit), len(per_archive), scanned, enc, len(unreadable)),
          file=sys.stderr)
    for u in unreadable: print('  unreadable: ' + u, file=sys.stderr)


if __name__ == '__main__':
    main()
