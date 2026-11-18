#!/usr/bin/env python3
"""Find Winamp Modern (`.wal`) skins that are not in the corpus (any tier) and download them.

    python3 -I scripts/wal_corpus_crawl.py <outdir> [--corpus <dir>] [--source heritage|archive|wincustomize]
    python3 -I scripts/wal_corpus_crawl.py selftest

Sources: winampheritage.com (every category, every skin page), archive.org's `winampskinsmodern`
collection, and wincustomize.com's WinAmp v3/v5 entries (and any `.wal` in other categories). A `.wal` download is kept as-is; a `.zip` is opened (recursively)
and every skin root inside it, a directory holding `skin.xml`, is repacked as its own `.wal` with
`skin.xml` at the archive root. Classic skins (no `skin.xml`) are ignored.

**Dedupe is by content, never by name.** Filenames differ for one skin (`K-jr.wal` vs
`k_jr_winamp_skin_by_marisa85_d329ymw.wal`) and `<skininfo><name>` is shared by different skins
(three `T-800`s, two `Winamp5 Base Skin`s, five `DewyTears` colour variants, blanks). A candidate
is a duplicate when >=90% of its (path-under-root, crc32) entries match an existing skin's. A
name match with different content is kept and flagged in `manifest.tsv` for a human to judge.

Downloads are cached in `<outdir>/.cache`, so a re-run only fetches what is new. RAR/7z payloads
are logged and skipped (no stdlib reader).
"""
import concurrent.futures, glob, hashlib, html, io, json, os, pathlib, re, subprocess, sys, threading, time, urllib.parse, zipfile, zlib

# Every tier, bronze and quarantine included: a skin already rated is not a candidate (B167).
CORPUS = os.path.expanduser("~/Library/Application Support/NullPlayer/WinampModernCorpus")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
HERITAGE = "https://winampheritage.com"
MAX_MEMBER = 200 << 20  # a skin member past this is a bomb or not a skin
SAME = 0.9


WAYBACK = threading.Lock()


class CurlError(OSError):
    def __init__(self, code):
        super().__init__(f"curl exit {code}")
        self.code = code


def curl(url, cookie=None):
    # curl, not urllib: wincustomize 403s Python's TLS handshake whatever the headers say
    cmd = ["curl", "-sfL", "--max-time", "120", "-A", UA] + (["-b", cookie] if cookie else []) + [url]
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode: raise CurlError(r.returncode)
    return r.stdout


def get(url, cookie=None):
    if not url.startswith("https://web.archive.org/"): return curl(url, cookie)
    # Wayback refuses connections (curl 7) from an IP sending parallel requests, and resets (56) or
    # 504s under load: one request at a time, at least 1 s apart (the first wait is that spacing,
    # not a retry), retried after longer pauses.
    with WAYBACK:
        for wait in (1, 15, 60):
            time.sleep(wait)
            try: return curl(url, cookie)
            except CurlError as e:
                if e.code == 22: raise  # an HTTP error status: retrying will not help
                err = e
        raise err


def pmap(fn, items, workers=8):
    with concurrent.futures.ThreadPoolExecutor(workers) as ex:
        return list(ex.map(fn, items))


# ---- sources: each yields (source_url, filename, cookie) ----

def heritage():
    cats = sorted(set(re.findall(r'href="/skins/([A-Za-z-]+-\d+)"', get(HERITAGE + "/skins").decode("utf-8", "replace"))))
    pages = set()
    for c in cats:
        n = 0
        while True:
            url = f"{HERITAGE}/skins/{c}" + (f"/page-{n}" if n else "")
            found = set(re.findall(r'href="(/skin/[^/"]+/\d+)"', get(url).decode("utf-8", "replace")))
            if not found - pages and n: break
            pages |= found
            n += 1
    print(f"heritage: {len(cats)} categories, {len(pages)} skin pages", file=sys.stderr)

    def one(page):
        try: m = re.search(r"showdd\('(?:[^'\\]|\\.)*','([^']+)','((?:[^'\\]|\\.)+)'\)", get(HERITAGE + page).decode("utf-8", "replace"))
        except Exception as e:
            print(f"  skip {page}: {e}", file=sys.stderr); return None
        if not m or not m.group(1).lower().endswith((".wal", ".zip")): return None
        # the download 404s without the cookie the skin page sets
        return HERITAGE + urllib.parse.quote(html.unescape(m.group(1))), html.unescape(m.group(2)).replace("\\'", "'"), "downloadsite=winampheritage"
    return [x for x in pmap(one, sorted(pages)) if x]


