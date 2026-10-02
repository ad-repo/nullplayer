#!/usr/bin/env python3
"""User-level regression test for the Skins menu's family switching, through the real menus.

    skills/app-control/scripts/skin-pick-matrix.py

Three passes on one debug-build launch (Classic `aquamp`), about three minutes:
  pick    a skin in every family from every other family (20) plus one within each family (5)
  switch  every family's "Switch to ..." item from every other family (20), landing on the
          family's remembered skin
  load    "Load ... Skin..." through the open panel into Original, Modern, Media Player and
          Classic, from outside the family and from inside it (8). Original-Metal runs Original's
          action with its family passed in; there is no Metal `.nsz` to import.

Per cell: the Skins menu ticks the target family, the target submenu ticks the skin, a
`reloadUI — switching to <family>` log line appears exactly when the family changed, the family's
own load evidence names the skin, and a window is on screen. One row per cell, then
`SKIN-PICK MATRIX PASS|FAIL: n/m cells` and a matching exit status.

It quits any running NullPlayer, saves and restores the debug `NullPlayer` defaults domain, and
deletes the `Matrix*` skins the load pass imports. The load pass types into the open panel, so the
build is brought to the front for it; leave the keyboard alone while it runs."""
import os, shutil, subprocess, sys, tempfile, time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
SCRIPTS = os.path.join(REPO, "skills/app-control/scripts")
MA = os.path.join(SCRIPTS, "menu.applescript")
WH = os.path.join(SCRIPTS, "winhelper")
SUPPORT = os.path.expanduser("~/Library/Application Support/NullPlayer")
TMP = tempfile.mkdtemp(prefix="np-skin-pick-matrix-")
LOG = os.path.join(TMP, "np.log")
BASE = os.path.join(TMP, "defaults-baseline.plist")

FAMILIES = {  # submenu -> two skins, alternated so every pick is a real change
    "Classic": ["aquamp", "ascii"],
    "Original": ["NeonWave", "ArcticMinimal"],
    "Original-Metal": ["Brushed Steel", "Gunmetal"],
    "Modern": ["2222-cPro__Bento", "211786-Cpro_Winamp_Modern"],
    "Media Player": ["corona", "9SeriesDefault"],
}
# Load pass: submenu -> (name it is listed under, file, where the import lands)
LOADS = {"Classic": ("MatrixClassic", "MatrixClassic.wsz", "Skins"),
         "Original": ("MatrixOriginal", "MatrixOriginal.nsz", "ModernSkins"),
         "Modern": ("MatrixModern", "MatrixModern.wal", "WinampModernSkins"),
         "Media Player": ("MatrixWMP", "MatrixWMP.wmz", "WMPSkins")}

def sh(*args, check=False):
    r = subprocess.run(args, capture_output=True, text=True)
    if check and r.returncode:
        raise RuntimeError(f"{args}: {r.stderr.strip()}")
    return r.stdout.strip()

def menu(pid, *args):
    return sh("osascript", MA, args[0], str(pid), *args[1:], check=True)

def log_lines():
    with open(LOG, errors="replace") as f:
        return f.read().splitlines()

def poll(fn, timeout=25, step=0.5):
    end = time.time() + timeout
    while True:
        try:
            v = fn()
        except RuntimeError:  # a `.wal` build holds the main thread; menu bar reads fail meanwhile
            v = None
        if v or time.time() > end:
            return v
        time.sleep(step)

def euler(nodes, start):
    """Hierholzer over the complete digraph: every ordered pair once."""
    adj = {n: [m for m in nodes if m != n] for n in nodes}
    stack, path = [start], []
    while stack:
        v = stack[-1]
        if adj[v]:
            stack.append(adj[v].pop(0))
        else:
            path.append(stack.pop())
    return path[::-1]

def make_load_files():
    d = os.path.join(TMP, "load")
    os.makedirs(d)
    shutil.copy(os.path.join(SUPPORT, "Skins/aquamp.wsz"), os.path.join(d, "MatrixClassic.wsz"))
    shutil.copy(os.path.join(SUPPORT, "WinampModernSkins/2222-cPro__Bento.wal"), os.path.join(d, "MatrixModern.wal"))
    shutil.copy(os.path.join(SUPPORT, "WMPSkins/corona.wmz"), os.path.join(d, "MatrixWMP.wmz"))
    subprocess.run(["zip", "-qr", os.path.join(d, "MatrixOriginal.nsz"), "."], check=True,
                   cwd=os.path.join(REPO, "Sources/NullPlayer/Resources/Skins/NeonWave"))
    return d

