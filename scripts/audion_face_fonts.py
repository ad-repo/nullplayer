#!/usr/bin/env python3
"""Extract the fonts Panic's original Audion faces ship, with the evidence for their licences.

    audion_face_fonts.py <cache> <corpus> [--ship <Sources/NullPlayer/Resources/Fonts/AudionFaces>]

<cache> is scripts/audion_panic_originals.sh's. 165 face archives carry the font the face names
next to the face file, a classic Mac font suitcase: `FOND` (the family, mapping size and style to
a font resource), `sfnt` (TrueType) and `NFNT`/`FONT` (QuickDraw bitmap strikes). The 2021
conversion dropped them. This writes each family once to <cache>/fonts/<family>/ — `sfnt-<style>.ttf` per
sfnt, `<size>-<style>.nfnt` per bitmap strike (the resource's bytes as stored) — and
<cache>/fonts/fonts.tsv: family, files, the archives carrying it, the installed faces naming it,
the TrueType name table's copyright and licence strings, and any archive text that mentions a
licence. Which families NullPlayer may ship is decided from that file, never assumed: `SHIP` is
the decision (2026-11-01: every family released as freeware or with redistribution allowed, and
named by an installed face; commercial and "redistribution prohibited" fonts never ship).
`--ship` copies those families' plain-style files into the app with a NOTICE.txt of the evidence,
and prints their scripts/third_party_components.tsv rows.
Documented in skills/audion-face-guide/reference/harness.md.
"""

import collections
import csv
import json
import os
import re
import struct
import sys



def fork_with_names(path):
    """{type: {id: (name, bytes)}} from an AppleDouble file's resource fork."""
    data = open(path, 'rb').read()
    if data[:4] != b'\x00\x05\x16\x07':
        return {}
    fork = b''
    for i in range(struct.unpack('>H', data[24:26])[0]):
        entry, offset, length = struct.unpack('>III', data[26 + 12 * i:38 + 12 * i])
        if entry == 2:
            fork = data[offset:offset + length]
    if len(fork) < 16:
        return {}
    data_offset, map_offset, _, map_length = struct.unpack('>IIII', fork[:16])
    rmap = fork[map_offset:map_offset + map_length]
    types_offset, names_offset = struct.unpack('>HH', rmap[24:28])
    found = {}
    for t in range(struct.unpack('>H', rmap[types_offset:types_offset + 2])[0] + 1):
        kind, count, refs = struct.unpack('>4sHH', rmap[types_offset + 2 + 8 * t:types_offset + 10 + 8 * t])
        for r in range(count + 1):
            at = types_offset + refs + 12 * r
            rid, name_at, attrs = struct.unpack('>hHI', rmap[at:at + 8])
            start = data_offset + (attrs & 0xFFFFFF)
            length = struct.unpack('>I', fork[start:start + 4])[0]
            name = ''
            if name_at != 0xFFFF:
                p = names_offset + name_at
                name = rmap[p + 1:p + 1 + rmap[p]].decode('mac_roman')
            found.setdefault(kind.decode('mac_roman'), {})[rid] = (name, fork[start + 4:start + 4 + length])
    return found


def associations(fond):
    """FOND's font association table: (size, style, resource id); size 0 is an sfnt."""
    count = struct.unpack('>h', fond[52:54])[0] + 1
    return [struct.unpack('>hhh', fond[54 + 6 * i:60 + 6 * i]) for i in range(count) if 60 + 6 * i <= len(fond)]


