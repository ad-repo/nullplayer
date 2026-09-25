#!/usr/bin/env python3
"""Which authored controls across the `.wmz` corpus reach one handler or member, and where to click
each one (W267) — `harness.md` § *Auditing one authored control across the whole corpus*, scripted.

  scripts/wmp_control_audit.py [--render <render.txt>] [--sample N] [--skin <archive>] [-v]
                               [--corpus <dir>] <member>

`<member>` is the name the handler has to reach — `returnToMediaCenter`, `view.returnToMediaCenter`,
`player.controls.play`; only its last path component is matched, case-insensitively, since the
receiver is spelled a dozen ways (W100: `vFull`, `ballview`, `KidsView` …).

  1. Every `.wms`/`.js` entry is decoded through `wmp_corpus.py`, and the encoding breakdown is
     printed as calibration: the census drives `onLoad`, a control's demand lives in `onClick`, and
     a scan that does not reproduce the corpus's breakdown is not reading what the engine reads.
  2. Each handler attribute is resolved through the skin's own functions to three levels, because
     `onClick` is usually `SwitchSmall()` and the mechanism is in the body.
  3. With `--render`, the clickable point comes from a `WMP_RENDER_PROBE=all` capture: a drawn node
     at its frame's centre; a `<BUTTONELEMENT>` through its group's mapping bitmap, at the **median**
     pixel of its colour in scan order — the first one lands on a stray and resolves to the
     adjacent button.
  4. A control with no probe line falls back to its authored `left`/`top` chain (`authored`,
     `authored-mapping`), or says `none (<why>)`. **The fallback is a guess, not a measurement**: it
     ignores alignment, script moves and hidden groups. Clicked across the corpus for W100's member
     (2026-09-25) it hit 26 of 65, where `probe`/`mapping` hit 129 of 131 — the two misses being
     `digitaldj`, whose script disables its transport, and `Plus!_The_Bionic_Dot`.
  5. `--sample N` prints the `WMP_RENDER_CLICK` + `WMP_CALL_TRACE=1` runs for N controls located
     from drawn geometry; read `unrecognised=` and `command=` on them, not the screen.

The census capture does not carry `PROBE` lines; without `--render` the script prints the command
that makes one (~35 s for the corpus once the tests are built). An id-less `<VIEW>` is `view-<n>` in
that capture and `-` here until a probe line names it.
"""
import argparse, io, os, re, sys
from collections import Counter, defaultdict

sys.dont_write_bytecode = True   # no scripts/__pycache__ from importing wmp_corpus
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmp_corpus import CORPUS, archives, decode, open_archive

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ATTR = re.compile(r'([A-Za-z_][\w:.-]*)\s*=\s*(?:"([^"]*)"|\'([^\']*)\')', re.S)
TAGRX = re.compile(r'<!--.*?-->|<\s*(/?)\s*([A-Za-z_][\w:]*)((?:[^<>"\']|"[^"]*"|\'[^\']*\')*?)(/?)\s*>', re.S)
CALL = re.compile(r'(?<![\w.$])([A-Za-z_$][\w$]*)\s*\(')
DEF = re.compile(r'\bfunction\s+([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{', re.I)
COMMENT = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)
PROBE = re.compile(r'^PROBE (\S+?)/(\S+) (\S+) id=(\S+) frame=(-?[\d.]+),(-?[\d.]+) ([\d.]+)x([\d.]+) .*attrs=\[(.*)\]$')


def is_handler(attribute):
    return attribute.startswith('on') or attribute.endswith('_onchange')


def body_of(text, name):
    """The source of `function name(...) { ... }`, brace-matched."""
    for m in DEF.finditer(text):
        if m.group(1).lower() != name: continue
        depth, i = 0, m.end() - 1
        while i < len(text):
            if text[i] == '{': depth += 1
            elif text[i] == '}':
                depth -= 1
                if depth == 0: return text[m.end():i]
            i += 1
    return None


def number(value):
    try: return float(value)
    except (TypeError, ValueError): return 0.0


class Control:
    def __init__(self, **kw): self.__dict__.update(kw)