def load_evidence(fam, skin, new, kind):
    text = "\n".join(new)
    if fam == "Classic":
        p = sh("defaults", "read", "NullPlayer", "lastClassicSkinPath")
        return os.path.splitext(os.path.basename(p))[0] == skin, f"lastClassicSkinPath={os.path.basename(p)}"
    if fam == "Modern":
        ok = f"WinampModern surfaces [{skin}.wal]" in text
        return ok, "surfaces line" if ok else "no surfaces line"
    if fam == "Media Player":
        n = sh("defaults", "read", "NullPlayer", "wmpSkinName")
        return n.lower() == skin.lower(), f"wmpSkinName={n}"
    if kind == "load":  # a `.nsz` loads from a temporary extraction, which names nothing
        return True, "n/a"
    hits = [l for l in new if "Loaded" in l and ("ModernSkinLoader" in l or "metal skin" in l)]
    ok = any(skin in l or skin.replace(" ", "") in l for l in hits)
    return ok, ("Loaded line" if ok else "no Loaded line")

def build_steps(names):
    route = euler(names, "Classic")
    steps, seen = [], set()
    for prev, cur in zip(route, route[1:]):
        steps.append(("pick", prev, cur))
        if cur not in seen:
            steps.append(("pick", cur, cur)); seen.add(cur)
    route2 = euler(names, route[-1])
    steps += [("switch", a, b) for a, b in zip(route2, route2[1:])]
    for fam in ["Original", "Modern", "Media Player", "Classic"]:
        prev = steps[-1][2]
        steps += [("load", prev, fam), ("load", fam, fam)]
    return steps

def run(pid, load_dir):
    for fam in FAMILIES:  # every skin named here must really be in its submenu
        items = [x.strip() for x in menu(pid, "list", fam).split(",")]
        missing = [s for s in FAMILIES[fam] if s not in items]
        if missing:
            print(f"SETUP FAIL: {missing} not in the {fam} submenu")
            return 1
    steps = build_steps(list(FAMILIES))
    current = {f: None for f in FAMILIES}
    current["Classic"] = "aquamp"
    fails = 0
    for i, (kind, src, dst) in enumerate(steps, 1):
        skin = {"pick": lambda: next(s for s in FAMILIES[dst] if s != current[dst]),
                "load": lambda: LOADS[dst][0],
                "switch": lambda: current[dst]}[kind]()
        mark = len(log_lines())
        t0 = time.time()
        if kind == "pick":
            menu(pid, "skin", dst, skin)
        elif kind == "load":
            menu(pid, "load", dst, os.path.join(load_dir, LOADS[dst][1]))
        else:
            r = menu(pid, "mode", dst)
            if not r.startswith("switched:"):
                print(f"{i:2d} FAIL  switch {src} -> {dst}: no Switch to item ({r})", flush=True)
                fails += 1
                continue
        fam_ok = poll(lambda: menu(pid, "family") == dst)
        skin_ok = poll(lambda: menu(pid, "current", dst) == skin, timeout=10) if fam_ok else False
        time.sleep(1.5)
        new = log_lines()[mark:]
        switched = any(f"reloadUI — switching to {dst} UI" in l for l in new)
        ev_ok, ev = load_evidence(dst, skin, new, kind)
        alive = subprocess.run(["kill", "-0", str(pid)]).returncode == 0
        win_ok = alive and bool(sh(WH, "windows", "--pid", str(pid)))
        ok = fam_ok and skin_ok and switched == (src != dst) and ev_ok and win_ok
        fails += not ok
        if skin_ok:
            current[dst] = skin
        print(f"{i:2d} {'PASS' if ok else 'FAIL'}  {kind:<6} {src:>14} -> {dst:<14} '{skin}'  "
              f"family={'ok' if fam_ok else 'no'} checkedSkin={'ok' if skin_ok else 'no'} "
              f"reloadUI={'yes' if switched else 'no'} load={ev} window={'ok' if win_ok else 'none'} "
              f"{time.time()-t0:.1f}s", flush=True)
        if not alive:
            print("ABORT: the app exited")
            fails += len(steps) - i
            break
    print(f"SKIN-PICK MATRIX {'PASS' if not fails else 'FAIL'}: {len(steps)-fails}/{len(steps)} cells")
    return 1 if fails else 0

def main():
    sh("defaults", "export", "NullPlayer", BASE, check=True)
    pid = None
    try:
        load_dir = make_load_files()
        out = subprocess.run([os.path.join(SCRIPTS, "launch.sh"), "aquamp", "--log", LOG],
                             cwd=REPO, capture_output=True, text=True)
        print(out.stdout.strip().splitlines()[-1] if out.stdout.strip() else out.stderr[-500:])
        if "LAUNCH PASS" not in out.stdout:
            return 1
        pid = int(sh("pgrep", "-nx", "NullPlayer"))
        time.sleep(3)
        return run(pid, load_dir)
    finally:
        if pid:
            subprocess.run(["kill", str(pid)], capture_output=True)
            time.sleep(2)
        sh("defaults", "delete", "NullPlayer")
        sh("defaults", "import", "NullPlayer", BASE)
        for _, f, d in LOADS.values():
            try:
                os.remove(os.path.join(SUPPORT, d, f))
            except FileNotFoundError:
                pass
        print(f"log: {LOG}")

if __name__ == "__main__":
    sys.exit(main())
