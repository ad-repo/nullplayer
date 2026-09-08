# scripts/wmp_implicit_key.py — the W78 class: drawn artwork that carries no alpha channel of its
# own, holds `#FF00FF` pixels, and hangs off a node declaring no colour key at all.
#
#   python3 scripts/wmp_implicit_key.py [--corpus <dir>] [--color RRGGBB] [--tsv <file>]
#
# WMP appears to treat magenta as the implicit transparency colour for such a bitmap; a skin author
# who keys three siblings by hand and leaves the fourth to the default is relying on it. This
# measures how large that class is before anything defaults, because the fix is engine-wide: a
# sprite that legitimately paints magenta loses those pixels.
#
# It reads `.wms` and artwork straight out of the archives, like wmp_markup_census.sh and
# wmp_input_kinds.py — authored demand, not a render result. A row here says a sprite *would*
# change; only a dumped PNG says the view improved.
#
# Two traps, the same ones every corpus script here enforces:
#   * a `.wms` is usually UTF-16 and a tag routinely spans lines, so tags are matched over the
#     decoded whole file, never per line;
#   * "no alpha channel" is not "no transparent pixel": a P-mode GIF/PNG carries its transparency in
#     `info['transparency']`, and an RGBA sprite that happens to be fully opaque still authored one.
#     Both count as *having* alpha and are excluded — only a sprite with no alpha channel at all is
#     a candidate for an implicit key.
#
# See skills/wmp-skin-guide/reference/harness.md; this script documents no probe flags.
import argparse, collections, io, os, posixpath, re, sys, zipfile
from PIL import Image

# Artwork the renderer actually blits. `mappingImage`, `clippingImage` and `positionImage` are masks
# read for their colours rather than drawn, so an implicit key would corrupt them, not fix them.
ARTWORK = ['backgroundimage', 'background', 'image', 'hoverimage', 'downimage', 'disabledimage',
           'foregroundimage', 'thumbimage', 'thumbhoverimage', 'thumbdownimage',
           'thumbdisabledimage']
KEYS = ['transparencycolor', 'clippingcolor']
TAG = re.compile(r'<\s*([A-Za-z]\w*)((?:[^>"\']|"[^"]*"|\'[^\']*\')*)>', re.S)
ATTR = re.compile(r'([A-Za-z_][\w:.-]*)\s*=\s*"([^"]*)"|([A-Za-z_][\w:.-]*)\s*=\s*\'([^\']*)\'')


def decode(raw):
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        return raw.decode('utf-16', 'ignore')
    return raw.decode('latin-1')


def attributes(text):
    found = {}
    for match in ATTR.finditer(text):
        name = (match.group(1) or match.group(3)).lower()
        found.setdefault(name, (match.group(2) if match.group(1) else match.group(4)))
    return found


def resolve(names_lower, definition, authored):
    """Archive-relative, case-insensitively, the way WMPArchive does."""
    authored = authored.strip().replace('\\', '/')
    if not authored or '://' in authored:
        return None
    for candidate in (posixpath.normpath(posixpath.join(posixpath.dirname(definition), authored)),
                      posixpath.normpath(authored)):
        entry = names_lower.get(candidate.lower().lstrip('./'))
        if entry:
            return entry
    return None


def sprite_facts(data, key):
    """(has_alpha, key_pixels) for one sprite, or None when it will not decode."""
    try:
        image = Image.open(io.BytesIO(data))
        image.load()
    except Exception:
        return None
    has_alpha = 'A' in image.getbands() or 'transparency' in image.info
    if has_alpha:
        return (True, 0)
    rgb = image.convert('RGB')
    count = sum(n for n, colour in rgb.getcolors(maxcolors=1 << 24) or [] if colour == key)
    return (False, count)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--corpus', default=os.path.expanduser(
        '~/Library/Application Support/NullPlayer/WMPSkins'))
    parser.add_argument('--color', default='FF00FF')
    parser.add_argument('--tsv')
    args = parser.parse_args()
    key = tuple(int(args.color[i:i + 2], 16) for i in (0, 2, 4))

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    excluded = set()
    try:
        with open(os.path.join(root, 'scripts', 'wmp_corpus_exclusions.txt')) as handle:
            excluded = {line.strip() for line in handle
                        if line.strip() and not line.startswith('#')}
    except OSError:
        pass

    rows, skins, sprites = [], set(), set()
    drawn_nodes = keyed_nodes = 0
    measured = dropped = 0
    for name in sorted(os.listdir(args.corpus)):
        if not name.lower().endswith(('.wmz', '.zip')):
            continue
        if name in excluded:
            dropped += 1
            continue
        try:
            archive = zipfile.ZipFile(os.path.join(args.corpus, name))
        except Exception:
            continue
        measured += 1
        names_lower = {e.lower(): e for e in archive.namelist()}
        cache = {}
        for definition in (e for e in archive.namelist() if e.lower().endswith('.wms')):
            try:
                text = decode(archive.read(definition))
            except Exception:
                continue
            view = '(no view)'
            for match in TAG.finditer(text):
                tag = match.group(1).lower()
                attrs = attributes(match.group(2))
                if tag == 'view':
                    view = attrs.get('id') or attrs.get('title') or '(unnamed view)'
                declares_key = any(attrs.get(k, '').strip() for k in KEYS)
                for attribute in ARTWORK:
                    authored = attrs.get(attribute)
                    if not authored:
                        continue
                    entry = resolve(names_lower, definition, authored)
                    if entry is None:
                        continue
                    drawn_nodes += 1
                    if declares_key:
                        keyed_nodes += 1
                        continue
                    if entry not in cache:
                        try:
                            cache[entry] = sprite_facts(archive.read(entry), key)
                        except Exception:
                            cache[entry] = None
                    facts = cache[entry]
                    if facts is None or facts[0] or facts[1] == 0:
                        continue
                    rows.append((name, view, tag, attribute, entry, facts[1]))
                    skins.add(name)
                    sprites.add((name, entry))

    print(f'{len(rows)} node/attribute references across {len(skins)} skins '
          f'and {len(sprites)} distinct sprites '
          f'({measured} archives measured, {dropped} excluded)')
    print(f'  of {drawn_nodes} drawn artwork references, {keyed_nodes} declare a key themselves')
    by_skin = collections.Counter(row[0] for row in rows)
    for skin, count in by_skin.most_common(15):
        views = sorted({row[1] for row in rows if row[0] == skin})
        print(f'  {skin:44} {count:4} refs / {len(views)} views: {", ".join(views[:4])}')
    if args.tsv:
        with open(args.tsv, 'w') as handle:
            handle.write('skin\tview\ttag\tattribute\tsprite\tkey_pixels\n')
            for row in sorted(rows, key=lambda r: (-r[5], r[0])):
                handle.write('\t'.join(str(field) for field in row) + '\n')
        print(f'  wrote {args.tsv}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
