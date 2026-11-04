#ifndef VIS_CLASSIC_PEAKS_H
#define VIS_CLASSIC_PEAKS_H

// Peak Effects, ported from the original plugin's Vis_Satan.cpp (`PeakLevel*`,
// `UpdatePeakColourLookup`). A peak's whole life is a table: once a bar sets it at `level`, it
// counts `t` down from `length[level]` to 0, sitting at `level[level][t]` and drawn in peak colour
// `colour[level][t]`.

#include <array>
#include <cstdint>

namespace visclassic {

enum PeakEffect { kPeakNormal = 0, kPeakFall, kPeakRise, kPeakFallAndRise, kPeakRiseFall, kPeakSparks };

struct PeakTables {
    std::array<int16_t, 256> length{};
    std::array<std::array<int16_t, 256>, 256> level{};
    std::array<std::array<uint8_t, 256>, 256> colour{};
};

using PeakColourFn = unsigned char (*)(int level, int y);

// Small seeded generator for Sparks (and the smoke effect): repeatable for tests.
struct Rng {
    uint32_t state = 0x12345678u;
    uint32_t next() {
        state = state * 1664525u + 1013904223u;
        return state >> 8;
    }
};

// Rebuilds the tables for these settings. Does nothing when `changeRate` is 0 (peaks off).
// `logFalloff` is the profile's PeakFallOffMode, used by Fall only.
void buildPeakTables(PeakTables &tables, int effect, int changeRate, bool logFalloff,
                     PeakColourFn colourScheme, Rng &rng);

}  // namespace visclassic

#endif
