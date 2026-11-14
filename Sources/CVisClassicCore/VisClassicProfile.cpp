#include "VisClassicProfile.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <sstream>

namespace visclassic {

namespace {

bool parseInt(const std::string &s, int &out) {
    try {
        size_t pos = 0;
        int v = std::stoi(trim(s), &pos, 10);
        if (pos == 0) return false;
        out = v;
        return true;
    } catch (...) {
        return false;
    }
}

// Profile colours are `R G B` as they appear on screen. The original plugin's source reads them
// into variables named `r g b` and stores `RGB(b, g, r)` into a COLORREF, but that COLORREF goes
// straight into a 32-bit DIB whose byte order undoes the swap — its built-in default,
// `bmpRGB(204 + i/5, i, 0)`, is the red→yellow of "Default Red & Yellow". Reading them as B G R
// drew every bundled profile with red and blue exchanged.
bool parseRGB(const std::string &s, RGB &out) {
    std::istringstream iss(s);
    int r = 0, g = 0, b = 0;
    if (!(iss >> r >> g >> b)) {
        return false;
    }
    out.b = static_cast<uint8_t>(std::clamp(b, 0, 255));
    out.g = static_cast<uint8_t>(std::clamp(g, 0, 255));
    out.r = static_cast<uint8_t>(std::clamp(r, 0, 255));
    return true;
}

void writePalette(std::ofstream &out, const char *section, const Palette &palette) {
    out << "[" << section << "]\n";
    for (int i = 0; i < kColorCount; ++i) {
        out << i << "=" << static_cast<int>(palette[i].r) << " "
            << static_cast<int>(palette[i].g) << " "
            << static_cast<int>(palette[i].b) << "\n";
    }
}

}  // namespace

std::string trim(const std::string &s) {
    size_t start = 0;
    while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start]))) {
        ++start;
    }
    size_t end = s.size();
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
        --end;
    }
    return s.substr(start, end - start);
}

std::string stemFromPath(const std::string &path) {
    const size_t slash = path.find_last_of("/\\");
    const std::string file = (slash == std::string::npos) ? path : path.substr(slash + 1);
    const size_t dot = file.find_last_of('.');
    if (dot == std::string::npos) return file;
    return file.substr(0, dot);
}

const std::string *IniProfile::analyzerValue(const std::string &key) const {
    for (auto it = analyzer.rbegin(); it != analyzer.rend(); ++it) {
        if (it->first == key) return &it->second;
    }
    return nullptr;
}

std::optional<int> IniProfile::analyzerInt(const std::string &key) const {
    const std::string *value = analyzerValue(key);
    int v = 0;
    if (!value || !parseInt(*value, v)) return std::nullopt;
    return v;
}

bool readProfile(const std::string &path, IniProfile &out) {
    std::ifstream in(path);
    if (!in) {
        return false;
    }

    std::string section;
    std::string line;
    while (std::getline(in, line)) {
        line = trim(line);
        if (line.empty()) continue;
        if (line[0] == ';' || line[0] == '#') continue;
        if (line.front() == '[' && line.back() == ']') {
            section = line.substr(1, line.size() - 2);
            continue;
        }

        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string key = trim(line.substr(0, eq));
        std::string value = trim(line.substr(eq + 1));

        if (section == "Classic Analyzer") {
            out.analyzer.emplace_back(key, value);
            continue;
        }

        int idx = -1;
        if (!parseInt(key, idx) || idx < 0 || idx >= kColorCount) {
            continue;
        }

        if (section == "VolumeFunction") {  // integers, not colours
            int v = 0;
            if (parseInt(value, v)) {
                out.volumeFunc[static_cast<size_t>(idx)] = v;
                out.hasVolumeFunc = true;
            }
            continue;
        }

        RGB c;
        if (!parseRGB(value, c)) {
            continue;
        }

        if (section == "BarColours") {
            out.barColors[static_cast<size_t>(idx)] = c;
            out.hasBarColors = true;
        } else if (section == "PeakColours") {
            out.peakColors[static_cast<size_t>(idx)] = c;
            out.hasPeakColors = true;
        } else if (section == "VolumeColours") {
            out.volumeColors[static_cast<size_t>(idx)] = c;
            out.hasVolumeColors = true;
        }
    }

    return true;
}

bool writeProfile(const std::string &path, const IniProfile &profile) {
    std::ofstream out(path, std::ios::out | std::ios::trunc);
    if (!out) {
        return false;
    }

    out << "[Classic Analyzer]\n";
    for (const auto &[key, value] : profile.analyzer) {
        out << key << "=" << value << "\n";
    }

    writePalette(out, "BarColours", profile.barColors);
    writePalette(out, "PeakColours", profile.peakColors);
    writePalette(out, "VolumeColours", profile.volumeColors);

    out << "[VolumeFunction]\n";
    for (int i = 0; i < kColorCount; ++i) {
        out << i << "=" << profile.volumeFunc[i] << "\n";
    }
    return true;
}

}  // namespace visclassic
