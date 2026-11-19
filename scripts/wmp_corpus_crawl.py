#!/usr/bin/env python3
"""Find Windows Media Player (`.wmz`) skins that are not in the corpus and download them.

    python3 -I scripts/wmp_corpus_crawl.py <outdir> [--corpus <dir>] [--source wayback|archive]
    python3 -I scripts/wmp_corpus_crawl.py selftest

The `.wal` crawler (`wal_corpus_crawl.py`) does the downloading, unpacking and dedupe; this file
only supplies the sources and what a WMP skin looks like. A skin root is a directory holding a
`.wms`; a `.wmz` download that is one skin is kept as-is, anything else is repacked per root.

Sources:
  wayback  Wayback Machine captures of the hosts that served `.wmz` files, chiefly Microsoft's own
           skin gallery (autoupdate.windowsmedia.com/mediaguide/gallery/wmzfiles/). wmplugins.com's
           `Download.aspx?Url=<real url>` links are unwrapped and the real URL is fetched from Wayback.
  archive  archive.org items whose title or subject names WMP skins or `wmz`.

Duplicates are skipped by content (>=90% shared path+crc32 entries), against every corpus archive
and everything already in <outdir>, exactly as the `.wal` crawler does; a name-only match is kept and
flagged in `manifest.tsv`. Downloads are cached in `<outdir>/.cache`.
"""
import html, json, os, pathlib, re, struct, sys, urllib.parse

sys.dont_write_bytecode = True  # no scripts/__pycache__
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I drops the script dir
from wal_corpus_crawl import crawl, get, pmap, skins_in, pack, fingerprint, is_dup
from wmp_corpus import CORPUS, decode, repaired

# Each is a CDX `matchType=domain` query (the name and its subdomains) filtered to `.wmz`. A
# filtered query over a big site (microsoft.com, wincustomize.com, customize.org, skinz.org,
# neowin.net) times out or answers "Temporarily Offline", so those are narrowed to the one host that
# served the files. Probed 2026-11-18; a name here had at least one archived .wmz.
WAYBACK_HOSTS = ["autoupdate.windowsmedia.com", "www.wmplugins.com", "theskinsfactory.com",
                 "skins.wincustomize.com", "skins2.wincustomize.com", "skins3.wincustomize.com",
                 "broadcastpc.tv", "media.warnerbros.com", "romanda.org", "neodecoder.com",
                 "neodecoder.net", "izdatabank.com", "sfcave.com", "download.softpedia.com"]
ARCHIVE_Q = ('title:wmz OR subject:wmz OR title:("windows media player" skin) OR '
             'subject:("windows media player" skin) OR title:("wmp skin") OR subject:("wmp skin") OR title:(wmp AND skin)')
MAX_DOWNLOAD = 200 << 20


def wms_def(base): return base.endswith(".wms")


def theme_name(files):
    data = next((b for n, b in sorted(files.items()) if n.lower().endswith(".wms")), b"")
    text = decode(data)[0] or ""
    t = re.search(r"<theme\b[^>]*>", text, re.I)
    tag = t.group(0) if t else ""
    # title before id: Stardock SkinStudio writes id="Summary" into every skin it generates
    m = re.search(r"\btitle\s*=\s*\"([^\"]*)\"", tag, re.I) or re.search(r"\bid\s*=\s*\"([^\"]*)\"", tag, re.I)
    return m.group(1).strip() if m else ""


def load(path):
    """An archive's bytes with WMPArchiveHeaderRepair applied: two corpus skins and several
    downloads have `01 00 01 00` local headers."""
    try: fixed = repaired(path)
    except struct.error: fixed = None  # a truncated directory: left for the ZIP reader to reject
    return fixed or pathlib.Path(path).read_bytes()


def captures(url, match="exact", wmz_only=False):
    """[(timestamp, original)] of Wayback's 200 captures of `url`, one per distinct URL."""
    q = [("url", url), ("matchType", match), ("filter", "statuscode:200"), ("collapse", "urlkey"), ("fl", "timestamp,original")]
    q += [("filter", r"original:(?i).*\.wmz.*")] if wmz_only else []
    rows = get("https://web.archive.org/cdx/search/cdx?" + urllib.parse.urlencode(q)).decode("utf-8", "replace").splitlines()
    return [r.split(" ", 1) for r in rows if re.match(r"\d{14} http", r)]