def controls_in(texts, member_rx):
    """Every element whose handler reaches the member, directly or through <=3 function levels."""
    whole = COMMENT.sub('', "\n".join(texts.values()))
    defined = {m.group(1).lower() for m in DEF.finditer(whole)}
    bodies = {}

    def reach(source, seen=()):
        """The call chain (tuple of function names) through which `source` reaches the member."""
        if member_rx.search(source): return seen
        if len(seen) >= 3: return None
        for name in CALL.findall(source):
            low = name.lower()
            if low not in defined or low in seen: continue
            if low not in bodies: bodies[low] = body_of(whole, low) or ''
            found = reach(bodies[low], seen + (low,))
            if found is not None: return found
        return None

    found = []
    for fname, text in texts.items():
        if not fname.lower().endswith('.wms'): continue
        stack, first_view = [], None
        pos = 0
        while True:
            m = TAGRX.search(text, pos)
            if not m: break
            pos = m.end()
            if m.group(0).startswith('<!--'): continue
            closing, tag, rest, selfclosing = m.group(1), m.group(2).upper(), m.group(3) or '', m.group(4)
            if closing:
                for i in range(len(stack) - 1, -1, -1):
                    if stack[i][0] == tag: del stack[i:]; break
                continue
            attrs = {a.group(1).lower(): a.group(2) if a.group(2) is not None else a.group(3)
                     for a in ATTR.finditer(rest)}
            if tag == 'VIEW' and first_view is None: first_view = attrs.get('id', '')
            if tag == 'SCRIPT' and not selfclosing and not rest.rstrip().endswith('/'):
                end = re.compile(r'</\s*script\s*>', re.I).search(text, pos)
                pos = end.end() if end else len(text)
                continue
            for attr, body in attrs.items():
                if not is_handler(attr): continue
                chain = reach(COMMENT.sub('', body))
                if chain is None: continue
                view = attrs if tag == 'VIEW' else next((a for t, a in reversed(stack) if t == 'VIEW'), {})
                group = next((a for t, a in reversed(stack) if t == 'BUTTONGROUP'), None) \
                    if tag == 'BUTTONELEMENT' else None
                # Authored offset: every positioned ancestor below the view, plus the element.
                chain_xy = [a for t, a in stack[next((i for i in range(len(stack) - 1, -1, -1)
                                                        if stack[i][0] == 'VIEW'), -1) + 1:]] + [attrs]
                found.append(Control(
                    file=fname, tag=tag, id=attrs.get('id', ''), attr=attr, body=' '.join(body.split()),
                    via=chain, tooltip=attrs.get('uptooltip') or attrs.get('tooltip') or '',
                    view=view.get('id', ''), first_view=first_view, group=group,
                    color=attrs.get('mappingcolor', ''), attrs=attrs,
                    authored=(sum(number(a.get('left')) for a in chain_xy),
                              sum(number(a.get('top')) for a in chain_xy)),
                    has_xy=any('left' in a or 'top' in a for a in chain_xy)))
            if not selfclosing and not rest.rstrip().endswith('/'):
                stack.append((tag, attrs))
    return found


def read_render(path):
    """{archive: [(view, sid, kind, id, x, y, w, h, attrs)]} from a WMP_RENDER_PROBE capture."""
    blocks, current = defaultdict(list), None
    for line in open(path, errors='replace'):
        if line.startswith('SKIN '):
            current = line.split()[1]; continue
        m = PROBE.match(line)
        if m and current:
            v, sid, kind, nid, x, y, w, h, attrs = m.groups()
            blocks[current].append((v, sid, kind, nid, float(x), float(y), float(w), float(h), attrs))
    return blocks


