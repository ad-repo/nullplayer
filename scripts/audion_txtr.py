#!/usr/bin/env python3
"""Read the text settings (`Txtr`) out of Panic's original Audion faces.

    audion_txtr.py map    <cache> <corpus>   # <cache>/map.tsv: archive -> installed face folder
    audion_txtr.py decode <cache> <corpus>   # <cache>/txtr.tsv, the layout check, the cohorts
    audion_txtr.py table  <cache> <corpus> Sources/NullPlayer/AudionFace/AudionFaceTextOverrides.swift

<cache> is what scripts/audion_panic_originals.sh fetched. Each extracted face is an AppleDouble
`.rsrc` file (`unar -k visible`); its resource fork holds a `Face` resource and, per text line,
a `Txtr` (200 artist, 201 album; some faces have one, 128, for both). These are the faces' own
data files, read as clean-room evidence, as the PNGs are. Documented in
skills/audion-face-guide/reference/harness.md.
"""

import collections
import csv
import hashlib
import json
import os
import struct
import sys
import unicodedata


def resources(path):
    """{type: {id: bytes}} from an AppleDouble file's resource fork (entry 2); {} if malformed."""
    try:
        named = named_resources(open(path, 'rb').read())
    except (struct.error, IndexError):
        return {}
    return {kind: {rid: data for rid, (_, data) in ids.items()} for kind, ids in named.items()}


def named_resources(data):
    """{type: {id: (name, bytes)}} from AppleDouble bytes' resource fork; '' for an unnamed resource."""
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


def key(name):
    return unicodedata.normalize('NFC', name).strip().casefold()


def face_files(cache):
    """(archive code, .rsrc path, face name) for every extracted file holding a `Face` resource."""
    root = os.path.join(cache, 'extract')
    for code in sorted(os.listdir(root)):
        if code.endswith('.part'):
            continue
        for folder, _, files in os.walk(os.path.join(root, code)):
            for file in sorted(files):
                path = os.path.join(folder, file)
                if file.endswith('.rsrc') and 'Face' in resources(path):
                    yield code, path, unicodedata.normalize('NFC', file[:-len('.rsrc')])


# `Face` resource version 0, per the template the faces carry (`TMPL` "Face"): byte offsets of the
# rects that identify a face, against their index.json keys.
FACE_RECTS = {'playButtonRect': 2, 'stopButtonRect': 10, 'artistDisplayRect': 74, 'albumDisplayRect': 82,
              'timeDigit1Rect': 162, 'timeDigit2Rect': 170, 'timeDigit3Rect': 178, 'timeDigit4Rect': 186}


def fit(found, index):
    """(agreeing, disagreeing) facts between an original's resources and an index.json: the `Face`
    rects (the converter keeps top and left and may add 1 to bottom and right; an empty rect on
    either side is skipped), and each `Txtr` 200/201 name and size the converter mapped."""
    agree = disagree = 0
    for role, rid in ROLES.items():
        line = txtr(found.get('Txtr', {}).get(rid, b''))
        if line and index.get(f'{role}DisplayFontName') is not None:
            same = (line['name'], line['size']) == (index[f'{role}DisplayFontName'], index.get(f'{role}FontSize'))
            agree, disagree = agree + same, disagree + (not same)
    face = found['Face'].get(128) or next(iter(found['Face'].values()))
    for name, offset in FACE_RECTS.items():
        t, l, b, r = struct.unpack('>4h', face[offset:offset + 8]) if len(face) >= offset + 8 else (0, 0, 0, 0)
        edges = index.get(name)
        if not isinstance(edges, dict) or b - t <= 1 or r - l <= 1:
            continue
        if edges.get('top') == t and edges.get('left') == l and \
                edges.get('bottom', 0) - b in (0, 1) and edges.get('right', 0) - r in (0, 1):
            agree += 1
        else:
            disagree += 1
    return agree, disagree


