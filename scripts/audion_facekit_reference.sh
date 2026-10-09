#!/bin/bash
#
# The FaceKit oracle: renders every face through Panic's own FaceKit, so an Audion render diff is
# classified against ground truth instead of against the engine's last guess.
#
#   scripts/audion_facekit_reference.sh <outdir> [--corpus <dir>] [--jobs <n>]
#
# Writes <outdir>/png/<face>/<state>.png for the canonical states, `stopped` and `playing`, and
# <outdir>/oracle.txt with one `ORACLE <face> ok|FAILED <why>` line per face. Compare with
# scripts/audion_oracle_compare.py. Output is never committed. See
# skills/audion-face-guide/reference/harness.md § *The oracle*; this script restates nothing there.
#
# FaceKit is cloned at the pinned commit into a cache outside the repo ($AUDION_FACEKIT_CACHE,
# default ~/Library/Caches/NullPlayer/facekit) and compiled unmodified beside the small headless
# main.swift below. One process per face: FaceKit traps on some hostile input (a negative animation
# frame count), and a trap must cost that face, not the run.

set -u -o pipefail
source "$(dirname "$0")/lib/audion_corpus.sh"

readonly PIN=5b7c847
readonly UPSTREAM=https://gitlab.com/panicinc/facekit.git
readonly CACHE="${AUDION_FACEKIT_CACHE:-$HOME/Library/Caches/NullPlayer/facekit}"

usage() { echo "usage: audion_facekit_reference.sh <outdir> [--corpus <dir>] [--jobs <n>]" >&2; exit 2; }

out="" corpus="$AUDION_CORPUS_DEFAULT" jobs="$(sysctl -n hw.ncpu)"
while [ $# -gt 0 ]; do
    case "$1" in
        --corpus) corpus="${2:-}"; shift 2 ;;
        --jobs) jobs="${2:-}"; shift 2 ;;
        -*) usage ;;
        *) [ -n "$out" ] && usage; out="$1"; shift ;;
    esac
done
[ -n "$out" ] || usage
[ -d "$corpus" ] || { echo "audion_facekit_reference: no corpus at $corpus" >&2; exit 1; }

mkdir -p "$CACHE/build"
if [ ! -d "$CACHE/src/.git" ]; then
    git clone --quiet "$UPSTREAM" "$CACHE/src" || exit 1
fi
git -C "$CACHE/src" checkout --quiet "$PIN" || { echo "audion_facekit_reference: cannot check out $PIN" >&2; exit 1; }

# The headless host. Everything it does is what FaceKit's own view does in a window, except that the
# view's backing layer never displays without a window server: FaceKit's own `draw(_:in:)` is called
# for it (base and animation) and the result put in a sublayer beneath every other, where the backing
# layer's own contents would sit. `render(in:)` then composites the tree with FaceKit's mask layer
# over all of it — but in sublayer array order, ignoring zPosition, so the siblings are first put
# in the zPosition order the screen draws them in: buttons 1, digits and indicators 2, labels 10.
# Reduce Motion is pinned on so the album line truncates rather than scrolls, whatever the machine.
cat > "$CACHE/build/main.swift" <<'SWIFT'
import Cocoa

final class Host: AudionFaceViewDelegate {
    let supportsStop = true, supportsRewind = true, supportsFastForward = true
    func play(_ sender: AudionFaceView) {}
    func pause(_ sender: AudionFaceView) {}
    func stop(_ sender: AudionFaceView) {}
    func rewind(_ sender: AudionFaceView) {}
    func fastForward(_ sender: AudionFaceView) {}
    func volumeChanged(to: Double, sender: AudionFaceView) {}
    func playTimeChanged(to: Double, sender: AudionFaceView) {}
    func pauseBeforeScrubbing(_ sender: AudionFaceView) {}
    func playAfterScrubbing(_ sender: AudionFaceView) {}
}

