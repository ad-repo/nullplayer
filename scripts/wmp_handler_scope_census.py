#!/usr/bin/env python3
"""What a `.wmz` event handler names without qualifying it, across the installed corpus (W216).

Two reports, because the class has two halves and only one of them was ever counted:

  * every unqualified **call** of an element-method name, resolved through the skin's own functions
    to three levels, and
  * every unqualified **property** reference that names an attribute the handler's own element
    authored — split into reads (which threw before W216) and writes (which silently made a global),
    and net of the two names the engine binds for a handler already: `value`, and the changing
    attribute inside an `<attribute>_onchange`.

**The census cannot answer either.** `wmp_skin_census.sh` drives `onLoad` and this demand is in
`onClick`, which is the blind spot that recorded W100 at 2 skins when 162 archives authored it. So
this reads the decoded script text directly, the way `WMPTextDecoder` does, and repairs the
`01 00 01 00` local file headers the way `WMPArchiveHeaderRepair` does — without that,
`Need_for_Speed_Underground` and `SplinterCellWMPSkin` are dropped on a `BadZipFile` and a scan
that never prints what it skipped reads as a clean corpus. The **encoding breakdown is printed as
calibration**: a correct run over 184 archives reproduces 158 UTF-16-BOM / 146 cp1252 / 89 UTF-8 /
9 UTF-8-BOM.

  scripts/wmp_handler_scope_census.py [json-out]

Measured 2026-09-21 for W216: 31 calls / 20 archives, and 255 unresolved reads + 249 silent writes
across 100 of 184 archives. See `docs/wmp-skin/wmp-backlog-archive.md` § W216.
"""
import io, os, re, struct, sys, zipfile
from collections import Counter, defaultdict

CORPUS = os.path.expanduser("~/Library/Application Support/NullPlayer/WMPSkins")
EXCL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wmp_corpus_exclusions.txt")

# WMPObjectModel.elementMethodVocabulary
VOCAB = set("""alphablendto movesizeto moveto slideto resizeto
close maximize minimize restore returntomediacenter size
abortcopy addselectedtoplaylist copy deleteselected deleteselectedfromlibrary
getnextcheckeditem getnextcheckeditem2 getnextselecteditem getnextselecteditem2
moveselecteddown moveselectedup setcheckedstate setcheckedstate2 setcolumnresizemode
setcolumnwidth setselectedstate setselectedstate2 sortcolumn
appenditem deleteall deleteitem dismiss finditem getitem insertitem replaceitem show
getline getlinefromchar getlineindex getselectionend getselectionstart replaceselection setselection
effecttitle effecttype next nexteffect nextpreset previous previouseffect previouspreset settings
click getbutton
hide removeallitems removeitem selectitem setfocus invoke play stop""".split())
# WMPObjectModel.implementedElementMethods
IMPLEMENTED = set("""moveto resizeto alphablendto close minimize returntomediacenter size
appenditem removeallitems getitem setcolumnresizemode setcolumnwidth next previous nextpreset""".split())

ATTR = re.compile(r'\b([A-Za-z_][\w]*)\s*=\s*(["\'])(.*?)\2', re.S)
CALL = re.compile(r'(?<![\w.$])([A-Za-z_$][\w$]*)\s*\(')
DEF = re.compile(r'\bfunction\s+([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{', re.I)
TAG = re.compile(r'<\s*([A-Za-z_][\w:]*)\b')


def decode(data):
    if data[:3] == b'\xef\xbb\xbf':
        try: return data[3:].decode('utf-8'), 'utf8-bom'
        except Exception: return None, None
    for bom, enc, label in ((b'\xff\xfe', 'utf-16-le', 'utf16-bom'), (b'\xfe\xff', 'utf-16-be', 'utf16-bom')):
        if data[:2] == bom:
            try: return data[2:].decode(enc), label
            except Exception: return None, None
    if len(data) >= 4 and len(data) % 2 == 0:
        s = data[:4096]
        even = sum(1 for i in range(len(s)) if s[i] == 0 and i % 2 == 0)
        odd = sum(1 for i in range(len(s)) if s[i] == 0 and i % 2 == 1)
        enc = 'utf-16-le' if (odd and not even) else 'utf-16-be' if (even and not odd) else None
        if enc:
            try:
                t = data.decode(enc)
                if t.lstrip()[:1] == '<': return t, 'utf16-nobom'
            except Exception: pass
    try: return data.decode('utf-8'), 'utf8'
    except Exception: pass
    try: return data.decode('cp1252'), 'cp1252'
    except Exception: return None, None


