#!/usr/bin/env python3
"""Shoot a skin's main window plus every accessory window as one transparent PNG.

groupshot.py <pid> <submenu> <item> <label> <settle> <outdir>

Each on-screen window is captured by id (screencapture -l, which brings its own shadow child), then
composited at its true relative position. A shadow adds `pad` points on every side, so a window's
image origin is its frame origin minus pad, with pad = (image points - frame points) / 2.
"""
import subprocess, sys, time, os, tempfile
pid, sub, item, label, settle, outdir = sys.argv[1:7]
SC = 2  # backing scale, from `winhelper screens`
base = os.path.expanduser("~/Projects/nullplayer/skills/app-control/scripts")
subprocess.run(["osascript", f"{base}/menu.applescript", "skin", pid, sub, item], check=True, timeout=60)
time.sleep(float(settle))

def windows():
    out = subprocess.run([f"{base}/winhelper", "windows", "--pid", pid], capture_output=True, text=True).stdout
    rows = []
    for ln in out.splitlines():
        f = ln.split("\t")
        if len(f) >= 8 and f[1] == "0" and float(f[6]) > 0:
            rows.append(dict(id=f[0], x=int(f[2]), y=int(f[3]), w=int(f[4]), h=int(f[5]), title=f[7]))
    return rows

rows = windows()
print(f"{label}: {len(rows)} windows")
tmp = tempfile.mkdtemp()
parts = []
for r in rows:
    p = f"{tmp}/{r['id']}.png"
    subprocess.run(["screencapture", "-o", "-x", "-l", r["id"], p], check=True)
    dim = subprocess.run(["magick", "identify", "-format", "%w %h", p], capture_output=True, text=True).stdout.split()
    pw, ph = int(dim[0]), int(dim[1])
    padx = (pw / SC - r["w"]) / 2
    pady = (ph / SC - r["h"]) / 2
    ox, oy = r["x"] - padx, r["y"] - pady
    parts.append((p, ox, oy, pw, ph))
    print(f"  id={r['id']} [{r['title']}] {r['w']}x{r['h']}pt img={pw}x{ph}px pad=({padx:g},{pady:g}) at ({ox:g},{oy:g})")
minx = min(o for _, o, _, _, _ in parts); miny = min(o for _, _, o, _, _ in parts)
maxx = max(o + pw / SC for _, o, _, pw, _ in parts); maxy = max(o + ph / SC for _, _, o, _, ph in parts)
W, H = round((maxx - minx) * SC), round((maxy - miny) * SC)
cmd = ["magick", "-size", f"{W}x{H}", "xc:none"]
for p, ox, oy, _, _ in reversed(parts):  # windows list is front to back
    cmd += [p, "-geometry", f"+{round((ox - minx) * SC)}+{round((oy - miny) * SC)}", "-compose", "over", "-composite"]
os.makedirs(outdir, exist_ok=True)
dest = f"{outdir}/{label}.png"
cmd.append(dest)
subprocess.run(cmd, check=True)
print(f"wrote {dest} {W}x{H}px")