def archive():
    q = urllib.parse.urlencode({"q": "collection:winampskinsmodern", "fl[]": "identifier", "rows": 10000, "output": "json"})
    ids = [d["identifier"] for d in json.loads(get("https://archive.org/advancedsearch.php?" + q))["response"]["docs"]]
    print(f"archive.org: {len(ids)} items", file=sys.stderr)

    def one(ident):
        try: files = json.loads(get(f"https://archive.org/metadata/{ident}")).get("files", [])
        except Exception as e:
            print(f"  skip {ident}: {e}", file=sys.stderr); return []
        return [(f"https://archive.org/download/{ident}/{urllib.parse.quote(f['name'])}", os.path.basename(f["name"]), None)
                for f in files if f["name"].lower().endswith((".wal", ".zip"))]
    return [x for xs in pmap(one, ids) for x in xs]


def wincustomize():
    base = "https://www.wincustomize.com/explore/winamp"
    ids, n = set(), 1
    while True:
        found = set(re.findall(r'/explore/winamp/(\d+)/', get(f"{base}/page/{n}").decode("utf-8", "replace")))
        if not found - ids: break
        ids |= found
        n += 1
    print(f"wincustomize: {n - 1} pages, {len(ids)} skins", file=sys.stderr)

    def one(i):
        try: m = re.search(r'name="keywords" content="([^"]*)', get(f"{base}/{i}/").decode("utf-8", "replace"))
        except Exception as e:
            print(f"  skip wincustomize {i}: {e}", file=sys.stderr); return None
        # keywords: WinAmp,winamp,Skin,<category>,<title>,<filename>,<author>,...
        kw = html.unescape(m.group(1)).split(",") if m else []
        if len(kw) < 6 or not (kw[5].lower().endswith(".wal") or kw[3] in ("WinAmp v3", "WinAmp v5")): return None
        return f"{base}/{i}/download", kw[5], None
    return [x for x in pmap(one, sorted(ids)) if x]


# ---- archive handling ----

def read(z, i):
    """A member whose central entry says `fonts\\a.ttf` and local header `fonts/a.ttf` (Wiimote,
    PokemonDS) is a BadZipFile to zipfile; Winamp reads it, so retry with the slashes flipped."""
    try: return z.read(i)
    except zipfile.BadZipFile:
        i.orig_filename = i.orig_filename.replace("\\", "/")
        return z.read(i)


def wal_def(base): return base == "skin.xml"


def skins_in(data, depth=0, is_def=wal_def, nested=(".zip", ".wal")):
    """Every skin root in a zip as (root_prefix, {relpath: bytes}), recursing into nested archives.
    A root is the directory of a member whose lower-cased basename `is_def` accepts; members ending
    in one of `nested` are opened in turn."""
    try: z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile: return []
    infos = [i for i in z.infolist() if not i.is_dir() and i.file_size <= MAX_MEMBER
             and not i.filename.startswith("/") and ".." not in i.filename.split("/")]
    names = [i.filename.replace("\\", "/") for i in infos]
    roots = sorted({n[:n.rfind("/") + 1] for n in names if is_def(n.lower().rsplit("/", 1)[-1])}, key=len)
    roots = [r for k, r in enumerate(roots) if not any(r.startswith(o) for o in roots[:k])]  # outermost only
    out = []
    for r in roots:
        try: out.append((r, {n[len(r):]: read(z, i) for i, n in zip(infos, names) if n.startswith(r)}))
        except Exception: pass  # unsupported compression, truncated member
    if depth < 3:
        for i, n in zip(infos, names):
            if n.lower().endswith(nested) and not any(n.startswith(r) for r in roots):
                try: out += skins_in(read(z, i), depth + 1, is_def, nested)
                except Exception: pass
    return out


def pack(files):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for n in sorted(files): z.writestr(n, files[n])
    return buf.getvalue()


def fingerprint(files):
    return frozenset((n.lower(), zlib.crc32(b)) for n, b in files.items()
                     if not n.lower().endswith((".txt", ".nfo", ".url", ".htm", ".html")))


def skin_name(files):
    x = next((b for n, b in files.items() if n.lower() == "skin.xml"), b"").decode("latin-1")
    m = re.search(r"<skininfo\b.*?<name>(.*?)</name>", x, re.S | re.I)
    return m.group(1).strip() if m else ""


def norm(s): return re.sub(r"[^a-z0-9]", "", s.lower())


def is_dup(fp, known):
    return next((label for kfp, label in known if fp and len(fp & kfp) >= SAME * max(len(fp), len(kfp))), None)


