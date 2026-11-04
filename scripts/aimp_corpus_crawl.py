#!/usr/bin/env python3
"""Find AIMP skins (`.acs3`, `.acs4`, `.acs5`) that are not in the corpus and download them.

    python3 -I scripts/aimp_corpus_crawl.py <outdir> [--corpus <dir>] [--csv <aimp_skins.csv>] [--limit N]
    python3 -I scripts/aimp_corpus_crawl.py selftest

Source: the official catalog at aimp.ru, "Skins « AIMP for PC". Its 150-odd listing pages give the
record ids; a record's own page must say it is a PC skin (a listing also carries featured records from
other categories, Android skins among them), and its download is `?do=catalog.download&id=<record>`.
`--csv` adds the ids of badcast/aimpskins' `aimp_skins.csv`, an older snapshot of the same catalog,
so a record dropped from the listing is still tried.

A download is a skin file as-is or an archive. A `.zip` is opened (recursively); RAR/7z payloads are
logged and skipped (no stdlib reader). **A skin is recognised by its first bytes, never its name:**
`ACS3`/`ACS4`/`ACS5`, and `ACS3` followed by `02` is AIMP 3.0. Another `ACS?` (AIMP 2's) is kept under
`other/` and counted, since it says how much of the catalog needs a reader NullPlayer lacks.

**Dedupe is by content:** a skin whose sha256 matches one already in the corpus or the output is
skipped, whatever its name (the same skin is uploaded under several records and versions). Skins
are written as `<record>-<sanitised name>.<ext>`; `manifest.tsv` records the file, its format, the
record id, the catalog title and the download URL.

Downloads are cached in `<outdir>/.cache`, so a re-run only fetches what is new. Requests are serial
with a short pause: aimp.ru is a community site, not a CDN. Nothing downloaded is executed; members
are size-capped and path-checked before they are read.
"""
import csv, glob, hashlib, html, io, os, re, subprocess, sys, time, zipfile

CORPUS = os.path.expanduser("~/Library/Application Support/NullPlayer/AIMPSkins")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
SITE = "https://aimp.ru/"
LISTING = SITE + "?do=catalog&os=desktop&id=0&page={}"
RECORD = SITE + "?do=catalog&rec_id={}"
DOWNLOAD = SITE + "?do=catalog.download&id={}"
MAX_MEMBER = 1 << 30    # a skin past this is a bomb (K-2 v1.15 is a genuine 245 MB .acs5)
PAUSE = 0.4             # seconds between requests to the site


def get(url):
    """The body, and the file name the server gave it (Content-Disposition), if any."""
    from urllib.parse import unquote
    r = subprocess.run(["curl", "-sfL", "--max-time", "180", "-A", UA, "-D", "-", "-o", "-", url], capture_output=True)
    if r.returncode: raise OSError(f"curl exit {r.returncode}")
    out = r.stdout
    # Headers of every hop come first, each block ending in a blank line; the body follows the last.
    name, body = None, out
    while body[:5] == b"HTTP/":
        end = body.find(b"\r\n\r\n")
        if end < 0: break
        head = body[:end].decode("latin-1")
        m = re.search(r'filename\*?=(?:UTF-8\'\')?"?([^";\r\n]+)', head, re.I)
        if m: name = unquote(m.group(1))
        body = body[end + 4:]
    time.sleep(PAUSE)
    return body, name


def page(url):
    return get(url)[0].decode("utf-8", "replace")


# ---- the catalog ----

def listed_records(limit=None):
    """Record ids from the PC skins listing, in listing order. Featured records from other
    categories appear on every page; `record_title` sorts them out."""
    first = page(LISTING.format(1))
    last = max([int(n) for n in re.findall(r"id=0&amp;page=(\d+)", first)] or [1])
    ids = []
    for p in range(1, last + 1):
        text = first if p == 1 else page(LISTING.format(p))
        ids += [rid for rid in dict.fromkeys(re.findall(r"rec_id=(\d+)", text)) if rid not in ids]
        if limit and len(ids) >= limit: break
    print(f"listing: {last} pages, {len(ids)} record ids", file=sys.stderr)
    return ids


