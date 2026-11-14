#ifndef VIS_CLASSIC_PROFILE_H
#define VIS_CLASSIC_PROFILE_H

// The original plugin's INI profile: a `[Classic Analyzer]` section of settings, then
// `[BarColours]`, `[PeakColours]`, `[VolumeColours]` (256 `R G B` rows each) and `[VolumeFunction]`
// (256 integers). This file only reads and writes it; the core decides what each setting means.

#include <array>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "VisClassicEffects.h"

namespace visclassic {

using VolumeFunction = std::array<int, kColorCount>;

struct IniProfile {
    std::vector<std::pair<std::string, std::string>> analyzer;  // file order; a repeated key's last value wins
    Palette barColors{};
    Palette peakColors{};
    Palette volumeColors{};
    VolumeFunction volumeFunc{};
    bool hasBarColors = false;
    bool hasPeakColors = false;
    bool hasVolumeColors = false;
    bool hasVolumeFunc = false;

    const std::string *analyzerValue(const std::string &key) const;
    // The `[Classic Analyzer]` integer `key`; nothing when absent or unparsable.
    std::optional<int> analyzerInt(const std::string &key) const;
};

bool readProfile(const std::string &path, IniProfile &out);

// Writes `profile.analyzer` in its order, then every palette and VolumeFunction.
bool writeProfile(const std::string &path, const IniProfile &profile);

std::string trim(const std::string &s);

// The file name without its directory or extension.
std::string stemFromPath(const std::string &path);

}  // namespace visclassic

#endif
