#!/usr/bin/env python3
"""Generate vis_classic profile catalog markdown from bundled INI files."""

from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Tuple

PROFILE_KEYS = [
    "Falloff",
    "PeakChange",
    "Bar Width",
    "X-Spacing",
    "Y-Spacing",
    "BackgroundDraw",
    "BarColourStyle",
    "PeakColourStyle",
    "Effect",
    "Peak Effect",
    "ReverseLeft",
    "ReverseRight",
    "Mono",
    "Bar Level",
    "FFTEqualize",
    "FFTEnvelope",
    "FFTScale",
    "FitToWidth",
    "Message",
]

BACKGROUND_DRAW_MAP = {
    0: "Black",
    1: "Flash-ish low gray",
    2: "Dark solid",
    3: "Dark grid",
    4: "Flash grid",
}

BAR_STYLE_MAP = {
    0: "BarColourClassic",
    1: "BarColourFire",
    2: "BarColourLines",
    3: "BarColourWinampFire",
    4: "BarColourElevator",
}

PEAK_STYLE_MAP = {
    0: "PeakColourFade",
    1: "PeakColourLevel",
    2: "PeakColourLevelFade",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def profile_dir() -> Path:
    return repo_root() / "Sources" / "NullPlayer" / "Resources" / "vis_classic" / "profiles"


def output_path() -> Path:
    return repo_root() / "skills" / "vis-classic-guide" / "references" / "profile-catalog.md"


def parse_ini(path: Path) -> Tuple[Dict[str, str], Dict[int, Tuple[int, int, int]], Dict[int, Tuple[int, int, int]]]:
    section = ""
    analyzer: Dict[str, str] = {}
    bar: Dict[int, Tuple[int, int, int]] = {}
    peak: Dict[int, Tuple[int, int, int]] = {}

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("#"):
            continue

        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            continue

        if "=" not in line:
            continue

        key, value = (part.strip() for part in line.split("=", 1))

        if section == "Classic Analyzer":
            analyzer[key] = value
            continue

        try:
            idx = int(key)
        except ValueError:
            continue
        if idx < 0 or idx > 255:
            continue

        parts = value.split()
        if len(parts) < 3:
            continue

        try:
            b, g, r = (max(0, min(255, int(parts[0]))), max(0, min(255, int(parts[1]))), max(0, min(255, int(parts[2]))))
        except ValueError:
            continue

        rgb = (r, g, b)
        if section == "BarColours":
            bar[idx] = rgb
        elif section == "PeakColours":
            peak[idx] = rgb

    return analyzer, bar, peak


def int_value(analyzer: Dict[str, str], key: str, default: int = 0) -> int:
    try:
        return int(analyzer.get(key, str(default)).strip())
    except ValueError:
        return default


def bool_label(value: int) -> str:
    return "On" if value else "Off"


def falloff_label(falloff: int) -> str:
    if falloff <= 8:
        return "slow decay / lingering bars"
    if falloff <= 12:
        return "moderate decay"
    return "fast decay / snappier drop"


def peak_label(peak_change: int) -> str:
    if peak_change <= 0:
        return "peaks disabled"
    if peak_change < 60:
        return "short peak hold"
    if peak_change < 100:
        return "medium peak hold"
    return "long peak hold"


def sensitivity_label(fft_scale: int) -> str:
    if fft_scale <= 180:
        return "high sensitivity"
    if fft_scale <= 210:
        return "balanced sensitivity"
    return "lower sensitivity"


def color_hex(rgb: Tuple[int, int, int]) -> str:
    r, g, b = rgb
    return f"#{r:02X}{g:02X}{b:02X}"


def color_entry(rgb: Tuple[int, int, int] | None) -> str:
    if rgb is None:
        return "n/a"
    return f"`{color_hex(rgb)}` ({rgb[0]}, {rgb[1]}, {rgb[2]})"


def luminance_stats(colors: Dict[int, Tuple[int, int, int]]) -> str:
    if not colors:
        return "n/a"
    lum = []
    for r, g, b in colors.values():
        lum.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
    return f"{min(lum):.1f}..{max(lum):.1f}"


def row(key: str, value: str) -> str:
    return f"| `{key}` | {value} |"


def render_profile(
    name: str,
    path: Path,
    analyzer: Dict[str, str],
    bar: Dict[int, Tuple[int, int, int]],
    peak: Dict[int, Tuple[int, int, int]],
) -> List[str]:
    falloff = int_value(analyzer, "Falloff", 12)
    peak_change = int_value(analyzer, "PeakChange", 80)
    fft_scale = int_value(analyzer, "FFTScale", 200)
    mono = int_value(analyzer, "Mono", 1)
    bar_level = int_value(analyzer, "Bar Level", 1)
    bar_width = int_value(analyzer, "Bar Width", 3)
    x_spacing = int_value(analyzer, "X-Spacing", 1)
    y_spacing = int_value(analyzer, "Y-Spacing", 2)
    background_draw = int_value(analyzer, "BackgroundDraw", 0)
    bar_style = int_value(analyzer, "BarColourStyle", 0)
    peak_style = int_value(analyzer, "PeakColourStyle", 0)

    message = analyzer.get("Message", "").strip() or "No Message field in this profile."
    mono_text = "Mono combined channels" if mono else "Stereo split channels"
    bar_level_text = "Average bins" if bar_level else "Union/max bins"

    anchors = [0, 64, 128, 192, 255]

    lines: List[str] = []
    lines.append(f"## {name}")
    lines.append("")
    lines.append(f"- File: `{path.relative_to(repo_root()).as_posix()}`")
    lines.append(f"- Description: {message}")
    lines.append("")

    lines.append("### Technical Settings")
    lines.append("")
    lines.append("| Key | Value |")
    lines.append("|---|---|")
    for key in PROFILE_KEYS:
        raw = analyzer.get(key, "")
        display = raw if raw else "(not set)"

        if key in ("ReverseLeft", "ReverseRight", "Mono", "FFTEqualize", "FitToWidth") and raw != "":
            display = f"{raw} ({bool_label(int_value(analyzer, key, 0))})"

        if key == "Bar Level" and raw != "":
            display = f"{raw} ({'Average' if int_value(analyzer, key, 1) else 'Union/Max'})"

        if key == "BackgroundDraw" and raw != "":
            mapped = BACKGROUND_DRAW_MAP.get(int_value(analyzer, key, 0), "Unknown")
            display = f"{raw} ({mapped})"

        if key == "BarColourStyle" and raw != "":
            mapped = BAR_STYLE_MAP.get(int_value(analyzer, key, 0), "Unknown")
            display = f"{raw} ({mapped})"

        if key == "PeakColourStyle" and raw != "":
            mapped = PEAK_STYLE_MAP.get(int_value(analyzer, key, 0), "Unknown")
            display = f"{raw} ({mapped})"

        lines.append(row(key, display))

    lines.append("")
    lines.append("### Derived Behavior")
    lines.append("")
    lines.append(f"- Dynamics: `Falloff={falloff}` -> {falloff_label(falloff)}.")
    lines.append(f"- Peak behavior: `PeakChange={peak_change}` -> {peak_label(peak_change)}.")
    lines.append(f"- Sensitivity: `FFTScale={fft_scale}` -> {sensitivity_label(fft_scale)} (lower values are more reactive).")
    lines.append(f"- Channel layout: `{mono_text}`; level aggregation uses `{bar_level_text}`.")
    lines.append(f"- Geometry: `Bar Width={bar_width}`, `X-Spacing={x_spacing}`, `Y-Spacing={y_spacing}`.")
    lines.append(
        f"- Style maps: `BackgroundDraw={background_draw}` (`{BACKGROUND_DRAW_MAP.get(background_draw, 'Unknown')}`), "
        f"`BarColourStyle={bar_style}` (`{BAR_STYLE_MAP.get(bar_style, 'Unknown')}`), "
        f"`PeakColourStyle={peak_style}` (`{PEAK_STYLE_MAP.get(peak_style, 'Unknown')}`)."
    )
    lines.append("")

    lines.append("### Palette Snapshot")
    lines.append("")
    lines.append("| Palette | idx 0 | idx 64 | idx 128 | idx 192 | idx 255 |")
    lines.append("|---|---|---|---|---|---|")
    lines.append(
        "| BarColours | "
        + " | ".join(color_entry(bar.get(idx)) for idx in anchors)
        + " |"
    )
    lines.append(
        "| PeakColours | "
        + " | ".join(color_entry(peak.get(idx)) for idx in anchors)
        + " |"
    )
    lines.append("")
    lines.append("| Palette Metric | Value |")
    lines.append("|---|---|")
    lines.append(row("BarColours entries", str(len(bar))))
    lines.append(row("PeakColours entries", str(len(peak))))
    lines.append(row("Bar luminance range", luminance_stats(bar)))
    lines.append(row("Peak luminance range", luminance_stats(peak)))
    lines.append("")

    return lines


def build_markdown() -> str:
    profiles_root = profile_dir()
    profile_files = sorted(profiles_root.glob("*.ini"), key=lambda p: p.stem.casefold())

    lines: List[str] = []
    lines.append("# vis_classic Profile Catalog")
    lines.append("")
    lines.append("Generated from bundled profile INI files in `Sources/NullPlayer/Resources/vis_classic/profiles/`.")
    lines.append("")
    lines.append(f"- Total profiles: **{len(profile_files)}**")
    lines.append("- Source format: `[Classic Analyzer]`, `[BarColours]`, `[PeakColours]`")
    lines.append("- Color values in INI are BGR; this catalog displays RGB.")
    lines.append("")

    lines.append("## Option Legend")
    lines.append("")
    lines.append("| Key | Meaning |")
    lines.append("|---|---|")
    lines.append("| `Falloff` | Per-frame bar decay amount when levels drop (higher = faster fall). |")
    lines.append("| `PeakChange` | Peak hold timer before peak marker decays. |")
    lines.append("| `Bar Width`, `X-Spacing`, `Y-Spacing` | Bar geometry and spacing controls. |")
    lines.append("| `BackgroundDraw` | Background style selector (0..4). |")
    lines.append("| `BarColourStyle` | Bar color index function selector (0..4). |")
    lines.append("| `PeakColourStyle` | Peak color index function selector (0..2). |")
    lines.append("| `Effect` | Effect selector; current port has explicit branch for `7` (fade shadow). |")
    lines.append("| `Peak Effect` | Parsed/persisted compatibility field; no dedicated render branch in current port. |")
    lines.append("| `ReverseLeft`, `ReverseRight` | Channel drawing direction flags. |")
    lines.append("| `Mono` | `1` uses mono combined bands; `0` uses stereo split halves. |")
    lines.append("| `Bar Level` | `0` union/max aggregation; `1` average aggregation. |")
    lines.append("| `FFTEqualize` | Toggle FFT equalization table. |")
    lines.append("| `FFTEnvelope` | FFT envelope power x100. |")
    lines.append("| `FFTScale` | FFT output divisor x100 (lower = more sensitive). |")
    lines.append("| `FitToWidth` | Whether bars are distributed across full output width. |")
    lines.append("| `Message` | Human description embedded in profile. |")
    lines.append("")

    lines.append("## Enum Values")
    lines.append("")
    lines.append("- `BackgroundDraw`: " + ", ".join(f"`{k}`={v}" for k, v in BACKGROUND_DRAW_MAP.items()))
    lines.append("- `BarColourStyle`: " + ", ".join(f"`{k}`={v}" for k, v in BAR_STYLE_MAP.items()))
    lines.append("- `PeakColourStyle`: " + ", ".join(f"`{k}`={v}" for k, v in PEAK_STYLE_MAP.items()))
    lines.append("")

    lines.append("## Profiles")
    lines.append("")
    for ini in profile_files:
        analyzer, bar, peak = parse_ini(ini)
        lines.extend(render_profile(ini.stem, ini, analyzer, bar, peak))

    return "\n".join(lines).rstrip() + "\n"


def main() -> None:
    markdown = build_markdown()
    out = output_path()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(markdown, encoding="utf-8")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
