#include "VisClassicPeaks.h"

#include <algorithm>
#include <cmath>

namespace visclassic {

namespace {

constexpr int kFallSpeed = 5;  // levels per frame once a peak moves

// The plugin's loops, kept as written (including their uneven hold lengths) so a profile moves as
// it did there. `lookup[level][length - i]` is the peak `i` frames after it was set.

void normal(PeakTables &t, int rate) {
    for (int level = 1; level < 256; ++level) {
        t.length[level] = static_cast<int16_t>(rate);
        for (int i = 0; i <= rate; ++i) t.level[level][i] = static_cast<int16_t>(level);
    }
}

void fallOne(PeakTables &t, int rate, int level, int holdIfLong, bool logFalloff) {
    const int dur = rate < 256 - 255 / kFallSpeed ? rate : holdIfLong;
    const int length = dur + level / kFallSpeed;
    t.length[level] = static_cast<int16_t>(length);
    for (int i = 0; i <= dur; ++i) t.level[level][length - i] = static_cast<int16_t>(level);
    for (int i = dur + 1, y = level - kFallSpeed; i <= length; ++i, y -= kFallSpeed) {
        int16_t v = static_cast<int16_t>(y);
        if (logFalloff) {  // normalised log change: slow, then fast
            v = y > 0 ? static_cast<int16_t>(std::floor(std::log10(y) / std::log10(level) * level)) : 0;
        }
        t.level[level][length - i] = v;
    }
}

void riseOne(PeakTables &t, int rate, int level) {
    const int dur = rate < 256 - 255 / kFallSpeed ? rate : 255 - (255 - level) / kFallSpeed;
    const int length = dur + (255 - level) / kFallSpeed;
    t.length[level] = static_cast<int16_t>(length);
    for (int i = 0; i <= dur; ++i) t.level[level][length - i] = static_cast<int16_t>(level);
    for (int i = dur + 1, y = level + kFallSpeed; i <= length; ++i, y += kFallSpeed) {
        t.level[level][length - i] = static_cast<int16_t>(y);
    }
}

void riseFall(PeakTables &t, int rate) {
    for (int level = 1; level < 256; ++level) {
        const int dur = rate < 256 - 255 / kFallSpeed ? rate : 255 - level / kFallSpeed;
        const int length = dur + level / kFallSpeed;
        t.length[level] = static_cast<int16_t>(length);
        const float riseAmount = 25.0f / static_cast<float>(dur + 1);
        float rise = 0.0f;
        for (int i = 0; i <= dur; ++i, rise += riseAmount) {
            t.level[level][length - i] = static_cast<int16_t>(std::min(255, static_cast<int>(level + rise)));
        }
        // The plugin starts the fall from `lookup[level][dur]`, as written.
        for (int i = dur + 1, y = t.level[level][dur] - kFallSpeed; i <= length; ++i, y -= kFallSpeed) {
            t.level[level][length - i] = static_cast<int16_t>(std::max(0, y));
        }
    }
}

void sparks(PeakTables &t, int rate, Rng &rng) {
    for (int level = 1; level < 256; ++level) {
        const int length = rate < 200 ? rate + static_cast<int>(rng.next() % 56) : rate;
        t.length[level] = static_cast<int16_t>(length);
        const int dur = length / 2 + static_cast<int>(rng.next() % static_cast<uint32_t>(length)) / 3;
        for (int i = length; i > dur; --i) t.level[level][i] = static_cast<int16_t>(level);
        const int riseValue = static_cast<int>(rng.next() % 5) + 3;
        for (int i = dur, rise = riseValue; i >= 0; --i, rise += riseValue) {
            t.level[level][i] = static_cast<int16_t>(level + rise > 255 ? 0 : level + rise);
        }
    }
}

}  // namespace

void buildPeakTables(PeakTables &t, int effect, int rate, bool logFalloff, PeakColourFn colourScheme, Rng &rng) {
    if (rate <= 0) return;

    switch (effect) {
    case kPeakFall:
        for (int level = 1; level < 256; ++level) fallOne(t, rate, level, (255 - level) / kFallSpeed, logFalloff);
        break;
    case kPeakRise:
        for (int level = 1; level < 256; ++level) riseOne(t, rate, level);
        break;
    case kPeakFallAndRise:  // odd levels fall, even levels rise
        for (int level = 1; level < 256; ++level) {
            if (level % 2) {
                fallOne(t, rate, level, 255 - level / kFallSpeed, false);
            } else {
                riseOne(t, rate, level);
            }
        }
        break;
    case kPeakRiseFall:
        riseFall(t, rate);
        break;
    case kPeakSparks:
        sparks(t, rate, rng);
        break;
    case kPeakNormal:
    default:
        normal(t, rate);
        break;
    }

    // The peak colour fades over its life: index by the peak's height and how far along it is.
    for (int level = 1; level < 256; ++level) {
        const int length = std::max(1, static_cast<int>(t.length[level]));
        for (int y = 0; y <= t.length[level]; ++y) {
            t.colour[level][y] = colourScheme(t.level[level][y], static_cast<int>(y * 255.0 / length));
        }
    }
}

}  // namespace visclassic
