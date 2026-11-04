#ifndef VIS_CLASSIC_EFFECTS_H
#define VIS_CLASSIC_EFFECTS_H

// Drawing passes ported from the original plugin's Vis_Satan.cpp: the backgrounds, the bars for
// each Effect, and the Effects' ghost state. Drawing is pure — it reads the core's state through a
// DrawContext and writes pixels — so one processed frame draws identically into several boxes
// (`.wal` skins). Ghost state advances only in `advanceGhosts`, once per plugin frame.

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

#include "VisClassicPeaks.h"

namespace visclassic {

struct RGB {
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
};

using Palette = std::array<RGB, 256>;
using BarColourFn = unsigned char (*)(int level, int y);

enum Background { kBackgroundBlack = 0, kBackgroundFlash, kBackgroundSolid, kBackgroundGrid, kBackgroundFlashGrid };

enum Effect {
    kEffectNone = 0,
    kEffectMirror,
    kEffectReflection,
    kEffectShadow,
    kEffectDoubleShadow,
    kEffectSmoke,
    kEffectReflectionWaves,
    kEffectFadeShadow,
};

// One frame's target and inputs. Rows are counted bottom-up (row 0 is the bottom line), as the
// plugin's DIB is; the buffer itself is top-down BGRA.
struct DrawContext {
    uint8_t *dst = nullptr;
    int w = 0;
    int h = 0;
    size_t stride = 0;
    int ySpacing = 1;
    int barWidth = 1;   // the profile's Bar Width: Smoke keeps that many columns per bar
    int xSpacing = 0;

    std::vector<int> barStart;  // per bar, drawn columns [barStart, barEnd)
    std::vector<int> barEnd;
    const int *level = nullptr;      // per bar, 0..255
    const int *peak = nullptr;       // per bar, 0..255; 0 = not drawn
    std::vector<uint8_t> peakColour; // per bar, index into `peaks`

    BarColourFn barScheme = nullptr;
    const Palette *bars = nullptr;
    const Palette *peaks = nullptr;
    const Palette *volumes = nullptr;

    void fillRow(int row, int x0, int x1, const RGB &c) const;
    int rows(int level) const;          // rows a bar of this level fills
    int peakRow(int peak) const;        // row a peak of this level sits on, before Y-Spacing
    uint8_t colourIndex(int level, int row) const;
};

// The plugin's `levelbuffer`s and Reflection Waves' statics.
struct GhostState {
    std::vector<int> ghost;   // Shadow, Fade Shadow; Double Shadow's outer ghost
    std::vector<int> ghost2;  // Double Shadow's inner ghost; Fade Shadow's countdown
    std::vector<int> smoke;   // Smoke: bands × Bar Width columns, each a level
    int smokeMove = 1;
    int waveStart = 2;
    int waveDivisor = 3;
    int waveOldVolume = 0;

    void reset(int bands, int barWidth);
};

// One plugin frame of the Effect's ghosts, after this frame's bar levels are set.
void advanceGhosts(GhostState &g, int effect, const std::vector<int> &level, int barWidth, int xSpacing, Rng &rng);

// BackgroundDraw. `volume` is the frame's average of VolumeFunction over the bars (0..255). Grid
// and Flash Grid follow the Mirror and Reflection layouts, as the plugin pairs them.
void drawBackground(const DrawContext &ctx, int mode, int effect, int volume);

// The bars, ghosts and peaks for `effect`.
void drawBars(const DrawContext &ctx, int effect, const GhostState &g);

}  // namespace visclassic

#endif