def wayback():
    out = {}
    for host in WAYBACK_HOSTS:
        try: rows = captures(host, "domain", wmz_only=True)
        except Exception as e:
            print(f"  skip wayback {host}: {e}", file=sys.stderr); continue
        for ts, orig in rows:
            # Redirect pages wrap the skin's real URL: wmplugins.com's Download.aspx?Url=<url>, and
            # theskinsfactory.com's data.php?outclick=<a Wayback URL of it>
            qs = urllib.parse.parse_qs(urllib.parse.urlsplit(orig).query)
            inner = html.unescape((qs.get("Url") or qs.get("outclick") or [""])[0])
            if inner:
                inner = re.sub(r"^https?://web\.archive\.org/web/\d+[a-z_]*/", "", inner)
                # Only a real capture: Wayback answers a guessed timestamp for a URL it holds only
                # as 404s with a redirect curl reports as a reset (56), retried for over a minute.
                try: hit = captures(urllib.parse.quote(inner, safe=":/?&=%~+#"))[:1]
                except Exception as e:
                    print(f"  skip {inner}: {e}", file=sys.stderr); continue
                if not hit: continue
                (ts, orig), = hit
            url = f"https://web.archive.org/web/{ts}id_/{urllib.parse.quote(orig, safe=':/?&=%~+#')}"
            fname = os.path.basename(urllib.parse.unquote(urllib.parse.urlsplit(orig).path)) or "skin.wmz"
            out.setdefault(url, (url, fname, None))
        print(f"wayback: {host}: {len(rows)} captures", file=sys.stderr)
    return list(out.values())


def archive():
    q = urllib.parse.urlencode({"q": ARCHIVE_Q, "fl[]": "identifier", "rows": 10000, "output": "json"})
    ids = [d["identifier"] for d in json.loads(get("https://archive.org/advancedsearch.php?" + q))["response"]["docs"]]
    print(f"archive.org: {len(ids)} items", file=sys.stderr)

    def one(ident):
        try: files = json.loads(get(f"https://archive.org/metadata/{ident}")).get("files", [])
        except Exception as e:
            print(f"  skip {ident}: {e}", file=sys.stderr); return []
        return [(f"https://archive.org/download/{ident}/{urllib.parse.quote(f['name'])}", os.path.basename(f["name"]), None)
                for f in files if f["name"].lower().endswith((".wmz", ".zip")) and int(f.get("size") or 0) <= MAX_DOWNLOAD]
    return [x for xs in pmap(one, ids) for x in xs]


def selftest():
    import io, zipfile
    z = io.BytesIO()
    with zipfile.ZipFile(z, "w") as w:
        w.writestr("Foo/foo.wms", '﻿<THEME id="Summary" title="Foo Skin" author="x">'.encode("utf-16-le"))
        w.writestr("Foo/back.bmp", "bmp")
        w.writestr("readme.txt", "hi")
    skins = skins_in(z.getvalue(), is_def=wms_def)
    assert [r for r, _ in skins] == ["Foo/"] and theme_name(skins[0][1]) == "Foo Skin", skins
    again = skins_in(pack(skins[0][1]), is_def=wms_def)
    assert again[0][0] == "" and is_dup(fingerprint(again[0][1]), [(fingerprint(skins[0][1]), "a")]) == "a"
    # a truncated end-of-central-directory record is rejected, not raised
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as f: f.write(b"PK\x05\x06")
    assert load(f.name) == b"PK\x05\x06" and skins_in(load(f.name), is_def=wms_def) == []
    os.unlink(f.name)
    print("selftest ok")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["selftest"]: selftest(); sys.exit()
    if not a or a[0].startswith("-"): sys.exit(__doc__)
    corpus = a[a.index("--corpus") + 1] if "--corpus" in a else CORPUS
    sources = [a[a.index("--source") + 1]] if "--source" in a else ["wayback", "archive"]
    found = [x for s in sources for x in {"wayback": wayback, "archive": archive}[s]()]
    crawl(os.path.abspath(a[0]), corpus, found, ext=".wmz", is_def=wms_def, name_of=theme_name, load=load)