def name_strings(ttf):
    """The TrueType name table's copyright (0), trademark (7), manufacturer (8), licence (13, 14)."""
    if len(ttf) < 12:
        return {}
    tables = {}
    for i in range(struct.unpack('>H', ttf[4:6])[0]):
        tag, _, offset, length = struct.unpack('>4sIII', ttf[12 + 16 * i:28 + 16 * i])
        tables[tag] = (offset, length)
    if b'name' not in tables:
        return {}
    base = tables[b'name'][0]
    count, strings = struct.unpack('>HH', ttf[base + 2:base + 6])
    mac, unicode = {}, {}
    for i in range(count):
        platform, encoding, _, name_id, length, offset = struct.unpack('>HHHHHH', ttf[base + 6 + 12 * i:base + 18 + 12 * i])
        if name_id not in (0, 7, 8, 13, 14):
            continue
        raw = ttf[base + strings + offset:base + strings + offset + length]
        if platform == 1:
            mac.setdefault(name_id, raw.decode('mac_roman'))
        elif platform in (0, 3):
            unicode.setdefault(name_id, raw.decode('utf-16-be', 'replace'))
    # The Mac Roman record is the author's own text; these fonts' Unicode records were converted
    # from it byte for byte (04b-03's "oshimoto" has 0xFFFF for its "t", IceDogg's © is 0x33FF).
    return unicode | mac


LICENCE_WORDS = re.compile(r'(?i)(licen[cs]e|freeware|shareware|public domain|copyright|©|\(c\)|free for|'
                           r'redistribut|commercial|all rights reserved)')


def archive_text(root):
    """Every line of readable text in an archive's data forks that mentions a licence."""
    lines = []
    for folder, _, files in os.walk(root):
        for file in files:
            if file.endswith('.rsrc'):
                continue
            path = os.path.join(folder, file)
            try:
                raw = open(path, 'rb').read(200_000)
            except OSError:
                continue
            if b'\x00' in raw[:2000]:
                continue
            text = raw.decode('mac_roman', 'replace').replace('\r', '\n')
            for line in text.split('\n'):
                if LICENCE_WORDS.search(line) and len(line) < 400:
                    lines.append(f'{file}: {line.strip()}')
    return lines


FREEWARE, NON_COMMERCIAL, PUBLIC_DOMAIN = ('LicenseRef-Freeware', 'LicenseRef-Freeware-NonCommercial',
                                         'LicenseRef-Public-Domain')
SHIP = {
    '04b-03': FREEWARE, '04b-08': FREEWARE, '04b-09': FREEWARE, '04b-11': FREEWARE, '04b-20': FREEWARE,
    '04b-24': FREEWARE, '04bit-10': FREEWARE, '04bit-16': FREEWARE, 'Architxt': PUBLIC_DOMAIN, 'BitBit': FREEWARE,
    'Bitsumishi': NON_COMMERCIAL, "Burton's Nightmare": FREEWARE, 'Cry Uncial': NON_COMMERCIAL, 'Display': FREEWARE,
    'FreeceMini': FREEWARE, 'Froufrou Regular': FREEWARE, 'HI-LOGIN-REG': FREEWARE, 'hooge 05_53': FREEWARE,
    'IceDogg': FREEWARE, 'less=more': FREEWARE, 'Lilliput Steps': FREEWARE, 'LipoD-Nine': FREEWARE,
    'Mini': FREEWARE, 'Mini Tight': FREEWARE, 'neo-geo': FREEWARE, 'Orchis 5': FREEWARE, 'Orchis 6': FREEWARE,
    'Roundstyle-Regular': FREEWARE, 'Squarodynamic 08': NON_COMMERCIAL,
}


def ship(out_root, families, dest):
    """Copy each SHIP family's plain-style files to dest/<family>/ with NOTICE.txt; print tsv rows."""
    os.makedirs(dest, exist_ok=True)
    rows = []
    for family, entry in sorted(families.items(), key=lambda e: e[0].strip().lower()):
        name = family.strip()
        if name not in SHIP:
            continue
        files = sorted(f for f in entry['files'] if f.endswith('-0.ttf') or f.endswith('-0.nfnt'))
        target = os.path.join(dest, name)
        os.makedirs(target, exist_ok=True)
        for file in files:
            with open(os.path.join(out_root, name.replace('/', ':'), file), 'rb') as src, \
                    open(os.path.join(target, file), 'wb') as out:
                out.write(src.read())
        copyright = entry['names'].get(0, '').replace('\x00', '').strip()
        evidence = sorted(line for line in entry['text']
                          if 'font' in line.lower() or name.lower().split()[0] in line.lower())
        with open(os.path.join(target, 'NOTICE.txt'), 'w') as notice:
            notice.write(f'{name}\n\nShipped as the author released it, with the Audion face(s) that carried it: '
                         + ', '.join(f'https://download.panic.com/audion/faces/{a}.sit.bin' for a in sorted(entry['archives']))
                         + f'.\nLicence: {SHIP[name]}.\n')
            if copyright:
                notice.write(f'\nThe font\'s own notice: {copyright}\n')
            if evidence:
                notice.write('\nWhat the face archives say about it:\n' + ''.join(f'  {line}\n' for line in evidence))
        key = 'audion-font-' + re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
        rows.append('\t'.join([key, f'{name} (Audion face font, original)', SHIP[name],
                                copyright or 'see NOTICE.txt', 'https://download.panic.com/audion/faces/',
                                'bundled', f'Fonts/AudionFaces/{name}/NOTICE.txt', '-']))
    print('\n'.join(rows))