def repaired(path):
    """WMPArchiveHeaderRepair in miniature: rewrite a local header signature only where the header
    already agrees with the central-directory record pointing at it."""
    data = bytearray(open(path, 'rb').read())
    end = data.rfind(b'PK\x05\x06')
    if end < 0: return None
    offset = struct.unpack_from('<I', data, end + 16)[0]
    count = struct.unpack_from('<H', data, end + 10)[0]
    fixed = 0
    for _ in range(count):
        if data[offset:offset + 4] != b'PK\x01\x02': break
        nlen, elen, clen = struct.unpack_from('<HHH', data, offset + 28)
        local = struct.unpack_from('<I', data, offset + 42)[0]
        name = bytes(data[offset + 46:offset + 46 + nlen])
        if data[local:local + 4] != b'PK\x03\x04':
            if struct.unpack_from('<H', data, local + 26)[0] == nlen \
               and bytes(data[local + 30:local + 30 + nlen]) == name:
                data[local:local + 4] = b'PK\x03\x04'; fixed += 1
        offset += 46 + nlen + elen + clen
    return bytes(data) if fixed else None


def archives():
    excluded = set()
    if os.path.exists(EXCL):
        for line in open(EXCL):
            line = line.split('#')[0].strip()
            if line: excluded.add(line)
    for name in sorted(os.listdir(CORPUS)):
        if name.lower().endswith('.wmz') and name not in excluded:
            yield name


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



IDENT = re.compile(r'(?<![\w.$])([A-Za-z_$][\w$]*)')
# JScript's own names, which are never the element's however the element is spelled.
KEYWORDS = {name.lower() for name in """var function return if else for while do break continue new
delete typeof instanceof this true false null undefined in with try catch finally throw switch case
default void Math String Number Array Object Date parseInt parseFloat isNaN alert setTimeout
setInterval clearTimeout clearInterval Boolean RegExp length toString eval jscript""".split()}
TAGSTART = re.compile(r'<\s*([A-Za-z_][\w:]*)((?:[^<>"\']|"[^"]*"|\'[^\']*\')*)>?', re.S)


def property_half(texts, whole):
    """(name, tag, attribute, kind, body) per unqualified reference to an own attribute.

    `kind` is `R` for a read and `W` for an assignment: they fail differently and are counted
    apart. Names the engine binds for the handler already — `value`, and the changing attribute in
    an `<attribute>_onchange` — are not part of this, and neither is a name the skin declares as a
    global of its own, which reaches that global whatever the element is called.
    """
    globals_ = {m.group(1).lower() for m in DEF.finditer(whole)}
    globals_ |= {m.group(3).lower() for m in ATTR.finditer(whole) if m.group(1).lower() == 'id'}
    globals_ |= {m.group(1).lower() for m in re.finditer(r'\bvar\s+([A-Za-z_$][\w$]*)', whole)}
    for filename, text in texts.items():
        if not filename.lower().endswith('.wms'):
            continue
        for tag in TAGSTART.finditer(text):
            attributes = {m.group(1).lower(): m.group(3) for m in ATTR.finditer(tag.group(2) or '')}
            own = {name for name in attributes if not is_handler(name)}
            for name, body in attributes.items():
                if not is_handler(name):
                    continue
                bound = {'value'} if 'value' in own else set()
                if name.endswith('_onchange'):
                    bound.add(name[:-len('_onchange')])
                for match in IDENT.finditer(body):
                    low = match.group(1).lower()
                    if low not in own or low in bound or low in globals_ or low in KEYWORDS:
                        continue
                    kind = 'W' if re.match(r'\s*=[^=]', body[match.end():]) else 'R'
                    yield low, tag.group(1).upper(), name, kind, ' '.join(body.split())[:90]


def is_handler(attribute):
    """`onClick`, `value_onchange` — the attributes WMP raises rather than reads."""
    return attribute.startswith('on') or attribute.endswith('_onchange')


