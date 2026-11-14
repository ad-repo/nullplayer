#ifndef VIS_CLASSIC_PROFILE_H
#define VIS_CLASSIC_PROFILE_H

// The original plugin's INI profile: a `[Classic Analyzer]` section of settings, then
// `[BarColours]`, `[PeakColours]`, `[VolumeColours]` (256 `R G B` rows each) and `[VolumeFunction]`
// (256 integers). This file only reads and writes it; the core decides what each setting means.

#include <array>
#include <map>
#include <string>
#include <utility>
#include <vector>

#include "VisClassicEffects.h"

namespace visclassic {

using VolumeFunction = std::array<int, 256>;

struct IniProfile {
    std::map<std::string, std::string> analyzer;
    Palette barColors{};
    Palette peakColors{};
    Palette volumeColors{};
    VolumeFunction volumeFunc{};
    bool hasBarColors = false;
    bool hasPeakColors = false;
    bool hasVolumeColors = false;
    bool hasVolumeFunc = false;

    // The `[Classic Analyzer]` integer `key`, clamped to [lo, hi]; `fallback` when absent or unparsable.
    int analyzerInt(const char *key, int fallback, int lo, int hi) const;
};

bool readProfile(const std::string &path, IniProfile &out);

// Writes `analyzer` in the order given, then the palettes and VolumeFunction.
bool writeProfile(const std::string &path,
                  const std::vector<std::pair<std::string, std::string>> &analyzer,
                  const Palette &bars, const Palette &peaks, const Palette &volumes,
                  const VolumeFunction &volumeFunc);

std::string trim(const std::string &s);

// The file name without its directory or extension.
std::string stemFromPath(const std::string &path);

}  // namespace visclassic

#endif
