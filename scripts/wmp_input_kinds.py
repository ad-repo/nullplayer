# scripts/wmp_input_kinds.py — nodes that author a mouse handler on a kind the scene builder
# does not treat as a control. Reads .wms straight out of the archives, like wmp_markup_census.sh.
import zipfile, glob, os, re, collections
CONTROLS = {'button','buttongroup','slider','volumeslider','seekslider','balanceslider',
    'customslider','playelement','pausebutton','stopelement','prevelement','nextelement',
    'rewbutton','rewelement','ffwdbutton','ffwdelement','returnbutton','shufflebutton','playlist',
    'dropdownplaylist','popup','editbox','listbox','buttonelement'}
HANDLER = re.compile(r'\bon(click|mouseover|mouseout|mousedown|mouseup|dblclick)\s*=', re.I)
TAG = re.compile(r'<\s*([A-Za-z]\w*)([^>]*)>', re.S)
kinds, skins = collections.Counter(), collections.defaultdict(set)
for archive in sorted(glob.glob(os.path.expanduser(
        '~/Library/Application Support/NullPlayer/WMPSkins/*.wmz'))):
    try: zf = zipfile.ZipFile(archive)
    except Exception: continue
    for entry in (e for e in zf.namelist() if e.lower().endswith('.wms')):
        try: raw = zf.read(entry)
        except Exception: continue
        text = (raw.decode('utf-16', 'ignore') if raw[:2] in (b'\xff\xfe', b'\xfe\xff')
                else raw.decode('latin-1'))
        for match in TAG.finditer(text):
            tag = match.group(1).lower()
            if tag not in CONTROLS and HANDLER.search(match.group(2)):
                kinds[tag] += 1
                skins[tag].add(os.path.basename(archive))
print(sum(kinds.values()), 'nodes across', len(set().union(*skins.values())), 'skins')
for tag, n in kinds.most_common(8):
    print(f'  {tag:14} {n:5} uses / {len(skins[tag])} skins')