def main():
    encodings, enc_archives = Counter(), defaultdict(set)
    direct = defaultdict(list)     # bare call written in the handler attribute itself
    indirect = defaultdict(list)   # bare call in a function the handler calls (<=3 levels)
    reads, writes = defaultdict(set), defaultdict(set)
    read_uses, write_uses = Counter(), Counter()
    unreadable = []
    scanned = 0
    for arch in archives():
        path = os.path.join(CORPUS, arch)
        try:
            data = repaired(path)
            zf = zipfile.ZipFile(io.BytesIO(data) if data else path)
        except Exception as exc:
            unreadable.append((arch, str(exc))); continue
        scanned += 1
        texts = {}
        for info in zf.infolist():
            if not info.filename.lower().endswith(('.wms', '.js')): continue
            try: raw = zf.read(info)
            except Exception as exc:
                unreadable.append((arch + '/' + info.filename, str(exc))); continue
            text, enc = decode(raw)
            if text is None: continue
            encodings[enc] += 1; enc_archives[enc].add(arch)
            texts[info.filename] = text
        whole = "\n".join(texts.values())
        defined = {m.group(1).lower() for m in DEF.finditer(whole)}

        def bare(source, seen=()):
            """(name, ...) for every unqualified call of an element-method name in `source`."""
            for name in CALL.findall(source):
                low = name.lower()
                if low in VOCAB and low not in defined:
                    yield low, None
                elif low in defined and low not in seen and len(seen) < 3:
                    body = body_of(whole, low)
                    if body:
                        for inner, _ in bare(body, tuple(seen) + (low,)):
                            yield inner, low

        for fname, text in texts.items():
            if not fname.lower().endswith('.wms'): continue
            for m in ATTR.finditer(text):
                attr = m.group(1).lower()
                if not is_handler(attr): continue
                body = m.group(3)
                start = text.rfind('<', 0, m.start())
                tagm = TAG.match(text[start:]) if start >= 0 else None
                tag = tagm.group(1).upper() if tagm else '?'
                for name, via in bare(body):
                    row = (arch, tag, attr, ' '.join(body.split())[:100], via)
                    (indirect if via else direct)[name].append(row)

        for name, _tag, _attr, kind, _body in property_half(texts, whole):
            if kind == 'W':
                writes[name].add(arch); write_uses[name] += 1
            else:
                reads[name].add(arch); read_uses[name] += 1

    print("archives scanned: %d" % scanned)
    print("\nencoding breakdown (files / archives touching that encoding):")
    for enc, count in encodings.most_common():
        print("  %-12s %5d files  %3d archives" % (enc, count, len(enc_archives[enc])))

    for label, table in (("written in the handler attribute", direct),
                         ("inside a function the handler calls (<=3 levels)", indirect)):
        arcs = {r[0] for rows in table.values() for r in rows}
        print("\n== unqualified element-method call %s ==" % label)
        print("   %d uses / %d archives" % (sum(len(v) for v in table.values()), len(arcs)))
        for name, rows in sorted(table.items(), key=lambda kv: -len(kv[1])):
            print("   %-16s %3d uses %3d archives  impl=%s tags=%s" % (
                name, len(rows), len({r[0] for r in rows}),
                'yes' if name in IMPLEMENTED else 'NO',
                dict(Counter(r[1] for r in rows))))
        for name, rows in sorted(table.items()):
            for r in rows:
                print("     %-12s %-32s %-10s %-14s %s" % (name, r[0], r[1], r[2], r[3]))
    print("\n== unqualified reference to an attribute the handler's own element authored ==")
    print("   (net of `value` and the `<attribute>_onchange` name, which the engine binds)")
    print("   %d reads + %d writes" % (sum(read_uses.values()), sum(write_uses.values())))
    for name in sorted(set(read_uses) | set(write_uses),
                       key=lambda n: -(read_uses[n] + write_uses[n])):
        print("   %-20s R %4d uses %3d archives   W %4d uses %3d archives" % (
            name, read_uses[name], len(reads[name]), write_uses[name], len(writes[name])))
    read_archives = set().union(*reads.values()) if reads else set()
    write_archives = set().union(*writes.values()) if writes else set()
    print("   archives with a read: %d ; with a write: %d ; either: %d"
          % (len(read_archives), len(write_archives), len(read_archives | write_archives)))

    both = {r[0] for t in (direct, indirect) for rows in t.values() for r in rows}
    print("\nARCHIVES AFFECTED (%d of %d), call half: %s"
          % (len(both), scanned, ", ".join(sorted(both))))
    if unreadable: print("\nUNREADABLE: %s" % unreadable)
    if len(sys.argv) > 1:
        import json
        json.dump({'direct': direct, 'indirect': indirect}, open(sys.argv[1], 'w'), indent=1)


main()