def mapping_point(zf, group, color, frame):
    """Median pixel of `color` in the group's mapping bitmap, scaled to the group's frame."""
    from PIL import Image
    path = group.get('mappingimage')
    if not path or not color: return None, 'no mapping'
    names = {i.filename.lower().replace('\\', '/'): i.filename for i in zf.infolist()}
    entry = names.get(path.lower().replace('\\', '/')) or next(
        (n for k, n in names.items() if k.endswith('/' + path.lower())), None)
    if not entry: return None, 'mapping %s missing' % path
    image = Image.open(io.BytesIO(zf.read(entry))).convert('RGBA')
    want = color.strip().lstrip('#').lower()
    try: target = tuple(int(want[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError: return None, 'colour %s unreadable' % color
    width, height = image.size
    pixels = image.load()
    # WMPMappingImage: an exact RGB match, and an alpha-zero pixel is never interactive.
    hits = [(x, y) for y in range(height) for x in range(width)
            if pixels[x, y][3] and pixels[x, y][:3] == target]
    if not hits: return None, 'colour %s absent' % color
    px, py = hits[len(hits) // 2]
    gx, gy, gw, gh = frame
    sx = gw / width if width and gw else 1
    sy = gh / height if height and gh else 1
    return (round(gx + (px + 0.5) * sx), round(gy + (py + 0.5) * sy)), 'mapping'


def locate(control, probes, zf):
    """(view, point, source) for one control."""
    def by_id(nid):
        rows = [r for r in probes if r[3].lower() == nid.lower()]
        same = [r for r in rows if r[0].lower() == control.view.lower()]
        return (same or rows or [None])[0]

    def by_handler():
        """A node with no id, matched on its own authored handler text (PROBE condenses to 80)."""
        text = ' '.join(control.attrs.get(control.attr, '').split())[:60].lower()
        rows = [r for r in probes if r[3] == '-' and r[2].lower() == control.tag.lower()
                and text and text in r[8].lower()]
        same = [r for r in rows if r[0].lower() == control.view.lower()]
        return (same or rows or [None])[0] if len(same or rows) == 1 else None

    if control.tag == 'BUTTONELEMENT' and control.group is not None:
        row = by_id(control.group['id']) if control.group.get('id') else None
        if row is None:
            # An unnamed group: the drawn group with the same mapping bitmap, anywhere in the skin —
            # an id-less view is `view-<n>` in the probe, and a nested group is drawn away from its
            # own left/top. Ties go to the same view, then to the group's own authored left/top.
            mapping = (control.group.get('mappingimage') or '').lower()
            rows = [r for r in probes if r[2] == 'buttonGroup' and mapping
                    and 'mappingimage=' + mapping in r[8].lower()]
            if len(rows) > 1:
                rows = [r for r in rows if r[0].lower() == control.view.lower()] or rows
            if len(rows) > 1:
                own = ['%s=%s' % (k, control.group[k]) for k in ('left', 'top') if k in control.group]
                rows = [r for r in rows if all(o.lower() in r[8].lower().split() for o in own)] or rows
            row = rows[0] if len(rows) == 1 else None
        if row:
            point, why = mapping_point(zf, control.group, control.color, row[4:8])
            if point: return row[0], point, 'mapping'
            return row[0], None, why
        # A group that draws nothing has no PROBE line (Cablemusic): decode the mapping at the
        # group's authored origin, unscaled.
        ax, ay = control.authored
        point, why = mapping_point(zf, control.group, control.color, (ax, ay, 0, 0))
        if point: return control.view, point, 'authored-mapping'
        return control.view, None, 'none (%s)' % why
    else:
        row = by_id(control.id) if control.id else by_handler()
        if row:
            v, _, _, _, x, y, w, h, _ = row
            return v, (round(x + w / 2), round(y + h / 2)), 'probe'
    if control.has_xy:
        w = number(control.attrs.get('width')); h = number(control.attrs.get('height'))
        ax, ay = control.authored
        return control.view, (round(ax + w / 2), round(ay + h / 2)), 'authored'
    return control.view, None, 'none'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('member')
    ap.add_argument('--render', help='a WMP_RENDER_PROBE=all capture (render.txt)')
    ap.add_argument('--sample', type=int, default=15, help='click runs to print (default 15)')
    ap.add_argument('--skin', help='one archive only')
    ap.add_argument('-v', action='store_true', help='one line per control')
    ap.add_argument('--corpus', default=CORPUS)
    a = ap.parse_args()

    name = a.member.split('.')[-1].strip('()')
    member_rx = re.compile(r'(?<![\w$])' + re.escape(name) + r'(?![\w$])', re.I)
    probes = read_render(a.render) if a.render else None

    encodings, unreadable, scanned = Counter(), [], 0
    rows = []   # (archive, control, view, point, source)
    for arch in archives(a.corpus):
        if a.skin and arch.lower() not in (a.skin.lower(), a.skin.lower() + '.wmz'): continue
        try:
            zf = open_archive(os.path.join(a.corpus, arch))
        except Exception as exc:
            unreadable.append('%s (%s)' % (arch, exc)); continue
        scanned += 1
        texts = {}
        for info in zf.infolist():
            if not info.filename.lower().endswith(('.wms', '.js')): continue
            try: text, enc = decode(zf.read(info))
            except Exception as exc:
                unreadable.append('%s/%s (%s)' % (arch, info.filename, exc)); continue
            if text is None:
                unreadable.append('%s/%s (undecodable)' % (arch, info.filename)); continue
            encodings[enc] += 1
            texts[info.filename] = text
        for control in controls_in(texts, member_rx):
            if probes is None:
                view, point, source = control.view, None, 'no-render'
            else:
                try: view, point, source = locate(control, probes.get(arch, []), zf)
                except Exception as exc: view, point, source = control.view, None, 'error %s' % exc
            rows.append((arch, control, view, point, source))

    hit_archives = sorted({r[0] for r in rows})
    enc = ' / '.join('%d %s' % (c, e) for e, c in sorted(encodings.items(), key=lambda kv: (-kv[1], kv[0])))
    print('%s: %d controls in %d of %d archives' % (name, len(rows), len(hit_archives), scanned))
    print('  decoded %s (.wms + .js entries); %d unreadable' % (enc, len(unreadable)))
    for u in unreadable: print('    unreadable: ' + u)
    direct = sum(1 for r in rows if not r[1].via)
    print('  handler reaches it: %d in the attribute, %d through a function (<=3 levels)'
          % (direct, len(rows) - direct))
    print('  in the first <VIEW> of its file: %d controls, %d archives'
          % (sum(1 for r in rows if r[1].view == r[1].first_view),
             len({r[0] for r in rows if r[1].view == r[1].first_view})))
    print('  by tag: ' + ', '.join('%s %d' % kv for kv in Counter(r[1].tag for r in rows).most_common()))
    print('  by handler: ' + ', '.join('%s %d' % kv for kv in Counter(r[1].attr for r in rows).most_common()))
    print('  tooltips: ' + ', '.join('"%s" %d' % kv for kv in Counter(r[1].tooltip for r in rows).most_common(5)))
    print('  point: ' + ', '.join('%s %d' % kv for kv in
                                  Counter(r[4].split(' ')[0] for r in rows).most_common())
          + ('   (authored* is unverified — drive it before believing it)' if probes is not None else ''))

    if a.v:
        print()
        for arch, c, view, point, source in rows:
            where = '%d,%d' % point if point else '-'
            via = '>'.join(c.via) if c.via else '-'
            print('%-34s %-16s %-13s %-18s %-10s %-9s %-24s via=%s  %s' % (
                arch, view or '-', c.tag, c.id or '-', c.attr, where, source, via, c.body[:90]))

    if probes is None:
        print('\nno render capture: the clickable point needs one. Make it (one sweep, ~the census):')
        print('  WMP_SKIN="%s" WMP_RENDER_PROBE=all swift test --filter '
              'WMPRenderDumpTests/testSweepsSkinOrCorpus > render.txt 2> render.stderr.txt' % a.corpus)
        print('then re-run with --render render.txt')
        return

    located = [r for r in rows if r[3] and r[2] and r[4] in ('probe', 'mapping')]
    step = max(1, len(located) // a.sample) if a.sample else 0
    picks = located[::step][:a.sample] if step else []
    if picks:
        print('\n%d click runs (read `unrecognised=` and `command=`, not the screen):' % len(picks))
    for arch, c, view, point, source in picks:
        print("  WMP_SKIN=\"%s\" WMP_RENDER_CLICK='%s@%d,%d' WMP_CALL_TRACE=1 swift test --filter "
              "WMPRenderDumpTests/testSweepsSkinOrCorpus 2>&1 | grep -E '^(CLICK|CALL)'   # %s %s (%s)"
              % (os.path.join(a.corpus, arch), view, point[0], point[1], c.tag, c.id or '-', source))


if __name__ == '__main__':
    main()