def main(cache, corpus, dest=None):
    out_root = os.path.join(cache, 'fonts')
    os.makedirs(out_root, exist_ok=True)
    families = collections.defaultdict(lambda: {'files': set(), 'archives': set(), 'names': {}, 'text': set()})
    extract = os.path.join(cache, 'extract')
    for code in sorted(os.listdir(extract)):
        root = os.path.join(extract, code)
        for folder, _, files in os.walk(root):
            for file in files:
                if not file.endswith('.rsrc'):
                    continue
                try:
                    found = fork_with_names(os.path.join(folder, file))
                except (struct.error, IndexError):
                    continue
                for fond_id, (family, fond) in found.get('FOND', {}).items():
                    if not family:
                        continue
                    entry = families[family]
                    entry['archives'].add(code)
                    entry['text'].update(archive_text(root))
                    target = os.path.join(out_root, family.strip().replace('/', ':'))
                    os.makedirs(target, exist_ok=True)
                    for size, style, rid in associations(fond):
                        if size == 0:
                            data = found.get('sfnt', {}).get(rid, (None, None))[1]
                            name = f'sfnt-{style}.ttf'
                            if data:
                                entry['names'].update(name_strings(data))
                        else:
                            data = (found.get('NFNT', {}).get(rid) or found.get('FONT', {}).get(rid) or (None, None))[1]
                            name = f'{size}-{style}.nfnt'
                        if data:
                            with open(os.path.join(target, name), 'wb') as handle:
                                handle.write(data)
                            entry['files'].add(name)
    named = collections.defaultdict(set)
    for face in os.listdir(corpus):
        path = os.path.join(corpus, face, 'index.json')
        if os.path.isfile(path):
            index = json.load(open(path, 'rb'))
            for role in ('artist', 'album'):
                name = index.get(f'{role}DisplayFontName')
                if name:
                    named[name.strip().lower()].add(face)
    with open(os.path.join(out_root, 'fonts.tsv'), 'w') as table:
        writer = csv.writer(table, delimiter='\t')
        writer.writerow(['family', 'files', 'archives', 'faces', 'copyright', 'trademark', 'maker', 'licence', 'licence url', 'archive text'])
        for family, entry in sorted(families.items(), key=lambda e: e[0].strip().lower()):
            names = entry['names']
            writer.writerow([family, ' '.join(sorted(entry['files'])), ' '.join(sorted(entry['archives'])),
                             ' | '.join(sorted(named.get(family.strip().lower(), ()))),
                             names.get(0, ''), names.get(7, ''), names.get(8, ''), names.get(13, ''), names.get(14, ''),
                             ' || '.join(sorted(entry['text']))[:2000]])
    print(f'audion_face_fonts: {len(families)} families -> {out_root}/fonts.tsv')
    if dest:
        ship(out_root, families, dest)


if __name__ == '__main__':
    if len(sys.argv) not in (3, 5) or (len(sys.argv) == 5 and sys.argv[3] != '--ship'):
        sys.exit(__doc__.strip().split('\n\n')[1])
    main(sys.argv[1], sys.argv[2], sys.argv[4] if len(sys.argv) == 5 else None)