def csv_records(path):
    ids = []
    with open(path, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            m = re.search(r"id=(\d+)", row.get("link", ""))
            if m: ids.append(m.group(1))
    return ids


def record_title(rid):
    """`(title, is a PC skin)` from the record's page title, `Name « Skins « AIMP for PC « …`."""
    m = re.search(r"<title>([^<]*)</title>", page(RECORD.format(rid)))
    title = html.unescape(m.group(1)) if m else ""
    parts = [p.strip() for p in title.split("«")]
    return parts[0], len(parts) >= 3 and parts[1] == "Skins" and parts[2] == "AIMP for PC"


# ---- skins inside a download ----

def kind(data):
    """`acs3`, `acs3-legacy` (AIMP 3.0), `acs4`, `acs5`, another `ACS?` as `other-<magic>`, or None."""
    if data[:4] == b"ACS3": return "acs3-legacy" if data[4:5] == b"\x02" else "acs3"
    if data[:4] in (b"ACS4", b"ACS5"): return data[:4].decode().lower()
    if data[:3] == b"ACS": return "other-" + re.sub(r"[^A-Za-z0-9]", "_", data[:4].decode("latin-1"))
    return None


def skins_in(data, name="", depth=0):
    """Every skin in a download as (member name, bytes): the download itself, or a zip's members,
    recursing into nested zips."""
    if kind(data): return [(name, data)]
    if data[:2] != b"PK" or depth > 3: return []
    try: z = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile: return []
    out = []
    for i in z.infolist():
        member = i.filename.replace("\\", "/")
        if i.is_dir() or member.startswith("/") or ".." in member.split("/"): continue
        if i.file_size > MAX_MEMBER:
            print(f"  oversized member skipped: {member} ({i.file_size >> 20} MB)", file=sys.stderr); continue
        try: blob = z.read(i)
        except Exception: continue  # unsupported compression, truncated member
        out += skins_in(blob, member, depth + 1)
    return out


def ext(k):
    return ".acs3" if k.startswith("acs3") else "." + k if k in ("acs4", "acs5") else ".acs"


def safe(s):
    return re.sub(r"[^\w.+-]+", "_", s).strip("_")[:80] or "skin"


# ---- the crawl ----

def crawl(out, corpus, csv_path=None, limit=None):
    cache = os.path.join(out, ".cache")
    os.makedirs(cache, exist_ok=True)
    known = {}
    for p in glob.glob(os.path.join(glob.escape(corpus), "*")) + glob.glob(os.path.join(glob.escape(out), "**", "*.acs*"), recursive=True):
        if os.path.isfile(p):
            known.setdefault(hashlib.sha256(open(p, "rb").read()).hexdigest(), os.path.basename(p))
    print(f"known: {len(known)} skins in corpus + {out}", file=sys.stderr)

    ids = listed_records(limit)
    if csv_path:
        extra = [r for r in csv_records(csv_path) if r not in ids]
        print(f"csv: {len(extra)} more record ids", file=sys.stderr)
        ids += extra
    if limit: ids = ids[:limit]

    manifest_path = os.path.join(out, "manifest.tsv")
    done = set()
    if os.path.exists(manifest_path):
        done = {line.split("\t")[2] for line in open(manifest_path) if line.count("\t") >= 2}
    manifest = open(manifest_path, "a")
    added = dups = skipped = failed = 0
    for n, rid in enumerate(ids, 1):
        if rid in done: continue
        try: title, is_skin = record_title(rid)
        except Exception as e:
            print(f"  fail record {rid}: {e}", file=sys.stderr); failed += 1; continue
        if not is_skin:
            skipped += 1; continue
        path = os.path.join(cache, rid)
        if os.path.exists(path):
            data, fname = open(path, "rb").read(), (open(path + ".name").read() if os.path.exists(path + ".name") else "")
        else:
            try: data, fname = get(DOWNLOAD.format(rid))
            except Exception as e:
                print(f"  fail download {rid} ({title}): {e}", file=sys.stderr); failed += 1; continue
            with open(path, "wb") as f: f.write(data)
            with open(path + ".name", "w") as f: f.write(fname or "")
        skins = skins_in(data, fname or "")
        if not skins:
            note = "rar" if data[:4] == b"Rar!" else "7z" if data[:6] == b"7z\xbc\xaf\x27\x1c" else f"no skin ({data[:4]!r})"
            manifest.write("\t".join(["", note, rid, title, DOWNLOAD.format(rid)]) + "\n"); manifest.flush()
            print(f"  {rid} {title}: {note}", file=sys.stderr); continue
        for member, blob in skins:
            k = kind(blob)
            digest = hashlib.sha256(blob).hexdigest()
            if digest in known:
                dups += 1
                manifest.write("\t".join([known[digest], "duplicate", rid, title, DOWNLOAD.format(rid)]) + "\n"); continue
            stem = safe(os.path.splitext(os.path.basename(member))[0] if len(skins) > 1 and member else title)
            folder = out if not k.startswith("other") else os.path.join(out, "other")
            os.makedirs(folder, exist_ok=True)
            dest = os.path.join(folder, f"{rid}-{stem}{ext(k)}")
            with open(dest, "wb") as f: f.write(blob)
            known[digest] = os.path.basename(dest)
            manifest.write("\t".join([os.path.relpath(dest, out), k, rid, title, DOWNLOAD.format(rid)]) + "\n")
            added += 1
        manifest.flush()
        if n % 25 == 0: print(f"  {n}/{len(ids)}: added {added}, duplicates {dups}", file=sys.stderr)
    print(f"added {added}, skipped {dups} duplicates and {skipped} non-skin records, {failed} failures -> {out}",
          file=sys.stderr)


def selftest():
    acs4, acs5, legacy = b"ACS4" + b"\x00" * 20, b"ACS5" + b"\x01" * 20, b"ACS3\x02" + b"\x00" * 20
    z = io.BytesIO()
    with zipfile.ZipFile(z, "w") as w:
        w.writestr("Deck/Deck.acs4", acs4)
        w.writestr("readme.txt", "hi")
        w.writestr("../evil.acs5", acs5)
    inner = io.BytesIO()
    with zipfile.ZipFile(inner, "w") as w: w.writestr("Vega AIO.acs3", legacy)
    with zipfile.ZipFile(z, "a") as w: w.writestr("old/vega.zip", inner.getvalue())
    found = [(m, kind(b)) for m, b in skins_in(z.getvalue())]
    assert found == [("Deck/Deck.acs4", "acs4"), ("Vega AIO.acs3", "acs3-legacy")], found
    assert skins_in(acs5, "x.acs5") == [("x.acs5", acs5)]
    assert kind(b"ACS2xx") == "other-ACS2" and kind(b"PK\x03\x04") is None
    assert ext("acs3-legacy") == ".acs3" and ext("other-ACS2") == ".acs"
    assert safe("Akai GX-F90 & AM-U01 / v2") == "Akai_GX-F90_AM-U01_v2"
    print("selftest ok")


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["selftest"]: selftest(); sys.exit()
    if not a or a[0].startswith("-"): sys.exit(__doc__)
    opt = lambda k: a[a.index(k) + 1] if k in a else None
    crawl(os.path.abspath(a[0]), opt("--corpus") or CORPUS, opt("--csv"), int(opt("--limit")) if opt("--limit") else None)