def crawl(out, corpus, found, ext=".wal", is_def=wal_def, name_of=skin_name, load=lambda p: pathlib.Path(p).read_bytes()):
    """Download `found` [(url, filename, cookie)] into `out`, keeping each `ext` skin not already in
    `corpus` (top level or one tier down) or `out`. `load` reads an archive's bytes, known or downloaded."""
    cache = os.path.join(out, ".cache")
    os.makedirs(cache, exist_ok=True)
    known, names = [], {}
    # case-insensitive "*.<ext>": ".wal" -> "*.[wW][aA][lL]", so "SKIN.WAL" is found too
    root, pat = glob.escape(corpus), "*." + "".join(f"[{c}{c.upper()}]" for c in ext[1:])
    for p in glob.glob(os.path.join(root, pat)) + glob.glob(os.path.join(root, "*", pat)) + glob.glob(os.path.join(glob.escape(out), pat)):
        for _, files in skins_in(load(p), is_def=is_def, nested=(".zip", ext)):
            known.append((fingerprint(files), os.path.basename(p)))
            names.setdefault(norm(name_of(files)), []).append(os.path.basename(p))
    print(f"known: {len(known)} skins in corpus + {out}", file=sys.stderr)
    print(f"candidates: {len(found)} downloads", file=sys.stderr)

    def fetch(item):
        url, fname, cookie = item
        path = os.path.join(cache, hashlib.sha1(url.encode()).hexdigest() + "-" + re.sub(r"[^\w.-]", "_", fname)[-80:])
        if not os.path.exists(path):
            try: data = get(url, cookie)
            except Exception as e:
                print(f"  fail {url}: {e}", file=sys.stderr); return item, None
            with open(path, "wb") as f: f.write(data)
        return item, path

    manifest = open(os.path.join(out, "manifest.tsv"), "a")
    added = dups = 0
    for (url, fname, _), path in pmap(fetch, found):
        if not path: continue
        data = load(path)
        if data[:2] != b"PK":
            print(f"  not a zip ({data[:4]!r}): {url}", file=sys.stderr); continue
        skins = skins_in(data, is_def=is_def, nested=(".zip", ext))
        for root, files in skins:
            fp = fingerprint(files)
            if is_dup(fp, known): dups += 1; continue
            name = name_of(files)
            stem = os.path.splitext(fname)[0] if len(skins) == 1 else (root.rstrip("/").rsplit("/", 1)[-1] or os.path.splitext(fname)[0])
            stem = re.sub(r'[/:\\]', "_", stem)
            dest = os.path.join(out, stem + ext)
            k = 2
            while os.path.exists(dest): dest = os.path.join(out, f"{stem}-{k}{ext}"); k += 1
            # a downloaded skin archive that already is one skin is kept byte-for-byte; everything else is repacked
            keep = fname.lower().endswith(ext) and len(skins) == 1
            with open(dest, "wb") as f: f.write(data if keep else pack(files))
            clash = names.get(norm(name), []) if norm(name) else []
            manifest.write("\t".join([os.path.basename(dest), name, url, "name-matches:" + ",".join(clash) if clash else ""]) + "\n")
            known.append((fp, os.path.basename(dest)))
            names.setdefault(norm(name), []).append(os.path.basename(dest))
            added += 1
    print(f"added {added}, skipped {dups} duplicates -> {out} (see manifest.tsv)", file=sys.stderr)


def selftest():
    z = io.BytesIO()
    with zipfile.ZipFile(z, "w") as w:
        w.writestr("Foo Skin/skin.xml", "<skininfo><name>Foo</name></skininfo>")
        w.writestr("Foo Skin/xml/player.xml", "<x/>")
        w.writestr("Foo Skin/readme.txt", "hi")
        w.writestr("classic/main.bmp", "bmp")
        w.writestr("../evil/skin.xml", "x")
    inner = io.BytesIO()
    with zipfile.ZipFile(inner, "w") as w: w.writestr("skin.xml", "<skininfo><name>Bar</name></skininfo>")
    with zipfile.ZipFile(z, "a") as w: w.writestr("bar.wal", inner.getvalue())
    skins = skins_in(z.getvalue())
    assert [(r, skin_name(f)) for r, f in skins] == [("Foo Skin/", "Foo"), ("", "Bar")], skins
    repacked = skins_in(pack(skins[0][1]))
    assert repacked[0][0] == "" and set(repacked[0][1]) == {"skin.xml", "xml/player.xml", "readme.txt"}
    fp = fingerprint(skins[0][1])
    assert is_dup(fingerprint(repacked[0][1]), [(fp, "a")]) == "a"           # same content, different packaging
    assert is_dup(fingerprint(skins[1][1]), [(fp, "a")]) is None              # different skin
    print("selftest ok")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["selftest"]: selftest(); sys.exit()
    if not a or a[0].startswith("-"): sys.exit(__doc__)
    corpus = a[a.index("--corpus") + 1] if "--corpus" in a else CORPUS
    sources = [a[a.index("--source") + 1]] if "--source" in a else ["heritage", "archive", "wincustomize"]
    crawl(os.path.abspath(a[0]), corpus, [x for s in sources for x in {"heritage": heritage, "archive": archive, "wincustomize": wincustomize}[s]()])