def command_map(cache, corpus):
    """Each original to its installed folder: by name (the converter appends " 1" to a second face
    of one name), confirmed by one rect or `Txtr` at least; failing the name, by the rects alone when
    exactly one installed face fits two or more facts. Unconfirmed originals are listed, never guessed."""
    installed = {}
    for folder in sorted(os.listdir(corpus)):
        path = os.path.join(corpus, folder, 'index.json')
        if os.path.isfile(path):
            with open(path, 'rb') as file:
                installed[folder] = json.load(file)
    jpgs = {name[:-4] for name in os.listdir(os.path.join(cache, 'download')) if name.endswith('.jpg')}
    rows, unmatched, claimed = [], [], {}
    for code, path, name in face_files(cache):
        found = resources(path)
        def good(folders, need):
            fits = [(fit(found, installed[f]), f) for f in folders]
            fits = [(agree, f) for (agree, disagree), f in fits if agree >= need and disagree == 0]
            # Prefer a folder no earlier original took, then the closest fit.
            return [f for _, f in sorted(fits, key=lambda x: (x[1] in claimed, -x[0]))]
        named = [f for f in installed if key(f) == key(name) or
                 (key(f).startswith(key(name) + ' ') and key(f)[len(key(name)) + 1:].isdigit())]
        folder, how = next(iter(good(named, 1)), ''), 'name'
        if not folder:
            fits = good(installed, 2)
            folder, how = (fits[0], 'rects') if len(fits) == 1 else ('', f'{len(fits)} rect fits')
        if folder:
            how += ' (again)' if folder in claimed else ''
            claimed.setdefault(folder, []).append(code)
        else:
            unmatched.append(f'{code}: {name!r} ({len(named)} named, {how})')
        rows.append((code, code if code in jpgs else '', folder, how, os.path.relpath(path, cache)))
    with open(os.path.join(cache, 'map.tsv'), 'w') as out:
        out.write('archive\tjpg\tface\tmatched\trsrc\n')
        for row in rows:
            out.write('\t'.join(row) + '\n')
    print(f'audion_txtr map: {len(rows)} face files, {len(rows) - len(unmatched)} matched to '
          f'{len(claimed)} of {len(installed)} installed faces; {len(unmatched)} unmatched')
    for line in unmatched:
        print(f'  unmatched {line}')
    for folder, codes in sorted(claimed.items()):
        if len(codes) > 1:
            print(f'  claimed by {len(codes)} originals {folder!r}: {", ".join(codes)}')
    for folder in sorted(f for f in installed if f not in claimed):
        print(f'  no original {folder!r}')


ROLES = {'artist': 200, 'album': 201}
STYLE_KEYS = ['Bold', 'Italic', 'Underline', 'Outline', 'Shadow', 'Condense', 'Extend']


def txtr(record):
    """A `Txtr` record: size, QuickDraw style bits, TextEdit justification (0 default, 1 centre,
    -1 right, -2 force left), transfer mode, an RGBColor (16-bit words; the converter kept the high
    bytes), then the font name as the record's tail. The bytes between colour and name vary (one or
    two pad bytes, a stale Pascal length), so the name is the run of printable bytes at the end."""
    if len(record) < 14:
        return None
    size, style, justification, mode, red, green, blue = struct.unpack('>hHhHHHH', record[:14])
    start = len(record)
    while start > 15 and record[start - 1] >= 0x20:
        start -= 1
    return {'size': size, 'style': style, 'just': justification, 'mode': mode,
            'rgb': f'{red >> 8:02x}{green >> 8:02x}{blue >> 8:02x}',
            'name': record[start:].decode('mac_roman'),
            'pascal': record[start - 1] == len(record) - start if start > 15 else False}


def decoded(cache):
    """(map row, role, resource id, record) for every matched face and line: 200 or 201 when the
    face has it, else 128. 128 alone is an older face's one record for both lines; beside 200/201
    it is the face template's leftover (Geneva 9 centred black in 49 of 52 faces), never authored."""
    with open(os.path.join(cache, 'map.tsv')) as file:
        rows = list(csv.DictReader(file, delimiter='\t'))
    for row in rows:
        if not row['face']:
            continue
        records = resources(os.path.join(cache, row['rsrc'])).get('Txtr', {})
        for role, rid in ROLES.items():
            rid = rid if rid in records else 128 if 128 in records else None
            yield row, role, rid, txtr(records[rid]) if rid is not None else None


def command_decode(cache, corpus):
    out = open(os.path.join(cache, 'txtr.tsv'), 'w')
    out.write('face\tarchive\trole\tid\tsize\tstyle\tjust\tmode\trgb\tname\tpascal\n')
    checks = collections.Counter()
    cohorts = collections.defaultdict(set)
    indexes = {}
    for row, role, rid, t in decoded(cache):
        face = row['face']
        if t is None:
            out.write(f'{face}\t{row["archive"]}\t{role}\t-\t\t\t\t\t\t\t\n')
            cohorts['no Txtr'].add(face)
            continue
        out.write('\t'.join([face, row['archive'], role, str(rid)] +
                             [str(t[k]) for k in ('size', 'style', 'just', 'mode', 'rgb', 'name', 'pascal')]) + '\n')
        if face not in indexes:
            with open(os.path.join(corpus, face, 'index.json'), 'rb') as file:
                indexes[face] = json.load(file)
        index = indexes[face]
        name, size = index.get(f'{role}DisplayFontName'), index.get(f'{role}FontSize')
        color = index.get(f'{role}DisplayTextFaceColorFromTxtr')
        if rid == 128 or name is None:
            # The converter read 200/201 only, and wrote no name when it found none.
            if t['name'] or t['size']:
                cohorts['dropped by the converter'].add(face)
            continue
        # The layout check: what the converter mapped, the decoder must reproduce.
        checks['name ' + ('agree' if name == t['name'] else f'differ: {name!r} vs {t["name"]!r}')] += 1
        checks['size ' + ('agree' if size == t['size'] else 'differ')] += 1
        hexed = color and f'{color["red"]:02x}{color["green"]:02x}{color["blue"]:02x}'
        checks['colour ' + ('agree' if hexed == t['rgb'] else 'differ')] += 1
        if hexed != t['rgb']:
            cohorts['colour differs'].add(face)
        bits = sum(1 << i for i, key in enumerate(STYLE_KEYS) if index.get(f'{role}{key}') is True)
        checks['style ' + ('agree' if bits == t['style'] & 0x7f else f'differ {bits:#x} vs {t["style"]:#x}')] += 1
        checks[f'Justify={index.get(f"{role}Justify")} just={t["just"]}'] += 1
        checks[f'TextMode={index.get(f"{role}TextMode")} mode={t["mode"]}'] += 1
    out.close()
    for row, role, rid, t in decoded(cache):
        if t and t['just'] not in (0, -2):
            cohorts[{1: 'centred', -1: 'right'}.get(t['just'], f'just {t["just"]}')].add(row['face'])
        if t and t['style'] & 0x7f:
            cohorts['style bits set'].add(row['face'])
    print(f'audion_txtr decode: {cache}/txtr.tsv')
    for check, count in sorted(checks.items()):
        print(f'  {count:5}  {check}')
    for cohort, faces in sorted(cohorts.items()):
        print(f'  cohort {cohort}: {len(faces)} faces')


