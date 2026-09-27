#!/usr/bin/env python3
"""Shared corpus reading for the `.wmz` scan scripts: decode the way `WMPTextDecoder` does, open an
archive the way `WMPArchiveHeaderRepair` does, and honour `wmp_corpus_exclusions.txt`.

An ad-hoc corpus scan written without these three is wrong in a way that exits 0:

  * **`grep` treats about half the `.wms` files as binary** (cp1252, with a 0xA9 copyright sign in
    the header comment) and prints nothing — W256's row claimed 19 archives lacked
    `<equalizerSettings>` when 99 of 184 did. UTF-16 files are wider still.
  * **Two archives (`Need_for_Speed_Underground`, `SplinterCellWMPSkin`) have `01 00 01 00` local
    headers**, and `zipfile` drops them on a `BadZipFile` unless the headers are repaired.
  * **An excluded archive must not rank work.**

Calibration: a correct pass over 184 archives decodes 158 UTF-16-BOM / 146 cp1252 / 89 UTF-8 /
9 UTF-8-BOM entries (`.wms` + `.js`). A scan that does not reproduce its corpus's breakdown is not
reading what the engine reads.
"""
import io, os, struct, zipfile

CORPUS = os.path.expanduser("~/Library/Application Support/NullPlayer/WMPSkins")
EXCL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wmp_corpus_exclusions.txt")


def decode(data):
    """(text, label) the way WMPTextDecoder reads it, or (None, None)."""
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


def excluded():
    names = set()
    if os.path.exists(EXCL):
        for line in open(EXCL):
            line = line.split('#')[0].strip()
            if line: names.add(line)
    return names


def archives(corpus=CORPUS):
    """Archive file names in `corpus`, sorted, exclusions removed."""
    skip = excluded()
    for name in sorted(os.listdir(corpus)):
        if name.lower().endswith('.wmz') and name not in skip:
            yield name


def open_archive(path):
    data = repaired(path)
    return zipfile.ZipFile(io.BytesIO(data) if data else path)