let reduceMotion: @convention(block) (NSWorkspace) -> Bool = { _ in true }
method_setImplementation(
    class_getInstanceMethod(NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion))!,
    imp_implementationWithBlock(reduceMotion))
_ = NSApplication.shared

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let folder = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let name = folder.lastPathComponent
let host = Host()

func render(_ face: AudionFace, playing: Bool) -> CGImage {
    let view = AudionFaceView(draggable: false, delegate: host)
    view.enableAllButtons = true
    view.face = face
    if playing {
        view.durationInSeconds = 213
        view.timeInSeconds = 83
        view.artistText = "A Fairly Long Track Title For The Oracle"
        view.albumText = "Harness Artist—Harness Album—MP3"
        view.play()
    } else {
        view.stop()
    }
    let size = NSSize(width: face.base.width, height: face.base.height)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                          backing: .buffered, defer: false)
    window.contentView!.wantsLayer = true
    window.contentView!.addSubview(view)
    view.frame = NSRect(origin: .zero, size: size)
    window.layoutIfNeeded()
    window.displayIfNeeded()
    CATransaction.flush()

    func context() -> CGContext {
        CGContext(data: nil, width: face.base.width, height: face.base.height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    let base = context()
    view.draw(view.layer!, in: base)
    // FaceKit's base pass marks the digit sublayer for display; a window would display it next.
    view.sublayer.displayIfNeeded()
    let backing = CALayer()
    backing.frame = view.layer!.bounds
    backing.zPosition = -1
    backing.contents = base.makeImage()
    view.layer!.insertSublayer(backing, at: 0)
    // `render(in:)` composites siblings in array order and ignores zPosition; the screen does not.
    view.layer!.sublayers = view.layer!.sublayers!.enumerated()
        .sorted { ($0.element.zPosition, $0.offset) < ($1.element.zPosition, $1.offset) }.map(\.element)
    let canvas = context()
    view.layer!.render(in: canvas)
    return canvas.makeImage()!
}

do {
    let face = try AudionFace.load(path: folder)
    let dir = out.appendingPathComponent("png").appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (state, playing) in [("stopped", false), ("playing", true)] {
        let data = NSBitmapImageRep(cgImage: render(face, playing: playing)).representation(using: .png, properties: [:])!
        try data.write(to: dir.appendingPathComponent("\(state).png"))
    }
    print("ORACLE \(name) ok")
} catch {
    print("ORACLE \(name) FAILED \(error)")
}
SWIFT

src="$CACHE/src/FaceKit"
if [ ! -x "$CACHE/build/oracle" ] || [ "$CACHE/build/main.swift" -nt "$CACHE/build/oracle" ]; then
    swiftc -O -module-name FaceKit "$src/AudionFace.swift" "$src/AudionFaceView.swift" \
        "$src/AudionSliderWindow.swift" "$CACHE/build/main.swift" -o "$CACHE/build/oracle" \
        || { echo "audion_facekit_reference: the oracle did not compile" >&2; exit 1; }
fi

mkdir -p "$out/png"
echo "audion_facekit_reference started $(date '+%F %T') — not finished" > "$out/INCOMPLETE"
# The same face list the sweep measures, exclusions applied. A process that dies prints nothing, so
# a face with no ORACLE line is reported below rather than passing as absent.
faces=$(audion_face_list "$corpus" "$out/faces.txt" audion_facekit_reference)
[ "$faces" -gt 0 ] || { echo "audion_facekit_reference: no faces in $corpus" >&2; exit 1; }
tr '\n' '\0' < "$out/faces.txt" |
    xargs -0 -n 1 -P "$jobs" "$CACHE/build/oracle" "$out" > "$out/oracle.txt" 2> "$out/stderr.txt"
ok=$(grep -c ' ok$' "$out/oracle.txt")
failed=$(grep -c ' FAILED ' "$out/oracle.txt")
echo "audion_facekit_reference: $faces faces, $ok rendered, $failed FaceKit refused, $((faces - ok - failed)) died"
rm -f "$out/INCOMPLETE"