# A `Txtr` with an empty name draws in the system font: the faces' screenshots show a heavy
# sans (Mint, Gears, Touchscreen), Mac OS 8.5–9's Charcoal, which AudionFaceFontSubstitutes covers.
SYSTEM_FONT = 'Charcoal'
SWIFT_ROLES = {'artist': '.artist', 'album': '.album'}
ALIGNMENTS = {-1: '.right'}


def command_table(cache, corpus, out_path):
    """Write AudionFaceTextOverrides.swift: what index.json lost, per line, keyed by the SHA-256
    of the face's index.json — a line's font, size and colour where the converter dropped an
    authored `Txtr` 200/201, and right justification (index.json's `…Justify` is centre or right)."""
    entries, digests = {}, {}
    for row, role, rid, t in decoded(cache):
        if t is None or rid == 128:
            continue
        face = row['face']
        path = os.path.join(corpus, face, 'index.json')
        with open(path, 'rb') as file:
            raw = file.read()
        index = json.loads(raw)
        other = 'album' if role == 'artist' else 'artist'
        line = {}
        # An unnamed artist line beside a named album line takes the album's font (Techno Jammo):
        # AudionFaceDocument's existing departure, so it is not overridden here.
        if index.get(f'{role}DisplayFontName') is None and (t['name'] or t['size']) and \
                index.get(f'{other}DisplayFontName') is None:
            line['fontName'] = json.dumps(t['name'] or SYSTEM_FONT)
            line['fontSize'] = str(t['size'])
            red, green, blue = (int(t['rgb'][i:i + 2], 16) for i in (0, 2, 4))
            line['color'] = f'AudionFace.color(red: {red}, green: {green}, blue: {blue})'
        if t['just'] in ALIGNMENTS:
            line['alignment'] = ALIGNMENTS[t['just']]
        if not line:
            continue
        digest = hashlib.sha256(raw).hexdigest()
        if entries.setdefault(digest, {}).setdefault(role, line) != line:
            entries[digest][role] = None
        digests.setdefault(digest, set()).add(face)
    clashes = sorted(d for d, roles in entries.items() if None in roles.values())
    for digest in clashes:
        print(f'  omitted: faces {sorted(digests[digest])} share an index.json but not its overrides')
        del entries[digest]
    body = []
    for digest, roles in sorted(entries.items(), key=lambda e: sorted(digests[e[0]])[0].casefold()):
        body.append(f'        // {", ".join(sorted(digests[digest]))}')
        lines = ', '.join(f'{SWIFT_ROLES[role]}: Line(' + ', '.join(f'{k}: {v}' for k, v in line.items()) + ')'
                          for role, line in sorted(roles.items()))
        body.append(f'        "{digest}": [{lines}],')
    with open(out_path, 'w') as out:
        out.write('''// Generated by `scripts/audion_txtr.py table` from the `Txtr` resources of Panic's original faces
// (download.panic.com/audion/faces). Do not edit; regenerate. Text metadata only, no artwork.

import CoreGraphics

/// What a face's index.json lost of its authored text settings, applied by `AudionFaceDocument`.
/// A face whose index.json is not one of these (edited, or not Panic's) draws from index.json.
enum AudionFaceTextOverrides {
    struct Line {
        var fontName: String?
        var fontSize: Int?
        var color: CGColor?
        var alignment: AudionFace.TextAlignment?
    }

    /// Keyed by the SHA-256 of the face's index.json.
    static let lines: [String: [AudionFace.TextRole: Line]] = [
BODY
    ]
}
'''.replace('BODY', '\n'.join(body)))
    print(f'audion_txtr table: {len(entries)} faces -> {out_path}')


if __name__ == '__main__':
    commands = {'map': (command_map, 4), 'decode': (command_decode, 4), 'table': (command_table, 5)}
    if sys.argv[1:2] == [] or sys.argv[1] not in commands or len(sys.argv) != commands[sys.argv[1]][1]:
        sys.exit(__doc__.strip().split('\n\n')[1])
    commands[sys.argv[1]][0](*sys.argv[2:])
